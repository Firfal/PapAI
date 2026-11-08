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

- [x] Couper les images et les états d'une autre assistance sur les liens de session terminée (fin normale, Arrêter, refus du plan, alerte, déconnexion), sans fermer le socket nécessaire à la rédaction de l'automate ; reconnexion sans image, réponse finale de sa propre assistance conservée. Test de non-régression : 21 contrôles réussis.
- [x] **Abonnement entreprise Stripe (mode test seulement)** : page Abonnement liée à la console, prix par poste, Checkout, portail et webhook signé ; stockage séparé de l'organisation, aucun blocage sans abonnement. Faux Stripe local, 5 tests OK ; suites serveur comparées à main sans nouvel échec. Paiement réel et interface à l'écran non vérifiés.
- [ ] **Réinstaller les apps Mac et iPhone depuis `main`** : celles des appareils datent d'avant les PR #1 à #4. Compilées sur macOS depuis, mais pas encore lancées.
- [ ] **Répétition réelle sur le Mac** : demande → plan → précision → validation → Holo ouvre `Documents/Comptabilité 2025` → Arrêter. Trois fois de suite sans accroc.
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

- [x] Bascule vers Linkup pour les questions complexes (`devin/1794127230-linkup`) : clé serveur facultative, recherche sourcée, cartes support iPhone/Mac/web/Android, correction et validation obligatoire, réponse et sources Mac/Windows et ticket web. Mac et iOS simulateur compilés ; Linkup 22, Windows unittest 44 et Node helper/tickets 2 réussis. Essai réel HP/Sonoma : réponse française, 10 sources, validation support et conservation au ticket vérifiées. httpx épinglé et import en venv neuf réussi. Restent l’essai visuel, Android (téléchargement Gradle HTTP 504 et SDK absent) ; test Windows d’invitation bloqué par qrcode absent du venv Mac.

- [x] Automates importés par un support (`.papai`) : import et retrait (page aidant, `POST /k/CLÉ/automations`), actions de premier niveau, lancement en un clic sans validation à chaque fois, 7 exemples dans `automations/` (dont démos Wi-Fi, bloqueur de publicités, navigateur remis à zéro). Tests : `tests/test_automatismes.py` (40 contrôles) et `apps/windows/tests/test_windows_app.py`.
- [x] Automates autonomes : pas de « le support s'en occupe », bouton discret « Demander une assistance » en haut à droite (Mac, Windows), étape bloquante gardée sur le ticket (`blocked`). Reste : afficher `blocked` et le bouton sur l'iPhone et Android, compiler et essayer à l'écran sur Mac.
- [ ] Charger les 7 exemples d'automates dans un nouvel espace (aujourd'hui il faut les importer à la main). Touche `backend/space.py`, réservé par Devin (multi-espaces).
- [x] Réglages Mac : sans taille du texte, sans changement de rôle, sans lien de parenté (`claude/reglages-connexion`).
- [x] Accueil support Mac : onglets Tickets (tous les utilisateurs), Utilisateurs, Mes automates (`claude/support-tickets`). Reste : même organisation sur l'iPhone et Android.
- [x] Plus de création d'automate « à partir de rien » côté support (décision de Corentin, 8 nov.) : enregistrement d'écran avec voix, import de document, création à la main et `POST /automations/draft` retirés. Un automate naît d'un ticket réglé, proposé quand une demande revient (chantier catégories des tickets).
- [x] Mode support Mac : « Mes automates » (bibliothèque du support, appliquer à des personnes), création à la main, depuis un document ou un enregistrement d'écran avec voix (`claude/support-automates`).
  - [ ] Porter « Mes automates » sur l'iPhone et Android.
