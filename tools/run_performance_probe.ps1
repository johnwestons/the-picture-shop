param([string]$Label = 'review', [int]$TimeoutSeconds = 60)
$ErrorActionPreference = 'Stop'
if ($Label -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Use a simple label for the report directory.' }
$perfRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$perfOutput = Join-Path $perfRoot ('output/performance/' + $Label)
New-Item -ItemType Directory -Force -Path $perfOutput | Out-Null
$perfEnvironment = @{
    APPDATA = (Join-Path $perfOutput 'appdata')
    PICTURE_SHOP_SMOKE = '1'
    PICTURE_SHOP_TEST_IDENTITY = 'the-picture-shop-test-perf-' + [guid]::NewGuid().ToString('N')
    PICTURE_SHOP_PERFORMANCE_PROBE = '1'
    PICTURE_SHOP_PERFORMANCE_OUTPUT = $perfOutput
}
$perfPrevious = @{}
$perfProcess = $null
try {
    foreach ($key in $perfEnvironment.Keys) {
        $perfPrevious[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $perfEnvironment[$key], 'Process')
    }
    $perfProcess = Start-Process -FilePath (Join-Path $env:ProgramFiles 'LOVE/lovec.exe') `
        -ArgumentList ('"' + $perfRoot + '"') -WorkingDirectory $perfRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $perfOutput 'stdout.log') `
        -RedirectStandardError (Join-Path $perfOutput 'stderr.log')
    if (-not $perfProcess.WaitForExit($TimeoutSeconds * 1000)) { throw 'Performance probe timed out.' }
    Get-Content (Join-Path $perfOutput 'stdout.log')
    if ($perfProcess.ExitCode -ne 0) {
        Get-Content (Join-Path $perfOutput 'stderr.log')
        throw 'Performance probe failed.'
    }
} finally {
    if ($perfProcess -and -not $perfProcess.HasExited) { Stop-Process -Id $perfProcess.Id -Force }
    foreach ($key in $perfPrevious.Keys) {
        [Environment]::SetEnvironmentVariable($key, $perfPrevious[$key], 'Process')
    }
}
