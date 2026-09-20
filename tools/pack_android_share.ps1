param()

$ErrorActionPreference = 'Stop'
# The existing native builder uses modern .NET APIs and long archive paths.
# A double-click starts Windows PowerShell 5; relaunch in PowerShell 7 first.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $bundledShell = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe'
    $shellCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $modernShell = if (Test-Path -LiteralPath $bundledShell) { $bundledShell } elseif ($shellCommand) { $shellCommand.Source } else { $null }
    if (-not $modernShell) { throw 'PowerShell 7 is required to build the Android installer.' }
    & $modernShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}
$buildShell = Join-Path $PSHOME 'pwsh.exe'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mobileRoot = Join-Path $projectRoot 'output\mobile'
$configPath = Join-Path $projectRoot 'mobile\config.json'
$utf8 = [System.Text.UTF8Encoding]::new($false)

# Run builds in child processes so a nested script's exit cannot skip validation.
& $buildShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot '.stabilization\run-smoke.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Desktop regression checks failed; no share package created.' }
if (-not (Test-Path -LiteralPath 'C:\Program Files\LOVE\lovec.exe')) {
    throw 'The mobile package smoke check requires C:\Program Files\LOVE\lovec.exe.'
}

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if ($config.versionName -notmatch '^(\d+\.\d+\.\d+)-android\.\d+$') {
    throw 'Expected an Android development version such as 0.1.0-android.26.'
}
$baseVersion = $Matches[1]
$previousApk = Get-ChildItem -LiteralPath $mobileRoot -Filter 'ThePictureShop-*-debug.apk' |
    Where-Object { $_.Name -match '^ThePictureShop-\d+\.\d+\.\d+-android\.\d+-debug\.apk$' } |
    Sort-Object { [int]([regex]::Match($_.Name, '-android\.(\d+)').Groups[1].Value) } -Descending |
    Select-Object -First 1
$highestCode = [int]$config.versionCode
if ($previousApk) {
    $highestCode = [Math]::Max($highestCode, [int]([regex]::Match($previousApk.Name, '-android\.(\d+)').Groups[1].Value))
}
$config.versionCode = $highestCode + 1
$config.versionName = "$baseVersion-android.$($config.versionCode)"
$shareRoot = Join-Path $projectRoot "output\android-share\$($config.versionName)"
if (Test-Path -LiteralPath $shareRoot) { throw "Share folder already exists: $shareRoot" }
[System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json) + "`n", $utf8)

& $buildShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'BUILD_ANDROID.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Android build failed; no share package created.' }
$report = Get-Content -Raw -LiteralPath (Join-Path $mobileRoot 'apk-report.json') | ConvertFrom-Json
$package = Get-Content -Raw -LiteralPath (Join-Path $mobileRoot 'build-report.json') | ConvertFrom-Json
if ($report.artifactKind -ne 'game-debug' -or $report.engineeringProbe -or
        -not $report.signed -or $report.applicationId -ne $config.applicationId -or
        $report.versionCode -ne $config.versionCode -or $report.versionName -ne $config.versionName -or
        $package.versionCode -ne $config.versionCode -or $report.embeddedLove.sha256 -ne $package.sha256) {
    throw 'APK report does not match this game build.'
}
$hash = (Get-FileHash -LiteralPath $report.apk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $report.sha256) { throw 'APK checksum does not match its verification report.' }

# Android accepts an update only when the application ID and signing key match.
# Compare actual certificates, so a regenerated debug keystore cannot silently
# turn a new build into an incompatible update.
$signer = Get-ChildItem (Join-Path $mobileRoot 'tooling\android-sdk\build-tools') -Recurse -Filter apksigner.bat |
    Sort-Object FullName -Descending | Select-Object -First 1
