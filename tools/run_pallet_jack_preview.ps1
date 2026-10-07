param([int]$TimeoutSeconds = 50)
$ErrorActionPreference = 'Stop'
$jackRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$jackOutput = Join-Path $jackRoot 'output/pallet-jack-motion-v2/engine'
New-Item -ItemType Directory -Force -Path $jackOutput | Out-Null
$jackEnvironment = @{
    PICTURE_SHOP_SMOKE = '1'
    PICTURE_SHOP_TEST_IDENTITY = 'the-picture-shop-test-jack-' + [guid]::NewGuid().ToString('N')
    PICTURE_SHOP_PALLET_JACK_PREVIEW = '1'
    PICTURE_SHOP_PREVIEW_OUTPUT = $jackOutput
}
$jackPrevious = @{}
$jackProcess = $null
try {
    foreach ($key in $jackEnvironment.Keys) {
        $jackPrevious[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $jackEnvironment[$key], 'Process')
    }
    $jackProcess = Start-Process -FilePath (Join-Path $env:ProgramFiles 'LOVE/lovec.exe') `
        -ArgumentList ('"' + $jackRoot + '"') -WorkingDirectory $jackRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $jackOutput 'stdout.log') `
        -RedirectStandardError (Join-Path $jackOutput 'stderr.log')
    if (-not $jackProcess.WaitForExit($TimeoutSeconds * 1000)) { throw 'Pallet jack preview timed out.' }
    if ($jackProcess.ExitCode -ne 0) {
        Get-Content (Join-Path $jackOutput 'stdout.log') -Tail 20
        throw 'Pallet jack preview failed.'
    }
    Get-Content (Join-Path $jackOutput 'engine-review.txt') -TotalCount 1
} finally {
    if ($jackProcess -and -not $jackProcess.HasExited) { Stop-Process -Id $jackProcess.Id -Force }
    foreach ($key in $jackPrevious.Keys) {
        [Environment]::SetEnvironmentVariable($key, $jackPrevious[$key], 'Process')
    }
}
