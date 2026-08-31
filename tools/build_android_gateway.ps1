[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string] $NdkPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$nativeRouteRoot = [IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'output/native-route'))
$buildRoot = [IO.Path]::GetFullPath(
    (Join-Path $nativeRouteRoot 'build/android'))
$toolingRoot = [IO.Path]::GetFullPath(
    (Join-Path $nativeRouteRoot 'tooling'))
$reportPath = Join-Path $buildRoot 'android_gateway_report.json'

function Assert-WithinNativeRouteOutput([string] $Path) {
    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = $nativeRouteRoot.TrimEnd(
        [IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith(
            $prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Android gateway build path escapes native-route output: $resolved"
    }
    return $resolved
}

function Remove-GeneratedDirectory([string] $Path) {
    $resolved = Assert-WithinNativeRouteOutput $Path
    if (-not (Test-Path -LiteralPath $resolved)) { return }
    $item = Get-Item -LiteralPath $resolved -Force
    if (-not $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to remove an unsafe Android gateway output: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Get-LowerSha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-VerifiedZig {
    $expectedExecutableSha256 =
        '086ce9d47ba42f33a514e1a6e04eb1d4a8fa1d75e0868e0213caad447c91e864'
    $candidates = @(
        (Join-Path $nativeRouteRoot 'tooling/zig-68659eb5f1e4/zig.exe'),
        (Join-Path $repoRoot 'output/native-crypto/tooling/zig-68659eb5f1e4/zig.exe'),
        (Join-Path $repoRoot 'output/native-crypto/tooling/zig-0.16.0/zig.exe'),
        (Join-Path $repoRoot `
            'output/native-crypto/tooling/zig-0.16.0/zig-x86_64-windows-0.16.0/zig.exe')
    )
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        if ((Get-LowerSha256 $candidate) -ne $expectedExecutableSha256) { continue }
        $version = @(& $candidate version 2>$null)
        if ($LASTEXITCODE -eq 0 -and $version.Count -eq 1 -and
                $version[0] -ceq '0.16.0') {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw 'Verified Zig 0.16.0 is unavailable for the Android gateway host test.'
}

$resolvedNdk = [IO.Path]::GetFullPath($NdkPath)
if (-not (Test-Path -LiteralPath (Join-Path $resolvedNdk 'source.properties') `
        -PathType Leaf)) {
    throw "Android NDK is unavailable at $resolvedNdk"
}
$toolchainBin = Join-Path $resolvedNdk `
    'toolchains/llvm/prebuilt/windows-x86_64/bin'
$clang = Join-Path $toolchainBin 'clang.exe'
$readelf = Join-Path $toolchainBin 'llvm-readelf.exe'
$nm = Join-Path $toolchainBin 'llvm-nm.exe'
$sysroot = Join-Path $resolvedNdk `
    'toolchains/llvm/prebuilt/windows-x86_64/sysroot'
foreach ($requiredTool in @($clang, $readelf, $nm)) {
    if (-not (Test-Path -LiteralPath $requiredTool -PathType Leaf)) {
        throw "Android NDK tool is missing: $requiredTool"
    }
}

New-Item -ItemType Directory -Force -Path $nativeRouteRoot,$toolingRoot |
    Out-Null
$lockPath = Assert-WithinNativeRouteOutput (
    (Join-Path $nativeRouteRoot 'android-gateway-build.lock'))
try {
    $buildLock = [IO.File]::Open(
        $lockPath,
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None)
} catch {
    throw 'Another Android gateway build is already running.'
}

try {
    Remove-GeneratedDirectory $buildRoot
    New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

    $includeRoot = Join-Path $repoRoot 'native/android_gateway/include'
    $sourceRoot = Join-Path $repoRoot 'native/android_gateway/src'
    $header = Join-Path $includeRoot 'tps_android_gateway.h'
    $internalHeader = Join-Path $sourceRoot 'tps_android_gateway_internal.h'
    $stateSource = Join-Path $sourceRoot 'tps_android_gateway_state.c'
    $jniSource = Join-Path $sourceRoot 'tps_android_gateway_jni.c'
    $testSource = Join-Path $repoRoot `
        'native/android_gateway/tests/tps_android_gateway_state_test.c'
    $javaBridgeSource = Join-Path $repoRoot `
        'mobile/android/java/com/thepictureshop/net/GatewayDiscoveryBridge.java'
    foreach ($inputPath in @(
            $header, $internalHeader, $stateSource, $jniSource, $testSource,
            $javaBridgeSource)) {
        if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
            throw "Android gateway source input is missing: $inputPath"
        }
    }

    $javaBridge = Get-Content -Raw -LiteralPath $javaBridgeSource
    foreach ($requiredFragment in @(
            'Build.VERSION.SDK_INT < 26',
            '@RequiresApi(26)',
            'network.getNetworkHandle()',
            'networkHandle == 0L',
            'matchingRouteCount == 1',
            'NetworkCapabilities.NET_CAPABILITY_VALIDATED',
            'NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED',
            'onBlockedStatusChanged',
            '!interfaceName.equals(route.getInterface())',
            '!address.isLinkLocalAddress()',
            'NetworkCapabilities.TRANSPORT_VPN',
            'NetworkCapabilities.TRANSPORT_CELLULAR',
            'NetworkCapabilities.TRANSPORT_WIFI',
            'NetworkCapabilities.TRANSPORT_ETHERNET')) {
        if (-not $javaBridge.Contains($requiredFragment)) {
            throw "Android gateway Java fail-closed contract is missing: $requiredFragment"
        }
    }
    foreach ($forbiddenFragment in @(
            'java.net.Socket', 'java.net.ServerSocket',
            'java.net.DatagramSocket', 'java.net.DatagramPacket',
            'java.net.URL', 'java.net.URLConnection',
            'java.net.HttpURLConnection',
            'java.nio.channels.DatagramChannel',
            'java.nio.channels.SocketChannel',
            'InetAddress.getByName', 'InetAddress.getAllByName',
            'openConnection(', 'bindSocket(', 'bindProcessToNetwork(',
            'android.net.wifi.WifiManager', 'java.net.NetworkInterface',
            'android.system.Os', 'android.util.Log',
            'System.out', 'System.err', 'printStackTrace(')) {
        if ($javaBridge.Contains($forbiddenFragment)) {
            throw "Android gateway Java socket/logging reference audit failed: $forbiddenFragment"
        }
    }
    $nativeContractSource = ((Get-Content -Raw -LiteralPath $header) +
        (Get-Content -Raw -LiteralPath $internalHeader) +
        (Get-Content -Raw -LiteralPath $stateSource) +
        (Get-Content -Raw -LiteralPath $jniSource))
    $forbiddenNativePatterns = [ordered]@{
        ifNameToIndex = '\bif_nametoindex\b'
        socketCall = '\bsocket\s*\('
        connectCall = '\bconnect\s*\('
        bindCall = '\bbind\s*\('
        sendCall = '\bsend\s*\('
        sendToCall = '\bsendto\s*\('
        sendMessageCall = '\bsendmsg\s*\('
        receiveCall = '\brecv\s*\('
        receiveFromCall = '\brecvfrom\s*\('
        receiveMessageCall = '\brecvmsg\s*\('
        syscallCall = '\bsyscall\s*\('
        socketSyscallNumber = '\b__NR_socket\b'
        internetAddressFamily = '\bAF_INET6?\b'
        androidSocketNetworkBinding = '\bandroid_setsocknetwork\b'
        androidNetworkResolver = '\bandroid_getaddrinfofornetwork\b'
        addressResolver = '\bgetaddrinfo\s*\('
        legacyHostResolver = '\bgethostbyname\s*\('
        androidLog = '\b__android_log\w*\b|<android/log\.h>'
        standardOutput = '\b(?:printf|fprintf|puts|perror)\s*\('
    }
    foreach ($entry in $forbiddenNativePatterns.GetEnumerator()) {
        if ($nativeContractSource -match $entry.Value) {
            throw "Android gateway native socket/logging reference audit failed: $($entry.Key)"
        }
    }

    $zig = Resolve-VerifiedZig
    $hostTest = Join-Path $buildRoot 'tps_android_gateway_state_test.exe'
    $hostArguments = @(
        'cc', '-target', 'x86_64-windows-gnu', '-O2', '-std=c11',
        '-Wall', '-Wextra', '-Werror',
        '-DTPS_ANDROID_GATEWAY_TEST_WINDOWS_THREADS=1',
        "-I$includeRoot", "-I$sourceRoot", $stateSource, $testSource,
        '-o', $hostTest
    )
    & $zig @hostArguments
    if ($LASTEXITCODE -ne 0 -or
            -not (Test-Path -LiteralPath $hostTest -PathType Leaf)) {
        throw 'Android gateway native state test build failed.'
    }
    $hostOutput = @(& $hostTest 2>&1)
    if ($LASTEXITCODE -ne 0 -or
            $hostOutput.Count -ne 1 -or
            $hostOutput[0] -cne 'TPS_ANDROID_GATEWAY_STATE=PASS') {
        throw 'Android gateway native state test failed.'
    }

    $expectedExports = @(
        'Java_com_thepictureshop_net_GatewayDiscoveryBridge_nativeClearDefaultIpv4',
        'Java_com_thepictureshop_net_GatewayDiscoveryBridge_nativePublishDefaultIpv4',
        'tps_android_gateway_abi_version',
        'tps_android_gateway_default_ipv4'
    ) | Sort-Object
    $targets = @(
        [ordered]@{
            abi = 'armeabi-v7a'
            triple = 'armv7a-linux-androideabi21'
            elfClass = 'ELF32'
            machine = 'ARM'
            dynamicUndefinedSymbols = @(
                '__cxa_atexit', '__cxa_finalize', 'memcmp', 'memcpy',
                'pthread_mutex_lock', 'pthread_mutex_unlock', 'strlen')
        },
        [ordered]@{
            abi = 'arm64-v8a'
            triple = 'aarch64-linux-android21'
            elfClass = 'ELF64'
            machine = 'AArch64'
            dynamicUndefinedSymbols = @(
                '__cxa_atexit', '__cxa_finalize', 'memcpy',
                'pthread_mutex_lock', 'pthread_mutex_unlock', 'strlen')
        },
        [ordered]@{
            abi = 'x86_64'
            triple = 'x86_64-linux-android21'
            elfClass = 'ELF64'
            machine = 'Advanced Micro Devices X86-64'
            dynamicUndefinedSymbols = @(
                '__cxa_atexit', '__cxa_finalize', 'memcpy',
                'pthread_mutex_lock', 'pthread_mutex_unlock', 'strlen')
        }
    )

    $artifacts = [ordered]@{}
    $previousSourceDateEpoch = $env:SOURCE_DATE_EPOCH
    try {
        $env:SOURCE_DATE_EPOCH = '0'
        foreach ($target in $targets) {
            $abiRoot = Join-Path $buildRoot $target.abi
            New-Item -ItemType Directory -Force -Path $abiRoot | Out-Null
            $library = Join-Path $abiRoot 'libtps_android_gateway.so'
            $arguments = @(
                "--target=$($target.triple)", "--sysroot=$sysroot",
                '-shared', '-O2', '-s', '-std=c11', '-fPIC',
                '-ffunction-sections', '-fdata-sections',
                '-fvisibility=hidden', '-Wall', '-Wextra', '-Werror',
                "-I$includeRoot", "-I$sourceRoot", $stateSource, $jniSource,
                '-pthread', '-Wl,--gc-sections', '-Wl,--no-undefined',
                '-Wl,--fatal-warnings', '-Wl,--build-id=sha1',
                '-Wl,-z,relro', '-Wl,-z,now',
                '-Wl,-z,max-page-size=16384',
                '-Wl,-z,common-page-size=16384',
                '-Wl,-soname,libtps_android_gateway.so', '-o', $library
            )
            & $clang @arguments
            if ($LASTEXITCODE -ne 0 -or
                    -not (Test-Path -LiteralPath $library -PathType Leaf)) {
                throw "Android gateway build failed for $($target.abi)."
            }

            $headerOutput = (& $readelf -h $library) -join "`n"
            if ($LASTEXITCODE -ne 0 -or
                    $headerOutput -notmatch
                    "Class:\s+$([regex]::Escape($target.elfClass))" -or
                    $headerOutput -notmatch
                    "Machine:\s+$([regex]::Escape($target.machine))") {
                throw "Android gateway ELF identity failed for $($target.abi)."
            }
            $programHeaders = @(& $readelf -lW $library)
            $programHeaderExitCode = $LASTEXITCODE
            $loadLines = @($programHeaders |
                Where-Object { $_ -match '^\s*LOAD\s' })
            if ($programHeaderExitCode -ne 0 -or $loadLines.Count -eq 0 -or
                    ($loadLines | Where-Object { $_ -notmatch '\s0x4000\s*$' })) {
                throw "Android gateway 16 KiB alignment failed for $($target.abi)."
            }
            $gnuRelroLines = @($programHeaders |
                Where-Object { $_ -match '^\s*GNU_RELRO\s' })
            if ($gnuRelroLines.Count -ne 1) {
                throw "Android gateway GNU_RELRO check failed for $($target.abi)."
            }
            $exports = @(& $nm -D --defined-only $library | ForEach-Object {
                if ($_ -match '\s([A-Za-z_][A-Za-z0-9_]*)$') { $Matches[1] }
            } | Sort-Object)
            if ($LASTEXITCODE -ne 0 -or
                    (Compare-Object $expectedExports $exports)) {
                throw "Android gateway export surface failed for $($target.abi)."
            }
            $undefinedLines = @(& $nm -D --undefined-only $library)
            $undefinedExitCode = $LASTEXITCODE
            $dynamicUndefinedSymbols = @()
            foreach ($line in $undefinedLines) {
                if ($line -notmatch '^\s*U\s+(\S+)\s*$') {
                    throw "Android gateway undefined-symbol output was malformed for $($target.abi)."
                }
                $dynamicUndefinedSymbols += ($Matches[1] -replace '@.*$', '')
            }
            $dynamicUndefinedSymbols = @($dynamicUndefinedSymbols |
                Sort-Object -Unique)
            if ($undefinedExitCode -ne 0 -or
                    $dynamicUndefinedSymbols.Count -ne $undefinedLines.Count -or
                    (Compare-Object $target.dynamicUndefinedSymbols `
                        $dynamicUndefinedSymbols)) {
                throw "Android gateway undefined-symbol allowlist failed for $($target.abi)."
            }
            $dynamic = (& $readelf -d $library) -join "`n"
            if ($LASTEXITCODE -ne 0 -or $dynamic -notmatch '\bBIND_NOW\b') {
                throw "Android gateway BIND_NOW check failed for $($target.abi)."
            }

            $artifacts[$target.abi] = [ordered]@{
                path = "output/native-route/build/android/$($target.abi)/libtps_android_gateway.so"
                sha256 = Get-LowerSha256 $library
                bytes = (Get-Item -LiteralPath $library).Length
                elfClass = $target.elfClass
                machine = $target.machine
                loadAlignment = '0x4000'
                gnuRelro = $true
                exportCount = $exports.Count
                exports = $exports
                dynamicUndefinedSymbolCount = $dynamicUndefinedSymbols.Count
                dynamicUndefinedSymbols = $dynamicUndefinedSymbols
            }
        }
    } finally {
        $env:SOURCE_DATE_EPOCH = $previousSourceDateEpoch
    }

    $report = [ordered]@{
        schemaVersion = 1
        status = 'engineering-foundation'
        productionReady = $false
        abiVersion = 2
        minAndroidApi = 26
        networkTrafficSent = $false
        addressesRecorded = $false
        androidSignalCoverage = [ordered]@{
            minBridgeApi = 26
            suspensionCheckedFromApi = 28
            blockedStatusCheckedFromApi = 29
            unavailablePreApiSignalsClaimed = $false
        }
        checks = [ordered]@{
            hostStateUnitTest = 'pass'
            nativeConcurrentSnapshotTest = 'pass'
            javaFailClosedContract = 'pass'
            javaExactNetworkHandleContract = 'pass'
            javaCellularTransportRejected = 'pass'
            sourceSocketAndLoggingReferenceAudit = 'pass'
            allRequiredAbisBuilt = 'pass'
            elf16KiBLoadAlignment = 'pass'
            exactAbiExportSurface = 'pass'
            exactDynamicUndefinedSymbolAllowlist = 'pass'
            gnuRelro = 'pass'
            bindNow = 'pass'
        }
        toolchain = [ordered]@{
            ndkSourcePropertiesSha256 = Get-LowerSha256 (
                (Join-Path $resolvedNdk 'source.properties'))
            clang = [string]((& $clang --version | Select-Object -First 1))
            hostTestCompiler = 'zig 0.16.0'
        }
        inputs = [ordered]@{
            publicHeaderSha256 = Get-LowerSha256 $header
            internalHeaderSha256 = Get-LowerSha256 $internalHeader
            stateSourceSha256 = Get-LowerSha256 $stateSource
            jniSourceSha256 = Get-LowerSha256 $jniSource
            stateTestSha256 = Get-LowerSha256 $testSource
            javaBridgeSourceSha256 = Get-LowerSha256 $javaBridgeSource
        }
        artifacts = $artifacts
    }
    [IO.File]::WriteAllText(
        $reportPath,
        (($report | ConvertTo-Json -Depth 8) + "`n"),
        [Text.UTF8Encoding]::new($false))

    Write-Output 'TPS_ANDROID_GATEWAY_BUILD=PASS'
    Write-Output 'TPS_ANDROID_GATEWAY_PRODUCTION_READY=False'
    Write-Output "REPORT=$reportPath"
} finally {
    if ($null -ne $buildLock) {
        $buildLock.Dispose()
    }
}
