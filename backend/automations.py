"""Automatismes importés : fournis par un support (service IT, proche) et non
nés d'une session.

Un automatisme importé ne contient que des actions de premier niveau, connues
de l'app : ouvrir un dossier, une page de Réglages, un lien https, copier des
modèles de documents, lancer un scan antivirus rapide, ou confier à Holo une
tâche à l'écran. Jamais de commande, de script ni de chemin libre : l'app ne
sait jouer que ces actions-là, avec des paramètres vérifiés ici puis sur
l'ordinateur.

Le support valide l'automatisme en l'important : la personne le lance ensuite
seule, en un clic.
"""

from __future__ import annotations

import base64
import binascii
import json
import re
import secrets
import time
from pathlib import Path
from urllib.parse import urlsplit

from .caremamory import KNOWN_FOLDERS, lessons_dir

FORMAT = 1
PLATFORMS = {"windows", "mac"}
SETTINGS_PAGES = {"printers", "default_apps", "updates", "antivirus", "wifi",
                  "bluetooth", "sound", "display"}
TEMPLATE_EXT = {".dotx", ".potx", ".xltx"}  # sans macros
MAX_ACTIONS = 8
MAX_FILES = 5
MAX_FILE_BYTES = 2_000_000
MAX_TEXT = 300
_BAD_NAME = re.compile(r'[\\/:*?"<>|\x00-\x1f]')


class Invalid(ValueError):
    """Automatisme refusé à l'import : le message dit pourquoi, en clair."""


def _text(v, what: str, limit: int = MAX_TEXT, required: bool = True) -> str:
    s = str(v or "").strip()
    if required and not s:
        raise Invalid(f"{what} manquant.")
    if len(s) > limit:
        raise Invalid(f"{what} trop long ({limit} caractères au plus).")
    return s


def _file_name(v) -> str:
    name = _text(v, "Nom de fichier", 120)
    if _BAD_NAME.search(name) or ".." in name or name.startswith("."):
        raise Invalid(f"Nom de fichier invalide : {name}")
    if not any(name.lower().endswith(e) for e in TEMPLATE_EXT):
        raise Invalid(f"Seuls les modèles sans macros sont acceptés ({', '.join(sorted(TEMPLATE_EXT))}) : {name}")
    return name


def _action(a, files: dict[str, bytes]) -> dict:
    if not isinstance(a, dict):
        raise Invalid("Chaque action doit être un objet.")
    do = str(a.get("do", "")).strip()
    if do == "open_folder":
        folder = str(a.get("folder", "")).strip().lower()
        if folder not in KNOWN_FOLDERS:
            raise Invalid(f"Dossier inconnu : {folder or '(vide)'}")
        sub = _text(a.get("subfolder"), "Sous-dossier", 120, required=False)
        if sub and (_BAD_NAME.search(sub) or ".." in sub or sub == "."):
            raise Invalid("Sous-dossier invalide : un nom, pas un chemin.")
        return {"do": do, "folder": folder, "subfolder": sub}
    if do == "open_settings":
        page = str(a.get("page", "")).strip().lower()
        if page not in SETTINGS_PAGES:
            raise Invalid(f"Page de Réglages inconnue : {page or '(vide)'}")
        return {"do": do, "page": page}
    if do == "open_url":
        url = _text(a.get("url"), "Lien", 500)
        u = urlsplit(url)
        if u.scheme != "https" or not u.hostname or u.username or u.password:
            raise Invalid("Lien refusé : seulement https://, sans identifiant.")
        return {"do": do, "url": url}
    if do == "install_templates":
        raw = a.get("files")
        if not isinstance(raw, list) or not raw or len(raw) > MAX_FILES:
            raise Invalid(f"install_templates : de 1 à {MAX_FILES} fichiers.")
        names = []
        for f in raw:
            if not isinstance(f, dict):
                raise Invalid("Fichier mal décrit.")
            name = _file_name(f.get("name"))
            try:
                data = base64.b64decode(str(f.get("data", "")), validate=True)
            except (binascii.Error, ValueError):
                raise Invalid(f"Contenu illisible : {name}") from None
            if not data or len(data) > MAX_FILE_BYTES:
                raise Invalid(f"Fichier vide ou trop gros : {name}")
            if not data.startswith(b"PK"):
                raise Invalid(f"Ce n'est pas un modèle Office : {name}")
            if name in files:
                raise Invalid(f"Fichier en double : {name}")
            files[name] = data
            names.append(name)
        return {"do": do, "app": "word", "files": names}
    if do == "antivirus_scan":
        return {"do": do}
    if do == "holo":
        goal = _text(a.get("goal"), "Objectif de Holo")
        steps = a.get("steps") or []
        if not isinstance(steps, list) or len(steps) > 12:
            raise Invalid("holo : 12 étapes au plus.")
        return {"do": do, "goal": goal,
                "steps": [_text(s, "Étape", MAX_TEXT) for s in steps if str(s or "").strip()]}
    raise Invalid(f"Action inconnue : {do or '(vide)'}. Aucune commande ni script n'est accepté.")


