@echo off
rem PapAI pour Windows : double-cliquer ce fichier, rien a installer.
rem Au premier lancement, un Python portable et les dependances sont recuperes
rem dans le dossier .python, a cote de ce fichier (aucune installation sur le PC).
setlocal
cd /d "%~dp0"
set "PYDIR=%~dp0.python"
set "PY=%PYDIR%\python.exe"
set "PYURL=https://www.python.org/ftp/python/3.12.8/python-3.12.8-embed-amd64.zip"

if not exist "%PY%" (
  echo Premier lancement : preparation de PapAI, une minute environ...
  if not exist "%PYDIR%" mkdir "%PYDIR%"
  curl.exe -fsSL -o "%PYDIR%\python.zip" "%PYURL%" || goto :erreur
  tar.exe -xf "%PYDIR%\python.zip" -C "%PYDIR%" || goto :erreur
  del "%PYDIR%\python.zip"
  rem ".." : le dossier apps\windows, pour que "python -m papai" trouve l'app.
  (echo python312.zip& echo .& echo Lib\site-packages& echo ..& echo import site)> "%PYDIR%\python312._pth"
  curl.exe -fsSL -o "%PYDIR%\get-pip.py" https://bootstrap.pypa.io/get-pip.py || goto :erreur
  "%PY%" "%PYDIR%\get-pip.py" -q --no-warn-script-location || goto :erreur
  "%PY%" -m pip install -q --no-warn-script-location setuptools wheel || goto :erreur
)

rem Dependances : reinstallees seulement quand requirements.txt change.
fc /b requirements.txt "%PYDIR%\requirements.txt" >nul 2>nul
if errorlevel 1 (
  echo Installation des dependances...
  "%PY%" -m pip install -q --disable-pip-version-check --no-warn-script-location --no-build-isolation -r requirements.txt || goto :erreur
  copy /y requirements.txt "%PYDIR%\requirements.txt" >nul
)

start "" "%PYDIR%\pythonw.exe" -m papai
exit /b 0

:erreur
echo.
echo La preparation de PapAI a echoue. Verifiez la connexion Internet puis relancez PapAI.bat.
echo Pour repartir de zero : supprimez le dossier .python a cote de ce fichier.
pause
exit /b 1
