<p align="center"><img src="brand/papai-mascotte-pastel.svg" width="120" alt="PapAI"></p>

# PapAI — le support informatique de premier niveau, automatisé

Christine décrit son problème sur son ordinateur. **Holo** propose un plan ; le
**support IT** le valide, le précise ou le refuse avant l'exécution. L'organisation
partage ses **automates** pour que les utilisateurs relancent les tâches courantes
sans ouvrir une nouvelle assistance à chaque fois.

Hackathon H Company × 42 AI, 7–8 novembre 2026.

La version famille existe sur la branche [`archive/particuliers`](https://github.com/Firfal/PapAI/tree/archive/particuliers).

## État de référence

Lecture du code et relevé Git/GitHub au **8 novembre 2026, 10 h 22 UTC**, sur
[`main` à `b905883`](https://github.com/Firfal/PapAI/commit/b905883), après
l'intégration [#90](https://github.com/Firfal/PapAI/pull/90). Les quinze chantiers
entreprise ci-dessous sont dans main ; code intégré ne signifie ni service
configuré en production, ni déploiement ou essai sur un parc réel.
Les textes prêts à copier et le relevé détaillé des contributions Devin sont dans
[`docs/soumission.md`](docs/soumission.md). Priorités et limites : [`TODO.md`](TODO.md).
Pitch : deck final [`docs/pitch/deck.html`](docs/pitch/deck.html) (version téléprompteur : [`docs/pitch/deck-prompteur.html`](docs/pitch/deck-prompteur.html)), vidéo de démo : [release `demo`](https://github.com/Firfal/PapAI/releases/tag/demo).

## Une assistance pour Christine

1. **Demander** : Christine décrit sa difficulté au clavier ou à la voix. La
   dictée utilise Gladia côté serveur ; les apps Mac et iPhone disposent aussi du
   direct et du secours Apple.
2. **Proposer** : après accord de partage d'écran, Holo examine l'écran et propose
   un plan de deux à cinq étapes.
3. **Valider** : le support choisit **Valider**, **Préciser** ou **Refuser**. Le
   serveur contrôle cette décision avant de laisser Holo agir.
4. **Accompagner** : Holo clique et saisit, affiche ce qu'il fait et peut poser une
   question. Christine peut mettre en pause ou arrêter ; le support suit
   l'assistance et peut prendre la main quand Holo est suspendu.
5. **Suivre** : un ticket garde la demande, le plan et l'issue. Si aucun support
   connu n'est connecté, la demande attend ; un rendez-vous peut être fixé.
6. **Réutiliser** : le support peut garder une assistance réussie comme automate
   ou importer un fichier `.papai`. Cet import valide les actions prévues : les
   actions locales s'exécutent directement ; une tâche confiée à Holo utilise son
   exécution contrôlée.

## Organisations, tickets et automates : déjà dans main

- **Un espace par ordinateur**, rattachable à une organisation par un jeton
  d'inscription. Le jeton support de l'organisation donne accès à sa liste de
  postes ; des jetons individuels révocables donnent à chaque support des clés
  dérivées par poste.
- **Catalogue partagé** : les automates importés dans l'organisation sont copiés
  vers ses postes, y compris ceux inscrits ensuite. Sept exemples sont fournis
  dans [`automations/`](automations/) ; un nouvel espace ne les charge pas tout seul.
- **Support Mac** : onglets **Tickets**, **Utilisateurs**, **Mes automates** ;
  bibliothèque locale, import `.papai` et application à plusieurs utilisateurs.
  Le bouton de création est masqué (`creationActive = false`), même si le code
  de brouillon depuis un document ou un enregistrement est conservé.
- **Tickets** : attente, rendez-vous, prise en charge, notes, clôture et réouverture ;
  vue d'organisation web avec filtres et export CSV, catégories corrigeables par
  le support et graphiques web/Mac.

Sources : [`backend/orgs.py`](backend/orgs.py), [`backend/space.py`](backend/space.py),
[`backend/tickets.py`](backend/tickets.py), [`tickets.js`](backend/static/tickets.js),
[`SupportAutomates.swift`](apps/mac/Sources/Support/SupportAutomates.swift) et
[`SupportTickets.swift`](apps/mac/Sources/Support/SupportTickets.swift).

## Entreprise : fonctionnalités intégrées

Chaque ligne a été relue dans le code de main à `b905883`, pas seulement sur
l'ancienne branche de PR. Les numéros indiquent la provenance du chantier, pas
son état GitHub : #72 et #81 restent ouvertes au relevé, alors que leur code est
intégré par #90.

| Fonctionnalité | État et périmètre du code |
|---|---|
| Mac configuré par l'IT | **[#71](https://github.com/Firfal/PapAI/pull/71)** : préférences gérées par profil MDM, serveur, organisation et nom affiché ; parcours initial retiré. |
| Support connecté d'office | **[#72](https://github.com/Firfal/PapAI/pull/72)** : configuration de l'organisation sur Mac/iPhone, liste des postes et retrait de la liaison poste par poste dans les interfaces concernées. |
| Windows par stratégie de groupe | **[#75](https://github.com/Firfal/PapAI/pull/75)** : lecture des stratégies machine/utilisateur, modèles ADMX/ADML, organisation et serveur configurés par l'IT ; intègre aussi les automates locaux hors ligne de #69. |
| Liens d'assistance terminée | **[#73](https://github.com/Firfal/PapAI/pull/73)** : coupe l'accès aux images après la fin et refuse le rafraîchissement d'une ancienne assistance. |
| Stockage durable | **[#76](https://github.com/Firfal/PapAI/pull/76)** : interface disque local ou Firestore, Cloud Storage pour les images ; dépend de la configuration des services. |
| Un jeton par support | **[#77](https://github.com/Firfal/PapAI/pull/77)** : empreinte du jeton conservée, clés de poste dérivées, révocation et coupure des connexions. |
| Sites du navigateur validés | **[#79](https://github.com/Firfal/PapAI/pull/79)** : sur Mac, surveillance des URL de Chrome PapAI, détection d'une sortie des sites prévus, pause et demande d'accord au support ; ce n'est pas un pare-feu réseau ni une garantie pour le mode web pur. |
| Linkup | **[#80](https://github.com/Firfal/PapAI/pull/80)** : recherche documentaire proposée avant l'exécution, requête relue par le support, réponse sourcée ; résultats non transmis à Holo. |
| Automates pendant l'attente | **[#81](https://github.com/Firfal/PapAI/pull/81)** : jusqu'à deux propositions pertinentes, classement par mots communs sans modèle. |
| Narration à voix haute | **[#82](https://github.com/Firfal/PapAI/pull/82)** : lecture locale en français sur Mac et Windows, désactivable et interrompue pendant la dictée. |
| Android du support en entreprise | **[#83](https://github.com/Firfal/PapAI/pull/83)** : configuration gérée Android Enterprise ou configuration locale de démonstration, organisation et gestion du retrait d'accès. |
| Abonnement Stripe | **[#84](https://github.com/Firfal/PapAI/pull/84)** : Checkout, portail et webhook signé, **mode test seulement**, pas d'encaissement réel. |
| Correction des tests | **[#85](https://github.com/Firfal/PapAI/pull/85)** : attentes de liaison et d'actions sensibles alignées sur « utilisateur » ; aucune garantie sur les tests des autres branches. |
| Catégories et graphiques des tickets | **[#86](https://github.com/Firfal/PapAI/pull/86)** : classement par règles, Holo en cas de doute, correction par le support, statistiques web et Mac. |
| Rangement guidé des dossiers | **[#87](https://github.com/Firfal/PapAI/pull/87)** : Mac seulement, noms de fichiers sans leur contenu, déplacements validés par le support, sans écrasement, avec journal d'annulation. |

Les profils MDM et stratégies de groupe préparent la **configuration** du parc :
ce code ne constitue pas un service de distribution des applications ni la preuve
d'un déploiement d'entreprise effectué.

Sources dans main : [`Poste.swift`](apps/mac/Sources/Poste.swift),
[`SupportConfig.swift`](apps/ios/Sources/SupportConfig.swift),
[`settings.py`](apps/windows/papai/settings.py), [stratégies Windows](apps/windows/policies/),
[`storage.py`](backend/storage.py), [`orgs.py`](backend/orgs.py),
[`sessions.py`](backend/sessions.py), [`app.py`](backend/app.py),
[`web_agent.py`](backend/web_agent.py), [`linkup.py`](backend/linkup.py),
[`suggest.py`](backend/suggest.py), [`Narration.swift`](apps/mac/Sources/Narration.swift),
[`narration.js`](apps/windows/ui/narration.js),
[`SupportConfig.kt`](apps/android/app/src/main/java/com/quentin/papai/aidant/SupportConfig.kt),
[`billing.py`](backend/billing.py), [`ticket_stats.py`](backend/ticket_stats.py),
[`Rangement.swift`](apps/mac/Sources/Rangement.swift) et [tests](tests/).

## Anti-arnaque et sécurité

- **Validation côté serveur**, pas seulement dans l'interface ; l'import d'un
  automate vaut validation de ses actions prévues. Le format `.papai` n'accepte
  ni commande arbitraire ni script.
- **Arrêt local sur Mac**, y compris hors connexion ; captures sans la fenêtre
  PapAI, contrôle d'ancienneté des captures pour les clics du support.
- **Zones sensibles sur Mac** : contrôles natifs avant les gestes, notamment sur
  les fenêtres système et de mots de passe ; un refus suspend Holo pour demander
  l'assistance du support. Ce n'est pas une garantie de reconnaissance de toute
  opération sensible sur tous les systèmes.
- **Gardien anti-arnaque** : règles sur les demandes et plans, et protection en
  temps réel optionnelle sur Mac/Windows. Hors assistance, elle envoie toutes les
  huit secondes des noms d'applications, un titre de fenêtre et un nom de site,
  **jamais une image de l'écran** ; désactivée, elle n'envoie pas ces signaux.
- **Navigateur sur Mac** : Chrome PapAI séparé, profil supprimé après l'assistance ;
  l'utilisateur se connecte lui-même, sans import de cookies ni mots de passe.
  La surveillance des sorties de sites suspend Holo et demande l'accord du support.
- **Accès** : l'IT configure le rattachement des postes et du support à
  l'organisation, sans liaison manuelle dans les interfaces entreprise. Les jetons
  individuels sont révocables : connexions coupées et assistance validée par le
  support révoqué arrêtée. Les liens d'une assistance terminée ne donnent plus
  accès aux images et ne permettent pas de relancer cette ancienne assistance.
  Ne publier aucun secret ni lien d'accès.

Sources : [`backend/sessions.py`](backend/sessions.py), [`backend/guard.py`](backend/guard.py),
[`backend/automations.py`](backend/automations.py), [`Safety.swift`](apps/mac/Sources/Safety.swift),
[`Core.swift`](apps/mac/Sources/Core.swift), [`WebAgent.swift`](apps/mac/Sources/WebAgent.swift)
et [`PROTOCOL.md`](PROTOCOL.md).

## Architecture et technologies

```text
Ordinateur de Christine          Serveur PapAI                 H Company
Mac (SwiftUI) ou Windows   <---> Python / FastAPI / WebSockets <---> Holo
capture, gestes, automates       organisations, validation,    plan, computer use
                                tickets, gardien
                                        ^
                                        |
                            Support IT : Mac, iPhone,
                            Android ou navigateur
```

- Holo : modèle `holo3-1-35b-a3b` par défaut, configurable, et Agents API pour le
  navigateur sur Mac (installation locale et accès H requis).
- Mac/iPhone : Swift et SwiftUI ; capture Mac via ScreenCaptureKit et gestes via CGEvent.
- Windows : Python, pywebview/WebView2. Android : Kotlin et Jetpack Compose.
- Gladia : API v2, transcription française enregistrée et relais WebSocket direct.
- Hébergement prévu par le dépôt : Google Cloud Run ; **cette documentation ne
  vérifie pas la révision en production**.
- Données : stockage local par défaut ; Firestore et Cloud Storage disponibles
  selon la configuration serveur. Le disque local seul ne garantit pas la
  conservation après redéploiement sur un hébergement éphémère.
- Linkup : recherche documentaire sourcée, avec validation du support ; accès
  fournisseur à configurer. Stripe : abonnement en **mode test uniquement**.

## Développer en local

Prérequis : Python 3.12 et `uv`, accès à Holo. Depuis la racine du dépôt :

```bash
cp .env.example .env
# Renseigner HAI_API_KEY dans .env, hors Git ; GLADIA_API_KEY est facultative.
uv venv -p 3.12 .venv
uv pip install -p .venv -r requirements-backend.txt
PORT=8000 .venv/bin/python -m backend.app
```

Ne pas activer le mode public pour un simple essai local, ne jamais versionner
`.env` et ne pas diffuser les adresses d'accès produites au démarrage.
Le contrat des routes et messages est dans [`PROTOCOL.md`](PROTOCOL.md), y compris
la création d'organisation et l'inscription des postes.

Pour les apps : [Mac](apps/mac/scripts/install-mac.sh),
[iPhone](apps/ios/scripts/install-iphone.sh), [Windows](apps/windows/README.md)
et [Android](apps/android/README.md). Les scripts Apple nécessitent macOS et les
autorisations système adéquates. Les réglages entreprise MDM/GPO ci-dessus sont
dans main ; leur déploiement réel reste à vérifier.

## Devin : un relevé vérifiable, pas une promesse

Au point de référence ci-dessus, `git log origin/main` compte **781 commits**,
**8 identités auteur (nom + adresse)** et **5 adresses distinctes**, pas cinq
personnes certifiées. Les identités Git de Devin totalisent **618 commits**
(587 « Devin AI » + 31 « devin-ai-integration[bot] »), dont **451 hors fusion**
et **167 de fusion**. Ce n'est pas un décompte de changements fonctionnels.

[#90](https://github.com/Firfal/PapAI/pull/90) est une **fusion, pas un squash** :
`b905883` a deux parents (`19a958d` et `062ef2c`). Les commits des branches
intégrées sont donc présents dans l'historique complet ; on les compte une seule
fois, sans ajouter à nouveau un total par PR.

GitHub indique **68 PR fusionnées**, dont **60 de l'application Devin** ; leurs
SHA de fusion sont tous présents dans `git log origin/main`. Le relevé du
8 novembre comprend **39 PR de Devin : 25 fusionnées, 11 ouvertes, trois fermées
sans fusion**. Liste, auteurs, liens et commandes de recomptage :
[section Devin de la soumission](docs/soumission.md#devin).

Agents de l'équipe : lire [`AGENTS.md`](AGENTS.md) et réserver les fichiers avant
de les modifier.
