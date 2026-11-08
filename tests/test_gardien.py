"""Le gardien reconnaît le faux support et l'hameçonnage, et se tait le reste du temps.

Les faux positifs comptent autant que les vrais : une alerte qui sonne pour la
page de connexion Microsoft de l'entreprise apprend à cliquer « J'ai compris »,
et le jour où l'alerte est vraie, on clique aussi.

    python tests/test_gardien.py
"""

from __future__ import annotations

import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RACINE))
sys.path.insert(0, str(RACINE / "apps" / "windows"))
from backend import guard  # noqa: E402
from papai import guard_local  # noqa: E402

ok = fails = 0
ORG = ["acme.fr"]


def check(label: str, cond: bool, detail="") -> None:
    global ok, fails
    if cond:
        ok += 1
        print(f"  OK      {label}")
    else:
        fails += 1
        print(f"  ECHEC   {label} {detail}")


def attendu(label: str, processus, fenetre, url, niveau: str | None, bloquant: bool | None = None,
            declares=()) -> None:
    """`niveau` None = le gardien doit se taire."""
    a = guard.evaluer(processus, fenetre, url, outils_declares=declares, domaines_org=ORG)
    obtenu = a.niveau if a else None
    check(f"{label:<46} -> {obtenu or 'silence'}", obtenu == niveau
          and (bloquant is None or a.bloquant == bloquant), f"(attendu {niveau or 'silence'}, bloquant {bloquant})")


print("Ce que le gardien doit signaler")
attendu("outil de prise en main non déclaré", ["Safari", "AnyDesk"], "Bureau", "", "danger", True)
attendu("TeamViewer non déclaré", ["TeamViewerQS"], "", "", "danger", True)
attendu("fausse alerte virus : prévient sans bloquer", [], "VOTRE ORDINATEUR EST INFECTÉ — appelez ce numéro", "", "danger", False)
attendu("faux support Microsoft dans le titre", [], "Microsoft Support - Alerte sécurité", "", "danger", False)
attendu("faux site de connexion Microsoft", [], "", "https://microsoft-login-secure.com", "danger", True)
attendu("faute de frappe volontaire", [], "", "https://micros0ft.com", "danger", True)
attendu("« office » comme morceau d'adresse", [], "", "https://office.secure-auth.net", "danger", True)
attendu("faux Google", [], "", "https://accounts-google.verify-session.com", "danger", True)
attendu("domaine qui contient celui de l'entreprise", [], "", "https://acme-login.com", "danger", True)
attendu("domaine sosie de l'entreprise", [], "", "https://acmee.fr", "danger", True)
attendu("SSO de l'entreprise sur un autre domaine", [], "", "https://okta.acme-sso.com", "danger", True)
attendu("adresse IP publique", [], "", "https://45.33.12.7/login", "attention", False)
attendu("caractères trompeurs", [], "", "https://xn--pple-43d.com", "attention", False)
attendu("outil + faux site : l'outil d'abord", ["AnyDesk"], "", "https://acmee.fr", "danger", True)

print()
print("Ce qu'il doit laisser tranquille")
for label, url in [
    ("connexion Microsoft 365", "https://login.microsoftonline.com"),
    ("SharePoint de l'entreprise", "https://acme.sharepoint.com"),
    ("OneDrive de l'entreprise", "https://acme-my.sharepoint.com"),
    ("Outlook", "https://outlook.office.com"),
    ("Teams", "https://teams.microsoft.com"),
    ("Google", "https://accounts.google.com"),
    ("Google national", "https://www.google.fr"),
    ("Okta de l'entreprise", "https://acme.okta.com"),
    ("intranet", "https://intranet.acme.fr"),
    ("site d'information", "https://www.lemonde.fr"),
    ("« office » dans un mot", "https://www.officedepot.fr"),
    ("imprimante du réseau", "http://192.168.1.10"),
    ("sa banque", "https://boursorama.com"),
]:
    attendu(label, [], "", url, None)
attendu("outil déclaré par l'IT", ["TeamViewer"], "", "", None, declares=["teamviewer"])
attendu("aucun signal", [], "", "", None)
attendu("bureau ordinaire", ["Finder", "Safari", "Mail"], "Finder", "", None)
attendu("le mot virus dans un article", [], "Grippe : le virus circule tôt", "https://lemonde.fr", None)
attendu("PapAI lui-même", ["PapAI", "Finder"], "PapAI", "", None)

print()
print("Règles envoyées à l'ordinateur, et ce qu'il renvoie")
r = guard.regles(["teamviewer"], ORG)
check("outil déclaré retiré des règles", "teamviewer" not in r["tools"] and "anydesk" in r["tools"])
check("domaines de l'entreprise et marques", "acme.fr" in r["official"] and "acme" in r["keywords"]
      and "microsoftonline.com" in r["official"])
check("sans règles, l'ordinateur n'envoie rien", guard_local.signals(["AnyDesk"], "", "", None) is None)
check("rien ne correspond : rien ne part",
      guard_local.signals(["Safari", "Mail"], "Rapport T3 — Excel", "https://www.lemonde.fr/x", r) is None)
sig = guard_local.signals(["Safari", "AnyDesk"], "Budget 2026", "https://acmee.fr/connexion?x=1", r)
check("seuls l'outil et le site en cause partent, sans chemin", sig == {
    "type": "guard", "processes": ["AnyDesk"], "window": "", "url": "https://acmee.fr"}, sig)
hotes = ["microsoft-login-secure.com", "micros0ft.com", "office.secure-auth.net", "acme-login.com", "acmee.fr",
         "okta.acme-sso.com", "45.33.12.7", "xn--pple-43d.com", "accounts-google.verify-session.com",
         "login.microsoftonline.com", "acme.sharepoint.com", "www.lemonde.fr", "intranet.acme.fr"]
manque = [h for h in hotes if guard.site_suspect(h, ORG) and not guard_local.site_to_report(h, r)]
check("tout site que le serveur signalerait part de l'ordinateur", not manque, manque)
officiels = [h for h in ["login.microsoftonline.com", "acme.sharepoint.com", "intranet.acme.fr"]
             if guard_local.site_to_report(h, r)]
check("les sites officiels restent sur l'ordinateur", not officiels, officiels)

print()
print(f"{ok} contrôles passés, {fails} échec(s)")
sys.exit(1 if fails else 0)
