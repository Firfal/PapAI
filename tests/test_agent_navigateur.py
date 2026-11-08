"""Agent navigateur de H : choix du mode, plan d'abord, contrôle du proche.

Faux Agents API local (tests/faux_agents_api.py), aucune clé ni navigateur.

    .venv-mac/bin/python tests/test_agent_navigateur.py
"""
import asyncio
from urllib.parse import urlsplit
import json
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

from backend import agent, app, web_agent  # noqa: E402
from backend.sessions import Frame, Registry, State  # noqa: E402
from faux_agents_api import FauxAgentsAPI  # noqa: E402
from papai_tools import PLAN_PROMPT, TOOLS, WEB_AGENT_INSTRUCTIONS  # noqa: E402
import test_demandes_suspectes as suspectes  # noqa: E402

NAV = "4f1c2b9a-0d3e-4c1b-9a77-2b6f3e1d5c80"
PLAN = ["Ouvrir le site de Météo-France", "Afficher la météo de Paris"]


def reponse_outil(name, args, call_id):
    call = SimpleNamespace(
        id=call_id,
        function=SimpleNamespace(name=name, arguments=json.dumps(args, ensure_ascii=False)),
    )
    message = SimpleNamespace(content="", tool_calls=[call])
    return SimpleNamespace(choices=[SimpleNamespace(message=message)], usage=None)


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

        for p in (patch.object(app.S(), "registry", self.registry), patch.object(app.S(), "bridge", self.link),
                  patch.object(app.S(), "pending_alert", None), patch.object(app, "broadcast_helper", diffuser),
                  patch.object(web_agent, "PAUSE_POLL_S", 0.05),
                  patch.object(app, "WEB_AGENT_START_TIMEOUT_S", 0.05)):
            p.start()
            self.addCleanup(p.stop)

    def session(self, task="Ouvre le site de la météo de Paris"):
        s = self.registry.create(task)
        s.grant_consent()
        return s

    def plan(self, where, sites=None):
        async def proposer(session, bridge, broadcast, note=""):
            session.plan_mode = where
            session.plan_sites = list(sites or ["meteofrance.com"]) if where == "mixed" else []
            session.web_steps = [2] if where == "mixed" else []
            session.where = "web" if where == "web" else "desktop"
            steps = list(PLAN)
            if where == "mixed":
                steps[1] = f"Dans Chrome PapAI ({', '.join(session.plan_sites)}) : {steps[1]}"
            return steps
        return patch.object(app, "propose_plan", side_effect=proposer)

    async def lancer(self, s, where="web", sans_gardien=True, sites=None):
        ctx = [self.plan(where, sites)]
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
        return next(reversed(self.api.sessions.values()), None)


