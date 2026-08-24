param(
    [int]$TimeoutSeconds = 90,
    [string]$ReportPath = (Join-Path $PSScriptRoot 'smoke-report.rpt'),
    [switch]$Visible
)

$ErrorActionPreference = 'Stop'
$workspacePath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$resolvedReportPath = [System.IO.Path]::GetFullPath($ReportPath)
$stdoutPath = Join-Path $PSScriptRoot 'smoke-watchdog-out.txt'
$stderrPath = Join-Path $PSScriptRoot 'smoke-watchdog-err.txt'
$statusPath = Join-Path $PSScriptRoot 'smoke-watchdog-status.txt'
$windowStyle = if ($Visible) { 'Normal' } else { 'Hidden' }
$testProcess = $null

function Find-LoveConsole {
    $candidates = @(
        (Join-Path $workspacePath 'runtime\lovec.exe'),
        (Join-Path $workspacePath 'runtime\love.exe'),
        (Join-Path $env:ProgramFiles 'LOVE\lovec.exe'),
        (Join-Path $env:ProgramFiles 'LOVE\love.exe')
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'LOVE\lovec.exe')
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'LOVE\love.exe')
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    foreach ($commandName in @('lovec.exe', 'love.exe', 'love')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    return $null
}

$lovePath = Find-LoveConsole
if (-not $lovePath) {
    Write-Error 'LÖVE 11.x was not found. Install it from https://love2d.org/ before running the smoke test.'
    exit 127
}

$previousSmoke = $env:PICTURE_SHOP_SMOKE
$previousReport = $env:PICTURE_SHOP_SMOKE_REPORT
Remove-Item -LiteralPath $stdoutPath, $stderrPath, $statusPath, $resolvedReportPath -Force -ErrorAction SilentlyContinue

try {
    $env:PICTURE_SHOP_SMOKE = '1'
    $env:PICTURE_SHOP_SMOKE_REPORT = $resolvedReportPath
    $testProcess = Start-Process -FilePath $lovePath `
        -ArgumentList ('"' + $workspacePath + '"') `
        -WorkingDirectory $workspacePath `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle $windowStyle `
        -PassThru
    $null = $testProcess.Handle

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not $testProcess.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
        $testProcess.Refresh()
    }

    if (-not $testProcess.HasExited) {
        Stop-Process -Id $testProcess.Id -Force -ErrorAction SilentlyContinue
        Set-Content -LiteralPath $statusPath -Value "TIMEOUT exit=124 seconds=$TimeoutSeconds"
        Write-Error "Smoke test exceeded $TimeoutSeconds seconds."
        exit 124
    }

    $testProcess.WaitForExit()
    $testProcess.Refresh()
    $processExitCode = $testProcess.ExitCode
    if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath }
    if (Test-Path -LiteralPath $stderrPath) {
        $stderrLines = @(Get-Content -LiteralPath $stderrPath)
        if ($stderrLines.Count -gt 0) { $stderrLines | Write-Error -ErrorAction Continue }
    }

    $reportExists = Test-Path -LiteralPath $resolvedReportPath
    $reportBytes = if ($reportExists) { (Get-Item -LiteralPath $resolvedReportPath).Length } else { 0 }
    Set-Content -LiteralPath $statusPath -Value "COMPLETE exit=$processExitCode report=$reportExists bytes=$reportBytes"
    if ($processExitCode -eq 0 -and $reportBytes -eq 0) {
        Write-Error "Smoke test exited successfully without a report: $resolvedReportPath"
        exit 2
    }
    exit $processExitCode
}
finally {
    if ($testProcess -and -not $testProcess.HasExited) {
        Stop-Process -Id $testProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($null -eq $previousSmoke) {
        Remove-Item Env:PICTURE_SHOP_SMOKE -ErrorAction SilentlyContinue
    } else {
        $env:PICTURE_SHOP_SMOKE = $previousSmoke
    }
    if ($null -eq $previousReport) {
        Remove-Item Env:PICTURE_SHOP_SMOKE_REPORT -ErrorAction SilentlyContinue
    } else {
        $env:PICTURE_SHOP_SMOKE_REPORT = $previousReport
    }
}
