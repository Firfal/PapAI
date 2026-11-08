# PapAI : passation complète (pour Devin ou tout nouvel agent)

Écrit le 7 novembre 2026 vers 16 h 30 par Claude (Claude Code), pour que Devin reprenne sans rien perdre.
Langue de travail : **français**, ton sobre. L'équipe préfère des réponses courtes et concrètes.

> **Aucun secret dans ce document.** Les clés existent, voici où elles sont :
> - clé Holo : `~/papai/.env` (`HAI_API_KEY`) et sur Cloud Run ;
> - clé famille de la démo en ligne : `~/papai/.papai-cloud` (non versionné) ;
> - coupons sponsors : `~/papai-secrets/sponsors.env`.
> Demandez-les à Quentin. Ne les poussez jamais, ne les collez nulle part de public.

---

## 1. Le hackathon

- **Événement :** hackathon H Company × 42 AI, « computer use agents ». Il a lieu à La Maison by Motier Ventures, à Paris, les 7 et 8 novembre 2026.
- **Rendu :** dimanche 8 novembre, **14 h sur Luma** et **14 h 30 sur BuilderBase**. Il faut se connecter soi-même. Dashboard : `builderbase.com/track-dashboard/h-company-42ai-computer-use-agents-hackathon/overview`, avec le compte de Quentin Robert.
- **Grille du jury :**

  | Critère | Poids |
  |---|---|
  | Computer use | 25 % |
  | Fiabilité | 25 % |
  | Utilité | 20 % |
  | Originalité | 15 % |
  | UX et contrôle | 10 % |
  | Démo | 5 % |

