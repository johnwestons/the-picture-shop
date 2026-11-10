param([switch]$Mobile)
$ErrorActionPreference='Stop'
$browserRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$browserMode=if($Mobile){'mobile'}else{'desktop'}
$browserOutput=Join-Path $browserRoot ('output/critternet-browser/'+$browserMode)
$browserAppData=Join-Path $browserOutput 'appdata'
$browserIdentity='the-picture-shop-test-browser-'+$browserMode
$browserSave=[IO.Path]::GetFullPath((Join-Path $browserAppData ('LOVE/'+$browserIdentity)))
$browserSaveRoot=[IO.Path]::GetFullPath((Join-Path $browserOutput 'appdata/LOVE')).TrimEnd('\')+'\'
if(-not $browserSave.StartsWith($browserSaveRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid browser test save path'}
New-Item -ItemType Directory -Force -Path $browserOutput,$browserAppData | Out-Null
if(Test-Path -LiteralPath $browserSave){Remove-Item -LiteralPath $browserSave -Recurse -Force}
$browserEnv=@{APPDATA=$browserAppData;PICTURE_SHOP_SMOKE='1';PICTURE_SHOP_SMOKE_FOCUS='computer-browser';
    PICTURE_SHOP_TEST_IDENTITY=$browserIdentity;PICTURE_SHOP_BROWSER_CAPTURE=$browserOutput;
    PICTURE_SHOP_MOBILE=$(if($Mobile){'1'}else{''});PICTURE_SHOP_SMOKE_REPORT=(Join-Path $browserOutput 'smoke.rpt')}
$previousEnv=@{};$process=$null
try {
    foreach($key in $browserEnv.Keys){$previousEnv[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$browserEnv[$key],'Process')}
    $process=Start-Process -FilePath (Join-Path $env:ProgramFiles 'LOVE/lovec.exe') -ArgumentList ('"'+$browserRoot+'"') `
        -WorkingDirectory $browserRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $browserOutput 'stdout.txt') -RedirectStandardError (Join-Path $browserOutput 'stderr.txt')
    $null=$process.Handle
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not $process.WaitForExit(1000)){
        if($watch.Elapsed.TotalSeconds -gt 180){Stop-Process -Id $process.Id -Force;throw 'Browser smoke timed out'}
    }
    Get-Content (Join-Path $browserOutput 'smoke.rpt') -Tail 14
    Get-Content (Join-Path $browserOutput 'stderr.txt')
    if($process.ExitCode -ne 0){throw ('Browser smoke failed: '+$process.ExitCode)}
    if(-not (Select-String -LiteralPath (Join-Path $browserOutput 'smoke.rpt') -SimpleMatch 'SMOKE_OK' -Quiet)){throw 'Missing successful report'}
} finally {
    if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force}
    foreach($key in $previousEnv.Keys){[Environment]::SetEnvironmentVariable($key,$previousEnv[$key],'Process')}
}
