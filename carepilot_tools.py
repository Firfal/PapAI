"""Contrat partagé avec le modèle Holo.

Importé par le harnais local (holo_agent.py) et par la boucle agent du backend.
Ne dépend ni de mss ni de pyautogui : le backend ne touche jamais l'écran.
"""

from __future__ import annotations

import os
import sys

from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

MODEL = os.environ.get("HOLO_MODEL", "holo3-1-35b-a3b")
BASE_URL = os.environ.get("HOLO_BASE_URL", "https://api.hcompany.ai/v1/")

# Visée déterministe. À 0.8, le modèle rate occasionnellement sa cible de
# plusieurs centaines de pixels (mesuré sur le bouton Démarrer : x=100 au lieu
# de 361). Pour du pointage, l'échantillonnage n'apporte rien et coûte des ratés.
TEMPERATURE = 0.0

# Free tier : 5 images max par requête, contexte 65k tokens.
MAX_IMAGES_IN_CONTEXT = 3

# Free tier : 10 requêtes / minute — une limite de REQUÊTES, pas de tokens.
# Vérifié sur la doc H : aucun plafond de tokens par minute sur ce palier.
MIN_SECONDS_PER_STEP = 6.5

# Tarifs holo3-1-35b-a3b, en dollars par million de tokens. Sert uniquement à
# estimer le coût d'une session pendant le développement.
PRICE_IN_PER_M = 0.25
PRICE_OUT_PER_M = 1.80


def estimate_cost(prompt_tokens: int, completion_tokens: int) -> float:
    return prompt_tokens * PRICE_IN_PER_M / 1e6 + completion_tokens * PRICE_OUT_PER_M / 1e6


def make_client() -> OpenAI:
    key = os.environ.get("HAI_API_KEY", "").strip()
    if not key or key.startswith(("hai_xxx", "hk_xxx", "hk-xxx")):
        sys.exit(
            "HAI_API_KEY manquante. Copier .env.example vers .env et y coller la clé "
            'créée sur https://platform.hcompany.ai (produit "Models API").'
        )
    return OpenAI(base_url=BASE_URL, api_key=key)


SYSTEM_PROMPT = """Tu es CarePilot, un assistant qui aide une personne âgée sur son PC Windows.
Tu vois une capture d'écran à chaque étape et tu agis avec les outils fournis.
Règles :
- Fais une seule action par étape, puis vérifie le résultat sur la capture suivante.
- Préfère les chemins simples et visibles (barre latérale de l'Explorateur, menu Démarrer).

Où chercher les fichiers de la personne :
- Ses fichiers sont rangés dans les raccourcis de la barre latérale gauche de
  l'Explorateur : Téléchargements, Images, Documents, Vidéos, Galerie, Bureau.
  Va DIRECTEMENT dans celui qui correspond à ce qu'elle cherche. Des photos ->
  Images ou Galerie. Un fichier qu'elle vient de télécharger -> Téléchargements.
  Un courrier ou un papier -> Documents. Une vidéo -> Vidéos.
- N'ouvre JAMAIS « Ce PC », « Disque local (C:) », « OS (C:) », « Utilisateurs »
  ni aucun chemin commençant par C:\\Users. Ce sont des chemins techniques :
  la personne n'y range rien elle-même et tu t'y perdrais en arborescence.
  Si tu t'y retrouves malgré tout, reviens à la barre latérale gauche.
- Si le bon dossier ne contient pas ce que tu cherches après deux essais,
  appelle ask_helper plutôt que de continuer à fouiller ailleurs.
- Si tu hésites entre plusieurs choix (par ex. deux dossiers plausibles), ou si une action
  semble sensible (mot de passe, paiement, suppression), appelle ask_helper au lieu d'agir.
- Ne touche jamais aux mots de passe, paiements, opérations bancaires ou démarches administratives.
- Quand la tâche est terminée et visible à l'écran, appelle answer avec une phrase simple
  destinée à la personne aidée.
"""

MAC_SYSTEM_PROMPT = """Tu es PapAI, un assistant qui aide une personne âgée sur son Mac.
Tu vois une capture d'écran à chaque étape et tu agis avec les outils fournis.
Règles :
- Fais une seule action par étape, puis vérifie le résultat sur la capture suivante.
- Préfère les chemins simples et visibles : le Dock, la barre latérale du Finder,
  le Launchpad, la recherche Spotlight (cmd+space puis le nom de l'app).

Où chercher les fichiers de la personne :
- Ses fichiers sont dans la barre latérale du Finder : Téléchargements, Images,
  Documents, Bureau, Vidéos. Des photos -> l'app Photos ou le dossier Images.
  Un fichier téléchargé -> Téléchargements. Un courrier -> Documents.
- N'ouvre jamais Macintosh HD, Utilisateurs, Bibliothèque ni un chemin technique.
- Si le bon dossier ne contient pas ce que tu cherches après deux essais,
  appelle ask_helper plutôt que de continuer à fouiller ailleurs.
- Si tu hésites entre plusieurs choix, ou si une action semble sensible
  (mot de passe, paiement, envoi d'un message, suppression), appelle ask_helper.
- Ne touche jamais aux mots de passe, paiements, opérations bancaires.
- Ne clique JAMAIS dans une fenêtre d'autorisation du système (accès à l'écran,
  au micro, Accessibilité, mot de passe, « Autoriser » / « Ne pas autoriser »),
  ni dans les Réglages Système. Ces choix appartiennent à la personne et à son
  proche : appelle ask_helper. Dans un plan, ne propose jamais de les fermer.
- Quand la tâche est terminée et visible à l'écran, appelle answer avec une phrase
  simple destinée à la personne aidée.
"""

