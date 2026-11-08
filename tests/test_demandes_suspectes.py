"""Règles et orchestration du gardien, sans réseau ni écran réel.

    .venv-mac/bin/python tests/test_demandes_suspectes.py
"""
import asyncio
import json
import os
import sys
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch
from fastapi import WebSocketDisconnect

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ.setdefault("HAI_API_KEY", "stub-key")
from backend import app, guard
from backend.sessions import Frame, Refused, Registry, State


LEGITIMES = [
    "Je ne retrouve plus le dossier de la comptabilité",
    "Imprimer le rapport mensuel",
    "Mon mot de passe Outlook a expiré",
    "Réinitialiser mon mot de passe Windows",
    "J'ai oublié mon mot de passe",
    "Changer mon mot de passe sur le portail RH",
    "Mon mot de passe a expiré, le support veut que je le change",
    "Je ne reçois pas le code par SMS pour me connecter",
    "Configurer Microsoft Authenticator sur mon nouveau téléphone",
    "Valider ma connexion sur le portail RH",
    "Le support me demande de redémarrer mon ordinateur",
    "Envoyer le code source du projet à Marc",
    "Envoyer le rapport au directeur",
    "Installer Teams",
    "Partager un fichier avec un collègue sur OneDrive",
    "Le Wi-Fi ne marche plus",
    "Connecter l'imprimante du bureau",
    "Ouvrir l'intranet sur intranet.acme.fr",
    "Se connecter à login.microsoftonline.com",
    "Mettre à jour Windows",
    "Faire un virement de 40 euros",
    "Acheter une carte cadeau pour le pot de départ d'un collègue",
    "Envoyer un rapport sur les mots de passe expirés",
]
SUSPECTES = [
    "Le support m'a appelé, il veut le code reçu par SMS",
    "Un technicien de Microsoft me demande mon mot de passe",
    "Donner mon mot de passe au technicien au téléphone",
    "Communiquer le code de vérification au support",
    "Envoyer mes identifiants à mon manager",
    "Dicter le code à 6 chiffres à la personne au téléphone",
    "Le c o d e reçu par s.m.s, l'envoyer au support",
    "On me demande de valider la notification Microsoft Authenticator au téléphone",
    "J'ai reçu plein de demandes de connexion sur mon téléphone",
    "Des notifications d'authentification que je n'ai pas demandées",
    "Le support technique me demande d'installer AnyDesk",
    "Un monsieur au téléphone veut que j'installe TeamViewer",
    "Une fenêtre dit que j'ai un virus, appelez ce numéro",
    "Mon ordinateur est bloqué, il faut appeler le support Microsoft au numéro affiché",
    "Saisir mes identifiants sur le lien reçu par mail",
    "Se connecter sur microsoft-login-secure.com",
    "Ouvrir la page http://45.33.12.7/login",
    "Saisir mon mot de passe sur office365-verification.com",
    "Le support veut mon mot de passe pour changer un paramètre",
    "Donner au technicien mon mot de passe",
    "Envoyer à la personne au téléphone le code de vérification",
]


class Regles(unittest.TestCase):
    def test_demandes_legitimes(self):
        for texte in LEGITIMES:
            with self.subTest(texte=texte):
                self.assertIsNone(guard.evaluer_demande(texte))
                self.assertFalse(guard.demande_incertaine(texte))

    def test_demandes_suspectes(self):
        for texte in SUSPECTES:
            with self.subTest(texte=texte):
                self.assertIsNotNone(guard.evaluer_demande(texte))

    def test_entreprise_declare_ses_outils_et_domaines(self):
        self.assertIsNone(guard.evaluer_demande("Le support technique me demande d'installer TeamViewer",
                                                outils_declares=["teamviewer"]))
        self.assertIsNotNone(guard.evaluer_demande("Le support technique me demande d'installer AnyDesk",
                                                   outils_declares=["teamviewer"]))
        self.assertIsNotNone(guard.evaluer_demande("Ouvrir acmee.fr", domaines_org=["acme.fr"]))
        self.assertIsNone(guard.evaluer_demande("Ouvrir acme.fr", domaines_org=["acme.fr"]))


