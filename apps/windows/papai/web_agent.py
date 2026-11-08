"""Agent navigateur de Holo sur Windows : portage de `WebAgentHost` (WebAgent.swift).

« Chrome PapAI » (Chrome, Brave ou Edge lancé avec un profil dédié) et
`holo local browser` : le navigateur que l'agent web de Holo pilote quand le
plan validé passe par un site. Profil neuf à chaque assistance, effacé après :
aucun compte, identifiant ni cookie n'est gardé. La clé de Holo reste dans
la configuration de holo, sa sortie ne va dans aucun journal.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
import uuid
from pathlib import Path
from typing import Callable

DEBUG_PORT = 9222
WINDOWS = sys.platform == "win32"
NO_WINDOW = 0x08000000 if WINDOWS else 0  # CREATE_NO_WINDOW


def support_dir() -> Path:
    base = os.environ.get("PAPAI_HOME") or os.environ.get("LOCALAPPDATA") or str(Path.home() / ".local" / "share")
    return Path(base) / "PapAI"


def profile_dir() -> Path:
    return support_dir() / "Chrome"


def holo_binary() -> Path:
    venv = support_dir() / "agent-navigateur" / "venv"
    return venv / ("Scripts/holo.exe" if WINDOWS else "bin/holo")


def browser_candidates() -> list[Path]:
    """Chrome d'abord, puis Brave et Edge, comme sur le Mac."""
    roots = [os.environ.get(k) for k in ("ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA")]
    rel = (r"Google\Chrome\Application\chrome.exe", r"BraveSoftware\Brave-Browser\Application\brave.exe",
           r"Microsoft\Edge\Application\msedge.exe")
    return [Path(r) / p for p in rel for r in roots if r]


def browser_executable() -> Path | None:
    return next((p for p in browser_candidates() if p.is_file()), None)


def debugger_listening(port: int = DEBUG_PORT) -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version", timeout=1) as r:  # noqa: S310
            return r.status == 200
    except Exception:  # noqa: BLE001
        return False


def wipe_profile(path: Path | None = None) -> None:
    shutil.rmtree(path or profile_dir(), ignore_errors=True)


def bring_pid_to_front(pid: int) -> None:
    """Met devant la fenêtre visible du navigateur lancé par PapAI."""
    if not WINDOWS:
        return
    try:
        import ctypes
        from ctypes import wintypes
        user32 = ctypes.windll.user32
        found: list[int] = []

        @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def each(hwnd, _):
            owner = wintypes.DWORD()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
            if owner.value == pid and user32.IsWindowVisible(hwnd) and user32.GetWindowTextLengthW(hwnd):
                found.append(hwnd)
                return False
            return True

        user32.EnumWindows(each, 0)
        if found:
            user32.ShowWindow(found[0], 9)  # SW_RESTORE
            user32.SetForegroundWindow(found[0])
    except Exception:  # noqa: BLE001
        pass


