"""Automates gardés sur l'ordinateur pour marcher sans réseau, dans
%APPDATA%\\PapAI\\automates-hors-ligne.json. Seulement ceux qui n'ont besoin
ni de Holo ni d'un fichier du serveur. Un automate ne contient que des actions
et des consignes : jamais de clé Wi-Fi, de mot de passe ni d'identifiant."""

from __future__ import annotations

import hashlib
import json

from . import settings

NEEDS_SERVER = {"holo", "install_templates"}


def _path():
    return settings._path().with_name("automates-hors-ligne.json")


def usable_offline(lesson) -> bool:
    if not isinstance(lesson, dict) or not lesson.get("id"):
        return False
    actions = lesson.get("actions") or []
    return not any(isinstance(a, dict) and a.get("do") in NEEDS_SERVER for a in actions)


def _space(base: str) -> str:
    """Empreinte de l'espace (le serveur et sa clé) : une liste ne sert que là où elle a été reçue."""
    return hashlib.sha256(base.encode()).hexdigest()


def save(lessons: list[dict], base: str) -> None:
    p = _path()
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps({"space": _space(base),
                                   "lessons": [x for x in lessons if usable_offline(x)]}, ensure_ascii=False), encoding="utf-8")
        tmp.replace(p)
    except OSError:
        pass


def load(base: str) -> list[dict]:
    try:
        data = json.loads(_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    if not isinstance(data, dict) or data.get("space") != _space(base) or not isinstance(data.get("lessons"), list):
        return []
    return [x for x in data["lessons"] if usable_offline(x)]
