$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reviewOutput=Join-Path $projectRoot 'output\bike-motion-fx-review'
New-Item -ItemType Directory -Force -Path $reviewOutput | Out-Null
$reviewEnv=@{PICTURE_SHOP_SMOKE='1';PICTURE_SHOP_COMMUTE_LAB='1';PICTURE_SHOP_BIKE_REVIEW='motionfx';
    PICTURE_SHOP_BIKE_FX_OUTPUT=$reviewOutput;PICTURE_SHOP_TEST_IDENTITY='the-picture-shop-test-bike-motion-fx'}
$previousEnv=@{}
try {
    foreach($key in $reviewEnv.Keys){
        $previousEnv[$key]=[Environment]::GetEnvironmentVariable($key,'Process')
        [Environment]::SetEnvironmentVariable($key,$reviewEnv[$key],'Process')
    }
    $p=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$projectRoot+'"') `
        -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $reviewOutput 'native-stdout.txt') `
        -RedirectStandardError (Join-Path $reviewOutput 'native-stderr.txt')
    $null=$p.Handle
    if(-not $p.WaitForExit(180000)){Stop-Process -Id $p.Id -Force;throw 'Bike motion review timed out'}
    Get-Content (Join-Path $reviewOutput 'native-stdout.txt') | Select-Object -Last 24
    Get-Content (Join-Path $reviewOutput 'native-stderr.txt')
    if($p.ExitCode -ne 0){throw ('Bike motion review failed: '+$p.ExitCode)}
} finally {
    foreach($key in $reviewEnv.Keys){[Environment]::SetEnvironmentVariable($key,$previousEnv[$key],'Process')}
}
