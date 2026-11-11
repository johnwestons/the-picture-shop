@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\dialogue_lab\launch.ps1" -Smoke
if errorlevel 1 pause