def validate(pack) -> tuple[dict, dict[str, bytes]]:
    """Vérifie un automatisme importé ; renvoie sa fiche et ses fichiers."""
    if not isinstance(pack, dict):
        raise Invalid("Un automatisme est un objet JSON.")
    if pack.get("papai") != FORMAT:
        raise Invalid(f"Format inconnu : « papai » doit valoir {FORMAT}.")
    platforms = pack.get("platforms") or sorted(PLATFORMS)
    if not isinstance(platforms, list) or not set(platforms) <= PLATFORMS or not platforms:
        raise Invalid("platforms : windows, mac, ou les deux.")
    raw = pack.get("actions")
    if not isinstance(raw, list) or not raw or len(raw) > MAX_ACTIONS:
        raise Invalid(f"De 1 à {MAX_ACTIONS} actions.")
    files: dict[str, bytes] = {}
    actions = [_action(a, files) for a in raw]
    holo = [i for i, a in enumerate(actions) if a["do"] == "holo"]
    if len(holo) > 1 or (holo and holo[0] != len(actions) - 1):
        raise Invalid("Une seule action holo, en dernier.")
    if any(a["do"] == "antivirus_scan" for a in actions) and platforms != ["windows"]:
        raise Invalid("antivirus_scan n'existe que sur Windows : platforms doit valoir [\"windows\"].")
    steps = pack.get("steps") or []
    if not isinstance(steps, list):
        raise Invalid("steps : une liste.")
    lesson = {
        "id": "imp-" + secrets.token_hex(6),
        "title": _text(pack.get("title"), "Titre", 120),
        "description": _text(pack.get("description"), "Description", 600, required=False),
        "publisher": _text(pack.get("publisher"), "Éditeur (qui fournit l'automatisme)", 80),
        "platforms": sorted(set(platforms)),
        "actions": actions,
        "steps": [{"instruction": _text(s.get("instruction") if isinstance(s, dict) else s, "Étape")}
                  for s in steps[:12]],
        "source": "import",
        "approved_by": "",
        "approved_at": 0.0,
    }
    first = actions[0]
    if len(actions) == 1 and first["do"] == "open_folder":
        lesson["shortcut"] = {"folder": first["folder"], "subfolder": first["subfolder"]}
    return lesson, files


def save(pack, by: str = "", folder: Path | None = None) -> dict:
    """Validation par le support = l'import. Rien n'est écrit si un point est refusé."""
    lesson, files = validate(pack)
    # Qui a validé : l'importateur s'il se nomme, sinon le détenteur de la clé, jamais l'éditeur.
    lesson["approved_by"] = _text(by, "Importé par", 80, required=False) or "import par la clé de la famille"
    lesson["approved_at"] = time.time()
    folder = (folder or lessons_dir()) / lesson["id"]
    folder.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        (folder / name).write_bytes(data)
    (folder / "lesson.json").write_text(json.dumps(lesson, ensure_ascii=False, indent=2), encoding="utf-8")
    return lesson


def load(lesson_id: str, folder: Path | None = None) -> dict | None:
    lid = str(lesson_id or "")
    if not re.fullmatch(r"imp-[0-9a-f]{12}", lid):
        return None
    try:
        return json.loads(((folder or lessons_dir()) / lid / "lesson.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def remove(lesson_id: str, folder: Path | None = None) -> bool:
    if load(lesson_id, folder) is None:
        return False
    folder = (folder or lessons_dir()) / lesson_id
    for f in folder.iterdir():
        f.unlink()
    folder.rmdir()
    return True


def holo_task(lesson: dict) -> tuple[str, list[str]] | None:
    """La tâche confiée à Holo et son plan, déjà validés par le support."""
    a = next((x for x in lesson.get("actions") or [] if x.get("do") == "holo"), None)
    if a is None:
        return None
    return a["goal"], list(a.get("steps") or []) or [a["goal"]]
