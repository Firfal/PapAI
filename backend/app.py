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

from .agent import AgentRunner, propose_plan
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

app = FastAPI(title="PapAI")
registry = Registry()

# Clé du lien permanent de l'aidant (app iPhone ou page /a/{clé}). Stable d'un
# lancement à l'autre si on la fixe dans .env, sinon tirée au démarrage.
AIDANT_KEY = os.environ.get("PAPAI_AIDANT_KEY") or secrets.token_urlsafe(9)

# En ligne, tout passe par /k/{clé de la famille}/… : sans la clé, personne ne
# peut se faire passer pour le PC de la personne aidée, ni lire ses fiches.
# Les routes sans clé ne restent ouvertes qu'en local (PAPAI_PUBLIC absent).
PUBLIC_MODE = os.environ.get("PAPAI_PUBLIC", "") == "1"


def _key_ok(fam: str) -> bool:
    return secrets.compare_digest(fam or "", AIDANT_KEY)


class BridgeLink:
    """Le pont Windows, vu du serveur. Un seul à la fois dans le MVP."""

    def __init__(self, ws: WebSocket) -> None:
        self.ws = ws
        self._pending: dict[str, asyncio.Future] = {}
        self.os = "windows"  # annoncé par le pont dans son message hello

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
    if PUBLIC_MODE:
        await ws.close(code=4403)
        return
    await _ws_bridge(ws)


async def _ws_bridge(ws: WebSocket) -> None:
    global bridge, agent_task
    await ws.accept()
    bridge = BridgeLink(ws)
    print("[pont] connecté")
    try:
        while True:
            msg = await ws.receive_json()
            kind = msg.get("type")

            if kind in ("frame", "result"):
                bridge.resolve(msg.get("req", ""), msg)
                continue

            if kind == "hello":
                bridge.os = str(msg.get("os", "windows")).lower()
                print(f"[pont] système : {bridge.os}")
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
                agent_task = asyncio.create_task(run_session(session, bridge))
                continue

            if kind == "automation_failed":
                # Un automatisme n'a pas pu se rejouer : l'écran ou le dossier a
                # changé. On ne tente rien à l'aveugle, on prévient l'aidant.
                await broadcast_helper({
                    "type": "alert",
                    "title": str(msg.get("title", "Un raccourci")),
                    "detail": str(msg.get("detail", "")),
                })
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
            print(f"[session {session.id}] plan proposé : {steps}")
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
            s = current_session()
            if s is None:
                await ws.send_json({"type": "refused", "reason": "Aucune demande en cours."})
                continue
            await handle_helper_msg(s, msg, ws)
    except WebSocketDisconnect:
        pass
    finally:
        helper_sockets.discard(ws)


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


@app.get("/lessons")
async def lessons():
    if PUBLIC_MODE:
        return JSONResponse({"error": "introuvable"}, status_code=404)
    """Les fiches validées par un proche. Les brouillons ne sortent jamais d'ici."""
    return list_lessons()


@app.get("/lessons/{lesson_id}/{filename}")
async def lesson_file(lesson_id: str, filename: str):
    if PUBLIC_MODE:
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return _serve_lesson_file(lesson_id, filename)


def _serve_lesson_file(lesson_id: str, filename: str):
    """Sert une capture de fiche. Chemins cloisonnés : pas de remontée possible."""
    safe = Path(filename).name
    path = (LESSONS_DIR / Path(lesson_id).name / safe).resolve()
    if not str(path).startswith(str(LESSONS_DIR.resolve())) or not path.is_file():
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return FileResponse(path)


@app.get("/sessions")
async def list_sessions():
    """Le journal des actions, lisible par la personne aidée (section 08).

    Sert aussi de point d'observation pendant les essais. Fermé en ligne.
    """
    if PUBLIC_MODE:
        return JSONResponse({"error": "introuvable"}, status_code=404)
    return [
        {**s.status(), "journal": s.journal}
        for s in registry._by_id.values()
    ]


if __name__ == "__main__":
    STATIC.mkdir(exist_ok=True)
    # Les hébergeurs imposent le port par la variable PORT.
    port = int(os.environ.get("PORT", "8000"))
    print(f"[aidant] lien permanent : {PUBLIC_URL}/a/{AIDANT_KEY}")
    print(f"[aidant] app iPhone : serveur {PUBLIC_URL}  clé {AIDANT_KEY}")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="warning")
