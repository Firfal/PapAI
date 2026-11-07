#!/bin/bash
# Compile PapAI, le signe avec la première identité valide (gdb-cert, comme
# Insomnia et Signet : macOS garde ainsi les permissions d'un build à l'autre)
# et l'installe dans ~/Applications. Relancer pour mettre à jour.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v xcodegen >/dev/null && xcodegen generate --quiet
xcodebuild -project PapAI.xcodeproj -scheme PapAI -destination 'platform=macOS' \
  -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build -quiet
APP="build/Build/Products/Release/PapAI.app"
# Première identité valide qui accepte vraiment de signer (gdb-cert d'abord ;
# si sa clé privée est inaccessible, la suivante). Jamais de signature ad hoc.
SIGNED=""
while IFS= read -r SIGN; do
  [[ -z "$SIGN" ]] && continue
  if codesign --force --deep --sign "$SIGN" "$APP" 2>/dev/null; then SIGNED="$SIGN"; break; fi
  echo "identité « $SIGN » inutilisable, essai suivant" >&2
done < <(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' 'NF>2 {print $2}')
if [[ -z "$SIGNED" ]]; then
  echo "Aucune identité de signature utilisable : arrêt (jamais ad hoc, macOS redemanderait les permissions)." >&2
  exit 1
fi
echo "signé avec $SIGNED"
mkdir -p "$HOME/Applications"
if [[ -d "$HOME/Applications/PapAI.app" ]]; then
  # On garde l'ancienne version au lieu de la supprimer.
  mv "$HOME/Applications/PapAI.app" "$ROOT/build/PapAI-previous-$(date +%Y%m%d-%H%M%S).app"
fi
ditto "$APP" "$HOME/Applications/PapAI.app"
echo "installé : $HOME/Applications/PapAI.app"
