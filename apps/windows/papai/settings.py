"""Réglages de l'app (équivalent des UserDefaults du Mac), dans
%APPDATA%\\PapAI\\settings.json. Le prénom, la taille du texte, le serveur, l'accord de partage d'écran."""

from __future__ import annotations

import json
import os
from pathlib import Path

DEFAULT_SERVER = "ws://localhost:8000/ws/bridge"


def _path() -> Path:
    base = os.environ.get("PAPAI_HOME") or os.environ.get("APPDATA") or str(Path.home() / ".config")
    return Path(base) / "PapAI" / "settings.json"


def load() -> dict:
    try:
        data = json.loads(_path().read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(values: dict) -> dict:
    data = load()
    for k in ("firstName", "server", "textScale", "onboarded", "screenConsent"):
        if k in values:
            data[k] = values[k]
    p = _path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)
    return data


def server_url(data: dict | None = None) -> str:
    stored = str((data if data is not None else load()).get("server") or "").strip()
    if stored:
        return stored
    return os.environ.get("PAPAI_SERVER", "").strip() or DEFAULT_SERVER


def http_base(ws_url: str) -> str:
    s = ws_url.replace("wss://", "https://").replace("ws://", "http://")
    if s.endswith("/ws/bridge"):
        s = s[: -len("/ws/bridge")]
    return s.rstrip("/")
