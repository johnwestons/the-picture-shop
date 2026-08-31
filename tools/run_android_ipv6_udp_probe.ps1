[CmdletBinding()]
param(
    [ValidateScript({ $_ -eq 0 -or ($_ -ge 20000 -and $_ -le 60999) })]
    [int]$Port = 0,
    [ValidateRange(20,60)][int]$TimeoutSeconds = 42
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$adb = Join-Path $projectRoot 'output\mobile\tooling\android-sdk\platform-tools\adb.exe'
$builder = Join-Path $PSScriptRoot 'build_android_apk.ps1'
$sourceRoot = Join-Path $projectRoot 'native\crypto\tests\love_ipv6_udp_probe'
$evidenceRoot = Join-Path $projectRoot 'output\native-crypto\device-tests'
$evidencePath = Join-Path $evidenceRoot 'android_two_device_ipv6_udp_probe_report.json'
$evidencePendingPath = Join-Path $evidenceRoot 'android_two_device_ipv6_udp_probe_report.pending.json'
$hostPackage = 'com.thepictureshop.ipv6_udp_probe.host'
$clientPackage = 'com.thepictureshop.ipv6_udp_probe.client'
$ephemeralParent = [System.IO.Path]::GetFullPath(
    (Join-Path ([System.IO.Path]::GetTempPath()) 'ThePictureShop\ipv6-udp'))
$ephemeralRoot = $null
$hostDevice = $null
$clientDevice = $null
$hostProcess = $null
$clientProcess = $null
$stage = 'preflight'
$failureStage = $null
$result = 'infrastructure_failure'
$hostReady = $false
$clientReady = $false
$clientSent = $false
$hostOk = $false
$clientOk = $false
$runId = $null
$networkBefore = $false
$networkAfter = $false
$packagesAbsent = $false
$sensitiveArtifactsRemoved = $false

if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'Android platform tools are not available.'
}
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw 'The Android APK builder is missing.'
}
foreach ($requiredSource in @('main.lua','conf.lua')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $requiredSource) -PathType Leaf)) {
        throw 'The IPv6 UDP diagnostic source is incomplete.'
    }
}

function Invoke-AdbText {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string[]]$CommandArguments
    )
    $text = (& $adb -s $Serial @CommandArguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'An Android diagnostic command failed.' }
    return $text
}

function Invoke-AdbBestEffort {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string[]]$CommandArguments
    )
    $text = (& $adb -s $Serial @CommandArguments 2>&1 | Out-String).Trim()
    return [pscustomobject]@{ exitCode = $LASTEXITCODE; output = $text }
}

