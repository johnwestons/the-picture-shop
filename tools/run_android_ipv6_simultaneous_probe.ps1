[CmdletBinding()]
param(
    [ValidateScript({ $_ -eq 0 -or ($_ -ge 20000 -and $_ -le 60999) })]
    [int]$Port = 57842,
    [ValidateRange(20,120)][int]$TimeoutSeconds = 42,
    [switch]$EncryptedBridge
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$adb = Join-Path $projectRoot 'output\mobile\tooling\android-sdk\platform-tools\adb.exe'
$builder = Join-Path $PSScriptRoot 'build_android_apk.ps1'
$sourceRoot = Join-Path $projectRoot $(if ($EncryptedBridge) {
    'native\crypto\tests\love_ipv6_bridge_probe'
} else {
    'native\crypto\tests\love_ipv6_simultaneous_probe'
})
$evidenceRoot = Join-Path $projectRoot 'output\native-crypto\device-tests'
$evidenceName = if ($EncryptedBridge) {
    'android_two_device_ipv6_encrypted_bridge_probe_report'
} else {
    'android_two_device_ipv6_simultaneous_udp_probe_report'
}
$evidencePath = Join-Path $evidenceRoot "$evidenceName.json"
$evidencePendingPath = Join-Path $evidenceRoot "$evidenceName.pending.json"
$hostPackage = if ($EncryptedBridge) {
    'com.thepictureshop.direct_probe.host'
} else { 'com.thepictureshop.ipv6_udp_probe.host' }
$clientPackage = if ($EncryptedBridge) {
    'com.thepictureshop.direct_probe.client'
} else { 'com.thepictureshop.ipv6_udp_probe.client' }
$ephemeralParent = [System.IO.Path]::GetFullPath(
    (Join-Path ([System.IO.Path]::GetTempPath()) $(if ($EncryptedBridge) {
        'ThePictureShop\ipv6-encrypted-bridge'
    } else { 'ThePictureShop\ipv6-simultaneous' })))
$ephemeralRoot = $null
$hostDevice = $null
$clientDevice = $null
$hostProcess = $null
$clientProcess = $null
$runId = $null
$runIdBytes = $null
$tokenBytes = $null
$invitationIdBytes = $null
$guestNonceBytes = $null
$masterKeyExpression = $null
$invitationIdExpression = $null
$guestNonceExpression = $null
$stage = 'preflight'
$failureStage = $null
$probeFailureStage = $null
$result = 'infrastructure_failure'
$networkBefore = $false
$networkAfter = $false
$sourceCandidatesResolved = $false
$sourceCandidatesRevalidated = $false
$hostRouteScope = $null
$clientRouteScope = $null
$preferredModelsSelected = $false
$hostReady = $false
$clientReady = $false
$hostSent = $false
$clientSent = $false
$hostPeerHello = $false
$clientPeerHello = $false
$hostPeerAck = $false
$clientPeerAck = $false
$hostOk = $false
$clientOk = $false
$hostOpeningReady = $false
$clientOpeningReady = $false
$hostSecureConnected = $false
$clientSecureConnected = $false
$hostFragmented = $false
$clientFragmented = $false
$packagesAbsent = $false
$sensitiveArtifactsRemoved = $false
$packageCleanupException = $false
$temporaryCleanupException = $false
$cleanupVerified = $false

if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'Android platform tools are not available.'
}
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw 'The Android APK builder is missing.'
}
foreach ($requiredSource in @('main.lua','conf.lua')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $requiredSource) -PathType Leaf)) {
        throw 'The simultaneous IPv6 UDP diagnostic source is incomplete.'
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
    # Android policy routing can omit the active network from `route show
    # default`. This local route lookup does not transmit any packet.
    $route = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-6','route','get','2001:db8::1')
    if ($route.exitCode -ne 0) { return $null }
    $match = [regex]::Match(
        $route.output,'(?:^|\s)dev\s+([A-Za-z0-9_.-]+)(?:\s|$)')
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
            $parsed.AddressFamily -ne
                [System.Net.Sockets.AddressFamily]::InterNetworkV6 -or
            [System.Net.IPAddress]::IsLoopback($parsed) -or
            $parsed.IsIPv6LinkLocal -or $parsed.IsIPv6SiteLocal -or
            $parsed.IsIPv6Multicast) {
        return $false
    }
    $bytes = $parsed.GetAddressBytes()
    if ($bytes.Length -ne 16 -or (($bytes[0] -band 0xe0) -ne 0x20)) {
        return $false
    }

    # Exclude documentation, transition, benchmarking, protocol-assignment,
    # and historic ranges even though some fall inside 2000::/3.
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and
            ($bytes[2] -eq 0x00 -or $bytes[2] -eq 0x01)) { return $false }
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and
            $bytes[2] -eq 0x0d -and $bytes[3] -eq 0xb8) { return $false }
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x02) { return $false }
    if ($bytes[0] -eq 0x3f -and $bytes[1] -eq 0xfe) { return $false }
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
    foreach ($line in @($query.output -split "`r?`n")) {
        $match = [regex]::Match(
            $line,'\binet6\s+([0-9A-Fa-f:]+)/([0-9]{1,3})\b')
        $invalidState = $line -match
            '(?:^|\s)(?:temporary|tentative|optimistic|dadfailed|deprecated)(?:\s|$)'
        if ($match.Success -and -not $invalidState -and
                (Test-GlobalIpv6 -Address $match.Groups[1].Value)) {
            return $match.Groups[1].Value.ToLowerInvariant()
        }
    }
    return $null
}

