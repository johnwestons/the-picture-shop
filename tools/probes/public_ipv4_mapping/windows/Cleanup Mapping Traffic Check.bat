@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_mapping_traffic_check.ps1" -Action Cleanup
echo.
pause
