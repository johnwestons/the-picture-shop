param(
    [ValidateRange(45,240)][int]$PhaseTimeoutSeconds = 150,
    [switch]$ReuseEngineeringArtifacts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$adb = Join-Path $projectRoot 'output\mobile\tooling\android-sdk\platform-tools\adb.exe'
$builder = Join-Path $PSScriptRoot 'build_android_apk.ps1'
$probeMain = Join-Path $PSScriptRoot 'probes\android_direct_gameplay\main.lua'
$mobileConfigPath = Join-Path $projectRoot 'mobile\config.json'
$mobileVersion = if (Test-Path -LiteralPath $mobileConfigPath -PathType Leaf) {
    (Get-Content -LiteralPath $mobileConfigPath -Raw | ConvertFrom-Json).versionName
} else { $null }
if ($mobileVersion -isnot [string] -or
    $mobileVersion -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
    throw 'The current Android versionName is missing or unsafe.'
}
$basePackage = Join-Path $projectRoot ("output\mobile\the-picture-shop-{0}.love" -f $mobileVersion)
$evidenceRoot = Join-Path $projectRoot 'output\native-crypto\device-tests'
$evidencePath = Join-Path $evidenceRoot 'android_two_device_direct_gameplay_report.json'
$pendingPath = Join-Path $evidenceRoot 'android_two_device_direct_gameplay_report.pending.json'
$hostPackage = 'com.thepictureshop.direct_probe.host'
$guestPackage = 'com.thepictureshop.direct_probe.client'
$saveRoot = 'files/save/the-picture-shop/probe'
$ephemeralParent = [System.IO.Path]::GetFullPath(
    (Join-Path ([System.IO.Path]::GetTempPath()) 'ThePictureShop\direct-gameplay'))
$ephemeralRoot = $null
$hostDevice = $null
$guestDevice = $null
$devices = @()
$hostInterface = $null
$guestInterface = $null
$hostAddress = $null
$guestAddress = $null
$hostCandidate = $null
$guestCandidate = $null
$hostCheck = $null
$guestCheck = $null
$hostAfter = $null
$guestAfter = $null
$hostCodeFirst = $null
$responseFirst = $null
$hostCodeFresh = $null
$responseReplay = $null
$responseFresh = $null
$stage = 'preflight'
$failureStage = $null
$failureClass = $null
$failureDetailRedacted = $null
$failure = $null
$cleanupVerified = $false
$sensitiveArtifactsRemoved = $false
$packagesAbsent = $false
$networkVerified = $false
$sourceCandidatesRevalidated = $false
$artifactSafetyVerified = $false
$hostApproval = $false
$firstSessionReady = $false
$snapshotApplied = $false
$directHudTwo = $false
$bayInteraction = $false
$cutterAction = $false
$movement = $false
$disconnectClean = $false
$kickControl = $false
$staleInviteRejected = $false
$freshInviteDistinct = $false
$freshReconnect = $false
$logsSecretFree = $false
$capturedLogs = @()

if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'Android platform tools are not available.'
}
foreach ($required in @($builder,$probeMain,$basePackage)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw 'A required Direct gameplay test artifact is missing.'
    }
}

function Invoke-AdbBestEffort {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string[]]$CommandArguments
    )
    $text = (& $adb -s $Serial @CommandArguments 2>&1 | Out-String).Trim()
    return [pscustomobject]@{ exitCode = $LASTEXITCODE; output = $text }
}