function Test-DifferentIpv6Prefixes {
    param(
        [Parameter(Mandatory=$true)][string]$First,
        [Parameter(Mandatory=$true)][string]$Second
    )
    $firstAddress = [System.Net.IPAddress]::Parse($First).GetAddressBytes()
    $secondAddress = [System.Net.IPAddress]::Parse($Second).GetAddressBytes()
    for ($index = 0; $index -lt 8; $index++) {
        if ($firstAddress[$index] -ne $secondAddress[$index]) { return $true }
    }
    return $false
}

function Test-CurrentGlobalIpv6Address {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Interface,
        [Parameter(Mandatory=$true)][string]$Address
    )
    if (-not (Test-GlobalIpv6 -Address $Address) -or
            $Interface -notmatch '^[A-Za-z0-9_.-]+$') {
        return $false
    }
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-6','-o','addr','show','dev',$Interface,'scope','global')
    if ($query.exitCode -ne 0) { return $false }
    $expectedAddress = [System.Net.IPAddress]::Parse($Address)
    foreach ($line in @($query.output -split "`r?`n")) {
        $match = [regex]::Match(
            $line,'\binet6\s+([0-9A-Fa-f:]+)/[0-9]{1,3}\b')
        if ($match.Success -and $line -notmatch
                '(?:^|\s)(?:tentative|optimistic|dadfailed|deprecated)(?:\s|$)') {
            $lineAddress = $null
            if ([System.Net.IPAddress]::TryParse(
                    $match.Groups[1].Value,[ref]$lineAddress) -and
                    $expectedAddress.Equals($lineAddress)) {
                return $true
            }
        }
    }
    return $false
}

function Resolve-KernelIpv6Source {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$ExpectedInterface
    )
    if (-not (Test-GlobalIpv6 -Address $Destination) -or
            $ExpectedInterface -notmatch '^[A-Za-z0-9_.-]+$') {
        return $null
    }
    $route = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-6','route','get',$Destination)
    if ($route.exitCode -ne 0) { return $null }
    $interfaceMatch = [regex]::Match(
        $route.output,'(?:^|\s)dev\s+([A-Za-z0-9_.-]+)(?:\s|$)')
    $sourceMatch = [regex]::Match(
        $route.output,'(?:^|\s)src\s+([0-9A-Fa-f:]+)(?:\s|$)')
    if (-not $interfaceMatch.Success -or -not $sourceMatch.Success -or
            $interfaceMatch.Groups[1].Value -cne $ExpectedInterface) {
        return $null
    }
    $source = $sourceMatch.Groups[1].Value.ToLowerInvariant()
    if (-not (Test-CurrentGlobalIpv6Address -Serial $Serial `
            -Interface $ExpectedInterface -Address $source)) {
        return $null
    }
    return $source
}

function Get-DeviceNetworkProfile {
    param([Parameter(Mandatory=$true)][pscustomobject]$Device)
    $ipv6Interface = Get-DefaultIpv6Interface -Serial $Device.serial
    if (-not $ipv6Interface) { return $null }
    $address = Get-StableGlobalIpv6 -Serial $Device.serial `
        -Interface $ipv6Interface
    if (-not $address) { return $null }
    $routeScope = if ($ipv6Interface -ceq 'wlan0') {
        'wifi'
    } elseif (Test-CellularInterface -Name $ipv6Interface) {
        'cellular'
    } else {
        'other'
    }
    return [pscustomobject]@{
        device = $Device
        interface = $ipv6Interface
        routeScope = $routeScope
        stableGlobalIpv6 = $address
        wifiIpv4Present = [bool](Get-WifiIpv4 -Serial $Device.serial)
    }
}

function Select-RoleProfile {
    param(
        [Parameter(Mandatory=$true)][object[]]$Candidates,
        [Parameter(Mandatory=$true)][string]$PreferredModel,
        [Parameter(Mandatory=$true)][ValidateSet('wifi','cellular')][string]$Scope
    )
    $eligible = @($Candidates | Where-Object {
        $_.routeScope -ceq $Scope -and
        ($Scope -cne 'cellular' -or -not $_.wifiIpv4Present)
    })
    $preferred = @($eligible | Where-Object {
        $_.device.model -ceq $PreferredModel
    })
    if ($preferred.Count -eq 1) { return $preferred[0] }
    if ($eligible.Count -eq 1) { return $eligible[0] }
    return $null
}

function Test-NetworkRoles {
    param([switch]$ReturnAddresses)
    $hostInterface = Get-DefaultIpv6Interface -Serial $hostDevice.serial
    $clientInterface = Get-DefaultIpv6Interface -Serial $clientDevice.serial
    if ($hostInterface -cne 'wlan0' -or
            -not (Test-CellularInterface -Name $clientInterface) -or
            -not (Get-WifiIpv4 -Serial $hostDevice.serial) -or
            (Get-WifiIpv4 -Serial $clientDevice.serial)) {
        return $null
    }
    $hostAddress = Get-StableGlobalIpv6 -Serial $hostDevice.serial `
        -Interface $hostInterface
    $clientAddress = Get-StableGlobalIpv6 -Serial $clientDevice.serial `
        -Interface $clientInterface
    if (-not $hostAddress -or -not $clientAddress -or
            -not (Test-DifferentIpv6Prefixes -First $hostAddress -Second $clientAddress)) {
        return $null
    }
    if ($ReturnAddresses) {
        return [pscustomobject]@{
            hostAddress = $hostAddress
            clientAddress = $clientAddress
        }
    }
    return 'verified'
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
        throw 'A phone cannot prove that the candidate UDP port is free.'
    }
    return $sockets.output -notmatch "(?m):$CandidatePort(?:\s|$)"
}

