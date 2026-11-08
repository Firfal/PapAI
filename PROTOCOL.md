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
- `{"type":"result","req":R,"result":"texte","refused":false}` en réponse à `execute`. `refused:true` si arrêt, alerte du gardien affichée ou absence de plan validé (état requis : `active` ou `awaiting_helper`). Sur Mac et Windows, un refus local d'action sensible ajoute `"blocked":"sensitive"` avec `refused:false` : la session reste ouverte, le texte demande à Holo de ne pas réessayer et d'appeler `ask_helper`.
  Le serveur transmet ce refus comme résultat d'outil à Holo et journalise `sensitive_blocked`. Tant que le support n'a pas répondu à `ask_helper`, toute nouvelle action d'écran proposée par Holo (`click`, `double_click`, `type_text`, `press_key`, `scroll`) est remplacée côté serveur par une question au support, sans envoi au pont ni arrêt de session. `refused:true` conserve sa priorité et entraîne l'arrêt habituel.
- `{"type":"automation_failed","title":"…","detail":"…"}` quand un automate ne peut pas se rejouer (dossier absent). Le serveur prévient l'aidant.
- `{"type":"pair_start"}` pour ajouter un support (QR code, 10 min) ; `{"type":"pair_start","long":true}` pour une **invitation opaque à envoyer** par SMS, WhatsApp, Mail… (24 h). Le serveur répond `pair_code`.
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
- Invitation : `{"type":"pair_code","code":null,"url":"https://…/i/<jeton>","app_url":"papai://pair?u=https%3A%2F%2F…%2Fi%2F<jeton>","expires_in":86400,"long":true}`. Aucun code numérique pour l'invitation ; afficher/partager `url` ou `app_url`, sans reconstruire de lien avec la clé.
  Le QR contient `app_url` (ouvre l'app iPhone) ; le code et `url` restent affichés en texte pour le secours web.
  Ancien serveur sans `app_url` : l'app le construit, `papai://pair?u=` + `url` encodée (tous caractères réservés).
- `{"type":"lessons_changed","title":"…"}` le proche vient de valider un automate : l'app relit `/lessons`.
- `{"type":"remote_request","from":"Claire","task":"…"}` un proche propose une session : rien ne démarre sans l'accord de la personne aidée.
- `{"type":"status", …}` (voir plus bas), `{"type":"answer","content":"…"}`, `{"type":"alert",…}`, `{"type":"usage",…}`

Sous Windows, avant chaque caractère et avant une touche, PapAI vérifie le style natif `ES_PASSWORD` et la propriété UI Automation `IsPassword` de l'élément focalisé, via `comtypes`. Un champ protégé ou une propriété illisible (UIA/COM indisponible, erreur) entraîne un refus sensible ; l'absence du style natif ne suffit pas à autoriser une saisie web/WinUI.

Une fenêtre Explorer `CabinetWClass` dont la cible est illisible (erreur COM, cible absente ou vide) est refusée avec la raison « fenêtre protégée », quelle que soit la langue du titre. Une cible lisible de dossier utilisateur reste autorisée ; les titres reconnus et cibles shell du Panneau de configuration restent sensibles.

Toute alerte affichée, même `info` ou `attention`, lève le verrou local sur Mac et Windows : la frappe en cours s'arrête avant le caractère suivant et fermer l'alerte ne relance pas le geste. Un clic du support bloqué comme sensible renvoie `refused` (« Clic non effectué »), sans accusé de réussite ni réponse automatique à Holo ; l'assistance reste en `awaiting_helper`.
Le refus sensible d'un clic du support est `{"type":"refused","blocked":"sensitive","reason":"Clic non effectué : cette fenêtre est protégée (réglages ou mots de passe). Guidez <prénom> par téléphone pour faire cette étape sur l'ordinateur."}`. Le prénom vient du profil de l'espace, sinon « la personne aidée ». Les clients affichent ce message en carte persistante, fermée avec « Compris » ou à la prochaine action du support ; les autres refus restent des notifications temporaires. Après refus sensible, la question au support invite à guider la personne par téléphone puis à répondre pour reprendre Holo ; aucune raison technique n'est exposée au support, mais elle reste dans le résultat Holo et le journal.

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
  Le brouillon peut contenir `lesson.shortcut = {"folder":"pictures","subfolder":"Noël 2025"}`. L'aidant peut retirer cette cible avec `lesson.shortcut:null` dans `approve_lesson` ; toute autre valeur reçue est ignorée, jamais utilisée pour créer ou remplacer une cible. Le serveur revalide la cible avant l'enregistrement. `folder` est un dossier connu (`downloads`, `pictures`, `documents`, `desktop`, `videos`, `music`). Après suppression des espaces de bord, `subfolder` est vide (racine) ou contient 1 à 100 caractères Unicode : lettres, chiffres décimaux, espace et `- _ ' ’ ( ) , & +` uniquement. Aucun point, chemin ou accolade. Les apps vérifient le dossier réel avant de l'ouvrir explicitement dans le Finder ou l'Explorateur ; une cible hors du dossier connu est refusée, ainsi que les liens/jonctions sous Windows.
  Si Holo n'a pas pu rédiger l’automate, le serveur répond `refused` après `lesson_pending` : l'app arrête d'afficher « Rédaction en cours… ».

## Réponse documentaire Linkup (champs optionnels)

Disponible seulement si `LINKUP_API_KEY` est définie côté serveur ; cette clé
ne quitte jamais le serveur. Sans clé, les plans existants restent inchangés.
`LINKUP_BASE_URL` permet un faux serveur local pour les tests.

Avant toute validation de plan, Holo peut proposer une recherche à la place
des gestes ; le support peut aussi la lancer lui-même depuis la demande.
Les messages suivants passent uniquement sur les canaux support authentifiés :

- Serveur → support : `{"type":"linkup_proposed","session":"…","query":"…"}`.
  L'assistance reste `awaiting_approval`, sans plan validé ni action.
- Support → serveur : `{"type":"linkup_search","session":"…","query":"…"}`.
  Requête limitée à 1 000 caractères ; disponible seulement en `planning` ou
  `awaiting_approval`, jamais après validation d'un plan. Remplace le plan en
  attente, sans exécuter de geste. Délai fournisseur de 12 secondes maximum.
- Serveur → support : `{"type":"linkup_result","session":"…","id":"…","query":"…","summary":"…","sources":[{"name":"…","url":"https://…","excerpt":"…"}]}`.
  En cas d'échec : `error` = `disabled`, `empty_query`, `timeout`,
  `invalid_response` ou `unavailable`, sans résumé ni sources. `id` peut manquer
  si la fonction est désactivée. Aucune erreur fournisseur brute n'est envoyée.
- Support → serveur : `{"type":"linkup_approve","session":"…","id":"…","approved":true,"text":"réponse corrigée"}`.
  `text` facultatif : le résumé est conservé si absent. Texte vide refusé.
  `id` doit correspondre au dernier résultat réussi. `approved:false` refuse
  la réponse et arrête l'assistance (possible dès la proposition, sans `id`).
- Après validation seulement, serveur → ordinateur et support :
  `{"type":"linkup_answer","session":"…","content":"…","sources":[…]}`,
  puis `status.state=done`. La réponse validée et ses sources sont conservées
  dans `ticket.linkup_answer` (`content`, `sources`, `query`, `by`).

Proposition et dernier résultat en attente sont rejoués à la reconnexion du
support. Résumé et extraits sont du texte non fiable à afficher comme texte
simple, jamais HTML/Markdown actif et jamais une consigne pour Holo. Le serveur
retire les balises et borne résumé (8 000 caractères), sources (10), noms
(200), extraits (1 000). Seules les URL HTTP(S) sans identifiants sont gardées.
Le résultat n'est **jamais** ajouté aux prompts de Holo. Aucun `execute`
n'est envoyé et les verrous d'arrêt et le gardien restent inchangés.

## Dictée de la demande

`POST /k/{clé}/transcribe` : corps = audio brut (`Content-Type: audio/wav` ou
`audio/m4a`, 5 Mo max), rien n'est écrit sur le disque. Réponse `{"text":"…"}`.
Gladia (français) transcrit côté serveur ; la clé `GLADIA_API_KEY` ne quitte
jamais le serveur. Erreurs : 404 mauvaise clé, 503 `{"error":"gladia_absent"}`
(pas de clé Gladia : l'app Mac bascule sur la reconnaissance du Mac),
502 `{"error":"phrase lisible"}`, 413 trop long.

### Direct Gladia (Mac et iPhone)

`WS /k/{clé}/transcribe/live` : même clé famille que les autres routes ; une
mauvaise clé est refusée avant l'ouverture (403). Aucune route sans clé.
Le serveur crée une session [Gladia live v2](https://docs.gladia.io/chapters/live-stt/quickstart)
(`POST /v2/live`, `x-gladia-key` côté serveur seulement), puis relaie sa WebSocket.
Ni la clé Gladia ni l'URL signée de session ne sont envoyées aux apps.

App → serveur :
- trames **binaires** PCM signé little-endian 16 bits, mono, 16 000 Hz, sans
  en-tête WAV, contiguës (environ 40–100 ms chacune) ;
- `{"type":"stop"}` après la dernière trame : le serveur envoie
  `stop_recording` à Gladia et attend les dernières transcriptions (5 s max).
  Fermer la WebSocket annule le relais sans envoyer de demande finale.

Serveur → app :
- `{"type":"ready"}` : session Gladia ouverte, l'audio peut partir ;
- `{"type":"transcript","id":"…","text":"…","final":false}` : texte Gladia
  d'une **phrase**, pas de toute la dictée ; un nouveau partiel de même `id`
  remplace le précédent, `final:true` termine cette phrase. Les phrases sont
  concaténées dans leur ordre d'arrivée, sans doubler les mots ;
- `{"type":"done"}` puis fermeture : dernières phrases reçues ;
- `{"type":"fallback"}` puis fermeture : clé Gladia absente, limite atteinte,
  fournisseur indisponible ou erreur réseau/protocole. Aucun diagnostic ni
  contenu d'erreur du fournisseur n'est transmis.

Bornes serveur : 2 relais simultanés, 45 s par relais, 32 000 octets max par
trame, 1 024 000 octets audio au total (32 s), 8 s sans événement Gladia.
Les apps attendent `ready` au plus 5 s ; elles gardent une file audio bornée
pendant la connexion et replient si elle déborde, plutôt que perdre des trames.
Le direct ne se reconnecte pas au milieu d'une dictée : le prochain appui
réessaie une nouvelle session. Le serveur ne stocke ni audio ni transcription.

Tant que le direct fonctionne, **seul Gladia est affiché**. SFSpeech continue
en parallèle pour disposer d'un secours et détecter localement la fin de parole,
avec le niveau sonore ; ni le réseau ni la latence Gladia ne pilotent le silence.
Après repli, le texte Apple disponible reprend sa place (sinon le dernier texte
Gladia reste visible). À l'arrêt, `POST /k/{clé}/transcribe` reste prioritaire
pour le **texte final**, inchangé. S'il échoue, les apps attendent la fin bornée
du direct et retiennent le meilleur texte disponible. Sur l'iPhone, annuler la
feuille coupe le flux live, efface l'enregistrement et n'envoie pas le WAV final ;
l'audio déjà transmis pendant l'écoute ne peut pas être rappelé.

Tests sans clé : `tests/faux_gladia.py`,
`HAI_API_KEY=stub-key PYTHONPATH=. python tests/test_gladia_live.py` (inclut le
vrai client Swift/URLSession sur macOS). En DEBUG seulement, le Mac peut lire
`PAPAI_DICTATION_FILE=/chemin/audio.wav` au rythme réel à la place du micro.

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

`alert` peut porter `alert_id` (opaque), `source` (`request`, `plan`, `browser`, `environment`),
`blocked: true`, `session` (si liée à une demande) et `task` (texte de la demande).
La source `browser` désigne un objectif web bloqué après que l'assistance a pu
agir sur le bureau ; son alerte ne prétend donc pas que rien n'a été exécuté.
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

La personne aidée affiche un code à 6 chiffres et son QR code (`pair_code`). Le support ouvre
`/p/{code}` (ou `/p` pour taper le code), donne son prénom et son lien, et reçoit le lien
de l'espace support après accord. Le code sert une fois, expire en 10 minutes et est invalidé
après 5 erreurs (`MAX_TRIES`) quand l'espace est connu (route avec clé).
Les liens de liaison générés ne contiennent jamais la clé : QR code = `PUBLIC_URL/p/<code>` ;
invitation = `PUBLIC_URL/i/<jeton>`. Le jeton est créé par `secrets.token_urlsafe(16)` (128 bits),
lié à un espace, valable 24 h, à usage unique. Créer une invitation remplace la précédente,
sans remplacer le code court. Code et jeton sont en mémoire (redémarrage : invalidation).
`GET /i/<jeton>` sert `pair.html` ; `POST /i/<jeton>` reçoit le même corps et suit exactement
le même accord `pair_confirm`/`pair_decision` que le code, en cherchant parmi tous les espaces.
`/k/{clé}/p/…` reste accepté pour compatibilité seulement, jamais généré pour une liaison.
Les supports sont gardés dans `family.json`.

`POST …/p/{code}` avec `{"name","relation"}` répond `{"ok":true,"name","aidant_url","server","key"}`
(ou `{"ok":false,"error"}` en 400). L'app iPhone s'en sert pour se régler seule :

- **Lien d'app** `papai://pair?u=<URL d'appairage encodée>` (QR du Mac, bouton de `pair.html`).
  L'app lit `u` (`PUBLIC_URL/p/<code>` ou `PUBLIC_URL/i/<jeton>`), demande prénom et lien, fait le POST sur `u`,
  puis enregistre `serverURL = server + "/k/" + key` et `helperKey = key`, et se connecte.
- Le scanner de l'app accepte `papai://pair?u=…` comme l'ancien `https://…/p/<code>`.
- Saisie du code à la main : le support ne tape que le code, jamais d'adresse. POST sur
  `<serverURL réglé>/p/<code>`, ou sur `https://papai-450417131702.europe-west1.run.app/p/<code>`
  (serveur officiel) si l'app n'est pas encore réglée. En ligne, `GET /p`, `GET /p/<code>` et
  `POST /p/<code>` répondent donc aussi sans clé : le code est le secret (une seule fois, 10 min
  pour le code ; 24 h pour le jeton d'invitation), et la réponse donne `server` et `key` après accord. Voir « Plusieurs espaces » : le code tapé
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
- **Liaison** (`POST /p/<code>`, `POST /i/<jeton>` ou compatibilité `POST /k/<clé>/p/<code>`) :
  sans clé, le serveur cherche l'espace dont le code est valide. Prénom nettoyé (40 caractères)
  et lien nettoyé (60) : lettres accentuées, chiffres, espace et `-'.` conservés, contrôles et
  caractères HTML retirés. Prénom vide → 400 « Indiquez votre prénom. », sans compter d'essai.
  En ligne (`PAPAI_PUBLIC=1`), l'ordinateur doit accepter le support sur toutes ces routes :
  même une URL contenant la clé peut être photographiée.
  - serveur → pont : `{"type":"pair_confirm","req":N,"name","relation"}` ;
  - pont → serveur : `{"type":"pair_decision","req":N,"accept":true|false}`.
  Le code ou jeton est consommé immédiatement avant l'envoi (aussi si l'ordinateur est déjà hors ligne),
  une seule demande en attente par espace/ordinateur. Accord, refus, délai ou ordinateur absent :
  la valeur consommée ne ressert jamais. Un jeton inconnu, expiré ou consommé donne INVALID_CODE.
  Un code qui expire pendant l'attente n'empêche pas l'ajout après accord. Délai : 120 s,
  surchargeable par `PAPAI_PAIR_CONFIRM_S`. Sur délai/annulation, serveur → pont :
  `{"type":"pair_confirm_closed","req":N}` ferme la demande sans réponse ; identifiant inconnu ignoré.
  - 200 après accord seulement : `{"ok":true,"name","id","senior","aidant_url","server","key"}`.
    Les supports déjà reliés reçoivent `{"type":"helper_added","name":…}` avant l'ajout du nouveau support,
    sans inclure celui-ci. Notice : « <prénom> est maintenant support. » (texte littéral).
    Le pont reçoit `helpers` avec `added` comme auparavant.
  - 400 pour code/jeton faux, expiré, consommé, ordinateur déjà hors ligne ou demande déjà en attente :
    « Ce code ne marche plus. Demandez un nouveau code sur l'ordinateur de la personne aidée. »
  - 403 : `{"ok":false,"refused":true,"error":"La personne aidée a refusé. Rien n'a été partagé."}`.
  - 408 : « Pas de réponse sur l'ordinateur. Demandez un nouveau code sur l'ordinateur de la personne aidée. »
  - 409 si pont déconnecté ou remplacé pendant l'attente : « L'ordinateur de la personne aidée n'est pas connecté.
    Allumez-le, ouvrez PapAI, puis réessayez. » Aucun accès partagé, code/jeton déjà consommé.
  - 429 au 11e essai faux en 10 min glissantes par IP : « Trop d'essais. Réessayez dans quelques minutes. »
    Une IP bloquée doit attendre même pour un code juste. Quand l'espace est connu, 5 erreurs suffisent
    à invalider son code. Les historiques d'IP sont bornés à 10 000 entrées.
    Sur `/p/<code>` et `/i/<jeton>`, un plafond global de 300 essais faux par 10 minutes glissantes
    couvre toutes les IP : une fois atteint, INVALID_CODE (400), avant toute recherche/validation du code,
    y compris pour une valeur juste. Après la fenêtre, la recherche reprend. Ce plafond précède la limite IP.
  Tout échec retourne `ok:false` et `error`, sans `server`, `key` ni `aidant_url` et sans ajout.
  IP : adresse cliente directe en local ; en ligne, **dernière** entrée de `X-Forwarded-For` si présent
  (les préfixes fournis par le client ne font pas foi). Même règle pour créations d'espaces et d'organisations.
  **Mode local** (sans `PAPAI_PUBLIC`) : pas d'accord sur l'ordinateur, pour le développement seulement ;
  nettoyage des libellés, usage unique et limite des essais faux restent appliqués.
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

- `pair_code` porte `expires_in` (600 ou 86400) et `long` (vrai pour une invitation opaque `/i/<jeton>`, `code:null`). `app_url` = `papai://pair?u=<url encodée>&n=<prénom encodé>` ; aucune clé dans ce lien.
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
- Le plan peut annoncer `where: "desktop"` ou `"web"` comme auparavant. Pour une
  tâche qui commence sur le bureau et passe par un ou plusieurs sites, Holo peut
  proposer `where: "mixed"` avec `web_steps` (numéros d'étapes à partir de 1) et
  `sites` (de 1 à 3 domaines en minuscules, sans schéma ni chemin). Le serveur
  valide ces champs et préfixe les étapes web visibles au proche par
  « Dans Chrome PapAI (domaine) : ». Un domaine absent ou invalide ramène le plan
  à `"desktop"` ; il en va de même sans numéro d'étape web valide.
- Serveur → apps, `status.where` : `"web"`, `"desktop"` ou `null` ; `"mixed"`
  n'est jamais envoyé. Avant validation, un plan mixte garde `where` à
  `"desktop"` ; sinon `where` reflète le lieu proposé par Holo. Après validation,
  `where` indique le mode réellement utilisé (`"desktop"` si le Mac n'a pas
  annoncé cette capacité ou si le démarrage du navigateur échoue). Dans une
  session mixte, il passe de `"desktop"` à `"web"` pendant la sous-tâche
  navigateur, puis revient à `"desktop"` quand le résumé est rendu à Holo. Les
  apps l'ignorent si absent.
- `open_browser` n'est proposé que si le plan validé est mixte et que
  `hello.web_agent_available` est vrai. Si le navigateur n'est pas disponible,
  l'agent bureau fait toute la tâche. L'outil porte un `goal` obligatoire et une
  `url` HTTPS facultative. L'appel doit annoncer une étape `plan_step` incluse
  dans `web_steps`. L'hôte doit être un des domaines validés ou un de leurs
  sous-domaines ; sans URL, le premier domaine du plan est utilisé.
  Le Gardien vérifie chaque domaine au moment du plan, puis l'URL et l'objectif
  avant de démarrer Chrome PapAI. L'agent web reçoit l'objectif, le plan validé
  comme contexte et la liste des sites autorisés, puis rend un résumé à l'agent
  bureau ; il ne termine pas la session. Un site hors plan ne démarre pas Chrome.
  Au plus trois bascules sont possibles par session. Le mode pur `where: "web"`
  reste inchangé.
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
  `holo local stop` et ferment le process Chrome PapAI, même hors ligne. Chrome
  part d'un profil neuf et temporaire à chaque assistance ; quand il est fermé,
  son profil est effacé. La personne aidée se connecte elle-même à ses sites,
  sans compte, identifiant ni cookie retenu d'une assistance à l'autre.
- Limite : `holo local browser` exige une clé H (`HAI_API_KEY`) sur le Mac de
  la personne aidée (`~/.config/hai/.env` ou variable d'environnement). Elle
  n'est jamais dans le dépôt ni dans les journaux.

## Brouillon d'automate (support)

`POST /automations/draft` (local) ou `/k/{clé}/automations/draft` : Holo prépare un brouillon, **rien n'est écrit**.
- Document : `{"kind":"document","name":"tuto.pdf","text":"…"}` (texte extrait sur le poste du support, PDF compris ; 20 000 caractères au plus).
- Enregistrement : `{"kind":"recording","frames":[{"b64":"…","mime":"image/jpeg"}],"narration":"…"}` (5 captures clés au plus, voix transcrite sur le poste du support).
- Réponse : `{"title","description","goal","steps":["…"],"platforms":["mac"|"windows"],"warning"}`, ou `{"error"}` (422 source inexploitable, 502 Holo injoignable).

Le support relit le brouillon, l'ajoute à « Mes automates » (bibliothèque gardée sur son poste), puis l'applique à qui il veut avec `POST /automations` : c'est cet import qui le valide.
