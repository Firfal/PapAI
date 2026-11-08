"""La boucle agent, côté serveur.

Elle décide ; elle n'agit pas. Chaque action part vers le pont Windows, qui
reste libre de la refuser — l'arrêt est appliqué sur la machine pilotée, pas ici.
"""

from __future__ import annotations

import asyncio
import json
import re
import time

from papai_tools import (
    MIN_SECONDS_PER_STEP,
    PLAN_PROMPT,
    system_prompt,
    TEMPERATURE,
    TOOLS,
    ACTUATING_TOOLS,
    MODEL,
    make_client,
    observation,
    to_assistant_message,
    trim_to_last_n_images,
)

from .sessions import Owner, Refused, Session, State
from . import space

import os

# Abaissé pendant les essais : un agent qui tâtonne sur un vrai bureau coûte
# des clics imprévus. 25 en usage normal.
# CAREPILOT_MAX_STEPS : ancien nom, encore lu pour les déploiements existants.
MAX_STEPS = int(os.environ.get("PAPAI_MAX_STEPS") or os.environ.get("CAREPILOT_MAX_STEPS") or "25")

client = make_client()


class SensitiveBlocked(str):
    def __new__(cls, result: str):
        text = str(result or "Action refusée par PapAI : action sensible bloquée.")
        if "appelle ask_helper" not in text:
            text += " Ne réessaie pas : appelle ask_helper pour que le support s'en occupe."
        return super().__new__(cls, text)

    @property
    def reason(self) -> str:
        return self.removeprefix("Action refusée par PapAI : ").split(". Ne réessaie pas", 1)[0].rstrip(".")


def protected_window_support_text(click: bool = False) -> str:
    name = space.current().family.senior.strip() or "la personne aidée"
    if click:
        return ("Clic non effectué : cette fenêtre est protégée (réglages ou mots de passe). "
                f"Guidez {name} par téléphone pour faire cette étape sur l'ordinateur.")
    return ("Holo s'est arrêté devant une fenêtre protégée (réglages ou mots de passe). "
            f"Guidez {name} par téléphone, puis répondez ici pour que Holo continue.")


async def propose_plan(session: Session, bridge, broadcast, note: str = "") -> list[str]:
    """Une capture, un appel à Holo, aucune action : un plan à faire valider."""
    frame = await bridge.capture()
    messages = [
        {"role": "system", "content": PLAN_PROMPT.format(os="Mac" if bridge.os == "macos" else "Windows")},
        {"role": "user", "content": f"Demande de la personne : « {session.task} »"
            + (f"\nPrécision de son support : {note}" if note else "")},
    ]
    if frame is not None:
        session.set_frame(frame)
        await broadcast({"type": "frame", "frame_id": frame.frame_id, "png_b64": frame.png_b64})
        messages.append(observation(frame.png_b64))
    try:
        resp = await asyncio.to_thread(
            client.chat.completions.create,
            model=MODEL, messages=messages, temperature=TEMPERATURE,
        )
        session.record_usage(getattr(resp, "usage", None))
        raw = resp.choices[0].message.content or ""
        m = re.search(r"\{.*\}", raw, re.S)
        data = json.loads(m.group(0))
        steps = [str(x).strip() for x in data.get("steps", []) if str(x).strip()]
        where = str(data.get("where", "")).strip().lower()
        session.where = where if where in ("web", "desktop") else "desktop"
    except Exception as e:  # noqa: BLE001 — un plan minimal vaut mieux qu'une session bloquée
        session.log("plan_failed", error=f"{type(e).__name__}: {e}")
        steps = []
        session.where = "desktop"
    return steps[:5] or [f"Faire : {session.task}"]


_FR = re.compile(r"\b(je|le|la|les|de|du|des|un|une|sur|pour|dans|est|il|vais)\b", re.I)


