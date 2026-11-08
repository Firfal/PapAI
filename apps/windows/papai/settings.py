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
    for k in ("firstName", "server", "textScale", "onboarded", "screenConsent", "orgJoined", "orgName",
              "realtimeProtection"):
        if k in values:
            data[k] = values[k]
    p = _path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)
    return data


def protection_on(data: dict | None = None) -> bool:
    """Protection en temps réel : activée par défaut, comme un antivirus."""
    return (data if data is not None else load()).get("realtimeProtection") is not False


def needs_space(data: dict | None = None) -> bool:
    """Aucun serveur réglé (ni dans l'app, ni par PAPAI_SERVER) : il faut un espace."""
    stored = str((data if data is not None else load()).get("server") or "").strip()
    return not stored and not os.environ.get("PAPAI_SERVER", "").strip()


# Poste d'entreprise : le service IT dépose son jeton d'inscription à côté de
# PapAI.bat (organisation.txt) ou dans PAPAI_ORG. Le poste rejoint seul l'organisation.
ORG_FILE = Path(__file__).resolve().parent.parent / "organisation.txt"


def org_token() -> str:
    t = os.environ.get("PAPAI_ORG", "").strip()
    if not t:
        try:
            t = ORG_FILE.read_text(encoding="utf-8").strip().splitlines()[0].strip()
        except (OSError, IndexError):
            t = ""
    return t if t.startswith("ins-") and len(t) <= 100 else ""


def machine_name() -> str:
    """Nom du poste vu par les supports de l'organisation avant que la personne donne son prénom."""
    import getpass
    import platform
    try:
        user = getpass.getuser()
    except Exception:  # noqa: BLE001
        user = ""
    return " · ".join(x for x in (user, platform.node()) if x)[:60]


def _post(url: str, body: dict, timeout: float) -> tuple[int, dict]:
    import urllib.error
    import urllib.request
    req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), method="POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, {}
    except (OSError, ValueError):
        return 0, {}


def provision(base: str = OFFICIAL_HTTP, timeout: float = 10, org: str = "",
              info: dict | None = None) -> str | None:
    """Crée l'espace de cet ordinateur (`POST /spaces`) et renvoie l'adresse du pont,
    clé comprise. L’utilisateur n'a rien à régler. `info` reçoit la réponse
    (nom de l'organisation pour un poste d'entreprise)."""
    body = {"org": org, "name": machine_name()} if org else {}
    st, d = _post(base.rstrip("/") + "/spaces", body, timeout)
    url = str(d.get("bridge_url") or "") if st == 200 else ""
    if info is not None:
        info.update(d, status=st)
    return url if url.startswith(("wss://", "ws://")) and "/k/" in url else None


def join_org(http: str, org: str, timeout: float = 10) -> str | None:
    """Poste déjà installé : rejoint l'organisation (`POST /k/<clé>/org`).
    Renvoie le nom de l'organisation, "" si le serveur refuse, None hors ligne."""
    st, d = _post(http.rstrip("/") + "/org", {"org": org, "name": machine_name()}, timeout)
    if st == 200:
        return str(d.get("org") or "")
    return None if st == 0 or st >= 500 else ""


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
