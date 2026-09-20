[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$kitRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$loveConsole = Join-Path $kitRoot 'runtime\lovec.exe'
$probePackage = Join-Path $kitRoot 'public-ipv4-probe.love'
$manifestPath = Join-Path $kitRoot 'manifest.json'
$resultPath = Join-Path $kitRoot 'last-guest-result.txt'

function Assert-WithinKit([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $kitRoot.TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'A packaged path escaped the acceptance-kit directory.'
    }
    return $full
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'The guest manifest is missing.'
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.kind -cne 'guest') {
    throw 'The guest manifest contract is invalid.'
}
foreach ($property in $manifest.files.PSObject.Properties) {
    $relative = ([string]$property.Name).Replace('/','\')
    if ($relative -match '(^|\\)\.\.(\\|$)') {
        throw 'The guest manifest contains an unsafe path.'
    }
    $full = Assert-WithinKit (Join-Path $kitRoot $relative)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw 'A packaged guest file is missing.'
    }
    $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).
        Hash.ToLowerInvariant()
    if ($actual -cne [string]$property.Value) {
        throw 'A packaged guest file failed its integrity check.'
    }
}
foreach ($required in @($loveConsole,$probePackage,
        (Join-Path $kitRoot 'tps_crypto.dll'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw 'A required guest component is missing.'
    }
}

if (Test-Path -LiteralPath $resultPath) {
    Remove-Item -LiteralPath $resultPath -Force
}
$priorRole = $env:TPS_PUBLIC_IPV4_PROBE_ROLE
$priorArmed = $env:TPS_PUBLIC_IPV4_PROBE_ARMED
$priorResult = $env:TPS_PUBLIC_IPV4_PROBE_RESULT
try {
    $env:TPS_PUBLIC_IPV4_PROBE_ROLE = 'guest'
    $env:TPS_PUBLIC_IPV4_PROBE_ARMED = ''
    $env:TPS_PUBLIC_IPV4_PROBE_RESULT = $resultPath
    & $loveConsole $probePackage | Out-Null
    $exitCode = $LASTEXITCODE
} finally {
    $env:TPS_PUBLIC_IPV4_PROBE_ROLE = $priorRole
    $env:TPS_PUBLIC_IPV4_PROBE_ARMED = $priorArmed
    $env:TPS_PUBLIC_IPV4_PROBE_RESULT = $priorResult
}
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw 'The guest probe ended without a safe result.'
}
$result = @(Get-Content -LiteralPath $resultPath)
foreach ($line in $result) {
    if ($line -notmatch '^[A-Z0-9_]+=(PASS|FAIL|True|False|[a-z_]+|[0-9]+)$') {
        throw 'The guest probe result contained an unexpected value.'
    }
    Write-Output $line
}
if ($exitCode -ne 0 -or
        $result -notcontains 'TPS_PUBLIC_IPV4_GUEST=PASS') {
    throw 'The guest probe did not pass.'
}
