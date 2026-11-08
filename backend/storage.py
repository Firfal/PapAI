"""Stockage des données : disque historique ou Firestore et Cloud Storage."""

from __future__ import annotations

import base64
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAX_DOCUMENT = 900 * 1024


def validate(key: str, *, prefix: bool = False) -> str:
    value = key[:-1] if prefix and key.endswith("/") else key
    if (not value or value.startswith("/") or "\\" in value
            or any(p in ("", ".", "..") for p in value.split("/"))
            or any(ord(c) < 32 for c in value)):
        raise ValueError("Clé de stockage invalide")
    return key


class Store:
    def read(self, key: str) -> bytes | None:
        raise NotImplementedError

    def write(self, key: str, data: bytes) -> None:
        raise NotImplementedError

    def delete(self, key: str) -> None:
        raise NotImplementedError

    def list(self, prefix: str) -> list[str]:
        raise NotImplementedError

    def read_json(self, key: str, default=None):
        data = self.read(key)
        return default if data is None else json.loads(data)

    def write_json(self, key: str, obj) -> None:
        self.write(key, json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8"))

    def delete_prefix(self, prefix: str) -> None:
        for key in self.list(prefix):
            self.delete(key)

    def copy_prefix(self, src: str, dst: str) -> None:
        validate(src, prefix=True)
        validate(dst, prefix=True)
        for key in self.list(src):
            data = self.read(key)
            if data is not None:
                self.write(dst + key[len(src):], data)


class LocalStore(Store):
    def __init__(self, root: Path = ROOT, data_dir: Path | None = None):
        self.root = Path(root)
        self.data_dir = Path(data_dir or os.environ.get("PAPAI_DATA_DIR") or self.root / "data")

    def _path(self, key: str) -> Path:
        validate(key)
        head, _, tail = key.partition("/")
        if head == "defaut":
            base, relative = self.root, tail
        elif head in ("spaces", "orgs"):
            base, relative = self.data_dir, key
        else:
            raise ValueError("Préfixe de stockage inconnu")
        path = base / relative
        if not path.resolve().is_relative_to(base.resolve()):
            raise ValueError("Chemin hors du stockage")
        return path

    def read(self, key):
        try:
            return self._path(key).read_bytes()
        except (FileNotFoundError, IsADirectoryError):
            return None

    def write(self, key, data):
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".stockage-")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
            os.replace(tmp, path)
        finally:
            Path(tmp).unlink(missing_ok=True)

    def delete(self, key):
        self._path(key).unlink(missing_ok=True)

    def list(self, prefix):
        validate(prefix, prefix=True)
        head = prefix.split("/", 1)[0]
        base = self._path(head)
        search = self._path(prefix.rstrip("/")) if prefix.endswith("/") else self._path(prefix).parent
        if not search.exists():
            return []
        return sorted(key for p in search.rglob("*") if p.is_file()
                      and not p.is_symlink()
                      for key in [head + "/" + p.relative_to(base).as_posix()]
                      if key.startswith(prefix))


