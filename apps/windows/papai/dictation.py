"""WAV mono, fin automatique après silence, puis Gladia. Aucun son à vide envoyé."""

from __future__ import annotations

import io
import json
import math
import queue
import struct
import sys
import threading
import time
import urllib.request
import wave
from concurrent.futures import ThreadPoolExecutor
from typing import Callable

LIMIT_S = 30
RATE = 16000


class SilenceDetector:
    def __init__(self):
        self.elapsed = 0.0
        self.quiet = 0.0
        self.voice = 0.0
        self.noise = 100.0

    def feed(self, rms: float, seconds: float) -> bool:
        self.elapsed += seconds
        if rms > max(250, self.noise * 3):
            self.voice += seconds
            self.quiet = 0
        else:
            self.quiet += seconds
            self.noise = self.noise * .95 + min(rms, 250) * .05
        return (self.voice >= .2 and self.quiet >= 1.8) or (self.voice < .2 and self.elapsed >= 8) or self.elapsed >= LIMIT_S


def rms_pcm(audio: bytes) -> float:
    samples = [s[0] for s in struct.iter_unpack('<h', audio)]
    return math.sqrt(sum(s * s for s in samples) / len(samples)) if samples else 0


class Dictation:
    def __init__(self, on_phase: Callable[[str, str | None], None],
                 on_text: Callable[[str], None]) -> None:
        self.on_phase = on_phase
        self.on_text = on_text
        self.phase = "idle"
        self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="papai-dictee")
        self._lock = threading.RLock()
        self._stop = threading.Event()
        self._cancel = threading.Event()
        self.run_id = 0

    def _set(self, phase: str, message: str | None = None) -> None:
        with self._lock:
            self.phase = phase
            self.on_phase(phase, message)

    def toggle(self, http_base: str) -> None:
        with self._lock:
            if self.phase == "idle":
                self.run_id += 1
                self._stop.clear()
                self._cancel.clear()
                self._set("starting")
                self._pool.submit(self._record, http_base)
            elif self.phase == "listening":
                self._stop.set()

    def cancel(self) -> None:
        with self._lock:
            self._cancel.set()
            self._stop.set()

    def close(self) -> None:
        self.cancel()
        self._pool.shutdown(wait=False, cancel_futures=True)

    def _record(self, http_base: str) -> None:
        try:
            if sys.platform != "win32":
                raise RuntimeError("Windows requis")
            import sounddevice as sd

            chunks: queue.Queue = queue.Queue(maxsize=320)

            def receive(data, frames, timing, status):
                try:
                    chunks.put_nowait((bytes(data), bool(status)))
                except queue.Full:
                    self._cancel.set()

            detector = SilenceDetector()
            audio = bytearray()
            with sd.RawInputStream(samplerate=RATE, blocksize=1600, channels=1,
                                   dtype='int16', callback=receive):
                self._set("listening")
                deadline = time.monotonic() + LIMIT_S
                while not self._stop.is_set() and not self._cancel.is_set():
                    if time.monotonic() >= deadline:
                        break
                    try:
                        data, overflow = chunks.get(timeout=.25)
                    except queue.Empty:
                        continue
                    if overflow:
                        raise RuntimeError("Entrée audio interrompue")
                    audio.extend(data)
                    if detector.feed(rms_pcm(data), len(data) / (RATE * 2)):
                        break
            if self._cancel.is_set():
                self._set("idle", "La dictée est interrompue. Écrivez votre demande.")
                return
            if detector.voice < .2:
                self._set("idle", "Je n'ai rien entendu. Touchez le micro et parlez, ou écrivez.")
                return
            self._set("transcribing")
            buf = io.BytesIO()
            with wave.open(buf, 'wb') as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(RATE)
                wav.writeframes(bytes(audio))
            text = self._transcribe(http_base, buf.getvalue())
            with self._lock:
                if text and not self._cancel.is_set():
                    self._set("idle")
                    self.on_text(text)
                else:
                    self._set("idle", "Je n'ai pas compris. Touchez le micro et redites-le, ou écrivez.")
        except Exception:  # noqa: BLE001 — permission refusée, micro retiré ou service indisponible
            self._set("idle", "Je n'ai pas accès au micro. Vérifiez qu'il est branché et autorisé, ou écrivez.")

    def _transcribe(self, http_base: str, audio: bytes) -> str | None:
        try:
            req = urllib.request.Request(http_base + "/transcribe", data=audio, method="POST",
                                         headers={"Content-Type": "audio/wav"})
            with urllib.request.urlopen(req, timeout=25) as r:  # noqa: S310
                if r.status != 200:
                    return None
                text = json.loads(r.read().decode()).get("text")
        except Exception:  # noqa: BLE001
            return None
        return str(text).strip() if text else None
