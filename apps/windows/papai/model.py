"""L'état de l'app et le parcours, port de `apps/mac/Sources/Model.swift`.

Indépendant de la fenêtre : l'interface HTML reçoit `snapshot()` à chaque
changement et appelle les méthodes publiques (voir `app.py`). Testable sans
Windows ni WebView.

App de l'employé : pas d'accueil ni de liaison. Le nom vient du compte Windows,
l'organisation et son support des stratégies de groupe (`settings.policy()`).
"""

from __future__ import annotations

import datetime
import json
import os
import re
import threading
import time
import urllib.request
from typing import Callable

from . import apps as start_apps
from . import settings
from . import offline_lessons
from .bridge import Bridge
from .core import StopGate, open_shortcut, play_actions

OPEN_STATES = ("planning", "awaiting_approval", "active", "awaiting_helper")
STATES = OPEN_STATES + ("done", "stopped")
TEXT_SCALES = [("Grande", 1.0), ("Très grande", 1.18)]
NOTICE_S = 7
HOME_AFTER_DONE_S = 90


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
        # Holo pose la question à l’utilisateur lui-même (`ask_senior`).
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
        self.answer_sources: list[dict] = []
        self.current_action: str | None = None
        self.actions: list[str] = []
        self.lessons: list[dict] = []
        self.requests: list[dict] = []
        self.requests_open = False
        self.requests_loading = False
        self.requests_error = False
        self.lesson: dict | None = None
        self.notice: str | None = None
        self.alert: dict | None = None
        self.helpers: list[dict] = []
        self.remote_request: dict | None = None
        # Demande partie en ticket sans support disponible : {ticket, number, task, rdv, show}.
        self.queued: dict | None = None
        # Demande qui a déjà son ticket : {kind: open|solved, ticket, number, task, status, rdv, solution}.
        self.existing: dict | None = None
        self.pending_task = ""
        self.pending_automation: str | None = None
        self.pending_automation_ticket: str | None = None
        self.automation_running: str | None = None
        self.apps: list[dict] = []
        self.dictation = {"phase": "idle", "message": None}
        # Nom du compte Windows (ou stratégie DisplayName) : rien à saisir.
        self._first_name = "" if self.demo else settings.display_name()
        self.auto_sent = False
        self._org_name = ""

        self.gate = StopGate()
        self._notice_timer: threading.Timer | None = None
        self._home_timer: threading.Timer | None = None
        self.bridge: Bridge | None = None
        self._bridge_factory = bridge_factory

    # ------------------------------------------------------------ dérivés

    @property
    def realtime_protection(self) -> bool:
        return settings.protection_on(self.prefs)

    @property
    def session_open(self) -> bool:
        return self.state in OPEN_STATES

    @property
    def first_name(self) -> str:
        return self._first_name

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
                "connected": self.connected,
                "firstName": self.first_name,
                "helperName": hn, "HelperName": hn[:1].upper() + hn[1:],
                "textScale": self.text_scale, "textScales": TEXT_SCALES,
                "server": self.server_url, "httpBase": self.http_base,
                "orgName": str(self.prefs.get("orgName") or ""),
                "orgConfigured": self.org_configured,
                "realtimeProtection": self.realtime_protection,
                "screen": self.screen, "state": self.state, "sessionOpen": self.session_open,
                "stoppedBy": self.stopped_by,
                "task": self.task, "pendingTask": self.pending_task, "screenConsent": self.screen_consent,
                "plan": list(self.plan), "planStep": self.plan_step,
                "question": self.question, "answer": self.answer, "answerSources": list(self.answer_sources),
                "questionForMe": self.question_for_me, "questionOptions": list(self.question_options),
                "paused": self.paused, "guardAcknowledged": self.guard_acknowledged,
                "carer": self.carer, "compact": self.compact,
                "currentAction": self.current_action, "actions": list(self.actions),
                "lessons": list(self.lessons), "lesson": self.lesson, "automationRunning": self.automation_running, "notice": self.notice, "alert": self.alert,
                "requests": [{**r, "relaunch": r.get("relaunch") if self._find_lesson(r.get("relaunch")) else None}
                             for r in self.requests],
                "requestsLoading": self.requests_loading, "requestsError": self.requests_error,
                "helpers": list(self.helpers), "remoteRequest": self.remote_request, "queued": self.queued,
                "existing": self.existing,
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
        """Réponse de l’utilisateur à une question de Holo qui lui est posée."""
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
                              self._connection, self._action,
                              alert_visible=lambda: self.alert is not None, **bridge_kw)
        self.bridge.protection = lambda: self.realtime_protection
        self.bridge.start()
        if settings.needs_space(self.prefs):
            threading.Thread(target=self._create_space, daemon=True).start()
        elif self._org_pending():
            threading.Thread(target=self._join_org, daemon=True).start()
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
                org = {"orgJoined": settings.org_token(), "orgName": self._org_name} if self._org_name else {}
                self.prefs = settings.save({"server": url, **org})
                self.reconnect()
                return
            wait(delay)
            delay = min(delay * 2, 60)

    def _provision(self) -> str | None:
        info: dict = {}
        tok = settings.org_token()
        url = settings.provision(org=tok, info=info)
        if url is None and tok and info.get("status") == 403:
            # Jeton refusé : le poste a quand même son espace, hors organisation.
            info = {}
            url = settings.provision(info=info)
        self._org_name = str(info.get("org") or "")
        return url

    def _org_pending(self) -> bool:
        """Jeton d'organisation déposé par l'IT, pas encore utilisé par ce poste."""
        tok = settings.org_token()
        return bool(tok) and self.prefs.get("orgJoined") != tok and "/k/" in self.server_url

    def _join_org(self, wait=time.sleep) -> None:
        delay = 5
        while self._org_pending():
            name = self._join(settings.org_token())
            if name:
                self.prefs = settings.save({"orgJoined": settings.org_token(), "orgName": name})
                self.push()
                threading.Thread(target=self.refresh_lessons, daemon=True).start()
                return
            if name == "":
                return  # refusé (jeton inconnu, autre organisation) : on n'insiste pas
            wait(delay)
            delay = min(delay * 2, 60)

    def _join(self, token: str) -> str | None:
        return settings.join_org(self.http_base, token)

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

    @property
    def org_configured(self) -> bool:
        """L'IT a déposé un jeton d'organisation (stratégie de groupe ou repli d'essai)."""
        return bool(self.prefs.get("orgName")) or bool(settings.org_token())

    def _send_profile(self) -> None:
        """Le nom du compte Windows, pour que le support lise le bon nom."""
        msg = {"type": "profile", "protection": self.realtime_protection}
        if self.first_name:
            msg["name"] = self.first_name
        self._send(msg)

    def _connection(self, ok: bool) -> None:
        if ok:
            self._send_profile()
            threading.Thread(target=self.refresh_lessons, daemon=True).start()
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
            data = None
        if not isinstance(data, list):
            # Pas de réseau : ceux qui n'ont pas besoin de Holo restent là.
            with self._lock:
                if self.lessons:
                    return
                self.lessons = offline_lessons.load(self.http_base)
            self.push()
            return
        lessons = [x for x in data if isinstance(x, dict) and x.get("id")]
        with self._lock:
            self.lessons = lessons
        offline_lessons.save(lessons, self.http_base)
        self.push()

    def reconnect(self) -> None:
        if self.bridge is not None and not self.demo:
            self.bridge.reconnect(self.server_url)

    def open_requests(self) -> None:
        self.requests_open = True
        if not self.demo:
            self.requests_loading = True
            self.requests_error = False
            self.push()
            threading.Thread(target=self.refresh_requests, daemon=True).start()

    def close_requests(self) -> None:
        self.requests_open = False

    def refresh_requests(self) -> None:
        if self.demo:
            return
        try:
            with urllib.request.urlopen(self.http_base + "/requests", timeout=5) as response:
                data = json.loads(response.read().decode())
            if not isinstance(data, dict) or not isinstance(data.get("requests"), list):
                raise ValueError("Invalid requests")
            rows = [r for r in data["requests"] if isinstance(r, dict) and isinstance(r.get("id"), str)]
        except Exception:
            with self._lock:
                self.requests, self.requests_error, self.requests_loading = [], True, False
        else:
            with self._lock:
                self.requests, self.requests_error, self.requests_loading = rows, False, False
        self.push()

    def relaunch_request(self, request_id: str) -> None:
        request = next((r for r in self.requests if r.get("id") == request_id), None)
        lesson_id = request.get("relaunch") if request else None
        if isinstance(lesson_id, str) and lesson_id and self._find_lesson(lesson_id):
            self.run_automation(lesson_id)

    # ------------------------------------------------------------ réglages

    def save_prefs(self, **values) -> None:
        if not self.demo:
            self.prefs = settings.save(values)
        else:
            self.prefs.update(values)

    def set_text_scale(self, v: float) -> None:
        self.save_prefs(textScale=float(v))
        self.push()

    def set_realtime_protection(self, on: bool) -> None:
        self.save_prefs(realtimeProtection=bool(on))
        self._send_profile()
        self.push()

    def accept_remote(self) -> None:
        """Le support propose une assistance : rien ne démarre sans ce clic."""
        r = self.remote_request
        if not r:
            return
        self.remote_request = None
        task = r.get("task") or f"{r.get('from')} propose de m'aider sur l'ordinateur"
        self.ask_help(task, requested_by=r.get("from"), ticket=r.get("ticket"))

    def dismiss_alert(self) -> None:
        if self.alert and self.alert.get("blocked"):
            return
        self.alert = None
        self.push()

    def refuse_remote(self) -> None:
        r = self.remote_request or {}
        self.remote_request = None
        msg = {"type": "remote_answer", "accepted": False}
        if r.get("ticket"):
            msg["ticket"] = r["ticket"]
        self._send(msg)
        self.push()

    # ------------------------------------------------------ ticket en attente

    def schedule_ticket(self, slot: str) -> None:
        """Rendez-vous pour la demande en attente : dans 1 h, demain 9 h ou 14 h."""
        q = self.queued
        if not q:
            return
        now = datetime.datetime.now()
        tomorrow = (now + datetime.timedelta(days=1)).replace(minute=0, second=0, microsecond=0)
        at = {"1h": now + datetime.timedelta(hours=1), "demain9": tomorrow.replace(hour=9),
              "demain14": tomorrow.replace(hour=14)}.get(slot)
        if at is None:
            return
        self._send({"type": "ticket_schedule", "ticket": q["ticket"], "at": int(at.timestamp())})

    def close_queued(self, show: bool = False) -> None:
        if self.queued:
            self.queued["show"] = show
        self.push()

    # ------------------------------------------------------ demande déjà connue

    def close_existing(self) -> None:
        self.existing = None
        self.push()

    def retry_existing(self) -> None:
        """Déjà réglée mais le problème est revenu : le même ticket est rouvert."""
        e, self.existing = self.existing, None
        if e and e["kind"] == "solved":
            self.ask_help(e["asked"] or e["task"], reopen=e["ticket"])

    def new_request(self) -> None:
        """Ce n'est pas la même demande : elle part avec son propre ticket."""
        e, self.existing = self.existing, None
        if e:
            self.ask_help(e["asked"] or e["task"], new=True)

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
            ticket_id, self.pending_automation_ticket = self.pending_automation_ticket, None
            self.pending_task = ""
            self.screen = "home"
            self.run_automation(lesson_id, ticket_id=ticket_id)
            return
        self.ask_help(self.pending_task)

    def revoke_consent(self) -> None:
        self.save_prefs(screenConsent=False)
        self.push()

    def cancel_consent(self) -> None:
        self.pending_task = ""
        self.pending_automation = None
        self.pending_automation_ticket = None
        self.screen = "home"
        self.push()

    def ask_help(self, task: str, requested_by: str | None = None, ticket: str | None = None,
                 reopen: str | None = None, new: bool = False) -> None:
        self.existing = None
        if self.queued:
            self.queued["show"] = False
            if ticket and self.queued["ticket"] == ticket:
                self.queued = None
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
            self.answer_sources = []
            self.state = "planning"
            self.screen = "session"
        self._level()
        if self.bridge is not None:
            if reopen or new:
                self.bridge.ask_help(self.task, requested_by, ticket, reopen=reopen, new=new)
            elif ticket:
                self.bridge.ask_help(self.task, requested_by, ticket)
            else:
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
        elif kind == "linkup_answer":
            self.answer = m.get("content")
            self.answer_sources = [s for s in (m.get("sources") or []) if isinstance(s, dict)
                                   and str(s.get("url", "")).startswith(("http://", "https://"))]
        elif kind == "answer":
            self.answer = m.get("content")
            self.answer_sources = []
        elif kind == "helpers":
            lst = m.get("helpers") or []
            self.helpers = [{"id": str(d["id"]), "name": str(d["name"]),
                             "relation": str(d.get("relation") or "")}
                            for d in lst if isinstance(d, dict) and d.get("id") and d.get("name")]
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
        elif kind == "tickets_changed":
            if self.requests_open:
                threading.Thread(target=self.refresh_requests, daemon=True).start()
        elif kind == "lessons_changed":
            def go() -> None:
                self.refresh_lessons()
                if m.get("title"):
                    self.show_notice(f"Nouvel automate : « {m['title']} »")
            threading.Thread(target=go, daemon=True).start()
        elif kind == "pair_confirm":
            # Poste d'entreprise : le support vient de l'organisation, jamais d'un code
            # tapé sur un téléphone. Toute demande de liaison est refusée sans rien afficher.
            if m.get("req") is not None:
                self._send({"type": "pair_decision", "req": m["req"], "accept": False})
            return
        elif kind == "ticket_queued":
            # Aucun support disponible : la demande attend, on revient à l'accueil.
            suggestions = m.get("suggestions")
            suggestions = [
                {"id": str(x["id"]), "title": str(x["title"])}
                for x in suggestions if isinstance(x, dict) and x.get("id") and x.get("title")
            ] if isinstance(suggestions, list) else []
            with self._lock:
                self.queued = {"ticket": str(m.get("ticket") or ""), "number": m.get("number"),
                               "task": str(m.get("task") or self.task), "rdv": None, "show": True,
                               "suggestions": suggestions, "suggestion_lancee": None}
                self.state, self.screen = None, "home"
            self._level()
        elif kind in ("ticket_exists", "ticket_solved"):
            # La demande a déjà son ticket : rien de nouveau n'est ouvert.
            sol = m.get("solution") if isinstance(m.get("solution"), dict) else {}
            with self._lock:
                self.existing = {
                    "kind": "open" if kind == "ticket_exists" else "solved",
                    "ticket": str(m.get("ticket") or ""), "number": m.get("number"),
                    "task": str(m.get("task") or self.task), "asked": self.task,
                    "status": str(m.get("status") or ""), "rdv": m.get("rdv"),
                    "note": str(sol.get("note") or ""), "by": str(sol.get("by") or ""),
                    "at": sol.get("at"), "steps": [str(x) for x in sol.get("steps") or []]}
                self.state, self.screen = None, "home"
            self._level()
        elif kind == "ticket_scheduled":
            if self.queued and self.queued["ticket"] == m.get("ticket"):
                self.queued["rdv"] = m.get("at")
        elif kind == "remote_request":
            if self.session_open:
                return
            self.remote_request = {"from": m.get("from") or "Votre support", "task": m.get("task") or "",
                                   "ticket": m.get("ticket"), "rdv": bool(m.get("rdv"))}
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

    # ---------------------------------------------- automates, tutoriels

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

    def run_suggested_automation(self, lesson_id: str, ticket_id: str) -> None:
        q = self.queued
        if not q or q.get("ticket") != ticket_id or not any(
            x.get("id") == lesson_id for x in q.get("suggestions", []) if isinstance(x, dict)
        ):
            return
        q["show"] = False
        self.run_automation(lesson_id, ticket_id=ticket_id)

    def run_automation(self, lesson_id: str, ticket_id: str | None = None) -> None:
        """Un automate importé par un support, lancé en un clic. Pas de
        validation à chaque fois : le support l'a validé à l'import."""
        lesson_id = str(lesson_id or "")
        lesson = self._find_lesson(lesson_id)
        if lesson is None or not lesson.get("actions"):
            return
        if ticket_id and (not self.queued or self.queued.get("ticket") != ticket_id
                          or not any(x.get("id") == lesson_id for x in self.queued.get("suggestions", [])
                                     if isinstance(x, dict))):
            ticket_id = None
        if "windows" not in (lesson.get("platforms") or ["windows"]):
            self.show_notice("Cet automate est prévu pour un autre ordinateur.")
            return
        holo = any(a.get("do") == "holo" for a in lesson["actions"])
        if holo and not self.screen_consent:
            self.pending_automation = lesson_id
            self.pending_automation_ticket = ticket_id
            self.pending_task = str(lesson.get("title") or "")
            self.screen = "consent"
            self.push()
            return
        if self.automation_running:
            return
        if ticket_id:
            self._send({"type": "ticket_automate_launched", "ticket": ticket_id, "lesson": lesson_id})
            if self.queued and self.queued.get("ticket") == ticket_id:
                self.queued["suggestion_lancee"] = lesson_id
        self.gate.reset()
        self.automation_running = str(lesson.get("title") or "Automate")
        self.show_notice(f"C'est parti : {lesson.get('title') or 'automate'}…")
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
            self.show_notice(f"« {lesson.get('title') or 'Cet automate'} » n'a pas pu aller au bout. "
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
            self.answer_sources = []
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
        """PAPAI_DEMO=home|home_no_org|consent|planning|awaiting_approval|active|
        awaiting_helper|done|stopped|remote|… : mêmes écrans de démonstration que le
        Mac, sans serveur. Sert aux captures. Poste de Jeanne, rattaché à « Acme »
        (sauf `home_no_org`, poste sans stratégie de groupe)."""
        self.connected = True
        self._first_name = "Jeanne"
        if demo != "home_no_org":
            self.prefs["orgName"] = "Acme"
        self.helpers = [{"id": "1", "name": "Marc", "relation": "Service informatique"}]
        self.apps = [{"label": n, "path": "", "icon": None}
                     for n in ("Mail", "Photos", "Internet", "Visio", "Explorateur", "Calendrier")]
        if demo == "remote":
            self.remote_request = {"from": "Marc", "task": "Mettre à jour votre ordinateur"}
            return
        self.lessons = [
            {"id": "a", "title": "Dossier comptabilité", "shortcut": {"folder": "documents"},
             "steps": [{"instruction": "Ouvrez l'Explorateur de fichiers"}]},
            {"id": "b", "title": "Mes téléchargements", "shortcut": {"folder": "downloads"}},
        ]
        if demo == "requests":
            self.lessons.append({"id": "print", "title": "Configurer mon imprimante", "platforms": ["windows"],
                                 "actions": [{"do": "open_settings", "page": "printers"}]})
            self.requests = [
                {"id": "r1", "created": 1794132000, "task": "Je voudrais imprimer un document", "status": "resolu",
                 "solution": {"kind": "automate", "title": "Configurer mon imprimante", "lesson": "print"}, "relaunch": "print"},
                {"id": "r2", "created": 1794045600, "task": "Retrouver mes documents", "status": "resolu",
                 "solution": {"kind": "plan", "steps": ["Ouvrir l'Explorateur de fichiers", "Ouvrir le dossier Documents"]}, "relaunch": None},
                {"id": "r3", "created": 1793959200, "task": "Comment changer la taille du texte ?", "status": "resolu",
                 "solution": {"kind": "answer", "text": "Ouvrez les Réglages, puis choisissez Très grande.",
                              "sources": [{"title": "Aide PapAI", "url": "https://example.org/aide"}]}, "relaunch": None},
                {"id": "r4", "created": 1793872800, "task": "Mon casque ne fonctionne plus", "status": "en_attente",
                 "solution": None, "relaunch": None},
            ]
            return
        if demo == "alert":
            self.alert = {"level": "danger", "title": "Attention : ce message est sans doute une arnaque",
                          "detail": "Un faux message d'alerte demande d'appeler un numéro. N'appelez pas. "
                                    "Votre support est prévenu."}
            return
        if demo in ("home", "home_no_org"):
            return
        if demo == "lesson":
            self.lesson = {"id": "a", "title": "Dossier comptabilité", "steps": [
                {"instruction": "Ouvrez l'Explorateur de fichiers",
                 "checkpoint": "une fenêtre avec vos dossiers à gauche"},
                {"instruction": "Cliquez sur « Documents »"}]}
            self.screen = "lesson"
            return
        if demo == "consent":
            self.pending_task = "Je ne retrouve plus le dossier de la comptabilité"
            self.screen = "consent"
            return
        state = {"senior_question": "awaiting_helper", "paused": "active",
                 "compact": "active", "gardien": "stopped"}.get(demo, demo)
        if state not in STATES:
            return
        self.task = "Je ne retrouve plus le dossier de la comptabilité"
        self.plan = ["Ouvrir l'Explorateur de fichiers", "Aller dans le dossier Documents",
                     "Ouvrir le dossier « Comptabilité 2025 »"]
        self.plan_step = 2
        self.answer = "Le dossier Comptabilité 2025 est ouvert dans Documents."
        self.current_action = "Je clique sur l'icône de l'Explorateur"
        self.actions = ["J'ouvre la recherche de Windows", "J'écris « Explorateur »",
                        "Je clique sur l'icône de l'Explorateur"]
        self.question = "Je vois deux dossiers « Comptabilité ». Lequel faut-il ouvrir ?"
        if demo == "senior_question":
            self.question = "Le dossier est-il sur cet ordinateur ou sur une clé USB ?"
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
