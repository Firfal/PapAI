# Protocole PapAI (serveur ↔ apps)

Le serveur Python (`backend/app.py`) décide. Les apps Swift affichent et exécutent.
Messages JSON sur WebSocket. Coordonnées toujours normalisées dans [0, 1000]
sur l'image envoyée, jamais en pixels.

## Cycle d'une demande

```
aîné : help_request ─▶ planning ─▶ awaiting_approval ──approve──▶ active ─▶ done
                                       │  ▲                          │
                                       │  └──refine (précision)──────┤ ask_helper ─▶ awaiting_helper
                                       └──refuse──▶ stopped          │
aîné : stop (à tout moment) ─────────────────────────────────────────▶ stopped
```

États (`status.state`) : `planning`, `awaiting_approval`, `active`,
`awaiting_helper`, `done`, `stopped`.

## Étape du plan en cours (`status.plan_step`)

`plan_step` est le numéro (à partir de 1) de l'étape du plan validé que Holo
exécute. Il vaut un entier entre 1 et `len(plan)` seulement si `plan_approved`
est vrai et que l'état est `active` ou `awaiting_helper` ; sinon `null`.
Il passe à 1 dès la validation, puis Holo l'annonce à chaque action (argument
`plan_step` de ses outils, retiré avant l'envoi à l'app). Il ne recule jamais
et ne sort jamais du plan. Le même `status` part vers le Mac et vers l'aidant.

**Champ optionnel** : une app qui ne le connaît pas l'ignore, et une app qui le
connaît doit accepter qu'il manque (ancien serveur) ou soit `null`.

## App de la personne aidée (Mac, puis Windows) : `ws://SERVEUR/ws/bridge`

Envoie :
- `{"type":"hello","os":"macos","name":"Sophie"}` à chaque connexion. `name` : le prénom saisi sur l'ordinateur (absent tant qu'il n'est pas saisi).
- `{"type":"profile","name":"Sophie"}` quand le prénom change. Le serveur le garde et le transmet aux aidants (`senior`).
- `{"type":"help_request","task":"…"}` quand elle appuie sur « Demander une assistance ».
- `{"type":"stop"}` bouton Arrêter. **Le verrou local passe d'abord** : plus aucune action exécutée, même hors ligne.
- `{"type":"frame","req":R,"frame_id":"…","png_b64":"…","width":W,"height":H}` en réponse à `capture`. La fenêtre PapAI est exclue de la capture.
- `{"type":"result","req":R,"result":"texte","refused":false}` en réponse à `execute`. `refused:true` si arrêt ou action interdite.
- `{"type":"automation_failed","title":"…","detail":"…"}` quand un automate ne peut pas se rejouer (dossier absent). Le serveur prévient l'aidant.
- `{"type":"pair_start"}` pour ajouter un proche (QR, 10 min) ; `{"type":"pair_start","long":true}` pour une **invitation à envoyer** par SMS, WhatsApp, Mail… (24 h). Le serveur répond `pair_code`.
- `{"type":"remove_helper","id":"…"}` retire un proche.
- `{"type":"remote_answer","accepted":false}` refus d'une session proposée par un proche. En cas d'accord, l'app envoie directement `help_request` avec `"requested_by":"Claire"`.

Reçoit :
- `{"type":"capture","req":R}`
- `{"type":"execute","req":R,"action":{"name":N,"args":{…}}}` avec N parmi
  `click`, `double_click` (`x`,`y`,`element`), `type_text` (`text`),
  `press_key` (`keys`, ex. `cmd+space`, `enter`, `esc`), `scroll` (`x`,`y`,`direction`).
