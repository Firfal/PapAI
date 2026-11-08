"""Agent navigateur de H : choix du mode, plan d'abord, contrôle du proche.

Faux Agents API local (tests/faux_agents_api.py), aucune clé ni navigateur.

    .venv-mac/bin/python tests/test_agent_navigateur.py
"""
import asyncio
import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

RACINE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RACINE))
sys.path.insert(0, str(RACINE / "tests"))
os.environ["HAI_API_KEY"] = "stub-key"

from backend import app, web_agent  # noqa: E402
from backend.sessions import Frame, Registry, State  # noqa: E402
from faux_agents_api import FauxAgentsAPI  # noqa: E402
from papai_tools import PLAN_PROMPT, WEB_AGENT_INSTRUCTIONS  # noqa: E402
import test_demandes_suspectes as suspectes  # noqa: E402

NAV = "4f1c2b9a-0d3e-4c1b-9a77-2b6f3e1d5c80"
PLAN = ["Ouvrir le site de Météo-France", "Afficher la météo de Paris"]


async def attendre(cond, delai=6.0):
    fin = asyncio.get_running_loop().time() + delai
    while asyncio.get_running_loop().time() < fin:
        if cond():
            return True
        await asyncio.sleep(0.02)
    return False


class Base(unittest.IsolatedAsyncioTestCase):
    scenario = "simple"

    def setUp(self):
        self.api = FauxAgentsAPI(self.scenario)
        self.addCleanup(self.api.fermer)
        os.environ["HAI_AGENTS_BASE_URL"] = self.api.url
        self.registry = Registry()
        self.bridge_sent = []
        self.web_reply = NAV

        async def envoyer_au_pont(message):
            self.bridge_sent.append(message)
            if message.get("type") == "web_agent_start" and self.web_reply is not None:
                self.link.receive_web_agent(self.web_reply)

        self.link = app.BridgeLink(SimpleNamespace(send_json=AsyncMock(side_effect=envoyer_au_pont)))
        self.link.capture = AsyncMock(return_value=None)
        self.link.execute = AsyncMock()
        self.link.os = "macos"
        self.link.web_agent_available = True
        self.envoyes = []

        async def diffuser(msg, to_bridge=True):
            self.envoyes.append(msg)

        for p in (patch.object(app, "registry", self.registry), patch.object(app, "bridge", self.link),
                  patch.object(app, "pending_alert", None), patch.object(app, "broadcast_helper", diffuser),
                  patch.object(web_agent, "PAUSE_POLL_S", 0.05),
                  patch.object(app, "WEB_AGENT_START_TIMEOUT_S", 0.05)):
            p.start()
            self.addCleanup(p.stop)

    def session(self, task="Ouvre le site de la météo de Paris"):
        s = self.registry.create(task)
        s.grant_consent()
        return s

    def plan(self, where):
        async def proposer(session, bridge, broadcast, note=""):
            session.where = where
            return list(PLAN)
        return patch.object(app, "propose_plan", side_effect=proposer)

    async def lancer(self, s, where="web", sans_gardien=True):
        ctx = [self.plan(where)]
        if sans_gardien:
            ctx.append(patch.object(app, "check_request", AsyncMock(return_value=False)))
        for c in ctx:
            c.start()
            self.addCleanup(c.stop)
        task = asyncio.create_task(app.run_session(s, self.link))
        self.addCleanup(task.cancel)
        self.assertTrue(await attendre(lambda: s.state == State.AWAITING_APPROVAL or not s.is_open))
        return task

    def h(self):
        return next(iter(self.api.sessions.values()), None)


