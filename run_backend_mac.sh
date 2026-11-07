#!/bin/bash
# Serveur PapAI en local sur macOS (équivalent de run_backend.bat).
cd "$(dirname "$0")"
PAPAI_AIDANT_KEY="${PAPAI_AIDANT_KEY:-demo}" PORT="${PORT:-8000}" exec .venv-mac/bin/python -m backend.app
