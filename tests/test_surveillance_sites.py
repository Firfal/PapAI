"""Surveillant CDP Windows : serveur HTTP local, sans navigateur ni pont."""

import importlib.util
import json
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("windows_site_check", ROOT / "apps/windows/papai/site_check.py")
site_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(site_check)


class SurveillanceSites(unittest.TestCase):
    def setUp(self):
        self.pages = []
        self.paths = []
        self.raw = None
        test = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                test.paths.append(self.path)
                body = test.raw if test.raw is not None else json.dumps(test.pages).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.received = []
        self.monitor = site_check.SiteMonitor(self.server.server_port, ["ameli.fr"], self.received.append)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.addCleanup(self.monitor.stop)

    def test_pages_seulement_et_debit_deux_secondes(self):
        self.pages = [
            {"type": "service_worker", "url": "https://evil.fr"},
            {"type": "page", "url": "about:blank"},
            {"type": "page", "url": "https://sous.ameli.fr"},
            {"type": "page", "url": "https://autre.fr/final"},
        ]
        with patch.object(site_check.time, "monotonic", return_value=10):
            self.monitor.poll()
            self.monitor.poll()
        self.assertEqual(self.received, ["https://autre.fr/final"])
        with patch.object(site_check.time, "monotonic", return_value=12):
            self.monitor.poll()
        self.assertEqual(len(self.received), 2)
        self.assertEqual(self.paths, ["/json/list"] * 3)

    def test_autorisation_exacte_et_actualisation(self):
        self.pages = [{"type": "page", "url": "https://autre.fr"}]
        self.monitor.update_sites(["ameli.fr"], ["autre.fr"])
        self.monitor.poll()
        self.assertEqual(self.received, [])
        self.pages[0]["url"] = "https://sous.autre.fr"
        self.monitor.poll()
        self.assertEqual(self.received, ["https://sous.autre.fr"])

    def test_toutes_les_pages_hors_site(self):
        self.pages = [{"type": "page", "url": "https://a.fr"},
                      {"type": "page", "url": "https://b.fr"}]
        self.monitor.poll()
        self.monitor.poll()
        self.assertEqual(self.received, ["https://a.fr", "https://b.fr"])

    def test_vide_et_ancien_serveur(self):
        self.monitor.poll()
        self.assertEqual(self.received, [])
        self.monitor.update_sites([])
        self.pages = [{"type": "page", "url": "https://evil.fr"}]
        previous = len(self.paths)
        self.monitor.poll()
        self.assertEqual(len(self.paths), previous)
        self.assertEqual(self.received, [])

    def test_reponses_invalides_et_erreur_reseau(self):
        for raw in (b"pas du JSON", b"{}", b"null", b'[null, {"type":"page"}]'):
            self.raw = raw
            self.monitor.poll()
        self.server.shutdown()
        self.server.server_close()
        self.monitor.poll()
        self.assertEqual(self.received, [])

    def test_demarrage_arret(self):
        event = threading.Event()
        self.monitor.callback = lambda url: event.set()
        self.pages = [{"type": "page", "url": "https://evil.fr"}]
        self.monitor.start()
        thread = self.monitor._thread
        self.monitor.start()
        self.assertIs(self.monitor._thread, thread)
        self.assertTrue(event.wait(2))
        self.monitor.stop()
        self.assertFalse(thread.is_alive())
        event.clear()
        self.monitor.poll()
        self.assertFalse(event.is_set())

    def test_port_invalide(self):
        for port in (0, 65536, "9222"):
            with self.assertRaises(ValueError):
                site_check.SiteMonitor(port, [], self.received.append)


if __name__ == "__main__":
    unittest.main(verbosity=1)
