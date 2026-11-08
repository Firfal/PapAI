"""Les supports de l’utilisateur et leur liaison par code à usage unique."""

from __future__ import annotations

import json
import secrets
import time
from collections.abc import Iterable
from pathlib import Path

from . import storage

DATA = Path(__file__).parent.parent / "family.json"
CODE_TTL = 600
# Invitation envoyée par SMS, WhatsApp… à un proche absent : il a le temps de l'ouvrir.
INVITE_TTL = 24 * 3600
MAX_TRIES = 5
INVALID_CODE = "Ce code ne marche plus. Demandez un nouveau code sur l'ordinateur de l’utilisateur."


def clean_label(value: str, limit: int) -> str:
    return "".join(c for c in value if c.isalnum() or c in " -'.").strip()[:limit]


class PairingError(Exception):
    pass


class Family:
    def __init__(self, path: Path = DATA) -> None:
        self.path = path
        self.helpers: list[dict] = []
        # Le prénom de l’utilisateur, saisi sur son ordinateur. C'est lui que
        # l'aidant doit voir partout (« Vous allez aider Sophie »), jamais un nom figé.
        self.senior: str = ""
        self._code: str | None = None
        self._expires = 0.0
        self._tries = 0
        self._invitation: str | None = None
        self._invitation_expires = 0.0
        try:
            data = storage.read_json(path, {})
            self.helpers = data.get("helpers", [])
            self.senior = str(data.get("senior", ""))
        except (OSError, ValueError):
            self.helpers = []

    # ------------------------------------------------------------ code

    def new_code(self, ttl: int = CODE_TTL, *, others: Iterable[Family] = ()) -> str:
        families = tuple(others)
        code = f"{secrets.randbelow(1_000_000):06d}"
        while any(family.code_valid(code) for family in families):
            code = f"{secrets.randbelow(1_000_000):06d}"
        self._code = code
        self._expires = time.time() + ttl
        self._tries = 0
        return self._code

    def code_valid(self, code: str) -> bool:
        return (
            self._code is not None
            and time.time() < self._expires
            and secrets.compare_digest((code or "").encode(), self._code.encode())
        )

    def new_invitation(self) -> str:
        self._invitation = secrets.token_urlsafe(16)
        self._invitation_expires = time.time() + INVITE_TTL
        return self._invitation

    def invitation_valid(self, token: str) -> bool:
        return (self._invitation is not None and time.time() < self._invitation_expires
                and secrets.compare_digest(token.encode(), self._invitation.encode()))

    def consume_invitation(self, token: str) -> None:
        if not self.invitation_valid(token):
            raise PairingError(INVALID_CODE)
        self._invitation = None

    def check_code(self, code: str) -> None:
        if not self.code_valid(code):
            self._tries += 1
            if self._tries >= MAX_TRIES:
                self._code = None
            raise PairingError(INVALID_CODE)

    def consume_code(self, code: str) -> None:
        self.check_code(code)
        self._code = None

    def pair(self, code: str, name: str, relation: str) -> dict:
        name = clean_label(name or "", 40)
        relation = clean_label(relation or "", 60)
        if not name:
            raise PairingError("Indiquez votre prénom.")
        self.consume_code(code)
        return self.add_helper(name, relation)

    def add_helper(self, name: str, relation: str) -> dict:
        helper = {"id": secrets.token_hex(4), "name": name, "relation": relation,
                  "added": int(time.time())}
        self.helpers.append(helper)
        self._save()
        return helper

    def remove(self, helper_id: str) -> None:
        self.helpers = [h for h in self.helpers if h["id"] != helper_id]
        self._save()

    def set_senior(self, name: str) -> bool:
        """Retient le prénom de l’utilisateur. Vrai s'il a changé."""
        name = (name or "").strip()[:40]
        if not name or name == self.senior:
            return False
        self.senior = name
        self._save()
        return True

    def connect(self, helper_id: str, name: str, relation: str = "") -> dict | None:
        """Un aidant ouvre l'app. S'il n'est pas encore dans la liste (lié avant
        que la liste existe, ou serveur redémarré), on l'y ajoute : un proche
        connecté doit toujours apparaître dans « Mes proches »."""
        name = (name or "").strip()[:40]
        relation = (relation or "").strip()[:60]
        helper_id = (helper_id or "").strip()[:32]
        if not name:
            return None
        found = next((h for h in self.helpers if helper_id and h["id"] == helper_id), None) \
            or next((h for h in self.helpers if h["name"].casefold() == name.casefold()), None)
        if found is None:
            found = {"id": helper_id or secrets.token_hex(4), "name": name, "relation": relation,
                     "added": int(time.time())}
            self.helpers.append(found)
        else:
            found["name"] = name
            if relation:
                found["relation"] = relation
        self._save()
        return found

    def restore(self, known: list) -> bool:
        """L'ordinateur renvoie les proches qu'il connaît. Sur Cloud Run, le disque
        repart à zéro à chaque mise en ligne : sans ça, « Mes proches » se viderait.
        Vrai si au moins un proche a été rajouté."""
        added = False
        ids = {h["id"] for h in self.helpers}
        for d in (known or [])[:20]:
            if not isinstance(d, dict):
                continue
            hid = str(d.get("id", "")).strip()[:32]
            name = str(d.get("name", "")).strip()[:40]
            if not hid or not name or hid in ids:
                continue
            self.helpers.append({"id": hid, "name": name, "relation": str(d.get("relation", "")).strip()[:60],
                                 "added": int(time.time())})
            ids.add(hid)
            added = True
        if added:
            self._save()
        return added

    def public(self, online: set[str] | None = None) -> list[dict]:
        online = online or set()
        return [{"id": h["id"], "name": h["name"], "relation": h.get("relation", ""),
                 "online": h["id"] in online}
                for h in self.helpers]

    def _save(self) -> None:
        storage.write_json(self.path, {"helpers": self.helpers, "senior": self.senior})
