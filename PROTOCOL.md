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
- `{"type":"help_request","task":"…"}` quand elle appuie sur « J'ai besoin d'aide ».
- `{"type":"stop"}` bouton Arrêter. **Le verrou local passe d'abord** : plus aucune action exécutée, même hors ligne.
- `{"type":"frame","req":R,"frame_id":"…","png_b64":"…","width":W,"height":H}` en réponse à `capture`. La fenêtre PapAI est exclue de la capture.
- `{"type":"result","req":R,"result":"texte","refused":false}` en réponse à `execute`. `refused:true` si arrêt ou action interdite.
- `{"type":"automation_failed","title":"…","detail":"…"}` quand un automatisme ne peut pas se rejouer (dossier absent). Le serveur prévient l'aidant.
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
- `{"type":"lessons_changed","title":"…"}` le proche vient de valider un tutoriel : l'app relit `/lessons`.
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
- `{"type":"alert","title":"…","detail":"…"}` un automatisme a échoué
- `{"type":"lesson_pending"}`, `{"type":"lesson_draft","lesson":{…},"preview":{frame_id:png_b64}}`, `{"type":"lesson_saved","lesson":{…}}`
  Chaque étape du brouillon a un `frame` : une vraie capture de la session, présente dans `preview`. Jamais d'image fabriquée. Sans aucune capture, le serveur répond `refused`.
- `{"type":"refused","reason":"…"}`, `{"type":"ack","what":"pause|click"}`

Envoie :
- `{"type":"approve_plan"}` · `{"type":"refine_plan","text":"précision"}` · `{"type":"refuse_plan"}`
- `{"type":"answer","text":"…"}` réponse à une question
- `{"type":"pause"}` · `{"type":"refresh"}` · `{"type":"click","frame_id":"…","x":0..1,"y":0..1}` (seulement en `awaiting_helper`)
- `{"type":"remote_request","text":"…","from":"Claire"}` proposer une session (seulement s'il n'y en a pas d'ouverte). Réponses : `ack` `remote_request`, puis `remote_refused` ou `remote_accepted`.
- `{"type":"draft_lesson"}` puis `{"type":"approve_lesson","lesson":{"title":"…","steps":[{"instruction":"…"}]}}` = « Garder comme automatisme »
  Si Holo n'a pas pu rédiger la fiche, le serveur répond `refused` après `lesson_pending` : l'app arrête d'afficher « Rédaction en cours… ».

## Dictée de la demande

`POST /k/{clé}/transcribe` : corps = audio brut (`Content-Type: audio/wav` ou
`audio/m4a`, 5 Mo max), rien n'est écrit sur le disque. Réponse `{"text":"…"}`.
Gladia (français) transcrit côté serveur ; la clé `GLADIA_API_KEY` ne quitte
jamais le serveur. Erreurs : 404 mauvaise clé, 503 `{"error":"gladia_absent"}`
(pas de clé Gladia : l'app Mac bascule sur la reconnaissance du Mac),
502 `{"error":"phrase lisible"}`, 413 trop long.

## Gardien anti-arnaque

L'app de la personne aidée observe en continu **trois signaux textuels**, et
n'envoie que ceux-là. Jamais de capture, jamais d'appel au modèle à ce stade :

```json
{"type":"guard",
 "processes":["Safari","AnyDesk"],
 "window":"Votre ordinateur est infecté",
 "url":"https://mabanque.exemple.fr"}
```

Fréquence conseillée : toutes les 5 à 10 secondes. Le serveur évalue
(`backend/guard.py`) et ne répond que s'il reconnaît une situation. Une même
situation ne resonne pas avant 5 minutes — une alerte qui se répète est une
alerte qu'on apprend à ignorer.

Quand ça se déclenche, l'aidant **et** la personne aidée reçoivent :

```json
{"type":"alert","level":"danger|attention|info","title":"…","detail":"…"}
```

Pour les situations visuelles (fausse alerte virus, page de paiement), le
serveur demande **une** capture et fait décrire l'écran par Holo : le proche lit
ce qui s'y trouve vraiment, pas un soupçon technique.

Ce qui est reconnu aujourd'hui : un outil de prise en main qui tourne
(AnyDesk, TeamViewer, UltraViewer…), une fausse alerte « votre ordinateur est
infecté, appelez ce numéro », un site de carte prépayée ou de transfert
irréversible, et la combinaison la plus grave — outil de prise en main **plus**
page bancaire ouverte.

Consulter sa banque seule ne déclenche rien.

## Automatismes

`GET /lessons` renvoie les automatismes validés. Chacun a `title`, `steps`
(pas à pas, mode « Montre-moi ») et `shortcut` `{"folder":"pictures","subfolder":"Noël 2025"}`
que l'app rejoue **localement, sans modèle** : elle ouvre le dossier connu du système.
Si le dossier n'existe plus, elle n'invente rien : `automation_failed`.
`GET /lessons/{id}/{image}` sert les captures des étapes.

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
- Saisie du code à la main : POST sur `<serverURL déjà connu>/p/<code>`.
- Arguments de lancement `-serverURL` et `-helperKey` (dépannage, démo) : l'app les enregistre.

## Prénom et invitation (7 novembre au soir)

- `pair_code` porte `expires_in` (600 ou 86400) et `long` (vrai pour une invitation). `app_url` = `papai://pair?u=<url>&n=<prénom>` : l'app iPhone affiche « Rejoindre Sophie » avant même l'appairage.
- La réponse de `POST …/p/<code>` contient `senior` (prénom de la personne aidée), en plus de `server` et `key`.
- Test : `python tests/test_profil.py http://127.0.0.1:8000 demo` (6 contrôles).

## Question à la personne aidée (`ask_senior`)

- Holo peut poser une question à la personne aidée elle-même, pour une information qu'elle seule connaît (banque, fournisseur, nom). Jamais de mot de passe ni de code.
- `status.question` porte alors `"to":"senior"` (sinon `"helper"`). Le message `question` aussi.
- App de la personne aidée : elle affiche la question et répond par `{"type":"senior_answer","text":"…"}`. L'aidant voit « Question posée à Sophie » et peut aussi répondre (`answer`). La première réponse compte.
- Côté personne aidée, le plan n'est plus affiché : seulement l'avancement (`state`, `plan_step` / longueur du plan).
