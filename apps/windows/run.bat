@echo off
cd /d "%~dp0"
rem Serveur par defaut : local. Pour le serveur en ligne :
rem   set PAPAI_SERVER=wss://votre-hote/k/<cle>/ws/bridge
if "%PAPAI_SERVER%"=="" set PAPAI_SERVER=ws://localhost:8000/ws/bridge
..\..\.venv\Scripts\python.exe -m papai.main
