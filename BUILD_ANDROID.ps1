param(
    [switch]$PackageOnly,
    [switch]$Install,
    [string]$DeviceSerial
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$bundledPython = 'C:\Users\johnw\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$python = if (Test-Path -LiteralPath $bundledPython) { $bundledPython } else { (Get-Command python -ErrorAction Stop).Source }

& $python (Join-Path $projectRoot 'tools\build_mobile_package.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$report = Get-Content -Raw (Join-Path $projectRoot 'output\mobile\build-report.json') | ConvertFrom-Json

$loveExecutable = 'C:\Program Files\LOVE\lovec.exe'
if (Test-Path -LiteralPath $loveExecutable) {
    $previousSmoke = $env:PICTURE_SHOP_SMOKE
    $previousMobile = $env:PICTURE_SHOP_MOBILE
    $previousReport = $env:PICTURE_SHOP_SMOKE_REPORT
    try {
        $env:PICTURE_SHOP_SMOKE = '1'
        $env:PICTURE_SHOP_MOBILE = '1'
        $env:PICTURE_SHOP_SMOKE_REPORT = (Join-Path $projectRoot '.stabilization\mobile-package-smoke.rpt')
        & $loveExecutable $report.package
        if ($LASTEXITCODE -ne 0) { throw "Packaged mobile smoke test failed with exit code $LASTEXITCODE" }
    }
    finally {
        $env:PICTURE_SHOP_SMOKE = $previousSmoke
        $env:PICTURE_SHOP_MOBILE = $previousMobile
        $env:PICTURE_SHOP_SMOKE_REPORT = $previousReport
    }
}

if (-not $PackageOnly) {
    $arguments = @{ PackagePath = $report.package }
    if ($Install) { $arguments.Install = $true }
    if ($DeviceSerial) { $arguments.DeviceSerial = $DeviceSerial }
    & (Join-Path $projectRoot 'tools\build_android_apk.ps1') @arguments
}
