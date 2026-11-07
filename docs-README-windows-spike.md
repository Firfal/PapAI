# CarePilot — spike H 0→6 (free tier H Company)

Objectif du spike : prouver sur le PC Windows de démo que Holo (modèle gratuit
`holo3-1-35b-a3b`) sait ouvrir l'Explorateur, retrouver un dossier, s'arrêter
quand on le lui demande, et poser une question au proche quand il hésite.

## Ce que donne le free tier
- Modèle : `holo3-1-35b-a3b` (Models API, OpenAI-compatible, `https://api.hcompany.ai/v1`)
- 10 requêtes / minute — une limite de **requêtes**, pas de tokens (vérifié sur
  la doc H : aucun plafond de tokens/minute sur ce palier). Pas de carte
  bancaire, zéro rétention des données
- Tarifs du modèle, si vous passez en payant : 0,25 $ / M en entrée,
  1,80 $ / M en sortie. Une session mesurée (4 appels, 14 823 tokens) revient à
  **0,46 centime de dollar**
- 5 images max par requête, contexte 65k tokens → on garde les 3 dernières captures
- Coordonnées renvoyées dans [0, 1000], normalisées sur l'image envoyée

## Installation (sur le PC Windows)
```bat
py -3.11 -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env     :: puis coller la clé
```

## Vérifier l'intégration avant toute action (H 0→6)
```bat
python holo_agent.py --check
```
Un seul aller-retour vers Holo, **sans jamais bouger la souris** : valide d'un coup
la clé, le modèle, le format des captures et le fait que Holo renvoie bien des
coordonnées dans [0, 1000]. À lancer en premier : c'est le test qui décide si le
spike passe ou si on bascule sur le plan B.

## Lancer
```bat
python holo_agent.py "Ouvre l'Explorateur de fichiers et affiche le dossier Téléchargements"
```

- Arrêt d'urgence : envoyer la souris dans le coin supérieur gauche (failsafe pyautogui)
  ou créer un fichier `STOP` à côté du script (ce sera le bouton « Arrêter » du senior).
- Quand le modèle appelle `ask_helper`, le script s'arrête et affiche la question :
  c'est le point d'escalade vers le proche. Répondre dans la console pour reprendre.
- Chaque étape écrit un JSON dans `trace.jsonl` + la capture correspondante dans `frames/` :
  c'est la matière première de CareMemory.

## Point de décision (H 6)
Le spike est validé si, 3 fois de suite :
1. le modèle ouvre l'Explorateur et atteint Téléchargements sans aide ;
2. face à deux dossiers plausibles (préparer `Photos` et `Photos vacances`), il appelle `ask_helper` ;
3. le fichier `STOP` coupe l'action avant le clic suivant.

Sinon : plan B de la doc — garder le clic distant du proche via le pont, et limiter H
à l'observation / aux actions réellement fiables.

---

# MVP — trois composants

```
PC de la personne aidée            Backend CarePilot              H Company
  bridge/bridge.py                   backend/app.py                 holo3-1-35b
    fenêtre ARRÊTER      ──WS──▶      boucle agent      ──HTTPS──▶   (inférence)
    capture (mss)        ◀─────       verrou de contrôle
    souris/clavier                    sessions, journal
                                            ▲
                                            │ WS  +  page /h/{jeton}
                                       téléphone du proche
```

## Lancer la démo
```bat
run_backend.bat          :: dans une fenêtre
run_bridge.bat           :: dans une autre
```
La fenêtre CarePilot s'ouvre sur le PC. Cochez le partage, décrivez le problème,
cliquez « Demander de l'aide » : le lien du proche s'affiche dans la fenêtre et
dans la console.

## Où tourne le backend

**Le PC de la personne aidée n'est jamais un serveur.** Le pont est un client :
il sort vers le backend. Rien n'entre sur sa machine, donc aucune règle de
pare-feu, aucun port ouvert, aucun réglage réseau chez elle. Elle installe un
logiciel, et c'est tout.

