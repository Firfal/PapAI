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
| Devin | `devin/1794069197-fiche-etapes-chaines` | Fiche : étapes en chaînes, erreur renvoyée à l'aidant | `backend/caremamory.py`, `backend/app.py` (branche `draft_lesson`), `apps/ios/Sources/HelperModel.swift` (cas `refused`), `tests/test_protocole.py`, `tests/faux_holo.py` | 7 nov. |

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
