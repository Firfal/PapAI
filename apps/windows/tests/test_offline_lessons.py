"""Automates hors ligne : python apps/windows/tests/test_offline_lessons.py."""

import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from papai import offline_lessons
from papai.model import Model

WIFI = {"id": "wifi", "title": "Se connecter au Wi-Fi", "actions": [{"do": "open_settings", "page": "wifi"}]}
DOSSIER = {"id": "photos", "title": "Mes photos", "shortcut": {"folder": "pictures"}}
HOLO = {"id": "adblock", "title": "Bloqueur", "actions": [{"do": "holo", "goal": "Installer uBlock"}]}
BASE = "http://127.0.0.1:9/k/famille-a"
MODELES = {"id": "word", "title": "Modèles", "actions": [{"do": "install_templates", "app": "word", "files": ["a.dotx"]}]}


class Offline(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        p = patch.dict(os.environ, {"PAPAI_HOME": self.tmp.name})
        p.start()
        self.addCleanup(p.stop)

    def test_garde_seulement_sans_holo_ni_fichier(self):
        offline_lessons.save([WIFI, HOLO, DOSSIER, MODELES, {"title": "sans id"}], BASE)
        self.assertEqual([x["id"] for x in offline_lessons.load(BASE)], ["wifi", "photos"])

    def test_fichier_absent_ou_abime(self):
        self.assertEqual(offline_lessons.load(BASE), [])
        offline_lessons._path().parent.mkdir(parents=True, exist_ok=True)
        offline_lessons._path().write_text("{pas du json", encoding="utf-8")
        self.assertEqual(offline_lessons.load(BASE), [])

    def fake(self, lessons=None):
        return SimpleNamespace(demo=False, http_base=BASE, _lock=threading.Lock(),
                               lessons=list(lessons or []), push=lambda: None)

    def test_sans_reseau_au_demarrage(self):
        offline_lessons.save([WIFI, HOLO], BASE)
        m = self.fake()
        with patch("urllib.request.urlopen", side_effect=OSError("hors ligne")):
            Model.refresh_lessons(m)
        self.assertEqual([x["id"] for x in m.lessons], ["wifi"])

    def test_coupure_garde_la_liste_complete(self):
        m = self.fake([WIFI, HOLO])
        with patch("urllib.request.urlopen", side_effect=OSError("hors ligne")):
            Model.refresh_lessons(m)
        self.assertEqual([x["id"] for x in m.lessons], ["wifi", "adblock"])

    def test_autre_espace_ne_voit_rien(self):
        offline_lessons.save([WIFI], BASE)
        self.assertEqual(offline_lessons.load("http://127.0.0.1:9/k/famille-b"), [])
        self.assertNotIn("famille-a", offline_lessons._path().read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
