"""Backend CarePilot : sessions, verrou de contrôle, relais vers le pont.

Deux WebSockets :
  /ws/bridge          le PC de la personne aidée (capture et exécution)
  /ws/helper/{token}  la page du proche (captures, questions, clics)

Rien de ce que dit la page du proche n'est cru sur parole : chaque message
repasse par les contrôles de sessions.py.
"""

from __future__ import annotations

import asyncio
import os
import secrets
from pathlib import Path

import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse

from .agent import AgentRunner
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


# En production, CAREPILOT_PUBLIC_URL porte l'URL publique du service hébergé.
PUBLIC_URL = os.environ.get("CAREPILOT_PUBLIC_URL") or f"http://{_lan_ip()}:{os.environ.get('PORT', '8000')}"

app = FastAPI(title="CarePilot")
registry = Registry()


def _pairing_token() -> str:
    """Le lien permanent du proche, stable d'un démarrage à l'autre.

    C'est l'appairage : il identifie le proche, et rien de plus. Il ne donne
    aucun accès à l'écran — seulement le droit de PROPOSER son aide. C'est la
    personne aidée qui accepte, sur sa machine, et cette acceptation vaut
    consentement au partage.
    """
    f = LESSONS_DIR / "pairing.txt"
    try:
        if f.is_file():
            tok = f.read_text(encoding="utf-8").strip()
            if tok:
                return tok
        tok = secrets.token_urlsafe(18)
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(tok, encoding="utf-8")
        return tok
    except OSError:
        return secrets.token_urlsafe(18)


PAIRING = _pairing_token()

# Proches connectés au lien permanent, en attente d'une occasion d'aider.
pairing_sockets: set[WebSocket] = set()
# Invitation en cours, le temps que la personne aidée réponde.
pending_invitation: dict | None = None


class BridgeLink:
    """Le pont Windows, vu du serveur. Un seul à la fois dans le MVP."""

    def __init__(self, ws: WebSocket) -> None:
        self.ws = ws
        self._pending: dict[str, asyncio.Future] = {}

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


async def broadcast_helper(payload: dict) -> None:
    dead = []
    for ws in helper_sockets:
        try:
            await ws.send_json(payload)
        except Exception:  # noqa: BLE001
            dead.append(ws)
    for ws in dead:
        helper_sockets.discard(ws)


# ------------------------------------------------------------------ pont


@app.websocket("/ws/bridge")
async def ws_bridge(ws: WebSocket) -> None:
    global bridge, agent_task
    await ws.accept()
    bridge = BridgeLink(ws)
    print("[pont] connecté")
    pairing_url = f"{PUBLIC_URL}/aidant/{PAIRING}"
    print(f"[pont] lien permanent du proche : {pairing_url}")
    await ws.send_json({"type": "pairing", "url": pairing_url})
    try:
        while True:
            msg = await ws.receive_json()
            kind = msg.get("type")

            if kind in ("frame", "result"):
                bridge.resolve(msg.get("req", ""), msg)
                continue

            if kind == "help_request":
                session = registry.create(msg.get("task", "").strip())
                session.grant_consent()  # le consentement est donné dans la même fenêtre
                url = f"{PUBLIC_URL}/h/{session.helper_token}"
                await ws.send_json({"type": "session", "id": session.id, "helper_url": url})
                print(f"[session {session.id}] {session.task}")
                print(f"[session {session.id}] lien du proche : {url}")
                await broadcast_helper(session.status())

                if agent_task and not agent_task.done():
                    agent_task.cancel()
                agent_task = asyncio.create_task(
                    AgentRunner(session, bridge, broadcast_helper).run()
                )
                continue

            if kind == "invitation_response":
                # La personne aidée a répondu à une proposition d'aide.
                global pending_invitation
                invitation, pending_invitation = pending_invitation, None
                if not msg.get("accepted") or invitation is None:
                    await broadcast_pairing(
                        {"type": "declined", "reason": "Votre proche n'a pas souhaité d'aide."}
                    )
                    continue

                session = registry.create(invitation["text"])
                session.grant_consent()  # accepter l'invitation, c'est consentir
                session.log("initiated_by", who="helper")
                url = f"{PUBLIC_URL}/h/{session.helper_token}"
                await ws.send_json({"type": "session", "id": session.id, "helper_url": url})
                await broadcast_pairing({"type": "accepted", "helper_url": url})
                print(f"[session {session.id}] proposée par le proche, acceptée")

                if agent_task and not agent_task.done():
                    agent_task.cancel()
                agent_task = asyncio.create_task(
                    AgentRunner(session, bridge, broadcast_helper).run()
                )
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

    except WebSocketDisconnect:
        print("[pont] déconnecté")
    finally:
        bridge = None
        for s in list(registry._by_id.values()):
            if s.is_open:
                s.stop(by="pont déconnecté")
                await broadcast_helper(s.status())


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
                    continue

            try:
                if kind == "answer":
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
                    lesson = await draft_lesson(session)
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

                else:
                    await ws.send_json({"type": "refused", "reason": "Message inconnu."})

            except Refused as e:
                await ws.send_json({"type": "refused", "reason": str(e)})

    except WebSocketDisconnect:
        pass
    finally:
        helper_sockets.discard(ws)


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


