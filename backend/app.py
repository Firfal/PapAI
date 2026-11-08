"""Backend PapAI : sessions, verrou de contrôle, relais vers le pont.

Deux WebSockets :
  /ws/bridge          le PC de l’utilisateur (capture et exécution)
  /ws/helper/{token}  la page du proche (captures, questions, clics)

Rien de ce que dit la page du proche n'est cru sur parole : chaque message
repasse par les contrôles de sessions.py.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import secrets
import time
from pathlib import Path
from urllib.parse import quote, urlsplit

import uvicorn
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse
from starlette.requests import HTTPConnection

from . import automate_draft, automations, guard, orgs as orgs_mod, space, ticket_stats, tickets as tickets_mod, voice
from .agent import AgentRunner, SensitiveBlocked, propose_plan, protected_window_support_text
from .web_agent import WebAgentRunner, valid_browser_session
from .family import CODE_TTL, INVITE_TTL, INVALID_CODE, Family, PairingError, clean_label
from .caremamory import lessons_dir, approve_and_save, draft_lesson, list_lessons
from .sessions import Frame, Owner, Refused, Registry, State

STATIC = Path(__file__).parent / "static"


def _lan_ip() -> str:
    """L'adresse de cette machine sur le réseau où elle est branchée.

    En démo locale, le téléphone du proche doit joindre ce serveur : un lien
    vers `localhost` ne veut rien dire pour lui. L'IP change à chaque réseau
    (Wi-Fi du lieu, partage de connexion du téléphone), donc on la relit au
    démarrage plutôt que de la figer dans un fichier qu'on oubliera.
    """
    import socket

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))  # n'envoie rien : choisit juste l'interface
        return s.getsockname()[0]
    except OSError:
        return "localhost"
    finally:
        s.close()


# En production, PAPAI_PUBLIC_URL porte l'URL publique du service hébergé
# (CAREPILOT_PUBLIC_URL : ancien nom, encore lu pour les déploiements existants).
PUBLIC_URL = os.environ.get("PAPAI_PUBLIC_URL") or os.environ.get("CAREPILOT_PUBLIC_URL") or f"http://{_lan_ip()}:{os.environ.get('PORT', '8000')}"

app = FastAPI(title="PapAI")

# Clé du lien permanent de l'aidant (app iPhone ou page /a/{clé}). Stable d'un
# lancement à l'autre si on la fixe dans .env, sinon tirée au démarrage.
AIDANT_KEY = os.environ.get("PAPAI_AIDANT_KEY") or secrets.token_urlsafe(9)
spaces = space.setup(AIDANT_KEY)
orgs = orgs_mod.Orgs()


def S() -> space.Space:
    """L'espace de la requête en cours (voir space.py)."""
    return space.current()

# Tout passe par /k/{clé de la famille}/… : sans la clé, personne ne peut se
# faire passer pour le PC de l’utilisateur, ni lire ses fiches. En local
# (PAPAI_PUBLIC absent), les routes sans clé ne répondent qu'à une app lancée
# sur la machine même du serveur (voir _same_machine).
PUBLIC_MODE = os.environ.get("PAPAI_PUBLIC", "") == "1"

# Bornes des messages du pont : une demande se lit en une phrase, et la liste
# des processus d'un PC chargé tient largement dans 500 noms.
MAX_TASK = 500
MAX_PROCESSES = 500
MAX_PROCESS_NAME = 200
WEB_AGENT_START_TIMEOUT_S = 20.0


def _key_ok(fam: str) -> bool:
    """Vrai si la clé ouvre un espace ; cet espace devient celui de la requête."""
    sp = spaces.get(fam)
    if sp is None:
        return False
    space.use(sp)
    return True


_LOOPBACK = {"127.0.0.1", "::1", "localhost"}


def _hostname(value: str) -> str:
    """`http://localhost:8000/x` ou `[::1]:8000` → `localhost`, `::1`."""
    v = (value or "").strip().lower()
    if "://" in v:
        v = v.split("://", 1)[1]
    v = v.split("/", 1)[0]
    if v.startswith("["):
        return v[1:].split("]", 1)[0]
    return v.rsplit(":", 1)[0] if v.count(":") == 1 else v


def _same_machine(conn: HTTPConnection) -> bool:
    """Vrai seulement pour une app lancée sur la machine du serveur.

    C'est le cas de la démo locale (Mac et serveur sur le même ordinateur) :
    l'app s'y connecte sans clé. Tout le reste — un autre appareil du même
    Wi-Fi, un tunnel (en-têtes de relais), une page web ouverte dans le
    navigateur (Origin, Host d'un autre site) — doit passer par /k/{clé}/….
    """
    if PUBLIC_MODE:
        return False
    if (conn.client.host if conn.client else "") not in _LOOPBACK:
        return False
    h = conn.headers
    if any(k in h for k in ("x-forwarded-for", "forwarded", "x-real-ip")):
        return False
    if _hostname(h.get("host", "")) not in _LOOPBACK:
        return False
    origin = h.get("origin")
    return not origin or _hostname(origin) in _LOOPBACK


# Jamais de clé ni de jeton dans les journaux : les chemins qui en portent un
# sont masqués, y compris dans les journaux d'accès d'uvicorn.
_SECRET_PATH = re.compile(r"/(k|a|h|p|i|o|ws/aidant|ws/helper)/[^/?#\s\"']+")


def masquer(texte: str) -> str:
    return _SECRET_PATH.sub(r"/\1/***", texte)


