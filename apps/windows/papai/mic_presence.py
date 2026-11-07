"""Présence d'une entrée audio, relue à chaud (sans ouvrir le micro)."""

from __future__ import annotations

import ctypes
import os
import sys
import threading
from typing import Callable


def microphone_present() -> bool:
    if os.environ.get("PAPAI_NOMIC") == "1":
        return False
    if os.environ.get("PAPAI_DEMO"):
        return os.environ.get("PAPAI_DEMO_MIC") == "1"
    if sys.platform != "win32":
        return False
    try:
        # WinMM réénumère les périphériques à chaque appel, y compris après USB.
        return ctypes.windll.winmm.waveInGetNumDevs() > 0
    except (OSError, AttributeError):
        return False


class MicPresence:
    def __init__(self, on_change: Callable[[bool], None], probe=microphone_present):
        self._probe = probe
        self._change = on_change
        self.present = bool(probe())
        self._closed = threading.Event()

    def refresh(self) -> bool:
        present = bool(self._probe())
        if present != self.present:
            self.present = present
            self._change(present)
        return present

    def start(self) -> None:
        threading.Thread(target=self._watch, daemon=True, name="papai-micro").start()

    def _watch(self) -> None:
        while not self._closed.wait(2):
            self.refresh()

    def close(self) -> None:
        self._closed.set()
