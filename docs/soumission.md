# PapAI : textes de soumission entreprise (Luma et BuilderBase)

Rendu prévu : **dimanche 8 novembre 2026, 14 h sur Luma, 14 h 30 sur BuilderBase**.
Tableau de bord : <https://builderbase.com/track-dashboard/h-company-42ai-computer-use-agents-hackathon/overview>.
Les blocs sont prêts à copier ; les champs `[À COMPLÉTER]` restent à remplir.

**Référence : code de main à [`19a958d`](https://github.com/Firfal/PapAI/commit/19a958d),
8 novembre 2026, 09 h 30 UTC.** Les mentions **[en PR]** font partie des textes à
copier : les conserver tant que la fonctionnalité n'est pas intégrée dans main.
La lecture du code et des tests présents ne vaut pas essai réel ni déploiement.
La matrice des quinze PR entreprise et leurs périmètres est dans le
[README](../README.md#entreprise--compléments-non-encore-intégrés).

## Titre

```text
PapAI — le support IT de premier niveau, automatisé
```

## Accroche (une ligne)

```text
Christine demande, le support valide, Holo agit ; l'organisation partage ses automates.
```

## Description courte (environ 300 caractères)

```text
Christine décrit son problème sur son ordinateur. Holo propose un plan, que le support IT valide, précise ou refuse avant l'exécution. PapAI suit l'assistance par ticket et permet à l'organisation de partager des automates pour les tâches courantes. L'utilisateur garde la possibilité d'arrêter.
```

## Description longue

```text
Le problème
Christine veut retrouver un document ou régler un problème d'imprimante. Le support IT reçoit ces demandes récurrentes, doit comprendre la situation puis guider l'utilisateur à distance. Une même procédure est souvent répétée d'un poste à l'autre.

La solution
PapAI automatise le support informatique de premier niveau sous contrôle du support. Christine décrit sa difficulté au clavier ou à la voix. Holo, d'H Company, examine l'écran après accord de partage et propose un plan de deux à cinq étapes. Le support choisit Valider, Préciser ou Refuser avant que Holo exécute. Christine voit l'avancement et ce que fait Holo, peut répondre à ses questions, mettre en pause ou arrêter.

Une organisation, plusieurs ordinateurs
Le serveur sait inscrire les postes dans une organisation, en lister les espaces et partager un catalogue d'automates. Le support importe des fichiers .papai : cet import valide leurs actions prévues. Christine lance ensuite un automate depuis son ordinateur ; certaines actions sont locales, d'autres font intervenir Holo. Le support Mac dispose des onglets Tickets, Utilisateurs et Mes automates. La création de nouveaux automates est actuellement masquée dans cette interface ; l'import et l'application restent disponibles.

Le déploiement d'entreprise est en préparation : configuration Mac par profil MDM [en PR] (#71), configuration Windows par stratégie de groupe avec modèles ADMX/ADML [en PR] (#75), support Mac/iPhone connecté d'office à son organisation [en PR] (#72) et adaptation Android Enterprise du support [en PR] (#83). Il s'agit du code de configuration du parc, pas de l'annonce d'un déploiement déjà réalisé.

Des tickets plutôt que des demandes perdues
Chaque demande est suivie par ticket : plan, prise en charge, issue, notes, clôture ou réouverture. Si aucun support connu n'est connecté, la demande attend et un rendez-vous peut être fixé. La vue web de l'organisation propose des filtres et un export CSV. Le classement des tickets par catégorie, les corrections par le support et les graphiques web/Mac sont [en PR] (#86). Jusqu'à deux automates pourront être proposés pendant l'attente [en PR] (#81).

La voix et la recherche documentaire
Gladia transcrit la demande en français côté serveur, avec du direct sur Mac/iPhone et le secours de la reconnaissance Apple. Holo affiche déjà une phrase décrivant son action. La lecture de ces phrases à voix haute, locale et désactivable sur Mac/Windows, est [en PR] (#82). Pour une question de documentation, Linkup propose une réponse sourcée après relecture de la requête par le support ; ces résultats ne sont pas transmis à Holo [en PR] (#80). Ce n'est pas un moteur de navigation ni une autorisation d'agir.

Anti-arnaque et sécurité
Les décisions du support sont contrôlées côté serveur. Le format d'automate n'accepte ni commande arbitraire ni script. Sur Mac, Arrêter est un verrou local, et des contrôles natifs bloquent les gestes sur des fenêtres protégées avant de demander l'aide du support. Le gardien vérifie les demandes et les plans ; sa protection en temps réel optionnelle sur Mac/Windows transmet hors assistance des noms d'applications, un titre de fenêtre et un nom de site toutes les huit secondes, jamais une image de l'écran.

Pour les tâches web sur Mac, Chrome PapAI utilise un profil séparé supprimé après l'assistance ; l'utilisateur se connecte lui-même, sans import de cookies ou mots de passe. La détection des sorties des sites validés, suivie d'une pause et d'une demande d'accord au support, est [en PR] (#79) ; ce n'est pas un pare-feu réseau. La coupure de l'accès aux images par les liens d'une assistance terminée est [en PR] (#73). Les jetons individuels du support, révocables et ne donnant que des clés dérivées par poste, sont [en PR] (#77). Ces protections ne permettent pas de promettre une détection infaillible des arnaques ou de toutes les actions sensibles.

Limites actuelles
Dans main, les données sont écrites sur le disque du serveur : sur un hébergement éphémère, elles ne sont pas garanties après redéploiement. Le stockage durable Firestore/Cloud Storage est [en PR] (#76). L'abonnement Stripe est [en PR] (#84), uniquement en mode test, sans encaissement réel. Le rangement guidé des dossiers, validé par le support, sans contenu de fichiers envoyé, sans écrasement et avec annulation, est [en PR] (#87), sur Mac seulement. L'alignement de tests sur le lexique « utilisateur » est [en PR] (#85) ; nous ne présentons pas toutes les branches comme intégrées ou tous les tests comme verts. Les essais MDM/GPO sur parc réel et les vérifications des services en production ne sont pas établis par ce texte.

La version famille existe sur la branche archive/particuliers.
```

## Technologies

```text
- Holo (H Company) : holo3-1-35b-a3b par défaut, configurable ; plan et computer use via API compatible OpenAI ; Agents API et navigateur local de H pour les tâches web sur Mac.
- Gladia API v2 : transcription française enregistrée et relais WebSocket direct ; reconnaissance Apple en secours sur Mac/iPhone.
- Mac : Swift, SwiftUI, ScreenCaptureKit, CGEvent ; mode utilisateur et mode support.
- iPhone du support : Swift et SwiftUI. Android du support : Kotlin et Jetpack Compose ; configuration entreprise [en PR] (#83).
- Windows : Python, pywebview et WebView2 ; configuration par stratégie de groupe [en PR] (#75). Configuration Mac MDM [en PR] (#71).
- Serveur : Python, FastAPI, WebSockets ; configuration d'hébergement Google Cloud Run dans le dépôt, révision de production non vérifiée ici.
- Recherche documentaire sourcée : Linkup [en PR] (#80).
- Données : disque local dans main ; Firestore et Cloud Storage [en PR] (#76).
- Abonnement : Stripe, mode test uniquement [en PR] (#84).
- Développement : Devin (Cognition), Claude Code et contributions de l'équipe ; voir le relevé Git ci-dessous.
```

Tags possibles : `computer use`, `support IT`, `entreprise`, `automates`, `sécurité`,
`H Company`, `Holo`, `Gladia`, `Devin` ; `Linkup` avec la mention **[en PR]**.

## Prix sponsors visés

### Gladia (dictée)

```text
Christine décrit son problème avec ses mots plutôt que de rédiger une procédure technique. PapAI utilise Gladia API v2 pour transcrire sa demande en français côté serveur. Sur Mac et iPhone, le relais WebSocket affiche les transcriptions partielles puis finales ; la clé Gladia reste côté serveur. PapAI conserve aussi la voie de transcription d'un enregistrement et le secours de la reconnaissance Apple. Le relais borne la durée, le volume audio et le nombre de connexions ; le code de PapAI n'écrit pas cet audio sur disque. Gladia sert à comprendre la demande, pas à lire les réponses de Holo : la narration locale est un autre chantier [en PR] (#82).
```

Sources : [`backend/voice.py`](../backend/voice.py),
[`Dictation.swift`](../apps/mac/Sources/Dictation.swift),
[`GladiaLive.swift`](../apps/shared/GladiaLive.swift),
[`tests/test_gladia_live.py`](../tests/test_gladia_live.py) et
[`PROTOCOL.md`](../PROTOCOL.md). Ce chantier documentaire n'a pas rejoué la dictée
avec un microphone physique ni vérifié le repli Apple ou Gladia en production.

### Devin

```text
Devin a contribué à PapAI sur des branches distinctes, avec réservation des fichiers dans AGENTS.md, tests ciblés et relectures. Au 8 novembre 2026 à 09 h 30 UTC, sur main à 19a958d, git log recense 620 commits. Les deux identités Git de Devin en représentent 471 : 347 hors fusion et 124 de fusion. Ce n'est donc pas « 471 changements fonctionnels » ni une mesure du travail humain remplacé. GitHub indique 52 PR fusionnées dont 47 de l'application Devin, avec des SHA de fusion présents dans l'historique de main. Les 30 PR de Devin créées le 8 novembre recensées à cette heure se répartissent en 12 fusionnées, 17 ouvertes et une fermée sans fusion. Elles couvrent notamment les tickets, la dictée Gladia, l'anti-arnaque et la sécurité ; les travaux entreprise, Linkup et narration encore ouverts sont signalés [en PR], pas présentés comme livrés.
```

#### Périmètre et méthode du recomptage

- Historique complet de `origin/main` à `19a958d`, **fusions incluses** : 620 commits,
  158 commits de fusion au total, 8 identités auteur (nom + adresse), 5 adresses
  distinctes. Ces identités ne permettent pas de compter des personnes.
- Auteurs Devin : **440** sous « Devin AI », **31** sous
  « devin-ai-integration[bot] », avec la même adresse Git du bot ; total **471**.
- Les **52 PR fusionnées**, dont **47** d'auteur `app/devin-ai-integration`, sont
  comptées par leur numéro GitHub, puis contrôlées par présence de `mergeCommit.oid`
  dans `git log origin/main --format=%H`. Plusieurs PR peuvent partager un SHA
  d'intégration : ne pas dédupliquer les numéros par SHA.
- `git log --merges` contient 33 messages « Merge pull request », dont 32 issus
  de branches `devin/` : **ce n'est pas le total des PR fusionnées**, car certaines
  ont été réunies dans une intégration ou fusionnées avec un autre message.
- La liste ci-dessous prend les dates de création renvoyées par GitHub pour
  `created:2026-11-08`, pas les dates des commits. Elle exclut les PR ultérieures
  à l'heure du relevé, y compris celle portant cette mise à jour documentaire.

Commandes de base, après `git fetch origin` :

```bash
git log origin/main --format=%H | wc -l
git log origin/main --format='%an <%ae>' | sort | uniq -c
git log origin/main --merges --format=%H | wc -l
git log origin/main --author='158243242+devin-ai-integration' --format=%H | wc -l
git log origin/main --author='158243242+devin-ai-integration' --no-merges --format=%H | wc -l
gh pr list --repo Firfal/PapAI --state all --search "created:2026-11-08" \
  --limit 200 --json number,title,author,state,mergedAt,createdAt,url
gh pr list --repo Firfal/PapAI --state merged --limit 200 \
  --json number,author,mergeCommit
```

#### PR de Devin créées le 8 novembre — état au relevé

L'auteur GitHub de **chaque ligne** est `app/devin-ai-integration` ; les PR de
`Firfal`, même sur une branche d'intégration contenant du travail de Devin, ne
sont pas attribuées au bot. « Fermée sans fusion » n'est ni « fusionnée » ni « ouverte ».

| PR | Sujet | Auteur GitHub | État réel |
|---|---|---|---|
| [#48](https://github.com/Firfal/PapAI/pull/48) | Vocabulaire support sur Mac/iPhone | app/devin-ai-integration | Fusionnée |
| [#49](https://github.com/Firfal/PapAI/pull/49) | Automate, assistance, QR code : lexique partagé | app/devin-ai-integration | Fusionnée |
| [#50](https://github.com/Firfal/PapAI/pull/50) | Tickets, attente et rendez-vous | app/devin-ai-integration | Fusionnée |
| [#52](https://github.com/Firfal/PapAI/pull/52) | Gladia en direct et repli Apple | app/devin-ai-integration | Fusionnée |
| [#53](https://github.com/Firfal/PapAI/pull/53) | Règles anti-arnaque, cartes cadeaux, impôts et loyer | app/devin-ai-integration | Fusionnée |
| [#54](https://github.com/Firfal/PapAI/pull/54) | Passage bureau → navigateur de H → bureau | app/devin-ai-integration | Fusionnée |
| [#55](https://github.com/Firfal/PapAI/pull/55) | Blocage des actions sensibles de Holo | app/devin-ai-integration | Fusionnée |
| [#56](https://github.com/Firfal/PapAI/pull/56) | Décisions produit : protection optionnelle, aucun identifiant retenu | app/devin-ai-integration | Fusionnée |
| [#57](https://github.com/Firfal/PapAI/pull/57) | Protection en temps réel optionnelle, profil navigateur nettoyé | app/devin-ai-integration | Fusionnée |
| [#58](https://github.com/Firfal/PapAI/pull/58) | Automates de démonstration | app/devin-ai-integration | Fusionnée |
| [#59](https://github.com/Firfal/PapAI/pull/59) | Liaison avec accord sur l'ordinateur, liens sans clé | app/devin-ai-integration | Fusionnée |
| [#60](https://github.com/Firfal/PapAI/pull/60) | Accueil Mac en deux colonnes | app/devin-ai-integration | Fusionnée |
| [#68](https://github.com/Firfal/PapAI/pull/68) | Design Windows aligné sur Mac | app/devin-ai-integration | Ouverte |
| [#69](https://github.com/Firfal/PapAI/pull/69) | Automates locaux hors ligne | app/devin-ai-integration | Ouverte |
| [#73](https://github.com/Firfal/PapAI/pull/73) | Images inaccessibles après la fin de l'assistance | app/devin-ai-integration | Ouverte |
| [#74](https://github.com/Firfal/PapAI/pull/74) | Première PR Linkup, remplacée par #80 | app/devin-ai-integration | Fermée sans fusion |
| [#75](https://github.com/Firfal/PapAI/pull/75) | Windows entreprise intégré | app/devin-ai-integration | Ouverte |
| [#76](https://github.com/Firfal/PapAI/pull/76) | Stockage local ou Firestore/Cloud Storage | app/devin-ai-integration | Ouverte |
| [#77](https://github.com/Firfal/PapAI/pull/77) | Jeton individuel révocable pour le support | app/devin-ai-integration | Ouverte |
| [#78](https://github.com/Firfal/PapAI/pull/78) | Retrait de la création d'automate à partir de rien | app/devin-ai-integration | Ouverte |
| [#79](https://github.com/Firfal/PapAI/pull/79) | Surveillance des sites du navigateur et accord hors plan | app/devin-ai-integration | Ouverte |
| [#80](https://github.com/Firfal/PapAI/pull/80) | Recherche documentaire Linkup | app/devin-ai-integration | Ouverte |
| [#81](https://github.com/Firfal/PapAI/pull/81) | Automates proposés pendant l'attente | app/devin-ai-integration | Ouverte |
| [#82](https://github.com/Firfal/PapAI/pull/82) | Narration locale en français | app/devin-ai-integration | Ouverte |
| [#83](https://github.com/Firfal/PapAI/pull/83) | Support Android après le pivot entreprise | app/devin-ai-integration | Ouverte |
| [#84](https://github.com/Firfal/PapAI/pull/84) | Abonnement Stripe en mode test | app/devin-ai-integration | Ouverte |
| [#85](https://github.com/Firfal/PapAI/pull/85) | Attentes des tests alignées sur le lexique utilisateur | app/devin-ai-integration | Ouverte |
| [#86](https://github.com/Firfal/PapAI/pull/86) | Catégories et graphiques des tickets | app/devin-ai-integration | Ouverte |
| [#87](https://github.com/Firfal/PapAI/pull/87) | Rangement guidé des dossiers sur Mac | app/devin-ai-integration | Ouverte |
| [#88](https://github.com/Firfal/PapAI/pull/88) | Retrait du verrou souris/clavier pendant l'exécution | app/devin-ai-integration | Ouverte |

## Équipe

```text
[À COMPLÉTER : prénom nom, rôle, lien GitHub ou LinkedIn de chaque membre]
- Quentin Robert : [rôle]
- Théo [nom] : [rôle]
- [cyp-cor] : [rôle]
- [snarbe] : [rôle]
```

## Liens

| Lien | Valeur |
|---|---|
| Code | <https://github.com/Firfal/PapAI> — [À COMPLÉTER : vérifier l'accès du jury] |
| Vidéo de démonstration (2 min) | [À COMPLÉTER : lien non répertorié] |
| Démonstration | [À COMPLÉTER : modalités d'accès du jury, sans publier de secret ni lien d'accès privé] |
| Slides | [À COMPLÉTER] |

## Vérifications avant d'envoyer

- [ ] Refaire `git fetch origin`, relire l'intégration finale éventuelle et mettre
  à jour la référence, les mentions **[en PR]**, les chiffres et les états GitHub.
- [ ] Remplir l'équipe et les liens ; vérifier l'accès du jury au code.
- [ ] Ne publier aucun secret ni lien contenant un secret d'accès, dans le texte,
  les captures, les journaux ou la vidéo.
- [ ] Utiliser uniquement des données de démonstration autorisées.
- [ ] Ne pas annoncer un essai réel, un déploiement MDM/GPO, un service externe
  opérationnel ou un encaissement Stripe sans l'avoir vérifié.
- [ ] Copier les mêmes textes à jour sur Luma et BuilderBase aux heures prévues.
