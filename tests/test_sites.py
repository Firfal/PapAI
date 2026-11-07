"""Contrôles du Gardien navigateur, seuls puis avec un serveur facultatif."""

from __future__ import annotations

import asyncio
import json
import os
import secrets
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from unittest.mock import patch

import websockets

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from backend import sites
from backend.family import PairingError

ok = fails = 0


def check(nom, condition):
    global ok, fails
    print(f"  {'OK' if condition else 'ECHEC'}      {nom}")
    if condition:
        ok += 1
    else:
        fails += 1


def refuse(liaison, code):
    try:
        liaison.pair(code)
        return False
    except PairingError:
        return True


EXTRAITS = {
    "impots.gouv.fr": ("Votre espace particulier", "Consultez votre avis d'imposition et déclarez vos revenus."),
    "ameli.fr": ("Compte ameli", "Retrouvez vos remboursements de soins et votre attestation de droits."),
    "laposte.fr": ("Suivre un colis", "Votre colis est en cours de livraison."),
    "service-public.fr": ("Vos démarches", "Demander le renouvellement de votre carte d'identité."),
    "caf.fr": ("Mon compte allocataire", "Consultez le calendrier des versements de vos prestations."),
    "franceconnect.gouv.fr": ("FranceConnect", "Choisissez un compte pour vous identifier."),
    "labanquepostale.fr": ("Espace client", "Consultez le solde de vos comptes et vos relevés."),
    "credit-agricole.fr": ("Ma banque", "Vos comptes, cartes et assurances dans votre espace sécurisé."),
    "google.com": ("Recherche Google", "Recherchez des informations sur le Web."),
    "youtube.com": ("YouTube", "Découvrez les vidéos et les chaînes auxquelles vous êtes abonné."),
    "wikipedia.org": ("Wikipédia", "L'encyclopédie libre que chacun peut améliorer."),
    "leboncoin.fr": ("Petites annonces", "Trouvez un meuble d'occasion près de chez vous."),
    "amazon.fr": ("Vos commandes", "Suivez la livraison de votre dernière commande."),
    "orange.fr": ("Espace client Orange", "Consultez votre facture internet et votre consommation."),
    "free.fr": ("Espace abonné", "Gérez votre abonnement Freebox et vos options."),
}
for domaine in sites.CONNUS:
    titre, extrait = EXTRAITS.get(domaine, ("Votre espace personnel", "Consultez vos documents et les informations de votre compte."))
    check(domaine, sites.evaluer("www." + domaine, titre, extrait).verdict == "sur")
for domaine, titre, texte in [
    ("ameli-remboursement.xyz", "Votre remboursement", "Saisissez votre carte"),
    ("impots-gouv-remboursement.com", "Impôts", "Remboursement"),
    ("laposte-colis-suivi.top", "Colis", "Frais de livraison"),
    ("caf-prime.com", "CAF", "Votre prime"),
    ("credit-agricole-securite.com", "Banque", "Identifiez-vous"),
    ("xn--amli-cpa.com", "Ameli", "Connexion"),
    ("ameIi.fr", "Assurance maladie", "Connexion"),
    ("amelli.fr", "Ameli", "Connexion"),
    ("assistance-pc.com", "Microsoft support", "Votre ordinateur est infecté"),
    ("cadeaux.top", "Paiement", "Achetez un coupon Transcash"),
    ("placement.com", "Urgent", "Virement immédiat en bitcoin"),
    ("transfert.com", "Compte bloqué", "Effectuez un virement immédiat"),
]:
    check(domaine, sites.evaluer(domaine, titre, texte).verdict == "arnaque")
check("signal unique hésitant", sites.evaluer("boutique.xyz", "Accueil", "Bonjour").hesite)
check("aucun signal", sites.evaluer("exemple.fr", "", "").verdict == "sur")
check("suffixe connu non contournable", sites.evaluer("ameli.fr.evil.com", "", "").verdict == "arnaque")
check("normalisation", sites.normaliser("https://AMELI.FR:443/compte") == "ameli.fr")

with tempfile.TemporaryDirectory() as dossier:
    chemin = Path(dossier) / "sites.json"
    liaison = sites.Liaison(chemin)
    code = liaison.new_code()
    check("code faux", refuse(liaison, "incorrect"))
    liaison._expires = 0
    check("code expiré", refuse(liaison, code))
    code = liaison.new_code()
    for _ in range(5):
        refuse(liaison, "incorrect")
    check("cinq essais", refuse(liaison, code))
    code = liaison.new_code()
    jeton = liaison.pair(code)
    check("usage unique", refuse(liaison, code))
    check("stockage hash seul", jeton not in chemin.read_text() and sites.Liaison.empreinte(jeton) in chemin.read_text())
    check("jeton inconnu", liaison.autoriser("inconnu") == 401)
    check("30 signalements", all(liaison.autoriser(jeton) == 200 for _ in range(30)))
    check("limite courte", liaison.autoriser(jeton) == 429)
    liaison.jetons[liaison.empreinte(jeton)] = [sites.time.time() - 700] * 300
    check("limite jour", liaison.autoriser(jeton) == 429)
    check("limite persistée", sites.Liaison(chemin).autoriser(jeton) == 429)


