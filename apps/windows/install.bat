@echo off
rem Une seule fois : crée l'environnement Python de l'app Windows.
cd /d "%~dp0"
where py >nul 2>nul && (py -3 -m venv .venv) || (python -m venv .venv)
if errorlevel 1 (
  echo Python 3.10 ou plus recent est necessaire : https://www.python.org/downloads/windows/
  pause & exit /b 1
)
.venv\Scripts\python.exe -m pip install --upgrade pip
.venv\Scripts\python.exe -m pip install -r requirements.txt
echo.
echo Installation terminee. Lancez PapAI avec run.bat
pause
