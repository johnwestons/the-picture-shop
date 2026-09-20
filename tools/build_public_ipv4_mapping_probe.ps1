[CmdletBinding()]
param(
    [string]$LoveRoot = 'C:\Program Files\LOVE'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'output\public-ipv4-probe'))
$workRoot = Join-Path $outputRoot 'work'
$appStage = Join-Path $workRoot 'love-app'
$kitStage = Join-Path $workRoot 'kit'
$kitName = 'The Picture Shop Public IPv4 Remote Test'
$kitRoot = Join-Path $kitStage $kitName
$hostRoot = Join-Path $kitRoot 'Host'
$guestRoot = Join-Path $kitRoot 'Guest'
$lovePackage = Join-Path $workRoot 'public-ipv4-probe.love'
$zipPath = Join-Path $outputRoot `
    'ThePictureShop-PublicIPv4-Remote-Test.zip'
$reportPath = Join-Path $outputRoot 'build-report.txt'

$cryptoRoot = Join-Path $repoRoot 'output\native-crypto\build\windows-x64'
$routeRoot = Join-Path $repoRoot 'output\native-route\build\windows-x64'
$cryptoDll = Join-Path $cryptoRoot 'tps_crypto.dll'
$routeDll = Join-Path $routeRoot 'tps_route.dll'
$cryptoReportPath = Join-Path $cryptoRoot 'native_crypto_report.json'
$routeReportPath = Join-Path $routeRoot 'native_route_report.json'
$probeSourceRoot = Join-Path $repoRoot 'tools\probes\public_ipv4_mapping'
$windowsSourceRoot = Join-Path $probeSourceRoot 'windows'
$instructionsPath = Join-Path $repoRoot `
    'docs\public_ipv4_remote_acceptance.md'

