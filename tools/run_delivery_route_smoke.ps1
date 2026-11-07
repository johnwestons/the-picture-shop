param(
    [ValidateRange(1,10)][int]$Runs = 3,
    [ValidateRange(1,1000)][int]$StartIndex = 1,
    [ValidateRange(60,1800)][int]$TimeoutSeconds = 600,
    [ValidateSet('delivery-route-smoke','delivery-traffic','ai-motorcycle-traffic')]
    [string]$Focus = 'delivery-route-smoke',
    [ValidateRange(0,2147483646)][int]$Seed = 0,
    [string]$From = '',
    [string]$To = '',
    [switch]$Trace
)
$ErrorActionPreference = 'Stop'
$smokeRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$smokeOutput = Join-Path $smokeRoot ('output/' + $Focus)
$smokeAppData = Join-Path $smokeOutput 'appdata'
$smokeLoveRoot = Join-Path $smokeAppData 'LOVE'
$smokeIdentity = 'the-picture-shop-test-' + $Focus
$smokeSave = Join-Path $smokeLoveRoot $smokeIdentity
$loveExe = Join-Path $env:ProgramFiles 'LOVE/lovec.exe'
New-Item -ItemType Directory -Force -Path $smokeOutput,$smokeLoveRoot | Out-Null

$fullLoveRoot = [IO.Path]::GetFullPath($smokeLoveRoot).TrimEnd('\') + '\'
$fullSmokeSave = [IO.Path]::GetFullPath($smokeSave)
if (-not $fullSmokeSave.StartsWith($fullLoveRoot,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Delivery route smoke save path escaped its isolated game-save sandbox.'
}
if (-not (Test-Path -LiteralPath $loveExe)) { throw "LÖVE was not found at $loveExe" }

$smokeEnvironment = @{
    APPDATA = $smokeAppData
    PICTURE_SHOP_SMOKE = '1'
    PICTURE_SHOP_TEST_IDENTITY = $smokeIdentity
    PICTURE_SHOP_SMOKE_FOCUS = $Focus
}
if ($Seed -gt 0) { $smokeEnvironment['PICTURE_SHOP_DELIVERY_ROUTE_SEED'] = [string]$Seed }
if ($From) { $smokeEnvironment['PICTURE_SHOP_DELIVERY_ROUTE_FROM'] = $From }
if ($To) { $smokeEnvironment['PICTURE_SHOP_DELIVERY_ROUTE_TO'] = $To }
if ($Trace) {
    $smokeEnvironment['PICTURE_SHOP_DELIVERY_ROUTE_TRACE'] = '1'
    $smokeEnvironment['PICTURE_SHOP_DELIVERY_ROUTE_GENERATION_TRACE'] = '1'
}
$previousEnvironment = @{}
$previousEnvironment['PICTURE_SHOP_SMOKE_REPORT'] = [Environment]::GetEnvironmentVariable('PICTURE_SHOP_SMOKE_REPORT','Process')
$process = $null
try {
    foreach ($key in $smokeEnvironment.Keys) {
        $previousEnvironment[$key] = [Environment]::GetEnvironmentVariable($key,'Process')
        [Environment]::SetEnvironmentVariable($key,$smokeEnvironment[$key],'Process')
    }
    for ($run = 1; $run -le $Runs; $run++) {
        # These are disposable route-smoke saves under this task's sandbox.
        if (Test-Path -LiteralPath $fullSmokeSave) {
            Remove-Item -LiteralPath $fullSmokeSave -Recurse -Force
        }
        $runNumber = $StartIndex + $run - 1
        $tag = 'run-{0:D2}' -f $runNumber
        $report = Join-Path $smokeOutput ($tag + '.rpt')
        $stdout = Join-Path $smokeOutput ($tag + '.stdout.txt')
        $stderr = Join-Path $smokeOutput ($tag + '.stderr.txt')
        Remove-Item -LiteralPath $report,$stdout,$stderr -Force -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable('PICTURE_SHOP_SMOKE_REPORT',$report,'Process')
        # Force the process handle to exist before waiting so ExitCode is
        # available consistently when the application has already exited.
        $process = Start-Process -FilePath $loveExe -ArgumentList ('"' + $smokeRoot + '"') `
            -WorkingDirectory $smokeRoot -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $null = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -Force
            throw "Delivery route smoke $tag timed out after $TimeoutSeconds seconds."
        }
        $process.Refresh()
        if (Test-Path -LiteralPath $stderr) {
            $errorText = Get-Content -LiteralPath $stderr -Raw
            if ($errorText -and $errorText.Trim()) { Write-Output $errorText.TrimEnd() }
        }
        $exitCode = $process.ExitCode
        if ($null -eq $exitCode) {
            throw "Delivery route smoke $tag exited without a process exit code."
        }
        if ($exitCode -ne 0) {
            if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Tail 30 }
            throw "Delivery route smoke $tag failed with exit code $exitCode."
        }
        $reportOkay = Test-Path -LiteralPath $report
        if ($reportOkay) { $reportOkay = Select-String -LiteralPath $report -SimpleMatch 'SMOKE_OK' -Quiet }
        if (-not $reportOkay) {
            throw "Delivery route smoke $tag exited without a successful smoke report."
        }
        $passLine = Select-String -LiteralPath $report -Pattern '^PASS delivery_route_smoke_' | Select-Object -First 1
        Write-Output ("{0} passed: {1}" -f $tag,$passLine.Line)
        $resultLines = Select-String -LiteralPath $stdout -Pattern '^DELIVERY_ROUTE_(SMOKE_RESULT|MAP_SNAPSHOT) '
        foreach ($resultLine in $resultLines) { Write-Output $resultLine.Line }
        $process = $null
    }
    Write-Output "All $Runs delivery route smoke runs passed."
} finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    foreach ($key in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($key,$previousEnvironment[$key],'Process')
    }
}