PLAN_PROMPT = """Tu prépares un plan pour aider une personne âgée sur son ordinateur ({os}).
Tu vois son écran actuel. Tu n'agis PAS : tu proposes un plan que son proche va valider.

Règles :
- 2 à 5 étapes, courtes, compréhensibles par quelqu'un qui ne voit pas l'écran.
- Chaque étape commence par un verbe à l'infinitif : « Ouvrir le Finder ».
- Pas de coordonnées, pas de pixels, pas de vocabulaire technique.
- Ignore les fenêtres d'autorisation du système et les Réglages Système : ne
  propose jamais de les fermer ni d'y cliquer.
- Si la demande touche à un paiement, un mot de passe ou une suppression, ajoute
  une dernière étape « Demander confirmation au proche avant de valider ».
- Français simple et correct, aucun mot anglais.

Réponds UNIQUEMENT par un objet JSON, sans texte autour :
{{"steps": ["...", "..."]}}"""


def system_prompt(os_name: str) -> str:
    return MAC_SYSTEM_PROMPT if os_name == "macos" else SYSTEM_PROMPT


TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "click",
            "description": "Clic gauche sur un élément",
            "parameters": {
                "type": "object",
                "properties": {
                    "element": {"type": "string", "description": "Description détaillée de l'élément visé"},
                    "x": {"type": "integer", "description": "X dans [0, 1000]"},
                    "y": {"type": "integer", "description": "Y dans [0, 1000]"},
                },
                "required": ["element", "x", "y"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "double_click",
            "description": "Double-clic gauche (ouvrir un dossier, un fichier, un raccourci)",
            "parameters": {
                "type": "object",
                "properties": {
                    "element": {"type": "string"},
                    "x": {"type": "integer"},
                    "y": {"type": "integer"},
                },
                "required": ["element", "x", "y"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "type_text",
            "description": "Taper du texte dans le champ qui a le focus",
            "parameters": {
                "type": "object",
                "properties": {"text": {"type": "string"}},
                "required": ["text"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "press_key",
            "description": "Appuyer sur une touche ou un raccourci, ex: 'enter', 'esc', 'win+e', 'ctrl+l'",
            "parameters": {
                "type": "object",
                "properties": {"keys": {"type": "string"}},
                "required": ["keys"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "scroll",
            "description": "Faire défiler à la position donnée",
            "parameters": {
                "type": "object",
                "properties": {
                    "x": {"type": "integer"},
                    "y": {"type": "integer"},
                    "direction": {"type": "string", "enum": ["up", "down"]},
                },
                "required": ["x", "y", "direction"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "wait",
            "description": "Attendre quelques secondes qu'une fenêtre se charge",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "ask_helper",
            "description": "Poser une question au proche aidant quand tu hésites ou que l'action est sensible. Suspend l'agent.",
            "parameters": {
                "type": "object",
                "properties": {
                    "question": {"type": "string", "description": "Question courte et concrète pour le proche"},
                    "options": {"type": "array", "items": {"type": "string"}, "description": "Choix possibles, si pertinent"},
                },
                "required": ["question"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "answer",
            "description": "Terminer la tâche et expliquer le résultat à la personne aidée",
            "parameters": {
                "type": "object",
                "properties": {"content": {"type": "string"}},
                "required": ["content"],
            },
        },
    },
]

# Actions qui pilotent réellement la souris ou le clavier du PC de la personne
# aidée. Toute action hors de cette liste est traitée par le backend et ne
# descend jamais au pont.
ACTUATING_TOOLS = {"click", "double_click", "type_text", "press_key", "scroll"}


def observation(b64: str) -> dict:
    """Une capture d'écran présentée au modèle comme une observation."""
    return {
        "role": "user",
        "content": [
            {"type": "text", "text": "<observation>\n"},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
            {"type": "text", "text": "\n</observation>"},
        ],
    }


def trim_to_last_n_images(messages: list, n: int = MAX_IMAGES_IN_CONTEXT) -> None:
    """Remplace les captures les plus anciennes par un marqueur texte."""
    seen = 0
    for msg in reversed(messages):
        if msg["role"] != "user" or not isinstance(msg["content"], list):
            continue
        for chunk in msg["content"]:
            if chunk.get("type") != "image_url":
                continue
            seen += 1
            if seen > n:
                chunk["type"] = "text"
                chunk["text"] = "[capture précédente]"
                chunk.pop("image_url", None)


def to_assistant_message(msg) -> dict:
    """Sérialise la réponse du modèle pour la rejouer dans l'historique.

    On ne renvoie jamais les objets du SDK tels quels, ni `tool_calls: None`.
    """
    out: dict = {"role": "assistant", "content": msg.content or ""}
    if msg.tool_calls:
        out["tool_calls"] = [
            {
                "id": c.id,
                "type": "function",
                "function": {"name": c.function.name, "arguments": c.function.arguments},
            }
            for c in msg.tool_calls
        ]
    return out
