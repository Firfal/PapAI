# PapAI Android : l'app du support

Même app que l'iPhone (`apps/ios`), en Kotlin + Jetpack Compose, distribuée en APK
à installer hors Play Store (« sources inconnues »). Il n'y a pas d'app mobile pour la personne aidée.

Ce qu'elle fait : appairage (QR, code à 6 chiffres, lien `papai://pair?u=…&n=…`), demande et plan
(valider, préciser au clavier ou à la voix, refuser), écran en direct, pause, question de Holo,
prise en main (viseur et loupe ×3, clic normalisé), dictée en direct de la personne aidée, alertes,
fin de session et automate (brouillon modifiable avec ses captures réelles).
Une notification « Liaison » (service de premier plan) garde la connexion ouverte, et une
notification forte arrive quand une demande ou une question attend l'aidant.

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
3. Ouvrir PapAI, autoriser les notifications, puis « Scanner le QR de l'ordinateur ».

Ou par câble : `adb install -r app-release.apk`.
