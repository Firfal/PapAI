"""Les proches de la personne aidée, et leur ajout par code à 6 chiffres.

La personne aidée affiche un code (et son QR). Le proche l'ouvre sur son
téléphone, donne son prénom et son lien (« ma fille »). Le code ne sert
qu'une fois, expire au bout de 10 minutes et tombe après 5 essais ratés :
6 chiffres ne protègent que s'ils ne vivent pas longtemps.
"""

from __future__ import annotations

import json
import secrets
import time
from pathlib import Path

DATA = Path(__file__).parent.parent / "family.json"
CODE_TTL = 600
MAX_TRIES = 5


class PairingError(Exception):
    pass


class Family:
    def __init__(self, path: Path = DATA) -> None:
        self.path = path
        self.helpers: list[dict] = []
        self._code: str | None = None
        self._expires = 0.0
        self._tries = 0
        if path.is_file():
            try:
                self.helpers = json.loads(path.read_text("utf-8")).get("helpers", [])
            except (OSError, ValueError):
                self.helpers = []

    # ------------------------------------------------------------ code

    def new_code(self) -> str:
        self._code = f"{secrets.randbelow(1_000_000):06d}"
        self._expires = time.time() + CODE_TTL
        self._tries = 0
        return self._code

    def code_valid(self, code: str) -> bool:
        return (
            self._code is not None
            and time.time() < self._expires
            and secrets.compare_digest(code or "", self._code)
        )

    def pair(self, code: str, name: str, relation: str) -> dict:
        if self._code is None or time.time() >= self._expires:
            raise PairingError("Ce code a expiré. Demandez-en un nouveau sur l'ordinateur.")
        if not secrets.compare_digest(code or "", self._code):
            self._tries += 1
            if self._tries >= MAX_TRIES:
                self._code = None
            raise PairingError("Code incorrect.")
        name = (name or "").strip()[:40]
        relation = (relation or "").strip()[:60]
        if not name:
            raise PairingError("Indiquez votre prénom.")
        self._code = None  # une seule fois
        helper = {"id": secrets.token_hex(4), "name": name, "relation": relation,
                  "added": int(time.time())}
        self.helpers.append(helper)
        self._save()
        return helper

    def remove(self, helper_id: str) -> None:
        self.helpers = [h for h in self.helpers if h["id"] != helper_id]
        self._save()

    def public(self) -> list[dict]:
        return [{"id": h["id"], "name": h["name"], "relation": h.get("relation", "")}
                for h in self.helpers]

    def _save(self) -> None:
        self.path.write_text(json.dumps({"helpers": self.helpers}, ensure_ascii=False, indent=1), "utf-8")
