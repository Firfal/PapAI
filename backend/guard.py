"""Le gardien : reconnaître une situation d'arnaque, et prévenir l'aidant.

Deux paliers, pour une raison de principe autant que de coût.

Le Mac observe en continu trois signaux **textuels** — processus actifs, titre
de la fenêtre, adresse du navigateur. Rien ne sort de la machine : pas de
capture, pas d'appel au modèle, pas de trace ailleurs. C'est ce qui permet à une
veille permanente de coexister avec la promesse « pas de contrôle permanent ».

Hors session, l'alerte repose sur ces seuls signaux : aucune capture ne part.
Pendant une session acceptée, où Holo voit déjà l'écran, un motif marqué
`confirmer` fait décrire la capture par le modèle, en français, pour l'aidant.

Ce module ne promet pas de protéger : il reconnaît des situations qu'on y a
mises. C'est une différence qu'il faut tenir dans le discours aussi.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# --------------------------------------------------------------- les motifs

# L'arnaque numéro un contre cette population : un inconnu au téléphone fait
# installer un outil de prise en main, puis vide le compte. C'est exactement ce
# que fait PapAI — à ceci près qu'ici un proche de confiance valide chaque pas.
OUTILS_PRISE_EN_MAIN = (
    "anydesk", "teamviewer", "ultraviewer", "supremo", "rustdesk", "ammyy",
    "quicksupport", "splashtop", "logmein", "gotoassist", "screenconnect",
    "connectwise", "vnc", "dwservice", "zohoassist", "aeroadmin",
)

# Pages et fenêtres qui annoncent elles-mêmes l'arnaque.
TITRES_ALARMANTS = (
    r"votre (ordinateur|syst[eè]me) est (infect|bloqu|verrouill)",
    r"virus d[ée]tect",
    r"appelez (imm[ée]diatement|ce num[ée]ro|le support)",
    r"microsoft (support|s[ée]curit[ée])",
    r"your (computer|system) (is|has been) (infected|blocked|locked)",
    r"call (microsoft|apple|windows) support",
    r"licence windows expir",
)

# Un achat de carte cadeau ou un transfert crypto demandé par téléphone est la
# sortie d'argent préférée des escrocs : intraçable et irréversible.
DOMAINES_SENSIBLES = (
    "paysafecard", "transcash", "neosurf", "pcsmastercard",
    "binance", "coinbase", "kraken", "localbitcoins",
    "westernunion", "moneygram",
)

# Contextes bancaires : pas dangereux en soi, mais aggravants.
DOMAINES_BANCAIRES = (
    "banque", "bank", "caisse-epargne", "creditagricole", "bnpparibas",
    "societegenerale", "labanquepostale", "credit-mutuel", "boursorama",
    "fortuneo", "hellobank", "revolut", "paypal",
)


@dataclass
class Alerte:
    niveau: str          # "info" | "attention" | "danger"
    titre: str
    detail: str
    motif: str           # ce qui a déclenché, pour le journal
    confirmer: bool      # décrire l'écran par le modèle (seulement en session)


def _contient(texte: str, aiguilles) -> str | None:
    t = (texte or "").lower()
    for a in aiguilles:
        if a in t:
            return a
    return None


def evaluer(processus: list[str], fenetre: str = "", url: str = "") -> Alerte | None:
    """Rend une alerte, ou None. Appelé en continu, sans rien envoyer nulle part.

    L'ordre compte : on rend l'alerte la plus grave, pas la première trouvée.
    """
    procs = " ".join(processus or []).lower()
    outil = _contient(procs, OUTILS_PRISE_EN_MAIN)
    argent = _contient(url, DOMAINES_SENSIBLES)
    banque = _contient(url, DOMAINES_BANCAIRES)

    titre_alarmant = None
    for motif in TITRES_ALARMANTS:
        if re.search(motif, (fenetre or "").lower()):
            titre_alarmant = motif
            break

    # Le pire cas : quelqu'un tient l'écran à distance pendant qu'on est sur un
    # site d'argent. Aucune raison légitime n'explique cette combinaison.
    if outil and (argent or banque):
        return Alerte(
            "danger",
            "Quelqu'un voit votre écran pendant une opération d'argent",
            f"Le logiciel « {outil} » permet à une autre personne de voir et "
            f"commander cet ordinateur, et une page bancaire ou de paiement est "
            f"ouverte. Si vous êtes au téléphone avec quelqu'un qui vous guide, "
            f"raccrochez et appelez votre proche.",
            f"outil={outil} + argent={argent or banque}",
            True,
        )

    if outil:
        return Alerte(
            "danger",
            "Quelqu'un est en train de prendre la main sur votre ordinateur",
            f"Le logiciel « {outil} » est en marche. Il permet à une personne "
            f"à distance de voir votre écran et de cliquer à votre place. "
            f"Est-ce bien quelqu'un que vous connaissez ?",
            f"outil={outil}",
            False,   # le nom du processus suffit : pas besoin de capture
        )

    if titre_alarmant:
        return Alerte(
            "danger",
            "Cette alerte à l'écran est fausse",
            "Une page affiche que votre ordinateur serait infecté ou bloqué, et "
            "vous demande d'appeler un numéro. Microsoft et Apple ne font jamais "
            "ça. N'appelez pas : fermez la fenêtre et prévenez votre proche.",
            f"titre={titre_alarmant}",
            True,
        )

    if argent:
        return Alerte(
            "attention",
            "Achat difficile à annuler",
            f"Le site « {argent} » sert à envoyer de l'argent d'une façon qu'on "
            f"ne peut presque jamais récupérer. Si quelqu'un vous a demandé de "
            f"le faire, parlez-en d'abord à votre proche.",
            f"argent={argent}",
            True,
        )

    return None


# ----------------------------------------------------- confirmation modèle

PROMPT_CONFIRMATION = """Tu regardes l'écran d'une personne âgée. Un indice technique
laisse penser qu'elle est peut-être victime d'une arnaque : {motif}

Dis en deux phrases, à son proche aidant, ce que tu vois réellement à l'écran et
si cela confirme ou non le soupçon. Sois factuel : décris, ne dramatise pas, et
dis clairement si tout semble normal.

Réponds uniquement par un objet JSON :
{{"confirme": true|false, "description": "deux phrases pour le proche"}}"""