En production, le backend est hébergé et le pont pointe dessus :
```bat
set CAREPILOT_SERVER=wss://carepilot.exemple.com/ws/bridge
```
En `wss://` sur le port 443, la connexion passe partout — 4G, Wi-Fi d'hôtel,
réseau d'entreprise. Le proche ouvre la même URL publique depuis n'importe où ;
il n'a pas besoin d'être sur le même réseau que la personne aidée.

### Démo du hackathon : tout en local, sur un partage de connexion
Backend et pont sur le PC, téléphone du proche sur le même réseau. L'IP locale
est détectée au démarrage, donc le QR code pointe toujours au bon endroit, même
après un changement de réseau — rien à régler à la main.

**Ne pas utiliser le Wi-Fi du lieu.** Beaucoup de réseaux publics isolent les
appareils entre eux : le téléphone ne verra jamais le PC, pare-feu ouvert ou
non, et ça ne se découvre qu'au moment de la démo. À la place, activez le
partage de connexion du téléphone et branchez le PC dessus. Le réseau est à
vous, l'isolation n'existe pas, et le PC garde un accès Internet pour l'API H.

Il faut quand même autoriser le port une fois sur le PC :
```powershell
New-NetFirewallRule -DisplayName "CarePilot 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Any
```
À retirer après l'évènement (`Remove-NetFirewallRule -DisplayName "CarePilot 8000"`).

### Simuler l'hébergement en local, avec Docker
Le backend tourne dans le conteneur exactement comme il tournerait chez un
hébergeur, et le pont sort vers lui — rien n'entre sur le PC :
```bat
docker build -t carepilot-backend .
docker run -d --name carepilot -p 8000:8000 --env-file .env ^
  -e CAREPILOT_PUBLIC_URL=http://192.168.1.20:8000 carepilot-backend
```
**`CAREPILOT_PUBLIC_URL` est obligatoire ici.** Dans un conteneur, la détection
automatique renverrait l'IP interne Docker (172.x), et le QR code pointerait
vers une adresse que le téléphone ne peut pas joindre.

Ce que ça valide : l'image, les variables, le démarrage, les WebSockets à
travers le conteneur. Ce que ça ne règle pas : le serveur reste sur votre
réseau, donc le pare-feu est toujours nécessaire pour que le téléphone entre.
Seule une adresse publique — hébergeur, ou tunnel type `cloudflared` — supprime
cette étape.

### Suivi de consommation (développement)
La fenêtre affiche en bas : appels, tokens cumulés, et surtout le contexte du
dernier appel rapporté à la limite de 65k du free tier. `CAREPILOT_DEV=0` masque
ce bandeau pour la démo.

## Où sont les garanties
- **L'arrêt est local.** `bridge/bridge.py` vérifie un verrou en mémoire avant
  chaque action. Serveur lent, réseau coupé, backend mort : plus rien ne bouge
  dès que la personne aidée clique sur ARRÊTER.
- **Les refus sont serveur.** `backend/sessions.py` revalide chaque message du
  proche : session ouverte, consentement donné, capture à jour, agent réellement
  en attente. Une page restée ouverte ne peut rien déclencher.
- **Un seul acteur à la fois.** `Owner` ∈ {none, agent, helper}. Le proche ne
  peut cliquer que pendant une pause de l'agent.
- **Les sessions expirent** après 15 min d'inactivité, et une capture de plus de
  30 s ne peut plus servir de repère à un clic.

## Fichiers
| Chemin | Rôle |
|---|---|
| `carepilot_tools.py` | prompt système, outils, contrat Holo (partagé) |
| `bridge/screen.py` | capture, choix du moniteur, actionneurs |
| `bridge/bridge.py` | app Windows : UI senior + pont WebSocket |
| `backend/sessions.py` | cycle de vie, verrou, fraîcheur — toutes les règles |
| `backend/agent.py` | boucle de décision |
| `backend/app.py` | WebSockets et routes |
| `backend/static/helper.html` | page du proche (une page, sans build) |
| `holo_agent.py` | harnais de visée local, sans backend |

## Reste à faire
- CareMemory : relire `trace.jsonl` et produire une fiche de 2 à 4 étapes.
- Déclenchement du côté du proche (il demande, la personne aidée accepte).
- Notification push — un bot Telegram porteur de lien suffit.
