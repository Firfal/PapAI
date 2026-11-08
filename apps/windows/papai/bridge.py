"""Le lien avec le serveur (`/ws/bridge`, voir PROTOCOL.md) et l'exécution.

Port de `apps/mac/Sources/Bridge.swift` et de la partie « messages du serveur »
de `Model.swift`. Envoie `hello` à chaque connexion, se reconnecte toutes les
3 s. Les captures et les actions sont traitées ici, jamais dans la vue.

Deux verrous avant chaque action :
- le verrou d'arrêt local (`StopGate`), qui vaut même hors ligne ;
- le dernier `status` reçu : sans plan validé par l'aidant (`plan_approved`)
  et une session `active` ou `awaiting_helper`, rien ne bouge.
"""

from __future__ import annotations

import asyncio
import json
import threading
import time
import uuid
from typing import Callable

from .core import (ProtectedZone, SensitiveTarget, StopGate, Stopped, UnknownKey,
                   describe_action, run_action)

RECONNECT_S = 3
MAX_SIZE = 16 * 1024 * 1024
STOPPED_TEXT = "Arrêt demandé par la personne aidée."


class Bridge:
    def __init__(self, url: str, gate: StopGate, screen_factory: Callable,
                 on_message: Callable[[dict], None], on_connection: Callable[[bool], None],
                 on_action: Callable[[str], None], protected: Callable[[], tuple | None] = lambda: None,
                 capture_mask: Callable[[], tuple | None] = lambda: None,
                 runner: Callable = run_action,
                 alert_visible: Callable[[], bool] | None = None) -> None:
        self.url = url
        self.gate = gate
        self._screen_factory = screen_factory
        self._screen = None
        self.on_message = on_message
        self.on_connection = on_connection
        self.on_action = on_action
        self.protected = protected
        self.capture_mask = capture_mask
        self.runner = runner
        self._alert: dict | None = None
        self.alert_visible = alert_visible or (lambda: self._alert is not None)
        self.connected = False
        self.last_status: dict = {}
        self._ws = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._task: asyncio.Task | None = None
        self._executions: set[asyncio.Task] = set()

    # ---------------------------------------------------------------- cycle

    def start(self) -> None:
        ready = threading.Event()

        def run() -> None:
            self._loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._loop)
            ready.set()
            self._loop.run_forever()

        threading.Thread(target=run, daemon=True, name="papai-bridge").start()
        ready.wait()
        self.reconnect(self.url)

    def reconnect(self, url: str) -> None:
        self.url = url

        def go() -> None:
            if self._task is not None:
                self._task.cancel()
            self._task = self._loop.create_task(self._run())

        self._loop.call_soon_threadsafe(go)

    def _set_connected(self, ok: bool) -> None:
        if ok != self.connected:
            self.connected = ok
            self.on_connection(ok)

    async def _run(self) -> None:
        import websockets

        while True:
            try:
                async with websockets.connect(self.url, max_size=MAX_SIZE, open_timeout=8) as ws:
                    self._ws = ws
                    await ws.send(json.dumps({"type": "hello", "os": "windows"}))
                    self._set_connected(True)
                    async for raw in ws:
                        try:
                            m = json.loads(raw)
                        except ValueError:
                            continue
                        if isinstance(m, dict):
                            await self._handle(ws, m)
            except asyncio.CancelledError:
                self._ws = None
                self._set_connected(False)
                raise
            except Exception:  # noqa: BLE001 — serveur absent ou coupé
                pass
            self._ws = None
            self._set_connected(False)
            await asyncio.sleep(RECONNECT_S)

    def send(self, payload: dict) -> None:
        """Appelable depuis n'importe quel fil. Sans connexion, le message est perdu
        (le verrou d'arrêt, lui, est déjà levé localement)."""
        ws, loop = self._ws, self._loop
        if ws is None or loop is None:
            return

        async def go() -> None:
            try:
                await ws.send(json.dumps(payload, ensure_ascii=False))
            except Exception:  # noqa: BLE001
                pass

        asyncio.run_coroutine_threadsafe(go(), loop)

    # ------------------------------------------------------------ demandes

    def ask_help(self, task: str, requested_by: str | None = None, ticket: str | None = None) -> None:
        self.gate.reset()
        self.last_status = {}
        msg = {"type": "help_request", "task": task}
        if requested_by:
            msg["requested_by"] = requested_by
        if ticket:
            msg["ticket"] = ticket
        self.send(msg)

    def run_automation(self, lesson_id: str) -> None:
        """Automate importé : plan déjà validé par le support à l'import."""
        self.gate.reset()
        self.last_status = {}
        self.send({"type": "run_automation", "id": lesson_id})

    def stop(self) -> None:
        """Le verrou local passe d'abord, puis le serveur est prévenu."""
        self.gate.raise_stop()
        self.send({"type": "stop"})

    def plan_allows_action(self) -> bool:
        s = self.last_status
        return bool(s.get("plan_approved")) and s.get("state") in ("active", "awaiting_helper")

    # -------------------------------------------------- messages du serveur

    @property
    def screen(self):
        if self._screen is None:
            self._screen = self._screen_factory()
        return self._screen

    async def _handle(self, ws, m: dict) -> None:
        kind = m.get("type")
        if kind == "capture":
            asyncio.create_task(self._capture(ws, str(m.get("req", ""))))
            return
        if kind == "execute":
            task = asyncio.create_task(self._execute(ws, str(m.get("req", "")), m.get("action") or {}))
            self._executions.add(task)
            task.add_done_callback(self._executions.discard)
            return
        if kind == "alert":
            self._alert = m
            self.gate.raise_stop()
        elif kind == "alert_cleared" and self._alert and m.get("alert_id") == self._alert.get("alert_id") and m.get("alert_id"):
            self._alert = None
        if kind == "alert" and (m.get("level") == "danger" or m.get("blocked")):
            self.gate.raise_stop()
            for task in self._executions:
                task.cancel()
        if kind == "status":
            self.last_status = m
        self.on_message(m)

    async def _capture(self, ws, req: str) -> None:
        if self.gate.is_stopped:
            return
        try:
            b64, w, h = await asyncio.to_thread(self.screen.grab, self.capture_mask())
        except Exception as e:  # noqa: BLE001
            print(f"[papai] capture impossible : {type(e).__name__}: {e}", flush=True)
            return
        if self.gate.is_stopped:
            return
        await ws.send(json.dumps({"type": "frame", "req": req, "frame_id": uuid.uuid4().hex[:8],
                                  "png_b64": b64, "width": w, "height": h}))

    async def _execute(self, ws, req: str, action: dict) -> None:
        name = str(action.get("name") or "")
        args = action.get("args") or {}
        if not isinstance(args, dict):
            args = {}

        async def reply(text: str, refused: bool, blocked: str | None = None) -> None:
            message = {"type": "result", "req": req, "result": text, "refused": refused}
            if blocked:
                message["blocked"] = blocked
            await ws.send(json.dumps(message, ensure_ascii=False))

        if self.gate.is_stopped:
            await reply(STOPPED_TEXT, True)
            return
        if self.alert_visible():
            await reply("Assistance arrêtée ou alerte du gardien en attente.", True)
            return
        if not self.plan_allows_action():
            await reply("Action refusée : aucun plan validé par le support.", True)
            return
        self.on_action(describe_action(name, args))
        gate = self.gate.pin()
        try:
            text = await asyncio.to_thread(self.runner, name, args, self.screen, gate,
                                           self.protected())
            if gate.is_stopped:
                raise Stopped()
            await reply(text, False)
        except asyncio.CancelledError:
            await reply(STOPPED_TEXT, True)
            raise
        except Stopped:
            await reply(STOPPED_TEXT, True)
        except ProtectedZone:
            await reply("Action refusée par PapAI : cette zone appartient à PapAI. "
                        "Ne réessaie pas : appelle ask_helper pour que le support s'en occupe.",
                        False, "sensitive")
        except SensitiveTarget as e:
            await reply(f"Action refusée par PapAI : {e}. "
                        "Ne réessaie pas : appelle ask_helper pour que le support s'en occupe.",
                        False, "sensitive")
        except UnknownKey as e:
            await reply(f"Touche inconnue : {e}", False)
        except Exception as e:  # noqa: BLE001
            await reply(f"échec : {type(e).__name__}: {e}", True)


def wait_until(pred: Callable[[], bool], timeout: float) -> bool:
    end = time.time() + timeout
    while time.time() < end:
        if pred():
            return True
        time.sleep(0.05)
    return pred()
