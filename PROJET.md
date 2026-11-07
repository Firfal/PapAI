# CarePilot — état du projet

*Mis à jour le 7 novembre 2026. Ce document dit ce qui est construit, ce qui est
prouvé, et ce qui ne l'est pas. Pour installer et lancer, voir [README.md](README.md).
Pour la vision produit et le plan 36 h, voir `carepilot_documentation.html`.*

---

## En une phrase

Une aide informatique à distance où l'IA agit sur le PC d'une personne âgée, le
proche supervise depuis son téléphone, et la personne aidée garde le contrôle.

**Promesse :** aider tout de suite, sans faire attendre un proche disponible, et
sans jamais lui retirer la main sur sa propre machine. L'IA agit ; quand elle
hésite ou que l'action est sensible, elle s'arrête et demande.

Les manipulations résolues sont mémorisées pour être refaites d'un bouton — et,
pour qui le souhaite, réexpliquées pas à pas. Cette dimension pédagogique existe
et fonctionne, mais elle n'est plus la promesse principale.

---

## Où en est-on

Le spike H 0→6 est validé et le MVP tourne de bout en bout sur une vraie machine :
la personne demande, l'agent agit, le proche arbitre quand il faut, et l'arrêt
reste entre les mains de la personne aidée. La mémorisation des manipulations
fonctionne par-dessus.

| Brique | État |
|---|---|
| Visée de Holo sur écran réel | ✅ vérifiée, au pixel près |
| Boucle agent (observer → décider → agir → vérifier) | ✅ tourne |
| Pont Windows + fenêtre de la personne aidée | ✅ tourne |
| Arrêt local, appliqué sur la machine pilotée | ✅ vérifié |
| Page web du proche, avec clic sur capture | ✅ page testée, clic distant jamais exercé |
| Refus côté serveur (session, fraîcheur, consentement) | ✅ 13 contrôles passent |
| Backend conteneurisé, prêt à héberger | ✅ image testée |
| Déclenchement par le proche | ✅ 10 contrôles passent |
| Mémoire : raccourci « faites-le pour moi » | ✅ testé, garde-fou vérifié |
| Mémoire : fiche générée et validée | ✅ testée de bout en bout |
| Mémoire : rejeu pas à pas (secondaire) | ✅ testé, n'exécute aucun clic |
| L'agent ne fait rien sans aval du proche | ✅ 8 contrôles passent |
| Accueil : dossiers et applications fréquents | ✅ détectés sur la machine |
| Escalade `ask_helper` | ⬜ jamais déclenchée en vrai |
| Notification push | ⬜ non commencé |

---


## L'accueil de la personne aidée

Trois choses sur un seul écran, par ordre d'usage attendu :

**Demander de l'aide.** Une phrase, le consentement au partage, un bouton. La
demande prévient le proche, et l'agent attend son arrivée sans rien regarder.

**Ouvrir directement.** Une grille de ses dossiers et applications, triée par ce
qu'elle ouvre réellement — le compteur est local, dans `usage.json`. Une bonne
part des demandes d'aide se résument à « où est mon dossier » et n'ont besoin
d'aucun agent : autant y répondre en un geste, sans réseau, sans capture et sans
modèle.

Les dossiers passent par l'API des dossiers connus de Windows, les applications
par les raccourcis du menu Démarrer. Rien n'est écrit en dur : un autre PC donne
une autre liste.

Un filtre écarte les raccourcis piégeux. Sans lui, « Zoom » tombait sur
*Uninstall Zoom Workplace* — une personne âgée cherchant à appeler sa famille
aurait désinstallé le logiciel. « Calculatrice » attrapait LibreOffice Calc.

**Refaire quelque chose.** Les automatismes enregistrés après une session
réussie, ouverts sans relancer l'agent.


## Architecture

```
PC de la personne aidée          Backend CarePilot               H Company
  bridge/bridge.py                 backend/app.py                  holo3-1-35b
    fenêtre ARRÊTER     ──WS──▶     boucle agent       ──HTTPS──▶   (inférence)
    capture (mss)       ◀─────      verrou de contrôle
    souris/clavier                  sessions, journal
                                          ▲
                                          │ WS + page /h/{jeton}
                                    téléphone du proche
```

