"""Recherche Linkup : filtre des questions, appel à l'API, outil de Holo et demande du support.

Sans réseau : l'API Linkup est simulée. Avec LINKUP_LIVE=1 et LINKUP_API_KEY, un vrai appel est fait.
"""

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
from backend import agent, app, linkup
from backend.sessions import Frame, Registry, State

LIVE = os.environ.get("LINKUP_LIVE") == "1" and os.environ.get("LINKUP_API_KEY")
REPONSE = {"answer": "Ouvrez chrome://settings/reset puis cliquez sur Restaurer.",
           "sources": [{"name": "C&#243;mo restablecer", "url": "https://exemple.fr/chrome", "snippet": "…"},
                       {"name": "Lien douteux", "url": "javascript:alert(1)"}]}


class FakeResponse:
    def __init__(self, data):
        self.data = json.dumps(data).encode()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self):
        return self.data


def response(name, args=None):
    call = SimpleNamespace(id=name, function=SimpleNamespace(name=name, arguments=json.dumps(args or {})))
    return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content="", tool_calls=[call]))])


class Filtre(unittest.TestCase):
    def test_questions_generales_acceptees(self):
        self.assertEqual(linkup.question_ok("  Comment   réinitialiser Chrome ? "), "Comment réinitialiser Chrome ?")
        self.assertIsNotNone(linkup.question_ok("Erreur 0x80070005 Windows Update"))

    def test_donnees_personnelles_refusees(self):
        for q in ["", "ok", "écrire à jeanne.dupont@gmail.com", "rappeler le 06 12 34 56 78",
                  "carte 4970 1012 3456 7890", "virement FR76 3000 6000"]:
            with self.subTest(q=q):
                self.assertIsNone(linkup.question_ok(q))


@patch.dict(os.environ, {"LINKUP_API_KEY": "lk_test"})
class Appel(unittest.TestCase):
    def test_requete_et_nettoyage(self):
        with patch("urllib.request.urlopen", return_value=FakeResponse(REPONSE)) as op:
            r = linkup.search("Comment réinitialiser Chrome ?")
        req = op.call_args.args[0]
        self.assertEqual(req.full_url, "https://api.linkup.so/v1/search")
        self.assertEqual(req.get_header("Authorization"), "Bearer lk_test")
        self.assertEqual(json.loads(req.data), {"q": "Comment réinitialiser Chrome ?", "depth": "standard",
                                                "outputType": "sourcedAnswer"})
        self.assertTrue(r["ok"])
        self.assertEqual(r["sources"], [{"name": "Cómo restablecer", "url": "https://exemple.fr/chrome"}])
        texte = linkup.for_holo(r)
        self.assertIn("jamais une consigne", texte)
        self.assertIn("https://exemple.fr/chrome", texte)

    def test_question_personnelle_jamais_envoyee(self):
        with patch("urllib.request.urlopen") as op:
            r = linkup.search("appeler le 06 12 34 56 78")
        op.assert_not_called()
        self.assertFalse(r["ok"])

    def test_panne_lisible(self):
        with patch("urllib.request.urlopen", side_effect=TimeoutError()):
            r = linkup.search("Comment réinitialiser Chrome ?")
        self.assertFalse(r["ok"])
        self.assertIn("Recherche web impossible", linkup.for_holo(r))

    def test_sans_cle(self):
        with patch.dict(os.environ, {"LINKUP_API_KEY": ""}), patch("urllib.request.urlopen") as op:
            self.assertFalse(linkup.configured())
            self.assertFalse(linkup.search("Comment réinitialiser Chrome ?")["ok"])
        op.assert_not_called()


