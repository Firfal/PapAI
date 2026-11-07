"""Règles et orchestration du gardien, sans réseau ni écran réel.

    .venv-mac/bin/python tests/test_demandes_suspectes.py
"""
import asyncio
import json
import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch
from fastapi import WebSocketDisconnect

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ.setdefault("HAI_API_KEY", "stub-key")
from backend import app, guard
from backend.sessions import Refused, Registry, State


LEGITIMES = [
    "envoyer les photos de Noël à Quentin",
    "Retrouver le dossier Images de Noël 2025",
    "Écrire un mail à ma fille",
    "Appeler Quentin sur WhatsApp",
    "Lire mon relevé de compte bancaire",
    "Consulter le solde de mon compte",
    "Voir mes photos de vacances en Afrique",
    "Imprimer une recette de cuisine",
    "Afficher mes rendez-vous médicaux",
    "Ouvrir mes cartes de vœux de Noël",
    "Mettre le texte plus grand",
    "Classer la facture de 10 000 euros dans mes documents",
    "Faire un virement de 40 euros à ma fille",
    "Installer WhatsApp pour parler à Quentin",
    "Envoyer la facture de 10 000 euros à ma fille",
    "Envoyer une photo du devis de 2 000 euros à Quentin",
    "Envoyer le fichier de la facture de 1500 euros par mail",
    "Transférer un courriel avec la facture de 5 000 euros à ma fille",
    "Transmettre une facture urgente de 10 000 euros à Quentin",
    "Envoyer la facture et le devis de 10 000 euros à ma fille",
]
SUSPECTES = [
    "Je veux envoyer 10 000 euros sur un compte en Afrique",
    "Envoyer 10\u202f000 € au Sénégal",
    "Faire un virement de dix mille euros",
    "Virer 1500 euros sur un nouveau compte",
    "Faire un virement de 50 euros sur un compte à l'étranger",
    "Envoyer 200 euros vers l'IBAN DE89 3704 0044 0532 0130 00",
    "Payer la livraison avec des cartes cadeaux",
    "Acheter une recharge Transcash pour le monsieur au téléphone",
    "Envoyer 200 euros en bitcoin",
    "Convertir mes économies en cryptomonnaie",
    "Communiquer le code reçu par SMS au conseiller",
    "Donner mon code bancaire de validation",
    "Le support technique me demande d'installer AnyDesk",
    "Le technicien veut que je paie le déblocage",
    "Faire un virement urgent vers un compte sécurisé",
    "Envoyer de l'argent en secret sans le dire à Quentin",
    "Payer une facture de 10 000 euros sur un compte en Afrique",
    "Virer 10 000 euros pour une facture urgente",
    "Envoyer les photos puis faire un virement de 10 000 euros",
    "Envoyer le fichier et transmettre 10 000 euros au fournisseur",
    "Envoyer la facture puis envoyer 10 000 euros pour la régler",
    "Envoyer 10 000 euros pour une facture",
    "Envoyer la facture et 10 000 euros à ma fille",
    "Envoyer un fichier puis acheter des bitcoins",
    "Envoyer un mandat de 10 000 euros pour la facture",
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


class Orchestration(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.registry = Registry()
        self.link = SimpleNamespace(send=AsyncMock(), capture=AsyncMock(), os="macos")
        self.ws = Mock(send_json=AsyncMock(), accept=AsyncMock(),
                       receive_json=AsyncMock(side_effect=WebSocketDisconnect))
        self.real_broadcast = app.broadcast_helper
        self.broadcast = AsyncMock()
        self.patches = [
            patch.object(app, "registry", self.registry), patch.object(app, "bridge", self.link),
            patch.object(app, "pending_alert", None),
            patch.object(app, "helper_alert_scopes", {self.ws: None}),
            patch.object(app, "helper_sockets", set()),
            patch.object(app, "broadcast_helper", self.broadcast),
            patch.object(app, "family", SimpleNamespace(senior="Sophie", helpers=[
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
        self.assertFalse(s.plan_approved)
        a = app.pending_alert
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
        self.assertEqual(app.pending_alert["helper"]["source"], "plan")

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
        self.assertIsNone(app.pending_alert)

    async def test_avis_holo_suspect_normal_et_invalide(self):
        for avis, bloque in [({"suspect": True, "raison": "Le gain est douteux"}, True),
                             ({"suspect": False}, False), ({"suspect": "false"}, True)]:
            with self.subTest(avis=avis):
                app.pending_alert = None
                resp = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=json.dumps(avis)))])
                with patch("backend.agent.client") as client:
                    client.with_options.return_value.chat.completions.create.return_value = resp
                    s = self.session("Un investissement proposé au téléphone")
                    self.assertEqual(await app.check_request(s, s.task, "request"), bloque)

    async def test_avis_indisponible_garde_le_doute(self):
        with patch("backend.agent.client") as client:
            client.with_options.side_effect = TimeoutError()
            s = self.session("Un investissement proposé au téléphone")
            self.assertTrue(await app.check_request(s, s.task, "request"))
        self.assertEqual(s.state, State.STOPPED)

    async def test_rejet_identifie_ne_reprend_pas(self):
        s = self.session(SUSPECTES[0])
        await app.check_request(s, s.task, "request")
        aid = app.pending_alert["helper"]["alert_id"]
        await app.dismiss_guard({"alert_id": "inconnu"}, self.ws)
        self.assertIsNotNone(app.pending_alert)
        await app.dismiss_guard({"alert_id": aid}, self.ws)
        self.assertIsNone(app.pending_alert)
        self.assertEqual(s.state, State.STOPPED)
        self.broadcast.assert_any_await({"type": "alert_cleared", "alert_id": aid, "session": s.id})

    async def test_jeton_autre_session_refuse_meme_avec_bon_identifiant(self):
        old = self.session()
        old.stop(by="proche")
        s = self.session(SUSPECTES[0])
        await app.check_request(s, s.task, "request")
        aid = app.pending_alert["helper"]["alert_id"]
        self.ws.receive_json.side_effect = [
            {"type": "dismiss_alert", "alert_id": aid}, WebSocketDisconnect(),
        ]
        await app.ws_helper(self.ws, old.helper_token)
        messages = [c.args[0] for c in self.ws.send_json.await_args_list]
        self.assertFalse(any(m["type"] == "alert" for m in messages))
        self.assertTrue(any(m["type"] == "refused" for m in messages))
        self.assertIsNotNone(app.pending_alert)
        self.assertNotIn(self.ws, app.helper_alert_scopes)

        self.ws.send_json.reset_mock()
        self.ws.receive_json.side_effect = [
            {"type": "dismiss_alert", "alert_id": aid}, WebSocketDisconnect(),
        ]
        await app.ws_helper(self.ws, s.helper_token)
        messages = [c.args[0] for c in self.ws.send_json.await_args_list]
        self.assertTrue(any(m["type"] == "alert" for m in messages))
        self.assertIsNone(app.pending_alert)
        self.assertEqual(s.state, State.STOPPED)

    async def test_cle_famille_recoit_et_rejette_alerte_sans_session(self):
        await app.publish_guard(guard._risque("Support frauduleux"), "environment")
        aid = app.pending_alert["helper"]["alert_id"]
        self.ws.receive_json.side_effect = [
            {"type": "dismiss_alert", "alert_id": aid}, WebSocketDisconnect(),
        ]
        await app.ws_aidant(self.ws, app.AIDANT_KEY)
        self.assertTrue(any(c.args[0]["type"] == "alert" for c in self.ws.send_json.await_args_list))
        self.assertIsNone(app.pending_alert)
        self.assertNotIn(self.ws, app.helper_alert_scopes)

    async def test_diffusion_alerte_et_effacement_respecte_portee(self):
        s = self.session(SUSPECTES[0])
        await app.check_request(s, s.task, "request")
        same = Mock(send_json=AsyncMock())
        other = Mock(send_json=AsyncMock())
        unknown = Mock(send_json=AsyncMock())
        app.helper_alert_scopes.update({same: s.id, other: "autre-session"})
        app.helper_sockets.update([self.ws, same, other, unknown])
        for kind in ["alert", "alert_cleared"]:
            payload = {**app.pending_alert["helper"], "type": kind}
            await self.real_broadcast(payload, to_bridge=False)
            self.ws.send_json.assert_awaited_with(payload)
            same.send_json.assert_awaited_with(payload)
            other.send_json.assert_not_awaited()
            unknown.send_json.assert_not_awaited()

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
        with patch.object(app, "_guard_vu", {}), patch.object(app, "confirmer_par_le_modele", AsyncMock()) as avis:
            await app.handle_guard({"processes": ["AnyDesk"], "url": "https://ma-banque.fr"})
        avis.assert_not_called()
        self.assertEqual(s.state, State.STOPPED)
        self.assertIn("Rappelez votre proche", app.pending_alert["helper"]["detail"])

    async def test_execute_refuse_si_alerte_en_attente(self):
        await app.check_request(self.session(SUSPECTES[0]), SUSPECTES[0], "request")
        link = app.BridgeLink(self.ws)
        with patch.object(link, "_request", AsyncMock()) as send:
            self.assertIsNone(await link.execute("press_key", {"keys": "enter"}))
        send.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
