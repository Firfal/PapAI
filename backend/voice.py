"""Transcription de la demande, par Gladia (v2, pré-enregistré, français).

L'audio part pour être transcrit puis il est oublié : rien n'est écrit sur le
disque, rien n'est gardé en mémoire au-delà de l'appel. La clé Gladia reste ici.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
import uuid

UPLOAD = "https://api.gladia.io/v2/upload"
TRANSCRIBE = "https://api.gladia.io/v2/pre-recorded"
LANGUE = "fr"


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
