"""Refus du pont et escalade serveur, sans API ni gestes réels."""

import copy
import json
import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ.setdefault("HAI_API_KEY", "stub-key")
from backend import agent, app
from backend.sessions import Frame, Registry, State
from papai_tools import ACTUATING_TOOLS, system_prompt

TEXT = ("Action refusée par PapAI : les réglages sont sensibles. "
        "Ne réessaie pas : appelle ask_helper pour que le proche s'en occupe.")


def response(name, args=None):
    call = SimpleNamespace(id=name, function=SimpleNamespace(name=name, arguments=json.dumps(args or {})))
    return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content="", tool_calls=[call]))])


class ActionsSensibles(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.session = Registry().create("Mes photos")
        self.session.grant_consent()
        self.session.state = State.ACTIVE
        self.session.plan_approved = True
        self.link = app.BridgeLink(SimpleNamespace(send_json=AsyncMock()))
        self.link._request = AsyncMock(return_value={"result": TEXT, "blocked": "sensitive", "refused": False})
        self.link.capture = AsyncMock(return_value=Frame("f", "aW1hZ2U=", 1, 1))
        self.events = []

        async def broadcast(message):
            self.events.append(copy.deepcopy(message))
            if message.get("type") == "question":
                self.assertEqual(self.session.state, State.AWAITING_HELPER)
                self.session.answer_from_helper("Je m'en occupe, vous pouvez continuer.")

        self.runner = agent.AgentRunner(self.session, self.link, broadcast)
        for p in (patch.object(app.S(), "pending_alert", None), patch.object(agent, "MIN_SECONDS_PER_STEP", 0)):
            p.start()
            self.addCleanup(p.stop)

    async def play(self, responses):
        seen = []
        scripted = iter(responses)

        def create(**kwargs):
            seen.append(copy.deepcopy(kwargs["messages"]))
            return next(scripted)

        with patch.object(agent.client.chat.completions, "create", side_effect=create):
            await self.runner.run()
        return seen

    async def test_refus_transmis_a_holo_sans_arret(self):
        seen = await self.play([response("click"), response("ask_helper", {"question": "Pouvez-vous ouvrir le dossier ?"}),
                                response("answer", {"content": "C'est prêt."})])
        self.assertEqual([m["content"] for m in seen[1] if m["role"] == "tool"], [TEXT])
        self.assertEqual(self.link._request.await_count, 1)
        self.assertEqual(self.session.state, State.DONE)
        self.assertFalse(any(e["kind"] == "stop" for e in self.session.journal))
        blocked = [e for e in self.session.journal if e["kind"] == "sensitive_blocked"]
        self.assertEqual(len(blocked), 1)
        self.assertEqual(blocked[0]["reason"], "les réglages sont sensibles")

    async def test_reessai_remplace_par_question_pour_chaque_action(self):
        for name in ACTUATING_TOOLS:
            with self.subTest(name=name):
                await self.runner._act("click", {})
                self.assertTrue(self.session.is_open)
                before = self.link._request.await_count
                result = await self.runner._act(name, {})
                self.assertEqual(self.link._request.await_count, before)
                self.assertTrue(self.session.is_open)
                self.assertIn("Réponse du support", result)
                question = [e for e in self.events if e.get("type") == "question"][-1]
                self.assertEqual(question["to"], "helper")
                self.assertEqual(question["question"],
                                 "PapAI a bloqué une action sensible (les réglages sont sensibles). Pouvez-vous vous en occuper ?")

    async def test_holo_reessaie_dans_la_boucle(self):
        await self.play([response("click"), response("type_text", {"text": "secret"}),
                         response("answer", {"content": "Le proche s'en occupe."})])
        self.assertEqual(self.link._request.await_count, 1)
        self.assertEqual(self.session.state, State.DONE)
        self.assertEqual(len([e for e in self.events if e.get("type") == "question"]), 1)

    async def test_ask_senior_ne_leve_pas_la_protection(self):
        await self.runner._act("click", {})
        await self.runner._escalate({"question": "Quel dossier ?"}, to="senior")
        await self.runner._act("press_key", {})
        self.assertEqual(self.link._request.await_count, 1)
        self.assertEqual([e["to"] for e in self.events if e.get("type") == "question"], ["senior", "helper"])

    async def test_action_autorisee_apres_reponse_du_proche(self):
        await self.runner._act("click", {})
        await self.runner._escalate({"question": "Pouvez-vous vous en occuper ?"})
        self.link._request.return_value = {"result": "fait", "refused": False}
        self.assertEqual(await self.runner._act("click", {}), "fait")
        self.assertEqual(self.link._request.await_count, 2)

    async def test_refused_vrai_garde_priorite_et_arrete(self):
        self.link._request.return_value = {"result": TEXT, "blocked": "sensitive", "refused": True}
        await self.play([response("click")])
        self.assertEqual(self.session.state, State.STOPPED)
        self.assertEqual(self.session.stopped_by, "pont")
        self.assertFalse(any(e["kind"] == "sensitive_blocked" for e in self.session.journal))

    async def test_clic_support_refuse_ne_reprend_pas_holo(self):
        for result in (agent.SensitiveBlocked(TEXT), None, "fait"):
            with self.subTest(result=result):
                session = Registry().create("Mes photos")
                session.grant_consent()
                session.state = State.ACTIVE
                session.plan_approved = True
                session.last_frame = Frame("capture", "aW1hZ2U=", 1, 1)
                reply = session.ask_helper("Pouvez-vous vous en occuper ?")
                ws = SimpleNamespace(send_json=AsyncMock())
                link = SimpleNamespace(execute=AsyncMock(return_value=result))
                with patch.object(app.S(), "bridge", link), patch.object(app, "broadcast_helper", AsyncMock()):
                    await app.handle_helper_msg(session, {"type": "click", "frame_id": "capture", "x": 0.5, "y": 0.5}, ws)
                messages = [call.args[0] for call in ws.send_json.await_args_list]
                if result == "fait":
                    self.assertTrue(reply.done())
                    self.assertEqual(session.state, State.ACTIVE)
                    self.assertTrue(any(m.get("type") == "ack" for m in messages))
                else:
                    self.assertFalse(reply.done())
                    self.assertEqual(session.state, State.AWAITING_HELPER)
                    self.assertTrue(any(m.get("type") == "refused" for m in messages))
                    self.assertFalse(any(m.get("type") == "ack" for m in messages))
                    if isinstance(result, agent.SensitiveBlocked):
                        self.assertIn("Clic non effectué", messages[0]["reason"])
                        self.assertTrue(any(e["kind"] == "sensitive_blocked" for e in session.journal))

    async def test_resultat_vide_erreur_et_refus_incomplet(self):
        self.link._request.return_value = {"result": "", "refused": False}
        self.assertEqual(await self.link.execute("click", {}), "")
        self.link._request.return_value = None
        self.assertIsNone(await self.link.execute("click", {}))
        self.link._request.return_value = {"blocked": "sensitive", "refused": False}
        result = await self.runner._act("click", {})
        self.assertTrue(self.session.is_open)
        self.assertIn("appelle ask_helper", result)
        self.assertIsInstance(result, agent.SensitiveBlocked)

    def test_prompt_mac_et_windows(self):
        for platform in ("macos", "windows"):
            self.assertIn("Action refusée par PapAI", system_prompt(platform))
            self.assertIn("ne réessaie pas, appelle ask_helper", system_prompt(platform))


if __name__ == "__main__":
    unittest.main()
