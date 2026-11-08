"""Liens terminés : cinq fins réelles, faux Mac et faux Holo, serveur isolé.

    .venv/bin/python tests/test_lien_session_termine.py
"""

import asyncio
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import websockets

from test_securite import CLE, Pont, connecter, http, port_libre

RACINE = Path(__file__).resolve().parent.parent
ok = fails = 0


def check(label, condition, detail=""):
    global ok, fails
    if condition:
        ok += 1
        print(f"  OK      {label}")
    else:
        fails += 1
        print(f"  ECHEC   {label}  {detail}")


class FauxHolo(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        message = {"role": "assistant", "content": json.dumps({"steps": ["Ouvrir Images"]})}
        if req.get("tools"):
            message = {"role": "assistant", "content": "", "tool_calls": [
                {"id": "fin", "type": "function", "function": {
                    "name": "answer", "arguments": json.dumps({"content": "Terminé."})}}]}
        data = json.dumps({"choices": [{"index": 0, "message": message,
                                         "finish_reason": "stop"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


async def scenario(base, fin):
    async with connecter(f"{base}/ws/bridge") as wm, connecter(f"{base}/ws/aidant/{CLE}") as wa:
        mac, support = Pont(wm), Pont(wa)
        await mac.envoyer({"type": "hello", "os": "macos"})
        await support.attendre("hello")
        await mac.envoyer({"type": "help_request", "task": "Ouvrir Images"})
        session = await mac.attendre("session")
        assert session, "assistance non créée"
        plan = await support.attendre("status", state="awaiting_approval")
        assert plan, "plan absent"
        token = session["helper_url"].rsplit("/", 1)[-1]
        async with connecter(f"{base}/ws/helper/{token}") as wh:
            lien = Pont(wh)
            assert await lien.attendre("status"), "lien non connecté"
            await lien.envoyer({"type": "refresh"})
            assert await lien.attendre("frame"), "capture initiale absente"
            if fin == "done":
                await support.envoyer({"type": "approve_plan"})
            elif fin == "refus":
                await support.envoyer({"type": "refuse_plan"})
            elif fin == "alerte":
                await mac.envoyer({"type": "guard", "processes": [], "window": "",
                                   "url": "https://microsoft-login-secure.com"})
                alerte = await support.attendre("alert")
                assert alerte, "alerte absente"
            elif fin == "déconnexion":
                await wm.close()
            else:
                await mac.envoyer({"type": "stop"})
            etat = "done" if fin == "done" else "stopped"
            assert await support.attendre("status", state=etat), "fin absente"
            check(f"{fin} : le lien reçoit sa propre fin", bool(await lien.attendre("status", state=etat)))
            if fin == "done":
                check("done : le lien reçoit la réponse finale de Holo",
                      any(m.get("type") == "answer" and m.get("content") == "Terminé." for m in lien.tous))
            if fin == "alerte":
                await support.envoyer({"type": "dismiss_alert", "alert_id": alerte["alert_id"]})
                assert await support.attendre("alert_cleared")
            if fin == "déconnexion":
                wm = await connecter(f"{base}/ws/bridge")
                mac = Pont(wm)
                await mac.envoyer({"type": "hello", "os": "macos"})
            try:
                async with connecter(f"{base}/ws/helper/{token}") as wr:
                    relie = Pont(wr)
                    assert await relie.attendre("status", state=etat)
                    await asyncio.sleep(0.15)
                    check(f"{fin} : reconnexion sans image", not any(m["type"] == "frame" for m in relie.tous))
                    debut = len(lien.tous)
                    await mac.envoyer({"type": "help_request", "task": "Ranger Images"})
                    suivante = await mac.attendre("session")
                    assert suivante and suivante["id"] != session["id"]
                    assert await support.attendre("status", state="awaiting_approval")
                    await support.envoyer({"type": "refresh"})
                    assert await support.attendre("frame"), "le support doit recevoir la nouvelle capture"
                    await support.envoyer({"type": "approve_plan"})
                    assert await support.attendre("status", state="done"), "nouvelle fin absente"
                    await asyncio.sleep(0.2)
                    for nom, messages in (("ancien lien", lien.tous[debut:]), ("reconnexion", relie.tous)):
                        fuites = [m["type"] for m in messages if m["type"] in ("frame", "answer") or
                                  (m["type"] == "status" and m.get("session") != session["id"])]
                        check(f"{fin} : {nom} isolé de la nouvelle assistance", not fuites, fuites)
            finally:
                if fin == "déconnexion":
                    await wm.close()


def main():
    holo = ThreadingHTTPServer(("127.0.0.1", 0), FauxHolo)
    threading.Thread(target=holo.serve_forever, daemon=True).start()
    tmp = Path(tempfile.mkdtemp(prefix="papai-liens-", dir=Path.home()))
    shutil.copytree(RACINE / "backend", tmp / "backend", ignore=shutil.ignore_patterns("__pycache__"))
    for module in RACINE.glob("*.py"):
        shutil.copy(module, tmp)
    port = port_libre()
    env = {**os.environ, "HAI_API_KEY": "stub-key", "HOLO_BASE_URL": f"http://127.0.0.1:{holo.server_port}/v1/",
           "PAPAI_AIDANT_KEY": CLE, "PORT": str(port), "PAPAI_PUBLIC_URL": f"http://127.0.0.1:{port}"}
    for var in ("PAPAI_PUBLIC", "GLADIA_API_KEY", "PAPAI_SHOW_KEY"):
        env.pop(var, None)
    with (tmp / "serveur.log").open("w") as log:
        serveur = subprocess.Popen([sys.executable, "-m", "backend.app"], cwd=tmp, env=env,
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            for _ in range(60):
                try:
                    http(f"http://127.0.0.1:{port}/")
                    break
                except OSError:
                    time.sleep(0.1)
            for fin in ("done", "stopped", "refus", "alerte", "déconnexion"):
                asyncio.run(asyncio.wait_for(scenario(f"ws://127.0.0.1:{port}", fin), 60))
        finally:
            serveur.terminate()
            serveur.wait(10)
            holo.shutdown()
    print(f"\n{ok} contrôles passés, {fails} échec(s)")
    print(f"Journal du serveur : {tmp / 'serveur.log'}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
