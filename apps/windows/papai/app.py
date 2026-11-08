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
from .home_shortcuts import HomeShortcuts
from .mic_presence import MicPresence
from .model import Model

UI = Path(__file__).resolve().parent.parent / "ui" / "index.html"
FULL_SIZE = (1100, 720)
MINI_SIZE = (380, 210)


class Api:
    """Ce que la page peut demander. Les attributs privés (_…) ne sont pas exposés."""

    def __init__(self, model: Model, dictation: Dictation) -> None:
        self._model = model
        self._dictation = dictation
        self._ready = threading.Event()
        self._closed = threading.Event()
        self._shortcuts = HomeShortcuts(demo=bool(model.demo))
        self._micro = MicPresence(self._micro_changed)

    def _micro_changed(self, present):
        if not present:
            self._dictation.cancel()
        self._model.push()

    def snapshot(self, snap=None):
        data = dict(snap if snap is not None else self._model.snapshot())
        data.update(microPresent=self._micro.present, homeShortcuts=self._shortcuts.snapshot())
        return data

    def start(self):
        self._micro.start()
        threading.Thread(target=self._watch_shortcuts, daemon=True, name='papai-raccourcis').start()

    def _watch_shortcuts(self):
        while not self._closed.wait(5):
            before = self._shortcuts.snapshot()
            self._shortcuts.refresh()
            if before != self._shortcuts.snapshot():
                self._model.push()

    def close(self):
        self._closed.set()
        self._micro.close()
        self._dictation.close()

    def ready(self):
        self._ready.set()
        return self.snapshot()

    def set_first_name(self, name): self._model.set_first_name(name)
    def set_text_scale(self, v): self._model.set_text_scale(v)
    def set_realtime_protection(self, on): self._model.set_realtime_protection(on)
    def set_onboarding_step(self, step): self._model.set_onboarding_step(step)
    def finish_onboarding(self): self._model.finish_onboarding()
    def reset_onboarding(self): self._model.reset_onboarding()
    def save_settings(self, name, server): self._model.save_settings(name, server)
    def start_pairing(self): self._model.start_pairing()
    def stop_pairing(self): self._model.stop_pairing()
    def copy_invitation(self): return self._model.copy_invitation()
    def remove_helper(self, helper_id): self._model.remove_helper(helper_id)
    def accept_remote(self): self._model.accept_remote()
    def answer_pair(self, accept): self._model.answer_pair(accept)
    def refuse_remote(self): self._model.refuse_remote()
    def schedule_ticket(self, slot): self._model.schedule_ticket(slot)
    def close_queued(self): self._model.close_queued()
    def open_queued(self): self._model.close_queued(show=True)
    def dismiss_alert(self): self._model.dismiss_alert()
    def request_consent(self, task): self._model.request_consent(task)
    def cancel_consent(self): self._model.cancel_consent()
    def give_consent(self): self._model.give_consent()
    def revoke_consent(self): self._model.revoke_consent()
    def ask_help(self, task): self._model.ask_help(task)
    def stop(self): self._model.stop()
    def back_home(self): self._model.back_home()
    def toggle_pause(self): self._model.toggle_pause()
    def answer_senior(self, text): self._model.answer_senior(text)
    def expand_window(self): self._model.expand_window()
    def run_shortcut(self, lesson_id): self._model.run_shortcut(lesson_id)
    def open_lesson(self, lesson_id): self._model.open_lesson(lesson_id)
    def close_lesson(self): self._model.close_lesson()
    def open_home_shortcut(self, shortcut_id):
        ok, message = self._shortcuts.open(shortcut_id)
        if not ok:
            self._model.show_notice(message)

    def remove_home_shortcut(self, shortcut_id):
        self._shortcuts.remove(shortcut_id)
        self._model.push()

    def add_home_folder(self):
        import webview
        window = webview.windows[0]
        chosen = window.create_file_dialog(webview.FileDialog.FOLDER)
        if not chosen:
            return {'ok': False}
        ok = self._shortcuts.add_folder(chosen[0])
        self._model.push()
        return {'ok': ok, 'message': None if ok else "Choisissez un dossier ordinaire. Si vous avez déjà 4 raccourcis personnels, retirez-en un d'abord."}

    def dictation_toggle(self):
        snap = self._model.snapshot()
        if self._micro.refresh() and snap['screen'] == 'home' and not snap['remoteRequest'] and not snap['alert']:
            self._dictation.toggle(self._model.http_base)


def main() -> None:
    import webview

    state = {"window": None, "hwnd": 0, "excluded": False, "api": None}

    def push(snap: dict) -> None:
        w, api = state["window"], state["api"]
        if w is None or api is None or not api._ready.is_set():
            return
        if snap['screen'] != 'home' or snap['remoteRequest'] or snap['alert']:
            if api._dictation.phase != 'idle':
                api._dictation.cancel()
        snap = api.snapshot(snap)
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

    def on_compact(compact: bool) -> None:
        # Holo agit : la fenêtre devient un petit encart en bas à droite (MiniPanel
        # du Mac), toujours au premier plan, avec l'avancement, Pause et Arrêter.
        w = state["window"]
        if w is None:
            return
        try:
            sw, sh = 1280, 800
            if webview.screens:
                sw, sh = webview.screens[0].width, webview.screens[0].height
            if compact:
                w.restore()  # réduite avant l'accord : l'encart doit rester visible
                w.show()
                w.resize(*MINI_SIZE)
                w.move(max(0, sw - MINI_SIZE[0] - 24), max(0, sh - MINI_SIZE[1] - 72))
            else:
                w.resize(*FULL_SIZE)
                w.move(max(0, (sw - FULL_SIZE[0]) // 2), max(0, (sh - FULL_SIZE[1]) // 2))
                w.restore()
                w.show()
        except Exception:  # noqa: BLE001 — fenêtre en cours de fermeture
            pass

    model = Model(push=push, on_level=on_level, on_remote=on_remote, on_compact=on_compact)
    dictation = Dictation(on_phase=lambda p, m: model.set_dictation(p, m),
                          on_text=lambda t: push_text(t))

    def push_text(text: str) -> None:
        model.send_dictation(text, final=True)
        w = state["window"]
        if w is not None:
            w.evaluate_js(f"window.PapAI && PapAI.dictated({json.dumps(text, ensure_ascii=False)}, {dictation.run_id})")

    api = Api(model, dictation)
    state["api"] = api
    window = webview.create_window(
        "PapAI", str(UI), js_api=api, width=FULL_SIZE[0], height=FULL_SIZE[1], min_size=MINI_SIZE,
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
        api.close()
        model.shutdown()

    window.events.shown += on_shown
    window.events.closing += on_closing
    api.start()
    model.start(protected=protected, capture_mask=capture_mask)
    webview.start(gui="edgechromium" if sys.platform == "win32" else None,
                  debug=bool(__import__("os").environ.get("PAPAI_DEBUG")))


if __name__ == "__main__":
    main()
