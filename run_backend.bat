@echo off
cd /d "%~dp0"
rem L'IP de la machine change avec le reseau : on la relit a chaque demarrage
rem plutot que de la figer. Le QR code du proche pointe ainsi toujours juste.
powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceAlias -notlike '*WSL*' -and $_.InterfaceAlias -notlike '*Hyper-V*' -and $_.InterfaceAlias -notlike '*Docker*' } | Select-Object -First 1 -ExpandProperty IPAddress)" > "%TEMP%\cp_ip.txt"
set /p IP=<"%TEMP%\cp_ip.txt"
echo Adresse detectee : %IP%
set CAREPILOT_PUBLIC_URL=http://%IP%:8000
.venv\Scripts\python.exe -m backend.app
