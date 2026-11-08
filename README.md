<p align="center"><img src="brand/papai-mascotte-pastel.svg" width="120" alt="PapAI"></p>

# PapAI — le support informatique de premier niveau, automatisé

Christine décrit son problème sur son ordinateur. **Holo** propose un plan ; le
**support IT** le valide, le précise ou le refuse avant l'exécution. L'organisation
partage ses **automates** pour que les utilisateurs relancent les tâches courantes
sans ouvrir une nouvelle assistance à chaque fois.

Hackathon H Company × 42 AI, 7–8 novembre 2026.

La version famille existe sur la branche [`archive/particuliers`](https://github.com/Firfal/PapAI/tree/archive/particuliers).

## État de référence

Lecture du code au **8 novembre 2026, 09 h 30 UTC**, sur
[`main` à `19a958d`](https://github.com/Firfal/PapAI/commit/19a958d).
**[en PR]** signifie : code présent sur la branche liée, mais pas encore dans ce
main ; cela ne signifie ni intégré, ni déployé, ni essayé sur un parc réel.
Les textes prêts à copier et le relevé détaillé des contributions Devin sont dans
[`docs/soumission.md`](docs/soumission.md). Priorités et limites : [`TODO.md`](TODO.md).

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
  postes ; les jetons individuels révocables restent **[en PR] #77**.
- **Catalogue partagé** : les automates importés dans l'organisation sont copiés
  vers ses postes, y compris ceux inscrits ensuite. Sept exemples sont fournis
  dans [`automations/`](automations/) ; un nouvel espace ne les charge pas tout seul.
- **Support Mac** : onglets **Tickets**, **Utilisateurs**, **Mes automates** ;
  bibliothèque locale, import `.papai` et application à plusieurs utilisateurs.
  Le bouton de création est masqué (`creationActive = false`), même si le code
  de brouillon depuis un document ou un enregistrement est conservé.
- **Tickets** : attente, rendez-vous, prise en charge, notes, clôture et réouverture ;
  vue d'organisation web avec filtres et export CSV. Les catégories et graphiques
  restent **[en PR] #86**.

Sources : [`backend/orgs.py`](backend/orgs.py), [`backend/space.py`](backend/space.py),
[`backend/tickets.py`](backend/tickets.py), [`tickets.js`](backend/static/tickets.js),
[`SupportAutomates.swift`](apps/mac/Sources/Support/SupportAutomates.swift) et
[`SupportTickets.swift`](apps/mac/Sources/Support/SupportTickets.swift).

## Entreprise : compléments non encore intégrés

Chaque ligne est **[en PR]**, vérifiée sur la branche correspondante.

| Fonctionnalité | État et périmètre du code |
|---|---|
| Mac configuré par l'IT | **[en PR] [#71](https://github.com/Firfal/PapAI/pull/71)** : préférences gérées par profil MDM, serveur, organisation et nom affiché ; parcours initial retiré. |
| Support connecté d'office | **[en PR] [#72](https://github.com/Firfal/PapAI/pull/72)** : configuration de l'organisation sur Mac/iPhone, liste des postes et retrait de la liaison poste par poste dans les interfaces concernées. |
| Windows par stratégie de groupe | **[en PR] [#75](https://github.com/Firfal/PapAI/pull/75)** : lecture des stratégies machine/utilisateur, modèles ADMX/ADML, organisation et serveur configurés par l'IT ; intègre aussi les automates locaux hors ligne de #69. |
| Liens d'assistance terminée | **[en PR] [#73](https://github.com/Firfal/PapAI/pull/73)** : coupe l'accès aux images après la fin et refuse le rafraîchissement d'une ancienne assistance. |
| Stockage durable | **[en PR] [#76](https://github.com/Firfal/PapAI/pull/76)** : interface disque local ou Firestore, Cloud Storage pour les images ; dépend de la configuration des services. |
| Un jeton par support | **[en PR] [#77](https://github.com/Firfal/PapAI/pull/77)** : empreinte du jeton conservée, clés de poste dérivées, révocation et coupure des connexions. |
| Sites du navigateur validés | **[en PR] [#79](https://github.com/Firfal/PapAI/pull/79)** : détection d'une sortie des sites prévus, pause et demande d'accord au support ; ce n'est pas un pare-feu réseau. |
| Linkup | **[en PR] [#80](https://github.com/Firfal/PapAI/pull/80)** : recherche documentaire proposée avant l'exécution, requête relue par le support, réponse sourcée ; résultats non transmis à Holo. |
| Automates pendant l'attente | **[en PR] [#81](https://github.com/Firfal/PapAI/pull/81)** : jusqu'à deux propositions pertinentes, classement par mots communs sans modèle. |
| Narration à voix haute | **[en PR] [#82](https://github.com/Firfal/PapAI/pull/82)** : lecture locale en français sur Mac et Windows, désactivable et interrompue pendant la dictée. |
| Android du support en entreprise | **[en PR] [#83](https://github.com/Firfal/PapAI/pull/83)** : configuration gérée Android Enterprise ou configuration locale de démonstration, organisation et gestion du retrait d'accès. |
| Abonnement Stripe | **[en PR] [#84](https://github.com/Firfal/PapAI/pull/84)** : Checkout, portail et webhook signé, **mode test seulement**, pas d'encaissement réel. |
| Correction des tests | **[en PR] [#85](https://github.com/Firfal/PapAI/pull/85)** : attentes de liaison et d'actions sensibles alignées sur « utilisateur » ; aucune garantie sur les tests des autres branches. |
| Catégories et graphiques des tickets | **[en PR] [#86](https://github.com/Firfal/PapAI/pull/86)** : classement par règles, Holo en cas de doute, correction par le support, statistiques web et Mac. |
| Rangement guidé des dossiers | **[en PR] [#87](https://github.com/Firfal/PapAI/pull/87)** : Mac seulement, noms de fichiers sans leur contenu, déplacements validés par le support, sans écrasement, avec journal d'annulation. |

Les profils MDM et stratégies de groupe préparent la **configuration** du parc :
ces PR ne constituent pas un service de distribution des applications ni la preuve
d'un déploiement d'entreprise effectué.

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
  La surveillance des sorties de sites reste **[en PR] #79**.
- **Accès** : espaces et organisation utilisent des secrets d'accès ; les liens
  de liaison ne portent pas la clé du poste et exigent un accord sur l'ordinateur.
  Ne publier aucun secret ni lien d'accès. Révocation individuelle et fermeture
  des images d'une assistance terminée restent **[en PR] #77 et #73**.

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
  vérifie pas la révision en production**. Firestore/Cloud Storage et Linkup
  restent **[en PR] #76 et #80**.

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
autorisations système adéquates. Les réglages entreprise MDM/GPO ci-dessus ne
sont pas encore ceux de main.

## Devin : un relevé vérifiable, pas une promesse

Au point de référence ci-dessus, `git log origin/main` compte **620 commits**,
**8 identités auteur (nom + adresse)** et **5 adresses distinctes**, pas cinq
personnes certifiées. Les identités Git de Devin totalisent **471 commits**
(440 « Devin AI » + 31 « devin-ai-integration[bot] »), dont **347 hors fusion**
et **124 de fusion**.

GitHub indique **52 PR fusionnées**, dont **47 de l'application Devin** ; leurs
SHA de fusion sont tous présents dans `git log origin/main`. Le relevé du
8 novembre comprend **30 PR de Devin : 12 fusionnées, 17 ouvertes, une fermée
sans fusion**. Liste, auteurs, liens et commandes de recomptage :
[section Devin de la soumission](docs/soumission.md#devin).

Agents de l'équipe : lire [`AGENTS.md`](AGENTS.md) et réserver les fichiers avant
de les modifier.
