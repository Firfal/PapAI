"""Relais réel HTTP + WS vers un faux Gladia, sans service externe.

HAI_API_KEY=stub-key PYTHONPATH=. .venv-mac/bin/python tests/test_gladia_live.py
"""
import json
import os
import socket
import subprocess
import tempfile
from pathlib import Path
import threading
import time
import unittest
from unittest.mock import patch

import uvicorn
from fastapi.testclient import TestClient

from backend import app as server, voice
from faux_gladia import FauxGladia


class LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fake = FauxGladia()
        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        cls.port = sock.getsockname()[1]
        cls.upstream = uvicorn.Server(uvicorn.Config(cls.fake.app, log_level="critical"))
        cls.thread = threading.Thread(target=cls.upstream.run, kwargs={"sockets": [sock]}, daemon=True)
        cls.thread.start()
        for _ in range(100):
            if cls.upstream.started:
                break
            time.sleep(.01)
        assert cls.upstream.started

    @classmethod
    def tearDownClass(cls):
        cls.upstream.should_exit = True
        cls.thread.join(timeout=5)

    def setUp(self):
        self.fake.mode = "normal"
        self.fake.audio.clear()
        self.fake.configs.clear()
        self.patches = [patch.dict(os.environ, {"GLADIA_API_KEY": "cle-factice"}),
                        patch.object(server, "spaces", server.space.Spaces("famille-test")),
                        patch.object(voice, "LIVE", f"http://127.0.0.1:{self.port}/v2/live"),
                        patch.object(voice, "_live_url_ok", lambda url: url.startswith(f"ws://127.0.0.1:{self.port}/"))]
        for p in self.patches:
            p.start()
            self.addCleanup(p.stop)
        self.client = TestClient(server.app)
        self.addCleanup(self.client.close)

    def connect(self, key="famille-test"):
        return self.client.websocket_connect(f"/k/{key}/transcribe/live")

    def test_live_partial_then_final(self):
        with self.connect() as ws:
            self.assertEqual(ws.receive_json(), {"type": "ready"})
            ws.send_bytes(b"\x01\x00" * 1600)
            first = ws.receive_json()
            self.assertEqual(first, {"type": "transcript", "id": "phrase-1", "text": "Bonjour", "final": False})
            ws.send_bytes(b"\x02\x00" * 1600)
            second = ws.receive_json()
            self.assertEqual(second["id"], first["id"])
            self.assertEqual(second["text"], "Bonjour les photos")
            ws.send_json({"type": "stop"})
            final = ws.receive_json()
            self.assertTrue(final["final"])
            self.assertEqual(ws.receive_json()["text"], "Merci.")
            self.assertEqual(ws.receive_json(), {"type": "done"})
        key, config = self.fake.configs[0]
        self.assertEqual(key, "cle-factice")
        self.assertEqual(config["sample_rate"], 16000)
        self.assertEqual(config["channels"], 1)
        self.assertEqual(config["bit_depth"], 16)
        self.assertEqual(config["language_config"]["languages"], ["fr"])
        self.assertTrue(config["messages_config"]["receive_partial_transcripts"])
        self.assertEqual(len(self.fake.audio), 2)
        self.assertNotIn("secret", json.dumps([first, second, final]))

    def test_wrong_key_never_opens_gladia(self):
        from starlette.websockets import WebSocketDisconnect
        with self.assertRaises(WebSocketDisconnect):
            with self.connect("mauvaise"):
                pass
        self.assertEqual(self.fake.configs, [])

    def test_other_space_key_opens_live(self):
        with tempfile.TemporaryDirectory() as folder:
            other = server.space.Space("autre-famille-test", Path(folder))
            with patch.dict(server.spaces._by_key, {other.key: other}), self.connect(other.key) as ws:
                self.assertEqual(ws.receive_json(), {"type": "ready"})
                ws.send_bytes(b"\x01\x00" * 1600)
                self.assertEqual(ws.receive_json()["text"], "Bonjour")
                ws.send_json({"type": "stop"})
                self.assertTrue(ws.receive_json()["final"])
                self.assertEqual(ws.receive_json()["text"], "Merci.")
                self.assertEqual(ws.receive_json(), {"type": "done"})

    def test_missing_key_falls_back(self):
        with patch.dict(os.environ, {"GLADIA_API_KEY": ""}), self.connect() as ws:
            self.assertEqual(ws.receive_json(), {"type": "fallback"})
        self.assertEqual(self.fake.configs, [])

    def test_init_error_falls_back_without_secret(self):
        self.fake.mode = "init_error"
        with self.connect() as ws:
            self.assertEqual(ws.receive_json(), {"type": "fallback"})

    def test_unreachable_service_falls_back(self):
        with patch.object(voice, "LIVE", "http://127.0.0.1:1/v2/live"), self.connect() as ws:
            self.assertEqual(ws.receive_json(), {"type": "fallback"})

    def test_prerecorded_still_works_after_live_failure(self):
        self.fake.mode = "init_error"
        with self.connect() as ws:
            self.assertEqual(ws.receive_json(), {"type": "fallback"})
        with patch.object(voice, "transcribe", return_value=(True, "Le texte final Gladia.")) as final:
            response = self.client.post("/k/famille-test/transcribe", content=b"RIFFaudio",
                                        headers={"Content-Type": "audio/wav"})
            self.assertEqual(response.json(), {"text": "Le texte final Gladia."})
            final.assert_called_once()

    def test_upstream_disconnect_and_error(self):
        for mode in ("disconnect", "error"):
            self.fake.mode = mode
            with self.subTest(mode=mode), self.connect() as ws:
                self.assertEqual(ws.receive_json()["type"], "ready")
                self.assertEqual(ws.receive_json(), {"type": "fallback"})

    def test_silent_upstream_timeout(self):
        self.fake.mode = "silent"
        with patch.object(voice, "LIVE_IDLE_SECONDS", .05), self.connect() as ws:
            self.assertEqual(ws.receive_json()["type"], "ready")
            self.assertEqual(ws.receive_json(), {"type": "fallback"})

    def test_final_timeout(self):
        self.fake.mode = "no_final"
        with patch.object(voice, "LIVE_DRAIN_SECONDS", .05), self.connect() as ws:
            self.assertEqual(ws.receive_json()["type"], "ready")
            ws.send_json({"type": "stop"})
            self.assertEqual(ws.receive_json(), {"type": "fallback"})

    def test_invalid_audio_and_control(self):
        for payload in (b"x", b"xx" * 16001, "{}", "x" * 129):
            with self.subTest(payload_size=len(payload)), self.connect() as ws:
                self.assertEqual(ws.receive_json()["type"], "ready")
                if isinstance(payload, bytes):
                    ws.send_bytes(payload)
                else:
                    ws.send_text(payload)
                self.assertEqual(ws.receive_json(), {"type": "fallback"})

    def test_total_audio_limit(self):
        with patch.object(voice, "LIVE_MAX_AUDIO", 4), self.connect() as ws:
            ws.receive_json()
            ws.send_bytes(b"xx" * 3)
            self.assertEqual(ws.receive_json(), {"type": "fallback"})

    def test_duration_limit(self):
        with patch.object(voice, "LIVE_SECONDS", .1), self.connect() as ws:
            self.assertEqual(ws.receive_json()["type"], "ready")
            self.assertEqual(ws.receive_json(), {"type": "fallback"})

    def test_disconnect_releases_slot(self):
        with self.connect() as ws:
            ws.receive_json()
        self.assertEqual(voice._live_connections, 0)

    def test_concurrency_limit(self):
        with self.connect() as a, self.connect() as b, self.connect() as c:
            self.assertEqual(a.receive_json()["type"], "ready")
            self.assertEqual(b.receive_json()["type"], "ready")
            self.assertEqual(c.receive_json(), {"type": "fallback"})

    def test_untrusted_upstream_url(self):
        with patch.object(voice, "_live_url_ok", lambda _: False), self.connect() as ws:
            self.assertEqual(ws.receive_json(), {"type": "fallback"})

    @unittest.skipUnless(__import__("sys").platform == "darwin", "URLSession vérifié sur macOS")
    def test_swift_client_against_relay(self):
        root = Path(__file__).resolve().parent.parent
        with tempfile.TemporaryDirectory() as tmp:
            binary = str(Path(tmp) / "gladia-live-test")
            subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library",
                            str(root / "apps/shared/GladiaLive.swift"),
                            str(root / "apps/mac/tests/gladia_live_test.swift"), "-o", binary], check=True)
            sock = socket.socket()
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
            backend = uvicorn.Server(uvicorn.Config(server.app, log_level="critical"))
            thread = threading.Thread(target=backend.run, kwargs={"sockets": [sock]}, daemon=True)
            thread.start()
            try:
                for _ in range(100):
                    if backend.started:
                        break
                    time.sleep(.01)
                assert backend.started
                for mode, upstream_mode in (("live", "normal"), ("fallback", "init_error"),
                                            ("fallback", "disconnect"), ("cancel", "normal")):
                    self.fake.mode = upstream_mode
                    with self.subTest(mode=mode, upstream=upstream_mode):
                        subprocess.run([binary, f"http://127.0.0.1:{port}/k/famille-test/transcribe", mode],
                                       check=True, timeout=20)
            finally:
                backend.should_exit = True
                thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