function Test-PortAvailableOnBothDevices {
    param([Parameter(Mandatory=$true)][int]$CandidatePort)
    return (Test-PortAvailable -Serial $hostDevice.serial `
        -CandidatePort $CandidatePort) -and
        (Test-PortAvailable -Serial $clientDevice.serial `
            -CandidatePort $CandidatePort)
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
    $installed = Invoke-AdbText -Serial $Serial -CommandArguments @(
        'install','-r',$Apk)
    if ($installed -notmatch '(?m)^Success\s*$') {
        throw 'A diagnostic APK did not install.'
    }
}

function Get-PackageProcess {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package
    )
    for ($attempt = 1; $attempt -le 40; $attempt++) {
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

function Assert-SafeTemporaryPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $temporaryRoot = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath()).TrimEnd('\')
    if (-not $fullPath.StartsWith($temporaryRoot + '\',
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The simultaneous-probe path must remain under the temporary root.'
    }
    # Start at the closest existing ancestor. This check is safe both before
    # creating the dedicated parent and after creating the final run root.
    $candidate = $fullPath
    while ($candidate -and -not (Test-Path -LiteralPath $candidate)) {
        $candidate = Split-Path $candidate -Parent
    }
    while ($candidate -and ($candidate -ceq $temporaryRoot -or
            $candidate.StartsWith($temporaryRoot + '\',
                [System.StringComparison]::OrdinalIgnoreCase))) {
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band
                [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Refusing a reparse point in the simultaneous-probe path.'
        }
        if ($candidate -ceq $temporaryRoot) { break }
        $candidate = Split-Path $candidate -Parent
    }
    return $fullPath
}

function Assert-SafeEphemeralRoot {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fullPath = Assert-SafeTemporaryPath -Path $Path
    $parentPrefix = $ephemeralParent.TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($parentPrefix,
            [System.StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path $fullPath -Leaf) -notmatch '^[0-9a-f]{32}$') {
        throw 'Refusing an unexpected simultaneous-probe temporary path.'
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
            throw 'Refusing to remove a link outside the simultaneous-probe root.'
        }
        Remove-Item -LiteralPath $linkPath -Force
    }
    if (@(Get-ChildItem -LiteralPath $fullPath -Recurse -Force |
            Where-Object {
                ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            }).Count -ne 0) {
        throw 'A reparse point remains in the simultaneous-probe root.'
    }
    Remove-Item -LiteralPath $fullPath -Recurse -Force
}

function New-ProbePackage {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('host','client')][string]$Role,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$Token,
        [Parameter(Mandatory=$true)][string]$PeerAddress,
        [string]$LocalAddress,
        [string]$MasterKeyExpression,
        [string]$InvitationIdExpression,
        [string]$GuestNonceExpression,
        [long]$IssuedAt
    )
    $stageRoot = Join-Path $ephemeralRoot "package-$Role"
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    $sourceFiles = [ordered]@{
        'main.lua' = Join-Path $sourceRoot 'main.lua'
        'conf.lua' = Join-Path $sourceRoot 'conf.lua'
    }
    if ($EncryptedBridge) {
        $sourceFiles['src\net\address.lua'] = Join-Path $projectRoot 'src\net\address.lua'
        $sourceFiles['src\net\crypto_native.lua'] = Join-Path $projectRoot 'src\net\crypto_native.lua'
        $sourceFiles['src\net\direct_bridge.lua'] = Join-Path $projectRoot 'src\net\direct_bridge.lua'
        $sourceFiles['src\net\direct_opening.lua'] = Join-Path $projectRoot 'src\net\direct_opening.lua'
        $sourceFiles['src\net\direct_opening_code.lua'] = Join-Path $projectRoot 'src\net\direct_opening_code.lua'
        $sourceFiles['src\net\ipv6_address.lua'] = Join-Path $projectRoot 'src\net\ipv6_address.lua'
        $sourceFiles['src\net\transport_direct.lua'] = Join-Path $projectRoot 'src\net\transport_direct.lua'
        $sourceFiles['src\net\transport_enet.lua'] = Join-Path $projectRoot 'src\net\transport_enet.lua'
        $sourceFiles['src\net\transport_ipv6_bridge.lua'] = Join-Path $projectRoot 'src\net\transport_ipv6_bridge.lua'
    }
    foreach ($relativePath in $sourceFiles.Keys) {
        $sourcePath = $sourceFiles[$relativePath]
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw 'A bridge-probe source file is missing.'
        }
        $destination = Join-Path $stageRoot $relativePath
        $destinationParent = Split-Path $destination -Parent
        if (-not (Test-Path -LiteralPath $destinationParent)) {
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $sourcePath -Destination $destination -Force
    }
    if ($EncryptedBridge) {
        if (-not $LocalAddress -or -not $MasterKeyExpression -or
                -not $InvitationIdExpression -or -not $GuestNonceExpression -or
                $IssuedAt -lt 0 -or $IssuedAt -gt [uint32]::MaxValue) {
            throw 'Encrypted bridge probe configuration is incomplete.'
        }
        $overallTimeout = [Math]::Max(75,$TimeoutSeconds + 35)
        $config = @"
return {
    role = "$Role",
    runId = "$RunId",
    localAddress = "$LocalAddress",
    peerAddress = "$PeerAddress",
    outerPort = $Port,
    loopbackPort = 22122,
    issuedAt = $IssuedAt,
    lifetime = $TimeoutSeconds,
    overallTimeoutSeconds = $overallTimeout,
    masterKey = $MasterKeyExpression,
    invitationId = $InvitationIdExpression,
    guestNonce = $GuestNonceExpression,
}
"@
    } else {
        $config = @"
return {
    role = "$Role",
    port = $Port,
    runId = "$RunId",
    token = "$Token",
    peerAddress = "$PeerAddress",
    timeoutSeconds = $TimeoutSeconds,
}
"@
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $stageRoot 'probe_config.lua'),
        $config,
        [System.Text.UTF8Encoding]::new($false))
    $packagePath = Join-Path $ephemeralRoot $(if ($EncryptedBridge) {
        "ipv6-encrypted-bridge-$Role.love"
    } else { "ipv6-simultaneous-$Role.love" })
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stageRoot,
        $packagePath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false)
    $archive = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $expectedEntries = @($sourceFiles.Keys | ForEach-Object {
            ([string]$_).Replace('\','/')
        }) + 'probe_config.lua' | Sort-Object
        $actualEntries = @($archive.Entries | Where-Object {
            $_.FullName -notmatch '/$'
        } | ForEach-Object {
            $_.FullName.Replace('\','/')
        } | Sort-Object)
        if (Compare-Object $expectedEntries $actualEntries) {
            throw 'A probe package contains unexpected files.'
        }
    }
    finally { $archive.Dispose() }
    return $packagePath
}