- [x] Plus de surveillance continue : les apps Mac et Windows n'envoient plus les signaux du gardien toutes les 8 s.
- [x] Protection en temps réel (8 nov., décision de Corentin) : le gardien reprend ses trois signaux textuels toutes les 8 s hors assistance, derrière l'interrupteur « Protection en temps réel » des Réglages Mac et Windows, activé par défaut et gardé ; coupé, rien ne part. L'état s'affiche sur la page du support. Profil Chrome PapAI effacé après chaque assistance, Holo demande à la personne de se connecter elle-même. Reste : Swift non compilé, pas essayé sur un vrai Mac ni un vrai Windows ; Android et iPhone n'affichent pas encore l'état.
- [ ] Compiler et essayer sur un Mac (`Automations` dans `Core.swift`) : modèles Word, page Imprimantes, Google via Holo.
- [ ] Essayer sur un vrai Windows : scan Defender (`MpCmdRun.exe`), modèles Word dans `%APPDATA%\Microsoft\Templates`, `ms-settings:printers`.
- [x] Chantier 4, textes entreprise actualisés après #90 (8 nov., 10 h 22 UTC) : `README.md` et `docs/soumission.md` recentrés sur Christine et le support IT ; quinze chantiers vérifiés dans main `b905883`, mentions de PR en attente retirées. Fusion à deux parents (pas un squash) explicitée ; 781 commits dont 618 sous les identités Git de Devin, 68 PR fusionnées dont 60 de Devin ; 39 PR de Devin du 8 novembre listées avec auteur et état réel (25 fusionnées, 11 ouvertes, trois fermées sans fusion). Blocs à copier conservés.
- [ ] Avant soumission : refaire le relevé si main ou les états GitHub évoluent ; compléter l'équipe et les liens, puis copier sur les plateformes. Pitch hors de ce chantier, non retouché.

## P1 — pitch et rendu (demain matin)

- [x] Script du pitch (2 à 3 min) et vidéo de 2 min : [`docs/pitch.md`](docs/pitch.md). Reste à tourner et monter la vidéo après la répétition P0.
- [x] Texte de soumission BuilderBase et Luma : [`docs/soumission.md`](docs/soumission.md). Reste à compléter l'équipe et les liens, puis à coller soi-même sur les plateformes.
- [ ] Captures propres des deux apps pour les slides (fenêtre PapAI, iPhone en validation).
- [ ] Logotype « papai » (papaye sur le i) dans les en-têtes des apps Mac et iPhone. Les sources sont dans `brand/` et le Figma.
- [x] Page web de secours de l'aidant (`backend/static/helper.html`) en design « Soin ».

## P2 — bonus, seulement si tout le P0 passe

