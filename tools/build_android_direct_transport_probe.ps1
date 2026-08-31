param(
    [Parameter(Mandatory=$true)][string]$HostAddress,
    [switch]$InternetProbe,
    [ValidateRange(20000,60999)][int]$HostPort = 22129,
    [string]$EphemeralRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sensitiveBuildRoot = $null
if ($InternetProbe) {
    if (-not $EphemeralRoot) {
        throw 'Internet probes require an isolated EphemeralRoot.'
    }
    $ephemeralFullPath = [System.IO.Path]::GetFullPath($EphemeralRoot)
    $temporaryPrefix = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $projectPrefix = [System.IO.Path]::GetFullPath($projectRoot).TrimEnd('\') + '\'
    if (-not $ephemeralFullPath.StartsWith($temporaryPrefix,
            [System.StringComparison]::OrdinalIgnoreCase) -or
            $ephemeralFullPath.StartsWith($projectPrefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'EphemeralRoot must be a dedicated local temporary directory outside the project.'
    }
    New-Item -ItemType Directory -Path $ephemeralFullPath -Force | Out-Null
    $candidate = $ephemeralFullPath
    $temporaryRoot = $temporaryPrefix.TrimEnd('\')
    while ($candidate -and ($candidate -ceq $temporaryRoot -or
            $candidate.StartsWith($temporaryPrefix,
                [System.StringComparison]::OrdinalIgnoreCase))) {
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'EphemeralRoot and its temporary ancestors must not be reparse points.'
        }
        if ($candidate -ceq $temporaryRoot) { break }
        $candidate = Split-Path $candidate -Parent
    }
    $EphemeralRoot = $ephemeralFullPath
    $probeRoot = Join-Path $EphemeralRoot 'probe'
    $sensitiveBuildRoot = Join-Path $EphemeralRoot 'mobile'
}
else {
    if ($EphemeralRoot) { throw '-EphemeralRoot requires -InternetProbe.' }
    $probeRoot = Join-Path $projectRoot 'output\native-crypto\probe\android\direct-transport'
}
$stagingRoot = Join-Path $probeRoot 'temporary-stages'
$port = $HostPort

function Get-Ipv4Scope {
    param([Parameter(Mandatory=$true)][System.Net.IPAddress]$Address)

    $bytes = $Address.GetAddressBytes()
    $a, $b = [int]$bytes[0], [int]$bytes[1]
    if ($a -eq 0) { return 'this_network' }
    if ($a -eq 10 -or ($a -eq 172 -and $b -ge 16 -and $b -le 31) -or
            ($a -eq 192 -and $b -eq 168)) { return 'private_use' }
    if ($a -eq 100 -and $b -ge 64 -and $b -le 127) { return 'carrier_grade_nat' }
    if ($a -eq 127) { return 'loopback' }
    if ($a -eq 169 -and $b -eq 254) { return 'link_local' }
    if ($a -eq 192 -and $b -eq 0 -and $bytes[2] -eq 0) {
        return 'protocol_assignment'
    }
    if ($a -eq 192 -and $b -eq 31 -and $bytes[2] -eq 196) { return 'special_service' }
    if ($a -eq 192 -and $b -eq 52 -and $bytes[2] -eq 193) { return 'special_service' }
    if ($a -eq 192 -and $b -eq 88 -and $bytes[2] -eq 99) { return 'deprecated_anycast' }
    if ($a -eq 192 -and $b -eq 175 -and $bytes[2] -eq 48) { return 'special_service' }
    if ($a -eq 192 -and $b -eq 0 -and $bytes[2] -eq 2) { return 'documentation' }
    if ($a -eq 198 -and ($b -eq 18 -or $b -eq 19)) { return 'benchmarking' }
    if ($a -eq 198 -and $b -eq 51 -and $bytes[2] -eq 100) { return 'documentation' }
    if ($a -eq 203 -and $b -eq 0 -and $bytes[2] -eq 113) { return 'documentation' }
    if ($a -ge 224 -and $a -le 239) { return 'multicast' }
    if ($a -ge 240) { return 'reserved' }
    return 'global_public_unicast'
}

$parsedHostAddress = $null
if (-not [System.Net.IPAddress]::TryParse($HostAddress.Trim(),[ref]$parsedHostAddress) -or
        $parsedHostAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or
        [System.Net.IPAddress]::IsLoopback($parsedHostAddress)) {
    throw 'HostAddress must be a non-loopback IPv4 address.'
}
$hostBytes = $parsedHostAddress.GetAddressBytes()
if ($hostBytes[0] -eq 0 -or $hostBytes[0] -ge 224 -or
        ($hostBytes[0] -eq 255 -and $hostBytes[1] -eq 255 -and
            $hostBytes[2] -eq 255 -and $hostBytes[3] -eq 255)) {
    throw 'HostAddress must be a usable unicast IPv4 address.'
}
$HostAddress = $parsedHostAddress.IPAddressToString
$hostAddressScope = Get-Ipv4Scope -Address $parsedHostAddress
if ($InternetProbe -and $hostAddressScope -cne 'global_public_unicast') {
    throw "Internet probe address is not public unicast (scope: $hostAddressScope)."
}
$internetProbeLiteral = if ($InternetProbe) { 'true' } else { 'false' }

function Get-LowerSha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-PathInsideRoot {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Root
    )
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $resolvedPath.StartsWith($resolvedRoot,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a probe path outside its output root: $resolvedPath"
    }
    return $resolvedPath
}

function Reset-DirectoryInsideRoot {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Root
    )
    $resolvedPath = Assert-PathInsideRoot -Path $Path -Root $Root
    if (Test-Path -LiteralPath $resolvedPath) {
        $item = Get-Item -LiteralPath $resolvedPath -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to reset a reparse-point probe directory: $resolvedPath"
        }
        Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $resolvedPath -Force | Out-Null
    return $resolvedPath
}

function Remove-DirectoryInsideRoot {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Root
    )
    $resolvedPath = Assert-PathInsideRoot -Path $Path -Root $Root
    if (-not (Test-Path -LiteralPath $resolvedPath)) { return }
    $item = Get-Item -LiteralPath $resolvedPath -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to remove a reparse-point probe directory: $resolvedPath"
    }
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