**Le PC n'est jamais un serveur.** Le pont est un client : il sort vers le
backend. Aucun port à ouvrir, aucun réglage réseau chez la personne aidée — elle
installe un logiciel, c'est tout. C'est le même principe que TeamViewer, qui fait
sortir les deux extrémités vers un serveur de rendez-vous.

Le pare-feu n'est nécessaire que dans le montage de développement actuel, où le
backend tourne sur le PC et où le téléphone doit donc y entrer.

### Les quatre garanties, et où elles sont appliquées

| Garantie | Où | Pourquoi là |
|---|---|---|
| L'arrêt coupe tout | `bridge/bridge.py` | Un verrou local vaut même si le réseau est coupé ou le serveur mort. Un arrêt qui n'est qu'un message envoyé au serveur n'est pas une garantie. |
| Les demandes du proche sont revalidées | `backend/sessions.py` | Une page restée ouverte ne doit rien pouvoir déclencher. L'interface ne porte aucune garantie. |
| Un seul acteur pilote à la fois | `backend/sessions.py` (`Owner`) | Le proche ne peut cliquer que pendant une pause de l'agent. |
| L'agent ne touche pas à l'interface de sécurité | `bridge/screen.py` | Le refus porte sur des coordonnées, pas sur ce que le modèle croit voir. |

---

## Ce que les tests réels ont trouvé

Sept problèmes, tous découverts en faisant tourner le système sur une vraie
machine — aucun n'aurait été visible en relisant le code.

**La clé API était en dur dans le source**, passée comme *nom* de variable
d'environnement : le script plantait au démarrage et le spike n'avait jamais pu
tourner. La clé a été exposée en clair ; elle doit être révoquée.

**Le mauvais écran était capturé.** `monitors[1]` était commenté « moniteur
principal » : c'est faux dès qu'il y a plusieurs écrans. L'agent regardait un
écran et cliquait dans le repère d'un autre. On sélectionne désormais l'écran
portant `is_primary`, avec un avertissement et un override `HOLO_MONITOR`.

**La température était à 0.8.** Mesuré sur la même capture, même cible : à 0,
quatre tirages donnent `x = 361, 361, 361, 361`. À 0.8, un tir a donné `x = 100`
— **337 pixels à côté**, un clic dans le vide. Les coordonnées étant générées
comme des tokens de texte, elles sont soumises à l'échantillonnage. Pour du
pointage, l'échantillonnage ne sert à rien et coûte des ratés.

**L'agent a fermé sa propre fenêtre d'arrêt.** Il voyait l'interface CarePilot
dans sa capture et a cliqué sur la croix. Corrigé des deux côtés : la fenêtre est
peinte en noir avant l'envoi au modèle, et tout clic visant sa zone est refusé
par le pont.

