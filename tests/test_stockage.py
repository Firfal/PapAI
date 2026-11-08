"""Contrat disque/Firestore, migration et redémarrage, sans accès Google Cloud."""

from __future__ import annotations

import contextlib
import copy
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from backend import storage
from scripts.migrer_stockage import main as migrer


class Filtre:
    def __init__(self, field, op, value):
        self.field_path, self.op_string, self.value = field, op, value


class Document:
    def __init__(self, collection, ident):
        self.collection, self.ident = collection, ident

    def get(self):
        value = copy.deepcopy(self.collection.values.get(self.ident))
        return SimpleNamespace(exists=value is not None, to_dict=lambda: value)

    def set(self, value):
        self.collection.values[self.ident] = copy.deepcopy(value)
        self.collection.writes += 1

    def delete(self):
        self.collection.values.pop(self.ident, None)


class Requete:
    def __init__(self, collection, filters=()):
        self.collection, self.filters = collection, filters

    def where(self, *, filter):
        return Requete(self.collection, (*self.filters, filter))

    def stream(self):
        for ident, value in self.collection.values.items():
            if all((value[f.field_path] >= f.value if f.op_string == ">=" else value[f.field_path] < f.value)
                   for f in self.filters):
                yield Document(self.collection, ident).get()


class Collection(Requete):
    def __init__(self, ident):
        super().__init__(self)
        self.id, self.values, self.writes = ident, {}, 0

    def document(self, ident):
        assert "/" not in ident
        return Document(self, ident)


class Client:
    def __init__(self):
        self.collections = {}

    def collection(self, ident):
        return self.collections.setdefault(ident, Collection(ident))


class Blob:
    def __init__(self, bucket, name):
        self.bucket, self.name = bucket, name

    def upload_from_string(self, data):
        self.bucket.values[self.name] = data

    def download_as_bytes(self):
        return self.bucket.values[self.name]

    def delete(self):
        self.bucket.values.pop(self.name, None)


class Bucket:
    def __init__(self):
        self.values = {}

    def blob(self, name):
        return Blob(self, name)


def distant(bucket=None, client=None):
    return storage.FirestoreStore(client=client or Client(), bucket=bucket, filter_factory=Filtre)


class Contrat:
    def test_lecture_ecriture_json(self):
        self.assertIsNone(self.store.read("defaut/absent.json"))
        self.assertEqual(self.store.read_json("defaut/absent.json", []), [])
        self.store.write("defaut/vide", b"")
        self.assertEqual(self.store.read("defaut/vide"), b"")
        self.store.write_json("spaces/a/family.json", {"prénom": "Zoé"})
        self.assertEqual(self.store.read_json("spaces/a/family.json"), {"prénom": "Zoé"})
        self.store.write("spaces/a/family.json", b"invalide")
        with self.assertRaises(ValueError):
            self.store.read_json("spaces/a/family.json")

    def test_prefixes_copie_suppression(self):
        self.assertEqual(self.store.list("spaces/"), [])
        for key in ("spaces/b/z", "spaces/a/z", "spaces/ab/z", "orgs/o/z"):
            self.store.write(key, b"texte")
        self.assertEqual(self.store.list("spaces/a/"), ["spaces/a/z"])
        self.assertEqual(self.store.list("spaces/"), ["spaces/a/z", "spaces/ab/z", "spaces/b/z"])
        self.assertEqual(self.store.list("spaces/a"), ["spaces/a/z", "spaces/ab/z"])
        self.store.copy_prefix("spaces/a/", "spaces/c/")
        self.assertEqual(self.store.read("spaces/c/z"), b"texte")
        self.store.delete_prefix("spaces/a/")
        self.assertIsNone(self.store.read("spaces/a/z"))
        self.assertEqual(self.store.read("spaces/ab/z"), b"texte")
        self.store.delete("spaces/c/z")
        self.store.delete("spaces/c/z")
        self.store.delete_prefix("spaces/inexistant/")

    def test_cles_invalides(self):
        for key in ("", "/ab", "../ab", "spaces/../ab", "spaces//ab", "spaces/./ab", "spaces/ab\\cd", "spaces/ab\x00"):
            for operation in (self.store.read, self.store.delete, self.store.list,
                              lambda k: self.store.write(k, b""), self.store.delete_prefix):
                with self.subTest(key=key, operation=operation), self.assertRaises(ValueError):
                    operation(key)


