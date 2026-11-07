# PapAI : textes de soumission (Luma et BuilderBase)

Rendu : **dimanche 8 novembre, 14 h sur Luma, 14 h 30 sur BuilderBase**. Il faut se connecter soi-même
(dashboard BuilderBase : `builderbase.com/track-dashboard/h-company-42ai-computer-use-agents-hackathon/overview`).
Les blocs ci-dessous sont prêts à copier-coller. Les champs `[À COMPLÉTER]` sont à remplir avant l'envoi.

> Relire avant d'envoyer : les phrases marquées *[si …]* ne restent que si la fonction marche le jour J
> (voir `TODO.md`, P0 et P2). Retirer les crochets et les marques avant de coller.

## Titre

```
PapAI
```

## Accroche (une ligne)

```
Un agent qui aide votre grand-parent sur son ordinateur, uniquement avec votre accord.
```

Variante courte (si la limite est très basse) :

```
L'aide à distance pour nos aînés : Holo agit, le proche valide d'abord.
```

## Description courte (environ 300 caractères)

```
La personne âgée demande de l'aide sur son Mac. Holo, le modèle d'H Company, regarde l'écran et propose un plan. Son proche le valide, le précise ou le refuse depuis son iPhone avant toute action. Holo exécute sous ses yeux, elle peut tout arrêter, et une réussite devient une tuile rejouable en un clic.
```

## Description longue

```
Le problème
Jeanne veut retrouver ses photos de Noël et ne sait pas dans quel dossier elles sont. Son proche est dans le métro, sans ordinateur. Lui faire installer un logiciel de prise en main n'est pas une option : c'est précisément ce que réclament les arnaqueurs au téléphone.

La solution
PapAI est un agent de computer use pour les personnes âgées, avec une règle non négociable : rien ne bouge sur l'ordinateur sans un plan validé par un proche.

1. Demander : la personne appuie sur un gros bouton « J'ai besoin d'aide » et explique avec ses mots, au clavier ou à la voix.
2. Proposer : Holo, le modèle d'H Company, regarde l'écran et propose un plan de 2 à 5 étapes en langage simple.
3. Valider : le proche reçoit le plan sur son iPhone (ou sur une page web de secours) et choisit Valider, Préciser ou Refuser. S'il précise, Holo refait le plan.
4. Exécuter : Holo clique et tape pendant que la personne regarde ; chaque action est expliquée en une phrase. Le bouton Arrêter est un verrou local sur le Mac, valable même hors ligne.
5. Garder : une session réussie devient un automatisme, une tuile que la personne relance seule. Le rejeu est local et sans modèle. Si le dossier a bougé, l'app s'arrête et prévient le proche au lieu d'agir à l'aveugle.

Les garde-fous
- Aucune action sans plan validé, et chaque décision de l'aidant est revalidée par le serveur.
- Holo ne touche jamais une fenêtre d'autorisation du système ni les Réglages. Face à un mot de passe, un paiement ou une suppression, il pose la question au proche au lieu d'agir. La première consigne vient d'une vraie répétition : le plan proposait de fermer une fenêtre de sécurité macOS, l'aidant a refusé, rien n'a bougé.
- La fenêtre PapAI est exclue des captures et des clics. Une capture trop ancienne ne peut pas servir à un clic de l'aidant.
- Un seul pilote à la fois : l'aidant ne prend la main que quand l'agent est suspendu.
- La personne accepte explicitement que PapAI regarde son écran, et c'est elle qui accepte ou refuse une session proposée par un proche.
- Les proches s'ajoutent par QR ou code à 6 chiffres, à usage unique ; toutes les routes en ligne sont protégées par une clé famille.

Gardien anti-arnaque [si branché ; sinon écrire « en cours de branchement, logique testée »]
PapAI reconnaît les situations d'arnaque typiques à partir de trois signaux textuels, sans capture : un outil de prise en main qui tourne (AnyDesk, TeamViewer…), une fausse alerte « votre ordinateur est infecté », un site de carte prépayée, et surtout un outil de prise en main avec une page bancaire ouverte. Le proche est prévenu, et Holo lui décrit ce qui est réellement à l'écran.
```

## Technologies

```
- Holo (H Company), modèle holo3-1-35b-a3b, via l'API compatible OpenAI d'H Company : planification et computer use (capture, clic, saisie, touches, défilement).
- App Mac de la personne aidée : Swift, SwiftUI, ScreenCaptureKit (capture sans la fenêtre PapAI), CGEvent (actions).
- App iPhone de l'aidant : Swift, SwiftUI.
- Serveur : Python, FastAPI, WebSockets, déployé sur Google Cloud Run.
- Dictée : Gladia (transcription française côté serveur), avec la reconnaissance vocale d'Apple en secours sur le Mac. [si GLADIA_API_KEY en ligne]
- Développement assisté par agents IA, dont Claude Code et Devin. [À COMPLÉTER : liste exacte des agents utilisés par l'équipe]
```

Tags éventuels : `computer use`, `accessibilité`, `seniors`, `aidants`, `sécurité`, `H Company`, `Holo`.

## Prix sponsors visés (`HANDOFF.md`)

- **Gladia** : la dictée de la demande passe par l'API Gladia (`backend/voice.py`, route `/transcribe`). À mentionner seulement si la clé est en ligne et la dictée essayée.
- **Devin** : [À COMPLÉTER : ce que Devin a fait dans le projet, par exemple la page web de l'aidant en design « Soin » et ces textes de rendu].

## Équipe

```
[À COMPLÉTER : prénom nom, rôle, lien (GitHub ou LinkedIn) pour chaque membre]
- Quentin Robert : [rôle]
- Théo [nom] : [rôle]
- [membre] : [rôle]
- [membre] : [rôle]
```

## Liens

| Lien | Valeur |
|---|---|
| Code | `https://github.com/Firfal/PapAI` [À VÉRIFIER : le dépôt est privé ; le rendre public ou donner l'accès au jury] |
| Vidéo de démo (2 min) | [À COMPLÉTER : lien YouTube ou Loom non répertorié] |
| Démo en ligne | [À COMPLÉTER ou retirer : l'accès demande la clé famille, qui ne doit jamais être publiée] |
| Slides | [À COMPLÉTER] |

## Vérifications avant d'envoyer

- [ ] Aucune clé (Holo, clé famille, Gladia) dans les textes, les liens ou les captures.
- [ ] Aucune capture d'un vrai écran personnel : seulement les écrans de démo.
- [ ] Les marques *[si …]* et `[À COMPLÉTER]` ont toutes été traitées.
- [ ] Le même texte est envoyé sur Luma (14 h) et BuilderBase (14 h 30).
