"""Organisations : un service informatique et tous les postes de ses employés.

Le service IT crée son organisation et reçoit deux jetons :
- le jeton d'**inscription**, déposé sur les postes (fichier, variable, préférence
  gérée) : au premier lancement, le poste crée son espace rattaché à l'organisation ;
- le jeton **support**, donné aux supports de l'organisation (personnes ou support
  IA) : il liste tous les postes et leurs clés, sans appairer les employés un par un.

Les automatismes importés pour l'organisation sont copiés sur chaque poste,
y compris ceux qui s'inscrivent plus tard.
"""

from __future__ import annotations

import json
import os
import secrets
import shutil
import time
from pathlib import Path

from .space import ROOT

ORGS_DIR = Path(os.environ.get("PAPAI_DATA_DIR") or ROOT / "data") / "orgs"


class Org:
    def __init__(self, oid: str, data: dict) -> None:
        self.id = oid
        self.name = str(data.get("name", ""))
        self.enroll = str(data.get("enroll", ""))
        self.support = str(data.get("support", ""))
        self.folder = ORGS_DIR / oid
        self.lessons_dir = self.folder / "lessons"

    def next_ticket(self) -> int:
        """Numéro de ticket unique dans toute l'organisation (T-0042 ne désigne qu'un ticket)."""
        seq = self.folder / "tickets_seq"
        try:
            n = int(seq.read_text().strip()) + 1
        except (OSError, ValueError):
            n = 1
        self.folder.mkdir(parents=True, exist_ok=True)
        seq.write_text(str(n))
        return n

    def automations(self) -> list[dict]:
        out = []
        for f in sorted(self.lessons_dir.glob("imp-*/lesson.json")):
            try:
                out.append(json.loads(f.read_text("utf-8")))
            except (OSError, ValueError):
                continue
        return out

    def copy_automations(self, dest: Path, only: str | None = None) -> None:
        """Copie le catalogue de l'organisation (ou un seul automatisme) sur un poste."""
        for src in sorted(self.lessons_dir.glob("imp-*")):
            if only and src.name != only:
                continue
            if (src / "lesson.json").is_file():
                shutil.copytree(src, dest / src.name, dirs_exist_ok=True)


class Orgs:
    def __init__(self) -> None:
        self._by_id: dict[str, Org] = {}
        if ORGS_DIR.is_dir():
            for f in sorted(ORGS_DIR.glob("*/org.json")):
                try:
                    self._by_id[f.parent.name] = Org(f.parent.name, json.loads(f.read_text("utf-8")))
                except (OSError, ValueError):
                    continue

    def create(self, name: str) -> Org:
        oid = secrets.token_hex(6)
        data = {"name": name, "enroll": "ins-" + secrets.token_urlsafe(24),
                "support": "sup-" + secrets.token_urlsafe(24), "created": int(time.time())}
        (ORGS_DIR / oid).mkdir(parents=True, exist_ok=True)
        (ORGS_DIR / oid / "org.json").write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        o = Org(oid, data)
        self._by_id[oid] = o
        return o

    def get(self, oid: str) -> Org | None:
        return self._by_id.get(oid or "")

    def _find(self, attr: str, token: str) -> Org | None:
        token = str(token or "")
        found = None
        for o in self._by_id.values():
            if secrets.compare_digest(token, getattr(o, attr)):
                found = o
        return found if token else None

    def by_enroll(self, token: str) -> Org | None:
        return self._find("enroll", token)

    def by_support(self, token: str) -> Org | None:
        return self._find("support", token)