class ChoixDuMode(Base):
    def test_prompt_et_consignes(self):
        self.assertIn('"where"', PLAN_PROMPT)
        self.assertIn("Ne saisis jamais de mot de passe, de code reçu par SMS, de numéro de carte ni d'IBAN.",
                      WEB_AGENT_INSTRUCTIONS)
        self.assertEqual(os.environ.get("HAI_AUTO_BRIDGE"), "0")

    async def test_session_web_ne_demarre_pas_de_pont_local(self):
        from hai_agents_local.manager import BridgeManager

        demarrages = []
        original_spec = web_agent.agent_spec

        def spec_sans_session(session_id):
            spec = original_spec(session_id)
            spec["environments"][0].pop("session_id")
            return spec

        def demarrer(_manager, bridge):
            demarrages.append(bridge)
            return False

        with patch.dict(os.environ, {"HAI_AUTO_BRIDGE": "1"}), \
             patch.object(BridgeManager, "_ensure_one", demarrer), \
             patch.object(web_agent, "agent_spec", side_effect=spec_sans_session):
            s = self.session()
            await self.lancer(s)
            s.decide_plan("approve", "")
            self.assertTrue(await attendre(lambda: not s.is_open))
        self.assertEqual(demarrages, [])

    def test_identifiant_annonce_valide(self):
        self.assertEqual(web_agent.valid_browser_session({"session_id": NAV}), NAV)
        for mauvais in (None, "", "a b", "x" * 80, NAV + "\n", "not-a-uuid",
                        {"session_id": "../etc"}, 42, {"autre": NAV}):
            self.assertIsNone(web_agent.valid_browser_session(mauvais), mauvais)

    async def mode(self, where, annonce):
        self.web_reply = annonce
        s = self.session()
        with patch.object(app, "AgentRunner") as bureau, patch.object(app, "WebAgentRunner") as web:
            bureau.return_value.run = AsyncMock()
            web.return_value.run = AsyncMock()
            await self.lancer(s, where)
            self.assertEqual(s.status()["where"], where)
            s.decide_plan("approve", "")
            self.assertTrue(await attendre(lambda: bureau.called or web.called))
        return s, bureau, web

    async def test_web_si_propose_et_annonce(self):
        s, bureau, web = await self.mode("web", NAV)
        self.assertIn({"type": "web_agent_start"}, self.bridge_sent)
        web.assert_called_once()
        self.assertEqual(web.call_args.args[1], NAV)
        bureau.assert_not_called()
        self.assertEqual(s.where, "web")

    async def test_bureau_si_pas_de_navigateur(self):
        s, bureau, web = await self.mode("web", None)
        self.assertTrue(any(e["kind"] == "web_agent_timeout" for e in s.journal))
        bureau.assert_called_once()
        web.assert_not_called()
        self.assertEqual(s.where, "desktop")
        start = next(i for i, m in enumerate(self.bridge_sent) if m["type"] == "web_agent_start")
        stop = next(i for i, m in enumerate(self.bridge_sent) if m["type"] == "web_agent_stop")
        self.assertLess(start, stop)
        await app.handle_web_agent_change(self.link, NAV)
        self.assertIsNone(self.link.web_agent)
        self.assertIsNone(s.status()["stopped_by"])
        web.assert_not_called()

    async def test_arret_pendant_attente_envoie_web_agent_stop(self):
        self.web_reply = None
        s = self.session()
        with patch.object(app, "AgentRunner") as bureau, patch.object(app, "WebAgentRunner") as web:
            task = await self.lancer(s, "web")
            s.decide_plan("approve", "")
            self.assertTrue(await attendre(
                lambda: any(m["type"] == "web_agent_start" for m in self.bridge_sent)
            ))
            s.stop(by="senior")
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task
        self.assertIn({"type": "web_agent_stop"}, self.bridge_sent)
        self.assertIsNone(self.link._web_agent_waiter)
        bureau.assert_not_called()
        web.assert_not_called()

    async def test_bureau_si_hello_sans_capacite_navigateur(self):
        self.link.web_agent_available = False
        s, bureau, web = await self.mode("web", NAV)
        bureau.assert_called_once()
        web.assert_not_called()
        self.assertFalse(any(m["type"] == "web_agent_start" for m in self.bridge_sent))
        self.assertEqual(s.where, "desktop")

    async def test_bureau_si_tache_hors_navigateur(self):
        s, bureau, web = await self.mode("desktop", NAV)
        bureau.assert_called_once()
        self.assertIs(bureau.call_args.args[1], self.link)
        web.assert_not_called()
        self.assertEqual(self.api.sessions, {})

    async def test_where_du_plan_lu_par_propose_plan(self):
        from backend import agent
        s = self.session()
        for brut, attendu in (('{"steps":["Ouvrir"],"where":"web"}', "web"),
                              ('{"steps":["Ouvrir"]}', "desktop"),
                              ('{"steps":["Ouvrir"],"where":"lune"}', "desktop")):
            rep = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=brut))], usage=None)
            with patch.object(agent, "client") as c:
                c.chat.completions.create.return_value = rep
                await agent.propose_plan(s, self.link, AsyncMock())
            self.assertEqual(s.where, attendu, brut)


