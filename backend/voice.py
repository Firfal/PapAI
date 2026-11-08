"""Transcription Gladia v2, pré-enregistrée et relais direct, en français.

L'audio part pour être transcrit puis il est oublié : rien n'est écrit sur le
disque, rien n'est gardé en mémoire au-delà de l'appel. La clé Gladia reste ici.
"""

from __future__ import annotations

import json
import asyncio
import os
import time
import urllib.error
import urllib.request
import uuid
from urllib.parse import urlparse

import websockets
from starlette.websockets import WebSocket, WebSocketDisconnect

UPLOAD = "https://api.gladia.io/v2/upload"
TRANSCRIBE = "https://api.gladia.io/v2/pre-recorded"
LANGUE = "fr"
LIVE = "https://api.gladia.io/v2/live"
LIVE_SECONDS = 45
LIVE_DRAIN_SECONDS = 5
LIVE_IDLE_SECONDS = 8
LIVE_MAX_AUDIO = 1_024_000  # 32 secondes de PCM 16 kHz, mono, 16 bits.
_live_connections = 0


def _live_url_ok(url: str) -> bool:
    parsed = urlparse(url)
    return (parsed.scheme == "wss" and parsed.username is None
            and (parsed.hostname == "api.gladia.io"
                 or (parsed.hostname or "").endswith(".gladia.io")))


async def relay_live(client: WebSocket) -> None:
    """Relais borné : aucun jeton Gladia, audio ou diagnostic fournisseur renvoyé."""
    global _live_connections
    await client.accept()
    if not configured() or _live_connections >= 2:
        await client.send_json({"type": "fallback"})
        await client.close()
        return
    _live_connections += 1
    tasks: list[asyncio.Task] = []
    try:
        async with asyncio.timeout(LIVE_SECONDS):
            config = {
                "encoding": "wav/pcm", "sample_rate": 16000, "bit_depth": 16,
                "channels": 1,
                "language_config": {"languages": [LANGUE], "code_switching": False},
                "messages_config": {"receive_partial_transcripts": True,
                                    "receive_final_transcripts": True},
            }
            session = await asyncio.to_thread(_post, LIVE, json.dumps(config).encode(), {
                "x-gladia-key": os.environ["GLADIA_API_KEY"].strip(),
                "Content-Type": "application/json",
            }, 4)
            url = session.get("url", "")
            if not isinstance(url, str) or not _live_url_ok(url):
                raise ValueError("live_url")
            async with websockets.connect(url, open_timeout=4, close_timeout=1,
                                          max_size=128_000, max_queue=8) as upstream:
                await client.send_json({"type": "ready"})

                async def send_audio() -> None:
                    total = 0
                    while True:
                        message = await client.receive()
                        if message["type"] == "websocket.disconnect":
                            raise WebSocketDisconnect()
                        audio = message.get("bytes")
                        if audio is not None:
                            total += len(audio)
                            if not audio or len(audio) > 32_000 or len(audio) % 2 or total > LIVE_MAX_AUDIO:
                                raise ValueError("audio_limit")
                            await upstream.send(audio)
                        else:
                            control = message.get("text", "")
                            if len(control) > 128 or json.loads(control) != {"type": "stop"}:
                                raise ValueError("control")
                            await upstream.send(json.dumps({"type": "stop_recording"}))
                            return

                async def receive_text() -> None:
                    while True:
                        raw = await asyncio.wait_for(upstream.recv(), LIVE_IDLE_SECONDS)
                        event = json.loads(raw)
                        kind = event.get("type")
                        if kind == "transcript":
                            data = event["data"]
                            text = data["utterance"]["text"]
                            ident = data["id"]
                            if not isinstance(text, str) or len(text) > 20_000 or not isinstance(ident, str) or len(ident) > 128:
                                raise ValueError("transcript")
                            await client.send_json({"type": "transcript", "id": ident,
                                                    "text": text, "final": data["is_final"] is True})
                        elif kind == "end_session":
                            await client.send_json({"type": "done"})
                            return
                        elif kind == "error":
                            raise ValueError("upstream_error")

                sender = asyncio.create_task(send_audio())
                receiver = asyncio.create_task(receive_text())
                tasks = [sender, receiver]
                done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
                for task in done:
                    task.result()
                if sender in done:
                    await asyncio.wait_for(receiver, LIVE_DRAIN_SECONDS)
                else:
                    sender.cancel()
    except WebSocketDisconnect:
        pass
    except Exception:  # noqa: BLE001 — ne pas exposer l'URL signée ni les erreurs Gladia.
        try:
            await client.send_json({"type": "fallback"})
        except Exception:  # noqa: BLE001
            pass
    finally:
        _live_connections -= 1
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        try:
            await client.close()
        except Exception:  # noqa: BLE001
            pass


def configured() -> bool:
    return bool(os.environ.get("GLADIA_API_KEY", "").strip())


def _post(url: str, body: bytes, headers: dict, timeout: int = 30) -> dict:
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def _get(url: str, key: str, timeout: int = 15) -> dict:
    req = urllib.request.Request(url, headers={"x-gladia-key": key})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def transcribe(audio: bytes, filename: str = "demande.wav",
               content_type: str = "audio/wav") -> tuple[bool, str]:
    """Rend (ok, texte) ou (False, message lisible par la personne aidée). Bloquant."""
    key = os.environ.get("GLADIA_API_KEY", "").strip()
    if not key:
        return False, "gladia_absent"
    if not audio:
        return False, "Je n'ai rien entendu."

    frontiere = uuid.uuid4().hex
    corps = (
        f"--{frontiere}\r\n"
        f'Content-Disposition: form-data; name="audio"; filename="{filename}"\r\n'
        f"Content-Type: {content_type}\r\n\r\n"
    ).encode() + audio + f"\r\n--{frontiere}--\r\n".encode()

    try:
        envoi = _post(UPLOAD, corps, {
            "x-gladia-key": key,
            "Content-Type": f"multipart/form-data; boundary={frontiere}",
        }, timeout=45)
        url_audio = envoi.get("audio_url")
        if not url_audio:
            return False, "Le service de transcription n'a pas accepté l'enregistrement."
        lance = _post(
            TRANSCRIBE,
            json.dumps({"audio_url": url_audio, "language": LANGUE}).encode(),
            {"x-gladia-key": key, "Content-Type": "application/json"},
        )
        suivi = lance.get("result_url")
        if not suivi:
            return False, "La transcription n'a pas démarré."
        for _ in range(25):
            time.sleep(0.7)
            etat = _get(suivi, key)
            statut = etat.get("status")
            if statut == "done":
                texte = (etat.get("result", {}).get("transcription", {})
                         .get("full_transcript", "")).strip()
                if not texte:
                    return False, "Je n'ai pas compris. Pouvez-vous répéter ?"
                return True, texte
            if statut == "error":
                return False, "La transcription a échoué."
        return False, "La transcription est trop longue."
    except urllib.error.HTTPError as e:
        print(f"[voix] Gladia : erreur {e.code}", flush=True)
        return False, "Le service de transcription n'a pas répondu."
    except Exception as e:  # noqa: BLE001
        print(f"[voix] {type(e).__name__}", flush=True)
        return False, "Le service de transcription n'a pas répondu."
