"""Agent navigateur de H (Agents API) pour les tâches qui se font dans un navigateur.

H pilote « Chrome PapAI », un Chrome à part que l'app de la personne aidée sert
avec `holo local browser --session-id <id>`. Le serveur ne fait que créer la
session H, relayer ses événements aux aidants et répondre à `ask_helper`.
Rien ici ne dépend du Mac : une autre app qui annonce un `web_agent` suffit.

Le plan est toujours validé avant : ce module n'est appelé qu'après
`approve_plan`, une fois le gardien passé.
"""
from __future__ import annotations

import asyncio
import os
import re
import secrets

# Obligatoire côté serveur : sinon le SDK branche le navigateur ou l'écran du
# serveur lui-même au lieu de celui de la personne aidée.
os.environ["HAI_AUTO_BRIDGE"] = "0"

from papai_tools import WEB_AGENT_INSTRUCTIONS  # noqa: E402

from .sessions import Frame, Refused, Session  # noqa: E402

ENV_ID = "papai-chrome"
MAX_STEPS = int(os.environ.get("PAPAI_WEB_MAX_STEPS", "40"))
MAX_TIME_S = float(os.environ.get("PAPAI_WEB_MAX_TIME_S", "900"))
PAUSE_POLL_S = 0.3
START_SESSION_CLEANUP_TIMEOUT_S = 15.0
DONE_DEFAULT = "C'est fait."

ASK_HELPER_DESCRIPTION = (
    "Pose une question au support de la personne et attends sa réponse. "
    "À utiliser avant tout paiement, virement, achat, inscription, suppression, "
    "ou si une page demande de payer, d'installer, d'appeler ou d'autoriser un accès à distance."
)

ASK_SENIOR_DESCRIPTION = (
    "Demande quelque chose à la personne aidée elle-même, sur son écran, et attends sa réponse. "
    "À utiliser quand une page demande de se connecter : elle se connecte elle-même, puis tu continues. "
    "Jamais pour obtenir un mot de passe, un code ou un numéro de carte."
)

_BROWSER_SESSION = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
_STEP = re.compile(r"\b[ÉéEe]tape\s+(\d+)\b")


def valid_browser_session(value) -> str | None:
    """L'identifiant annoncé par l'app : UUID canonique en minuscules."""
    if isinstance(value, dict):
        value = value.get("session_id")
    if isinstance(value, str) and re.fullmatch(_BROWSER_SESSION, value):
        return value
    return None


def environment(browser_session: str) -> dict:
    return {"id": ENV_ID, "kind": "web", "host": "user_device", "session_id": browser_session}


def agent_spec(browser_session: str) -> dict:
    return {
        "name": "papai-navigateur",
        "description": "Aide une personne dans son navigateur, sous le contrôle de son support.",
        "environments": [environment(browser_session)],
        "instructions": WEB_AGENT_INSTRUCTIONS,
    }


def brief(session: Session, notes: list[str] | None = None) -> str:
    """La demande, le plan validé et les consignes, en un seul message."""
    lines = [f"Demande de la personne : « {session.task} »"]
    for n in notes or []:
        if n:
            lines.append(f"Précision du support : {n}")
    if session.plan:
        lines.append("")
        lines.append("Plan validé par le support, à suivre :")
        lines += [f"Étape {i}. {s}" for i, s in enumerate(session.plan, 1)]
        lines.append("Avant chaque action, écris « Étape N » pour l'étape du plan en cours.")
    lines.append("")
    lines.append(WEB_AGENT_INSTRUCTIONS)
    return "\n".join(lines)


def describe_web_action(tool: str, args: dict) -> str:
    """Une phrase pour le support, comme `describe_doing` en mode bureau."""
    t = (tool or "").lower()
    a = args or {}
    cible = str(a.get("element") or a.get("target") or a.get("description") or a.get("selector") or "").strip()[:80]
    url = str(a.get("url") or "").strip()
    if t in ("ask_helper",):
        return "Holo vous pose une question"
    if t == "ask_senior":
        return "Holo pose une question à la personne aidée"
    if "navigate" in t or "goto" in t or "open" in t or url:
        site = re.sub(r"^https?://(www\.)?", "", url).split("/")[0] if url else ""
        return f"Holo ouvre {site}" if site else "Holo ouvre une page"
    if "click" in t:
        return f"Holo clique sur {cible}" if cible else "Holo clique dans la page"
    if "type" in t or "write" in t or "fill" in t:
        txt = str(a.get("text") or a.get("value") or "").strip()
        return f"Holo écrit « {txt[:60]} »" if txt else "Holo écrit dans la page"
    if "scroll" in t:
        return "Holo fait défiler la page"
    if "back" in t:
        return "Holo revient à la page précédente"
    if "key" in t or "press" in t:
        return "Holo appuie sur une touche"
    if "wait" in t:
        return "Holo attend que la page se charge"
    if "tab" in t:
        return "Holo change d'onglet"
    return "Holo regarde la page"


