@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\shadow_lab\launch.ps1" -Smoke
if errorlevel 1 pause