function Get-ConnectedDevices {
    $serials = @(& $adb devices | Select-Object -Skip 1 |
        Where-Object { $_ -match "\tdevice$" } |
        ForEach-Object { ($_ -split '\s+')[0] })
    $devices = @()
    foreach ($serial in $serials) {
        if ($serial -notmatch '^[A-Za-z0-9._:-]{1,128}$') {
            throw 'An Android device reported an unsafe serial identifier.'
        }
        $sdk = 0
        $sdkText = Invoke-AdbText -Serial $serial -CommandArguments @(
            'shell','getprop','ro.build.version.sdk')
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

function Test-CellularInterface {
    param([AllowNull()][string]$Name)
    return $null -ne $Name -and
        $Name -match '^(?:rmnet|ccmni|pdp|wwan)[A-Za-z0-9_.-]*$'
}

function Get-DefaultIpv6Interface {
    param([Parameter(Mandatory=$true)][string]$Serial)
    # Android policy routing often leaves `route show default` empty even
    # though a per-network IPv6 default is active. A route lookup is local
    # kernel inspection only; the documentation address is never contacted.
    $route = Invoke-AdbText -Serial $Serial -CommandArguments @(
        'shell','ip','-6','route','get','2001:db8::1')
    $match = [regex]::Match($route,'(?:^|\s)dev\s+([A-Za-z0-9_.-]+)(?:\s|$)')
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value
}

function Get-WifiIpv4 {
    param([Parameter(Mandatory=$true)][string]$Serial)
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-o','-4','addr','show','dev','wlan0')
    if ($query.exitCode -ne 0) { return $null }
    $match = [regex]::Match($query.output,'\binet\s+([0-9]+(?:\.[0-9]+){3})/')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Test-GlobalIpv6 {
    param([Parameter(Mandatory=$true)][string]$Address)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address,[ref]$parsed) -or
            $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6 -or
            [System.Net.IPAddress]::IsLoopback($parsed) -or
            $parsed.IsIPv6LinkLocal -or $parsed.IsIPv6SiteLocal -or $parsed.IsIPv6Multicast) {
        return $false
    }
    $bytes = $parsed.GetAddressBytes()
    if ($bytes.Length -ne 16 -or (($bytes[0] -band 0xE0) -ne 0x20)) {
        return $false
    }
    # Exclude special-purpose ranges that sit inside 2000::/3 and are not
    # usable native Internet candidates for this probe.
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and
            $bytes[2] -eq 0x0d -and $bytes[3] -eq 0xb8) { return $false }
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and
            $bytes[2] -eq 0x00 -and ($bytes[3] -eq 0x00 -or
                $bytes[3] -eq 0x02 -or
                ($bytes[3] -band 0xf0) -in @(0x10,0x20,0x30))) { return $false }
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x02) { return $false }
    if ($bytes[0] -eq 0x3f -and $bytes[1] -eq 0xff -and
            ($bytes[2] -band 0xf0) -eq 0x00) { return $false }
    return $true
}

function Get-StableGlobalIpv6 {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Interface
    )
    if ($Interface -notmatch '^[A-Za-z0-9_.-]+$') { return $null }
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-6','-o','addr','show','dev',$Interface,'scope','global')
    if ($query.exitCode -ne 0) { return $null }
    $candidates = @()
    foreach ($line in @($query.output -split "`r?`n")) {
        $match = [regex]::Match($line,'\binet6\s+([0-9A-Fa-f:]+)/([0-9]{1,3})\b')
        $invalidState = $line -match
            '(?:^|\s)(?:tentative|dadfailed|deprecated)(?:\s|$)'
        if ($match.Success -and -not $invalidState -and
                (Test-GlobalIpv6 -Address $match.Groups[1].Value)) {
            $candidates += [pscustomobject]@{
                address = $match.Groups[1].Value.ToLowerInvariant()
                temporary = $line -match '(?:^|\s)temporary(?:\s|$)'
            }
        }
    }
    $selected = $candidates | Sort-Object temporary | Select-Object -First 1
    if ($null -eq $selected) { return $null }
    return $selected.address
}

function Test-PortAvailable {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][int]$CandidatePort
    )
    $sockets = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ss','-lun')
    if ($sockets.exitCode -ne 0 -or
            $sockets.output -match 'not found|Permission denied|Cannot open') {
        $sockets = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
            'shell','netstat','-anu')
    }
    if ($sockets.exitCode -ne 0) {
        throw 'The host phone cannot prove that the candidate UDP port is free.'
    }
    return $sockets.output -notmatch "(?m):$CandidatePort(?:\s|$)"
}

function Test-PackageAbsent {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package
    )
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','pm','list','packages','--user','0',$Package)
    return $query.exitCode -eq 0 -and [string]::IsNullOrWhiteSpace($query.output)
}

function Remove-ProbePackages {
    foreach ($device in @($hostDevice,$clientDevice)) {
        if ($null -eq $device) { continue }
        foreach ($package in @($hostPackage,$clientPackage)) {
            Invoke-AdbBestEffort -Serial $device.serial -CommandArguments @(
                'shell','am','force-stop',$package) | Out-Null
            Invoke-AdbBestEffort -Serial $device.serial -CommandArguments @(
                'uninstall',$package) | Out-Null
        }
    }
}

function Install-Probe {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Apk
    )
    $installed = Invoke-AdbText -Serial $Serial -CommandArguments @('install','-r',$Apk)
    if ($installed -notmatch '(?m)^Success\s*$') {
        throw 'A diagnostic APK did not install.'
    }
}