- **Prix sponsors :** Gladia (1 000 €, pour l'usage de leur transcription) et Devin (1 000 €).
- **Équipe :** Quentin (Mac de démo, iPhone de démo, compte Google Cloud), Théo, et des coéquipiers qui codent via leurs propres agents (commits signés `cyp-cor` et `snarbe`).
- **Nom :** l'ancien nom interne était CarePilot. Le nom de soumission est **PapAI**, qu'on lit « papaye » : c'est le jeu de mots du logo.

## 2. Le produit en une phrase

**Un agent qui aide votre grand-parent sur son ordinateur, uniquement avec votre accord. Ce que vous avez validé une fois, il peut ensuite le refaire seul en un clic.**

Le problème : Mamie veut retrouver ses photos de Noël et ne sait pas dans quel dossier elles sont. L'aidant est dans le métro, sans PC, et TeamViewer n'est pas envisageable.

### La boucle, cœur du pitch

1. **Demander :** la personne aidée appuie sur le gros bouton « Demander une assistance », puis tape ou dicte sa demande avec ses mots.
2. **Proposer :** Holo (le modèle de H Company) regarde l'écran et propose un plan de 2 à 5 étapes, en langage simple.
3. **Valider :** l'aidant reçoit la demande sur son iPhone et choisit **Valider**, **Préciser** (Holo refait alors un plan) ou **Refuser**. **Rien ne bouge sur l'ordinateur avant.**
4. **Exécuter :** Holo agit pendant que la personne regarde. Elle peut tout **Arrêter** à tout moment, même si la connexion est coupée.
5. **Garder :** l'aidant transforme la réussite en **automatisme**, une tuile sur l'écran de l'aîné qu'il relance seul. Le rejeu est local et sans modèle. Si le dossier a bougé, l'app s'arrête et prévient l'aidant au lieu d'agir à l'aveugle.

### Le vocal de Théo (validé)
Il décrit exactement cette boucle : un gros bouton, le langage naturel, une notification à l'aidant qui est dans le métro, l'agent H qui propose les tâches puis agit. Rien ne contredit le produit.

### Démo prévue (2 min)
1. Mamie demande ses photos de Noël, et le téléphone de l'aidant reçoit la demande.
2. Holo propose un plan. L'aidant précise : « c'est dans Images › Noël 2025 ». Holo propose un nouveau plan, l'aidant valide.
3. Holo ouvre le dossier pendant que Mamie regarde.
4. L'aidant appuie sur « Garder comme automatisme », et la tuile apparaît chez Mamie.
5. Mamie clique sur la tuile : c'est instantané.
6. **Le moment fort :** on déplace le dossier, Mamie relance la tuile, et l'app s'arrête puis prévient l'aidant. On montre ainsi la fiabilité, pas seulement le scénario idéal.
7. Si on a le temps : la dictée de la demande (Gladia) et le gardien anti-arnaque.

Une anecdote vraie, utile pour le pitch : pendant la répétition, macOS a affiché une fenêtre d'autorisation de sécurité. Le plan de Holo proposait de « la fermer ». L'aidant l'a refusé, et rien n'a bougé. Depuis, Holo a pour consigne de ne jamais toucher une fenêtre d'autorisation.

## 3. Architecture

```
Mac de la personne aidée          Serveur PapAI (Cloud Run)            H Company
  apps/mac (SwiftUI)     ──wss──▶   backend/ (FastAPI, Python)  ──HTTPS──▶  Holo
  capture d'écran,                  sessions, plan, validation,           holo3-1-35b-a3b
  clics CGEvent, Arrêter,           boucle agent, garde-fous,
  automatismes locaux, dictée       proches, dictée (Gladia)
                                           ▲
                                           │ wss (lien permanent)
                                  iPhone de l'aidant : apps/ios (SwiftUI)
                                  (+ pages web de secours /a/… /h/… /p/…)
```

- **Le serveur décide, les apps exécutent.** Le contrat exact de tous les messages est dans [`PROTOCOL.md`](PROTOCOL.md). Tout changement de message se fait d'abord là.
- **Coordonnées :** elles sont toujours normalisées dans [0, 1000] sur l'image envoyée, jamais en pixels.
- **États d'une session :** `planning` → `awaiting_approval` → (`refine` revient à `planning`) → `active` → (`awaiting_helper` en cas de question à l'aidant) → `done`. `stopped` est terminal.
- **Garde-fous et où ils sont appliqués :**
  - **Arrêt :** un verrou local sur le Mac, levé **avant** d'envoyer `stop` au serveur, et vérifié avant chaque action (`apps/mac/Sources/Bridge.swift`).
  - **Plan :** aucune action sans plan validé, revalidé côté serveur (`backend/sessions.py` : `propose_plan`, `decide_plan`).
  - **Un seul pilote à la fois :** l'aidant ne clique que lorsque l'agent est suspendu (`Owner` dans `sessions.py`).
  - **Fenêtre PapAI :** elle est exclue de la capture (ScreenCaptureKit) et les clics qui la visent sont refusés.
  - **Fraîcheur :** une capture de plus de 30 s ne peut plus servir à un clic de l'aidant.
  - **Consignes de Holo** (`papai_tools.py`) : jamais de mot de passe, de paiement ni de suppression, jamais de fenêtre d'autorisation du système ni de Réglages, et `ask_helper` après deux essais ratés.
- **Holo :** modèle `holo3-1-35b-a3b`, API compatible OpenAI sur `https://api.hcompany.ai/v1/`. Palier gratuit : 10 requêtes par minute, d'où une étape toutes les 6,5 s minimum. Maximum 5 images par requête, on en garde 3. Contexte de 65 000 tokens. La température est à 0 (à 0,8, les clics ratent leur cible de plusieurs centaines de pixels). Une session typique coûte moins d'un centime de dollar. La clé H « papai-hackathon » est sur le compte robertquentin732, avec 100 $ de crédits.

## 4. Où est quoi

