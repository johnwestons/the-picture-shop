[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$androidRoot = Join-Path $projectRoot 'output\mobile\tooling\android-sdk'
$adb = Join-Path $androidRoot 'platform-tools\adb.exe'
$builder = Join-Path $PSScriptRoot 'build_android_direct_transport_probe.ps1'
$stateRoot = Join-Path $projectRoot 'output\native-crypto\probe\android\internet-direct'
$statePath = Join-Path $stateRoot 'active-state.json'
$stateTemporaryPath = Join-Path $stateRoot 'active-state.pending.json'
$blockedEvidenceRoot = Join-Path $projectRoot 'output\native-crypto\device-tests'
$blockedEvidencePath = Join-Path $blockedEvidenceRoot `
    'android_two_device_internet_direct_probe_blocked_report.json'
$hostPackage = 'com.thepictureshop.direct_probe.host'
$clientPackage = 'com.thepictureshop.direct_probe.client'
$ephemeralParent = [System.IO.Path]::GetFullPath(
    (Join-Path ([System.IO.Path]::GetTempPath()) 'ThePictureShop\internet-direct'))
$ephemeralRoot = $null
$hostDevice = $null
$clientDevice = $null

if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'Android platform tools are not available.'
}
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw 'The Direct transport probe builder is missing.'
}
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    throw 'An Internet Direct probe is already active. Complete its cleanup before starting another.'
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

function Test-PortAvailable {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][int]$Port
    )
    $sockets = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ss','-lun')
    if ($sockets.exitCode -ne 0 -or
            $sockets.output -match 'not found|Permission denied|Cannot open') {
        $sockets = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
            'shell','netstat','-anu')
    }
    if ($sockets.exitCode -ne 0) {
        throw 'The host phone cannot prove that a candidate UDP port is free.'
    }
    return $sockets.output -notmatch "(?m):$Port(?:\s|$)"
}

function Install-Probe {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Apk
    )
    $result = Invoke-AdbText -Serial $Serial -CommandArguments @('install','-r',$Apk)
    if ($result -notmatch '(?m)^Success\s*$') { throw 'A diagnostic APK did not install.' }
}

function Test-PackageAbsent {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package
    )
    $result = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','pm','list','packages','--user','0',$Package)
    return $result.exitCode -eq 0 -and
        [string]::IsNullOrWhiteSpace($result.output)
}

function Assert-SafeEphemeralRoot {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parentPrefix = $ephemeralParent.TrimEnd('\') + '\'
    $leaf = Split-Path $fullPath -Leaf
    if (-not $fullPath.StartsWith($parentPrefix,
            [System.StringComparison]::OrdinalIgnoreCase) -or
            $leaf -notmatch '^[0-9a-f]{32}$') {
        throw 'Refusing an unexpected Internet-probe temporary path.'
    }
    $temporaryRoot = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath()).TrimEnd('\')
    $candidate = if (Test-Path -LiteralPath $fullPath) {
        $fullPath
    } else { Split-Path $fullPath -Parent }
    while ($candidate -and ($candidate -ceq $temporaryRoot -or
            $candidate.StartsWith($temporaryRoot + '\',
                [System.StringComparison]::OrdinalIgnoreCase))) {
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Refusing a reparse point in the Internet-probe temporary path.'
        }
        if ($candidate -ceq $temporaryRoot) { break }
        $candidate = Split-Path $candidate -Parent
    }
    return $fullPath
}

function Remove-EphemeralRoot {
    param([AllowNull()][string]$Path)
    if (-not $Path) { return }
    $fullPath = Assert-SafeEphemeralRoot -Path $Path
    if (Test-Path -LiteralPath $fullPath) {
        # Never let recursive removal traverse a link planted anywhere inside
        # the generated tree. Remove link objects themselves first, deepest
        # first, and prove none remain before deleting the exact GUID root.
        $rootPrefix = $fullPath.TrimEnd('\') + '\'
        $reparseItems = @(Get-ChildItem -LiteralPath $fullPath -Recurse -Force |
            Where-Object {
                ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            } | Sort-Object { $_.FullName.Length } -Descending)
        foreach ($reparseItem in $reparseItems) {
            $reparsePath = [System.IO.Path]::GetFullPath($reparseItem.FullName)
            if (-not $reparsePath.StartsWith($rootPrefix,
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Refusing to remove a link outside the Internet-probe temporary root.'
            }
            Remove-Item -LiteralPath $reparsePath -Force
        }
        $remainingLinks = @(Get-ChildItem -LiteralPath $fullPath -Recurse -Force |
            Where-Object {
                ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            })
        if ($remainingLinks.Count -ne 0) {
            throw 'A reparse point remains inside the Internet-probe temporary root.'
        }
        Remove-Item -LiteralPath $fullPath -Recurse -Force
    }
}

function Remove-FixedProbePackages {
    foreach ($device in @($hostDevice,$clientDevice)) {
        if ($null -ne $device) {
            Invoke-AdbBestEffort -Serial $device.serial -CommandArguments @(
                'shell','am','force-stop',$hostPackage) | Out-Null
            Invoke-AdbBestEffort -Serial $device.serial -CommandArguments @(
                'shell','am','force-stop',$clientPackage) | Out-Null
            Invoke-AdbBestEffort -Serial $device.serial -CommandArguments @(
                'uninstall',$hostPackage) | Out-Null
            Invoke-AdbBestEffort -Serial $device.serial -CommandArguments @(
                'uninstall',$clientPackage) | Out-Null
        }
    }
}

$devices = Get-ConnectedDeviceInfo
$hostCandidates = @($devices | Where-Object {
    $_.sdk -le 27 -and $_.abi -ceq 'armeabi-v7a'
})
$clientCandidates = @($devices | Where-Object {
    $_.sdk -ge 36 -and $_.abi -ceq 'arm64-v8a'
})
if ($hostCandidates.Count -ne 1 -or $clientCandidates.Count -ne 1) {
    throw 'Expected exactly one API-27 ARM32 host and one API-36-or-newer ARM64 client.'
}
$hostDevice = $hostCandidates[0]
$clientDevice = $clientCandidates[0]
if ($hostDevice.serial -ceq $clientDevice.serial) {
    throw 'Host and client must be different Android devices.'
}

# Fixed diagnostic package IDs are cleaned before any endpoint/key is built.
# This prevents install -r or the LÖVE game cache from reusing a stale run.
Remove-FixedProbePackages
foreach ($probeTarget in @(
    @($hostDevice.serial,$hostPackage),
    @($hostDevice.serial,$clientPackage),
    @($clientDevice.serial,$hostPackage),
    @($clientDevice.serial,$clientPackage)
)) {
    if (-not (Test-PackageAbsent -Serial $probeTarget[0] -Package $probeTarget[1])) {
        throw 'A stale diagnostic package could not be removed safely.'
    }
}

$hostWifiAddress = Get-WifiIpv4 -Serial $hostDevice.serial
$hostRouteInterface = Get-DefaultRouteInterface -Serial $hostDevice.serial
if (-not $hostWifiAddress -or -not (Test-PrivateIpv4 -Address $hostWifiAddress) -or
        $hostRouteInterface -cne 'wlan0') {
    throw 'The host phone is not using its private Wi-Fi connection.'
}
$clientWifiAddress = Get-WifiIpv4 -Serial $clientDevice.serial
$clientRouteInterface = Get-DefaultRouteInterface -Serial $clientDevice.serial
if ($clientWifiAddress -or -not (Test-CellularInterface -Name $clientRouteInterface)) {
    throw 'The client phone must have Wi-Fi off and cellular as its default IPv4 route.'
}

$port = 0
for ($attempt = 1; $attempt -le 32; $attempt++) {
    $candidatePort = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32(
        20000,61000)
    if (Test-PortAvailable -Serial $hostDevice.serial -Port $candidatePort) {
        $port = $candidatePort
        break
    }
}
if ($port -eq 0) { throw 'Could not select a free random UDP probe port.' }

$secureAddress = Read-Host 'Enter the gateway-reported WAN IPv4 address (input is hidden)' -AsSecureString
$addressPointer = [IntPtr]::Zero
$wanAddress = $null
try {
    $addressPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureAddress)
    $wanAddress = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($addressPointer)
}
finally {
    if ($addressPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($addressPointer)
    }
    $secureAddress.Dispose()
}
if (-not $wanAddress) { throw 'A WAN IPv4 address is required.' }

try {
    New-Item -ItemType Directory -Path $ephemeralParent -Force | Out-Null
    $ephemeralLeaf = [Guid]::NewGuid().ToString('N')
    $ephemeralRoot = Assert-SafeEphemeralRoot -Path `
        (Join-Path $ephemeralParent $ephemeralLeaf)
    New-Item -ItemType Directory -Path $ephemeralRoot -Force | Out-Null

    & $builder -HostAddress $wanAddress -InternetProbe -HostPort $port `
        -EphemeralRoot $ephemeralRoot | Out-Host
    if (-not $?) { throw 'The Internet Direct probe build failed.' }
    $wanAddress = $null

    $buildReportPath = Join-Path $ephemeralRoot `
        'probe\direct-transport-probe-report.json'
    if (-not (Test-Path -LiteralPath $buildReportPath -PathType Leaf)) {
        throw 'The isolated Internet Direct probe build report is missing.'
    }
    $buildReport = Get-Content -Raw -LiteralPath $buildReportPath | ConvertFrom-Json
    if ($buildReport.productionReady -ne $false -or
            $buildReport.internetProbe -ne $true -or
            $buildReport.hostAddressRecorded -ne $false -or
            $buildReport.endpointRecordedInReport -ne $false -or
            $buildReport.endpointEmbeddedInClientArtifact -ne $true -or
            $buildReport.addressRedacted -ne $true -or
            $buildReport.hostAddressScope -cne 'global_public_unicast' -or
            [int]$buildReport.port -ne $port) {
        throw 'The Internet Direct probe privacy or production gate failed.'
    }

    $hostApk = [string]$buildReport.artifacts.host.apk
    $clientApk = [string]$buildReport.artifacts.client.apk
    foreach ($apk in @($hostApk,$clientApk)) {
        $apkFullPath = [System.IO.Path]::GetFullPath($apk)
        $ephemeralPrefix = $ephemeralRoot.TrimEnd('\') + '\'
        if (-not $apkFullPath.StartsWith($ephemeralPrefix,
                [System.StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-Path -LiteralPath $apkFullPath -PathType Leaf)) {
            throw 'A diagnostic APK escaped the isolated build tree or is missing.'
        }
    }

    Install-Probe -Serial $hostDevice.serial -Apk $hostApk
    Install-Probe -Serial $clientDevice.serial -Apk $clientApk

    # Installed diagnostic apps are now the only necessary copies.  Remove
    # the key and endpoint-bearing local tree before opening the listener.
    Remove-EphemeralRoot -Path $ephemeralRoot
    if (Test-Path -LiteralPath $ephemeralRoot) {
        throw 'The isolated sensitive build tree was not removed.'
    }
    $ephemeralRoot = $null

    Invoke-AdbBestEffort -Serial $hostDevice.serial -CommandArguments @(
        'shell','am','force-stop',$hostPackage) | Out-Null
    Invoke-AdbBestEffort -Serial $clientDevice.serial -CommandArguments @(
        'shell','am','force-stop',$clientPackage) | Out-Null
    Invoke-AdbText -Serial $hostDevice.serial -CommandArguments @(
        'shell','am','start','-W','-n',
        "$hostPackage/org.love2d.android.GameActivity") | Out-Null

    $runId = [string]$buildReport.runId
    $escapedRunId = [regex]::Escape($runId)
    $hostReady = $false
    for ($attempt = 1; $attempt -le 45; $attempt++) {
        $hostLog = Get-PackageLog -Serial $hostDevice.serial -Package $hostPackage
        if ($hostLog -match 'TPS_DIRECT_PROBE_FAIL|FATAL EXCEPTION|ANR in ') {
            throw 'The Wi-Fi host probe failed before opening its listener.'
        }
        if ($hostLog -match "TPS_DIRECT_PROBE_GATE_CLOSED_OK run=$escapedRunId" -and
                $hostLog -match "TPS_DIRECT_PROBE_HOST_READY run=$escapedRunId port=$port address=redacted") {
            $hostReady = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $hostReady) { throw 'The Wi-Fi host did not reach its secure-listener marker.' }

    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    if (Test-Path -LiteralPath $stateTemporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $stateTemporaryPath -Force
    }
    $state = [ordered]@{
        artifactKind = 'active-android-internet-direct-probe'
        version = 2
        status = 'prepared'
        runId = $runId
        port = $port
        routerRuleName = "TPS Direct $port"
        createdUtc = [DateTime]::UtcNow.ToString('o')
        expiresUtc = [DateTime]::UtcNow.AddMinutes(12).ToString('o')
        productionReady = $false
        host = [ordered]@{
            serial = $hostDevice.serial
            model = $hostDevice.model
            api = $hostDevice.sdk
            abi = $hostDevice.abi
            privateAddress = $hostWifiAddress
        }
        client = [ordered]@{
            serial = $clientDevice.serial
            model = $clientDevice.model
            api = $clientDevice.sdk
            abi = $clientDevice.abi
        }
        publicAddressRecorded = $false
        endpointRecordedInReport = $false
        endpointEmbeddedInInstalledClient = $true
        localSensitiveArtifactsRemoved = $true
        cleanup = [ordered]@{
            packagesMayBeInstalled = $true
            routerRuleRemovalRequired = $true
            routerRuleRemovalConfirmed = $false
        }
    }
    [System.IO.File]::WriteAllText(
        $stateTemporaryPath,
        ($state | ConvertTo-Json -Depth 8) + "`n",
        [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $stateTemporaryPath -Destination $statePath

    $watchdog = Join-Path $PSScriptRoot 'watch_android_internet_direct_probe.ps1'
    $pwshPath = (Get-Process -Id $PID).Path
    $watchdogArguments = @(
        '-NoProfile', '-File', ('"' + $watchdog + '"'),
        '-HostSerial', $hostDevice.serial,
        '-ClientSerial', $clientDevice.serial,
        '-RunId', $runId,
        '-ExpiresUtc', ('"' + [string]$state.expiresUtc + '"')
    )
    Start-Process -FilePath $pwshPath -ArgumentList $watchdogArguments `
        -WindowStyle Hidden | Out-Null

    Write-Output 'INTERNET_DIRECT_HOST_READY=True'
    Write-Output "HOST_DEVICE=$($hostDevice.model)"
    Write-Output "HOST_PRIVATE_ADDRESS=$hostWifiAddress"
    Write-Output "UDP_PORT=$port"
    Write-Output "ROUTER_RULE_NAME=TPS Direct $port"
    Write-Output 'PUBLIC_ADDRESS_RECORDED_IN_REPORT=False'
    Write-Output 'LOCAL_SENSITIVE_BUILD_REMOVED=True'
    Write-Output 'NEXT_ACTION=Create the one displayed temporary UDP rule, then run the completion script.'
}
catch {
    $failureMessage = [string]$_.Exception.Message
    $scopeMatch = [regex]::Match($failureMessage,
        'Internet probe address is not public unicast \(scope: ([a-z_]+)\)')
    $wanAddress = $null
    Remove-FixedProbePackages
    if ($ephemeralRoot) {
        Remove-EphemeralRoot -Path $ephemeralRoot
    }
    if (Test-Path -LiteralPath $stateTemporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $stateTemporaryPath -Force
    }
    $blockedPackagesAbsent = $true
    foreach ($probeTarget in @(
        @($hostDevice.serial,$hostPackage),
        @($hostDevice.serial,$clientPackage),
        @($clientDevice.serial,$hostPackage),
        @($clientDevice.serial,$clientPackage)
    )) {
        $blockedPackagesAbsent = $blockedPackagesAbsent -and
            (Test-PackageAbsent -Serial $probeTarget[0] -Package $probeTarget[1])
    }
    if ($scopeMatch.Success) {
        New-Item -ItemType Directory -Path $blockedEvidenceRoot -Force | Out-Null
        $blockedReport = [ordered]@{
            artifactKind = 'android-two-device-internet-direct-probe-blocked'
            observedUtc = [DateTime]::UtcNow.ToString('o')
            productionReady = $false
            success = $false
            blockedBeforeBuild = $true
            blockedBeforeListener = $true
            blockedBeforeRouterRule = $true
            publicEndpointRecorded = $false
            invitationKeyGenerated = $false
            wanAddressClassification = $scopeMatch.Groups[1].Value
            blocker = 'non_public_gateway_wan_address'
            diagnosticPackagesInstalled = -not $blockedPackagesAbsent
            activeProbeStatePresent = $false
            host = [ordered]@{
                model = $hostDevice.model
                api = $hostDevice.sdk
                abi = $hostDevice.abi
                network = 'wifi'
            }
            client = [ordered]@{
                model = $clientDevice.model
                api = $clientDevice.sdk
                abi = $clientDevice.abi
                network = 'cellular'
            }
        }
        [System.IO.File]::WriteAllText(
            $blockedEvidencePath,
            ($blockedReport | ConvertTo-Json -Depth 8) + "`n",
            [System.Text.UTF8Encoding]::new($false))
    }
    throw
}