class PlanDabord(Base):
    async def test_rien_avant_validation_puis_session_h(self):
        s = self.session()
        await self.lancer(s)
        await asyncio.sleep(0.3)
        self.assertEqual(self.api.sessions, {})
        self.assertFalse(s.execution_started)
        self.link.execute.assert_not_called()
        s.decide_plan("approve", "")
        self.assertTrue(await attendre(lambda: s.state == State.DONE))
        corps = self.h().corps
        self.assertEqual(corps["agent"]["environments"],
                         [{"id": "papai-chrome", "kind": "web", "host": "user_device", "session_id": NAV}])
        self.assertEqual(corps["agent"]["instructions"], WEB_AGENT_INSTRUCTIONS)
        self.assertIn("ask_helper", [t["name"] for t in corps["agent"]["tools"]])
        for morceau in (s.task, *PLAN, WEB_AGENT_INSTRUCTIONS):
            self.assertIn(morceau, corps["messages"])
        self.assertTrue(s.execution_started)
        self.link.execute.assert_not_called()
        doing = [m.get("doing") for m in self.envoyes if m.get("type") == "status"]
        self.assertIn("Holo ouvre meteofrance.com", doing)
        self.assertIn("Holo clique sur Paris", doing)
        self.assertTrue(any(m.get("type") == "frame" for m in self.envoyes))
        self.assertIn(2, [m.get("plan_step") for m in self.envoyes if m.get("type") == "status"])
        self.assertIn({"type": "answer", "content": "La météo de Paris est affichée à l'écran."}, self.envoyes)

    async def test_refus_du_plan(self):
        s = self.session()
        await self.lancer(s)
        s.decide_plan("refuse", "")
        self.assertTrue(await attendre(lambda: not s.is_open))
        await asyncio.sleep(0.2)
        self.assertEqual(s.status()["stopped_by"], "proche")
        self.assertEqual(self.api.sessions, {})

    async def test_gardien_avant_tout(self):
        s = self.session(suspectes.SUSPECTES[0])
        with patch.object(app, "propose_plan", AsyncMock()) as plan:
            await app.run_session(s, self.link)
        plan.assert_not_called()
        self.assertEqual(s.status()["stopped_by"], "gardien")
        self.assertEqual(self.api.sessions, {})


class FramesWeb(Base):
    scenario = "wait_frame"

    async def test_refresh_avant_premiere_image_h_ne_renvoie_pas_le_plan(self):
        s = self.session()
        s.set_frame(Frame(frame_id="plan", png_b64="plan-frame", width=1, height=1))
        await self.lancer(s)
        s.decide_plan("approve", "")
        self.assertTrue(await attendre(lambda: self.h() is not None))
        self.assertIsNone(s.last_frame)

        ws = SimpleNamespace(send_json=AsyncMock())
        await app.handle_helper_refresh(s, ws)
        ws.send_json.assert_not_awaited()

        self.h().frame_gate.set()
        self.assertTrue(await attendre(lambda: s.last_frame is not None))


class CreationAnnulee(Base):
    async def test_annulation_pendant_creation_annule_la_session_h(self):
        self.api.start_delay = 0.25
        s = self.session()
        task = await self.lancer(s)
        s.decide_plan("approve", "")
        self.assertTrue(await asyncio.to_thread(self.api.creation_started.wait, 2))

        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertTrue(await attendre(lambda: self.api.a_appele("DELETE", "/h1")))
        self.assertEqual(self.api.sessions["h1"].status, "interrupted")

    async def test_annulations_repetees_pendant_creation_n_annulent_qu_une_fois(self):
        self.api.start_delay = 0.4
        s = self.session()
        task = await self.lancer(s)
        s.decide_plan("approve", "")
        self.assertTrue(await asyncio.to_thread(self.api.creation_started.wait, 2))

        task.cancel()
        await asyncio.sleep(0.03)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertTrue(await attendre(lambda: self.api.a_appele("DELETE", "/h1")))
        await asyncio.sleep(0.05)
        self.assertEqual(self.api.sessions["h1"].status, "interrupted")
        self.assertEqual(
            sum(m == "DELETE" and p.endswith("/h1") for m, p in self.api.appels),
            1,
        )


class QuestionAuProche(Base):
    scenario = "question"

    async def test_ask_helper_aller_retour(self):
        s = self.session()
        await self.lancer(s)
        s.decide_plan("approve", "")
        self.assertTrue(await attendre(lambda: s.state == State.AWAITING_HELPER))
        self.assertEqual(s.question["question"], "Faut-il accepter les cookies ?")
        self.assertEqual(self.h().tool_results, [])
        s.answer_from_helper("Oui, accepte")
        self.assertTrue(await attendre(lambda: s.state == State.DONE))
        res = self.h().tool_results[0]
        self.assertEqual(res["kind"], "tool_result")
        self.assertEqual(res["tool_req"]["id"], "q1")
        self.assertEqual(res["result"], "Réponse du support : Oui, accepte")

    async def test_pas_de_prise_en_main_du_bureau(self):
        s = self.session()
        await self.lancer(s)
        s.decide_plan("approve", "")
        self.assertTrue(await attendre(lambda: s.state == State.AWAITING_HELPER))
        ws = SimpleNamespace(send_json=AsyncMock())
        with patch.object(app, "bridge", self.link):
            with self.assertRaises(app.Refused):
                await app.handle_helper_click(s, {"frame_id": "x", "x": 0.5, "y": 0.5}, ws)
            await app.handle_helper_refresh(s, ws)
        self.link.execute.assert_not_called()
        self.link.capture.assert_not_called()
        s.answer_from_helper("Oui")

    async def test_arret_pendant_la_question(self):
        s = self.session()
        await self.lancer(s)
        s.decide_plan("approve", "")
        self.assertTrue(await attendre(lambda: s.state == State.AWAITING_HELPER))
        s.stop(by="senior")
        self.assertTrue(await attendre(lambda: self.api.a_appele("DELETE", "/sessions/h1")))


