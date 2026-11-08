# PapAI pour Windows

L'app de l'employé, avec les mêmes écrans d'assistance et le même design « Soin »
que l'app Mac (`apps/mac`). Elle parle au même serveur, par le pont `/ws/bridge`
(voir `PROTOCOL.md`), et s'annonce avec `{"type":"hello","os":"windows"}`.

**Poste d'entreprise, sans aucun réglage côté employé.** L'app s'ouvre directement
sur l'accueil, « Bonjour <prénom> » tiré du compte Windows. Le support IT est rattaché
par les stratégies de groupe du poste : pas d'accueil en étapes, pas de saisie du
prénom, pas de liaison par QR code, code à 6 chiffres ou lien d'invitation. Une
demande de liaison reçue du serveur (`pair_confirm`) est refusée d'office. La version
« particuliers » complète reste dans la branche `archive/particuliers`.

## Configurer un poste (service informatique)

L'app lit `SOFTWARE\Policies\PapAI`, d'abord dans `HKEY_LOCAL_MACHINE` (stratégie
ordinateur, prioritaire), puis dans `HKEY_CURRENT_USER` (stratégie utilisateur).
Valeurs, toutes de type `REG_SZ` :

| Valeur | Rôle | Sans elle |
|---|---|---|
| `OrgToken` | jeton d'inscription `ins-…` (`enroll_token` de `POST /orgs`) : le poste rejoint seul l'organisation | aucune organisation : Réglages > Mon support affiche « contactez votre service informatique » |
| `Server` | adresse du serveur PapAI, `https://…` (ou `wss://…/ws/bridge`) ; un poste déjà inscrit ailleurs crée son espace sur celui-ci | serveur PapAI officiel |
| `DisplayName` | nom complet de l'employé ; l'app dit bonjour avec le premier mot | nom complet du compte Windows (`GetUserNameExW(NameDisplay)`), sinon identifiant de connexion (`jean.dupont` donne « Jean ») |
| `Role` | service ou fonction (« Comptabilité »), montré au support avec le nom | rien |

Le support IT voit le poste sous « <nom complet> · <service> · <nom de l'ordinateur> »,
et le prénom dans ses demandes.

- **Console de stratégies de groupe** : copier `policies/PapAI.admx` dans
  `PolicyDefinitions` (magasin central `\\<domaine>\SYSVOL\<domaine>\Policies\PolicyDefinitions`
  ou `C:\Windows\PolicyDefinitions`) et `policies/fr-FR/PapAI.adml` dans son sous-dossier
  `fr-FR`. Les réglages apparaissent dans *Modèles d'administration > PapAI*, côté
  ordinateur et côté utilisateur. Seule la langue fr-FR est fournie : une console dans
  une autre langue ne montre pas les libellés.
- **Sans console** : `policies/PapAI-exemple.reg`, à compléter puis `reg import` en
  administrateur. Ou en une ligne :
  `reg add HKLM\SOFTWARE\Policies\PapAI /v OrgToken /t REG_SZ /d ins-… /f`.
- **Essais** (repli quand aucune stratégie n'est posée) : `organisation.txt` à côté de
  `PapAI.bat` (ignoré par git) ou variable `PAPAI_ORG`. Hors Windows, le registre n'est
  jamais lu : les tests passent par ces replis.

## Lancer sur Windows 10 ou 11

Depuis le dépôt (cloné ou téléchargé), double-cliquer `apps\windows\PapAI.bat`.
Rien à installer : au premier lancement, il récupère un Python portable et les
dépendances dans `apps\windows\.python` (une minute environ, il faut Internet),
puis ouvre PapAI. Les lancements suivants sont immédiats. Si Windows affiche
« Windows a protégé votre ordinateur » : Informations complémentaires > Exécuter
quand même. Pour repartir de zéro, supprimer le dossier `.python`.

Avec un Python déjà installé sur le PC : `install.bat` (crée un `.venv`), puis `run.bat`.

Au premier lancement, l'app crée son espace (`POST /spaces`, avec le jeton de
l'organisation) sur le serveur de la stratégie `Server`, sinon sur le serveur PapAI
officiel, et garde l'adresse reçue, clé comprise. Pour viser directement un pont
(démo : `ws://localhost:8000/ws/bridge`), variable `PAPAI_SERVER` avant `PapAI.bat`.
Les Réglages n'ont plus ni prénom ni serveur : taille du texte, protection en temps
réel, accord de partage, et « Mon support » en lecture seule (« Support IT · Acme »,
en ligne ou non).

En ligne de commande : `.python\python -m papai` (avec `PAPAI_DEBUG=1`
pour les outils de développement de WebView2).

### Essayer sans clé H Company

Sur la machine du serveur (depuis la racine du dépôt) :

```bash
python tests/faux_holo.py
HOLO_BASE_URL=http://127.0.0.1:8999/v1/ HAI_API_KEY=stub-key PAPAI_AIDANT_KEY=demo python -m backend.app
```

Puis lancer l'app Windows, et ouvrir la page aidant `http://<serveur>:8000/a/demo`.

## Technologie : Python + pywebview (WebView2)

- **Rendu le plus proche de SwiftUI** : l'interface est en HTML/CSS (`ui/`), qui
  reprend les tailles de police en points et la structure de chaque `*View.swift`.
  Le design suit la maquette commune (8 nov.) : en-tête en dégradé bleu qui porte
  le titre de l'écran en blanc (et le champ de demande à l'accueil), fond bleu
  lavande très clair, cartes blanches à ombre douce, pastilles d'état pâles,
  bouton principal en pilule bleue ; l'arrêt par le gardien et ses alertes
  passent en rouge. Police : Segoe UI, celle de Windows (Nunito reste embarquée).
