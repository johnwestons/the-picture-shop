@echo off
setlocal
set "PICTURE_SHOP_WAREHOUSE_PERSPECTIVE_LAB=1"
set "LOVE_EXE="
where love.exe >nul 2>nul && set "LOVE_EXE=love.exe"
if not defined LOVE_EXE if exist "%~dp0runtime\love.exe" set "LOVE_EXE=%~dp0runtime\love.exe"
if not defined LOVE_EXE if exist "%ProgramFiles%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles%\LOVE\love.exe"
if not defined LOVE_EXE if exist "%ProgramFiles(x86)%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles(x86)%\LOVE\love.exe"
if not defined LOVE_EXE (
  echo LOVE 11.x was not found.
  exit /b 1
)
pushd "%~dp0"
"%LOVE_EXE%" "."
set "LAB_EXIT=%ERRORLEVEL%"
popd
exit /b %LAB_EXIT%
