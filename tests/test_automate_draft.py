"""Brouillon d'automate (document, enregistrement) : contrôles sans clé H.

    python tests/test_automate_draft.py
"""

from __future__ import annotations

import asyncio
import base64
import os
import sys
from types import SimpleNamespace

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("HAI_API_KEY", "test")

from backend import automate_draft as d  # noqa: E402

ok = fails = 0


def check(label, cond, detail=""):
    global ok, fails
    if cond:
        ok += 1
        print(f"  OK      {label}")
    else:
        fails += 1
        print(f"  ECHEC   {label}  {detail}")


def refused(req) -> bool:
    try:
        d.build_messages(req)
    except d.DraftError:
        return True
    return False


class FakeClient:
    def __init__(self, answer: str):
        self.answer = answer
        self.seen = None
        self.chat = SimpleNamespace(completions=SimpleNamespace(create=self.create))

    def create(self, **kw):
        self.seen = kw
        return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=self.answer))])


TUTO = "Pour vous connecter au Wi-Fi sur Mac : cliquez sur l'icône Wi-Fi en haut à droite, choisissez votre réseau, tapez la clé."
PNG = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"0" * 50).decode()

check("source inconnue refusée", refused({"kind": "url", "url": "https://x"}))
check("document vide refusé", refused({"kind": "document", "text": "  "}))
check("enregistrement sans capture refusé", refused({"kind": "recording", "frames": []}))
check("capture illisible refusée", refused({"kind": "recording", "frames": [{"b64": "%%%"}]}))
check("type d'image refusé", refused({"kind": "recording", "frames": [{"b64": PNG, "mime": "image/gif"}]}))
m = d.build_messages({"kind": "recording", "narration": "j'ouvre le Wi-Fi",
                      "frames": [{"b64": PNG, "mime": "image/png"}] * 9})
imgs = [c for c in m[1]["content"] if c.get("type") == "image_url"]
check("5 captures au plus envoyées à Holo", len(imgs) == 5, len(imgs))
check("la narration accompagne les captures", "j'ouvre le Wi-Fi" in m[1]["content"][0]["text"])

c = d.clean({"title": "Se connecter au Wi-Fi", "goal": "Ouvrir le menu Wi-Fi",
             "steps": ["a", {"instruction": "b"}, "", "c", "d", "e", "f", "g"],
             "platforms": ["mac", "linux"], "warning": ""})
check("étapes nettoyées et limitées à 6", c["steps"] == ["a", "b", "c", "d", "e", "f"], c["steps"])
check("plateformes inconnues écartées", c["platforms"] == ["mac"], c["platforms"])
try:
    d.clean({"error": "Pas de tutoriel ici."})
    check("source sans tutoriel signalée", False)
except d.DraftError as e:
    check("source sans tutoriel signalée", "tutoriel" in str(e))

fake = FakeClient('Voici : {"title":"Se connecter au Wi-Fi","description":"x","goal":"Connecter le Mac au Wi-Fi",'
                  '"steps":["Cliquer sur l\'icône Wi-Fi","Choisir le réseau"],"platforms":["mac"],"warning":""}')
d._client = fake
r = asyncio.run(d.draft({"kind": "document", "name": "wifi.txt", "text": TUTO}))
check("brouillon produit depuis un document", r["title"] == "Se connecter au Wi-Fi" and len(r["steps"]) == 2, r)
check("le document est transmis à Holo", TUTO in str(fake.seen["messages"]))

print(f"\n{ok} contrôles passés, {fails} échec(s)")
sys.exit(1 if fails else 0)
