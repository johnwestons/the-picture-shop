@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0.stabilization\run-smoke.ps1" %*
set "TEST_EXIT=%ERRORLEVEL%"
if not "%TEST_EXIT%"=="0" pause
exit /b %TEST_EXIT%
