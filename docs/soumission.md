# PapAI : textes de soumission (Luma et BuilderBase)

Rendu : **dimanche 8 novembre, 14 h sur Luma, 14 h 30 sur BuilderBase**. Il faut se connecter soi-même
(dashboard BuilderBase : `builderbase.com/track-dashboard/h-company-42ai-computer-use-agents-hackathon/overview`).
Relu le 7 novembre à 18 h sur l'état réel. Les blocs sont prêts à copier-coller.

> **Avant d'envoyer** : une phrase suivie de **[R1]** à **[R6]** dépend d'un essai pas encore fait
> (tableau dans [`docs/pitch.md`](pitch.md)). Si l'essai a réussi, retirer la marque ; sinon, **supprimer la phrase**.
> Les champs `[À COMPLÉTER]` sont à remplir.

## Titre

```
PapAI
```

## Accroche (une ligne)

```
Un agent qui aide votre grand-parent sur son ordinateur, uniquement avec votre accord.
```

Variante courte :

```
L'aide à distance pour nos aînés : Holo agit, le proche valide d'abord.
```

## Description courte (environ 300 caractères)

```
La personne âgée dicte sa demande sur son Mac. Holo, le modèle d'H Company, regarde l'écran et propose un plan. Son proche le valide, le précise ou le refuse depuis son iPhone : rien ne bouge avant. Holo exécute sous ses yeux, et une réussite devient un bouton qu'elle relance seule.
```

Seule la dernière proposition dépend d'un essai (R1, R4) : si R4 manque, finir sur « Holo exécute sous ses yeux. »

## Description longue

```
Le problème
Jeanne veut revoir ses photos de Noël et ne sait plus dans quel dossier elles sont. Son proche est dans le métro, sans ordinateur. Lui faire installer un logiciel de prise en main n'est pas une option : c'est précisément ce que réclament les arnaqueurs au téléphone.

La solution
PapAI est un agent de computer use pour les personnes âgées, avec une règle non négociable : rien ne bouge sur l'ordinateur sans un plan validé par un proche.

1. Demander : la personne appuie sur un gros bouton « J'ai besoin d'aide » et explique avec ses mots, au clavier ou à la voix. La dictée est transcrite par Gladia côté serveur, avec la reconnaissance vocale d'Apple en secours sur le Mac. Elle accepte ensuite que PapAI regarde son écran.
2. Proposer : Holo, le modèle d'H Company, regarde l'écran et propose un plan de 2 à 5 étapes en langage simple.
3. Valider : le proche reçoit le plan sur son iPhone (ou sur une page web) et choisit Valider, Préciser ou Refuser. S'il précise, Holo refait le plan.
4. Exécuter : Holo clique et tape pendant que la personne regarde [R1] ; chaque action est expliquée en une phrase, avec l'étape du plan en cours. Le bouton Arrêter lève un verrou local sur le Mac qui bloque toute action suivante [R3].
5. Garder : une session réussie devient un automatisme, une tuile que la personne relance seule [R4]. Le rejeu est local et sans modèle : l'app ouvre un dossier connu du système. Si le dossier a bougé, l'app s'arrête et prévient le proche au lieu d'agir à l'aveugle [R5].

Les garde-fous
- Aucune action sans plan validé, et chaque décision du proche est revalidée par le serveur.
- Holo a pour consigne de ne jamais toucher une fenêtre d'autorisation du système ni les Réglages. Cette consigne vient d'une vraie répétition : le plan proposait de fermer une fenêtre de sécurité macOS, le proche a refusé, rien n'a bougé.
- Face à un mot de passe, un paiement ou une suppression, Holo a pour consigne de poser la question au proche au lieu d'agir.
- La fenêtre PapAI est exclue des captures et des clics. Une capture de plus de 30 secondes ne peut pas servir à un clic du proche.
- Un seul pilote à la fois : le proche ne prend la main que quand l'agent est suspendu.
- La personne accepte explicitement que PapAI regarde son écran, et c'est elle qui accepte ou refuse une session proposée par un proche.
- Les proches s'ajoutent par QR ou code à 6 chiffres, à usage unique ; toutes les routes en ligne sont protégées par une clé famille.

Gardien anti-arnaque
PapAI sait reconnaître les situations d'arnaque typiques à partir de trois signaux textuels, sans capture : un outil de prise en main qui tourne (AnyDesk, TeamViewer…), une fausse alerte « votre ordinateur est infecté », un site de carte prépayée, et surtout un outil de prise en main avec une page bancaire ouverte. La logique est écrite et testée (14 contrôles) ; son branchement sur l'app Mac est en cours. [R6 : si la PR #8 est fusionnée et essayée, remplacer la dernière phrase par « Le proche est prévenu, et Holo lui décrit ce qui est réellement à l'écran. »]

Limites connues
Les automatismes sont gardés sur une seule instance du serveur et disparaissent à un redéploiement ; le stockage durable est la prochaine étape. Les notifications de l'iPhone demandent que l'app soit ouverte (pas encore de push).
```

