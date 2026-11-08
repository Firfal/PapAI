"""L'état de l'app et le parcours, port de `apps/mac/Sources/Model.swift`.

Indépendant de la fenêtre : l'interface HTML reçoit `snapshot()` à chaque
changement et appelle les méthodes publiques (voir `app.py`). Testable sans
Windows ni WebView.
"""

from __future__ import annotations

import base64
import json
import os
import threading
import time
import urllib.request
from urllib.parse import quote
from typing import Callable

from . import apps as start_apps
from . import settings
from .bridge import Bridge
from .core import StopGate, open_shortcut, play_actions

OPEN_STATES = ("planning", "awaiting_approval", "active", "awaiting_helper")
STATES = OPEN_STATES + ("done", "stopped")
TEXT_SCALES = [("Grande", 1.0), ("Très grande", 1.18)]
NOTICE_S = 7
HOME_AFTER_DONE_S = 90


def qr_data_url(text: str) -> str | None:
    """QR code en SVG (data URL), comme CIQRCodeGenerator sur le Mac."""
    if not text:
        return None
    try:
        import qrcode
        import qrcode.image.svg
    except ImportError:
        return None
    img = qrcode.make(text, image_factory=qrcode.image.svg.SvgPathImage, border=0,
                      error_correction=qrcode.constants.ERROR_CORRECT_M)
    raw = img.to_string()
    return "data:image/svg+xml;base64," + base64.b64encode(raw).decode()


