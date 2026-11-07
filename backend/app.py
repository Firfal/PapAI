"""Backend PapAI : sessions, verrou de contrôle, relais vers le pont.

Deux WebSockets :
  /ws/bridge          le PC de la personne aidée (capture et exécution)
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
from pathlib import Path
from urllib.parse import quote

import uvicorn
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse
from starlette.requests import HTTPConnection

from . import guard, voice
from .agent import AgentRunner, propose_plan
from .family import Family, PairingError
from .caremamory import LESSONS_DIR, approve_and_save, draft_lesson, list_lessons
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
registry = Registry()
family = Family()

# Clé du lien permanent de l'aidant (app iPhone ou page /a/{clé}). Stable d'un
# lancement à l'autre si on la fixe dans .env, sinon tirée au démarrage.
AIDANT_KEY = os.environ.get("PAPAI_AIDANT_KEY") or secrets.token_urlsafe(9)

# Tout passe par /k/{clé de la famille}/… : sans la clé, personne ne peut se
# faire passer pour le PC de la personne aidée, ni lire ses fiches. En local
# (PAPAI_PUBLIC absent), les routes sans clé ne répondent qu'à une app lancée
# sur la machine même du serveur (voir _same_machine).
PUBLIC_MODE = os.environ.get("PAPAI_PUBLIC", "") == "1"

# Bornes des messages du pont : une demande se lit en une phrase, et la liste
# des processus d'un PC chargé tient largement dans 500 noms.
MAX_TASK = 500
MAX_PROCESSES = 500
MAX_PROCESS_NAME = 200


def _key_ok(fam: str) -> bool:
    return secrets.compare_digest(fam or "", AIDANT_KEY)


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
_SECRET_PATH = re.compile(r"/(k|a|h|p|ws/aidant|ws/helper)/[^/?#\s\"']+")


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
        self.os = "windows"  # annoncé par le pont dans son message hello

    async def close(self, code: int = 1000) -> None:
        try:
            await self.ws.close(code=code)
        except Exception:  # noqa: BLE001 — déjà fermé
            pass

    async def _request(self, payload: dict, timeout: float = 20.0):
        req = secrets.token_hex(6)
        fut = asyncio.get_running_loop().create_future()
        self._pending[req] = fut
        try:
            await self.ws.send_json({**payload, "req": req})
            return await asyncio.wait_for(fut, timeout)
        except (asyncio.TimeoutError, WebSocketDisconnect, RuntimeError):
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
        data = await self._request({"type": "execute", "action": {"name": name, "args": args}})
        if data is None:
            return None
        if data.get("refused"):
            return None  # le pont a refusé : arrêt local, la session s'arrête
        return data.get("result", "")

    async def send(self, payload: dict) -> None:
        try:
            await self.ws.send_json(payload)
        except Exception:  # noqa: BLE001 — pont déconnecté
            pass


bridge: BridgeLink | None = None
helper_sockets: set[WebSocket] = set()
agent_task: asyncio.Task | None = None


# Ce que la personne aidée doit aussi voir : l'état de la session, le plan en
# attente, la réponse finale. Jamais les captures, qu'elle a sous les yeux.
BRIDGE_TYPES = {"status", "answer", "alert"}


async def broadcast_helper(payload: dict) -> None:
    if bridge is not None and payload.get("type") in BRIDGE_TYPES:
        await bridge.send(payload)
    dead = []
    for ws in helper_sockets:
        try:
            await ws.send_json(payload)
        except Exception:  # noqa: BLE001
            dead.append(ws)
    for ws in dead:
        helper_sockets.discard(ws)


# ------------------------------------------------------------------ pont


@app.websocket("/k/{fam}/ws/bridge")
async def ws_bridge_keyed(ws: WebSocket, fam: str) -> None:
    if not _key_ok(fam):
        await ws.close(code=4403)
        return
    await _ws_bridge(ws)


@app.websocket("/ws/bridge")
async def ws_bridge(ws: WebSocket) -> None:
    # Sans clé : seulement depuis la machine du serveur (démo locale).
    if not _same_machine(ws):
        await ws.close(code=4403)
        return
    await _ws_bridge(ws)


async def _stop_open_sessions(by: str) -> None:
    for s in list(registry._by_id.values()):
        if s.is_open:
            s.stop(by=by)
            await broadcast_helper(s.status())


async def _ws_bridge(ws: WebSocket) -> None:
    global bridge, agent_task
    await ws.accept()
    link = BridgeLink(ws)
    old, bridge = bridge, link
    if old is not None:
        # Un seul pont. Le nouveau a passé le même contrôle que l'ancien :
        # c'est en général le même Mac qui se reconnecte après une coupure.
        # La session de l'ancien lien ne peut plus agir : on l'arrête.
        print("[pont] remplacé par une nouvelle connexion")
        if agent_task and not agent_task.done():
            agent_task.cancel()
        await _stop_open_sessions("pont remplacé")
        await old.close(code=4409)
    print("[pont] connecté")
    try:
        while True:
            msg = await ws.receive_json()
            if not isinstance(msg, dict):
                continue
            kind = msg.get("type")

            if kind in ("frame", "result"):
                link.resolve(str(msg.get("req", "")), msg)
                continue

            if kind == "hello":
                link.os = str(msg.get("os", "windows")).lower()[:20]
                print(f"[pont] système : {link.os}")
                await ws.send_json({"type": "helpers", "helpers": family.public()})
                continue

            if kind == "pair_start":
                # Ajout d'un proche : un code à 6 chiffres et son lien (QR).
                code = family.new_code()
                await ws.send_json({"type": "pair_code", "code": code, "url": pairing_url(code),
                                    "app_url": app_pairing_url(code), "expires_in": 600})
                continue

            if kind == "remove_helper":
                family.remove(str(msg.get("id", "")))
                await ws.send_json({"type": "helpers", "helpers": family.public()})
                continue

            if kind == "remote_answer":
                # Réponse de la personne aidée à une session proposée par un proche.
                if not msg.get("accepted"):
                    await broadcast_helper({"type": "remote_refused"})
                    print("[pont] session à distance refusée")
                continue

            if kind == "help_request":
                session = registry.create(str(msg.get("task") or "").strip()[:MAX_TASK])
                session.grant_consent()  # le consentement est donné dans la même fenêtre
                if msg.get("requested_by"):
                    # Lancée par un proche, acceptée à l'instant sur le Mac.
                    session.log("remote_accepted", by=str(msg["requested_by"])[:40])
                    await broadcast_helper({"type": "remote_accepted"})
                url = f"{PUBLIC_URL}/h/{session.helper_token}"
                await ws.send_json({"type": "session", "id": session.id, "helper_url": url})
                # Ni la demande ni le lien du proche (son jeton) dans le journal.
                print(f"[session {session.id}] nouvelle demande")
                await broadcast_helper(session.status())

                if agent_task and not agent_task.done():
                    agent_task.cancel()
                agent_task = asyncio.create_task(run_session(session, link))
                continue

            if kind == "automation_failed":
                # Un automatisme n'a pas pu se rejouer : l'écran ou le dossier a
                # changé. On ne tente rien à l'aveugle, on prévient l'aidant.
                await broadcast_helper({
                    "type": "alert",
                    "title": str(msg.get("title", "Un raccourci"))[:200],
                    "detail": str(msg.get("detail", ""))[:1000],
                })
                continue

            if kind == "guard":
                # Le gardien du Mac a vu passer un signal. Il n'envoie que du
                # texte — processus, titre de fenêtre, adresse — jamais l'écran.
                # À part : pendant une session, la confirmation attend une
                # capture que cette boucle doit pouvoir recevoir.
                t = asyncio.create_task(handle_guard(msg))
                _guard_taches.add(t)
                t.add_done_callback(_guard_taches.discard)
                continue

            if kind == "stop":
                for s in list(registry._by_id.values()):
                    if s.is_open:
                        s.stop(by="senior")
                        await broadcast_helper(s.status())
                if agent_task and not agent_task.done():
                    agent_task.cancel()
                print("[pont] ARRÊT demandé par la personne aidée")
                continue

    except (WebSocketDisconnect, RuntimeError, ValueError):
        print("[pont] déconnecté")
    finally:
        # Un nouveau pont a pu prendre la place entre-temps : on ne le
        # débranche pas, et ses sessions continuent.
        if bridge is link:
            bridge = None
            await _stop_open_sessions("pont déconnecté")


async def run_session(session, link: "BridgeLink") -> None:
    """Plan d'abord, validé par l'aidant ; l'agent n'agit qu'ensuite."""
    notes: list[str] = []
    try:
        while True:
            await broadcast_helper(session.status())
            steps = await propose_plan(session, link, broadcast_helper, " ; ".join(notes))
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
        await AgentRunner(session, link, broadcast_helper, notes).run()
    except asyncio.CancelledError:
        session.stop(by="annulation")
        raise