class ChoixDuMode(Base):
    def test_prompt_et_consignes(self):
        self.assertIn('"where"', PLAN_PROMPT)
        self.assertIn('"web_steps"', PLAN_PROMPT)
        self.assertIn('"sites"', PLAN_PROMPT)
        prompt = PLAN_PROMPT.format(os="Mac")
        self.assertIn('"where": "mixed"', prompt)
        self.assertIn('"web_steps": [2]', prompt)
        self.assertIn('"sites": ["ameli.fr"]', prompt)
        self.assertIn("Ne saisis jamais de mot de passe, de code reçu par SMS, de numéro de carte ni d'IBAN.",
                      WEB_AGENT_INSTRUCTIONS)
        self.assertEqual(os.environ.get("HAI_AUTO_BRIDGE"), "0")

    async def test_plan_mixte_valide_sites_et_prefixe_les_etapes_web(self):
        s = self.session()
        contenu = json.dumps({
            "steps": ["Ouvrir le dossier", "Consulter le site"],
            "where": "mixed",
            "web_steps": [2, 0, 3, True, "1"],
            "sites": ["ameli.fr"],
        })
        resultat = SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=contenu))], usage=None
        )

        with patch.object(agent, "client") as client:
            client.chat.completions.create.return_value = resultat
            steps = await agent.propose_plan(s, self.link, AsyncMock())

        self.assertEqual(s.plan_mode, "mixed")
        self.assertEqual(s.plan_sites, ["ameli.fr"])
        self.assertEqual(s.web_steps, [2])
        self.assertEqual(s.where, "desktop")
        self.assertEqual(steps, [
            "Ouvrir le dossier", "Dans Chrome PapAI (ameli.fr) : Consulter le site"
        ])
        self.assertEqual(s.status()["where"], "desktop")

    async def test_plan_mixte_sans_domaine_valide_redevient_bureau(self):
        s = self.session()
        contenu = json.dumps({
            "steps": ["Ouvrir le dossier", "Consulter le site"],
            "where": "mixed",
            "web_steps": [2],
            "sites": ["https://ameli.fr", "AMELI.fr", "ameli.fr/compte"],
        })
        resultat = SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=contenu))], usage=None
        )

        with patch.object(agent, "client") as client:
            client.chat.completions.create.return_value = resultat
            steps = await agent.propose_plan(s, self.link, AsyncMock())

        self.assertEqual(s.plan_mode, "desktop")
        self.assertEqual(s.plan_sites, [])
        self.assertEqual(s.web_steps, [])
        self.assertEqual(s.where, "desktop")
        self.assertEqual(steps, ["Ouvrir le dossier", "Consulter le site"])

    async def test_plan_mixte_sans_etape_web_valide_redevient_bureau(self):
        s = self.session()
        contenu = json.dumps({
            "steps": ["Ouvrir le dossier", "Consulter le site"],
            "where": "mixed",
            "web_steps": [0, 3],
            "sites": ["ameli.fr"],
        })
        resultat = SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=contenu))], usage=None
        )

        with patch.object(agent, "client") as client:
            client.chat.completions.create.return_value = resultat
            steps = await agent.propose_plan(s, self.link, AsyncMock())

        self.assertEqual(s.plan_mode, "desktop")
        self.assertEqual(s.plan_sites, [])
        self.assertEqual(s.web_steps, [])
        self.assertEqual(steps, ["Ouvrir le dossier", "Consulter le site"])

    async def test_plan_mixte_avec_plus_de_trois_sites_redevient_bureau(self):
        s = self.session()
        contenu = json.dumps({
            "steps": ["Ouvrir le dossier", "Consulter le site"],
            "where": "mixed",
            "web_steps": [2],
            "sites": ["ameli.fr", "caf.fr", "service-public.fr", "impots.gouv.fr"],
        })
        resultat = SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=contenu))], usage=None
        )

        with patch.object(agent, "client") as client:
            client.chat.completions.create.return_value = resultat
            steps = await agent.propose_plan(s, self.link, AsyncMock())

        self.assertEqual(s.plan_mode, "desktop")
        self.assertEqual(s.plan_sites, [])
        self.assertEqual(s.web_steps, [])
        self.assertEqual(steps, ["Ouvrir le dossier", "Consulter le site"])

    def test_brief_sous_tache_web_ne_demande_que_l_objectif_et_les_sites_valides(self):
        s = self.session("Faire une démarche depuis le bureau")
        s.plan = ["Ouvrir les réglages", "Dans Chrome PapAI (ameli.fr) : consulter l'attestation"]
        s.plan_sites = ["ameli.fr"]

        contenu = web_agent.brief(
            s, ["Précision du support"], goal="Consulter l'attestation", url="https://ameli.fr"
        )

        self.assertTrue(contenu.startswith("Priorité : exécute uniquement l'objectif de cette sous-tâche web"))
        self.assertIn(
            "Contexte : plan validé de toute l'aide. Un autre agent fait les étapes sur le bureau. "
            "Fais uniquement l'objectif ci-dessus, puis rends un résumé.",
            contenu,
        )
        self.assertIn("Sites validés par le support : ameli.fr. Reste sur ces domaines ou leurs sous-domaines.",
                      contenu)
        self.assertIn("La consigne « Étape N » ne s'applique qu'aux étapes de cet objectif web.", contenu)
        self.assertIn("Plan validé par le support, pour contexte uniquement :", contenu)
        self.assertIn(WEB_AGENT_INSTRUCTIONS, contenu)

    def test_brief_web_complet_est_inchange(self):
        s = self.session("Consulter la météo")
        s.plan = list(PLAN)

        attendu = (
            "Demande de la personne : « Consulter la météo »\n\n"
            "Plan validé par le support, à suivre :\n"
            "Étape 1. Ouvrir le site de Météo-France\n"
            "Étape 2. Afficher la météo de Paris\n"
            "Avant chaque action, écris « Étape N » pour l'étape du plan en cours.\n\n"
            f"{WEB_AGENT_INSTRUCTIONS}"
        )
        self.assertEqual(web_agent.brief(s), attendu)

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
        self.assertIn({"type": "web_agent_start", "sites": [], "hosts": []}, self.bridge_sent)
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
        with patch.object(app.S(), "bridge", self.link):
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
        with patch.object(app.S(), "agent_task", task):
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
            if app.S().bridge is not None and vus is not None and len(vus) < 4:
                vus.append((app.S().bridge.web_agent, app.S().bridge.web_agent_available))
            if msgs:
                return msgs.pop(0)
            raise WebSocketDisconnect()

        ws = SimpleNamespace(accept=AsyncMock(), send_json=AsyncMock(), close=AsyncMock(), receive_json=recevoir)
        with patch.object(app.S(), "bridge", None), patch.object(app.S(), "registry", Registry()), \
                patch.object(app, "broadcast_helper", AsyncMock()), patch.object(app.S(), "family") as fam:
            fam.set_senior.return_value = False
            fam.restore.return_value = False
            await app._ws_bridge(ws)
        self.assertEqual(vus, [(None, False)] * 4)


