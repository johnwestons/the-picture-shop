param([int]$TimeoutSeconds = 45)
$ErrorActionPreference = 'Stop'
$visitorProject = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$visitorOutput = Join-Path $visitorProject 'output/visitor-motion-review/engine'
New-Item -ItemType Directory -Path $visitorOutput -Force | Out-Null
$visitorLove = @(
    (Join-Path $visitorProject 'runtime/lovec.exe'),
    (Join-Path $env:ProgramFiles 'LOVE/lovec.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $visitorLove) { throw 'LÖVE 11.5 console runtime was not found.' }
$visitorPrevious = @{}
$visitorEnvironment = @{
    PICTURE_SHOP_SMOKE = '1'
    PICTURE_SHOP_TEST_IDENTITY = 'the-picture-shop-test-visitors-' + [Guid]::NewGuid().ToString('N')
    PICTURE_SHOP_VISITOR_PREVIEW = '1'
    PICTURE_SHOP_PREVIEW_ROOT = $visitorProject
    PICTURE_SHOP_PREVIEW_OUTPUT = $visitorOutput
}
$visitorProcess = $null
try {
    foreach ($visitorKey in $visitorEnvironment.Keys) {
        $visitorPrevious[$visitorKey] = [Environment]::GetEnvironmentVariable($visitorKey, 'Process')
        [Environment]::SetEnvironmentVariable($visitorKey, $visitorEnvironment[$visitorKey], 'Process')
    }
    $visitorProcess = Start-Process -FilePath $visitorLove `
        -ArgumentList ('"' + $visitorProject + '"') -WorkingDirectory $visitorProject `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $visitorOutput 'stdout.log') `
        -RedirectStandardError (Join-Path $visitorOutput 'stderr.log')
    $visitorDeadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not $visitorProcess.HasExited -and [DateTime]::UtcNow -lt $visitorDeadline) {
        Start-Sleep -Milliseconds 100
        $visitorProcess.Refresh()
    }
    if (-not $visitorProcess.HasExited) { throw "Visitor preview exceeded $TimeoutSeconds seconds." }
    $visitorProcess.WaitForExit()
    if ($visitorProcess.ExitCode -ne 0) {
        Get-Content -LiteralPath (Join-Path $visitorOutput 'stdout.log') -Tail 20
        throw "Visitor preview failed with exit code $($visitorProcess.ExitCode)."
    }
    Get-Content -LiteralPath (Join-Path $visitorOutput 'engine-review.txt')
} finally {
    if ($visitorProcess -and -not $visitorProcess.HasExited) { Stop-Process -Id $visitorProcess.Id -Force }
    foreach ($visitorKey in $visitorPrevious.Keys) {
        [Environment]::SetEnvironmentVariable($visitorKey, $visitorPrevious[$visitorKey], 'Process')
    }
}
