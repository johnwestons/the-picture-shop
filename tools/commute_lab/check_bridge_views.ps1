$ErrorActionPreference='Stop'
$commuteRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$commuteOutput=Join-Path $commuteRoot 'output\commute-bridge-concrete\native-views'
New-Item -ItemType Directory -Force -Path $commuteOutput | Out-Null
$env:PICTURE_SHOP_COMMUTE_LAB='1'
$env:PICTURE_SHOP_SMOKE='1'
$env:PICTURE_SHOP_COMMUTE_CAPTURE=$commuteOutput
$env:PICTURE_SHOP_BRIDGE_REVIEW='1'
$commuteProcess=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$commuteRoot+'"') -WorkingDirectory $commuteRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $commuteOutput 'stdout.txt') -RedirectStandardError (Join-Path $commuteOutput 'stderr.txt')
try {
    if(-not $commuteProcess.WaitForExit(60000)){ Stop-Process -Id $commuteProcess.Id -Force; throw 'Bridge view capture timed out' }
    Get-Content (Join-Path $commuteOutput 'stdout.txt')
    Get-Content (Join-Path $commuteOutput 'stderr.txt')
    if($commuteProcess.ExitCode -ne 0){ throw ('Bridge view capture failed: '+$commuteProcess.ExitCode) }
} finally {
    Remove-Item Env:PICTURE_SHOP_COMMUTE_LAB,Env:PICTURE_SHOP_SMOKE,Env:PICTURE_SHOP_COMMUTE_CAPTURE,Env:PICTURE_SHOP_BRIDGE_REVIEW -ErrorAction SilentlyContinue
}
