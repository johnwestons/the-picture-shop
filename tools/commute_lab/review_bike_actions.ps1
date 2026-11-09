param([switch]$UnitOnly,[switch]$Mobile,[switch]$Runtime,[switch]$Full,
    [ValidateSet('motorcycle-camera','motorcycle-effects','commute')][string]$Focus='motorcycle-camera')
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reviewOutput=Join-Path $projectRoot 'output\bike-actions-64-review'
New-Item -ItemType Directory -Force -Path $reviewOutput | Out-Null
$mode=if($UnitOnly){'units'}elseif($Full){'full'}elseif($Runtime -and $Mobile){'runtime-mobile'}elseif($Runtime){'runtime-desktop'}elseif($Mobile){'mobile'}else{'native'}
if($Runtime -and -not $Full -and $Focus -ne 'motorcycle-camera'){$mode='runtime-'+$Focus+$(if($Mobile){'-mobile'}else{''})}
$captureOutput=Join-Path $reviewOutput $mode
New-Item -ItemType Directory -Force -Path $captureOutput | Out-Null
$reviewEnv=@{
    PICTURE_SHOP_SMOKE='1';PICTURE_SHOP_COMMUTE_LAB=$(if($Runtime){''}else{'1'})
    PICTURE_SHOP_BIKE_REVIEW=$(if($Runtime){''}else{'actions64'})
    PICTURE_SHOP_BIKE_ACTION_UNITS=$(if($UnitOnly){'1'}else{''})
    PICTURE_SHOP_TEST_IDENTITY=('the-picture-shop-test-actions-'+$mode+'-'+[guid]::NewGuid().ToString('N').Substring(0,10))
    PICTURE_SHOP_SMOKE_FOCUS=$(if($Full){''}else{$Focus});PICTURE_SHOP_MOBILE=$(if($Mobile){'1'}else{''})
    PICTURE_SHOP_SMOKE_REPORT=(Join-Path $reviewOutput ($mode+'-smoke.rpt'))
    PICTURE_SHOP_COMMUTE_CAPTURE=$captureOutput;PICTURE_SHOP_BIKE_ACTION_OUTPUT=$reviewOutput
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
    if(-not $p.WaitForExit(180000)){Stop-Process -Id $p.Id -Force;throw 'Bike action review timed out'}
    Get-Content (Join-Path $reviewOutput ($mode+'-stdout.txt')) | Select-Object -Last 16
    Get-Content (Join-Path $reviewOutput ($mode+'-stderr.txt'))
    if($p.ExitCode -ne 0){throw ('Bike action review failed: '+$p.ExitCode)}
} finally {
    foreach($key in $reviewEnv.Keys){[Environment]::SetEnvironmentVariable($key,$previousEnv[$key],'Process')}
}
