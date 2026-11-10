param([ValidateSet('desktop','phone','tablet')][string]$Mode='desktop',[string]$Only='',[switch]$Regression)
$ErrorActionPreference='Stop'
$reviewRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$reviewOutput=Join-Path $reviewRoot ('output/ui-readability/'+$Mode)
if($Regression){$reviewOutput=Join-Path $reviewOutput 'regression'}
$reviewAppData=Join-Path $reviewOutput 'appdata'
$reviewIdentity='the-picture-shop-test-ui-'+$Mode
$reviewSave=[IO.Path]::GetFullPath((Join-Path $reviewAppData ('LOVE/'+$reviewIdentity)))
$reviewSaveRoot=[IO.Path]::GetFullPath((Join-Path $reviewOutput 'appdata/LOVE')).TrimEnd('\')+'\'
if(-not $reviewSave.StartsWith($reviewSaveRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid UI review save path'}
New-Item -ItemType Directory -Force -Path $reviewOutput,$reviewAppData | Out-Null
if(Test-Path -LiteralPath $reviewSave){Remove-Item -LiteralPath $reviewSave -Recurse -Force}
$reviewEnv=@{APPDATA=$reviewAppData;PICTURE_SHOP_SMOKE='1';PICTURE_SHOP_SMOKE_FOCUS='ui-readability';
    PICTURE_SHOP_TEST_IDENTITY=$reviewIdentity;PICTURE_SHOP_UI_OUTPUT=$reviewOutput;
    PICTURE_SHOP_UI_MODE=$Mode;PICTURE_SHOP_UI_ONLY=$Only;
    PICTURE_SHOP_MOBILE=$(if($Mode -ne 'desktop'){'1'}else{''});
    PICTURE_SHOP_SMOKE_REPORT=(Join-Path $reviewOutput 'smoke.rpt')}
if($Regression){$reviewEnv.PICTURE_SHOP_SMOKE_FOCUS='ui-regression'}
$previousEnv=@{};$process=$null
try {
    foreach($key in $reviewEnv.Keys){$previousEnv[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$reviewEnv[$key],'Process')}
    $process=Start-Process -FilePath (Join-Path $env:ProgramFiles 'LOVE/lovec.exe') -ArgumentList ('"'+$reviewRoot+'"') `
        -WorkingDirectory $reviewRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $reviewOutput 'stdout.txt') -RedirectStandardError (Join-Path $reviewOutput 'stderr.txt')
    $null=$process.Handle
    if(-not $process.WaitForExit(600000)){Stop-Process -Id $process.Id -Force;throw 'UI review timed out'}
    Get-Content (Join-Path $reviewOutput 'stdout.txt') -Tail 12
    Get-Content (Join-Path $reviewOutput 'stderr.txt')
    if($process.ExitCode -ne 0){throw ('UI review failed: '+$process.ExitCode)}
    if(-not (Select-String -LiteralPath (Join-Path $reviewOutput 'smoke.rpt') -SimpleMatch 'SMOKE_OK' -Quiet)){throw 'Missing successful report'}
} finally {
    if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force}
    foreach($key in $previousEnv.Keys){[Environment]::SetEnvironmentVariable($key,$previousEnv[$key],'Process')}
}
