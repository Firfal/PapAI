# PapAI Gardien

Extension Manifest V3 pour Chrome, Edge et Brave, sur Mac et Windows. Aucun outil
de build ni dépendance : le dossier est prêt à charger.

## Installer et lier

1. Ouvrez `chrome://extensions` dans Chrome, `edge://extensions` dans Edge ou
   `brave://extensions` dans Brave. Activez le **mode développeur**.
2. Choisissez **Charger l'extension non empaquetée** et sélectionnez ce dossier
   `extension/`. Épinglez **PapAI Gardien** dans la barre du navigateur.
3. Dans les Réglages de PapAI, demandez un code de protection du navigateur.
   Dans le popup de l'extension, saisissez l'adresse du serveur (sans chemin ni
   clé famille) et le code à six chiffres. Validez.
4. Le message **Ce navigateur est protégé** confirme la liaison. **Délier** efface
   le jeton et les avis locaux. Si le serveur perd le jeton, un nouveau code sera
   demandé à la prochaine vérification.

La commande de code dans les Réglages Mac sera ajoutée à l'étape suivante ; pour
les essais serveur, le pont peut déjà envoyer `ext_pair_start`.

## Ce qui est transmis

Lors d'un changement de domaine, uniquement : **nom de domaine**, titre (300
caractères maximum) et extrait du texte visible (2 000 caractères maximum).
Les champs de saisie, zones éditables et textes cachés sont exclus. Jamais les
valeurs des champs, mots de passe, cookies, URL complète ou paramètres d'URL.
Le jeton d'extension n'est pas une clé famille et ne donne aucun contrôle sur
l'ordinateur. Les requêtes n'envoient pas de cookies.

Les domaines de `sites_connus.json` et leurs sous-domaines ne déclenchent aucune
requête. Les avis sont conservés localement sept jours pour `sur`, une heure
pour `douteux` et `arnaque` ; le texte de la page n'est pas conservé. Un site
douteux affiche une bannière ; une arnaque probable affiche un voile avec le
prénom du proche. **Quitter ce site** ouvre une page vide dans le même onglet.
Une panne réseau ne produit jamais un faux avis rassurant. Le gardien ne garantit
pas de reconnaître toutes les arnaques et ne remplace pas un proche.

Les autorisations `storage`, `webNavigation` et `<all_urls>` servent à mémoriser
la liaison, repérer les changements de domaine, lire l'extrait et joindre le
serveur. Aucun accès aux cookies, à l'historique ou aux captures d'écran.

Safari viendra plus tard via `safari-web-extension-converter` : non fait ici.
