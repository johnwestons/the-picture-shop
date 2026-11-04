param([switch]$Mobile,[switch]$Runtime,[switch]$Full)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reviewOutput=Join-Path $projectRoot 'output\bike-turning-quality-review'
New-Item -ItemType Directory -Force -Path $reviewOutput | Out-Null
$mode=if($Full){'full'}elseif($Runtime -and $Mobile){'runtime-mobile'}elseif($Runtime){'runtime-desktop'}elseif($Mobile){'mobile'}else{'desktop'}
$captureOutput=Join-Path $reviewOutput $mode
New-Item -ItemType Directory -Force -Path $captureOutput | Out-Null
$reviewEnv=@{
    PICTURE_SHOP_SMOKE='1';PICTURE_SHOP_COMMUTE_LAB=$(if($Runtime){''}else{'1'})
    PICTURE_SHOP_BIKE_REVIEW=$(if($Runtime){''}else{'turning'})
    PICTURE_SHOP_TEST_IDENTITY=('the-picture-shop-test-turning-'+$mode+'-'+[guid]::NewGuid().ToString('N').Substring(0,10))
    PICTURE_SHOP_SMOKE_FOCUS=$(if($Full){''}else{'motorcycle-camera'});PICTURE_SHOP_MOBILE=$(if($Mobile){'1'}else{''})
    PICTURE_SHOP_SMOKE_REPORT=(Join-Path $reviewOutput ($mode+'-smoke.rpt'))
    PICTURE_SHOP_COMMUTE_CAPTURE=$captureOutput;PICTURE_SHOP_BIKE_TURNING_OUTPUT=$reviewOutput
}
$previousEnv=@{}
try {
    foreach($key in $reviewEnv.Keys){
        $previousEnv[$key]=[Environment]::GetEnvironmentVariable($key,'Process')
        [Environment]::SetEnvironmentVariable($key,$reviewEnv[$key],'Process')
    }
    $p=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$projectRoot+'"') `
        -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $reviewOutput ($mode+'-stdout.txt')) `
        -RedirectStandardError (Join-Path $reviewOutput ($mode+'-stderr.txt'))
    $null=$p.Handle
    if(-not $p.WaitForExit(60000)){Stop-Process -Id $p.Id -Force;throw 'Bike turning review timed out'}
    Get-Content (Join-Path $reviewOutput ($mode+'-stdout.txt')) | Select-Object -Last 12
    Get-Content (Join-Path $reviewOutput ($mode+'-stderr.txt'))
    if($p.ExitCode -ne 0){throw ('Bike turning review failed: '+$p.ExitCode)}
} finally {
    foreach($key in $reviewEnv.Keys){[Environment]::SetEnvironmentVariable($key,$previousEnv[$key],'Process')}
}
