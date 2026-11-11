@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\critter-studio\launch.ps1"
if errorlevel 1 pause