function New-LovePackage {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('host','client')][string]$Role,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$KeyExpression
    )

    $stageRoot = Join-Path $stagingRoot $Role
    $stageRoot = Reset-DirectoryInsideRoot -Path $stageRoot -Root $probeRoot
    $packagePath = Join-Path $probeRoot "direct-transport-probe-$Role.love"
    $temporaryPackagePath = Join-Path $probeRoot "direct-transport-probe-$Role.tmp.love"

    $sourceFiles = [ordered]@{
        'main.lua' = Join-Path $projectRoot 'native\crypto\tests\love_direct_probe\main.lua'
        'conf.lua' = Join-Path $projectRoot 'native\crypto\tests\love_direct_probe\conf.lua'
        'src\net\address.lua' = Join-Path $projectRoot 'src\net\address.lua'
        'src\net\ip_scope.lua' = Join-Path $projectRoot 'src\net\ip_scope.lua'
        'src\net\crypto_native.lua' = Join-Path $projectRoot 'src\net\crypto_native.lua'
        'src\net\transport_direct.lua' = Join-Path $projectRoot 'src\net\transport_direct.lua'
        'src\net\transport_enet.lua' = Join-Path $projectRoot 'src\net\transport_enet.lua'
    }
    foreach ($relativePath in $sourceFiles.Keys) {
        $sourcePath = $sourceFiles[$relativePath]
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Direct-transport probe source is missing: $sourcePath"
        }
        $destinationPath = Join-Path $stageRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path $destinationPath -Parent) -Force |
            Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }

    $packagedHostAddress = if ($Role -ceq 'client') { $HostAddress } else { 'redacted' }
    $overallTimeoutSeconds = if ($InternetProbe -and $Role -ceq 'host') { 720 } else { 45 }
    $configText = @"
return {
    role = "$Role",
    hostAddress = "$packagedHostAddress",
    internetProbe = $internetProbeLiteral,
    overallTimeoutSeconds = $overallTimeoutSeconds,
    port = $port,
    runId = "$RunId",
    key = $KeyExpression,
}
"@
    [System.IO.File]::WriteAllText(
        (Join-Path $stageRoot 'probe_config.lua'),
        $configText,
        [System.Text.UTF8Encoding]::new($false)
    )

    foreach ($oldPackage in @($packagePath,$temporaryPackagePath)) {
        if (Test-Path -LiteralPath $oldPackage) {
            Remove-Item -LiteralPath $oldPackage -Force
        }
    }
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stageRoot,
        $temporaryPackagePath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )
    Move-Item -LiteralPath $temporaryPackagePath -Destination $packagePath

    $archive = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $expectedEntries = @(
            'conf.lua',
            'main.lua',
            'probe_config.lua',
            'src/net/address.lua',
            'src/net/ip_scope.lua',
            'src/net/crypto_native.lua',
            'src/net/transport_direct.lua',
            'src/net/transport_enet.lua'
        ) | Sort-Object
        $actualEntries = @($archive.Entries |
            Where-Object { $_.FullName -notmatch '/$' } |
            ForEach-Object { $_.FullName.Replace('\','/') } |
            Sort-Object)
        if (Compare-Object $expectedEntries $actualEntries) {
            throw "The $Role Direct-transport probe package has unexpected files."
        }
    }
    finally {
        $archive.Dispose()
    }
    return $packagePath
}

New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
Reset-DirectoryInsideRoot -Path $stagingRoot -Root $probeRoot | Out-Null