class FirestoreStore(Store):
    def __init__(self, client=None, bucket=None, collection: str | None = None, *, filter_factory=None):
        if client is None:
            from google.cloud import firestore
            client = firestore.Client(project=os.environ.get("GOOGLE_CLOUD_PROJECT"))
        self.collection = client.collection(collection or os.environ.get("PAPAI_FIRESTORE_COLLECTION", "papai"))
        if bucket is None and os.environ.get("PAPAI_GCS_BUCKET"):
            from google.cloud import storage
            bucket = storage.Client(project=os.environ.get("GOOGLE_CLOUD_PROJECT")).bucket(os.environ["PAPAI_GCS_BUCKET"])
        self.bucket = bucket
        self.filter_factory = filter_factory

    def _doc(self, key):
        validate(key)
        return self.collection.document(base64.urlsafe_b64encode(key.encode()).decode())

    def read(self, key):
        snap = self._doc(key).get()
        if not snap.exists:
            return None
        data = snap.to_dict()
        if "gcs" in data:
            if self.bucket is None:
                raise ValueError("Le bucket Cloud Storage est requis pour ce fichier")
            return self.bucket.blob(data["gcs"]).download_as_bytes()
        return data["data"]

    def write(self, key, data):
        from datetime import datetime, timezone

        doc = self._doc(key)
        binary = Path(key).suffix.lower() not in (".json", "")
        oversized = len(data) > MAX_DOCUMENT
        if oversized and self.bucket is None:
            raise ValueError("Fichier trop volumineux pour Firestore (900 Ko) : configurez PAPAI_GCS_BUCKET")
        previous = doc.get()
        old = previous.to_dict() if previous.exists else {}
        if old.get("gcs") and self.bucket is None:
            raise ValueError("Le bucket Cloud Storage est requis pour ce fichier")
        value = {"key": key, "updated": datetime.now(timezone.utc)}
        if (binary or oversized) and self.bucket is not None:
            import uuid
            name = self.collection.id + "/" + key + "/" + uuid.uuid4().hex
            self.bucket.blob(name).upload_from_string(data)
            value["gcs"] = name
        else:
            value["data"] = data
        new_blob = value.get("gcs") if (binary or oversized) and self.bucket is not None else None
        try:
            doc.set(value)
        except Exception:
            if new_blob is not None:
                try:
                    self.bucket.blob(new_blob).delete()
                except Exception:
                    pass
            raise
        if old.get("gcs"):
            self.bucket.blob(old["gcs"]).delete()

    def delete(self, key):
        doc = self._doc(key)
        snap = doc.get()
        blob = snap.to_dict().get("gcs") if snap.exists else None
        if blob and self.bucket is None:
            raise ValueError("Le bucket Cloud Storage est requis pour ce fichier")
        doc.delete()
        if blob:
            self.bucket.blob(blob).delete()

    def list(self, prefix):
        validate(prefix, prefix=True)
        factory = self.filter_factory
        if factory is None:
            from google.cloud.firestore_v1.base_query import FieldFilter
            factory = FieldFilter
        query = self.collection.where(filter=factory("key", ">=", prefix)).where(filter=factory("key", "<", prefix + "\uf8ff"))
        return sorted(s.to_dict()["key"] for s in query.stream())


_store: Store | None = None


def reset(store: Store | None = None) -> None:
    global _store
    _store = store


def get() -> Store:
    global _store
    if _store is None:
        mode = os.environ.get("PAPAI_STORAGE", "local")
        if mode not in ("local", "firestore"):
            raise ValueError("PAPAI_STORAGE inconnu : " + mode)
        _store = LocalStore() if mode == "local" else FirestoreStore()
    return _store


def location(path: Path) -> tuple[Store, str]:
    """Conserve les chemins historiques, y compris les dossiers isolés des tests."""
    store = get()
    path = Path(path).absolute()
    data = Path(os.environ.get("PAPAI_DATA_DIR") or ROOT / "data")
    roots = []
    for module, attr, prefix in (("backend.space", "DATA_DIR", "spaces"),
                                  ("backend.orgs", "ORGS_DIR", "orgs")):
        mod = sys.modules.get(module)
        roots.append((Path(getattr(mod, attr, data / prefix)).absolute(), prefix))
    roots.append((ROOT, "defaut"))
    for base, prefix in roots:
        if path.is_relative_to(base):
            suffix = path.relative_to(base).as_posix()
            key = prefix if suffix == "." else prefix + "/" + suffix
            if isinstance(store, LocalStore):
                # Les points d'entrée patchés par les suites gardent leur destination.
                return LocalStore(root=base), "defaut" if suffix == "." else "defaut/" + suffix
            return store, validate(key)
    if isinstance(store, LocalStore):
        return LocalStore(root=path.parent), "defaut/" + path.name
    raise ValueError("Chemin sans clé de stockage logique")


def read(path: Path) -> bytes | None:
    store, key = location(path)
    return store.read(key)


def read_json(path: Path, default=None):
    store, key = location(path)
    return store.read_json(key, default)


def write(path: Path, data: bytes) -> None:
    store, key = location(path)
    store.write(key, data)


def write_json(path: Path, obj) -> None:
    store, key = location(path)
    store.write_json(key, obj)


def files(folder: Path, pattern: str) -> list[Path]:
    from pathlib import PurePosixPath

    store, prefix = location(folder)
    return [folder / key[len(prefix) + 1:] for key in store.list(prefix + "/")
            if PurePosixPath(key[len(prefix) + 1:]).match(pattern)
            and len(PurePosixPath(key[len(prefix) + 1:]).parts) == len(PurePosixPath(pattern).parts)]


def delete_folder(folder: Path) -> None:
    store, key = location(folder)
    if key in ("defaut", "spaces", "orgs"):
        raise ValueError("La racine du stockage ne peut pas être supprimée")
    store.delete_prefix(key + "/")
    if isinstance(store, LocalStore):
        import errno

        try:
            store._path(key).rmdir()
        except OSError as exc:
            if exc.errno not in (errno.ENOENT, errno.ENOTEMPTY, errno.EEXIST):
                raise
