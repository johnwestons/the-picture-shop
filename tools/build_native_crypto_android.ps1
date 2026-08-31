[CmdletBinding()]
param(
    [string] $NdkPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$nativeOutputRoot = [IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'output/native-crypto'))
$androidBuildRoot = Join-Path $nativeOutputRoot 'build/android'
if (-not $NdkPath) {
    $NdkPath = Join-Path $repoRoot `
        'output/mobile/tooling/android-sdk/ndk/25.2.9519653'
}
$NdkPath = [IO.Path]::GetFullPath($NdkPath)

function Assert-WithinNativeOutput([string] $Path) {
    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = $nativeOutputRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith(
            $prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Android native build path escapes its output root: $resolved"
    }
    return $resolved
}

function Reset-GeneratedDirectory([string] $Path) {
    $resolved = Assert-WithinNativeOutput $Path
    if (Test-Path -LiteralPath $resolved) {
        $item = Get-Item -LiteralPath $resolved -Force
        if (-not $item.PSIsContainer -or
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to replace an unexpected Android build path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    New-Item -ItemType Directory -Path $resolved | Out-Null
    return $resolved
}

function Response-Argument([string] $Value) {
    $normalized = $Value.Replace('\', '/')
    if ($normalized -match '\s') {
        return '"' + $normalized.Replace('"', '\"') + '"'
    }
    return $normalized
}

if (-not (Test-Path -LiteralPath (Join-Path $NdkPath 'source.properties'))) {
    throw "Android NDK is not installed at $NdkPath"
}
$toolchainBin = Join-Path $NdkPath `
    'toolchains/llvm/prebuilt/windows-x86_64/bin'
$clang = Join-Path $toolchainBin 'clang.exe'
$readelf = Join-Path $toolchainBin 'llvm-readelf.exe'
$nm = Join-Path $toolchainBin 'llvm-nm.exe'
$sysroot = Join-Path $NdkPath `
    'toolchains/llvm/prebuilt/windows-x86_64/sysroot'
foreach ($required in @($clang, $readelf, $nm)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Android NDK tool is missing: $required"
    }
}

# This performs clean archive extraction, patch application, pinned dependency
# tests, and Windows conformance before Android consumes the staged sources.
& (Join-Path $PSScriptRoot 'build_native_crypto.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Pinned native source preparation failed.' }

$windowsReportPath = Join-Path $nativeOutputRoot `
    'build/windows-x64/native_crypto_report.json'
$windowsReport = Get-Content -Raw -LiteralPath $windowsReportPath |
    ConvertFrom-Json
if ([int]$windowsReport.abiVersion -ne 3 -or
        $windowsReport.status -cne 'engineering-candidate-non-production' -or
        $windowsReport.productionReady -ne $false -or
        [int]$windowsReport.artifacts.library.exportCount -ne 24 -or
        $windowsReport.checks.exactAbiExportSurface -cne 'pass' -or
        $windowsReport.checks.responseAuthenticationConformance -cne 'pass' -or
        $windowsReport.checks.simultaneousOpeningConformance -cne 'pass' -or
        $windowsReport.checks.bridgeFragmentAuthenticationConformance -cne 'pass') {
    throw 'Windows native preparation did not produce the required ABI v3 engineering candidate.'
}
$dependencyManifestPath = Join-Path $repoRoot 'native/crypto/dependencies.json'
$dependencyManifest = Get-Content -Raw -LiteralPath $dependencyManifestPath |
    ConvertFrom-Json
$sodiumDependencies = @($dependencyManifest.dependencies |
    Where-Object { $_.name -eq 'libsodium' })
if ($sodiumDependencies.Count -ne 1) {
    throw 'The native dependency manifest must contain exactly one libsodium pin.'
}
$sodiumDependency = $sodiumDependencies[0]
$sodiumArchive = Join-Path $nativeOutputRoot `
    (Join-Path 'downloads' ([string] $sodiumDependency.archiveFile))
if (-not (Test-Path -LiteralPath $sodiumArchive -PathType Leaf)) {
    throw "Prepared libsodium source archive is missing: $sodiumArchive"
}
$sodiumArchiveHash = (Get-FileHash -LiteralPath $sodiumArchive `
    -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sodiumArchiveHash -cne ([string] $sodiumDependency.sha256).ToLowerInvariant()) {
    throw 'Prepared libsodium source archive does not match its manifest pin.'
}
$windowsSodiumVersionHeader = Join-Path $nativeOutputRoot `
    'build/windows-x64/libsodium/include/sodium/version.h'
if (-not (Test-Path -LiteralPath $windowsSodiumVersionHeader -PathType Leaf)) {
    throw "Prepared libsodium version header is missing: $windowsSodiumVersionHeader"
}
$patchPrefix = ([string] $windowsReport.inputs.noiseCPatchSha256).Substring(0, 12)
$noiseSource = Join-Path $nativeOutputRoot `
    "work/noise-c-94c010364df4-patch-$patchPrefix"