class BasculeDepuisLeBureau(Base):
    def frame(self):
        self.link.capture.return_value = Frame("desktop", "desktop-frame", 1, 1)

    def test_journal_masque_les_mots_de_passe_et_les_codes(self):
        texte = "mdp Soleil2024. pass Azerty!. PIN 4821. cryptogramme 123."
        journal = app._safe_handoff_log_text(texte)

        for secret in ("Soleil2024", "Azerty", "4821", "123"):
            self.assertNotIn(secret, journal)
        self.assertEqual(journal.count("[donnée sensible masquée]"), 4)

    async def executer_bascule(self, sites, url=None):
        self.api.navigation_url = url or f"https://{sites[0]}"
        self.frame()
        s = self.session()
        task = await self.lancer(s, "mixed", sites=sites)
        s.decide_plan("approve", "")
        args = {"goal": "Consulter les informations demandées", "plan_step": 2}
        if url is not None:
            args["url"] = url
        appels = []
        responses = [
            reponse_outil("open_browser", args, "browser"),
            reponse_outil("answer", {"content": "Terminé."}, "answer"),
        ]

        def creer(**kwargs):
            appels.append(kwargs)
            return responses.pop(0)

        with patch.object(agent, "client") as client, patch.object(agent, "MIN_SECONDS_PER_STEP", 0):
            client.chat.completions.create.side_effect = creer
            await asyncio.wait_for(task, 8)
        return s, appels

    async def test_alerte_web_apres_action_bureau_ne_pretend_pas_que_rien_na_ete_execute(self):
        from backend.agent import AgentRunner

        s = self.session()
        s.state = State.ACTIVE
        s.plan_approved = True
        s.plan_sites = ["example.com"]
        self.link.execute.return_value = "Action exécutée"
        runner = AgentRunner(s, self.link, AsyncMock())
        await runner._act("click", {"element": "un bouton", "x": 100, "y": 100})
        self.assertTrue(s.execution_started)

        result = await app.browser_handoff(
            s, self.link, [], "virer 5000 € à mon petit-fils qui a perdu son téléphone", None
        )

        self.assertIsNone(result)
        alerts = [
            m for m in [*self.bridge_sent, *self.envoyes]
            if m.get("type") == "alert"
        ]
        self.assertTrue(alerts)
        self.assertTrue(any(m.get("source") == "browser" for m in alerts))
        self.assertFalse(any("Rien n'a été exécuté" in m.get("detail", "") for m in alerts))
        self.assertTrue(any("L'assistance est arrêtée." in m.get("detail", "") for m in alerts))
        self.assertFalse(any(m.get("type") == "web_agent_start" for m in self.bridge_sent))

    async def test_open_browser_absent_si_navigateur_indisponible(self):
        self.link.web_agent_available = False
        self.frame()
        s = self.session()
        task = await self.lancer(s, "mixed")
        s.decide_plan("approve", "")
        appels = []

        def creer(**kwargs):
            appels.append(kwargs)
            return reponse_outil("answer", {"content": "Terminé."}, "answer")

        with patch.object(agent, "client") as client, patch.object(agent, "MIN_SECONDS_PER_STEP", 0):
            client.chat.completions.create.side_effect = creer
            await asyncio.wait_for(task, 5)

        outils = appels[0]["tools"]
        self.assertNotIn("open_browser", [t["function"]["name"] for t in outils])
        self.assertEqual(outils, TOOLS)
        self.assertNotIn("appelle open_browser", appels[0]["messages"][0]["content"])
        runner = agent.AgentRunner(s, self.link, AsyncMock())
        self.assertEqual(await runner._open_browser({"goal": "Consulter Météo-France"}), "outil indisponible")

    async def test_open_browser_absent_pour_un_plan_bureau_meme_avec_navigateur(self):
        self.frame()
        s = self.session()
        task = await self.lancer(s, "desktop")
        s.decide_plan("approve", "")
        appels = []

        def creer(**kwargs):
            appels.append(kwargs)
            return reponse_outil("answer", {"content": "Terminé."}, "answer")

        with patch.object(agent, "client") as client, patch.object(agent, "MIN_SECONDS_PER_STEP", 0):
            client.chat.completions.create.side_effect = creer
            await asyncio.wait_for(task, 5)

        self.assertTrue(self.link.web_agent_available)
        self.assertEqual(appels[0]["tools"], TOOLS)
        self.assertNotIn("open_browser", appels[0]["messages"][0]["content"])
        self.assertFalse(any(m.get("type") == "web_agent_start" for m in self.bridge_sent))

    async def test_sous_domaine_du_plan_est_accepte(self):
        s, appels = await self.executer_bascule(["ameli.fr"], "https://www.ameli.fr/compte")

        self.assertEqual(s.state, State.DONE)
        self.assertIn({"type": "web_agent_start", "sites": ["ameli.fr"], "hosts": []}, self.bridge_sent)
        self.assertIn("https://www.ameli.fr/compte", self.api.sessions["h1"].corps["messages"])
        self.assertIn("Reste sur ces domaines ou leurs sous-domaines.", self.api.sessions["h1"].corps["messages"])
        self.assertIn("open_browser", [t["function"]["name"] for t in appels[0]["tools"]])

    async def test_sans_url_demarre_sur_le_premier_site_du_plan(self):
        _, _ = await self.executer_bascule(["ameli.fr", "service-public.fr"])

        self.assertIn("URL HTTPS de départ : https://ameli.fr", self.api.sessions["h1"].corps["messages"])

    async def test_url_hors_du_plan_est_refusee_sans_chrome(self):
        _, appels = await self.executer_bascule(["ameli.fr"], "https://example.com/payer")

        self.assertFalse(any(m.get("type") == "web_agent_start" for m in self.bridge_sent))
        self.assertEqual(self.api.sessions, {})
        resultats = [m["content"] for m in appels[1]["messages"] if m.get("role") == "tool"]
        self.assertTrue(any(
            "Ce site n'était pas dans le plan validé par le support." in r for r in resultats
        ))

    async def test_domaine_qui_contient_le_site_sans_point_est_refuse(self):
        _, appels = await self.executer_bascule(["ameli.fr"], "https://evilameli.fr/")

        self.assertFalse(any(m.get("type") == "web_agent_start" for m in self.bridge_sent))
        self.assertEqual(self.api.sessions, {})
        resultats = [m["content"] for m in appels[1]["messages"] if m.get("role") == "tool"]
        self.assertTrue(any("Ce site n'était pas dans le plan validé" in r for r in resultats))

    async def test_faux_site_edf_hors_plan_est_refuse(self):
        _, appels = await self.executer_bascule(
            ["edf.fr"], "https://edf-regularisation-facture.com/payer"
        )

        self.assertFalse(any(m.get("type") == "web_agent_start" for m in self.bridge_sent))
        self.assertEqual(self.api.sessions, {})
        resultats = [m["content"] for m in appels[1]["messages"] if m.get("role") == "tool"]
        self.assertTrue(any("Ce site n'était pas dans le plan validé" in r for r in resultats))

    async def test_site_du_plan_signale_par_le_gardien_bloque_avant_validation(self):
        self.frame()
        s = self.session()
        alerte = app.guard.Alerte("danger", "Site à vérifier", "Domaine risqué", "domaine", False)

        with patch.object(app.guard, "evaluer", return_value=alerte) as evaluer:
            task = await self.lancer(s, "mixed", sites=["ameli.fr"])
            await asyncio.wait_for(task, 5)

        evaluer.assert_any_call([], "", url="https://ameli.fr")
        self.assertEqual(s.stopped_by, "gardien")
        self.assertFalse(any(m.get("type") == "web_agent_start" for m in self.bridge_sent))

    async def test_url_web_signalee_par_le_gardien_bloquee_avant_chrome(self):
        self.frame()
        s = self.session()
        url = "https://www.edf.fr/facture"
        alerte = app.guard.Alerte("danger", "Site à vérifier", "Domaine risqué", "domaine", False)

        def evaluer(processus, fenetre="", url=""):
            return alerte if url == "https://www.edf.fr/facture" else None

        with patch.object(app.guard, "evaluer", side_effect=evaluer) as evaluer_mock:
            task = await self.lancer(s, "mixed", sites=["edf.fr"])
            s.decide_plan("approve", "")
            appels = []
            responses = [
                reponse_outil("open_browser", {
                    "goal": "Consulter la facture EDF",
                    "url": url,
                    "plan_step": 2,
                }, "browser"),
            ]

            def creer(**kwargs):
                appels.append(kwargs)
                return responses.pop(0)

            with patch.object(agent, "client") as client, patch.object(agent, "MIN_SECONDS_PER_STEP", 0):
                client.chat.completions.create.side_effect = creer
                await asyncio.wait_for(task, 5)

        evaluer_mock.assert_any_call([], "", url=url)
        self.assertEqual(s.stopped_by, "gardien")
        self.assertFalse(any(m.get("type") == "web_agent_start" for m in self.bridge_sent))
        self.assertEqual(self.api.sessions, {})
        self.assertEqual(len(appels), 1)

    async def test_sites_du_plan_sont_inclus_dans_le_texte_gardien(self):
        self.frame()
        s = self.session()
        check = AsyncMock(return_value=False)
        plan_patch = self.plan("mixed", ["ameli.fr"])
        plan_patch.start()
        self.addCleanup(plan_patch.stop)
        with patch.object(app, "check_request", check):
            task = asyncio.create_task(app.run_session(s, self.link))
            self.addCleanup(task.cancel)
            self.assertTrue(await attendre(lambda: s.state == State.AWAITING_APPROVAL))
            s.decide_plan("refuse", "")
            await asyncio.wait_for(task, 5)

        plan_call = next(call for call in check.await_args_list if call.args[2] == "plan")
        self.assertIn("https://ameli.fr", plan_call.args[1])

    async def test_sous_tache_web_revient_au_bureau_avec_son_resume(self):
        self.frame()
        s = self.session("Aide-moi à me renseigner sur la météo locale")
        task = await self.lancer(s, "mixed")
        self.assertEqual(s.status()["where"], "desktop")
        self.assertIn("Dans Chrome PapAI (meteofrance.com) :", s.status()["plan"][1])
        s.decide_plan("approve", "")
        responses = [
            reponse_outil("open_browser", {
                "goal": "Consulter la météo de Paris sur Météo-France",
                "url": "https://meteofrance.com/paris",
                "plan_step": 2,
            }, "browser"),
            reponse_outil("answer", {"content": "La météo est affichée."}, "answer"),
        ]
        appels = []

        def creer(**kwargs):
            appels.append(kwargs)
            return responses.pop(0)

        with patch.object(agent, "client") as client, patch.object(agent, "MIN_SECONDS_PER_STEP", 0):
            client.chat.completions.create.side_effect = creer
            await asyncio.wait_for(task, 8)

        self.assertEqual(s.state, State.DONE)
        self.assertEqual(s.where, "desktop")
        self.assertIn("Dans Chrome PapAI (meteofrance.com) :", s.status()["plan"][1])
        self.assertIn("open_browser", [t["function"]["name"] for t in appels[0]["tools"]])
        self.assertIn("appelle open_browser", appels[0]["messages"][0]["content"])
        self.assertEqual(self.api.sessions["h1"].status, "completed")
        contexte_web = self.api.sessions["h1"].corps["messages"]
        self.assertIn("Consulter la météo de Paris", contexte_web)
        self.assertIn(PLAN[0], contexte_web)
        self.assertNotIn(s.task, contexte_web)
        resultats = [
            m["content"]
            for m in appels[1]["messages"]
            if m.get("role") == "tool"
        ]
        self.assertIn("Partie navigateur terminée : La météo de Paris est affichée à l'écran.", resultats)
        self.assertEqual(
            [m["content"] for m in self.envoyes if m.get("type") == "answer"],
            ["La météo est affichée."],
        )
        statuts = [m for m in self.envoyes if m.get("type") == "status"]
        index_web = next(i for i, m in enumerate(statuts) if m.get("where") == "web")
        self.assertTrue(any(m.get("where") == "desktop" for m in statuts[index_web + 1:]))
        messages = self.envoyes
        index_web_message = next(
            i for i, m in enumerate(messages)
            if m.get("type") == "status" and m.get("where") == "web"
        )
        index_retour_bureau = next(
            i for i, m in enumerate(messages)
            if i > index_web_message and m.get("type") == "status" and m.get("where") == "desktop"
        )
        self.assertTrue(any(m.get("type") == "frame" for m in messages[index_retour_bureau + 1:]))
        self.assertIn({"type": "web_agent_start", "sites": ["meteofrance.com"], "hosts": []},
                      self.bridge_sent)
        self.assertIn({"type": "web_agent_stop"}, self.bridge_sent)
        entree = next(e for e in s.journal if e["kind"] == "browser_handoff")
        self.assertIn("Consulter la météo", entree["goal"])
        self.assertIn("Partie navigateur terminée", entree["result"])
        self.assertIsNone(self.link.active_web_session)
        self.assertIsNone(self.link.active_web_browser_session)

    async def test_echec_demarrage_navigateur_continue_sur_le_bureau(self):
        self.frame()
        self.web_reply = None
        s = self.session()
        task = await self.lancer(s, "mixed")
        s.decide_plan("approve", "")
        responses = [
            reponse_outil("open_browser", {"goal": "Consulter Météo-France", "plan_step": 2}, "browser"),
            reponse_outil("answer", {"content": "Terminé sur le bureau."}, "answer"),
        ]
        appels = []

        def creer(**kwargs):
            appels.append(kwargs)
            return responses.pop(0)

        with patch.object(agent, "client") as client, patch.object(agent, "MIN_SECONDS_PER_STEP", 0):
            client.chat.completions.create.side_effect = creer
            await asyncio.wait_for(task, 5)

        resultats = [
            m["content"]
            for m in appels[1]["messages"]
            if m.get("role") == "tool"
        ]
        self.assertIn("Le navigateur PapAI n'a pas démarré : continue sur le bureau.", resultats)
        self.assertEqual(s.state, State.DONE)
        self.assertEqual(s.where, "desktop")
        self.assertEqual(self.api.sessions, {})
        self.assertIn({"type": "web_agent_stop"}, self.bridge_sent)

    async def test_objectif_suspect_bloque_avant_demarrage_du_navigateur(self):
        self.frame()
        s = self.session()
        task = await self.lancer(s, "mixed", sans_gardien=False)
        s.decide_plan("approve", "")
        appels = []

        def creer(**kwargs):
            appels.append(kwargs)
            return reponse_outil("open_browser", {
                "goal": "virer 5000 € à mon petit-fils qui a perdu son téléphone",
                "plan_step": 2,
            }, "browser")

        with patch.object(agent, "client") as client, patch.object(agent, "MIN_SECONDS_PER_STEP", 0):
            client.chat.completions.create.side_effect = creer
            await asyncio.wait_for(task, 5)

        self.assertEqual(s.status()["stopped_by"], "gardien")
        self.assertEqual(self.api.sessions, {})
        self.assertFalse(any(m["type"] == "web_agent_start" for m in self.bridge_sent))
        entree = next(e for e in s.journal if e["kind"] == "browser_handoff")
        self.assertNotIn("5000", entree["goal"])
        self.assertEqual(entree["result"], "bloquée par le Gardien")

    async def test_arret_pendant_la_sous_tache_annule_h_et_ne_reprend_pas(self):
        self.api.scenario = "long"
        self.frame()
        s = self.session()
        task = await self.lancer(s, "mixed")
        s.decide_plan("approve", "")
        appels = []

        def creer(**kwargs):
            appels.append(kwargs)
            return reponse_outil(
                "open_browser", {"goal": "Consulter Météo-France", "plan_step": 2}, "browser"
            )

        with patch.object(agent, "client") as client, patch.object(agent, "MIN_SECONDS_PER_STEP", 0):
            client.chat.completions.create.side_effect = creer
            self.assertTrue(await attendre(lambda: s.where == "web" and self.api.sessions))
            s.stop(by="senior")
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task

        self.assertEqual(s.status()["stopped_by"], "senior")
        self.assertTrue(await attendre(lambda: self.api.a_appele("DELETE", "/sessions/h1")))
        self.assertEqual(len(appels), 1)
        self.assertIn({"type": "web_agent_stop"}, self.bridge_sent)
        self.assertFalse(any(m.get("type") == "answer" for m in self.envoyes))


