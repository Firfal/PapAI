# PapAI : script du pitch et plan de la vidéo

Rendu : dimanche 8 novembre, 14 h (Luma) et 14 h 30 (BuilderBase).
Relu le 7 novembre à 18 h sur l'état réel : `main`, journal d'`AGENTS.md`, `TODO.md`, `HANDOFF.md`, PR #1 à #9.
Checklist du jour J : [`docs/demo.md`](demo.md).

## Ce qui est vrai aujourd'hui, et ce qui reste à essayer

Le texte du pitch ne dit que ce qui marche. Une phrase suivie d'une marque **[R1]** à **[R6]** dépend d'un essai
**pas encore fait** : si l'essai n'a pas réussi le jour J, **on coupe la phrase**, on ne la promet pas.

| Marque | Essai à faire sur le vrai Mac et le vrai iPhone | État au 7 nov., 18 h |
|---|---|---|
| R1 | Holo clique pour de vrai sur le Mac (CGEvent) et ouvre `Images › Noël 2025` dans le Finder | jamais fait en réel |
| R2 | Préciser puis Valider depuis l'app iPhone sur l'appareil (gestes réels) | fait sur simulateur seulement |
| R3 | Arrêter pendant une action : plus rien ne passe, même réseau coupé | logique écrite (verrou local), jamais essayée en réel |
| R4 | « Garder comme automatisme » sur l'iPhone, la tuile apparaît sur le Mac et rouvre le dossier | jamais fait en réel |
| R5 | Dossier déplacé, tuile relancée : le Mac s'arrête, l'iPhone reçoit l'alerte | jamais fait en réel |
| R6 | Gardien anti-arnaque branché sur le Mac | PR #8 ouverte, pas fusionnée |

**Vérifié** (sans marque) : le serveur sur Cloud Run déployé depuis `main` ; rien ne bouge avant validation
(tests protocole 13/13, gardien 14/14) ; le plan refait après une précision (en ligne, avec un faux Mac) ; le refus d'un
plan sur le vrai Mac de Quentin ; la dictée de l'app Mac par Gladia (en ligne, essayée par Quentin) ; la consigne
« ne jamais toucher une fenêtre d'autorisation », ajoutée après une vraie répétition.

## Ce que le jury note (`HANDOFF.md`)

