#!/bin/bash
# Crée, une seule fois, un certificat de signature local « PapAI Dev » dans le
# trousseau de session. Avec lui, chaque recompilation garde la même identité :
# macOS se souvient des autorisations (Écran, Accessibilité, Micro) au lieu de
# les oublier à chaque build, comme avec une signature ad hoc.
# Rien n'est ajouté aux certificats de confiance du système.
set -euo pipefail
NAME="PapAI Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Le certificat « $NAME » existe déjà."
  exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cfg" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="papai-dev"
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/id.p12" -passout pass:"$PASS" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
       -out "$TMP/id.p12" -passout pass:"$PASS"
# -T : codesign peut utiliser la clé sans redemander à chaque build.
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign
echo "Certificat « $NAME » créé. Recompilez PapAI : apps/mac/scripts/build-mac-cli.sh"
