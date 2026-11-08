"""Non-régression sécurité (issues #14, #17, #18), en une commande.

Lance un serveur temporaire en mode local (sans PAPAI_PUBLIC), avec un Holo
simulé, puis vérifie :
  #14  sans clé, /ws/bridge, /sessions et /lessons ne répondent qu'à une app
       de la machine même du serveur ; un seul pont à la fois, et l'ancien ne
       débranche pas le nouveau en partant ;
  #18  hors session, le gardien n'envoie aucune capture à Holo et l'alerte
       arrive une seule fois sur le pont ; même en session, alerte immédiate
       et arrêt sans capture ni avis Holo ; demandes et listes bornées ;
  #17  ni clé, ni jeton de session, ni demande, ni prénom dans le journal.

    python tests/test_securite.py
"""

from __future__ import annotations

import asyncio
import json
import os
import secrets
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
CLE = secrets.token_urlsafe(16)
TACHE = "Retrouver le dossier comptabilité de Paulette " + secrets.token_hex(4)
PRENOM = "Claire" + secrets.token_hex(3)
DESCRIPTION = "Une page de carte prepayee est ouverte."
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


def ip_reseau() -> str | None:
    """Une adresse de cette machine qui n'est pas 127.0.0.1 : un « autre appareil »."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        return None if ip.startswith("127.") else ip
    except OSError:
        return None
    finally:
        s.close()


def avec_image(req: dict) -> bool:
    return any(isinstance(m.get("content"), list)
               and any(p.get("type") == "image_url" for p in m["content"])
               for m in req.get("messages", []))


class FauxHolo(BaseHTTPRequestHandler):
    """Un plan, ou la description de l'écran quand on lui parle d'arnaque."""

    def log_message(self, *_):
        pass

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        holo_vu.append(req)
        systeme = str(req["messages"][0].get("content", ""))
        if "arnaque" in systeme:
            contenu = json.dumps({"confirme": True, "description": DESCRIPTION})
        else:
            contenu = json.dumps({"steps": ["Ouvrir le Finder", "Aller dans Images"]})
        corps = json.dumps({
            "id": "x", "object": "chat.completion", "created": int(time.time()), "model": "faux",
            "choices": [{"index": 0, "message": {"role": "assistant", "content": contenu},
                         "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)


# ------------------------------------------------------------------ outils

NOUVEAU_CLIENT = int(websockets.__version__.split(".")[0]) >= 14


def connecter(uri: str, entetes: dict | None = None, origin: str | None = None):
    kw: dict = {"max_size": 2**24, "open_timeout": 5}
    if entetes:
        kw["additional_headers" if NOUVEAU_CLIENT else "extra_headers"] = entetes
    if origin:
        kw["origin"] = origin
    return websockets.connect(uri, **kw)


async def refuse(uri: str, **kw) -> bool:
    """Vrai si le serveur refuse la poignée de main ou ferme aussitôt en 4403."""
    try:
        async with connecter(uri, **kw) as ws:
            await ws.send(json.dumps({"type": "hello", "os": "macos"}))
            await asyncio.wait_for(ws.recv(), 3)
            return False
    except websockets.exceptions.InvalidHandshake:
        return True
    except websockets.exceptions.ConnectionClosed as e:
        return getattr(e, "code", None) == 4403 or getattr(getattr(e, "rcvd", None), "code", None) == 4403
    except (OSError, asyncio.TimeoutError):
        return False


class Pont:
    """Un faux Mac : répond seul aux captures, garde le reste dans une file."""

    def __init__(self, ws) -> None:
        self.ws = ws
        self.recus: asyncio.Queue = asyncio.Queue()
        self.tous: list[dict] = []
        self.ferme_code: int | None = None
        self.tache = asyncio.create_task(self._lire())

    async def _lire(self) -> None:
        n = 0
        try:
            async for brut in self.ws:
                m = json.loads(brut)
                if m.get("type") == "capture":
                    n += 1
                    await self.envoyer({"type": "frame", "req": m["req"], "frame_id": f"f{n}",
                                        "png_b64": FRAME, "width": 1280, "height": 800})
                    continue
                self.tous.append(m)
                await self.recus.put(m)
        except websockets.ConnectionClosed as e:
            self.ferme_code = getattr(e, "code", None) or getattr(getattr(e, "rcvd", None), "code", None)
        self.ferme_code = self.ferme_code or self.ws.close_code

    async def envoyer(self, m: dict) -> None:
        await self.ws.send(json.dumps(m, ensure_ascii=False))

    async def attendre(self, type_: str, delai: float = 15, **champs) -> dict | None:
        fin = time.monotonic() + delai
        while (reste := fin - time.monotonic()) > 0:
            try:
                m = await asyncio.wait_for(self.recus.get(), reste)
            except asyncio.TimeoutError:
                return None
            if m.get("type") == type_ and all(m.get(k) == v for k, v in champs.items()):
                return m
        return None


def http(url: str, entetes: dict | None = None, corps: dict | None = None) -> tuple[int, object]:
    data = json.dumps(corps).encode() if corps is not None else None
    req = urllib.request.Request(url, data, {"Content-Type": "application/json", **(entetes or {})})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")


# ------------------------------------------------------------------ contrôles


async def controles(port: int) -> dict:
    loc = f"127.0.0.1:{port}"
    ip = ip_reseau()
    lan = f"{ip}:{port}" if ip else None
    vus: dict = {}

    print("\n#14 Accès sans clé")
    if lan:
        check("pont sans clé depuis un autre appareil : refusé",
              await refuse(f"ws://{lan}/ws/bridge"))
    else:
        print("  (pas d'adresse réseau : contrôle « autre appareil » sauté)")
    check("pont sans clé derrière un tunnel (X-Forwarded-For) : refusé",
          await refuse(f"ws://{loc}/ws/bridge", entetes={"X-Forwarded-For": "203.0.113.7"}))
    check("pont sans clé ouvert par une page web (Origin) : refusé",
          await refuse(f"ws://{loc}/ws/bridge", origin="http://site-piege.example"))
    check("pont avec une mauvaise clé : refusé",
          await refuse(f"ws://{lan or loc}/k/pas-la-cle/ws/bridge"))
    for route in ("/sessions", "/lessons"):
        if lan:
            st, _ = http(f"http://{lan}{route}")
            check(f"{route} sans clé depuis un autre appareil : 404", st == 404, st)
        st, _ = http(f"http://{loc}{route}", {"Host": "site-piege.example"})
        check(f"{route} sans clé avec un Host étranger (rebinding DNS) : 404", st == 404, st)
        st, _ = http(f"http://{loc}{route}")
        check(f"{route} sans clé sur la machine du serveur : 200 (app Mac locale)", st == 200, st)
        st, _ = http(f"http://{lan or loc}/k/{CLE}{route}")
        check(f"/k/<clé>{route} : 200", st == 200, st)

    print("\n#14 Un seul pont")
    async with connecter(f"ws://{loc}/ws/bridge") as w1, \
            connecter(f"ws://{loc}/ws/aidant/{CLE}") as w_aid:
        mac1, aid = Pont(w1), Pont(w_aid)
        await mac1.envoyer({"type": "hello", "os": "macos"})
        check("app de la machine du serveur, sans clé : connectée (compatibilité)",
              await mac1.attendre("helpers") is not None)

        # Appairage : le vrai pont obtient un code, le proche reçoit la clé.
        await mac1.envoyer({"type": "pair_start"})
        code = await mac1.attendre("pair_code")
        st, r = http(f"http://{loc}/p/{code['code'] if code else '000000'}",
                     corps={"name": PRENOM, "relation": "sa fille"})
        check("appairage par le vrai pont : le proche reçoit la clé", st == 200 and r.get("key") == CLE)

        async with connecter(f"ws://{lan or loc}/k/{CLE}/ws/bridge") as w2:
            mac2 = Pont(w2)
            await mac2.envoyer({"type": "hello", "os": "macos"})
            check("pont avec la clé : connecté", await mac2.attendre("helpers") is not None)
            await asyncio.wait_for(mac1.tache, 5)
            check("l'ancien pont est fermé (4409)", mac1.ferme_code == 4409, mac1.ferme_code)
            await asyncio.sleep(0.5)
            st, r = http(f"http://{loc}/")
            check("le départ de l'ancien pont ne débranche pas le nouveau", r.get("bridge") is True, r)
            await aid.envoyer({"type": "remote_request", "text": "test", "from": PRENOM})
            check("le proche joint bien le nouveau pont", await mac2.attendre("remote_request") is not None)

            print("\n#18 Gardien")
            avant = len(holo_vu)
            await mac2.envoyer({"type": "guard", "processes": ["Safari"],
                                "window": "Votre ordinateur est infecté", "url": ""})
            alerte = await mac2.attendre("alert", 8)
            check("hors session, fausse alerte virus : l'utilisateur est prévenu sans écran bloqué",
                  alerte is not None and alerte.get("blocked") is False and not alerte.get("alert_id"), alerte)
            check("hors session : aucun appel à Holo, aucune capture", len(holo_vu) == avant,
                  len(holo_vu) - avant)
            proche_alerte = await aid.attendre("guard_advice", 5)
            check("le support reçoit l'avertissement", proche_alerte is not None
                  and proche_alerte.get("source") == "environment")
            await asyncio.sleep(1.5)
            n = sum(1 for m in mac2.tous if m.get("type") == "alert")
            check("l'alerte arrive une seule fois sur le pont", n == 1, n)

            await mac2.envoyer({"type": "guard", "processes": "AnyDesk", "window": 42})
            await mac2.envoyer({"type": "guard",
                                "processes": ["x" * 2_000] * 3_000 + ["AnyDesk"], "url": ""})
            await asyncio.sleep(1.5)
            await mac2.envoyer({"type": "guard", "processes": ["AnyDesk"] + ["x"] * 20_000})
            alerte = await mac2.attendre("alert", 8)
            proche_alerte = await aid.attendre("alert", 5)
            check("liste de processus énorme ou mal formée : bornée, le pont répond encore",
                  alerte is not None and proche_alerte is not None
                  and "anydesk" in proche_alerte.get("detail", "").lower(), proche_alerte)
            await aid.envoyer({"type": "dismiss_alert", "alert_id": alerte["alert_id"]})
            await mac2.attendre("alert_cleared")
            await aid.attendre("alert_cleared")

            await mac2.envoyer({"type": "help_request", "task": TACHE + " " + "a" * 10_000})
            session = await mac2.attendre("session")
            vus["jeton"] = (session or {}).get("helper_url", "").rsplit("/", 1)[-1]
            st = await aid.attendre("status", 15, state="awaiting_approval")
            check("demande bornée à 500 caractères", st is not None and len(st.get("task", "")) <= 500,
                  len((st or {}).get("task", "")))
            avant = len(holo_vu)
            await mac2.envoyer({"type": "guard", "processes": [], "window": "",
                                "url": "https://microsoft-login-secure.com"})
            alerte = await mac2.attendre("alert", 15)
            check("en session : l'alerte est immédiatement bloquante",
                  alerte is not None and alerte.get("blocked") is True, alerte)
            check("en session : aucun appel Holo ni capture avant l'alerte", len(holo_vu) == avant)
            check("en session : arrêt terminal", await aid.attendre("status", 5, state="stopped") is not None)
            async with connecter(f"ws://{loc}/ws/aidant/{CLE}") as wr:
                reconnecte = Pont(wr)
                rep = await reconnecte.attendre("alert", 5)
                check("reconnexion aidant : alerte en attente renvoyée",
                      rep is not None and rep.get("alert_id") == alerte["alert_id"])
                await reconnecte.envoyer({"type": "dismiss_alert", "alert_id": "faux"})
                check("rejet d'un identifiant périmé : refus", await reconnecte.attendre("refused", 5) is not None)
                reconnecte.tache.cancel()
            await aid.envoyer({"type": "dismiss_alert", "alert_id": alerte["alert_id"]})
            check("rejet par le proche : fermeture explicite sur le Mac", await mac2.attendre("alert_cleared", 5) is not None)
        aid.tache.cancel()
    return vus


def main() -> None:
    holo = ThreadingHTTPServer(("127.0.0.1", port_libre()), FauxHolo)
    threading.Thread(target=holo.serve_forever, daemon=True).start()
    tmp = Path(tempfile.mkdtemp(prefix="papai-securite-"))
    shutil.copytree(RACINE / "backend", tmp / "backend", ignore=shutil.ignore_patterns("__pycache__"))
    for module in RACINE.glob("*.py"):
        shutil.copy(module, tmp)
    port = port_libre()
    env = {**os.environ, "HAI_API_KEY": "faux", "HOLO_BASE_URL": f"http://127.0.0.1:{holo.server_port}/v1/",
           "PAPAI_AIDANT_KEY": CLE, "PORT": str(port), "PAPAI_PUBLIC_URL": f"http://127.0.0.1:{port}",
           "PYTHONUNBUFFERED": "1"}
    for var in ("PAPAI_PUBLIC", "GLADIA_API_KEY", "PAPAI_SHOW_KEY"):
        env.pop(var, None)
    journal = tmp / "serveur.log"
    log = open(journal, "w")
    serveur = subprocess.Popen([sys.executable, "-m", "backend.app"], cwd=tmp, env=env,
                               stdout=log, stderr=subprocess.STDOUT)
    vus: dict = {}
    try:
        for _ in range(60):
            try:
                http(f"http://127.0.0.1:{port}/")
                break
            except OSError:
                if serveur.poll() is not None:
                    break
                time.sleep(0.5)
        if serveur.poll() is not None:
            print("Le serveur n'a pas démarré :\n" + journal.read_text())
            sys.exit(1)
        print(f"Serveur de test : http://127.0.0.1:{port}  (Holo simulé, dossier {tmp})")
        vus = asyncio.run(asyncio.wait_for(controles(port), 120))
    except asyncio.TimeoutError:
        check("les contrôles se terminent en moins de 2 minutes", False)
    finally:
        serveur.terminate()
        serveur.wait(10)
        holo.shutdown()

    print("\n#17 Journal du serveur")
    texte = journal.read_text()
    check("le journal n'est pas vide", "[pont] connecté" in texte)
    check("pas de clé famille", CLE not in texte)
    check("pas de jeton de session", bool(vus.get("jeton")) and vus["jeton"] not in texte)
    check("pas de demande en clair", "Paulette" not in texte)
    check("pas de prénom de proche", PRENOM not in texte)
    if fails:
        print(f"\nJournal du serveur : {journal}")
    else:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{ok} contrôles passés, {fails} échec(s)")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
