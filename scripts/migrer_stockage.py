"""Copie les clés absentes vers le stockage durable, sans effacer la source.

Les clés déjà présentes sont ignorées, même si leur contenu diffère.
L'option --ecraser remplace explicitement la cible par la copie disque.
"""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from backend import storage


def migrate(source: storage.LocalStore, target: storage.Store | None, *, dry_run=False, ecraser=False) -> Counter:
    keys = [key for key in ("defaut/family.json", "defaut/tickets.json") if source.read(key) is not None]
    for prefix in ("defaut/lessons/", "spaces/", "orgs/"):
        keys.extend(source.list(prefix))
    counts = Counter()
    ignored = Counter()
    for key in sorted(keys):
        prefix = "/".join(key.split("/")[:2]) if key.startswith("defaut/") else key.split("/")[0]
        counts[prefix] += 1
        if dry_run:
            print(key)
        else:
            data = source.read(key)
            if data is None:
                raise ValueError("Un fichier source a disparu pendant la migration")
            existing = target.read(key)
            if existing is not None and not ecraser:
                ignored[prefix] += 1
            elif existing != data:
                target.write(key, data)
    for prefix, count in sorted(counts.items()):
        print(f"{prefix} : {count} fichier(s) ; {ignored[prefix]} déjà présent, ignoré(s)")
    print(f"Total : {sum(counts.values())} fichier(s) ; " + ("simulation, aucune écriture" if dry_run else "copie terminée"))
    return counts


def main(argv=None, *, target=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Lister sans écrire ni contacter Google Cloud")
    parser.add_argument("--ecraser", action="store_true", help="Remplacer les clés existantes par la copie disque (par défaut : ignorer)")
    parser.add_argument("--root", type=Path, default=storage.ROOT, help="Racine du dépôt source")
    parser.add_argument("--data-dir", type=Path, help="Dossier source des espaces et organisations")
    args = parser.parse_args(argv)
    source = storage.LocalStore(args.root, args.data_dir)
    if not args.dry_run and target is None:
        import os
        mode = os.environ.get("PAPAI_STORAGE", "firestore")
        if mode != "firestore":
            raise ValueError("La cible de migration doit être Firestore")
        target = storage.FirestoreStore()
    return migrate(source, target, dry_run=args.dry_run, ecraser=args.ecraser)


if __name__ == "__main__":
    main()
