@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0.stabilization\run-sprite-lab.ps1"
if errorlevel 1 pause
