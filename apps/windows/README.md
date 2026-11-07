# PapAI pour Windows

L'app de la personne aidée, avec les mêmes écrans, le même parcours et le même
design « Soin » que l'app Mac (`apps/mac`). Elle parle au même serveur, par le
pont `/ws/bridge` (voir `PROTOCOL.md`), et s'annonce avec `{"type":"hello","os":"windows"}`.

## Lancer sur Windows 10 ou 11

1. Installer Python 3.10 ou plus récent (python.org, cocher « Add to PATH »).
2. Double-cliquer `install.bat` (une seule fois : crée `.venv` et installe les dépendances).
3. Double-cliquer `run.bat`.

Le serveur par défaut est `ws://localhost:8000/ws/bridge`. Pour un autre
serveur : roue dentée > Serveur, ou variable `PAPAI_SERVER` avant `run.bat`.
WebView2 est déjà présent sur Windows 10 (à jour) et 11 ; sinon, l'installer
depuis le site de Microsoft (« Evergreen Runtime »).

En ligne de commande : `.venv\Scripts\python -m papai` (avec `PAPAI_DEBUG=1`
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
  reprend tel quel les jetons de `Theme.swift` (couleurs, rayons 28/36, pilules,
  tailles de police en points) et la structure de chaque `*View.swift`. La police
  Nunito (OFL, embarquée) remplace SF Rounded, absente de Windows.
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
| `OnboardingView`, `HelpersPanel`, `RemoteRequestView`, `SettingsView` | `onboarding()`, `helpersPanel()`, `remote()`, `settingsSheet()` |
| `Model.swift` | `papai/model.py` |
| `Bridge.swift` | `papai/bridge.py` |
| `Core.swift` (StopGate, capture, actions, raccourcis) | `papai/core.py` |
| `Dictation.swift` | `papai/dictation.py` (MCI de Windows, transcription par le serveur) |
| `PAPAI_DEMO`, `PAPAI_AUTOTASK` | identiques |

Différences assumées :

- **Autorisations** : Windows n'en demande pas pour voir l'écran ni pour la
  souris. L'étape 4 de l'accueil garde les mêmes engagements, déjà cochés ;
  l'écran d'autorisations du Mac n'apparaît jamais.
- **Applications** : six raccourcis du menu Démarrer (Mail, Photos, Internet,
  Visio, Explorateur, Calendrier) au lieu des identifiants de paquets du Mac ;
  jamais un raccourci de désinstallation.
- **Touches** : le modèle connaît surtout le Mac ; `cmd` devient `ctrl`, et
  `cmd+space` (recherche du Mac) devient la touche Windows.
- **Dictée** : sans réponse du serveur (Gladia), pas de secours local ; l'app
  invite à écrire.

## Sécurité

- Le bouton **Arrêter** (ou Échap, ou fermer la fenêtre) lève d'abord le verrou
  local (`StopGate`), puis prévient le serveur. Le verrou est relu avant chaque
  geste, et même pendant une saisie lettre par lettre : il vaut hors ligne.
- **Rien ne bouge sans plan validé** : en plus du serveur, l'app refuse tout
  `execute` tant que le dernier `status` reçu n'a pas `plan_approved: true` et
  un état `active` ou `awaiting_helper`.
- La fenêtre PapAI est exclue des captures (`SetWindowDisplayAffinity`, sinon
  masquée) et les clics dans sa zone sont refusés : seule la personne aidée la
  manipule. Session ouverte, elle reste au premier plan.
- **Gardien anti-arnaque** : toutes les 8 s, l'app envoie `guard` avec trois
  signaux textuels (processus, titre de la fenêtre active, URL vide faute
  d'équivalent simple à l'AppleScript du Mac). Jamais l'écran. Une `alert` du
  serveur s'affiche par-dessus tout, jusqu'à « J'ai compris ».

## Provenance

Deux branches ont porté l'app Windows le même jour ; celle-ci les réunit.

- `devin/windows-soin` : interface (tous les écrans de l'app Mac actuelle),
  `model.py`, `bridge.py` (refus sans plan validé), `settings.py`, `dictation.py`,
  accueil en 5 écrans, proches et QR, `remote_request`, `lessons_changed`,
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

États : `home`, `consent`, `planning`, `awaiting_approval`, `active`,
`awaiting_helper`, `done`, `stopped`, `lesson`, `remote`, `onboarding0` à
`onboarding4` (et `&sheet=settings`). Les captures de `screenshots/` en viennent :
ce sont des écrans de démonstration, aucune capture réelle.

```bash
python apps/windows/tests/test_windows_app.py             # verrou, refus, raccourcis
python apps/windows/tests/test_windows_app.py --serveur   # parcours complet contre le serveur local + faux Holo
```

Icônes : tracés Material Icons (Apache 2.0). Police : Nunito (SIL OFL, `ui/fonts/OFL.txt`).