# ------------------------------------------------------------------ proche


@app.get("/h/{token}")
async def helper_page(token: str):
    try:
        registry.by_token(token)
    except Refused as e:
        return JSONResponse({"error": str(e)}, status_code=404)
    return FileResponse(STATIC / "helper.html")


@app.websocket("/ws/helper/{token}")
async def ws_helper(ws: WebSocket, token: str) -> None:
    try:
        session = registry.by_token(token)
    except Refused as e:
        await ws.accept()
        await ws.send_json({"type": "refused", "reason": str(e)})
        await ws.close()
        return

    await ws.accept()
    helper_sockets.add(ws)
    await ws.send_json(session.status())
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
        helper_sockets.discard(ws)


async def handle_helper_msg(session, msg: dict, ws: WebSocket) -> None:
    """Un message de l'aidant, page web ou app iPhone. Tout est revalidé ici."""
    kind = msg.get("type")
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
                lesson = await draft_lesson(session)
            except Exception as e:  # noqa: BLE001 — l'aidant ne doit pas rester sans réponse
                session.log("lesson_failed", error=f"{type(e).__name__}: {e}")
                raise Refused("Holo n'a pas pu rédiger la fiche. Réessayez.") from e
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
                raise Refused("Aucune fiche à valider.")
            # Le proche a pu corriger le texte : on reprend le sien.
            edited = msg.get("lesson") or {}
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
            if bridge is not None:
                # La personne aidée le retrouve aussitôt dans « Mes tutoriels ».
                await bridge.send({"type": "lessons_changed", "title": saved.get("title", "")})

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
    if bridge is None:
        raise Refused("Le PC n'est pas connecté.")

    frame = await bridge.capture()
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

    session.validate_click(str(msg.get("frame_id", "")))

    x = float(msg.get("x", -1))
    y = float(msg.get("y", -1))
    if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
        raise Refused("Coordonnées hors de la capture.")

    if bridge is None:
        raise Refused("Le PC n'est pas connecté.")

    session.take_control(Owner.HELPER)
    args = {"element": "clic du proche", "x": round(x * 1000), "y": round(y * 1000)}
    session.log("helper_click", x=args["x"], y=args["y"])
    result = await bridge.execute("click", args)
    session.release_control()

    if result is None:
        raise Refused("Le PC a refusé l'action.")

    await ws.send_json({"type": "ack", "what": "click", "result": result})
    session.answer_from_helper("J'ai cliqué moi-même sur l'écran. Reprends à partir de là.")
    await broadcast_helper(session.status())


