"""Banc d'essai du protocole PapAI, sans Mac ni iPhone.

Simule les deux apps en WebSocket et déroule le cycle complet décrit dans
PROTOCOL.md. Sert à vérifier le serveur depuis n'importe quelle machine, et à
protéger la démo : si l'un de ces contrôles tombe, un pan du produit est cassé.

    python tests/test_protocole.py [http://127.0.0.1:8000] [cle]
"""

from __future__ import annotations

import asyncio
import base64
import io
import json
import sys

import websockets
from PIL import Image, ImageDraw

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000").rstrip("/")
CLE = sys.argv[2] if len(sys.argv) > 2 else "demo"
WS = BASE.replace("https://", "wss://").replace("http://", "ws://")
W, H = 1280, 800

ok = fails = 0
FUITES: list = []  # actions reçues par le Mac avec l'argument interne plan_step


def check(label: str, cond: bool, detail: object = "") -> None:
    global ok, fails
    if cond:
        ok += 1
        print(f"  OK      {label}")
    else:
        fails += 1
        print(f"  ECHEC   {label}  {detail}")


def bureau() -> str:
    """Un faux bureau : on n'envoie jamais l'écran réel d'un testeur."""
    img = Image.new("RGB", (W, H), (28, 30, 34))
    d = ImageDraw.Draw(img)
    d.rectangle([60, 40, 1220, 740], fill=(246, 246, 248), outline=(200, 200, 205))
    d.rectangle([60, 40, 1220, 86], fill=(232, 233, 238))
    d.text((80, 58), "Finder  —  Images", fill=(30, 30, 35))
    d.rectangle([60, 86, 300, 740], fill=(238, 239, 243))
    for i, nom in enumerate(["Favoris", "Bureau", "Documents", "Images", "Téléchargements"]):
        d.text((84, 110 + i * 32), nom, fill=(50, 50, 60))
    for nom, x in [("Photos", 360), ("Noël 2025", 600)]:
        d.rectangle([x, 140, x + 170, 250], fill=(255, 214, 128), outline=(214, 170, 80))
        d.text((x + 10, 262), nom, fill=(30, 30, 35))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


FRAME = bureau()


async def attendre(ws, voulu: str, delai: float = 45) -> dict | None:
    fin = asyncio.get_running_loop().time() + delai
    while asyncio.get_running_loop().time() < fin:
        reste = fin - asyncio.get_running_loop().time()
        try:
            m = json.loads(await asyncio.wait_for(ws.recv(), reste))
        except (asyncio.TimeoutError, websockets.ConnectionClosed):
            return None
        if m.get("type") == voulu:
            return m
    return None


async def mac(ws, actions: list, arret: asyncio.Event) -> None:
    """Le Mac : répond aux captures, note les actions, n'exécute rien."""
    n = 0
    try:
        async for brut in ws:
            m = json.loads(brut)
            if m.get("type") == "capture":
                n += 1
                await ws.send(json.dumps({
                    "type": "frame", "req": m["req"], "frame_id": f"f{n}",
                    "png_b64": FRAME, "width": W, "height": H,
                }))
            elif m.get("type") == "execute":
                a = m["action"]
                actions.append(a["name"])
                if "plan_step" in (a.get("args") or {}):
                    FUITES.append(a)
                await ws.send(json.dumps({
                    "type": "result", "req": m["req"],
                    "result": f"{a['name']} simulé", "refused": arret.is_set(),
                }))
    except websockets.ConnectionClosed:
        pass


