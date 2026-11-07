"""Ce que PapAI fait sur l'ordinateur : regarder, agir, et s'arrêter.

Portage de `apps/mac/Sources/Core.swift`. Mêmes règles, mêmes phrases, mêmes
refus ; seules les API changent : mss au lieu de ScreenCaptureKit, SendInput
(via pyautogui, et en direct pour le texte accentué) au lieu de CGEvent, les
dossiers connus de Windows au lieu de FileManager.
"""

from __future__ import annotations

import base64
import ctypes
import io
import os
import sys
import threading
import time
from pathlib import Path
from typing import Callable

WINDOWS = sys.platform == "win32"
SEND_WIDTH = 1280  # comme le Mac : assez pour viser juste, pas plus


# ------------------------------------------------------------ verrou d'arrêt


class StopGate:
    """Le verrou d'arrêt. Levé depuis l'interface AVANT d'envoyer `stop` au
    serveur, lu avant chaque action : il ne dépend d'aucun réseau."""

    def __init__(self) -> None:
        self._stopped = threading.Event()

    def raise_stop(self) -> None:
        self._stopped.set()

    def reset(self) -> None:
        """Nouvelle session : un verrou neuf. Un geste encore en cours garde
        l'ancien, levé, et ne reprend jamais."""
        if self._stopped.is_set():
            self._stopped = threading.Event()

    def pin(self) -> "StopGate":
        """Le verrou tel qu'il est maintenant, pour toute la durée d'un geste."""
        g = StopGate.__new__(StopGate)
        g._stopped = self._stopped
        return g

    @property
    def is_stopped(self) -> bool:
        return self._stopped.is_set()


class Stopped(Exception):
    pass


class ProtectedZone(Exception):
    pass


class UnknownKey(Exception):
    pass


# ------------------------------------------------------------------ l'écran


class Screen:
    """L'écran principal, et lui seul : c'est là que tombent les clics."""

    def __init__(self) -> None:
        import mss

        self._mss = mss
        with mss.mss() as sct:
            ecrans = sct.monitors[1:]
            m = next((e for e in ecrans if e.get("is_primary")), None) or ecrans[0]
        self.monitor = dict(m)
        self.width, self.height = m["width"], m["height"]
        self.left, self.top = m["left"], m["top"]

    def grab(self, mask: tuple | None = None) -> tuple[str, int, int]:
        """(png_b64, largeur, hauteur) de l'image envoyée. `mask` : cadre de la
        fenêtre PapAI à effacer si Windows n'a pas pu l'exclure de la capture."""
        from PIL import Image, ImageDraw

        with self._mss.mss() as sct:
            brut = sct.grab(self.monitor)
        img = Image.frombytes("RGB", brut.size, brut.bgra, "raw", "BGRX")
        if mask is not None:
            x0, y0, x1, y1 = mask
            box = (max(0, x0 - self.left), max(0, y0 - self.top),
                   min(img.width, x1 - self.left), min(img.height, y1 - self.top))
            if box[2] > box[0] and box[3] > box[1]:
                ImageDraw.Draw(img).rectangle(box, fill=(238, 240, 238))
        if img.width > SEND_WIDTH:
            img = img.resize((SEND_WIDTH, max(1, round(img.height * SEND_WIDTH / img.width))),
                             Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return base64.b64encode(buf.getvalue()).decode(), img.width, img.height

    def to_pixels(self, x, y) -> tuple[int, int]:
        """[0, 1000] -> pixels de l'écran principal, comme le Mac."""
        def num(v) -> float:
            try:
                return float(v)
            except (TypeError, ValueError):
                return 0.0
        return (self.left + round(num(x) / 1000 * self.width),
                self.top + round(num(y) / 1000 * self.height))


# ------------------------------------------------------------- les actions

_ALIAS = {
    "return": "enter", "escape": "esc", "control": "ctrl", "option": "alt", "opt": "alt",
    "command": "cmd", "meta": "cmd", "super": "win", "windows": "win",
    "arrowleft": "left", "arrowright": "right", "arrowup": "up", "arrowdown": "down",
    "forwarddelete": "delete", "del": "delete", "plus": "+",
}


def parse_keys(spec: str) -> list[str]:
    """« cmd+space » -> touches pyautogui. Le modèle connaît surtout le Mac :
    cmd devient ctrl (même intention), et cmd+space, la recherche du Mac,
    devient la touche Windows, qui ouvre la recherche de Windows."""
    import pyautogui

    parts = [p.strip().lower() for p in str(spec or "").split("+")]
    if len(parts) > 1 and parts[-1] == "" and parts[-2] == "":
        parts = parts[:-2] + ["+"]
    parts = [_ALIAS.get(p, p) for p in parts if p]
    if not parts:
        raise UnknownKey(spec)
    if parts == ["cmd", "space"]:
        return ["win"]
    out = ["ctrl" if p == "cmd" else p for p in parts]
    for k in out:
        if k not in pyautogui.KEYBOARD_KEYS:
            raise UnknownKey(spec)
    return out


def _type_unicode(ch: str) -> None:
    """Un caractère, accents compris, par SendInput (KEYEVENTF_UNICODE).
    pyautogui.write ignore « é », « à », « ç » : inutilisable en français."""
    from ctypes import wintypes

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
                    ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]

    class MOUSEINPUT(ctypes.Structure):
        _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD),
                    ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD),
                    ("dwExtraInfo", ctypes.c_size_t)]

    class _U(ctypes.Union):
        _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT)]

    class INPUT(ctypes.Structure):
        _fields_ = [("type", wintypes.DWORD), ("u", _U)]

    unicode_, keyup = 0x0004, 0x0002
    data = ch.encode("utf-16-le")
    for i in range(0, len(data), 2):
        code = int.from_bytes(data[i:i + 2], "little")
        for flags in (unicode_, unicode_ | keyup):
            inp = INPUT(type=1)
            inp.u.ki = KEYBDINPUT(0, code, flags, 0, 0)
            ctypes.windll.user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))


