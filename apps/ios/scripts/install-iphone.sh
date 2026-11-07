#!/bin/bash
# Installe PapAI (app de l'aidant) sur l'iPhone branché à ce Mac.
# Il faut : un identifiant Apple ajouté dans Xcode > Réglages > Comptes, l'iPhone branché
# et déverrouillé, le mode développeur activé. Avec un compte gratuit, l'app cesse de
# s'ouvrir après 7 jours : relancer ce script.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# Équipe : $TEAM, sinon .team, sinon celle de Signet (déjà utilisée sur cette machine).
TEAM="${TEAM:-$(cat .team 2>/dev/null || cat "$HOME/Signet/.team" 2>/dev/null || true)}"
if [[ -z "$TEAM" ]]; then
  TEAM="$(grep -m1 -o 'DEVELOPMENT_TEAM = [A-Z0-9]\{10\}' PapAI.xcodeproj/project.pbxproj 2>/dev/null | awk '{print $3}' || true)"
fi
[[ -n "$TEAM" ]] && echo "$TEAM" > .team
command -v xcodegen >/dev/null && xcodegen generate --quiet
if [[ -z "$TEAM" ]]; then
  echo "Aucune équipe Apple trouvée. Ajoutez votre identifiant dans Xcode > Réglages > Comptes,"
  echo "puis relancez, ou : TEAM=<id d'équipe> $0"
  exit 1
fi
DEVICE="$(xcrun devicectl list devices 2>/dev/null | grep -i iphone | grep -E 'available|connected' | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1 || true)"
if [[ -z "$DEVICE" ]]; then echo "Aucun iPhone connecté. Branchez-le, déverrouillez-le et relancez."; exit 1; fi
xcodebuild -project PapAI.xcodeproj -scheme PapAI -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic build -quiet
xcrun devicectl device install app --device "$DEVICE" build/Build/Products/Release-iphoneos/PapAIAidant.app
echo "Installée. La première fois : Réglages > Général > VPN et gestion de l'appareil > faire confiance à votre identifiant Apple."
