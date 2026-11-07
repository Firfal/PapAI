"""Un faux Mac, pour essayer PapAI sans Mac.

Se connecte comme l'app de la personne aidée, demande de l'aide, répond aux
captures avec un faux bureau, et journalise les actions sans rien exécuter.
Permet d'essayer tout le parcours de l'aidant depuis un navigateur.

    python tests/faux_mac.py                      demande d'aide
    python tests/faux_mac.py --guard anydesk      déclenche le gardien
    python tests/faux_mac.py --guard virus        fausse alerte à l'écran
"""

from __future__ import annotations

import asyncio
import base64
import io
import json
import sys

import websockets
from PIL import Image, ImageDraw

BASE = "ws://127.0.0.1:8000"
W, H = 1280, 800

GARDIEN = {
    "anydesk": {"processes": ["Safari", "AnyDesk"], "window": "Bureau", "url": ""},
    "banque": {"processes": ["AnyDesk"], "window": "Safari",
               "url": "https://mabanque.bnpparibas/comptes"},
    "virus": {"processes": [], "url": "",
              "window": "VOTRE ORDINATEUR EST INFECTÉ — appelez le 01 23 45 67 89"},
    "cadeau": {"processes": [], "window": "Safari",
               "url": "https://transcash.fr/recharger"},
}


def bureau(etape: int) -> str:
    img = Image.new("RGB", (W, H), (28, 30, 34))
    d = ImageDraw.Draw(img)
    d.rectangle([60, 40, 1220, 740], fill=(246, 246, 248), outline=(200, 200, 205))
    d.rectangle([60, 40, 1220, 86], fill=(232, 233, 238))
    d.text((80, 58), "Finder  —  Images" if etape else "Bureau", fill=(30, 30, 35))
    d.rectangle([60, 86, 300, 740], fill=(238, 239, 243))
    for i, nom in enumerate(["Favoris", "Bureau", "Documents", "Images", "Téléchargements"]):
        d.text((84, 110 + i * 32), nom, fill=(50, 50, 60))
    for nom, x in [("Photos", 360), ("Noël 2025", 600)]:
        d.rectangle([x, 140, x + 170, 250], fill=(255, 214, 128), outline=(214, 170, 80))
        d.text((x + 10, 262), nom, fill=(30, 30, 35))
    d.rectangle([0, 756, W, H], fill=(20, 22, 26))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


async def main() -> None:
    args = sys.argv[1:]
    signal = None
    if args and args[0] == "--guard":
        cle = args[1] if len(args) > 1 else "anydesk"
        signal = GARDIEN.get(cle)
        if signal is None:
            print(f"situations connues : {', '.join(GARDIEN)}")
            return

    tache = "Je ne retrouve pas mes photos de Noël"
    async with websockets.connect(f"{BASE}/ws/bridge", max_size=2**24) as ws:
        await ws.send(json.dumps({"type": "hello", "os": "macos"}))

        if signal is not None:
            await ws.send(json.dumps({"type": "guard", **signal}))
            print(f"[faux mac] signal gardien envoyé : {signal}", flush=True)
        else:
            await ws.send(json.dumps({"type": "help_request", "task": tache}))
            print(f"[faux mac] demande d'aide : « {tache} »", flush=True)

        n = 0
        async for brut in ws:
            m = json.loads(brut)
            t = m.get("type")
            if t == "capture":
                n += 1
                await ws.send(json.dumps({
                    "type": "frame", "req": m["req"], "frame_id": f"f{n}",
                    "png_b64": bureau(n), "width": W, "height": H,
                }))
            elif t == "execute":
                a = m["action"]
                cible = a["args"].get("element") or a["args"].get("keys") or ""
                print(f"[faux mac] ACTION {a['name']} — {cible}  (simulée)", flush=True)
                await ws.send(json.dumps({
                    "type": "result", "req": m["req"],
                    "result": f"{a['name']} simulé", "refused": False,
                }))
            elif t == "alert":
                print(f"[faux mac] ALERTE [{m.get('level')}] {m.get('title')}", flush=True)
                print(f"           {m.get('detail','')[:200]}", flush=True)
            elif t == "status":
                print(f"[faux mac] état : {m.get('state')}", flush=True)
            elif t == "answer":
                print(f"[faux mac] terminé : {m.get('content','')}", flush=True)


asyncio.run(main())