# ------------------------------------------------------------------ proches


def pairing_url(code: str) -> str:
    base = f"{PUBLIC_URL}/k/{AIDANT_KEY}" if PUBLIC_MODE else PUBLIC_URL
    return f"{base}/p/{code}"


def app_pairing_url(code: str) -> str:
    """Le lien du QR : ouvre l'app iPhone, qui fait elle-même le POST sur `url`."""
    return "papai://pair?u=" + quote(pairing_url(code), safe="")


def aidant_url() -> str:
    return f"{PUBLIC_URL}/a/{AIDANT_KEY}"


async def _pair_page(code: str):
    return FileResponse(STATIC / "pair.html")


async def _pair_submit(code: str, request: Request):
    try:
        body = await request.json()
    except ValueError:
        body = {}
    try:
        helper = family.pair(code, str(body.get("name", "")), str(body.get("relation", "")))
    except PairingError as e:
        return JSONResponse({"ok": False, "error": str(e)}, status_code=400)
    print("[proches] un proche ajouté")
    if bridge is not None:
        await bridge.send({"type": "helpers", "helpers": family.public(), "added": helper["name"]})
    return {"ok": True, "name": helper["name"], "aidant_url": aidant_url(),
            "server": PUBLIC_URL, "key": AIDANT_KEY}


@app.get("/p")
async def pair_page_manual():
    if PUBLIC_MODE:
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return await _pair_page("")


@app.get("/k/{fam}/p")
async def pair_page_manual_keyed(fam: str):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return await _pair_page("")


@app.get("/p/{code}")
async def pair_page(code: str):
    if PUBLIC_MODE:
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return await _pair_page(code)


@app.post("/p/{code}")
async def pair_submit(code: str, request: Request):
    if PUBLIC_MODE:
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return await _pair_submit(code, request)


@app.get("/k/{fam}/p/{code}")
async def pair_page_keyed(fam: str, code: str):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return await _pair_page(code)


@app.post("/k/{fam}/p/{code}")
async def pair_submit_keyed(fam: str, code: str, request: Request):
    if not _key_ok(fam):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return await _pair_submit(code, request)


async def handle_remote_request(msg: dict, ws: WebSocket) -> None:
    """Le proche propose une session. Rien ne démarre sans l'accord du Mac."""
    if bridge is None:
        await ws.send_json({"type": "refused", "reason": "L'ordinateur n'est pas connecté."})
        return
    s = current_session()
    if s is not None and s.is_open:
        await ws.send_json({"type": "refused", "reason": "Une demande est déjà en cours."})
        return
    names = [h["name"] for h in family.helpers]
    who = str(msg.get("from", "")).strip()
    if who not in names:
        who = names[0] if len(names) == 1 else "Votre proche"
    task = str(msg.get("text", "")).strip()[:300]
    await bridge.send({"type": "remote_request", "from": who, "task": task})
    await ws.send_json({"type": "ack", "what": "remote_request"})
    print("[proches] un proche propose une session")


