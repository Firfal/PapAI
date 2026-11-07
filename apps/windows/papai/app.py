"""Point d'entrée : la fenêtre PapAI (pywebview, donc WebView2 sur Windows).

La fenêtre affiche `ui/index.html`, qui dessine les écrans de l'app Mac.
Tout ce qui touche à l'ordinateur ou au serveur reste en Python (`model.py`,
`bridge.py`, `core.py`) ; la page n'appelle que les méthodes de `Api`.
"""

from __future__ import annotations

import ctypes
import json
import sys
import threading
from pathlib import Path

from .core import exclude_from_capture, window_rect
from .dictation import Dictation
from .model import Model

UI = Path(__file__).resolve().parent.parent / "ui" / "index.html"


class Api:
    """Ce que la page peut demander. Les attributs privés (_…) ne sont pas exposés."""

    def __init__(self, model: Model, dictation: Dictation) -> None:
        self._model = model
        self._dictation = dictation
        self._ready = threading.Event()

    def ready(self):
        self._ready.set()
        return self._model.snapshot()

    def set_first_name(self, name): self._model.set_first_name(name)
    def set_text_scale(self, v): self._model.set_text_scale(v)
    def set_onboarding_step(self, step): self._model.set_onboarding_step(step)
    def finish_onboarding(self): self._model.finish_onboarding()
    def reset_onboarding(self): self._model.reset_onboarding()
    def save_settings(self, name, server): self._model.save_settings(name, server)
    def start_pairing(self): self._model.start_pairing()
    def stop_pairing(self): self._model.stop_pairing()
    def remove_helper(self, helper_id): self._model.remove_helper(helper_id)
    def accept_remote(self): self._model.accept_remote()
    def refuse_remote(self): self._model.refuse_remote()
    def request_consent(self, task): self._model.request_consent(task)
    def cancel_consent(self): self._model.cancel_consent()
    def ask_help(self, task): self._model.ask_help(task)
    def stop(self): self._model.stop()
    def back_home(self): self._model.back_home()
    def run_shortcut(self, lesson_id): self._model.run_shortcut(lesson_id)
    def open_lesson(self, lesson_id): self._model.open_lesson(lesson_id)
    def close_lesson(self): self._model.close_lesson()
    def open_app(self, path): self._model.open_app(path)
    def dictation_toggle(self): self._dictation.toggle(self._model.http_base)


def main() -> None:
    import webview

    state = {"window": None, "hwnd": 0, "excluded": False, "api": None}

    def push(snap: dict) -> None:
        w, api = state["window"], state["api"]
        if w is None or api is None or not api._ready.is_set():
            return
        try:
            w.evaluate_js(f"window.PapAI && PapAI.update({json.dumps(snap, ensure_ascii=False)})")
        except Exception:  # noqa: BLE001 — fenêtre en cours de fermeture
            pass

    def on_level(on_top: bool) -> None:
        # Session ouverte : la fenêtre reste au premier plan, comme .floating sur le Mac,
        # pour que le bouton Arrêter soit toujours visible.
        w = state["window"]
        if w is not None:
            try:
                w.on_top = on_top
            except Exception:  # noqa: BLE001
                pass

    def on_remote() -> None:
        w = state["window"]
        if w is not None:
            try:
                w.restore()
                w.show()
            except Exception:  # noqa: BLE001
                pass

    model = Model(push=push, on_level=on_level, on_remote=on_remote)
    dictation = Dictation(on_phase=lambda p, m: model.set_dictation(p, m),
                          on_text=lambda t: push_text(t))

    def push_text(text: str) -> None:
        w = state["window"]
        if w is not None:
            w.evaluate_js(f"window.PapAI && PapAI.dictated({json.dumps(text, ensure_ascii=False)})")

    api = Api(model, dictation)
    state["api"] = api
    window = webview.create_window(
        "PapAI", str(UI), js_api=api, width=1100, height=720, min_size=(900, 640),
        background_color="#EEF0EE", text_select=False,
    )
    state["window"] = window

    def protected():
        return window_rect(state["hwnd"])

    def capture_mask():
        # Si Windows a exclu la fenêtre des captures, rien à masquer.
        return None if state["excluded"] else window_rect(state["hwnd"])

    def on_shown() -> None:
        if sys.platform == "win32":
            hwnd = 0
            try:
                hwnd = int(window.native.Handle.ToInt64())
            except Exception:  # noqa: BLE001
                hwnd = ctypes.windll.user32.FindWindowW(None, "PapAI")
            state["hwnd"] = hwnd
            state["excluded"] = exclude_from_capture(hwnd)

    def on_closing() -> None:
        model.shutdown()

    window.events.shown += on_shown
    window.events.closing += on_closing
    model.start(protected=protected, capture_mask=capture_mask)
    webview.start(gui="edgechromium" if sys.platform == "win32" else None,
                  debug=bool(__import__("os").environ.get("PAPAI_DEBUG")))


if __name__ == "__main__":
    main()
