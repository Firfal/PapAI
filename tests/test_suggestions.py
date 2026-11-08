import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from backend.suggest import suggerer


class TestSuggestions(unittest.TestCase):
    def test_accents_and_plural(self):
        results = suggerer(
            "Je veux retrouver mes photos de l’été",
            [{"id": "photo", "title": "Retrouver une photo de l'ete"}],
        )
        self.assertEqual(results, [{"id": "photo", "title": "Retrouver une photo de l'ete"}])

    def test_no_common_words(self):
        self.assertEqual(
            suggerer("Configurer une imprimante", [{"id": "photos", "title": "Ranger des photos"}]),
            [],
        )

    def test_limit_defaults_to_two(self):
        automates = [
            {"id": "c", "title": "Imprimer un document C"},
            {"id": "a", "title": "Imprimer un document A"},
            {"id": "b", "title": "Imprimer un document B"},
        ]
        self.assertEqual(
            [item["id"] for item in suggerer("Imprimer un document", automates)],
            ["a", "b"],
        )

    def test_title_scores_double_and_ties_use_title(self):
        automates = [
            {"id": "beta", "title": "Beta facture", "description": "photo"},
            {"id": "top", "title": "Zeta photo facture"},
            {"id": "alpha", "title": "Alpha photo", "description": "facture"},
        ]
        self.assertEqual(
            [item["id"] for item in suggerer("photo facture", automates, limite=3)],
            ["top", "alpha", "beta"],
        )

    def test_duplicate_ids_are_returned_once(self):
        automates = [
            {"id": "same", "title": "Imprimer la facture"},
            {"id": "same", "title": "Imprimer le document"},
        ]
        self.assertEqual(
            suggerer("imprimer facture", automates),
            [{"id": "same", "title": "Imprimer la facture"}],
        )


if __name__ == "__main__":
    unittest.main()