# ------------------------------------------------------------------ aidant permanent


def current_session():
    """La session la plus récente : c'est celle que suit l'aidant."""
    sessions = list(registry._by_id.values())
    return sessions[-1] if sessions else None


@app.get("/a/{key}")
async def aidant_page(key: str):
    if not secrets.compare_digest(key, AIDANT_KEY):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return FileResponse(STATIC / "helper.html")


@app.websocket("/k/{fam}/ws/aidant/{key}")
async def ws_aidant_keyed(ws: WebSocket, fam: str, key: str) -> None:
    if not _key_ok(fam):
        await ws.close(code=4403)
        return
    await ws_aidant(ws, key)


@app.websocket("/ws/aidant/{key}")
async def ws_aidant(ws: WebSocket, key: str) -> None:
    """Le canal de l'app iPhone : il suit toujours la dernière demande.

    Contrairement au lien par session, il reste ouvert entre deux demandes :
    c'est lui qui « sonne » quand la personne aidée appuie sur le bouton.
    """
    await ws.accept()
    if not secrets.compare_digest(key, AIDANT_KEY):
        await ws.send_json({"type": "refused", "reason": "Lien invalide."})
        await ws.close()
        return
    helper_sockets.add(ws)
    await ws.send_json({"type": "hello", "bridge": bridge is not None,
                        "os": bridge.os if bridge else None})
    s = current_session()
    if s is not None:
        await ws.send_json(s.status())
        if s.last_frame:
            await ws.send_json({"type": "frame", "frame_id": s.last_frame.frame_id,
                                "png_b64": s.last_frame.png_b64})
    try:
        while True:
            msg = await ws.receive_json()
            if msg.get("type") == "remote_request":
                await handle_remote_request(msg, ws)
                continue
            s = current_session()
            if s is None:
                await ws.send_json({"type": "refused", "reason": "Aucune demande en cours."})
                continue
            await handle_helper_msg(s, msg, ws)
    except WebSocketDisconnect:
        pass
    finally:
        helper_sockets.discard(ws)


# Une même situation ne doit pas sonner en boucle : on retient ce qui a déjà
# été signalé, pour ne pas apprendre à la personne à ignorer les alertes.
_guard_vu: dict[str, float] = {}
_guard_taches: set[asyncio.Task] = set()
GUARD_SILENCE_S = 300


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

    dernier = _guard_vu.get(alerte.motif, 0.0)
    if time.time() - dernier < GUARD_SILENCE_S:
        return
    _guard_vu[alerte.motif] = time.time()

    detail = alerte.detail
    s = current_session()
    if alerte.confirmer and s is not None and s.is_open and s.consented:
        # Seulement pendant une session acceptée, où Holo voit déjà l'écran.
        # Hors session, aucune capture ne part : l'alerte repose sur les
        # seuls signaux textuels.
        vu = await confirmer_par_le_modele(alerte)
        if vu:
            detail = detail + "\n\nCe que voit PapAI : " + vu

    print(f"[gardien] {alerte.niveau} — {alerte.motif}", flush=True)
    charge = {
        "type": "alert", "level": alerte.niveau,
        "title": alerte.titre, "detail": detail,
    }
    await broadcast_helper(charge)   # part aussi vers le pont (BRIDGE_TYPES)


async def confirmer_par_le_modele(alerte) -> str:
    """Une capture, un appel, une description. Rien de plus."""
    if bridge is None:
        return ""
    frame = await bridge.capture()
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
    return {"service": "PapAI", "bridge": bridge is not None}


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
    path = (LESSONS_DIR / Path(lesson_id).name / safe).resolve()
    if not str(path).startswith(str(LESSONS_DIR.resolve())) or not path.is_file():
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return FileResponse(path)


def _sessions_journal():
    return [
        {**s.status(), "journal": s.journal}
        for s in registry._by_id.values()
    ]


@app.get("/sessions")
async def list_sessions(request: Request):
    """Le journal des actions, lisible par la personne aidée (section 08).

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
        print(f"[aidant] lien permanent : {PUBLIC_URL}/a/{AIDANT_KEY}")
    else:
        origine = "PAPAI_AIDANT_KEY" if os.environ.get("PAPAI_AIDANT_KEY") else "tirée au hasard"
        print(f"[aidant] lien permanent : {PUBLIC_URL}/a/<clé famille> ({origine} ; "
              "PAPAI_SHOW_KEY=1 pour l'afficher)")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="warning")
