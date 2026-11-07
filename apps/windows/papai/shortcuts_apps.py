"""Les applications de la personne, trouvées dans le menu Démarrer.

L'app Mac affiche six applications par identifiant de paquet (Mail, Photos,
Safari…). Windows n'a pas d'équivalent stable, alors on cherche dans les
raccourcis du menu Démarrer — ce que l'utilisateur voit lui-même.
"""

from __future__ import annotations

import os
from pathlib import Path

# Six entrées, comme sur le Mac, dans le même esprit : ce dont une personne
# âgée se sert vraiment.
CANDIDATS = [
    ("Courrier", ("outlook", "thunderbird", "courrier", "mail")),
    ("Photos", ("photos",)),
    ("Internet", ("google chrome", "microsoft edge", "firefox", "opera")),
    ("Visio", ("whatsapp", "skype", "zoom", "teams", "facetime")),
    ("Explorateur", ("explorateur de fichiers", "file explorer", "explorer")),
    ("Calendrier", ("calendrier", "calendar")),
]

# Un raccourci dont le nom contient l'un de ces mots n'est jamais l'application.
# Sans ce filtre, « Zoom » tombe sur « Uninstall Zoom Workplace » : chercher à
# appeler sa famille désinstallerait le logiciel.
EXCLUS = (
    "uninstall", "désinstall", "desinstall", "remove", "repair", "réparer",
    "readme", "lisez-moi", "help", "aide", "documentation", "licence", "license",
    "settings", "paramètres", "config", "manager", "updater", "mise à jour",
)

MENUS = (
    Path(os.environ.get("APPDATA", "")) / "Microsoft/Windows/Start Menu/Programs",
    Path(os.environ.get("PROGRAMDATA", "")) / "Microsoft/Windows/Start Menu/Programs",
)


def installees() -> list[dict]:
    candidats: list[tuple[str, str]] = []
    for racine in MENUS:
        if not racine.is_dir():
            continue
        try:
            candidats += [(l.stem.lower(), str(l)) for l in racine.rglob("*.lnk")]
        except OSError:
            continue

    trouves: dict[str, tuple[int, str]] = {}
    for nom, chemin in candidats:
        if any(mot in nom for mot in EXCLUS):
            continue
        for libelle, motifs in CANDIDATS:
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
                if libelle not in trouves or score < trouves[libelle][0]:
                    trouves[libelle] = (score, chemin)
                break

    return [
        {"label": libelle, "path": trouves[libelle][1]}
        for libelle, _ in CANDIDATS
        if libelle in trouves
    ]


def lancer(chemin: str) -> tuple[bool, str]:
    """N'ouvre qu'un raccourci du menu Démarrer, jamais un exécutable quelconque."""
    cible = Path(chemin or "")
    if cible.suffix.lower() != ".lnk" or not cible.is_file():
        return False, "Cette application n'est plus installée."
    if not any(str(cible).lower().startswith(str(r).lower()) for r in MENUS if str(r)):
        return False, "Raccourci hors du menu Démarrer."
    try:
        os.startfile(str(cible))  # noqa: S606 — raccourci du menu Démarrer
    except OSError as e:
        return False, str(e)
    return True, str(cible)
