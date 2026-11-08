"""Réponse documentaire reçue par le modèle Windows, sans poste Windows."""

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from papai.model import Model


class LinkupAnswer(unittest.TestCase):
    def test_answer_sources_are_data(self):
        model = SimpleNamespace(answer=None, answer_sources=[], push=Mock())
        Model._handle(model, {"type": "linkup_answer", "content": "Réponse validée", "sources": [
            {"name": "<b>Documentation</b>", "url": "https://example.org"},
            {"url": "javascript:alert(1)"}, None]})
        self.assertEqual(model.answer, "Réponse validée")
        self.assertEqual(model.answer_sources, [{"name": "<b>Documentation</b>", "url": "https://example.org"}])

    def test_empty_sources_and_old_answer(self):
        model = SimpleNamespace(answer=None, answer_sources=[{"url": "https://example.org"}], push=Mock())
        Model._handle(model, {"type": "linkup_answer", "content": "Réponse", "sources": []})
        self.assertEqual(model.answer_sources, [])
        Model._handle(model, {"type": "answer", "content": "Terminé"})
        self.assertEqual(model.answer, "Terminé")
        self.assertEqual(model.answer_sources, [])


if __name__ == "__main__":
    unittest.main()