class _MasqueJournal(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        msg = record.getMessage()
        propre = masquer(msg)
        if propre != msg:
            record.msg, record.args = propre, ()
        return True


for _nom in ("uvicorn.access", "uvicorn.error"):
    logging.getLogger(_nom).addFilter(_MasqueJournal())


class BridgeLink:
    """Le pont Windows, vu du serveur. Un seul à la fois dans le MVP."""

    def __init__(self, ws: WebSocket) -> None:
        self.ws = ws
        self._pending: dict[str, asyncio.Future] = {}
        self.connected = True
        self.os = "windows"  # annoncé par le pont dans son message hello
        self.web_agent_available = False
        # Protection en temps réel, annoncée par l'app (None : app qui ne la connaît pas).
        self.protection: bool | None = None
        # Identifiant du navigateur servi par `holo local browser` sur la machine
        # de l’utilisateur, s'il tourne (PROTOCOL.md, agent navigateur).
        self.web_agent: str | None = None
        self._web_agent_waiter: asyncio.Future[str] | None = None
        self.active_web_session: Session | None = None
        self.active_web_browser_session: str | None = None

    async def close(self, code: int = 1000) -> None:
        try:
            await self.ws.close(code=code)
        except Exception:  # noqa: BLE001 — déjà fermé
            pass

    def disconnect(self) -> None:
        self.connected = False
        for fut in self._pending.values():
            if not fut.done():
                fut.set_result(None)

    async def _request(self, payload: dict, timeout: float = 20.0, *, req: str | None = None):
        req = req or secrets.token_hex(6)
        fut = asyncio.get_running_loop().create_future()
        self._pending[req] = fut
        try:
            await self.ws.send_json({**payload, "req": req})
            return await asyncio.wait_for(fut, timeout)
        except asyncio.TimeoutError:
            return None
        except (WebSocketDisconnect, RuntimeError, OSError):
            self.disconnect()
            return None
        finally:
            self._pending.pop(req, None)

    def resolve(self, req: str, value) -> None:
        fut = self._pending.get(req)
        if fut is not None and not fut.done():
            fut.set_result(value)

    async def capture(self) -> Frame | None:
        data = await self._request({"type": "capture"})
        if not data or "png_b64" not in data:
            return None
        return Frame(
            frame_id=data["frame_id"],
            png_b64=data["png_b64"],
            width=data["width"],
            height=data["height"],
        )

    async def execute(self, name: str, args: dict) -> str | None:
        if S().pending_alert:
            return None
        data = await self._request({"type": "execute", "action": {"name": name, "args": args}})
        if data is None:
            return None
        if data.get("refused"):
            return None  # le pont a refusé : arrêt local, la session s'arrête
        if data.get("blocked") == "sensitive":
            return SensitiveBlocked(data.get("result", ""))
        return data.get("result", "")

    async def send(self, payload: dict) -> None:
        try:
            await self.ws.send_json(payload)
        except Exception:  # noqa: BLE001 — pont déconnecté
            pass

    def receive_web_agent(self, value) -> str | None:
        waiter = self._web_agent_waiter
        if waiter is None and self.active_web_session is None:
            self.web_agent = None
            return None
        self.web_agent = valid_browser_session(value)
        if self.web_agent and waiter is not None and not waiter.done():
            waiter.set_result(self.web_agent)
        return self.web_agent

    async def stop_web_agent(self) -> None:
        waiter = self._web_agent_waiter
        self._web_agent_waiter = None
        self.web_agent = None
        if waiter is not None and not waiter.done():
            waiter.cancel()
        await self.send({"type": "web_agent_stop"})

    async def start_web_agent(self) -> str | None:
        self.web_agent = None
        waiter = asyncio.get_running_loop().create_future()
        self._web_agent_waiter = waiter
        try:
            await self.send({"type": "web_agent_start"})
            return await asyncio.wait_for(waiter, WEB_AGENT_START_TIMEOUT_S)
        except asyncio.TimeoutError:
            await self.stop_web_agent()
            return None
        except asyncio.CancelledError:
            await asyncio.shield(self.stop_web_agent())
            raise
        finally:
            if self._web_agent_waiter is waiter:
                self._web_agent_waiter = None
            if not waiter.done():
                waiter.cancel()




# Ce que l’utilisateur doit aussi voir : l'état de la session, le plan en
# attente, la réponse finale. Jamais les captures, qu'elle a sous les yeux.
BRIDGE_TYPES = {"status", "answer", "alert", "alert_cleared", "alert_acknowledged"}


# Qui est derrière chaque app d'aidant ouverte : son prénom et son identifiant.


def _online_ids() -> set[str]:
    return {w["id"] for w in S().helper_who.values() if w.get("id")}


async def _send_helpers_to_bridge() -> None:
    if S().bridge is not None:
        try:
            await S().bridge.send({"type": "helpers", "helpers": S().family.public(_online_ids())})
        except Exception:  # noqa: BLE001
            pass


# --- Tickets : chaque demande laisse une trace, et attend un support si besoin ---

OFFER_AGAIN_S = 600
RDV_TICK_S = float(os.environ.get("PAPAI_RDV_TICK_S", "20"))
RDV_MIN_S = float(os.environ.get("PAPAI_RDV_MIN_S", "60"))
_bg_tasks: set = set()


def _support_expected() -> bool:
    """Quelqu'un peut répondre à cette personne : un support connu ou une organisation."""
    return bool(S().family.helpers) or bool(getattr(S(), "org", None))


def _is_support(ws) -> bool:
    """Socket d'un support de l'espace (pas un lien de session, limité à sa session)."""
    return ws in S().helper_alert_scopes and S().helper_alert_scopes[ws] is None


def _support_available() -> bool:
    return any(_is_support(ws) for ws in S().helper_sockets)


SUPPORT_ONLY = ("ticket_due", "tickets_changed")


def _rdv_at(v) -> int | None:
    """Un rendez-vous : un instant (secondes Unix) entre 1 min (par défaut) et 30 jours d'ici."""
    try:
        at = float(v)
    except (TypeError, ValueError):
        return None
    now = time.time()
    return int(at) if now + RDV_MIN_S <= at <= now + tickets_mod.RDV_MAX_S else None


def _open_ticket(task: str, source: str, status: str = "nouveau", by: str = "") -> dict:
    o = orgs.get(S().org) if getattr(S(), "org", "") else None
    t = S().tickets.open(task, source, status=status, by=by, number=o.next_ticket() if o else None)
    if t.get("category_by") == "doute" and task.strip():
        _later(_holo_category(S(), t))
    return t


async def _holo_category(sp, t: dict) -> None:
    """Les règles hésitent : Holo choisit dans la liste, sans repasser sur le choix du support."""
    cat = await ticket_stats.classify_holo(t.get("task", ""))
    if cat is None:
        return
    space.use(sp)
    if sp.tickets.categorize(t, cat, "holo"):
        await _tickets_changed()


async def _tickets_changed() -> None:
    await broadcast_helper({"type": "tickets_changed"}, to_bridge=False)


async def _sync_ticket(st: dict) -> None:
    s = S().registry.get(str(st.get("session", "")))
    t = S().tickets.get(s.ticket) if s is not None and s.ticket else None
    if t is None or t["status"] == "resolu" and t.get("closed_by"):
        return
    before = t["status"]
    if S().tickets.sync(t, st) and t["status"] != before:
        await _tickets_changed()
        if t["status"] in ("resolu", "a_reprendre"):
            _later(_offer_next(space.current()))


async def _offer_waiting(who: str = "") -> bool:
    """Un support est là (ou c'est l'heure du rendez-vous) : on repropose la
    demande en attente à l’utilisateur, qui accepte ou non."""
    if S().bridge is None:
        return False
    s = current_session()
    if s is not None and s.is_open:
        return False
    now = time.time()
    due = S().tickets.due(now)
    waiting = [t for t in S().tickets.waiting() if now - t.get("offered", 0) > OFFER_AGAIN_S]
    if not due and not waiting:
        return False
    t = (due or waiting)[0]
    rdv = bool(due)
    # Rendez-vous sans support en ligne : le prochain support qui arrive le repropose.
    offered = int(now) if not rdv or _support_available() else 0
    S().tickets.update(t, offered=offered, **({"rdv_notified": True, "status": "en_attente"} if rdv else {}))
    names = [h["name"] for h in S().family.helpers]
    who = who or t.get("assignee") or (names[0] if len(names) == 1 else "Votre support")
    await S().bridge.send({"type": "remote_request", "from": who, "task": t["task"],
                           "ticket": t["id"], "number": t["number"], "rdv": rdv})
    if rdv:
        await broadcast_helper({"type": "ticket_due", "ticket": t["id"], "number": t["number"],
                                "task": t["task"]}, to_bridge=False)
    await _tickets_changed()
    print(f"[tickets] demande n° {t['number']} reproposée")
    return True


async def _offer_soon(sp, ws) -> None:
    # La page du support ne se présente pas toujours (helper_hello) : on lui
    # laisse un instant, puis on repropose ce qui attend.
    await asyncio.sleep(1.5)
    space.use(sp)
    if ws in sp.helper_sockets:
        await _offer_waiting(sp.helper_who.get(ws, {}).get("name", ""))


async def _offer_next(sp) -> None:
    # Une demande vient d'être refusée ou finie : la suivante en attente est proposée.
    await asyncio.sleep(2)
    space.use(sp)
    if _support_available():
        await _offer_waiting("")


def _later(coro) -> None:
    task = asyncio.create_task(coro)
    _bg_tasks.add(task)
    task.add_done_callback(_bg_tasks.discard)


async def _rdv_loop() -> None:
    while True:
        await asyncio.sleep(RDV_TICK_S)
        for sp in spaces.all():
            try:
                if sp.bridge is None or not sp.tickets.due():
                    continue
                space.use(sp)
                await _offer_waiting("")
            except Exception as e:  # noqa: BLE001
                print(f"[tickets] rendez-vous : {type(e).__name__}")


@app.on_event("startup")
async def _start_rdv_loop() -> None:
    _later(_rdv_loop())


def helper_can_access_alert(ws: WebSocket, alert: dict) -> bool:
    if ws not in S().helper_alert_scopes:
        return False
    scope = S().helper_alert_scopes[ws]
    return scope is None or scope == alert.get("session")


async def broadcast_helper(payload: dict, *, to_bridge: bool = True) -> None:
    if payload.get("type") == "status":
        await _sync_ticket(payload)
    if to_bridge and S().bridge is not None and payload.get("type") in BRIDGE_TYPES:
        await S().bridge.send(payload)
    dead = []
    for ws in S().helper_sockets:
        scoped = payload.get("type") == "guard_advice" or (payload.get("type") in ("alert", "alert_cleared", "alert_acknowledged") and payload.get("alert_id"))
        if scoped and not helper_can_access_alert(ws, payload):
            continue
        if payload.get("type") in SUPPORT_ONLY and not _is_support(ws):
            continue
        try:
            await ws.send_json(payload)
        except Exception:  # noqa: BLE001
            dead.append(ws)
    for ws in dead:
        S().helper_sockets.discard(ws)


async def handle_web_agent_change(link: BridgeLink, value) -> None:
    browser = link.receive_web_agent(value)
    session = link.active_web_session
    if (session is None or not session.is_open or session.where != "web"
            or link.active_web_browser_session is None
            or browser == link.active_web_browser_session):
        return
    session.stop(by="navigateur")
    session.doing = "Le navigateur PapAI s'est fermé : l'aide est arrêtée."
    if S().agent_task and not S().agent_task.done():
        S().agent_task.cancel()
    await broadcast_helper(session.status())


# ------------------------------------------------------------------ pont


@app.websocket("/k/{fam}/ws/bridge")
async def ws_bridge_keyed(ws: WebSocket, fam: str) -> None:
    if not _key_ok(fam):
        # Clé inconnue mais bien formée : l'ordinateur revient après un
        # redéploiement qui a effacé le disque. Il retrouve un espace à sa clé.
        if not (space.KEY_RE.match(fam or "") and _rate_ok(_space_creations, _client_ip(ws), SPACES_PER_HOUR, 3600)):
            await ws.close(code=4403)
            return
        space.use(spaces.create(fam))
    await _ws_bridge(ws)


@app.websocket("/ws/bridge")
async def ws_bridge(ws: WebSocket) -> None:
    # Sans clé : seulement depuis la machine du serveur (démo locale).
    if not _same_machine(ws):
        await ws.close(code=4403)
        return
    await _ws_bridge(ws)


async def _stop_open_sessions(by: str) -> None:
    for s in list(S().registry._by_id.values()):
        if s.is_open:
            s.stop(by=by)
            await broadcast_helper(s.status())


async def _ws_bridge(ws: WebSocket) -> None:
    await ws.accept()
    link = BridgeLink(ws)
    old, S().bridge = S().bridge, link
    if old is not None:
        old.disconnect()
        # Un seul pont. Le nouveau a passé le même contrôle que l'ancien :
        # c'est en général le même Mac qui se reconnecte après une coupure.
        # La session de l'ancien lien ne peut plus agir : on l'arrête.
        print("[pont] remplacé par une nouvelle connexion")
        if S().agent_task and not S().agent_task.done():
            S().agent_task.cancel()
        await _stop_open_sessions("pont remplacé")
        await old.close(code=4409)
    print("[pont] connecté")
    try:
        while True:
            msg = await ws.receive_json()
            if not isinstance(msg, dict):
                continue
            kind = msg.get("type")

            if kind in ("frame", "result", "pair_decision"):
                link.resolve(str(msg.get("req", "")), msg)
                continue

            if kind in ("hello", "profile"):
                if kind == "hello":
                    link.os = str(msg.get("os", "windows")).lower()[:20]
                    link.web_agent_available = msg.get("web_agent_available") is True
                    link.web_agent = None
                    print(f"[pont] système : {link.os}, navigateur : {'disponible' if link.web_agent_available else 'non'}")
                if isinstance(msg.get("protection"), bool) and msg["protection"] != link.protection:
                    link.protection = msg["protection"]
                    print(f"[pont] protection en temps réel : {'activée' if link.protection else 'coupée'}")
                    await broadcast_helper({"type": "protection", "on": link.protection})
                # Le prénom saisi sur l'ordinateur, transmis aux aidants.
                if S().family.set_senior(str(msg.get("name", ""))):
                    await broadcast_helper({"type": "senior", "name": S().family.senior})
                # Les proches que l'ordinateur connaît : la liste survit aux redémarrages.
                if isinstance(msg.get("known_helpers"), list) and S().family.restore(msg["known_helpers"]):
                    await ws.send_json({"type": "helpers", "helpers": S().family.public(_online_ids())})
                if kind == "profile":
                    continue
                await ws.send_json({"type": "helpers", "helpers": S().family.public(_online_ids())})
                if S().pending_alert:
                    await ws.send_json(S().pending_alert["senior"])
                if _support_available():
                    await _offer_waiting("")
                continue

            if kind == "pair_start":
                # Ajout d'un proche : un code à 6 chiffres et son lien (QR).
                # `long` : invitation à envoyer par SMS ou WhatsApp, valable 24 h.
                invitation = bool(msg.get("long"))
                value = S().family.new_invitation() if invitation else spaces.new_code(S())
                await ws.send_json({"type": "pair_code", "code": None if invitation else value,
                                    "url": pairing_url(value, invitation=invitation),
                                    "app_url": app_pairing_url(value, invitation=invitation),
                                    "expires_in": INVITE_TTL if invitation else CODE_TTL,
                                    "long": invitation})
                continue

            if kind == "remove_helper":
                S().family.remove(str(msg.get("id", "")))
                await ws.send_json({"type": "helpers", "helpers": S().family.public(_online_ids())})
                continue

            if kind == "remote_answer":
                # Réponse de l’utilisateur à une session proposée par un proche.
                if not msg.get("accepted"):
                    t = S().tickets.get(str(msg.get("ticket") or ""))
                    if t is not None:
                        S().tickets.note(t, S().family.senior or "L’utilisateur", "Pas disponible pour l'instant.")
                        await _tickets_changed()
                        _later(_offer_next(space.current()))
                    await broadcast_helper({"type": "remote_refused"})
                    print("[pont] session à distance refusée")
                continue

            if kind == "ticket_schedule":
                # La personne fixe un rendez-vous pour sa demande en attente.
                t = S().tickets.get(str(msg.get("ticket") or ""))
                at = _rdv_at(msg.get("at"))
                if t is None or at is None or t["status"] not in ("nouveau", "en_attente", "rdv", "a_reprendre"):
                    await ws.send_json({"type": "ticket_refused", "ticket": str(msg.get("ticket") or "")[:40],
                                        "reason": "Ce rendez-vous n'est pas possible."})
                    continue
                S().tickets.update(t, status="rdv", rdv=at, rdv_notified=False)
                await ws.send_json({"type": "ticket_scheduled", "ticket": t["id"], "number": t["number"], "at": at})
                await _tickets_changed()
                continue

            if kind == "help_request":
                task = str(msg.get("task") or "").strip()[:MAX_TASK]
                by = str(msg.get("requested_by") or "")[:40]
                ticket = S().tickets.get(str(msg.get("ticket") or ""))
                if ticket is not None and ticket["status"] == "resolu":
                    ticket = None
                if ticket is None and not by and _support_expected() and not _support_available():
                    # Aucun support disponible : la demande attend, la personne
                    # sera reprévenue dès qu'un support est là (ou au rendez-vous).
                    ticket = _open_ticket(task, "personne", status="en_attente", by=S().family.senior)
                    await ws.send_json({"type": "ticket_queued", "ticket": ticket["id"],
                                        "number": ticket["number"], "task": task})
                    await _tickets_changed()
                    print(f"[tickets] demande n° {ticket['number']} en attente d'un support")
                    continue
                session = S().registry.create(task)
                session.grant_consent()  # le consentement est donné dans la même fenêtre
                if msg.get("requested_by"):
                    # Lancée par un proche, acceptée à l'instant sur le Mac.
                    session.log("remote_accepted", by=str(msg["requested_by"])[:40])
                    await broadcast_helper({"type": "remote_accepted"})
                if ticket is None:
                    ticket = _open_ticket(task, "support" if by else "personne", by=by or S().family.senior)
                session.ticket = ticket["id"]
                S().tickets.update(ticket, session=session.id, status="en_cours", rdv=None)
                await _tickets_changed()
                url = f"{PUBLIC_URL}/h/{session.helper_token}"
                await ws.send_json({"type": "session", "id": session.id, "helper_url": url,
                                    "ticket": ticket["id"], "number": ticket["number"]})
                # Ni la demande ni le lien du proche (son jeton) dans le journal.
                print(f"[session {session.id}] nouvelle demande")
                await broadcast_helper(session.status())

                if S().agent_task and not S().agent_task.done():
                    S().agent_task.cancel()
                S().agent_task = asyncio.create_task(run_session(session, link))
                continue

            if kind == "run_automation":
                # Un automate importé, lancé en un clic : son plan a été
                # validé par le support à l'import, pas besoin d'un aidant en ligne.
                lesson = automations.load(str(msg.get("id", "")))
                task = automations.holo_task(lesson) if lesson else None
                if task is None or _os_family(link.os) not in lesson.get("platforms", []):
                    await ws.send_json({"type": "automation_refused", "id": str(msg.get("id", ""))[:40],
                                        "reason": "Cet automate n'est pas disponible sur cet ordinateur."})
                    continue
                goal, steps = task
                session = S().registry.create(goal[:MAX_TASK])
                session.grant_consent()
                session.preapprove_plan(steps, by=lesson.get("approved_by", ""))
                session.log("automation", id=lesson["id"], title=lesson.get("title", ""))
                ticket = _open_ticket(lesson.get("title") or goal[:MAX_TASK], "automatisme",
                                          status="en_cours", by=S().family.senior)
                session.ticket = ticket["id"]
                S().tickets.update(ticket, session=session.id)
                await _tickets_changed()
                url = f"{PUBLIC_URL}/h/{session.helper_token}"
                await ws.send_json({"type": "session", "id": session.id, "helper_url": url,
                                    "automation": lesson["id"]})
                print(f"[session {session.id}] automate importé {lesson['id']}")
                await broadcast_helper(session.status())
                if S().agent_task and not S().agent_task.done():
                    S().agent_task.cancel()
                S().agent_task = asyncio.create_task(run_automation(session, link))
                continue

            if kind == "automation_failed":
                # Un automate n'a pas pu se rejouer : l'écran ou le dossier a
                # changé. On ne tente rien à l'aveugle, on prévient l'aidant.
                await broadcast_helper({
                    "type": "alert",
                    "title": str(msg.get("title", "Un automate"))[:200],
                    "detail": str(msg.get("detail", ""))[:1000],
                }, to_bridge=False)
                continue

            if kind == "guard":
                if link.protection is False:
                    # Protection coupée sur l'ordinateur : rien ne doit être évalué.
                    continue
                # Le gardien du Mac a vu passer un signal. Il n'envoie que du
                # texte — processus, titre de fenêtre, adresse — jamais l'écran.
                # À part : pendant une session, la confirmation attend une
                # capture que cette boucle doit pouvoir recevoir.
                t = asyncio.create_task(handle_guard(msg))
                _guard_taches.add(t)
                t.add_done_callback(_guard_taches.discard)
                continue

            if kind == "web_agent":
                # Chrome PapAI et `holo local browser` viennent de démarrer ou de s'arrêter.
                await handle_web_agent_change(link, msg.get("session_id"))
                print(f"[pont] navigateur : {'oui' if link.web_agent else 'non'}")
                continue

            if kind in ("pause", "resume"):
                # L’utilisateur suspend ou reprend l'aide depuis son écran.
                s = current_session()
                if s is not None and s.is_open:
                    s.paused = kind == "pause"
                    s.log("senior_" + kind)
                    await broadcast_helper(s.status())
                continue

            if kind == "dictation":
                # Transcription en direct : l'aidant voit ce que la personne dit.
                await broadcast_helper({"type": "dictation",
                                        "text": str(msg.get("text", ""))[:300],
                                        "final": bool(msg.get("final"))})
                continue

            if kind == "senior_answer":
                # L’utilisateur répond à une question de Holo qui lui était posée.
                s = current_session()
                text = str(msg.get("text", "")).strip()[:300]
                if s is not None and text and s.question and s.question.get("to") == "senior":
                    try:
                        s.log("senior_reply", text=text)
                        s.answer_from_helper(text)
                        await broadcast_helper(s.status())
                    except Refused:
                        pass
                continue

            if kind == "stop":
                for s in list(S().registry._by_id.values()):
                    if s.is_open:
                        s.stop(by="senior")
                        await broadcast_helper(s.status())
                if S().agent_task and not S().agent_task.done():
                    S().agent_task.cancel()
                print("[pont] ARRÊT demandé par l’utilisateur")
                continue

    except (WebSocketDisconnect, RuntimeError, ValueError):
        print("[pont] déconnecté")
    finally:
        link.disconnect()
        # Un nouveau pont a pu prendre la place entre-temps : on ne le
        # débranche pas, et ses sessions continuent.
        if S().bridge is link:
            S().bridge = None
            await _stop_open_sessions("pont déconnecté")
            if link.protection is not None:
                await broadcast_helper({"type": "protection", "on": None})


def _safe_handoff_log_text(text: str) -> str:
    value = re.sub(r"https?://\S+", "[URL masquée]", str(text or ""), flags=re.I)
    value = re.sub(r"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b", "[adresse masquée]", value)
    value = re.sub(r"\b[A-Z]{2}\d{2}(?:[\s-]?[A-Z0-9]){10,30}\b", "[IBAN masqué]", value, flags=re.I)
    value = re.sub(
        r"\b(?:mot de passe|mdp|password|pass|pin|cryptogramme|code(?: de sécurité)?|"
        r"iban|numéro de carte|identifiant|carte bancaire)\b[^.!?\n]*",
        "[donnée sensible masquée]", value, flags=re.I
    )
    value = re.sub(
        r"\b\d[\d\s.,]*\s*(?:euros?|eur|dollars?)\b",
        "[montant masqué]", value, flags=re.I
    )
    value = re.sub(r"\b\d[\d\s.,]*\s*[€$]", "[montant masqué]", value)
    value = re.sub(r"(?<!\w)\+?\d[\d\s().-]{5,}\d(?!\w)", "[numéro masqué]", value)
    return value[:240]


def _browser_site_allowed(url: str, sites: list[str]) -> bool:
    if not isinstance(url, str):
        return False
    try:
        parsed = urlsplit(url)
        host = (parsed.hostname or "").lower().rstrip(".")
        port = parsed.port
    except (TypeError, ValueError):
        return False
    return (
        parsed.scheme.lower() == "https"
        and parsed.username is None
        and parsed.password is None
        and bool(host)
        and (port is None or 1 <= port <= 65535)
        and not any(char.isspace() for char in url)
        and any(host == site or host.endswith("." + site) for site in sites)
    )


async def browser_handoff(session, link: BridgeLink, notes: list[str],
                          goal: str, url: str | None) -> str | None:
    if url is None and session.plan_sites:
        url = f"https://{session.plan_sites[0]}"
    if not url or not _browser_site_allowed(url, session.plan_sites):
        result = (
            "Ce site n'était pas dans le plan validé par le support. Continue sur le bureau, "
            "ou pose la question au support avec ask_helper."
        )
        session.log("browser_handoff", goal=_safe_handoff_log_text(goal), result=result)
        return result

    alerte = guard.evaluer([], "", url=url)
    if alerte:
        await publish_guard(alerte, "browser", session)
        session.log("browser_handoff", goal=_safe_handoff_log_text(goal),
                    result="bloquée par le Gardien")
        return None

    demande = goal + (f"\nURL de départ : {url}" if url else "")
    if await check_request(session, demande, "browser"):
        session.log("browser_handoff", goal=_safe_handoff_log_text(goal),
                    result=("bloquée par le Gardien" if session.stopped_by == "gardien"
                            else "session arrêtée"))
        return None

    try:
        browser = await link.start_web_agent()
    except asyncio.CancelledError:
        session.log("browser_handoff", goal=_safe_handoff_log_text(goal),
                    result="annulée pendant le démarrage")
        raise
    except Exception:
        await link.stop_web_agent()
        browser = None
    if not session.is_open:
        if browser is not None:
            await link.stop_web_agent()
        session.log("browser_handoff", goal=_safe_handoff_log_text(goal),
                    result="session arrêtée avant l'ouverture")
        return None
    if browser is None:
        result = "Le navigateur PapAI n'a pas démarré : continue sur le bureau."
        session.log("browser_handoff", goal=_safe_handoff_log_text(goal), result=result)
        return result

    session.where = "web"
    session.last_frame = None
    session.log("mode", where="web")
    link.active_web_session = session
    link.active_web_browser_session = browser
    result_log = "session arrêtée pendant la sous-tâche"
    try:
        await broadcast_helper(session.status())
        summary = await WebAgentRunner(
            session, browser, broadcast_helper, notes,
            goal=goal, url=url, finish_session=False,
        ).run()
        if not session.is_open or summary is None:
            return None
        result = f"Partie navigateur terminée : {summary}"
        result_log = _safe_handoff_log_text(result)
        return result
    finally:
        await asyncio.shield(link.stop_web_agent())
        if link.active_web_session is session:
            link.active_web_session = None
            link.active_web_browser_session = None
        if session.is_open and session.where == "web":
            session.where = "desktop"
            session.last_frame = None
            session.doing = "Holo reprend sur le bureau"
            session.log("mode", where="desktop")
            await asyncio.shield(broadcast_helper(session.status()))
        session.log("browser_handoff", goal=_safe_handoff_log_text(goal), result=result_log)


def _os_family(name: str) -> str:
    n = (name or "").lower()
    return "mac" if n.startswith(("mac", "darwin", "osx")) else "windows"


async def run_automation(session, link: "BridgeLink") -> None:
    """Plan déjà validé par le support : l'agent agit directement.

    Le gardien relit quand même l'objectif et les étapes : un fichier importé
    ne doit pas pouvoir faire ce qu'une demande libre ne ferait pas."""
    try:
        if S().pending_alert:
            session.stop(by="gardien")
            await broadcast_helper(session.status())
            await link.send(S().pending_alert["senior"])
            await broadcast_helper(S().pending_alert["helper"], to_bridge=False)
            return
        if await check_request(session, " ; ".join([session.task, *session.plan]), "plan"):
            return
        await broadcast_helper(session.status())
        await AgentRunner(session, link, broadcast_helper).run()
    except asyncio.CancelledError:
        session.stop(by="annulation")
        raise


async def run_session(session, link: "BridgeLink") -> None:
    """Plan d'abord, validé par l'aidant ; l'agent n'agit qu'ensuite."""
    notes: list[str] = []
    try:
        if S().pending_alert:
            session.stop(by="gardien")
            await broadcast_helper(session.status())
            await link.send(S().pending_alert["senior"])
            await broadcast_helper(S().pending_alert["helper"], to_bridge=False)
            return
        if await check_request(session, session.task, "request"):
            return
        while True:
            await broadcast_helper(session.status())
            steps = await propose_plan(session, link, broadcast_helper, " ; ".join(notes))
            if not session.is_open:
                return
            for site in session.plan_sites:
                alerte = guard.evaluer([], "", url=f"https://{site}")
                if alerte:
                    await publish_guard(alerte, "plan", session)
                    return
            plan_text = "\n".join([
                session.task, *notes, *steps,
                *(f"https://{site}" for site in session.plan_sites),
            ])
            if await check_request(session, plan_text, "plan"):
                return
            if not session.is_open:
                return
            decision = session.propose_plan(steps)
            await broadcast_helper(session.status())
            print(f"[session {session.id}] plan proposé : {len(steps)} étape(s)")
            result = await decision
            if result is None or not session.is_open:
                return
            kind, note = result
            if kind == "approve":
                break
            if kind == "refuse":
                session.stop(by="proche")
                await broadcast_helper(session.status())
                return
            notes.append(note)  # refine : on refait un plan avec la précision
        if session.where == "web":
            session.last_frame = None
        # Mode web seulement si Holo l'a proposé ET si l'ordinateur sert un navigateur.
        browser = None
        if session.where == "web" and link.web_agent_available:
            browser = await link.start_web_agent()
            if not session.is_open:
                if browser is not None:
                    await link.stop_web_agent()
                return
            if browser is None:
                session.log("web_agent_timeout")
        session.where = "web" if browser else "desktop"
        session.log("mode", where=session.where)
        if browser:
            link.active_web_session = session
            link.active_web_browser_session = browser
            try:
                await WebAgentRunner(session, browser, broadcast_helper, notes).run()
            finally:
                if link.active_web_session is session:
                    link.active_web_session = None
                    link.active_web_browser_session = None
        else:
            handoff = None
            if session.plan_mode == "mixed" and link.web_agent_available:
                async def handoff(goal, url):
                    return await browser_handoff(session, link, notes, goal, url)
            await AgentRunner(session, link, broadcast_helper, notes,
                              browser_handoff=handoff).run()
    except asyncio.CancelledError:
        session.stop(by="annulation")
        raise


# ------------------------------------------------------------------ proche


def _session_by_token(token: str):
    """Le jeton d'une session désigne aussi son espace."""
    for sp in spaces.all():
        try:
            session = sp.registry.by_token(token)
        except Refused:
            continue
        space.use(sp)
        return session
    return S().registry.by_token(token)  # lève le bon message


@app.get("/h/{token}")
async def helper_page(token: str):
    try:
        _session_by_token(token)
    except Refused as e:
        return JSONResponse({"error": str(e)}, status_code=404)
    return FileResponse(STATIC / "helper.html")


@app.websocket("/ws/helper/{token}")
async def ws_helper(ws: WebSocket, token: str) -> None:
    try:
        session = _session_by_token(token)
    except Refused as e:
        await ws.accept()
        await ws.send_json({"type": "refused", "reason": str(e)})
        await ws.close()
        return

    await ws.accept()
    S().helper_sockets.add(ws)
    S().helper_alert_scopes[ws] = session.id
    await ws.send_json(session.status())
    await ws.send_json({"type": "senior", "name": S().family.senior or None})
    if S().pending_alert and helper_can_access_alert(ws, S().pending_alert["helper"]):
        await ws.send_json(S().pending_alert["helper"])
    if session.last_frame:
        await ws.send_json(
            {
                "type": "frame",
                "frame_id": session.last_frame.frame_id,
                "png_b64": session.last_frame.png_b64,
            }
        )

    try:
        while True:
            msg = await ws.receive_json()
            await handle_helper_msg(session, msg, ws)
    except WebSocketDisconnect:
        pass
    finally:
        S().helper_sockets.discard(ws)
        S().helper_alert_scopes.pop(ws, None)


async def handle_helper_msg(session, msg: dict, ws: WebSocket) -> None:
    """Un message de l'aidant, page web ou app iPhone. Tout est revalidé ici."""
    kind = msg.get("type")
    if kind == "ack_alert":
        await acknowledge_guard(msg, ws)
        return
    if kind == "dismiss_alert":
        await dismiss_guard(msg, ws)
        return
    # Le jeton identifie la session, mais la session a pu se fermer
    # depuis que la page est ouverte : on revérifie avant toute action
    # sur le PC. Rédiger une fiche, en revanche, se fait APRÈS la
    # session — c'est même le seul moment où ça a un sens.
    if kind in ("answer", "pause", "click", "refresh"):
        try:
            session.require_open()
        except Refused as e:
            await ws.send_json({"type": "refused", "reason": str(e)})
            await ws.send_json(session.status())
            return

    try:
        who = S().helper_who.get(ws, {}).get("name", "")
        if who and kind in ("approve_plan", "answer", "click"):
            session.helper_name = who
        if kind in ("approve_plan", "refine_plan", "refuse_plan"):
            session.decide_plan(kind.split("_")[0], str(msg.get("text", "")).strip())
            await broadcast_helper(session.status())

        elif kind == "answer":
            session.answer_from_helper(str(msg.get("text", "")).strip())
            await broadcast_helper(session.status())

        elif kind == "pause":
            session.pause_requested = True
            session.log("helper_pause")
            await ws.send_json({"type": "ack", "what": "pause"})

        elif kind == "refresh":
            # Le proche demande une capture fraîche avant de viser.
            # Pendant `awaiting_helper` l'agent est suspendu : sans ça,
            # la dernière image date de son dernier pas et dépasse le
            # délai de fraîcheur avant même qu'il ait pu pointer.
            await handle_helper_refresh(session, ws)

        elif kind == "click":
            await handle_helper_click(session, msg, ws)

        elif kind == "draft_lesson":
            await ws.send_json({"type": "lesson_pending"})
            try:
                lesson = await draft_lesson(session, S().bridge.os if S().bridge else "windows")
            except Exception as e:  # noqa: BLE001 — l'aidant ne doit pas rester sans réponse
                session.log("lesson_failed", error=f"{type(e).__name__}: {e}")
                raise Refused("Holo n'a pas pu rédiger l'automate. Réessayez.") from e
            session.lesson = lesson
            # Aperçu : les captures voyagent avec le brouillon, mais
            # ne sont écrites nulle part tant que rien n'est validé.
            preview = {
                s["frame"]: session.frames.get(s["frame"], "")
                for s in lesson["steps"] if s.get("frame")
            }
            await ws.send_json(
                {"type": "lesson_draft", "lesson": lesson, "preview": preview}
            )

        elif kind == "approve_lesson":
            if not session.lesson:
                raise Refused("Aucun automate à valider.")
            # Le proche a pu corriger le texte : on reprend le sien.
            edited = msg.get("lesson") or {}
            if "shortcut" in edited and edited["shortcut"] is None:
                session.lesson["shortcut"] = None
            for i, step in enumerate(session.lesson["steps"]):
                if i < len(edited.get("steps", [])):
                    step["instruction"] = str(
                        edited["steps"][i].get("instruction", step["instruction"])
                    ).strip()
            session.lesson["title"] = str(
                edited.get("title", session.lesson["title"])
            ).strip()
            saved = approve_and_save(session.lesson, session)
            await ws.send_json({"type": "lesson_saved", "lesson": saved})
            if S().bridge is not None:
                # L’utilisateur le retrouve aussitôt dans « Mes automates ».
                await S().bridge.send({"type": "lessons_changed", "title": saved.get("title", "")})

        else:
            await ws.send_json({"type": "refused", "reason": "Message inconnu."})

    except Refused as e:
        await ws.send_json({"type": "refused", "reason": str(e)})



async def handle_helper_refresh(session, ws: WebSocket) -> None:
    """Une nouvelle capture, à la demande du proche.

    Ne touche à rien sur le PC : c'est une lecture d'écran, soumise aux mêmes
    conditions que le reste (session ouverte, partage autorisé).
    """
    if not session.consented:
        raise Refused("Le partage d'écran n'a pas été autorisé.")
    if session.where == "web":
        # Agent navigateur : aucune capture du bureau, la dernière image vient de H.
        frame = session.last_frame
        if frame is not None:
            await ws.send_json({"type": "frame", "frame_id": frame.frame_id, "png_b64": frame.png_b64})
        return
    if S().bridge is None:
        raise Refused("Le PC n'est pas connecté.")

    frame = await S().bridge.capture()
    if frame is None:
        raise Refused("Le PC n'a pas répondu.")

    session.set_frame(frame)
    await broadcast_helper(
        {"type": "frame", "frame_id": frame.frame_id, "png_b64": frame.png_b64}
    )


async def handle_helper_click(session, msg: dict, ws: WebSocket) -> None:
    """Un clic du proche sur la capture.

    Autorisé seulement quand l'agent est suspendu : deux acteurs ne pilotent
    jamais la souris en même temps.
    """
    if session.state is not State.AWAITING_HELPER:
        raise Refused("Mettez d'abord l'assistance en pause pour prendre la main.")
    if session.where == "web":
        # L'image vient du Chrome PapAI, pas du bureau : un clic ici tomberait ailleurs.
        raise Refused("Dans le navigateur, répondez à la question de Holo : la prise en main n'est pas possible.")

    session.validate_click(str(msg.get("frame_id", "")))

    x = float(msg.get("x", -1))
    y = float(msg.get("y", -1))
    if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
        raise Refused("Coordonnées hors de la capture.")

    if S().bridge is None:
        raise Refused("Le PC n'est pas connecté.")

    session.take_control(Owner.HELPER)
    args = {"element": "clic du support", "x": round(x * 1000), "y": round(y * 1000)}
    session.log("helper_click", x=args["x"], y=args["y"])
    session.execution_started = True
    result = await S().bridge.execute("click", args)
    session.release_control()

    if result is None:
        raise Refused("Le PC a refusé l'action.")
    if isinstance(result, SensitiveBlocked):
        session.log("sensitive_blocked", tool="click", source="helper", reason=result.reason)
        await ws.send_json({"type": "refused", "blocked": "sensitive", "reason": protected_window_support_text(click=True)})
        return

    await ws.send_json({"type": "ack", "what": "click", "result": result})
    session.answer_from_helper("J'ai cliqué moi-même sur l'écran. Reprends à partir de là.")
    await broadcast_helper(session.status())


# ------------------------------------------------------------------ proches


def pairing_url(code: str, *, invitation: bool = False) -> str:
    return f"{PUBLIC_URL}/{'i' if invitation else 'p'}/{code}"


def app_pairing_url(code: str, *, invitation: bool = False) -> str:
    """Le lien du QR : ouvre l'app iPhone, qui fait elle-même le POST sur `url`.

    `n` porte le prénom de l’utilisateur, pour que l'aidant lise « Rejoindre
    Sophie » avant même d'avoir validé.
    """
    link = "papai://pair?u=" + quote(pairing_url(code, invitation=invitation), safe="")
    if S().family.senior:
        link += "&n=" + quote(S().family.senior, safe="")
    return link


def aidant_url() -> str:
    return f"{PUBLIC_URL}/a/{S().key}"


async def _pair_page(code: str):
    return FileResponse(STATIC / "pair.html")


async def _pair_submit(code: str, request: Request, confirm: bool = False, *, find_space: bool = False,
                       invitation: bool = False):
    try:
        body = await request.json()
    except ValueError:
        body = {}
    if not isinstance(body, dict):
        body = {}
    name = clean_label(str(body.get("name") or ""), 40)
    relation = clean_label(str(body.get("relation") or ""), 60)
    if not name:
        return JSONResponse({"ok": False, "error": "Indiquez votre prénom."}, status_code=400)
    ip = _client_ip(request)
    if find_space and not _rate_ok(_global_wrong_codes, "all", GLOBAL_WRONG_CODES_MAX, 600, record=False):
        return JSONResponse({"ok": False, "error": INVALID_CODE}, status_code=400)
    if not _rate_ok(_wrong_codes, ip, WRONG_CODES_MAX, 600, record=False):
        return JSONResponse({"ok": False, "error": "Trop d'essais. Réessayez dans quelques minutes."}, status_code=429)
    sp = next((x for x in spaces.all() if
               (x.family.invitation_valid(code) if invitation else x.family.code_valid(code))), None) if find_space else S()
    try:
        if sp is None or sp.key in _pair_waiting:
            raise PairingError(INVALID_CODE)
        if not invitation:
            sp.family.check_code(code)
    except PairingError:
        _rate_ok(_wrong_codes, ip, WRONG_CODES_MAX, 600)
        if find_space:
            _rate_ok(_global_wrong_codes, "all", GLOBAL_WRONG_CODES_MAX, 600)
        return JSONResponse({"ok": False, "error": INVALID_CODE}, status_code=400)
    space.use(sp)
    link = sp.bridge
    try:
        if invitation:
            sp.family.consume_invitation(code)
        else:
            sp.family.consume_code(code)
    except PairingError:
        _rate_ok(_wrong_codes, ip, WRONG_CODES_MAX, 600)
        return JSONResponse({"ok": False, "error": INVALID_CODE}, status_code=400)
    if confirm and (link is None or not link.connected):
        return JSONResponse({"ok": False, "error": INVALID_CODE}, status_code=400)
    # En local, pas d'accord : parcours de développement uniquement.
    if confirm:
        _pair_waiting.add(sp.key)
        req = secrets.token_hex(6)
        decided = False
        try:
            answer = await link._request({"type": "pair_confirm", "name": name, "relation": relation},
                                         timeout=PAIR_CONFIRM_S, req=req)
            if sp.bridge is not link or not link.connected:
                return JSONResponse({"ok": False, "error": PAIR_OFFLINE}, status_code=409)
            if answer is None:
                return JSONResponse({"ok": False, "error": "Pas de réponse sur l'ordinateur. Demandez un nouveau code sur l'ordinateur de l’utilisateur."}, status_code=408)
            decided = True
            if not (isinstance(answer, dict) and answer.get("accept") is True):
                return JSONResponse({"ok": False, "refused": True, "error": "L’utilisateur a refusé. Rien n'a été partagé."}, status_code=403)
        finally:
            _pair_waiting.discard(sp.key)
            if not decided:
                await link.send({"type": "pair_confirm_closed", "req": req})
    await broadcast_helper({"type": "helper_added", "name": name}, to_bridge=False)
    helper = sp.family.add_helper(name, relation)
    print("[supports] un support ajouté")
    if S().bridge is not None:
        await S().bridge.send({"type": "helpers", "helpers": S().family.public(_online_ids()), "added": helper["name"]})
    return {"ok": True, "name": helper["name"], "id": helper["id"], "senior": S().family.senior or None,
            "aidant_url": aidant_url(),
            "server": PUBLIC_URL, "key": S().key}


PAIR_CONFIRM_S = float(os.environ.get("PAPAI_PAIR_CONFIRM_S", "120"))
PAIR_OFFLINE = "L'ordinateur de l’utilisateur n'est pas connecté. Allumez-le, ouvrez PapAI, puis réessayez."
_pair_waiting: set[str] = set()
WRONG_CODES_MAX = 10
GLOBAL_WRONG_CODES_MAX = 300
SPACES_PER_HOUR = 5
_wrong_codes: dict[str, list[float]] = {}
_global_wrong_codes: dict[str, list[float]] = {}
_space_creations: dict[str, list[float]] = {}
# Postes d'une même organisation (souvent derrière la même adresse IP) : plafond par organisation.
ORG_ENROLLS_PER_HOUR = int(os.environ.get("PAPAI_ORG_ENROLLS_PER_HOUR", "200"))
_org_enrolls: dict[str, list[float]] = {}


def _client_ip(request: HTTPConnection) -> str:
    if PUBLIC_MODE:  # derrière le proxy de Cloud Run
        fwd = request.headers.get("x-forwarded-for", "")
        if fwd:
            # Cloud Run ajoute la vraie adresse en dernier ; les valeurs
            # précédentes viennent du client et peuvent être inventées.
            return fwd.split(",")[-1].strip()
    return request.client.host if request.client else ""


def _rate_ok(book: dict[str, list[float]], who: str, limit: int, window: float, *, record: bool = True) -> bool:
    now = time.time()
    hits = [t for t in book.get(who, []) if now - t < window]
    ok = len(hits) < limit
    if ok and record:
        hits.append(now)
    if who not in book and len(book) >= 10_000:
        book.pop(next(iter(book)))
    book[who] = hits
    return ok


@app.get("/p")
async def pair_page_manual():
    return await _pair_page("")


@app.get("/k/{fam}/p")
async def pair_page_manual_keyed(fam: str):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return await _pair_page("")


@app.get("/p/{code}")
async def pair_page(code: str):
    return await _pair_page(code)


@app.post("/p/{code}")
async def pair_submit(code: str, request: Request):
    return await _pair_submit(code, request, confirm=PUBLIC_MODE, find_space=True)


@app.get("/i/{token}")
async def invitation_page(token: str):
    return await _pair_page(token)


@app.post("/i/{token}")
async def invitation_submit(token: str, request: Request):
    return await _pair_submit(token, request, confirm=PUBLIC_MODE, find_space=True, invitation=True)


# Création d'un espace : au premier lancement, l'ordinateur de l’utilisateur reçoit sa clé.
@app.post("/spaces")
async def create_space(request: Request):
    body = await _small_json(request)
    org = None
    if body.get("org"):
        # Poste d'entreprise : le jeton d'inscription le rattache à son organisation.
        org = orgs.by_enroll(str(body["org"]))
        if org is None:
            return JSONResponse({"error": "Jeton d'organisation inconnu."}, status_code=403)
        if not _rate_ok(_org_enrolls, org.id, ORG_ENROLLS_PER_HOUR, 3600):
            return JSONResponse({"error": "Trop d'inscriptions. Réessayez plus tard."}, status_code=429)
    elif not _rate_ok(_space_creations, _client_ip(request), SPACES_PER_HOUR, 3600):
        return JSONResponse({"error": "Trop de créations. Réessayez plus tard."}, status_code=429)
    sp = spaces.create(org=org.id if org else "", label=_label(body))
    if org is not None:
        org.copy_automations(sp.lessons_dir)
    print(f"[espaces] nouvel espace {sp.id}" + (f" (organisation {org.id})" if org else ""))
    ws_base = PUBLIC_URL.replace("https://", "wss://").replace("http://", "ws://")
    return {"key": sp.key, "server": PUBLIC_URL, "bridge_url": f"{ws_base}/k/{sp.key}/ws/bridge",
            **({"org": org.name} if org else {})}


# ------------------------------------------------------------------ organisations (service IT)

ORGS_PER_HOUR = 3
_org_creations: dict[str, list[float]] = {}


async def _small_json(request: Request, limit: int = 4096) -> dict:
    raw = await request.body()
    if not raw or len(raw) > limit:
        return {}
    try:
        d = json.loads(raw)
    except ValueError:
        return {}
    return d if isinstance(d, dict) else {}


def _label(body: dict) -> str:
    return re.sub(r"\s+", " ", str(body.get("name") or "")).strip()[:60]


def _org_links(o: orgs_mod.Org) -> dict:
    return {"support_url": f"{PUBLIC_URL}/o/{o.support}",
            "app_url": f"papai://org?u={quote(PUBLIC_URL, safe='')}&t={o.support}"}


@app.post("/orgs")
async def create_org(request: Request):
    """Le service IT crée son organisation : un jeton pour les postes, un pour les supports."""
    body = await _small_json(request)
    name = _label(body)
    if not name:
        return JSONResponse({"error": "Donnez le nom de l'organisation."}, status_code=400)
    if not _rate_ok(_org_creations, _client_ip(request), ORGS_PER_HOUR, 3600):
        return JSONResponse({"error": "Trop de créations. Réessayez plus tard."}, status_code=429)
    o = orgs.create(name)
    print(f"[organisations] nouvelle organisation {o.id}")
    return {"id": o.id, "name": o.name, "enroll_token": o.enroll, "support_token": o.support,
            "server": PUBLIC_URL, **_org_links(o)}


@app.post("/k/{fam}/org")
async def join_org(fam: str, request: Request):
    """Un poste déjà installé rejoint l'organisation (jeton déposé après coup par l'IT)."""
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    body = await _small_json(request)
    o = orgs.by_enroll(str(body.get("org") or ""))
    if o is None:
        return JSONResponse({"error": "Jeton d'organisation inconnu."}, status_code=403)
    if S().org and S().org != o.id:
        return JSONResponse({"error": "Ce poste appartient déjà à une autre organisation."}, status_code=409)
    first = S().org != o.id
    if not spaces.join(S(), o.id, _label(body)):
        return JSONResponse({"error": "Cet espace ne peut pas rejoindre une organisation."}, status_code=409)
    o.copy_automations(S().lessons_dir)
    if first:
        S().tickets.renumber(o.next_ticket)
    if S().bridge is not None:
        await S().bridge.send({"type": "lessons_changed", "title": ""})
    return {"org": o.name}


@app.get("/o/{token}")
async def org_page(token: str):
    if orgs.by_support(token) is None:
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return FileResponse(STATIC / "org.html")


@app.get("/o/{token}/spaces")
async def org_spaces(token: str):
    """Tous les postes de l'organisation, avec leur clé : le support les suit sans appairage."""
    o = orgs.by_support(token)
    if o is None:
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return {"org": o.name, "server": PUBLIC_URL, "spaces": [
        {"key": sp.key, "name": sp.family.senior or sp.label, "label": sp.label,
         "online": sp.bridge is not None} for sp in spaces.members(o.id)]}


@app.get("/o/{token}/automations")
async def org_automations(token: str):
    o = orgs.by_support(token)
    if o is None:
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return o.automations()


@app.post("/o/{token}/automations")
async def org_import_automation(token: str, request: Request):
    """Importé une fois par l'IT, proposé sur tous les postes, présents et à venir."""
    o = orgs.by_support(token)
    if o is None:
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    pack = await _read_pack(request)
    if isinstance(pack, JSONResponse):
        return pack
    try:
        lesson = automations.save(pack, by=request.query_params.get("by", "") or o.name, folder=o.lessons_dir)
    except automations.Invalid as e:
        return JSONResponse({"error": str(e)}, status_code=422)
    print(f"[organisations] automate {lesson['id']} pour {o.id}")
    for sp in spaces.members(o.id):
        o.copy_automations(sp.lessons_dir, only=lesson["id"])
        if sp.bridge is not None:
            await sp.bridge.send({"type": "lessons_changed", "title": lesson["title"]})
    return lesson


@app.delete("/o/{token}/automations/{lesson_id}")
async def org_remove_automation(token: str, lesson_id: str):
    o = orgs.by_support(token)
    if o is None:
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    if not automations.remove(lesson_id, o.lessons_dir):
        return JSONResponse({"error": "introuvable"}, status_code=404)
    for sp in spaces.members(o.id):
        if automations.remove(lesson_id, sp.lessons_dir) and sp.bridge is not None:
            await sp.bridge.send({"type": "lessons_changed", "title": ""})
    return {"removed": lesson_id}


@app.get("/k/{fam}/p/{code}")
async def pair_page_keyed(fam: str, code: str):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return await _pair_page(code)


@app.post("/k/{fam}/p/{code}")
async def pair_submit_keyed(fam: str, code: str, request: Request):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return await _pair_submit(code, request, confirm=PUBLIC_MODE)


async def handle_remote_request(msg: dict, ws: WebSocket) -> None:
    """Le proche propose une session. Rien ne démarre sans l'accord du Mac."""
    if S().bridge is None:
        await ws.send_json({"type": "refused", "reason": "L'ordinateur n'est pas connecté."})
        return
    s = current_session()
    if s is not None and s.is_open:
        await ws.send_json({"type": "refused", "reason": "Une demande est déjà en cours."})
        return
    names = [h["name"] for h in S().family.helpers]
    who = str(msg.get("from", "")).strip()
    if who not in names:
        who = names[0] if len(names) == 1 else "Votre support"
    task = str(msg.get("text", "")).strip()[:300]
    await S().bridge.send({"type": "remote_request", "from": who, "task": task})
    await ws.send_json({"type": "ack", "what": "remote_request"})
    print("[proches] un proche propose une session")


# ------------------------------------------------------------------ aidant permanent


def current_session():
    """La session la plus récente : c'est celle que suit l'aidant."""
    sessions = list(S().registry._by_id.values())
    return sessions[-1] if sessions else None


@app.get("/a/{key}")
async def aidant_page(key: str):
    if not _key_ok(key):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return FileResponse(STATIC / "helper.html")


@app.websocket("/k/{fam}/ws/aidant/{key}")
async def ws_aidant_keyed(ws: WebSocket, fam: str, key: str) -> None:
    # Les deux clés désignent le même espace : pas de mélange entre espaces.
    if not (_key_ok(fam) and secrets.compare_digest(fam, key)):
        await ws.close(code=4403)
        return
    await ws_aidant(ws, key)


@app.websocket("/ws/aidant/{key}")
async def ws_aidant(ws: WebSocket, key: str) -> None:
    """Le canal de l'app iPhone : il suit toujours la dernière demande.

    Contrairement au lien par session, il reste ouvert entre deux demandes :
    c'est lui qui « sonne » quand l’utilisateur appuie sur le bouton.
    """
    await ws.accept()
    if not _key_ok(key):
        await ws.send_json({"type": "refused", "reason": "Lien invalide."})
        await ws.close()
        return
    S().helper_sockets.add(ws)
    S().helper_alert_scopes[ws] = None
    await ws.send_json({"type": "hello", "bridge": S().bridge is not None,
                        "os": S().bridge.os if S().bridge else None, "senior": S().family.senior or None,
                        "protection": getattr(S().bridge, "protection", None),
                        "tickets_waiting": len(S().tickets.waiting()) + len(S().tickets.due())})
    s = current_session()
    if s is not None:
        await ws.send_json(s.status())
        if s.last_frame:
            await ws.send_json({"type": "frame", "frame_id": s.last_frame.frame_id,
                                "png_b64": s.last_frame.png_b64})
    if S().pending_alert and helper_can_access_alert(ws, S().pending_alert["helper"]):
        await ws.send_json(S().pending_alert["helper"])
    _later(_offer_soon(space.current(), ws))
    try:
        while True:
            msg = await ws.receive_json()
            if msg.get("type") == "remote_request":
                await handle_remote_request(msg, ws)
                continue
            if msg.get("type") == "helper_hello":
                # L'app se présente : elle apparaît dans « Mes proches » sur l'ordinateur.
                h = S().family.connect(str(msg.get("id", "")), str(msg.get("name", "")),
                                   str(msg.get("relation", "")))
                if h is not None:
                    S().helper_who[ws] = {"id": h["id"], "name": h["name"]}
                    await ws.send_json({"type": "helper_id", "id": h["id"]})
                    await _send_helpers_to_bridge()
                    await _offer_waiting(h["name"])
                continue
            if msg.get("type") == "dismiss_alert":
                await dismiss_guard(msg, ws)
                continue
            if msg.get("type") == "ack_alert":
                await acknowledge_guard(msg, ws)
                continue
            s = current_session()
            if s is None:
                await ws.send_json({"type": "refused", "reason": "Aucune demande en cours."})
                continue
            await handle_helper_msg(s, msg, ws)
    except WebSocketDisconnect:
        pass
    finally:
        S().helper_sockets.discard(ws)
        S().helper_alert_scopes.pop(ws, None)
        if S().helper_who.pop(ws, None) is not None:
            await _send_helpers_to_bridge()


# Une même situation ne doit pas sonner en boucle : on retient ce qui a déjà
# été signalé, pour ne pas apprendre à la personne à ignorer les alertes.
_guard_taches: set[asyncio.Task] = set()
GUARD_SILENCE_S = 300
GUARD_ADVICE_TIMEOUT_S = 9


def guard_contact() -> str:
    if not S().family.helpers:
        return "votre support"
    h = next((h for h in S().family.helpers if h["id"] in _online_ids()), S().family.helpers[0])
    relation = re.sub(r"^(mon|ma|mes|son|sa|ses|votre|un|une|le|la)\s+", "", h.get("relation", "").strip(), flags=re.I)
    return f"votre {relation} {h['name']}" if relation else h["name"]


async def publish_guard(alerte: guard.Alerte, source: str, session=None, *,
                        senior_detail: str | None = None, helper_detail: str | None = None) -> None:
    for s in S().registry._by_id.values():
        if s.is_open:
            s.stop(by="gardien")
    if S().pending_alert:
        return
    common = {"type": "alert", "alert_id": secrets.token_hex(12), "level": alerte.niveau,
              "source": source, "blocked": True,
              "session": session.id if session else None, "task": session.task if session else ""}
    detail = f"Contactez {guard_contact()} avant d'aller plus loin. "
    detail += ("Rien n'a été exécuté pour cette demande." if source in ("request", "plan")
               else "L'assistance est arrêtée.")
    senior = {**common, "title": "Attention, cette démarche peut être une arnaque.",
              "detail": senior_detail or detail}
    who = S().family.senior or "L’utilisateur"
    detail = f"{who} a besoin de votre avis. {alerte.detail}"
    if session:
        detail += f"\nDemande : « {session.task} »"
    detail += f"\nPrenez contact avec {S().family.senior or 'l’utilisateur'} avant de poursuivre. Choisissez « C'est normal » uniquement si vous connaissez cette démarche. L'assistance ne reprendra pas automatiquement."
    helper = {**common, "title": f"Démarche à vérifier pour {who}", "detail": helper_detail or detail}
    S().pending_alert = {"senior": senior, "helper": helper}
    if S().bridge:
        await S().bridge.send(senior)
    await broadcast_helper(helper, to_bridge=False)
    s = session or current_session()
    if s:
        await broadcast_helper(s.status())


def guard_action_allowed(msg: dict, ws: WebSocket) -> bool:
    return bool(S().pending_alert and helper_can_access_alert(ws, S().pending_alert["helper"])
                and msg.get("alert_id") == S().pending_alert["helper"]["alert_id"])


async def acknowledge_guard(msg: dict, ws: WebSocket) -> None:
    if not guard_action_allowed(msg, ws):
        await ws.send_json({"type": "refused", "reason": "Cette alerte n'est plus en attente."})
        return
    alert = S().pending_alert
    for payload in alert.values():
        payload["acknowledged"] = True
    session = S().registry.get(alert["helper"]["session"])
    if session:
        session.guard_acknowledged = True
    await broadcast_helper({"type": "alert_acknowledged", "alert_id": alert["helper"]["alert_id"],
                            "session": alert["helper"]["session"],
                            "acknowledged": True})


async def dismiss_guard(msg: dict, ws: WebSocket) -> None:
    if not guard_action_allowed(msg, ws):
        await ws.send_json({"type": "refused", "reason": "Cette alerte n'est plus en attente."})
        return
    aid = S().pending_alert["helper"]["alert_id"]
    session_id = S().pending_alert["helper"]["session"]
    S().pending_alert = None
    await broadcast_helper({"type": "alert_cleared", "alert_id": aid, "session": session_id})


async def check_request(session, texte: str, source: str) -> bool:
    alerte = guard.evaluer_demande(texte)
    if alerte is None and guard.demande_incertaine(texte):
        from .agent import client
        from papai_tools import MODEL, TEMPERATURE
        try:
            resp = await asyncio.wait_for(asyncio.to_thread(
                client.with_options(timeout=8, max_retries=0).chat.completions.create,
                model=MODEL, temperature=TEMPERATURE,
                messages=[{"role": "system", "content": guard.PROMPT_DEMANDE},
                          {"role": "user", "content": json.dumps({"texte_a_evaluer": texte}, ensure_ascii=False)}],
            ), timeout=GUARD_ADVICE_TIMEOUT_S)
            session.record_usage(getattr(resp, "usage", None))
            avis = json.loads(resp.choices[0].message.content or "")
            if type(avis.get("suspect")) is not bool:
                raise ValueError("Avis manquant")
            if avis["suspect"]:
                raison = str(avis.get("raison") or "Demande inhabituelle à vérifier avec votre support.")[:500]
                alerte = guard.Alerte("attention", "Démarche à vérifier", raison, "avis_holo", False)
        except Exception:
            if session.is_open:
                await broadcast_helper({"type": "guard_advice", "level": "attention",
                                        "source": "avis_indisponible", "session": session.id,
                                        "title": "Avis de sécurité indisponible",
                                        "detail": "Un doute subsiste. Vérifiez cette demande et le plan avant de les valider."},
                                       to_bridge=False)
    if not session.is_open:
        return True
    if alerte:
        await publish_guard(alerte, source, session)
        return True
    return False


async def handle_guard(msg: dict) -> None:
    """Un signal du gardien. Évalue, et ne dérange que si ça vaut la peine."""
    import time

    procs = msg.get("processes")
    if not isinstance(procs, list):
        procs = []
    alerte = guard.evaluer(
        processus=[str(p)[:MAX_PROCESS_NAME] for p in procs[:MAX_PROCESSES]],
        fenetre=str(msg.get("window", ""))[:500],
        url=str(msg.get("url", ""))[:2000],
    )
    if alerte is None:
        return

    dernier = S().guard_vu.get(alerte.motif, 0.0)
    if time.time() - dernier < GUARD_SILENCE_S:
        return
    S().guard_vu[alerte.motif] = time.time()

    s = current_session()
    print(f"[gardien] {alerte.niveau} — {alerte.motif}", flush=True)
    await publish_guard(alerte, "environment", s)


async def confirmer_par_le_modele(alerte) -> str:
    """Une capture, un appel, une description. Rien de plus."""
    if S().bridge is None:
        return ""
    frame = await S().bridge.capture()
    if frame is None:
        return ""
    try:
        from papai_tools import MODEL, TEMPERATURE, observation
        from .agent import client

        resp = await asyncio.to_thread(
            client.chat.completions.create,
            model=MODEL,
            messages=[
                {"role": "system",
                 "content": guard.PROMPT_CONFIRMATION.format(motif=alerte.motif)},
                observation(frame.png_b64),
            ],
            temperature=TEMPERATURE,
        )
        brut = resp.choices[0].message.content or ""
        m = re.search(r"\{.*\}", brut, re.S)
        if not m:
            return ""
        return str(json.loads(m.group(0)).get("description", "")).strip()
    except Exception as e:  # noqa: BLE001 — l'alerte part quand même
        print(f"[gardien] confirmation impossible : {type(e).__name__}", flush=True)
        return ""


@app.get("/")
async def root():
    return {"service": "PapAI", "bridge": S().bridge is not None}


@app.get("/k/{fam}/lessons")
async def lessons_keyed(fam: str):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return list_lessons()


@app.get("/k/{fam}/lessons/{lesson_id}/{filename}")
async def lesson_file_keyed(fam: str, lesson_id: str, filename: str):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return _serve_lesson_file(lesson_id, filename)


@app.websocket("/k/{fam}/transcribe/live")
async def transcribe_live_keyed(ws: WebSocket, fam: str) -> None:
    if not _key_ok(fam):
        await ws.close(code=4403)
        return
    await voice.relay_live(ws)


MAX_IMPORT = 15_000_000


async def _read_pack(request: Request):
    """Le fichier `.papai` envoyé, ou la réponse d'erreur à renvoyer telle quelle."""
    trop = JSONResponse({"error": "Fichier trop gros."}, status_code=413)
    try:
        if int(request.headers.get("content-length") or 0) > MAX_IMPORT:
            return trop
    except ValueError:
        return trop
    body = bytearray()
    async for part in request.stream():
        body += part
        if len(body) > MAX_IMPORT:
            return trop
    try:
        return json.loads(body)
    except ValueError:
        return JSONResponse({"error": "Ce n'est pas un fichier .papai (JSON attendu)."}, status_code=400)


async def _import_automation(request: Request):
    """Le support (service IT, proche) importe un automate : c'est sa validation."""
    pack = await _read_pack(request)
    if isinstance(pack, JSONResponse):
        return pack
    try:
        lesson = automations.save(pack, by=request.query_params.get("by", ""))
    except automations.Invalid as e:
        return JSONResponse({"error": str(e)}, status_code=422)
    print(f"[automate] importé {lesson['id']}")
    if S().bridge is not None:
        await S().bridge.send({"type": "lessons_changed", "title": lesson["title"]})
    return lesson


async def _remove_automation(lesson_id: str):
    if not automations.remove(lesson_id):
        return JSONResponse({"error": "introuvable"}, status_code=404)
    if S().bridge is not None:
        await S().bridge.send({"type": "lessons_changed", "title": ""})
    return {"removed": lesson_id}


@app.post("/k/{fam}/automations")
async def import_automation_keyed(fam: str, request: Request):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return await _import_automation(request)


@app.delete("/k/{fam}/automations/{lesson_id}")
async def remove_automation_keyed(fam: str, lesson_id: str):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return await _remove_automation(lesson_id)


async def _draft_automation(request: Request):
    """Brouillon d'automate (document ou enregistrement) : appelle Holo, n'écrit rien."""
    try:
        body = await request.json()
    except ValueError:
        return JSONResponse({"error": "Requête illisible (JSON attendu)."}, status_code=400)
    if not isinstance(body, dict):
        return JSONResponse({"error": "Requête illisible (JSON attendu)."}, status_code=400)
    try:
        return await automate_draft.draft(body)
    except automate_draft.DraftError as e:
        return JSONResponse({"error": str(e)}, status_code=422)
    except Exception as e:  # noqa: BLE001 — Holo injoignable, quota…
        print(f"[automate] brouillon impossible : {type(e).__name__}")
        return JSONResponse({"error": "Holo ne répond pas pour le moment. Réessayez."}, status_code=502)


@app.post("/k/{fam}/automations/draft")
async def draft_automation_keyed(fam: str, request: Request):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return await _draft_automation(request)


@app.post("/automations/draft")
async def draft_automation(request: Request):
    if not _same_machine(request):
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return await _draft_automation(request)


@app.post("/automations")
async def import_automation(request: Request):
    if not _same_machine(request):
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return await _import_automation(request)


@app.delete("/automations/{lesson_id}")
async def remove_automation(lesson_id: str, request: Request):
    if not _same_machine(request):
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return await _remove_automation(lesson_id)


@app.post("/k/{fam}/transcribe")
async def transcribe_keyed(fam: str, request: Request):
    """Dictée de la demande : audio brut en entrée, {"text": "..."} en sortie."""
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    if not voice.configured():
        return JSONResponse({"error": "gladia_absent"}, status_code=503)
    audio = await request.body()
    if len(audio) > 5_000_000:
        return JSONResponse({"error": "trop_long"}, status_code=413)
    ctype = request.headers.get("content-type", "audio/wav").split(";")[0].strip()
    ext = "m4a" if "m4a" in ctype or "mp4" in ctype else "wav"
    ok, text = await asyncio.to_thread(voice.transcribe, audio, f"demande.{ext}", ctype)
    if not ok:
        return JSONResponse({"error": text}, status_code=502)
    return {"text": text}


@app.get("/lessons")
async def lessons(request: Request):
    """Les fiches validées par un proche. Les brouillons ne sortent jamais d'ici.

    Sans clé, seulement pour l'app de la machine du serveur ; sinon /k/{clé}/lessons.
    """
    if not _same_machine(request):
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return list_lessons()


@app.get("/lessons/{lesson_id}/{filename}")
async def lesson_file(lesson_id: str, filename: str, request: Request):
    if not _same_machine(request):
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return _serve_lesson_file(lesson_id, filename)


def _serve_lesson_file(lesson_id: str, filename: str):
    """Sert une capture de fiche. Chemins cloisonnés : pas de remontée possible."""
    safe = Path(filename).name
    path = (lessons_dir() / Path(lesson_id).name / safe).resolve()
    if not str(path).startswith(str(lessons_dir().resolve())) or not path.is_file():
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return FileResponse(path)


def _sessions_journal():
    return [
        {**s.status(), "journal": s.journal}
        for s in S().registry._by_id.values()
    ]


# --- Tickets : vus et traités par le support (page web, apps, organisation) ---

async def _ticket_action(tid: str, body: dict):
    t = S().tickets.get(tid)
    if t is None:
        return JSONResponse({"error": "Ticket introuvable."}, status_code=404)
    act = body.get("action")
    by = str(body.get("by") or "").strip()[:40]
    text = str(body.get("text") or "").strip()
    if act == "note":
        if not text:
            return JSONResponse({"error": "Note vide."}, status_code=400)
        S().tickets.note(t, by, text)
    elif act == "close":
        if t["status"] == "en_cours":
            return JSONResponse({"error": "Une assistance est en cours sur ce ticket."}, status_code=409)
        S().tickets.update(t, status="resolu", closed_by=by or "Support", rdv=None)
        if text:
            S().tickets.note(t, by, text)
    elif act == "reopen":
        if t["status"] == "en_cours":
            return JSONResponse({"error": "Une assistance est en cours sur ce ticket."}, status_code=409)
        S().tickets.update(t, status="en_attente", offered=0, rdv=None, closed_by="")
    elif act == "schedule":
        at = _rdv_at(body.get("at"))
        if at is None or t["status"] in ("en_cours", "resolu"):
            return JSONResponse({"error": "Ce rendez-vous n'est pas possible."}, status_code=400)
        S().tickets.update(t, status="rdv", rdv=at, rdv_notified=False, assignee=by or t.get("assignee", ""))
        if S().bridge is not None:
            await S().bridge.send({"type": "ticket_scheduled", "ticket": t["id"], "number": t["number"],
                                   "at": at, "by": by})
    elif act == "category":
        if not S().tickets.categorize(t, str(body.get("category") or ""), "support", by):
            return JSONResponse({"error": "Catégorie inconnue."}, status_code=400)
    elif act == "take":
        if t["status"] in ("en_cours", "resolu"):
            return JSONResponse({"error": "Ce ticket n'est pas en attente."}, status_code=409)
        if S().bridge is None:
            return JSONResponse({"error": "L'ordinateur n'est pas connecté."}, status_code=409)
        s = current_session()
        if s is not None and s.is_open:
            return JSONResponse({"error": "Une demande est déjà en cours."}, status_code=409)
        S().tickets.update(t, assignee=by, status="en_attente", offered=int(time.time()))
        await S().bridge.send({"type": "remote_request", "from": by or "Votre support", "task": t["task"],
                               "ticket": t["id"], "number": t["number"], "rdv": False})
    else:
        return JSONResponse({"error": "Action inconnue."}, status_code=400)
    await _tickets_changed()
    return {"ticket": tickets_mod.public(t)}


async def _json_body(request: Request) -> dict:
    try:
        body = await request.json()
    except Exception:  # noqa: BLE001
        return {}
    return body if isinstance(body, dict) else {}


@app.get("/tickets.js")
async def tickets_js():
    return FileResponse(STATIC / "tickets.js", media_type="text/javascript")


@app.get("/ticket_stats.js")
async def ticket_stats_js():
    return FileResponse(STATIC / "ticket_stats.js", media_type="text/javascript")


@app.get("/k/{fam}/tickets")
async def tickets_keyed(fam: str):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return {"tickets": [tickets_mod.public(t) for t in S().tickets.all()[:200]]}


@app.get("/k/{fam}/tickets/stats")
async def tickets_stats_keyed(fam: str, weeks: int = ticket_stats.WEEKS):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return ticket_stats.stats(S().tickets.all(), weeks=weeks)


@app.post("/k/{fam}/tickets/{tid}")
async def ticket_action_keyed(fam: str, tid: str, request: Request):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return await _ticket_action(tid, await _json_body(request))


@app.get("/o/{token}/tickets")
async def org_tickets(token: str):
    """Les tickets de tous les postes de l'organisation, les plus récents d'abord."""
    o = orgs.by_support(token)
    if o is None:
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    out = []
    for sp in spaces.members(o.id):
        poste = sp.family.senior or getattr(sp, "label", "") or "Poste"
        out += [{**tickets_mod.public(t), "space": sp.key, "poste": poste,
                 "online": sp.bridge is not None} for t in sp.tickets.all()[:200]]
    out.sort(key=lambda t: t.get("updated", 0), reverse=True)
    return {"org": o.name, "tickets": out[:1000]}


@app.get("/o/{token}/tickets/stats")
async def org_tickets_stats(token: str, weeks: int = ticket_stats.WEEKS):
    """Les mêmes agrégats, sur tous les postes de l'organisation."""
    o = orgs.by_support(token)
    if o is None:
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    rows = []
    for sp in spaces.members(o.id):
        poste = sp.family.senior or getattr(sp, "label", "") or "Poste"
        rows += [{**t, "space": sp.key, "poste": poste} for t in sp.tickets.all()]
    return {"org": o.name, **ticket_stats.stats(rows, weeks=weeks)}


@app.post("/o/{token}/tickets/{key}/{tid}")
async def org_ticket_action(token: str, key: str, tid: str, request: Request):
    o = orgs.by_support(token)
    sp = spaces.get(key)
    if o is None or sp is None or getattr(sp, "org", None) != o.id:
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    space.use(sp)
    return await _ticket_action(tid, await _json_body(request))


@app.get("/sessions")
async def list_sessions(request: Request):
    """Le journal des actions, lisible par l’utilisateur (section 08).

    Sert aussi de point d'observation pendant les essais. Sans clé, seulement
    depuis la machine du serveur ; sinon /k/{clé}/sessions.
    """
    if not _same_machine(request):
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return _sessions_journal()


@app.get("/k/{fam}/sessions")
async def list_sessions_keyed(fam: str):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return _sessions_journal()


if __name__ == "__main__":
    STATIC.mkdir(exist_ok=True)
    # Les hébergeurs imposent le port par la variable PORT.
    port = int(os.environ.get("PORT", "8000"))
    # La clé ne s'écrit pas dans le journal : un proche la reçoit en
    # s'ajoutant par code ou QR. PAPAI_SHOW_KEY=1 l'affiche sur ce terminal.
    if os.environ.get("PAPAI_SHOW_KEY") == "1":
        print(f"[aidant] lien permanent : {PUBLIC_URL}/a/{S().key}")
    else:
        origine = "PAPAI_AIDANT_KEY" if os.environ.get("PAPAI_AIDANT_KEY") else "tirée au hasard"
        print(f"[aidant] lien permanent : {PUBLIC_URL}/a/<clé famille> ({origine} ; "
              "PAPAI_SHOW_KEY=1 pour l'afficher)")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="warning")
