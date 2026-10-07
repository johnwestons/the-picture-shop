param([int]$TimeoutSeconds = 50, [switch]$FullSuite)
$ErrorActionPreference = 'Stop'
$auditRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$auditOutput = Join-Path $auditRoot 'output/pallet-jack-audit'
if ($FullSuite) { $auditOutput = Join-Path $auditOutput 'full' }
$auditAppData = Join-Path $auditOutput 'appdata'
New-Item -ItemType Directory -Force -Path $auditOutput, $auditAppData | Out-Null
$auditEnvironment = @{
    APPDATA = $auditAppData
    PICTURE_SHOP_SMOKE = '1'
    PICTURE_SHOP_TEST_IDENTITY = 'the-picture-shop-test-jack-audit-' + [guid]::NewGuid().ToString('N')
    PICTURE_SHOP_SMOKE_FOCUS = $(if ($FullSuite) { 'all' } else { 'pallet-jack' })
    PICTURE_SHOP_SMOKE_REPORT = Join-Path $auditOutput 'smoke-report.rpt'
}
$auditPrevious = @{}
$auditProcess = $null
try {
    foreach ($key in $auditEnvironment.Keys) {
        $auditPrevious[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $auditEnvironment[$key], 'Process')
    }
    $auditProcess = Start-Process -FilePath (Join-Path $env:ProgramFiles 'LOVE/lovec.exe') `
        -ArgumentList ('"' + $auditRoot + '"') -WorkingDirectory $auditRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $auditOutput 'stdout.log') `
        -RedirectStandardError (Join-Path $auditOutput 'stderr.log')
    if (-not $auditProcess.WaitForExit($TimeoutSeconds * 1000)) { throw 'Pallet jack audit timed out.' }
    if ($auditProcess.ExitCode -ne 0) {
        Get-Content (Join-Path $auditOutput 'smoke-report.rpt') -Tail 24
        throw 'Pallet jack audit failed.'
    }
    Get-Content (Join-Path $auditOutput 'smoke-report.rpt') -Tail 3
} finally {
    if ($auditProcess -and -not $auditProcess.HasExited) { Stop-Process -Id $auditProcess.Id -Force }
    foreach ($key in $auditPrevious.Keys) {
        [Environment]::SetEnvironmentVariable($key, $auditPrevious[$key], 'Process')
    }
}
