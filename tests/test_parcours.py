"""Test de bout en bout du parcours PapAI, en une commande, sans clé ni Mac.

Démarre le serveur dans un dossier temporaire avec un Holo simulé, puis joue
l'app Mac et le proche en WebSocket : ajout d'un proche par code, session
proposée (refusée puis acceptée), plan à préciser puis valider, action,
question au proche, fin de session, plan refusé, Arrêter.

    .venv/bin/python tests/test_parcours.py
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
CLE = "e2e"
PLAN = ["Ouvrir l'App Store", "Chercher WhatsApp", "Cliquer sur Obtenir"]
# PNG 1×1 : on n'envoie jamais l'écran réel d'un testeur.
FRAME = ("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")

ok = fails = 0
holo_vu: list[dict] = []


def check(label: str, cond: object, detail: object = "") -> None:
    global ok, fails
    if cond:
        ok += 1
        print(f"  OK      {label}")
    else:
        fails += 1
        print(f"  ECHEC   {label}  {detail}")


def port_libre() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


# ------------------------------------------------------------------ Holo simulé


class FauxHolo(BaseHTTPRequestHandler):
    """Répond comme l'API Holo : un plan, puis clic, question au proche, fin."""

    def log_message(self, *_):
        pass

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        holo_vu.append(req)
        msg: dict = {"role": "assistant", "content": ""}
        if not req.get("tools"):
            msg["content"] = json.dumps({"steps": PLAN}, ensure_ascii=False)
        else:
            faits = sum(1 for m in req["messages"] if m.get("role") == "tool")
            nom, args = [
                ("click", {"element": "App Store", "x": 500, "y": 500}),
                ("ask_helper", {"question": "Faut-il aussi installer WhatsApp sur l'iPhone ?",
                                "options": ["Oui", "Non"]}),
            ][faits] if faits < 2 else ("answer", {"content": "WhatsApp est installé."})
            msg["tool_calls"] = [{"id": f"c{faits}", "type": "function",
                                  "function": {"name": nom, "arguments": json.dumps(args)}}]
        corps = json.dumps({
            "id": "x", "object": "chat.completion", "created": int(time.time()), "model": "faux",
            "choices": [{"index": 0, "message": msg, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)


# ------------------------------------------------------------------ outils


class Canal:
    """Une WebSocket lue en continu ; le Mac répond seul aux captures et actions."""

    def __init__(self, ws, mac: bool = False) -> None:
        self.ws, self.mac = ws, mac
        self.recus: asyncio.Queue = asyncio.Queue()
        self.actions: list[str] = []
        self.tache = asyncio.create_task(self._lire())

    async def _lire(self) -> None:
        n = 0
        try:
            async for brut in self.ws:
                m = json.loads(brut)
                if self.mac and m.get("type") == "capture":
                    n += 1
                    await self.envoyer({"type": "frame", "req": m["req"], "frame_id": f"f{n}",
                                        "png_b64": FRAME, "width": 1280, "height": 800})
                    continue
                if self.mac and m.get("type") == "execute":
                    self.actions.append(m["action"]["name"])
                    await self.envoyer({"type": "result", "req": m["req"],
                                        "result": "simulé", "refused": False})
                    continue
                if m.get("type") != "frame":
                    await self.recus.put(m)
        except websockets.ConnectionClosed:
            pass

    async def envoyer(self, m: dict) -> None:
        await self.ws.send(json.dumps(m, ensure_ascii=False))

    async def attendre(self, type_: str, delai: float = 30, **champs) -> dict | None:
        fin = time.monotonic() + delai
        while (reste := fin - time.monotonic()) > 0:
            try:
                m = await asyncio.wait_for(self.recus.get(), reste)
            except asyncio.TimeoutError:
                return None
            if m.get("type") == type_ and all(m.get(k) == v for k, v in champs.items()):
                return m
        return None


def post(url: str, corps: dict) -> tuple[int, dict]:
    req = urllib.request.Request(url, json.dumps(corps).encode(), {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def get(url: str) -> str:
    with urllib.request.urlopen(url, timeout=10) as r:
        return r.read().decode()


# ------------------------------------------------------------------ parcours


async def parcours(base: str) -> None:
    ws = base.replace("http://", "ws://")

    print("\n1. Page de l'aidant")
    page = get(f"{base}/a/{CLE}")
    check("la page aidant affiche le plan avec Valider, Préciser, Refuser",
          all(x in page for x in ("planApprove", "planRefine", "planRefuse")))
    check("les états planning et awaiting_approval ont un libellé",
          "planning:" in page and "awaiting_approval:" in page)

    async with websockets.connect(f"{ws}/ws/bridge", max_size=2**24) as w_mac:
        mac = Canal(w_mac, mac=True)
        await mac.envoyer({"type": "hello", "os": "macos"})

        print("\n2. Ajout d'un proche")
        await mac.envoyer({"type": "pair_start"})
        pc = await mac.attendre("pair_code", 10)
        check("le Mac reçoit un code à 6 chiffres", pc and len(pc.get("code", "")) == 6, pc)
        code = pc["code"] if pc else "000000"
        faux = "111111" if code != "111111" else "222222"
        st, r = post(f"{base}/p/{faux}", {"name": "Claire", "relation": "sa fille"})
        check("un mauvais code est refusé", st == 400 and not r.get("ok"), r)
        st, r = post(f"{base}/p/{code}", {"name": "Claire", "relation": "sa fille"})
        check("le bon code ajoute Claire", st == 200 and r.get("ok"), r)
        hp = await mac.attendre("helpers", 10, added="Claire")
        check("le Mac voit Claire tout de suite", hp is not None)
        st, r = post(f"{base}/p/{code}", {"name": "Intrus", "relation": "?"})
        check("un code ne sert qu'une fois", st == 400, r)

        async with websockets.connect(f"{ws}/ws/aidant/{CLE}", max_size=2**24) as w_aid:
            aid = Canal(w_aid)
            h = await aid.attendre("hello", 10)
            check("l'aidant voit l'ordinateur connecté", h and h.get("bridge"), h)

            print("\n3. Session proposée par le proche")
            await aid.envoyer({"type": "remote_request", "from": "Claire", "text": "installer WhatsApp"})
            rr = await mac.attendre("remote_request", 10)
            check("la proposition arrive sur le Mac", rr and rr.get("from") == "Claire"
                  and rr.get("task") == "installer WhatsApp", rr)
            await mac.envoyer({"type": "remote_answer", "accepted": False})
            check("le refus revient à l'aidant", await aid.attendre("remote_refused", 10))

            await aid.envoyer({"type": "remote_request", "from": "Claire", "text": "installer WhatsApp"})
            rr = await mac.attendre("remote_request", 10)
            await mac.envoyer({"type": "help_request", "task": rr["task"] if rr else "installer WhatsApp",
                               "requested_by": "Claire"})
            check("l'accord revient à l'aidant", await aid.attendre("remote_accepted", 10))

            print("\n4. Plan de Holo")
            p = await aid.attendre("status", 40, state="awaiting_approval")
            check("l'aidant reçoit le plan à valider", p and p.get("plan") == PLAN, p)
            check("rien ne bouge avant l'accord", mac.actions == [], mac.actions)
            await aid.envoyer({"type": "remote_request", "from": "Claire", "text": "autre chose"})
            r = await aid.attendre("refused", 10)
            check("pas de 2e proposition pendant une session", r and "déjà" in r.get("reason", ""), r)

            await aid.envoyer({"type": "refine_plan", "text": "Passe par l'App Store"})
            check("Préciser relance la préparation", await aid.attendre("status", 10, state="planning"))
            p = await aid.attendre("status", 40, state="awaiting_approval")
            check("un nouveau plan revient", p is not None)
            check("la précision est transmise à Holo",
                  any("Passe par l'App Store" in json.dumps(r, ensure_ascii=False) for r in holo_vu))
            check("toujours rien ne bouge", mac.actions == [], mac.actions)

            await aid.envoyer({"type": "approve_plan"})
            check("Valider lance l'assistance", await aid.attendre("status", 10, state="active"))

            print("\n5. Exécution, question, fin")
            q = await aid.attendre("question", 40)
            check("Holo agit puis pose une question au proche", q and mac.actions == ["click"],
                  (q, mac.actions))
            await aid.envoyer({"type": "answer", "text": "Non"})
            fin = await aid.attendre("answer", 40)
            check("la session se termine avec un message", fin and "installé" in fin.get("content", ""), fin)
            check("état final : terminée", await aid.attendre("status", 10, state="done"))

            print("\n6. Plan refusé par le proche")
            await aid.envoyer({"type": "remote_request", "from": "Claire", "text": "vider la corbeille"})
            rr = await mac.attendre("remote_request", 10)
            await mac.envoyer({"type": "help_request", "task": "vider la corbeille", "requested_by": "Claire"})
            await aid.attendre("status", 40, state="awaiting_approval")
            avant = list(mac.actions)
            await aid.envoyer({"type": "refuse_plan"})
            check("Refuser arrête la session", await aid.attendre("status", 10, state="stopped"))
            check("aucune action après refus", mac.actions == avant, mac.actions)

            print("\n7. Arrêter depuis le Mac")
            await mac.envoyer({"type": "help_request", "task": "ranger le bureau"})
            await aid.attendre("status", 40, state="awaiting_approval")
            await mac.envoyer({"type": "stop"})
            check("Arrêter coupe la session", await aid.attendre("status", 10, state="stopped"))
            check("aucune action après Arrêter", mac.actions == avant, mac.actions)

            aid.tache.cancel()
        mac.tache.cancel()


def main() -> None:
    holo = ThreadingHTTPServer(("127.0.0.1", port_libre()), FauxHolo)
    threading.Thread(target=holo.serve_forever, daemon=True).start()

    # Copie temporaire : ni family.json ni les fiches du dépôt ne sont touchés.
    tmp = Path(tempfile.mkdtemp(prefix="papai-e2e-"))
    shutil.copytree(RACINE / "backend", tmp / "backend", ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copy(RACINE / "carepilot_tools.py", tmp)
    port = port_libre()
    env = {**os.environ, "HAI_API_KEY": "faux", "HOLO_BASE_URL": f"http://127.0.0.1:{holo.server_port}/v1/",
           "PAPAI_AIDANT_KEY": CLE, "PORT": str(port), "CAREPILOT_PUBLIC_URL": f"http://127.0.0.1:{port}"}
    env.pop("PAPAI_PUBLIC", None)
    log = open(tmp / "serveur.log", "w")
    serveur = subprocess.Popen([sys.executable, "-m", "backend.app"], cwd=tmp, env=env,
                               stdout=log, stderr=subprocess.STDOUT)
    base = f"http://127.0.0.1:{port}"
    try:
        for _ in range(60):
            try:
                get(base + "/")
                break
            except OSError:
                if serveur.poll() is not None:
                    break
                time.sleep(0.5)
        if serveur.poll() is not None:
            print("Le serveur n'a pas démarré :\n" + (tmp / "serveur.log").read_text())
            sys.exit(1)
        print(f"Serveur de test : {base}  (Holo simulé, dossier {tmp})")
        asyncio.run(asyncio.wait_for(parcours(base), 300))
    except asyncio.TimeoutError:
        check("le parcours se termine en moins de 5 minutes", False)
    finally:
        serveur.terminate()
        serveur.wait(10)
        holo.shutdown()
        if fails:
            print(f"\nJournal du serveur : {tmp / 'serveur.log'}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{ok} contrôles passés, {fails} échec(s)")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