$keyBytes = [byte[]]::new(32)
$runBytes = [byte[]]::new(16)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($keyBytes)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($runBytes)
$runId = ([System.BitConverter]::ToString($runBytes)).Replace('-','').ToLowerInvariant()
$keyExpression = 'string.char(' + (($keyBytes | ForEach-Object { [string]$_ }) -join ',') + ')'

try {
    $packages = [ordered]@{}
    foreach ($role in @('host','client')) {
        $packages[$role] = New-LovePackage -Role $role -RunId $runId `
            -KeyExpression $keyExpression
    }

    $buildApkScript = Join-Path $PSScriptRoot 'build_android_apk.ps1'
    foreach ($role in @('host','client')) {
        $buildArguments = @{
            PackagePath = $packages[$role]
            EngineeringDirectTransportProbe = $true
            DirectTransportProbeRole = $role
        }
        if ($InternetProbe) {
            $buildArguments.SensitiveBuildRoot = $sensitiveBuildRoot
        }
        & $buildApkScript @buildArguments
        if (-not $?) { throw "Engineering Direct-transport $role APK build failed." }
    }

    $artifacts = [ordered]@{}
    $apkOutputRoot = if ($InternetProbe) {
        Join-Path $sensitiveBuildRoot 'artifacts'
    } else {
        Join-Path $projectRoot 'output\mobile'
    }
    foreach ($role in @('host','client')) {
        $apkPath = Join-Path $apkOutputRoot "ThePictureShop-DirectTransportProbe-$role-engineering.apk"
        $apkReportPath = Join-Path $apkOutputRoot "direct-transport-probe-$role-apk-report.json"
        if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf) -or
                -not (Test-Path -LiteralPath $apkReportPath -PathType Leaf)) {
            throw "Direct-transport $role APK or verification report is missing."
        }
        $apkReport = Get-Content -Raw -LiteralPath $apkReportPath | ConvertFrom-Json
        if ($apkReport.applicationId -cne "com.thepictureshop.direct_probe.$role" -or
                $apkReport.internetPermission -ne $true -or
                $apkReport.signed -ne $true -or
                $apkReport.sixteenKbCompatible -ne $true -or
                $apkReport.nativeCrypto.productionReady -ne $false) {
            throw "Direct-transport $role APK report failed its engineering safety checks."
        }
        $artifacts[$role] = [ordered]@{
            applicationId = [string]$apkReport.applicationId
            lovePackage = $packages[$role]
            lovePackageBytes = (Get-Item -LiteralPath $packages[$role]).Length
            lovePackageSha256 = Get-LowerSha256 -Path $packages[$role]
            apk = $apkPath
            apkBytes = (Get-Item -LiteralPath $apkPath).Length
            apkSha256 = Get-LowerSha256 -Path $apkPath
            apkReport = $apkReportPath
            apkReportSha256 = Get-LowerSha256 -Path $apkReportPath
            internetPermissionOnly = $true
            signed = $true
            nativeCryptoProductionReady = $false
            packagedNativeCrypto = $apkReport.nativeCrypto.packagedArtifacts
        }
    }

    $report = [ordered]@{
        artifactKind = 'two-device-direct-transport-engineering-probe'
        engineeringOnly = $true
        productionReady = $false
        runId = $runId
        # The client APK necessarily contains the address it must contact, but
        # reports and console output must not retain a player's public address.
        hostAddress = 'redacted'
        hostAddressRecorded = $false
        endpointRecordedInReport = $false
        endpointEmbeddedInClientArtifact = $true
        hostAddressScope = $hostAddressScope
        addressRedacted = $true
        internetProbe = [bool]$InternetProbe
        port = $port
        channels = @(0,1,2)
        sharedKey = 'ephemeral-embedded-only-not-reported'
        artifacts = $artifacts
    }
    $reportPath = Join-Path $probeRoot 'direct-transport-probe-report.json'
    [System.IO.File]::WriteAllText(
        $reportPath,
        ($report | ConvertTo-Json -Depth 12) + "`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Output "DIRECT_TRANSPORT_PROBE_RUN=$runId"
    Write-Output "DIRECT_TRANSPORT_PROBE_HOST_APK=$($artifacts.host.apk)"
    Write-Output "DIRECT_TRANSPORT_PROBE_CLIENT_APK=$($artifacts.client.apk)"
    Write-Output "DIRECT_TRANSPORT_PROBE_REPORT=$reportPath"
}
finally {
    [System.Array]::Clear($keyBytes,0,$keyBytes.Length)
    [System.Array]::Clear($runBytes,0,$runBytes.Length)
    $keyExpression = $null
    Remove-DirectoryInsideRoot -Path $stagingRoot -Root $probeRoot
    # Internet-probe intermediates intentionally remain inside the isolated
    # GUID tree until preparation removes that exact tree with reparse-safe
    # traversal immediately after both APKs are installed.
}
