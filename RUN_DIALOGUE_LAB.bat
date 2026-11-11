@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\dialogue_lab\launch.ps1"
if errorlevel 1 pause