def describe_doing(thought: str, name: str, args: dict) -> str:
    """Une seule phrase pour l'aidant : ce que Holo fait, d'après ce qu'il pense.

    Holo écrit parfois sa réflexion avant d'agir : on en garde la première
    phrase, si elle est en français. Sinon on décrit l'action elle-même.
    """
    t = re.sub(r"\s+", " ", (thought or "")).strip()
    t = re.sub(r"^(thought|pensée|réflexion)\s*:\s*", "", t, flags=re.I)
    if t and len(_FR.findall(t)) >= 2:
        first = re.split(r"(?<=[.!?])\s", t, maxsplit=1)[0].strip()
        if len(first) > 120:
            first = first[:117].rsplit(" ", 1)[0] + "…"
        if len(first) >= 12:
            return first[0].upper() + first[1:]
    cible = str(args.get("element", "")).strip()
    if name == "click":
        return f"Holo clique sur {cible}" if cible else "Holo clique sur l'écran"
    if name == "double_click":
        return f"Holo ouvre {cible}" if cible else "Holo ouvre un élément"
    if name == "type_text":
        txt = str(args.get("text", "")).strip()
        return f"Holo écrit « {txt[:60]} »" if txt else "Holo écrit au clavier"
    if name == "press_key":
        k = str(args.get("keys", "")).strip().lower()
        return {"enter": "Holo valide avec Entrée", "return": "Holo valide avec Entrée",
                "esc": "Holo ferme avec Échap", "escape": "Holo ferme avec Échap",
                "cmd+space": "Holo ouvre la recherche du Mac"}.get(k, f"Holo appuie sur {k}" if k else "Holo appuie sur une touche")
    if name == "scroll":
        return "Holo fait défiler la page"
    if name == "wait":
        return "Holo attend que l'ordinateur réponde"
    if name == "ask_helper":
        return "Holo vous pose une question"
    if name == "ask_senior":
        return "Holo pose une question à la personne aidée"
    if name == "answer":
        return "Holo termine"
    return "Holo regarde l'écran"


