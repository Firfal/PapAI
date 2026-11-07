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

## App de la personne aidée (Mac, puis Windows) : `ws://SERVEUR/ws/bridge`

Envoie :
- `{"type":"hello","os":"macos"}` à chaque connexion.
- `{"type":"help_request","task":"…"}` quand elle appuie sur « J'ai besoin d'aide ».
- `{"type":"stop"}` bouton Arrêter. **Le verrou local passe d'abord** : plus aucune action exécutée, même hors ligne.
- `{"type":"frame","req":R,"frame_id":"…","png_b64":"…","width":W,"height":H}` en réponse à `capture`. La fenêtre PapAI est exclue de la capture.
- `{"type":"result","req":R,"result":"texte","refused":false}` en réponse à `execute`. `refused:true` si arrêt ou action interdite.
- `{"type":"automation_failed","title":"…","detail":"…"}` quand un automatisme ne peut pas se rejouer (dossier absent). Le serveur prévient l'aidant.

Reçoit :
- `{"type":"capture","req":R}`
- `{"type":"execute","req":R,"action":{"name":N,"args":{…}}}` avec N parmi
  `click`, `double_click` (`x`,`y`,`element`), `type_text` (`text`),
  `press_key` (`keys`, ex. `cmd+space`, `enter`, `esc`), `scroll` (`x`,`y`,`direction`).
- `{"type":"session","id":…,"helper_url":…}`
- `{"type":"status", …}` (voir plus bas), `{"type":"answer","content":"…"}`, `{"type":"alert",…}`, `{"type":"usage",…}`

## App de l'aidant (iPhone) : `ws://SERVEUR/ws/aidant/CLÉ`

Lien permanent : suit toujours la dernière demande, reste ouvert entre deux demandes.
La clé est affichée au démarrage du serveur (`PAPAI_AIDANT_KEY` dans `.env` pour la figer).

Reçoit :
- `{"type":"hello","bridge":true,"os":"macos"}`
- `{"type":"status","session":id,"state":…,"task":"…","plan":["…"]|null,"plan_approved":bool,"question":{"question":"…","options":["…"]}|null,"usage":{…}}`
- `{"type":"frame","frame_id":"…","png_b64":"…"}` capture de l'écran de l'aîné
- `{"type":"question","question":"…","options":["…"]}`
- `{"type":"answer","content":"…"}` fin de tâche
- `{"type":"alert","title":"…","detail":"…"}` un automatisme a échoué
- `{"type":"lesson_pending"}`, `{"type":"lesson_draft","lesson":{…},"preview":{frame_id:png_b64}}`, `{"type":"lesson_saved","lesson":{…}}`
- `{"type":"refused","reason":"…"}`, `{"type":"ack","what":"pause|click"}`

Envoie :
- `{"type":"approve_plan"}` · `{"type":"refine_plan","text":"précision"}` · `{"type":"refuse_plan"}`
- `{"type":"answer","text":"…"}` réponse à une question
- `{"type":"pause"}` · `{"type":"refresh"}` · `{"type":"click","frame_id":"…","x":0..1,"y":0..1}` (seulement en `awaiting_helper`)
- `{"type":"draft_lesson"}` puis `{"type":"approve_lesson","lesson":{"title":"…","steps":[{"instruction":"…"}]}}` = « Garder comme automatisme »

## Automatismes

`GET /lessons` renvoie les automatismes validés. Chacun a `title`, `steps`
(pas à pas, mode « Montre-moi ») et `shortcut` `{"folder":"pictures","subfolder":"Noël 2025"}`
que l'app rejoue **localement, sans modèle** : elle ouvre le dossier connu du système.
Si le dossier n'existe plus, elle n'invente rien : `automation_failed`.
`GET /lessons/{id}/{image}` sert les captures des étapes.
