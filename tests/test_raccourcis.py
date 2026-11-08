"""Cibles des tutoriels : règle partagée et approbation sans remplacement."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ.setdefault("HAI_API_KEY", "stub-key")
from backend import app, caremamory
from backend.sessions import Registry


class Raccourcis(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.session = Registry().create("Mes photos")
        self.session.frames["f"] = "aW1hZ2U="

    def test_regle_partagee(self):
        cases = json.loads(Path(__file__).with_name("subfolder_cases.json").read_text())
        for case in cases:
            with self.subTest(name=case["name"]):
                result = caremamory.valid_subfolder(case["name"])
                self.assertEqual(result is not None, case["valid"])
                if result is not None:
                    self.assertEqual(result, case["name"].strip())

    async def test_extraction(self):
        for sub in ("Séminaire 2025", "", "Facture.app", "{Photos}", "../Photos", None, 12):
            response = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(
                content=json.dumps({"folder": "pictures", "subfolder": sub})))])
            with patch.object(caremamory.client.chat.completions, "create", return_value=response):
                shortcut = await caremamory._extract_shortcut(self.session)
            self.assertEqual(shortcut, {"folder": "pictures", "subfolder": sub}
                             if sub in ("Séminaire 2025", "") else None)

    async def test_extraction_vide_et_erreur(self):
        self.session.frames.clear()
        with patch.object(caremamory.client.chat.completions, "create") as create:
            self.assertIsNone(await caremamory._extract_shortcut(self.session))
            create.assert_not_called()
        self.session.frames["f"] = "aW1hZ2U="
        with patch.object(caremamory.client.chat.completions, "create", side_effect=ValueError("indisponible")):
            self.assertIsNone(await caremamory._extract_shortcut(self.session))

    async def test_brouillon_plateforme_et_validation(self):
        for os_name, label, explorer in (("macOS", "macOS", "Finder"),
                                         ("windows", "Windows", "Explorateur de fichiers")):
            for sub in ("Séminaire 2025", "", "Facture.app", "../Photos"):
                with self.subTest(os=os_name, subfolder=sub):
                    responses = [SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(
                        content=json.dumps(data)))]) for data in (
                            {"title": "Mes photos", "steps": ["Ouvrez Images."]},
                            {"folder": "pictures", "subfolder": sub})]
                    with patch.object(caremamory.client.chat.completions, "create", side_effect=responses) as create:
                        lesson = await caremamory.draft_lesson(self.session, os_name)
                    self.assertEqual(lesson["os"], label)
                    self.assertEqual(lesson["shortcut"], {"folder": "pictures", "subfolder": sub}
                                     if sub in ("Séminaire 2025", "") else None)
                    self.assertIn(explorer, create.call_args.kwargs["messages"][0]["content"])

    def lesson(self, shortcut):
        return {"id": "test", "title": "Mes photos", "steps": [], "shortcut": shortcut}

    def test_sauvegarde_revalidee(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(caremamory, "lessons_dir", return_value=Path(directory)):
            for shortcut in ({"folder": "pictures", "subfolder": "Facture.app"},
                             {"folder": "ailleurs", "subfolder": ""}, None):
                saved = caremamory.approve_and_save(self.lesson(shortcut), self.session)
                self.assertIsNone(saved["shortcut"])
                self.assertIsNone(json.loads((Path(directory) / "test/lesson.json").read_text())["shortcut"])
            saved = caremamory.approve_and_save(self.lesson({"folder": "pictures", "subfolder": "Séminaire 2025"}), self.session)
            self.assertEqual(saved["shortcut"]["subfolder"], "Séminaire 2025")

    async def test_approbation_retrait_ou_valeur_ignoree(self):
        original = {"folder": "pictures", "subfolder": "Séminaire 2025"}
        for edit in ({"shortcut": None}, {"shortcut": {"folder": "desktop", "subfolder": "Autre"}},
                     {"shortcut": "Autre"}, {}):
            self.session.lesson = self.lesson(dict(original))
            ws = Mock(send_json=AsyncMock())
            with patch.object(app, "approve_and_save", side_effect=lambda lesson, session: lesson), \
                    patch.object(app.S(), "bridge", None):
                await app.handle_helper_msg(self.session, {"type": "approve_lesson", "lesson": edit}, ws)
            self.assertEqual(self.session.lesson["shortcut"], None if edit == {"shortcut": None} else original)
            self.assertEqual(ws.send_json.call_args.args[0]["type"], "lesson_saved")


if __name__ == "__main__":
    unittest.main()
