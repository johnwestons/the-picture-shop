param(
    [string]$WindowsReport = (Join-Path $PSScriptRoot '..\output\windows\windows-build-report.json'),
    [string]$AndroidReport = (Join-Path $PSScriptRoot '..\output\mobile\apk-report.json'),
    [string]$MobileBuildReport = (Join-Path $PSScriptRoot '..\output\mobile\build-report.json'),
    [string]$PhysicalAcceptanceReport = (Join-Path $PSScriptRoot '..\output\mobile\device-tests\guest-worker-physical-acceptance.json')
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testerRoot = Join-Path $projectRoot 'output\tester-release'
$windows = Get-Content -Raw -LiteralPath $WindowsReport | ConvertFrom-Json
$android = Get-Content -Raw -LiteralPath $AndroidReport | ConvertFrom-Json
$mobileBuild = Get-Content -Raw -LiteralPath $MobileBuildReport | ConvertFrom-Json

function Find-Python {
    $candidates = @(
        (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
    )
    foreach ($name in @('python.exe', 'python', 'py.exe', 'py')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { $candidates += $command.Source }
    }
    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        & $candidate -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>$null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    throw 'Python 3.10+ was not found for physical-acceptance verification.'
}

if ($windows.version -notmatch '^(\d+\.\d+\.\d+)-test\.(\d+)$') {
    throw 'Windows build report has an invalid tester version.'
}
$releaseVersion = [string]$windows.version
$androidExpected = "$($Matches[1])-android.$($Matches[2])"
if ([string]$android.versionName -ne $androidExpected) {
    throw "Android $($android.versionName) does not match Windows $releaseVersion."
}
if (-not $windows.installer -or -not (Test-Path -LiteralPath $windows.installer)) {
    throw 'Windows installer is missing.'
}
if (-not $android.apk -or -not (Test-Path -LiteralPath $android.apk)) {
    throw 'Android APK is missing.'
}
$windowsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $windows.installer).Hash.ToLowerInvariant()
$androidHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $android.apk).Hash.ToLowerInvariant()
if ($windowsHash -ne [string]$windows.installerSha256) {
    throw 'Windows installer does not match its build report.'
}
if ($androidHash -ne [string]$android.sha256) {
    throw 'Android APK does not match its build report.'
}
if ([bool]$windows.sourceDirty -or [bool]$mobileBuild.sourceDirty -or
        [string]$windows.sourceCommit -cne [string]$mobileBuild.sourceCommit) {
    throw 'Windows and Android tester artifacts must come from the same clean source commit.'
}

$python = Find-Python
& $python (Join-Path $projectRoot 'tools\verify_guest_worker_physical_acceptance.py') `
    --report $PhysicalAcceptanceReport `
    --apk-report $AndroidReport `
    --build-report $MobileBuildReport
if ($LASTEXITCODE -ne 0) {
    throw 'Three-phone Guest Worker physical acceptance is missing, incomplete, or for another APK.'
}

$releaseRoot = Join-Path $testerRoot $releaseVersion
$resolvedTester = [IO.Path]::GetFullPath($testerRoot)
$resolvedRelease = [IO.Path]::GetFullPath($releaseRoot)
if ([IO.Path]::GetDirectoryName($resolvedRelease) -ne $resolvedTester) {
    throw "Refusing unexpected tester release directory: $resolvedRelease"
}
if (Test-Path -LiteralPath $resolvedRelease) {
    Remove-Item -LiteralPath $resolvedRelease -Recurse -Force
}
$windowsRoot = Join-Path $resolvedRelease 'Windows'
$androidRoot = Join-Path $resolvedRelease 'Android'
New-Item -ItemType Directory -Path $windowsRoot, $androidRoot -Force | Out-Null

$windowsName = "ThePictureShop-Windows-Setup-$releaseVersion.exe"
$androidName = "ThePictureShop-Android-$releaseVersion.apk"
$windowsDestination = Join-Path $windowsRoot $windowsName
$androidDestination = Join-Path $androidRoot $androidName
Copy-Item -LiteralPath $windows.installer -Destination $windowsDestination
Copy-Item -LiteralPath $android.apk -Destination $androidDestination
Copy-Item -LiteralPath (Join-Path $projectRoot 'packaging\README-TESTERS.txt') `
    -Destination $resolvedRelease
Copy-Item -LiteralPath (Join-Path $projectRoot 'packaging\windows\README-TESTERS.txt') `
    -Destination (Join-Path $windowsRoot 'README-TESTERS-WINDOWS.txt')
Copy-Item -LiteralPath (Join-Path $projectRoot 'packaging\android\README-TESTERS.txt') `
    -Destination (Join-Path $androidRoot 'README-TESTERS-ANDROID.txt')

$checksums = @(
    "$windowsHash  Windows/$windowsName",
    "$androidHash  Android/$androidName"
)
[IO.File]::WriteAllText(
    (Join-Path $resolvedRelease 'SHA256SUMS.txt'),
    (($checksums -join "`n") + "`n"),
    [Text.UTF8Encoding]::new($false)
)
$manifest = [ordered]@{
    schemaVersion = 1
    release = $releaseVersion
    sourceCommit = [string]$windows.sourceCommit
    sourceDirty = [bool]$windows.sourceDirty
    windows = [ordered]@{
        file = "Windows/$windowsName"
        bytes = (Get-Item -LiteralPath $windowsDestination).Length
        sha256 = $windowsHash
        signed = [bool]$windows.signed
    }
    android = [ordered]@{
        file = "Android/$androidName"
        bytes = (Get-Item -LiteralPath $androidDestination).Length
        sha256 = $androidHash
        signed = [bool]$android.signed
        versionName = [string]$android.versionName
        versionCode = [int]$android.versionCode
    }
}
[IO.File]::WriteAllText(
    (Join-Path $resolvedRelease 'tester-release-manifest.json'),
    (($manifest | ConvertTo-Json -Depth 6) + "`n"),
    [Text.UTF8Encoding]::new($false)
)
Write-Output "TESTER_RELEASE=$resolvedRelease"
Write-Output "WINDOWS_DOWNLOAD=$windowsDestination"
Write-Output "ANDROID_DOWNLOAD=$androidDestination"
Write-Output "CHECKSUMS=$(Join-Path $resolvedRelease 'SHA256SUMS.txt')"
