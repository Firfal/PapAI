"""État d'une session d'assistance : cycle de vie, verrou de contrôle, fraîcheur.

Tout ce qui autorise ou refuse une action vit ici, côté serveur. L'interface du
proche ne porte aucune garantie : un bouton resté affiché dans un historique
doit être refusé par ce module, pas masqué par la page.
"""

from __future__ import annotations

import asyncio
import secrets
import time
from dataclasses import dataclass, field
from enum import Enum

# Une session oubliée est une session ouverte. Sans expiration, l'accès du
# proche redevient permanent, ce que le produit s'interdit.
INACTIVITY_TIMEOUT_S = 15 * 60

# Une capture plus vieille que ça ne peut plus servir de base à un clic :
# l'écran a pu changer entre-temps.
FRAME_TTL_S = 30


class State(str, Enum):
    WAITING_CONSENT = "waiting_consent"   # aide demandée, partage pas encore accordé
    PLANNING = "planning"                 # Holo regarde l'écran et prépare un plan
    AWAITING_APPROVAL = "awaiting_approval"  # plan envoyé, le proche doit valider
    ACTIVE = "active"                     # l'agent travaille
    AWAITING_HELPER = "awaiting_helper"   # agent suspendu, question posée au proche
    DONE = "done"
    STOPPED = "stopped"                   # arrêt par l’utilisateur — terminal


class Owner(str, Enum):
    """Qui tient souris et clavier. Un seul à la fois, jamais deux."""

    NONE = "none"
    AGENT = "agent"
    HELPER = "helper"


OPEN_STATES = {
    State.WAITING_CONSENT, State.PLANNING, State.AWAITING_APPROVAL,
    State.ACTIVE, State.AWAITING_HELPER,
}
TERMINAL_STATES = {State.DONE, State.STOPPED}


class Refused(Exception):
    """Une demande rejetée par le serveur. Le message est destiné au proche."""


@dataclass
class Frame:
    frame_id: str
    png_b64: str
    width: int
    height: int
    created_at: float = field(default_factory=time.time)

    @property
    def age(self) -> float:
        return time.time() - self.created_at