$sodiumSource = Join-Path $nativeOutputRoot `
    "vendor/libsodium-$($sodiumArchiveHash.Substring(0, 12))"
foreach ($source in @($noiseSource, $sodiumSource)) {
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Prepared native dependency source is missing: $source"
    }
}

# The stable libsodium source archive intentionally contains version.h.in.
# Reuse the concrete header produced by the clean pinned-source preparation,
# but stage only that generated header so Android cannot accidentally consume
# host-target headers or libraries from the Windows prefix.
$androidBuildRoot = Reset-GeneratedDirectory $androidBuildRoot
$generatedSodiumInclude = Join-Path $androidBuildRoot 'generated/include'
$generatedSodiumDirectory = Join-Path $generatedSodiumInclude 'sodium'
New-Item -ItemType Directory -Path $generatedSodiumDirectory | Out-Null
Copy-Item -LiteralPath $windowsSodiumVersionHeader -Destination `
    (Join-Path $generatedSodiumDirectory 'version.h')

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
) | ForEach-Object { Join-Path $noiseSource $_ }
$sodiumSources = @(Get-ChildItem -LiteralPath `
    (Join-Path $sodiumSource 'src/libsodium') -Recurse -File -Filter '*.c' |
    Sort-Object FullName | Select-Object -ExpandProperty FullName)
if ($sodiumSources.Count -lt 100) {
    throw 'Pinned libsodium source enumeration is unexpectedly incomplete.'
}

$commonArguments = @(
    '-shared', '-O2', '-s', '-std=c11', '-fPIC',
    '-ffunction-sections', '-fdata-sections', '-fvisibility=hidden',
    '-fno-strict-aliasing', '-fno-strict-overflow', '-fwrapv',
    '-Werror=vla', '-Wno-unused-parameter',
    '-D_GNU_SOURCE=1', '-DCONFIGURED=1', '-DDEV_MODE=1',
    '-DHAVE_ATOMIC_OPS=1', '-DHAVE_C11_MEMORY_FENCES=1',
    '-DHAVE_GCC_MEMORY_FENCES=1', '-DHAVE_INLINE_ASM=1',
    '-DHAVE_INTTYPES_H=1', '-DHAVE_STDINT_H=1',
    '-DNATIVE_LITTLE_ENDIAN=1', '-DASM_HIDE_SYMBOL=.hidden',
    '-DTLS=_Thread_local', '-DHAVE_CATCHABLE_ABRT=1',
    '-DHAVE_CATCHABLE_SEGV=1', '-DHAVE_CLOCK_GETTIME=1',
    '-DHAVE_GETPID=1', '-DHAVE_MADVISE=1', '-DHAVE_MLOCK=1',
    '-DHAVE_MMAP=1', '-DHAVE_MPROTECT=1', '-DHAVE_NANOSLEEP=1',
    '-DHAVE_POSIX_MEMALIGN=1', '-DHAVE_PTHREAD_PRIO_INHERIT=1',
    '-DHAVE_PTHREAD=1', '-DHAVE_RAISE=1', '-DHAVE_SYSCONF=1',
    '-DHAVE_SYS_AUXV_H=1', '-DHAVE_SYS_MMAN_H=1',
    '-DHAVE_SYS_PARAM_H=1', '-DHAVE_WEAK_SYMBOLS=1',
    '-DSODIUM_STATIC=1', '-DUSE_LIBSODIUM=1', '-DUSE_OPENSSL=0',
    "-I$generatedSodiumInclude",
    "-I$generatedSodiumDirectory",
    "-I$(Join-Path $repoRoot 'native/crypto/include')",
    "-I$(Join-Path $noiseSource 'include')",
    "-I$(Join-Path $noiseSource 'src')",
    "-I$(Join-Path $noiseSource 'src/protocol')",
    "-I$(Join-Path $sodiumSource 'src/libsodium/include')",
    "-I$(Join-Path $sodiumSource 'src/libsodium/include/sodium')"
)
$linkArguments = @(
    '-Wl,--gc-sections', '-Wl,--exclude-libs,ALL',
    '-Wl,--no-undefined', '-Wl,--fatal-warnings', '-Wl,--build-id=sha1',
    '-Wl,-z,relro', '-Wl,-z,now',
    '-Wl,-z,max-page-size=16384', '-Wl,-z,common-page-size=16384',
    '-Wl,-soname,libtps_crypto.so', '-latomic'
)
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
$targets = @(
    [ordered]@{ abi = 'armeabi-v7a'; triple = 'armv7a-linux-androideabi21';
        elfClass = 'ELF32'; machine = 'ARM'; tiMode = $false },
    [ordered]@{ abi = 'arm64-v8a'; triple = 'aarch64-linux-android21';
        elfClass = 'ELF64'; machine = 'AArch64'; tiMode = $true },
    [ordered]@{ abi = 'x86_64'; triple = 'x86_64-linux-android21';
        elfClass = 'ELF64'; machine = 'Advanced Micro Devices X86-64';
        tiMode = $true }
)

$artifactReports = [ordered]@{}
$previousSourceDateEpoch = $env:SOURCE_DATE_EPOCH
try {
    $env:SOURCE_DATE_EPOCH = '0'
    foreach ($target in $targets) {
        $abiRoot = Reset-GeneratedDirectory `
            (Join-Path $androidBuildRoot $target.abi)
        $library = Join-Path $abiRoot 'libtps_crypto.so'
        $arguments = [Collections.Generic.List[string]]::new()
        $arguments.Add("--target=$($target.triple)")
        $arguments.Add("--sysroot=$sysroot")
        foreach ($argument in $commonArguments) { $arguments.Add($argument) }
        if ($target.tiMode) { $arguments.Add('-DHAVE_TI_MODE=1') }
        $arguments.Add((Join-Path $repoRoot 'native/crypto/src/tps_crypto.c'))
        foreach ($source in $noiseSources) { $arguments.Add($source) }
        foreach ($source in $sodiumSources) { $arguments.Add($source) }
        foreach ($argument in $linkArguments) { $arguments.Add($argument) }
        $arguments.Add('-o')
        $arguments.Add($library)

        $responsePath = Join-Path $abiRoot 'compile.rsp'
        $responseLines = $arguments | ForEach-Object { Response-Argument $_ }
        [IO.File]::WriteAllLines($responsePath, $responseLines,
            [Text.UTF8Encoding]::new($false))
        & $clang "@$responsePath"
        if ($LASTEXITCODE -ne 0 -or
                -not (Test-Path -LiteralPath $library -PathType Leaf)) {
            throw "Android native provider build failed for $($target.abi)."
        }

        $header = (& $readelf -h $library) -join "`n"
        if ($LASTEXITCODE -ne 0 -or
                $header -notmatch "Class:\s+$([regex]::Escape($target.elfClass))" -or
                $header -notmatch "Machine:\s+$([regex]::Escape($target.machine))") {
            throw "Android ELF identity check failed for $($target.abi)."
        }
        $loadLines = @(& $readelf -lW $library |
            Where-Object { $_ -match '^\s*LOAD\s' })
        if ($LASTEXITCODE -ne 0 -or $loadLines.Count -eq 0 -or
                ($loadLines | Where-Object { $_ -notmatch '\s0x4000\s*$' })) {
            throw "Android 16 KiB LOAD alignment check failed for $($target.abi)."
        }
        $exports = @(& $nm -D --defined-only $library | ForEach-Object {
            if ($_ -match '\s([A-Za-z_][A-Za-z0-9_]*)$') { $Matches[1] }
        } | Sort-Object)
        if ($LASTEXITCODE -ne 0 -or
                (Compare-Object $expectedExports $exports)) {
            throw "Android export-surface check failed for $($target.abi)."
        }
        $dynamic = (& $readelf -d $library) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $dynamic -notmatch '\bBIND_NOW\b') {
            throw "Android immediate-binding hardening check failed for $($target.abi)."
        }
        $artifactReports[$target.abi] = [ordered]@{
            path = "output/native-crypto/build/android/$($target.abi)/libtps_crypto.so"
            target = $target.triple
            sha256 = (Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant()
            bytes = (Get-Item -LiteralPath $library).Length
            elfClass = $target.elfClass
            machine = $target.machine
            loadAlignment = '0x4000'
            exportCount = $exports.Count
            exports = $exports
            runtimeConformance = 'pending-device'
        }
    }
} finally {
    $env:SOURCE_DATE_EPOCH = $previousSourceDateEpoch
}

