# PapAI Gardien

Extension Manifest V3 pour Chrome, Edge et Brave, sur Mac et Windows. Aucun outil
de build ni dépendance : le dossier est prêt à charger.

## Installer et lier

1. Ouvrez `chrome://extensions` dans Chrome, `edge://extensions` dans Edge ou
   `brave://extensions` dans Brave. Activez le **mode développeur**.
2. Choisissez **Charger l'extension non empaquetée** et sélectionnez ce dossier
   `extension/`. Épinglez **PapAI Gardien** dans la barre du navigateur.
3. Dans les Réglages de PapAI, demandez un code de protection du navigateur.
   Le popup contient par défaut l'adresse du serveur officiel ; choisissez
   **Autre serveur** pour en saisir une autre. Entrez le code à six chiffres.
4. Le message **Ce navigateur est protégé** confirme la liaison. **Retirer la protection** efface
   le jeton et les avis locaux. Si le serveur perd le jeton, un nouveau code sera
   demandé à la prochaine vérification.

Sur le Mac, la ligne **Protéger le navigateur** des Réglages affiche le code et
l'adresse du serveur. Un code expiré peut être renouvelé avec **Afficher le code**.

## Ce qui est transmis

Lors d'un changement de domaine, uniquement : **nom de domaine**, titre (300
caractères maximum) et extrait du texte visible (2 000 caractères maximum).
L'extrait envoyé peut contenir des données personnelles affichées dans la page.
Les champs de saisie, zones éditables et textes cachés sont exclus. Jamais les
valeurs des champs, mots de passe, cookies, URL complète ou paramètres d'URL.
Le jeton d'extension n'est pas une clé famille et ne donne aucun contrôle sur
l'ordinateur. Les requêtes n'envoient pas de cookies.

Les domaines de `sites_connus.json` et leurs sous-domaines ne déclenchent aucune
requête, sauf les exclusions indiquées dans ce fichier. Les avis sont conservés
localement 24 heures pour `sur`, une heure
pour `douteux` et `arnaque` ; le texte de la page n'est pas conservé. Un site
douteux affiche une bannière ; une arnaque probable affiche un voile avec le
prénom du proche. **Quitter ce site** ouvre une page vide dans le même onglet.
Les hôtes locaux, adresses IPv4 privées et l'hôte du serveur lié sont exclus des
signalements par l'extension et le serveur.
Une panne réseau ne produit jamais un faux avis rassurant. Le gardien ne garantit
pas de reconnaître toutes les arnaques et ne remplace pas un proche.

Les autorisations `storage`, `webNavigation` et l'accès aux serveurs autorisés
servent à mémoriser la liaison, repérer les changements de domaine, lire
l'extrait et joindre le serveur. L'accès à un autre serveur HTTPS est demandé
au moment de la liaison ; HTTP est refusé hors `127.0.0.1` et `localhost`.
Aucun accès aux cookies, à l'historique ou aux captures d'écran.

Safari viendra plus tard via `safari-web-extension-converter` : non fait ici.
