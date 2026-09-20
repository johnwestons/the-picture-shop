[CmdletBinding()]
param(
    [switch] $RequireLiveRoute
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'output/native-route'))
$buildRoot = [IO.Path]::GetFullPath((Join-Path $outputRoot 'build/windows-x64'))
$toolingRoot = [IO.Path]::GetFullPath((Join-Path $outputRoot 'tooling'))

function Assert-WithinOutput([string] $Path) {
    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = $outputRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith(
            $prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Native route build path escapes the output directory: $resolved"
    }
    return $resolved
}

function Remove-OutputTree([string] $Path) {
    $resolved = Assert-WithinOutput $Path
    if (-not (Test-Path -LiteralPath $resolved)) { return }
    $item = Get-Item -LiteralPath $resolved -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to remove a native route reparse point: $resolved"
    }
    if (-not $item.PSIsContainer) {
        throw "Expected a generated native route directory: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Resolve-ZigExecutable {
    $archive = [IO.Path]::GetFullPath((Join-Path $repoRoot `
        'output/native-crypto/tooling/zig-x86_64-windows-0.16.0.zip'))
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
        throw 'Pinned Zig 0.16.0 archive is unavailable. Build the native crypto candidate first.'
    }
    $expectedArchiveSha256 =
        '68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e'
    $actualArchiveSha256 = (Get-FileHash -LiteralPath $archive `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualArchiveSha256 -ne $expectedArchiveSha256) {
        throw 'Pinned Zig archive hash check failed.'
    }

    $destination = Assert-WithinOutput (
        (Join-Path $toolingRoot 'zig-68659eb5f1e4'))
    Remove-OutputTree $destination
    $temporary = Assert-WithinOutput (
        "$destination.extract-$([Guid]::NewGuid().ToString('N'))")
    try {
        Expand-Archive -LiteralPath $archive -DestinationPath $temporary
        $entries = @(Get-ChildItem -LiteralPath $temporary -Force)
        if ($entries.Count -ne 1 -or -not $entries[0].PSIsContainer -or
                $entries[0].Name -ne 'zig-x86_64-windows-0.16.0') {
            throw 'Pinned Zig archive has an unexpected root structure.'
        }
        Move-Item -LiteralPath $entries[0].FullName -Destination $destination
        Remove-OutputTree $temporary
    } catch {
        Remove-OutputTree $temporary
        Remove-OutputTree $destination
        throw
    }

    $full = Join-Path $destination 'zig.exe'
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw 'Pinned Zig archive did not contain zig.exe.'
    }
    $expectedExecutableSha256 =
        '086ce9d47ba42f33a514e1a6e04eb1d4a8fa1d75e0868e0213caad447c91e864'
    $actualExecutableSha256 = (Get-FileHash -LiteralPath $full `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualExecutableSha256 -ne $expectedExecutableSha256) {
        throw 'Pinned Zig executable hash check failed.'
    }
    $version = @(& $full version 2>$null)
    if ($LASTEXITCODE -ne 0 -or $version.Count -ne 1 -or
            $version[0] -ne '0.16.0') {
        throw 'Verified Zig version check failed.'
    }
    return $full
}

function Get-PeExportNames([string] $Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $readU16 = {
        param([int] $Offset)
        if ($Offset -lt 0 -or $Offset + 2 -gt $bytes.Length) {
            throw 'Native route provider has a truncated PE structure.'
        }
        [BitConverter]::ToUInt16($bytes, $Offset)
    }
    $readU32 = {
        param([int] $Offset)
        if ($Offset -lt 0 -or $Offset + 4 -gt $bytes.Length) {
            throw 'Native route provider has a truncated PE structure.'
        }
        [BitConverter]::ToUInt32($bytes, $Offset)
    }

    if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
        throw 'Native route provider is not a valid PE image.'
    }
    $peOffset = [int](& $readU32 0x3c)
    if ($peOffset -lt 0 -or $peOffset + 24 -gt $bytes.Length -or
            $bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45 -or
            $bytes[$peOffset + 2] -ne 0 -or $bytes[$peOffset + 3] -ne 0) {
        throw 'Native route provider has an invalid PE header.'
    }

    $sectionCount = [int](& $readU16 ($peOffset + 6))
    $optionalBytes = [int](& $readU16 ($peOffset + 20))
    $optionalOffset = $peOffset + 24
    $optionalMagic = [int](& $readU16 $optionalOffset)
    $directoryOffset = if ($optionalMagic -eq 0x20b) {
        $optionalOffset + 112
    } elseif ($optionalMagic -eq 0x10b) {
        $optionalOffset + 96
    } else {
        throw 'Native route provider has an unsupported PE optional header.'
    }
    $exportRva = [uint32](& $readU32 $directoryOffset)
    if ($exportRva -eq 0 -or $sectionCount -lt 1 -or $sectionCount -gt 96) {
        throw 'Native route provider has no bounded PE export directory.'
    }

    $sectionOffset = $optionalOffset + $optionalBytes
    $sections = @()
    for ($index = 0; $index -lt $sectionCount; $index++) {
        $offset = $sectionOffset + 40 * $index
        if ($offset + 40 -gt $bytes.Length) {
            throw 'Native route provider has a truncated PE section table.'
        }
        $sections += [pscustomobject]@{
            VirtualSize = [uint32](& $readU32 ($offset + 8))
            VirtualAddress = [uint32](& $readU32 ($offset + 12))
            RawSize = [uint32](& $readU32 ($offset + 16))
            RawOffset = [uint32](& $readU32 ($offset + 20))
        }
    }
    $mapRva = {
        param([uint32] $Rva)
        foreach ($section in $sections) {
            $span = [Math]::Max(
                [uint64]$section.VirtualSize, [uint64]$section.RawSize)
            $start = [uint64]$section.VirtualAddress
            if ([uint64]$Rva -ge $start -and [uint64]$Rva -lt $start + $span) {
                $mapped = [uint64]$section.RawOffset + ([uint64]$Rva - $start)
                if ($mapped -ge [uint64]$bytes.Length) {
                    throw 'Native route provider PE export address is out of range.'
                }
                return [int]$mapped
            }
        }
        throw 'Native route provider PE export address is unmapped.'
    }

    $exportOffset = & $mapRva $exportRva
    $functionCount = [uint32](& $readU32 ($exportOffset + 20))
    $nameCount = [uint32](& $readU32 ($exportOffset + 24))
    $nameTableRva = [uint32](& $readU32 ($exportOffset + 32))
    if ($functionCount -ne $nameCount -or $nameCount -lt 1 -or
            $nameCount -gt 16) {
        throw 'Native route provider exports must all be named and bounded.'
    }
    $nameTableOffset = & $mapRva $nameTableRva
    $names = @()
    for ($index = 0; $index -lt $nameCount; $index++) {
        $nameRva = [uint32](& $readU32 ($nameTableOffset + 4 * $index))
        $nameOffset = & $mapRva $nameRva
        $end = $nameOffset
        while ($end -lt $bytes.Length -and $bytes[$end] -ne 0 -and
                $end - $nameOffset -le 63) {
            $end++
        }
        if ($end -ge $bytes.Length -or $bytes[$end] -ne 0 -or
                $end -eq $nameOffset -or $end - $nameOffset -gt 63) {
            throw 'Native route provider has an invalid PE export name.'
        }
        $name = [Text.Encoding]::ASCII.GetString(
            $bytes, $nameOffset, $end - $nameOffset)
        if ($name -notmatch '^tps_route_[a-z0-9_]+$') {
            throw 'Native route provider has an unexpected PE export name.'
        }
        $names += $name
    }
    if (@($names | Sort-Object -Unique).Count -ne $names.Count) {
        throw 'Native route provider has duplicate named PE exports.'
    }
    return @($names | Sort-Object)
}

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$lockPath = Assert-WithinOutput (Join-Path $outputRoot 'build.lock')
try {
    $buildLock = [IO.File]::Open(
        $lockPath,
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None)
} catch {
    throw 'Another native route build is already running.'
}

try {
New-Item -ItemType Directory -Force -Path $buildRoot, $toolingRoot | Out-Null
$zig = Resolve-ZigExecutable
$dll = Join-Path $buildRoot 'tps_route.dll'
$importLibrary = Join-Path $buildRoot 'tps_route.lib'
$testExecutable = Join-Path $buildRoot 'tps_route_test.exe'
$header = Join-Path $repoRoot 'native/route/include/tps_route.h'
$source = Join-Path $repoRoot 'native/route/src/tps_route_windows.c'
$testSource = Join-Path $repoRoot 'native/route/tests/tps_route_test.c'

$compileArguments = @(
    'cc', '-target', 'x86_64-windows-gnu', '-shared', '-O2', '-s', '-std=c11',
    '-Wall', '-Wextra', '-Werror',
    "-I$(Join-Path $repoRoot 'native/route/include')",
    $source, '-liphlpapi', '-lws2_32',
    "-Wl,--out-implib,$importLibrary", '-o', $dll
)
$previousSourceDateEpoch = $env:SOURCE_DATE_EPOCH
try {
    $env:SOURCE_DATE_EPOCH = '0'
    & $zig @compileArguments
    if ($LASTEXITCODE -ne 0) { throw 'Native route provider build failed.' }
} finally {
    $env:SOURCE_DATE_EPOCH = $previousSourceDateEpoch
}
if (-not (Test-Path -LiteralPath $dll -PathType Leaf) -or
        -not (Test-Path -LiteralPath $importLibrary -PathType Leaf)) {
    throw 'Native route provider artifacts were not produced.'
}

$expectedExports = @(
    'tps_route_abi_version',
    'tps_route_default_ipv4'
) | Sort-Object
$actualExports = @(Get-PeExportNames $dll)
if (Compare-Object $expectedExports $actualExports) {
    throw 'Native route provider export surface does not exactly match ABI v2.'
}

$testCompileArguments = @(
    'cc', '-target', 'x86_64-windows-gnu', '-O2', '-std=c11',
    '-Wall', '-Wextra', '-Werror',
    "-I$(Join-Path $repoRoot 'native/route/include')",
    $testSource, $importLibrary, '-lws2_32', '-o', $testExecutable
)
& $zig @testCompileArguments
if ($LASTEXITCODE -ne 0) { throw 'Native route provider test build failed.' }

$testArguments = @()
if ($RequireLiveRoute) { $testArguments += '--require-live' }
$rawTestOutput = @(& $testExecutable @testArguments 2>&1)
$testExit = $LASTEXITCODE
if ($testExit -ne 0) { throw 'Native route provider conformance test failed.' }
$testOutput = @($rawTestOutput | ForEach-Object { [string] $_ })
$allowedTestOutput = @(
    'TPS_ROUTE_NATIVE=PASS',
    'TPS_ROUTE_NATIVE=UNAVAILABLE',
    'TPS_ROUTE_LIVE=PASS',
    'SOURCE_CANONICAL=True',
    'GATEWAY_CANONICAL=True',
    'INTERFACE_INDEX_PRESENT=True',
    'NETWORK_GENERATION_PRESENT=True',
    'NETWORK_TRAFFIC_SENT=False'
)
foreach ($line in $testOutput) {
    if ($allowedTestOutput -notcontains $line) {
        throw 'Native route provider test emitted unexpected output.'
    }
}
$passMarkers = @(
    'TPS_ROUTE_NATIVE=PASS',
    'TPS_ROUTE_LIVE=PASS',
    'SOURCE_CANONICAL=True',
    'GATEWAY_CANONICAL=True',
    'INTERFACE_INDEX_PRESENT=True',
    'NETWORK_GENERATION_PRESENT=True',
    'NETWORK_TRAFFIC_SENT=False'
)
if ($testOutput -contains 'TPS_ROUTE_NATIVE=PASS') {
    if ($testOutput.Count -ne $passMarkers.Count -or
            (Compare-Object $passMarkers $testOutput)) {
        throw 'Native route provider test returned an inconsistent pass result.'
    }
} elseif ($testOutput.Count -ne 1 -or
        $testOutput[0] -ne 'TPS_ROUTE_NATIVE=UNAVAILABLE') {
    throw 'Native route provider test returned an inconsistent unavailable result.'
}
if ($RequireLiveRoute -and $testOutput -notcontains 'TPS_ROUTE_LIVE=PASS') {
    throw 'A live local default route was required but not verified.'
}
foreach ($line in $testOutput) { Write-Output $line }

$liveStatus = if ($testOutput -contains 'TPS_ROUTE_LIVE=PASS') {
    'pass'
} elseif ($RequireLiveRoute) {
    'fail'
} else {
    'not-required'
}
$report = [ordered]@{
    schemaVersion = 1
    status = 'engineering-candidate-non-production'
    abiVersion = 2
    target = 'x86_64-windows-gnu'
    productionReady = $false
    readOnly = $true
    networkTrafficSent = $false
    checks = [ordered]@{
        exactAbiExportSurface = 'pass'
        boundedNativeContract = 'pass'
        osBackedNetworkGeneration = 'pass'
        liveLocalDefaultRoute = $liveStatus
    }
    artifacts = [ordered]@{
        provider = [ordered]@{
            path = 'output/native-route/build/windows-x64/tps_route.dll'
            sha256 = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        conformanceTest = [ordered]@{
            path = 'output/native-route/build/windows-x64/tps_route_test.exe'
            sha256 = (Get-FileHash -LiteralPath $testExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    inputs = [ordered]@{
        providerSourceSha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        abiHeaderSha256 = (Get-FileHash -LiteralPath $header -Algorithm SHA256).Hash.ToLowerInvariant()
        testSourceSha256 = (Get-FileHash -LiteralPath $testSource -Algorithm SHA256).Hash.ToLowerInvariant()
        zigVersion = '0.16.0'
        zigArchiveSha256 = '68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e'
        zigExecutableSha256 = (Get-FileHash -LiteralPath $zig -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$reportPath = Join-Path $buildRoot 'native_route_report.json'
[IO.File]::WriteAllText(
    $reportPath,
    (($report | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false))
Write-Output "REPORT=$reportPath"
} finally {
    $buildLock.Dispose()
}
