"""Protection en temps réel : l'interrupteur de l'ordinateur décide si le gardien écoute.

Serveur temporaire. Activée, un signal du gardien (outil de prise en main
ouvert) déclenche une alerte ; coupée, rien n'est évalué. Le support voit
l'état à sa connexion et à chaque changement.

    python tests/test_protection.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import websockets

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_appairage_code as base_test  # noqa: E402
from test_tickets import attendre, drain  # noqa: E402

check, http = base_test.check, base_test.http
SIGNAL = {"type": "guard", "processes": ["AnyDesk"], "window": "", "url": ""}


async def parcours(base: str) -> None:
    wsb = base.replace("http://", "ws://")
    st, a = http(f"{base}/spaces", {})
    key = a["key"]
    async with websockets.connect(a["bridge_url"]) as wa:
        await wa.send(json.dumps({"type": "hello", "os": "windows", "protection": False}))
        await drain(wa, 0.5)
        async with websockets.connect(f"{wsb}/k/{key}/ws/aidant/{key}") as ha:
            h = json.loads(await ha.recv())
            check("le support voit la protection coupée à sa connexion",
                  h.get("type") == "hello" and h.get("protection") is False)
            await drain(ha, 0.5)

            await wa.send(json.dumps(SIGNAL))
            check("protection coupée : aucun signal n'est évalué", await attendre(wa, "alert", 1.5) is None)

            await wa.send(json.dumps({"type": "profile", "protection": True}))
            m = await attendre(ha, "protection")
            check("le support est prévenu quand elle est réactivée", m is not None and m.get("on") is True)

            await wa.send(json.dumps(SIGNAL))
            al = await attendre(wa, "alert")
            check("protection activée : l'outil de prise en main déclenche l'alerte", al is not None)

            await wa.send(json.dumps({"type": "profile", "protection": True}))
            check("même état renvoyé : pas de message en double", await attendre(ha, "protection", 1.0) is None)

    async with websockets.connect(f"{wsb}/k/{key}/ws/aidant/{key}") as ha:
        h = json.loads(await ha.recv())
        check("ordinateur hors ligne : état inconnu", h.get("type") == "hello" and h.get("protection") is None)


if __name__ == "__main__":
    base_test.parcours = parcours
    base_test.main()