- [x] Agent navigateur local de H pour les tâches web (`backend/web_agent.py`, Agents API) : `where` web/desktop dans le plan, mode web seulement si le Mac annonce `web_agent` ; session H créée après validation, `ask_helper`, pause/reprise, annulation sur arrêt/refus/alerte/déconnexion. Mac : Chrome PapAI (profil dédié) + `holo local browser` (`WebAgent.swift`, `apps/mac/scripts/install-agent-navigateur.sh`). Testé avec un faux Agents API (`tests/test_agent_navigateur.py`). Branche `devin/1794089468-agent-navigateur`, pas encore fusionnée.
- [ ] **Agent navigateur en réel** : clé H avec accès Agents API sur le Mac (`holo login`), puis « Ouvre le site de la météo de Paris » avec validation et Arrêter en cours d'action. Windows : brancher `web_agent.py` ensuite.
- [x] **Agent navigateur limité aux sites validés** (8 nov.) : règle URL partagée serveur/Mac/Windows, surveillance CDP Mac, pause H et question au support en cas de sortie, autorisation d'un hôte exact pour l'assistance ou arrêt ; journaux hors-site sans URL complète. Tests navigateur 63, sites 162, Swift 77, surveillant Windows simulé 7, parcours 27, sécurité 35, gardien 14 et build Mac réussis. Vrai Chrome + harnais Swift : Wikipédia autorisé, example.com et redirection vers Wikimedia signalés, about:blank neutre ; profil effacé. Pas de vraie assistance H faute de clé, Windows non branché et non essayé sur Windows natif. Mode web pur non surveillé ; surveillance a posteriori ~0,5 s, pas un filtrage réseau.
- [x] Gardien anti-arnaque (sans surveillance continue depuis le 7 nov. au soir : plus d'envoi périodique par les apps) : demandes/plans vérifiés, règles déterministes et avis Holo (si indisponible : attention au proche, plan à valider). Alerte Mac/iPhone/web et verrou Windows ; famille/session pour diffusion, accusé anonyme et rejet sans reprise. Fin Mac blanche avec consignes, lisible en Très grande ; fin web selon `execution_started` irréversible avant envoi d'action ; pas de Tout va bien sous alerte. Faux proche/téléphone perdu, factures habituelles ≤ 1 500 € sans autre signal, confirmation de virement sans montant, français/anglais/allemand, k€, codes et mots espacés/ponctués. 43 légitimes/70 suspectes, 22 tests règles/orchestration ; autres suites et 49 contrôles Windows simulés au vert. Builds Mac/iPhone après main : zéro erreur. UI Mac réel/iPhone simulé/web revérifiée ; après action = execute envoyé à un pont sûr simulé, sans geste OS. Captures/vidéo transmises. Branche `devin/1794084400-demandes-suspectes`, pas encore fusionnée. Reste : iPhone physique/reconnexion native, parcours normal natif avec capture, Windows natif, compatibilité ancien serveur en UI. Android attend la fusion de #23.
- [x] Voix : dicter la demande (micro de l'app Mac, Gladia puis secours Apple sur l'appareil). `GLADIA_API_KEY` est sur Cloud Run, transcription testée en ligne.
  - [x] Direct Gladia sur Mac/iPhone via relais WebSocket authentifié ; clé seulement serveur, Apple en secours, silence local et final HTTP conservés. Faux Gladia et client Swift testés (16 tests), builds Mac/iOS simulateur réussis ; affichage Mac vérifié avec audio synthétisé et final HTTP simulé, sans modifier l'accueil.
  - [ ] Essayer le direct avec la vraie clé Gladia (sur Cloud Run uniquement), le micro physique et le repli vers une reconnaissance Apple opérationnelle ; UI iPhone live non essayée.
  - [ ] Essayer la dictée sur le vrai Mac (autorisation du micro).
  - [x] Entendre ce que fait Holo : narration locale française Mac (AVSpeechSynthesizer) et Windows (voix locale WebView), réglage « Lire à voix haute » activé par défaut, file sans doublons par assistance et coupure pendant dictée/pause/arrêt/alerte/déconnexion. PR #82 : logique Swift/Windows et compilation Mac réussies.
    - [ ] Vérifier à l'écran et à l'écoute sur un Mac et sur Windows natif/WebView2 avec une voix française installée, ainsi que la coupure pendant une vraie dictée au micro.
- [ ] Rangement guidé des dossiers : plan de rangement validé par l'aidant, rien supprimé, tout annulable.
- [x] Rangement guidé des dossiers (Mac) : plan des déplacements validé par le support, noms de fichiers seulement, rien supprimé ni écrasé, « Annuler le rangement ».
- [ ] Rangement guidé des dossiers sur Windows.
- [ ] Notification push quand l'app iPhone est fermée (APNs).
- [x] Automatismes stockés de façon durable (stockage local ou Firestore via `backend/storage.py` ; plus perdus au redémarrage).
- [x] App Windows au niveau du Mac pendant l'aide : Pause/Reprendre, question de Holo à la personne, avancement en 3 étapes, encart en bas à droite pendant que Holo agit, fin du gardien adaptée à l'aidé, dictée transmise à l'aidant. Reste : l'essayer sur un vrai Windows ; verrou souris/clavier pendant que Holo agit écarté pour l'instant (décision de Corentin, voir `AGENTS.md`).
- [x] Stockage durable : interface unique disque local / Firestore + Cloud Storage pour les automates, espaces, organisations, supports et tickets ; migration idempotente sans suppression de la source (`scripts/migrer_stockage.py`, `--dry-run` sans accès Cloud), 14 tests avec doubles. Disposition historique conservée par défaut (`PAPAI_STORAGE=local`). Cible : `PAPAI_STORAGE=firestore`, `PAPAI_FIRESTORE_COLLECTION` (défaut `papai`), `GOOGLE_CLOUD_PROJECT` et, pour les images, `PAPAI_GCS_BUCKET` ; identifiants par défaut du compte de service, aucun secret dans les fichiers.
- [ ] activer Firestore en production (Quentin) : attribuer les droits Firestore/Cloud Storage au compte de service, simuler puis exécuter la migration depuis le disque source conservé, vérifier avant de basculer. Firestore/GCS réels jamais appelés pendant ce chantier.
- [x] Version Windows de l'app de la personne aidée, design « Soin » de l'app Mac (`apps/windows`) : accueil voix d'abord, micro détecté à chaud, envoi après silence, logotype et raccourcis locaux sécurisés (4 dossiers personnels). Tests Windows app/serveur + faux Holo et rendu Chrome/Linux comparé au Mac vérifiés. Reste : l'essayer sur un vrai Windows (capture, clics, accents, exclusion de la fenêtre, dictée et branchement du micro).
- [x] Plusieurs espaces sur un même serveur : un par ordinateur aidé, créé au premier lancement (`POST /spaces`), code à 6 chiffres sans clé accepté sur l'ordinateur (`pair_confirm`). Tests : `tests/test_appairage_code.py`.
- [x] Apps du support : liste « Mes personnes aidées » (page web, Android, iPhone : une liaison par ordinateur, demandes des autres signalées).
- [x] Organisation IT : jeton d'inscription des postes (Windows `organisation.txt`, Mac `orgToken`), jeton support qui liste tous les postes (page `/o/<jeton>`, Android, iPhone), automatismes partagés. Tests : `tests/test_organisation.py`.
- [ ] Essayer l'inscription d'un vrai poste Windows et d'un vrai Mac avec un jeton d'organisation.
- [x] Support connecté d'office à l'organisation, liaison archivée : Mac (`supportToken`), iPhone (MDM, xcconfig local), Android (restrictions gérées), web (`/o/<jeton>`). Tests : `apps/mac/tests/support_org_test.swift`, `tests/test_helper_postes.js`.
- [x] Android après le pivot (`devin/1794128283-android-pivot`, contient #72) : compilé, 26 tests JVM, jeton personnel du support (#77) et clé dérivée acceptés, accès retiré (4401/4403) sans reconnexion en boucle ; parcours joué sur émulateur contre un serveur local (postes, demande, plan à valider, en cours, fin, demande d'un autre poste).
- [ ] Essayer le support sur un vrai iPhone avec une configuration MDM (ou le xcconfig local) et sur un vrai Android avec restrictions gérées.
- [x] Un jeton par support, révocable (C1, #51) : la console `/o/<jeton org>` crée un lien par support et le retire (sockets fermées aussitôt, assistance validée par lui arrêtée, jeton et clés dérivées refusés), renouvelle le jeton de l'organisation ; le journal dit quel support a validé chaque plan. Tests : `tests/test_supports_revocables.py`.
- [ ] Apps du support (iPhone, Mac support, Android) : afficher « Accès retiré » à la fermeture 4401 au lieu de se reconnecter en boucle (non fait, Swift non compilé ici).
- [ ] Une fois chaque support passé à son lien personnel : renouveler le jeton de l'organisation (`POST /o/<jeton>/rotate`) pour couper l'ancien lien partagé.
- [ ] Essayer « Mes personnes aidées » sur un vrai Android et un vrai iPhone (Swift non compilé ici).
- [ ] Plusieurs aidants : plusieurs proches s'ajoutent déjà et reçoivent tous la demande. Reste à éprouver « le premier disponible valide » avec deux aidants connectés.
- [x] Renommer `carepilot_tools.py` en `papai_tools.py` (fusionné le 7 novembre au soir).

## Fait

- [x] `main` au vert : `tests/test_appairage_code.py` (et donc organisation, tickets, protection qui l'importent) et `tests/test_actions_sensibles.py` attendaient encore « la personne aidée » ; alignés sur le lexique « utilisateur » du serveur.
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
- [x] Tickets : pendant l'attente d'un support, proposer jusqu'à deux automates de l'organisation ou de l'espace ; lancement suivi sur le ticket et indiqué à l'utilisateur sur Windows/Mac et au support sur le web/Mac (`tests/test_suggestions.py`, `tests/test_tickets.py`).
- [x] Pas de ticket en double : une demande déjà ouverte est signalée à l'utilisateur, une demande déjà réglée renvoie vers sa solution (mot du support, étapes), avec « Refaire avec Holo » qui rouvre le même ticket (serveur, Windows, Mac ; `tests/test_tickets.py`).
- [x] Mes demandes, serveur : `GET /k/<clé>/requests`, 100 demandes du poste en lecture seule, solution texte et automate relançable seulement si résolu et encore disponible ; clés dérivées du support refusées (`tests/test_mes_demandes.py`).
- [x] Mes demandes Windows : accès discret depuis l'accueil, feuille lecture seule (dates, états, automate/plan/réponse et sources texte), chargement à l'ouverture et sur `tickets_changed`, relance via le lancement existant si automate disponible, feuille fermée avant lancement. Démo `?demo=requests`, tests modèle et UI, captures Chrome regardées ; Windows natif non essayé.
- [x] Mes demandes Mac : même feuille SwiftUI lecture seule près de Réglages, chargement URLSession, décodage tolérant, relance par le chemin existant après fermeture. Démo `PAPAI_DEMO=requests`, 22 contrôles Swift, builds Xcode/CLI et captures regardées ; liste réelle et relance essayées contre serveur local. `tickets_changed` traité si reçu, mais actuellement diffusé au support seulement par le serveur.
- [ ] Tickets dans les apps Android et iPhone du support (aujourd'hui : page web seulement).
  - [x] iPhone : accueil du support en trois onglets comme sur Mac (Tickets de tous les utilisateurs avec Ouverts/Tous, Prendre en charge / Clore / Rouvrir / Voir l’utilisateur ; Utilisateurs ; Mes automates avec import `.papai` et « Appliquer… »), palette du Mac (`devin/1794129480-iphone-support-onglets`). Essayé sur simulateur.
  - [x] « Appliquer… » à toute une organisation d'un coup (iPhone et Mac), y compris les postes qui la rejoindront (`devin/1794129480-iphone-support-onglets`).
  - [ ] Android.
- [x] Gardien d'entreprise : faux support, fausse alerte virus, hameçonnage web ; comparaison sur l'ordinateur, rien ne part sans correspondance ; domaines et outils déclarés par l'IT (`/o/<jeton>/security`) ; avertissement non bloquant hors assistance ; ticket « Sécurité » (`tests/test_gardien*.py`). Reste : bouton « Ce mail est-il fiable ? », liste de sites malveillants, réglage dans la page de l'organisation, compiler le Swift, essai sur vrai Windows.
- [x] Automates sans Holo disponibles hors ligne sur Mac et Windows (liste gardée sur l'ordinateur, sans Holo ni fichier du serveur). Les images du « Montrez-moi » restent sur le serveur.
- [x] Tickets par catégorie (Wi-Fi et réseau, imprimante, comptes et mots de passe, logiciels, messagerie, fichiers, sécurité, autre) : règles, Holo en cas de doute, correction par le support ; statistiques par catégorie et par semaine, temps de résolution, part réglée par un automate, exemples cliquables, suggestion d'automate préremplie ; web (organisation et page du support) et onglet Tickets du Mac support (`devin/1794127200-tickets-categories`, `tests/test_ticket_categories.py`). Reste : iPhone et Android ; suggestion à refaire à partir des tickets réglés sur un même sujet (règles dans AGENTS.md, « Décisions produit »), d'ici là le bouton « Créer l’automate » du Mac est masqué (`TicketStatsPanel.canCreate`, aussi pour la carte « Cette semaine »).
- [x] Point de la semaine pour le support : carte « Cette semaine » (demandes reçues, réglées, part réglée par un automate, temps moyen, 3 catégories en tête, automate le plus utile, suggestion d'automate) dans la console de l'organisation et en tête de l'onglet Tickets du Mac support ; champ `week` des statistiques de #86, rien par mail (`devin/1794132846-point-semaine`, `tests/test_point_semaine.py`). Reste : iPhone, Android et page du support `helper.html` ; le panneau des statistiques ne répète plus la suggestion de la carte, ni sur la console (`skipCategory`) ni sur le Mac (`panelSuggestions`).