- **Se lance facilement** : WebView2 est fourni par Windows ; Python et deux
  fichiers `.bat` suffisent. Pas de Visual Studio, pas de compilation.
- **Réutilise le prototype** (`archive/windows-7-nov`) : capture (mss), clics et
  touches (pyautogui), saisie accentuée par SendInput, dossiers connus,
  applications du menu Démarrer filtrées.
- WinUI 3 ou WPF auraient demandé de redessiner chaque composant en XAML, avec
  un rendu plus éloigné et une chaîne de compilation lourde.

## Correspondance avec l'app Mac

| Mac (`apps/mac/Sources`) | Windows |
|---|---|
| `Theme.swift`, `Header` | `ui/style.css`, `header()` dans `ui/app.js` |
| `HomeView`, `SessionView`, `ConsentView`, `LessonView` | `home()`, `session()`, `consent()`, `lesson()` |
| `RemoteRequestView`, `SettingsView` | `remote()`, `settingsSheet()` (+ `supportInfo()`) |
| `OnboardingView`, `HelpersPanel` (liaison) | aucun : poste configuré par stratégie de groupe |
| `Model.swift` | `papai/model.py` |
| `Bridge.swift` | `papai/bridge.py` |
| `Core.swift` (StopGate, capture, actions, raccourcis) | `papai/core.py` |
| `Dictation.swift` | `papai/dictation.py` (PortAudio, silence, transcription par le serveur) |
| `PAPAI_DEMO`, `PAPAI_AUTOTASK` | identiques |

Différences assumées :

- **Autorisations** : Windows n'en demande pas pour voir l'écran ni pour la
  souris ; l'écran d'autorisations du Mac n'apparaît jamais.
- **Pas d'accueil ni de liaison** : le Mac garde ses parcours ; sur Windows, le
  nom vient du compte, l'organisation des stratégies de groupe.
- **Mes raccourcis** : les trois applications connues les plus utilisées (passages
  au premier plan comptés localement), Images, Documents, Téléchargements, le
  dernier dossier de photos, et jusqu'à quatre dossiers personnels. « Ajouter »
  ouvre le sélecteur natif ; « Retirer » libère une place. Compteurs et choix dans
  `%APPDATA%/PapAI/home-shortcuts.json`, jamais envoyés au serveur.
- **Applications connues** : Photos, Outlook, Edge, Chrome, Firefox, Thunderbird,
  Word, Excel, Explorateur, seulement si installées. Les exécutables sont résolus
  à nouveau à l'ouverture dans Program Files ou Windows ; Photos passe par son
  URI connue. Aucun `.lnk` du menu Démarrer n'est exécuté.
- **Touches** : le modèle connaît surtout le Mac ; `cmd` devient `ctrl`, et
  `cmd+space` (recherche du Mac) devient la touche Windows.
- **Dictée** : sans réponse du serveur (Gladia), pas de secours local ; l'app
  invite à écrire. Sounddevice/PortAudio enregistre en mémoire (WAV mono 16 kHz),
  coupe après 1,8 s de silence, 8 s sans voix ou 30 s maximum. Une seule demande
  part après transcription, rien si le micro est muet. WinMM détecte les entrées
  audio toutes les 2 s, y compris après branchement/débranchement ; sans micro,
  le champ s'affiche d'office et le bouton micro disparaît.

