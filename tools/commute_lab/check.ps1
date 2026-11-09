param([switch]$Capture,[switch]$SessionOnly,[switch]$WarehouseViews)
$ErrorActionPreference='Stop'
$commuteRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$commuteOutput=Join-Path $commuteRoot 'output\commute-lab'
New-Item -ItemType Directory -Force -Path $commuteOutput | Out-Null
$env:PICTURE_SHOP_COMMUTE_LAB='1'
$env:PICTURE_SHOP_SMOKE='1'
$env:PICTURE_SHOP_COMMUTE_TEST='1'
if($SessionOnly){$env:PICTURE_SHOP_COMMUTE_SESSION_TEST='1'}
if($Capture -or $WarehouseViews){ $env:PICTURE_SHOP_COMMUTE_CAPTURE=$commuteOutput }
if($WarehouseViews){$env:PICTURE_SHOP_WAREHOUSE_REVIEW='1'}
$commuteProcess=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$commuteRoot+'"') -WorkingDirectory $commuteRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $commuteOutput 'stdout.txt') -RedirectStandardError (Join-Path $commuteOutput 'stderr.txt')
try {
    if(-not $commuteProcess.WaitForExit(60000)){ Stop-Process -Id $commuteProcess.Id -Force; throw 'Commute check timed out' }
    Get-Content (Join-Path $commuteOutput 'stdout.txt')
    Get-Content (Join-Path $commuteOutput 'stderr.txt')
    if($commuteProcess.ExitCode -ne 0){ throw ('Commute check failed: '+$commuteProcess.ExitCode) }
} finally {
    Remove-Item Env:PICTURE_SHOP_COMMUTE_LAB,Env:PICTURE_SHOP_SMOKE,Env:PICTURE_SHOP_COMMUTE_TEST,Env:PICTURE_SHOP_COMMUTE_CAPTURE,Env:PICTURE_SHOP_COMMUTE_SESSION_TEST,Env:PICTURE_SHOP_WAREHOUSE_REVIEW -ErrorAction SilentlyContinue
}