@app.get("/")
async def root():
    return {"service": "CarePilot", "bridge": bridge is not None}


@app.get("/aidant/{pairing}")
async def helper_standing_page(pairing: str):
    """Le lien permanent du proche. Ne montre aucun écran : il propose, c'est tout."""
    if not secrets.compare_digest(pairing, PAIRING):
        return JSONResponse({"error": "Lien invalide."}, status_code=404)
    return FileResponse(STATIC / "aidant.html")


@app.websocket("/ws/aidant/{pairing}")
async def ws_pairing(ws: WebSocket, pairing: str) -> None:
    global pending_invitation
    if not secrets.compare_digest(pairing, PAIRING):
        await ws.accept()
        await ws.send_json({"type": "refused", "reason": "Lien invalide."})
        await ws.close()
        return

    await ws.accept()
    pairing_sockets.add(ws)
    await ws.send_json({"type": "ready", "pc_connected": bridge is not None})
    try:
        while True:
            msg = await ws.receive_json()
            if msg.get("type") != "offer_help":
                continue
            if bridge is None:
                await ws.send_json({"type": "refused", "reason": "L'ordinateur n'est pas allumé."})
                continue

            text = str(msg.get("text", "")).strip()[:200]
            pending_invitation = {"text": text}
            # On propose : rien ne démarre tant que la personne aidée n'a pas
            # accepté sur sa propre machine.
            await bridge.send({"type": "invitation", "text": text})
            await ws.send_json({"type": "waiting"})
    except WebSocketDisconnect:
        pass
    finally:
        pairing_sockets.discard(ws)


async def broadcast_pairing(payload: dict) -> None:
    for ws in list(pairing_sockets):
        try:
            await ws.send_json(payload)
        except Exception:  # noqa: BLE001
            pairing_sockets.discard(ws)


@app.get("/lessons")
async def lessons():
    """Les fiches validées par un proche. Les brouillons ne sortent jamais d'ici."""
    return list_lessons()


@app.get("/lessons/{lesson_id}/{filename}")
async def lesson_file(lesson_id: str, filename: str):
    """Sert une capture de fiche. Chemins cloisonnés : pas de remontée possible."""
    safe = Path(filename).name
    path = (LESSONS_DIR / Path(lesson_id).name / safe).resolve()
    if not str(path).startswith(str(LESSONS_DIR.resolve())) or not path.is_file():
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return FileResponse(path)


@app.get("/sessions")
async def list_sessions():
    """Le journal des actions, lisible par la personne aidée (section 08).

    Sert aussi de point d'observation pendant les essais.
    """
    return [
        {**s.status(), "journal": s.journal}
        for s in registry._by_id.values()
    ]


if __name__ == "__main__":
    STATIC.mkdir(exist_ok=True)
    # Les hébergeurs imposent le port par la variable PORT.
    port = int(os.environ.get("PORT", "8000"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="warning")
