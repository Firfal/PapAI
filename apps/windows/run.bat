@echo off
rem Lance PapAI avec le .venv de install.bat. Serveur par defaut : ws://localhost:8000/ws/bridge
rem (modifiable dans les reglages de l'app, ou avec PAPAI_SERVER).
cd /d "%~dp0"
if not exist .venv\Scripts\pythonw.exe call install.bat
rem Dependances ajoutees depuis l'installation : mises a jour seulement si requirements.txt a change.
fc /b requirements.txt .venv\requirements.txt >nul 2>nul
if errorlevel 1 (
  .venv\Scripts\python.exe -m pip install -q --disable-pip-version-check -r requirements.txt && copy /y requirements.txt .venv\requirements.txt >nul
)
start "" .venv\Scripts\pythonw.exe -m papai
