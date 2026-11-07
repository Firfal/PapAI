# PapAI — Windows

Portage de l'app Mac (`apps/mac`), même protocole et même dessin. Le serveur ne
fait aucune différence entre les deux : il envoie `capture` et `execute`, il
reçoit `frame` et `result`.

Le rendu passe par WebView2 — présent d'origine sur Windows 11 — ce qui permet
de reprendre les jetons de `apps/mac/Sources/Theme.swift` tels quels plutôt que
d'approximer le dessin avec des composants natifs.

## Lancer

```bat
py -3.11 -m venv ..\..\.venv
..\..\.venv\Scripts\pip install -r requirements.txt
run.bat
```

Variables :

| | |
|---|---|
| `PAPAI_SERVER` | `ws://localhost:8000/ws/bridge` par défaut ; en ligne, `wss://<hôte>/k/<clé>/ws/bridge` |
| `PAPAI_PRENOM` | `Jeanne` |
| `PAPAI_AIDANT` | `Quentin` |

Aucune autorisation à accorder : Windows ne demande ni capture d'écran ni
accessibilité, contrairement à macOS.

## Ce qui est porté

| | |
|---|---|
| Accueil : demande, consentement, raccourcis, applications | ✅ |
| Session : plan affiché, états, bouton Arrêter | ✅ |
| Pas à pas d'un automatisme | ✅ |
| Capture, exclusion de la fenêtre PapAI | ✅ |
| Clics, saisie, touches, défilement | ✅ codés, pas encore exercés |
| Verrou d'arrêt local | ✅ |
| Gardien anti-arnaque (processus + fenêtre active) | ✅ |
| URL du navigateur pour le gardien | ⬜ le Mac l'obtient par AppleScript, pas d'équivalent simple ici |
| Icônes réelles des applications | ⬜ symboles en attendant |

## Les différences assumées

**Les touches.** Le modèle, entraîné sur macOS, propose `cmd+…`. Le pont le
traduit en `ctrl+…` : c'est la même intention sur les deux systèmes.

**Les applications.** macOS a des identifiants de paquet stables
(`com.apple.mail`). Windows n'a pas d'équivalent, alors on cherche les
raccourcis du menu Démarrer — ce que l'utilisateur voit lui-même. Un filtre
écarte les pièges : sans lui, « Zoom » tombe sur *Uninstall Zoom Workplace*.

**Les dossiers.** Jamais de chemin écrit en dur : l'API des dossiers connus de
Windows, qui suit les redirections OneDrive.