try {
    $stage = 'select_devices_and_verify_routes'
    $devices = @(Get-ConnectedDevices)
    if ($devices.Count -lt 2) {
        throw 'Two attached Android devices are required.'
    }
    $profiles = @()
    foreach ($device in $devices) {
        $profile = Get-DeviceNetworkProfile -Device $device
        if ($profile) { $profiles += $profile }
    }
    $hostProfile = Select-RoleProfile -Candidates $profiles `
        -PreferredModel 'SM-J410G' -Scope wifi
    $clientProfile = Select-RoleProfile -Candidates $profiles `
        -PreferredModel 'SM-S938U' -Scope cellular
    if (-not $hostProfile -or -not $clientProfile -or
            $hostProfile.device.serial -ceq $clientProfile.device.serial) {
        throw 'Could not unambiguously map separate Wi-Fi and cellular phones.'
    }
    $hostDevice = $hostProfile.device
    $clientDevice = $clientProfile.device
    $preferredModelsSelected =
        $hostDevice.model -ceq 'SM-J410G' -and
        $clientDevice.model -ceq 'SM-S938U'

    $roleAddresses = Test-NetworkRoles -ReturnAddresses
    if (-not $roleAddresses) {
        throw 'The phones are not on separate globally routed IPv6 networks.'
    }
    $networkBefore = $true
    $hostRouteScope = 'wifi'
    $clientRouteScope = 'cellular'

    # A wildcard-bound connected UDP6 socket uses the kernel's selected source
    # address. Resolve both selections to a fixed point before packaging so a
    # privacy address cannot cause the peer's connected-socket filter to reject
    # an otherwise valid datagram.
    $stage = 'resolve_kernel_source_candidates'
    $hostSource = Resolve-KernelIpv6Source -Serial $hostDevice.serial `
        -Destination $roleAddresses.clientAddress -ExpectedInterface 'wlan0'
    if (-not $hostSource) {
        throw 'The Wi-Fi phone did not expose a usable IPv6 source candidate.'
    }
    $clientSource = Resolve-KernelIpv6Source -Serial $clientDevice.serial `
        -Destination $hostSource -ExpectedInterface $clientProfile.interface
    if (-not $clientSource) {
        throw 'The cellular phone did not expose a usable IPv6 source candidate.'
    }
    $hostSourceCheck = Resolve-KernelIpv6Source -Serial $hostDevice.serial `
        -Destination $clientSource -ExpectedInterface 'wlan0'
    $clientSourceCheck = if ($hostSourceCheck) {
        Resolve-KernelIpv6Source -Serial $clientDevice.serial `
            -Destination $hostSourceCheck -ExpectedInterface $clientProfile.interface
    } else { $null }
    if (-not $hostSourceCheck -or -not $clientSourceCheck -or
            $hostSourceCheck -cne $hostSource -or
            $clientSourceCheck -cne $clientSource -or
            -not (Test-DifferentIpv6Prefixes -First $hostSource `
                -Second $clientSource)) {
        throw 'The phones did not produce stable, distinct IPv6 source candidates.'
    }
    $roleAddresses = [pscustomobject]@{
        hostAddress = $hostSource
        clientAddress = $clientSource
    }
    $sourceCandidatesResolved = $true

    $stage = 'remove_stale_packages'
    Remove-ProbePackages
    foreach ($target in @(
        @($hostDevice.serial,$hostPackage),
        @($hostDevice.serial,$clientPackage),
        @($clientDevice.serial,$hostPackage),
        @($clientDevice.serial,$clientPackage)
    )) {
        if (-not (Test-PackageAbsent -Serial $target[0] -Package $target[1])) {
            throw 'A stale simultaneous-probe package could not be removed.'
        }
    }

    $stage = 'select_shared_port'
    if ($Port -eq 0) {
        for ($attempt = 1; $attempt -le 32; $attempt++) {
            $candidate = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32(
                20000,61000)
            if (Test-PortAvailableOnBothDevices -CandidatePort $candidate) {
                $Port = $candidate
                break
            }
        }
    } elseif (-not (Test-PortAvailableOnBothDevices -CandidatePort $Port)) {
        throw 'The selected shared UDP port is already in use on a phone.'
    }
    if ($Port -lt 20000 -or $Port -gt 60999) {
        throw 'No shared UDP probe port was available.'
    }

    $stage = 'build_isolated_probes'
    Assert-SafeTemporaryPath -Path $ephemeralParent | Out-Null
    New-Item -ItemType Directory -Path $ephemeralParent -Force | Out-Null
    Assert-SafeTemporaryPath -Path $ephemeralParent | Out-Null
    $ephemeralRoot = Assert-SafeEphemeralRoot -Path (
        Join-Path $ephemeralParent ([Guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $ephemeralRoot -Force | Out-Null
    # Revalidate the newly created root before writing endpoint or token data.
    $ephemeralRoot = Assert-SafeEphemeralRoot -Path $ephemeralRoot
    $runIdBytes = [byte[]]::new(16)
    $tokenBytes = [byte[]]::new(32)
    $invitationIdBytes = [byte[]]::new(16)
    $guestNonceBytes = [byte[]]::new(16)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($runIdBytes)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($tokenBytes)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($invitationIdBytes)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($guestNonceBytes)
    $runId = [Convert]::ToHexString($runIdBytes).ToLowerInvariant()
    $escapedRunId = [regex]::Escape($runId)
    $token = [Convert]::ToHexString($tokenBytes).ToLowerInvariant()
    $masterKeyExpression = 'string.char(' + (($tokenBytes |
        ForEach-Object { [string]$_ }) -join ',') + ')'
    $invitationIdExpression = 'string.char(' + (($invitationIdBytes |
        ForEach-Object { [string]$_ }) -join ',') + ')'
    $guestNonceExpression = 'string.char(' + (($guestNonceBytes |
        ForEach-Object { [string]$_ }) -join ',') + ')'
    $issuedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $packages = @{
        host = New-ProbePackage -Role host -RunId $runId -Token $token `
            -PeerAddress $roleAddresses.clientAddress `
            -LocalAddress $roleAddresses.hostAddress `
            -MasterKeyExpression $masterKeyExpression `
            -InvitationIdExpression $invitationIdExpression `
            -GuestNonceExpression $guestNonceExpression -IssuedAt $issuedAt
        client = New-ProbePackage -Role client -RunId $runId -Token $token `
            -PeerAddress $roleAddresses.hostAddress `
            -LocalAddress $roleAddresses.clientAddress `
            -MasterKeyExpression $masterKeyExpression `
            -InvitationIdExpression $invitationIdExpression `
            -GuestNonceExpression $guestNonceExpression -IssuedAt $issuedAt
    }
    foreach ($role in @('host','client')) {
        if ($EncryptedBridge) {
            & $builder -PackagePath $packages[$role] `
                -EngineeringDirectTransportProbe -DirectTransportProbeRole $role `
                -SensitiveBuildRoot (Join-Path $ephemeralRoot 'mobile')
        } else {
            & $builder -PackagePath $packages[$role] -EngineeringIpv6UdpProbe `
                -Ipv6UdpProbeRole $role `
                -SensitiveBuildRoot (Join-Path $ephemeralRoot 'mobile')
        }
        if (-not $?) { throw 'An isolated simultaneous-probe APK build failed.' }
    }

    $stage = 'verify_and_install_probes'
    $artifactRoot = Join-Path $ephemeralRoot 'mobile\artifacts'
    $hostApk = Join-Path $artifactRoot $(if ($EncryptedBridge) {
        'ThePictureShop-DirectTransportProbe-host-engineering.apk'
    } else { 'ThePictureShop-Ipv6UdpProbe-host-engineering.apk' })
    $clientApk = Join-Path $artifactRoot $(if ($EncryptedBridge) {
        'ThePictureShop-DirectTransportProbe-client-engineering.apk'
    } else { 'ThePictureShop-Ipv6UdpProbe-client-engineering.apk' })
    foreach ($role in @('host','client')) {
        $reportPath = Join-Path $artifactRoot $(if ($EncryptedBridge) {
            "direct-transport-probe-$role-apk-report.json"
        } else { "ipv6-udp-probe-$role-apk-report.json" })
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
            throw 'A simultaneous-probe APK report is missing.'
        }
        $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
        $expectedApplicationId = if ($EncryptedBridge) {
            "com.thepictureshop.direct_probe.$role"
        } else { "com.thepictureshop.ipv6_udp_probe.$role" }
        if ($report.applicationId -cne $expectedApplicationId -or
                $report.engineeringProbe -ne $true -or
                $report.engineeringProbeRole -cne $role -or
                $report.internetPermission -ne $true -or
                $report.signed -ne $true -or
                $report.sixteenKbCompatible -ne $true -or
                $report.nativeCrypto.productionReady -ne $false) {
            throw 'A simultaneous-probe APK failed its engineering safety checks.'
        }
    }
    Install-Probe -Serial $hostDevice.serial -Apk $hostApk
    Install-Probe -Serial $clientDevice.serial -Apk $clientApk

    $stage = 'revalidate_packaged_source_candidates'
    $hostSourceAfterBuild = Resolve-KernelIpv6Source `
        -Serial $hostDevice.serial -Destination $clientSource `
        -ExpectedInterface 'wlan0'
    $clientSourceAfterBuild = Resolve-KernelIpv6Source `
        -Serial $clientDevice.serial -Destination $hostSource `
        -ExpectedInterface $clientProfile.interface
    if ($hostSourceAfterBuild -cne $hostSource -or
            $clientSourceAfterBuild -cne $clientSource -or
            (Test-NetworkRoles) -cne 'verified') {
        throw 'A packaged IPv6 source candidate or separate route changed during the build.'
    }
    $sourceCandidatesRevalidated = $true

    # Before opening either socket, remove every local build copy containing
    # the two public endpoints and the one-time authentication token.
    Remove-EphemeralRoot -Path $ephemeralRoot
    if (Test-Path -LiteralPath $ephemeralRoot) {
        throw 'The isolated simultaneous-probe build tree was not removed.'
    }
    $ephemeralRoot = $null
    $sensitiveArtifactsRemoved = $true
    $roleAddresses = $null
    $hostSource = $null
    $clientSource = $null
    $hostSourceCheck = $null
    $clientSourceCheck = $null
    $hostSourceAfterBuild = $null
    $clientSourceAfterBuild = $null
    if ($tokenBytes) {
        [System.Array]::Clear($tokenBytes,0,$tokenBytes.Length)
    }
    if ($invitationIdBytes) {
        [System.Array]::Clear($invitationIdBytes,0,$invitationIdBytes.Length)
    }
    if ($guestNonceBytes) {
        [System.Array]::Clear($guestNonceBytes,0,$guestNonceBytes.Length)
    }
    $token = $null
    $masterKeyExpression = $null
    $invitationIdExpression = $null
    $guestNonceExpression = $null

    $stage = 'launch_both_probes'
    $hostStart = Invoke-AdbBestEffort -Serial $hostDevice.serial `
        -CommandArguments @('shell','am','start','-n',
            "$hostPackage/org.love2d.android.GameActivity")
    $clientStart = Invoke-AdbBestEffort -Serial $clientDevice.serial `
        -CommandArguments @('shell','am','start','-n',
            "$clientPackage/org.love2d.android.GameActivity")
    if ($hostStart.exitCode -ne 0 -or $clientStart.exitCode -ne 0) {
        throw 'A simultaneous-probe activity did not launch.'
    }
    $hostProcess = Get-PackageProcess -Serial $hostDevice.serial `
        -Package $hostPackage
    $clientProcess = Get-PackageProcess -Serial $clientDevice.serial `
        -Package $clientPackage
    if (-not $hostProcess -or -not $clientProcess) {
        throw 'A simultaneous-probe process did not remain active.'
    }

    $stage = if ($EncryptedBridge) {
        'wait_for_encrypted_ipv6_bridge'
    } else { 'wait_for_simultaneous_ipv6_udp' }
    $waitSeconds = if ($EncryptedBridge) {
        [Math]::Max(75,$TimeoutSeconds + 35) + 12
    } else { $TimeoutSeconds + 8 }
    $deadline = [DateTime]::UtcNow.AddSeconds($waitSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $hostLog = Get-ProcessLog -Serial $hostDevice.serial `
            -ProcessId $hostProcess
        $clientLog = Get-ProcessLog -Serial $clientDevice.serial `
            -ProcessId $clientProcess

        if ($EncryptedBridge) {
            $hostReady = $hostReady -or ($hostLog -match
                "TPS_IPV6_BRIDGE_READY run=$escapedRunId role=host(?:\s|$)")
            $clientReady = $clientReady -or ($clientLog -match
                "TPS_IPV6_BRIDGE_READY run=$escapedRunId role=client(?:\s|$)")
            $hostOpeningReady = $hostOpeningReady -or ($hostLog -match
                "TPS_IPV6_BRIDGE_OPEN_READY run=$escapedRunId role=host(?:\s|$)")
            $clientOpeningReady = $clientOpeningReady -or ($clientLog -match
                "TPS_IPV6_BRIDGE_OPEN_READY run=$escapedRunId role=client(?:\s|$)")
            $hostSecureConnected = $hostSecureConnected -or ($hostLog -match
                "TPS_IPV6_BRIDGE_SECURE_CONNECTED run=$escapedRunId role=host(?:\s|$)")
            $clientSecureConnected = $clientSecureConnected -or ($clientLog -match
                "TPS_IPV6_BRIDGE_SECURE_CONNECTED run=$escapedRunId role=client(?:\s|$)")
            $hostFragmented = $hostFragmented -or ($hostLog -match
                "TPS_IPV6_BRIDGE_FRAGMENTED run=$escapedRunId role=host(?:\s|$)")
            $clientFragmented = $clientFragmented -or ($clientLog -match
                "TPS_IPV6_BRIDGE_FRAGMENTED run=$escapedRunId role=client(?:\s|$)")
            $hostOk = $hostOk -or ($hostLog -match
                "TPS_IPV6_BRIDGE_OK run=$escapedRunId role=host channels=0,1,2 fragmented=true(?:\s|$)")
            $clientOk = $clientOk -or ($clientLog -match
                "TPS_IPV6_BRIDGE_OK run=$escapedRunId role=client channels=0,1,2 fragmented=true(?:\s|$)")
            $hostFail = [regex]::Match($hostLog,
                "TPS_IPV6_BRIDGE_FAIL run=$escapedRunId role=host stage=([^\s]+)")
            $clientFail = [regex]::Match($clientLog,
                "TPS_IPV6_BRIDGE_FAIL run=$escapedRunId role=client stage=([^\s]+)")
        } else {
            $hostReady = $hostReady -or ($hostLog -match
                "TPS_IPV6_SIM_READY run=$escapedRunId role=host(?:\s|$)")
            $clientReady = $clientReady -or ($clientLog -match
                "TPS_IPV6_SIM_READY run=$escapedRunId role=client(?:\s|$)")
            $hostSent = $hostSent -or ($hostLog -match
                "TPS_IPV6_SIM_SENT run=$escapedRunId role=host(?:\s|$)")
            $clientSent = $clientSent -or ($clientLog -match
                "TPS_IPV6_SIM_SENT run=$escapedRunId role=client(?:\s|$)")
            $hostPeerHello = $hostPeerHello -or ($hostLog -match
                "TPS_IPV6_SIM_PEER_HELLO run=$escapedRunId role=host(?:\s|$)")
            $clientPeerHello = $clientPeerHello -or ($clientLog -match
                "TPS_IPV6_SIM_PEER_HELLO run=$escapedRunId role=client(?:\s|$)")
            $hostPeerAck = $hostPeerAck -or ($hostLog -match
                "TPS_IPV6_SIM_PEER_ACK run=$escapedRunId role=host(?:\s|$)")
            $clientPeerAck = $clientPeerAck -or ($clientLog -match
                "TPS_IPV6_SIM_PEER_ACK run=$escapedRunId role=client(?:\s|$)")
            $hostOk = $hostOk -or ($hostLog -match
                "TPS_IPV6_SIM_OK run=$escapedRunId role=host(?:\s|$)")
            $clientOk = $clientOk -or ($clientLog -match
                "TPS_IPV6_SIM_OK run=$escapedRunId role=client(?:\s|$)")
            $hostFail = [regex]::Match($hostLog,
                "TPS_IPV6_SIM_FAIL run=$escapedRunId role=host stage=([^\s]+)")
            $clientFail = [regex]::Match($clientLog,
                "TPS_IPV6_SIM_FAIL run=$escapedRunId role=client stage=([^\s]+)")
        }
        if ($hostFail.Success -or $clientFail.Success) {
            $probeFailureStage = if ($hostFail.Success) {
                "host:$($hostFail.Groups[1].Value)"
            } else { "client:$($clientFail.Groups[1].Value)" }
            $onlyTimeout =
                (-not $hostFail.Success -or
                    $hostFail.Groups[1].Value -ceq 'timeout') -and
                (-not $clientFail.Success -or
                    $clientFail.Groups[1].Value -ceq 'timeout')
            $result = if ($onlyTimeout) { 'timeout' } else { 'probe_failure' }
            break
        }
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
    foreach ($secretBuffer in @(
            $runIdBytes,$tokenBytes,$invitationIdBytes,$guestNonceBytes)) {
        if ($secretBuffer -is [byte[]]) {
            [System.Array]::Clear($secretBuffer,0,$secretBuffer.Length)
        }
    }
    $masterKeyExpression = $null
    $invitationIdExpression = $null
    $guestNonceExpression = $null
    try { Remove-ProbePackages } catch { $packageCleanupException = $true }
    try {
        if ($ephemeralRoot) { Remove-EphemeralRoot -Path $ephemeralRoot }
    } catch { $temporaryCleanupException = $true }
    $sensitiveArtifactsRemoved = -not $temporaryCleanupException -and
        ($sensitiveArtifactsRemoved -or (-not $ephemeralRoot) -or
            (-not (Test-Path -LiteralPath $ephemeralRoot)))
    if ($null -ne $hostDevice -and $null -ne $clientDevice) {
        $packagesAbsent = $true
        foreach ($target in @(
            @($hostDevice.serial,$hostPackage),
            @($hostDevice.serial,$clientPackage),
            @($clientDevice.serial,$hostPackage),
            @($clientDevice.serial,$clientPackage)
        )) {
            try {
                if (-not (Test-PackageAbsent -Serial $target[0] `
                        -Package $target[1])) {
                    $packagesAbsent = $false
                }
            } catch { $packagesAbsent = $false }
        }
    }
}

