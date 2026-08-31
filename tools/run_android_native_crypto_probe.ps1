[CmdletBinding()]
param(
    [string[]] $DeviceSerials
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$nativeOutputRoot = [IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'output\native-crypto'))
$deviceTestRoot = [IO.Path]::GetFullPath(
    (Join-Path $nativeOutputRoot 'device-tests'))
$evidencePath = [IO.Path]::GetFullPath(
    (Join-Path $deviceTestRoot 'android_native_crypto_opening_probe_report.json'))
$apkPath = [IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'output\mobile\ThePictureShop-CryptoProbe-engineering.apk'))
$apkReportPath = [IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'output\mobile\native-crypto-probe-apk-report.json'))
$androidReportPath = [IO.Path]::GetFullPath(
    (Join-Path $nativeOutputRoot 'build\android\native_crypto_android_report.json'))
$windowsReportPath = [IO.Path]::GetFullPath(
    (Join-Path $nativeOutputRoot 'build\windows-x64\native_crypto_report.json'))
$adb = [IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'output\mobile\tooling\android-sdk\platform-tools\adb.exe'))

$applicationId = 'com.thepictureshop.crypto_probe'
$activity = "$applicationId/org.love2d.android.GameActivity"
$pollTimeoutSeconds = 45
$requiredAbis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
$supportedPhysicalAbis = @('arm64-v8a', 'armeabi-v7a')
$expectedAbiMetadata = @{
    'armeabi-v7a' = @{
        target = 'armv7a-linux-androideabi21'
        elfClass = 'ELF32'
        machine = 'ARM'
    }
    'arm64-v8a' = @{
        target = 'aarch64-linux-android21'
        elfClass = 'ELF64'
        machine = 'AArch64'
    }
    'x86_64' = @{
        target = 'x86_64-linux-android21'
        elfClass = 'ELF64'
        machine = 'Advanced Micro Devices X86-64'
    }
}
$expectedExports = @(
    'tps_crypto_abi_version', 'tps_crypto_admission_token',
    'tps_crypto_init', 'tps_crypto_opening_state_free',
    'tps_crypto_opening_state_is_ready', 'tps_crypto_opening_state_new',
    'tps_crypto_opening_state_next', 'tps_crypto_opening_state_receive',
    'tps_crypto_bridge_state_free', 'tps_crypto_bridge_state_new',
    'tps_crypto_bridge_state_open', 'tps_crypto_bridge_state_seal',
    'tps_crypto_random', 'tps_crypto_response_tag',
    'tps_crypto_response_verify', 'tps_crypto_self_test',
    'tps_crypto_state_free', 'tps_crypto_state_handshake',
    'tps_crypto_state_is_ready', 'tps_crypto_state_new',
    'tps_crypto_state_open', 'tps_crypto_state_seal',
    'tps_crypto_state_start', 'tps_crypto_suite'
) | Sort-Object
$infoMarker = 'TPS_ANDROID_CRYPTO_PROBE_INFO abi=3 engineeringOnly=true productionReady=false'
$luaMarker = 'TPS_LUA_CRYPTO_OK'
$okMarker = 'TPS_ANDROID_CRYPTO_PROBE_OK'
$failMarker = 'TPS_ANDROID_CRYPTO_PROBE_FAIL'
$loveLogPrefix = '[LOVE] '

function Assert-WithinRoot([string] $Path, [string] $Root) {
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar)
    $prefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
    if ($resolvedPath -cne $resolvedRoot -and
            -not $resolvedPath.StartsWith(
                $prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Probe evidence path escapes its intended output root.'
    }
    return $resolvedPath
}

function Assert-NoReparsePath([string] $Path, [string] $Root) {
    $resolvedPath = Assert-WithinRoot $Path $Root
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar)
    $candidate = $resolvedPath
    while ($candidate -and ($candidate -ceq $resolvedRoot -or
            $candidate.StartsWith(
                $resolvedRoot + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase))) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Probe evidence path must not contain a reparse point.'
            }
        }
        if ($candidate -ceq $resolvedRoot) { break }
        $candidate = Split-Path $candidate -Parent
    }
    return $resolvedPath
}

function Assert-RegularFile([string] $Path, [string] $Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing."
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must not be a reparse point."
    }
}

function Get-LowerSha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-Sha256([object] $Value) {
    return $Value -is [string] -and $Value -cmatch '^[0-9a-f]{64}$'
}

