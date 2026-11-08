"""Tickets : chaque demande d'assistance laisse une trace pour le support.

Un ticket naît avec la demande (de la personne, du support ou d'un automatisme)
et suit la session : plan, qui l'a validé, comment elle s'est terminée. Si aucun
support n'est disponible, la demande attend ; la personne peut aussi fixer un
rendez-vous. Rien que du texte : aucune capture d'écran n'est gardée.
"""

from __future__ import annotations

import re
import secrets
import time
import unicodedata
from pathlib import Path

from . import storage, ticket_stats

OPEN = ("nouveau", "en_attente", "rdv", "en_cours", "a_reprendre")
STATUSES = (*OPEN, "resolu")
MAX = 500
RDV_MAX_S = 30 * 86400

SAME_MAX_AGE_S = 90 * 86400
SAME_MIN_SCORE = 0.6
REDEMANDE = "Demandé à nouveau par l’utilisateur."
_MOTS_VIDES = set("""
le la les un une des du de au aux et ou en dans sur sous pour par avec sans ce cet cette ces
mon ma mes ton ta tes son sa ses notre nos votre vos leur leurs je tu il elle on nous vous ils
elles me te se ne pas plus que qui quoi est sont suis ai as avons avez ont etre avoir moi toi lui
ca cela ceci tout tous toute toutes tres bien encore deja aussi comment pourquoi quand faire fait
veux voudrais voudrait peux peut pouvez arrive arriver marche marcher fonctionne fonctionner
probleme problemes souci soucis aide aider besoin svp merci bonjour depuis toujours jamais rien
""".split())

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

    def same(self, task: str, now: float | None = None) -> dict | None:
        """Un ticket qui porte déjà cette demande : ouvert d'abord, sinon réglé il y a moins de 90 jours.
        Les tickets d'automates (titre de l'automate) ne comptent pas."""
        now = time.time() if now is None else now
        best, best_key = None, None
        for t in self._load():
            if t.get("source") == "automatisme":
                continue
            ouvert = t.get("status") in OPEN
            if not ouvert and now - int(t.get("resolved") or t.get("updated") or 0) > SAME_MAX_AGE_S:
                continue
            score = similarity(task, t.get("task", ""))
            key = (ouvert, score, int(t.get("updated") or 0))
            if score >= SAME_MIN_SCORE and (best_key is None or key > best_key):
                best, best_key = t, key
        return best

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


def _mots(text: str) -> set[str]:
    s = unicodedata.normalize("NFKD", str(text or "").lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r"(?<=[a-z0-9])-(?=[a-z0-9])", "", s)
    return {m[:5] for m in re.findall(r"[a-z0-9]+", s) if len(m) > 2 and m not in _MOTS_VIDES}


def similarity(a: str, b: str) -> float:
    """Même demande dite autrement : mots en commun (sans accents ni mots vides, radical de 5 lettres)."""
    x, y = _mots(a), _mots(b)
    if not x or not y:
        return 0.0
    common = len(x & y)
    small, big = sorted((len(x), len(y)))
    if common == small and big <= small + 2:
        return 1.0
    return 2 * common / (len(x) + len(y))


def solution(t: dict) -> dict:
    """Ce qui a réglé le ticket : le mot du support à la clôture, et les étapes si Holo est allé au bout."""
    note = str(t.get("solution") or "")
    by = t.get("closed_by") or ""
    if not note and by:
        # Ancien ticket : le texte de clôture est la note du support posée à la clôture même.
        closed = int(t.get("resolved") or 0)
        note = next((n.get("text", "") for n in reversed(t.get("notes") or [])
                     if closed and n.get("by") == by and int(n.get("t") or 0) >= closed), "")
    steps = list(t.get("plan") or []) if t.get("end") == "done" else []
    return {"note": note, "steps": steps, "by": by or t.get("helper") or "", "at": int(t.get("resolved") or t.get("updated") or 0)}


def public(t: dict) -> dict:
    return {k: v for k, v in ticket_stats.ensure(dict(t)).items() if k not in ("rdv_notified", "offered")}
