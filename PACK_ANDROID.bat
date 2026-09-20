@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\pack_android_share.ps1"
set "BUILD_EXIT=%ERRORLEVEL%"
if not "%BUILD_EXIT%"=="0" echo Packaging failed. Do not send an older installer by mistake.
pause
exit /b %BUILD_EXIT%
