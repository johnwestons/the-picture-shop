@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_gameplay_smoke.ps1"
set "GAMEPLAY_EXIT=%ERRORLEVEL%"
echo.
if not "%GAMEPLAY_EXIT%"=="0" echo Gameplay readiness failed. Inspect the output\gameplay-smoke reports.
pause
exit /b %GAMEPLAY_EXIT%
