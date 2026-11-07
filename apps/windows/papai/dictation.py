"""Dictée de la demande, port de `apps/mac/Sources/Dictation.swift`.

L'app enregistre (wav 16 kHz mono, par le MCI de Windows : aucune dépendance),
le serveur transcrit avec Gladia (`POST {httpBase}/transcribe`). Le Mac a un
secours sur l'appareil ; ici, sans réponse du serveur, on invite à écrire.
"""

from __future__ import annotations

import ctypes
import json
import os
import sys
import tempfile
import threading
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Callable

LIMIT_S = 30


class Dictation:
    def __init__(self, on_phase: Callable[[str, str | None], None],
                 on_text: Callable[[str], None]) -> None:
        self.on_phase = on_phase
        self.on_text = on_text
        self.phase = "idle"
        self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="papai-mci")
        self._file = Path(tempfile.gettempdir()) / "papai-dictee.wav"
        self._base = ""
        self._limit: threading.Timer | None = None

    def _set(self, phase: str, message: str | None = None) -> None:
        self.phase = phase
        self.on_phase(phase, message)

    @staticmethod
    def _mci(cmd: str) -> int:
        return ctypes.windll.winmm.mciSendStringW(cmd, None, 0, None)

    def toggle(self, http_base: str) -> None:
        if self.phase == "idle":
            self._pool.submit(self._start, http_base)
        elif self.phase == "listening":
            self._pool.submit(self._stop)

    def _start(self, http_base: str) -> None:
        if sys.platform != "win32":
            self._set("idle", "La dictée n'est pas disponible sur cet ordinateur. Écrivez votre demande.")
            return
        self._base = http_base
        self._mci("close papai_rec")
        cmds = ("open new type waveaudio alias papai_rec",
                "set papai_rec bitspersample 16 channels 1 samplespersec 16000 "
                "bytespersec 32000 alignment 2",
                "record papai_rec")
        for c in cmds:
            if self._mci(c) != 0:
                self._mci("close papai_rec")
                self._set("idle", "Je n'ai pas accès au micro. Vérifiez qu'il est branché et autorisé "
                                  "dans Paramètres, Confidentialité, Microphone.")
                return
        self._set("listening")
        self._limit = threading.Timer(LIMIT_S, lambda: self._pool.submit(self._stop))
        self._limit.daemon = True
        self._limit.start()

    def _stop(self) -> None:
        if self.phase != "listening":
            return
        if self._limit is not None:
            self._limit.cancel()
        self._mci("stop papai_rec")
        self._mci(f'save papai_rec "{self._file}"')
        self._mci("close papai_rec")
        self._set("transcribing")
        text = self._transcribe()
        try:
            os.remove(self._file)
        except OSError:
            pass
        if text:
            self._set("idle")
            self.on_text(text)
        else:
            self._set("idle", "Je n'ai pas compris. Touchez le micro et redites-le, ou écrivez.")

    def _transcribe(self) -> str | None:
        try:
            audio = self._file.read_bytes()
            req = urllib.request.Request(self._base + "/transcribe", data=audio, method="POST",
                                         headers={"Content-Type": "audio/wav"})
            with urllib.request.urlopen(req, timeout=25) as r:  # noqa: S310
                if r.status != 200:
                    return None
                text = json.loads(r.read().decode()).get("text")
        except Exception:  # noqa: BLE001
            return None
        return str(text).strip() if text else None
