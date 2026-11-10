param([Parameter(Mandatory=$true)][string]$GameExecutable)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$game=(Resolve-Path -LiteralPath $GameExecutable).Path
$identity='the-picture-shop-test-route-cache'
# Exercise a real packaged DLL at a save path where the previous 64-character
# cache filename exceeded MAX_PATH. The complete digest must still be checked.
$cacheDirectoryLength=170
$appDataLength=$cacheDirectoryLength-('/'+$identity+'/native-cache').Length
$run=Join-Path $root ('output/route-cache-'+[guid]::NewGuid().ToString('N'))
if($run.Length -gt $appDataLength){throw 'Workspace path is too long for this controlled cache-path regression.'}
$run=$run+('x'*($appDataLength-$run.Length))
if(Test-Path -LiteralPath $run){throw 'Test folder unexpectedly exists.'}
New-Item -ItemType Directory -Path $run | Out-Null
$report=Join-Path $run 'checks.rpt'
$environment=@{APPDATA=$run;PICTURE_SHOP_SMOKE='1';PICTURE_SHOP_SMOKE_FOCUS='direct-multiplayer';
    PICTURE_SHOP_MOBILE='0';PICTURE_SHOP_TEST_IDENTITY=$identity;PICTURE_SHOP_SMOKE_REPORT=$report}
$previous=@{};$process=$null
try {
    foreach($key in $environment.Keys){
        $previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process')
        [Environment]::SetEnvironmentVariable($key,$environment[$key],'Process')
    }
    $process=Start-Process -FilePath $game -WorkingDirectory (Split-Path $game) -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $run 'stdout.log') -RedirectStandardError (Join-Path $run 'stderr.log')
    $null=$process.Handle
    if(-not $process.WaitForExit(180000)){throw 'Packaged networking regression timed out.'}
    if($process.ExitCode -ne 0){throw "Packaged networking regression failed: $($process.ExitCode)"}
    $lines=@(Get-Content -LiteralPath $report)
    if($lines -notcontains 'SMOKE_OK' -or $lines -match '^FAIL' -or
        $lines -notcontains 'PASS gateway_release_provider_is_embedded_hashed_and_abi_compatible'){
        throw 'Packaged provider verification did not complete.'
    }
    $cache=Join-Path $run ($identity+'/native-cache')
    if($cache.Length -ne $cacheDirectoryLength){throw 'Unexpected fused save-directory layout.'}
    $dlls=@(Get-ChildItem -LiteralPath $cache -File -Filter 'tps_route_*.dll')
    if($dlls.Count -lt 1 -or @($dlls | Where-Object {$_.FullName.Length -ge 260}).Count){
        throw 'Native DLL cache paths exceeded the intended bound.'
    }
    Write-Output "WINDOWS_ROUTE_CACHE_PASS checks=$(@($lines -match '^PASS ').Count) cacheDirectoryLength=$cacheDirectoryLength"
    Write-Output "REPORT=$report"
} finally {
    if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force}
    foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')}
}