$clangVersion = (& $clang --version | Select-Object -First 1)
$report = [ordered]@{
    schemaVersion = 1
    status = 'engineering-candidate-non-production'
    suite = 'TPS-Direct-v3/Noise_NNpsk0_25519_ChaChaPoly_BLAKE2s/XChaCha20-Poly1305'
    abiVersion = 3
    minAndroidApi = 21
    productionReady = $false
    checks = [ordered]@{
        cleanPinnedSourcePreparation = 'pass'
        allRequiredAbisBuilt = 'pass'
        elf16KiBLoadAlignment = 'pass'
        hiddenDependencySymbols = 'pass'
        exactAbiExportSurface = 'pass'
        bindNow = 'pass'
        onDeviceKnownAnswerAndConformance = 'pending'
    }
    toolchain = [ordered]@{
        ndkSourcePropertiesSha256 = (Get-FileHash -LiteralPath `
            (Join-Path $NdkPath 'source.properties') -Algorithm SHA256).Hash.ToLowerInvariant()
        clang = [string] $clangVersion
    }
    inputs = [ordered]@{
        windowsPreparationReportSha256 = (Get-FileHash -LiteralPath `
            $windowsReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        providerSourceSha256 = (Get-FileHash -LiteralPath `
            (Join-Path $repoRoot 'native/crypto/src/tps_crypto.c') `
            -Algorithm SHA256).Hash.ToLowerInvariant()
        generatedSodiumVersionHeaderSha256 = (Get-FileHash -LiteralPath `
            $windowsSodiumVersionHeader -Algorithm SHA256).Hash.ToLowerInvariant()
        libsodiumArchiveSha256 = $sodiumArchiveHash
        noiseCPatchSha256 = [string] $windowsReport.inputs.noiseCPatchSha256
        dependencyManifestSha256 = (Get-FileHash -LiteralPath `
            $dependencyManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        buildScriptSha256 = (Get-FileHash -LiteralPath `
            $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    artifacts = $artifactReports
}
$reportPath = Join-Path $androidBuildRoot 'native_crypto_android_report.json'
[IO.File]::WriteAllText($reportPath,
    (($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false))

Write-Output 'TPS_NATIVE_CRYPTO_ANDROID_BUILD_OK'
Write-Output $reportPath