def _answer_text(answer) -> str:
    if isinstance(answer, str):
        return answer.strip()
    if isinstance(answer, dict):
        for k in ("content", "text", "answer", "message"):
            if isinstance(answer.get(k), str):
                return answer[k].strip()
    return ""


def make_client():
    """Client asynchrone de l'Agents API. La clé reste dans l'environnement du serveur."""
    from hai_agents import AsyncClient

    kwargs = {"api_key": os.environ.get("HAI_API_KEY") or None}
    base = os.environ.get("HAI_AGENTS_BASE_URL")
    if base:
        kwargs["base_url"] = base
    client = AsyncClient(**kwargs)
    client._auto_bridges = False  # HAI_AUTO_BRIDGE seul ne suffit pas à empêcher un pont local.
    return client


class WebAgentRunner:
    """Pilote une session H web du plan validé jusqu'à la réponse ou l'arrêt.

    Même contrat que `AgentRunner` : la session PapAI ne reste jamais ouverte
    sans pilote, et toute sortie anticipée annule la session H.
    """

    def __init__(self, session: Session, browser_session: str, broadcast,
                 notes: list[str] | None = None, client=None) -> None:
        self.s = session
        self.browser_session = browser_session
        self.broadcast = broadcast
        self.notes = notes or []
        self.client = client
        self.handle = None
        self._h_paused = False
        self._answer = ""
        self._cancel_task: asyncio.Future | None = None

    async def run(self) -> None:
        watcher = None
        try:
            if not self.s.is_open:
                return
            self.s.last_frame = None
            from hai_agents import tool

            ask = tool(name="ask_helper", description=ASK_HELPER_DESCRIPTION)(self._ask_helper_tool)
            ask_senior = tool(name="ask_senior", description=ASK_SENIOR_DESCRIPTION)(self._ask_senior_tool)
            self.client = self.client or make_client()
            # Dès la création, H peut agir sans repasser par nous.
            self.s.execution_started = True
            self.s.doing = "Holo ouvre le navigateur"
            await self.broadcast(self.s.status())
            creation = asyncio.create_task(self.client.start_session(
                agent=agent_spec(self.browser_session),
                messages=brief(self.s, self.notes),
                tools=[ask, ask_senior],
                max_steps=MAX_STEPS,
                max_time_s=MAX_TIME_S,
                idempotency_key=f"papai-{self.s.id}-{secrets.token_hex(4)}",
            ))
            late_cancel_armed = False

            def arm_late_cancel() -> None:
                nonlocal late_cancel_armed
                if not creation.done() and not late_cancel_armed:
                    creation.add_done_callback(self._cancel_late_creation)
                    late_cancel_armed = True

            try:
                self.handle = await asyncio.shield(creation)
            except asyncio.CancelledError:
                arm_late_cancel()
                try:
                    self.handle = await asyncio.wait_for(
                        asyncio.shield(creation), timeout=START_SESSION_CLEANUP_TIMEOUT_S
                    )
                except asyncio.CancelledError:
                    arm_late_cancel()
                    raise
                except asyncio.TimeoutError:
                    arm_late_cancel()
                except Exception:
                    pass
                if self.handle is not None:
                    await self._cancel_remote()
                raise
            self.s.log("web_agent_started", h_session=self.handle.id)
            watcher = asyncio.create_task(self._watch())
            async for event in self.handle.stream(tools=[ask]):
                if not self.s.is_open:
                    break
                await self._on_event(event)
            if not self.s.is_open:
                return
            status = await self.handle.status()
            st = getattr(status, "status", "")
            if st in ("completed", "idle") or self._answer:
                text = self._answer or DONE_DEFAULT
                self.s.finish(text)
                await self.broadcast({"type": "answer", "content": text})
            else:
                self.s.log("web_agent_ended", status=str(st), error=str(getattr(status, "error", "") or "")[:200])
                self.s.stop(by="navigateur")
        except Refused as e:
            self.s.log("refused", reason=str(e))
        except asyncio.CancelledError:
            self.s.stop(by="annulation")
            raise
        except Exception as e:  # noqa: BLE001 — un plantage ne doit pas laisser la session ouverte
            self.s.log("error", error=f"{type(e).__name__}: {e}"[:300])
            if self.s.is_open:
                self.s.stop(by="erreur interne")
        finally:
            if watcher:
                watcher.cancel()
            if not self.s.is_open and self.s.state.value != "done":
                await asyncio.shield(self._cancel_remote())
            await self.broadcast(self.s.status())

    async def _cancel_remote(self) -> None:
        # Une seule annulation, menée à terme même si l'appelant (watcher) est annulé.
        if self.handle is None:
            return
        if self._cancel_task is None:
            self._cancel_task = asyncio.ensure_future(self._do_cancel())
        await asyncio.shield(self._cancel_task)

    def _cancel_late_creation(self, task: asyncio.Task) -> None:
        try:
            handle = task.result()
        except (asyncio.CancelledError, Exception):
            return
        if self.handle is not None:
            return
        self.handle = handle
        if self._cancel_task is None:
            asyncio.create_task(self._cancel_remote())

    async def _do_cancel(self) -> None:
        try:
            await asyncio.wait_for(self.handle.cancel(), timeout=10)
            self.s.log("web_agent_cancelled", h_session=self.handle.id)
        except Exception as e:  # noqa: BLE001
            self.s.log("web_agent_cancel_failed", error=type(e).__name__)

    async def _watch(self) -> None:
        """Pause, reprise et arrêt décidés côté PapAI, reportés sur la session H."""
        while True:
            await asyncio.sleep(PAUSE_POLL_S)
            if not self.s.is_open:
                await self._cancel_remote()
                return
            try:
                if self.s.paused and not self._h_paused:
                    self._h_paused = True
                    await self.handle.pause()
                    self.s.log("web_agent_paused")
                elif not self.s.paused and self._h_paused and self.s.question is None:
                    self._h_paused = False
                    await self.handle.resume()
                    self.s.log("web_agent_resumed")
                if self.s.pause_requested:
                    self.s.pause_requested = False
                    await self._helper_pause()
            except asyncio.CancelledError:
                raise
            except Exception as e:  # noqa: BLE001 — H peut refuser une pause déjà en cours
                self.s.log("web_agent_control_failed", error=type(e).__name__)

    async def _helper_pause(self) -> None:
        """Le support a demandé une pause : H s'arrête, puis on lui demande quoi faire."""
        if not self._h_paused:
            await self.handle.pause()
            self._h_paused = True
        reply = await self._escalate("Vous avez mis l'assistance en pause. Que faut-il faire ?",
                                     ["Continuer", "Indiquez-moi quoi faire"])
        if reply is None or not self.s.is_open:
            return
        if self.s.paused:
            return  # la personne aidée a aussi mis en pause : sa reprise relancera H
        self._h_paused = False
        if reply.strip().lower() == "continuer":
            await self.handle.resume()
        else:
            await self.handle.send_message(f"Consigne du support : {reply}")
            await self.handle.resume()

    async def _escalate(self, question: str, options: list[str] | None = None,
                        to: str = "helper") -> str | None:
        fut = self.s.ask_helper(question, options or [], to=to)
        await self.broadcast(self.s.status())
        await self.broadcast({"type": "question", "question": question, "options": options or [], "to": to})
        reply = await fut
        if reply is None or not self.s.is_open:
            return None
        return reply

    async def _ask_helper_tool(self, question: str) -> str:
        """Pose une question au support et attends sa réponse."""
        self.s.doing = describe_web_action("ask_helper", {})
        self.s.log("tool_call", tool="ask_helper", args={"question": question[:300]})
        reply = await self._escalate(str(question)[:300])
        if reply is None:
            return "L'assistance est arrêtée. Arrête-toi tout de suite, sans rien faire d'autre."
        return f"Réponse du support : {reply}"

    async def _ask_senior_tool(self, question: str) -> str:
        """Demande à la personne aidée elle-même (se connecter à un site…) et attends sa réponse."""
        self.s.doing = describe_web_action("ask_senior", {})
        self.s.log("tool_call", tool="ask_senior", args={"question": question[:300]})
        reply = await self._escalate(str(question)[:300], to="senior")
        if reply is None:
            return "L'assistance est arrêtée. Arrête-toi tout de suite, sans rien faire d'autre."
        return f"Réponse de la personne aidée : {reply}"

    async def _on_event(self, event) -> None:
        ev = event.model_dump(mode="json") if hasattr(event, "model_dump") else dict(event)
        data = ev.get("data") or {}
        if not isinstance(data, dict):
            return
        kind = data.get("kind")
        if kind == "policy_event":
            text = " ".join(str(data.get(k) or "") for k in ("content", "reasoning_content"))
            m = _STEP.search(text)
            if m:
                self.s.advance_plan(int(m.group(1)))
            for req in data.get("tool_reqs") or []:
                name = str(req.get("tool_name", ""))
                args = req.get("args") or {}
                if name in ("ask_helper", "ask_senior"):
                    continue
                self.s.doing = describe_web_action(name, args)
                self.s.log("tool_call", tool=name, web=True)
                await self.broadcast(self.s.status())
        elif kind == "observation_event":
            img = data.get("image") or {}
            if img.get("type") == "base64" and img.get("source"):
                b64 = img["source"]
                frame = Frame(frame_id=secrets.token_hex(6), png_b64=b64, width=0, height=0)
                self.s.set_frame(frame)
                await self.broadcast({"type": "frame", "frame_id": frame.frame_id, "png_b64": b64})
        elif kind == "answer_event":
            self._answer = _answer_text(data.get("answer")) or self._answer
