param(
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [string]$OutputDirectory,
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configPath = Join-Path $projectRoot 'mobile\config.json'
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$testVersion = ([string]$config.versionName).Replace('-android.', '-direct-test.')
if ($testVersion -ceq [string]$config.versionName) {
    throw 'Expected an Android version name for the isolated Direct Test build.'
}
$package = (Resolve-Path -LiteralPath $PackagePath).Path
$sourceReportPath = Join-Path (Split-Path $package -Parent) 'build-report.json'
if (-not (Test-Path -LiteralPath $sourceReportPath -PathType Leaf)) {
    throw 'Build a fresh shared .love with build_mobile_package.py first; its build-report.json is required.'
}
$sourceReport = Get-Content -Raw -LiteralPath $sourceReportPath | ConvertFrom-Json
$probeRoot = Join-Path $projectRoot 'tools\probes\android_manual_direct'
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $projectRoot "output\android-manual-direct-$runId"
}
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
$outputPrefix = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'output')).TrimEnd('\') + '\'
if (-not $output.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must be a new directory inside this project output directory.'
}
if (Test-Path -LiteralPath $output) {
    throw 'OutputDirectory already exists. Choose a fresh directory to preserve previous test evidence.'
}

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-EntrySha256($Entry) {
    $stream = $Entry.Open()
    $digest = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($digest.ComputeHash($stream)).Replace('-','').ToLowerInvariant()
    }
    finally { $digest.Dispose(); $stream.Dispose() }
}

function Read-EntryText($Entry) {
    if (-not $Entry) { throw 'Required shared package metadata is missing.' }
    $reader = [IO.StreamReader]::new($Entry.Open(), [Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() }
    finally { $reader.Dispose() }
}

function Write-Report($Value, [string]$Path) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 14) + "`n",
        [Text.UTF8Encoding]::new($false))
}

$packageHash = Get-LowerSha256 $package
if ($packageHash -cne [string]$sourceReport.sha256 -or
        [long](Get-Item -LiteralPath $package).Length -ne [long]$sourceReport.packageBytes -or
        [string]$sourceReport.versionName -cne [string]$config.versionName -or
        [int]$sourceReport.versionCode -ne [int]$config.versionCode) {
    throw 'Shared package/report do not match the current version and exact source package hash.'
}

