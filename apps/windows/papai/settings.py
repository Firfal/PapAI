"""Réglages de l'app (équivalent des UserDefaults du Mac), dans
%APPDATA%\\PapAI\\settings.json. Le prénom, la taille du texte, le serveur, l'accord de partage d'écran."""

from __future__ import annotations

import json
import os
from pathlib import Path

DEFAULT_SERVER = "ws://localhost:8000/ws/bridge"
# Serveur PapAI officiel : sans réglage, l'ordinateur y crée son espace au premier lancement.
OFFICIAL_HTTP = "https://papai-450417131702.europe-west1.run.app"


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


def needs_space(data: dict | None = None) -> bool:
    """Aucun serveur réglé (ni dans l'app, ni par PAPAI_SERVER) : il faut un espace."""
    stored = str((data if data is not None else load()).get("server") or "").strip()
    return not stored and not os.environ.get("PAPAI_SERVER", "").strip()


def provision(base: str = OFFICIAL_HTTP, timeout: float = 10) -> str | None:
    """Crée l'espace de cet ordinateur (`POST /spaces`) et renvoie l'adresse du pont,
    clé comprise. La personne aidée n'a rien à régler."""
    import urllib.request
    req = urllib.request.Request(base.rstrip("/") + "/spaces", data=b"{}", method="POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            url = str(json.loads(r.read().decode("utf-8")).get("bridge_url") or "")
    except (OSError, ValueError):
        return None
    return url if url.startswith(("wss://", "ws://")) and "/k/" in url else None


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
