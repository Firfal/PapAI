# Pitch PapAI : script (3 min, 8 slides)

Pour le dimanche 8 novembre, 14 h. Deck : `docs/pitch/deck-local.html`, à ouvrir dans Chrome.
- `F` passe en plein écran.
- `→`, espace ou un clic font avancer ; un clic sur le tiers gauche fait reculer.
- `1` à `8` ouvrent directement une slide.

Le deck marche hors ligne, sauf les polices (sans réseau, il prend celles du système).

**Rôles.**
- Une seule voix, qui parle face au jury.
- Une deuxième personne au Mac et à l'iPhone, qui fait les gestes en silence.

**Le fil, en une phrase par slide :**
1. Une demande.
2. Ce qu'elle coûte.
3. La boucle.
4. La démo.
5. Une fois, partout.
6. Sous contrôle.
7. Rien à installer.
8. La phrase de fin.

Environ 380 mots, soit 130 mots par minute : un débit calme, avec de la place pour les silences.

## Le minutage

**0:00-0:15 · Slide 1, « Je ne retrouve plus le dossier des factures. »**
- Geste : on laisse la phrase se taper, puis un temps de silence.
- À dire : « Christine est comptable. Il est 9 h 12, et elle ne retrouve plus son dossier de factures. Elle fait comme tout le monde : elle ouvre un ticket, et elle attend. »

**0:15-0:30 · Slide 2, 22 $**
- Geste : le chiffre monte.
- À dire : « Une demande de niveau 1 coûte en moyenne 22 dollars. Et le plus souvent, le support connaît déjà la réponse : il l'a donnée cent fois. »

**0:30-0:50 · Slide 3, la boucle**
- Geste : la ligne relie les quatre étapes.
- À dire : « PapAI, c'est le support informatique de premier niveau, avec un agent qui agit. Christine demande, à la voix. Holo, le modèle d'H Company, regarde son écran et propose un plan. Le support le valide depuis son téléphone. Et alors seulement, Holo exécute. »

**0:50-1:50 · Slide 4, en direct (LIVE)**
- Geste : on bascule sur le Mac, puis on suit les repères LIVE ci-dessous.
- Christine dicte sa demande : « Christine parle, Gladia transcrit. »
- Le plan arrive sur l'iPhone : « Le plan arrive chez le support. Rien n'a encore bougé. »
- Valider, puis Holo agit : « Je valide. Holo ouvre le Finder, puis Documents, puis le dossier. Christine voit chaque étape, et elle peut tout arrêter. »
- À « C'est fait » : « Ticket résolu, sans que personne se déplace. »

**1:50-2:10 · Slide 5, réglé une fois, rejoué partout**
- Geste : les postes s'allument.
- À dire : « Une demande réglée devient un automate. Le support l'envoie à toute l'organisation, et chaque employé le relance d'un clic : le Wi-Fi, les modèles Word, l'imprimante de l'accueil. »

**2:10-2:30 · Slide 6, sous contrôle**
- Geste : les trois lignes arrivent une à une.
- À dire : « Trois règles. Rien sans plan validé. Arrêter, à tout moment. Et Holo ne touche jamais une fenêtre de sécurité : une règle née d'une vraie répétition. En plus, un gardien repère les arnaques à la prise en main. »

**2:30-2:45 · Slide 7, rien à installer**
- Geste : le code s'affiche.
- À dire : « Côté entreprise, l'IT déploie PapAI avec ses outils habituels : stratégie de groupe sur Windows, MDM sur Mac. Christine ouvre l'app : son nom est déjà là, son support aussi. »

**2:45-3:00 · Slide 8, fin**
- Geste : le logotype.
- À dire : « On l'a construit avec Holo, Gladia pour la voix, et Devin dans l'équipe. PapAI : le support valide, Holo exécute. Merci. »

Si l'on est en retard à 2:10, on dit la slide 6 en une phrase : « Rien ne bouge sans plan validé, et on peut tout arrêter. » On gagne 12 s.

## Les repères LIVE (slide 4)