# Verify the actual archive against today's working tree, including dirty edits.
# A timestamp or Git commit alone cannot prove an old .love contains a fix.
$sourceHashes = [ordered]@{}
$sourceArchive = [IO.Compression.ZipFile]::OpenRead($package)
try {
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $sourceArchive.Entries) {
        $relative = $entry.FullName
        if (-not $relative -or $relative.Contains('\') -or
                $relative.StartsWith('/') -or $relative.Contains(':') -or
                $relative.Split('/') -contains '..' -or -not $names.Add($relative)) {
            throw 'Shared package has an unsafe or duplicate entry.'
        }
        if ($relative -ceq 'mobile-build.json' -or $relative -ceq 'src/build_version.lua') {
            continue
        }
        $source = Join-Path $projectRoot $relative.Replace('/','\')
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Shared package contains an unexpected or missing source file: $relative"
        }
        $hash = Get-LowerSha256 $source
        if ($hash -cne (Get-EntrySha256 $entry)) {
            throw "Shared package is stale. Rebuild it before testing: $relative"
        }
        $sourceHashes[$relative] = $hash
    }
    foreach ($source in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') -Recurse -File) {
        $relative = $source.FullName.Substring($projectRoot.Length + 1).Replace('\','/')
        if ($relative -ceq 'src/screens/frontier_arcade.lua') { continue }
        if (-not $names.Contains($relative)) { throw "Shared package is incomplete: $relative" }
    }
    if (-not $names.Contains('main.lua') -or -not $names.Contains('conf.lua') -or
            -not $names.Contains('src/net/local_ipv6.lua') -or
            $sourceArchive.Entries.Count -ne [int]$sourceReport.runtimeFiles + 1) {
        throw 'Shared package is missing required runtime content or its entry count does not match.'
    }
    $embedded = Read-EntryText ($sourceArchive.GetEntry('mobile-build.json')) | ConvertFrom-Json
    $runtimeVersion = Read-EntryText ($sourceArchive.GetEntry('src/build_version.lua'))
    if ([int]$embedded.versionCode -ne [int]$config.versionCode -or
            [string]$embedded.versionName -cne [string]$config.versionName -or
            $runtimeVersion.Trim() -cne ('return { name = "' + $config.versionName + '" }')) {
        throw 'Embedded shared game version does not match mobile/config.json.'
    }
    $cryptoText = Read-EntryText ($sourceArchive.GetEntry('src/net/crypto_native.lua'))
    if ($cryptoText -notmatch '(?m)^\s*productionReady = false,\s*$') {
        throw 'Normal native crypto source must retain its closed production-readiness gate.'
    }
    $testRuntimeFileCount = $sourceArchive.Entries.Count - 1
    $testRuntimeBytes = [long](($sourceArchive.Entries | Where-Object {
        $_.FullName -cne 'mobile-build.json'
    } | Measure-Object -Property Length -Sum).Sum)
}
finally { $sourceArchive.Dispose() }

New-Item -ItemType Directory -Path $output | Out-Null
$testPackage = Join-Path $output "ThePictureShop-DirectTest-$testVersion.love"
$reportPath = Join-Path $output 'manual-direct-test-report.json'
$report = [ordered]@{
    status = 'preparing'
    artifactKind = 'manual-direct-engineering-test'
    applicationId = 'com.thepictureshop.direct_test'
    applicationName = 'Picture Shop Direct Test'
    versionName = $testVersion
    versionCode = [int]$config.versionCode
    createdUtc = [DateTime]::UtcNow.ToString('o')
    roles = @('host','guest')
    sourcePackage = $package
    sourceVersionName = [string]$config.versionName
    sourcePackageSha256 = $packageHash
    sourceBuildReportSha256 = Get-LowerSha256 $sourceReportPath
    sourceCommit = $sourceReport.sourceCommit
    sourceDirty = $sourceReport.sourceDirty
    currentRuntimeSourceVerified = $true
    sourceFileSha256 = $sourceHashes
    engineeringSourceSha256 = [ordered]@{}
    generatedArchiveEntrySha256 = [ordered]@{}
    builderSourceSha256 = Get-LowerSha256 $PSCommandPath
    apkBuilderSourceSha256 = Get-LowerSha256 (Join-Path $PSScriptRoot 'build_android_apk.ps1')
    mobileConfigSha256 = Get-LowerSha256 $configPath
    normalCryptoProductionReady = $false
    cryptoOptIn = 'candidate-only; process-local; isolated test entry point'
    automaticallyConnects = $false
    containsInviteOrPeerConfiguration = $false
    installed = $false
    remoteConnectionVerified = $false
}
Write-Report $report $reportPath
$temporaryBuildRoot = $null

function Assert-StableInputs {
    if ((Get-LowerSha256 $package) -cne $packageHash -or
            (Get-LowerSha256 $configPath) -cne $report.mobileConfigSha256 -or
            (Get-LowerSha256 $PSCommandPath) -cne $report.builderSourceSha256 -or
            (Get-LowerSha256 (Join-Path $PSScriptRoot 'build_android_apk.ps1')) -cne $report.apkBuilderSourceSha256) {
        throw 'Build inputs changed during preparation. Rebuild from a stable source tree.'
    }
    foreach ($relative in $sourceHashes.Keys) {
        if ((Get-LowerSha256 (Join-Path $projectRoot $relative.Replace('/','\'))) -cne $sourceHashes[$relative]) {
            throw "Runtime source changed during preparation. Rebuild the shared package: $relative"
        }
    }
    foreach ($relative in $report.engineeringSourceSha256.Keys) {
        $source = if ($relative -ceq 'main.lua' -or $relative -ceq 'conf.lua') {
            Join-Path $probeRoot $relative
        } else { Join-Path $projectRoot $relative.Replace('/','\') }
        if ((Get-LowerSha256 $source) -cne $report.engineeringSourceSha256[$relative]) {
            throw 'Engineering entry point changed during preparation. Rebuild this test package.'
        }
    }
}

try {
    Copy-Item -LiteralPath $package -Destination $testPackage
    $testArchive = [IO.Compression.ZipFile]::Open($testPackage, [IO.Compression.ZipArchiveMode]::Update)
    try {
        foreach ($source in Get-ChildItem -LiteralPath $probeRoot -Recurse -File | Sort-Object FullName) {
            $relative = $source.FullName.Substring($probeRoot.Length + 1).Replace('\','/')
            $entryName = if ($relative -ceq 'main.lua' -or $relative -ceq 'conf.lua') {
                $relative
            } else { "tools/probes/android_manual_direct/$relative" }
            $existing = $testArchive.GetEntry($entryName)
            if ($existing) {
                $testRuntimeBytes -= $existing.Length
                $existing.Delete()
            }
            else { $testRuntimeFileCount++ }
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($testArchive,
                $source.FullName, $entryName, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
            $report.engineeringSourceSha256[$entryName] = Get-LowerSha256 $source.FullName
            $testRuntimeBytes += $source.Length
        }
        $generatedVersion = 'return { name = "' + $testVersion + '" }' + "`n"
        $testRuntimeBytes += [Text.Encoding]::UTF8.GetByteCount($generatedVersion) -
            $testArchive.GetEntry('src/build_version.lua').Length
        $embedded.applicationId = $report.applicationId
        $embedded.applicationName = $report.applicationName
        $embedded.versionName = $testVersion
        $embedded.runtimeFiles = $testRuntimeFileCount
        $embedded.runtimeBytes = $testRuntimeBytes
        $generatedEntries = [ordered]@{
            'src/build_version.lua' = $generatedVersion
            'mobile-build.json' = ($embedded | ConvertTo-Json -Depth 10) + "`n"
        }
        foreach ($entryName in $generatedEntries.Keys) {
            $testArchive.GetEntry($entryName).Delete()
            $entry = $testArchive.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
            $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
            try { $writer.Write($generatedEntries[$entryName]) }
            finally { $writer.Dispose() }
            $report.generatedArchiveEntrySha256[$entryName] = Get-EntrySha256 $entry
        }
    }
    finally { $testArchive.Dispose() }
    $report.testPackage = $testPackage
    $report.testPackageSha256 = Get-LowerSha256 $testPackage
    $report.status = 'package-prepared'
    Write-Report $report $reportPath
    if (-not $PrepareOnly) {
        # Each run gets its own wrapper and output directory; old acceptance
        # reports and role-specific probe APKs are never overwritten.
        $temporaryBuildRoot = Join-Path ([IO.Path]::GetTempPath()) "tps-manual-direct-$runId"
        if (Test-Path -LiteralPath $temporaryBuildRoot) { throw 'Temporary build directory already exists.' }
        & (Join-Path $PSScriptRoot 'build_android_apk.ps1') -PackagePath $testPackage `
            -EngineeringManualDirectTest -SensitiveBuildRoot $temporaryBuildRoot
        if (-not $?) { throw 'Manual Direct APK build failed.' }
        $apkReportPath = Join-Path $temporaryBuildRoot 'artifacts\manual-direct-test-apk-report.json'
        $apkReport = Get-Content -Raw -LiteralPath $apkReportPath | ConvertFrom-Json
        if ($apkReport.artifactKind -cne 'manual-direct-engineering-test' -or
                $apkReport.applicationId -cne $report.applicationId -or
                [int]$apkReport.versionCode -ne [int]$config.versionCode -or
                $apkReport.versionName -cne $testVersion -or
                $apkReport.embeddedLove.sha256 -cne $report.testPackageSha256 -or
                $apkReport.nativeCrypto.productionReady -ne $false -or
                $apkReport.signed -ne $true -or
                $apkReport.deviceLaunchVerified -ne $false -or
                $apkReport.installedDeviceSerial) {
            throw 'Manual Direct APK report does not match the requested isolated engineering package.'
        }
        Assert-StableInputs
        $apk = Join-Path $output (Split-Path $apkReport.apk -Leaf)
        Copy-Item -LiteralPath $apkReport.apk -Destination $apk
        if ((Get-LowerSha256 $apk) -cne [string]$apkReport.sha256) {
            throw 'Copied manual Direct APK hash mismatch.'
        }
        $apkReport.apk = $apk
        Write-Report $apkReport (Join-Path $output 'manual-direct-test-apk-report.json')
        $report.apk = $apk
        $report.apkSha256 = [string]$apkReport.sha256
        $report.apkBytes = [long]$apkReport.apkBytes
        $report.status = 'apk-built-not-installed-or-remotely-tested'
        Write-Output "ANDROID_MANUAL_DIRECT_APK=$apk"
    }
    else { Assert-StableInputs }
    Write-Report $report $reportPath
    Write-Output "ANDROID_MANUAL_DIRECT_PACKAGE=$testPackage"
    Write-Output "ANDROID_MANUAL_DIRECT_REPORT=$reportPath"
}
catch {
    $report.status = 'failed'
    Write-Report $report $reportPath
    throw
}
finally {
    if ($temporaryBuildRoot -and (Test-Path -LiteralPath $temporaryBuildRoot)) {
        $resolvedTemporary = [IO.Path]::GetFullPath($temporaryBuildRoot)
        $temporaryPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $resolvedTemporary.StartsWith($temporaryPrefix, [StringComparison]::OrdinalIgnoreCase) -or
                (Split-Path $resolvedTemporary -Leaf) -cne "tps-manual-direct-$runId" -or
                ((Get-Item -LiteralPath $resolvedTemporary -Force).Attributes -band
                    [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Refusing to clean an unexpected temporary Android build path.'
        }
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
    }
}