| Ressource | Lien ou emplacement |
|---|---|
| Code | GitHub **Firfal/PapAI** (privé), branche `main` : https://github.com/Firfal/PapAI |
| Ancien travail Windows (Python/Tk, voix) | branche `archive/windows-7-nov` |
| Copie locale | `~/papai` sur le Mac de Quentin |
| Règles multi-agents | [`AGENTS.md`](AGENTS.md) : une branche par chantier, réserver ses fichiers, journal |
| To-do de l'équipe | [`TODO.md`](TODO.md) |
| Notion du hackathon | https://app.notion.com/p/411f9555857f8003a634eab83e3da14e (pitch, infos clés, base **Features**) |
| Base Features (Notion) | https://app.notion.com/p/fda8c6ccb5934cafb7dd8213e032a575 |
| Figma | fichier `8ZG6WjtN5AkMhCVEfsaSB9` : https://www.figma.com/design/8ZG6WjtN5AkMhCVEfsaSB9 |
| Figma : 6 directions de design | page « V2 — 6 directions de marques » (`7:2`). **Retenue : V1 « Soin »**, téléphone `15:8`, ordinateur `15:75` |
| Figma : logos | page « Logos — papaye » (`26:2`). Logotype v2 `28:2`, mascottes `29:2`, `30:2`, `34:2`, **retenue : `35:2`, « Pastel », sans main** |
| Logo et icônes en SVG | `brand/` (mascotte Pastel, icônes iOS et Mac) |
| Serveur en ligne | **https://papai-450417131702.europe-west1.run.app**. `GET /` répond `{"service":"PapAI","bridge":true/false}` |
| Projet Google Cloud | `papai-h42-ifiy5`, région `europe-west1`, service `papai`, facturation du compte d'open-flow (`01887C-…`). Compte gcloud : robertquentin732@gmail.com |
| Archive du contexte d'origine | `~/Desktop/papaitripleh.zip` |
| Secrets sponsors | `~/papai-secrets/sponsors.env` (coupons Gladia et Linkup **pas encore activés**, à faire par Quentin ; Stripe crédité après l'événement) |

## 5. Le serveur (`backend/`)

| Fichier | Rôle |
|---|---|
| `app.py` | routes HTTP et WebSocket, orchestration `run_session` (plan, puis décision de l'aidant, puis agent) |
| `sessions.py` | cycle de vie, verrou, plan, fraîcheur des captures, questions à l'aidant |
| `agent.py` | `propose_plan` (une capture et un appel à Holo, sans aucune action), `AgentRunner` (boucle observer, décider, agir, vérifier) |
| `caremamory.py` | transforme une session en fiche (titre et étapes), raccourci de dossier, enregistrement à la validation |
| `guard.py` | gardien anti-arnaque (cyp-cor) : reconnaît une situation suspecte et prévient le proche |
| `family.py` | proches : appairage par QR ou code à 6 chiffres, page `/p/{code}` (snarbe) |
| `voice.py` | dictée : Gladia v2 (upload puis pre-recorded), route `POST /k/{fam}/transcribe` |
| `static/` | pages web de secours (`helper.html` est encore dans l'ancien thème sombre, plus `pair.html`, etc.) |
| `../papai_tools.py` | contrat avec Holo : outils, `SYSTEM_PROMPT` (Windows), `MAC_SYSTEM_PROMPT`, `PLAN_PROMPT` |

**Sécurité en ligne :**
- Avec `PAPAI_PUBLIC=1`, toutes les routes utiles passent par **`/k/{clé famille}/…`** : `/k/{k}/ws/bridge`, `/k/{k}/ws/aidant/{k}`, `/k/{k}/lessons`, `/k/{k}/lessons/{id}/{img}`, `/k/{k}/transcribe`.
- Les routes sans clé (`/ws/bridge`, `/lessons`, `/sessions`) répondent 404 ou refusent la connexion. Ça a été vérifié.
- La clé famille vaut `PAPAI_AIDANT_KEY`.

**Variables d'environnement :**

| Variable | Valeur |
|---|---|
| `HAI_API_KEY` | clé de l'API Holo |
| `HOLO_MODEL` | `holo3-1-35b-a3b` |
| `PAPAI_AIDANT_KEY` | la clé famille |
| `PAPAI_PUBLIC` | `1` en ligne |
| `PAPAI_PUBLIC_URL` | l'URL Cloud Run (l'ancien nom `CAREPILOT_PUBLIC_URL` est encore lu) |
| `PAPAI_MAX_STEPS` | 25 par défaut (l'ancien nom `CAREPILOT_MAX_STEPS` est encore lu) |
| `GLADIA_API_KEY` | **pas encore définie** : la dictée bascule sur la reconnaissance vocale d'Apple, sur le Mac |

**En local :**
```bash
cd ~/papai
uv venv -p 3.12 .venv-mac && uv pip install -p .venv-mac -r requirements-backend.txt   # déjà fait sur le Mac de Quentin
PAPAI_AIDANT_KEY=demo PORT=8000 .venv-mac/bin/python -m backend.app
```

**Tests**, à lancer avant tout push serveur :
```bash
.venv-mac/bin/python tests/test_gardien.py                                   # 14 contrôles
.venv-mac/bin/python tests/test_protocole.py http://127.0.0.1:8000 demo      # 9 contrôles, dont « aucune action avant validation » et « après Arrêter, plus rien »
.venv-mac/bin/python tests/test_transcribe.py http://127.0.0.1:8000 demo     # 404 avec une mauvaise clé, 503 sans Gladia
.venv-mac/bin/python tests/faux_mac.py                                       # un faux Mac pour essayer sans Mac
```

**Déployer.** Les variables d'environnement sont conservées d'une révision à l'autre :
```bash
gcloud run deploy papai --source . --project papai-h42-ifiy5 --region europe-west1 --quiet
```
- Ajouter Gladia : `gcloud run services update papai --project papai-h42-ifiy5 --region europe-west1 --update-env-vars GLADIA_API_KEY=…`
- Réglages du service : `--min-instances 1 --max-instances 1` (une seule instance, car l'état est en mémoire), `--timeout 3600`, `--session-affinity`, `--no-cpu-throttling`, `--allow-unauthenticated`. L'accès public est voulu : c'est la clé famille qui protège.
- **Attention :** la révision en ligne a été construite au commit `a371a9f` (la dictée). Le parcours de snarbe (accueil, proches, `family.py`, commits `04d4d12`, `e52c880`, `af640b6`) **n'est pas encore déployé.** Il faut lancer les tests, puis redéployer.
- Après un redéploiement, les anciennes connexions WebSocket restent accrochées à l'ancienne révision. Il faut relancer l'app Mac (et l'iPhone) pour qu'ils se reconnectent.
- Coût : quelques euros par jour, car l'instance tourne en permanence. **À arrêter après le hackathon** (`gcloud run services delete papai …` ou `--min-instances 0`), avec l'accord de Quentin.
- Les automatismes sont stockés sur le disque du conteneur : **ils sont perdus à chaque redémarrage ou redéploiement.** Il faut les créer juste avant la démo.

## 6. App Mac de la personne aidée (`apps/mac/`)

- **Projet :** XcodeGen (`project.yml`), macOS 15 minimum, bundle `com.quentin.papai`, nom « PapAI ».
- **Installer :** `apps/mac/scripts/install-mac.sh` construit, signe et installe dans `~/Applications/PapAI.app`. L'ancienne version est déplacée dans `build/` et jamais supprimée.
  - Il existe aussi `apps/mac/scripts/build-mac-cli.sh` (swiftc sans Xcode, signature ad hoc, de snarbe).
  - **Signature :** la règle de Quentin est d'utiliser la première identité valide et **jamais l'ad hoc**, sinon macOS redemande les permissions à chaque build. Ici, « gdb-cert » est listée mais inutilisable (clé privée inaccessible). Le script prend donc « Apple Development: quentinrobert732@icloud.com (ML7DMKPNKZ) ».
- **Sources :**

  | Fichier | Rôle |
  |---|---|
  | `Bridge.swift` | WebSocket, capture ScreenCaptureKit sans les fenêtres PapAI, actions CGEvent (click, double_click, type_text, press_key, scroll), verrou d'arrêt, refus des clics sur la fenêtre PapAI |
  | `Model.swift` | état et réglages ; `serverURL` est lu dans `defaults` à la clé `server`, puis dans `PAPAI_SERVER`, puis vaut `ws://localhost:8000/ws/bridge` |
  | `HomeView.swift` | accueil « Soin » : carte menthe, champ de demande, micro, gros bouton noir (raccourcis retirés le 8 nov.) |
  | `SessionView.swift` | écrans planning, plan en attente, action en cours, question, fin, arrêt |
  | `OnboardingView.swift` | accueil en 5 écrans et proches (snarbe) |
  | `Dictation.swift` | enregistrement wav de 30 s maximum, envoi à `/transcribe`, secours avec SFSpeechRecognizer fr-FR sur l'appareil |
  | `LessonView.swift` | « Montrez-moi » : pas à pas d'une fiche, sans aucun clic |
  | `PermissionsView.swift` | Enregistrement de l'écran et Accessibilité |

- **Réglage serveur en ligne :** `wss://papai-450417131702.europe-west1.run.app/k/<clé famille>/ws/bridge`, à mettre via l'engrenage, ou avec `defaults write com.quentin.papai server "<url>"`.
- **Variables de test :**
  - `PAPAI_AUTOTASK="…"` envoie une demande dès la connexion. Lancer `~/Applications/PapAI.app/Contents/MacOS/PapAI` avec cette variable.
  - `PAPAI_DEMO=home|planning|awaiting_approval|active|awaiting_helper|done|stopped` affiche un écran sans serveur.
- **Permissions :**
  - Accessibilité : PapAI est **activée**.
  - Enregistrement de l'écran : la capture fonctionne.
  - Une fenêtre macOS « contourner le sélecteur de fenêtre privée » a dû être autorisée par Quentin.
  - Micro et reconnaissance vocale : macOS les demandera au premier usage du micro.
  - Une entrée inutile « .papai-cloud » a été ajoutée par erreur dans Accessibilité, Quentin peut la retirer.
- **Pas encore exercé en vrai :** les vrais clics CGEvent sur le bureau, le bouton Arrêter pendant une session, le rejeu d'un automatisme, `automation_failed` et la dictée.

## 7. App iPhone de l'aidant (`apps/ios/`)

- **Projet :** XcodeGen, iOS 18, iPhone seulement, bundle `com.quentin.papai.aidant`. Le produit s'appelle `PapAIAidant` pour éviter un conflit avec l'app Mac, et le nom affiché est « PapAI ».
- **Installer :** `apps/ios/scripts/install-iphone.sh`, avec l'iPhone branché, déverrouillé et le Mode développeur activé. L'équipe est lue dans `~/Signet/.team`. Avec un compte Apple gratuit, **il faut réinstaller tous les 7 jours.** L'app est actuellement installée sur « iPhone de Quentin » (iPhone 17).
- **Réglages :** touchez l'avatar Q.
  - Serveur : `https://papai-450417131702.europe-west1.run.app/k/<clé famille>`.
  - Clé : `<clé famille>`.
- **Écrans :**
  - Rien en cours : « Tout va bien ».
  - `planning`.
  - **`awaiting_approval`**, fidèle à la maquette Figma `15:8` : Valider, Préciser, Refuser.
  - `active` : capture en direct et Pause.
  - `awaiting_helper` : question, options, prise de main avec viseur, loupe ×3 et confirmation, capture de moins de 30 s.
  - `done` : réponse puis « Garder comme automatisme », brouillon éditable et Valider.
  - `stopped`.
- **Limites :**
  - Les notifications ne fonctionnent que si l'app est au premier plan, car le WebSocket se coupe en arrière-plan : **il faut la garder ouverte pendant la démo.** Les notifications push (APNs) ne sont pas faites.
  - Les gestes au doigt n'ont été essayés que sur simulateur.
  - « Jeanne, 81 ans » est écrit en dur.
  - `DebugDriver.swift` ne sert qu'aux tests en Debug et ne sort pas en Release.

## 8. Design et marque

- **Direction « Soin »**, inspirée du shot Dribbble « CareLink » : fond gris doux, grandes cartes blanches très arrondies, accent menthe, état sélectionné en pilule noire.
- **Tokens :**

  | Rôle | Valeur |
  |---|---|
  | Fond | `#EEF0EE` |
  | Cartes | `#FFFFFF` |
  | Encre | `#111312` |
  | Texte secondaire | `#7A807C` |
  | Accent | `#2E9E5B` |
  | Accent doux | `#E2F2E7` |

  Rayons de 22 à 36 pt, boutons en capsule, SF Pro Rounded.
- **Règles de Quentin :** style Apple, retenu, un seul accent, 2 couleurs maximum, **pas d'emojis**, pas de formes décoratives flottantes, de vraies maquettes. Les illustrations sont en **SVG dessiné**, jamais générées par IA d'image.
- **Logotype retenu (piste C) :** le mot **« papai »** en Outfit Bold, dont le point du i est une petite papaye orange.
- **Mascotte retenue :** la papaye cartoon **« Pastel », sans bras ni main** (clin d'œil, sourire, joues, pépins).
  - Couleurs : peau `#79BE8C`, chair `#F9A56C`, cavité `#FFEDDA`, joues `#F58A6A`, contour `#3E3631`, fond crème `#FFF5EC`.
  - C'est l'icône des deux apps. Source dans `brand/`, Figma `35:2`, carte « Pastel ».
  - La v4, plus détaillée, n'a **pas** plu : l'équipe préfère la v3 en couleurs douces.
  - En dessous de 32 px, il faut une version simplifiée (pas encore faite).
- **Pistes écartées :** les logos v1 (papaye bouton, cœur, P en coupe…), le symbole « curseur dans la papaye » et le monogramme « p-papaye ».

## 9. Notion

- Page du hackathon : pitch, infos clés, problème, boucle, lien Figma, base Features.
- La base **Features** a ces colonnes : Feature, Statut (Idée / À faire / En cours / Fait), Priorité (P0 démo / P1 bonus / P2 après), Pour qui (Aîné / Aidant), Critère jury, Description.
- **Lignes :**

  | Feature | Statut | Priorité |
  |---|---|---|
  | Demande d'aide supervisée | En cours | P0 |
  | Automatismes validés | À faire | P0 |
  | Arrêt si l'écran a changé | À faire | P0 |
  | Actions sensibles toujours bloquées | À faire | P0 |
  | Bouton Arrêter côté aîné | Fait | P0 |
  | Gardien anti-arnaque dans le navigateur | Idée | P1 |
  | Voix : parler et entendre | Idée | P1 |
  | Mode Montre-moi | Fait | P1 |
  | Rangement guidé des dossiers | Idée | P1 |
  | Plusieurs aidants | Idée | P2 |
  | Résumé de la semaine | Idée | P2 |

- La base est **à mettre à jour** : la voix est en partie faite, plusieurs aidants aussi (`family.py`), et le gardien a sa logique.

## 10. État au 7 novembre, 16 h 30

**Fait et vérifié :**
- Serveur : plan, précision, validation et refus avant toute action. C'est testé de bout en bout **en ligne**, avec un faux Mac et un faux aidant : Holo a proposé un plan, l'a refait après la précision, puis a cliqué sur Photos après validation, et la session s'est arrêtée proprement.
- Serveur en ligne protégé par la clé famille. Les routes sans clé sont refusées, c'est vérifié.
- App Mac connectée au serveur en ligne, capture sans sa propre fenêtre, plan affiché. Le refus d'un plan par l'aidant a été vérifié en réel sur le Mac de Quentin.
- App iPhone : flux complet sur simulateur, installée sur l'appareil.
- Tests : gardien 14/14, protocole 9/9, transcribe.
- Ménage du dépôt, README, TODO, PROTOCOL et AGENTS à jour.

**Répétition réelle sur le Mac de Quentin, ce qui s'est passé :**
1. 1er essai : le plan proposait l'app Photos. Après la précision vers le Finder, le nouveau plan commençait par « Fermer la fenêtre de demande d'autorisation » (une fenêtre macOS de sécurité était ouverte). **Plan refusé.** Consigne ajoutée à Holo et déployée.
2. 2e essai : la fenêtre était toujours là, donc le plan a été laissé en attente puis la session s'est arrêtée.
3. 3e essai : la fenêtre avait disparu, mais **Brave était en plein écran** au premier plan pendant que Quentin l'utilisait. Plan refusé pour ne pas cliquer dans son navigateur.
4. **Il reste à faire une vraie répétition complète :** bureau dégagé (aucune app en plein écran), PapAI visible, et personne ne touche la souris.
- Données de démo prêtes : `~/Pictures/Noël 2025/` avec 4 images générées (« Le sapin », « Repas de famille », « Les petits-enfants », « Ouverture des cadeaux »).
- Holo propose spontanément l'app Photos : **il faut préciser « dans le Finder, dossier Images › Noël 2025 »**, ce qui sert justement la démo de « Préciser ».
- L'outil d'aidant de répétition de Claude (script Python qui suit `/ws/aidant` et lit des commandes dans un fichier) était dans un dossier temporaire de session et n'est pas dans le dépôt. Utilisez l'iPhone, ou `tests/faux_mac.py` et `tests/test_protocole.py` comme modèles.

**Prochaines étapes, dans l'ordre :**
1. Lancer les tests, puis **redéployer** pour mettre en ligne le parcours de snarbe.
2. **Répétition réelle ×3** : demande, plan, précision, validation, Holo ouvre `Images/Noël 2025`, puis Arrêter pendant une action.
3. Automatisme : le créer sur l'iPhone, le rejouer sur le Mac, puis déplacer le dossier et vérifier l'alerte.
4. Essayer la dictée sur le Mac (permissions micro). **Clé Gladia :** Quentin active le coupon sur app.gladia.io, crée une clé et la met dans `sponsors.env`, puis on fait `gcloud run services update … --update-env-vars GLADIA_API_KEY=…`. Il faut **utiliser Gladia** pour viser le prix.
5. Pitch : script de 2 à 3 min, vidéo de 2 min, texte de soumission BuilderBase et Luma, captures propres. Mettre en avant Devin s'il est utilisé (prix Devin).
6. Logotype « papai » dans les en-têtes des apps, page web aidant en design « Soin ».
7. Bonus : brancher le gardien anti-arnaque sur l'écran et l'iPhone, la voix de Holo (entendre ce qu'il fait), le rangement guidé.

## 11. Pièges connus

- Sur le Mac de Quentin, **une app en plein écran** (Brave) recouvre tout : Holo voit et clique dedans. Il faut dégager le bureau avant une session.
- **Fenêtres d'autorisation macOS :** ni l'agent ni Holo n'y touchent. C'est l'humain qui clique.
- **Redéploiement Cloud Run :** relancer l'app Mac ensuite (`osascript -e 'quit app "PapAI"'; open ~/Applications/PapAI.app`).
- Le mode automatique de Claude Code a bloqué `--allow-unauthenticated`. Le premier déploiement a été lancé à la main par Quentin, les suivants passent.
- **Nommage :** si deux apps s'appellent « PapAI », un `killall PapAI` tue la mauvaise. L'app iPhone a été renommée `PapAIAidant` côté produit.
- **Réseau :** le serveur local affiche l'IP du Mac au démarrage. Avec Cloud Run, on n'en dépend plus.
- `lessons/` et les captures d'écran réelles ne doivent **jamais** être versionnées, car elles contiennent l'écran de la personne aidée.
- **Règles de Quentin pour les agents :**
  - Ne jamais supprimer sans sauvegarde (tout doit pouvoir être annulé).
  - Signer les apps Mac avec une identité stable, jamais en ad hoc.
  - Déployer directement une évolution testée, sans redemander.
  - Messages courts et en français, sans emojis.
- **Multi-agents :** respecter `AGENTS.md`, c'est-à-dire une branche par chantier, réserver ses fichiers et tenir le journal. D'autres agents poussent sur `main` en parallèle : faites `git pull --rebase` avant chaque push.

## 12. Historique des décisions (résumé)

1. Idée affinée : la règle « jamais sans aval de l'aidant », plus les automatismes validés une fois puis rejoués localement.
2. 6 directions de design dans Figma, et choix de « Soin ».
3. Vocal de Théo vérifié, puis lancement du code.
4. **Pivot de stack :** le serveur Python est gardé, les apps passent en **Swift** (Mac pour la personne aidée, iPhone pour l'aidant). Windows viendra plus tard.
5. Notion structuré avec la base Features (et les idées de gardien anti-arnaque et de rangement guidé).
6. Logos : v1 rejetée, v2 avec 3 pistes et choix du logotype C, mascottes cartoon et choix de « Coucou », puis la v4 détaillée rejetée. Retenu : la v3 en **Pastel, sans main**.
7. **Plus de serveur local :** passage sur Cloud Run avec la clé famille.
8. GitHub nettoyé : l'ancien `main` est archivé, puis `main` est remplacé.
9. La répétition réelle a montré deux pièges (fenêtre d'autorisation, plein écran), corrigés ou documentés.
10. Dictée : route Gladia côté serveur, avec la reconnaissance vocale d'Apple en secours sur le Mac.
11. Passation vers Devin (ce document).
