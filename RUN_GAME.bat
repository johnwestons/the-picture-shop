@echo off
setlocal
set "LOVE_EXE="
where love.exe >nul 2>nul && set "LOVE_EXE=love.exe"
if not defined LOVE_EXE if exist "%~dp0runtime\love.exe" set "LOVE_EXE=%~dp0runtime\love.exe"
if not defined LOVE_EXE if exist "%ProgramFiles%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles%\LOVE\love.exe"
if not defined LOVE_EXE if exist "%ProgramFiles(x86)%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles(x86)%\LOVE\love.exe"
if not defined LOVE_EXE (
  echo LOVE 11.x was not found.
  echo Install it from https://love2d.org/ and run this file again.
  pause
  exit /b 1
)
pushd "%~dp0"
"%LOVE_EXE%" "."
set "GAME_EXIT=%ERRORLEVEL%"
popd
exit /b %GAME_EXIT%