## Technologies

```
- Holo (H Company), modèle holo3-1-35b-a3b, via l'API compatible OpenAI d'H Company : plan, puis computer use (capture, clic, saisie, touches, défilement).
- Gladia : transcription française de la demande dictée, côté serveur (route /transcribe) ; reconnaissance vocale d'Apple en secours sur le Mac.
- App Mac de la personne aidée : Swift, SwiftUI, ScreenCaptureKit (capture sans la fenêtre PapAI), CGEvent (actions).
- App iPhone du proche : Swift, SwiftUI.
- Serveur : Python, FastAPI, WebSockets, sur Google Cloud Run.
- Développement avec des agents IA : Devin (Cognition) en sessions parallèles, Claude Code, [À COMPLÉTER : agents de cyp-cor et snarbe].
```

Tags éventuels : `computer use`, `accessibilité`, `seniors`, `aidants`, `sécurité`, `H Company`, `Holo`, `Gladia`, `Devin`.

## Prix sponsors visés

### Gladia (dictée)

```
Une personne de 81 ans tape lentement et fait des fautes. Dans PapAI, elle touche le micro et dit sa demande avec ses mots : « Je veux voir mes photos de Noël ». L'app Mac enregistre au plus 30 secondes, le serveur envoie l'audio à Gladia (API v2, français) et renvoie le texte à l'écran, où elle peut le relire avant d'envoyer. La clé Gladia reste sur le serveur, rien n'est écrit sur le disque. Si Gladia ne répond pas, le Mac transcrit lui-même avec la reconnaissance vocale d'Apple. La dictée est le premier geste de la démo.
```

Sources : `backend/voice.py`, `apps/mac/Sources/Dictation.swift`, `PROTOCOL.md` (« Dictée de la demande »).
Vérifié : Gladia en ligne sur Cloud Run, dictée de l'app Mac essayée par Quentin. Pas vérifié : le secours Apple en conditions réelles.

### Devin

```
Devin a travaillé sur PapAI comme un membre de l'équipe, en plusieurs sessions parallèles le 7 novembre, chacune sur sa branche et avec une réservation de fichiers dans AGENTS.md pour ne pas gêner les autres agents. Au 7 novembre à 18 h, il a écrit 33 des 64 commits de la branche principale, avec 5 pull requests fusionnées et 3 ouvertes :
- la page web du proche, refaite sur le modèle des apps macOS et iPhone : plan à valider, préciser ou refuser, écran en direct avec prise en main, alertes (PR #1) ;
- l'étape du plan en cours, du serveur jusqu'aux écrans du Mac et de l'iPhone (PR #3) ;
- la robustesse de la rédaction des automatismes : une réponse mal formée de Holo ne fait plus planter « Garder comme automatisme », et le proche est prévenu au lieu d'attendre en silence ; un faux Holo local pour tester sans clé (PR #4) ;
- un correctif de l'accueil Mac, compilé et essayé sur une machine macOS, et un test de bout en bout en une commande : serveur, Holo simulé, faux Mac et faux proche, 26 contrôles (PR #5) ;
- le pitch, la vidéo et ces textes de soumission (PR #2) ;
- en cours : l'app Windows (PR #7), le gardien anti-arnaque branché sur le Mac (PR #8), la fin du renommage CarePilot vers PapAI (PR #6).
```

Sources : journal d'`AGENTS.md`, `git log main` (auteur « Devin AI »), PR #1 à #8 de `Firfal/PapAI`.
Mettre à jour les chiffres et la liste « en cours » le jour J (`git log main --format=%an | sort | uniq -c`).

## Équipe

```
[À COMPLÉTER : prénom nom, rôle, lien (GitHub ou LinkedIn) pour chaque membre]
- Quentin Robert : [rôle]
- Théo [nom] : [rôle]
- [cyp-cor] : [rôle]
- [snarbe] : [rôle]
```

## Liens

| Lien | Valeur |
|---|---|
| Code | `https://github.com/Firfal/PapAI` [À VÉRIFIER : le dépôt est privé ; le rendre public ou donner l'accès au jury] |
| Vidéo de démo (2 min) | [À COMPLÉTER : lien YouTube ou Loom non répertorié] |
| Démo en ligne | à retirer : l'accès demande la clé famille, qui ne doit jamais être publiée |
| Slides | [À COMPLÉTER] |

## Vérifications avant d'envoyer

- [ ] Aucune clé (Holo, clé famille, Gladia) dans les textes, les liens ou les captures.
- [ ] Aucune capture d'un vrai écran personnel : seulement les écrans de démo.
- [ ] Chaque marque [R1] à [R6] traitée : retirée si l'essai a réussi, phrase supprimée sinon.
- [ ] Les `[À COMPLÉTER]` remplis, les chiffres Devin remis à jour.
- [ ] Le même texte envoyé sur Luma (14 h) et BuilderBase (14 h 30).