function Read-JsonReport([string] $Path, [string] $Label) {
    Assert-RegularFile $Path $Label
    try {
        return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        throw "$Label is not valid JSON."
    }
}

function Test-ExactSet([object[]] $Expected, [object[]] $Actual) {
    return @(Compare-Object -ReferenceObject @($Expected | Sort-Object) `
        -DifferenceObject @($Actual | Sort-Object) -CaseSensitive).Count -eq 0
}

function Get-ZipEntrySha256([object] $Entry) {
    $stream = $Entry.Open()
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $algorithm.ComputeHash($stream)
        return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Assert-ValidSerial([string] $Serial) {
    if ([string]::IsNullOrEmpty($Serial) -or $Serial.Length -gt 128 -or
            $Serial -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
        throw 'An Android device serial is invalid.'
    }
}

function Invoke-AdbDiscard([string] $Serial, [string[]] $Arguments) {
    & $adb '-s' $Serial @Arguments *> $null
    return $LASTEXITCODE -eq 0
}

function Invoke-AdbUninstall([string] $Serial) {
    $success = @(& $adb '-s' $Serial 'uninstall' $applicationId 2>$null |
        ForEach-Object {
            if (([string] $_) -ceq 'Success') { 'success' }
        })
    return $LASTEXITCODE -eq 0 -and $success.Count -eq 1
}

function Get-AdbProperty(
    [string] $Serial,
    [string] $Property,
    [string] $FailureLabel
) {
    $values = @(& $adb '-s' $Serial 'shell' 'getprop' $Property 2>$null |
        ForEach-Object { [string] $_ })
    if ($LASTEXITCODE -ne 0 -or $values.Count -ne 1) {
        throw $FailureLabel
    }
    return $values[0]
}

function Read-ProbeMarkerCodes([string] $Serial) {
    # LÖVE writes probe messages under the SDL/APP tag and prefixes the raw
    # message with "[LOVE] ".  Filter at logcat before PowerShell sees any
    # lines, then reduce those messages immediately to fixed marker codes.
    $codes = @(& $adb '-s' $Serial 'shell' 'logcat' '-d' '-t' '4096' '-v' 'raw' `
        '-s' 'SDL/APP' `
        2>$null | ForEach-Object {
            $line = [string] $_
            if ($line.StartsWith($loveLogPrefix, [StringComparison]::Ordinal)) {
                $line = $line.Substring($loveLogPrefix.Length)
            }
            if ($line -ceq $infoMarker) {
                'info'
            }
            elseif ($line -ceq $luaMarker) {
                'lua'
            }
            elseif ($line -ceq $okMarker) {
                'ok'
            }
            elseif ($line -ceq $failMarker -or
                    $line.StartsWith($failMarker + ' ',
                        [StringComparison]::Ordinal)) {
                'fail'
            }
        })
    if ($LASTEXITCODE -ne 0) {
        throw 'Probe marker polling failed.'
    }
    return $codes
}

function Test-PackageAbsent([string] $Serial) {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $pathEntries = @(& $adb '-s' $Serial 'shell' 'pm' 'path' $applicationId `
            2>$null | ForEach-Object {
                if (([string] $_).StartsWith(
                        'package:', [StringComparison]::Ordinal)) {
                    'present'
                }
            })
        # Android's `pm path` returns exit 1 when absence is the successful
        # answer, so corroborate the empty path with the package manager's
        # exit-0 list operation rather than treating that status as ambiguity.
        $listed = @(& $adb '-s' $Serial 'shell' 'cmd' 'package' 'list' `
            'packages' $applicationId 2>$null | ForEach-Object {
                if (([string] $_) -ceq "package:$applicationId") {
                    'present'
                }
            })
        $listSucceeded = $LASTEXITCODE -eq 0
        if ($pathEntries.Count -eq 0 -and $listSucceeded -and
                $listed.Count -eq 0) {
            return $true
        }
        if ($attempt -lt 2) { Start-Sleep -Milliseconds 250 }
    }
    return $false
}

function Write-Evidence([object] $Evidence) {
    Assert-NoReparsePath $deviceTestRoot $nativeOutputRoot | Out-Null
    if (-not (Test-Path -LiteralPath $deviceTestRoot)) {
        New-Item -ItemType Directory -Path $deviceTestRoot | Out-Null
    }
    Assert-NoReparsePath $deviceTestRoot $nativeOutputRoot | Out-Null
    Assert-NoReparsePath $evidencePath $nativeOutputRoot | Out-Null
    if (Test-Path -LiteralPath $evidencePath) {
        $existing = Get-Item -LiteralPath $evidencePath -Force
        if (-not $existing.PSIsContainer -and
                ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
            # The fixed evidence file is the only existing path this runner replaces.
        }
        else {
            throw 'Probe evidence target is not a regular file.'
        }
    }
    $json = $Evidence | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText(
        $evidencePath,
        $json + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false))
}

# Validate the fixed evidence destination before touching a device.
Assert-WithinRoot $evidencePath $nativeOutputRoot | Out-Null
if (-not (Test-Path -LiteralPath $nativeOutputRoot -PathType Container)) {
    throw 'Native crypto output root is missing.'
}
Assert-NoReparsePath $nativeOutputRoot $nativeOutputRoot | Out-Null
Assert-RegularFile $adb 'Android platform tool'
Assert-RegularFile $apkPath 'Native crypto probe APK'

$apkReport = Read-JsonReport $apkReportPath 'Native crypto probe APK report'
$androidReport = Read-JsonReport $androidReportPath 'Android native crypto build report'
$windowsReport = Read-JsonReport $windowsReportPath 'Windows native crypto build report'

$actualApkHash = Get-LowerSha256 $apkPath
$actualApkBytes = (Get-Item -LiteralPath $apkPath).Length
$actualApkReportHash = Get-LowerSha256 $apkReportPath
$actualAndroidReportHash = Get-LowerSha256 $androidReportPath
$actualWindowsReportHash = Get-LowerSha256 $windowsReportPath

$reportedApkPath = [IO.Path]::GetFullPath([string] $apkReport.apk)
$reportedAndroidPath = [IO.Path]::GetFullPath([string] $apkReport.nativeCrypto.buildReport)
if ($apkReport.applicationId -cne $applicationId -or
        $apkReport.artifactKind -cne 'native-crypto-engineering-probe' -or
        $apkReport.engineeringProbe -ne $true -or
        $apkReport.internetPermission -ne $false -or
        $apkReport.signed -ne $true -or
        $apkReport.sixteenKbCompatible -ne $true -or
        $apkReport.nativeCrypto.bundled -ne $true -or
        $apkReport.nativeCrypto.productionReady -ne $false -or
        $apkReport.nativeCrypto.status -cne 'engineering-candidate-non-production' -or
        $reportedApkPath -cne $apkPath -or
        $reportedAndroidPath -cne $androidReportPath -or
        -not (Test-Sha256 $apkReport.sha256) -or
        [string] $apkReport.sha256 -cne $actualApkHash -or
        [long] $apkReport.apkBytes -ne $actualApkBytes -or
        -not (Test-Sha256 $apkReport.nativeCrypto.buildReportSha256) -or
        [string] $apkReport.nativeCrypto.buildReportSha256 -cne
            $actualAndroidReportHash) {
    throw 'Native crypto probe APK report validation failed.'
}

$requiredAndroidChecks = @(
    'cleanPinnedSourcePreparation', 'allRequiredAbisBuilt',
    'elf16KiBLoadAlignment', 'hiddenDependencySymbols',
    'exactAbiExportSurface', 'bindNow'
)
if ([int] $androidReport.abiVersion -ne 3 -or
        $androidReport.status -cne 'engineering-candidate-non-production' -or
        $androidReport.productionReady -ne $false -or
        [int] $androidReport.minAndroidApi -lt 21) {
    throw 'Android native crypto build report validation failed.'
}
foreach ($checkName in $requiredAndroidChecks) {
    if ($androidReport.checks.$checkName -cne 'pass') {
        throw 'Android native crypto build report validation failed.'
    }
}
$androidAbiNames = @(
    $androidReport.artifacts.PSObject.Properties.Name | Sort-Object)
$packagedAbiNames = @(
    $apkReport.nativeCrypto.packagedArtifacts.PSObject.Properties.Name |
        Sort-Object)
if (-not (Test-ExactSet $requiredAbis $androidAbiNames) -or
        -not (Test-ExactSet $requiredAbis $packagedAbiNames)) {
    throw 'Native crypto reports do not contain exactly the three required ABIs.'
}

$requiredWindowsChecks = @(
    'pinnedArchiveHashes', 'cleanSourceExtraction', 'noiseCMaintainedPatch',
    'libsodiumKnownAnswerTests', 'pinnedCacophonyNoiseVector',
    'deterministicTpsProviderV2KnownAnswer',
    'providerHandshakeAndReplayConformance',
    'responseAuthenticationConformance', 'simultaneousOpeningConformance',
    'bridgeFragmentAuthenticationConformance',
    'exactAbiExportSurface'
)
$windowsExports = @($windowsReport.artifacts.library.exports)
if ([int] $windowsReport.abiVersion -ne 3 -or
        $windowsReport.status -cne 'engineering-candidate-non-production' -or
        $windowsReport.productionReady -ne $false -or
        [int] $windowsReport.artifacts.library.exportCount -ne 24 -or
        -not (Test-ExactSet $expectedExports $windowsExports) -or
        -not (Test-Sha256 $androidReport.inputs.windowsPreparationReportSha256) -or
        [string] $androidReport.inputs.windowsPreparationReportSha256 -cne
            $actualWindowsReportHash) {
    throw 'Windows native crypto build report validation failed.'
}
foreach ($checkName in $requiredWindowsChecks) {
    if ($windowsReport.checks.$checkName -cne 'pass') {
        throw 'Windows native crypto build report validation failed.'
    }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$libraryEvidence = [ordered]@{}
$archive = [IO.Compression.ZipFile]::OpenRead($apkPath)
try {
    $expectedLibraryEntries = @($requiredAbis | ForEach-Object {
        "lib/$_/libtps_crypto.so"
    } | Sort-Object)
    $actualLibraryEntries = @($archive.Entries | Where-Object {
        $_.Name -ceq 'libtps_crypto.so'
    } | ForEach-Object {
        $_.FullName.Replace('\', '/')
    } | Sort-Object)
    if ($actualLibraryEntries.Count -ne $expectedLibraryEntries.Count -or
            -not (Test-ExactSet $expectedLibraryEntries $actualLibraryEntries)) {
        throw 'Native crypto probe APK does not contain exactly three ABI libraries.'
    }
    foreach ($abi in $requiredAbis) {
        $artifact = $androidReport.artifacts.PSObject.Properties[$abi].Value
        $packaged = $apkReport.nativeCrypto.packagedArtifacts.PSObject.Properties[$abi].Value
        $metadata = $expectedAbiMetadata[$abi]
        $expectedRelativePath = "output/native-crypto/build/android/$abi/libtps_crypto.so"
        $libraryPath = [IO.Path]::GetFullPath(
            (Join-Path $repoRoot $expectedRelativePath.Replace('/', '\')))
        Assert-RegularFile $libraryPath "Native crypto $abi library"
        $libraryHash = Get-LowerSha256 $libraryPath
        $libraryBytes = (Get-Item -LiteralPath $libraryPath).Length
        $entryName = "lib/$abi/libtps_crypto.so"
        $entry = $archive.GetEntry($entryName)
        if (-not $entry) {
            throw 'Native crypto probe APK is missing a required ABI library.'
        }
        $entryHash = Get-ZipEntrySha256 $entry
        $artifactExports = @($artifact.exports)
        if (([string] $artifact.path).Replace('\', '/') -cne
                $expectedRelativePath -or
                [string] $artifact.target -cne $metadata.target -or
                [string] $artifact.elfClass -cne $metadata.elfClass -or
                [string] $artifact.machine -cne $metadata.machine -or
                [string] $artifact.loadAlignment -cne '0x4000' -or
                [int] $artifact.exportCount -ne 24 -or
                -not (Test-ExactSet $expectedExports $artifactExports) -or
                -not (Test-Sha256 $artifact.sha256) -or
                [string] $artifact.sha256 -cne $libraryHash -or
                [long] $artifact.bytes -ne $libraryBytes -or
                [string] $packaged.apkEntry -cne $entryName -or
                -not (Test-Sha256 $packaged.sha256) -or
                [string] $packaged.sha256 -cne $entryHash -or
                [string] $packaged.sha256 -cne $libraryHash -or
                [long] $packaged.bytes -ne $entry.Length -or
                [long] $entry.Length -ne $libraryBytes) {
            throw 'Native crypto ABI artifact validation failed.'
        }
        $libraryEvidence[$abi] = [ordered]@{
            sha256 = $entryHash
            bytes = [long] $entry.Length
            exportCount = 24
        }
    }
}
finally {
    $archive.Dispose()
}

$attachedSerials = @(& $adb 'devices' 2>$null | ForEach-Object {
    $line = [string] $_
    if ($line -cmatch '^([A-Za-z0-9][A-Za-z0-9._:-]{0,127})\tdevice$') {
        $Matches[1]
    }
})
if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate Android devices.' }
if ($attachedSerials.Count -lt 1) {
    throw 'At least one authorized Android device is required.'
}

$attachedSet = New-Object 'Collections.Generic.HashSet[string]' `
    ([StringComparer]::Ordinal)
foreach ($serial in $attachedSerials) {
    Assert-ValidSerial $serial
    $null = $attachedSet.Add($serial)
}
$selectedSerials = @()
if ($null -eq $DeviceSerials -or $DeviceSerials.Count -eq 0) {
    $selectedSerials = @($attachedSerials)
}
else {
    $selectionSet = New-Object 'Collections.Generic.HashSet[string]' `
        ([StringComparer]::Ordinal)
    foreach ($serial in $DeviceSerials) {
        Assert-ValidSerial $serial
        if (-not $selectionSet.Add($serial)) {
            throw 'Duplicate Android device serials are not allowed.'
        }
        if (-not $attachedSet.Contains($serial)) {
            throw 'A selected Android device is not authorized and attached.'
        }
        $selectedSerials += $serial
    }
}
if ($selectedSerials.Count -lt 1) {
    throw 'At least one authorized Android device is required.'
}

$deviceEvidence = @()
$allDevicesPassed = $true
$deviceIndex = 0
foreach ($serial in $selectedSerials) {
    $deviceIndex++
    $record = [ordered]@{
        index = $deviceIndex
        pass = $false
        model = $null
        api = $null
        abi = $null
        markers = [ordered]@{
            info = $false
            luaConformance = $false
            probeOk = $false
            probeFail = $false
        }
        cleanup = [ordered]@{
            forceStopAttempted = $false
            forceStopSucceeded = $false
            uninstallAttempted = $false
            uninstallSucceeded = $false
            packagePathAbsent = $false
            pass = $false
        }
        failureCode = $null
    }
    $failureCode = $null
    $packageInstalled = $false
    try {
        $stateLines = @(& $adb '-s' $serial 'get-state' 2>$null |
            Where-Object { ([string] $_) -ceq 'device' })
        if ($LASTEXITCODE -ne 0 -or $stateLines.Count -ne 1) {
            throw 'Device state query failed.'
        }
        $model = Get-AdbProperty $serial 'ro.product.model' 'Device model query failed.'
        $apiText = Get-AdbProperty $serial 'ro.build.version.sdk' 'Device API query failed.'
        $abi = Get-AdbProperty $serial 'ro.product.cpu.abi' 'Device ABI query failed.'
        if ($model.Length -lt 1 -or $model.Length -gt 80 -or
                $model -cnotmatch '^[A-Za-z0-9][A-Za-z0-9 ._()+-]{0,79}$' -or
                $apiText -cnotmatch '^[0-9]{2,3}$' -or
                $supportedPhysicalAbis -cnotcontains $abi) {
            $failureCode = 'unsupported-device'
            throw 'Selected device is not a supported physical ARM Android device.'
        }
        $api = [int] $apiText
        if ($api -lt [int] $androidReport.minAndroidApi -or $api -gt 100) {
            $failureCode = 'unsupported-device'
            throw 'Selected device API is unsupported.'
        }
        $record.model = $model
        $record.api = $api
        $record.abi = $abi

        $failureCode = 'install'
        if (-not (Invoke-AdbDiscard $serial @('install', '-r', $apkPath))) {
            throw 'Probe APK installation failed.'
        }
        $packageInstalled = $true
        $failureCode = 'prepare'
        if (-not (Invoke-AdbDiscard $serial @('shell', 'am', 'force-stop',
                    $applicationId)) -or
                -not (Invoke-AdbDiscard $serial @('logcat', '-c'))) {
            throw 'Probe launch preparation failed.'
        }

        $failureCode = 'launch'
        $launchStatus = @(& $adb '-s' $serial 'shell' 'am' 'start' '-W' '-n' `
            $activity 2>$null | ForEach-Object {
                if (([string] $_) -ceq 'Status: ok') { 'ok' }
            })
        if ($LASTEXITCODE -ne 0 -or $launchStatus.Count -ne 1) {
            throw 'Probe activity launch failed.'
        }

        $failureCode = 'probe-timeout'
        $deadline = [DateTime]::UtcNow.AddSeconds($pollTimeoutSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            foreach ($code in @(Read-ProbeMarkerCodes $serial)) {
                if ($code -ceq 'info') { $record.markers.info = $true }
                elseif ($code -ceq 'lua') { $record.markers.luaConformance = $true }
                elseif ($code -ceq 'ok') { $record.markers.probeOk = $true }
                elseif ($code -ceq 'fail') { $record.markers.probeFail = $true }
            }
            if ($record.markers.probeFail) {
                $failureCode = 'probe-fail-marker'
                throw 'Probe reported a failure marker.'
            }
            if ($record.markers.info -and $record.markers.luaConformance -and
                    $record.markers.probeOk) {
                $failureCode = $null
                break
            }
            $remaining = $deadline - [DateTime]::UtcNow
            if ($remaining.TotalMilliseconds -gt 0) {
                Start-Sleep -Milliseconds ([Math]::Min(
                    250, [int] $remaining.TotalMilliseconds))
            }
        }
        if (-not $record.markers.info -or
                -not $record.markers.luaConformance -or
                -not $record.markers.probeOk -or
                $record.markers.probeFail) {
            $failureCode = 'probe-timeout'
            throw 'Probe conformance markers were incomplete.'
        }
    }
    catch {
        if (-not $failureCode) { $failureCode = 'device-operation' }
    }
    finally {
        $record.cleanup.forceStopAttempted = $true
        $record.cleanup.forceStopSucceeded = Invoke-AdbDiscard $serial @(
            'shell', 'am', 'force-stop', $applicationId)
        $record.cleanup.uninstallAttempted = $true
        $record.cleanup.uninstallSucceeded = Invoke-AdbUninstall $serial
        $record.cleanup.packagePathAbsent = Test-PackageAbsent $serial
        $record.cleanup.pass = $record.cleanup.forceStopSucceeded -and
            $record.cleanup.packagePathAbsent -and
            (-not $packageInstalled -or $record.cleanup.uninstallSucceeded)
        if (-not $record.cleanup.pass) {
            if (-not $failureCode) { $failureCode = 'cleanup' }
        }
    }
    $record.failureCode = $failureCode
    $record.pass = -not $failureCode -and $record.cleanup.pass -and
        $record.markers.info -and $record.markers.luaConformance -and
        $record.markers.probeOk -and -not $record.markers.probeFail
    if (-not $record.pass) { $allDevicesPassed = $false }
    $deviceEvidence += $record
}