| Critère | Poids | Où on le montre |
|---|---|---|
| Computer use | 25 % | Holo regarde l'écran du Mac, propose un plan, puis clique lui-même [R1] |
| Fiabilité | 25 % | Rien sans plan validé ; l'automatisme s'arrête si le dossier a bougé [R5] |
| Utilité | 20 % | Un proche âgé seul devant son ordinateur, l'aidant loin et sans PC |
| Originalité | 15 % | L'aidant valide avant l'action ; une réussite devient une tuile rejouée sans modèle |
| UX et contrôle | 10 % | Gros bouton, dictée, phrases simples, Valider / Préciser / Refuser, Arrêter |
| Démo | 5 % | Une démo réelle, y compris un échec maîtrisé (l'alerte) |

---

## 1. Script mot à mot (2 min 30, 3 min avec la rallonge)

Environ 150 mots par minute. Le texte à dire est en clair, les indications de scène entre crochets.
Démo en direct pendant 0:40 – 1:45 ; si elle cale, on passe la vidéo (section 2) et on dit le même texte.

### 0:00 – 0:20 · Le problème

[Écran : logo papai.]

« Jeanne a 81 ans. Elle veut revoir ses photos de Noël, et elle ne sait plus où elles sont.
Son petit-fils est dans le métro, sans ordinateur. Lui faire installer un logiciel de prise en main à distance ?
C'est exactement ce que demandent les arnaqueurs au téléphone. »

### 0:20 – 0:40 · La promesse

[Écran : demander, proposer, valider, exécuter, garder.]

« PapAI, c'est un agent qui aide votre grand-parent sur son ordinateur, uniquement avec votre accord.
Elle demande. Holo, le modèle d'H Company, propose un plan. Vous validez depuis votre téléphone.
Holo exécute sous ses yeux. Et ce qui a marché devient un bouton qu'elle relance seule.
Une seule règle : rien ne bouge sans plan validé. »

### 0:40 – 1:45 · La démo

[Mac de Jeanne à l'écran, iPhone de l'aidant dans la main, recopié à côté si possible.]

« Jeanne appuie sur le micro et dit : "Je veux voir mes photos de Noël."
Elle n'a rien à taper : c'est Gladia qui transcrit sa voix, en français.
Elle accepte que PapAI regarde son écran.

Holo regarde l'écran et propose un plan. Sur mon iPhone, je peux valider, préciser ou refuser. [R2]
Je précise : "dans le Finder, Images, Noël 2025". Holo refait son plan. Je valide.
Jusqu'ici, rien n'a bougé sur son ordinateur.

Maintenant seulement, Holo agit : il ouvre le Finder, puis le dossier Noël 2025. [R1]
Jeanne lit chaque action en une phrase simple, et l'étape du plan en cours. [R1]
Elle peut tout arrêter à tout moment : le bouton Arrêter est un verrou sur son Mac. [R3]

C'est fait. Je garde ça comme automatisme. Un bouton apparaît chez Jeanne. [R4]
Elle clique : le dossier s'ouvre aussitôt, sans rappeler Holo. [R4]

Et maintenant, le cas qui compte : quelqu'un a déplacé le dossier. Jeanne relance le bouton.
PapAI ne cherche pas à l'aveugle : il s'arrête, et je reçois une alerte. » [R5]

### 1:45 – 2:05 · Pourquoi on peut lui faire confiance

« Pendant une répétition, macOS a ouvert une fenêtre d'autorisation. Le plan de Holo proposait de la fermer.
J'ai refusé, et rien n'a bougé. Depuis, Holo a pour consigne de ne jamais toucher une fenêtre d'autorisation.
C'est tout le principe : un proche de confiance décide, l'agent exécute. »

### 2:05 – 2:25 · Comment on l'a construit

« Holo pour voir et agir. Gladia pour la voix de Jeanne. Et une équipe d'humains et d'agents.
Devin a travaillé en sessions parallèles, chacune sur sa branche : la page web de l'aidant,
la rédaction fiable des automatismes, l'étape du plan affichée en direct, un test de bout en bout,
la compilation de l'app Mac sur macOS, ce pitch, et une app Windows au même design. »

### 2:25 – 2:30 · Conclusion

[Écran : logo papai.]

« PapAI : l'aide à distance, sans donner les clés de la maison. »

### Rallonge (jusqu'à 3 min), avant la conclusion

- **Garde-fous** (15 s), vérifié dans le code : « La fenêtre PapAI est exclue de ce que Holo voit et de là où il clique.
  Une capture de plus de 30 secondes ne peut pas servir à un clic du proche. Mot de passe, paiement, suppression : Holo pose la question au proche. »
- **Gardien anti-arnaque** (20 s) [R6] : « PapAI regarde aussi trois indices textuels, sans capture : les applications ouvertes,
  le titre de la fenêtre, l'adresse du navigateur. AnyDesk avec la banque ouverte ? Le proche est prévenu. »
  Si R6 n'est pas fait : « La détection est écrite et testée, 14 contrôles ; on la branche sur le Mac. »
- **Technique** (10 s) : « Deux apps SwiftUI, un serveur FastAPI sur Cloud Run. Le serveur décide, les apps exécutent. »

### Questions probables du jury

| Question | Réponse courte |
|---|---|
| Et si l'aidant ne répond pas ? | Rien ne bouge. Le plan reste en attente ; Jeanne peut arrêter. |
| Et si Holo se trompe en cours de route ? | Arrêter coupe tout sur le Mac. Holo peut aussi poser une question au proche, qui peut prendre la main sur une capture récente. |
| L'automatisme rappelle-t-il Holo ? | Non : l'app ouvre un dossier connu du système. S'il n'existe plus, elle n'invente rien et prévient le proche (`automation_failed`). |
| Qui voit l'écran ? | Holo pendant la session, et le proche. Les routes en ligne sont protégées par une clé famille. |
| Où sont gardés les automatismes ? | Aujourd'hui sur le serveur, une seule instance : ils disparaissent à un redéploiement. Le stockage durable est la suite. |
| Et la dictée sans réseau ? | Gladia côté serveur ; en secours, la reconnaissance vocale d'Apple sur le Mac. |
| Windows ? | Une app Windows au design du Mac est dans le dépôt (PR #7 et #9). Une session a été essayée sur un vrai écran Windows, mais l'app complète pas encore : on ne la montre pas aujourd'hui. |
| Qu'a fait Devin exactement ? | Voir `docs/soumission.md`, section « Prix Devin » : PR #1 à #5, #7 et #9 fusionnées ; #6 et #8 ouvertes. |

---

## 2. Vidéo de 2 min : plan par plan

Même scénario que la démo (`docs/demo.md`) : demande dictée → plan → précision → validation → Holo ouvre
`Images › Noël 2025` → garder comme automatisme → rejeu → dossier déplacé → alerte.

**Tournage**
- Deux captures en même temps : l'écran du Mac (enregistrement macOS, `Cmd + Maj + 5`) et l'iPhone (enregistrement d'écran iOS).
  Montage en écran partagé : Mac à gauche (2/3), iPhone à droite (1/3).
- Bureau dégagé, aucune app en plein écran, aucune fenêtre d'autorisation ouverte, personne ne touche la souris quand Holo agit.
- Notifications coupées (Ne pas déranger) sur le Mac et l'iPhone. Aucune clé famille visible (réglages, URL, terminal).
- Holo fait au plus une action toutes les 6,5 s (`MIN_SECONDS_PER_STEP`) : accélérer ces passages (×2 à ×4) et écrire « accéléré » à l'écran.
- Ne jamais monter un plan qui n'a pas eu lieu : si un essai R manque, on coupe le plan correspondant.

| # | Temps | Image | Ce qui se passe | Sous-titre ou voix off | Dépend de |
|---|---|---|---|---|---|
| 1 | 0:00 – 0:08 | Plein cadre : logo papai | Titre | « Jeanne veut revoir ses photos de Noël. Son petit-fils est dans le métro. » | |
| 2 | 0:08 – 0:20 | Mac : accueil PapAI | Jeanne touche le micro, dit « Je veux voir mes photos de Noël », le texte apparaît | « Elle dicte. Gladia transcrit. » | |
| 3 | 0:20 – 0:26 | Mac : « PapAI va regarder votre écran » | Elle accepte | « Rien n'est regardé sans son accord. » | |
| 4 | 0:26 – 0:36 | Écran partagé | Mac en attente ; l'iPhone reçoit la demande puis le plan de Holo | « Holo, d'H Company, regarde l'écran et propose un plan. » | R2 |
| 5 | 0:36 – 0:48 | Gros plan iPhone | Préciser : « dans le Finder, Images › Noël 2025 » | « Le proche peut valider, préciser ou refuser. Il précise. » | R2 |
| 6 | 0:48 – 0:56 | Écran partagé | Nouveau plan sur les deux écrans ; Valider | « Validé. Rien n'a bougé avant ce moment. » | R2 |
| 7 | 0:56 – 1:12 | Mac (accéléré) | Holo ouvre le Finder puis `Noël 2025` ; phrase simple et étape du plan à l'écran | « Holo exécute. Jeanne voit tout. » | R1 |
| 8 | 1:12 – 1:18 | Mac : « C'est fait ! » | Le partage d'écran s'arrête | « C'est fait, et le partage s'arrête. » | R1 |
| 9 | 1:18 – 1:30 | iPhone puis Mac | « Garder comme automatisme », brouillon validé ; la tuile apparaît chez Jeanne | « Ce qui a marché devient un bouton. » | R4 |
| 10 | 1:30 – 1:36 | Mac | Jeanne clique la tuile : le dossier s'ouvre aussitôt | « Un clic, sans rappeler Holo. » | R4 |
| 11 | 1:36 – 1:50 | Écran partagé | Dossier déplacé ; tuile relancée ; « Je ne retrouve pas ce dossier » sur le Mac, alerte sur l'iPhone | « Le dossier a bougé ? PapAI ne devine pas : il prévient le proche. » | R5 |
| 12 | 1:50 – 2:00 | Plein cadre : logo papai | Carton : « Holo · Gladia · Devin » | « PapAI. Rien ne bouge sans votre accord. » | |

- **Plan en option** (prise séparée, si R3 est fait) : Jeanne appuie sur Arrêter pendant une action, plus rien ne bouge. 6 s, pris sur les plans 7 et 8.
- **Si R4 ou R5 manque** : couper les plans 9 à 11, rallonger les plans 5 à 7, et finir sur « Ce qui a marché pourra devenir un bouton » (au futur, sans image).
