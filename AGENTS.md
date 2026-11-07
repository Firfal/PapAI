# Agents IA : qui fait quoi

Plusieurs agents (Claude, Codex…) travaillent sur ce dépôt en même temps.
Ce fichier sert à ne pas se marcher dessus. **À lire avant de commencer, à mettre à jour avant de pousser.**

## Règles

1. **Une branche par agent et par chantier**, jamais de travail direct sur `main`.
2. **Réserver avant de toucher** : ajouter une ligne dans « En cours » avec la branche et les fichiers ou dossiers visés. Si un fichier est déjà réservé par un autre agent, se coordonner (ou attendre) au lieu de le modifier.
3. **Petits commits fréquents**, poussés sur la branche, pour que les autres voient l'avancée.
4. **À la fin** : déplacer la ligne dans « Journal », cocher la ToDo de l'équipe (`TODO.md`), mettre à jour `PROTOCOL.md` si un message serveur ↔ app change.
6. Avant de pousser, `git fetch` puis remettre sa branche à jour sur `main` : un autre agent a peut-être touché aux mêmes fichiers.
5. Le contrat entre le serveur et les apps est `PROTOCOL.md` : tout nouveau message y est décrit.

## En cours

| Agent | Branche | Chantier | Fichiers réservés | Depuis |
|---|---|---|---|---|
| _(personne pour l'instant)_ | | | | |

## Journal

| Date | Agent | Branche | Fait |
|---|---|---|---|
| 7 nov. | Claude | `parcours-onboarding` | Lancement sur Mac sans Xcode : `run_backend_mac.sh`, `apps/mac/scripts/build-mac-cli.sh` (swiftc + bundle + signature ad hoc). |
| 7 nov. | Claude | `parcours-onboarding` | Étapes 1-2 : accueil en 5 écrans (bienvenue, prénom, taille du texte, autorisations, proches), ajout d'un proche par QR ou code à 6 chiffres (`backend/family.py`, `/p/{code}`, `pair.html`), session proposée par le proche à accepter sur le Mac (`remote_request`). |
| 7 nov. | Claude | `parcours-onboarding` | Étapes 3 à 8 : écran de consentement, actions expliquées en phrases simples avec historique, question du proche, écran de fin avec retour auto à l'accueil, « Mes tutoriels » rafraîchi quand le proche valide une fiche (`lessons_changed`). |
| 7 nov. | Claude | `parcours-onboarding` | Branche remise à jour sur `main` : la dictée de l'équipe (Gladia) remplace la mienne, ma partie de ToDo est fusionnée dans le `TODO.md` de l'équipe. |
| 7 nov. | Claude | `main` | Parcours des étapes 1 à 8 fusionné dans `main` (tests gardien 14/14, protocole 9/9). Fichiers libérés. |
| 7 nov. | Devin | `devin/aidant-web-soin` | Page web de l'aidant (`helper.html`) en design « Soin » avec le logotype : carte du plan avec Valider, Préciser (champ de précision) et Refuser ; carte d'alerte (gardien, `automation_failed`) ; « Garder comme automatisme » seulement en fin de session. Essayée avec `faux_mac.py` et un faux Holo. Fichier libéré. |
| 7 nov. | Devin | `devin/aidant-web-soin` | Page aidant refaite sur le modèle des apps macOS/iPhone : en-tête, carte de demande menthe, plan en cartes numérotées, barre Valider / Préciser / Refuser en bas, feuilles de précision et de refus, écran en direct avec pause et prise en main (loupe ×3), fin de session et automatisme. Alertes visibles sur tous les écrans. Fichier libéré. |
| 7 nov. | Devin | `devin/1794069197-fiche-etapes-chaines` | Fiche : `draft_lesson()` accepte des étapes en chaînes ; en cas d'échec l'aidant reçoit `refused` (iPhone : bouton libéré). Faux Holo `tests/faux_holo.py`, contrôle « la fiche est rédigée » (protocole 10/10, gardien 14/14). Reste `helper.html` (réservé ailleurs) : gérer `refused` pendant la rédaction. Fichiers libérés. |
| 7 nov. | Devin | `devin/1794069172-pitch` | `docs/pitch.md` (script minuté de 2 min 30, découpage en 13 plans de la vidéo de 2 min calé sur la démo P0) et `docs/soumission.md` (titre, accroche, descriptions, technos, équipe et liens à compléter). Passages conditionnels marqués quand une case P0 ou P2 est encore ouverte. Fichiers libérés. |
| 7 nov. | Devin | `devin/etape-du-plan` | Étape du plan en cours : champ optionnel `plan_step` dans `status` (`PROTOCOL.md`, `backend/sessions.py`, `backend/agent.py`, argument `plan_step` des outils dans `carepilot_tools.py`, retiré avant l'envoi au Mac), affiché sur le Mac (`SessionView.swift`) et l'iPhone (`LiveViews.swift`). Swift non compilé (VM Linux). Tests gardien 14/14, protocole 12/12 avec un faux Holo. Fichiers libérés. |
| 7 nov. | Devin | `devin/1794069172-pitch` | `docs/pitch.md` (script minuté de 2 min 30, découpage en 13 plans de la vidéo de 2 min calé sur la démo P0) et `docs/soumission.md` (titre, accroche, descriptions, technos, équipe et liens à compléter). Passages conditionnels marqués quand une case P0 ou P2 est encore ouverte. Fichiers libérés. |
