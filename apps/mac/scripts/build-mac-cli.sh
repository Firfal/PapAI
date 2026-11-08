#!/bin/bash
# Compile PapAI sans Xcode (Command Line Tools seuls) : swiftc + bundle .app
# à la main + signature ad hoc. macOS peut redemander les permissions
# (Écran, Accessibilité) après chaque recompilation.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT="build/cli"
APP="$OUT/PapAI.app"
mkdir -p "$OUT"
swiftc -O -swift-version 5 -enable-bare-slash-regex -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  Sources/*.swift Sources/Support/*.swift ../shared/*.swift \
  ../ios/Sources/{HelperModel,People,SupportConfig,Platform,FlowLayout}.swift -o "$OUT/PapAI"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/PapAI" "$APP/Contents/MacOS/PapAI"
sed -e 's/$(DEVELOPMENT_LANGUAGE)/fr/' -e 's/$(EXECUTABLE_NAME)/PapAI/' \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.quentin.papai/' \
    -e 's/$(PRODUCT_NAME)/PapAI/' Sources/Info.plist > "$APP/Contents/Info.plist"

# Icône : l'asset catalog demande actool (Xcode), on fabrique un .icns.
ICONS="Resources/Assets.xcassets/AppIcon.appiconset"
if [[ -f "$ICONS/icon-1024.png" ]]; then
  SET="$OUT/AppIcon.iconset"; rm -rf "$SET"; mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICONS/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ICONS/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "construit : $ROOT/$APP"