**À préparer avant de monter :**
- Un dossier `~/Documents/Factures 2026` avec 3 ou 4 fichiers neutres, et aucun autre dossier de ce nom.
- PapAI ouverte sur le Mac en « Christine », dans Acme, au premier plan, connectée.
- L'iPhone avec l'app du support ouverte, déjà connectée à Acme, verrouillage auto sur « Jamais ».

**Les gestes, dans l'ordre :**
1. Toucher le micro et dire : « Je ne retrouve plus le dossier des factures. »
2. Lire le plan à voix haute, puis Valider. Si Holo propose autre chose, faire Préciser : « dans le Finder, Documents, Factures 2026 ».
3. Personne ne touche la souris pendant que Holo agit. Holo fait une action toutes les 6 s environ : parler pendant ce temps.
4. Revenir sur le deck dès « C'est fait ».

## Plan B

| Ce qui arrive | Ce qu'on fait |
|---|---|
| Le plan n'arrive pas en 30 s | Rester sur la slide 4, qui montre la vraie carte du support. Dire : « Voici ce que reçoit le support. » Ne jamais dire « en direct ». |
| Holo part ailleurs | Refuser ou Arrêter, puis dire : « Rien ne bouge sans le support : c'est exactement le principe. » Passer à la slide 5. |
| Plus de réseau | Partage de connexion 4G. Sinon, rester sur le deck. |
| Le micro ne répond pas | Taper la demande au clavier. |

## Ce qu'on ne dit pas

- **Pas de « autonome ».** Holo agit après la validation du support, jamais avant.
- **Le 22 $ :** c'est le coût moyen d'un ticket de niveau 1 selon MetricNet (Amérique du Nord), une étude ancienne. On ne cite pas de part des demandes de mot de passe : aucune source primaire trouvée.
- **Les « 60 postes » de la slide 5** illustrent l'organisation de démo Acme. On ne cite pas de client réel.
- **GPO et MDM (slide 7) :**
  - le code est dans les PR #70 (Windows) et #71 (Mac), pas encore fusionnées ;
  - s'il n'est pas fusionné à 14 h, on dit « c'est prévu pour se déployer par GPO et MDM » ;
  - on ne montre jamais un vrai jeton.
- **Pas de « le rejeu n'appelle jamais Holo ».** Certains automates ouvrent un dossier en local, d'autres demandent à Holo de refaire un plan déjà validé.
- **Windows :**
  - l'app existe et suit les mêmes écrans ;
  - la démo d'aujourd'hui se fait sur Mac ;
  - on ne dit pas qu'elle a été essayée de bout en bout sur un vrai Windows.

## Questions probables

1. **« Et si le support ne répond pas ? »**
   Rien ne bouge. La demande devient un ticket en attente, reproposé dès qu'un support se connecte.
2. **« Et si Holo se trompe ? »**
   On peut tout arrêter à tout moment, sur le Mac comme sur le téléphone. Une action en cours est verrouillée.
3. **« Qui voit l'écran ? »**
   Seulement Holo et le support, pendant l'assistance. Hors assistance, le gardien envoie au plus des noms d'apps et de sites, jamais une image.
4. **« Pourquoi pas TeamViewer ? »**
   TeamViewer donne toutes les clés et mobilise un technicien. Ici, le technicien valide en quelques secondes et Holo fait le geste. C'est aussi l'outil que réclament les arnaqueurs, et notre gardien le repère.
5. **« Mots de passe et paiements ? »**
   Holo n'en saisit jamais : les champs protégés et les fenêtres sensibles sont bloqués. La personne se connecte elle-même, puis Holo continue.
6. **« Combien ça coûte ? »**
   Pas de prix aujourd'hui. On le compare aux 22 $ d'une demande de niveau 1.
7. **« Qu'a fait Devin ? »**
   Il a travaillé en sessions parallèles, chacune sur sa branche : l'app Windows, l'app Android, la sécurité des actions sensibles, les tickets, les organisations. Les détails sont dans `docs/soumission.md`.
