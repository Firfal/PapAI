# PapAI : script du pitch et découpage de la vidéo

Rendu : dimanche 8 novembre, 14 h (Luma) et 14 h 30 (BuilderBase).
Sources : `README.md`, `HANDOFF.md`, `TODO.md` (P0), `PROTOCOL.md`. Aucun chiffre ni partenaire hors du dépôt.

> **Avant de dire une phrase, vérifier qu'elle est vraie le jour J.** Les passages marqués
> *[si P0 validé]* ou *[si branché]* dépendent de cases encore ouvertes dans `TODO.md`.
> S'ils ne sont pas faits, on les coupe : le jury note la fiabilité (25 %), pas les promesses.

## Ce que le jury note (rappel, `HANDOFF.md`)

| Critère | Poids | Où on le montre |
|---|---|---|
| Computer use | 25 % | Holo regarde l'écran du Mac, propose un plan, puis clique et tape lui-même |
| Fiabilité | 25 % | Rien sans plan validé, Arrêter local, automatisme qui s'arrête quand le dossier a bougé |
| Utilité | 20 % | Un vrai besoin : un proche âgé seul devant son ordinateur, l'aidant loin |
| Originalité | 15 % | L'aidant valide avant l'action ; une réussite devient une tuile rejouable sans modèle |
| UX et contrôle | 10 % | Gros bouton, phrases simples, Valider / Préciser / Refuser, Arrêter toujours visible |
| Démo | 5 % | Une démo réelle, y compris un échec maîtrisé |

---

## 1. Script du pitch (2 min 30, extensible à 3 min)

Environ 150 mots par minute. Le texte à dire est en clair, les indications de scène entre crochets.

### 0:00 – 0:20 · Le problème

[Écran : logo papai, mascotte papaye.]

« Jeanne veut retrouver ses photos de Noël. Elle ne sait pas dans quel dossier elles sont.
Son petit-fils est dans le métro, sans ordinateur. Lui faire installer un logiciel de prise en main ?
C'est exactement ce que demandent les arnaqueurs au téléphone. »

### 0:20 – 0:45 · La promesse

[Écran : les cinq mots de la boucle.]

« PapAI, c'est un agent qui aide votre grand-parent sur son ordinateur, **uniquement avec votre accord**.
Cinq temps : elle demande, Holo propose un plan, vous validez depuis votre téléphone, Holo exécute pendant
qu'elle regarde, et ce qui a marché devient un automatisme qu'elle relance seule.
Une seule règle : **rien ne bouge sans plan validé**. »

### 0:45 – 1:50 · La démo

[Démo en direct ou vidéo de la section 2. Le Mac de Jeanne à gauche, l'iPhone de l'aidant à droite.]

« Jeanne appuie sur "J'ai besoin d'aide" et le dit avec ses mots.
Holo, le modèle d'H Company, regarde son écran et propose un plan en quelques étapes simples.
Sur mon iPhone, je peux valider, préciser ou refuser. Je précise : "dans le Finder, dossier Images, Noël 2025".
Holo refait son plan. Je valide. Seulement maintenant, il agit, et Jeanne voit chaque action expliquée en une phrase.
Elle peut tout arrêter, à tout moment, même si la connexion tombe : le bouton Arrêter est un verrou local sur son Mac.

C'est fait. Je garde ça comme automatisme : une tuile apparaît chez Jeanne. Elle clique, c'est instantané,
sans modèle, sans réseau vers Holo.

Et maintenant, le cas qui compte : on a déplacé le dossier. Jeanne relance la tuile.
PapAI ne cherche pas à l'aveugle : il s'arrête et me prévient. » *[si P0 validé]*

### 1:50 – 2:20 · Pourquoi on peut lui faire confiance

[Écran : schéma Mac ↔ serveur ↔ iPhone, ou liste des garde-fous.]

« Pendant nos répétitions, macOS a ouvert une fenêtre d'autorisation de sécurité. Le plan de Holo proposait de la fermer.
J'ai refusé, et rien n'a bougé. Depuis, Holo a pour consigne de ne jamais toucher une fenêtre d'autorisation ni les Réglages.
C'est tout le principe : un humain de confiance décide, l'agent exécute.

Le reste suit la même logique : la fenêtre PapAI est exclue de ce que Holo voit et de là où il clique,
une capture trop ancienne ne peut pas servir à un clic, et toute demande de l'aidant est revalidée par le serveur. »

### 2:20 – 2:30 · Conclusion

[Écran : logo papai et une phrase.]

« PapAI : l'aide à distance, sans donner les clés de la maison. Ce que vous avez validé une fois, il le refait seul. »

### Rallonge possible (jusqu'à 3 min), à placer avant la conclusion

