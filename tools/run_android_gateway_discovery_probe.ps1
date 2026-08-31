[CmdletBinding()]
param(
    [string[]] $DeviceSerials
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$nativeRouteRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'output\native-route'))
$deviceTestRoot = [IO.Path]::GetFullPath((Join-Path $nativeRouteRoot `
    'device-tests'))
$evidencePath = [IO.Path]::GetFullPath((Join-Path $deviceTestRoot `
    'android_gateway_discovery_probe_report.json'))
$apkPath = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'output\mobile\ThePictureShop-GatewayDiscoveryProbe-engineering.apk'))
$apkReportPath = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'output\mobile\gateway-discovery-probe-apk-report.json'))
$nativeReportPath = [IO.Path]::GetFullPath((Join-Path $nativeRouteRoot `
    'build\android\android_gateway_report.json'))
$javaBridgeSourcePath = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'mobile\android\java\com\thepictureshop\net\GatewayDiscoveryBridge.java'))
$adb = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'output\mobile\tooling\android-sdk\platform-tools\adb.exe'))

$applicationId = 'com.thepictureshop.gateway_probe'
$activity = "$applicationId/org.love2d.android.GameActivity"
$requiredAbis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
$supportedDeviceAbis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
$commonUndefinedSymbols = @(
    '__cxa_atexit',
    '__cxa_finalize',
    'memcpy',
    'pthread_mutex_lock',
    'pthread_mutex_unlock',
    'strlen'
) | Sort-Object
$requiredUndefinedSymbols = [ordered]@{
    'armeabi-v7a' = @($commonUndefinedSymbols + 'memcmp' | Sort-Object)
    'arm64-v8a' = @($commonUndefinedSymbols)
    'x86_64' = @($commonUndefinedSymbols)
}
$infoMarker =
    'TPS_ANDROID_GATEWAY_PROBE_INFO abi=2 readOnly=true networkTrafficSent=false'
$modulesMarker = 'TPS_ANDROID_GATEWAY_MODULES_OK'
$libraryMarker = 'TPS_ANDROID_GATEWAY_LIBRARY_OK'
$abiMarker = 'TPS_ANDROID_GATEWAY_ABI_OK'
$nativeSnapshotMarker = 'TPS_ANDROID_GATEWAY_NATIVE_SNAPSHOT_OK'
$callbackHealthyMarker = 'TPS_ANDROID_GATEWAY_CALLBACK_HEALTHY_OK'
$routeMarker = 'TPS_ANDROID_GATEWAY_ROUTE_OK'
$revalidationMarker = 'TPS_ANDROID_GATEWAY_REVALIDATION_OK'
$okMarker = 'TPS_ANDROID_GATEWAY_PROBE_OK'
$failMarker = 'TPS_ANDROID_GATEWAY_PROBE_FAIL'
$loveLogPrefix = '[LOVE] '
$pollTimeoutSeconds = 45

function Assert-WithinRoot([string] $Path, [string] $Root) {
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar)
    $prefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
    if ($resolvedPath -cne $resolvedRoot -and
            -not $resolvedPath.StartsWith(
                $prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Android gateway evidence path escapes its output root.'
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

function Test-ExactSet([object[]] $Expected, [object[]] $Actual) {
    return @(Compare-Object -ReferenceObject @($Expected | Sort-Object) `
        -DifferenceObject @($Actual | Sort-Object) -CaseSensitive).Count -eq 0
}