function Get-PackageProcess {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package
    )
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
            'shell','pidof',$Package)
        if ($query.exitCode -eq 0 -and $query.output -match '^\d+$') {
            return $query.output
        }
        Start-Sleep -Milliseconds 100
    }
    return $null
}

function Get-ProcessLog {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$ProcessId
    )
    if ($ProcessId -notmatch '^\d+$') { return '' }
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','logcat',"--pid=$ProcessId",'-d','-v','brief')
    if ($query.exitCode -ne 0) { return '' }
    return $query.output
}

function Assert-SafeEphemeralRoot {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parentPrefix = $ephemeralParent.TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($parentPrefix,
            [System.StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path $fullPath -Leaf) -notmatch '^[0-9a-f]{32}$') {
        throw 'Refusing an unexpected IPv6-probe temporary path.'
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
            throw 'Refusing a reparse point in the IPv6-probe temporary path.'
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
    if (-not (Test-Path -LiteralPath $fullPath)) { return }
    $rootPrefix = $fullPath.TrimEnd('\') + '\'
    $links = @(Get-ChildItem -LiteralPath $fullPath -Recurse -Force |
        Where-Object {
            ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        } | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($link in $links) {
        $linkPath = [System.IO.Path]::GetFullPath($link.FullName)
        if (-not $linkPath.StartsWith($rootPrefix,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a link outside the IPv6-probe temporary root.'
        }
        Remove-Item -LiteralPath $linkPath -Force
    }
    if (@(Get-ChildItem -LiteralPath $fullPath -Recurse -Force |
            Where-Object {
                ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            }).Count -ne 0) {
        throw 'A reparse point remains in the IPv6-probe temporary root.'
    }
    Remove-Item -LiteralPath $fullPath -Recurse -Force
}

function New-ProbePackage {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('host','client')][string]$Role,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$Token,
        [Parameter(Mandatory=$true)][string]$HostAddress
    )
    $stageRoot = Join-Path $ephemeralRoot "package-$Role"
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'main.lua') `
        -Destination (Join-Path $stageRoot 'main.lua')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'conf.lua') `
        -Destination (Join-Path $stageRoot 'conf.lua')
    $packagedAddress = if ($Role -ceq 'client') { $HostAddress } else { 'redacted' }
    $config = @"
return {
    role = "$Role",
    port = $Port,
    runId = "$RunId",
    token = "$Token",
    hostAddress = "$packagedAddress",
}
"@
    [System.IO.File]::WriteAllText(
        (Join-Path $stageRoot 'probe_config.lua'),
        $config,
        [System.Text.UTF8Encoding]::new($false))
    $packagePath = Join-Path $ephemeralRoot "ipv6-udp-$Role.love"
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stageRoot,
        $packagePath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false)
    return $packagePath
}

function Test-NetworkRoles {
    param([switch]$ReturnHostAddress)
    $hostInterface = Get-DefaultIpv6Interface -Serial $hostDevice.serial
    $clientInterface = Get-DefaultIpv6Interface -Serial $clientDevice.serial
    if ($hostInterface -cne 'wlan0' -or
            -not (Test-CellularInterface -Name $clientInterface) -or
            (Get-WifiIpv4 -Serial $clientDevice.serial)) {
        return $null
    }
    $hostAddress = Get-StableGlobalIpv6 -Serial $hostDevice.serial `
        -Interface $hostInterface
    $clientAddress = Get-StableGlobalIpv6 -Serial $clientDevice.serial `
        -Interface $clientInterface
    if (-not $hostAddress -or -not $clientAddress) { return $null }
    if ($ReturnHostAddress) { return $hostAddress }
    return 'verified'
}