def run_action(name: str, args: dict, screen: Screen, gate: StopGate,
               protected: tuple | None = None) -> str:
    """Joue une action. Le verrou est relu juste avant chaque geste."""
    gate = gate.pin()
    if gate.is_stopped:
        raise Stopped()
    import pyautogui

    pyautogui.FAILSAFE = False  # un clic légitime peut viser un coin (bouton Démarrer)
    pyautogui.PAUSE = 0.05

    def aim() -> tuple[int, int]:
        px, py = screen.to_pixels(args.get("x"), args.get("y"))
        if protected is not None:
            a, b, c, d = protected
            if a <= px <= c and b <= py <= d:
                raise ProtectedZone()
        return px, py

    if name in ("click", "double_click"):
        px, py = aim()
        pyautogui.moveTo(px, py)
        time.sleep(0.2)
        if gate.is_stopped:
            raise Stopped()
        pyautogui.click(px, py, clicks=2 if name == "double_click" else 1, interval=0.08)
        return f"{name} à ({px}, {py}) sur « {args.get('element') or ''} »"

    if name == "type_text":
        text = str(args.get("text") or "")
        for ch in text:
            if gate.is_stopped:
                raise Stopped()
            if ch == "\n":
                pyautogui.press("enter")
            elif WINDOWS:
                _type_unicode(ch)
            else:
                pyautogui.write(ch)
            time.sleep(0.025)
        return f"texte tapé : {text}"

    if name == "press_key":
        spec = str(args.get("keys") or "")
        keys = parse_keys(spec)
        if gate.is_stopped:
            raise Stopped()
        if len(keys) > 1:
            pyautogui.hotkey(*keys)
        else:
            pyautogui.press(keys[0])
        return f"touche : {spec}"

    if name == "scroll":
        px, py = aim()
        direction = str(args.get("direction") or "down").lower()
        if direction in ("left", "right"):
            pyautogui.hscroll(-5 if direction == "left" else 5, x=px, y=py)
        else:
            pyautogui.scroll(5 if direction == "up" else -5, x=px, y=py)
        return f"scroll {direction}"

    if name == "wait":
        for _ in range(20):
            if gate.is_stopped:
                raise Stopped()
            time.sleep(0.1)
        return "attente 2 s"

    return f"outil inconnu : {name}"


