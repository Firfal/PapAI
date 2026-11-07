@echo off
rem Lance PapAI. Serveur par defaut : ws://localhost:8000/ws/bridge
rem (modifiable dans les reglages de l'app, ou avec PAPAI_SERVER).
cd /d "%~dp0"
if not exist .venv\Scripts\pythonw.exe call install.bat
start "" .venv\Scripts\pythonw.exe -m papai