try {
    $devices = Get-ConnectedDevices
    $hostCandidates = @($devices | Where-Object {
        $_.sdk -le 27 -and $_.abi -ceq 'armeabi-v7a'
    })
    $clientCandidates = @($devices | Where-Object {
        $_.sdk -ge 36 -and $_.abi -ceq 'arm64-v8a'
    })
    if ($hostCandidates.Count -ne 1 -or $clientCandidates.Count -ne 1) {
        throw 'Expected the prepared ARM32 Wi-Fi host and ARM64 cellular client.'
    }
    $hostDevice = $hostCandidates[0]
    $clientDevice = $clientCandidates[0]
    if ($hostDevice.serial -ceq $clientDevice.serial) {
        throw 'Host and client must be different Android devices.'
    }

    $stage = 'remove_stale_packages'
    Remove-ProbePackages
    foreach ($target in @(
        @($hostDevice.serial,$hostPackage),
        @($hostDevice.serial,$clientPackage),
        @($clientDevice.serial,$hostPackage),
        @($clientDevice.serial,$clientPackage)
    )) {
        if (-not (Test-PackageAbsent -Serial $target[0] -Package $target[1])) {
            throw 'A stale IPv6 diagnostic package could not be removed.'
        }
    }

    $stage = 'verify_separate_networks'
    $hostAddress = Test-NetworkRoles -ReturnHostAddress
    if (-not $hostAddress) {
        throw 'The phones are not on the required separate IPv6 Wi-Fi and cellular routes.'
    }
    $networkBefore = $true

    $stage = 'select_port'
    if ($Port -eq 0) {
        for ($attempt = 1; $attempt -le 32; $attempt++) {
            $candidate = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32(
                20000,61000)
            if (Test-PortAvailable -Serial $hostDevice.serial `
                    -CandidatePort $candidate) {
                $Port = $candidate
                break
            }
        }
    } elseif (-not (Test-PortAvailable -Serial $hostDevice.serial `
            -CandidatePort $Port)) {
        throw 'The selected IPv6 UDP port is already in use.'
    }
    if ($Port -lt 20000 -or $Port -gt 60999) {
        throw 'No free IPv6 UDP probe port was available.'
    }

    $stage = 'build_isolated_probes'
    New-Item -ItemType Directory -Path $ephemeralParent -Force | Out-Null
    $ephemeralRoot = Assert-SafeEphemeralRoot -Path (
        Join-Path $ephemeralParent ([Guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $ephemeralRoot -Force | Out-Null
    $runIdBytes = [byte[]]::new(16)
    $tokenBytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($runIdBytes)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($tokenBytes)
    $runId = [Convert]::ToHexString($runIdBytes).ToLowerInvariant()
    $escapedRunId = [regex]::Escape($runId)
    $token = [Convert]::ToHexString($tokenBytes).ToLowerInvariant()
    $packages = @{}
    foreach ($role in @('host','client')) {
        $packages[$role] = New-ProbePackage -Role $role -RunId $runId `
            -Token $token -HostAddress $hostAddress
        & $builder -PackagePath $packages[$role] -EngineeringIpv6UdpProbe `
            -Ipv6UdpProbeRole $role -SensitiveBuildRoot (Join-Path $ephemeralRoot 'mobile')
        if (-not $?) { throw 'An isolated IPv6 diagnostic APK build failed.' }
    }

    $stage = 'verify_and_install_probes'
    $artifactRoot = Join-Path $ephemeralRoot 'mobile\artifacts'
    $hostApk = Join-Path $artifactRoot 'ThePictureShop-Ipv6UdpProbe-host-engineering.apk'
    $clientApk = Join-Path $artifactRoot 'ThePictureShop-Ipv6UdpProbe-client-engineering.apk'
    foreach ($role in @('host','client')) {
        $reportPath = Join-Path $artifactRoot "ipv6-udp-probe-$role-apk-report.json"
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
            throw 'An IPv6 diagnostic APK report is missing.'
        }
        $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
        if ($report.applicationId -cne "com.thepictureshop.ipv6_udp_probe.$role" -or
                $report.engineeringProbe -ne $true -or
                $report.engineeringProbeRole -cne $role -or
                $report.internetPermission -ne $true -or
                $report.signed -ne $true -or
                $report.sixteenKbCompatible -ne $true -or
                $report.nativeCrypto.productionReady -ne $false) {
            throw 'An IPv6 diagnostic APK failed its engineering safety checks.'
        }
    }
    Install-Probe -Serial $hostDevice.serial -Apk $hostApk
    Install-Probe -Serial $clientDevice.serial -Apk $clientApk

    # The installed packages are the only remaining copies before the global
    # IPv6 listener opens. Remove the address/token-bearing local build tree.
    Remove-EphemeralRoot -Path $ephemeralRoot
    if (Test-Path -LiteralPath $ephemeralRoot) {
        throw 'The isolated IPv6 diagnostic build tree was not removed.'
    }
    $ephemeralRoot = $null
    $sensitiveArtifactsRemoved = $true
    $hostAddress = $null
    $token = $null

    $stage = 'launch_host'
    Invoke-AdbText -Serial $hostDevice.serial -CommandArguments @(
        'shell','am','start','-W','-n',
        "$hostPackage/org.love2d.android.GameActivity") | Out-Null
    $hostProcess = Get-PackageProcess -Serial $hostDevice.serial -Package $hostPackage
    if (-not $hostProcess) { throw 'The IPv6 host diagnostic did not remain active.' }
    for ($attempt = 1; $attempt -le 100; $attempt++) {
        $hostLog = Get-ProcessLog -Serial $hostDevice.serial -ProcessId $hostProcess
        if ($hostLog -match
                "TPS_IPV6_UDP_FAIL run=$escapedRunId role=host(?:\s|$)") {
            throw 'The IPv6 host diagnostic failed before opening its listener.'
        }
        if ($hostLog -match
                "TPS_IPV6_UDP_READY run=$escapedRunId role=host(?:\s|$)") {
            $hostReady = $true
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $hostReady) { throw 'The IPv6 host listener did not become ready.' }

    $stage = 'launch_client'
    Invoke-AdbText -Serial $clientDevice.serial -CommandArguments @(
        'shell','am','start','-W','-n',
        "$clientPackage/org.love2d.android.GameActivity") | Out-Null
    $clientProcess = Get-PackageProcess -Serial $clientDevice.serial -Package $clientPackage
    if (-not $clientProcess) { throw 'The IPv6 client diagnostic did not remain active.' }

    $stage = 'wait_for_ipv6_udp'
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $hostLog = Get-ProcessLog -Serial $hostDevice.serial -ProcessId $hostProcess
        $clientLog = Get-ProcessLog -Serial $clientDevice.serial -ProcessId $clientProcess
        $clientReady = $clientReady -or ($clientLog -match
            "TPS_IPV6_UDP_READY run=$escapedRunId role=client(?:\s|$)")
        $clientSent = $clientSent -or ($clientLog -match
            "TPS_IPV6_UDP_SENT run=$escapedRunId role=client(?:\s|$)")
        $hostFailed = $hostLog -match
            "TPS_IPV6_UDP_FAIL run=$escapedRunId role=host(?:\s|$)"
        $clientFailed = $clientLog -match
            "TPS_IPV6_UDP_FAIL run=$escapedRunId role=client(?:\s|$)"
        if ($hostFailed -or $clientFailed) {
            $nonTimeoutFailure = $hostLog -match
                "TPS_IPV6_UDP_FAIL run=$escapedRunId role=host stage=(?!timeout\b)" -or
                $clientLog -match
                "TPS_IPV6_UDP_FAIL run=$escapedRunId role=client stage=(?!timeout\b)"
            $result = if ($nonTimeoutFailure) { 'probe_failure' } else { 'timeout' }
            break
        }
        $hostOk = $hostLog -match
            "TPS_IPV6_UDP_OK run=$escapedRunId role=host(?:\s|$)"
        $clientOk = $clientLog -match
            "TPS_IPV6_UDP_OK run=$escapedRunId role=client(?:\s|$)"
        if ($hostOk -and $clientOk) {
            $result = 'pass'
            break
        }
        Start-Sleep -Milliseconds 250
    }
    if ($result -notin @('pass','probe_failure','timeout')) { $result = 'timeout' }

    $stage = 'verify_separate_networks_after'
    $networkAfter = (Test-NetworkRoles) -ceq 'verified'
    if (-not $networkAfter -and $result -ceq 'pass') {
        $result = 'network_changed'
    }
}
catch {
    $failureStage = $stage
}
finally {
    try { Remove-ProbePackages } catch { }
    try {
        if ($ephemeralRoot) { Remove-EphemeralRoot -Path $ephemeralRoot }
    } catch { }
    $sensitiveArtifactsRemoved = $sensitiveArtifactsRemoved -or
        (-not $ephemeralRoot) -or (-not (Test-Path -LiteralPath $ephemeralRoot))
    if ($null -ne $hostDevice -and $null -ne $clientDevice) {
        $packagesAbsent = $true
        foreach ($target in @(
            @($hostDevice.serial,$hostPackage),
            @($hostDevice.serial,$clientPackage),
            @($clientDevice.serial,$hostPackage),
            @($clientDevice.serial,$clientPackage)
        )) {
            try {
                if (-not (Test-PackageAbsent -Serial $target[0] -Package $target[1])) {
                    $packagesAbsent = $false
                }
            } catch { $packagesAbsent = $false }
        }
    }
}

if ($failureStage) { $result = 'infrastructure_failure' }
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$evidence = [ordered]@{
    artifactKind = 'android-two-device-ipv6-udp-reachability-probe'
    engineeringOnly = $true
    productionReady = $false
    encryptedGameTransport = $false
    result = $result
    failureStage = $failureStage
    port = if ($Port -ge 20000 -and $Port -le 60999) { $Port } else { $null }
    devices = [ordered]@{
        hostModel = if ($hostDevice) { $hostDevice.model } else { $null }
        clientModel = if ($clientDevice) { $clientDevice.model } else { $null }
        hostIpv6UdpReady = $hostReady
        clientIpv6UdpReady = $clientReady
    }
    network = [ordered]@{
        separateWifiAndCellularBefore = $networkBefore
        separateWifiAndCellularAfter = $networkAfter
        hostGlobalIpv6Available = $networkBefore
        clientGlobalIpv6Available = $networkBefore
        endpointRecorded = $false
        publicIpv6Recorded = $false
    }
    exchange = [ordered]@{
        clientDatagramSendAccepted = $clientSent
        hostReceivedAuthenticatedToken = $hostOk
        clientReceivedAuthenticatedReply = $clientOk
    }
    cleanup = [ordered]@{
        diagnosticPackagesAbsent = $packagesAbsent
        localSensitiveArtifactsRemoved = $sensitiveArtifactsRemoved
    }
    interpretation = if ($result -ceq 'pass') {
        'Raw direct IPv6 UDP is reachable; this does not yet prove encrypted game transport.'
    } elseif ($result -ceq 'timeout' -and $hostReady -and $clientReady) {
        'Both IPv6 sockets initialized, but no authenticated exchange was observed; this does not identify where packets were lost.'
    } else {
        'The probe did not reach a network-valid conclusion.'
    }
    createdUtc = [DateTime]::UtcNow.ToString('o')
}
[System.IO.File]::WriteAllText(
    $evidencePendingPath,
    ($evidence | ConvertTo-Json -Depth 8) + "`n",
    [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $evidencePendingPath -Destination $evidencePath -Force

Write-Output "TPS_IPV6_UDP_PROBE_RESULT=$result"
Write-Output "HOST_IPV6_UDP_READY=$hostReady"
Write-Output "CLIENT_IPV6_UDP_READY=$clientReady"
Write-Output "CLIENT_DATAGRAM_SENT=$clientSent"
Write-Output "SEPARATE_NETWORKS_VERIFIED=$($networkBefore -and $networkAfter)"
Write-Output "DIAGNOSTIC_PACKAGES_ABSENT=$packagesAbsent"
Write-Output "SENSITIVE_ARTIFACTS_REMOVED=$sensitiveArtifactsRemoved"
if ($Port -ge 20000 -and $Port -le 60999) { Write-Output "PROBE_PORT=$Port" }
Write-Output "PUBLIC_IPV6_RECORDED=False"
if ($result -cne 'pass') { exit 2 }