function Read-JsonReport([string] $Path, [string] $Label) {
    Assert-RegularFile $Path $Label
    try {
        return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    } catch {
        throw "$Label is not valid JSON."
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

function Get-AdbProperty(
    [string] $Serial,
    [string] $Property,
    [string] $FailureLabel
) {
    $values = @(& $adb '-s' $Serial 'shell' 'getprop' $Property 2>$null |
        ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0 -or $values.Count -ne 1) {
        throw $FailureLabel
    }
    return $values[0]
}

function Get-ProbeProcessId([string] $Serial) {
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        $values = @(& $adb '-s' $Serial 'shell' 'pidof' $applicationId `
            2>$null | ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ -ne '' })
        if ($LASTEXITCODE -eq 0 -and $values.Count -eq 1 -and
                $values[0] -cmatch '^[1-9][0-9]{0,9}$') {
            $value = [int64]$values[0]
            if ($value -le [int]::MaxValue) { return [int]$value }
        }
        if ($attempt -lt 39) { Start-Sleep -Milliseconds 100 }
    }
    throw 'Android gateway probe process did not become available.'
}

function Read-ProbeMarkerCodes([string] $Serial, [int] $ProcessId) {
    if ($ProcessId -lt 1) { throw 'Probe process identity is invalid.' }
    # Filter by the newly launched dedicated process before log lines cross
    # this boundary. This is non-destructive and cannot consume or clear logs
    # belonging to other applications.
    $codes = @(& $adb '-s' $Serial 'shell' 'logcat' `
        "--pid=$ProcessId" '-d' '-t' '4096' '-v' 'raw' '-s' 'SDL/APP' `
        2>$null |
        ForEach-Object {
            $line = [string]$_
            if ($line.StartsWith($loveLogPrefix,
                    [StringComparison]::Ordinal)) {
                $line = $line.Substring($loveLogPrefix.Length)
            }
            if ($line -ceq $infoMarker) { 'info' }
            elseif ($line -ceq $modulesMarker) { 'modules' }
            elseif ($line -ceq $libraryMarker) { 'library' }
            elseif ($line -ceq $abiMarker) { 'abi' }
            elseif ($line -ceq $nativeSnapshotMarker) { 'native-snapshot' }
            elseif ($line -ceq $callbackHealthyMarker) { 'callback-healthy' }
            elseif ($line -ceq $routeMarker) { 'route' }
            elseif ($line -ceq $revalidationMarker) { 'revalidation' }
            elseif ($line -ceq $okMarker) { 'ok' }
            elseif ($line -ceq $failMarker) { 'fail' }
        })
    if ($LASTEXITCODE -ne 0) { throw 'Probe marker polling failed.' }
    return $codes
}

function Test-PackageAbsent([string] $Serial) {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $paths = @(& $adb '-s' $Serial 'shell' 'pm' 'path' $applicationId `
            2>$null | ForEach-Object {
                if (([string]$_).StartsWith(
                        'package:', [StringComparison]::Ordinal)) {
                    'present'
                }
            })
        $listed = @(& $adb '-s' $Serial 'shell' 'cmd' 'package' 'list' `
            'packages' $applicationId 2>$null | ForEach-Object {
                if (([string]$_) -ceq "package:$applicationId") {
                    'present'
                }
            })
        $listSucceeded = $LASTEXITCODE -eq 0
        if ($paths.Count -eq 0 -and $listSucceeded -and
                $listed.Count -eq 0) {
            return $true
        }
        if ($attempt -lt 2) { Start-Sleep -Milliseconds 250 }
    }
    return $false
}

function Write-Evidence([object] $Evidence) {
    Assert-WithinRoot $deviceTestRoot $nativeRouteRoot | Out-Null
    Assert-WithinRoot $evidencePath $nativeRouteRoot | Out-Null
    New-Item -ItemType Directory -Path $deviceTestRoot -Force | Out-Null
    foreach ($path in @($deviceTestRoot, $evidencePath)) {
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Android gateway evidence path must not be a reparse point.'
            }
        }
    }
    [IO.File]::WriteAllText(
        $evidencePath,
        (($Evidence | ConvertTo-Json -Depth 12) + [Environment]::NewLine),
        [Text.UTF8Encoding]::new($false))
}

Assert-WithinRoot $evidencePath $nativeRouteRoot | Out-Null
Assert-RegularFile $adb 'Android platform tool'
Assert-RegularFile $apkPath 'Android gateway probe APK'
Assert-RegularFile $javaBridgeSourcePath 'Tracked Android gateway Java bridge'
$apkReport = Read-JsonReport $apkReportPath 'Android gateway probe APK report'
$nativeReport = Read-JsonReport $nativeReportPath `
    'Android gateway native build report'

$actualApkHash = Get-LowerSha256 $apkPath
$actualNativeReportHash = Get-LowerSha256 $nativeReportPath
$actualJavaBridgeSourceHash = Get-LowerSha256 $javaBridgeSourcePath
$reportedNativeAbis = @(
    $nativeReport.artifacts.PSObject.Properties.Name | Sort-Object)
$packagedAbis = @(
    $apkReport.androidGatewayDiscovery.packagedArtifacts.PSObject.Properties.Name |
        Sort-Object)
if ([int]$nativeReport.schemaVersion -ne 1 -or
        $nativeReport.status -cne 'engineering-foundation' -or
        $nativeReport.productionReady -ne $false -or
        [int]$nativeReport.abiVersion -ne 2 -or
        [int]$nativeReport.minAndroidApi -ne 26 -or
        -not (Test-Sha256 $nativeReport.inputs.javaBridgeSourceSha256) -or
        [string]$nativeReport.inputs.javaBridgeSourceSha256 -cne
            $actualJavaBridgeSourceHash -or
        -not (Test-ExactSet $requiredAbis $reportedNativeAbis) -or
        -not (Test-ExactSet $requiredAbis $packagedAbis)) {
    throw 'Android gateway native or packaged ABI report is invalid.'
}
if ([int]$nativeReport.androidSignalCoverage.minBridgeApi -ne 26 -or
        [int]$nativeReport.androidSignalCoverage.suspensionCheckedFromApi -ne
            28 -or
        [int]$nativeReport.androidSignalCoverage.blockedStatusCheckedFromApi -ne
            29 -or
        $nativeReport.androidSignalCoverage.unavailablePreApiSignalsClaimed -ne
            $false) {
    throw 'Android gateway native signal-coverage report is invalid.'
}
foreach ($checkName in @('hostStateUnitTest','nativeConcurrentSnapshotTest',
        'javaFailClosedContract',
        'javaExactNetworkHandleContract','javaCellularTransportRejected',
        'sourceSocketAndLoggingReferenceAudit',
        'allRequiredAbisBuilt','elf16KiBLoadAlignment',
        'exactAbiExportSurface','exactDynamicUndefinedSymbolAllowlist',
        'gnuRelro','bindNow')) {
    if ($nativeReport.checks.$checkName -cne 'pass') {
        throw 'Android gateway native build checks are incomplete.'
    }
}
foreach ($requiredAbi in $requiredAbis) {
    $nativeArtifact =
        $nativeReport.artifacts.PSObject.Properties[$requiredAbi].Value
    $packagedArtifact =
        $apkReport.androidGatewayDiscovery.packagedArtifacts.PSObject.Properties[
            $requiredAbi].Value
    $actualUndefinedSymbols = @($nativeArtifact.dynamicUndefinedSymbols |
        Sort-Object)
    $expectedUndefinedSymbols = @($requiredUndefinedSymbols[$requiredAbi])
    if ($nativeArtifact.gnuRelro -ne $true -or
            [int]$nativeArtifact.dynamicUndefinedSymbolCount -ne
                $expectedUndefinedSymbols.Count -or
            $actualUndefinedSymbols.Count -ne
                $expectedUndefinedSymbols.Count -or
            -not (Test-ExactSet $expectedUndefinedSymbols `
                $actualUndefinedSymbols) -or
            -not (Test-Sha256 $nativeArtifact.sha256) -or
            [string]$packagedArtifact.sha256 -cne
                [string]$nativeArtifact.sha256 -or
            [long]$packagedArtifact.bytes -ne [long]$nativeArtifact.bytes) {
        throw 'Android gateway packaged native security metadata is invalid.'
    }
}
if ($apkReport.applicationId -cne $applicationId -or
        $apkReport.artifactKind -cne 'gateway-discovery-engineering-probe' -or
        $apkReport.engineeringProbe -ne $true -or
        $apkReport.internetPermission -ne $false -or
        $apkReport.accessNetworkStatePermission -ne $true -or
        $apkReport.signed -ne $true -or
        $apkReport.androidGatewayDiscovery.bundled -ne $true -or
        $apkReport.androidGatewayDiscovery.status -cne
            'engineering-foundation' -or
        $apkReport.androidGatewayDiscovery.productionReady -ne $false -or
        $apkReport.androidGatewayDiscovery.networkTrafficSent -ne $false -or
        $apkReport.androidGatewayDiscovery.addressesRecorded -ne $false -or
        $apkReport.androidGatewayDiscovery.bridgeClass -cne
            'com.thepictureshop.net.GatewayDiscoveryBridge' -or
        $apkReport.androidGatewayDiscovery.bridgeClassPackaged -ne $true -or
        [int]$apkReport.androidGatewayDiscovery.abiVersion -ne 2 -or
        [int]$apkReport.androidGatewayDiscovery.minAndroidApi -ne 26 -or
        $apkReport.androidGatewayDiscovery.trackedAndStagedSourceMatchNativeReport -ne
            $true -or
        $apkReport.androidGatewayDiscovery.trackedSourceStableThroughBuild -ne
            $true -or
        $apkReport.androidGatewayDiscovery.stagedSourceStableThroughBuild -ne
            $true -or
        $apkReport.androidGatewayDiscovery.packagedBridgeClassAndNativeMethodsVerified -ne
            $true -or
        $apkReport.androidGatewayDiscovery.packagedLifecycleHooksVerified -ne
            $true -or
        $apkReport.androidGatewayDiscovery.packagedImplementationReferencesVerified -ne
            $true -or
        $apkReport.androidGatewayDiscovery.packagedCellularRejectionVerified -ne
            $true -or
        $apkReport.androidGatewayDiscovery.packagedForbiddenSocketAndLoggingReferencesAbsent -ne
            $true -or
        $apkReport.androidGatewayDiscovery.nativeArtifactSecurityMetadataVerified -ne
            $true -or
        -not (Test-Sha256 `
            $apkReport.androidGatewayDiscovery.trackedBridgeSourceSha256) -or
        [string]$apkReport.androidGatewayDiscovery.trackedBridgeSourceSha256 -cne
            $actualJavaBridgeSourceHash -or
        -not (Test-Sha256 `
            $apkReport.androidGatewayDiscovery.stagedBridgeSourceSha256) -or
        [string]$apkReport.androidGatewayDiscovery.stagedBridgeSourceSha256 -cne
            $actualJavaBridgeSourceHash -or
        -not (Test-Sha256 `
            $apkReport.androidGatewayDiscovery.nativeReportTrackedBridgeSourceSha256) -or
        [string]$apkReport.androidGatewayDiscovery.nativeReportTrackedBridgeSourceSha256 -cne
            $actualJavaBridgeSourceHash -or
        -not (Test-Sha256 $apkReport.sha256) -or
        [string]$apkReport.sha256 -cne $actualApkHash -or
        -not (Test-Sha256 `
            $apkReport.androidGatewayDiscovery.buildReportSha256) -or
        [string]$apkReport.androidGatewayDiscovery.buildReportSha256 -cne
            $actualNativeReportHash) {
    throw 'Android gateway probe APK report validation failed.'
}

if ($DeviceSerials -and $DeviceSerials.Count -gt 0) {
    $serials = @($DeviceSerials)
} else {
    $serials = @(& $adb devices 2>$null | ForEach-Object {
        $line = [string]$_
        if ($line -cmatch '^([^\s]+)\s+device$') { $Matches[1] }
    })
    if ($LASTEXITCODE -ne 0) { throw 'Connected Android device query failed.' }
}
$serials = @($serials | Sort-Object -Unique)
if ($serials.Count -lt 1) { throw 'No authorized Android device is connected.' }
foreach ($serial in $serials) { Assert-ValidSerial $serial }

$deviceEvidence = [System.Collections.Generic.List[object]]::new()
$allDevicesPassed = $true
foreach ($serial in $serials) {
    $model = $null
    $api = $null
    $abi = $null
    $processId = $null
    $failureCode = 'device-metadata'
    $modulesPassed = $false
    $libraryPassed = $false
    $abiPassed = $false
    $nativeSnapshotPassed = $false
    $callbackHealthyPassed = $false
    $routePassed = $false
    $revalidationPassed = $false
    $infoPassed = $false
    $failMarkerSeen = $false
    $probePassed = $false
    $processLogScoped = $false
    $preExistingPackageAbsent = $null
    $cleanupAuthorized = $false
    $forceStopAttempted = $false
    $forceStopSucceeded = $false
    $uninstallAttempted = $false
    $uninstallSucceeded = $false
    $cleanupPassed = $false
    try {
        $model = Get-AdbProperty $serial 'ro.product.model' `
            'Android model query failed.'
        $apiText = Get-AdbProperty $serial 'ro.build.version.sdk' `
            'Android API query failed.'
        $abi = Get-AdbProperty $serial 'ro.product.cpu.abi' `
            'Android ABI query failed.'
        if ($model.Length -lt 1 -or $model.Length -gt 96 -or
                $model -cnotmatch '^[A-Za-z0-9._ +()-]+$' -or
                $apiText -cnotmatch '^[0-9]{1,3}$' -or
                $supportedDeviceAbis -cnotcontains $abi) {
            throw 'Connected Android device metadata is unsupported.'
        }
        $api = [int]$apiText
        if ($api -lt 26) {
            throw 'Physical gateway discovery requires Android API 26 or newer.'
        }

        $failureCode = 'preexisting-package-check'
        $preExistingPackageAbsent = Test-PackageAbsent $serial
        if (-not $preExistingPackageAbsent) {
            throw 'A pre-existing or unverifiable gateway probe package was preserved.'
        }
        # From this point onward the runner owns any package with this ID,
        # including a partial result left by a failed install attempt.
        $cleanupAuthorized = $true

        $failureCode = 'install'
        if (-not (Invoke-AdbDiscard $serial @('install',$apkPath))) {
            throw 'Android gateway probe installation failed.'
        }

        $failureCode = 'launch'
        if (-not (Invoke-AdbDiscard $serial @(
                    'shell','am','start','-W','-n',$activity))) {
            throw 'Android gateway probe launch failed.'
        }
        $processId = Get-ProbeProcessId $serial
        $processLogScoped = $true

        $failureCode = 'probe-timeout'
        $deadline = [DateTime]::UtcNow.AddSeconds($pollTimeoutSeconds)
        do {
            $codes = @(Read-ProbeMarkerCodes $serial $processId)
            $infoPassed = $infoPassed -or $codes -contains 'info'
            $modulesPassed = $modulesPassed -or $codes -contains 'modules'
            $libraryPassed = $libraryPassed -or $codes -contains 'library'
            $abiPassed = $abiPassed -or $codes -contains 'abi'
            $nativeSnapshotPassed = $nativeSnapshotPassed -or
                $codes -contains 'native-snapshot'
            $callbackHealthyPassed = $callbackHealthyPassed -or
                $codes -contains 'callback-healthy'
            $routePassed = $routePassed -or $codes -contains 'route'
            $revalidationPassed = $revalidationPassed -or
                $codes -contains 'revalidation'
            $failMarkerSeen = $failMarkerSeen -or $codes -contains 'fail'
            if ($failMarkerSeen) {
                $failureCode = 'probe-fail-marker'
                break
            }
            if ($codes -contains 'ok') {
                $probePassed = $infoPassed -and $modulesPassed -and
                    $libraryPassed -and $abiPassed -and
                    $nativeSnapshotPassed -and $callbackHealthyPassed -and
                    $routePassed -and $revalidationPassed
                $failureCode = if ($probePassed) {
                    $null
                } else {
                    'incomplete-marker-set'
                }
                break
            }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $deadline)
    } catch {
        if (-not $failureCode) { $failureCode = 'device-operation' }
    } finally {
        if ($cleanupAuthorized) {
            $forceStopAttempted = $true
            try {
                $forceStopSucceeded = Invoke-AdbDiscard $serial @(
                    'shell','am','force-stop',$applicationId)
            } catch { $forceStopSucceeded = $false }
            $uninstallAttempted = $true
            try {
                $uninstallSucceeded = Invoke-AdbDiscard $serial @(
                    'uninstall',$applicationId)
            } catch { $uninstallSucceeded = $false }
            try { $cleanupPassed = Test-PackageAbsent $serial }
            catch { $cleanupPassed = $false }
        }
        $processId = $null
    }

    $callbackFailure = -not $callbackHealthyPassed
    $passed = $probePassed -and -not $callbackFailure -and $cleanupPassed
    if ($cleanupAuthorized -and -not $cleanupPassed) {
        $failureCode = 'cleanup'
    }
    if (-not $passed) { $allDevicesPassed = $false }
    $deviceEvidence.Add([ordered]@{
        model = $model
        api = $api
        abi = $abi
        failureCode = $failureCode
        luaModulesLoaded = $modulesPassed
        nativeLibraryLoaded = $libraryPassed
        nativeAbiVerified = $abiPassed
        nativeSnapshot = $nativeSnapshotPassed
        callbackFailure = $callbackFailure
        routeSnapshot = $routePassed
        immediateRevalidation = $revalidationPassed
        processScopedLogRead = $processLogScoped
        noInternetPermission = $true
        preExistingPackageAbsent = $preExistingPackageAbsent
        cleanupAuthorized = $cleanupAuthorized
        unownedPackageMutationAttempted = $false
        forceStopAttempted = $forceStopAttempted
        forceStopSucceeded = $forceStopSucceeded
        uninstallAttempted = $uninstallAttempted
        uninstallSucceededOrPackageAlreadyAbsent =
            ($uninstallSucceeded -or $cleanupPassed)
        packageRemoved = $cleanupPassed
        passed = $passed
    })
}

$evidence = [ordered]@{
    schemaVersion = 1
    status = if ($allDevicesPassed) { 'pass' } else { 'fail' }
    productionReady = $false
    readOnly = $true
    networkTrafficSent = $false
    addressesRecorded = $false
    networkIdentifiersRecorded = $false
    globalLogCleared = $false
    processScopedLogsOnly = $true
    apk = [ordered]@{
        sha256 = $actualApkHash
        internetPermission = $false
        accessNetworkStatePermission = $true
        gatewayBridgePackaged = $true
        gatewayLifecycleHooksVerified = $true
        gatewayImplementationReferencesVerified = $true
        gatewayCellularRejectionVerified = $true
        gatewayForbiddenSocketAndLoggingReferencesAbsent = $true
    }
    native = [ordered]@{
        abiVersion = 2
        minAndroidApi = 26
        reportSha256 = $actualNativeReportHash
        trackedJavaBridgeSourceSha256 = $actualJavaBridgeSourceHash
        trackedJavaBridgeSourceMatchesNativeReport = $true
        gnuRelro = $true
        exactDynamicUndefinedSymbolAllowlist = $true
        staticAbiCoverage = $requiredAbis
    }
    deviceCount = $deviceEvidence.Count
    devices = $deviceEvidence
}
Write-Evidence $evidence

if (-not $allDevicesPassed) {
    throw 'Android gateway discovery probe failed; redacted evidence was written.'
}
Write-Output 'TPS_ANDROID_GATEWAY_DISCOVERY_RUNNER_OK'
Write-Output "REPORT=$evidencePath"
