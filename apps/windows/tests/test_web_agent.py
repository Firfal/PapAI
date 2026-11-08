"""Agent navigateur sur Windows (WebAgentHost du Mac) : lancement, arrêt, protocole."""

import asyncio
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from papai import core  # noqa: E402
from papai.bridge import Bridge  # noqa: E402
from papai.model import Model  # noqa: E402
from papai.web_agent import WebAgentHost  # noqa: E402


class FakeProc:
    n = 100

    def __init__(self, args, **_):
        FakeProc.n += 1
        self.args, self.pid, self.code, self.terminated = args, FakeProc.n, None, False

    def poll(self):
        return self.code

    def terminate(self):
        self.terminated, self.code = True, 0

    kill = terminate

    def wait(self, timeout=None):
        return self.code


class Host:
    def __init__(self, listening_after=0, installed=True):
        self.dir = Path(tempfile.mkdtemp())
        self.holo = self.dir / "holo.exe"
        if installed:
            self.holo.write_text("")
        self.calls, self.changes, self.fronted, self.polls = [], [], [], 0
        self.listening_after = listening_after

        def popen(args, **kw):
            p = FakeProc(args, **kw)
            self.calls.append(p)
            return p

        def listening():
            self.polls += 1
            return self.polls > self.listening_after

        self.host = WebAgentHost(self.changes.append, popen=popen, listening=listening,
                                 executable=lambda: Path("C:/chrome.exe"), holo=lambda: self.holo,
                                 profile=lambda: self.dir / "Chrome", sleep=lambda s: None,
                                 front=self.fronted.append, spawn=lambda fn: None)


