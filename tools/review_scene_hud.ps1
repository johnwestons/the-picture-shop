param([switch]$Mobile)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mode=if($Mobile){'mobile'}else{'desktop'}
$reviewOutput=Join-Path $projectRoot ('output\scene-hud-review\'+$mode)
New-Item -ItemType Directory -Force -Path $reviewOutput | Out-Null
$reviewEnv=@{PICTURE_SHOP_SMOKE='1';PICTURE_SHOP_SMOKE_FOCUS='scene-hud';
    PICTURE_SHOP_HUD_OUTPUT=$reviewOutput;PICTURE_SHOP_MOBILE=$(if($Mobile){'1'}else{''});
    PICTURE_SHOP_SMOKE_REPORT=(Join-Path $reviewOutput 'smoke.rpt');
    PICTURE_SHOP_TEST_IDENTITY=('the-picture-shop-test-hud-'+$mode+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
$previousEnv=@{}
try {
    foreach($key in $reviewEnv.Keys){
        $previousEnv[$key]=[Environment]::GetEnvironmentVariable($key,'Process')
        [Environment]::SetEnvironmentVariable($key,$reviewEnv[$key],'Process')
    }
    $p=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$projectRoot+'"') `
        -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $reviewOutput 'stdout.txt') -RedirectStandardError (Join-Path $reviewOutput 'stderr.txt')
    $null=$p.Handle
    if(-not $p.WaitForExit(60000)){Stop-Process -Id $p.Id -Force;throw 'Scene HUD review timed out'}
    Get-Content (Join-Path $reviewOutput 'stdout.txt') | Select-Object -Last 12
    Get-Content (Join-Path $reviewOutput 'stderr.txt')
    if($p.ExitCode -ne 0){throw ('Scene HUD review failed: '+$p.ExitCode)}
} finally {
    foreach($key in $reviewEnv.Keys){[Environment]::SetEnvironmentVariable($key,$previousEnv[$key],'Process')}
}
