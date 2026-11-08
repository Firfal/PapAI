# PapAI — to-do de l'équipe

Rendu : **dimanche 8 novembre, 14 h (Luma) et 14 h 30 (BuilderBase)**.
Mis à jour le 7 novembre à 18 h 30. Cochez au fur et à mesure et poussez.

## À lire avant de toucher au code (agents compris)

- **Avant de commencer, réservez vos fichiers dans [`AGENTS.md`](AGENTS.md)** (une branche par chantier), et notez-y ce que vous avez fait en finissant. C'est ce qui évite que deux agents modifient le même fichier.
- Le contrat serveur ↔ apps est dans [`PROTOCOL.md`](PROTOCOL.md). Un changement de message se fait là d'abord.
- **Règle produit, non négociable : rien ne bouge sur l'ordinateur sans plan validé par l'aidant, ou par le support quand il importe un automatisme.** Jamais de commande ni de script dans un automatisme. Le bouton Arrêter du Mac coupe tout, même hors ligne.
- Holo ne doit jamais cliquer dans une fenêtre d'autorisation du système ni dans les Réglages (`papai_tools.py`).
- Avant de pousser du code serveur, lancez les tests. Les deux doivent passer. Sans clé H Company : `python tests/faux_holo.py`, puis lancez le serveur avec `HOLO_BASE_URL=http://127.0.0.1:8999/v1/ HAI_API_KEY=stub-key`.
  - `python tests/test_gardien.py`
  - `python tests/test_automatismes.py` (automates importés, Holo simulé)
  - `python tests/test_protocole.py http://127.0.0.1:8000 demo` (avec un serveur local lancé)
- Serveur en ligne : Cloud Run, projet `papai-h42-ifiy5`, service `papai`, région `europe-west1`. Les routes passent par `/k/<clé famille>/…`. **La clé n'est jamais dans le dépôt** : demandez-la à Quentin.
- Redéployer : `gcloud run deploy papai --source . --project papai-h42-ifiy5 --region europe-west1 --quiet`. Les variables d'environnement sont conservées.
- Ne poussez jamais `.env`, `.papai-cloud`, ni de capture d'écran réelle d'un ordinateur.

## P0 — pour que la démo marche (ce soir)