class WebAgentTests(unittest.TestCase):
    def test_surveillance_des_sites_valides(self):
        h = Host()
        pages = [{"type": "page", "url": "https://www.ameli.fr/compte"}]
        now = [100.0]
        h.host._pages, h.host._clock = (lambda: pages), (lambda: now[0])
        seen = []
        h.host.on_off_site = seen.append
        self.assertIsNone(h.host.check_sites(), "sans sites validés, rien n'est surveillé")
        h.host.update_sites(["ameli.fr"])
        self.assertIsNone(h.host.check_sites(), "page du plan : rien à signaler")
        pages.append({"type": "page", "url": "https://autre.fr/x"})
        self.assertEqual(h.host.check_sites(), "https://autre.fr/x")
        self.assertIsNone(h.host.check_sites(), "pas deux signalements en moins de 2 s")
        now[0] += 3
        h.host.update_sites(["ameli.fr"], ["autre.fr"])
        self.assertIsNone(h.host.check_sites(), "hôte autorisé par le support")
        self.assertEqual(seen, ["https://autre.fr/x"])

    def test_lancement_profil_neuf_puis_session(self):
        h = Host(listening_after=1)
        (h.dir / "Chrome").mkdir()
        (h.dir / "Chrome" / "Cookies").write_text("ancien")
        h.host._launch(Path("C:/chrome.exe"), h.host._generation)
        chrome, holo = h.calls
        self.assertIn("--remote-debugging-port=9222", chrome.args)
        self.assertIn(f"--user-data-dir={h.dir / 'Chrome'}", chrome.args)
        self.assertFalse((h.dir / "Chrome" / "Cookies").exists(), "profil effacé avant l'assistance")
        self.assertEqual(holo.args[1:4], ["local", "browser", "--session-id"])
        self.assertEqual(h.changes, [holo.args[4]])
        h.host.bring_to_front()
        self.assertEqual(h.fronted, [chrome.pid])

    def test_port_deja_pris_on_ne_se_branche_pas(self):
        h = Host(listening_after=0)
        h.host._launch(Path("C:/chrome.exe"), h.host._generation)
        self.assertEqual(h.calls, [])
        self.assertEqual(h.changes, [])

    def test_arret_ferme_tout_et_prevenir_le_serveur(self):
        h = Host(listening_after=1)
        h.host._launch(Path("C:/chrome.exe"), h.host._generation)
        chrome, holo = h.calls
        h.host.stop_local()
        self.assertTrue(holo.terminated)
        self.assertEqual(h.changes[-1], None)
        self.assertEqual(h.calls[-1].args[1:], ["local", "stop"])
        h.host.stop_local()
        self.assertEqual(len(h.calls), 3, "deuxième arrêt sans effet")

    def test_arret_pendant_le_lancement(self):
        h = Host(listening_after=1)
        gen = h.host._generation
        h.host.starting = True
        h.host.stop_local(notify_server=False)
        h.host._launch(Path("C:/chrome.exe"), gen)
        self.assertTrue(all(p.terminated for p in h.calls if "local" not in p.args))
        self.assertEqual(h.changes, [])

    def test_profil_verrouille_on_ne_lance_rien(self):
        from unittest.mock import patch
        h = Host(listening_after=1)
        (h.dir / "Chrome").mkdir()
        with patch("papai.web_agent.wipe_profile", lambda p=None: None):
            h.host._launch(Path("C:/chrome.exe"), h.host._generation)
        self.assertEqual(h.calls, [], "jamais de lancement sur un ancien profil")

    def test_holo_qui_tombe_ferme_chrome(self):
        h = Host(listening_after=1)
        orig = h.host._popen

        def popen(args, **kw):
            p = orig(args, **kw)
            if "browser" in args:
                p.code = 1
            return p
        h.host._popen = popen
        h.host._spawn = lambda fn: fn()
        h.host._launch(Path("C:/chrome.exe"), h.host._generation)
        self.assertTrue(h.calls[0].terminated, "Chrome PapAI fermé")
        self.assertIsNone(h.host.chrome)
        self.assertEqual(h.changes, [])

    def test_nettoyage_n_efface_pas_le_lancement_suivant(self):
        h = Host(listening_after=1)
        finishes = []
        h.host._spawn = finishes.append
        h.host._launch(Path("C:/chrome.exe"), h.host._generation)
        h.host.stop_local()
        h.host.start()
        (h.dir / "Chrome").mkdir(exist_ok=True)
        (h.dir / "Chrome" / "nouveau").write_text("x")
        finishes[0]()
        self.assertTrue((h.dir / "Chrome" / "nouveau").exists())

    def test_disponible_seulement_si_holo_installe(self):
        self.assertTrue(Host().host.available())
        self.assertFalse(Host(installed=False).host.available())


class FakeHost:
    def __init__(self):
        self.events = []
        self.on_change = None

    def available(self):
        return True

    def start(self):
        self.events.append("start")

    def update_sites(self, sites, hosts=()):
        self.events.append(("sites", list(sites), list(hosts)))

    def stop_local(self, notify_server=True):
        self.events.append(("stop", notify_server))

    def bring_to_front(self):
        self.events.append("front")


