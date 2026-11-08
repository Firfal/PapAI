"""Un jeton par support de l'organisation, révocable (sécurité C1, issue #51).

Serveur temporaire en mode en ligne (PAPAI_PUBLIC=1) et Holo simulé. L'IT crée
deux supports avec le jeton de l'organisation ; chacun voit les postes par des
clés dérivées (jamais la vraie clé) ; Alice valide un plan ; l'IT la révoque
pendant l'assistance : sa socket est fermée, l'assistance qu'elle a validée
s'arrête, son jeton et ses clés sont refusés. Bob et l'ancien jeton continuent.

    python tests/test_supports_revocables.py
"""
from __future__ import annotations

import asyncio
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import websockets

RACINE = Path(__file__).resolve().parent.parent
CLE = "cle-de-test-supports"
PLAN = ["Ouvrir les Réglages Wi-Fi", "Choisir le réseau du bureau"]
FRAME = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
fails = 0


def check(label: str, cond: object, detail: object = "") -> None:
    global fails
    print(("ok   " if cond else "FAIL ") + label + ("" if cond or detail == "" else f"  → {detail}"))
    fails += 0 if cond else 1


def port_libre() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class FauxHolo(BaseHTTPRequestHandler):
    """Un plan, puis une question au support : l'assistance reste ouverte."""

    def log_message(self, *_):
        pass

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        msg: dict = {"role": "assistant", "content": ""}
        if not req.get("tools"):
            msg["content"] = json.dumps({"steps": PLAN}, ensure_ascii=False)
        else:
            msg["tool_calls"] = [{"id": "c0", "type": "function", "function": {
                "name": "ask_helper", "arguments": json.dumps({"question": "Quel réseau ?"})}}]
        corps = json.dumps({"id": "x", "object": "chat.completion", "created": int(time.time()), "model": "faux",
                            "choices": [{"index": 0, "message": msg, "finish_reason": "stop"}],
                            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)


def http(url: str, body: dict | None = None, method: str | None = None) -> tuple[int, dict | str]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method or ("POST" if data is not None else "GET"),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            raw, st = r.read().decode(), r.status
    except urllib.error.HTTPError as e:
        raw, st = e.read().decode(), e.code
    try:
        return st, json.loads(raw)
    except ValueError:
        return st, raw


async def ahttp(url: str, body: dict | None = None, method: str | None = None):
    return await asyncio.to_thread(http, url, body, method)


class Canal:
    """Une WebSocket lue en continu ; côté poste, répond seul aux captures et actions."""

    def __init__(self, ws, poste: bool = False) -> None:
        self.ws, self.poste = ws, poste
        self.recus: asyncio.Queue = asyncio.Queue()
        self.ferme: int | None = None
        self.tache = asyncio.create_task(self._lire())

    async def _lire(self) -> None:
        n = 0
        try:
            async for brut in self.ws:
                m = json.loads(brut)
                if self.poste and m.get("type") == "capture":
                    n += 1
                    await self.envoyer({"type": "frame", "req": m["req"], "frame_id": f"f{n}",
                                        "png_b64": FRAME, "width": 1280, "height": 800})
                    continue
                if self.poste and m.get("type") == "execute":
                    await self.envoyer({"type": "result", "req": m["req"], "result": "simulé", "refused": False})
                    continue
                if m.get("type") != "frame":
                    await self.recus.put(m)
        except websockets.ConnectionClosed:
            pass
        self.ferme = self.ws.close_code if self.ws.close_code is not None else -1

    async def envoyer(self, m: dict) -> None:
        await self.ws.send(json.dumps(m, ensure_ascii=False))

    async def attendre(self, type_: str, delai: float = 20, **champs) -> dict | None:
        fin = time.monotonic() + delai
        while (reste := fin - time.monotonic()) > 0:
            try:
                m = await asyncio.wait_for(self.recus.get(), reste)
            except asyncio.TimeoutError:
                return None
            if m.get("type") == type_ and all(m.get(k) == v for k, v in champs.items()):
                return m
        return None


async def refuse_ws(url: str) -> bool:
    """Vrai si la WebSocket est refusée (fermée sans message ou réponse `refused`)."""
    try:
        async with websockets.connect(url) as ws:
            m = json.loads(await asyncio.wait_for(ws.recv(), 5))
            return m.get("type") == "refused"
    except (websockets.ConnectionClosed, websockets.InvalidStatus, websockets.InvalidHandshake):
        return True


async def parcours(base: str, data: Path, log: Path) -> None:
    wsb = base.replace("http://", "ws://")
    st, o = await ahttp(f"{base}/orgs", {"name": "Acme"})
    org = o["support_token"]
    _, o2 = await ahttp(f"{base}/orgs", {"name": "Autre"})

    print("\n1. L'IT crée un jeton par support")
    st, alice = await ahttp(f"{base}/o/{org}/supports", {"name": "Alice"})
    check("le jeton de l'organisation crée un support", st == 200 and alice["token"].startswith("sup-")
          and alice["token"] != org and alice["support_url"].endswith(alice["token"]), alice)
    _, bob = await ahttp(f"{base}/o/{org}/supports", {"name": "Bob"})
    check("chaque support a son jeton", bob["token"] not in (alice["token"], org))
    st, _ = await ahttp(f"{base}/o/{org}/supports", {})
    check("un support sans nom est refusé", st == 400)
    st, lst = await ahttp(f"{base}/o/{org}/supports")
    check("la console liste les supports, sans jeton", st == 200
          and [d["name"] for d in lst["supports"]] == ["Alice", "Bob"]
          and not any("token" in d or "hash" in d for d in lst["supports"]), lst)
    for label, url, body in (("lister", f"{base}/o/{alice['token']}/supports", None),
                             ("créer", f"{base}/o/{alice['token']}/supports", {"name": "Intrus"}),
                             ("révoquer", f"{base}/o/{alice['token']}/supports/{bob['id']}/revoke", {}),
                             ("renouveler", f"{base}/o/{alice['token']}/rotate", {})):
        st, _ = await ahttp(url, body)
        check(f"un jeton de support ne peut pas {label} les supports", st == 403, st)
    st, _ = await ahttp(f"{base}/o/{o2['support_token']}/supports/{alice['id']}/revoke", {})
    check("une autre organisation ne révoque pas Alice", st == 404, st)
    org_json = "".join(p.read_text("utf-8") for p in (data / "orgs").glob("*/org.json"))
    check("le serveur ne garde que l'empreinte des jetons de support",
          alice["token"] not in org_json and bob["token"] not in org_json)

    print("\n2. Postes et clés dérivées")
    _, poste = await ahttp(f"{base}/spaces", {"org": o["enroll_token"], "name": "Poste compta"})
    _, autre = await ahttp(f"{base}/spaces", {"org": o2["enroll_token"], "name": "Poste ailleurs"})
    st, sa = await ahttp(f"{base}/o/{alice['token']}/spaces")
    dk_a = sa["spaces"][0]["key"] if st == 200 and sa["spaces"] else ""
    check("le jeton d'Alice liste les postes de l'organisation", st == 200 and len(sa["spaces"]) == 1, sa)
    check("…avec une clé dérivée, jamais la vraie clé du poste",
          dk_a.startswith("sk") and len(dk_a) == 54 and poste["key"] not in json.dumps(sa), dk_a)
    _, sb = await ahttp(f"{base}/o/{bob['token']}/spaces")
    dk_b = sb["spaces"][0]["key"]
    check("la clé dérivée est propre à chaque support", dk_b != dk_a)
    st, lo = await ahttp(f"{base}/o/{org}/spaces")
    check("l'ancien jeton de l'organisation donne toujours la clé du poste (PR #72)",
          st == 200 and lo["spaces"][0]["key"] == poste["key"])
    st, les = await ahttp(f"{base}/k/{dk_a}/lessons")
    check("la clé dérivée ouvre les routes du support", st == 200 and isinstance(les, list), st)
    st, _ = await ahttp(f"{base}/a/{dk_a}")
    check("…et la page du support", st == 200)
    pack = {"papai": 1, "title": "Vider la corbeille", "publisher": "IT",
            "actions": [{"do": "antivirus_scan"}], "platforms": ["windows"]}
    st, imp = await ahttp(f"{base}/k/{dk_a}/automations?by=IT%20de%20confiance", pack)
    check("un automate importé par Alice porte son nom, pas celui envoyé",
          st == 200 and imp.get("approved_by") == "Alice", (st, imp))
    sid_autre = next(p.parent.name for p in (data / "spaces").glob("*/space.json")
                     if json.loads(p.read_text())["key"] == autre["key"])
    forge = "sk" + sid_autre + dk_a[14:]
    st, _ = await ahttp(f"{base}/k/{forge}/lessons")
    check("autre organisation : clé d'Alice refusée sur un poste d'ailleurs", st == 404, st)
    st, _ = await ahttp(f"{base}/o/{alice['token']}/tickets/{autre['key']}/T-1", {"action": "note", "text": "x"})
    check("autre organisation : action sur un ticket d'ailleurs refusée", st == 404, st)
    st, _ = await ahttp(f"{base}/o/{bob['token']}/tickets/{dk_a}/T-1", {"action": "note", "text": "x"})
    check("la clé d'Alice ne sert pas avec le jeton de Bob", st == 404, st)
    check("la clé dérivée n'ouvre pas le pont du poste", await refuse_ws(f"{wsb}/k/{dk_a}/ws/bridge"))
    st, lo2 = await ahttp(f"{base}/o/{org}/spaces")
    check("…et ne crée pas d'espace à son nom", len(lo2["spaces"]) == 1)
    st, _ = await ahttp(f"{base}/k/{dk_a}/p")
    st2, _ = await ahttp(f"{base}/k/{dk_a}/org", {"org": o["enroll_token"]})
    check("la clé dérivée n'ouvre ni la liaison ni l'inscription", st == 404 and st2 == 404, (st, st2))

    print("\n3. Alice valide un plan, l'IT la révoque pendant l'assistance")
    async with websockets.connect(poste["bridge_url"], max_size=2**24) as w_mac, \
            websockets.connect(f"{wsb}/k/{dk_a}/ws/aidant/{dk_a}", max_size=2**24) as w_a, \
            websockets.connect(f"{wsb}/k/{dk_b}/ws/aidant/{dk_b}", max_size=2**24) as w_b:
        mac, a, b = Canal(w_mac, poste=True), Canal(w_a), Canal(w_b)
        await mac.envoyer({"type": "hello", "os": "macos"})
        check("Alice est connectée au poste", await a.attendre("hello", 10))
        await a.envoyer({"type": "helper_hello", "id": "x", "name": "Directeur", "relation": "?"})
        await b.envoyer({"type": "helper_hello", "id": "y", "name": "Bob", "relation": "IT"})
        await a.attendre("helper_id", 5)
        await b.attendre("helper_id", 5)
        hp = None
        for _ in range(4):
            hp = await mac.attendre("helpers", 5)
            if hp and len(hp.get("helpers", [])) == 2:
                break
        noms = {h["name"] for h in (hp or {}).get("helpers", [])}
        check("le poste voit le nom donné par l'IT, pas celui annoncé par l'app", noms == {"Alice", "Bob"}, hp)
        st, lst = await ahttp(f"{base}/o/{org}/supports")
        check("la console voit Alice et Bob en ligne", all(d["online"] for d in lst["supports"]), lst)

        await mac.envoyer({"type": "help_request", "task": "Le Wi-Fi ne marche plus"})
        p = await a.attendre("status", 30, state="awaiting_approval")
        check("Alice reçoit le plan", p and p.get("plan") == PLAN, p)
        await a.envoyer({"type": "approve_plan"})
        act = await a.attendre("status", 10, state="active")
        check("Alice valide : l'assistance démarre à son nom", act and act.get("helper_name") == "Alice", act)
        q = await b.attendre("question", 30)
        check("Holo pose une question : l'assistance est ouverte", q is not None)
        st, journal = await ahttp(f"{base}/k/{poste['key']}/sessions")
        dec = [e for s in journal for e in s["journal"] if e["kind"] == "plan_decision"] if st == 200 else []
        check("le journal montre quel support a validé le plan",
              dec and dec[-1].get("by") == {"name": "Alice", "via": "jeton_support", "support": alice["id"]}, dec)

        st, rv = await ahttp(f"{base}/o/{org}/supports/{alice['id']}/revoke", {})
        check("l'IT révoque Alice", st == 200 and rv.get("revoked") and rv.get("closed") == 1
              and rv.get("stopped") == 1, rv)
        await asyncio.wait_for(a.tache, 5)
        check("la socket d'Alice est fermée tout de suite (4401)", a.ferme == 4401, a.ferme)
        stop = await b.attendre("status", 10, state="stopped")
        check("l'assistance validée par Alice s'arrête", stop and stop.get("stopped_by") == "support_revoque", stop)
        check("le poste reçoit l'arrêt", await mac.attendre("status", 10, state="stopped"))
        check("la socket de Bob reste ouverte", b.ferme is None and not b.tache.done())

        print("\n4. Après la révocation")
        st, _ = await ahttp(f"{base}/o/{alice['token']}/spaces")
        check("ancien jeton d'Alice refusé", st == 404, st)
        st, _ = await ahttp(f"{base}/o/{alice['token']}")
        check("…y compris la page de l'organisation", st == 404, st)
        st, _ = await ahttp(f"{base}/k/{dk_a}/lessons")
        check("clé dérivée d'Alice refusée", st == 404, st)
        check("Alice ne peut plus se reconnecter", await refuse_ws(f"{wsb}/k/{dk_a}/ws/aidant/{dk_a}"))
        st, lst = await ahttp(f"{base}/o/{org}/supports")
        etat = {d["name"]: d for d in lst["supports"]}
        check("la console montre Alice révoquée, Bob actif",
              etat["Alice"]["revoked"] and not etat["Alice"]["online"] and not etat["Bob"]["revoked"]
              and etat["Bob"]["online"], lst)
        st, tk = await ahttp(f"{base}/o/{bob['token']}/tickets")
        t = tk["tickets"][0] if st == 200 and tk["tickets"] else {}
        check("le ticket garde le nom du support qui a validé", t.get("helper") == "Alice", t)
        check("les tickets vus par Bob portent sa clé dérivée", t.get("space") == dk_b and poste["key"] not in json.dumps(tk))
        st, _ = await ahttp(f"{base}/o/{bob['token']}/tickets/{dk_b}/{t.get('id')}",
                            {"action": "note", "text": "Rappeler demain", "by": "Faux nom"})
        _, tk = await ahttp(f"{base}/o/{bob['token']}/tickets")
        notes = tk["tickets"][0].get("notes") or []
        check("une note de Bob est signée Bob, quel que soit le nom envoyé",
              st == 200 and notes and notes[-1].get("by") == "Bob", (st, notes))

    print("\n5. Fin de migration : nouveau jeton de l'organisation")
    st, rot = await ahttp(f"{base}/o/{org}/rotate", {})
    check("l'IT renouvelle le jeton de l'organisation", st == 200 and rot["support_token"] != org)
    st, _ = await ahttp(f"{base}/o/{org}/spaces")
    check("l'ancien jeton de l'organisation est refusé", st == 404, st)
    st, _ = await ahttp(f"{base}/o/{rot['support_token']}/supports")
    st2, _ = await ahttp(f"{base}/o/{bob['token']}/spaces")
    check("le nouveau jeton gère les supports, Bob continue", st == 200 and st2 == 200, (st, st2))

    journal = log.read_text("utf-8", "replace")
    check("ni jeton ni clé dérivée dans le journal du serveur",
          not any(x in journal for x in (alice["token"], bob["token"], dk_a, dk_b, org)))
    check("le journal du serveur nomme qui a validé", "validée par Alice (jeton_support" in journal)


def main() -> None:
    holo = ThreadingHTTPServer(("127.0.0.1", port_libre()), FauxHolo)
    threading.Thread(target=holo.serve_forever, daemon=True).start()
    tmp = Path(tempfile.mkdtemp(prefix="papai-supports-"))
    shutil.copytree(RACINE / "backend", tmp / "backend", ignore=shutil.ignore_patterns("__pycache__", "family.json"))
    for module in RACINE.glob("*.py"):
        shutil.copy(module, tmp)
    port = port_libre()
    base = f"http://127.0.0.1:{port}"
    env = {**os.environ, "HAI_API_KEY": "faux", "HOLO_BASE_URL": f"http://127.0.0.1:{holo.server_port}/v1/",
           "PAPAI_PUBLIC": "1", "PAPAI_AIDANT_KEY": CLE, "PAPAI_DATA_DIR": str(tmp / "data"),
           "PORT": str(port), "PAPAI_PUBLIC_URL": base}
    env.pop("GLADIA_API_KEY", None)
    log = tmp / "serveur.log"
    serveur = subprocess.Popen([sys.executable, "-u", "-m", "backend.app"], cwd=tmp, env=env,
                               stdout=open(log, "w"), stderr=subprocess.STDOUT)
    try:
        for _ in range(60):
            try:
                urllib.request.urlopen(base + "/", timeout=2)
                break
            except urllib.error.HTTPError:
                break
            except OSError:
                if serveur.poll() is not None:
                    break
                time.sleep(0.5)
        if serveur.poll() is not None:
            print("Le serveur n'a pas démarré :\n" + log.read_text())
            sys.exit(1)
        asyncio.run(asyncio.wait_for(parcours(base, tmp / "data", log), 120))
    except asyncio.TimeoutError:
        check("le parcours se termine en moins de 2 minutes", False)
    finally:
        serveur.terminate()
        serveur.wait(10)
        holo.shutdown()
        if fails:
            print(f"\nJournal du serveur : {log}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{'ÉCHEC' if fails else 'OK'} : {fails} échec(s)")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