class WebAgentHost:
    """Lance et arrête Chrome PapAI et holo. `on_change(session_id | None)` prévient le serveur."""

    def __init__(self, on_change: Callable[[str | None], None] = lambda _id: None, *,
                 popen: Callable = subprocess.Popen, listening: Callable[[], bool] = debugger_listening,
                 executable: Callable[[], Path | None] = browser_executable,
                 holo: Callable[[], Path] = holo_binary, profile: Callable[[], Path] = profile_dir,
                 sleep: Callable[[float], None] = time.sleep, front: Callable[[int], None] = bring_pid_to_front,
                 spawn: Callable[[Callable], None] | None = None) -> None:
        self.on_change = on_change
        self._popen, self._listening, self._executable = popen, listening, executable
        self._holo_path, self._profile, self._sleep, self._front = holo, profile, sleep, front
        self._spawn = spawn or (lambda fn: threading.Thread(target=fn, daemon=True).start())
        self._lock = threading.RLock()
        self._generation = 0
        self.starting = False
        self.chrome = None
        self.holo = None
        self.session_id: str | None = None

    # Annoncé au serveur seulement si holo et un navigateur sont là.
    def available(self) -> bool:
        try:
            return self._holo_path().is_file() and self._executable() is not None
        except OSError:
            return False

    def start(self) -> None:
        with self._lock:
            if self.starting or self.holo is not None or not self.available():
                return
            exe = self._executable()
            self.starting = True
            gen = self._generation
        self._spawn(lambda: self._launch(exe, gen))

    def _stale(self, gen: int) -> bool:
        with self._lock:
            return gen != self._generation

    def _abort(self, gen: int, chrome, holo) -> bool:
        if not self._stale(gen):
            return False
        for p in (holo, chrome):
            if p is not None and p.poll() is None:
                p.terminate()
        with self._lock:
            if holo is not None and self.holo is holo:
                self.holo = None
            if chrome is not None and self.chrome is chrome:
                self.chrome = None
        return True

    def _launch(self, exe: Path, gen: int) -> None:
        try:
            self._launch_inner(exe, gen)
        finally:
            with self._lock:
                self.starting = False

    def _launch_inner(self, exe: Path, gen: int) -> None:
        # Un navigateur écoute déjà sur ce port (pas le nôtre ou un reste d'avant) :
        # on ne s'y branche pas, pour ne jamais piloter un profil avec des comptes.
        if self._listening():
            return
        profile = self._profile()
        # Un reste de l'assistance d'avant (fichier encore verrouillé) : jamais réutilisé.
        for _ in range(10):
            wipe_profile(profile)
            if not profile.exists() or self._stale(gen):
                break
            self._sleep(0.5)
        if profile.exists() or self._stale(gen):
            return
        profile.mkdir(parents=True, exist_ok=True)
        try:
            chrome = self._popen([str(exe), f"--remote-debugging-port={DEBUG_PORT}", f"--user-data-dir={profile}",
                                  "--no-first-run", "--no-default-browser-check", "about:blank"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            return
        with self._lock:
            self.chrome = chrome
        for _ in range(60):
            listening = self._listening()
            if self._abort(gen, chrome, None):
                return
            if listening:
                break
            self._sleep(0.25)
        else:
            self.stop_local(notify_server=False)
            return
        sid = str(uuid.uuid4())
        try:
            holo = self._popen([str(self._holo_path()), "local", "browser", "--session-id", sid,
                                "--debug-port", str(DEBUG_PORT)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=NO_WINDOW)
        except OSError:
            self.stop_local(notify_server=False)
            return
        with self._lock:
            self.holo = holo
        self._sleep(1.5)
        if self._abort(gen, chrome, holo):
            return
        if holo.poll() is not None:
            # holo n'a pas tenu : le serveur repasse au bureau, Chrome PapAI ne reste pas ouvert.
            self.stop_local(notify_server=False)
            return
        with self._lock:
            self.session_id = sid
        self.on_change(sid)
        self._spawn(lambda: self._watch_holo(holo))

    def _watch_holo(self, holo) -> None:
        holo.wait()
        with self._lock:
            if self.holo is not holo:
                return
            self.holo = None
            sid, self.session_id = self.session_id, None
        if sid is not None:
            self.on_change(None)

    def stop_local(self, notify_server: bool = True) -> None:
        """Arrêter, fin d'assistance, alerte ou coupure : marche hors ligne, sans le serveur."""
        with self._lock:
            self._generation += 1
            if self.holo is None and self.session_id is None and self.chrome is None and not self.starting:
                return
            holo, chrome, sid = self.holo, self.chrome, self.session_id
            self.holo = self.chrome = self.session_id = None
        if sid is not None and notify_server:
            self.on_change(None)
        if holo is not None and holo.poll() is None:
            holo.terminate()
        holo_path = self._holo_path()
        if holo_path.is_file():
            try:
                self._popen([str(holo_path), "local", "stop"], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, creationflags=NO_WINDOW)
            except OSError:
                pass
        profile = self._profile()

        def finish() -> None:
            if chrome is not None:
                if chrome.poll() is None:
                    chrome.terminate()
                try:
                    chrome.wait(timeout=5)
                except Exception:  # noqa: BLE001
                    chrome.kill()
            if holo is not None:
                try:
                    holo.wait(timeout=2)
                except Exception:  # noqa: BLE001
                    holo.kill()
            # Chrome a lâché ses fichiers : le profil de l'assistance est effacé.
            for _ in range(10):
                wipe_profile(profile)
                if not profile.exists():
                    break
                self._sleep(0.5)

        self._spawn(finish)

    def bring_to_front(self) -> None:
        chrome = self.chrome
        if chrome is not None and chrome.poll() is None:
            self._front(chrome.pid)
