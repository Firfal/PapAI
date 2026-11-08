"""Organisations : un service informatique et tous les postes de ses employés.

Le service IT crée son organisation et reçoit deux jetons :
- le jeton d'**inscription**, déposé sur les postes (fichier, variable, préférence
  gérée) : au premier lancement, le poste crée son espace rattaché à l'organisation ;
- le jeton **de l'organisation** (`sup-…`, champ `support`), gardé par l'IT : il liste
  tous les postes et leurs clés, et ouvre la console où l'IT gère ses supports ;
- un jeton **par support** (`sup-…` aussi, pour les apps), créé dans la console et
  révocable : seul son empreinte est gardée. Il ne donne jamais la clé d'un poste,
  seulement une clé dérivée (`sk…`) propre à ce support et à ce poste, refusée dès
  que le support est révoqué.

Les automatismes importés pour l'organisation sont copiés sur chaque poste,
y compris ceux qui s'inscrivent plus tard.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import shutil
import time
from pathlib import Path

from .space import ROOT
from . import storage

ORGS_DIR = Path(os.environ.get("PAPAI_DATA_DIR") or ROOT / "data") / "orgs"
MAX_SUPPORTS = 200
# Clé dérivée d'un poste pour un support : "sk" + id du poste (12) + id du support (8) + sceau (32).
# Mêmes caractères qu'une clé d'espace : les apps la gardent telle quelle.
DERIVED_LEN = 54


def _digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _seal(digest: str, space_id: str) -> str:
    mac = hmac.new(bytes.fromhex(digest), space_id.encode(), hashlib.sha256).digest()[:24]
    return base64.urlsafe_b64encode(mac).decode().rstrip("=")


def parse_derived(key: str) -> tuple[str, str, str] | None:
    """`sk…` → (id du poste, id du support, sceau), sinon None."""
    key = str(key or "")
    if len(key) != DERIVED_LEN or not key.startswith("sk"):
        return None
    sid, sup, seal = key[2:14], key[14:22], key[22:]
    if not all(c in "0123456789abcdef" for c in sid + sup):
        return None
    return sid, sup, seal


class Org:
    def __init__(self, oid: str, data: dict) -> None:
        self.id = oid
        self.name = str(data.get("name", ""))
        self.enroll = str(data.get("enroll", ""))
        self.support = str(data.get("support", ""))
        self.created = int(data.get("created") or 0)
        sups = data.get("supports")
        self.supports: list[dict] = [d for d in sups if isinstance(d, dict) and d.get("id")] \
            if isinstance(sups, list) else []
        self.folder = ORGS_DIR / oid
        self.lessons_dir = self.folder / "lessons"

    def _save(self) -> None:
        self.folder.mkdir(parents=True, exist_ok=True)
        data = {"name": self.name, "enroll": self.enroll, "support": self.support,
                "created": self.created, "supports": self.supports}
        tmp = self.folder / "org.json.tmp"
        tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        tmp.replace(self.folder / "org.json")

    # ------------------------------------------------------------ supports

    def add_support(self, name: str) -> tuple[dict, str]:
        """Nouveau support : son jeton n'est donné qu'ici, seule l'empreinte est gardée."""
        if len(self.supports) >= MAX_SUPPORTS:
            raise ValueError("Trop de supports dans cette organisation.")
        ids = {d["id"] for d in self.supports}
        sid = secrets.token_hex(4)
        while sid in ids:
            sid = secrets.token_hex(4)
        token = "sup-" + secrets.token_urlsafe(24)
        rec = {"id": sid, "name": name, "hash": _digest(token), "created": int(time.time()), "revoked": 0}
        self.supports.append(rec)
        self._save()
        return rec, token

    def revoke_support(self, sid: str) -> dict | None:
        rec = self.support_by_id(sid, active_only=False)
        if rec is None:
            return None
        if not rec.get("revoked"):
            rec["revoked"] = int(time.time())
            self._save()
        return rec

    def support_by_id(self, sid: str, active_only: bool = True) -> dict | None:
        rec = next((d for d in self.supports if d.get("id") == sid), None)
        if rec is None or active_only and rec.get("revoked"):
            return None
        return rec

    def support_by_token(self, token: str) -> dict | None:
        """Le support actif à qui appartient ce jeton (comparaison des empreintes)."""
        h = _digest(str(token or ""))
        found = None
        for d in self.supports:
            if hmac.compare_digest(h, str(d.get("hash", ""))) and not d.get("revoked"):
                found = d
        return found

    def derived_key(self, rec: dict, space_id: str) -> str:
        return f"sk{space_id}{rec['id']}{_seal(rec['hash'], space_id)}"

    def check_derived(self, rec: dict, space_id: str, seal: str) -> bool:
        return hmac.compare_digest(_seal(str(rec.get("hash", "")), space_id), seal)

    def rotate(self) -> str:
        """Nouveau jeton de l'organisation : l'ancien est refusé aussitôt."""
        self.support = "sup-" + secrets.token_urlsafe(24)
        self._save()
        return self.support

    @staticmethod
    def public_support(rec: dict, online: bool = False) -> dict:
        return {"id": rec["id"], "name": rec.get("name", ""), "created": rec.get("created", 0),
                "revoked": rec.get("revoked", 0) or None, "online": online}

    def next_ticket(self) -> int:
        """Numéro de ticket unique dans toute l'organisation (T-0042 ne désigne qu'un ticket)."""
        seq = self.folder / "tickets_seq"
        try:
            n = int((storage.read(seq) or b"0").strip()) + 1
        except (OSError, ValueError):
            n = 1
        storage.write(seq, str(n).encode())
        return n

    def automations(self) -> list[dict]:
        out = []
        for f in storage.files(self.lessons_dir, "imp-*/lesson.json"):
            try:
                out.append(storage.read_json(f))
            except (OSError, ValueError):
                continue
        return out

    def copy_automations(self, dest: Path, only: str | None = None) -> None:
        """Copie le catalogue de l'organisation (ou un seul automatisme) sur un poste."""
        for lesson in storage.files(self.lessons_dir, "imp-*/lesson.json"):
            src = lesson.parent
            if only and src.name != only:
                continue
            for f in storage.files(src, "*"):
                storage.write(dest / src.name / f.name, storage.read(f))


class Orgs:
    def __init__(self) -> None:
        self._by_id: dict[str, Org] = {}
        for f in storage.files(ORGS_DIR, "*/org.json"):
            try:
                self._by_id[f.parent.name] = Org(f.parent.name, storage.read_json(f))
            except (OSError, ValueError):
                continue

    def create(self, name: str) -> Org:
        oid = secrets.token_hex(6)
        data = {"name": name, "enroll": "ins-" + secrets.token_urlsafe(24),
                "support": "sup-" + secrets.token_urlsafe(24), "created": int(time.time())}
        storage.write_json(ORGS_DIR / oid / "org.json", data)
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
        """Jeton de l'organisation ou jeton actif d'un de ses supports."""
        found = self.auth(token)
        return found[0] if found else None

    def by_org_token(self, token: str) -> Org | None:
        """Seulement le jeton de l'organisation (console : gestion des supports)."""
        return self._find("support", token)

    def auth(self, token: str) -> tuple[Org, dict | None] | None:
        """(organisation, support) ; support None pour le jeton de l'organisation."""
        o = self._find("support", token)
        if o is not None:
            return o, None
        if not str(token or "").startswith("sup-"):
            return None
        for o in self._by_id.values():
            rec = o.support_by_token(token)
            if rec is not None:
                return o, rec
        return None
