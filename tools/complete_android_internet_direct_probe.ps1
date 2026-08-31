[CmdletBinding()]
param(
    [ValidateRange(45,180)][int]$TimeoutSeconds = 75
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$adb = Join-Path $projectRoot 'output\mobile\tooling\android-sdk\platform-tools\adb.exe'
$stateRoot = Join-Path $projectRoot 'output\native-crypto\probe\android\internet-direct'
$statePath = Join-Path $stateRoot 'active-state.json'
$stateTemporaryPath = Join-Path $stateRoot 'active-state.pending.json'
$evidenceRoot = Join-Path $projectRoot 'output\native-crypto\device-tests'
$evidencePath = Join-Path $evidenceRoot 'android_two_device_internet_direct_probe_report.json'
$hostPackage = 'com.thepictureshop.direct_probe.host'
$clientPackage = 'com.thepictureshop.direct_probe.client'

if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'Android platform tools are not available.'
}
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw 'No prepared or cleanup-pending Internet Direct probe is active.'
}

function Invoke-AdbText {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string[]]$CommandArguments
    )
    $result = (& $adb -s $Serial @CommandArguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'An Android diagnostic command failed.' }
    return $result
}

function Invoke-AdbBestEffort {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string[]]$CommandArguments
    )
    $result = (& $adb -s $Serial @CommandArguments 2>&1 | Out-String).Trim()
    return [pscustomobject]@{ exitCode = $LASTEXITCODE; output = $result }
}

function Get-ConnectedDeviceInfo {
    $serials = @(& $adb devices | Select-Object -Skip 1 |
        Where-Object { $_ -match "\tdevice$" } |
        ForEach-Object { ($_ -split '\s+')[0] })
    $devices = @()
    foreach ($serial in $serials) {
        if ($serial -notmatch '^[A-Za-z0-9._:-]{1,128}$') {
            throw 'An Android device reported an unsafe serial identifier.'
        }
        $sdkText = Invoke-AdbText -Serial $serial -CommandArguments @(
            'shell','getprop','ro.build.version.sdk')
        $sdk = 0
        if (-not [int]::TryParse($sdkText,[ref]$sdk)) {
            throw 'An Android device reported an invalid API level.'
        }
        $devices += [pscustomobject]@{
            serial = $serial
            model = Invoke-AdbText -Serial $serial -CommandArguments @(
                'shell','getprop','ro.product.model')
            sdk = $sdk
            abi = Invoke-AdbText -Serial $serial -CommandArguments @(
                'shell','getprop','ro.product.cpu.abi')
        }
    }
    return @($devices)
}

function Get-WifiIpv4 {
    param([Parameter(Mandatory=$true)][string]$Serial)
    $result = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-o','-4','addr','show','dev','wlan0')
    if ($result.exitCode -ne 0) { return $null }
    $match = [regex]::Match($result.output,'\binet\s+([0-9]+(?:\.[0-9]+){3})/')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Get-DefaultRouteInterface {
    param([Parameter(Mandatory=$true)][string]$Serial)
    $route = Invoke-AdbText -Serial $Serial -CommandArguments @(
        'shell','ip','-o','-4','route','get','1.1.1.1')
    $match = [regex]::Match($route,'(?:^|\s)dev\s+([A-Za-z0-9_.-]+)(?:\s|$)')
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value
}

function Test-PrivateIpv4 {
    param([Parameter(Mandatory=$true)][string]$Address)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address,[ref]$parsed)) { return $false }
    $bytes = $parsed.GetAddressBytes()
    return $bytes.Length -eq 4 -and ($bytes[0] -eq 10 -or
        ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168))
}

function Test-CellularInterface {
    param([AllowNull()][string]$Name)
    return $null -ne $Name -and
        $Name -match '^(?:rmnet|ccmni|pdp|wwan)[A-Za-z0-9_.-]*$'
}

function Get-PackageLog {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package
    )
    $pidText = Invoke-AdbText -Serial $Serial -CommandArguments @(
        'shell','pidof',$Package)
    if ($pidText -notmatch '^\d+$') { return $null }
    return Invoke-AdbText -Serial $Serial -CommandArguments @(
        'shell','logcat',"--pid=$pidText",'-d','-v','brief')
}