function Invoke-AdbText {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string[]]$CommandArguments
    )
    $result = Invoke-AdbBestEffort -Serial $Serial -CommandArguments $CommandArguments
    if ($result.exitCode -ne 0) { throw 'An Android test command failed.' }
    return $result.output
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
        if (-not [int]::TryParse((Invoke-AdbText -Serial $serial -CommandArguments @(
                'shell','getprop','ro.build.version.sdk')),[ref]$sdk)) {
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
    return $match.Success ? $match.Groups[1].Value : $null
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

function Test-CurrentGlobalIpv6Address {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Interface,
        [Parameter(Mandatory=$true)][string]$Address
    )
    if (-not (Test-GlobalIpv6 -Address $Address) -or
            $Interface -notmatch '^[A-Za-z0-9_.-]+$') { return $false }
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-6','-o','addr','show','dev',$Interface,'scope','global')
    if ($query.exitCode -ne 0) { return $false }
    $expected = [System.Net.IPAddress]::Parse($Address)
    foreach ($line in @($query.output -split "`r?`n")) {
        $match = [regex]::Match($line,'\binet6\s+([0-9A-Fa-f:]+)/[0-9]{1,3}\b')
        if ($match.Success -and $line -notmatch
                '(?:^|\s)(?:tentative|optimistic|dadfailed|deprecated)(?:\s|$)') {
            $candidate = $null
            if (([System.Net.IPAddress]::TryParse(
                    $match.Groups[1].Value,[ref]$candidate)) -and
                    $expected.Equals($candidate)) { return $true }
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
            $ExpectedInterface -notmatch '^[A-Za-z0-9_.-]+$') { return $null }
    $route = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-6','route','get',$Destination)
    if ($route.exitCode -ne 0) { return $null }
    $interfaceMatch = [regex]::Match(
        $route.output,'(?:^|\s)dev\s+([A-Za-z0-9_.-]+)(?:\s|$)')
    $sourceMatch = [regex]::Match(
        $route.output,'(?:^|\s)src\s+([0-9A-Fa-f:]+)(?:\s|$)')
    if (-not $interfaceMatch.Success -or -not $sourceMatch.Success -or
            $interfaceMatch.Groups[1].Value -cne $ExpectedInterface) { return $null }
    $source = $sourceMatch.Groups[1].Value.ToLowerInvariant()
    if (-not (Test-CurrentGlobalIpv6Address -Serial $Serial `
            -Interface $ExpectedInterface -Address $source)) { return $null }
    return $source
}

function Test-DifferentIpv6Prefixes {
    param(
        [Parameter(Mandatory=$true)][string]$First,
        [Parameter(Mandatory=$true)][string]$Second
    )
    $a = [System.Net.IPAddress]::Parse($First).GetAddressBytes()
    $b = [System.Net.IPAddress]::Parse($Second).GetAddressBytes()
    for ($index = 0; $index -lt 8; $index++) {
        if ($a[$index] -ne $b[$index]) { return $true }
    }
    return $false
}

function Test-PortAvailable {
    param([Parameter(Mandatory=$true)][string]$Serial)
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ss','-lun')
    if ($query.exitCode -ne 0 -or
            $query.output -match 'not found|Permission denied|Cannot open') {
        $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
            'shell','netstat','-anu')
    }
    if ($query.exitCode -ne 0) {
        throw 'A phone could not prove that the Direct gameplay port is free.'
    }
    return $query.output -notmatch '(?m):57842(?:\s|$)'
}

function Assert-SafeTemporaryPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $temporary = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath()).TrimEnd('\')
    if (-not $full.StartsWith($temporary + '\',
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The Direct gameplay test path must remain under the temporary root.'
    }
    $candidate = $full
    while ($candidate -and -not (Test-Path -LiteralPath $candidate)) {
        $candidate = Split-Path $candidate -Parent
    }
    while ($candidate -and ($candidate -ceq $temporary -or
            $candidate.StartsWith($temporary + '\',
                [System.StringComparison]::OrdinalIgnoreCase))) {
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Refusing a reparse point in the Direct gameplay test path.'
        }
        if ($candidate -ceq $temporary) { break }
        $candidate = Split-Path $candidate -Parent
    }
    return $full
}

function Assert-SafeEphemeralRoot {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = Assert-SafeTemporaryPath -Path $Path
    if (-not $full.StartsWith($ephemeralParent.TrimEnd('\') + '\',
            [System.StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path $full -Leaf) -notmatch '^[0-9a-f]{32}$') {
        throw 'Refusing an unexpected Direct gameplay temporary path.'
    }
    return $full
}

function Remove-EphemeralRoot {
    param([AllowNull()][string]$Path)
    if (-not $Path) { return }
    $full = Assert-SafeEphemeralRoot -Path $Path
    if (-not (Test-Path -LiteralPath $full)) { return }
    $prefix = $full.TrimEnd('\') + '\'
    $links = @(Get-ChildItem -LiteralPath $full -Recurse -Force |
        Where-Object {
            ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        } | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($link in $links) {
        $linkPath = [System.IO.Path]::GetFullPath($link.FullName)
        if (-not $linkPath.StartsWith($prefix,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a link outside the Direct gameplay test root.'
        }
        Remove-Item -LiteralPath $linkPath -Force
    }
    if (@(Get-ChildItem -LiteralPath $full -Recurse -Force |
            Where-Object {
                ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            }).Count -ne 0) {
        throw 'A reparse point remains in the Direct gameplay test root.'
    }
    Remove-Item -LiteralPath $full -Recurse -Force
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

function Remove-EngineeringPackages {
    foreach ($device in @($hostDevice,$guestDevice)) {
        if ($null -eq $device) { continue }
        foreach ($package in @($hostPackage,$guestPackage)) {
            Invoke-AdbBestEffort -Serial $device.serial -CommandArguments @(
                'shell','am','force-stop',$package) | Out-Null
            Invoke-AdbBestEffort -Serial $device.serial -CommandArguments @(
                'uninstall',$package) | Out-Null
        }
    }
}

function Install-EngineeringPackage {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Apk
    )
    $output = Invoke-AdbText -Serial $Serial -CommandArguments @('install','-r',$Apk)
    if ($output -notmatch '(?m)^Success\s*$') {
        throw 'An engineering Direct gameplay package did not install.'
    }
}

function New-GameplayPackage {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('host','guest')][string]$Role
    )
    $stageRoot = Join-Path $ephemeralRoot "package-$Role"
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($basePackage,$stageRoot)
    Copy-Item -LiteralPath $probeMain -Destination (Join-Path $stageRoot 'main.lua') -Force
    $luaRole = if ($Role -ceq 'guest') { 'guest' } else { 'host' }
    $playerName = if ($luaRole -ceq 'guest') {
        'TPSAndroidGuestProbe'
    } else {
        'TPSAndroidHostProbe'
    }
    $config = "return {`n    role = `"$luaRole`",`n" +
        "    playerName = `"$playerName`",`n}`n"
    [System.IO.File]::WriteAllText(
        (Join-Path $stageRoot 'direct_gameplay_probe_config.lua'),
        $config,[System.Text.UTF8Encoding]::new($false))
    $packagePath = Join-Path $ephemeralRoot "direct-gameplay-$Role.love"
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stageRoot,$packagePath,
        [System.IO.Compression.CompressionLevel]::Optimal,$false)
    return $packagePath
}

function Clear-PackageData {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package
    )
    Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','am','force-stop',$Package) | Out-Null
    $result = Invoke-AdbText -Serial $Serial -CommandArguments @(
        'shell','pm','clear',$Package)
    if ($result -notmatch 'Success') { throw 'Engineering app data could not be cleared.' }
}

function Start-EngineeringApp {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package
    )
    Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','am','force-stop',$Package) | Out-Null
    $result = Invoke-AdbText -Serial $Serial -CommandArguments @(
        'shell','am','start','-W','-n',"$Package/org.love2d.android.GameActivity")
    if ($result -match 'Error:|Exception') {
        throw 'An engineering Direct gameplay app did not launch.'
    }
}

function Private-Path {
    param([Parameter(Mandatory=$true)][string]$Name)
    if ($Name -notmatch '^[a-z0-9-]+$') { throw 'Unsafe private marker name.' }
    return "$saveRoot/$Name.txt"
}

function Read-PrivateFile {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $path = Private-Path -Name $Name
    $exists = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','run-as',$Package,'ls',$path)
    if ($exists.exitCode -ne 0) { return $null }
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'exec-out','run-as',$Package,'cat',$path)
    if ($query.exitCode -ne 0) { return $null }
    return $query.output
}

function Remove-PrivateFile {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package,
        [Parameter(Mandatory=$true)][string]$Name
    )
    Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','run-as',$Package,'rm','-f',(Private-Path -Name $Name)) | Out-Null
}

function Write-PrivateFile {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Value
    )
    if ($Value.Length -lt 1 -or $Value.Length -gt 160 -or
            $Value -match '[^A-Za-z0-9_.-]') {
        throw 'A private Direct code failed local validation.'
    }
    if ($Package -notmatch '^com\.thepictureshop\.direct_probe\.(?:host|client)$') {
        throw 'Unexpected engineering package name.'
    }
    $relativePath = Private-Path -Name $Name
    $created = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','run-as',$Package,'mkdir','-p',$saveRoot)
    if ($created.exitCode -ne 0) { throw 'Private app directory creation failed.' }
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $adb
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in @('-s',$Serial,'shell','run-as',$Package,'dd',
            "of=$relativePath")) {
        $psi.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::Start($psi)
    try {
        $process.StandardInput.Write($Value)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $process.StandardOutput.ReadToEnd() | Out-Null
        $process.StandardError.ReadToEnd() | Out-Null
        if ($process.ExitCode -ne 0) { throw 'Private Direct code transfer failed.' }
    } finally {
        $process.Dispose()
    }
}

function Write-PrivateAddress {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package,
        [Parameter(Mandatory=$true)][string]$Value
    )
    if (-not (Test-GlobalIpv6 -Address $Value) -or $Value.Length -gt 39) {
        throw 'A private local address failed validation.'
    }
    if ($Package -notmatch '^com\.thepictureshop\.direct_probe\.(?:host|client)$') {
        throw 'Unexpected engineering package name.'
    }
    $relativePath = Private-Path -Name 'inbox-local-address'
    $created = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','run-as',$Package,'mkdir','-p',$saveRoot)
    if ($created.exitCode -ne 0) { throw 'Private app directory creation failed.' }
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $adb
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in @('-s',$Serial,'shell','run-as',$Package,'dd',
            "of=$relativePath")) {
        $psi.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::Start($psi)
    try {
        $process.StandardInput.Write($Value)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $process.StandardOutput.ReadToEnd() | Out-Null
        $process.StandardError.ReadToEnd() | Out-Null
        if ($process.ExitCode -ne 0) { throw 'Private local-address transfer failed.' }
    } finally {
        $process.Dispose()
    }
}

function Test-AppRunning {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package
    )
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','pidof',$Package)
    return $query.exitCode -eq 0 -and $query.output -match '^\d+$'
}

function Wait-PrivateValue {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int]$TimeoutSeconds,
        [switch]$Code
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $value = Read-PrivateFile -Serial $Serial -Package $Package -Name $Name
        if ($null -ne $value) {
            $value = $value.Trim()
            if ($Code -and ($value.Length -lt 1 -or $value.Length -gt 160 -or
                    $value -match '[^A-Za-z0-9_.-]')) {
                throw 'An engineering app produced an invalid private code.'
            }
            return $value
        }
        if ($null -ne (Read-PrivateFile -Serial $Serial -Package $Package -Name 'failure')) {
            throw 'An engineering app reached its internal timeout.'
        }
        if (-not (Test-AppRunning -Serial $Serial -Package $Package)) {
            throw 'An engineering Direct gameplay app stopped unexpectedly.'
        }
        Start-Sleep -Milliseconds 200
    }
    throw 'Timed out waiting for an engineering Direct gameplay milestone.'
}

function Wait-Marker {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int]$TimeoutSeconds
    )
    Wait-PrivateValue -Serial $Serial -Package $Package -Name $Name `
        -TimeoutSeconds $TimeoutSeconds | Out-Null
    return $true
}

function Get-AppLog {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package
    )
    $processQuery = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','pidof',$Package)
    if ($processQuery.exitCode -ne 0 -or $processQuery.output -notmatch '^\d+$') { return '' }
    $log = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'logcat',"--pid=$($processQuery.output)",'-d','-v','brief')
    return $log.exitCode -eq 0 ? $log.output : ''
}