class Orchestration(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.registry = Registry()
        self.link = SimpleNamespace(send=AsyncMock(), capture=AsyncMock(), os="macos")
        self.ws = Mock(send_json=AsyncMock(), accept=AsyncMock(),
                       receive_json=AsyncMock(side_effect=WebSocketDisconnect))
        self.real_broadcast = app.broadcast_helper
        self.broadcast = AsyncMock()
        self.patches = [
            patch.object(app.S(), "registry", self.registry), patch.object(app.S(), "bridge", self.link),
            patch.object(app.S(), "pending_alert", None),
            patch.object(app.S(), "helper_alert_scopes", {self.ws: None}),
            patch.object(app.S(), "helper_sockets", set()),
            patch.object(app, "broadcast_helper", self.broadcast),
            patch.object(app.S(), "family", SimpleNamespace(senior="Sophie", helpers=[
                {"id": "q", "name": "Quentin", "relation": "mon petit-fils"}])),
        ]
        for p in self.patches:
            p.start()
            self.addCleanup(p.stop)

    def session(self, task="Retrouver mes photos"):
        s = self.registry.create(task)
        s.grant_consent()
        return s

    async def test_exemple_sans_holo_ni_capture_ni_plan(self):
        s = self.session(SUSPECTES[0])
        with patch.object(app, "propose_plan", AsyncMock()) as plan, patch("backend.agent.client") as client:
            await app.run_session(s, self.link)
        plan.assert_not_called()
        client.with_options.assert_not_called()
        self.link.capture.assert_not_called()
        self.assertEqual(s.state, State.STOPPED)
        self.assertEqual(s.status()["stopped_by"], "gardien")
        self.assertFalse(s.plan_approved)
        a = app.S().pending_alert
        self.assertIn("votre petit-fils Quentin", a["senior"]["detail"])
        self.assertIn("Sophie", a["helper"]["title"])
        self.assertIn(s.task, a["helper"]["detail"])
        self.assertNotEqual(a["senior"]["detail"], a["helper"]["detail"])
        with self.assertRaises(Refused):
            s.decide_plan("approve", "")

    async def test_plan_suspect_jamais_propose(self):
        s = self.session()
        with patch.object(app, "propose_plan", AsyncMock(return_value=[SUSPECTES[0]])), \
                patch.object(app, "AgentRunner") as runner:
            await app.run_session(s, self.link)
        runner.assert_not_called()
        self.assertIsNone(s.plan)
        self.assertEqual(app.S().pending_alert["helper"]["source"], "plan")

    async def test_plan_revise_verifie_aussi(self):
        s = self.session()
        with patch.object(app, "propose_plan", AsyncMock(side_effect=[["Ouvrir Images"], [SUSPECTES[0]]])):
            task = asyncio.create_task(app.run_session(s, self.link))
            for _ in range(50):
                if s.state == State.AWAITING_APPROVAL:
                    break
                await asyncio.sleep(0)
            s.decide_plan("refine", "Préciser le dossier")
            await task
        self.assertEqual(s.state, State.STOPPED)
        self.assertFalse(s.plan_approved)

    async def test_toutes_legitimes_sans_avis_holo(self):
        with patch("backend.agent.client") as client:
            for texte in LEGITIMES:
                self.assertFalse(await app.check_request(self.session(texte), texte, "request"))
        client.with_options.assert_not_called()
        self.assertIsNone(app.S().pending_alert)

    async def test_avis_holo_suspect_normal_et_invalide(self):
        for avis, bloque in [({"suspect": True, "raison": "Le gain est douteux"}, True),
                             ({"suspect": False}, False), ({"suspect": "false"}, False)]:
            with self.subTest(avis=avis):
                app.S().pending_alert = None
                resp = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=json.dumps(avis)))])
                with patch("backend.agent.client") as client:
                    client.with_options.return_value.chat.completions.create.return_value = resp
                    s = self.session("Un technicien veut prendre la main sur mon ordinateur")
                    self.assertEqual(await app.check_request(s, s.task, "request"), bloque)

    async def test_avis_indisponible_avertit_seulement_le_proche(self):
        with patch("backend.agent.client") as client:
            client.with_options.side_effect = TimeoutError()
            s = self.session("Un technicien veut prendre la main sur mon ordinateur")
            self.assertFalse(await app.check_request(s, s.task, "request"))
        self.assertEqual(s.state, State.PLANNING)
        self.assertIsNone(app.S().pending_alert)
        self.link.send.assert_not_awaited()
        args = self.broadcast.await_args
        self.assertEqual(args.args[0]["type"], "guard_advice")
        self.assertEqual(args.args[0]["level"], "attention")
        self.assertFalse(args.kwargs["to_bridge"])

    async def test_holo_sans_reponse_laisse_le_plan_attendre_validation(self):
        release = threading.Event()
        def sans_reponse(**kwargs):
            release.wait(1)
            raise TimeoutError()
        s = self.session("Un technicien veut prendre la main sur mon ordinateur")
        with patch("backend.agent.client") as client, \
                patch.object(app, "GUARD_ADVICE_TIMEOUT_S", 0.01), \
                patch.object(app, "propose_plan", AsyncMock(return_value=["Ouvrir le document"])), \
                patch.object(app, "AgentRunner") as runner:
            client.with_options.return_value.chat.completions.create.side_effect = sans_reponse
            task = asyncio.create_task(app.run_session(s, self.link))
            try:
                for _ in range(100):
                    if s.state == State.AWAITING_APPROVAL:
                        break
                    await asyncio.sleep(0.01)
                self.assertEqual(s.state, State.AWAITING_APPROVAL)
                self.assertFalse(s.plan_approved)
                self.assertIsNone(app.S().pending_alert)
                self.link.send.assert_not_awaited()
                runner.assert_not_called()
            finally:
                release.set()
                s.stop(by="test")
                await task

    async def test_rejet_identifie_ne_reprend_pas(self):
        s = self.session(SUSPECTES[0])
        await app.check_request(s, s.task, "request")
        aid = app.S().pending_alert["helper"]["alert_id"]
        await app.dismiss_guard({"alert_id": "inconnu"}, self.ws)
        self.assertIsNotNone(app.S().pending_alert)
        await app.dismiss_guard({"alert_id": aid}, self.ws)
        self.assertIsNone(app.S().pending_alert)
        self.assertEqual(s.state, State.STOPPED)
        self.broadcast.assert_any_await({"type": "alert_cleared", "alert_id": aid, "session": s.id})

    async def test_jeton_autre_session_refuse_meme_avec_bon_identifiant(self):
        old = self.session()
        old.stop(by="proche")
        s = self.session(SUSPECTES[0])
        await app.check_request(s, s.task, "request")
        aid = app.S().pending_alert["helper"]["alert_id"]
        self.ws.receive_json.side_effect = [
            {"type": "dismiss_alert", "alert_id": aid}, WebSocketDisconnect(),
        ]
        await app.ws_helper(self.ws, old.helper_token)
        messages = [c.args[0] for c in self.ws.send_json.await_args_list]
        self.assertFalse(any(m["type"] == "alert" for m in messages))
        self.assertTrue(any(m["type"] == "refused" for m in messages))
        self.assertIsNotNone(app.S().pending_alert)
        self.assertNotIn(self.ws, app.S().helper_alert_scopes)

        self.ws.send_json.reset_mock()
        self.ws.receive_json.side_effect = [
            {"type": "dismiss_alert", "alert_id": aid}, WebSocketDisconnect(),
        ]
        await app.ws_helper(self.ws, s.helper_token)
        messages = [c.args[0] for c in self.ws.send_json.await_args_list]
        self.assertTrue(any(m["type"] == "alert" for m in messages))
        self.assertIsNone(app.S().pending_alert)
        self.assertEqual(s.state, State.STOPPED)

    async def test_cle_famille_recoit_et_rejette_alerte_sans_session(self):
        await app.publish_guard(guard._risque("Support frauduleux"), "environment")
        aid = app.S().pending_alert["helper"]["alert_id"]
        self.ws.receive_json.side_effect = [
            {"type": "dismiss_alert", "alert_id": aid}, WebSocketDisconnect(),
        ]
        await app.ws_aidant(self.ws, app.AIDANT_KEY)
        self.assertTrue(any(c.args[0]["type"] == "alert" for c in self.ws.send_json.await_args_list))
        self.assertIsNone(app.S().pending_alert)
        self.assertNotIn(self.ws, app.S().helper_alert_scopes)

    async def test_diffusion_alerte_et_effacement_respecte_portee(self):
        s = self.session(SUSPECTES[0])
        await app.check_request(s, s.task, "request")
        same = Mock(send_json=AsyncMock())
        other = Mock(send_json=AsyncMock())
        unknown = Mock(send_json=AsyncMock())
        app.S().helper_alert_scopes.update({same: s.id, other: "autre-session"})
        app.S().helper_sockets.update([self.ws, same, other, unknown])
        for kind in ["alert", "alert_cleared", "alert_acknowledged", "guard_advice"]:
            payload = {**app.S().pending_alert["helper"], "type": kind}
            if kind == "guard_advice":
                payload.pop("alert_id")
            await self.real_broadcast(payload, to_bridge=False)
            self.ws.send_json.assert_awaited_with(payload)
            same.send_json.assert_awaited_with(payload)
            other.send_json.assert_not_awaited()
            unknown.send_json.assert_not_awaited()

    async def test_alerte_raccourci_historique_pas_diffusee_a_une_ancienne_session(self):
        old = Mock(send_json=AsyncMock())
        app.S().helper_sockets.update([self.ws, old])
        app.S().helper_alert_scopes[old] = "ancienne-session"
        alert = {"type": "alert", "title": "Raccourci introuvable", "detail": "Le dossier a changé."}
        await self.real_broadcast(alert)
        old.send_json.assert_not_awaited()
        self.ws.send_json.assert_awaited_with(alert)
        self.link.send.assert_awaited_with(alert)

    async def test_prise_en_charge_anonyme_sans_fermeture_ni_reprise(self):
        s = self.session(SUSPECTES[0])
        await app.check_request(s, s.task, "request")
        aid = app.S().pending_alert["helper"]["alert_id"]
        other = Mock(send_json=AsyncMock())
        app.S().helper_alert_scopes[other] = "autre-session"
        await app.acknowledge_guard({"alert_id": aid}, other)
        other.send_json.assert_awaited()
        self.assertNotIn("acknowledged_by", app.S().pending_alert["helper"])
        self.assertFalse(app.S().pending_alert["helper"].get("acknowledged"))
        with patch.object(app.S(), "helper_who", {self.ws: {"name": "Quentin"}}):
            await app.acknowledge_guard({"alert_id": "périmé"}, self.ws)
            self.assertNotIn("acknowledged_by", app.S().pending_alert["helper"])
            self.assertFalse(app.S().pending_alert["helper"].get("acknowledged"))
            await app.acknowledge_guard({"alert_id": aid, "name": "Usurpation"}, self.ws)
            await app.acknowledge_guard({"alert_id": aid}, self.ws)
        self.assertTrue(app.S().pending_alert["helper"]["acknowledged"])
        self.assertTrue(app.S().pending_alert["senior"]["acknowledged"])
        self.assertNotIn("acknowledged_by", app.S().pending_alert["senior"])
        self.assertTrue(s.status()["guard_acknowledged"])
        self.assertEqual(s.status()["stopped_by"], "gardien")
        self.broadcast.assert_any_await({"type": "alert_acknowledged", "alert_id": aid,
                                        "session": s.id, "acknowledged": True})
        await app.ws_helper(self.ws, s.helper_token)
        self.assertTrue(any(c.args[0].get("acknowledged") is True
                            for c in self.ws.send_json.await_args_list))
        app.S().helper_alert_scopes[self.ws] = None
        await app.dismiss_guard({"alert_id": aid}, self.ws)
        self.assertIsNone(app.S().pending_alert)
        self.assertEqual(s.status()["stopped_by"], "gardien")

    async def test_accuse_anonyme_rejoue_et_conserve_apres_rejet(self):
        s = self.session(SUSPECTES[0])
        await app.check_request(s, s.task, "request")
        aid = app.S().pending_alert["helper"]["alert_id"]
        await app.acknowledge_guard({"alert_id": aid}, self.ws)
        await app.dismiss_guard({"alert_id": aid}, self.ws)
        self.assertTrue(s.status()["guard_acknowledged"])
        await app.ws_helper(self.ws, s.helper_token)
        self.assertTrue(any(c.args[0].get("guard_acknowledged") is True
                            for c in self.ws.send_json.await_args_list))

    async def test_arret_avant_tout_geste_explicitement_signale(self):
        s = self.session(SUSPECTES[0])
        await app.check_request(s, s.task, "request")
        self.assertIs(s.status()["execution_started"], False)
        await app.dismiss_guard({"alert_id": app.S().pending_alert["helper"]["alert_id"]}, self.ws)
        self.assertIs(s.status()["execution_started"], False)

    async def test_action_holo_en_cours_comptee_meme_sans_resultat(self):
        s = self.session()
        s.state = State.ACTIVE
        s.plan_approved = True
        started, release = asyncio.Event(), asyncio.Event()
        async def execute(name, args):
            started.set()
            await release.wait()
            return None
        link = SimpleNamespace(execute=execute)
        task = asyncio.create_task(app.AgentRunner(s, link, self.broadcast)._act("click", {}))
        try:
            await asyncio.wait_for(started.wait(), 1)
            self.assertIs(s.status()["execution_started"], True)
            await app.check_request(s, SUSPECTES[0], "plan")
            self.assertIs(s.status()["execution_started"], True)
        finally:
            release.set()
            await task

    async def test_clic_proche_compte_et_clic_refuse_non_compte(self):
        s = self.session()
        with self.assertRaises(Refused):
            await app.handle_helper_click(s, {"frame_id": "f", "x": 0.5, "y": 0.5}, self.ws)
        self.assertIs(s.status()["execution_started"], False)
        s.state = State.AWAITING_HELPER
        s.set_frame(Frame("f", "image", 100, 100))
        with patch.object(app.S(), "bridge", SimpleNamespace(execute=AsyncMock(return_value="clic"))):
            await app.handle_helper_click(s, {"frame_id": "f", "x": 0.5, "y": 0.5}, self.ws)
        s.stop(by="gardien")
        self.assertIs(s.status()["execution_started"], True)

    async def test_nouvelle_demande_bloquee_tant_que_alerte(self):
        s = self.session(SUSPECTES[0])
        await app.check_request(s, s.task, "request")
        new = self.session()
        with patch.object(app, "propose_plan", AsyncMock()) as plan:
            await app.run_session(new, self.link)
        plan.assert_not_called()
        self.assertEqual(new.state, State.STOPPED)

    async def test_veille_arrete_avant_tout_avis(self):
        s = self.session()
        with patch.object(app.S(), "guard_vu", {}), patch.object(app, "confirmer_par_le_modele", AsyncMock()) as avis:
            await app.handle_guard({"processes": ["AnyDesk"], "url": "https://ma-banque.fr"})
        avis.assert_not_called()
        self.assertEqual(s.state, State.STOPPED)
        self.assertIn("Prenez contact avec ", app.S().pending_alert["helper"]["detail"])

    async def test_execute_refuse_si_alerte_en_attente(self):
        await app.check_request(self.session(SUSPECTES[0]), SUSPECTES[0], "request")
        link = app.BridgeLink(self.ws)
        with patch.object(link, "_request", AsyncMock()) as send:
            self.assertIsNone(await link.execute("press_key", {"keys": "enter"}))
        send.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