function Get-PackageLogForPid {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$ProcessId
    )
    if ($ProcessId -notmatch '^\d+$') { throw 'A probe process ID is invalid.' }
    return Invoke-AdbText -Serial $Serial -CommandArguments @(
        'shell','logcat',"--pid=$ProcessId",'-d','-v','brief')
}

function Test-PackageAbsent {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package
    )
    $result = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','pm','list','packages','--user','0',$Package)
    if ($result.exitCode -ne 0) { return $false }
    return [string]::IsNullOrWhiteSpace($result.output)
}

function Test-DeviceOnline {
    param([Parameter(Mandatory=$true)][string]$Serial)
    $result = (& $adb -s $Serial get-state 2>&1 | Out-String).Trim()
    return $LASTEXITCODE -eq 0 -and $result -ceq 'device'
}

function Test-PortReleased {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][int]$Port
    )
    $result = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ss','-lun')
    if ($result.exitCode -ne 0 -or
            $result.output -match 'not found|Permission denied|Cannot open') {
        $result = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
            'shell','netstat','-anu')
    }
    if ($result.exitCode -ne 0) { return $null }
    return $result.output -notmatch "(?m):$Port(?:\s|$)"
}

function Write-StateAtomically {
    param([Parameter(Mandatory=$true)]$Value)
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    [System.IO.File]::WriteAllText(
        $stateTemporaryPath,
        ($Value | ConvertTo-Json -Depth 10) + "`n",
        [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $stateTemporaryPath -Destination $statePath -Force
}

$state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
$stateStatus = if ($state.PSObject.Properties.Name -contains 'status') {
    [string]$state.status
} else { 'prepared' }
$port = [int]$state.port
$runId = [string]$state.runId
$routerRuleName = [string]$state.routerRuleName
if ($state.artifactKind -cne 'active-android-internet-direct-probe' -or
        $state.version -ne 2 -or $state.productionReady -ne $false -or
        $state.publicAddressRecorded -ne $false -or
        $state.endpointRecordedInReport -ne $false -or
        $state.endpointEmbeddedInInstalledClient -ne $true -or
        $state.localSensitiveArtifactsRemoved -ne $true -or
        $stateStatus -notin @('prepared','cleanup_pending') -or
        $runId -notmatch '^[0-9a-f]{32}$' -or
        $port -lt 20000 -or $port -gt 60999 -or
        $routerRuleName -cne "TPS Direct $port" -or
        [string]$state.host.serial -notmatch '^[A-Za-z0-9._:-]{1,128}$' -or
        [string]$state.client.serial -notmatch '^[A-Za-z0-9._:-]{1,128}$' -or
        [string]$state.host.serial -ceq [string]$state.client.serial -or
        -not (Test-PrivateIpv4 -Address ([string]$state.host.privateAddress))) {
    throw 'The active Internet Direct probe state is invalid; no device was changed.'
}

$createdAt = [DateTimeOffset]::MinValue
$expiresAt = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse([string]$state.createdUtc,[ref]$createdAt) -or
        -not [DateTimeOffset]::TryParse([string]$state.expiresUtc,[ref]$expiresAt) -or
        $expiresAt -le $createdAt -or $expiresAt -gt $createdAt.AddMinutes(15)) {
    throw 'The probe lifetime in active state is invalid; no device was changed.'
}

$devices = Get-ConnectedDeviceInfo
$hostCandidates = @($devices | Where-Object {
    $_.sdk -le 27 -and $_.abi -ceq 'armeabi-v7a'
})
$clientCandidates = @($devices | Where-Object {
    $_.sdk -ge 36 -and $_.abi -ceq 'arm64-v8a'
})
if ($hostCandidates.Count -ne 1 -or $clientCandidates.Count -ne 1) {
    throw 'Both prepared device roles must be connected before exchange or cleanup.'
}
$hostDevice = $hostCandidates[0]
$clientDevice = $clientCandidates[0]
if ($hostDevice.serial -cne [string]$state.host.serial -or
        $clientDevice.serial -cne [string]$state.client.serial -or
        $hostDevice.model -cne [string]$state.host.model -or
        $clientDevice.model -cne [string]$state.client.model -or
        $hostDevice.sdk -ne [int]$state.host.api -or
        $clientDevice.sdk -ne [int]$state.client.api -or
        $hostDevice.abi -cne [string]$state.host.abi -or
        $clientDevice.abi -cne [string]$state.client.abi) {
    throw 'Live Android roles do not match the prepared state; no device was changed.'
}

$cleanupOnly = $stateStatus -ceq 'cleanup_pending'
$priorProgress = if ($cleanupOnly -and
        $state.PSObject.Properties.Name -contains 'progress') {
    $state.progress
} else { $null }
$exchangeSucceeded = if ($null -ne $priorProgress) {
    [bool]$priorProgress.exchangeSucceeded
} else { $false }
$hostOk = if ($null -ne $priorProgress) { [bool]$priorProgress.hostResult } else { $false }
$clientOk = if ($null -ne $priorProgress) { [bool]$priorProgress.clientResult } else { $false }
$hostRuntimeGate = if ($null -ne $priorProgress) { [bool]$priorProgress.hostRuntimeGate } else { $false }
$clientRuntimeGate = if ($null -ne $priorProgress) { [bool]$priorProgress.clientRuntimeGate } else { $false }
$networkBefore = if ($null -ne $priorProgress) { [bool]$priorProgress.networkBefore } else { $false }
$networkAfter = if ($null -ne $priorProgress) { [bool]$priorProgress.networkAfter } else { $false }
$failureStage = $null
$stage = 'verify_networks'

if (-not $cleanupOnly) {
    try {
        if ([DateTimeOffset]::UtcNow -ge $expiresAt) {
            throw 'The bounded probe lifetime expired before launch.'
        }
        $remainingSeconds = ($expiresAt - [DateTimeOffset]::UtcNow).TotalSeconds
        $requiredSeconds = [Math]::Max(120,$TimeoutSeconds + 30)
        if ($remainingSeconds -lt $requiredSeconds) {
            throw 'Less than two minutes remain in the bounded probe window; clean up and prepare a fresh run.'
        }

        $hostWifiBefore = Get-WifiIpv4 -Serial $hostDevice.serial
        $hostRouteBefore = Get-DefaultRouteInterface -Serial $hostDevice.serial
        $clientWifiBefore = Get-WifiIpv4 -Serial $clientDevice.serial
        $clientRouteBefore = Get-DefaultRouteInterface -Serial $clientDevice.serial
        $networkBefore = $hostWifiBefore -ceq [string]$state.host.privateAddress -and
            $hostRouteBefore -ceq 'wlan0' -and -not $clientWifiBefore -and
            (Test-CellularInterface -Name $clientRouteBefore)
        if (-not $networkBefore) {
            throw 'The host must remain on its prepared Wi-Fi and the client must use cellular with Wi-Fi off.'
        }

        $stage = 'verify_host'
        $hostProcess = Invoke-AdbText -Serial $hostDevice.serial -CommandArguments @(
            'shell','pidof',$hostPackage)
        $hostLog = Get-PackageLogForPid -Serial $hostDevice.serial `
            -ProcessId $hostProcess
        $escapedRunId = [regex]::Escape($runId)
        $hostRuntimeGate = $hostLog -match
            "TPS_DIRECT_PROBE_GATE_CLOSED_OK run=$escapedRunId"
        if ($hostProcess -notmatch '^\d+$' -or -not $hostRuntimeGate -or
                $hostLog -notmatch "TPS_DIRECT_PROBE_HOST_READY run=$escapedRunId port=$port address=redacted" -or
                $hostLog -match 'TPS_DIRECT_PROBE_FAIL') {
            throw 'The prepared Wi-Fi host is no longer ready.'
        }

        $stage = 'launch_fresh_cellular_client'
        Invoke-AdbBestEffort -Serial $clientDevice.serial -CommandArguments @(
            'shell','am','force-stop',$clientPackage) | Out-Null
        $oldClientPid = Invoke-AdbBestEffort -Serial $clientDevice.serial -CommandArguments @(
            'shell','pidof',$clientPackage)
        if ($oldClientPid.output -match '^\d+$') {
            throw 'The client probe did not stop cleanly before its fresh launch.'
        }
        Invoke-AdbText -Serial $clientDevice.serial -CommandArguments @(
            'shell','am','start','-W','-n',
            "$clientPackage/org.love2d.android.GameActivity") | Out-Null
        $clientProcess = $null
        for ($pidAttempt = 1; $pidAttempt -le 20; $pidAttempt++) {
            $pidResult = Invoke-AdbBestEffort -Serial $clientDevice.serial `
                -CommandArguments @('shell','pidof',$clientPackage)
            if ($pidResult.output -match '^\d+$') {
                $clientProcess = $pidResult.output
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if (-not $clientProcess) {
            throw 'The fresh cellular client process did not stay active.'
        }

        $stage = 'wait_for_encrypted_exchange'
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            $hostLog = Get-PackageLogForPid -Serial $hostDevice.serial `
                -ProcessId $hostProcess
            $clientLog = Get-PackageLogForPid -Serial $clientDevice.serial `
                -ProcessId $clientProcess
            if ($hostLog -match 'TPS_DIRECT_PROBE_FAIL' -or
                    $clientLog -match 'TPS_DIRECT_PROBE_FAIL') {
                throw 'An Android probe reported a redacted connection failure.'
            }
            $hostRuntimeGate = $hostRuntimeGate -or ($hostLog -match
                "TPS_DIRECT_PROBE_GATE_CLOSED_OK run=$escapedRunId")
            $clientRuntimeGate = $clientLog -match
                "TPS_DIRECT_PROBE_GATE_CLOSED_OK run=$escapedRunId"
            $hostOk = $hostLog -match
                "TPS_DIRECT_PROBE_OK run=$escapedRunId role=host channels=0,1,2"
            $clientOk = $clientLog -match
                "TPS_DIRECT_PROBE_OK run=$escapedRunId role=client channels=0,1,2"
            if ($hostOk -and $clientOk -and $hostRuntimeGate -and $clientRuntimeGate) {
                break
            }
            Start-Sleep -Milliseconds 500
        }
        if (-not $hostOk -or -not $clientOk -or
                -not $hostRuntimeGate -or -not $clientRuntimeGate) {
            throw 'The encrypted cellular-to-Wi-Fi exchange timed out.'
        }

        $stage = 'verify_networks_after_exchange'
        $hostWifiAfter = Get-WifiIpv4 -Serial $hostDevice.serial
        $hostRouteAfter = Get-DefaultRouteInterface -Serial $hostDevice.serial
        $clientWifiAfter = Get-WifiIpv4 -Serial $clientDevice.serial
        $clientRouteAfter = Get-DefaultRouteInterface -Serial $clientDevice.serial
        $networkAfter = $hostWifiAfter -ceq [string]$state.host.privateAddress -and
            $hostRouteAfter -ceq 'wlan0' -and -not $clientWifiAfter -and
            (Test-CellularInterface -Name $clientRouteAfter)
        if (-not $networkAfter) {
            throw 'Network roles changed during the exchange, so it is not Internet proof.'
        }
        $exchangeSucceeded = $true
    }
    catch {
        $failureStage = $stage
    }
}

# Cleanup is deliberately independent and idempotent.  Only fixed diagnostic
# package IDs are touched, and the serials came from live role discovery.
Invoke-AdbBestEffort -Serial $hostDevice.serial -CommandArguments @(
    'shell','am','force-stop',$hostPackage) | Out-Null
Invoke-AdbBestEffort -Serial $clientDevice.serial -CommandArguments @(
    'shell','am','force-stop',$clientPackage) | Out-Null
Invoke-AdbBestEffort -Serial $hostDevice.serial -CommandArguments @(
    'uninstall',$hostPackage) | Out-Null
Invoke-AdbBestEffort -Serial $clientDevice.serial -CommandArguments @(
    'uninstall',$clientPackage) | Out-Null
$hostOnlineAfter = Test-DeviceOnline -Serial $hostDevice.serial
$clientOnlineAfter = Test-DeviceOnline -Serial $clientDevice.serial
$hostProbeAbsent = $hostOnlineAfter -and
    (Test-PackageAbsent -Serial $hostDevice.serial -Package $hostPackage)
$clientProbeAbsent = $clientOnlineAfter -and
    (Test-PackageAbsent -Serial $clientDevice.serial -Package $clientPackage)
$portReleased = if ($hostOnlineAfter) {
    Test-PortReleased -Serial $hostDevice.serial -Port $port
} else { $null }

# Persist the observed exchange and package/socket cleanup before any
# interactive router-removal prompt. A terminal interruption can then resume
# cleanup without rerunning or overstating the exchange.
$prePromptState = [ordered]@{
    artifactKind = 'active-android-internet-direct-probe'
    version = 2
    status = 'cleanup_pending'
    runId = $runId
    port = $port
    routerRuleName = $routerRuleName
    createdUtc = $createdAt.ToString('o')
    expiresUtc = $expiresAt.ToString('o')
    productionReady = $false
    host = $state.host
    client = $state.client
    publicAddressRecorded = $false
    endpointRecordedInReport = $false
    endpointEmbeddedInInstalledClient = $true
    localSensitiveArtifactsRemoved = $true
    progress = [ordered]@{
        exchangeSucceeded = $exchangeSucceeded
        hostResult = $hostOk
        clientResult = $clientOk
        hostRuntimeGate = $hostRuntimeGate
        clientRuntimeGate = $clientRuntimeGate
        networkBefore = $networkBefore
        networkAfter = $networkAfter
    }
    cleanup = [ordered]@{
        packagesMayBeInstalled = -not ($hostProbeAbsent -and $clientProbeAbsent)
        hostUdpPortReleased = $portReleased
        routerRuleRemovalRequired = $true
        routerRuleRemovalConfirmed = $false
    }
}
Write-StateAtomically -Value $prePromptState

$routerRuleRemoved = [bool]$state.cleanup.routerRuleRemovalConfirmed
if (-not $routerRuleRemoved) {
    Write-Output "Remove the temporary router rule '$routerRuleName' now."
    $confirmation = Read-Host "After it is deleted, type exactly: REMOVED $port"
    $routerRuleRemoved = $confirmation -ceq "REMOVED $port"
}

$mobileConfig = Get-Content -Raw -LiteralPath
    (Join-Path $projectRoot 'mobile\config.json') | ConvertFrom-Json
$gamePackage = [string]$mobileConfig.applicationId
$hostGame = Invoke-AdbBestEffort -Serial $hostDevice.serial -CommandArguments @(
    'shell','am','start','-W','-n',
    "$gamePackage/org.love2d.android.GameActivity")
$clientGame = Invoke-AdbBestEffort -Serial $clientDevice.serial -CommandArguments @(
    'shell','am','start','-W','-n',
    "$gamePackage/org.love2d.android.GameActivity")
$gameRestored = $hostGame.exitCode -eq 0 -and $clientGame.exitCode -eq 0

$smokePasses = 0
$smokeFailures = 0
$smokeScript = Join-Path $projectRoot '.stabilization\run-smoke.ps1'
$pwshPath = (Get-Process -Id $PID).Path
& $pwshPath -NoProfile -File $smokeScript -TimeoutSeconds 120 | Out-Host
$smokeExit = $LASTEXITCODE
$smokeReport = Join-Path $projectRoot '.stabilization\smoke-report.rpt'
if (Test-Path -LiteralPath $smokeReport -PathType Leaf) {
    $smokePasses = @(Select-String -LiteralPath $smokeReport
        -Pattern '^PASS(?:\s|$)').Count
    $smokeFailures = @(Select-String -LiteralPath $smokeReport
        -Pattern '^FAIL(?:\s|$)').Count
}

$cleanupSucceeded = $hostProbeAbsent -and $clientProbeAbsent -and
    $hostOnlineAfter -and $clientOnlineAfter -and
    $portReleased -eq $true -and $routerRuleRemoved
$runtimeGateClosed = $hostRuntimeGate -and $clientRuntimeGate
$overallSuccess = $exchangeSucceeded -and $runtimeGateClosed -and
    $networkBefore -and $networkAfter -and $cleanupSucceeded -and
    $gameRestored -and $smokeExit -eq 0 -and $smokeFailures -eq 0

New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$report = [ordered]@{
    artifactKind = 'android-two-device-internet-direct-probe'
    observedUtc = [DateTime]::UtcNow.ToString('o')
    runId = $runId
    productionReady = $false
    success = $overallSuccess
    exchangeSucceeded = $exchangeSucceeded
    failureStage = $failureStage
    endpointRecordedInReport = $false
    endpointWasEmbeddedInInstalledClient = $true
    localSensitiveArtifactsRemovedBeforeListener = $true
    endpointClassification = 'global_public_unicast'
    productionGateClosedVerified = $runtimeGateClosed
    port = $port
    channels = @(0,1,2)
    networkIsolation = [ordered]@{
        verifiedBeforeExchange = $networkBefore
        verifiedAfterExchange = $networkAfter
        hostDefaultRoute = if ($networkBefore -and $networkAfter) { 'wifi' } else { $null }
        clientDefaultRoute = if ($networkBefore -and $networkAfter) { 'cellular' } else { $null }
        clientWifiAddressAbsent = $networkBefore -and $networkAfter
    }
    host = [ordered]@{
        model = $hostDevice.model
        api = $hostDevice.sdk
        abi = $hostDevice.abi
        network = if ($networkBefore -and $networkAfter) { 'wifi' } else { 'unverified' }
        result = $hostOk
    }
    client = [ordered]@{
        model = $clientDevice.model
        api = $clientDevice.sdk
        abi = $clientDevice.abi
        network = if ($networkBefore -and $networkAfter) { 'cellular' } else { 'unverified' }
        result = $clientOk
    }
    cleanup = [ordered]@{
        hostProbeAbsent = $hostProbeAbsent
        clientProbeAbsent = $clientProbeAbsent
        hostDeviceOnlineAfterCleanup = $hostOnlineAfter
        clientDeviceOnlineAfterCleanup = $clientOnlineAfter
        hostUdpPortReleased = $portReleased
        localSensitiveBuildRemoved = $true
        gameRestored = $gameRestored
        temporaryRouterRuleRemovalRequired = $true
        temporaryRouterRuleRemovalConfirmed = $routerRuleRemoved
        complete = $cleanupSucceeded
    }
    smoke = [ordered]@{
        exitCode = $smokeExit
        passes = $smokePasses
        failures = $smokeFailures
    }
}
[System.IO.File]::WriteAllText(
    $evidencePath,
    ($report | ConvertTo-Json -Depth 10) + "`n",
    [System.Text.UTF8Encoding]::new($false))

if ($cleanupSucceeded) {
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        Remove-Item -LiteralPath $statePath -Force
    }
    if (Test-Path -LiteralPath $stateTemporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $stateTemporaryPath -Force
    }
}
else {
    $pendingState = [ordered]@{
        artifactKind = 'active-android-internet-direct-probe'
        version = 2
        status = 'cleanup_pending'
        runId = $runId
        port = $port
        routerRuleName = $routerRuleName
        createdUtc = $createdAt.ToString('o')
        expiresUtc = $expiresAt.ToString('o')
        productionReady = $false
        host = $state.host
        client = $state.client
        publicAddressRecorded = $false
        endpointRecordedInReport = $false
        endpointEmbeddedInInstalledClient = $true
        localSensitiveArtifactsRemoved = $true
        progress = [ordered]@{
            exchangeSucceeded = $exchangeSucceeded
            hostResult = $hostOk
            clientResult = $clientOk
            hostRuntimeGate = $hostRuntimeGate
            clientRuntimeGate = $clientRuntimeGate
            networkBefore = $networkBefore
            networkAfter = $networkAfter
        }
        cleanup = [ordered]@{
            packagesMayBeInstalled = -not ($hostProbeAbsent -and $clientProbeAbsent)
            hostUdpPortReleased = $portReleased
            routerRuleRemovalRequired = $true
            routerRuleRemovalConfirmed = $routerRuleRemoved
        }
    }
    Write-StateAtomically -Value $pendingState
}

Write-Output "INTERNET_DIRECT_PROBE_SUCCESS=$overallSuccess"
Write-Output "EXCHANGE_SUCCEEDED=$exchangeSucceeded"
Write-Output "NETWORK_ROLES_VERIFIED=$($networkBefore -and $networkAfter)"
Write-Output "PROBE_PACKAGES_ABSENT=$($hostProbeAbsent -and $clientProbeAbsent)"
Write-Output "HOST_UDP_PORT_RELEASED=$portReleased"
Write-Output "ROUTER_RULE_REMOVAL_CONFIRMED=$routerRuleRemoved"
Write-Output 'PUBLIC_ENDPOINT_RECORDED_IN_REPORT=False'
Write-Output "EVIDENCE_REPORT=$evidencePath"
if (-not $overallSuccess) {
    throw 'The Internet Direct proof or its required cleanup is incomplete; sanitized retry state was retained when needed.'
}
