param([switch]$Actions)
$ErrorActionPreference='Stop'
$commuteRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reviewOutput=Join-Path $commuteRoot 'output\commute-bike-v2-review'
New-Item -ItemType Directory -Force -Path $reviewOutput | Out-Null
$reviewEnv=@{
    PICTURE_SHOP_COMMUTE_LAB='1';PICTURE_SHOP_SMOKE='1';PICTURE_SHOP_BIKE_REVIEW=$(if($Actions){'actions'}else{'1'})
    PICTURE_SHOP_BIKE_REVIEW_OUTPUT=(Join-Path $reviewOutput $(if($Actions){'native-action-sequence.png'}else{'native-runtime-directions.png'}))
}
$previousEnv=@{}
try {
    foreach($key in $reviewEnv.Keys){$previousEnv[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$reviewEnv[$key],'Process')}
    $reviewProcess=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$commuteRoot+'"') -WorkingDirectory $commuteRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $reviewOutput 'stdout.txt') -RedirectStandardError (Join-Path $reviewOutput 'stderr.txt')
    if(-not $reviewProcess.WaitForExit(60000)){Stop-Process -Id $reviewProcess.Id -Force;throw 'Native bike review timed out'}
    Get-Content (Join-Path $reviewOutput 'stdout.txt')
    Get-Content (Join-Path $reviewOutput 'stderr.txt')
    if($reviewProcess.ExitCode -ne 0){throw ('Native bike review failed: '+$reviewProcess.ExitCode)}
} finally {
    foreach($key in $reviewEnv.Keys){[Environment]::SetEnvironmentVariable($key,$previousEnv[$key],'Process')}
}