- **Gardien anti-arnaque** (20 s) *[si branché ; aujourd'hui la logique est testée côté serveur, 14 contrôles, mais l'app Mac n'envoie pas encore les signaux]* :
  « PapAI surveille aussi trois indices textuels, sans capture : les applications ouvertes, le titre de la fenêtre, l'adresse du navigateur.
  AnyDesk qui tourne, une fausse alerte "votre ordinateur est infecté", et surtout un outil de prise en main avec la banque ouverte :
  le proche est prévenu, et Holo lui décrit ce qui est vraiment à l'écran. »
- **Dictée** (10 s) *[si la clé Gladia est en ligne]* : « Jeanne peut aussi dicter sa demande : la transcription est faite par Gladia, côté serveur. »
- **Technique** (10 s) : « Deux apps SwiftUI, un serveur FastAPI sur Cloud Run, et Holo d'H Company pour voir et agir. Le serveur décide, les apps exécutent. »

### Questions probables du jury

| Question | Réponse courte |
|---|---|
| Que se passe-t-il si l'aidant ne répond pas ? | Rien ne bouge. Le plan reste en attente ; la personne peut arrêter. |
| Et si Holo se trompe pendant l'exécution ? | Arrêter coupe tout localement. Holo peut aussi poser une question à l'aidant, qui peut prendre la main sur une capture récente. |
| L'automatisme rappelle-t-il Holo ? | Non : le rejeu est local et sans modèle. S'il ne trouve pas le dossier, il s'arrête et prévient l'aidant (`automation_failed`). |
| Qui voit l'écran ? | Holo, pour la session en cours, et l'aidant. Les routes en ligne sont protégées par une clé famille. |
| Windows ? | Prévu après le Mac ; un prototype existe dans la branche `archive/windows-7-nov`. |

---

## 2. Vidéo de 2 min : découpage plan par plan

Calée sur la démo P0 de `TODO.md` : demande → plan → précision → validation → Holo ouvre `Images/Noël 2025`
→ Arrêter → automatisme → dossier déplacé → alerte.

**Tournage**
- Deux captures synchronisées : l'écran du Mac (enregistrement macOS) et l'iPhone (recopie de l'écran ou enregistrement iOS).
  Montage en écran partagé : Mac à gauche (2/3), iPhone à droite (1/3).
- Bureau dégagé : aucune app en plein écran, PapAI visible, personne ne touche la souris pendant que Holo agit (`HANDOFF.md`, pièges connus).
- App iPhone au premier plan pendant toute la prise : en arrière-plan, la connexion se coupe.
- Créer l'automatisme juste avant la prise : il est perdu à chaque redémarrage du serveur.
- Données de démo : `~/Pictures/Noël 2025/` sur le Mac de démo.
- Vérifier chaque image avant publication : aucune donnée personnelle visible (notifications, autres fenêtres, clé famille dans une URL).
- Holo agit au rythme d'environ une étape toutes les 6,5 s (palier gratuit) : accélérer ces passages au montage (×2 à ×4), en le signalant à l'écran (« accéléré »).

| # | Temps | Image | Ce qui se passe | Voix off / sous-titre |
|---|---|---|---|---|
| 1 | 0:00 – 0:08 | Plein cadre : logo papai, mascotte | Titre | « Jeanne veut retrouver ses photos de Noël. Son petit-fils est dans le métro. » |
| 2 | 0:08 – 0:18 | Mac plein cadre : accueil PapAI | Jeanne tape (ou dicte *[si Gladia en ligne]*) « Je veux voir mes photos de Noël », puis appuie sur « J'ai besoin d'aide » | « Elle demande de l'aide avec ses mots. » |
| 3 | 0:18 – 0:24 | Mac : écran de consentement | « PapAI va regarder votre écran », elle accepte | « Rien n'est regardé sans son accord. » |
| 4 | 0:24 – 0:34 | Écran partagé | Mac en `planning` ; l'iPhone reçoit la demande, puis le plan de Holo | « Holo, le modèle d'H Company, regarde l'écran et propose un plan. » |
| 5 | 0:34 – 0:46 | Gros plan iPhone | L'aidant touche Préciser et écrit « dans le Finder, dossier Images › Noël 2025 » | « Le proche peut valider, préciser ou refuser. Il précise. » |
| 6 | 0:46 – 0:54 | Écran partagé | Nouveau plan sur l'iPhone et sur le Mac ; l'aidant touche Valider | « Nouveau plan. Validé. Rien n'a bougé avant ce moment. » |
| 7 | 0:54 – 1:10 | Mac plein cadre (accéléré) | Holo ouvre le Finder puis le dossier `Noël 2025` ; chaque action est expliquée en une phrase | « Holo exécute. Jeanne voit tout ce qu'il fait. » |
| 8 | 1:10 – 1:18 | Mac : écran de fin | « C'est fait ! », le partage s'arrête | « C'est fait, et le partage d'écran s'arrête. » |
| 9 | 1:18 – 1:26 | Gros plan sur le bouton Arrêter (prise séparée d'une autre session) *[si P0 validé]* | Jeanne appuie sur Arrêter pendant une action ; plus rien ne bouge | « À tout moment, elle peut tout arrêter, même hors ligne. » |
| 10 | 1:26 – 1:36 | Gros plan iPhone, puis Mac | « Garder comme automatisme », brouillon validé ; la tuile apparaît chez Jeanne | « Ce qui a marché devient une tuile. » |
| 11 | 1:36 – 1:42 | Mac | Jeanne clique sur la tuile : le dossier s'ouvre aussitôt | « Un clic, instantané, sans modèle. » |
| 12 | 1:42 – 1:54 | Écran partagé | Le dossier a été déplacé ; Jeanne relance la tuile ; l'app s'arrête, l'iPhone affiche l'alerte | « Le dossier a bougé ? PapAI ne devine pas : il s'arrête et prévient le proche. » |
| 13 | 1:54 – 2:00 | Plein cadre : logo papai | Carton final | « PapAI. Rien ne bouge sans votre accord. » |

**Si un plan n'est pas prêt** : couper le plan 9 (Arrêter) ou le plan 12 (alerte) plutôt que de les simuler,
et redistribuer le temps sur les plans 5 à 7. Ne jamais monter un écran qui n'a pas réellement eu lieu.

**Plan de secours pour le pitch en direct** : si la démo réelle échoue sur scène, passer cette vidéo à partir du plan 2.