def describe_action(name: str, args: dict) -> str:
    """Une phrase simple, à la première personne, comme sur le Mac."""
    cible = str(args.get("element") or "").strip()
    if name == "click":
        return f"Je clique sur {cible}" if cible else "Je clique sur l'écran"
    if name == "double_click":
        return f"J'ouvre {cible}" if cible else "J'ouvre l'élément"
    if name == "type_text":
        t = str(args.get("text") or "").strip()
        return f"J'écris « {t} »" if t else "J'écris au clavier"
    if name == "press_key":
        k = str(args.get("keys") or "").strip().lower()
        if k in ("enter", "return"):
            return "Je valide avec la touche Entrée"
        if k in ("esc", "escape"):
            return "Je ferme avec la touche Échap"
        if k in ("cmd+space", "win", "windows"):
            return "J'ouvre la recherche de Windows"
        return f"J'appuie sur {k}" if k else "J'appuie sur une touche"
    if name == "scroll":
        return "Je fais défiler la page"
    if name == "wait":
        return "J'attends que l'ordinateur réponde…"
    return "Je regarde l'écran…"


# ---------------------------------------------------- fenêtre de PapAI


def exclude_from_capture(hwnd: int) -> bool:
    """Windows 10 2004+ : la fenêtre PapAI n'apparaît plus dans aucune capture,
    comme le filtre ScreenCaptureKit du Mac. False si Windows refuse."""
    if not WINDOWS or not hwnd:
        return False
    return bool(ctypes.windll.user32.SetWindowDisplayAffinity(hwnd, 0x11))


def window_rect(hwnd: int) -> tuple | None:
    """Cadre de la fenêtre PapAI en pixels écran, marge de 4 px comprise."""
    if not WINDOWS or not hwnd:
        return None
    from ctypes import wintypes

    u = ctypes.windll.user32
    if not u.IsWindowVisible(hwnd) or u.IsIconic(hwnd):
        return None
    r = wintypes.RECT()
    if not u.GetWindowRect(hwnd, ctypes.byref(r)):
        return None
    return (r.left - 4, r.top - 4, r.right + 4, r.bottom + 4)


# ------------------------------------------------------------ automatismes

KNOWN_FOLDERS = {
    "pictures": "{33E28130-4E1E-4676-835A-98395C3BC3BB}",
    "documents": "{FDD39AD0-238F-46AF-ADB4-6C85480369C7}",
    "downloads": "{374DE290-123F-4565-9164-39C4925E467B}",
    "desktop": "{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}",
    "videos": "{18989B1D-99B5-455B-841C-AB7C74E4DDFC}",
    "music": "{4BD8D571-6D19-48D3-BE97-422220080E43}",
}
_XDG = {"pictures": "Pictures", "documents": "Documents", "downloads": "Downloads",
        "desktop": "Desktop", "videos": "Videos", "music": "Music"}


def known_folder(name: str) -> Path | None:
    """Où Windows range vraiment ce dossier (suit les redirections OneDrive).
    Jamais de chemin écrit en dur."""
    key = (name or "").strip().lower()
    if key not in KNOWN_FOLDERS:
        return None
    if not WINDOWS:
        return Path.home() / _XDG[key]
    from ctypes import wintypes

    class GUID(ctypes.Structure):
        _fields_ = [("a", wintypes.DWORD), ("b", wintypes.WORD),
                    ("c", wintypes.WORD), ("d", ctypes.c_ubyte * 8)]

    g = GUID()
    if ctypes.windll.ole32.CLSIDFromString(KNOWN_FOLDERS[key], ctypes.byref(g)) != 0:
        return None
    out = ctypes.c_wchar_p()
    if ctypes.windll.shell32.SHGetKnownFolderPath(ctypes.byref(g), 0, None, ctypes.byref(out)) != 0:
        return None
    try:
        return Path(out.value)
    finally:
        ctypes.windll.ole32.CoTaskMemFree(out)