async def main() -> None:
    actions: list = []
    arret = asyncio.Event()

    # --- clé invalide
    try:
        async with websockets.connect(f"{WS}/ws/aidant/pas-la-bonne") as mauvais:
            m = json.loads(await asyncio.wait_for(mauvais.recv(), 5))
            check("clé d'aidant invalide refusée", m.get("type") == "refused", m)
    except Exception as e:
        check("clé d'aidant invalide refusée", True, f"({type(e).__name__})")

    async with websockets.connect(f"{WS}/ws/bridge", max_size=2**24) as pont:
        await pont.send(json.dumps({"type": "hello", "os": "macos"}))
        service = asyncio.create_task(mac(pont, actions, arret))

        async with websockets.connect(f"{WS}/ws/aidant/{CLE}", max_size=2**24) as aidant:
            h = await attendre(aidant, "hello", 10)
            check("l'aidant est informé que le Mac est là", h and h.get("bridge"), h)

            # --- la personne aidée demande de l'aide
            await pont.send(json.dumps({
                "type": "help_request", "task": "Je ne retrouve pas mes photos de Noël"}))

            st = await attendre(aidant, "status", 20)
            check("l'aidant reçoit l'état de la demande", st is not None, st)

            # --- Holo propose un plan ; rien ne doit bouger avant validation
            vu_plan = None
            fin = asyncio.get_running_loop().time() + 60
            while asyncio.get_running_loop().time() < fin:
                m = json.loads(await asyncio.wait_for(aidant.recv(), 60))
                if m.get("type") == "status" and m.get("state") == "awaiting_approval":
                    vu_plan = m
                    break
            check("Holo propose un plan et attend", vu_plan is not None, "pas de plan")
            if vu_plan:
                for i, e in enumerate(vu_plan.get("plan") or [], 1):
                    print(f"          {i}. {str(e)[:66]}")
            check("aucune action avant validation", actions == [], actions)

            # --- l'aidant précise plutôt que valider
            await aidant.send(json.dumps({
                "type": "refine_plan", "text": "Ce sont les photos de Noël 2025."}))
            encore = None
            fin = asyncio.get_running_loop().time() + 60
            while asyncio.get_running_loop().time() < fin:
                m = json.loads(await asyncio.wait_for(aidant.recv(), 60))
                if m.get("type") == "status" and m.get("state") == "awaiting_approval":
                    encore = m
                    break
            check("une précision relance un nouveau plan", encore is not None)
            check("toujours aucune action après précision", actions == [], actions)
            check("pas d'étape en cours avant validation",
                  encore is not None and encore.get("plan_step") is None, encore and encore.get("plan_step"))

            # --- l'aidant valide : l'exécution commence
            await aidant.send(json.dumps({"type": "approve_plan"}))
            await asyncio.sleep(16)
            check("l'exécution démarre après validation", actions != [], "aucune action")
            if actions:
                print(f"          actions : {actions}")

            # --- l'étape du plan en cours (status.plan_step, champ optionnel)
            etapes = []
            while True:
                try:
                    m = json.loads(await asyncio.wait_for(aidant.recv(), 0.5))
                except asyncio.TimeoutError:
                    break
                if m.get("type") == "status" and m.get("state") == "active":
                    etapes.append(m.get("plan_step"))
            nb = len((encore or {}).get("plan") or [])
            check("l'étape du plan en cours est indiquée",
                  bool(etapes) and all(isinstance(e, int) and 1 <= e <= nb for e in etapes)
                  and etapes == sorted(etapes), etapes)
            print(f"          étapes : {etapes}")
            check("plan_step ne descend pas jusqu'au Mac", FUITES == [], FUITES)

            # --- l'arrêt de la personne aidée coupe tout
            avant = len(actions)
            arret.set()
            await pont.send(json.dumps({"type": "stop"}))
            await asyncio.sleep(14)
            check("après Arrêter, plus aucune action", len(actions) == avant,
                  f"{len(actions) - avant} action(s) de trop")

            # --- « Garder comme automatisme » : jamais de silence, même si
            # Holo renvoie des étapes en simples chaînes (faux_holo.py).
            await aidant.send(json.dumps({"type": "draft_lesson"}))
            fiche = None
            fin = asyncio.get_running_loop().time() + 60
            while asyncio.get_running_loop().time() < fin:
                try:
                    m = json.loads(await asyncio.wait_for(aidant.recv(), 60))
                except (asyncio.TimeoutError, websockets.ConnectionClosed):
                    break
                if m.get("type") in ("lesson_draft", "refused"):
                    fiche = m
                    break
            etapes = ((fiche or {}).get("lesson") or {}).get("steps") or []
            check("la fiche est rédigée, étapes lisibles",
                  fiche is not None and fiche.get("type") == "lesson_draft"
                  and all(isinstance(e, dict) and e.get("instruction") for e in etapes)
                  and etapes != [], fiche)

        service.cancel()

    print()
    print(f"{ok} contrôles passés, {fails} échec(s)")
    sys.exit(1 if fails else 0)


asyncio.run(main())
