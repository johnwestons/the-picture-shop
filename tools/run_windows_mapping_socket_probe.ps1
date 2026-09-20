[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$provider = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'output/native-route/build/windows-x64/tps_route.dll'))
$cryptoProvider = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'output/native-crypto/build/windows-x64/tps_crypto.dll'))
$probe = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'tools/probes/windows_mapping_socket'))
if (-not (Test-Path -LiteralPath $provider -PathType Leaf)) {
    throw 'Build the native route provider before running this probe.'
}
if (-not (Test-Path -LiteralPath $cryptoProvider -PathType Leaf)) {
    throw 'Build the native crypto provider before running this probe.'
}

$candidates = [System.Collections.Generic.List[string]]::new()
$command = Get-Command lovec.exe -CommandType Application `
    -ErrorAction SilentlyContinue | Select-Object -First 1
if ($command) { $candidates.Add($command.Source) }
if ($env:ProgramFiles) {
    $candidates.Add((Join-Path $env:ProgramFiles 'LOVE/lovec.exe'))
}
$candidates.Add((Join-Path $repoRoot 'runtime/love/lovec.exe'))
$loveConsole = $null
foreach ($candidate in $candidates) {
    $full = [IO.Path]::GetFullPath($candidate)
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $loveConsole = $full
        break
    }
}
if (-not $loveConsole) { throw 'The LÖVE console runtime is unavailable.' }

$previousRoot = $env:TPS_MAPPING_SOCKET_PROBE_ROOT
$previousLibrary = $env:TPS_ROUTE_LIBRARY
$previousCryptoLibrary = $env:TPS_CRYPTO_LIBRARY
try {
    $env:TPS_MAPPING_SOCKET_PROBE_ROOT = $repoRoot.Replace('\', '/')
    $env:TPS_ROUTE_LIBRARY = $provider
    $env:TPS_CRYPTO_LIBRARY = $cryptoProvider
    $output = @(& $loveConsole $probe 2>&1)
    $exitCode = $LASTEXITCODE
} finally {
    $env:TPS_MAPPING_SOCKET_PROBE_ROOT = $previousRoot
    $env:TPS_ROUTE_LIBRARY = $previousLibrary
    $env:TPS_CRYPTO_LIBRARY = $previousCryptoLibrary
}

$required = @(
    'TPS_MAPPING_SOCKET=PASS',
    'SOURCE_ADDRESS_BOUND=True',
    'INTERFACE_INDEX_BOUND=True',
    'GATEWAY_ROUTE_MATCHED=True',
    'NETWORK_GENERATION_BOUND=True',
    'SECURE_IPV4_LISTENER_BOUND=True',
    'WILDCARD_BIND_USED=False',
    'INVITATION_CREATED=False',
    'PRODUCTION_GATE_RETAINED=True',
    'NETWORK_TRAFFIC_SENT=False'
)
if ($exitCode -ne 0) {
    $reason = @($output | Where-Object { $_ -match '^REASON=[a-z_]+$' } |
        Select-Object -First 1)
    if ($reason.Count -eq 1) { Write-Output $reason[0] }
    throw 'Windows mapping-socket probe failed.'
}
foreach ($marker in $required) {
    if ($output -notcontains $marker) {
        throw 'Windows mapping-socket probe returned an incomplete result.'
    }
    Write-Output $marker
}
