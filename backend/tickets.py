"""Tickets : chaque demande d'assistance laisse une trace pour le support.

Un ticket naît avec la demande (de la personne, du support ou d'un automatisme)
et suit la session : plan, qui l'a validé, comment elle s'est terminée. Si aucun
support n'est disponible, la demande attend ; la personne peut aussi fixer un
rendez-vous. Rien que du texte : aucune capture d'écran n'est gardée.
"""

from __future__ import annotations

import json
import secrets
import time
from pathlib import Path

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
                d = json.loads(self.path.read_text("utf-8"))
                self._items = [t for t in d if isinstance(t, dict) and t.get("id")] if isinstance(d, list) else []
            except (OSError, ValueError):
                self._items = []
        return self._items

    def _save(self) -> None:
        items = self._load()[-MAX:]
        self._items = items
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(items, ensure_ascii=False), encoding="utf-8")
        tmp.replace(self.path)

    def all(self) -> list[dict]:
        return list(reversed(self._load()))

    def get(self, tid: str) -> dict | None:
        tid = str(tid or "")
        return next((t for t in self._load() if t["id"] == tid), None) if tid else None

    def open(self, task: str, source: str, status: str = "nouveau", by: str = "", number: int | None = None) -> dict:
        items = self._load()
        now = int(time.time())
        number = number or max((int(x.get("number", 0)) for x in items), default=0) + 1
        t = {"id": secrets.token_hex(6), "number": number,
             "task": task, "source": source, "by": by[:40], "status": status, "created": now, "updated": now,
             "session": "", "plan": [], "steps_done": 0, "helper": "", "end": "", "stopped_by": "",
             "rdv": None, "rdv_notified": False, "offered": 0, "assignee": "", "notes": [], "tokens": 0}
        items.append(t)
        self._save()
        return t

    def update(self, t: dict, **kw) -> dict:
        t.update(kw)
        t["updated"] = int(time.time())
        self._save()
        return t

    def note(self, t: dict, by: str, text: str) -> None:
        t.setdefault("notes", []).append({"t": int(time.time()), "by": by[:40], "text": text[:1000]})
        self.update(t)

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
    return {k: v for k, v in t.items() if k not in ("rdv_notified", "offered")}
