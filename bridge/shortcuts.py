"""Ce que la personne aidée ouvre souvent : ses dossiers, ses applications.

Tout est résolu sur la machine, à l'instant où on le demande. Aucun chemin n'est
écrit en dur : les dossiers passent par l'API des dossiers connus de Windows, les
applications par les raccourcis du menu Démarrer. Un PC d'une autre personne
donnera une autre liste, sans qu'une ligne change.

L'ordre d'affichage vient de l'usage réel, compté localement.
"""

from __future__ import annotations

import ctypes
import json
import os
from ctypes import wintypes
from pathlib import Path

USAGE_FILE = Path(__file__).resolve().parent.parent / "usage.json"

# Dossiers personnels, par identifiant officiel Windows. Jamais « C:\\Users\\… » :
# ce chemin casse sous un autre compte et quand OneDrive redirige le dossier.
KNOWN_FOLDERS = {
    "downloads": ("Téléchargements", "{374DE290-123F-4565-9164-39C4925E467B}"),
    "pictures": ("Images", "{33E28130-4E1E-4676-835A-98395C3BC3BB}"),
    "documents": ("Documents", "{FDD39AD0-238F-46AF-ADB4-6C85480369C7}"),
    "desktop": ("Bureau", "{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}"),
    "videos": ("Vidéos", "{18989B1D-99B5-455B-841C-AB7C74E4DDFC}"),
    "music": ("Musique", "{4BD8D571-6D19-48D3-BE97-422220080E43}"),
}

# Applications qu'on sait nommer simplement. Le reste du menu Démarrer est
# ignoré : une liste de soixante entrées n'aide personne.
APP_HINTS = [
    ("Internet", ("google chrome", "microsoft edge", "firefox", "opera")),
    ("Courrier", ("outlook", "thunderbird", "courrier", "mail")),
    ("Photos", ("photos",)),
    ("WhatsApp", ("whatsapp",)),
    ("Skype", ("skype",)),
    ("Zoom", ("zoom", "zoom workplace")),
    ("Word", ("word",)),
    ("Excel", ("excel",)),
    ("Calculatrice", ("calculatrice", "calculator")),
    ("Météo", ("météo", "meteo", "weather")),
]

# Un raccourci dont le nom contient l'un de ces mots n'est jamais l'application.
# Sans ce filtre, « Zoom » tombe sur « Uninstall Zoom Workplace » : une personne
# âgée qui cherche à appeler sa famille désinstallerait le logiciel.
EXCLUS = (
    "uninstall", "désinstall", "desinstall", "remove", "repair", "réparer",
    "readme", "lisez-moi", "help", "aide", "documentation", "licence", "license",
    "settings", "paramètres", "config", "manager", "updater", "mise à jour",
)

START_MENUS = (
    Path(os.environ.get("APPDATA", "")) / "Microsoft/Windows/Start Menu/Programs",
    Path(os.environ.get("PROGRAMDATA", "")) / "Microsoft/Windows/Start Menu/Programs",
)


# ------------------------------------------------------------------ dossiers


def known_folder(name: str) -> Path | None:
    """Demande à Windows où se trouve réellement ce dossier, maintenant."""
    entry = KNOWN_FOLDERS.get((name or "").strip().lower())
    if entry is None:
        return None

    class GUID(ctypes.Structure):
        _fields_ = [("a", wintypes.DWORD), ("b", wintypes.WORD),
                    ("c", wintypes.WORD), ("d", ctypes.c_byte * 8)]

    g = GUID()
    if ctypes.windll.ole32.CLSIDFromString(entry[1], ctypes.byref(g)) != 0:
        return None
    out = ctypes.c_wchar_p()
    if ctypes.windll.shell32.SHGetKnownFolderPath(
        ctypes.byref(g), 0, None, ctypes.byref(out)
    ) != 0:
        return None
    try:
        return Path(out.value)
    finally:
        ctypes.windll.ole32.CoTaskMemFree(out)


def folders() -> list[dict]:
    """Les dossiers personnels qui existent vraiment sur cette machine."""
    out = []
    for key, (label, _) in KNOWN_FOLDERS.items():
        p = known_folder(key)
        if p and p.is_dir():
            out.append({"kind": "folder", "key": key, "label": label})
    return out