- `{"type":"session","id":…,"helper_url":…}`
- `{"type":"helpers","helpers":[{"id","name","relation"}],"added":"Claire"?}` à chaque `hello` et après chaque ajout ou retrait.
- `{"type":"pair_code","code":"482913","url":"http://…/p/482913","app_url":"papai://pair?u=http%3A%2F%2F…%2Fp%2F482913","expires_in":600}` code à afficher.
  Le QR contient `app_url` (ouvre l'app iPhone) ; le code et `url` restent affichés en texte pour le secours web.
  Ancien serveur sans `app_url` : l'app le construit, `papai://pair?u=` + `url` encodée (tous caractères réservés).
- `{"type":"lessons_changed","title":"…"}` le proche vient de valider un automate : l'app relit `/lessons`.
- `{"type":"remote_request","from":"Claire","task":"…"}` un proche propose une session : rien ne démarre sans l'accord de la personne aidée.
- `{"type":"status", …}` (voir plus bas), `{"type":"answer","content":"…"}`, `{"type":"alert",…}`, `{"type":"usage",…}`

## App de l'aidant (iPhone) : `ws://SERVEUR/ws/aidant/CLÉ`

Lien permanent : suit toujours la dernière demande, reste ouvert entre deux demandes.
La clé est affichée au démarrage du serveur (`PAPAI_AIDANT_KEY` dans `.env` pour la figer).

Reçoit :
- `{"type":"hello","bridge":true,"os":"macos","senior":"Sophie"|null}` : `senior` est le prénom de la personne aidée, à afficher partout à la place d'un nom figé.
- `{"type":"senior","name":"Sophie"}` : le prénom a changé sur l'ordinateur.
- `{"type":"status","session":id,"state":…,"task":"…","plan":["…"]|null,"plan_approved":bool,"plan_step":2|null,"question":{"question":"…","options":["…"]}|null,"usage":{…}}`
- `{"type":"frame","frame_id":"…","png_b64":"…"}` capture de l'écran de l'aîné
- `{"type":"question","question":"…","options":["…"]}`
- `{"type":"answer","content":"…"}` fin de tâche
- `{"type":"alert","title":"…","detail":"…"}` un automate a échoué
- `{"type":"lesson_pending"}`, `{"type":"lesson_draft","lesson":{…},"preview":{frame_id:png_b64}}`, `{"type":"lesson_saved","lesson":{…}}`
  Chaque étape du brouillon a un `frame` : une vraie capture de la session, présente dans `preview`. Jamais d'image fabriquée. Sans aucune capture, le serveur répond `refused`.
- `{"type":"refused","reason":"…"}`, `{"type":"ack","what":"pause|click"}`

Envoie :
- `{"type":"approve_plan"}` · `{"type":"refine_plan","text":"précision"}` · `{"type":"refuse_plan"}`
- `{"type":"answer","text":"…"}` réponse à une question
- `{"type":"pause"}` · `{"type":"refresh"}` · `{"type":"click","frame_id":"…","x":0..1,"y":0..1}` (seulement en `awaiting_helper`)
- `{"type":"remote_request","text":"…","from":"Claire"}` proposer une session (seulement s'il n'y en a pas d'ouverte). Réponses : `ack` `remote_request`, puis `remote_refused` ou `remote_accepted`.
- `{"type":"draft_lesson"}` puis `{"type":"approve_lesson","lesson":{"title":"…","steps":[{"instruction":"…"}]}}` = « Garder comme automate »
  Si Holo n'a pas pu rédiger l'automate, le serveur répond `refused` après `lesson_pending` : l'app arrête d'afficher « Rédaction en cours… ».

## Dictée de la demande

`POST /k/{clé}/transcribe` : corps = audio brut (`Content-Type: audio/wav` ou
`audio/m4a`, 5 Mo max), rien n'est écrit sur le disque. Réponse `{"text":"…"}`.
Gladia (français) transcrit côté serveur ; la clé `GLADIA_API_KEY` ne quitte
jamais le serveur. Erreurs : 404 mauvaise clé, 503 `{"error":"gladia_absent"}`
(pas de clé Gladia : l'app Mac bascule sur la reconnaissance du Mac),
502 `{"error":"phrase lisible"}`, 413 trop long.

## Gardien anti-arnaque

### Protection en temps réel

Comme la protection en temps réel d'un antivirus, elle s'active ou se coupe
dans les Réglages de l'ordinateur (Mac et Windows) ; elle est **activée par
défaut** et l'état est gardé (`realtimeProtection`). Activée, l'app envoie
toutes les 8 secondes **trois signaux textuels**, et rien d'autre. Jamais de
capture, jamais d'appel au modèle à ce stade :

```json
{"type":"guard",
 "processes":["Safari","AnyDesk"],
 "window":"Votre ordinateur est infecté",
 "url":"https://mabanque.exemple.fr"}
```

`url` ne garde que le site (schéma et hôte, sans chemin ni paramètres) ; le Mac
ne le lit pas pendant une assistance, Windows l'envoie vide. **Coupée, rien ne
part** ; le serveur ignore d'ailleurs tout `guard` d'un ordinateur qui a
annoncé la protection coupée.

L'état voyage dans `hello` et dans `profile` (`"protection": true|false`,
renvoyé dès qu'il change). Le serveur le relaie aux supports :
`{"type":"protection","on":false}` (`"on": null` quand l'ordinateur se
déconnecte), et le `hello` des supports porte
`"protection": true|false|null` (`null` : ordinateur hors ligne ou app qui ne
le connaît pas). La page du support l'affiche.

Le serveur évalue (`backend/guard.py`) et ne répond que s'il reconnaît une
situation. Une même situation ne resonne pas avant 5 minutes. Il répond par :

```json
{"type":"alert","level":"danger|attention|info","title":"…","detail":"…"}
```

### Demandes suspectes (champs optionnels, anciens clients compatibles)

Le serveur examine le texte de **chaque** `help_request` avant capture et
planification, puis chaque plan (y compris après `refine_plan`). Les règles
déterministes suffisent aux cas manifestes ; Holo ne donne qu'un avis textuel
en cas d'hésitation. Si cet avis expire ou échoue, le serveur envoie seulement
au proche un `guard_advice` non bloquant (ni `alert_id`, ni `blocked`) :
`{"type":"guard_advice","level":"attention","source":"avis_indisponible","session":"…","title":"Avis de sécurité indisponible","detail":"…"}`.
Le proche de la famille et le jeton de cette session le reçoivent, jamais le
pont aidé. La préparation continue et le plan attend toujours sa validation.
Un verdict Holo réellement suspect ou une règle déterministe reste bloquant.
Les achats de cartes cadeaux offerts à un proche ne déclenchent pas seuls le
gardien ; transmettre leurs codes ou les utiliser comme moyen de paiement
suspect reste signalé. Un virement explicitement adressé à un membre de la
famille, ou une facture d'un fournisseur habituel (EDF, Engie, Orange, SFR,
Free, Bouygues, impôts, eau, loyer) jusqu'à 1 500 € inclus, n'est pas bloqué
pour son seul montant. La dispense facture ne vaut pas au-delà de 1 500 €.
Étranger, urgence, compte/numéro nouveau ou inconnu, IBAN, code reçu ou support
suspect annulent cette exception. Un proche annonçant un téléphone perdu ou
un nouveau numéro ne bénéficie pas de la dispense familiale. Les montants
`k€`, les lettres espacées/ponctuées et les demandes en anglais/allemand
sont aussi analysés. Confirmer un virement, même sans montant, est signalé.
Une demande suspecte termine la session en `stopped`, sans `execute` ni plan à
approuver. Les alertes de veille arrêtent aussi l'assistance en cours.

`alert` peut porter `alert_id` (opaque), `source` (`request`, `plan`, `environment`),
`blocked: true`, `session` (si liée à une demande) et `task` (texte de la demande).
**`title` et `detail` sont adaptés au destinataire** : sur le Mac, avertissement
et « Contactez votre petit-fils Quentin avant d'aller plus loin » (prénom et lien
familial connus, sinon « votre proche ») ; côté aidant, demande de rappel,
raison du soupçon et texte de la demande. Aucun numéro n'est inventé : le proche
utilise son moyen de contact habituel. L'app iPhone réutilise notification locale
et Live Activity existantes (pas de nouvelle promesse de push APNs).

Le Mac garde l'alerte bloquante au-dessus de l'interface et refuse tout `execute`,
y compris `press_key`. Aucune touche (Entrée, Échap…) ne ferme l'alerte.
Le proche a deux actions : « Je m'en occupe » et « C'est normal ».
La première ne passe aucun appel et envoie :

```json
{"type":"ack_alert","alert_id":"…"}
```

Même contrôle d'identité et de portée que le rejet ci-dessous. Le serveur
envoie `{"type":"alert_acknowledged","alert_id":"…","session":"…","acknowledged":true}`.
L'aidé lit « Un proche a vu l'alerte et s'en occupe ». Aucun prénom n'est
attribué : la clé famille n'authentifie pas une identité individuelle.
Cet accusé est conservé dans le champ optionnel `alert.acknowledged` et
rejoué à la reconnexion. Les clients peuvent lire l'ancien champ
`acknowledged_by` uniquement comme présence d'un accusé, jamais l'afficher.
Un client ignore l'accusé si son identifiant ne correspond plus à l'alerte
affichée : un accusé tardif ne fait pas réapparaître une alerte rejetée.
Il ne ferme rien et ne relance aucune action. Un deuxième accusé est
idempotent. Aucun bouton côté aidé ne prétend passer un appel.

« C'est normal » demande une confirmation puis envoie :

```json
{"type":"dismiss_alert","alert_id":"…"}
```

Le rejet exige la clé famille (canal aidant permanent), ou le jeton de la
session indiquée par `alert.session`, même si celle-ci est déjà arrêtée.
Le jeton d'une autre session n'autorise ni la réception/relecture de cette
alerte ni son rejet. Une alerte sans session n'est accessible qu'à la famille.

Ce message, accepté uniquement sur un canal aidant authentifié, signifie
« Je connais cette démarche, rejeter l'alerte », **pas autoriser l'exécution**.
Le serveur vérifie l'identifiant puis envoie aux apps :

```json
{"type":"alert_cleared","alert_id":"…","session":"…"}
```

Le champ optionnel `session` (ou `null`) conserve la même portée de diffusion
que l'alerte d'origine. Les anciens clients peuvent l'ignorer.

La session arrêtée reste terminale. Il faut une nouvelle demande et une nouvelle
validation normale. Tant qu'une alerte reste ouverte, les nouvelles demandes
sont arrêtées aussi. L'alerte est renvoyée aux aidants et au pont à la reconnexion
(mémoire serveur uniquement, pas de persistance après redémarrage).

Les alertes de veille partent immédiatement à partir des signaux textuels,
sans attendre de capture ni de confirmation visuelle de Holo.
`status.stopped_by` est optionnel (`null` hors arrêt explicite). La valeur
`gardien` est conservée même après rejet de l'alerte : l'iPhone et le web
affichent « PapAI a arrêté l'assistance : démarche suspecte » ;
la fin Mac et Windows adaptée à l'aidé est décrite ci-dessous. Aucun de ces écrans
n'attribue l'arrêt à la personne aidée. Les autres causes restent inchangées.
`status.execution_started` est un booléen irréversible dans une session, posé
juste avant l'envoi d'une action Holo ou d'un clic du proche au pont. Il peut
donc valoir `true` pour une action en cours, refusée ou sans résultat confirmé.
Seule la valeur explicite `false` permet d'affirmer « Rien n'a été fait sur
son ordinateur ». Si `true` ou absent (ancien serveur), l'aidant lit
« L'assistance est arrêtée. Vérifiez avec Sophie ce qui a été fait. »
`status.guard_acknowledged` conserve l'accusé anonyme après rejet de l'alerte.
La fin Mac (et Windows) du gardien est une carte blanche : « PapAI a arrêté : cette démarche
peut être une arnaque », sans paiement/code et appel du premier proche connu
à son numéro habituel. Aucune carte « Tout va bien » ne coexiste avec une alerte.
Sur Windows, `level: danger` ou `blocked: true` lève immédiatement le verrou
local et annule les tâches `execute` engagées. Le fil d'exécution conserve le
verrou de sa demande et le relit avant les gestes suivants, même si une nouvelle
demande réinitialise ensuite le verrou courant.

Ce qui est reconnu aujourd'hui : un outil de prise en main qui tourne
(AnyDesk, TeamViewer, UltraViewer…), une fausse alerte « votre ordinateur est
infecté, appelez ce numéro », un site de carte prépayée ou de transfert
irréversible, et la combinaison la plus grave — outil de prise en main **plus**
page bancaire ouverte.

Consulter sa banque seule ne déclenche rien.

## Automates

`GET /lessons` renvoie les automates validés. Chacun a `title`, `steps`
(pas à pas, mode « Montre-moi ») et `shortcut` `{"folder":"pictures","subfolder":"Noël 2025"}`
que l'app rejoue **localement, sans modèle** : elle ouvre le dossier connu du système.
Si le dossier n'existe plus, elle n'invente rien : `automation_failed`.
`GET /lessons/{id}/{image}` sert les captures des étapes.

### Automates importés par un support (fichier `.papai`)

Un service IT ou un proche fournit un automate ; **l'importer, c'est le
valider**. La personne le lance ensuite seule, en un clic, sans attendre
l'accord d'un support. Exemples dans [`automations/`](automations/).

```json
{"papai": 1,
 "title": "Lancer un scan antivirus",
 "publisher": "Service IT Acme",
 "description": "…",
 "platforms": ["windows"],
 "actions": [{"do": "antivirus_scan"}],
 "steps": ["Texte du mode « Montre-moi »", "…"]}
```

Uniquement des **actions de premier niveau**, connues de l'app. **Jamais de
commande, de script (PowerShell, shell), d'exécutable ni de chemin libre** :
toute autre valeur de `do` est refusée à l'import.

| `do` | Paramètres | Effet |
|---|---|---|
| `open_folder` | `folder` (pictures, documents, downloads, desktop, videos, music), `subfolder` (un nom) | Ouvre le dossier. |
| `open_settings` | `page` : printers, default_apps, updates, antivirus, wifi, bluetooth, sound, display | Ouvre la page des Réglages (`ms-settings:` sur Windows, `x-apple.systempreferences:` sur Mac). |
| `open_url` | `url` en `https://`, sans identifiant | Ouvre le lien dans le navigateur. |
| `install_templates` | `files` : 1 à 5 `{"name":"Lettre.dotx","data":"<base64>"}`, `.dotx`/`.potx`/`.xltx` (sans macros) | Copie les modèles dans le dossier des modèles personnels de Word. |
| `antivirus_scan` | — (Windows seulement) | Scan rapide Microsoft Defender : `MpCmdRun.exe -Scan -ScanType 1`, exécutable et arguments fixes, sans shell. Menace trouvée : `automation_failed`. |
| `holo` | `goal`, `steps` (≤ 12) — une seule, en dernier | Holo fait la tâche à l'écran, avec ce plan déjà validé. |

Routes (protégées par la clé, ou depuis la machine du serveur sans `/k/CLÉ`) :

- `POST /k/CLÉ/automations` (corps : le fichier `.papai`) : `200` et la fiche
  enregistrée (`id` en `imp-…`, `source:"import"`, `approved_by`,
  `approved_at`), ou `422 {"error":"…"}` qui dit en clair ce qui est refusé.
  Les modèles sont rangés à part et servis par `GET /lessons/{id}/{nom}`.
  L'ordinateur reçoit `lessons_changed`.
- `DELETE /k/CLÉ/automations/{id}` : retire un automate importé.
- La page du support (`/a/CLÉ`) a un bouton « Importer un automate ».

Lancement, côté app :

1. Vérifier que `platforms` contient le système ; sinon ne rien faire.
2. Jouer les actions locales dans l'ordre, en relisant le verrou Arrêter avant
   chacune. Un échec : `automation_failed` et on s'arrête.
3. S'il y a une action `holo` : la première fois, l'accord de partage d'écran ;
   puis `{"type":"run_automation","id":"imp-…"}` sur `/ws/bridge`.
   Le serveur ouvre une session dont le plan est déjà validé
   (`plan_approved:true`, journal `plan_preapproved` avec `by`), répond
   `{"type":"session","id":"…","helper_url":"…","automation":"imp-…"}` et
   l'agent agit aussitôt. Arrêter, les actions sensibles bloquées et
   l'exclusion de la fenêtre PapAI s'appliquent comme pour une demande.
   Automate inconnu, sans `holo` ou d'une autre plateforme :
   `{"type":"automation_refused","id":"…","reason":"…"}`.

## Proches

La personne aidée affiche un code à 6 chiffres et son QR (`pair_code`). Le proche ouvre
`/p/{code}` (ou `/p` pour taper le code), donne son prénom et son lien, et reçoit le lien
de l'espace aidant. Le code sert une fois, expire en 10 minutes et tombe après 5 essais ratés.
En ligne, ces routes passent aussi par `/k/{clé}/p/…`. Les proches sont gardés dans `family.json`.

`POST …/p/{code}` avec `{"name","relation"}` répond `{"ok":true,"name","aidant_url","server","key"}`
(ou `{"ok":false,"error"}` en 400). L'app iPhone s'en sert pour se régler seule :

- **Lien d'app** `papai://pair?u=<URL d'appairage encodée>` (QR du Mac, bouton de `pair.html`).
  L'app lit `u` (`https://…[/k/<clé>]/p/<code>`), demande prénom et lien, fait le POST sur `u`,
  puis enregistre `serverURL = server + "/k/" + key` et `helperKey = key`, et se connecte.
- Le scanner de l'app accepte `papai://pair?u=…` comme l'ancien `https://…/p/<code>`.
- Saisie du code à la main : le support ne tape que le code, jamais d'adresse. POST sur
  `<serverURL réglé>/p/<code>`, ou sur `https://papai-450417131702.europe-west1.run.app/p/<code>`
  (serveur officiel) si l'app n'est pas encore réglée. En ligne, `GET /p`, `GET /p/<code>` et
  `POST /p/<code>` répondent donc aussi sans clé : le code est le secret (une seule fois, 10 min
  ou 24 h), et la réponse donne `server` et `key`. Voir « Plusieurs espaces » : le code tapé
  sans clé cherche son espace et doit être accepté sur l'ordinateur aidé.
- Arguments de lancement `-serverURL` et `-helperKey` (dépannage, démo) : l'app les enregistre.

## Plusieurs espaces (un par ordinateur aidé)

Le serveur héberge un **espace** par ordinateur aidé : sa clé, ses supports (`family.json`), ses
sessions, son alerte en cours, ses fiches et automatismes. `/k/<clé>/…` choisit l'espace. L'espace
historique (`PAPAI_AIDANT_KEY`) garde `family.json` et `lessons/` à la racine ; les autres vivent
dans `$PAPAI_DATA_DIR/spaces/<id>/` (par défaut `data/spaces/`). Un support suit plusieurs
personnes aidées en gardant une clé par espace.

- **Premier lancement** (Windows, Mac) sans serveur réglé : `POST /spaces` sur le serveur officiel
  → `{"key","server","bridge_url"}` (`bridge_url` = `wss://…/k/<clé>/ws/bridge`). L'app garde
  `bridge_url` comme serveur : rien à régler. Limité à 5 créations par heure et par adresse IP (429).
- **Clé inconnue mais bien formée** (12 à 64 caractères `A-Za-z0-9_-`) sur `/k/<clé>/ws/bridge` :
  l'ordinateur revient après un redéploiement qui a effacé le disque, un espace est recréé à sa
  clé (même limite). Les supports sont restaurés par `known_helpers`.
- **Code tapé sans clé** (`POST /p/<code>`) : le serveur cherche l'espace dont le code est valide.
  Code inconnu → 400 ; plus de 10 codes faux en 10 min depuis une même adresse → 429.
  En ligne (`PAPAI_PUBLIC=1`), avec plusieurs espaces 6 chiffres se devinent : l'ordinateur aidé
  doit accepter le support.
  - serveur → pont : `{"type":"pair_confirm","req":N,"name","relation"}` ;
  - pont → serveur : `{"type":"pair_decision","req":N,"accept":true|false}`.
  Sans réponse en 120 s, ou refus : 403 `{"ok":false,"error"}`. Les liens avec clé (QR, SMS :
  `/k/<clé>/p/<code>`) ne demandent pas cette confirmation.
- Le jeton d'une session (`/h/<jeton>`, `/ws/helper/<jeton>`) désigne aussi son espace.
- Test : `python tests/test_appairage_code.py` (deux espaces, confirmation, force brute).

## Organisations (service IT)

Un service IT suit tous les postes de ses employés sans les appairer un par un. Données dans
`$PAPAI_DATA_DIR/orgs/<id>/` (`org.json`, `lessons/`) ; le poste garde `org` et `label` dans son `space.json`.

- `POST /orgs` `{"name"}` → `{"id","name","enroll_token","support_token","server","support_url","app_url"}`.
  3 créations par heure et par adresse IP (429). Les deux jetons ne sont donnés qu'ici.
  - `enroll_token` (`ins-…`) : déposé sur les postes. Windows : `apps\windows\organisation.txt`
    (ignoré par git) ou `PAPAI_ORG`. Mac : préférence `orgToken` (`defaults write`, profil MDM) ou `PAPAI_ORG`.
  - `support_token` (`sup-…`) : donné aux supports (personnes ou support IA). `support_url` =
    `<server>/o/<jeton>` (page web), `app_url` = `papai://org?u=<server>&t=<jeton>` (Android, iPhone).
- `POST /spaces` `{"org": "<enroll_token>", "name": "<utilisateur · poste>"}` : le poste s'inscrit
  au premier lancement (pas de limite par IP). Réponse : en plus, `"org": "<nom>"`.
  Jeton inconnu → 403 : l'app crée alors son espace sans organisation. Plus de
  `PAPAI_ORG_ENROLLS_PER_HOUR` (200 par défaut) inscriptions par heure pour une organisation → 429 :
  l'app réessaie plus tard, comme hors ligne.
- `POST /k/<clé>/org` `{"org","name"}` : un poste déjà installé rejoint l'organisation → `{"org"}`.
  403 jeton inconnu, 409 si le poste appartient à une autre organisation ou si c'est l'espace historique.
- `GET /o/<support_token>/spaces` → `{"org","server","spaces":[{"key","name","label","online"}]}`
  (`name` = prénom donné sur le poste, sinon `label`). Le support garde une liaison par `key`
  (`<server>/k/<key>`), comme après un appairage. Jeton inconnu → 404.
- `GET|POST /o/<support_token>/automations`, `DELETE /o/<support_token>/automations/<id>` : catalogue
  de l'organisation (même format `.papai` que `POST /k/<clé>/automations`). Un import est copié sur
  chaque poste et sur ceux qui s'inscrivent plus tard ; un retrait l'enlève partout. Les postes
  connectés reçoivent `lessons_changed`.
- `GET /o/<support_token>` : page web de l'organisation (postes, automatismes partagés). Elle ajoute
  les postes à « Mes personnes aidées » de ce navigateur (`papai_people`, `papai_orgs`).
- Test : `python tests/test_organisation.py`.

## Tickets (chaque demande d'assistance)

Chaque demande devient un ticket, gardé dans `<espace>/tickets.json` (500 derniers, texte seulement :
aucune capture). Numéro `number` par espace, ou unique dans l’organisation (`orgs/<id>/tickets_seq`), affiché `T-0001`. Statuts : `nouveau`, `en_attente`
(aucun support disponible), `rdv`, `en_cours`, `a_reprendre` (session arrêtée ou échouée), `resolu`.
`source` : `personne`, `support` ou `automatisme`. Le ticket suit la session (`plan`, `steps_done`,
`helper`, `stopped_by`, `tokens`) ; `assignee`, `closed_by`, `notes` [{t, by, text}], `rdv` (secondes Unix).

**Ordinateur aidé (`/ws/bridge`)**
- `help_request` peut porter `"ticket"` (reprise d'un ticket proposé par `remote_request`).
- Sans `requested_by` ni `ticket`, si l'espace a un support connu (appairé ou organisation) mais
  aucun connecté : pas de session. Serveur → `{"type":"ticket_queued","ticket","number","task"}`.
  L'app revient à l'accueil et propose un rendez-vous. Sans aucun support connu : session comme avant.
- `session` porte en plus `"ticket"` et `"number"`.
- App → `{"type":"ticket_schedule","ticket","at"}` (entre 1 min et 30 jours) →
  `{"type":"ticket_scheduled","ticket","number","at"}` ou `{"type":"ticket_refused","ticket","reason"}`.
  `ticket_scheduled` arrive aussi quand le support fixe le rendez-vous (avec `by`).
- Le serveur repropose la demande par `remote_request` avec `"ticket"`, `"number"` et `"rdv"` (vrai à
  l'heure du rendez-vous) : quand un support se connecte (`/ws/aidant`, au plus une fois par 10 min et
  par ticket), quand l'ordinateur se reconnecte avec un support en ligne, à l'heure d'un rendez-vous
  (vérifié toutes les `PAPAI_RDV_TICK_S` secondes, 20 par défaut), ou quand un support prend le ticket.
  Accepter = `help_request` avec `requested_by` et `ticket` ; refuser = `remote_answer` avec `ticket`
  (note « Pas disponible » sur le ticket, qui reste en attente).

**Support (`/ws/aidant`)** : `hello` porte `tickets_waiting` (nombre en attente ou rendez-vous échu).
Serveur → `{"type":"tickets_changed"}` (relire la liste) et `{"type":"ticket_due","ticket","number","task"}`.

**HTTP**
- `GET /k/<clé>/tickets` → `{"tickets":[…]}` (200 plus récents d'abord).
- `POST /k/<clé>/tickets/<id>` `{"action","by","text"?,"at"?}` → `{"ticket"}`. Actions : `take`
  (propose la session à la personne ; 409 si ordinateur hors ligne ou session en cours), `note`,
  `schedule` (`at`), `close`, `reopen` (409 pendant une session).
- `GET /o/<support_token>/tickets` → `{"org","tickets":[… + "space","poste","online"]}` ;
  `POST /o/<support_token>/tickets/<clé du poste>/<id>` : mêmes actions (404 hors organisation).
- `GET /tickets.js` : liste commune à la page du support et à celle de l'organisation (filtres, export CSV).
- Test : `python tests/test_tickets.py`.

## Prénom et invitation (7 novembre au soir)

- `pair_code` porte `expires_in` (600 ou 86400) et `long` (vrai pour une invitation). `app_url` = `papai://pair?u=<url>&n=<prénom>` : l'app iPhone affiche « Rejoindre Sophie » avant même l'appairage.
- La réponse de `POST …/p/<code>` contient `senior` (prénom de la personne aidée), en plus de `server` et `key`.
- Test : `python tests/test_profil.py http://127.0.0.1:8000 demo` (6 contrôles).

## Question à la personne aidée (`ask_senior`)

- Holo peut poser une question à la personne aidée elle-même, pour une information qu'elle seule connaît (banque, fournisseur, nom). Jamais de mot de passe ni de code.
- `status.question` porte alors `"to":"senior"` (sinon `"helper"`). Le message `question` aussi.
- App de la personne aidée : elle affiche la question et répond par `{"type":"senior_answer","text":"…"}`. L'aidant voit « Question posée à Sophie » et peut aussi répondre (`answer`). La première réponse compte.
- Côté personne aidée, le plan n'est plus affiché : seulement l'avancement (`state`, `plan_step` / longueur du plan).

## Dictée en direct

- App de la personne aidée → serveur : `{"type":"dictation","text":"…","final":false}` pendant qu'elle parle (au plus 3 par seconde), puis `final:true` avec le texte retenu.
- Serveur → aidants : le même message. L'iPhone affiche « Sophie est en train de parler : « … » ».

## Pause de la personne aidée et contrôle des entrées

- App de la personne aidée → serveur : `{"type":"pause"}` / `{"type":"resume"}`. Le serveur met `status.paused` à vrai ou faux et le transmet à tous. Holo n'agit pas tant que `paused` est vrai.
- Pendant que Holo agit (`active`, `awaiting_helper`, hors pause), l'app Mac bloque la souris et le clavier de la personne aidée hors de sa fenêtre. Échap arrête tout. Le verrou se lève à la pause, à l'arrêt, à la fin, si la connexion tombe, ou après 45 s sans message du serveur.

## Aidant connecté, nom de l'aidant, phrase de Holo (7 nov.)

- iPhone → serveur, juste après `hello` : `{"type": "helper_hello", "id": "<id ou vide>", "name": "Quentin", "relation": "son fils"}`.
  Le serveur l'ajoute à la famille s'il n'y est pas (même id, ou même prénom), et répond `{"type": "helper_id", "id": "…"}` que l'app garde.
- Serveur → ordinateur : `helpers` porte maintenant `online` (true tant que l'app de cet aidant est ouverte). Renvoyé à chaque connexion et déconnexion d'un aidant.
- Réponse de `POST /p/{code}` : ajoute `id`.
- `status` ajoute :
  - `helper_name` : le prénom de l'aidant qui a validé le plan, répondu ou cliqué. L'ordinateur affiche « Quentin s'en occupe ».
  - `doing` : une seule phrase sur ce que fait Holo, tirée de sa réflexion (si elle est en français) ou de l'action.
- Ordinateur → serveur : `profile` porte `known_helpers` (la liste gardée sur le Mac). Le serveur rajoute ceux qui lui manquent (disque Cloud Run effacé à chaque mise en ligne) et renvoie `helpers`.

## Agent navigateur de H (tâches dans le navigateur, Mac)

Quand la demande se fait dans un navigateur, le serveur pilote l'agent web
local de H (Agents API) au lieu de l'agent bureau. Tous les champs sont
optionnels : un ancien serveur ou une ancienne app les ignore et le mode
bureau reste le comportement par défaut.

- Mac → serveur, `hello` : `"web_agent_available": true` quand
  `WebAgentHost.isInstalled` et `browserExecutable()` sont vrais. Le Mac
  n'annonce plus de session navigateur dans `hello`; l'absence du champ signifie
  que le serveur doit rester en mode bureau.
- Après la validation du plan, serveur → Mac :
  `{"type":"web_agent_start"}` si le plan demande le web et que le Mac a annoncé
  cette capacité. Le Mac ne démarre le navigateur que pour une session en cours
  et si le verrou local n'est pas levé.
- Si aucune session navigateur valide n'arrive dans les 20 secondes, ou si la
  session est arrêtée pendant son démarrage, le serveur envoie
  `{"type":"web_agent_stop"}` au Mac. Celui-ci annule son démarrage local sans
  renvoyer de réponse. Après l'expiration, une réponse tardive est ignorée et la
  session encore ouverte passe en mode bureau.
- Mac → serveur, en cours de session :
  `{"type":"web_agent","session_id":"<uuid>"}` après le démarrage de Chrome
  PapAI (profil dédié, port de debug 9222) et de
  `holo local browser --session-id <uuid>`; `{"type":"web_agent","session_id":null}`
  quand ils s'arrêtent. Le serveur attend au plus 20 secondes une session valide,
  puis utilise le mode bureau si le Mac ne répond pas.
- Serveur → apps, `status.where` : `"web"`, `"desktop"` ou `null`. Avant la
  validation, c'est l'endroit proposé par Holo avec le plan ; après la
  validation, c'est le mode réellement utilisé (`"desktop"` si le Mac n'a pas
  annoncé cette capacité ou si le démarrage du navigateur échoue). Les apps
  l'ignorent si absent.
- Rien ne change avant `approve_plan` : gardien, capture pour le plan, plan à
  valider. La session H n'est créée qu'après la validation.
- En mode web, le serveur n'envoie ni `capture` ni `execute` au Mac pendant
  l'exécution : H agit dans Chrome PapAI. `status.doing`, `plan_step`, `frame`
  (aidants seulement), `ask_helper` / `answer`, `pause` / `resume` et `answer`
  final gardent leur forme. La capture du bureau ayant servi au plan est
  effacée avant le démarrage web ; seuls les `frame` de H sont ensuite renvoyés.
  Arrêt, refus, alerte du gardien ou pont déconnecté : le serveur annule la session H.
- Prise en main du proche : en mode web, `click` est refusé (l'image vient de
  Chrome PapAI, pas du bureau) et `refresh` renvoie la dernière image de H sans
  capturer le bureau. Le proche répond à la question de Holo.
- Le Mac met la fenêtre Chrome PapAI au premier plan une fois, quand
  `where == "web"` et que la session passe `active` ou `awaiting_helper`.
  « Arrêter », une alerte ou la fin de session (`done`, `stopped`) exécutent
  `holo local stop` et terminent le process, même hors ligne. Chrome PapAI
  reste ouvert, plus rien ne le pilote.
- Chrome PapAI part d'un profil neuf à chaque assistance, effacé une fois
  Chrome fermé : l'app ne retient jamais de compte, d'identifiant ni de
  cookie. La personne aidée se connecte elle-même à ses sites.
- Limite : `holo local browser` exige une clé H (`HAI_API_KEY`) sur le Mac de
  la personne aidée (`~/.config/hai/.env` ou variable d'environnement). Elle
  n'est jamais dans le dépôt ni dans les journaux.
