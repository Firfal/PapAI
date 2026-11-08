# PapAI Android : l'app du support

Même app que l'iPhone (`apps/ios`), en Kotlin + Jetpack Compose, distribuée en APK
à installer hors Play Store (« sources inconnues »). Il n'y a pas d'app mobile pour la personne aidée.

Version entreprise uniquement : le support est rattaché d'office à son organisation par le jeton
support (`sup-…`) déposé par le service informatique. Il n'y a ni liaison poste par poste (QR code,
code à 6 chiffres, lien d'invitation) ni réglage à la main : l'app lit la liste des postes de
l'organisation (`GET <serveur>/o/<jeton>/spaces`, toutes les 30 s), suit un poste en détail et
signale les demandes et alertes des autres. La version avec liaison est archivée dans la branche
`archive/particuliers`.

Ce qu'elle fait : postes de l'organisation (« prénom · service »), demande et plan
(valider, préciser au clavier ou à la voix, refuser), écran en direct, pause, question de Holo,
prise en main (viseur et loupe ×3, clic normalisé), dictée en direct de la personne aidée, alertes,
fin de l'assistance et automate (brouillon modifiable avec ses captures réelles).
Une notification « Connexion » (service de premier plan) garde la connexion ouverte, et une
notification forte arrive quand une demande ou une question attend le support.

## Configuration de l'organisation

Rien ne se saisit dans l'app. Sans configuration, elle affiche « Aucune organisation configurée »
et invite à contacter l'administrateur. Sources, dans l'ordre (la première qui porte un jeton valide
l'emporte ; le serveur vient de la même source) :

1. **Configuration gérée** (EMM / Android Enterprise ; restrictions déclarées dans
   `app/src/main/res/xml/app_restrictions.xml`) :

   | Clé | Valeur |
   |---|---|
   | `supportToken` | jeton support de l'organisation, `sup-…` (14 à 104 caractères `A-Z a-z 0-9 _ -`) |
   | `server` | facultatif : serveur PapAI `https://…` (ramené à son origine) ; absent ou invalide : serveur officiel `https://papai-450417131702.europe-west1.run.app` |
   | `supportName` | facultatif : nom affiché aux employés ; absent : « Support IT · <organisation> » |

   Une configuration poussée après coup est relue quand l'app revient au premier plan.

2. **Démo sans EMM** : copier `support.local.properties.example` en `support.local.properties`
   (dans `apps/android/`, fichier local non suivi), y mettre `supportToken` (et `server` si besoin),
   puis reconstruire l'APK. Les valeurs sont compilées dans `BuildConfig.PAPAI_SUPPORT_TOKEN` et
   `BuildConfig.PAPAI_SERVER` : l'APK ainsi construit contient le jeton, ne pas le diffuser.

## Construire l'APK

Il faut le JDK 17 et le SDK Android (plateforme 35), avec `sdk.dir=…` dans `local.properties`
ou `ANDROID_HOME`.

```bash
cd apps/android
./gradlew assembleRelease     # app/build/outputs/apk/release/app-release.apk
./gradlew assembleDebug       # app/build/outputs/apk/debug/app-debug.apk
```

### Signature

Android n'accepte une mise à jour que si l'APK est signé avec la même clé que la version
installée. La clé n'est jamais dans le dépôt : `keystore.properties` (ignoré par git) à côté de ce
fichier, ou les variables `PAPAI_KEYSTORE`, `PAPAI_KEYSTORE_PASSWORD`, `PAPAI_KEY_ALIAS`,
`PAPAI_KEY_PASSWORD`.

```properties
keystore=/chemin/vers/papai-release.jks
keystore_password=…
key_alias=papai
```

Sans clé, l'APK de release est signé avec la clé de debug de la machine.

## Installer sur un téléphone

1. Copier `app-release.apk` sur le téléphone (lien, mail, câble…), puis l'ouvrir.
2. Android demande d'autoriser l'installation depuis cette source (navigateur, Fichiers…) : accepter.
3. Ouvrir PapAI et autoriser les notifications : les postes de l'organisation apparaissent seuls.

Ou par câble : `adb install -r app-release.apk`.
