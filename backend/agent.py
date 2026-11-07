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

import os

# Abaissé pendant les essais : un agent qui tâtonne sur un vrai bureau coûte
# des clics imprévus. 25 en usage normal.
# CAREPILOT_MAX_STEPS : ancien nom, encore lu pour les déploiements existants.
MAX_STEPS = int(os.environ.get("PAPAI_MAX_STEPS") or os.environ.get("CAREPILOT_MAX_STEPS") or "25")

client = make_client()


async def propose_plan(session: Session, bridge, broadcast, note: str = "") -> list[str]:
    """Une capture, un appel à Holo, aucune action : un plan à faire valider."""
    frame = await bridge.capture()
    messages = [
        {"role": "system", "content": PLAN_PROMPT.format(os="Mac" if bridge.os == "macos" else "Windows")},
        {"role": "user", "content": f"Demande de la personne : « {session.task} »"
            + (f"\nPrécision de son proche : {note}" if note else "")},
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
        steps = [str(x).strip() for x in json.loads(m.group(0)).get("steps", []) if str(x).strip()]
    except Exception as e:  # noqa: BLE001 — un plan minimal vaut mieux qu'une session bloquée
        session.log("plan_failed", error=f"{type(e).__name__}: {e}")
        steps = []
    return steps[:5] or [f"Faire : {session.task}"]


class AgentRunner:
    """Pilote une session du premier screenshot jusqu'à `answer` ou l'arrêt."""

    def __init__(self, session: Session, bridge, broadcast, notes: list[str] | None = None) -> None:
        self.s = session
        self.bridge = bridge
        self.broadcast = broadcast  # async (dict) -> None, vers le proche
        self.notes = notes or []

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
            brief += "\n\nPlan validé par le proche, à suivre :\n" + "\n".join(
                f"{i}. {step}" for i, step in enumerate(self.s.plan, 1)
            )
            brief += "\nÀ chaque action, indique dans plan_step le numéro de l'étape du plan que tu exécutes."
        for n in self.notes:
            brief += f"\nPrécision du proche : {n}"
        messages = [
            {"role": "system", "content": system_prompt(self.bridge.os)},
            {"role": "user", "content": brief},
        ]

        for step in range(1, MAX_STEPS + 1):
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
                # La capture est enregistrée avec l'action : c'est la matière
                # première d'une fiche CareMemory.
                self.s.log("tool_call", step=step, tool=name, args=args, frame=frame.frame_id)
                await self.broadcast(self.s.status())

                if name == "answer":
                    self.s.finish(args.get("content", ""))
                    await self.broadcast({"type": "answer", "content": args.get("content", "")})
                    return

                if name == "ask_helper":
                    result = await self._escalate(args)
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
                messages.append({"role": "user", "content": f"Consigne du proche : {result}"})

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

        try:
            self.s.take_control(Owner.AGENT)
        except Refused as e:
            return str(e)

        result = await self.bridge.execute(name, args)
        self.s.log("action_result", tool=name, result=result)
        if result is None:
            return None
        return result

    async def _escalate(self, args: dict) -> str | None:
        """Suspend l'agent et attend le proche. None = arrêt ou expiration."""
        question = args.get("question", "")
        options = args.get("options") or []
        fut = self.s.ask_helper(question, options)
        await self.broadcast(self.s.status())
        await self.broadcast({"type": "question", "question": question, "options": options})

        reply = await fut
        if reply is None or not self.s.is_open:
            return None
        return f"Réponse du proche : {reply}"
