"""Prénom de la personne aidée et invitation à distance.

    python tests/test_profil.py [http://127.0.0.1:8000] [cle]

Vérifie que le prénom saisi sur l'ordinateur arrive chez l'aidant (hello, mise à
jour, appairage, lien du QR) et que l'invitation envoyée par SMS vaut 24 h.
"""
from __future__ import annotations

import asyncio
import json
import sys
import urllib.request
from urllib.parse import parse_qs, urlparse

import websockets

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
KEY = sys.argv[2] if len(sys.argv) > 2 else "demo"
WS = BASE.replace("http", "ws", 1)
fails = 0


def check(ok: bool, label: str) -> None:
    global fails
    print(("  OK      " if ok else "  ÉCHEC   ") + label)
    fails += 0 if ok else 1


async def recv_type(ws, kind: str, timeout: float = 5.0) -> dict:
    end = asyncio.get_running_loop().time() + timeout
    while True:
        m = json.loads(await asyncio.wait_for(ws.recv(), end - asyncio.get_running_loop().time()))
        if m.get("type") == kind:
            return m


async def main() -> None:
    async with websockets.connect(f"{WS}/ws/bridge") as mac:
        await mac.send(json.dumps({"type": "hello", "os": "macos", "name": "Sophie"}))
        await recv_type(mac, "helpers")
        async with websockets.connect(f"{WS}/ws/aidant/{KEY}") as aidant:
            hello = await recv_type(aidant, "hello")
            check(hello.get("senior") == "Sophie", "l'aidant reçoit le prénom saisi sur l'ordinateur (hello)")

            await mac.send(json.dumps({"type": "profile", "name": "Martine"}))
            m = await recv_type(aidant, "senior")
            check(m.get("name") == "Martine", "un changement de prénom arrive chez l'aidant (senior)")

            await mac.send(json.dumps({"type": "pair_start"}))
            short = await recv_type(mac, "pair_code")
            check(short.get("expires_in") == 600 and not short.get("long"), "code de QR : 10 minutes")

            await mac.send(json.dumps({"type": "pair_start", "long": True}))
            inv = await recv_type(mac, "pair_code")
            check(inv.get("expires_in") == 24 * 3600 and inv.get("long") is True, "invitation à envoyer : 24 heures")
            q = parse_qs(urlparse(inv.get("app_url", "")).query)
            check(q.get("n") == ["Martine"], "le lien de l'app porte le prénom (n=)")

            req = urllib.request.Request(inv["url"], method="POST",
                                         data=json.dumps({"name": "Léa", "relation": "sa petite-fille"}).encode(),
                                         headers={"Content-Type": "application/json"})
            r = json.loads(urllib.request.urlopen(req, timeout=10).read())
            check(r.get("ok") is True and r.get("senior") == "Martine", "l'appairage renvoie le prénom de la personne aidée")
            helpers = await recv_type(mac, "helpers")
            # Nettoyage : on retire le proche de test.
            for h in helpers.get("helpers", []):
                if h.get("name") == "Léa":
                    await mac.send(json.dumps({"type": "remove_helper", "id": h["id"]}))

    print(f"\n{6 - fails} contrôles passés, {fails} échec(s)")
    sys.exit(1 if fails else 0)


asyncio.run(main())
