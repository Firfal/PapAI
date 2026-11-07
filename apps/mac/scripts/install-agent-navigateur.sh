#!/bin/bash
# Installe l'agent navigateur de H pour PapAI, sur le Mac de la personne aidée.
#   apps/mac/scripts/install-agent-navigateur.sh
# Crée ~/Library/Application Support/PapAI/agent-navigateur/venv (holo) et le
# profil dédié de Chrome PapAI. La clé H n'est jamais écrite par ce script.
set -euo pipefail

SUPPORT="$HOME/Library/Application Support/PapAI"
VENV="$SUPPORT/agent-navigateur/venv"
PAQUET="hai-agents[cli,browser]>=1.2.2"
mkdir -p "$SUPPORT/agent-navigateur" "$SUPPORT/Chrome"

if command -v uv >/dev/null 2>&1; then
  uv venv -q -p 3.12 "$VENV"
  uv pip install -q -p "$VENV/bin/python" "$PAQUET"
else
  PY=""
  for c in python3.13 python3.12 python3.11 python3.10; do
    if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
  done
  if [ -z "$PY" ]; then
    echo "Python 3.10 ou plus récent est nécessaire (brew install python@3.12)." >&2
    exit 1
  fi
  "$PY" -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q "$PAQUET"
fi

found=""
for app in "Google Chrome" "Brave Browser" "Microsoft Edge"; do
  if [ -d "/Applications/$app.app" ]; then found="$app"; break; fi
done
echo "holo installé : $VENV/bin/holo"
echo "Navigateur pour Chrome PapAI : ${found:-aucun (installer Google Chrome)}"

# holo local browser exige une clé H sur ce Mac.
if [ -z "${HAI_API_KEY:-}" ] && [ ! -s "$HOME/.config/hai/.env" ]; then
  echo "Clé H absente sur ce Mac. Lancez : \"$VENV/bin/holo\" login"
  echo "(ou mettez HAI_API_KEY=... dans ~/.config/hai/.env). Ne la copiez jamais dans le dépôt."
fi
