@echo off
cd /d "%~dp0"
rem L IP locale est detectee au demarrage. Ne definir CAREPILOT_PUBLIC_URL
rem que pour pointer vers un backend heberge.
.venv\Scripts\python.exe -m backend.app