function Assert-NoSecretInLogs {
    param([Parameter(Mandatory=$true)][string[]]$Logs)
    foreach ($log in $Logs) {
        if ($log -match 'TPS2[HR][A-Za-z0-9_.-]{16,}') {
            throw 'A Direct invitation appeared in Android logs.'
        }
        foreach ($secret in @($hostCodeFirst,$responseFirst,$hostCodeFresh,
                $responseReplay,$responseFresh)) {
            if ($secret -and $log.Contains($secret)) {
                throw 'A private Direct code appeared in Android logs.'
            }
        }
    }
    return $true
}

try {
    $stage = 'select_devices_and_verify_routes'
    $devices = @(Get-ConnectedDevices)
    if ($devices.Count -lt 2) { throw 'Two attached Android devices are required.' }
    $hostDevice = @($devices | Where-Object { $_.model -ceq 'SM-J410G' }) | Select-Object -First 1
    $guestDevice = @($devices | Where-Object { $_.model -ceq 'SM-S938U' }) | Select-Object -First 1
    if (-not $hostDevice -or -not $guestDevice -or
            $hostDevice.serial -ceq $guestDevice.serial) {
        throw 'Could not unambiguously select the two expected Android phones.'
    }
    $hostInterface = Get-DefaultIpv6Interface -Serial $hostDevice.serial
    $guestInterface = Get-DefaultIpv6Interface -Serial $guestDevice.serial
    if ($hostInterface -cne 'wlan0' -or
            -not (Test-CellularInterface -Name $guestInterface) -or
            -not (Get-WifiIpv4 -Serial $hostDevice.serial) -or
            (Get-WifiIpv4 -Serial $guestDevice.serial)) {
        throw 'The phones are not on the required Wi-Fi host and cellular guest routes.'
    }
    $hostCandidate = Get-StableGlobalIpv6 -Serial $hostDevice.serial `
        -Interface $hostInterface
    $guestCandidate = Get-StableGlobalIpv6 -Serial $guestDevice.serial `
        -Interface $guestInterface
    if (-not $hostCandidate -or -not $guestCandidate) {
        throw 'A phone does not currently have global IPv6.'
    }
    $hostAddress = Resolve-KernelIpv6Source -Serial $hostDevice.serial `
        -Destination $guestCandidate -ExpectedInterface $hostInterface
    $guestAddress = if ($hostAddress) {
        Resolve-KernelIpv6Source -Serial $guestDevice.serial `
            -Destination $hostAddress -ExpectedInterface $guestInterface
    } else { $null }
    $hostCheck = if ($guestAddress) {
        Resolve-KernelIpv6Source -Serial $hostDevice.serial `
            -Destination $guestAddress -ExpectedInterface $hostInterface
    } else { $null }
    $guestCheck = if ($hostCheck) {
        Resolve-KernelIpv6Source -Serial $guestDevice.serial `
            -Destination $hostCheck -ExpectedInterface $guestInterface
    } else { $null }
    if (-not $hostAddress -or -not $guestAddress -or
            $hostCheck -cne $hostAddress -or $guestCheck -cne $guestAddress -or
            -not (Test-DifferentIpv6Prefixes -First $hostAddress -Second $guestAddress)) {
        throw 'The phones did not produce stable source addresses on distinct IPv6 prefixes.'
    }
    if (-not (Test-PortAvailable -Serial $hostDevice.serial) -or
            -not (Test-PortAvailable -Serial $guestDevice.serial)) {
        throw 'The Direct gameplay UDP port is already in use.'
    }
    $networkVerified = $true

    $stage = 'verify_production_gate'
    $cryptoSource = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'src\net\crypto_native.lua')
    if ($cryptoSource -notmatch '(?m)^\s*productionReady\s*=\s*false,?\s*$') {
        throw 'The normal native provider production gate is not closed.'
    }

    $stage = 'create_isolated_engineering_packages'
    Assert-SafeTemporaryPath -Path $ephemeralParent | Out-Null
    New-Item -ItemType Directory -Path $ephemeralParent -Force | Out-Null
    $ephemeralRoot = Assert-SafeEphemeralRoot -Path (
        Join-Path $ephemeralParent ([Guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $ephemeralRoot -Force | Out-Null
    $ephemeralRoot = Assert-SafeEphemeralRoot -Path $ephemeralRoot
    $artifactRoot = Join-Path $projectRoot 'output\mobile'
    $hostApk = Join-Path $artifactRoot 'ThePictureShop-DirectTransportProbe-host-engineering.apk'
    $guestApk = Join-Path $artifactRoot 'ThePictureShop-DirectTransportProbe-client-engineering.apk'
    if (-not $ReuseEngineeringArtifacts) {
        $hostLove = New-GameplayPackage -Role host
        $guestLove = New-GameplayPackage -Role guest
        & $builder -PackagePath $hostLove -EngineeringDirectTransportProbe `
            -DirectTransportProbeRole host | Out-Null
        if (-not $?) { throw 'The host engineering package build failed.' }
        & $builder -PackagePath $guestLove -EngineeringDirectTransportProbe `
            -DirectTransportProbeRole client | Out-Null
        if (-not $?) { throw 'The guest engineering package build failed.' }
    }
    if (-not (Test-Path -LiteralPath $hostApk -PathType Leaf) -or
            -not (Test-Path -LiteralPath $guestApk -PathType Leaf)) {
        throw 'The address-free engineering APKs are unavailable.'
    }
    foreach ($role in @('host','client')) {
        $report = Get-Content -Raw -LiteralPath (
            Join-Path $artifactRoot "direct-transport-probe-$role-apk-report.json") |
            ConvertFrom-Json
        if ($report.applicationId -cne "com.thepictureshop.direct_probe.$role" -or
                $report.engineeringProbe -ne $true -or
                $report.internetPermission -ne $true -or
                $report.signed -ne $true -or
                $report.sixteenKbCompatible -ne $true -or
                $report.nativeCrypto.productionReady -ne $false) {
            throw 'An engineering APK failed its safety checks.'
        }
    }
    $artifactSafetyVerified = $true

    $stage = 'install_isolated_engineering_packages'
    Remove-EngineeringPackages
    Install-EngineeringPackage -Serial $hostDevice.serial -Apk $hostApk
    Install-EngineeringPackage -Serial $guestDevice.serial -Apk $guestApk

    $stage = 'revalidate_routes_after_build'
    $hostAfter = Resolve-KernelIpv6Source -Serial $hostDevice.serial `
        -Destination $guestAddress -ExpectedInterface $hostInterface
    $guestAfter = Resolve-KernelIpv6Source -Serial $guestDevice.serial `
        -Destination $hostAddress -ExpectedInterface $guestInterface
    if ($hostAfter -cne $hostAddress -or $guestAfter -cne $guestAddress) {
        throw 'A selected IPv6 source changed during the engineering build.'
    }
    $sourceCandidatesRevalidated = $true

    $stage = 'first_player_flow'
    Clear-PackageData -Serial $hostDevice.serial -Package $hostPackage
    Clear-PackageData -Serial $guestDevice.serial -Package $guestPackage
    $stage = 'first_launch_host'
    Start-EngineeringApp -Serial $hostDevice.serial -Package $hostPackage
    $stage = 'first_launch_guest'
    Start-EngineeringApp -Serial $guestDevice.serial -Package $guestPackage
    $stage = 'first_wait_apps_loaded'
    Wait-Marker -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'app-loaded' -TimeoutSeconds 30 | Out-Null
    Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'app-loaded' -TimeoutSeconds 30 | Out-Null
    Write-PrivateAddress -Serial $hostDevice.serial -Package $hostPackage `
        -Value $hostAddress
    Write-PrivateAddress -Serial $guestDevice.serial -Package $guestPackage `
        -Value $guestAddress
    $stage = 'first_wait_host_code'
    $hostCodeFirst = Wait-PrivateValue -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'host-code' -TimeoutSeconds $PhaseTimeoutSeconds -Code
    Remove-PrivateFile -Serial $hostDevice.serial -Package $hostPackage -Name 'host-code'
    $stage = 'first_transfer_host_code'
    Write-PrivateFile -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'inbox-host-code' -Value $hostCodeFirst
    $stage = 'first_wait_guest_response'
    $responseFirst = Wait-PrivateValue -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'response-code' -TimeoutSeconds $PhaseTimeoutSeconds -Code
    Remove-PrivateFile -Serial $guestDevice.serial -Package $guestPackage -Name 'response-code'
    $stage = 'first_transfer_guest_response'
    Write-PrivateFile -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'inbox-response-code' -Value $responseFirst

    $stage = 'first_wait_player_approval'
    $hostApproval = Wait-Marker -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'host-approved' -TimeoutSeconds $PhaseTimeoutSeconds
    $stage = 'first_wait_host_acceptance'
    Wait-Marker -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'host-complete' -TimeoutSeconds $PhaseTimeoutSeconds | Out-Null
    $stage = 'first_wait_guest_acceptance'
    Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'client-complete' -TimeoutSeconds $PhaseTimeoutSeconds | Out-Null
    $firstSessionReady = (Wait-Marker -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'session-ready' -TimeoutSeconds 5) -and
        (Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
            -Name 'session-ready' -TimeoutSeconds 5)
    $snapshotApplied = Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'snapshot-applied' -TimeoutSeconds 5
    $directHudTwo = (Wait-Marker -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'hud-direct-two' -TimeoutSeconds 5) -and
        (Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
            -Name 'hud-direct-two' -TimeoutSeconds 5)
    $bayInteraction = Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'bay-interaction' -TimeoutSeconds 5
    $cutterAction = Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'cutter-action' -TimeoutSeconds 5
    $movement = (Wait-Marker -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'movement' -TimeoutSeconds 5) -and
        (Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
            -Name 'movement' -TimeoutSeconds 5)

    $stage = 'disconnect_cleanup'
    Write-PrivateFile -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'inbox-disconnect' -Value 'quit'
    $disconnectClean = Wait-Marker -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'host-disconnect' -TimeoutSeconds 20
    Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'client-graceful-exit' -TimeoutSeconds 5 | Out-Null
    $capturedLogs += Get-AppLog -Serial $hostDevice.serial -Package $hostPackage
    $capturedLogs += Get-AppLog -Serial $guestDevice.serial -Package $guestPackage
    Invoke-AdbText -Serial $guestDevice.serial -CommandArguments @(
        'shell','am','force-stop',$guestPackage) | Out-Null
    Invoke-AdbText -Serial $hostDevice.serial -CommandArguments @(
        'shell','am','force-stop',$hostPackage) | Out-Null

    $stage = 'stale_invite_rejection'
    Clear-PackageData -Serial $hostDevice.serial -Package $hostPackage
    Clear-PackageData -Serial $guestDevice.serial -Package $guestPackage
    Start-EngineeringApp -Serial $hostDevice.serial -Package $hostPackage
    Start-EngineeringApp -Serial $guestDevice.serial -Package $guestPackage
    Wait-Marker -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'app-loaded' -TimeoutSeconds 30 | Out-Null
    Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'app-loaded' -TimeoutSeconds 30 | Out-Null
    Write-PrivateAddress -Serial $hostDevice.serial -Package $hostPackage `
        -Value $hostAddress
    Write-PrivateAddress -Serial $guestDevice.serial -Package $guestPackage `
        -Value $guestAddress
    $stage = 'replay_wait_fresh_host_code'
    $hostCodeFresh = Wait-PrivateValue -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'host-code' -TimeoutSeconds $PhaseTimeoutSeconds -Code
    Remove-PrivateFile -Serial $hostDevice.serial -Package $hostPackage -Name 'host-code'
    $freshInviteDistinct = $hostCodeFresh -cne $hostCodeFirst
    if (-not $freshInviteDistinct) { throw 'A fresh host flow reused its previous invitation.' }
    Write-PrivateFile -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'inbox-host-code' -Value $hostCodeFirst
    $stage = 'replay_wait_stale_response'
    $responseReplay = Wait-PrivateValue -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'response-code' -TimeoutSeconds $PhaseTimeoutSeconds -Code
    Remove-PrivateFile -Serial $guestDevice.serial -Package $guestPackage -Name 'response-code'
    Write-PrivateFile -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'inbox-response-code' -Value $responseReplay
    $stage = 'replay_wait_rejection'
    $staleInviteRejected = Wait-Marker -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'response-rejected' -TimeoutSeconds 10

    $stage = 'fresh_invite_reconnect'
    $capturedLogs += Get-AppLog -Serial $guestDevice.serial -Package $guestPackage
    Clear-PackageData -Serial $guestDevice.serial -Package $guestPackage
    Start-EngineeringApp -Serial $guestDevice.serial -Package $guestPackage
    Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'app-loaded' -TimeoutSeconds 30 | Out-Null
    Write-PrivateAddress -Serial $guestDevice.serial -Package $guestPackage `
        -Value $guestAddress
    Write-PrivateFile -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'inbox-host-code' -Value $hostCodeFresh
    $stage = 'fresh_wait_guest_response'
    $responseFresh = Wait-PrivateValue -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'response-code' -TimeoutSeconds $PhaseTimeoutSeconds -Code
    Remove-PrivateFile -Serial $guestDevice.serial -Package $guestPackage -Name 'response-code'
    Write-PrivateFile -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'inbox-response-code' -Value $responseFresh
    $stage = 'fresh_wait_host_acceptance'
    Wait-Marker -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'host-complete' -TimeoutSeconds $PhaseTimeoutSeconds | Out-Null
    Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'client-complete' -TimeoutSeconds $PhaseTimeoutSeconds | Out-Null
    $freshReconnect = $true

    $stage = 'fresh_host_kick'
    Write-PrivateFile -Serial $guestDevice.serial -Package $guestPackage `
        -Name 'inbox-kick' -Value 'kick'
    Write-PrivateFile -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'inbox-kick' -Value 'kick'
    $kickControl = (Wait-Marker -Serial $hostDevice.serial -Package $hostPackage `
        -Name 'host-kick' -TimeoutSeconds 20) -and
        (Wait-Marker -Serial $guestDevice.serial -Package $guestPackage `
            -Name 'guest-kicked' -TimeoutSeconds 20)

    $stage = 'verify_logs'
    $capturedLogs += Get-AppLog -Serial $hostDevice.serial -Package $hostPackage
    $capturedLogs += Get-AppLog -Serial $guestDevice.serial -Package $guestPackage
    $logsSecretFree = Assert-NoSecretInLogs -Logs $capturedLogs
} catch {
    $failureStage = $stage
    $failureDetailRedacted = [string]$_.Exception.Message
    $failureDetailRedacted = $failureDetailRedacted -replace
        'TPS2[HR][A-Za-z0-9_.-]{8,}','[DIRECT-CODE-REDACTED]'
    $failureDetailRedacted = $failureDetailRedacted -replace
        '(?i)(?:[0-9a-f]{0,4}:){2,}[0-9a-f:]{0,4}','[IPV6-REDACTED]'
    if ($failureDetailRedacted.Length -gt 240) {
        $failureDetailRedacted = $failureDetailRedacted.Substring(0,240)
    }
    $failureClass = if ($_.Exception.Message -match 'stopped unexpectedly') {
        'engineering_app_stopped'
    } elseif ($_.Exception.Message -match 'Timed out') {
        'milestone_timeout'
    } elseif ($_.Exception.Message -match 'private code transfer') {
        'private_exchange_write_failed'
    } elseif ($_.Exception.Message -match 'invalid private code') {
        'private_exchange_invalid'
    } else {
        'test_assertion'
    }
    $diagnosticTargets = @()
    if ($hostDevice) {
        $diagnosticTargets += [pscustomobject]@{
            device = $hostDevice; package = $hostPackage
        }
    }
    if ($guestDevice) {
        $diagnosticTargets += [pscustomobject]@{
            device = $guestDevice; package = $guestPackage
        }
    }
    foreach ($diagnosticTarget in $diagnosticTargets) {
        $diagnosticLog = Invoke-AdbBestEffort `
            -Serial $diagnosticTarget.device.serial -CommandArguments @(
                'logcat','-d','-v','brief')
        if ($diagnosticLog.output -match
                'engineering native provider is not ready|expected the production provider gate') {
            $failureClass = 'engineering_provider_assertion'
        } elseif ($diagnosticLog.output -match
                'host player flow failure category=host-save') {
            $failureClass = 'host_save_preflight'
        } elseif ($diagnosticLog.output -match
                'host player flow failure category=socket') {
            $failureClass = 'direct_socket_open'
        } elseif ($diagnosticLog.output -match
                'host player flow failure category=address') {
            $failureClass = 'local_address_validation'
        } elseif ($diagnosticLog.output -match
                'host player flow failure category=unavailable') {
            $failureClass = 'direct_provider_unavailable'
        } elseif ($diagnosticLog.output -match
                'host player flow failure category=|guest player flow did not open') {
            $failureClass = 'player_flow_assertion'
        } elseif ($diagnosticLog.output -match
                'Lua error|stack traceback|PANIC: unprotected error in call to Lua API') {
            $failureClass = 'lua_runtime_error'
        }
    }
    $failure = $_
} finally {
    $stage = 'cleanup'
    try { Remove-EngineeringPackages } catch { }
    if ($hostDevice -and $guestDevice) {
        $packagesAbsent =
            (Test-PackageAbsent -Serial $hostDevice.serial -Package $hostPackage) -and
            (Test-PackageAbsent -Serial $hostDevice.serial -Package $guestPackage) -and
            (Test-PackageAbsent -Serial $guestDevice.serial -Package $hostPackage) -and
            (Test-PackageAbsent -Serial $guestDevice.serial -Package $guestPackage)
    }
    try {
        if ($ephemeralRoot) {
            Remove-EphemeralRoot -Path $ephemeralRoot
            $sensitiveArtifactsRemoved = -not (Test-Path -LiteralPath $ephemeralRoot)
        } else {
            $sensitiveArtifactsRemoved = $true
        }
    } catch {
        $sensitiveArtifactsRemoved = $false
    }
    $cleanupVerified = $packagesAbsent -and $sensitiveArtifactsRemoved
    $hostAddress = $null
    $guestAddress = $null
    $hostCandidate = $null
    $guestCandidate = $null
    $hostCheck = $null
    $guestCheck = $null
    $hostAfter = $null
    $guestAfter = $null
    $hostCodeFirst = $null
    $responseFirst = $null
    $hostCodeFresh = $null
    $responseReplay = $null
    $responseFresh = $null
}

$passed = $null -eq $failure -and $networkVerified -and
    $sourceCandidatesRevalidated -and $artifactSafetyVerified -and
    $hostApproval -and $firstSessionReady -and $snapshotApplied -and $directHudTwo -and
    $bayInteraction -and $cutterAction -and $movement -and
    $disconnectClean -and $kickControl -and $staleInviteRejected -and $freshInviteDistinct -and
    $freshReconnect -and $logsSecretFree -and $cleanupVerified

$report = [ordered]@{
    schemaVersion = 1
    result = if ($passed) { 'passed' } else { 'failed' }
    failureStage = $failureStage
    failureClass = $failureClass
    failureDetailRedacted = $failureDetailRedacted
    productionReady = $false
    engineeringOnly = $true
    noAccount = $true
    noMatchmaking = $true
    noRelay = $true
    noThirdPartyService = $true
    network = [ordered]@{
        separateRoutes = $networkVerified
        distinctIpv6Prefixes = $networkVerified
        sourceCandidatesRevalidated = $sourceCandidatesRevalidated
        host = [ordered]@{
            model = if ($hostDevice) { $hostDevice.model } else { $null }
            api = if ($hostDevice) { $hostDevice.sdk } else { $null }
            abi = if ($hostDevice) { $hostDevice.abi } else { $null }
            routeScope = 'wifi'
        }
        guest = [ordered]@{
            model = if ($guestDevice) { $guestDevice.model } else { $null }
            api = if ($guestDevice) { $guestDevice.sdk } else { $null }
            abi = if ($guestDevice) { $guestDevice.abi } else { $null }
            routeScope = 'cellular'
        }
    }
    artifactSafety = [ordered]@{
        isolatedEngineeringApplicationIds = $artifactSafetyVerified
        normalProviderGateClosed = $true
        invitationMaterialAbsentFromReport = $true
        androidLogsSecretFree = $logsSecretFree
    }
    acceptance = [ordered]@{
        twoCodePlayerFlow = $firstSessionReady
        explicitHostApproval = $hostApproval
        protocolV9SnapshotApplied = $snapshotApplied
        directHudTwoOfFour = $directHudTwo
        bidirectionalSessionReady = $firstSessionReady
        remoteMovement = $movement
        loadingBayInteraction = $bayInteraction
        remoteCutterSafetyAction = $cutterAction
        disconnectCleanup = $disconnectClean
        hostKickControl = $kickControl
        staleInvitationRejected = $staleInviteRejected
        freshInvitationDistinct = $freshInviteDistinct
        freshInvitationReconnect = $freshReconnect
    }
    cleanup = [ordered]@{
        engineeringPackagesAbsent = $packagesAbsent
        sensitiveTemporaryArtifactsRemoved = $sensitiveArtifactsRemoved
        verified = $cleanupVerified
    }
}

New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$json = ($report | ConvertTo-Json -Depth 8) + "`n"
$target = if ($passed) { $evidencePath } else { $pendingPath }
[System.IO.File]::WriteAllText($target,$json,[System.Text.UTF8Encoding]::new($false))
if ($passed -and (Test-Path -LiteralPath $pendingPath)) {
    Remove-Item -LiteralPath $pendingPath -Force
}

if (-not $passed) {
    $safeStage = $failureStage ?? 'acceptance_assertion'
    throw "Direct gameplay acceptance failed at stage '$safeStage'. Engineering packages and private material were removed."
}

Write-Output 'DIRECT_GAMEPLAY_ACCEPTANCE=PASS'
Write-Output 'SEPARATE_WIFI_AND_CELLULAR_IPV6=True'
Write-Output 'PROTOCOL_V9_SNAPSHOT=True'
Write-Output 'DIRECT_HUD_2_OF_4=True'
Write-Output 'REMOTE_MOVEMENT=True'
Write-Output 'LOADING_BAY_INTERACTION=True'
Write-Output 'REMOTE_CUTTER_ACTION=True'
Write-Output 'DISCONNECT_CLEANUP=True'
Write-Output 'STALE_INVITATION_REJECTED=True'
Write-Output 'FRESH_INVITATION_RECONNECT=True'
Write-Output 'PRODUCTION_READY=False'
Write-Output 'NO_RELAY_NO_ACCOUNT_NO_THIRD_PARTY=True'
Write-Output 'ENGINEERING_PACKAGES_AND_PRIVATE_MATERIAL_REMOVED=True'
