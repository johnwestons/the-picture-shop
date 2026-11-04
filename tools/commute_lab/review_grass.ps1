param([switch]$UnitOnly)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reviewOutput=Join-Path $projectRoot 'output\grass-review'
New-Item -ItemType Directory -Force -Path $reviewOutput | Out-Null
$reviewEnv=@{PICTURE_SHOP_SMOKE='1';PICTURE_SHOP_COMMUTE_LAB='1';PICTURE_SHOP_BIKE_REVIEW='grass';
    PICTURE_SHOP_GRASS_OUTPUT=$reviewOutput;PICTURE_SHOP_GRASS_UNIT_ONLY=$(if($UnitOnly){'1'}else{''});
    PICTURE_SHOP_TEST_IDENTITY='the-picture-shop-test-grass'}
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
    if(-not $p.WaitForExit(55000)){Stop-Process -Id $p.Id -Force;throw 'Grass review exceeded its 55-second bound'}
    Get-Content (Join-Path $reviewOutput 'native-stdout.txt') | Select-Object -Last 16
    Get-Content (Join-Path $reviewOutput 'native-stderr.txt')
    if($p.ExitCode -ne 0){throw ('Grass review failed: '+$p.ExitCode)}
} finally {
    foreach($key in $reviewEnv.Keys){[Environment]::SetEnvironmentVariable($key,$previousEnv[$key],'Process')}
}
