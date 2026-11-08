# Démo PapAI : checklist du jour J

Une page, à imprimer. Mac = celui de Jeanne (l’utilisateur). iPhone = celui du support (Quentin).
Serveur : `https://papai-450417131702.europe-west1.run.app` (une seule instance, état en mémoire).
Rien de ce scénario n'a encore été fait en entier sur le vrai Mac : **faire la répétition complète avant**, au moins une fois.

## Avant

- [ ] **H − 60 min : plus aucun déploiement Cloud Run.** Un redéploiement efface les automates et oblige à relancer les apps.
- [ ] **Réseau** : celui de la scène, essayé sur place par le Mac et l'iPhone (dictée comprise). Partage de connexion 4G prêt en secours.
- [ ] **Mac** : sur secteur, Ne pas déranger, son coupé, une seule fenêtre de chaque app.
- [ ] **Bureau dégagé** : aucune app en plein écran (Brave quitté), aucune fenêtre Finder ouverte,
      **aucune fenêtre d'autorisation macOS** à l'écran (c'est un humain qui y répond, avant la démo, jamais Holo).
- [ ] **PapAI ouverte** à l'accueil, relancée après le dernier déploiement, prénom « Jeanne », serveur en ligne réglé.
      Autorisations déjà données : Enregistrement de l'écran, Accessibilité, Micro, Reconnaissance vocale (faire une dictée d'essai avant).
- [ ] **Gardien** : aucun outil de prise en main ouvert (AnyDesk, TeamViewer…), sinon une alerte s'affiche par-dessus tout entre deux sessions.
      Si macOS demande d'autoriser PapAI à contrôler un navigateur (lecture de l'adresse), répondre avant la démo.
- [ ] **Dossier** `~/Pictures/Noël 2025` présent avec ses 4 images ; aucun autre dossier « Noël 2025 » ailleurs (Bureau compris).
- [ ] **iPhone** : app PapAI **au premier plan** et connectée, Verrouillage auto sur Jamais, Ne pas déranger, batterie chargée.
      En arrière-plan, la connexion se coupe et le plan n'arrive pas.
- [ ] **H − 30 min : automate de secours créé** (session complète puis « Garder comme automate »). Sur le Mac, la tuile rouvre bien le dossier.
      Hors de la vue du public, vérifier que le raccourci retient le sous-dossier :
      `curl -s https://papai-450417131702.europe-west1.run.app/k/<clé famille>/lessons` doit contenir `"subfolder": "Noël 2025"`.
      Sinon la tuile ouvre seulement Images, et le déplacement du dossier ne déclenchera pas d'alerte.
- [ ] Vidéo de 2 min prête à lancer (plan B), sur l'ordinateur de projection.

## Scénario (environ 3 min, ce qu'on doit voir à chaque pas)

1. **Demande** (Mac) : toucher le micro, dire « Je veux voir mes photos de Noël », retoucher le micro. Le texte apparaît (Gladia). « Demander une assistance ».
2. **Consentement** (Mac) : « PapAI va regarder votre écran », accepter. L'iPhone reçoit la demande.
3. **Plan** (iPhone) : le plan de Holo arrive. Le lire à voix haute. Il propose souvent l'app Photos : c'est voulu.
4. **Précision** (iPhone) : Préciser, écrire « dans le Finder, Images › Noël 2025 ». Un nouveau plan arrive sur l'iPhone et le Mac.
5. **Validation** (iPhone) : Valider. **Plus personne ne touche la souris.**
6. **Holo ouvre le dossier** (Mac) : Finder, Images, Noël 2025. Une phrase et l'étape du plan à chaque action (environ 6,5 s par action). « C'est fait ! ».
7. **Garder comme automate** (iPhone) : relire le brouillon, Valider. La tuile apparaît dans « Mes automates » sur l'accueil du Mac.
8. **Rejeu** (Mac) : fermer la fenêtre Finder, cliquer la tuile. « C'est ouvert. », le dossier s'ouvre sans appel à Holo.
9. **Déplacement** : fermer le Finder, glisser `Noël 2025` d'Images vers le Bureau (déplacer, jamais supprimer).
10. **Alerte** : cliquer la tuile. Mac : « Je ne retrouve pas ce dossier. <prénom du proche> a reçu un message pour s'en occuper. »
    iPhone : alerte au titre de l'automate, « « Noël 2025 » n'existe pas (ou plus) sur cet ordinateur. »

Après : remettre `Noël 2025` du Bureau dans Images.

## Plan B si Holo rate

| Ce qui arrive | Ce qu'on fait |
|---|---|
| Le plan touche une fenêtre d'autorisation, une app en plein écran ou part ailleurs | **Refuser** sur l'iPhone et le dire : « rien n'a bougé, c'est le proche qui décide ». Dégager l'écran, relancer une fois. |
| Holo clique à côté ou tourne en rond pendant l'exécution | **Arrêter** sur le Mac. Puis sauter à l'étape 8 avec la tuile de secours. |
| Le plan n'arrive pas après 30 s (Holo lent ou indisponible) | Lancer la vidéo pour les étapes 1 à 6, puis faire 8 à 10 en direct avec la tuile de secours : elles n'appellent pas Holo. |
| « Garder comme automate » échoue (l'iPhone libère le bouton) | Réessayer une fois, sinon utiliser la tuile de secours. |
| La dictée ne répond pas | Taper la demande au clavier, continuer. |
| Le plan n'arrive pas sur l'iPhone | Remettre l'app au premier plan. Sinon, page web du proche `…/a/<clé famille>` sur un autre appareil (essayée en local seulement). |
| L'alerte n'arrive pas sur l'iPhone | Montrer le message du Mac ; ne pas dire « le proche est prévenu ». |
| Plus de réseau | Vidéo de 2 min en entier, script dit par-dessus. |

Jamais pendant la démo : redéployer, toucher la souris quand Holo agit, cliquer une fenêtre d'autorisation, montrer la clé famille.
