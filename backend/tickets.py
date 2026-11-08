"""Tickets : chaque demande d'assistance laisse une trace pour le support.

Un ticket naît avec la demande (de la personne, du support ou d'un automatisme)
et suit la session : plan, qui l'a validé, comment elle s'est terminée. Si aucun
support n'est disponible, la demande attend ; la personne peut aussi fixer un
rendez-vous. Rien que du texte : aucune capture d'écran n'est gardée.
"""

from __future__ import annotations

import secrets
import time
from pathlib import Path

from . import storage, ticket_stats
OPEN = ("nouveau", "en_attente", "rdv", "en_cours", "a_reprendre")
STATUSES = (*OPEN, "resolu")
MAX = 500
RDV_MAX_S = 30 * 86400

_LIVE = {"waiting_consent", "planning", "awaiting_approval", "awaiting_helper", "active"}


class Tickets:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._items: list[dict] | None = None

    def _load(self) -> list[dict]:
        if self._items is None:
            try:
                d = storage.read_json(self.path, [])
                self._items = [t for t in d if isinstance(t, dict) and t.get("id")] if isinstance(d, list) else []
            except (OSError, ValueError):
                self._items = []
        return self._items

    def _save(self) -> None:
        items = self._load()[-MAX:]
        self._items = items
        storage.write_json(self.path, items)

    def all(self) -> list[dict]:
        return list(reversed(self._load()))

    def get(self, tid: str) -> dict | None:
        tid = str(tid or "")
        return next((t for t in self._load() if t["id"] == tid), None) if tid else None

    def open(self, task: str, source: str, status: str = "nouveau", by: str = "",
             number: int | None = None, suggestions: list[dict] | None = None) -> dict:
        items = self._load()
        now = int(time.time())
        category, sure = ticket_stats.classify(task)
        number = number or max((int(x.get("number", 0)) for x in items), default=0) + 1
        t = {"id": secrets.token_hex(6), "number": number,
             "task": task, "source": source, "by": by[:40], "status": status, "created": now, "updated": now,
             "session": "", "plan": [], "steps_done": 0, "helper": "", "end": "", "stopped_by": "",
             "rdv": None, "rdv_notified": False, "offered": 0, "assignee": "", "notes": [], "tokens": 0,
             "suggestions": list(suggestions or []), "suggestion_lancee": None,
             "category": category, "category_by": "regles" if sure else "doute", "resolved": None}
        items.append(t)
        self._save()
        return t

    def renumber(self, next_number) -> None:
        """Le poste rejoint une organisation : ses tickets prennent des numéros uniques dans l'organisation."""
        items = self._load()
        if not items:
            return
        for t in sorted(items, key=lambda x: int(x.get("number", 0))):
            t["number"] = next_number()
        self._save()

    def update(self, t: dict, **kw) -> dict:
        now = int(time.time())
        if "status" in kw and kw["status"] != t.get("status"):
            kw["resolved"] = now if kw["status"] == "resolu" else None
        t.update(kw)
        t["updated"] = now
        self._save()
        return t

    def note(self, t: dict, by: str, text: str) -> None:
        t.setdefault("notes", []).append({"t": int(time.time()), "by": by[:40], "text": text[:1000]})
        self.update(t)

    def categorize(self, t: dict, category: str, by: str, who: str = "") -> bool:
        """Change la catégorie. Holo ne repasse jamais sur un choix du support."""
        if category not in ticket_stats.IDS or by not in ticket_stats.BY:
            return False
        if by == "holo" and t.get("category_by") == "support":
            return False
        self.update(t, category=category, category_by=by, category_who=who[:40] if by == "support" else "")
        return True

    def waiting(self) -> list[dict]:
        return [t for t in self._load() if t.get("status") == "en_attente"]

    def due(self, now: float | None = None) -> list[dict]:
        now = time.time() if now is None else now
        return [t for t in self._load() if t.get("status") == "rdv" and t.get("rdv") and t["rdv"] <= now]

    def sync(self, t: dict, st: dict) -> bool:
        """Reporte l'état de la session sur son ticket. Vrai si quelque chose a changé."""
        state = st.get("state")
        status = "en_cours" if state in _LIVE else "resolu" if state == "done" else "a_reprendre" if state == "stopped" else t["status"]
        new = {"status": status, "plan": list(st.get("plan") or t.get("plan") or []),
               "steps_done": max(int(t.get("steps_done") or 0), int(st.get("plan_step") or 0)),
               "helper": st.get("helper_name") or t.get("helper", ""),
               "end": state if state in ("done", "stopped") else "",
               "stopped_by": st.get("stopped_by") or "",
               "tokens": int((st.get("usage") or {}).get("total") or t.get("tokens") or 0)}
        if state == "done" and t.get("plan"):
            new["steps_done"] = len(new["plan"])
        if all(t.get(k) == v for k, v in new.items()):
            return False
        self.update(t, **new)
        return True


def public(t: dict) -> dict:
    return {k: v for k, v in ticket_stats.ensure(dict(t)).items() if k not in ("rdv_notified", "offered")}


def for_user(t: dict, lessons: list[dict]) -> dict:
    """Vue texte : automate (demande résolue seulement) prioritaire sur la réponse validée, puis le plan exécuté."""
    def text(value):
        return value if isinstance(value, str) else ""

    result = {k: text(t.get(k)) for k in ("id", "task", "status")}
    result.update({k: t.get(k) if type(t.get(k)) in (int, float) else 0
                   for k in ("number", "created", "updated")})
    solution, relaunch = None, None
    lesson_id = text(t.get("automate")) or text(t.get("suggestion_lancee"))
    if lesson_id and t.get("status") == "resolu":
        lesson = next((a for a in lessons if a.get("id") == lesson_id), None)
        title = text(lesson.get("title")) if lesson else next(
            (text(a.get("title")) for a in t.get("suggestions", [])
             if isinstance(a, dict) and a.get("id") == lesson_id), "")
        solution = {"kind": "automate", "lesson": lesson_id, "title": title}
        if lesson is not None:
            relaunch = lesson_id
    elif isinstance(t.get("linkup_answer"), dict):
        answer = t["linkup_answer"]
        solution = {"kind": "answer", "text": text(answer.get("content")),
                    "sources": [{"title": text(s.get("title")), "url": text(s.get("url"))}
                                for s in answer.get("sources", []) if isinstance(s, dict)]}
    elif t.get("end") == "done":
        steps = [s for s in t.get("plan", []) if isinstance(s, str) and s]
        if steps:
            solution = {"kind": "plan", "steps": steps}
    return {**result, "solution": solution, "relaunch": relaunch}