def open_shortcut(shortcut: dict | None) -> tuple[bool, str]:
    """Ouvre le dossier d'un automatisme. Le modèle ne fournit jamais de chemin :
    un dossier connu du système et au plus un nom de sous-dossier. Si le dossier
    n'existe plus, on n'invente rien."""
    sc = shortcut or {}
    base = known_folder(str(sc.get("folder") or ""))
    if base is None:
        return False, "Aucun raccourci enregistré."
    sub = str(sc.get("subfolder") or "").strip()
    target = base
    if sub:
        if any(c in sub for c in '\\/:*?"<>|') or ".." in sub or sub == ".":
            return False, "Nom de dossier invalide."
        target = base / sub
    if not target.is_dir():
        quoi = f"« {sub} »" if sub else "Ce dossier"
        return False, f"{quoi} n'existe pas (ou plus) sur cet ordinateur."
    try:
        if WINDOWS:
            os.startfile(str(target))  # noqa: S606 — un dossier, dans l'Explorateur
        else:
            import subprocess

            subprocess.Popen(["xdg-open", str(target)])  # noqa: S603,S607
    except OSError as e:
        return False, str(e)
    return True, str(target)


# ------------------------------------------------------------- le gardien


def guard_signals() -> dict | None:
    """Les trois signaux textuels du gardien anti-arnaque (PROTOCOL.md) :
    processus, titre de la fenêtre active, URL. Jamais l'écran.
    L'URL du navigateur n'a pas d'équivalent simple sous Windows : vide."""
    if sys.platform != "win32":
        return None
    import subprocess

    buf = ctypes.create_unicode_buffer(512)
    user32 = ctypes.windll.user32
    user32.GetWindowTextW(user32.GetForegroundWindow(), buf, 512)
    try:
        out = subprocess.run(["tasklist", "/fo", "csv", "/nh"], capture_output=True, text=True,
                             timeout=5, creationflags=0x08000000).stdout  # sans console
    except (OSError, subprocess.SubprocessError):
        out = ""
    names = sorted({line.split('","')[0].strip('"').removesuffix(".exe")
                    for line in out.splitlines() if line.startswith('"')})
    return {"type": "guard", "processes": names, "window": buf.value, "url": ""}


# ------------------------------------------------- automatismes importés
#
# Un automatisme fourni par un support (service IT, proche) ne contient que
# des actions de premier niveau, connues ici. Jamais de commande, de script
# ni de chemin libre : le serveur les a vérifiées à l'import, on revérifie.

SETTINGS_PAGES = {
    "printers": "ms-settings:printers",
    "default_apps": "ms-settings:defaultapps",
    "updates": "ms-settings:windowsupdate",
    "antivirus": "windowsdefender:",
    "wifi": "ms-settings:network-wifi",
    "bluetooth": "ms-settings:bluetooth",
    "sound": "ms-settings:sound",
    "display": "ms-settings:display",
}
TEMPLATE_EXT = (".dotx", ".potx", ".xltx")
SCAN_TIMEOUT_S = 30 * 60


def _start(target: str) -> None:
    if WINDOWS:
        os.startfile(target)  # noqa: S606 — une URI ou un dossier, jamais une commande
    else:
        import webbrowser
        webbrowser.open(target)


def open_settings(page: str) -> tuple[bool, str]:
    uri = SETTINGS_PAGES.get(str(page or "").strip().lower())
    if uri is None:
        return False, f"Page de Réglages inconnue : {page}"
    try:
        _start(uri)
    except OSError as e:
        return False, str(e)
    return True, uri


def open_https(url: str) -> tuple[bool, str]:
    from urllib.parse import urlsplit
    u = urlsplit(str(url or ""))
    if u.scheme != "https" or not u.hostname or u.username or u.password:
        return False, "Lien refusé : seulement https://."
    try:
        _start(u.geturl())
    except OSError as e:
        return False, str(e)
    return True, u.geturl()


