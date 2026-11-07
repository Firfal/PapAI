"""Le gardien reconnaît les situations d'arnaque, et se tait le reste du temps.

Les faux positifs comptent autant que les vrais : une alerte qui sonne pour un
relevé de compte apprend à la personne à cliquer « ignorer », et le jour où
l'alerte est vraie, elle l'ignore aussi.

    python tests/test_gardien.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from backend import guard

ok = fails = 0


def attendu(label: str, processus, fenetre, url, niveau: str | None) -> None:
    """`niveau` None = le gardien doit se taire."""
    global ok, fails
    a = guard.evaluer(processus, fenetre, url)
    obtenu = a.niveau if a else None
    if obtenu == niveau:
        ok += 1
        print(f"  OK      {label:<44} -> {obtenu or 'silence'}")
    else:
        fails += 1
        print(f"  ECHEC   {label:<44} -> {obtenu or 'silence'} (attendu {niveau or 'silence'})")


print("Ce que le gardien doit signaler")
attendu("outil de prise en main qui tourne", ["Safari", "AnyDesk"], "Bureau", "", "danger")
attendu("TeamViewer", ["TeamViewerQS"], "", "", "danger")
attendu("outil + site bancaire", ["UltraViewer"], "Safari", "https://mabanque.bnpparibas", "danger")
attendu("fausse alerte virus", [], "VOTRE ORDINATEUR EST INFECTÉ — appelez ce numéro", "", "danger")
attendu("faux support Microsoft", [], "Microsoft Support - Alerte sécurité", "", "danger")
attendu("fausse alerte en anglais", [], "Your computer is infected", "", "danger")
attendu("carte prépayée", [], "Safari", "https://transcash.fr/recharger", "attention")
attendu("transfert crypto", [], "Safari", "https://www.binance.com/fr", "attention")

print()
print("Ce qu'il doit laisser tranquille")
attendu("navigation ordinaire", [], "Le Monde", "https://www.lemonde.fr", None)
attendu("sa banque, seule", [], "Safari", "https://boursorama.com", None)
attendu("aucun signal", [], "", "", None)
attendu("bureau vide", ["Finder", "Safari", "Mail"], "Finder", "", None)
attendu("le mot virus dans un article", [], "Grippe : le virus circule tôt", "https://lemonde.fr", None)
attendu("PapAI lui-même", ["PapAI", "Finder"], "PapAI", "", None)

print()
print(f"{ok} contrôles passés, {fails} échec(s)")
sys.exit(1 if fails else 0)
