"""La fenêtre de la personne aidée, en vraie application.

Le rendu est confié à WebView2 : même langage visuel que la page du proche, des
textes qu'on peut vraiment agrandir, et des écrans qui ne ressemblent plus à un
outil de développement. La logique reste en Python — la vue ne décide de rien,
elle appelle `Api`.
"""

from __future__ import annotations

import base64
import ctypes
import io
import json
import queue
import threading
import time
import urllib.request
from ctypes import wintypes
from pathlib import Path

import webview

from . import shortcuts, voice

UI = Path(__file__).parent / "ui" / "index.html"
TITLE = "CarePilot"


def _qr(url: str, side: int = 320) -> str:
    try:
        import qrcode

        img = qrcode.make(url, box_size=4, border=2).convert("RGB").resize((side, side))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return base64.b64encode(buf.getvalue()).decode()
    except Exception:  # noqa: BLE001 — le lien en clair reste affiché
        return ""


class Api:
    """Tout ce que l'interface a le droit de demander. Rien de plus."""

    def __init__(self, bridge) -> None:
        self.b = bridge          # le module bridge, pour gate / send_soon / HTTP_BASE
        self._lessons: dict = {}

    # ------------------------------------------------------------ session

    def ask_help(self, task: str) -> dict:
        self.b.gate.reset()
        self.b.send_soon({"type": "help_request", "task": (task or "").strip()[:200]})
        call_js("live", (task or "").strip())
        return {"ok": True}

    def answer_invite(self, accepted: bool) -> dict:
        self.b.gate.reset()
        self.b.send_soon({"type": "invitation_response", "accepted": bool(accepted)})
        if accepted:
            call_js("live", "")
        else:
            call_js("home")
        return {"ok": True}

    def stop(self) -> dict:
        # Le verrou local d'abord : plus aucune action ne passera, même si le
        # réseau est coupé ou le serveur injoignable. Le serveur est prévenu
        # ensuite, par politesse.
        self.b.gate.raise_stop()
        self.b.send_soon({"type": "stop"})
        call_js("stopped")
        return {"ok": True}

    # --------------------------------------------------------------- voix

    def voice_ready(self) -> bool:
        return voice.configured()

    def transcribe(self, audio_b64: str) -> dict:
        """Reçoit l'enregistrement, rend le texte. L'audio n'est pas conservé."""
        try:
            audio = base64.b64decode((audio_b64 or "").split(",")[-1])
        except Exception:  # noqa: BLE001
            return {"ok": False, "text": "L'enregistrement est illisible."}
        ok, texte = voice.transcribe(audio)
        return {"ok": ok, "text": texte}

    # ------------------------------------------------------- accès rapide

    def quick_items(self) -> list:
        try:
            return shortcuts.frequent(8)
        except Exception as e:  # noqa: BLE001 — l'accueil doit rester utilisable
            print("[pont] raccourcis indisponibles : " + str(e), flush=True)
            return []

    def open_quick(self, item: dict) -> dict:
        ok, detail = shortcuts.launch(item)
        return {"ok": ok, "detail": detail}

    # ------------------------------------------------------------- fiches

    def lessons(self) -> list:
        """Les fiches validées, captures incluses pour un affichage immédiat."""
        try:
            with urllib.request.urlopen(f"{self.b.HTTP_BASE}/lessons", timeout=5) as r:
                data = json.loads(r.read().decode())
        except Exception as e:  # noqa: BLE001 — serveur absent : pas de fiches
            print("[pont] fiches indisponibles : " + str(e), flush=True)
            return []

        for l in data:
            for step in l.get("steps", []):
                step["image_data"] = self._image(l["id"], step.get("image", ""))
            self._lessons[l["id"]] = l
        return data

    def _image(self, lesson_id: str, name: str) -> str:
        if not name:
            return ""
        try:
            url = f"{self.b.HTTP_BASE}/lessons/{lesson_id}/{name}"
            with urllib.request.urlopen(url, timeout=5) as r:
                return base64.b64encode(r.read()).decode()
        except Exception:  # noqa: BLE001
            return ""

    def run_shortcut(self, lesson_id: str) -> dict:
        lesson = self._lessons.get(lesson_id) or {}
        sc = dict(lesson.get("shortcut") or {})
        sc["kind"] = "folder"
        sc["key"] = sc.get("folder", "")
        ok, detail = shortcuts.launch(sc)
        return {"ok": ok, "detail": detail}

    # ---------------------------------------------------------- appairage

    def pairing(self) -> dict:
        url = getattr(self.b, "PAIRING_URL", "") or ""
        return {"url": url, "qr": _qr(url) if url else ""}


# ------------------------------------------------------------------ pont JS

_window = None


def call_js(fn: str, *args) -> None:
    """Appelle une fonction de `window.carepilot`. La vue ne répond jamais."""
    if _window is None:
        return
    try:
        payload = ", ".join(json.dumps(a, ensure_ascii=False) for a in args)
        _window.evaluate_js(f"window.carepilot.{fn}({payload})")
    except Exception:  # noqa: BLE001 — fenêtre fermée pendant l'appel
        pass


def _self_rect() -> tuple | None:
    """Où est notre propre fenêtre, pour que l'agent ne la voie ni ne la clique."""
    hwnd = ctypes.windll.user32.FindWindowW(None, TITLE)
    if not hwnd:
        return None
    r = wintypes.RECT()
    if not ctypes.windll.user32.GetWindowRect(hwnd, ctypes.byref(r)):
        return None
    return (r.left, r.top, r.right, r.bottom)


def _pump(bridge) -> None:
    """Draine les messages du réseau vers l'interface."""
    while True:
        try:
            bridge.self_window.set(_self_rect())
        except Exception:  # noqa: BLE001
            pass
        try:
            while True:
                kind, value = bridge.to_ui.get_nowait()
                if kind == "action" and not bridge.gate.is_stopped():
                    call_js("doing", value)
                elif kind == "session":
                    call_js("session", value, _qr(value, 240))
                elif kind == "pairing":
                    bridge.PAIRING_URL = value
                    print("LIEN PERMANENT DU PROCHE : " + value, flush=True)
                elif kind == "invitation":
                    call_js("invitation", value)
                elif kind == "link":
                    call_js("net", value == "connecté", f"Connexion : {value}")
                elif kind == "screen":
                    print("[pont] " + value, flush=True)
        except queue.Empty:
            pass
        time.sleep(0.12)


def run(bridge) -> None:
    """Ouvre la fenêtre. Bloque jusqu'à sa fermeture."""
    global _window
    api = Api(bridge)
    _window = webview.create_window(
        TITLE, UI.as_uri(), js_api=api,
        width=520, height=860, min_size=(440, 640),
        background_color="#11151c", on_top=True,
    )

    def on_closed() -> None:
        # Fermer la fenêtre, c'est arrêter : rien ne doit continuer sans elle.
        bridge.gate.raise_stop()
        bridge.send_soon({"type": "stop"})

    _window.events.closed += on_closed
    threading.Thread(target=_pump, args=(bridge,), daemon=True).start()
    webview.start()
