"""Rangement guidé de bout en bout : vrai serveur, Holo simulé, Mac et support en WebSocket.

Vérifie que seuls des noms de fichiers partent à Holo, que le plan liste chaque
déplacement, qu'un refus n'envoie aucun ordre et que l'ordre `tidy_execute`
n'arrive au Mac qu'après Valider.

    .venv/bin/python tests/test_rangement_parcours.py
"""

from __future__ import annotations

import asyncio
import json
import sys
import time
from http.server import BaseHTTPRequestHandler
from pathlib import Path

import websockets

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_parcours as tp  # noqa: E402

FILES = ["facture_edf.pdf", "Contrat bail.pdf", "IMG_2041.HEIC", "Chrome.dmg", "notes"]
TIDY = {"folder": "documents", "files": FILES, "folders": ["Factures"]}
holo_vu: list[dict] = []


class FauxHolo(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        holo_vu.append(req)
        moves = {"facture_edf.pdf": "Factures", "Contrat bail.pdf": "Contrats",
                 "IMG_2041.HEIC": "Images", "Chrome.dmg": "Installateurs",
                 "../../etc/passwd": "Factures", "notes": "../Ailleurs"}
        corps = json.dumps({
            "id": "x", "object": "chat.completion", "created": int(time.time()), "model": "faux",
            "choices": [{"index": 0, "finish_reason": "stop", "message": {
                "role": "assistant", "content": json.dumps({"moves": moves}, ensure_ascii=False)}}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)


class Mac(tp.Canal):
    """Le Mac répond aux ordres de rangement et les garde pour vérification."""

    def __init__(self, ws) -> None:
        self.ordres: list[dict] = []
        super().__init__(ws, mac=True)

    async def _lire(self) -> None:
        try:
            async for brut in self.ws:
                m = json.loads(brut)
                if m.get("type") == "tidy_execute":
                    self.ordres.append(m)
                    await self.envoyer({"type": "result", "req": m["req"], "refused": False,
                                        "result": "4 fichiers rangés", "moved": 4, "renamed": 1, "skipped": 0})
                    continue
                if m.get("type") in ("capture", "execute"):
                    self.actions.append(m["type"])
                    await self.envoyer({"type": "result", "req": m["req"], "result": "", "refused": True})
                    continue
                await self.recus.put(m)
        except websockets.ConnectionClosed:
            pass


async def parcours(base: str) -> None:
    ws = base.replace("http://", "ws://")
    check = tp.check
    async with websockets.connect(f"{ws}/ws/bridge", max_size=2**24) as w_mac:
        mac = Mac(w_mac)
        await mac.envoyer({"type": "hello", "os": "macos"})
        async with websockets.connect(f"{ws}/ws/aidant/{tp.CLE}", max_size=2**24) as w_aid:
            aid = tp.Canal(w_aid)
            await aid.attendre("hello", 10)

            print("\n1. Demande « range mes documents »")
            await mac.envoyer({"type": "help_request", "task": "range mes documents", "tidy": TIDY})
            p = await aid.attendre("status", 40, state="awaiting_approval")
            plan = (p or {}).get("plan") or []
            check("le support reçoit un déplacement par étape", plan == [
                "Déplacer « facture_edf.pdf » dans Documents/Factures",
                "Déplacer « Contrat bail.pdf » dans Documents/Contrats",
                "Déplacer « IMG_2041.HEIC » dans Documents/Images",
                "Déplacer « Chrome.dmg » dans Documents/Installateurs"], plan)
            texte = json.dumps(holo_vu, ensure_ascii=False)
            check("Holo a reçu les noms des fichiers", all(json.dumps(f, ensure_ascii=False)[1:-1] in texte for f in FILES))
            check("Holo n'a reçu aucune image", "image_url" not in texte and "png_b64" not in texte)
            check("aucune capture ni action demandée au Mac", mac.actions == [], mac.actions)
            check("aucun ordre avant Valider", mac.ordres == [], mac.ordres)

            print("\n2. Préciser")
            n = len(holo_vu)
            await aid.envoyer({"type": "refine_plan", "text": "Mets les images à part"})
            check("Préciser relance la préparation", await aid.attendre("status", 10, state="planning"))
            check("un nouveau plan revient", await aid.attendre("status", 40, state="awaiting_approval"))
            check("la précision est transmise à Holo",
                  len(holo_vu) > n and "Mets les images à part" in json.dumps(holo_vu[n:], ensure_ascii=False))
            check("toujours aucun ordre", mac.ordres == [])

            print("\n3. Valider")
            await aid.envoyer({"type": "approve_plan"})
            fin = await aid.attendre("answer", 40)
            check("le Mac reçoit l'ordre de rangement", len(mac.ordres) == 1 and mac.ordres[0]["folder"] == "documents")
            check("l'ordre ne contient que les déplacements du plan",
                  mac.ordres and [m["from"] for m in mac.ordres[0]["moves"]] == FILES[:4], mac.ordres)
            check("le support voit le résultat et l'annulation possible",
                  fin and "4" in fin["content"] and "Annuler le rangement" in fin["content"], fin)
            check("état final : terminée", await aid.attendre("status", 10, state="done"))

            print("\n4. Refuser")
            await mac.envoyer({"type": "help_request", "task": "range mes documents", "tidy": TIDY})
            await aid.attendre("status", 40, state="awaiting_approval")
            await aid.envoyer({"type": "refuse_plan"})
            check("Refuser arrête l'assistance", await aid.attendre("status", 10, state="stopped"))
            await asyncio.sleep(0.5)
            check("aucun ordre après refus", len(mac.ordres) == 1, mac.ordres)

            print("\n5. Demande invalide")
            await mac.envoyer({"type": "help_request", "task": "range mes documents",
                               "tidy": {"folder": "library", "files": FILES}})
            r = await aid.attendre("answer", 20)
            check("dossier hors liste refusé par le serveur", r and "Documents" in r.get("content", ""), r)
            await mac.envoyer({"type": "help_request", "task": "range mes documents",
                               "tidy": {"folder": "documents", "files": [f"f{i}.txt" for i in range(201)]}})
            r = await aid.attendre("answer", 20)
            check("plus de 200 fichiers refusés par le serveur", r and "200" in r.get("content", ""), r)
            check("aucun ordre en plus", len(mac.ordres) == 1, mac.ordres)
            aid.tache.cancel()
        mac.tache.cancel()


if __name__ == "__main__":
    tp.FauxHolo = FauxHolo
    tp.parcours = parcours
    tp.main()