**`requirements.txt` empêchait tout hébergement.** Il embarquait `pyautogui` et
`mss`, qui exigent un écran et ne s'installent pas sur un serveur Linux. Les
dépendances sont séparées : `requirements-backend.txt` (5 paquets, aucun lien
avec l'affichage) et `requirements-bridge.txt`.

**La fenêtre était illisible en HiDPI.** Géométrie en pixels fixes, polices Tk en
points : sur un écran à 200 %, le titre était tronqué et **le bouton « Demander
de l'aide » tombait hors cadre**. La fenêtre suit maintenant l'échelle de son
texte.

**L'agent partait dans `C:\Users`.** Au lieu des raccourcis de la barre latérale,
il ouvrait « Ce PC », « Disque local (C:) », « Utilisateurs », et se perdait.
Trois règles ajoutées au prompt : aller directement au bon raccourci, ne jamais
ouvrir les chemins techniques, et appeler `ask_helper` après deux essais
infructueux plutôt que de continuer à fouiller.

---

## Ce qui n'est pas prouvé

- **Le clic distant du proche** n'a jamais été exercé depuis un vrai téléphone.
  C'est la fonctionnalité la plus fragile et un critère de votre définition de
  terminé.
- **L'escalade `ask_helper`** n'a jamais été déclenchée. Il faut préparer
  `Photos` et `Photos vacances` et demander « retrouve mes photos de vacances ».
- **Les trois parcours consécutifs** du point de décision H 6 n'ont pas été
  enchaînés.
- **Rien n'est committé.** Le dépôt git existe, les fichiers sont indexés, mais
  il n'y a aucun commit.

---

## Mémoire des manipulations

Une session terminée est mémorisée, pour deux usages d'importance inégale.

**Le raccourci, d'abord** : rouvrir en un geste l'endroit déjà trouvé, sans
relancer l'agent. C'est ce que la personne utilisera dix fois.

**La fiche pas à pas, ensuite** : une explication de 2 à 4 étapes qu'elle peut
suivre seule si elle veut apprendre. Proposée, jamais imposée.

La fiche est rédigée par le modèle à partir de la trajectoire **en texte** — ce que l'agent a visé, jamais où il a
cliqué. Pas de coordonnées dans une fiche : elle ne se périme pas quand une
fenêtre change de taille. Les tâtonnements sont ignorés, seul le chemin qui a
marché est retenu.

Le proche relit sur son téléphone, corrige chaque texte, valide. **C'est
seulement à la validation que des captures sont écrites sur disque**, et
uniquement celles des étapes retenues : avant, elles ne vivent qu'en mémoire.

La personne aidée retrouve ses fiches dans sa fenêtre, bouton « Mes fiches ».
L'affichage est pas à pas : instruction, capture, repère visuel à vérifier.
**Aucun clic n'est exécuté** — vérifié, le rejeu ne déclenche aucune session et
n'envoie aucune action au pont. C'est elle qui fait la manipulation.

```
lessons/lesson-<id>/lesson.json
lessons/lesson-<id>/step-1.png …
```

Le dossier est monté en volume dans le conteneur, donc les fiches survivent aux
redémarrages.

### Refaire sans tout refaire

Une fiche retient aussi sa **destination**, pas son trajet. Pas sous forme de
chemin : le modèle nomme un dossier personnel de Windows — `pictures`,
`downloads`, `documents`, `desktop`, `videos`, `music` — et éventuellement un
sous-dossier. C'est le PC qui résout, à l'ouverture, via l'API Windows des
dossiers connus.

```json
{"folder": "pictures", "subfolder": "Photos vacances"}
```

**Jamais de `C:\Users\<nom>`.** Un chemin écrit en dur casse sur une autre
machine, sous un autre compte, et surtout quand Windows redirige Images ou
Documents vers OneDrive — le cas par défaut sur beaucoup de PC récents.
Demander un chemin au modèle l'invitait en plus à en inventer un : sur un faux
bureau sans barre d'adresse, il avait produit `C:\Users\Utilisateur\Images`.
Avec une liste fermée de six valeurs, il n'y a plus rien à inventer.

La personne aidée a alors le choix — « Montrez-moi comment faire », ou
« Faites-le pour moi », qui ouvre le dossier directement. Ce raccourci **ne
rejoue aucune coordonnée et n'appelle aucun modèle** : instantané, gratuit, et
insensible aux fenêtres qui ont bougé. C'est le « rejeu intelligent » de la
documentation produit, pris par l'autre bout : on ne rejoue pas des clics, on
retient où il fallait arriver.

Le pont vérifie avant d'ouvrir. Mesuré : dossier hors liste, raccourci vide,
chemin glissé dans le nom du sous-dossier, barre oblique, sous-dossier
inexistant, ancien format à chemin — tous refusés. Un sous-dossier absent fait
simplement basculer la fenêtre sur les étapes pas à pas.


### Le proche propose, la personne aidée décide

Un lien permanent, donné une fois au proche (QR dans la fenêtre, bouton
« Inviter un proche »). Ce lien **ne montre aucun écran** : il permet seulement
de proposer son aide. La personne aidée voit la proposition sur sa machine et
l'accepte ou non — et cette acceptation vaut consentement au partage.

Vérifié : jeton d'appairage inventé refusé, proposition refusée quand le PC est
éteint, rien ne démarre avant la réponse, refus transmis au proche, et session
créée avec l'agent lancé seulement après acceptation.

Le jeton est stocké dans le volume des fiches, donc il survit aux
reconstructions : le proche garde le même lien.

## Le modèle

`holo3-1-35b-a3b` — vision-langage, architecture Qwen, mélange d'experts :
35 milliards de paramètres, 3 actifs par token. Il tourne chez H Company ; aucune
variante du projet ne le fait tourner sur le PC de la personne aidée.

Tout se passe **en un seul appel** : la capture est encodée dans le même contexte
que le texte, le modèle génère sa réflexion puis l'appel d'outil. Il n'y a pas de
détecteur d'objets séparé — les coordonnées sortent de la même génération que le
texte. La boucle observer / décider / agir / vérifier est notre code ; le modèle
n'a aucune mémoire entre deux étapes.

**Free tier :** 10 requêtes par minute — une limite de *requêtes*, pas de tokens.
Contexte de 65 536 tokens, 5 images maximum par requête.

**Consommation mesurée :** une session de 5 appels consomme 19 426 tokens, dont
4 545 de contexte au dernier appel — soit **7 % de la limite**. La marge est
large ; on pourrait garder plus de 3 captures en contexte.

**Coût mesuré :** 0,61 centime de dollar pour cette session. Moins de 5 centimes
pour dix sessions.

---

## Décisions prises, et pourquoi

**La boucle agent est sur le backend, pas sur le PC.** Sinon la clé API vit sur
la machine de la personne aidée, le verrou de contrôle n'est pas arbitrable, et
l'état de conversation est du mauvais côté du réseau.

**Une page web pour le proche, pas Telegram ni Claude.** Telegram ne permet pas
de cliquer sur une capture — or c'est un critère de votre définition de terminé.
Un chat tiers est en outre *pull* : votre backend ne peut pas réveiller Claude,
ce qui casse l'escalade. La page est servie par le backend, sans build, avec un
lien signé qui meurt avec la session.

**Pas de chat React.** Une page, une centaine de lignes de JavaScript. Le reste
du budget va à CareMemory.

**Démo en local, sur le partage de connexion du téléphone.** Beaucoup de Wi-Fi
publics isolent les appareils entre eux, ce qui bloque le montage local même
pare-feu ouvert — et ça ne se découvre qu'au moment de la démo.

**Le backend est quand même conteneurisé.** `Dockerfile` et `render.yaml` sont
écrits et l'image testée : c'est le plan B si le réseau du lieu est impraticable,
et un argument de crédibilité devant le jury.

---

## Reste à faire

1. **Éprouver le clic distant** depuis un vrai téléphone. C'est la fonctionnalité
   la plus fragile, et un critère de la définition de terminé.
2. **Déclencher `ask_helper`** avec deux dossiers plausibles (`Photos` et
   `Photos vacances`) : c'est le moment clé de la démo, jamais obtenu en vrai.
3. **Préparer une session Windows de démo** — barre latérale propre, dossiers
   factices. Les captures partent chez H Company et sur le téléphone du proche ;
   aucun dossier client ne doit s'y trouver.
4. **Élargir le raccourci au-delà des dossiers.** Aujourd'hui il ne couvre qu'un
   seul type de résultat : « un dossier est ouvert ». C'est maintenant la
   fonctionnalité principale de la mémoire, elle mérite de couvrir plus de cas.
5. **Notification push** — un bot Telegram porteur de lien suffit.

*Déprioritisé :* enrichir le rejeu pas à pas. Il fonctionne et reste proposé,
mais il n'est plus ce qui porte le produit.

## Points de vigilance pour le pitch

**Pas de chiffrement de bout en bout, contrairement à TeamViewer.** Votre backend
doit *voir* les captures puisqu'il les envoie à Holo. C'est le service rendu, pas
un effet de bord — mais préparez la réponse : ne rien persister par défaut, ne
garder que les captures validées pour une fiche, héberger en Europe.

**La cadence est contrainte.** 10 requêtes/minute imposent une étape toutes les
6,5 secondes. Un parcours de 10 étapes prend un peu plus d'une minute : le
scénario de démo doit être court et déterministe.

**Ne présenter que des chiffres réellement mesurés.** Ceux de ce document le
sont ; ils viennent de sessions enregistrées dans le journal du serveur.
