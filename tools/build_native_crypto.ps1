[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'output/native-crypto'))
$toolingRoot = Join-Path $outputRoot 'tooling'
$downloadsRoot = Join-Path $outputRoot 'downloads'
$vendorRoot = Join-Path $outputRoot 'vendor'
$workRoot = Join-Path $outputRoot 'work'
$buildRoot = Join-Path $outputRoot 'build/windows-x64'
$patchPath = Join-Path $repoRoot 'native/crypto/patches/noise-c-rev32-tps.patch'

function Resolve-GitExecutable {
    $command = Get-Command git.exe -CommandType Application `
        -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return [IO.Path]::GetFullPath($command.Source)
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($PSHOME) {
        $candidates.Add((Join-Path $PSHOME '..\git\cmd\git.exe'))
    }
    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles 'Git\cmd\git.exe'))
    }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe'))
    }
    foreach ($candidate in $candidates) {
        $full = [IO.Path]::GetFullPath($candidate)
        if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
    }
    throw 'Git could not be located for the verified native crypto build.'
}

function Assert-WithinOutput([string] $Path) {
    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = $outputRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Native build path escapes the output directory: $resolved"
    }
    return $resolved
}

function Assert-Sha256([string] $Path, [string] $Expected) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required archive is missing: $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected.ToLowerInvariant()) {
        throw "SHA-256 mismatch for $([IO.Path]::GetFileName($Path))."
    }
}

function Get-PeExportNames([string] $Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $readU16 = {
        param([int] $Offset)
        if ($Offset -lt 0 -or $Offset + 2 -gt $bytes.Length) {
            throw 'Native provider has a truncated PE structure.'
        }
        [BitConverter]::ToUInt16($bytes, $Offset)
    }
    $readU32 = {
        param([int] $Offset)
        if ($Offset -lt 0 -or $Offset + 4 -gt $bytes.Length) {
            throw 'Native provider has a truncated PE structure.'
        }
        [BitConverter]::ToUInt32($bytes, $Offset)
    }

    if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
        throw 'Native provider is not a valid PE image.'
    }
    $peOffset = [int](& $readU32 0x3c)
    if ($peOffset -lt 0 -or $peOffset + 24 -gt $bytes.Length -or
            $bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45 -or
            $bytes[$peOffset + 2] -ne 0 -or $bytes[$peOffset + 3] -ne 0) {
        throw 'Native provider has an invalid PE header.'
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
        throw 'Native provider has an unsupported PE optional header.'
    }
    $exportRva = [uint32](& $readU32 $directoryOffset)
    if ($exportRva -eq 0 -or $sectionCount -lt 1 -or $sectionCount -gt 96) {
        throw 'Native provider has no bounded PE export directory.'
    }

    $sectionOffset = $optionalOffset + $optionalBytes
    $sections = @()
    for ($index = 0; $index -lt $sectionCount; $index++) {
        $offset = $sectionOffset + 40 * $index
        if ($offset + 40 -gt $bytes.Length) {
            throw 'Native provider has a truncated PE section table.'
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
                    throw 'Native provider PE export address is out of range.'
                }
                return [int]$mapped
            }
        }
        throw 'Native provider PE export address is unmapped.'
    }

    $exportOffset = & $mapRva $exportRva
    $functionCount = [uint32](& $readU32 ($exportOffset + 20))
    $nameCount = [uint32](& $readU32 ($exportOffset + 24))
    $nameTableRva = [uint32](& $readU32 ($exportOffset + 32))
    if ($functionCount -ne $nameCount -or $nameCount -lt 1 -or $nameCount -gt 128) {
        throw 'Native provider PE exports must all be named and bounded.'
    }
    $nameTableOffset = & $mapRva $nameTableRva
    $names = @()
    for ($index = 0; $index -lt $nameCount; $index++) {
        $nameRva = [uint32](& $readU32 ($nameTableOffset + 4 * $index))
        $nameOffset = & $mapRva $nameRva
        $end = $nameOffset
        while ($end -lt $bytes.Length -and $bytes[$end] -ne 0 -and
                $end - $nameOffset -le 127) {
            $end++
        }
        if ($end -ge $bytes.Length -or $bytes[$end] -ne 0 -or
                $end -eq $nameOffset -or $end - $nameOffset -gt 127) {
            throw 'Native provider has an invalid PE export name.'
        }
        $name = [Text.Encoding]::ASCII.GetString(
            $bytes, $nameOffset, $end - $nameOffset)
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw 'Native provider has an invalid PE export name.'
        }
        $names += $name
    }
    if (@($names | Sort-Object -Unique).Count -ne $names.Count) {
        throw 'Native provider has duplicate named PE exports.'
    }
    return @($names | Sort-Object)
}

function Remove-OutputTree([string] $Path) {
    $resolved = Assert-WithinOutput $Path
    if (-not (Test-Path -LiteralPath $resolved)) { return }
    $item = Get-Item -LiteralPath $resolved -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to remove a reparse point during the native build: $resolved"
    }
    if (-not $item.PSIsContainer) {
        throw "Expected a generated directory, not a file: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Assert-SafeTar([string] $Archive) {
    $members = @(& tar -tzf $Archive)
    if ($LASTEXITCODE -ne 0 -or $members.Count -eq 0) {
        throw "Could not inspect $Archive."
    }
    foreach ($member in $members) {
        $normalized = ([string] $member).Replace('\', '/').TrimEnd('/')
        if (-not $normalized) { continue }
        $segments = $normalized.Split('/')
        if ($normalized.StartsWith('/') -or $normalized -match '^[A-Za-z]:' -or
                $segments -contains '..') {
            throw "Archive contains an unsafe member path: $member"
        }
    }
    $verboseMembers = @(& tar -tvzf $Archive)
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect archive links in $Archive." }
    if ($verboseMembers | Where-Object { $_ -match '^[lh]' }) {
        throw "Archive links are not allowed in pinned native inputs: $Archive"
    }
}

function Get-PinnedArchive(
    [string] $Url,
    [string] $Destination,
    [string] $Sha256
) {
    $Destination = Assert-WithinOutput $Destination
    if (Test-Path -LiteralPath $Destination) {
        Assert-Sha256 $Destination $Sha256
        return
    }

    $temporary = "$Destination.part-$([Guid]::NewGuid().ToString('N'))"
    $temporary = Assert-WithinOutput $temporary
    Invoke-WebRequest -Uri $Url -OutFile $temporary
    try {
        Assert-Sha256 $temporary $Sha256
        Move-Item -LiteralPath $temporary -Destination $Destination
    } catch {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            [IO.File]::Delete($temporary)
        }
        throw
    }
}

function Expand-PinnedTar(
    [string] $Archive,
    [string] $Destination
) {
    $Destination = Assert-WithinOutput $Destination
    Assert-SafeTar $Archive
    Remove-OutputTree $Destination
    $temporary = Assert-WithinOutput (
        "$Destination.extract-$([Guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $temporary | Out-Null
    try {
        & tar -xzf $Archive -C $temporary --strip-components=1
        if ($LASTEXITCODE -ne 0) { throw "Could not extract $Archive." }
        Move-Item -LiteralPath $temporary -Destination $Destination
    } catch {
        Remove-OutputTree $temporary
        throw
    }
}

function Expand-PinnedZig(
    [string] $Archive,
    [string] $Destination
) {
    $Destination = Assert-WithinOutput $Destination
    Remove-OutputTree $Destination
    $temporary = Assert-WithinOutput (
        "$Destination.extract-$([Guid]::NewGuid().ToString('N'))")
    try {
        Expand-Archive -LiteralPath $Archive -DestinationPath $temporary
        $zigExecutable = Get-ChildItem -LiteralPath $temporary -Filter zig.exe -File -Recurse |
            Select-Object -First 1
        if (-not $zigExecutable) { throw 'Pinned Zig archive did not contain zig.exe.' }
        Move-Item -LiteralPath $zigExecutable.Directory.FullName -Destination $Destination
        Remove-OutputTree $temporary
    } catch {
        Remove-OutputTree $temporary
        throw
    }
}

$buildDirectories = @($toolingRoot, $downloadsRoot, $vendorRoot, $workRoot, $buildRoot)
New-Item -ItemType Directory -Force -Path $buildDirectories | Out-Null

$zigArchive = Join-Path $outputRoot 'tooling/zig-x86_64-windows-0.16.0.zip'
$noiseSpecArchive = Join-Path $downloadsRoot 'noise_spec-ecdf084ece2bf92b16b1201b6ae5c99d23fb4151.tar.gz'
$cacophonyArchive = Join-Path $downloadsRoot 'cacophony-8ee9d41e34a1a596cfa3ab12aa4069ff87dc1247.tar.gz'
$noiseArchive = Join-Path $downloadsRoot 'noise-c-rev32.tar.gz'
$sodiumArchive = Join-Path $downloadsRoot 'libsodium-1.0.22-stable.tar.gz'

Get-PinnedArchive 'https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip' $zigArchive '68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e'
Get-PinnedArchive 'https://codeload.github.com/noiseprotocol/noise_spec/tar.gz/ecdf084ece2bf92b16b1201b6ae5c99d23fb4151' $noiseSpecArchive '992e27784cf48ad3bb93213b26f82e5fe5e3175f8274fc11922bff48ecbf9383'
Get-PinnedArchive 'https://codeload.github.com/centromere/cacophony/tar.gz/8ee9d41e34a1a596cfa3ab12aa4069ff87dc1247' $cacophonyArchive '55f86375f5ed487b9426603e42e8f42344e9bb34e3dcd05bd2c47855037e2123'
Get-PinnedArchive 'https://codeload.github.com/rweather/noise-c/tar.gz/4c02abf6e097f33991fd6799d65c4a96083bf8fe' $noiseArchive '94c010364df4e141cde13b8ff9d69e08bcf2572134a6f6aa5d154d36d239165c'
Get-PinnedArchive 'https://download.libsodium.org/libsodium/releases/libsodium-1.0.22-stable.tar.gz' $sodiumArchive '3f909c648c5b6391f121cc7d1a979504c2a601f47c7aefe6140d47e81c7f0339'

$zigDirectory = Join-Path $outputRoot 'tooling/zig-68659eb5f1e4'
$noiseSource = Join-Path $vendorRoot 'noise-c-94c010364df4'
$sodiumSource = Join-Path $vendorRoot 'libsodium-3f909c648c5b'
Expand-PinnedZig $zigArchive $zigDirectory
Expand-PinnedTar $noiseArchive $noiseSource
Expand-PinnedTar $sodiumArchive $sodiumSource
$zig = Join-Path $zigDirectory 'zig.exe'
if ((& $zig version) -ne '0.16.0') { throw 'Pinned Zig version check failed.' }

$patchSha = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
$patchedNoise = Join-Path $workRoot ("noise-c-94c010364df4-patch-" +
    $patchSha.Substring(0, 12))
Remove-OutputTree $patchedNoise
Copy-Item -LiteralPath $noiseSource -Destination $patchedNoise -Recurse
$relative = [IO.Path]::GetRelativePath($repoRoot, $patchedNoise).Replace('\', '/')
$include = "$relative/**"
$gitExecutable = Resolve-GitExecutable
& $gitExecutable -C $repoRoot apply --directory=$relative --include=$include --check $patchPath
if ($LASTEXITCODE -ne 0) { throw 'Noise-C patch validation failed.' }
& $gitExecutable -C $repoRoot apply --directory=$relative --include=$include $patchPath
if ($LASTEXITCODE -ne 0) { throw 'Noise-C patch application failed.' }

$sodiumPrefix = Join-Path $buildRoot 'libsodium'
$sodiumCache = Join-Path $outputRoot 'cache/libsodium-windows-x64'
Remove-OutputTree $sodiumPrefix
Remove-OutputTree $sodiumCache
New-Item -ItemType Directory -Force -Path $sodiumCache | Out-Null
Push-Location $sodiumSource
$previousSourceDateEpoch = $env:SOURCE_DATE_EPOCH
try {
    $env:SOURCE_DATE_EPOCH = '0'
    $sodiumBuildArguments = @(
        'build', '-Dtarget=x86_64-windows-gnu', '-Doptimize=ReleaseSafe',
        '-Dstatic=true', '-Dshared=false', '-Dtest=false',
        '--cache-dir', $sodiumCache, '--prefix', $sodiumPrefix,
        '--seed', '0'
    )
    & $zig @sodiumBuildArguments
    if ($LASTEXITCODE -ne 0) { throw 'Pinned libsodium build failed.' }
} finally {
    $env:SOURCE_DATE_EPOCH = $previousSourceDateEpoch
    Pop-Location
}

$sodiumLibrary = Join-Path $sodiumPrefix 'lib/libsodium-static.lib'
$sodiumInclude = Join-Path $sodiumPrefix 'include'
if (-not (Test-Path -LiteralPath $sodiumLibrary -PathType Leaf)) {
    throw 'Pinned libsodium library was not produced.'
}

$noiseSources = @(
    'src/protocol/cipherstate.c',
    'src/protocol/dhstate.c',
    'src/protocol/errors.c',
    'src/protocol/handshakestate.c',
    'src/protocol/hashstate.c',
    'src/protocol/names.c',
    'src/protocol/patterns.c',
    'src/protocol/symmetricstate.c',
    'src/protocol/util.c',
    'src/protocol/rand_sodium.c',
    'src/backend/sodium/cipher-chachapoly.c',
    'src/backend/sodium/dh-curve25519.c',
    'src/backend/ref/hash-blake2s.c',
    'src/crypto/blake2/blake2s.c'
) | ForEach-Object { Join-Path $patchedNoise $_ }

$dll = Join-Path $buildRoot 'tps_crypto.dll'
$importLibrary = Join-Path $buildRoot 'tps_crypto.lib'
$testExecutable = Join-Path $buildRoot 'tps_crypto_test.exe'
$expectedExports = @(
    'tps_crypto_abi_version', 'tps_crypto_admission_token',
    'tps_crypto_init', 'tps_crypto_random', 'tps_crypto_self_test',
    'tps_crypto_response_tag', 'tps_crypto_response_verify',
    'tps_crypto_opening_state_free', 'tps_crypto_opening_state_is_ready',
    'tps_crypto_opening_state_new', 'tps_crypto_opening_state_next',
    'tps_crypto_opening_state_receive',
    'tps_crypto_bridge_state_free', 'tps_crypto_bridge_state_new',
    'tps_crypto_bridge_state_open', 'tps_crypto_bridge_state_seal',
    'tps_crypto_state_free', 'tps_crypto_state_handshake',
    'tps_crypto_state_is_ready', 'tps_crypto_state_new',
    'tps_crypto_state_open', 'tps_crypto_state_seal',
    'tps_crypto_state_start', 'tps_crypto_suite'
) | Sort-Object
$compileArguments = @(
    'cc', '-target', 'x86_64-windows-gnu', '-shared', '-O2', '-s', '-std=c11',
    '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
    '-DSODIUM_STATIC=1', '-DUSE_LIBSODIUM=1', '-DUSE_OPENSSL=0',
    '-DHAVE_PTHREAD=0',
    "-I$(Join-Path $repoRoot 'native/crypto/include')",
    "-I$(Join-Path $patchedNoise 'include')",
    "-I$(Join-Path $patchedNoise 'src')",
    "-I$(Join-Path $patchedNoise 'src/protocol')",
    "-I$sodiumInclude",
    (Join-Path $repoRoot 'native/crypto/src/tps_crypto.c')
) + $noiseSources + @(
    $sodiumLibrary, '-ladvapi32', '-lcrypt32', '-o', $dll
)
$previousSourceDateEpoch = $env:SOURCE_DATE_EPOCH
try {
    $env:SOURCE_DATE_EPOCH = '0'
    & $zig @compileArguments
    if ($LASTEXITCODE -ne 0) { throw 'Native provider build failed.' }
} finally {
    $env:SOURCE_DATE_EPOCH = $previousSourceDateEpoch
}
if (-not (Test-Path -LiteralPath $dll -PathType Leaf) -or
    -not (Test-Path -LiteralPath $importLibrary -PathType Leaf)) {
    throw 'Native provider artifacts were not produced.'
}
$actualExports = @(Get-PeExportNames $dll)
if (Compare-Object $expectedExports $actualExports) {
    throw 'Native provider export surface does not exactly match ABI v3.'
}

$testCompileArguments = @(
    'cc', '-target', 'x86_64-windows-gnu', '-O2', '-std=c11',
    '-Wall', '-Wextra', '-Werror',
    "-I$(Join-Path $repoRoot 'native/crypto/include')",
    (Join-Path $repoRoot 'native/crypto/tests/tps_crypto_test.c'),
    $importLibrary, '-o', $testExecutable
)
& $zig @testCompileArguments
if ($LASTEXITCODE -ne 0) { throw 'Native provider test build failed.' }
& $testExecutable
if ($LASTEXITCODE -ne 0) { throw 'Native provider conformance test failed.' }

$report = [ordered]@{
    schemaVersion = 1
    status = 'engineering-candidate-non-production'
    suite = 'TPS-Direct-v3/Noise_NNpsk0_25519_ChaChaPoly_BLAKE2s/XChaCha20-Poly1305'
    abiVersion = 3
    target = 'x86_64-windows-gnu'
    productionReady = $false
    checks = [ordered]@{
        pinnedArchiveHashes = 'pass'
        cleanSourceExtraction = 'pass'
        noiseCMaintainedPatch = 'pass'
        libsodiumKnownAnswerTests = 'pass'
        pinnedCacophonyNoiseVector = 'pass'
        deterministicTpsProviderV2KnownAnswer = 'pass'
        providerHandshakeAndReplayConformance = 'pass'
        responseAuthenticationConformance = 'pass'
        simultaneousOpeningConformance = 'pass'
        bridgeFragmentAuthenticationConformance = 'pass'
        exactAbiExportSurface = 'pass'
        reproducibleBinary = 'not-run-use-tools/verify_native_crypto_reproducible.ps1'
    }
    artifacts = [ordered]@{
        library = [ordered]@{
            path = 'output/native-crypto/build/windows-x64/tps_crypto.dll'
            sha256 = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()
            exportCount = $actualExports.Count
            exports = $actualExports
        }
        testExecutable = [ordered]@{
            path = 'output/native-crypto/build/windows-x64/tps_crypto_test.exe'
            sha256 = (Get-FileHash -LiteralPath $testExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    inputs = [ordered]@{
        zigVersion = (& $zig version)
        zigArchiveSha256 = (Get-FileHash -LiteralPath $zigArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        noiseSpecArchiveSha256 = (Get-FileHash -LiteralPath $noiseSpecArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        cacophonyArchiveSha256 = (Get-FileHash -LiteralPath $cacophonyArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        noiseCArchiveSha256 = (Get-FileHash -LiteralPath $noiseArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        libsodiumArchiveSha256 = (Get-FileHash -LiteralPath $sodiumArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        noiseCPatchSha256 = $patchSha
        providerSourceSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'native/crypto/src/tps_crypto.c') -Algorithm SHA256).Hash.ToLowerInvariant()
        abiHeaderSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'native/crypto/include/tps_crypto.h') -Algorithm SHA256).Hash.ToLowerInvariant()
        testSourceSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'native/crypto/tests/tps_crypto_test.c') -Algorithm SHA256).Hash.ToLowerInvariant()
        dependencyManifestSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'native/crypto/dependencies.json') -Algorithm SHA256).Hash.ToLowerInvariant()
        buildScriptSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$reportPath = Join-Path $buildRoot 'native_crypto_report.json'
$json = $report | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($reportPath, $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))

Write-Output "TPS_NATIVE_CRYPTO_BUILD_OK"
Write-Output $dll
Write-Output $reportPath
