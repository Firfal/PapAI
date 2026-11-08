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
import subprocess
import sys
import threading
import time
import unicodedata
from pathlib import Path

from . import apps

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


class SensitiveTarget(Exception):
    pass


SENSITIVE_PROCESSES = frozenset({
    "consent", "credentialuibroker", "systemsettings", "logonui", "sechealthui",
    "useraccountcontrolsettings", "1password", "bitwarden", "dashlane", "lastpass",
    "keepass", "keepassxc", "enpass", "keeper", "nordpass", "roboform",
})


def process_name(name: str | None) -> str:
    return str(name or "").replace("\\", "/").rsplit("/", 1)[-1].lower().removesuffix(".exe")


def pointer_verdict(pid: int, name: str | None, own_pid: int | None = None) -> str | None:
    if pid == (os.getpid() if own_pid is None else own_pid):
        return "PapAI ne peut pas se manipuler elle-même"
    if not pid or not process_name(name):
        return "l’application visée ne peut pas être vérifiée"
    if process_name(name) in SENSITIVE_PROCESSES:
        return "cette application contient des réglages ou des informations sensibles"
    return None


def keyboard_verdict(pid: int, name: str | None, own_pid: int | None = None) -> str | None:
    return pointer_verdict(pid, name, own_pid)


class Win32Targets:
    def __init__(self):
        from ctypes import wintypes as w

        self.user = ctypes.WinDLL("user32", use_last_error=True)
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self.callback = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
        signatures = [
            (self.user.WindowFromPoint, [w.POINT], w.HWND),
            (self.user.GetAncestor, [w.HWND, w.UINT], w.HWND),
            (self.user.GetWindowThreadProcessId, [w.HWND, ctypes.POINTER(w.DWORD)], w.DWORD),
            (self.user.GetForegroundWindow, [], w.HWND),
            (self.user.SetForegroundWindow, [w.HWND], w.BOOL),
            (self.user.GetWindow, [w.HWND, w.UINT], w.HWND),
            (self.user.IsWindowVisible, [w.HWND], w.BOOL),
            (self.user.GetClassNameW, [w.HWND, w.LPWSTR, ctypes.c_int], ctypes.c_int),
            (self.user.EnumChildWindows, [w.HWND, self.callback, w.LPARAM], w.BOOL),
            (self.kernel.OpenProcess, [w.DWORD, w.BOOL, w.DWORD], w.HANDLE),
            (self.kernel.QueryFullProcessImageNameW,
             [w.HANDLE, w.DWORD, w.LPWSTR, ctypes.POINTER(w.DWORD)], w.BOOL),
            (self.kernel.CloseHandle, [w.HANDLE], w.BOOL),
        ]
        for function, args, result in signatures:
            function.argtypes, function.restype = args, result

    def root(self, hwnd):
        return self.user.GetAncestor(hwnd, 2) or hwnd

    def at_point(self, x, y):
        from ctypes.wintypes import POINT
        return self.root(self.user.WindowFromPoint(POINT(x, y)))

    def foreground(self):
        return self.root(self.user.GetForegroundWindow())

    def identity(self, hwnd):
        from ctypes.wintypes import DWORD
        pid = DWORD()
        self.user.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        handle = self.kernel.OpenProcess(0x1000, False, pid.value)
        if not handle:
            return pid.value, None
        try:
            size = DWORD(32768)
            name = ctypes.create_unicode_buffer(size.value)
            if self.kernel.QueryFullProcessImageNameW(handle, 0, name, ctypes.byref(size)):
                return pid.value, name.value
            return pid.value, None
        finally:
            self.kernel.CloseHandle(handle)

    def children(self, hwnd):
        children = []

        @self.callback
        def collect(child, _):
            name = ctypes.create_unicode_buffer(256)
            self.user.GetClassNameW(child, name, len(name))
            if name.value == "Windows.UI.Core.CoreWindow":
                children.append(child)
            return True

        self.user.EnumChildWindows(hwnd, collect, 0)
        return children

    def next_visible(self, hwnd):
        seen = set()
        while hwnd and hwnd not in seen:
            seen.add(hwnd)
            hwnd = self.user.GetWindow(hwnd, 2)
            if hwnd and self.user.IsWindowVisible(hwnd):
                yield hwnd

    def activate(self, hwnd):
        self.user.SetForegroundWindow(hwnd)