async def erreurs_holo():
    os.environ.setdefault("HAI_API_KEY", "stub-key")
    from backend import agent
    with patch.object(agent.client.chat.completions, "create", side_effect=RuntimeError("panne")):
        check("Holo en panne reste douteux", (await sites.avis_holo("exemple.xyz", "", "")).verdict == "douteux")
    with patch.object(agent.client.chat.completions, "create") as appel:
        appel.return_value.choices[0].message.content = '{"verdict":"sur","raison":42}'
        check("JSON invalide reste douteux", (await sites.avis_holo("exemple.xyz", "", "")).verdict == "douteux")


def http(base, chemin, corps, jeton=""):
    requete = urllib.request.Request(base + chemin, data=json.dumps(corps).encode(),
                                   headers={"Content-Type": "application/json", "Authorization": "Bearer " + jeton})
    try:
        with urllib.request.urlopen(requete) as reponse:
            return reponse.status, json.load(reponse)
    except urllib.error.HTTPError as erreur:
        return erreur.code, {}


async def recevoir(ws, type_attendu, delai=2):
    async with asyncio.timeout(delai):
        while True:
            message = json.loads(await ws.recv())
            if message.get("type") == type_attendu:
                return message


async def integration(base, cle):
    wsbase = base.replace("http", "ws", 1)
    async with websockets.connect(wsbase + "/ws/bridge") as pont:
        await pont.send(json.dumps({"type": "hello", "os": "macos", "name": "Jeanne"}))
        await pont.send(json.dumps({"type": "ext_pair_start"}))
        code = await recevoir(pont, "ext_pair_code")
        statut, liaison = await asyncio.to_thread(http, base, "/ext/pair", {"code": code["code"]})
        check("appairage HTTP", statut == 200 and code["expires_in"] == 600)
        jeton = liaison["token"]
        async with websockets.connect(wsbase + "/ws/aidant/" + cle) as aidant:
            await recevoir(aidant, "hello")
            await aidant.send(json.dumps({"type": "helper_hello", "id": "test-sites", "name": "Claire"}))
            await recevoir(aidant, "helper_id")
            suffixe = secrets.token_hex(4)
            page = {"domain": "ameli-remboursement-" + suffixe + ".xyz", "title": "Remboursement", "text": "TEXTE_SECRET_PAGE_GARDIEN"}
            statut, avis = await asyncio.to_thread(http, base, "/ext/site", page, jeton)
            check("arnaque HTTP", statut == 200 and avis["verdict"] == "arnaque" and avis["proche"])
            alerte = await recevoir(pont, "alert")
            check("texte aidé danger", alerte["level"] == "danger" and "Ne donnez rien" in alerte["detail"])
            alerte = await recevoir(aidant, "alert")
            check("texte aidant distinct", "Jeanne" in alerte["detail"] and "Ameli" in alerte["detail"] and "Ne donnez rien" not in alerte["detail"])
            await asyncio.to_thread(http, base, "/ext/site", page, jeton)
            for canal, nom in ((pont, "pont"), (aidant, "aidant")):
                try:
                    await recevoir(canal, "alert", .3)
                    check("anti-rebond " + nom, False)
                except TimeoutError:
                    check("anti-rebond " + nom, True)
            statut, avis = await asyncio.to_thread(http, base, "/ext/site", {"domain": "ameli.fr"}, jeton)
            check("site connu HTTP", statut == 200 and avis["verdict"] == "sur")
            statut, avis = await asyncio.to_thread(http, base, "/ext/site", {"domain": "boutique-" + suffixe + ".xyz"}, jeton)
            check("Holo pour un signal faible", statut == 200 and avis["verdict"] == "douteux")
            alerte = await recevoir(aidant, "alert")
            check("doute aidant attention", alerte["level"] == "attention")
            try:
                await recevoir(pont, "alert", .3)
                check("doute absent du pont", False)
            except TimeoutError:
                check("doute absent du pont", True)
            check("401 inconnu", (await asyncio.to_thread(http, base, "/ext/site", page, "inconnu"))[0] == 401)
            check("bornes", (await asyncio.to_thread(http, base, "/ext/site", {"domain": "a" * 254}, jeton))[0] == 400)
            requete = urllib.request.Request(base + "/k/" + jeton + "/lessons", headers={"Authorization": "Bearer " + jeton})
            try:
                urllib.request.urlopen(requete)
                check("jeton refusé ailleurs", False)
            except urllib.error.HTTPError as erreur:
                check("jeton refusé ailleurs", erreur.code == 404)
            journal = Path(__file__).resolve().parent.parent / "logs/extension-serveur.log"
            if journal.exists():
                check("texte absent du journal", page["text"] not in journal.read_text())


asyncio.run(erreurs_holo())
if len(sys.argv) > 1:
    asyncio.run(integration(sys.argv[1].rstrip("/"), sys.argv[2] if len(sys.argv) > 2 else "demo"))
print(f"\n{ok} contrôles réussis, {fails} échecs")
sys.exit(bool(fails))