# -------------------------------------------------------------- applications


def apps() -> list[dict]:
    """Les applications courantes présentes dans le menu Démarrer."""
    candidats: list[tuple[str, str]] = []
    for racine in START_MENUS:
        if not racine.is_dir():
            continue
        try:
            candidats += [(lnk.stem.lower(), str(lnk)) for lnk in racine.rglob("*.lnk")]
        except OSError:
            continue

    trouves: dict[str, tuple[int, str]] = {}
    for nom, chemin in candidats:
        if any(mot in nom for mot in EXCLUS):
            continue
        for label, motifs in APP_HINTS:
            for motif in motifs:
                # Un nom qui EST le motif vaut mieux qu'un nom qui le contient :
                # « Calculatrice » doit gagner contre « LibreOffice Calc ».
                if nom == motif:
                    score = 0
                elif nom.startswith(motif + " ") or nom.endswith(" " + motif):
                    score = 1
                elif f" {motif} " in f" {nom} ":
                    score = 2
                else:
                    continue
                if label not in trouves or score < trouves[label][0]:
                    trouves[label] = (score, chemin)
                break

    return [
        {"kind": "app", "key": label, "label": label, "path": trouves[label][1]}
        for label, _ in APP_HINTS
        if label in trouves
    ]


# --------------------------------------------------------------- lancement


def launch(item: dict) -> tuple[bool, str]:
    """Ouvre un dossier ou une application. Rien d'autre n'est exécutable.

    C'est la personne aidée qui clique : c'est son geste, sur sa machine.
    L'agent, lui, ne passe jamais par ici.
    """
    kind = item.get("kind")

    if kind == "folder":
        base = known_folder(item.get("key", ""))
        if base is None:
            return False, "Dossier inconnu."
        sub = (item.get("subfolder") or "").strip()
        if sub:
            if any(c in sub for c in '\\/:*?"<>|') or sub in (".", ".."):
                return False, "Nom de dossier invalide."
            base = base / sub
        if not base.is_dir():
            quoi = f"« {sub} »" if sub else "Ce dossier"
            return False, f"{quoi} n'existe pas (ou plus) sur cet ordinateur."
        cible = base

    elif kind == "app":
        cible = Path(item.get("path", ""))
        # Seulement un raccourci du menu Démarrer : pas un exécutable arbitraire.
        if cible.suffix.lower() != ".lnk" or not cible.is_file():
            return False, "Cette application n'est plus installée."
        if not any(
            str(cible).lower().startswith(str(r).lower()) for r in START_MENUS if str(r)
        ):
            return False, "Raccourci hors du menu Démarrer."

    else:
        return False, "Raccourci inconnu."

    try:
        os.startfile(str(cible))  # noqa: S606 — dossier ou raccourci du menu Démarrer
    except OSError as e:
        return False, str(e)

    bump(item)
    return True, str(cible)


# ------------------------------------------------------------------ usages


def _read_usage() -> dict:
    try:
        return json.loads(USAGE_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def bump(item: dict) -> None:
    """Compte une ouverture. C'est ce compteur qui trie l'écran d'accueil."""
    data = _read_usage()
    cle = f"{item.get('kind')}:{item.get('key')}:{item.get('subfolder', '')}"
    data[cle] = data.get(cle, 0) + 1
    try:
        USAGE_FILE.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass


def frequent(limit: int = 8) -> list[dict]:
    """Dossiers et applications, les plus ouverts d'abord.

    À usage égal, l'ordre de déclaration tranche : il place les dossiers
    personnels avant les applications, ce qui correspond à ce qu'on cherche
    le plus souvent sur le PC de quelqu'un.
    """
    data = _read_usage()
    items = folders() + apps()
    for rang, it in enumerate(items):
        cle = f"{it['kind']}:{it['key']}:"
        it["count"] = data.get(cle, 0)
        it["_rang"] = rang
    items.sort(key=lambda it: (-it["count"], it["_rang"]))
    return items[:limit]
