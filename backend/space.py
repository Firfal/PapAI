"""Espaces : un par ordinateur aidé, chacun avec sa clé.

Un support peut suivre plusieurs personnes aidées (un proche, le service IT) :
le serveur héberge autant d'espaces que d'ordinateurs. Chaque espace a ses
supports, ses sessions, son alerte en cours et ses automatismes. La clé de
l'URL (`/k/<clé>/…`) choisit l'espace ; le reste du code lit `current()`.

L'espace historique (`PAPAI_AIDANT_KEY`) garde `family.json` et `lessons/` à
la racine du dépôt : rien ne change pour un déploiement existant.
"""

from __future__ import annotations

import contextvars
import json
import os
import re
import secrets
import time
from pathlib import Path

from .family import Family
from .sessions import Registry

ROOT = Path(__file__).parent.parent
DATA_DIR = Path(os.environ.get("PAPAI_DATA_DIR") or ROOT / "data") / "spaces"
# Clé d'un espace : assez longue pour ne pas se deviner, sans caractère d'URL.
KEY_RE = re.compile(r"^[A-Za-z0-9_-]{12,64}$")


class Space:
    def __init__(self, key: str, folder: Path, sid: str = "") -> None:
        self.key = key
        self.id = sid or "defaut"
        self.folder = folder
        self.family = Family(folder / "family.json")
        self.registry = Registry()
        self.lessons_dir = folder / "lessons"
        self.bridge = None
        self.helper_sockets: set = set()
        self.helper_alert_scopes: dict = {}
        self.helper_who: dict = {}
        self.agent_task = None
        self.pending_alert: dict | None = None
        self.guard_vu: dict[str, float] = {}


class Spaces:
    def __init__(self, default_key: str) -> None:
        self.default = Space(default_key, ROOT)
        self._by_key: dict[str, Space] = {default_key: self.default}
        if DATA_DIR.is_dir():
            for f in sorted(DATA_DIR.glob("*/space.json")):
                try:
                    d = json.loads(f.read_text("utf-8"))
                    self._add(str(d["key"]), f.parent.name)
                except (OSError, ValueError, KeyError):
                    continue

    def _add(self, key: str, sid: str) -> Space:
        sp = Space(key, DATA_DIR / sid, sid)
        self._by_key[key] = sp
        return sp

    def get(self, key: str) -> Space | None:
        for k, sp in self._by_key.items():
            if secrets.compare_digest(key or "", k):
                return sp
        return None

    def all(self) -> list[Space]:
        return list(self._by_key.values())

    def create(self, key: str | None = None) -> Space:
        """Nouvel espace. `key` : un ordinateur qui revient avec sa clé après
        un redéploiement (disque effacé) retrouve un espace à son nom."""
        key = key or secrets.token_urlsafe(18)
        if not KEY_RE.match(key):
            raise ValueError("clé invalide")
        sid = secrets.token_hex(6)
        (DATA_DIR / sid).mkdir(parents=True, exist_ok=True)
        (DATA_DIR / sid / "space.json").write_text(
            json.dumps({"key": key, "created": int(time.time())}), encoding="utf-8")
        return self._add(key, sid)


_current: contextvars.ContextVar[Space | None] = contextvars.ContextVar("papai_space", default=None)
_spaces: Spaces | None = None


def setup(default_key: str) -> Spaces:
    global _spaces
    _spaces = Spaces(default_key)
    return _spaces


def current() -> Space:
    sp = _current.get()
    if sp is not None:
        return sp
    assert _spaces is not None, "space.setup() pas encore appelé"
    return _spaces.default


def use(sp: Space) -> None:
    """Fixe l'espace de la requête en cours (et des tâches qu'elle lance)."""
    _current.set(sp)
