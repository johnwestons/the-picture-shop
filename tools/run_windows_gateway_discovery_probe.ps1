[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$provider = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'output/native-route/build/windows-x64/tps_route.dll'))
$buildRoot = [IO.Path]::GetDirectoryName($provider)
$probe = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'tools/probes/windows_gateway_discovery'))
if (-not (Test-Path -LiteralPath $provider -PathType Leaf)) {
    throw 'Build the native route provider before running this probe.'
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

$previousRoot = $env:TPS_GATEWAY_PROBE_ROOT
$previousLibrary = $env:TPS_ROUTE_LIBRARY
function Invoke-GatewayProbe([string] $Library) {
    $env:TPS_ROUTE_LIBRARY = $Library
    $output = @(& $loveConsole $probe 2>&1)
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = $output
    }
}
try {
    $env:TPS_GATEWAY_PROBE_ROOT = $repoRoot.Replace('\', '/')
    $positive = Invoke-GatewayProbe $provider

    $missingLibrary = Join-Path $buildRoot 'tps_route_missing.dll'
    if (Test-Path -LiteralPath $missingLibrary) {
        throw 'The reserved missing-library test path unexpectedly exists.'
    }
    $missing = Invoke-GatewayProbe $missingLibrary

    $systemLibrary = Join-Path $env:SystemRoot 'System32/kernel32.dll'
    if (-not (Test-Path -LiteralPath $systemLibrary -PathType Leaf)) {
        throw 'The system negative-test library is unavailable.'
    }
    $missingSymbol = Invoke-GatewayProbe $systemLibrary
} finally {
    $env:TPS_GATEWAY_PROBE_ROOT = $previousRoot
    $env:TPS_ROUTE_LIBRARY = $previousLibrary
}

$allowed = @(
    'TPS_GATEWAY_DISCOVERY=PASS',
    'DEFAULT_IPV4_ROUTE=VERIFIED',
    'ROUTE_SNAPSHOT_ALLOWLISTED=True',
    'NETWORK_TRAFFIC_SENT=False'
)
if ($positive.ExitCode -ne 0 -or $positive.Output -notcontains $allowed[0]) {
    $reason = @($positive.Output | Where-Object {
        $_ -match '^REASON=[a-z_]+$'
    } | Select-Object -First 1)
    if ($reason.Count -eq 1) { Write-Output $reason[0] }
    throw 'Windows gateway discovery probe failed.'
}
foreach ($marker in $allowed) {
    if ($positive.Output -notcontains $marker) {
        throw 'Windows gateway discovery probe returned an incomplete result.'
    }
    Write-Output $marker
}

$negativeReason = 'REASON=gateway_discovery_unavailable'
if ($missing.ExitCode -eq 0 -or
        $missing.Output -notcontains 'TPS_GATEWAY_DISCOVERY=FAIL' -or
        $missing.Output -notcontains $negativeReason) {
    throw 'A missing native route library did not fail closed.'
}
Write-Output 'MISSING_LIBRARY_FAILS_CLOSED=True'
if ($missingSymbol.ExitCode -eq 0 -or
        $missingSymbol.Output -notcontains 'TPS_GATEWAY_DISCOVERY=FAIL' -or
        $missingSymbol.Output -notcontains $negativeReason) {
    throw 'A native library with a missing ABI symbol did not fail closed.'
}
Write-Output 'MISSING_SYMBOL_FAILS_CLOSED=True'
