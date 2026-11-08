# PapAI : textes de soumission entreprise (Luma et BuilderBase)

Rendu prévu : **dimanche 8 novembre 2026, 14 h sur Luma, 14 h 30 sur BuilderBase**.
Tableau de bord : <https://builderbase.com/track-dashboard/h-company-42ai-computer-use-agents-hackathon/overview>.
Les blocs sont prêts à copier ; les champs `[À COMPLÉTER]` restent à remplir.

**Référence : code de main à [`b905883`](https://github.com/Firfal/PapAI/commit/b905883),
8 novembre 2026, 10 h 22 UTC**, après l'intégration
[#90](https://github.com/Firfal/PapAI/pull/90). Les quinze chantiers entreprise
ci-dessous sont intégrés ; la lecture du code et des tests présents ne vaut pas
essai réel, configuration des services en production ou déploiement.
La matrice des fonctionnalités et leurs périmètres relus dans main est dans le
[README](../README.md#entreprise--fonctionnalités-intégrées).

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

Le code de configuration d'entreprise est intégré : configuration Mac par profil MDM, configuration Windows par stratégie de groupe avec modèles ADMX/ADML, support Mac/iPhone connecté d'office à son organisation et configuration gérée Android Enterprise du support. L'IT configure le rattachement à l'organisation, sans liaison manuelle poste par poste. Il s'agit du code de configuration du parc, pas de l'annonce d'un déploiement déjà réalisé.

Des tickets plutôt que des demandes perdues
Chaque demande est suivie par ticket : plan, prise en charge, issue, notes, clôture ou réouverture. Si aucun support connu n'est connecté, la demande attend et un rendez-vous peut être fixé. La vue web de l'organisation propose des filtres et un export CSV. Le classement des tickets par catégorie, les corrections par le support et les graphiques web/Mac sont intégrés. Jusqu'à deux automates pertinents sont proposés pendant l'attente, selon les mots communs à la demande et au catalogue, sans appel à un modèle.

La voix et la recherche documentaire
Gladia transcrit la demande en français côté serveur, avec du direct sur Mac/iPhone et le secours de la reconnaissance Apple. Holo affiche déjà une phrase décrivant son action. Ces phrases peuvent être lues à voix haute localement en français sur Mac/Windows, avec un réglage désactivable et une coupure pendant la dictée. Pour une question de documentation, Linkup propose une réponse sourcée après relecture de la requête par le support ; le support valide aussi la réponse, et ces résultats ne sont pas transmis à Holo. Ce n'est pas un moteur de navigation ni une autorisation d'agir.

Anti-arnaque et sécurité
Les décisions du support sont contrôlées côté serveur. Le format d'automate n'accepte ni commande arbitraire ni script. Sur Mac, Arrêter est un verrou local, et des contrôles natifs bloquent les gestes sur des fenêtres protégées avant de demander l'aide du support. Le gardien vérifie les demandes et les plans ; sa protection en temps réel optionnelle sur Mac/Windows transmet hors assistance des noms d'applications, un titre de fenêtre et un nom de site toutes les huit secondes, jamais une image de l'écran.

Pour les tâches web sur Mac, Chrome PapAI utilise un profil séparé supprimé après l'assistance ; l'utilisateur se connecte lui-même, sans import de cookies ou mots de passe. La surveillance des URL de Chrome PapAI sur Mac détecte les sorties des sites validés, puis suspend Holo et demande l'accord du support ; ce n'est ni un pare-feu réseau ni une garantie pour le mode web pur. Les liens d'une assistance terminée ne donnent plus accès aux images. Les jetons individuels du support sont révocables et ne donnent que des clés dérivées par poste ; la révocation ferme les connexions et arrête l'assistance validée par ce support. Ces protections ne permettent pas de promettre une détection infaillible des arnaques ou de toutes les actions sensibles.

Limites actuelles
Le stockage dispose d'une interface disque local ou Firestore, avec Cloud Storage pour les images. Le disque local reste le choix par défaut et ne garantit pas la conservation après redéploiement sur un hébergement éphémère ; la configuration et la migration vers les services Cloud restent à effectuer et vérifier en production. L'abonnement Stripe est intégré uniquement en mode test, sans encaissement réel. Le rangement guidé des dossiers est intégré sur Mac seulement : déplacements validés par le support, noms de fichiers sans leur contenu, sans écrasement et avec journal d'annulation. L'alignement de tests sur le lexique « utilisateur » est intégré ; cela ne prouve pas que tous les tests sont verts. Les essais MDM/GPO sur parc réel et les vérifications des services en production ne sont pas établis par ce texte.

La version famille existe sur la branche archive/particuliers.
```

## Technologies

```text
- Holo (H Company) : holo3-1-35b-a3b par défaut, configurable ; plan et computer use via API compatible OpenAI ; Agents API et navigateur local de H pour les tâches web sur Mac.
- Gladia API v2 : transcription française enregistrée et relais WebSocket direct ; reconnaissance Apple en secours sur Mac/iPhone.
- Mac : Swift, SwiftUI, ScreenCaptureKit, CGEvent ; mode utilisateur et mode support.
- iPhone du support : Swift et SwiftUI. Android du support : Kotlin et Jetpack Compose ; configuration entreprise gérée.
- Windows : Python, pywebview et WebView2 ; configuration par stratégie de groupe avec modèles ADMX/ADML. Configuration Mac MDM.
- Serveur : Python, FastAPI, WebSockets ; configuration d'hébergement Google Cloud Run dans le dépôt, révision de production non vérifiée ici.
- Recherche documentaire sourcée : Linkup, requête et réponse validées par le support.
- Données : disque local par défaut ; Firestore et Cloud Storage selon la configuration serveur.
- Abonnement : Stripe, mode test uniquement.
- Développement : Devin (Cognition), Claude Code et contributions de l'équipe ; voir le relevé Git ci-dessous.
```

Tags possibles : `computer use`, `support IT`, `entreprise`, `automates`, `sécurité`,
`H Company`, `Holo`, `Gladia`, `Devin`, `Linkup`.

## Prix sponsors visés

### Gladia (dictée)

```text
Christine décrit son problème avec ses mots plutôt que de rédiger une procédure technique. PapAI utilise Gladia API v2 pour transcrire sa demande en français côté serveur. Sur Mac et iPhone, le relais WebSocket affiche les transcriptions partielles puis finales ; la clé Gladia reste côté serveur. PapAI conserve aussi la voie de transcription d'un enregistrement et le secours de la reconnaissance Apple. Le relais borne la durée, le volume audio et le nombre de connexions ; le code de PapAI n'écrit pas cet audio sur disque. Gladia sert à comprendre la demande, pas à lire les réponses de Holo : la narration locale française est distincte et intégrée sur Mac/Windows.
```

Sources : [`backend/voice.py`](../backend/voice.py),
[`Dictation.swift`](../apps/mac/Sources/Dictation.swift),
[`GladiaLive.swift`](../apps/shared/GladiaLive.swift),
[`tests/test_gladia_live.py`](../tests/test_gladia_live.py) et
[`PROTOCOL.md`](../PROTOCOL.md). Ce chantier documentaire n'a pas rejoué la dictée
avec un microphone physique ni vérifié le repli Apple ou Gladia en production.

### Devin

```text
Devin a contribué à PapAI sur des branches distinctes, avec réservation des fichiers dans AGENTS.md, tests ciblés et relectures. Au 8 novembre 2026 à 10 h 22 UTC, sur main à b905883, git log recense 781 commits. Les deux identités Git de Devin en représentent 618 : 451 hors fusion et 167 de fusion. Ce n'est donc pas « 618 changements fonctionnels » ni une mesure du travail humain remplacé. L'intégration #90 est une fusion à deux parents, pas un squash : l'historique des branches intégrées reste présent et chaque commit est compté une seule fois. GitHub indique 68 PR fusionnées dont 60 de l'application Devin, avec des SHA de fusion présents dans l'historique de main. Les 39 PR de Devin créées le 8 novembre recensées à cette heure se répartissent en 25 fusionnées, 11 ouvertes et trois fermées sans fusion. Les quinze chantiers entreprise, dont Linkup et la narration, sont maintenant dans main ; cela ne prouve pas un déploiement ou un essai réel.
```

#### Périmètre et méthode du recomptage

- Historique complet de `origin/main` à `b905883`, **fusions incluses** : 781 commits,
  202 commits de fusion au total, 8 identités auteur (nom + adresse), 5 adresses
  distinctes. Ces identités ne permettent pas de compter des personnes.
- Auteurs Devin : **587** sous « Devin AI », **31** sous
  « devin-ai-integration[bot] », avec la même adresse Git du bot ; total **618**,
  dont **451 hors fusion** et **167 de fusion**.
- #90 est une **fusion, pas un squash** : `git show --no-patch --format=%P b905883`
  donne deux parents, `19a958d` et `062ef2c`. Les commits des branches intégrées
  sont atteignables depuis main ; ils sont comptés une seule fois par `git log`,
  sans additionner les historiques de chaque PR.
- Les **68 PR fusionnées**, dont **60** d'auteur `app/devin-ai-integration`, sont
  comptées par leur numéro GitHub, puis contrôlées par présence de `mergeCommit.oid`
  dans `git log origin/main --format=%H`. Plusieurs PR peuvent partager un SHA
  d'intégration : ne pas dédupliquer les numéros par SHA.
- `git log --merges` contient 33 messages « Merge pull request », dont 32 issus
  de branches `devin/` : **ce n'est pas le total des PR fusionnées**, car certaines
  ont été réunies dans une intégration ou fusionnées avec un autre message.
- La liste ci-dessous prend les dates de création renvoyées par GitHub pour
  `created:2026-11-08`, pas les dates des commits. Elle exclut les PR ultérieures
  à l'heure du relevé. La PR documentaire #89 et l'intégration #90 sont désormais
  incluses ; les changements d'état ultérieurs ne sont pas anticipés.

Commandes de base, après `git fetch origin` :

```bash
git log origin/main --format=%H | wc -l
git log origin/main --format='%an <%ae>' | sort | uniq -c
git log origin/main --merges --format=%H | wc -l
git show --no-patch --format='%H %P' b905883
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
**39 PR : 25 fusionnées, 11 ouvertes, trois fermées sans fusion** au relevé.
L'état GitHub ne suffit pas à savoir si le code est dans main : #81 reste
ouverte mais son code est intégré par #90 ; #68 et #69 sont fermées sans fusion,
mais leur code est repris dans #75. #72 (auteur `Firfal`, hors liste) est également
ouverte malgré son intégration.

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
| [#68](https://github.com/Firfal/PapAI/pull/68) | Design Windows aligné sur Mac | app/devin-ai-integration | Fermée sans fusion |
| [#69](https://github.com/Firfal/PapAI/pull/69) | Automates locaux hors ligne | app/devin-ai-integration | Fermée sans fusion |
| [#73](https://github.com/Firfal/PapAI/pull/73) | Images inaccessibles après la fin de l'assistance | app/devin-ai-integration | Fusionnée |
| [#74](https://github.com/Firfal/PapAI/pull/74) | Première PR Linkup, remplacée par #80 | app/devin-ai-integration | Fermée sans fusion |
| [#75](https://github.com/Firfal/PapAI/pull/75) | Windows entreprise intégré | app/devin-ai-integration | Fusionnée |
| [#76](https://github.com/Firfal/PapAI/pull/76) | Stockage local ou Firestore/Cloud Storage | app/devin-ai-integration | Fusionnée |
| [#77](https://github.com/Firfal/PapAI/pull/77) | Jeton individuel révocable pour le support | app/devin-ai-integration | Fusionnée |
| [#78](https://github.com/Firfal/PapAI/pull/78) | Retrait de la création d'automate à partir de rien | app/devin-ai-integration | Ouverte |
| [#79](https://github.com/Firfal/PapAI/pull/79) | Surveillance des sites du navigateur et accord hors plan | app/devin-ai-integration | Fusionnée |
| [#80](https://github.com/Firfal/PapAI/pull/80) | Recherche documentaire Linkup | app/devin-ai-integration | Fusionnée |
| [#81](https://github.com/Firfal/PapAI/pull/81) | Automates proposés pendant l'attente | app/devin-ai-integration | Ouverte |
| [#82](https://github.com/Firfal/PapAI/pull/82) | Narration locale en français | app/devin-ai-integration | Fusionnée |
| [#83](https://github.com/Firfal/PapAI/pull/83) | Support Android après le pivot entreprise | app/devin-ai-integration | Fusionnée |
| [#84](https://github.com/Firfal/PapAI/pull/84) | Abonnement Stripe en mode test | app/devin-ai-integration | Fusionnée |
| [#85](https://github.com/Firfal/PapAI/pull/85) | Attentes des tests alignées sur le lexique utilisateur | app/devin-ai-integration | Fusionnée |
| [#86](https://github.com/Firfal/PapAI/pull/86) | Catégories et graphiques des tickets | app/devin-ai-integration | Fusionnée |
| [#87](https://github.com/Firfal/PapAI/pull/87) | Rangement guidé des dossiers sur Mac | app/devin-ai-integration | Fusionnée |
| [#88](https://github.com/Firfal/PapAI/pull/88) | Retrait du verrou souris/clavier pendant l'exécution | app/devin-ai-integration | Ouverte |
| [#89](https://github.com/Firfal/PapAI/pull/89) | Docs entreprise : Christine, support IT et soumission à jour | app/devin-ai-integration | Ouverte |
| [#90](https://github.com/Firfal/PapAI/pull/90) | Intégration finale : réunir les PR #71 à #87 | app/devin-ai-integration | Fusionnée |
| [#91](https://github.com/Firfal/PapAI/pull/91) | Windows employé aligné sur le Mac : agent navigateur, « Mes automates », Réglages, assistance et encart | app/devin-ai-integration | Ouverte |
| [#92](https://github.com/Firfal/PapAI/pull/92) | iPhone support aligné sur le Mac : onglets Tickets / Utilisateurs / Mes automates, une seule palette, « Appliquer… » à toute une organisation | app/devin-ai-integration | Ouverte |
| [#93](https://github.com/Firfal/PapAI/pull/93) | Android aligné sur l'iPhone et le support Mac : onglets Tickets / Utilisateurs / Mes automates, gardien, Modifier l'étape | app/devin-ai-integration | Ouverte |
| [#94](https://github.com/Firfal/PapAI/pull/94) | Retrait du cas « photos de Noël » : exemples et démos sur Documents › Comptabilité 2025 | app/devin-ai-integration | Ouverte |
| [#95](https://github.com/Firfal/PapAI/pull/95) | Pré-traitement de la demande : Holo fait préciser une demande floue avant le ticket | app/devin-ai-integration | Ouverte |
| [#96](https://github.com/Firfal/PapAI/pull/96) | Automates autonomes : « Demander une assistance » discret, étape bloquante sur le ticket | app/devin-ai-integration | Ouverte |
| [#97](https://github.com/Firfal/PapAI/pull/97) | Point de la semaine pour le support : carte « Cette semaine » (console et Mac) | app/devin-ai-integration | Ouverte |

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

- [x] Relire main après #90, actualiser la référence et les quinze chantiers intégrés,
  recompter Git et relever les états GitHub au 8 novembre, 10 h 22 UTC.
- [ ] Refaire ce relevé si main ou les états GitHub évoluent avant l'envoi.
- [ ] Remplir l'équipe et les liens ; vérifier l'accès du jury au code.
- [ ] Ne publier aucun secret ni lien contenant un secret d'accès, dans le texte,
  les captures, les journaux ou la vidéo.
- [ ] Utiliser uniquement des données de démonstration autorisées.
- [ ] Ne pas annoncer un essai réel, un déploiement MDM/GPO, un service externe
  opérationnel ou un encaissement Stripe sans l'avoir vérifié.
- [ ] Copier les mêmes textes à jour sur Luma et BuilderBase aux heures prévues.