- [ ] **Réinstaller les apps Mac et iPhone depuis `main`** : celles des appareils datent d'avant les PR #1 à #4. Compilées sur macOS depuis, mais pas encore lancées.
- [ ] **Répétition réelle sur le Mac** : demande → plan → précision → validation → Holo ouvre `Images/Noël 2025` → Arrêter. Trois fois de suite sans accroc.
  - [ ] Bloqué : Quentin doit cliquer « Autoriser » dans la fenêtre macOS « contourner le sélecteur de fenêtre privée » (enregistrement de l'écran de PapAI).
- [ ] **Vrais clics CGEvent** de l'app Mac (`apps/mac/Sources/Bridge.swift`) : jamais exercés en réel.
- [ ] **Bouton Arrêter** cliqué pendant une session active : vérifier qu'aucune action ne passe ensuite.
- [ ] **Automate** : « Garder comme automate » sur l'iPhone, puis rejeu depuis la tuile du Mac.
- [x] Fiche : des étapes renvoyées en simples chaînes ne font plus planter « Garder comme automatisme ». En cas d'échec, l'aidant reçoit `refused` et l'app iPhone libère le bouton. Faux Holo pour tester sans clé : `tests/faux_holo.py`.
- [x] Fiche : chaque étape est illustrée par une vraie capture d'écran de la session (Holo voit les captures pour rédiger ; si son choix n'est pas valable, le serveur prend la capture correspondante). Aucune illustration faite à la main.
- [x] Page web aidant (`helper.html`) : sur `refused`, réactiver le bouton « Garder comme automatisme » resté sur « Rédaction en cours… ».
- [ ] **Moment fort de la démo** : déplacer le dossier, rejouer, et vérifier que l'app s'arrête et que l'aidant reçoit l'alerte (`automation_failed`).
- [ ] **App iPhone sur l'appareil** : gestes réels (valider, préciser, refuser, prendre la main avec la loupe), notifications acceptées.
- [x] iPhone : glisser une étape vers la gauche → « Modifier » (feuille préremplie, consigne envoyée par `refine_plan`, Holo repropose, l'aidant valide). Dictée partout où l'aidant écrit (préciser, modifier, répondre à Holo) : Gladia par `/k/<clé>/transcribe`, SFSpeech en secours. Annuler dans chaque feuille, clavier bloqué pendant l'écoute, indice du glisser montré une fois. Essayé sur simulateur avec un fichier audio ; pas encore sur un vrai iPhone.
- [ ] Décider quel iPhone et quel Mac servent sur scène, et sur quel réseau. Garder l'app iPhone au premier plan : en arrière-plan, la connexion se coupe.

## Parcours de la personne aidée (app Mac, fusionné le 7 novembre)

- [x] 1. Accueil au premier lancement : bienvenue, prénom, taille du texte (grande par défaut), autorisations expliquées.
  - [x] Étape prénom Mac : « Revoir l'accueil » repart de la bienvenue (plus de prénom sauté), prénom des Réglages affiché aussitôt sur l'accueil.
- [x] 2. Ajouter un proche : QR ou code à 6 chiffres (10 min, usage unique), prénom et lien, plusieurs proches. Page `/p/{code}`, `backend/family.py`.
  - [x] Réglages Mac : section Mon support, Ajouter un support avec démarrage à la connexion, liste existante, QR/code/lien et copie confirmée ; partage SMS, WhatsApp ou mail, panneaux défilants en Très grande.
- [x] Session proposée à distance par le proche, que la personne aidée accepte ou refuse sur le Mac (`remote_request`).
- [x] 3. Demande : gros bouton, dictée (celle de l'équipe, Gladia) ou clavier.
  - [x] Accueil Mac voix d'abord : grand micro, écriture discrète, détection du micro, tutoriels masqués si vides, logotype et taille du texte dans l'encart.
  - [x] Mes raccourcis sur Mac : applications utilisées, dossiers et groupes de photos, nouveau message Mail, albums ajoutés à la main ; ajout/retrait local, dossiers validés et ouverts dans le Finder explicitement (#16). Cibles des automatismes sécurisées sur serveur/Mac/Windows : règle Unicode commune, refus des paquets et liens, ouverture Finder/Explorer ; cible affichée et retirable par l'aidant web. Vérifié sur la VM Mac (Noël 2025 ouvert, Facture.app refusé) et par tests Windows simulés. Retirés de l’accueil Mac le 8 nov. (simplification : barre de recherche, micro, automates).
- [x] 4. Consentement : écran dédié « PapAI va regarder votre écran » à la place de la case à cocher.
- [x] Accord de partage d'écran demandé une seule fois (Mac et Windows), gardé ensuite ; « Retirer l'accord de partage » dans Réglages.
- [x] 5. Holo explique chaque action en phrase simple, avec l'historique et le plan validé.
- [x] 6. Escalade : la question de Holo affichée pendant que le proche répond.
- [x] 7. Fin : « C'est fait ! », partage coupé, retour automatique à l'accueil.
- [x] 8. « Mes tutoriels » rafraîchi dès que le proche valide une fiche (`lessons_changed`).
- [x] « Quentin » n'est plus écrit en dur : l'app affiche le prénom du ou des proches ajoutés.
- [x] Page web aidant : valider, préciser ou refuser le plan (l'app iPhone le fait déjà).
- [x] Afficher quelle étape du plan est en cours : `status.plan_step` côté serveur, affiché sur le Mac et l'iPhone. Swift compilé sur macOS, pas encore lancé sur les appareils.
- [x] Fusionner `parcours-onboarding` dans `main`.

## Support informatique de niveau 1 (7 novembre au soir)

- [x] Automates importés par un support (`.papai`) : import et retrait (page aidant, `POST /k/CLÉ/automations`), actions de premier niveau, lancement en un clic sans validation à chaque fois, 7 exemples dans `automations/` (dont démos Wi-Fi, bloqueur de publicités, navigateur remis à zéro). Tests : `tests/test_automatismes.py` (40 contrôles) et `apps/windows/tests/test_windows_app.py`.
- [x] Plus de surveillance continue : les apps Mac et Windows n'envoient plus les signaux du gardien toutes les 8 s.
- [x] Protection en temps réel (8 nov., décision de Corentin) : le gardien reprend ses trois signaux textuels toutes les 8 s hors assistance, derrière l'interrupteur « Protection en temps réel » des Réglages Mac et Windows, activé par défaut et gardé ; coupé, rien ne part. L'état s'affiche sur la page du support. Profil Chrome PapAI effacé après chaque assistance, Holo demande à la personne de se connecter elle-même. Reste : Swift non compilé, pas essayé sur un vrai Mac ni un vrai Windows ; Android et iPhone n'affichent pas encore l'état.
- [ ] Compiler et essayer sur un Mac (`Automations` dans `Core.swift`) : modèles Word, page Imprimantes, Google via Holo.
- [ ] Essayer sur un vrai Windows : scan Defender (`MpCmdRun.exe`), modèles Word dans `%APPDATA%\Microsoft\Templates`, `ms-settings:printers`.
- [ ] Pitch et soumission : passer au support niveau 1, garder les grands-parents comme exemple.

## P1 — pitch et rendu (demain matin)

- [x] Script du pitch (2 à 3 min) et vidéo de 2 min : [`docs/pitch.md`](docs/pitch.md). Reste à tourner et monter la vidéo après la répétition P0.
- [x] Texte de soumission BuilderBase et Luma : [`docs/soumission.md`](docs/soumission.md). Reste à compléter l'équipe et les liens, puis à coller soi-même sur les plateformes.
- [ ] Captures propres des deux apps pour les slides (fenêtre PapAI, iPhone en validation).
- [ ] Logotype « papai » (papaye sur le i) dans les en-têtes des apps Mac et iPhone. Les sources sont dans `brand/` et le Figma.
- [x] Page web de secours de l'aidant (`backend/static/helper.html`) en design « Soin ».

## P2 — bonus, seulement si tout le P0 passe

- [x] Agent navigateur local de H pour les tâches web (`backend/web_agent.py`, Agents API) : `where` web/desktop dans le plan, mode web seulement si le Mac annonce `web_agent` ; session H créée après validation, `ask_helper`, pause/reprise, annulation sur arrêt/refus/alerte/déconnexion. Mac : Chrome PapAI (profil dédié) + `holo local browser` (`WebAgent.swift`, `apps/mac/scripts/install-agent-navigateur.sh`). Testé avec un faux Agents API (`tests/test_agent_navigateur.py`). Branche `devin/1794089468-agent-navigateur`, pas encore fusionnée.
- [ ] **Agent navigateur en réel** : clé H avec accès Agents API sur le Mac (`holo login`), puis « Ouvre le site de la météo de Paris » avec validation et Arrêter en cours d'action. Windows : brancher `web_agent.py` ensuite.
- [x] Gardien anti-arnaque (sans surveillance continue depuis le 7 nov. au soir : plus d'envoi périodique par les apps) : demandes/plans vérifiés, règles déterministes et avis Holo (si indisponible : attention au proche, plan à valider). Alerte Mac/iPhone/web et verrou Windows ; famille/session pour diffusion, accusé anonyme et rejet sans reprise. Fin Mac blanche avec consignes, lisible en Très grande ; fin web selon `execution_started` irréversible avant envoi d'action ; pas de Tout va bien sous alerte. Faux proche/téléphone perdu, factures habituelles ≤ 1 500 € sans autre signal, confirmation de virement sans montant, français/anglais/allemand, k€, codes et mots espacés/ponctués. 43 légitimes/70 suspectes, 22 tests règles/orchestration ; autres suites et 49 contrôles Windows simulés au vert. Builds Mac/iPhone après main : zéro erreur. UI Mac réel/iPhone simulé/web revérifiée ; après action = execute envoyé à un pont sûr simulé, sans geste OS. Captures/vidéo transmises. Branche `devin/1794084400-demandes-suspectes`, pas encore fusionnée. Reste : iPhone physique/reconnexion native, parcours normal natif avec capture, Windows natif, compatibilité ancien serveur en UI. Android attend la fusion de #23.
- [x] Voix : dicter la demande (micro de l'app Mac, Gladia puis secours Apple sur l'appareil). `GLADIA_API_KEY` est sur Cloud Run, transcription testée en ligne.
  - [x] Direct Gladia sur Mac/iPhone via relais WebSocket authentifié ; clé seulement serveur, Apple en secours, silence local et final HTTP conservés. Faux Gladia et client Swift testés (16 tests), builds Mac/iOS simulateur réussis ; affichage Mac vérifié avec audio synthétisé et final HTTP simulé, sans modifier l'accueil.
  - [ ] Essayer le direct avec la vraie clé Gladia (sur Cloud Run uniquement), le micro physique et le repli vers une reconnaissance Apple opérationnelle ; UI iPhone live non essayée.
  - [ ] Essayer la dictée sur le vrai Mac (autorisation du micro).
  - [ ] Entendre ce que fait Holo (synthèse vocale) : rien n'est codé.
- [ ] Rangement guidé des dossiers : plan de rangement validé par l'aidant, rien supprimé, tout annulable.
- [ ] Notification push quand l'app iPhone est fermée (APNs).
- [ ] Automatismes stockés de façon durable (aujourd'hui en mémoire du serveur : perdus au redémarrage).
- [x] App Windows au niveau du Mac pendant l'aide : Pause/Reprendre, question de Holo à la personne, avancement en 3 étapes, encart en bas à droite pendant que Holo agit, fin du gardien adaptée à l'aidé, dictée transmise à l'aidant. Reste : l'essayer sur un vrai Windows ; verrou souris/clavier pendant que Holo agit (`InputLock` du Mac) pas porté.
- [x] Version Windows de l'app de la personne aidée, design « Soin » de l'app Mac (`apps/windows`) : accueil voix d'abord, micro détecté à chaud, envoi après silence, logotype et raccourcis locaux sécurisés (4 dossiers personnels). Tests Windows app/serveur + faux Holo et rendu Chrome/Linux comparé au Mac vérifiés. Reste : l'essayer sur un vrai Windows (capture, clics, accents, exclusion de la fenêtre, dictée et branchement du micro).
- [x] Plusieurs espaces sur un même serveur : un par ordinateur aidé, créé au premier lancement (`POST /spaces`), code à 6 chiffres sans clé accepté sur l'ordinateur (`pair_confirm`). Tests : `tests/test_appairage_code.py`.
- [x] Apps du support : liste « Mes personnes aidées » (page web, Android, iPhone : une liaison par ordinateur, demandes des autres signalées).
- [x] Organisation IT : jeton d'inscription des postes (Windows `organisation.txt`, Mac `orgToken`), jeton support qui liste tous les postes (page `/o/<jeton>`, Android, iPhone), automatismes partagés. Tests : `tests/test_organisation.py`.
- [ ] Essayer l'inscription d'un vrai poste Windows et d'un vrai Mac avec un jeton d'organisation.
- [x] Support connecté d'office à l'organisation, liaison archivée : Mac (`supportToken`), iPhone (MDM, xcconfig local), Android (restrictions gérées), web (`/o/<jeton>`). Tests : `apps/mac/tests/support_org_test.swift`, `tests/test_helper_postes.js`.
- [ ] Essayer le support sur un vrai iPhone avec une configuration MDM (ou le xcconfig local) et sur un vrai Android avec restrictions gérées.
- [ ] Essayer « Mes personnes aidées » sur un vrai Android et un vrai iPhone (Swift non compilé ici).
- [ ] Plusieurs aidants : plusieurs proches s'ajoutent déjà et reçoivent tous la demande. Reste à éprouver « le premier disponible valide » avec deux aidants connectés.
- [x] Renommer `carepilot_tools.py` en `papai_tools.py` (fusionné le 7 novembre au soir).

## Fait

- [x] Serveur : plan proposé par Holo, puis précisé, validé ou refusé par l'aidant, avant toute action.
- [x] Serveur en ligne sur Cloud Run, protégé par la clé famille, testé de bout en bout à distance. Révision `papai-00007` avec les PR #1 à #4 ; la PR #5 (`tests/test_parcours.py`, message après refus sur la page web) est dans `main` après ce déploiement.
- [x] App Mac (SwiftUI) : connexion, capture sans sa propre fenêtre, plan affiché, Arrêter local, automatismes.
- [x] App iPhone (SwiftUI) : validation, précision, capture en direct, prise de main, automatisme. Testée sur simulateur et installée sur l'iPhone.
- [x] App Android de l'aidant (`apps/android/`, APK hors store) : mêmes écrans que l'iPhone, appairage QR/code/lien `papai://`, notifications. Lancée sur émulateur.
- [ ] App Android sur un vrai téléphone : installer l'APK, appairer, faire tout le parcours (plan, prise de main, automatisme), vérifier la notification écran éteint.
- [x] Gardien anti-arnaque (logique et 14 contrôles), banc d'essai du protocole (13 contrôles avec `tests/faux_holo.py`), parcours de bout en bout (`tests/test_parcours.py`, 26 contrôles), route de dictée (`tests/test_transcribe.py`), faux Mac.
- [x] Design « Soin », logo (logotype C) et mascotte papaye Pastel en icône des deux apps.
- [x] UX plus chaleureuse : mascotte Papaye et palette réchauffée sur Mac et iPhone, mascotte qui s'efface en petite fenêtre, iPhone hors connexion sans fausse assurance (PR #39). Reste : Windows et Android, essai VoiceOver, écran « Lancer une tâche » `.papi` à la place de « Mes tutoriels ».
- [x] Accueil Mac simplifié : barre de demande avec petit micro et « Mes automates » (automates existants, futurs `.papi`) à la place de « Mes tutoriels ». Reste : Windows, et l'import des `.papi` (#34).
- [x] Accueil Mac en deux colonnes (60/40) : barre de demande réduite puis « Mes automates » à gauche ; « Applications récentes » (6 dernières applications utilisées) au milieu à droite.
- [x] Notion du hackathon avec la base Features, mise à jour le 7 novembre à 18 h 30 selon l'état réel.
- [x] Tickets : chaque demande d'assistance suivie (numéro, statut, plan, fin), demande en attente quand aucun support n'est là, personne reprévenue dès qu'un support arrive, rendez-vous et rappel ; onglet Tickets de l'organisation (filtres, CSV) et liste sur la page du support (`tests/test_tickets.py`).
- [ ] Tickets dans les apps Android et iPhone du support (aujourd'hui : page web seulement).