def templates_dir() -> Path:
    """Le dossier « Modèles personnels » de Word (%APPDATA%\\Microsoft\\Templates)."""
    if WINDOWS and os.environ.get("APPDATA"):
        return Path(os.environ["APPDATA"]) / "Microsoft" / "Templates"
    return Path.home() / ".papai" / "Templates"


def template_name_ok(name: str) -> bool:
    n = str(name or "")
    return (bool(n) and not any(c in n for c in '\\/:*?"<>|') and ".." not in n
            and not n.startswith(".") and n.lower().endswith(TEMPLATE_EXT))


def install_templates(files: list[tuple[str, bytes]], dest: Path | None = None) -> tuple[bool, str]:
    dest = dest or templates_dir()
    for name, data in files:
        if not template_name_ok(name) or not data.startswith(b"PK"):
            return False, f"Modèle refusé : {name}"
    try:
        dest.mkdir(parents=True, exist_ok=True)
        for name, data in files:
            target = dest / name
            if target.is_file() and target.read_bytes() != data:
                # Jamais rien de perdu : l'ancien modèle est gardé à côté.
                stem, ext = os.path.splitext(name)
                target.replace(dest / f"{stem} (avant PapAI {time.strftime('%Y-%m-%d %H%M%S')}){ext}")
            target.write_bytes(data)
    except OSError as e:
        return False, str(e)
    n = len(files)
    return True, f"{n} modèle{'s' if n > 1 else ''} ajouté{'s' if n > 1 else ''} dans Word."


def defender_exe() -> Path | None:
    base = os.environ.get("ProgramFiles") or r"C:\Program Files"
    exe = Path(base) / "Windows Defender" / "MpCmdRun.exe"
    return exe if WINDOWS and exe.is_file() else None


def antivirus_scan(gate: "StopGate | None" = None) -> tuple[bool, str]:
    """Scan rapide Microsoft Defender : exécutable fixe, arguments fixes, sans shell.
    Code 0 : rien trouvé. Code 2 : une menace a été trouvée, le support est prévenu."""
    exe = defender_exe()
    if exe is None:
        return False, "Microsoft Defender est introuvable sur cet ordinateur."
    import subprocess
    p = subprocess.Popen([str(exe), "-Scan", "-ScanType", "1"],  # noqa: S603
                         shell=False, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    t0 = time.monotonic()
    while p.poll() is None:
        if (gate is not None and gate.is_stopped) or time.monotonic() - t0 > SCAN_TIMEOUT_S:
            p.terminate()
            return False, "Scan interrompu."
        time.sleep(0.5)
    if p.returncode == 0:
        return True, "Scan antivirus terminé : rien à signaler."
    if p.returncode == 2:
        return False, "Le scan antivirus a trouvé une menace."
    return False, f"Le scan antivirus n'a pas abouti (code {p.returncode})."


def play_actions(lesson: dict, fetch: Callable[[str], bytes], gate: "StopGate") -> tuple[bool, str]:
    """Joue, dans l'ordre, les actions locales d'un automatisme importé.
    L'action `holo` (s'il y en a une) est confiée ensuite au serveur."""
    detail = ""
    for a in lesson.get("actions") or []:
        if gate.is_stopped:
            return False, "Arrêté."
        do = str(a.get("do") or "")
        if do == "open_folder":
            ok, detail = open_shortcut({"folder": a.get("folder"), "subfolder": a.get("subfolder")})
        elif do == "open_settings":
            ok, detail = open_settings(a.get("page"))
        elif do == "open_url":
            ok, detail = open_https(a.get("url"))
        elif do == "install_templates":
            try:
                files = [(n, fetch(n)) for n in a.get("files") or [] if template_name_ok(n)]
            except Exception as e:  # noqa: BLE001 — serveur injoignable
                return False, f"Modèles introuvables : {e}"
            ok, detail = install_templates(files) if files else (False, "Aucun modèle valable.")
        elif do == "antivirus_scan":
            ok, detail = antivirus_scan(gate)
        elif do == "holo":
            continue
        else:
            return False, f"Action inconnue : {do}"
        if not ok:
            return False, detail
    return True, detail
