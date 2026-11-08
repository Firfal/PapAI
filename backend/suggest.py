from __future__ import annotations

import re
import unicodedata

STOP_WORDS = frozenset({
    "les", "des", "une", "pour", "avec", "dans", "sur", "mon", "ma", "mes",
    "est", "pas", "que", "qui", "comment", "faire", "veux", "voudrais",
    "aider", "aide", "peux", "plus", "tout", "son", "ses", "leur", "cette",
    "ces", "par", "aux", "du", "de", "la", "le", "et", "ou", "en", "un",
    "au", "a", "d", "l", "me", "moi", "te", "toi", "se", "nous", "vous",
    "ils", "elles", "on", "quoi", "quand", "ce", "cet", "sa", "sont", "etre",
    "avoir", "fait", "comme", "bien", "tres",
})
_APOSTROPHES = str.maketrans({"'": " ", "’": " ", "‘": " ", "`": " "})


def _mots(texte: str) -> set[str]:
    decomposed = unicodedata.normalize("NFKD", str(texte or "").casefold())
    ascii_text = "".join(c for c in decomposed if not unicodedata.combining(c))
    tokens = set()
    for mot in re.findall(r"[a-z0-9]+", ascii_text.translate(_APOSTROPHES)):
        if len(mot) < 3 or mot in STOP_WORDS:
            continue
        if len(mot) >= 4 and mot.endswith(("s", "x")):
            mot = mot[:-1]
        if mot not in STOP_WORDS:
            tokens.add(mot)
    return tokens


def suggerer(demande: str, automates: list[dict], limite: int = 2) -> list[dict]:
    """Classe les automates par mots communs, sans appel à un modèle."""
    demande_mots = _mots(demande)
    try:
        maximum = max(0, int(limite))
    except (TypeError, ValueError):
        return []
    if not demande_mots or maximum == 0:
        return []

    vus: set[str] = set()
    classes: list[tuple[int, str, str, dict]] = []
    for automate in automates or []:
        if not isinstance(automate, dict):
            continue
        identifiant = str(automate.get("id") or "").strip()
        titre = str(automate.get("title") or "").strip()
        if not identifiant or not titre or identifiant in vus:
            continue
        vus.add(identifiant)
        titre_mots = _mots(titre)
        description_mots = _mots(str(automate.get("description") or ""))
        score = 2 * len(demande_mots & titre_mots) + len(demande_mots & description_mots)
        if score:
            classes.append((-score, titre.casefold(), identifiant, {"id": identifiant, "title": titre}))

    classes.sort(key=lambda x: (x[0], x[1], x[2]))
    return [item[3] for item in classes[:maximum]]