if ($failureStage) { $result = 'infrastructure_failure' }
$cleanupVerified = -not $packageCleanupException -and
    -not $temporaryCleanupException -and $packagesAbsent -and
    $sensitiveArtifactsRemoved
if ($result -ceq 'pass' -and -not $cleanupVerified) {
    $result = 'cleanup_failure'
    $failureStage = 'cleanup'
}
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$exchangeEvidence = if ($EncryptedBridge) {
    [ordered]@{
        hostAuthenticatedOpeningReady = $hostOpeningReady
        clientAuthenticatedOpeningReady = $clientOpeningReady
        hostSecureEnetConnected = $hostSecureConnected
        clientSecureEnetConnected = $clientSecureConnected
        channels = @(0,1,2)
        clientToHostLargeDurablePayloadBytes = 1200
        hostToClientLargeDurablePayloadBytes = 8192
        hostObservedAuthenticatedBridgeFragmentation = $hostFragmented
        clientObservedAuthenticatedBridgeFragmentation = $clientFragmented
        bidirectionalEncryptedGameTransport = $hostOk -and $clientOk
    }
} else {
    [ordered]@{
        hostDatagramSendAccepted = $hostSent
        clientDatagramSendAccepted = $clientSent
        hostReceivedAuthenticatedHello = $hostPeerHello
        clientReceivedAuthenticatedHello = $clientPeerHello
        hostReceivedAuthenticatedAck = $hostPeerAck
        clientReceivedAuthenticatedAck = $clientPeerAck
        bidirectionalAuthenticatedExchange = $hostOk -and $clientOk
    }
}
$interpretation = if ($EncryptedBridge -and $result -ceq 'pass') {
    'Authenticated simultaneous IPv6 opening transferred into the encrypted ENet bridge across separate Wi-Fi and cellular routes; channels 0, 1, and 2 and bidirectional fragmented durable traffic passed.'
} elseif ($EncryptedBridge) {
    'The encrypted bridge probe did not reach a complete network-valid encrypted ENet exchange.'
} elseif ($result -ceq 'pass') {
    'Simultaneous authenticated IPv6 UDP opening worked across separate Wi-Fi and cellular routes; encrypted game transport is not yet proven.'
} elseif ($result -ceq 'timeout' -and $hostReady -and $clientReady) {
    'Both same-port IPv6 sockets initialized, but a complete authenticated bidirectional exchange was not observed; this does not identify where packets were lost.'
} else {
    'The probe did not reach a network-valid conclusion.'
}
$evidence = [ordered]@{
    artifactKind = if ($EncryptedBridge) {
        'android-two-device-ipv6-encrypted-enet-bridge-probe'
    } else { 'android-two-device-ipv6-simultaneous-opening-probe' }
    engineeringOnly = $true
    productionReady = $false
    encryptedGameTransport = [bool]$EncryptedBridge
    result = $result
    failureStage = if ($failureStage) { $failureStage } else { $probeFailureStage }
    port = if ($Port -ge 20000 -and $Port -le 60999) { $Port } else { $null }
    devices = [ordered]@{
        preferredModelsSelected = $preferredModelsSelected
        hostRouteScope = $hostRouteScope
        clientRouteScope = $clientRouteScope
        hostSocketReady = $hostReady
        clientSocketReady = $clientReady
    }
    network = [ordered]@{
        separateRoutesBefore = $networkBefore
        separateRoutesAfter = $networkAfter
        stableGlobalIpv6Required = $true
        differentIpv6PrefixesRequired = $true
        kernelSourceCandidatesResolved = $sourceCandidatesResolved
        kernelSourceCandidatesRevalidatedAfterBuild =
            $sourceCandidatesRevalidated
        routerOrFirewallChanged = $false
        endpointRecorded = $false
        publicIpv6Recorded = $false
        ephemeralCredentialRecorded = $false
    }
    exchange = $exchangeEvidence
    cleanup = [ordered]@{
        diagnosticPackagesAbsent = $packagesAbsent
        localSensitiveArtifactsRemoved = $sensitiveArtifactsRemoved
        packageRemovalExceptionObserved = $packageCleanupException
        temporaryRemovalExceptionObserved = $temporaryCleanupException
        verifiedForPass = $cleanupVerified
    }
    interpretation = $interpretation
    createdUtc = [DateTime]::UtcNow.ToString('o')
}
[System.IO.File]::WriteAllText(
    $evidencePendingPath,
    ($evidence | ConvertTo-Json -Depth 8) + "`n",
    [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $evidencePendingPath -Destination $evidencePath -Force

Write-Output $(if ($EncryptedBridge) {
    "TPS_IPV6_ENCRYPTED_BRIDGE_PROBE_RESULT=$result"
} else { "TPS_IPV6_SIMULTANEOUS_PROBE_RESULT=$result" })
Write-Output "HOST_SOCKET_READY=$hostReady"
Write-Output "CLIENT_SOCKET_READY=$clientReady"
if ($EncryptedBridge) {
    Write-Output "HOST_OPENING_READY=$hostOpeningReady"
    Write-Output "CLIENT_OPENING_READY=$clientOpeningReady"
    Write-Output "HOST_SECURE_ENET_CONNECTED=$hostSecureConnected"
    Write-Output "CLIENT_SECURE_ENET_CONNECTED=$clientSecureConnected"
    Write-Output "HOST_FRAGMENTATION_OBSERVED=$hostFragmented"
    Write-Output "CLIENT_FRAGMENTATION_OBSERVED=$clientFragmented"
    Write-Output "BIDIRECTIONAL_ENCRYPTED_GAME_TRANSPORT=$($hostOk -and $clientOk)"
} else {
    Write-Output "HOST_DATAGRAM_SENT=$hostSent"
    Write-Output "CLIENT_DATAGRAM_SENT=$clientSent"
    Write-Output "BIDIRECTIONAL_AUTHENTICATED_EXCHANGE=$($hostOk -and $clientOk)"
}
Write-Output "SEPARATE_NETWORKS_VERIFIED=$($networkBefore -and $networkAfter)"
Write-Output "DIAGNOSTIC_PACKAGES_ABSENT=$packagesAbsent"
Write-Output "SENSITIVE_ARTIFACTS_REMOVED=$sensitiveArtifactsRemoved"
Write-Output "CLEANUP_VERIFIED_FOR_PASS=$cleanupVerified"
if ($Port -ge 20000 -and $Port -le 60999) { Write-Output "PROBE_PORT=$Port" }
Write-Output 'PUBLIC_IPV6_RECORDED=False'
Write-Output 'EPHEMERAL_CREDENTIAL_RECORDED=False'
if ($result -cne 'pass') { exit 2 }