class ModelWebTests(unittest.TestCase):
    def model(self):
        web = FakeHost()
        m = Model(demo="home", web_host=web)
        m.prefs = {}
        sent = []
        m._send = sent.append
        m.ask_help("Réserver un train")
        return m, web, sent

    def test_messages_du_serveur(self):
        m, web, sent = self.model()
        m._handle({"type": "web_agent_start"})
        self.assertEqual(web.events, [("sites", [], []), "start"])
        m._handle({"type": "status", "state": "active", "where": "web", "plan": ["a"]})
        self.assertEqual(m.snapshot()["sessionWhere"], "web")
        self.assertEqual(web.events[-1], "front")
        m._handle({"type": "status", "state": "active", "where": "web", "plan": ["a"]})
        self.assertEqual(web.events.count("front"), 1, "Chrome PapAI passe devant une seule fois")
        m._handle({"type": "web_agent_stop"})
        self.assertEqual(web.events[-1], ("stop", False))
        m._handle({"type": "status", "state": "done", "where": "web"})
        self.assertEqual(web.events[-1], ("stop", True))
        m.web.on_change("abc")
        m.web.on_change(None)

    def test_chrome_repasse_devant_a_chaque_passage_web(self):
        m, web, _ = self.model()
        for where in ("web", "desktop", "web"):
            m._handle({"type": "status", "state": "active", "where": where, "plan": ["a"]})
        self.assertEqual(web.events.count("front"), 2)

    def test_raccourci_pendant_un_automate_garde_arreter(self):
        m, _, _ = self.model()
        m.automation_running = "Automate"
        m.show_run_status("c", "En cours…", running=True)
        m.show_run_status("a", "C'est ouvert")
        self.assertEqual(m.run_status, {"id": "c", "text": "En cours…", "running": True})

    def test_arreter_et_alerte_ferment_chrome(self):
        m, web, _ = self.model()
        m.stop()
        self.assertIn(("stop", False), web.events)
        m._handle({"type": "web_agent_start"})
        self.assertNotIn("start", web.events, "après Arrêter, rien ne se relance")
        m2, web2, _ = self.model()
        m2._handle({"type": "alert", "level": "danger", "title": "x"})
        self.assertIn(("stop", True), web2.events)
        m2._connection(False)
        self.assertIn(("stop", False), web2.events)

    def test_sites_du_plan_transmis(self):
        m, web, _ = self.model()
        m._handle({"type": "web_agent_start", "sites": ["ameli.fr"], "hosts": []})
        m._handle({"type": "web_sites", "sites": ["ameli.fr"], "hosts": ["connexion.exemple.fr"]})
        self.assertEqual(web.events[:3], [("sites", ["ameli.fr"], []), "start",
                                          ("sites", ["ameli.fr"], ["connexion.exemple.fr"])])

    def test_web_off_site_envoye(self):
        web = FakeHost()
        m = Model(demo="home", web_host=web)
        sent = []
        m.bridge = type("B", (), {"send": lambda self, p: sent.append(p)})()
        m.web.on_off_site("https://autre.fr/x")
        self.assertEqual(sent, [{"type": "web_off_site", "url": "https://autre.fr/x"}])

    def test_session_id_envoye_au_serveur(self):
        web = FakeHost()
        m = Model(demo="home", web_host=web)
        sent = []
        m.bridge = type("B", (), {"send": lambda self, p: sent.append(p)})()
        m.web.on_change("abc")
        m.web.on_change(None)
        self.assertEqual(sent, [{"type": "web_agent", "session_id": "abc"},
                                {"type": "web_agent", "session_id": None}])

    def test_helpers_online(self):
        m, _, _ = self.model()
        m._handle({"type": "helpers", "helpers": [{"id": "1", "name": "Marc", "online": True}]})
        self.assertTrue(m.snapshot()["helpers"][0]["online"])


class BridgeHelloTests(unittest.TestCase):
    def test_hello_annonce_l_agent_navigateur(self):
        sent = []

        class WS:
            async def send(self, raw):
                sent.append(json.loads(raw))
                raise ConnectionError

            async def __aenter__(self):
                return self

            async def __aexit__(self, *a):
                return False

        import websockets
        b = Bridge("ws://x", core.StopGate(), object, lambda m: None, lambda ok: None, lambda s: None)
        b.web_agent_available = lambda: True
        orig = websockets.connect
        websockets.connect = lambda *a, **k: WS()

        async def go():
            t = asyncio.create_task(b._run())
            await asyncio.sleep(0.05)
            t.cancel()
        try:
            asyncio.run(go())
        except BaseException:  # noqa: BLE001
            pass
        finally:
            websockets.connect = orig
        self.assertTrue(sent)
        self.assertEqual(sent[0]["type"], "hello")
        self.assertIs(sent[0]["web_agent_available"], True)


if __name__ == "__main__":
    unittest.main()