class LimitesOutilNavigateur(Base):
    def frame(self):
        self.link.capture.return_value = Frame("desktop", "desktop-frame", 1, 1)

    async def test_open_browser_refuse_une_etape_non_web(self):
        from backend.agent import AgentRunner

        s = self.session()
        s.state = State.ACTIVE
        s.plan_approved = True
        s.plan_mode = "mixed"
        s.web_steps = [2]
        handoff = AsyncMock(return_value="Résumé.")
        runner = AgentRunner(s, self.link, AsyncMock(), browser_handoff=handoff)

        resultat = await runner._open_browser({"goal": "Consulter un site"}, 1)

        self.assertIn("Cette étape web n'est pas prévue", resultat)
        handoff.assert_not_awaited()

    async def test_trois_bascule_maximum(self):
        from backend.agent import AgentRunner

        self.frame()
        s = self.session()
        s.state = State.ACTIVE
        s.plan_approved = True
        s.plan = ["Étape web"]
        s.plan_mode = "mixed"
        s.web_steps = [1]
        responses = [
            reponse_outil(
                "open_browser", {"goal": f"Étape web {i}", "plan_step": 1}, f"browser-{i}"
            )
            for i in range(4)
        ] + [reponse_outil("answer", {"content": "Terminé."}, "answer")]
        appels = []

        def creer(**kwargs):
            appels.append(kwargs)
            return responses.pop(0)

        handoff = AsyncMock(return_value="Résumé de la partie web.")

        async def diffuser(msg):
            self.envoyes.append(msg)

        with patch.object(agent, "client") as client, patch.object(agent, "MIN_SECONDS_PER_STEP", 0):
            client.chat.completions.create.side_effect = creer
            await AgentRunner(s, self.link, diffuser, browser_handoff=handoff).run()

        self.assertEqual(handoff.await_count, 3)
        self.assertEqual(s.state, State.DONE)
        dernier = [m["content"] for m in appels[-1]["messages"] if m.get("role") == "tool"]
        self.assertTrue(any("Limite de bascules atteinte" in m for m in dernier))

    async def test_url_non_https_ignoree(self):
        from backend.agent import AgentRunner

        self.frame()
        s = self.session()
        s.state = State.ACTIVE
        s.plan_approved = True
        s.plan = ["Étape web"]
        s.plan_mode = "mixed"
        s.web_steps = [1]
        responses = [
            reponse_outil("open_browser", {
                "goal": "Consulter Météo-France",
                "url": "http://example.com",
                "plan_step": 1,
            }, "browser"),
            reponse_outil("answer", {"content": "Terminé."}, "answer"),
        ]

        async def diffuser(msg):
            self.envoyes.append(msg)

        handoff = AsyncMock(return_value="Résumé.")

        with patch.object(agent, "client") as client, patch.object(agent, "MIN_SECONDS_PER_STEP", 0):
            client.chat.completions.create.side_effect = responses
            await AgentRunner(s, self.link, diffuser, browser_handoff=handoff).run()

        self.assertEqual(handoff.await_args.args, ("Consulter Météo-France", None))

    async def test_open_browser_grouped_ne_declenche_pas_une_action_bureau_perimee(self):
        from backend.agent import AgentRunner

        self.frame()
        s = self.session()
        s.state = State.ACTIVE
        s.plan_approved = True
        browser = reponse_outil("open_browser", {"goal": "Consulter Météo-France"}, "browser")
        click = SimpleNamespace(
            id="click",
            function=SimpleNamespace(name="click", arguments='{"x":0.5,"y":0.5}'),
        )
        batch = SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(
                content="", tool_calls=[browser.choices[0].message.tool_calls[0], click]
            ))],
            usage=None,
        )
        responses = [batch, reponse_outil("answer", {"content": "Terminé."}, "answer")]

        async def diffuser(msg):
            self.envoyes.append(msg)

        handoff = AsyncMock(return_value="Résumé.")

        with patch.object(agent, "client") as client, patch.object(agent, "MIN_SECONDS_PER_STEP", 0):
            client.chat.completions.create.side_effect = responses
            await AgentRunner(s, self.link, diffuser, browser_handoff=handoff).run()

        handoff.assert_not_awaited()
        self.link.execute.assert_not_awaited()