class Disque(Contrat, unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.store = storage.LocalStore(self.root, self.root / "donnees")

    def test_disposition_et_liens(self):
        self.store.write("defaut/family.json", b"{}")
        self.store.write("spaces/a/space.json", b"{}")
        self.assertTrue((self.root / "family.json").is_file())
        self.assertTrue((self.root / "donnees/spaces/a/space.json").is_file())
        (self.root / "sortie").symlink_to(self.root.parent, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.store.read("defaut/sortie/interdit")
        self.assertFalse(list(self.root.rglob(".stockage-*")))


class Firestore(Contrat, unittest.TestCase):
    def setUp(self):
        self.bucket = Bucket()
        self.store = distant(self.bucket)

    def test_images_et_remplacement(self):
        key = "defaut/lessons/a/step1.png"
        data = b"x" * (storage.MAX_DOCUMENT + 1)
        self.store.write(key, data)
        self.assertEqual(self.store.read(key), data)
        self.assertEqual(len(self.bucket.values), 1)
        self.store.write(key, b"petite image")
        self.assertEqual(len(self.bucket.values), 1)
        self.assertEqual(self.store.read(key), b"petite image")
        self.store.delete_prefix("defaut/lessons/a/")
        self.assertFalse(self.bucket.values)
        self.assertIsNone(self.store.read(key))

    def test_limite_sans_bucket(self):
        store = distant()
        key = "spaces/a/lessons/b/step.png"
        store.write(key, b"x" * storage.MAX_DOCUMENT)
        with self.assertRaisesRegex(ValueError, "900 Ko"):
            store.write(key, b"x" * (storage.MAX_DOCUMENT + 1))
        self.assertEqual(len(store.read(key)), storage.MAX_DOCUMENT)
        with self.assertRaisesRegex(ValueError, "900 Ko"):
            store.write("spaces/a/tickets.json", b"x" * (storage.MAX_DOCUMENT + 1))

    def test_json_volumineux_puis_petit(self):
        key = "spaces/a/tickets.json"
        tickets = [{"notes": "é" * storage.MAX_DOCUMENT}]
        self.store.write_json(key, tickets)
        data = self.store.read(key)
        self.assertGreater(len(data), storage.MAX_DOCUMENT)
        self.assertEqual(self.store.read_json(key), tickets)
        document = self.store._doc(key).get().to_dict()
        self.assertNotIn("data", document)
        blob = document["gcs"]
        self.assertEqual(self.bucket.values[blob], data)
        self.store.write_json(key, [])
        self.assertEqual(self.store.read_json(key), [])
        document = self.store._doc(key).get().to_dict()
        self.assertNotIn("gcs", document)
        self.assertEqual(json.loads(document["data"]), [])
        self.assertNotIn(blob, self.bucket.values)

    def test_erreurs_non_masquees(self):
        with patch.object(self.store.collection, "document", side_effect=RuntimeError("indisponible")):
            with self.assertRaisesRegex(RuntimeError, "indisponible"):
                self.store.read("defaut/family.json")

    def test_suppression_document_refusee_preserve_image(self):
        key = "spaces/a/lessons/b/step.png"
        self.store.write(key, b"image")
        blob = self.store._doc(key).get().to_dict()["gcs"]
        with patch.object(Document, "delete", side_effect=RuntimeError("suppression refusée")):
            with self.assertRaisesRegex(RuntimeError, "suppression refusée"):
                self.store.delete(key)
        self.assertEqual(self.bucket.values[blob], b"image")
        self.assertEqual(self.store.read(key), b"image")


class Integration(unittest.TestCase):
    def tearDown(self):
        storage.reset()

    def test_selection(self):
        storage.reset()
        with patch.dict(os.environ, {"PAPAI_STORAGE": "inconnu"}):
            with self.assertRaisesRegex(ValueError, "inconnu"):
                storage.get()
        with patch.dict(os.environ, {"PAPAI_STORAGE": "local"}):
            storage.reset()
            self.assertIs(storage.get(), storage.get())
            self.assertIsInstance(storage.get(), storage.LocalStore)

    def test_images_locales_cloisonnees(self):
        from backend.app import _serve_lesson_file

        storage.reset(storage.LocalStore())
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lessons = root / "lessons"
            (lessons / "a").mkdir(parents=True)
            (root / "secret").write_bytes(b"confidentiel")
            (lessons / "a/image.png").symlink_to(root / "secret")
            with patch("backend.app.lessons_dir", return_value=lessons):
                self.assertEqual(_serve_lesson_file("a", "image.png").status_code, 404)
                self.assertEqual(_serve_lesson_file("a", "absent.png").status_code, 404)

    def test_migration(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = storage.LocalStore(root, root / "donnees")
            keys = ("defaut/family.json", "defaut/tickets.json", "defaut/lessons/a/step.png",
                    "spaces/a/space.json", "orgs/a/org.json", "orgs/a/tickets_seq")
            for key in keys:
                source.write(key, b"contenu confidentiel")
            target = distant(Bucket())
            args = ["--root", str(root), "--data-dir", str(root / "donnees")]
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                migrer(args + ["--dry-run"], target=target)
            self.assertIn("Total : 6", output.getvalue())
            self.assertNotIn("contenu confidentiel", output.getvalue())
            self.assertFalse(target.collection.values)
            with contextlib.redirect_stdout(io.StringIO()):
                migrer(args, target=target)
                writes = target.collection.writes
                migrer(args, target=target)
            self.assertEqual(target.collection.writes, writes)
            for key in keys:
                self.assertEqual(target.read(key), source.read(key))
            target.write("defaut/family.json", b"version plus recente")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                migrer(args, target=target)
            self.assertEqual(target.read("defaut/family.json"), b"version plus recente")
            self.assertIn("defaut/family.json : 1 fichier(s) ; 1 déjà présent, ignoré(s)", output.getvalue())
            with contextlib.redirect_stdout(io.StringIO()):
                migrer(args + ["--ecraser"], target=target)
            self.assertEqual(target.read("defaut/family.json"), source.read("defaut/family.json"))
            with patch.object(target, "write", side_effect=RuntimeError("écriture refusée")), \
                    contextlib.redirect_stdout(io.StringIO()):
                source.write("defaut/family.json", b"nouveau")
                with self.assertRaisesRegex(RuntimeError, "écriture refusée"):
                    migrer(args + ["--ecraser"], target=target)
            self.assertEqual(source.read("defaut/family.json"), b"nouveau")
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(sum(migrer(["--root", tmp, "--dry-run"]).values()), 0)

    def test_redemarrage(self):
        from backend import automations, caremamory, orgs, space

        client, bucket = Client(), Bucket()
        storage.reset(distant(bucket, client))
        registry, organisations = space.Spaces("cle-defaut-test"), orgs.Orgs()
        organisation = organisations.create("Support informatique")
        sp = registry.create(org=organisation.id, label="Accueil")
        sp.family.set_senior("Zoé")
        sp.family.add_helper("Claire", "")
        ticket = sp.tickets.open("Ouvrir mes photos", "utilisateur", number=organisation.next_ticket())
        pack = json.loads((storage.ROOT / "automations/google-moteur-de-recherche.papai").read_text())
        lesson = automations.save(pack, folder=organisation.lessons_dir)
        organisation.copy_automations(sp.lessons_dir)
        storage.write(sp.lessons_dir / lesson["id"] / "step.png", b"image")
        session = SimpleNamespace(frames={"capture": "aW1hZ2U="}, log=lambda *a, **kw: None)
        draft = {"id": "memoire-test", "title": "Photos", "steps": [{"frame": "capture"}, {}]}
        with patch.object(caremamory, "lessons_dir", return_value=sp.lessons_dir):
            caremamory.approve_and_save(draft, session)
        storage.reset(distant(bucket, client))
        restarted, reorgs = space.Spaces("cle-defaut-test"), orgs.Orgs()
        sp2, org2 = restarted.get(sp.key), reorgs.get(organisation.id)
        self.assertEqual(sp2.family.senior, "Zoé")
        self.assertEqual(sp2.family.helpers[0]["name"], "Claire")
        self.assertEqual(sp2.org, organisation.id)
        self.assertEqual(sp2.tickets.get(ticket["id"])["number"], 1)
        self.assertEqual(org2.next_ticket(), 2)
        self.assertEqual(org2.automations()[0]["id"], lesson["id"])
        self.assertEqual(automations.load(lesson["id"], sp2.lessons_dir)["title"], lesson["title"])
        with patch.object(caremamory, "lessons_dir", return_value=sp2.lessons_dir):
            self.assertEqual({x["id"] for x in caremamory.list_lessons()}, {lesson["id"], "memoire-test"})
        self.assertEqual(storage.read(sp2.lessons_dir / "memoire-test/step-1.png"), b"image")
        self.assertEqual(storage.read_json(sp2.lessons_dir / "memoire-test/lesson.json")["steps"][1]["image"], "")
        from backend.app import _serve_lesson_file
        with patch("backend.app.lessons_dir", return_value=sp2.lessons_dir):
            self.assertEqual(_serve_lesson_file(lesson["id"], "step.png").body, b"image")
            for lid, name in (("..", "family.json"), (lesson["id"], "../space.json"), (lesson["id"], "absent.png")):
                self.assertEqual(_serve_lesson_file(lid, name).status_code, 404)
        self.assertTrue(automations.remove(lesson["id"], sp2.lessons_dir))
        self.assertFalse(automations.remove(lesson["id"], sp2.lessons_dir))
        storage.delete_folder(sp2.lessons_dir / "memoire-test")
        self.assertEqual(storage.files(sp2.lessons_dir, "*/lesson.json"), [])


if __name__ == "__main__":
    os.environ.setdefault("HAI_API_KEY", "stub-key")
    unittest.main(verbosity=2)