$java = Get-ChildItem (Join-Path $mobileRoot 'tooling\jdk-17') -Recurse -Filter java.exe | Select-Object -First 1
if (-not $signer -or -not $java) { throw 'Cannot verify Android signing certificate.' }
function Get-SignerDigest([string]$Path) {
    $lines = & $signer.FullName verify --print-certs $Path 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $lines -notmatch 'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]+)') {
        throw "Cannot verify installer signature: $Path"
    }
    return $Matches[1].ToLowerInvariant()
}
$previousJava = $env:JAVA_HOME
try {
    $env:JAVA_HOME = $java.Directory.Parent.FullName
    $certificate = Get-SignerDigest $report.apk
    if ($previousApk -and $certificate -ne (Get-SignerDigest $previousApk.FullName)) {
        throw 'Signing key changed from the previous APK. Resolve signing before sharing an update.'
    }
}
finally { $env:JAVA_HOME = $previousJava }

New-Item -ItemType Directory -Path $shareRoot | Out-Null
$filename = "ThePictureShop-$($config.versionName)-Install.apk"
$destination = Join-Path $shareRoot $filename
Copy-Item -LiteralPath $report.apk -Destination $destination
if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) {
    throw 'Copied installer failed checksum verification.'
}
[System.IO.File]::WriteAllText((Join-Path $shareRoot 'SHA256SUMS.txt'), "$hash  $filename`n", $utf8)
$instructions = @"
THE PICTURE SHOP - ANDROID PRIVATE TEST INSTALLER
Version: $($config.versionName)

SEND FROM YOUR PHONE
1. Find this folder in OneDrive on your phone, or copy the APK to Downloads.
2. Download the APK onto your phone before sharing it as a file attachment.
3. Share the .apk with your brother using an app that accepts APK files of this size.
   SMS/MMS is not suitable for this installer; text apps may reject APK files.
   If the attachment is rejected, share a OneDrive download link by text instead.
   He must download the APK from the link before opening it.

INSTALL WITH FRESH TEST SAVES (REQUESTED FOR THIS HANDOFF)
1. Download the new APK first.
2. Uninstall ONLY the old The Picture Shop app. Do not keep its app data if asked.
   This deletes that game's old test saves.
3. Open $filename in Downloads / My Files / Files.
4. If Android asks, allow this source to install unknown apps, then tap Install.
5. Open The Picture Shop and start a new save.

FUTURE UPDATES
This APK also supports installing over a previous build signed by this computer:
open the new APK and choose Update. An update by itself KEEPS existing saves.
No separate installer app or LOVE download is required.

This is a private development build. Automated checks passed; this packaging
command does not perform the full physical-device multiplayer acceptance.
Local Play participants need matching builds. Direct Play remains unavailable.

BUILD ANOTHER UPDATE ON THE PC
Double-click PACK_ANDROID.bat in the project folder. It advances the Android
version, runs the checks, builds and verifies the installer, and writes a new
numbered folder under output/android-share. Send the new APK from that folder.
"@
[System.IO.File]::WriteAllText((Join-Path $shareRoot 'READ-ME.txt'), $instructions + "`n", $utf8)
$shareReport = [ordered]@{
    versionName = $report.versionName
    versionCode = $report.versionCode
    applicationId = $report.applicationId
    installer = $filename
    bytes = (Get-Item -LiteralPath $destination).Length
    sha256 = $hash
    signingCertificateSha256 = $certificate
    previousSigningCertificateMatched = [bool]$previousApk
    sourceCommit = $package.sourceCommit
    sourceDirty = $package.sourceDirty
    physicalDeviceTested = [bool]$report.deviceLaunchVerified
    distribution = 'private-development-test'
}
[System.IO.File]::WriteAllText((Join-Path $shareRoot 'share-report.json'), ($shareReport | ConvertTo-Json) + "`n", $utf8)
Write-Output "INSTALLER_READY=$destination"
Write-Output ('SIZE_MB={0:N1}' -f ((Get-Item -LiteralPath $destination).Length / 1MB))