class Model:
    def __init__(self, push: Callable[[dict], None] = lambda s: None,
                 on_level: Callable[[bool], None] = lambda on: None,
                 on_remote: Callable[[], None] = lambda: None,
                 on_compact: Callable[[bool], None] = lambda on: None,
                 demo: str | None = None, bridge_factory: Callable | None = None) -> None:
        self._push = push
        self._on_level = on_level
        self._on_remote = on_remote
        self._on_compact = on_compact
        self._lock = threading.RLock()
        self.demo = demo if demo is not None else (os.environ.get("PAPAI_DEMO") or None)
        self.prefs = settings.load()

        self.connected = False
        self.screen = "home"
        self.state: str | None = None
        self.stopped_by: str | None = None
        self.task = ""
        self.plan: list[str] = []
        self.plan_step: int | None = None
        self.question: str | None = None
        # Holo pose la question à la personne aidée elle-même (`ask_senior`).
        self.question_for_me = False
        self.question_options: list[str] = []
        self.paused = False
        self.guard_acknowledged = False
        self.session_helper: str | None = None
        # Pendant que Holo agit, la fenêtre devient un petit encart (MiniPanel du Mac).
        self.compact = False
        self.user_expanded = False
        self._last_state: str | None = None
        self.answer: str | None = None
        self.current_action: str | None = None
        self.actions: list[str] = []
        self.lessons: list[dict] = []
        self.lesson: dict | None = None
        self.notice: str | None = None
        self.alert: dict | None = None
        self.helpers: list[dict] = []
        self.pair_code: str | None = None
        self.pair_url: str | None = None
        # Lien `papai://` du QR : ouvre l'app du support au lieu du navigateur.
        self.pair_app_url: str | None = None
        # Invitation à envoyer (SMS, WhatsApp…), valable 24 h, comme sur le Mac.
        self.pair_long = False
        self.pair_expires = 600
        self.pair_added: str | None = None
        self.remote_request: dict | None = None
        self.pair_request: dict | None = None
        self.pending_task = ""
        self.pending_automation: str | None = None
        self.automation_running: str | None = None
        self.apps: list[dict] = []
        self.dictation = {"phase": "idle", "message": None}
        self.onboarded = bool(self.prefs.get("onboarded"))
        self.onboarding_step = 0
        self.auto_sent = False

        self.gate = StopGate()
        self._notice_timer: threading.Timer | None = None
        self._home_timer: threading.Timer | None = None
        self.bridge: Bridge | None = None
        self._bridge_factory = bridge_factory

    # ------------------------------------------------------------ dérivés

    @property
    def session_open(self) -> bool:
        return self.state in OPEN_STATES

    @property
    def first_name(self) -> str:
        n = str(self.prefs.get("firstName") or "").strip()
        return n or "Jeanne"

    @property
    def text_scale(self) -> float:
        try:
            v = float(self.prefs.get("textScale") or 1.0)
        except (TypeError, ValueError):
            v = 1.0
        return v if v > 0 else 1.0

    @property
    def server_url(self) -> str:
        return settings.server_url(self.prefs)

    @property
    def http_base(self) -> str:
        return settings.http_base(self.server_url)

    @property
    def helper_name(self) -> str:
        """Qui aide : toujours au singulier pour accorder le verbe qui suit."""
        h = self.helpers
        if not h:
            return "votre support"
        if len(h) == 1:
            return h[0]["name"]
        if len(h) == 2:
            return f"{h[0]['name']} ou {h[1]['name']}"
        return "votre support"

    @property
    def carer(self) -> str:
        """Qui s'occupe de la session en cours (comme `carer` sur le Mac)."""
        if self.session_helper:
            return self.session_helper
        return self.helpers[0]["name"] if len(self.helpers) == 1 else "Votre support"

    def snapshot(self) -> dict:
        with self._lock:
            hn = self.helper_name
            return {
                "os": "windows", "demo": self.demo,
                "connected": self.connected, "onboarded": self.onboarded,
                "onboardingStep": self.onboarding_step,
                "firstName": self.first_name, "storedFirstName": str(self.prefs.get("firstName") or ""),
                "helperName": hn, "HelperName": hn[:1].upper() + hn[1:],
                "textScale": self.text_scale, "textScales": TEXT_SCALES,
                "server": self.server_url, "httpBase": self.http_base,
                "screen": self.screen, "state": self.state, "sessionOpen": self.session_open,
                "stoppedBy": self.stopped_by,
                "task": self.task, "pendingTask": self.pending_task, "screenConsent": self.screen_consent,
                "plan": list(self.plan), "planStep": self.plan_step,
                "question": self.question, "answer": self.answer,
                "questionForMe": self.question_for_me, "questionOptions": list(self.question_options),
                "paused": self.paused, "guardAcknowledged": self.guard_acknowledged,
                "carer": self.carer, "compact": self.compact,
                "currentAction": self.current_action, "actions": list(self.actions),
                "lessons": list(self.lessons), "lesson": self.lesson, "automationRunning": self.automation_running, "notice": self.notice, "alert": self.alert,
                "helpers": list(self.helpers), "pairCode": self.pair_code,
                "pairURL": self.pair_url, "pairQR": qr_data_url(self.pair_app_url or self.pair_url or ""),
                "pairLong": self.pair_long, "pairExpires": self.pair_expires,
                "pairAdded": self.pair_added, "remoteRequest": self.remote_request,
                "pairRequest": self.pair_request,
                "apps": list(self.apps), "dictation": dict(self.dictation),
            }

    def push(self) -> None:
        self._push(self.snapshot())

    def _level(self) -> None:
        with self._lock:
            if self.state != self._last_state:
                self._last_state = self.state
                self.user_expanded = False
            want = (self.session_open and not self.user_expanded and
                    (self.state == "active" or (self.state == "awaiting_helper" and not self.question_for_me)))
            changed = want != self.compact
            self.compact = want
        self._on_level(self.session_open)
        if changed:
            self._on_compact(want)

    def expand_window(self) -> None:
        """Bouton « agrandir » de l'encart : la grande fenêtre revient."""
        with self._lock:
            self.user_expanded = True
        self._level()
        self.push()

    def toggle_pause(self) -> None:
        with self._lock:
            if not self.session_open:
                return
            self.paused = not self.paused
            paused = self.paused
        if self.bridge is not None:
            self.bridge.send({"type": "pause" if paused else "resume"})
        self._level()
        self.push()

    def answer_senior(self, text: str) -> None:
        """Réponse de la personne aidée à une question de Holo qui lui est posée."""
        t = str(text or "").strip()[:300]
        if t and self.bridge is not None:
            self.bridge.send({"type": "senior_answer", "text": t})

    def send_dictation(self, text: str, final: bool = False) -> None:
        """La dictée part aussi chez l'aidant, qui voit ce qu'elle a dit."""
        t = str(text or "").strip()[:300]
        if t and self.bridge is not None:
            self.bridge.send({"type": "dictation", "text": t, "final": final})

    # ------------------------------------------------------------ démarrage

    def start(self, screen_factory: Callable | None = None, **bridge_kw) -> None:
        if self.demo:
            self._apply_demo(self.demo)
            self.push()
            return
        factory = self._bridge_factory or Bridge
        if screen_factory is None:
            from .core import Screen
            screen_factory = Screen
        self.bridge = factory(self.server_url, self.gate, screen_factory, self._handle,
                              self._connection, self._action, **bridge_kw)
        self.bridge.start()
        if settings.needs_space(self.prefs):
            threading.Thread(target=self._create_space, daemon=True).start()
        threading.Thread(target=self._load_apps, daemon=True).start()
        threading.Thread(target=self.refresh_lessons, daemon=True).start()
        self.push()

    def _create_space(self, wait=time.sleep) -> None:
        """Premier lancement sans serveur réglé : l'espace est créé sur le serveur officiel.

        Hors ligne, on réessaie jusqu'au retour du réseau, sans redémarrer l'app."""
        delay = 5
        while settings.needs_space():
            url = self._provision()
            if not settings.needs_space():
                return  # un serveur a été choisi entre-temps : on n'y touche pas
            if url:
                self.prefs = settings.save({"server": url})
                self.reconnect()
                return
            wait(delay)
            delay = min(delay * 2, 60)

    def _provision(self) -> str | None:
        return settings.provision()

    def _load_apps(self) -> None:
        try:
            found = start_apps.installed()
        except Exception:  # noqa: BLE001
            found = []
        with self._lock:
            self.apps = found
        self.push()

    def _send(self, payload: dict) -> None:
        if self.bridge is not None:
            self.bridge.send(payload)

    def _send_profile(self) -> None:
        """Le prénom réellement saisi, pour que l'aidant lise le bon nom."""
        n = str(self.prefs.get("firstName") or "").strip()
        if n:
            self._send({"type": "profile", "name": n})

    def _connection(self, ok: bool) -> None:
        if ok:
            self._send_profile()
        with self._lock:
            self.connected = ok
            t = os.environ.get("PAPAI_AUTOTASK", "").strip()
            auto = ok and not self.auto_sent and bool(t)
            if auto:
                self.auto_sent = True
        if auto:
            self.ask_help(t)
        else:
            self.push()

    def _action(self, said: str) -> None:
        with self._lock:
            self.current_action = said
            if not self.actions or self.actions[-1] != said:
                self.actions.append(said)
        self.push()

    def refresh_lessons(self) -> None:
        if self.demo:
            return
        try:
            with urllib.request.urlopen(self.http_base + "/lessons", timeout=5) as r:  # noqa: S310
                data = json.loads(r.read().decode())
        except Exception:  # noqa: BLE001
            return
        if isinstance(data, list):
            with self._lock:
                self.lessons = [x for x in data if isinstance(x, dict) and x.get("id")]
            self.push()

    def reconnect(self) -> None:
        if self.bridge is not None and not self.demo:
            self.bridge.reconnect(self.server_url)

    # ------------------------------------------------------ accueil, proches

    def save_prefs(self, **values) -> None:
        if not self.demo:
            self.prefs = settings.save(values)
        else:
            self.prefs.update(values)

    def set_first_name(self, name: str) -> None:
        self.save_prefs(firstName=str(name or "").strip())
        self._send_profile()
        self.push()

    def set_text_scale(self, v: float) -> None:
        self.save_prefs(textScale=float(v))
        self.push()

    def set_onboarding_step(self, step: int) -> None:
        self.onboarding_step = max(0, min(3, int(step)))
        self.push()

    def finish_onboarding(self) -> None:
        self.save_prefs(onboarded=True)
        with self._lock:
            self.onboarded = True
            self.onboarding_step = 0
            self._clear_pair()
        self.push()

    def reset_onboarding(self) -> None:
        self.save_prefs(onboarded=False)
        with self._lock:
            self.onboarded = False
            self.onboarding_step = 0
        self.push()

    def save_settings(self, name: str, server: str) -> None:
        self.save_prefs(firstName=str(name or "").strip(), server=str(server or "").strip())
        self.reconnect()
        threading.Thread(target=self.refresh_lessons, daemon=True).start()
        self.push()

    def start_pairing(self) -> None:
        self.pair_added = None
        self._send({"type": "pair_start", "long": True})
        self.push()

    def stop_pairing(self) -> None:
        self._clear_pair()
        self.push()

    def _clear_pair(self) -> None:
        self.pair_code = self.pair_url = self.pair_app_url = None
        self.pair_long = False

    @staticmethod
    def app_pairing_url(url: str) -> str:
        """`papai://pair?u=<url encodée>` : l'appareil photo du téléphone ouvre l'app, pas le navigateur."""
        return "papai://pair?u=" + quote(url, safe="-._~")

    @property
    def invitation_text(self) -> str:
        n = str(self.prefs.get("firstName") or "").strip()
        who = n or "Votre support"
        return (f"{who} aimerait que vous l'aidiez sur son ordinateur avec PapAI. Ouvrez ce lien sur votre "
                f"téléphone pour vous relier (valable {'24 heures' if self.pair_long else '10 minutes'}) :")

    def copy_invitation(self) -> bool:
        """« Envoyer par SMS, WhatsApp… » : Windows n'a pas de ShareLink, l'invitation part dans le presse-papiers."""
        if not self.pair_url:
            return False
        try:
            import pyperclip
            pyperclip.copy(f"{self.invitation_text}\n{self.pair_url}")
        except Exception:  # noqa: BLE001 — pas de presse-papiers (aperçu, session distante)
            return False
        return True

    def answer_pair(self, accept: bool) -> None:
        """Quelqu'un a tapé le code à 6 chiffres : il ne devient support qu'avec ce clic."""
        r = self.pair_request
        if not r:
            return
        self.pair_request = None
        self._send({"type": "pair_decision", "req": r["req"], "accept": bool(accept)})
        self.push()

    def remove_helper(self, helper_id: str) -> None:
        self._send({"type": "remove_helper", "id": helper_id})

    def accept_remote(self) -> None:
        """Le proche propose une session : rien ne démarre sans ce clic."""
        r = self.remote_request
        if not r:
            return
        self.remote_request = None
        task = r.get("task") or f"{r.get('from')} propose de m'aider sur l'ordinateur"
        self.ask_help(task, requested_by=r.get("from"))

    def dismiss_alert(self) -> None:
        if self.alert and self.alert.get("blocked"):
            return
        self.alert = None
        self.push()

    def refuse_remote(self) -> None:
        self.remote_request = None
        self._send({"type": "remote_answer", "accepted": False})
        self.push()

    # ------------------------------------------------------ demande d'aide

    @property
    def screen_consent(self) -> bool:
        return bool(self.prefs.get("screenConsent"))

    def request_consent(self, task: str) -> None:
        """Étape 4 : la première fois, un écran qui dit ce qui va se passer.
        Ensuite la demande part directement : l'accord est déjà donné."""
        if self.screen_consent:
            self.ask_help(str(task or "").strip())
            return
        self.pending_task = str(task or "").strip()
        self.screen = "consent"
        self.push()

    def give_consent(self) -> None:
        self.save_prefs(screenConsent=True)
        if self.pending_automation:
            lesson_id, self.pending_automation = self.pending_automation, None
            self.pending_task = ""
            self.screen = "home"
            self.run_automation(lesson_id)
            return
        self.ask_help(self.pending_task)

    def revoke_consent(self) -> None:
        self.save_prefs(screenConsent=False)
        self.push()

    def cancel_consent(self) -> None:
        self.pending_task = ""
        self.pending_automation = None
        self.screen = "home"
        self.push()

    def ask_help(self, task: str, requested_by: str | None = None) -> None:
        self.gate.reset()
        self.stopped_by = None
        self._cancel(self._home_timer)
        with self._lock:
            self.task = str(task or "")
            self.pending_task = ""
            self.plan, self.plan_step, self.question = [], None, None
            self.question_for_me, self.question_options, self.paused = False, [], False
            self.session_helper = None
            self.answer, self.current_action, self.actions = None, None, []
            self.state = "planning"
            self.screen = "session"
        self._level()
        if self.bridge is not None:
            self.bridge.ask_help(self.task, requested_by)
        self.push()

    def stop(self) -> None:
        """Le verrou local passe d'abord, puis le serveur est prévenu."""
        self.gate.raise_stop()
        if self.bridge is not None:
            self.bridge.stop()
        with self._lock:
            self.state = "stopped"
            self.current_action = None
        self._level()
        self.push()

    def back_home(self) -> None:
        self._cancel(self._home_timer)
        with self._lock:
            self.screen = "home"
            self.state = None
        self._level()
        self.push()

    def shutdown(self) -> None:
        """Fermeture de la fenêtre : même effet que le bouton Arrêter."""
        self.gate.raise_stop()
        if self.session_open and self.bridge is not None:
            self.bridge.stop()

    # ------------------------------------------------- messages du serveur

    def _handle(self, m: dict) -> None:
        kind = m.get("type")
        if kind == "status":
            self._apply_status(m)
        elif kind == "answer":
            self.answer = m.get("content")
        elif kind == "helpers":
            lst = m.get("helpers") or []
            self.helpers = [{"id": str(d["id"]), "name": str(d["name"]),
                             "relation": str(d.get("relation") or "")}
                            for d in lst if isinstance(d, dict) and d.get("id") and d.get("name")]
            if m.get("added"):
                self.pair_added = str(m["added"])
                self._clear_pair()
        elif kind == "alert":
            self.guard_acknowledged = bool(m.get("acknowledged") or m.get("acknowledged_by"))
            if m.get("level") == "danger" or m.get("blocked"):
                self.gate.raise_stop()
                self.state = "stopped"
                self.current_action = None
            self.alert = {"level": str(m.get("level") or "info"), "title": str(m.get("title") or ""),
                          "detail": str(m.get("detail") or ""), "id": m.get("alert_id"),
                          "blocked": bool(m.get("blocked")), "acknowledged": bool(m.get("acknowledged") or m.get("acknowledged_by"))}
        elif kind == "alert_acknowledged":
            if self.alert and m.get("alert_id") and m["alert_id"] == self.alert.get("id"):
                self.alert["acknowledged"] = True
                self.guard_acknowledged = True
        elif kind == "alert_cleared":
            if self.alert and m.get("alert_id") and m["alert_id"] == self.alert.get("id"):
                self.alert = None
        elif kind == "lessons_changed":
            def go() -> None:
                self.refresh_lessons()
                if m.get("title"):
                    self.show_notice(f"Nouveau tutoriel : « {m['title']} »")
            threading.Thread(target=go, daemon=True).start()
        elif kind == "pair_code":
            self.pair_code = m.get("code")
            self.pair_url = m.get("url")
            self.pair_app_url = m.get("app_url") or (self.app_pairing_url(self.pair_url) if self.pair_url else None)
            self.pair_long = bool(m.get("long"))
            try:
                self.pair_expires = int(m.get("expires_in") or 600)
            except (TypeError, ValueError):
                self.pair_expires = 600
        elif kind == "pair_confirm":
            if m.get("req") is None:
                return
            self.pair_request = {"req": m["req"], "name": str(m.get("name") or "Quelqu'un")[:40],
                                 "relation": str(m.get("relation") or "")[:60]}
            self._on_remote()
        elif kind == "remote_request":
            if self.session_open:
                return
            self.remote_request = {"from": m.get("from") or "Votre support", "task": m.get("task") or ""}
            self._on_remote()
        else:
            return
        self.push()

    def _apply_status(self, m: dict) -> None:
        with self._lock:
            self.stopped_by = m.get("stopped_by")
            if isinstance(m.get("guard_acknowledged"), bool):
                self.guard_acknowledged = m["guard_acknowledged"]
            if self.screen != "session":
                return
            if self.gate.is_stopped:
                self.state = "stopped"
            else:
                before = self.state
                if m.get("state") in STATES:
                    self.state = m["state"]
                if self.state == "done" and before != "done":
                    self._schedule_home()
                if m.get("task"):
                    self.task = m["task"]
                plan = m.get("plan")
                self.plan = [str(s) for s in plan] if isinstance(plan, list) else []
                ps = m.get("plan_step")
                self.plan_step = ps if isinstance(ps, int) and not isinstance(ps, bool) else None
                q = m.get("question")
                self.question = q.get("question") if isinstance(q, dict) else None
                self.question_for_me = isinstance(q, dict) and q.get("to") == "senior"
                opts = q.get("options") if isinstance(q, dict) else None
                self.question_options = [str(o) for o in opts][:4] if isinstance(opts, list) else []
                self.paused = bool(m.get("paused"))
                if m.get("helper_name"):
                    self.session_helper = str(m["helper_name"])
                if self.state != "active":
                    self.current_action = None
        self._level()

    def _schedule_home(self) -> None:
        """Étape 7 : l'écran de fin reste un moment, puis l'accueil revient seul."""
        self._cancel(self._home_timer)

        def go() -> None:
            if self.screen == "session" and self.state == "done":
                self.back_home()

        self._home_timer = threading.Timer(HOME_AFTER_DONE_S, go)
        self._home_timer.daemon = True
        self._home_timer.start()

    # ---------------------------------------------- automatismes, tutoriels

    def _find_lesson(self, lesson_id: str) -> dict | None:
        return next((x for x in self.lessons if x.get("id") == lesson_id), None)

    def run_shortcut(self, lesson_id: str) -> None:
        lesson = self._find_lesson(lesson_id)
        if lesson is None:
            return
        if lesson.get("actions"):
            self.run_automation(lesson_id)
            return
        if not lesson.get("shortcut"):
            self.open_lesson(lesson_id)
            return
        ok, detail = open_shortcut(lesson.get("shortcut"))
        if ok:
            self.show_notice("C'est ouvert.")
        else:
            hn = self.helper_name
            self.show_notice(f"Je ne retrouve pas ce dossier. {hn[:1].upper() + hn[1:]} "
                             "a reçu un message pour s'en occuper.")
            self._send({"type": "automation_failed", "title": lesson.get("title") or "",
                        "detail": detail})

    def run_automation(self, lesson_id: str) -> None:
        """Un automatisme importé par un support, lancé en un clic. Pas de
        validation à chaque fois : le support l'a validé à l'import."""
        lesson = self._find_lesson(lesson_id)
        if lesson is None or not lesson.get("actions"):
            return
        if "windows" not in (lesson.get("platforms") or ["windows"]):
            self.show_notice("Cet automatisme est prévu pour un autre ordinateur.")
            return
        holo = any(a.get("do") == "holo" for a in lesson["actions"])
        if holo and not self.screen_consent:
            self.pending_automation = lesson_id
            self.pending_task = str(lesson.get("title") or "")
            self.screen = "consent"
            self.push()
            return
        if self.automation_running:
            return
        self.gate.reset()
        self.automation_running = str(lesson.get("title") or "Automatisme")
        self.show_notice(f"C'est parti : {lesson.get('title') or 'automatisme'}…")
        threading.Thread(target=self._play_automation, args=(lesson, holo), daemon=True).start()

    def _fetch_lesson_file(self, lesson_id: str, name: str) -> bytes:
        from urllib.parse import quote
        url = f"{self.http_base}/lessons/{quote(lesson_id)}/{quote(name)}"
        with urllib.request.urlopen(url, timeout=20) as r:  # noqa: S310
            return r.read(3_000_000)

    def _play_automation(self, lesson: dict, holo: bool) -> None:
        gate = self.gate
        try:
            ok, detail = play_actions(lesson, lambda n: self._fetch_lesson_file(lesson["id"], n), gate)
        finally:
            self.automation_running = None
        if gate.is_stopped:
            self.show_notice("Arrêté. Rien d'autre ne sera fait.")
            return
        if not ok:
            hn = self.helper_name
            self.show_notice(f"« {lesson.get('title') or 'Cet automatisme'} » n'a pas pu aller au bout. "
                             f"{hn[:1].upper() + hn[1:]} a reçu un message pour s'en occuper.")
            self._send({"type": "automation_failed", "title": lesson.get("title") or "",
                        "detail": detail})
            return
        if not holo:
            self.show_notice(detail or "C'est fait.")
            return
        goal = next(a.get("goal") for a in lesson["actions"] if a.get("do") == "holo")
        self._cancel(self._home_timer)
        with self._lock:
            self.task = str(goal or lesson.get("title") or "")
            self.plan, self.plan_step, self.question = [], None, None
            self.answer, self.current_action, self.actions = None, None, []
            self.state = "planning"
            self.screen = "session"
        self._level()
        if self.bridge is not None:
            self.bridge.run_automation(lesson["id"])
        self.push()

    def open_lesson(self, lesson_id: str) -> None:
        lesson = self._find_lesson(lesson_id)
        if lesson is not None:
            self.lesson = lesson
            self.screen = "lesson"
            self.push()

    def close_lesson(self) -> None:
        self.screen = "home"
        self.push()

    def open_app(self, path: str) -> None:
        if self.demo:
            return
        ok, _ = start_apps.launch(path)
        if not ok:
            self.show_notice("Cette application n'est pas disponible sur cet ordinateur.")

    def show_notice(self, text: str) -> None:
        self._cancel(self._notice_timer)
        self.notice = text

        def clear() -> None:
            self.notice = None
            self.push()

        self._notice_timer = threading.Timer(NOTICE_S, clear)
        self._notice_timer.daemon = True
        self._notice_timer.start()
        self.push()

    def set_dictation(self, phase: str, message: str | None = None) -> None:
        self.dictation = {"phase": phase, "message": message}
        self.push()

    @staticmethod
    def _cancel(t: threading.Timer | None) -> None:
        if t is not None:
            t.cancel()

    # --------------------------------------------------------------- démo

    def _apply_demo(self, demo: str) -> None:
        """PAPAI_DEMO=home|consent|planning|awaiting_approval|active|awaiting_helper|
        done|stopped|remote|onboarding0..4 : mêmes écrans de démonstration que le Mac,
        sans serveur. Sert aux captures."""
        self.connected = True
        if demo.startswith("onboarding"):
            self.onboarded = False
            try:
                self.onboarding_step = max(0, min(3, int(demo[len("onboarding"):] or 0)))
            except ValueError:
                self.onboarding_step = 0
            if self.onboarding_step == 1:
                self.prefs["firstName"] = "Jeanne"
            if self.onboarding_step == 3:
                self.helpers = [{"id": "1", "name": "Claire", "relation": "sa fille"}]
                self.pair_code = "482913"
                self.pair_url = "http://192.168.1.20:8000/p/482913"
                self.pair_app_url = self.app_pairing_url(self.pair_url)
                self.pair_long = True
            return
        self.onboarded = True
        self.helpers = [{"id": "1", "name": "Claire", "relation": "sa fille"}]
        self.apps = [{"label": n, "path": "", "icon": None}
                     for n in ("Mail", "Photos", "Internet", "Visio", "Explorateur", "Calendrier")]
        if demo == "remote":
            self.remote_request = {"from": "Claire", "task": "Mettre à jour votre ordinateur"}
            return
        self.lessons = [
            {"id": "a", "title": "Mes photos de Noël", "shortcut": {"folder": "pictures"},
             "steps": [{"instruction": "Ouvrez l'Explorateur de fichiers"}]},
            {"id": "b", "title": "Mes documents", "shortcut": {"folder": "documents"}},
        ]
        if demo == "alert":
            self.alert = {"level": "danger", "title": "Attention : ce message est sans doute une arnaque",
                          "detail": "Un faux message d'alerte demande d'appeler un numéro. N'appelez pas. "
                                    "Claire est prévenue."}
            return
        if demo == "home":
            return
        if demo == "lesson":
            self.lesson = {"id": "a", "title": "Mes photos de Noël", "steps": [
                {"instruction": "Ouvrez l'Explorateur de fichiers",
                 "checkpoint": "une fenêtre avec vos dossiers à gauche"},
                {"instruction": "Cliquez sur « Images »"}]}
            self.screen = "lesson"
            return
        if demo == "consent":
            self.pending_task = "Je ne retrouve plus mes photos de Noël"
            self.screen = "consent"
            return
        state = {"senior_question": "awaiting_helper", "paused": "active",
                 "compact": "active", "gardien": "stopped"}.get(demo, demo)
        if state not in STATES:
            return
        self.task = "Je ne retrouve plus mes photos de Noël"
        self.plan = ["Ouvrir l'Explorateur de fichiers", "Aller dans le dossier Images",
                     "Ouvrir le dossier « Noël 2025 »"]
        self.plan_step = 2
        self.answer = "Vos photos de Noël sont ouvertes dans le dossier Images."
        self.current_action = "Je clique sur l'icône de l'Explorateur"
        self.actions = ["J'ouvre la recherche de Windows", "J'écris « Explorateur »",
                        "Je clique sur l'icône de l'Explorateur"]
        self.question = "Je vois deux dossiers « Noël ». Lequel faut-il ouvrir ?"
        if demo == "senior_question":
            self.question = "Vos photos de Noël sont-elles sur cet ordinateur ou sur une clé USB ?"
            self.question_for_me = True
            self.question_options = ["Sur l'ordinateur", "Sur une clé USB"]
        self.paused = demo == "paused"
        if demo == "gardien":
            self.stopped_by, self.guard_acknowledged = "gardien", True
        self.state = state
        self.screen = "session"
        self._last_state = state
        self.compact = demo == "compact"
        self.user_expanded = not self.compact
