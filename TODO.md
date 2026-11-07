# PapAI — to-do de l'équipe

Rendu : **dimanche 8 novembre, 14 h (Luma) et 14 h 30 (BuilderBase)**.
Mis à jour le 7 novembre à 16 h 30. Cochez au fur et à mesure et poussez.

## À lire avant de toucher au code (agents compris)

- **Avant de commencer, réservez vos fichiers dans [`AGENTS.md`](AGENTS.md)** (une branche par chantier), et notez-y ce que vous avez fait en finissant. C'est ce qui évite que deux agents modifient le même fichier.
- Le contrat serveur ↔ apps est dans [`PROTOCOL.md`](PROTOCOL.md). Un changement de message se fait là d'abord.
- **Règle produit, non négociable : rien ne bouge sur l'ordinateur sans plan validé par l'aidant.** Le bouton Arrêter du Mac coupe tout, même hors ligne.
- Holo ne doit jamais cliquer dans une fenêtre d'autorisation du système ni dans les Réglages (`carepilot_tools.py`).
- Avant de pousser du code serveur, lancez les tests. Les deux doivent passer.
  - `python tests/test_gardien.py`
  - `python tests/test_protocole.py http://127.0.0.1:8000 demo` (avec un serveur local lancé)
- Serveur en ligne : Cloud Run, projet `papai-h42-ifiy5`, service `papai`, région `europe-west1`. Les routes passent par `/k/<clé famille>/…`. **La clé n'est jamais dans le dépôt** : demandez-la à Quentin.
- Redéployer : `gcloud run deploy papai --source . --project papai-h42-ifiy5 --region europe-west1 --quiet`. Les variables d'environnement sont conservées.
- Ne poussez jamais `.env`, `.papai-cloud`, ni de capture d'écran réelle d'un ordinateur.

## P0 — pour que la démo marche (ce soir)

- [ ] **Répétition réelle sur le Mac** : demande → plan → précision → validation → Holo ouvre `Images/Noël 2025` → Arrêter. Trois fois de suite sans accroc.
  - [ ] Bloqué : Quentin doit cliquer « Autoriser » dans la fenêtre macOS « contourner le sélecteur de fenêtre privée » (enregistrement de l'écran de PapAI).
- [ ] **Vrais clics CGEvent** de l'app Mac (`apps/mac/Sources/Bridge.swift`) : jamais exercés en réel.
- [ ] **Bouton Arrêter** cliqué pendant une session active : vérifier qu'aucune action ne passe ensuite.
- [ ] **Automatisme** : « Garder comme automatisme » sur l'iPhone, puis rejeu depuis la tuile du Mac.
- [ ] **Moment fort de la démo** : déplacer le dossier, rejouer, et vérifier que l'app s'arrête et que l'aidant reçoit l'alerte (`automation_failed`).
- [ ] **App iPhone sur l'appareil** : gestes réels (valider, préciser, refuser, prendre la main avec la loupe), notifications acceptées.
- [ ] Décider quel iPhone et quel Mac servent sur scène, et sur quel réseau. Garder l'app iPhone au premier plan : en arrière-plan, la connexion se coupe.

## Parcours de la personne aidée (app Mac, fusionné le 7 novembre)

- [x] 1. Accueil au premier lancement : bienvenue, prénom, taille du texte (grande par défaut), autorisations expliquées.
- [x] 2. Ajouter un proche : QR ou code à 6 chiffres (10 min, usage unique), prénom et lien, plusieurs proches. Page `/p/{code}`, `backend/family.py`.
- [x] Session proposée à distance par le proche, que la personne aidée accepte ou refuse sur le Mac (`remote_request`).
- [x] 3. Demande : gros bouton, dictée (celle de l'équipe, Gladia) ou clavier.
- [x] 4. Consentement : écran dédié « PapAI va regarder votre écran » à la place de la case à cocher.
- [x] 5. Holo explique chaque action en phrase simple, avec l'historique et le plan validé.
- [x] 6. Escalade : la question de Holo affichée pendant que le proche répond.
- [x] 7. Fin : « C'est fait ! », partage coupé, retour automatique à l'accueil.
- [x] 8. « Mes tutoriels » rafraîchi dès que le proche valide une fiche (`lessons_changed`).
- [x] « Quentin » n'est plus écrit en dur : l'app affiche le prénom du ou des proches ajoutés.
- [x] Page web aidant : valider, préciser ou refuser le plan (l'app iPhone le fait déjà).
- [ ] Afficher quelle étape du plan est en cours (demande un champ côté serveur).
- [x] Fusionner `parcours-onboarding` dans `main`.

## P1 — pitch et rendu (demain matin)

- [x] Script du pitch (2 à 3 min) et vidéo de 2 min : [`docs/pitch.md`](docs/pitch.md). Reste à tourner et monter la vidéo après la répétition P0.
- [x] Texte de soumission BuilderBase et Luma : [`docs/soumission.md`](docs/soumission.md). Reste à compléter l'équipe et les liens, puis à coller soi-même sur les plateformes.
- [ ] Captures propres des deux apps pour les slides (fenêtre PapAI, iPhone en validation).
- [ ] Logotype « papai » (papaye sur le i) dans les en-têtes des apps Mac et iPhone. Les sources sont dans `brand/` et le Figma.
- [x] Page web de secours de l'aidant (`backend/static/helper.html`) en design « Soin ».

## P2 — bonus, seulement si tout le P0 passe

- [ ] Gardien anti-arnaque : brancher la détection (`backend/guard.py`) sur l'écran de l'aîné et l'alerte iPhone. La logique est déjà testée.
- [x] Voix : dicter la demande (micro de l'app Mac, Gladia puis secours Apple sur l'appareil). Reste : entendre ce que fait Holo ; `GLADIA_API_KEY` à mettre sur Cloud Run.
- [ ] Rangement guidé des dossiers : plan de rangement validé par l'aidant, rien supprimé, tout annulable.
- [ ] Notification push quand l'app iPhone est fermée (APNs).
- [ ] Automatismes stockés de façon durable (aujourd'hui en mémoire du serveur : perdus au redémarrage).
- [ ] Version Windows de l'app de la personne aidée (le prototype est dans la branche `archive/windows-7-nov`).

## Fait

- [x] Serveur : plan proposé par Holo, puis précisé, validé ou refusé par l'aidant, avant toute action.
- [x] Serveur en ligne sur Cloud Run, protégé par la clé famille, testé de bout en bout à distance.
- [x] App Mac (SwiftUI) : connexion, capture sans sa propre fenêtre, plan affiché, Arrêter local, automatismes.
- [x] App iPhone (SwiftUI) : validation, précision, capture en direct, prise de main, automatisme. Testée sur simulateur et installée sur l'iPhone.
- [x] Gardien anti-arnaque (logique et 14 contrôles), banc d'essai du protocole (9 contrôles), faux Mac.
- [x] Design « Soin », logo (logotype C) et mascotte papaye Pastel en icône des deux apps.
- [x] Notion du hackathon avec la base Features.
