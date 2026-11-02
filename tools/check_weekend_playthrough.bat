@echo off
setlocal
set "PICTURE_SHOP_COMMUTE_RESET="
set "PICTURE_SHOP_COMMUTE_LAB="
set "PICTURE_SHOP_RIDE_PREVIEW="
set "PICTURE_SHOP_COMMUTE="
set "PICTURE_SHOP_SMOKE=1"
set "weekendFocus=weekend-playthrough"
if /I "%~1"=="weekend-flow" set "weekendFocus=weekend-flow"
set "PICTURE_SHOP_SMOKE_FOCUS=%weekendFocus%"
set "PICTURE_SHOP_TEST_IDENTITY=the-picture-shop-test-weekend-playthrough"
set "weekendOutput=%~dp0..\output\%weekendFocus%"
if not exist "%weekendOutput%" mkdir "%weekendOutput%"
set "PICTURE_SHOP_HOME_PREVIEW_DIR=%weekendOutput%"
set "PICTURE_SHOP_SMOKE_REPORT=%weekendOutput%\report.rpt"
"C:\Program Files\LOVE\lovec.exe" "%~dp0.." > "%weekendOutput%\stdout.txt" 2>&1
set "weekendExit=%errorlevel%"
type "%weekendOutput%\stdout.txt"
exit /b %weekendExit%
