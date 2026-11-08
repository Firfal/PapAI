"""Réglages de l'app (équivalent des UserDefaults du Mac), dans
%APPDATA%\\PapAI\\settings.json : la taille du texte, le serveur, l'accord de partage d'écran.

Poste d'entreprise : l'organisation, le serveur et le nom affiché viennent des
stratégies de groupe (`HKLM|HKCU\\SOFTWARE\\Policies\\PapAI`), voir `policy()`.
L'employé n'a rien à régler."""

from __future__ import annotations

import json
import os
import sys
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
    for k in ("server", "textScale", "screenConsent", "orgJoined", "orgName", "realtimeProtection"):
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
    """Aucun serveur réglé (ni dans l'app, ni par PAPAI_SERVER) : il faut un espace.
    Aussi quand la stratégie `Server` désigne un autre serveur que celui de l'espace gardé."""
    if os.environ.get("PAPAI_SERVER", "").strip():
        return False
    stored = str((data if data is not None else load()).get("server") or "").strip()
    if not stored:
        return True
    return bool(policy().get("Server")) and not http_base(stored).startswith(enroll_base())


# ------------------------------------------------- stratégies de groupe (GPO)

POLICY_KEY = r"SOFTWARE\Policies\PapAI"
POLICY_VALUES = ("OrgToken", "Server", "DisplayName", "Role")


def _read_policy_key(root) -> dict:
    import winreg  # noqa: PLC0415 — Windows seulement
    out: dict = {}
    try:
        with winreg.OpenKey(root, POLICY_KEY) as k:
            for name in POLICY_VALUES:
                try:
                    v, kind = winreg.QueryValueEx(k, name)
                except OSError:
                    continue
                if kind in (winreg.REG_SZ, winreg.REG_EXPAND_SZ) and str(v).strip():
                    out[name] = str(v).strip()[:200]
    except OSError:
        pass
    return out


def policy() -> dict:
    """Valeurs posées par l'IT : `HKLM` (stratégie ordinateur) l'emporte sur `HKCU`
    (stratégie utilisateur). Vide hors Windows : les tests passent par PAPAI_ORG."""
    if sys.platform != "win32":
        return {}
    import winreg  # noqa: PLC0415
    merged = _read_policy_key(winreg.HKEY_CURRENT_USER)
    merged.update(_read_policy_key(winreg.HKEY_LOCAL_MACHINE))
    return merged


# Repli pour les essais : jeton déposé à côté de PapAI.bat (organisation.txt) ou PAPAI_ORG.
ORG_FILE = Path(__file__).resolve().parent.parent / "organisation.txt"


def _valid_token(t: str) -> str:
    t = (t or "").strip()
    return t if t.startswith("ins-") and len(t) <= 100 else ""


def org_token() -> str:
    """Jeton d'inscription : stratégie de groupe, puis PAPAI_ORG, puis organisation.txt."""
    t = _valid_token(policy().get("OrgToken", ""))
    if t:
        return t
    t = os.environ.get("PAPAI_ORG", "").strip()
    if not t:
        try:
            t = ORG_FILE.read_text(encoding="utf-8").strip().splitlines()[0].strip()
        except (OSError, IndexError):
            t = ""
    return _valid_token(t)


def enroll_base() -> str:
    """Serveur où le poste s'inscrit : `Server` de la stratégie (adresse https:// ou
    wss://…/ws/bridge), sinon le serveur PapAI officiel."""
    s = policy().get("Server", "")
    if s.startswith(("https://", "http://", "wss://", "ws://")) and "/k/" not in s:
        return http_base(s)
    return OFFICIAL_HTTP


def _windows_display_name() -> str:
    """Nom complet du compte Windows (« Jeanne Martin »), celui de l'annuaire."""
    if sys.platform != "win32":
        return ""
    import ctypes  # noqa: PLC0415
    try:
        fn = ctypes.windll.secur32.GetUserNameExW
        size = ctypes.c_ulong(0)
        fn(3, None, ctypes.byref(size))  # 3 = NameDisplay
        if not size.value:
            return ""
        buf = ctypes.create_unicode_buffer(size.value + 1)
        if fn(3, buf, ctypes.byref(size)):
            return buf.value.strip()
    except Exception:  # noqa: BLE001 — hors domaine, secur32 absent
        pass
    return ""


def _login_name() -> str:
    try:
        n = os.getlogin()
    except OSError:
        n = ""
    return (n or os.environ.get("USERNAME") or os.environ.get("USER") or "").strip()


def full_name() -> str:
    """Nom complet de l'employé : stratégie `DisplayName`, puis compte Windows, puis identifiant."""
    return (policy().get("DisplayName") or _windows_display_name() or _login_name())[:60]


def display_name() -> str:
    """Le prénom de « Bonjour <prénom> » : premier mot du nom complet.
    « Martin, Jeanne » (annuaire) donne « Jeanne » ; l'identifiant `jean.dupont`, « Jean »."""
    named = policy().get("DisplayName") or _windows_display_name()
    if named:
        if "," in named:
            named = named.split(",", 1)[1] or named
        words = named.split()
        return words[0][:40] if words else ""
    words = _login_name().replace(".", " ").replace("_", " ").split()
    if not words:
        return ""
    w = words[0][:40]
    return w[:1].upper() + w[1:]


def role() -> str:
    """Service ou fonction de l'employé (stratégie `Role`), montré au support à côté du nom."""
    return policy().get("Role", "")[:60]


def machine_name() -> str:
    """Nom du poste vu par les supports de l'organisation : nom, service, ordinateur."""
    import platform
    return " · ".join(x for x in (full_name(), role(), platform.node()) if x)[:60]


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


def provision(base: str | None = None, timeout: float = 10, org: str = "",
              info: dict | None = None) -> str | None:
    """Crée l'espace de cet ordinateur (`POST /spaces`) et renvoie l'adresse du pont,
    clé comprise. L’utilisateur n'a rien à régler. `info` reçoit la réponse
    (nom de l'organisation pour un poste d'entreprise)."""
    body = {"org": org, "name": machine_name()} if org else {}
    st, d = _post((base or enroll_base()).rstrip("/") + "/spaces", body, timeout)
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
