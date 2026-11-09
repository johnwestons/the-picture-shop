param()
$ErrorActionPreference='Stop'
$rideRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$rideOutput=Join-Path $rideRoot 'output\first-person'
New-Item -ItemType Directory -Force -Path $rideOutput | Out-Null
$rideEnv=@{
    PICTURE_SHOP_COMMUTE_LAB='1';PICTURE_SHOP_RIDE_PREVIEW='1';PICTURE_SHOP_SMOKE='1'
    PICTURE_SHOP_FIRST_PERSON_CHECK='1';PICTURE_SHOP_COMMUTE_CAPTURE=$rideOutput
    PICTURE_SHOP_COMMUTE_RESET='';PICTURE_SHOP_COMMUTE_TEST='';PICTURE_SHOP_COMMUTE_SESSION_TEST=''
    PICTURE_SHOP_RIDE_PREVIEW_CHECK='';PICTURE_SHOP_WAREHOUSE_REVIEW='';PICTURE_SHOP_BRIDGE_REVIEW=''
    PICTURE_SHOP_BIKE_REVIEW='';PICTURE_SHOP_GEAR_ACTION_REVIEW='';PICTURE_SHOP_COMMUTE_AUDIO_TEST=''
}
$ridePrevious=@{}
try {
    foreach($key in $rideEnv.Keys){$ridePrevious[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$rideEnv[$key],'Process')}
    $rideProcess=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$rideRoot+'"') -WorkingDirectory $rideRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $rideOutput 'stdout.txt') -RedirectStandardError (Join-Path $rideOutput 'stderr.txt')
    $rideWatch=[Diagnostics.Stopwatch]::StartNew()
    while(-not $rideProcess.WaitForExit(1000)){
        if($rideWatch.Elapsed.TotalSeconds -gt 180){Stop-Process -Id $rideProcess.Id -Force;throw 'First-person check timed out'}
    }
    Get-Content (Join-Path $rideOutput 'stdout.txt')
    Get-Content (Join-Path $rideOutput 'stderr.txt')
    if($rideProcess.ExitCode -ne 0){throw ('First-person check failed: '+$rideProcess.ExitCode)}
} finally {
    foreach($key in $rideEnv.Keys){[Environment]::SetEnvironmentVariable($key,$ridePrevious[$key],'Process')}
}