function Assert-WithinOutput([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $outputRoot.TrimEnd('\') + '\'
    if ($full -cne $outputRoot -and -not $full.StartsWith(
            $prefix,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Generated path escaped the public-IPv4 output root: $full"
    }
    return $full
}

function Reset-GeneratedDirectory([string]$Path) {
    $full = Assert-WithinOutput $Path
    if (Test-Path -LiteralPath $full) {
        $item = Get-Item -LiteralPath $full -Force
        if (-not $item.PSIsContainer -or
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to reset an unsafe generated path: $full"
        }
        Remove-Item -LiteralPath $full -Recurse -Force
    }
    New-Item -ItemType Directory -Path $full -Force | Out-Null
}

function Assert-File([string]$Path,[string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description is missing: $Path"
    }
}

function Copy-RequiredFile([string]$Source,[string]$Destination) {
    Assert-File $Source 'Required acceptance-kit input'
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Assert-ReportedArtifact($Report,[string]$ArtifactPath,[string]$Key) {
    $expected = [string]$Report.artifacts.$Key.sha256
    $actual = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    if ($expected -notmatch '^[0-9a-f]{64}$' -or $actual -cne $expected) {
        throw 'A native candidate no longer matches its verified build report.'
    }
}

function Get-ArchiveFiles([string]$ArchivePath) {
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        return @($archive.Entries |
            Where-Object { $_.FullName -notmatch '/$' } |
            ForEach-Object { $_.FullName.Replace('\','/') } |
            Sort-Object)
    } finally {
        $archive.Dispose()
    }
}

function Assert-ExactArchive([string]$ArchivePath,[string[]]$Expected) {
    $actual = @(Get-ArchiveFiles $ArchivePath)
    $difference = @(Compare-Object @($Expected | Sort-Object) $actual)
    if ($difference.Count -ne 0) {
        throw "Archive contains an unexpected or missing file: $ArchivePath"
    }
}

function Write-Manifest([string]$Folder,[string]$Kind) {
    $hashes = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Folder -Recurse -File |
            Where-Object { $_.Name -cne 'manifest.json' -and
                $_.Name -notlike 'last-*-result.txt' } |
            Sort-Object FullName)) {
        $relative = $file.FullName.Substring($Folder.Length).
            TrimStart('\').Replace('\','/')
        $hashes[$relative] = (Get-FileHash -LiteralPath $file.FullName `
            -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        kind = $Kind
        probePort = 59281
        leaseSeconds = 120
        files = $hashes
    }
    $json = $manifest | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $Folder 'manifest.json'),
        $json + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}

function Assert-Manifest([string]$Folder,[string]$Kind) {
    $manifestPath = Join-Path $Folder 'manifest.json'
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $manifest.kind -cne $Kind -or
            $manifest.probePort -ne 59281 -or
            $manifest.leaseSeconds -ne 120) {
        throw "The $Kind manifest contract is invalid."
    }
    foreach ($property in $manifest.files.PSObject.Properties) {
        $relative = ([string]$property.Name).Replace('/','\')
        if ($relative -match '(^|\\)\.\.(\\|$)') {
            throw "The $Kind manifest contains an unsafe path."
        }
        $full = [IO.Path]::GetFullPath((Join-Path $Folder $relative))
        $prefix = [IO.Path]::GetFullPath($Folder).TrimEnd('\') + '\'
        if (-not $full.StartsWith($prefix,
                [StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "The $Kind manifest references an invalid file."
        }
        $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).
            Hash.ToLowerInvariant()
        if ($actual -cne [string]$property.Value) {
            throw "The $Kind manifest failed verification."
        }
    }
}

Assert-File $cryptoReportPath 'Native crypto build report'
Assert-File $routeReportPath 'Native route build report'
Assert-File $cryptoDll 'Native crypto candidate'
Assert-File $routeDll 'Native route candidate'
Assert-File $instructionsPath 'Remote acceptance instructions'

$cryptoReport = Get-Content -Raw -LiteralPath $cryptoReportPath |
    ConvertFrom-Json
if ($cryptoReport.schemaVersion -ne 1 -or $cryptoReport.abiVersion -ne 3 -or
        $cryptoReport.target -cne 'x86_64-windows-gnu' -or
        $cryptoReport.status -cne 'engineering-candidate-non-production' -or
        $cryptoReport.productionReady -ne $false -or
        $cryptoReport.checks.exactAbiExportSurface -cne 'pass' -or
        $cryptoReport.checks.providerHandshakeAndReplayConformance -cne 'pass') {
    throw 'The Windows native crypto candidate is not acceptance-ready.'
}
Assert-ReportedArtifact $cryptoReport $cryptoDll 'library'

$routeReport = Get-Content -Raw -LiteralPath $routeReportPath |
    ConvertFrom-Json
if ($routeReport.schemaVersion -ne 1 -or $routeReport.abiVersion -ne 2 -or
        $routeReport.target -cne 'x86_64-windows-gnu' -or
        $routeReport.status -cne 'engineering-candidate-non-production' -or
        $routeReport.productionReady -ne $false -or
        $routeReport.readOnly -ne $true -or
        $routeReport.networkTrafficSent -ne $false -or
        $routeReport.checks.exactAbiExportSurface -cne 'pass' -or
        $routeReport.checks.osBackedNetworkGeneration -cne 'pass' -or
        $routeReport.checks.liveLocalDefaultRoute -cne 'pass') {
    throw 'The Windows native route candidate is not acceptance-ready.'
}
Assert-ReportedArtifact $routeReport $routeDll 'provider'

$loveRootFull = [IO.Path]::GetFullPath($LoveRoot)
$loveConsole = Join-Path $loveRootFull 'lovec.exe'
Assert-File $loveConsole 'LÖVE console runtime'
$loveVersion = [string](Get-Item -LiteralPath $loveConsole).VersionInfo.
    ProductVersion
if ($loveVersion -notmatch '^11\.5(\.|$)') {
    throw "LÖVE 11.5 is required; found '$loveVersion'."
}

Reset-GeneratedDirectory $outputRoot
New-Item -ItemType Directory -Path $appStage,$hostRoot,$guestRoot `
    -Force | Out-Null

$appFiles = [ordered]@{
    'main.lua' = Join-Path $probeSourceRoot 'main.lua'
    'conf.lua' = Join-Path $probeSourceRoot 'conf.lua'
    'src/net/address.lua' = Join-Path $repoRoot 'src\net\address.lua'
    'src/net/crypto_native.lua' = Join-Path $repoRoot 'src\net\crypto_native.lua'
    'src/net/direct_invite.lua' = Join-Path $repoRoot 'src\net\direct_invite.lua'
    'src/net/transport_direct.lua' = Join-Path $repoRoot 'src\net\transport_direct.lua'
    'src/net/transport_enet.lua' = Join-Path $repoRoot 'src\net\transport_enet.lua'
    'src/net/ip_scope.lua' = Join-Path $repoRoot 'src\net\ip_scope.lua'
    'src/net/gateway_native.lua' = Join-Path $repoRoot 'src\net\gateway_native.lua'
    'src/net/gateway_android.lua' = Join-Path $repoRoot 'src\net\gateway_android.lua'
    'src/net/gateway_discovery.lua' = Join-Path $repoRoot 'src\net\gateway_discovery.lua'
    'src/net/mapping_socket_windows.lua' = Join-Path $repoRoot 'src\net\mapping_socket_windows.lua'
    'src/net/upnp_transport_windows.lua' = Join-Path $repoRoot 'src\net\upnp_transport_windows.lua'
    'src/net/upnp_mapping_adapter.lua' = Join-Path $repoRoot 'src\net\upnp_mapping_adapter.lua'
    'src/net/upnp_igd.lua' = Join-Path $repoRoot 'src\net\upnp_igd.lua'
    'src/net/router_mapping_adapter.lua' = Join-Path $repoRoot 'src\net\router_mapping_adapter.lua'
    'src/net/pcp.lua' = Join-Path $repoRoot 'src\net\pcp.lua'
    'src/net/nat_pmp.lua' = Join-Path $repoRoot 'src\net\nat_pmp.lua'
    'src/net/reachability.lua' = Join-Path $repoRoot 'src\net\reachability.lua'
    'src/net/direct_ipv4_listener.lua' = Join-Path $repoRoot 'src\net\direct_ipv4_listener.lua'
    'src/net/direct_ipv4_host.lua' = Join-Path $repoRoot 'src\net\direct_ipv4_host.lua'
    'src/net/public_ipv4_probe_protocol.lua' = Join-Path $repoRoot 'src\net\public_ipv4_probe_protocol.lua'
    'src/net/public_ipv4_probe_watchdog.lua' = Join-Path $repoRoot 'src\net\public_ipv4_probe_watchdog.lua'
}
foreach ($relative in $appFiles.Keys) {
    Copy-RequiredFile $appFiles[$relative] (Join-Path $appStage `
        $relative.Replace('/','\'))
}

$probeText = Get-Content -Raw -LiteralPath (Join-Path $appStage 'main.lua')
foreach ($requiredText in @(
    'ALLOW_TEMPORARY_ROUTER_MAPPING',
    'TPS_PUBLIC_IPV4_TRAFFIC',
    'NETWORK_TRAFFIC_SENT=False',
    'UPNP_TRANSPORT_READY=True',
    'PRODUCTION_GATE_RETAINED=True',
    'DELETION_ACKNOWLEDGED=',
    'LISTENER_CLOSED_BEFORE_DELETE=')) {
    if ($probeText -notmatch [regex]::Escape($requiredText)) {
        throw "The probe lost a required safety gate: $requiredText"
    }
}
$trafficCheckText = Get-Content -Raw -LiteralPath (Join-Path `
    $windowsSourceRoot 'run_mapping_traffic_check.ps1')
foreach ($requiredText in @(
    "'--counters-only'",
    "'--comp','nics'",
    "'filter','add',`$filterName,'-d','IPv4'",
    'PACKET_LOGGING=False',
    'PACKET_CONTENTS_RETAINED=False',
    'NETWORK_DETAILS_RETAINED=False')) {
    if ($trafficCheckText -notmatch [regex]::Escape($requiredText)) {
        throw "The traffic check lost a required safety gate: $requiredText"
    }
}
if ($trafficCheckText -match "'--file-name'|'--pkt-size'|'etl2") {
    throw 'The counters-only traffic check unexpectedly enables packet logging.'
}
foreach ($file in @(Get-ChildItem -LiteralPath $appStage -Recurse `
        -File -Filter '*.lua')) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    # UPnP uses gateway-local numeric HTTP plus two XML namespace identifiers.
    # Remove only those reviewed literals; every other URL/service path remains
    # forbidden in this self-contained probe.
    if ($file.Name -eq 'upnp_igd.lua') {
        $text = $text.Replace('http://schemas.xmlsoap.org/soap/envelope/','')
        $text = $text.Replace('http://schemas.xmlsoap.org/soap/encoding/','')
        $text = $text.Replace('"http://"','')
        $text = $text.Replace('"http:"','')
    }
    if ($text -match '(?i)https?://|socket\.http|io\.popen|os\.execute') {
        throw "The local acceptance probe contains an external-service path: $($file.Name)"
    }
}

[IO.Compression.ZipFile]::CreateFromDirectory($appStage,$lovePackage,
    [IO.Compression.CompressionLevel]::Optimal,$false)
Assert-ExactArchive $lovePackage @($appFiles.Keys)

$runtimeFiles = @(
    'lovec.exe','love.dll','lua51.dll','mpg123.dll','msvcp120.dll',
    'msvcr120.dll','OpenAL32.dll','SDL2.dll','license.txt','readme.txt'
)
foreach ($destinationRoot in @($hostRoot,$guestRoot)) {
    foreach ($runtimeFile in $runtimeFiles) {
        Copy-RequiredFile (Join-Path $loveRootFull $runtimeFile) `
            (Join-Path $destinationRoot "runtime\$runtimeFile")
    }
    Copy-RequiredFile $lovePackage (Join-Path $destinationRoot `
        'public-ipv4-probe.love')
    Copy-RequiredFile $cryptoDll (Join-Path $destinationRoot 'tps_crypto.dll')
    Copy-RequiredFile $instructionsPath (Join-Path $destinationRoot `
        'INSTRUCTIONS.md')
    Copy-RequiredFile (Join-Path $windowsSourceRoot 'run_ipv6_readiness.ps1') `
        (Join-Path $destinationRoot 'run_ipv6_readiness.ps1')
    Copy-RequiredFile (Join-Path $windowsSourceRoot 'Check IPv6 Readiness.bat') `
        (Join-Path $destinationRoot 'Check IPv6 Readiness.bat')
}
Copy-RequiredFile $routeDll (Join-Path $hostRoot 'tps_route.dll')
Copy-RequiredFile (Join-Path $windowsSourceRoot 'run_host.ps1') `
    (Join-Path $hostRoot 'run_host.ps1')
Copy-RequiredFile (Join-Path $windowsSourceRoot `
    'run_mapping_traffic_check.ps1') `
    (Join-Path $hostRoot 'run_mapping_traffic_check.ps1')
Copy-RequiredFile (Join-Path $windowsSourceRoot 'run_guest.ps1') `
    (Join-Path $guestRoot 'run_guest.ps1')
foreach ($name in @('Start Host Preflight.bat','Start Host Mapping Test.bat',
        'Start Host Mapping Traffic Check.bat',
        'Cleanup Host Firewall Rule.bat',
        'Cleanup Mapping Traffic Check.bat',
        'Remove Accidental Test Firewall Rules.bat')) {
    Copy-RequiredFile (Join-Path $windowsSourceRoot $name) `
        (Join-Path $hostRoot $name)
}
Copy-RequiredFile (Join-Path $windowsSourceRoot 'Start Guest.bat') `
    (Join-Path $guestRoot 'Start Guest.bat')
Copy-RequiredFile $instructionsPath (Join-Path $kitRoot 'READ ME FIRST.md')

foreach ($script in @((Join-Path $hostRoot 'run_host.ps1'),
        (Join-Path $hostRoot 'run_mapping_traffic_check.ps1'),
        (Join-Path $hostRoot 'run_ipv6_readiness.ps1'),
        (Join-Path $guestRoot 'run_guest.ps1'),
        (Join-Path $guestRoot 'run_ipv6_readiness.ps1'))) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $script,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -ne 0) {
        throw "A packaged launcher has a PowerShell syntax error: $script"
    }
}

Write-Manifest $hostRoot 'host'
Write-Manifest $guestRoot 'guest'
Assert-Manifest $hostRoot 'host'
Assert-Manifest $guestRoot 'guest'

$expectedKitFiles = @(Get-ChildItem -LiteralPath $kitStage -Recurse -File |
    ForEach-Object {
        $_.FullName.Substring($kitStage.Length).TrimStart('\').Replace('\','/')
    } | Sort-Object)
[IO.Compression.ZipFile]::CreateFromDirectory($kitStage,$zipPath,
    [IO.Compression.CompressionLevel]::Optimal,$false)
Assert-ExactArchive $zipPath $expectedKitFiles

$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).
    Hash.ToLowerInvariant()
$report = @(
    'TPS_PUBLIC_IPV4_KIT_BUILD=PASS',
    'HOST_MANIFEST_VERIFIED=True',
    'GUEST_MANIFEST_VERIFIED=True',
    'NATIVE_CRYPTO_ABI=3',
    'NATIVE_ROUTE_ABI=2',
    'FINITE_LEASE_SECONDS=120',
    'PROBE_PORT=59281',
    'PRODUCTION_GATE_RETAINED=True',
    'NETWORK_TRAFFIC_SENT=False',
    "ZIP_SHA256=$zipHash"
)
[IO.File]::WriteAllLines($reportPath,$report,[Text.UTF8Encoding]::new($false))
$report | Write-Output
Write-Output "PACKAGE=$zipPath"
Write-Output "REPORT=$reportPath"
