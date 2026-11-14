#Requires -Version 7.0
param(
    [switch]$PackageOnly,
    [switch]$Install,
    [switch]$ReuseVerifiedNativeCryptoArtifacts,
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
    $previousFocus = $env:PICTURE_SHOP_SMOKE_FOCUS
    $previousIdentity = $env:PICTURE_SHOP_TEST_IDENTITY
    $previousAppData = $env:APPDATA
    $previousCrypto = $env:TPS_CRYPTO_LIBRARY
    $packageSmokeRoot = $null
    $storySmokeRoot = $null
    try {
        # The Android package contains ARM libraries. Its desktop smoke run
        # needs the Windows provider to create multiplayer resident identities.
        if (-not $previousCrypto) {
            $provider = Join-Path $projectRoot 'output/native-crypto/build/windows-x64/tps_crypto.dll'
            if (-not (Test-Path -LiteralPath $provider -PathType Leaf)) {
                & (Join-Path $projectRoot 'tools/build_native_crypto.ps1')
            }
            $env:TPS_CRYPTO_LIBRARY = (Resolve-Path -LiteralPath $provider).Path
        }
        $env:PICTURE_SHOP_SMOKE = '1'
        $env:PICTURE_SHOP_MOBILE = '1'
        $env:PICTURE_SHOP_SMOKE_FOCUS = $null
        $env:PICTURE_SHOP_TEST_IDENTITY = 'the-picture-shop-test-mobile-package'
        $packageSmokeRoot = Join-Path $projectRoot ('output\mobile\package-smoke-' + [guid]::NewGuid().ToString('N'))
        $env:APPDATA = Join-Path $packageSmokeRoot 'appdata'
        New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
        $env:PICTURE_SHOP_SMOKE_REPORT = (Join-Path $projectRoot '.stabilization\mobile-package-smoke.rpt')
        & $loveExecutable $report.package
        if ($LASTEXITCODE -ne 0) { throw "Packaged mobile smoke test failed with exit code $LASTEXITCODE" }

        # The generic boot smoke does not enter story mode. Render the story
        # opening from the exact packaged archive so cutscene art omissions
        # fail before an Android APK is produced.
        $storySmokeRoot = Join-Path $projectRoot ('output\mobile\story-smoke-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $storySmokeRoot | Out-Null
        $env:APPDATA = Join-Path $storySmokeRoot 'appdata'
        New-Item -ItemType Directory -Path $env:APPDATA | Out-Null
        $env:PICTURE_SHOP_TEST_IDENTITY = 'the-picture-shop-test-mobile-story'
        $env:PICTURE_SHOP_SMOKE_FOCUS = 'story-intro'
        $env:PICTURE_SHOP_SMOKE_REPORT = Join-Path $projectRoot '.stabilization\mobile-story-package-smoke.rpt'
        & $loveExecutable $report.package
        if ($LASTEXITCODE -ne 0) { throw "Packaged story-opening smoke test failed with exit code $LASTEXITCODE" }
        $storySmokeReport = Get-Content -LiteralPath $env:PICTURE_SHOP_SMOKE_REPORT
        if ($storySmokeReport -notcontains 'PASS story_opening_packing_scene_renders' -or
                $storySmokeReport -notcontains 'PASS story_opening_travel_montage_renders') {
            throw 'Packaged story-opening smoke test did not render both story scenes.'
        }
    }
    finally {
        $env:PICTURE_SHOP_SMOKE = $previousSmoke
        $env:PICTURE_SHOP_MOBILE = $previousMobile
        $env:PICTURE_SHOP_SMOKE_REPORT = $previousReport
        $env:PICTURE_SHOP_SMOKE_FOCUS = $previousFocus
        $env:PICTURE_SHOP_TEST_IDENTITY = $previousIdentity
        $env:APPDATA = $previousAppData
        $env:TPS_CRYPTO_LIBRARY = $previousCrypto
        if ($storySmokeRoot -and (Test-Path -LiteralPath $storySmokeRoot)) {
            $resolvedSmokeRoot = (Resolve-Path -LiteralPath $storySmokeRoot).Path
            $resolvedMobileRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'output\mobile')).TrimEnd('\', '/')
            if (-not $resolvedSmokeRoot.StartsWith(
                    $resolvedMobileRoot + [System.IO.Path]::DirectorySeparatorChar,
                    [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Refusing to remove story smoke data outside output/mobile.'
            }
            Remove-Item -LiteralPath $resolvedSmokeRoot -Recurse -Force
        }
        if ($packageSmokeRoot -and (Test-Path -LiteralPath $packageSmokeRoot)) {
            $resolvedSmokeRoot = (Resolve-Path -LiteralPath $packageSmokeRoot).Path
            $resolvedMobileRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'output\mobile')).TrimEnd('\', '/')
            if (-not $resolvedSmokeRoot.StartsWith(
                    $resolvedMobileRoot + [System.IO.Path]::DirectorySeparatorChar,
                    [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Refusing to remove package smoke data outside output/mobile.'
            }
            Remove-Item -LiteralPath $resolvedSmokeRoot -Recurse -Force
        }
    }
}

if (-not $PackageOnly) {
    $arguments = @{ PackagePath = $report.package }
    if ($Install) { $arguments.Install = $true }
    if ($ReuseVerifiedNativeCryptoArtifacts) { $arguments.ReuseVerifiedNativeCryptoArtifacts = $true }
    if ($DeviceSerial) { $arguments.DeviceSerial = $DeviceSerial }
    & (Join-Path $projectRoot 'tools\build_android_apk.ps1') @arguments
}