class DesktopSafety:
    def __init__(self, api=None, own_pid=None, sleep=time.sleep):
        self.api = api
        self.own_pid = os.getpid() if own_pid is None else own_pid
        self.sleep = sleep
        self.previous = None

    def window_reason(self, hwnd):
        pid, name = self.api.identity(hwnd)
        reason = pointer_verdict(pid, name, self.own_pid)
        if reason:
            return reason
        if process_name(name) == "applicationframehost":
            children = self.api.children(hwnd)
            if not children:
                return "l’application hébergée ne peut pas être vérifiée"
            for child in children:
                child_pid, child_name = self.api.identity(child)
                if process_name(child_name) == "applicationframehost":
                    return "l’application hébergée ne peut pas être vérifiée"
                reason = pointer_verdict(child_pid, child_name, self.own_pid)
                if reason:
                    return reason
        return None

    def remember_foreground(self):
        hwnd = self.api.foreground()
        pid, _ = self.api.identity(hwnd)
        if hwnd and pid and pid != self.own_pid:
            self.previous = hwnd

    def check_pointer(self, x, y):
        if self.api is None:
            return
        self.remember_foreground()
        reason = self.window_reason(self.api.at_point(x, y))
        if reason:
            raise SensitiveTarget(reason)

    def check_keyboard(self):
        if self.api is None:
            return
        self.remember_foreground()
        reason = self.window_reason(self.api.foreground())
        if reason:
            raise SensitiveTarget(reason)

    def prepare_keyboard(self):
        if self.api is None:
            return
        hwnd = self.api.foreground()
        pid, _ = self.api.identity(hwnd)
        if pid == self.own_pid:
            candidates = ([self.previous] if self.previous else [])
            candidates.extend(self.api.next_visible(hwnd))
            for candidate in candidates:
                candidate_pid, name = self.api.identity(candidate)
                if candidate_pid and candidate_pid != self.own_pid and name:
                    self.api.activate(candidate)
                    self.sleep(0.2)
                    break
        self.check_keyboard()


desktop_safety = DesktopSafety(Win32Targets() if WINDOWS else None)


if WINDOWS:
    def _watch_foreground():
        while True:
            desktop_safety.remember_foreground()
            time.sleep(0.1)

    threading.Thread(target=_watch_foreground, daemon=True, name="papai-focus").start()


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
               protected: tuple | None = None, safety=None) -> str:
    """Joue une action. Le verrou est relu juste avant chaque geste."""
    gate = gate.pin()
    safety = desktop_safety if safety is None else safety
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
        safety.check_pointer(px, py)
        return px, py

    if name in ("click", "double_click"):
        px, py = aim()
        pyautogui.moveTo(px, py)
        time.sleep(0.2)
        if gate.is_stopped:
            raise Stopped()
        safety.check_pointer(px, py)
        pyautogui.click(px, py, clicks=2 if name == "double_click" else 1, interval=0.08)
        return f"{name} à ({px}, {py}) sur « {args.get('element') or ''} »"

    if name == "type_text":
        safety.prepare_keyboard()
        text = str(args.get("text") or "")
        for ch in text:
            if gate.is_stopped:
                raise Stopped()
            safety.check_keyboard()
            if ch == "\n":
                pyautogui.press("enter")
            elif WINDOWS:
                _type_unicode(ch)
            else:
                pyautogui.write(ch)
            time.sleep(0.025)
        return f"texte tapé : {text}"

    if name == "press_key":
        safety.prepare_keyboard()
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


def valid_subfolder(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    sub = value.strip()
    if len(sub) > 100 or any(
        unicodedata.category(c) not in {"Lu", "Ll", "Lt", "Lm", "Lo", "Nd"}
        and c not in " -_'’(),&+" for c in sub
    ):
        return None
    return sub


def open_shortcut(shortcut: dict | None) -> tuple[bool, str]:
    """Ouvre le dossier d'un automatisme. Le modèle ne fournit jamais de chemin :
    un dossier connu du système et au plus un nom de sous-dossier. Si le dossier
    n'existe plus, on n'invente rien."""
    sc = shortcut or {}
    base = known_folder(str(sc.get("folder") or ""))
    if base is None:
        return False, "Aucun raccourci enregistré."
    sub = valid_subfolder(sc.get("subfolder", ""))
    if sub is None:
        return False, "Nom de dossier invalide."
    from .home_shortcuts import valid_folder

    target = valid_folder(base / sub if sub else base, reject_links=True)
    if target is None or not target.is_relative_to(base.resolve()):
        return False, "Ce dossier n'est pas disponible ou ne peut pas être ouvert en toute sécurité."
    try:
        if WINDOWS:
            subprocess.Popen([str(apps.windows_directory() / "explorer.exe"), str(target)], shell=False)
        else:
            return False, "L'Explorateur Windows n'est pas disponible."
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