class PauseEtArret(Base):
    scenario = "long"

    async def demarrer(self):
        s = self.session()
        task = await self.lancer(s)
        s.decide_plan("approve", "")
        self.assertTrue(await attendre(lambda: self.h() is not None and len(self.h().events) > 3))
        return s, task

    async def test_pause_puis_reprise(self):
        s, _ = await self.demarrer()
        s.paused = True
        self.assertTrue(await attendre(lambda: self.h().status == "paused"))
        n = len(self.h().events)
        await asyncio.sleep(0.4)
        self.assertEqual(len(self.h().events), n)
        s.paused = False
        self.assertTrue(await attendre(lambda: self.h().status == "running"))
        self.assertTrue(await attendre(lambda: len(self.h().events) > n))

    async def test_pause_du_proche_question_puis_continuer(self):
        s, _ = await self.demarrer()
        s.pause_requested = True
        self.assertTrue(await attendre(lambda: self.h().status == "paused" and s.state == State.AWAITING_HELPER))
        s.answer_from_helper("Continuer")
        self.assertTrue(await attendre(lambda: self.h().status == "running"))

    async def test_pause_du_proche_avec_consigne(self):
        s, _ = await self.demarrer()
        s.pause_requested = True
        self.assertTrue(await attendre(lambda: s.state == State.AWAITING_HELPER))
        s.answer_from_helper("Ferme la fenêtre de publicité")
        self.assertTrue(await attendre(lambda: self.h().messages))
        self.assertIn("Ferme la fenêtre de publicité", str(self.h().messages[0]))

    async def test_arreter_annule_la_session_h(self):
        s, task = await self.demarrer()
        # Comme le message `stop` du pont : la session est arrêtée, la tâche annulée.
        s.stop(by="senior")
        task.cancel()
        self.assertTrue(await attendre(lambda: self.h().status == "interrupted"))
        self.assertTrue(self.api.a_appele("DELETE", "/sessions/h1"))
        self.assertEqual(s.status()["stopped_by"], "senior")

    async def test_navigateur_perdu_arrete_et_annule_h(self):
        s, task = await self.demarrer()
        with patch.object(app, "agent_task", task):
            await app.handle_web_agent_change(self.link, None)
        self.assertEqual(s.status()["stopped_by"], "navigateur")
        self.assertTrue(await attendre(lambda: self.api.a_appele("DELETE", "/sessions/h1")))
        self.assertTrue(any(
            m.get("type") == "status" and m.get("doing") ==
            "Le navigateur PapAI s'est fermé : l'aide est arrêtée."
            for m in self.envoyes
        ))

    async def test_alerte_du_gardien_annule(self):
        s, _ = await self.demarrer()
        s.stop(by="gardien")
        self.assertTrue(await attendre(lambda: self.h().status == "interrupted"))

    async def test_pont_deconnecte_annule(self):
        s, _ = await self.demarrer()
        await app._stop_open_sessions("pont déconnecté")
        self.assertTrue(await attendre(lambda: self.h().status == "interrupted"))


class MessagesDuPont(unittest.IsolatedAsyncioTestCase):
    async def test_hello_puis_web_agent(self):
        from fastapi import WebSocketDisconnect
        msgs = [{"type": "hello", "os": "macos", "web_agent": {"session_id": NAV}},
                {"type": "web_agent", "session_id": None},
                {"type": "web_agent", "session_id": "pas valide !"}]
        vus = []

        async def recevoir():
            if app.bridge is not None and vus is not None and len(vus) < 4:
                vus.append((app.bridge.web_agent, app.bridge.web_agent_available))
            if msgs:
                return msgs.pop(0)
            raise WebSocketDisconnect()

        ws = SimpleNamespace(accept=AsyncMock(), send_json=AsyncMock(), close=AsyncMock(), receive_json=recevoir)
        with patch.object(app, "bridge", None), patch.object(app, "registry", Registry()), \
                patch.object(app, "broadcast_helper", AsyncMock()), patch.object(app, "family") as fam:
            fam.set_senior.return_value = False
            fam.restore.return_value = False
            await app._ws_bridge(ws)
        self.assertEqual(vus, [(None, False)] * 4)


if __name__ == "__main__":
    unittest.main(verbosity=1)