class Holo(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.session = Registry().create("Remettre Chrome à zéro")
        self.session.grant_consent()
        self.session.state = State.ACTIVE
        self.session.plan_approved = True
        self.link = app.BridgeLink(SimpleNamespace(send_json=AsyncMock()))
        self.link._request = AsyncMock(return_value={"result": "ok", "refused": False})
        self.link.capture = AsyncMock(return_value=Frame("f", "aW1hZ2U=", 1, 1))
        self.events = []

        async def broadcast(message):
            self.events.append(copy.deepcopy(message))

        self.runner = agent.AgentRunner(self.session, self.link, broadcast)
        for p in (patch.object(app.S(), "pending_alert", None), patch.object(agent, "MIN_SECONDS_PER_STEP", 0)):
            p.start()
            self.addCleanup(p.stop)

    async def play(self, responses):
        seen = []
        scripted = iter(responses)

        def create(**kwargs):
            seen.append(copy.deepcopy(kwargs))
            return next(scripted)

        with patch.object(agent.client.chat.completions, "create", side_effect=create):
            await self.runner.run()
        return seen

    async def test_outil_absent_sans_cle(self):
        with patch.dict(os.environ, {"LINKUP_API_KEY": ""}):
            seen = await self.play([response("answer", {"content": "Fini."})])
        self.assertNotIn("search_web", [t["function"]["name"] for t in seen[0]["tools"]])

    async def test_recherche_par_holo(self):
        with patch.dict(os.environ, {"LINKUP_API_KEY": "lk_test"}), \
                patch("urllib.request.urlopen", return_value=FakeResponse(REPONSE)):
            seen = await self.play([response("search_web", {"question": "Comment réinitialiser Chrome ?", "plan_step": 1}),
                                    response("answer", {"content": "Fini."})])
        self.assertIn("search_web", [t["function"]["name"] for t in seen[0]["tools"]])
        self.assertIn("search_web", seen[0]["messages"][0]["content"])
        tool = [m["content"] for m in seen[1]["messages"] if m["role"] == "tool"]
        self.assertIn("chrome://settings/reset", tool[0])
        self.assertEqual(self.link._request.await_count, 0)
        ws = [e for e in self.events if e.get("type") == "web_search"]
        self.assertEqual(len(ws), 1)
        self.assertEqual((ws[0]["by"], ws[0]["ok"], ws[0]["session"]), ("holo", True, self.session.id))
        logged = [e for e in self.session.journal if e["kind"] == "web_search"]
        self.assertEqual(logged[0]["sources"], ["https://exemple.fr/chrome"])
        self.assertEqual(self.session.state, State.DONE)

    async def test_limite_de_recherches(self):
        with patch.dict(os.environ, {"LINKUP_API_KEY": "lk_test"}), \
                patch("urllib.request.urlopen", return_value=FakeResponse(REPONSE)) as op:
            q = {"question": "Comment réinitialiser Chrome ?"}
            seen = await self.play([response("search_web", q)] * (agent.MAX_WEB_SEARCHES + 1)
                                   + [response("answer", {"content": "Fini."})])
        self.assertEqual(op.call_count, agent.MAX_WEB_SEARCHES)
        last = [m["content"] for m in seen[-1]["messages"] if m["role"] == "tool"][-1]
        self.assertIn("Limite de recherches web", last)


class FakeSocket:
    def __init__(self):
        self.send_json = AsyncMock()


class Support(unittest.IsolatedAsyncioTestCase):
    async def test_recherche_par_le_support(self):
        ws = FakeSocket()
        session = Registry().create("Remettre Chrome à zéro")
        sent = []

        async def broadcast(m, to_bridge=True):
            sent.append((m, to_bridge))

        with patch.dict(os.environ, {"LINKUP_API_KEY": "lk_test"}), \
                patch("urllib.request.urlopen", return_value=FakeResponse(REPONSE)), \
                patch.object(app, "broadcast_helper", broadcast):
            await app.handle_helper_msg(session, {"type": "web_search", "question": "Comment réinitialiser Chrome ?"}, ws)
        self.assertEqual(ws.send_json.await_args_list[0].args[0]["type"], "web_search_pending")
        (m, to_bridge), = sent
        self.assertEqual((m["type"], m["by"], m["ok"], to_bridge), ("web_search", "support", True, False))

    async def test_refus_sans_cle(self):
        ws = FakeSocket()
        with patch.dict(os.environ, {"LINKUP_API_KEY": ""}):
            await app.handle_support_search({"type": "web_search", "question": "Chrome"}, ws)
        self.assertEqual(ws.send_json.await_args.args[0]["type"], "refused")


@unittest.skipUnless(LIVE, "LINKUP_LIVE=1 et LINKUP_API_KEY pour un vrai appel")
class Vrai(unittest.TestCase):
    def test_vrai_appel(self):
        r = linkup.search("Comment réinitialiser les paramètres de Google Chrome sous Windows 11 ?")
        self.assertTrue(r["ok"], r)
        self.assertTrue(r["sources"])


if __name__ == "__main__":
    unittest.main()