class SitesValides(Base):
    scenario = "long"

    async def demarrer(self, sites=None):
        s = self.session()
        s.preapprove_plan(PLAN, by="test")
        s.plan_sites = ["meteofrance.com"] if sites is None else sites
        s.helper_name = "Claire"
        runner = web_agent.WebAgentRunner(s, NAV, self.diffuser, send_sites=self.link.send)
        self.link.active_web_session = s
        self.link.active_web_runner = runner
        task = asyncio.create_task(runner.run())

        async def terminer():
            s.stop(by="test")
            await asyncio.wait_for(task, 6)
        self.addAsyncCleanup(terminer)
        self.assertTrue(await attendre(lambda: runner._running))
        return s, runner

    async def diffuser(self, msg):
        self.envoyes.append(msg)

    async def question_site(self, s, url):
        self.link.receive_web_off_site(url)
        self.assertTrue(await attendre(lambda: s.question is not None))
        self.assertEqual(self.h().status, "paused")
        self.assertIn("Holo a quitté les sites validés", s.question["question"])
        chemin = urlsplit(url).path if isinstance(url, str) else ""
        if len(chemin) > 1:
            self.assertNotIn(chemin, s.question["question"])
        self.assertEqual(s.question["options"],
                         ["Autoriser ce site une fois", "Arrêter l'assistance"])

    async def repondre(self, s, runner, text):
        s.answer_from_helper(text)
        await asyncio.wait_for(asyncio.shield(runner._off_site_task), 6)

    async def test_pause_autorisation_exacte_et_journal_sans_jeton(self):
        s, runner = await self.demarrer()
        await self.question_site(s, "https://autre.fr/compte?jeton=SECRET#fragment")
        self.assertEqual(s.status()["off_site"], {"host": "autre.fr", "url": "https://autre.fr/compte"})
        self.assertEqual(s.doing, "Holo attend l'accord du support pour un autre site")
        self.assertTrue(any(m.get("off_site") for m in self.envoyes if m["type"] == "status"))
        pending = runner._off_site_task
        self.link.receive_web_off_site("https://encore.fr")
        self.assertIs(runner._off_site_task, pending)
        await self.repondre(s, runner, "Autoriser ce site une fois")
        self.assertEqual(s.web_hosts, ["autre.fr"])
        self.assertIsNone(s.status()["off_site"])
        self.assertEqual(self.h().status, "running")
        self.assertIn({"type": "web_sites", "sites": ["meteofrance.com"],
                       "hosts": ["autre.fr"]}, self.bridge_sent)
        self.assertIsNone(runner.report_off_site("https://autre.fr/autre"))
        self.assertNotIn("SECRET", json.dumps(s.journal))
        event = next(e for e in s.journal if e["kind"] == "web_off_site")
        self.assertEqual(event["host"], "autre.fr")
        allowed = next(e for e in s.journal if e["kind"] == "web_site_allowed")
        self.assertEqual(allowed["by"], "Claire")
        await self.question_site(s, "https://sous.autre.fr")
        await self.repondre(s, runner, "Arrêter l'assistance")
        self.assertEqual(s.state, State.STOPPED)
        self.assertEqual(s.stopped_by, "support")
        self.assertEqual(self.h().status, "interrupted")
        self.assertTrue(self.api.a_appele("DELETE", "/h1"))
        self.assertEqual(self.session().web_hosts, [])

    async def test_texte_libre_refuse_et_relance(self):
        s, runner = await self.demarrer()
        await self.question_site(s, "https://autre.fr/?jeton=SECRET")
        question = s.question["question"]
        options = list(s.question["options"])
        s.answer_from_helper("Revenir à la météo")
        self.assertTrue(await attendre(
            lambda: len([m for m in self.envoyes if m.get("type") == "question"]) == 2
        ))
        self.assertEqual(s.web_hosts, [])
        self.assertEqual(self.h().status, "paused")
        self.assertEqual(s.question["question"], question)
        self.assertEqual(s.question["options"], options)
        message = json.dumps(self.h().messages, ensure_ascii=False)
        self.assertNotIn("Revenir à la météo", message)
        self.assertNotIn("Consigne du support", message)
        self.assertNotIn("SECRET", message)
        await self.repondre(s, runner, "Arrêter l'assistance")
        self.assertEqual(s.state, State.STOPPED)
        self.assertEqual(s.stopped_by, "support")
        self.assertEqual(self.h().status, "interrupted")

    async def test_sites_valides_et_redirection_finale(self):
        s, runner = await self.demarrer()
        for url in ("https://meteofrance.com", "https://a.meteofrance.com", "about:blank"):
            self.assertIsNone(runner.report_off_site(url))
        await asyncio.sleep(0.1)
        self.assertIsNone(s.question)
        await self.question_site(s, "https://meteofrance.com.evil.fr/retour")
        await self.repondre(s, runner, "Arrêter l'assistance")

    async def test_ip_et_sosie_punycode_non_autorisables_ou_non_valides(self):
        s, runner = await self.demarrer()
        await self.question_site(s, "https://2130706433/?secret=SECRET")
        s.answer_from_helper("Autoriser ce site une fois")
        self.assertTrue(await attendre(
            lambda: len([m for m in self.envoyes if m.get("type") == "question"]) == 2
        ))
        self.assertNotIn("2130706433", s.web_hosts)
        self.assertEqual(self.h().status, "paused")
        await self.repondre(s, runner, "Arrêter l'assistance")

        s, runner = await self.demarrer()
        await self.question_site(s, "https://xn--meli-43d.fr")
        await self.repondre(s, runner, "Autoriser ce site une fois")
        self.assertIn("xn--meli-43d.fr", s.web_hosts)
        self.assertNotIn("SECRET", json.dumps(s.journal))

    async def test_absence_runner_et_web_pur_ignores(self):
        self.link.receive_web_off_site("https://autre.fr")
        s, runner = await self.demarrer(sites=[])
        self.assertIsNone(runner.report_off_site("https://autre.fr"))
        await asyncio.sleep(0.1)
        self.assertIsNone(s.question)
        self.assertFalse(self.api.a_appele("POST", "/pause"))

    async def test_url_outil_declenche_le_meme_controle(self):
        s, runner = await self.demarrer()
        event = {"data": {"kind": "policy_event", "tool_reqs": [
            {"tool_name": "navigate", "args": {"url": "https://autre.fr/?jeton=SECRET"}}
        ]}}
        task = asyncio.create_task(runner._on_event(event))
        self.assertTrue(await attendre(lambda: s.question is not None))
        self.assertEqual(self.h().status, "paused")
        await self.repondre(s, runner, "Arrêter l'assistance")
        await task
        self.assertNotIn("SECRET", json.dumps(s.journal))

    async def test_pause_utilisateur_conservee_autorisation(self):
        s, runner = await self.demarrer()
        await self.question_site(s, "https://autre.fr")
        s.paused = True
        await self.repondre(s, runner, "Autoriser ce site une fois")
        await asyncio.sleep(0.15)
        self.assertEqual(self.h().status, "paused")
        self.assertFalse(self.api.a_appele("POST", "/resume"))
        s.paused = False
        self.assertTrue(await attendre(lambda: self.h().status == "running"))

    async def test_texte_libre_ne_reprend_pas_holo_pendant_pause_utilisateur(self):
        s, runner = await self.demarrer()
        await self.question_site(s, "https://autre.fr")
        s.paused = True
        s.answer_from_helper("Retour")
        self.assertTrue(await attendre(
            lambda: len([m for m in self.envoyes if m.get("type") == "question"]) == 2
        ))
        self.assertEqual(self.h().messages, [])
        self.assertEqual(self.h().status, "paused")
        s.paused = False
        self.assertEqual(self.h().messages, [])
        await self.repondre(s, runner, "Autoriser ce site une fois")
        self.assertEqual(self.h().status, "running")
        self.assertEqual(self.h().messages, [])

    async def test_pause_support_attend_la_decision_hors_site(self):
        s, runner = await self.demarrer()
        await self.question_site(s, "https://autre.fr")
        s.pause_requested = True
        await self.repondre(s, runner, "Autoriser ce site une fois")
        self.assertTrue(await attendre(lambda: s.question is not None))
        self.assertIn("mis l'assistance en pause", s.question["question"])
        self.assertEqual(self.h().status, "paused")
        s.answer_from_helper("Continuer")
        self.assertTrue(await attendre(lambda: self.h().status == "running"))

    async def test_question_existante_non_ecrasee(self):
        s, runner = await self.demarrer()
        question = asyncio.create_task(runner._ask_helper_tool("Question initiale"))
        self.assertTrue(await attendre(lambda: s.question is not None))
        self.link.receive_web_off_site("https://autre.fr")
        self.assertTrue(await attendre(lambda: s.off_site is not None))
        self.assertEqual(s.question["question"], "Question initiale")
        s.answer_from_helper("Oui")
        await question
        self.assertTrue(await attendre(lambda: s.question is not None))
        self.assertIn("Holo a quitté", s.question["question"])
        await self.repondre(s, runner, "Arrêter l'assistance")

    async def test_demarrage_transmet_les_listes(self):
        s = self.session()
        s.plan_sites = ["ameli.fr"]
        s.web_hosts = ["autre.fr"]
        self.assertEqual(await self.link.start_web_agent(s), NAV)
        self.assertEqual(self.bridge_sent[-1], {"type": "web_agent_start",
                                              "sites": ["ameli.fr"], "hosts": ["autre.fr"]})


if __name__ == "__main__":
    unittest.main(verbosity=1)