@dataclass
class Session:
    id: str
    task: str
    helper_token: str = field(default_factory=lambda: secrets.token_urlsafe(24))
    state: State = State.WAITING_CONSENT
    stopped_by: str | None = None
    execution_started: bool = False
    where: str | None = None  # "web" ou "desktop" : proposé avec le plan, puis mode réel
    guard_acknowledged: bool = False
    owner: Owner = Owner.NONE
    consented: bool = False
    last_frame: Frame | None = None

    # Captures de la session, gardées en mémoire le temps de la session.
    # Rien n'est écrit sur disque tant qu'un proche n'a pas validé une fiche :
    # « pas de capture persistante par défaut ».
    frames: dict[str, str] = field(default_factory=dict, repr=False)

    question: dict | None = None

    # Le plan proposé par Holo. Rien ne bouge sur le PC tant que le proche ne
    # l'a pas validé : c'est la règle « jamais sans aval ».
    plan: list[str] | None = None
    plan_mode: str | None = None
    plan_sites: list[str] = field(default_factory=list)
    web_steps: list[int] = field(default_factory=list)
    plan_approved: bool = False
    linkup_query: str = ""
    linkup_result: dict | None = None
    linkup_id: str = ""
    # Numéro (à partir de 1) de l'étape du plan validé en cours d'exécution.
    plan_step: int | None = None

    # Brouillon de fiche CareMemory, en attente de validation du proche.
    lesson: dict | None = None
    # Le ticket de cette demande (suivi par le support IT).
    ticket: str = ""
    journal: list[dict] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    last_activity: float = field(default_factory=time.time)

    # Posé par le proche, lu par la boucle entre deux étapes : on ne coupe
    # jamais une action en cours, on refuse la suivante.
    pause_requested: bool = False
    # Le prénom de l'aidant qui a validé le plan : l’utilisateur lit
    # « Quentin s'en occupe » plutôt que le nom de l'agent.
    helper_name: str = ""
    # Une seule phrase pour l'aidant : ce que Holo est en train de faire.
    doing: str = ""

    # Pause demandée par l’utilisateur depuis son écran : Holo n'agit plus,
    # elle reprend la main sur sa souris et son clavier, jusqu'à « Reprendre ».
    paused: bool = False

    # Consommation du modèle. Le contexte du dernier appel est le chiffre qui
    # compte : le free tier plafonne à 65k tokens, et trois captures pèsent.
    usage: dict = field(
        default_factory=lambda: {
            "calls": 0, "total": 0, "prompt": 0, "completion": 0,
            "last_prompt": 0, "last_completion": 0,
        }
    )

    # Rempli par le proche, attendu par la boucle agent.
    _helper_reply: asyncio.Future | None = field(default=None, repr=False)
    _plan_decision: asyncio.Future | None = field(default=None, repr=False)

    # ---------------------------------------------------------------- journal

    def log(self, kind: str, **data) -> dict:
        entry = {"t": round(time.time() - self.created_at, 2), "kind": kind, **data}
        self.journal.append(entry)
        self.last_activity = time.time()
        return entry

    # ------------------------------------------------------------ cycle de vie

    @property
    def is_open(self) -> bool:
        return self.state in OPEN_STATES and not self.expired

    @property
    def expired(self) -> bool:
        return time.time() - self.last_activity > INACTIVITY_TIMEOUT_S

    def require_open(self) -> None:
        if self.state in TERMINAL_STATES:
            raise Refused("Cette assistance est terminée.")
        if self.expired:
            self.state = State.STOPPED
            raise Refused("Cette assistance a expiré.")

    def grant_consent(self) -> None:
        self.require_open()
        self.consented = True
        # Le partage d'écran est accordé, mais l'agent n'a pas encore la main :
        # il doit d'abord faire valider un plan par le proche.
        self.state = State.PLANNING
        self.owner = Owner.NONE
        self.log("consent", granted=True)

    def stop(self, by: str = "senior") -> None:
        """Terminal et irréversible. Aucune reprise n'est prévue : on rouvre
        une session, ce qui redemande le consentement."""
        if self.state in TERMINAL_STATES:
            return
        self.state = State.STOPPED
        self.owner = Owner.NONE
        self.stopped_by = by
        self.log("stop", by=by)
        self._resolve_reply(None)
        self._resolve_plan(None)

    def finish(self, message: str) -> None:
        self.require_open()
        self.state = State.DONE
        self.owner = Owner.NONE
        self.log("answer", content=message)
        self._resolve_reply(None)

    # ------------------------------------------------------------ verrou

    def take_control(self, owner: Owner) -> None:
        """Changement de propriétaire explicite. L'agent et le proche ne
        peuvent jamais agir en même temps."""
        self.require_open()
        if self.owner not in (Owner.NONE, owner):
            raise Refused(f"Le contrôle est actuellement détenu par : {self.owner.value}.")
        self.owner = owner

    def release_control(self) -> None:
        self.owner = Owner.NONE

    # ------------------------------------------------------------ captures

    MAX_KEPT_FRAMES = 12

    def set_frame(self, frame: Frame) -> None:
        self.last_frame = frame
        self.last_activity = time.time()
        self.frames[frame.frame_id] = frame.png_b64
        if len(self.frames) > self.MAX_KEPT_FRAMES:
            self.frames.pop(next(iter(self.frames)))

    def validate_click(self, frame_id: str) -> Frame:
        """Un clic du proche ne vaut que sur la dernière capture, et récente.

        C'est ce contrôle qui rend inoffensif un bouton resté cliquable dans un
        historique de conversation.
        """
        self.require_open()
        if not self.consented:
            raise Refused("Le partage d'écran n'a pas été autorisé.")
        if self.last_frame is None:
            raise Refused("Aucune capture disponible.")
        if frame_id != self.last_frame.frame_id:
            raise Refused("Cette capture n'est plus à jour. Attendez la suivante.")
        if self.last_frame.age > FRAME_TTL_S:
            raise Refused("Cette capture est trop ancienne pour servir de repère.")
        return self.last_frame

    # ------------------------------------------------------------ escalade

    def ask_helper(self, question: str, options: list[str] | None = None,
                   to: str = "helper") -> asyncio.Future:
        """`to` : « helper » (le proche) ou « senior » (l’utilisateur, pour ce
        qu'elle seule sait). Les deux peuvent répondre ; la première réponse compte."""
        self.require_open()
        self.state = State.AWAITING_HELPER
        self.owner = Owner.NONE
        to = "senior" if to == "senior" else "helper"
        self.question = {"question": question, "options": options or [], "to": to}
        self.log("ask_senior" if to == "senior" else "ask_helper", question=question, options=options or [])
        self._helper_reply = asyncio.get_running_loop().create_future()
        return self._helper_reply

    def answer_from_helper(self, text: str) -> None:
        self.require_open()
        if self.state is not State.AWAITING_HELPER:
            raise Refused("L'agent n'attend aucune réponse pour le moment.")
        self.log("helper_reply", text=text)
        self.question = None
        self.state = State.ACTIVE
        self.owner = Owner.AGENT
        self._resolve_reply(text)

    def _resolve_reply(self, value) -> None:
        fut, self._helper_reply = self._helper_reply, None
        if fut is not None and not fut.done():
            fut.set_result(value)

    # ------------------------------------------------------------ plan

    def propose_plan(self, steps: list[str]) -> asyncio.Future:
        """Le plan part chez le proche. L'agent attend sa décision, les mains libres."""
        self.require_open()
        self.plan = steps
        self.plan_approved = False
        self.plan_step = None
        self.state = State.AWAITING_APPROVAL
        self.owner = Owner.NONE
        self.log("plan_proposed", steps=steps)
        self._plan_decision = asyncio.get_running_loop().create_future()
        return self._plan_decision

    def preapprove_plan(self, steps: list[str], by: str) -> None:
        """Automate importé : le support a validé le plan à l'import.
        La personne le lance seule ; Arrêter et les garde-fous restent les mêmes."""
        self.require_open()
        if not self.consented:
            raise Refused("Partage d'écran non accordé.")
        self.plan = steps
        self.plan_approved = True
        self.plan_step = 1 if steps else None
        self.state = State.ACTIVE
        self.owner = Owner.AGENT
        self.log("plan_preapproved", by=by, steps=steps)

    def decide_plan(self, decision: str, note: str = "") -> None:
        """approve, refine (avec une précision) ou refuse. Revalidé côté serveur."""
        self.require_open()
        if self.state is not State.AWAITING_APPROVAL or self.linkup_query:
            raise Refused("Aucun plan n'attend votre validation.")
        if decision not in ("approve", "refine", "refuse"):
            raise Refused("Décision inconnue.")
        if decision == "refine" and not note:
            raise Refused("Écrivez la précision à donner à Holo.")
        self.log("plan_decision", decision=decision, note=note)
        if decision == "approve":
            self.plan_approved = True
            self.plan_step = 1 if self.plan else None
            self.state = State.ACTIVE
            self.owner = Owner.AGENT
        elif decision == "refine":
            self.state = State.PLANNING
        self._resolve_plan((decision, note))

    def advance_plan(self, step) -> bool:
        """Holo annonce l'étape du plan qu'il exécute. Jamais en arrière,
        jamais hors du plan. True si l'étape affichée a changé."""
        if not self.plan_approved or not self.plan or isinstance(step, bool):
            return False
        try:
            n = int(step)
        except (TypeError, ValueError):
            return False
        n = min(max(n, 1), len(self.plan))
        if self.plan_step is not None and n <= self.plan_step:
            return False
        self.plan_step = n
        self.log("plan_step", step=n)
        return True

    def _resolve_plan(self, value) -> None:
        fut, self._plan_decision = self._plan_decision, None
        if fut is not None and not fut.done():
            fut.set_result(value)

    # ------------------------------------------------------------ vue publique

    def record_usage(self, usage) -> dict:
        """Cumule la consommation d'un appel au modèle."""
        if usage is None:
            return self.usage
        p = getattr(usage, "prompt_tokens", 0) or 0
        c = getattr(usage, "completion_tokens", 0) or 0
        self.usage["calls"] += 1
        self.usage["last_prompt"] = p
        self.usage["last_completion"] = c
        self.usage["prompt"] += p
        self.usage["completion"] += c
        self.usage["total"] += getattr(usage, "total_tokens", 0) or (p + c)
        return self.usage

    def status(self) -> dict:
        return {
            "type": "status",
            "session": self.id,
            "state": self.state.value,
            "stopped_by": self.stopped_by,
            "execution_started": self.execution_started,
            "guard_acknowledged": self.guard_acknowledged,
            "owner": self.owner.value,
            "consented": self.consented,
            "task": self.task,
            "question": self.question,
            "plan": self.plan,
            "plan_approved": self.plan_approved,
            "paused": self.paused,
            "helper_name": self.helper_name or None,
            "doing": self.doing or None,
            "where": self.where,
            "plan_step": self.plan_step
            if self.plan_approved and self.state in (State.ACTIVE, State.AWAITING_HELPER)
            else None,
            "usage": self.usage,
        }


class Registry:
    """Les sessions vivantes. Une seule à la fois dans le MVP, mais la clé
    d'accès est déjà un jeton, pas un identifiant devinable."""

    def __init__(self) -> None:
        self._by_id: dict[str, Session] = {}
        self._by_token: dict[str, str] = {}

    def create(self, task: str) -> Session:
        for old in list(self._by_id.values()):
            if old.is_open:
                old.stop(by="nouvelle session")
        sid = secrets.token_hex(4)
        s = Session(id=sid, task=task)
        self._by_id[sid] = s
        self._by_token[s.helper_token] = sid
        s.log("created", task=task)
        return s

    def get(self, session_id: str) -> Session | None:
        return self._by_id.get(session_id)

    def by_token(self, token: str) -> Session:
        sid = self._by_token.get(token or "")
        if sid is None:
            raise Refused("Lien invalide.")
        return self._by_id[sid]