La tuile **Nouveau message** ouvre seulement l'URL fixe `mailto:` avec la
messagerie par défaut, sans destinataire ni donnée fournie par l'interface.
Les boutons **Retirer** n'apparaissent qu'après **Modifier**, puis disparaissent
avec **Terminer**.

Les dossiers sont validés à l'ajout **et à chaque ouverture**, après résolution
des liens et jonctions, puis ouverts explicitement dans l'Explorateur. Fichiers,
chemins relatifs/réseau et dossiers déguisés en `.exe`, `.bat`, `.cmd`, `.ps1`,
`.lnk`, `.vbs`, `.msi`, `.scr` (entre autres) sont refusés. Aucun fichier trouvé
dans un dossier ne sert de raccourci d'application.

## Sécurité

- Le bouton **Arrêter** (ou Échap, ou fermer la fenêtre) lève d'abord le verrou
  local (`StopGate`), puis prévient le serveur. Le verrou est relu avant chaque
  geste, et même pendant une saisie lettre par lettre : il vaut hors ligne.
- **Rien ne bouge sans plan validé** : en plus du serveur, l'app refuse tout
  `execute` tant que le dernier `status` reçu n'a pas `plan_approved: true` et
  un état `active` ou `awaiting_helper`.
- La fenêtre PapAI est exclue des captures (`SetWindowDisplayAffinity`, sinon
  masquée) et les clics dans sa zone sont refusés : seul l’utilisateur la
  manipule. Session ouverte, elle reste au premier plan.
- **Gardien anti-arnaque** : toutes les 8 s, l'app envoie `guard` avec trois
  signaux textuels (processus, titre de la fenêtre active, URL vide faute
  d'équivalent simple à l'AppleScript du Mac). Jamais l'écran. Une `alert` du
  serveur s'affiche par-dessus tout, jusqu'à « J'ai compris ».

## Provenance

Deux branches ont porté l'app Windows le même jour ; celle-ci les réunit.

- `devin/windows-soin` : interface (tous les écrans de l'app Mac actuelle),
  `model.py`, `bridge.py` (refus sans plan validé), `settings.py`, `dictation.py`,
  structure initiale de l'accueil, `remote_request`, `lessons_changed`,
  `plan_step`, saisie accentuée par SendInput, aperçu Linux et tests.
- `devin/1794070934-windows-vers-main` (app de cyp-cor, branche `windows`) :
  gardien (`guard`, `alert`), écran principal choisi par `is_primary`, masque de
  la fenêtre dans la capture, refus ciblé des clics sur PapAI (la session
  survit), filtre « Uninstall » du menu Démarrer, dossiers connus. Ces gestes
  ont été essayés sur un vrai écran Windows dans cette branche (clic, saisie,
  touches, défilement, verrou d'arrêt). Son `main.py` et sa vue sont remplacés
  par la structure ci-dessus ; son historique est conservé par la fusion.

## Aperçu et tests sans Windows

```bash
cd apps/windows && python -m papai.preview      # http://127.0.0.1:8765/?demo=home
```

États : `home`, `home_empty`, `home_shortcuts`, `home_no_org` (poste sans stratégie),
`consent`, `planning`, `awaiting_approval`, `active`, `awaiting_helper`, `done`, `stopped`,
`lesson`, `remote` (et `&sheet=settings`, `&connected=0`). Démo : Jeanne, poste rattaché à « Acme ». Les captures de `screenshots/` en viennent :
ce sont des écrans de démonstration, aucune capture réelle.

Accueil avec micro : `/?demo=home&mic=1` ; sans micro : `/?demo=home&mic=0` ;
sans automate : `/?demo=home_empty` ; avec ajouts personnels : `/?demo=home_shortcuts`.
L'aperçu simule la présence audio : il n'ouvre pas le micro du navigateur.

```bash
python apps/windows/tests/test_windows_app.py             # verrou, refus, raccourcis, stratégies de groupe
python apps/windows/tests/test_windows_app.py --serveur   # parcours complet contre le serveur local + faux Holo
python -m unittest discover -s apps/windows/tests -p test_home.py -v  # raccourcis, micro, silence
node --test apps/windows/tests/test_home_ui.js             # bascule et envoi unique, sans dépendance npm
```

Icônes : tracés Material Icons (Apache 2.0). Police : Nunito (SIL OFL, `ui/fonts/OFL.txt`).