$evidence = [ordered]@{
    schemaVersion = 1
    status = if ($allDevicesPassed) { 'pass' } else { 'fail' }
    probe = 'android-native-crypto-opening-and-bridge-conformance'
    applicationId = $applicationId
    engineeringProbe = $true
    productionReady = $false
    publicAddressRecorded = $false
    secretRecorded = $false
    cleanupVerified = @($deviceEvidence | Where-Object {
        -not $_.cleanup.pass
    }).Count -eq 0
    pollTimeoutSeconds = $pollTimeoutSeconds
    artifacts = [ordered]@{
        apk = [ordered]@{
            path = 'output/mobile/ThePictureShop-CryptoProbe-engineering.apk'
            sha256 = $actualApkHash
            bytes = [long] $actualApkBytes
        }
        reports = [ordered]@{
            apkSha256 = $actualApkReportHash
            androidNativeSha256 = $actualAndroidReportHash
            windowsNativeSha256 = $actualWindowsReportHash
        }
        nativeAbiVersion = 3
        nativeExportCount = 24
        libraries = $libraryEvidence
    }
    deviceCount = $deviceEvidence.Count
    devices = $deviceEvidence
}
Write-Evidence $evidence

if (-not $allDevicesPassed) {
    throw 'Android native crypto probe failed; redacted evidence was written.'
}
Write-Output 'TPS_ANDROID_NATIVE_CRYPTO_RUNNER_OK'
Write-Output $evidencePath