class AgentRunner:
    """Pilote une session du premier screenshot jusqu'à `answer` ou l'arrêt."""

    def __init__(self, session: Session, bridge, broadcast, notes: list[str] | None = None) -> None:
        self.s = session
        self.bridge = bridge
        self.broadcast = broadcast  # async (dict) -> None, vers le proche
        self.notes = notes or []
        self._sensitive_blocked: SensitiveBlocked | None = None

    async def run(self) -> None:
        try:
            await self._loop()
            if self.s.is_open:
                # Sortie de boucle sans réponse : le pont a refusé ou n'a plus
                # répondu. Une session ne reste jamais ouverte sans pilote.
                self.s.stop(by="pont")
        except Refused as e:
            self.s.log("refused", reason=str(e))
        except asyncio.CancelledError:
            self.s.stop(by="annulation")
            raise
        except Exception as e:  # noqa: BLE001 — un plantage ne doit pas laisser la session ouverte
            self.s.log("error", error=f"{type(e).__name__}: {e}")
            self.s.stop(by="erreur interne")
        finally:
            await self.broadcast(self.s.status())

    async def _loop(self) -> None:
        brief = self.s.task
        if self.s.plan:
            brief += "\n\nPlan validé par le support, à suivre :\n" + "\n".join(
                f"{i}. {step}" for i, step in enumerate(self.s.plan, 1)
            )
            brief += "\nÀ chaque action, indique dans plan_step le numéro de l'étape du plan que tu exécutes."
        for n in self.notes:
            brief += f"\nPrécision du support : {n}"
        messages = [
            {"role": "system", "content": system_prompt(self.bridge.os)},
            {"role": "user", "content": brief},
        ]

        for step in range(1, MAX_STEPS + 1):
            if not self.s.is_open:
                return

            # En pause : Holo attend, sans rien faire, que la personne reprenne.
            while self.s.paused and self.s.is_open:
                await asyncio.sleep(0.4)
            if not self.s.is_open:
                return

            started = time.time()

            frame = await self.bridge.capture()
            if frame is None:
                self.s.log("capture_failed")
                return
            self.s.set_frame(frame)
            await self.broadcast(
                {"type": "frame", "frame_id": frame.frame_id, "png_b64": frame.png_b64}
            )

            messages.append(observation(frame.png_b64))
            trim_to_last_n_images(messages)

            resp = await asyncio.to_thread(
                client.chat.completions.create,
                model=MODEL,
                messages=messages,
                tools=TOOLS,
                tool_choice="required",
                temperature=TEMPERATURE,
            )
            msg = resp.choices[0].message

            usage = self.s.record_usage(getattr(resp, "usage", None))
            self.s.log("usage", **usage)
            await self.bridge.send({"type": "usage", **usage})
            await self.broadcast({"type": "usage", **usage})

            messages.append(to_assistant_message(msg))

            if not msg.tool_calls:
                self.s.log("no_action", step=step)
                continue

            for call in msg.tool_calls:
                name = call.function.name
                args = json.loads(call.function.arguments or "{}")
                self.s.advance_plan(args.pop("plan_step", None))
                self.s.doing = describe_doing(msg.content or "", name, args)
                # La capture est enregistrée avec l'action : c'est la matière
                # première d'une fiche CareMemory.
                self.s.log("tool_call", step=step, tool=name, args=args, frame=frame.frame_id)
                await self.broadcast(self.s.status())

                if name == "answer":
                    self.s.finish(args.get("content", ""))
                    await self.broadcast({"type": "answer", "content": args.get("content", "")})
                    return

                if name in ("ask_helper", "ask_senior"):
                    result = await self._escalate(args, to="senior" if name == "ask_senior" else "helper")
                    if result is None:
                        return
                else:
                    result = await self._act(name, args)
                    if result is None:
                        return

                messages.append({"role": "tool", "tool_call_id": call.id, "content": result})

            if self.s.pause_requested:
                self.s.pause_requested = False
                result = await self._escalate(
                    {
                        "question": "Vous avez mis l'assistance en pause. Que faut-il faire ?",
                        "options": ["Continuer", "Indiquez-moi quoi faire"],
                    }
                )
                if result is None:
                    return
                messages.append({"role": "user", "content": f"Consigne du support : {result}"})

            # Free tier : 10 requêtes / minute.
            elapsed = time.time() - started
            if elapsed < MIN_SECONDS_PER_STEP:
                await asyncio.sleep(MIN_SECONDS_PER_STEP - elapsed)

        self.s.log("budget_exhausted")
        self.s.finish("Je n'ai pas réussi à terminer. Je passe la main.")

    # ------------------------------------------------------------------ actions

    async def _act(self, name: str, args: dict) -> str | None:
        """Exécute une action du modèle via le pont. None = la session s'arrête."""
        if name == "wait":
            await asyncio.sleep(2)
            return "attente 2 s"

        if name not in ACTUATING_TOOLS:
            return f"outil inconnu : {name}"

        if self._sensitive_blocked is not None:
            return await self._escalate({})

        try:
            self.s.take_control(Owner.AGENT)
        except Refused as e:
            return str(e)

        self.s.execution_started = True
        result = await self.bridge.execute(name, args)
        self.s.log("action_result", tool=name, result=result)
        if result is None:
            return None
        if isinstance(result, SensitiveBlocked):
            self._sensitive_blocked = result
            self.s.log("sensitive_blocked", tool=name, reason=result.reason)
        return result

    async def _escalate(self, args: dict, to: str = "helper") -> str | None:
        """Suspend l'agent et attend une réponse. None = arrêt ou expiration."""
        question = args.get("question", "")
        options = args.get("options") or []
        if to == "helper" and self._sensitive_blocked is not None:
            question = protected_window_support_text()
            options = []
        fut = self.s.ask_helper(question, options, to=to)
        await self.broadcast(self.s.status())
        await self.broadcast({"type": "question", "question": question, "options": options, "to": to})

        reply = await fut
        if reply is None or not self.s.is_open:
            return None
        if to == "helper":
            self._sensitive_blocked = None
        who = "la personne aidée" if to == "senior" else "du support"
        return f"Réponse de {who} : {reply}" if to == "senior" else f"Réponse du support : {reply}"
