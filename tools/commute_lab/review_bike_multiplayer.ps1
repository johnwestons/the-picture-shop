param([switch]$Mobile)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reviewOutput=Join-Path $projectRoot ('output\bike-multiplayer-review\'+$(if($Mobile){'mobile'}else{'desktop'}))
New-Item -ItemType Directory -Force -Path $reviewOutput | Out-Null
$reviewEnv=@{PICTURE_SHOP_SMOKE='1';PICTURE_SHOP_COMMUTE_LAB='1';PICTURE_SHOP_BIKE_REVIEW='multiplayer';
    PICTURE_SHOP_BIKE_MULTIPLAYER_OUTPUT=$reviewOutput;PICTURE_SHOP_MOBILE=$(if($Mobile){'1'}else{''});
    PICTURE_SHOP_TEST_IDENTITY='the-picture-shop-test-bike-multiplayer'}
$previousEnv=@{}
try {
    foreach($key in $reviewEnv.Keys){
        $previousEnv[$key]=[Environment]::GetEnvironmentVariable($key,'Process')
        [Environment]::SetEnvironmentVariable($key,$reviewEnv[$key],'Process')
    }
    $p=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$projectRoot+'"') `
        -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $reviewOutput 'stdout.txt') `
        -RedirectStandardError (Join-Path $reviewOutput 'stderr.txt')
    $null=$p.Handle
    if(-not $p.WaitForExit(60000)){Stop-Process -Id $p.Id -Force;throw 'Bike multiplayer review timed out'}
    Get-Content (Join-Path $reviewOutput 'stdout.txt') | Select-Object -Last 18
    Get-Content (Join-Path $reviewOutput 'stderr.txt')
    if($p.ExitCode -ne 0){throw ('Bike multiplayer review failed: '+$p.ExitCode)}
} finally {
    foreach($key in $reviewEnv.Keys){[Environment]::SetEnvironmentVariable($key,$previousEnv[$key],'Process')}
}
