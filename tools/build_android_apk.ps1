param(
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [switch]$Install,
    [string]$DeviceSerial,
    [switch]$EngineeringNativeCryptoProbe,
    [switch]$EngineeringDirectTransportProbe,
    [ValidateSet('host','client')][string]$DirectTransportProbeRole,
    [switch]$EngineeringIpv6UdpProbe,
    [ValidateSet('host','client')][string]$Ipv6UdpProbeRole,
    [switch]$EngineeringGatewayDiscoveryProbe,
    [string]$SensitiveBuildRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Resolve-GitExecutable {
    $command = Get-Command git.exe -CommandType Application `
        -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return [System.IO.Path]::GetFullPath($command.Source)
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
        $full = [System.IO.Path]::GetFullPath($candidate)
        if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
    }
    throw 'Git could not be located for the isolated Android wrapper build.'
}

if ($DeviceSerial) {
    $DeviceSerial = $DeviceSerial.Trim()
    if (-not $Install) { throw '-DeviceSerial requires -Install.' }
    if (-not $DeviceSerial -or $DeviceSerial -match '\s|[\x00-\x1F\x7F]') {
        throw 'Android device serial contains invalid characters.'
    }
}
$engineeringProbeCount = @(
    $EngineeringNativeCryptoProbe,
    $EngineeringDirectTransportProbe,
    $EngineeringIpv6UdpProbe,
    $EngineeringGatewayDiscoveryProbe
).Where({ $_ }).Count
if ($engineeringProbeCount -gt 1) {
    throw 'Select only one engineering probe type.'
}
if ($engineeringProbeCount -gt 0 -and $Install) {
    throw 'Engineering probe builders never install to devices.'
}
if ($EngineeringDirectTransportProbe -and -not $DirectTransportProbeRole) {
    throw '-EngineeringDirectTransportProbe requires -DirectTransportProbeRole.'
}
if ($DirectTransportProbeRole -and -not $EngineeringDirectTransportProbe) {
    throw '-DirectTransportProbeRole requires -EngineeringDirectTransportProbe.'
}
if ($EngineeringIpv6UdpProbe -and -not $Ipv6UdpProbeRole) {
    throw '-EngineeringIpv6UdpProbe requires -Ipv6UdpProbeRole.'
}
if ($Ipv6UdpProbeRole -and -not $EngineeringIpv6UdpProbe) {
    throw '-Ipv6UdpProbeRole requires -EngineeringIpv6UdpProbe.'
}
if ($SensitiveBuildRoot -and
        -not ($EngineeringDirectTransportProbe -or $EngineeringIpv6UdpProbe)) {
    throw '-SensitiveBuildRoot is restricted to an engineering Internet probe.'
}
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $projectRoot 'output\mobile'
$toolingRoot = Join-Path $outputRoot 'tooling'
$androidRoot = Join-Path $toolingRoot 'android-sdk'
$jdkRoot = Join-Path $toolingRoot 'jdk-17'
$workspaceLoveAndroidRoot = Join-Path $outputRoot 'love-android'
$artifactOutputRoot = $outputRoot
$loveAndroidRoot = $workspaceLoveAndroidRoot
if ($SensitiveBuildRoot) {
    $sensitiveFullPath = [System.IO.Path]::GetFullPath($SensitiveBuildRoot)
    $temporaryRoot = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $projectPrefix = [System.IO.Path]::GetFullPath($projectRoot).TrimEnd('\') + '\'
    if (-not $sensitiveFullPath.StartsWith($temporaryRoot,
            [System.StringComparison]::OrdinalIgnoreCase) -or
            $sensitiveFullPath.StartsWith($projectPrefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'SensitiveBuildRoot must be a dedicated directory under the local temporary root and outside the project.'
    }
    $temporaryRootWithoutSlash = $temporaryRoot.TrimEnd('\')
    # Validate every existing ancestor before creation so New-Item cannot
    # traverse a junction planted below the temporary root.
    $candidate = $sensitiveFullPath
    while ($candidate -and -not (Test-Path -LiteralPath $candidate)) {
        $candidate = Split-Path $candidate -Parent
    }
    while ($candidate -and ($candidate -ceq $temporaryRootWithoutSlash -or
            $candidate.StartsWith($temporaryRoot,
                [System.StringComparison]::OrdinalIgnoreCase))) {
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'SensitiveBuildRoot and its temporary ancestors must not be reparse points.'
        }
        if ($candidate -ceq $temporaryRootWithoutSlash) { break }
        $candidate = Split-Path $candidate -Parent
    }
    New-Item -ItemType Directory -Path $sensitiveFullPath -Force | Out-Null
    # Revalidate after creation to fail closed on a race during New-Item.
    $candidate = $sensitiveFullPath
    while ($candidate -and ($candidate -ceq $temporaryRootWithoutSlash -or
            $candidate.StartsWith($temporaryRoot,
                [System.StringComparison]::OrdinalIgnoreCase))) {
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'SensitiveBuildRoot and its temporary ancestors must not be reparse points.'
        }
        if ($candidate -ceq $temporaryRootWithoutSlash) { break }
        $candidate = Split-Path $candidate -Parent
    }
    $artifactOutputRoot = Join-Path $sensitiveFullPath 'artifacts'
    $loveAndroidRoot = Join-Path $sensitiveFullPath 'love-android'
}
$config = Get-Content -Raw (Join-Path $projectRoot 'mobile\config.json') | ConvertFrom-Json
$manifestPath = Join-Path $projectRoot 'mobile\android\AndroidManifest.xml'
$apkFileName = "ThePictureShop-$($config.versionName)-debug.apk"
$reportFileName = 'apk-report.json'
$artifactKind = 'game-debug'
$requiresInternetPermission = $true
$requiresNetworkStatePermission = $true
$exactPermissions = @(
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.INTERNET'
)
if ($EngineeringNativeCryptoProbe) {
    $config = [pscustomobject]@{
        applicationId = 'com.thepictureshop.crypto_probe'
        applicationName = 'The Picture Shop Crypto Probe'
        versionName = '0.1.0-engineering-probe'
        versionCode = 1
        loveVersion = [string]$config.loveVersion
    }
    $manifestPath = Join-Path $projectRoot 'mobile\android\NativeCryptoProbeManifest.xml'
    $apkFileName = 'ThePictureShop-CryptoProbe-engineering.apk'
    $reportFileName = 'native-crypto-probe-apk-report.json'
    $artifactKind = 'native-crypto-engineering-probe'
    $requiresInternetPermission = $false
    $requiresNetworkStatePermission = $false
    $exactPermissions = @()
}
elseif ($EngineeringDirectTransportProbe) {
    $config = [pscustomobject]@{
        applicationId = "com.thepictureshop.direct_probe.$DirectTransportProbeRole"
        applicationName = "The Picture Shop Direct Probe $DirectTransportProbeRole"
        versionName = '0.1.0-engineering-direct-probe'
        versionCode = 1
        loveVersion = [string]$config.loveVersion
    }
    $manifestPath = Join-Path $projectRoot 'mobile\android\DirectTransportProbeManifest.xml'
    $apkFileName = "ThePictureShop-DirectTransportProbe-$DirectTransportProbeRole-engineering.apk"
    $reportFileName = "direct-transport-probe-$DirectTransportProbeRole-apk-report.json"
    $artifactKind = "direct-transport-engineering-probe-$DirectTransportProbeRole"
    $requiresInternetPermission = $true
    $requiresNetworkStatePermission = $false
    $exactPermissions = @('android.permission.INTERNET')
}
elseif ($EngineeringIpv6UdpProbe) {
    $config = [pscustomobject]@{
        applicationId = "com.thepictureshop.ipv6_udp_probe.$Ipv6UdpProbeRole"
        applicationName = "The Picture Shop IPv6 UDP Probe $Ipv6UdpProbeRole"
        versionName = '0.1.0-engineering-ipv6-udp-probe'
        versionCode = 1
        loveVersion = [string]$config.loveVersion
    }
    $manifestPath = Join-Path $projectRoot 'mobile\android\Ipv6UdpProbeManifest.xml'
    $apkFileName = "ThePictureShop-Ipv6UdpProbe-$Ipv6UdpProbeRole-engineering.apk"
    $reportFileName = "ipv6-udp-probe-$Ipv6UdpProbeRole-apk-report.json"
    $artifactKind = "ipv6-udp-engineering-probe-$Ipv6UdpProbeRole"
    $requiresInternetPermission = $true
    $requiresNetworkStatePermission = $false
    $exactPermissions = @('android.permission.INTERNET')
}
elseif ($EngineeringGatewayDiscoveryProbe) {
    $config = [pscustomobject]@{
        applicationId = 'com.thepictureshop.gateway_probe'
        applicationName = 'The Picture Shop Gateway Probe'
        versionName = '0.1.0-engineering-gateway-probe'
        versionCode = 1
        loveVersion = [string]$config.loveVersion
    }
    $manifestPath = Join-Path $projectRoot `
        'mobile\android\GatewayDiscoveryProbeManifest.xml'
    $apkFileName = 'ThePictureShop-GatewayDiscoveryProbe-engineering.apk'
    $reportFileName = 'gateway-discovery-probe-apk-report.json'
    $artifactKind = 'gateway-discovery-engineering-probe'
    $requiresInternetPermission = $false
    $requiresNetworkStatePermission = $true
    $exactPermissions = @('android.permission.ACCESS_NETWORK_STATE')
}
$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Android manifest is missing: $manifestPath"
}
$sharedMobile = Join-Path (Split-Path $projectRoot -Parent) 'Mouse Frontier 8.10\output\mobile'

New-Item -ItemType Directory -Force -Path $outputRoot,$toolingRoot,$artifactOutputRoot | Out-Null

function Get-LowerSha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-ZipEntryLowerSha256 {
    param([Parameter(Mandatory=$true)][System.IO.Compression.ZipArchiveEntry]$Entry)
    $stream = $Entry.Open()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha256.ComputeHash($stream)
        return ([System.BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

$resolvedPackageHash = Get-LowerSha256 -Path $resolvedPackage

function Get-VerifiedDownload {
    param([string]$Uri,[string]$Destination,[string]$Hash)
    if (-not (Test-Path -LiteralPath $Destination)) {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
    }
    $algorithm = if ($Hash.Length -eq 40) { 'SHA1' } else { 'SHA256' }
    if ((Get-FileHash -Algorithm $algorithm -LiteralPath $Destination).Hash -ne $Hash) {
        Remove-Item -LiteralPath $Destination -Force
        throw "Checksum verification failed for $Uri"
    }
}

if (-not (Test-Path -LiteralPath $jdkRoot)) {
    $sharedJdk = Join-Path $sharedMobile 'tooling\jdk-17'
    if (Test-Path -LiteralPath $sharedJdk) {
        New-Item -ItemType Junction -Path $jdkRoot -Target $sharedJdk | Out-Null
    }
    else {
        Write-Output 'Downloading verified JDK 17 build tooling...'
        $metadata = Invoke-RestMethod -Uri 'https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse'
        $package = $metadata[0].binary.package
        $archive = Join-Path $toolingRoot 'jdk-17.zip'
        Get-VerifiedDownload -Uri $package.link -Destination $archive -Hash $package.checksum
        New-Item -ItemType Directory -Force -Path $jdkRoot | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $jdkRoot -Force
    }
}

if (-not (Test-Path -LiteralPath $androidRoot)) {
    $sharedSdk = Join-Path $sharedMobile 'tooling\android-sdk'
    if (Test-Path -LiteralPath $sharedSdk) {
        New-Item -ItemType Junction -Path $androidRoot -Target $sharedSdk | Out-Null
    }
    else {
        Write-Output 'Downloading verified Android command-line tooling...'
        $archive = Join-Path $toolingRoot 'android-command-line-tools-12.zip'
        Get-VerifiedDownload -Uri 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -Destination $archive -Hash '3d2917302740f476999a091bc5558837c7a863c5'
        $extractRoot = Join-Path $toolingRoot 'android-command-line-tools-extract'
        New-Item -ItemType Directory -Force -Path $extractRoot,$androidRoot | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot -Force
        $versionedRoot = Join-Path $androidRoot 'cmdline-tools\12.0'
        New-Item -ItemType Directory -Force -Path $versionedRoot | Out-Null
        Copy-Item -Path (Join-Path $extractRoot 'cmdline-tools\*') -Destination $versionedRoot -Recurse -Force
    }
}

$javaExecutable = Get-ChildItem $jdkRoot -Recurse -Filter java.exe | Select-Object -First 1 -ExpandProperty FullName
if (-not $javaExecutable) { throw 'JDK 17 could not be located' }
$javaHome = Split-Path (Split-Path $javaExecutable -Parent) -Parent
$sdkManager = Join-Path $androidRoot 'cmdline-tools\12.0\bin\sdkmanager.bat'
$requiredAndroidTools = @(
    (Join-Path $androidRoot 'platform-tools\adb.exe'),
    (Join-Path $androidRoot 'platforms\android-34\android.jar'),
    (Join-Path $androidRoot 'build-tools\35.0.0\aapt.exe'),
    (Join-Path $androidRoot 'ndk\25.2.9519653\source.properties')
)
if (@($requiredAndroidTools | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -gt 0) {
    $previousJavaHome = $env:JAVA_HOME
    try {
        $env:JAVA_HOME = $javaHome
        1..100 | ForEach-Object { 'y' } | & $sdkManager --sdk_root=$androidRoot --licenses | Out-Null
        & $sdkManager --sdk_root=$androidRoot 'platform-tools' 'platforms;android-34' 'build-tools;35.0.0' 'ndk;25.2.9519653'
        if ($LASTEXITCODE -ne 0) { throw "Android SDK setup failed with exit code $LASTEXITCODE" }
    }
    finally { $env:JAVA_HOME = $previousJavaHome }
}

$nativeCryptoNdkPath = Join-Path $androidRoot 'ndk\25.2.9519653'
$nativeCryptoBuildScript = Join-Path $PSScriptRoot 'build_native_crypto_android.ps1'
if (-not (Test-Path -LiteralPath $nativeCryptoBuildScript -PathType Leaf)) {
    throw "Android native crypto build script is missing: $nativeCryptoBuildScript"
}
Write-Output 'Building the non-production Android native crypto candidate...'
& $nativeCryptoBuildScript -NdkPath $nativeCryptoNdkPath
if (-not $?) { throw 'Android native crypto candidate build failed.' }

$nativeCryptoReportPath = Join-Path $projectRoot 'output\native-crypto\build\android\native_crypto_android_report.json'
if (-not (Test-Path -LiteralPath $nativeCryptoReportPath -PathType Leaf)) {
    throw "Android native crypto report is missing: $nativeCryptoReportPath"
}
$nativeCryptoReport = Get-Content -Raw -LiteralPath $nativeCryptoReportPath | ConvertFrom-Json
$requiredNativeCryptoAbis = @('armeabi-v7a','arm64-v8a','x86_64')
$reportedNativeCryptoAbis = @($nativeCryptoReport.artifacts.PSObject.Properties.Name | Sort-Object)
if (Compare-Object ($requiredNativeCryptoAbis | Sort-Object) $reportedNativeCryptoAbis) {
    throw 'Android native crypto report does not contain exactly the required ABIs.'
}
if ($nativeCryptoReport.status -cne 'engineering-candidate-non-production' -or
        $nativeCryptoReport.productionReady -ne $false -or
        [int]$nativeCryptoReport.abiVersion -ne 3) {
    throw 'Android native crypto report must remain a non-production engineering candidate.'
}
foreach ($checkName in @('cleanPinnedSourcePreparation','allRequiredAbisBuilt','elf16KiBLoadAlignment','hiddenDependencySymbols','exactAbiExportSurface','bindNow')) {
    if ($nativeCryptoReport.checks.$checkName -cne 'pass') {
        throw "Android native crypto prerequisite did not pass: $checkName"
    }
}

$nativeCryptoArtifacts = [ordered]@{}
foreach ($abi in $requiredNativeCryptoAbis) {
    $artifact = $nativeCryptoReport.artifacts.PSObject.Properties[$abi].Value
    if ([int]$artifact.exportCount -ne 24) {
        throw "Android native crypto artifact has an unexpected ABI export count for $abi."
    }
    $expectedRelativePath = "output/native-crypto/build/android/$abi/libtps_crypto.so"
    if (([string]$artifact.path).Replace('\','/') -cne $expectedRelativePath) {
        throw "Android native crypto report has an unexpected path for $abi."
    }
    $sourcePath = Join-Path $projectRoot ($expectedRelativePath.Replace('/','\'))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Android native crypto artifact is missing for ${abi}: $sourcePath"
    }
    $sourceHash = Get-LowerSha256 -Path $sourcePath
    if ($sourceHash -cne ([string]$artifact.sha256).ToLowerInvariant() -or
            (Get-Item -LiteralPath $sourcePath).Length -ne [long]$artifact.bytes) {
        throw "Android native crypto artifact does not match its report for $abi."
    }
    $nativeCryptoArtifacts[$abi] = [ordered]@{
        sourcePath = $sourcePath
        sha256 = $sourceHash
        bytes = [long]$artifact.bytes
    }
}

$androidGatewayBuildScript = Join-Path $PSScriptRoot `
    'build_android_gateway.ps1'
if (-not (Test-Path -LiteralPath $androidGatewayBuildScript -PathType Leaf)) {
    throw "Android gateway build script is missing: $androidGatewayBuildScript"
}
Write-Output 'Building the non-production Android gateway-discovery foundation...'
& $androidGatewayBuildScript -NdkPath $nativeCryptoNdkPath
if (-not $?) { throw 'Android gateway-discovery foundation build failed.' }

$androidGatewayReportPath = Join-Path $projectRoot `
    'output\native-route\build\android\android_gateway_report.json'
if (-not (Test-Path -LiteralPath $androidGatewayReportPath -PathType Leaf)) {
    throw "Android gateway build report is missing: $androidGatewayReportPath"
}
$androidGatewayReport = Get-Content -Raw -LiteralPath `
    $androidGatewayReportPath | ConvertFrom-Json
$gatewayBridgeSource = Join-Path $projectRoot `
    'mobile\android\java\com\thepictureshop\net\GatewayDiscoveryBridge.java'
if (-not (Test-Path -LiteralPath $gatewayBridgeSource -PathType Leaf)) {
    throw "Tracked Android gateway bridge is missing: $gatewayBridgeSource"
}
$gatewayBridgeSourceHash = Get-LowerSha256 -Path $gatewayBridgeSource
$reportedGatewayBridgeSourceHash =
    [string]$androidGatewayReport.inputs.javaBridgeSourceSha256
$reportedAndroidGatewayAbis = @(
    $androidGatewayReport.artifacts.PSObject.Properties.Name | Sort-Object)
if (Compare-Object ($requiredNativeCryptoAbis | Sort-Object) `
        $reportedAndroidGatewayAbis) {
    throw 'Android gateway report does not contain exactly the required ABIs.'
}
if ([int]$androidGatewayReport.schemaVersion -ne 1 -or
        $androidGatewayReport.status -cne 'engineering-foundation' -or
        $androidGatewayReport.productionReady -ne $false -or
        $androidGatewayReport.networkTrafficSent -ne $false -or
        $androidGatewayReport.addressesRecorded -ne $false -or
        [int]$androidGatewayReport.abiVersion -ne 2 -or
        [int]$androidGatewayReport.minAndroidApi -ne 26 -or
        $reportedGatewayBridgeSourceHash -cnotmatch '^[0-9a-f]{64}$' -or
        $reportedGatewayBridgeSourceHash -cne $gatewayBridgeSourceHash) {
    throw 'Android gateway report must remain a source-bound non-production ABI-v2 engineering foundation.'
}
if ([int]$androidGatewayReport.androidSignalCoverage.minBridgeApi -ne 26 -or
        [int]$androidGatewayReport.androidSignalCoverage.suspensionCheckedFromApi -ne 28 -or
        [int]$androidGatewayReport.androidSignalCoverage.blockedStatusCheckedFromApi -ne 29 -or
        $androidGatewayReport.androidSignalCoverage.unavailablePreApiSignalsClaimed -ne
            $false) {
    throw 'Android gateway report has an invalid platform-signal coverage claim.'
}
foreach ($checkName in @('hostStateUnitTest','nativeConcurrentSnapshotTest',
        'javaFailClosedContract',
        'javaExactNetworkHandleContract','javaCellularTransportRejected',
        'sourceSocketAndLoggingReferenceAudit',
        'allRequiredAbisBuilt','elf16KiBLoadAlignment',
        'exactAbiExportSurface','exactDynamicUndefinedSymbolAllowlist',
        'gnuRelro','bindNow')) {
    if ($androidGatewayReport.checks.$checkName -cne 'pass') {
        throw "Android gateway prerequisite did not pass: $checkName"
    }
}
$requiredAndroidGatewayExports = @(
    'Java_com_thepictureshop_net_GatewayDiscoveryBridge_nativeClearDefaultIpv4',
    'Java_com_thepictureshop_net_GatewayDiscoveryBridge_nativePublishDefaultIpv4',
    'tps_android_gateway_abi_version',
    'tps_android_gateway_default_ipv4'
) | Sort-Object
$commonAndroidGatewayUndefinedSymbols = @(
    '__cxa_atexit',
    '__cxa_finalize',
    'memcpy',
    'pthread_mutex_lock',
    'pthread_mutex_unlock',
    'strlen'
) | Sort-Object
$requiredAndroidGatewayUndefinedSymbols = [ordered]@{
    'armeabi-v7a' = @($commonAndroidGatewayUndefinedSymbols + 'memcmp' |
        Sort-Object)
    'arm64-v8a' = @($commonAndroidGatewayUndefinedSymbols)
    'x86_64' = @($commonAndroidGatewayUndefinedSymbols)
}
$androidGatewayArtifacts = [ordered]@{}
foreach ($abi in $requiredNativeCryptoAbis) {
    $artifact = $androidGatewayReport.artifacts.PSObject.Properties[$abi].Value
    $expectedRelativePath =
        "output/native-route/build/android/$abi/libtps_android_gateway.so"
    if (([string]$artifact.path).Replace('\','/') -cne $expectedRelativePath) {
        throw "Android gateway report has an unexpected path for $abi."
    }
    $sourcePath = Join-Path $projectRoot ($expectedRelativePath.Replace('/','\'))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Android gateway artifact is missing for ${abi}: $sourcePath"
    }
    $sourceHash = Get-LowerSha256 -Path $sourcePath
    $reportedExports = @($artifact.exports | Sort-Object)
    $reportedUndefinedSymbols = @($artifact.dynamicUndefinedSymbols |
        Sort-Object)
    $requiredUndefinedSymbols =
        @($requiredAndroidGatewayUndefinedSymbols[$abi])
    if ($sourceHash -cne ([string]$artifact.sha256).ToLowerInvariant() -or
            (Get-Item -LiteralPath $sourcePath).Length -ne [long]$artifact.bytes -or
            $artifact.gnuRelro -ne $true -or
            [int]$artifact.exportCount -ne $requiredAndroidGatewayExports.Count -or
            $reportedExports.Count -ne $requiredAndroidGatewayExports.Count -or
            [int]$artifact.dynamicUndefinedSymbolCount -ne
                $requiredUndefinedSymbols.Count -or
            $reportedUndefinedSymbols.Count -ne
                $requiredUndefinedSymbols.Count -or
            (Compare-Object $requiredAndroidGatewayExports $reportedExports `
                -CaseSensitive) -or
            (Compare-Object $requiredUndefinedSymbols `
                $reportedUndefinedSymbols -CaseSensitive)) {
        throw "Android gateway artifact does not match its report for $abi."
    }
    $androidGatewayArtifacts[$abi] = [ordered]@{
        sourcePath = $sourcePath
        sha256 = $sourceHash
        bytes = [long]$artifact.bytes
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $loveAndroidRoot 'gradlew.bat'))) {
    $gitExecutable = Resolve-GitExecutable
    if ($SensitiveBuildRoot -and
            (Test-Path -LiteralPath (Join-Path $workspaceLoveAndroidRoot 'gradlew.bat') -PathType Leaf)) {
        Write-Output 'Creating an isolated local LÖVE Android wrapper...'
        & $gitExecutable clone --recurse-submodules --local --no-hardlinks `
            $workspaceLoveAndroidRoot $loveAndroidRoot
    }
    else {
        Write-Output 'Creating the local LÖVE Android wrapper...'
        & $gitExecutable clone --recurse-submodules --depth 1 --branch $config.loveVersion `
            https://github.com/love2d/love-android.git $loveAndroidRoot
    }
    if ($LASTEXITCODE -ne 0) { throw "LÖVE Android checkout failed with exit code $LASTEXITCODE" }
}

$loveAppSourceRoot = [System.IO.Path]::GetFullPath((Join-Path $loveAndroidRoot 'app\src'))
$loveAppSourcePrefix = $loveAppSourceRoot.TrimEnd('\') + '\'
$staleNativeCryptoLibraries = @(Get-ChildItem -LiteralPath $loveAppSourceRoot -Recurse -File -Filter 'libtps_crypto.so' -ErrorAction SilentlyContinue)
foreach ($staleLibrary in $staleNativeCryptoLibraries) {
    $stalePath = [System.IO.Path]::GetFullPath($staleLibrary.FullName)
    if (-not $stalePath.StartsWith($loveAppSourcePrefix,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a native crypto library outside the LÖVE app sources: $stalePath"
    }
    Remove-Item -LiteralPath $stalePath -Force
}
$nativeCryptoJniRoot = Join-Path $loveAppSourceRoot 'main\jniLibs'
foreach ($abi in $requiredNativeCryptoAbis) {
    $abiJniRoot = Join-Path $nativeCryptoJniRoot $abi
    New-Item -ItemType Directory -Force -Path $abiJniRoot | Out-Null
    $stagedLibrary = Join-Path $abiJniRoot 'libtps_crypto.so'
    Copy-Item -LiteralPath $nativeCryptoArtifacts[$abi].sourcePath -Destination $stagedLibrary -Force
    if ((Get-LowerSha256 -Path $stagedLibrary) -cne $nativeCryptoArtifacts[$abi].sha256) {
        throw "Staged Android native crypto library does not match its report for $abi."
    }
    $nativeCryptoArtifacts[$abi].stagedPath = $stagedLibrary
}

$staleAndroidGatewayLibraries = @(Get-ChildItem -LiteralPath `
    $loveAppSourceRoot -Recurse -File -Filter 'libtps_android_gateway.so' `
    -ErrorAction SilentlyContinue)
foreach ($staleLibrary in $staleAndroidGatewayLibraries) {
    $stalePath = [System.IO.Path]::GetFullPath($staleLibrary.FullName)
    if (-not $stalePath.StartsWith($loveAppSourcePrefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an Android gateway library outside the LÖVE app sources: $stalePath"
    }
    Remove-Item -LiteralPath $stalePath -Force
}
$androidGatewayJniRoot = Join-Path $loveAppSourceRoot 'main\jniLibs'
foreach ($abi in $requiredNativeCryptoAbis) {
    $abiJniRoot = Join-Path $androidGatewayJniRoot $abi
    New-Item -ItemType Directory -Force -Path $abiJniRoot | Out-Null
    $stagedLibrary = Join-Path $abiJniRoot 'libtps_android_gateway.so'
    Copy-Item -LiteralPath $androidGatewayArtifacts[$abi].sourcePath `
        -Destination $stagedLibrary -Force
    if ((Get-LowerSha256 -Path $stagedLibrary) -cne
            $androidGatewayArtifacts[$abi].sha256) {
        throw "Staged Android gateway library does not match its report for $abi."
    }
    $androidGatewayArtifacts[$abi].stagedPath = $stagedLibrary
}

$loveSourceRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $loveAndroidRoot 'love\src'))
$loveSourcePrefix = $loveSourceRoot.TrimEnd('\') + '\'
$gatewayBridgeDestination = [System.IO.Path]::GetFullPath(
    (Join-Path $loveSourceRoot `
        'main\java\com\thepictureshop\net\GatewayDiscoveryBridge.java'))
if (-not $gatewayBridgeDestination.StartsWith($loveSourcePrefix,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Android gateway bridge destination escapes the LÖVE source root.'
}
$staleGatewayBridgeSources = @(Get-ChildItem -LiteralPath @(
        $loveAppSourceRoot, $loveSourceRoot) -Recurse -File `
        -Filter 'GatewayDiscoveryBridge.java' -ErrorAction SilentlyContinue)
$wrapperRootPrefix = [System.IO.Path]::GetFullPath($loveAndroidRoot).TrimEnd('\') + '\'
foreach ($staleSource in $staleGatewayBridgeSources) {
    $stalePath = [System.IO.Path]::GetFullPath($staleSource.FullName)
    if (-not $stalePath.StartsWith($wrapperRootPrefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an Android gateway bridge outside the wrapper: $stalePath"
    }
    Remove-Item -LiteralPath $stalePath -Force
}
New-Item -ItemType Directory -Force `
    -Path (Split-Path $gatewayBridgeDestination -Parent) | Out-Null
Copy-Item -LiteralPath $gatewayBridgeSource `
    -Destination $gatewayBridgeDestination -Force
$gatewayBridgeStagedSourceHash = Get-LowerSha256 -Path `
    $gatewayBridgeDestination
if ($gatewayBridgeStagedSourceHash -cne $gatewayBridgeSourceHash) {
    throw 'Staged Android gateway bridge does not match its tracked source.'
}

$gameActivityPath = Join-Path $loveAndroidRoot 'love\src\main\java\org\love2d\android\GameActivity.java'
$gameActivity = Get-Content -Raw -LiteralPath $gameActivityPath
if ($gameActivity -notmatch 'PICTURE_SHOP_ANDROID_GATEWAY_LIFECYCLE') {
    $replacement = @'
    private static native void nativeSetDefaultStreamValues(int sampleRate, int framesPerBurst);

    // PICTURE_SHOP_ANDROID_GATEWAY_LIFECYCLE
    @Override
    public void loadLibraries() {
        super.loadLibraries();
        com.thepictureshop.net.GatewayDiscoveryBridge.start(this);
    }
'@
    $gameActivity = $gameActivity.Replace(
        '    private static native void nativeSetDefaultStreamValues(int sampleRate, int framesPerBurst);',
        $replacement.TrimEnd())
}
if ($gameActivity -notmatch 'PICTURE_SHOP_ANDROID_GATEWAY_LIBRARY') {
    $replacement = @'
            "openal",
            // PICTURE_SHOP_ANDROID_GATEWAY_LIBRARY
            "tps_android_gateway",
'@
    $gameActivity = $gameActivity.Replace('            "openal",',
        $replacement.TrimEnd())
}
if ($gameActivity -notmatch 'PICTURE_SHOP_ANDROID_GATEWAY_STOP') {
    $replacement = @'
    protected void onDestroy() {
        // PICTURE_SHOP_ANDROID_GATEWAY_STOP
        com.thepictureshop.net.GatewayDiscoveryBridge.stop();
'@
    $gameActivity = $gameActivity.Replace('    protected void onDestroy() {',
        $replacement.TrimEnd())
}
if ($gameActivity -notmatch 'PICTURE_SHOP_LANDSCAPE_LOCK') {
    $replacement = @'
public class GameActivity extends SDLActivity {
    // PICTURE_SHOP_LANDSCAPE_LOCK
    @Override
    public void setOrientationBis(int width, int height, boolean resizable, String hint) {
        setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    }
'@
    $gameActivity = $gameActivity.Replace('public class GameActivity extends SDLActivity {',$replacement.TrimEnd())
}
if ($gameActivity -notmatch 'PICTURE_SHOP_EMBEDDED_GAME') {
    $replacement = @'
        embed = getResources().getBoolean(R.bool.embed);
        // PICTURE_SHOP_EMBEDDED_GAME
        if (embed) {
            needToCopyGameInArchive = true;
        }
'@
    $gameActivity = $gameActivity.Replace('        embed = getResources().getBoolean(R.bool.embed);',$replacement.TrimEnd())
}
if ($gameActivity -notmatch 'PICTURE_SHOP_GAME_CACHE') {
    $replacement = @'
    private void copyGameInsideArchive() {
        // PICTURE_SHOP_GAME_CACHE
        File cachedGame = new File(this.getCacheDir(), "game.love");
        File installedApk = new File(this.getApplicationInfo().sourceDir);
        if (cachedGame.isFile() && cachedGame.length() > 0 && cachedGame.lastModified() >= installedApk.lastModified()) {
            gamePath = cachedGame.getPath();
            storagePermissionUnnecessary = true;
            Log.d("GameActivity", "Reusing cached embedded game: " + gamePath);
            return;
        }
'@
    $gameActivity = $gameActivity.Replace('    private void copyGameInsideArchive() {',$replacement.TrimEnd())
}
if ($gameActivity -notmatch 'PICTURE_SHOP_STATIC_LIBCPP') {
    $gameActivity = $gameActivity.Replace('            "c++_shared",',
        '            // PICTURE_SHOP_STATIC_LIBCPP: linked into each native library.')
}
foreach ($marker in @('PICTURE_SHOP_ANDROID_GATEWAY_LIFECYCLE',
        'PICTURE_SHOP_ANDROID_GATEWAY_LIBRARY',
        'PICTURE_SHOP_ANDROID_GATEWAY_STOP','PICTURE_SHOP_LANDSCAPE_LOCK',
        'PICTURE_SHOP_EMBEDDED_GAME','PICTURE_SHOP_GAME_CACHE',
        'PICTURE_SHOP_STATIC_LIBCPP')) {
    if ($gameActivity -notmatch $marker) { throw "Android wrapper patch failed: $marker" }
}
[System.IO.File]::WriteAllText($gameActivityPath,$gameActivity,[System.Text.UTF8Encoding]::new($false))

# LÖVE Android 11.5 predates Android's 16 KB page-size requirement. Rebuild
# every native library with Android's documented r27-and-earlier linker flags.
# Static libc++ avoids bundling NDK r25's own 4 KB-only libc++_shared.so.
$applicationMkPath = Join-Path $loveAndroidRoot 'love\src\jni\Application.mk'
$applicationMk = Get-Content -Raw -LiteralPath $applicationMkPath
$originalApplicationMk = $applicationMk
$applicationMk = $applicationMk -replace '(?m)^APP_STL := c\+\+_shared\r?$','APP_STL := c++_static'
$applicationMk = $applicationMk -replace '(?m)^APP_LDFLAGS :=.*\r?$',
    'APP_LDFLAGS := -llog -landroid -lz -fuse-ld=lld -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384'
if ($applicationMk -notmatch 'APP_STL := c\+\+_static' -or $applicationMk -notmatch 'max-page-size=16384') {
    throw 'Unable to apply Android 16 KB native-library compatibility settings'
}
if ($applicationMk -ne $originalApplicationMk) {
    [System.IO.File]::WriteAllText($applicationMkPath,$applicationMk,[System.Text.UTF8Encoding]::new($false))
}

$embedAssets = Join-Path $loveAndroidRoot 'app\src\embed\assets'
New-Item -ItemType Directory -Force -Path $embedAssets | Out-Null
Copy-Item -LiteralPath $resolvedPackage -Destination (Join-Path $embedAssets 'game.love') -Force
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $loveAndroidRoot 'app\src\embed\AndroidManifest.xml') -Force
$androidResources = Join-Path $outputRoot 'android-res'
if (Test-Path -LiteralPath $androidResources) {
    Copy-Item -Path (Join-Path $androidResources '*') -Destination (Join-Path $loveAndroidRoot 'app\src\main\res') -Recurse -Force
}

$propertiesPath = Join-Path $loveAndroidRoot 'gradle.properties'
$properties = Get-Content -Raw $propertiesPath
$properties = $properties -replace '(?m)^app\.name_byte_array=.*$','# app.name_byte_array disabled for Picture Shop'
$properties = $properties -replace '(?m)^#?app\.name=.*$',("app.name=" + $config.applicationName)
$properties = $properties -replace '(?m)^app\.application_id=.*$',("app.application_id=" + $config.applicationId)
$properties = $properties -replace '(?m)^app\.orientation=.*$','app.orientation=landscape'
$properties = $properties -replace '(?m)^app\.version_code=.*$',("app.version_code=" + $config.versionCode)
$properties = $properties -replace '(?m)^app\.version_name=.*$',("app.version_name=" + $config.versionName)
if ($properties -notmatch '(?m)^org\.gradle\.jvmargs=') { $properties += "`r`norg.gradle.jvmargs=-Xmx4g -Dfile.encoding=UTF-8`r`n" }
[System.IO.File]::WriteAllText($propertiesPath,$properties,[System.Text.UTF8Encoding]::new($false))

$appProguardPath = Join-Path $loveAndroidRoot 'app\proguard-rules.pro'
$appProguard = Get-Content -Raw -LiteralPath $appProguardPath
if ($appProguard -notmatch 'PICTURE_SHOP_KEEP_GATEWAY_BRIDGE') {
    $appProguard = $appProguard.TrimEnd() + @'


# PICTURE_SHOP_KEEP_GATEWAY_BRIDGE: invoked through JNI and activity lifecycle.
-keep class com.thepictureshop.net.GatewayDiscoveryBridge { *; }
'@
    [System.IO.File]::WriteAllText($appProguardPath,
        $appProguard.TrimEnd() + "`r`n",
        [System.Text.UTF8Encoding]::new($false))
}

$appBuildPath = Join-Path $loveAndroidRoot 'app\build.gradle'
$appBuild = Get-Content -Raw $appBuildPath
$appBuildChanged = $false
if ($appBuild -notmatch "noCompress 'love'") {
    $appBuild = $appBuild -replace 'android \{',"android {`r`n    aaptOptions { noCompress 'love' }"
    $appBuildChanged = $true
}
if ($appBuild -notmatch 'PICTURE_SHOP_PRESERVE_NATIVE_CRYPTO') {
    $nativeCryptoPackaging = @'
android {
    // PICTURE_SHOP_PRESERVE_NATIVE_CRYPTO: final APK bytes must match the audited build report.
    packagingOptions {
        jniLibs {
            keepDebugSymbols += ['**/libtps_crypto.so', '**/libtps_android_gateway.so']
        }
    }
'@
    $appBuild = $appBuild -replace 'android \{',$nativeCryptoPackaging.TrimEnd()
    $appBuildChanged = $true
}
elseif ($appBuild -notmatch 'libtps_android_gateway\.so') {
    $appBuild = $appBuild.Replace(
        "keepDebugSymbols += ['**/libtps_crypto.so']",
        "keepDebugSymbols += ['**/libtps_crypto.so', '**/libtps_android_gateway.so']")
    $appBuildChanged = $true
}
if ($appBuild -notmatch 'libtps_android_gateway\.so') {
    throw 'Unable to preserve Android gateway symbols in the APK.'
}
if ($appBuildChanged) {
    [System.IO.File]::WriteAllText($appBuildPath,$appBuild,[System.Text.UTF8Encoding]::new($false))
}

$previousJavaHome = $env:JAVA_HOME
$previousAndroidHome = $env:ANDROID_HOME
$previousAndroidSdkRoot = $env:ANDROID_SDK_ROOT
$substDrive = $null
$sensitiveSubstDrive = $null
$buildLoveRoot = $loveAndroidRoot
$buildAndroidRoot = $androidRoot
$buildJavaHome = $javaHome
try {
    foreach ($candidate in @('M:','N:','O:','P:')) {
        if (-not (Test-Path ($candidate + '\'))) {
            & subst.exe $candidate $outputRoot
            if ($LASTEXITCODE -eq 0) { $substDrive = $candidate; break }
        }
    }
    if ($SensitiveBuildRoot) {
        foreach ($candidate in @('Q:','R:','S:','T:')) {
            if (-not (Test-Path ($candidate + '\'))) {
                & subst.exe $candidate $SensitiveBuildRoot
                if ($LASTEXITCODE -eq 0) {
                    $sensitiveSubstDrive = $candidate
                    $buildLoveRoot = $candidate + '\love-android'
                    break
                }
            }
        }
        if (-not $sensitiveSubstDrive) {
            throw 'A short isolated build mount is required for the sensitive Android probe.'
        }
    }
    if ($substDrive) {
        if (-not $SensitiveBuildRoot) {
            $buildLoveRoot = $substDrive + '\love-android'
        }
        $buildAndroidRoot = $substDrive + '\tooling\android-sdk'
        $buildJavaHome = (Get-ChildItem ($substDrive + '\tooling\jdk-17') -Recurse -Filter java.exe | Select-Object -First 1).Directory.Parent.FullName
    }
    $env:JAVA_HOME = $buildJavaHome
    $env:ANDROID_HOME = $buildAndroidRoot
    $env:ANDROID_SDK_ROOT = $buildAndroidRoot

    $buildLabel = if ($EngineeringNativeCryptoProbe) {
        'engineering native-crypto probe'
    } elseif ($EngineeringDirectTransportProbe) {
        "engineering Direct-transport $DirectTransportProbeRole probe"
    } elseif ($EngineeringIpv6UdpProbe) {
        "engineering IPv6 UDP $Ipv6UdpProbeRole probe"
    } elseif ($EngineeringGatewayDiscoveryProbe) {
        'engineering Android gateway-discovery probe'
    } else {
        'Picture Shop Android APK'
    }
    Write-Output "Building the $buildLabel..."
    & (Join-Path $buildLoveRoot 'gradlew.bat') --project-dir $buildLoveRoot --no-daemon :app:clean assembleEmbedNoRecordDebug
    if ($LASTEXITCODE -ne 0) { throw "Android APK build failed with exit code $LASTEXITCODE" }
}
finally {
    $env:JAVA_HOME = $previousJavaHome
    $env:ANDROID_HOME = $previousAndroidHome
    $env:ANDROID_SDK_ROOT = $previousAndroidSdkRoot
    if ($sensitiveSubstDrive) { & subst.exe $sensitiveSubstDrive /D | Out-Null }
    if ($substDrive) { & subst.exe $substDrive /D | Out-Null }
}

$gatewayBridgeFinalTrackedSourceHash = Get-LowerSha256 -Path `
    $gatewayBridgeSource
$gatewayBridgeFinalStagedSourceHash = Get-LowerSha256 -Path `
    $gatewayBridgeDestination
if ($gatewayBridgeFinalTrackedSourceHash -cne $gatewayBridgeSourceHash -or
        $gatewayBridgeFinalStagedSourceHash -cne
            $gatewayBridgeStagedSourceHash -or
        $gatewayBridgeFinalStagedSourceHash -cne
            $gatewayBridgeFinalTrackedSourceHash -or
        [string]$androidGatewayReport.inputs.javaBridgeSourceSha256 -cne
            $gatewayBridgeFinalTrackedSourceHash) {
    throw 'Android gateway Java source changed during the audited APK build.'
}

$builtApk = Get-ChildItem (Join-Path $loveAndroidRoot 'app\build\outputs\apk') -Recurse -Filter '*embed-noRecord-debug*.apk' | Select-Object -First 1
if (-not $builtApk) { $builtApk = Get-ChildItem (Join-Path $loveAndroidRoot 'app\build\outputs\apk') -Recurse -Filter '*.apk' | Select-Object -First 1 }
if (-not $builtApk) { throw 'Gradle completed without producing an APK' }
$apkPath = Join-Path $artifactOutputRoot $apkFileName
Copy-Item -LiteralPath $builtApk.FullName -Destination $apkPath -Force

$archive = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
$packagedNativeCrypto = [ordered]@{}
$packagedAndroidGateway = [ordered]@{}
try {
    $embeddedGame = $archive.GetEntry('assets/game.love')
    if (-not $embeddedGame) { throw 'APK is missing assets/game.love' }
    if ($embeddedGame.Length -ne (Get-Item -LiteralPath $resolvedPackage).Length) { throw 'Embedded game size does not match the package' }
    if ((Get-ZipEntryLowerSha256 -Entry $embeddedGame) -cne $resolvedPackageHash) {
        throw 'Embedded game bytes do not match the selected package.'
    }

    $expectedNativeCryptoEntries = @($requiredNativeCryptoAbis | ForEach-Object { "lib/$_/libtps_crypto.so" } | Sort-Object)
    $actualNativeCryptoEntries = @($archive.Entries |
        Where-Object { $_.Name -ceq 'libtps_crypto.so' } |
        Select-Object -ExpandProperty FullName |
        Sort-Object)
    if (Compare-Object $expectedNativeCryptoEntries $actualNativeCryptoEntries) {
        throw 'APK does not contain exactly one native crypto library for each required ABI.'
    }
    foreach ($abi in $requiredNativeCryptoAbis) {
        $entryName = "lib/$abi/libtps_crypto.so"
        $entry = $archive.GetEntry($entryName)
        if (-not $entry) { throw "APK is missing $entryName" }
        $entryHash = Get-ZipEntryLowerSha256 -Entry $entry
        if ($entryHash -cne $nativeCryptoArtifacts[$abi].sha256 -or
                $entry.Length -ne $nativeCryptoArtifacts[$abi].bytes) {
            throw "Packaged native crypto library does not match its report for $abi."
        }
        $packagedNativeCrypto[$abi] = [ordered]@{
            apkEntry = $entryName
            sha256 = $entryHash
            bytes = [long]$entry.Length
        }
    }

    $expectedAndroidGatewayEntries = @($requiredNativeCryptoAbis |
        ForEach-Object { "lib/$_/libtps_android_gateway.so" } | Sort-Object)
    $actualAndroidGatewayEntries = @($archive.Entries |
        Where-Object { $_.Name -ceq 'libtps_android_gateway.so' } |
        Select-Object -ExpandProperty FullName | Sort-Object)
    if (Compare-Object $expectedAndroidGatewayEntries `
            $actualAndroidGatewayEntries) {
        throw 'APK does not contain exactly one Android gateway library for each required ABI.'
    }
    foreach ($abi in $requiredNativeCryptoAbis) {
        $entryName = "lib/$abi/libtps_android_gateway.so"
        $entry = $archive.GetEntry($entryName)
        if (-not $entry) { throw "APK is missing $entryName" }
        $entryHash = Get-ZipEntryLowerSha256 -Entry $entry
        if ($entryHash -cne $androidGatewayArtifacts[$abi].sha256 -or
                $entry.Length -ne $androidGatewayArtifacts[$abi].bytes) {
            throw "Packaged Android gateway library does not match its report for $abi."
        }
        $packagedAndroidGateway[$abi] = [ordered]@{
            apkEntry = $entryName
            sha256 = $entryHash
            bytes = [long]$entry.Length
        }
    }
}
finally { $archive.Dispose() }

$buildToolsRoot = Join-Path $androidRoot 'build-tools\35.0.0'
$apksigner = Join-Path $buildToolsRoot 'apksigner.bat'
$signatureJavaHome = $env:JAVA_HOME
try {
    $env:JAVA_HOME = $javaHome
    & $apksigner verify --verbose $apkPath
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed' }
}
finally { $env:JAVA_HOME = $signatureJavaHome }
$aapt = Join-Path $buildToolsRoot 'aapt.exe'
$badging = & $aapt dump badging $apkPath | Out-String
if ($badging -notmatch [regex]::Escape("package: name='$($config.applicationId)'")) { throw 'APK application ID verification failed' }
$analyzerRoot = Join-Path $androidRoot 'cmdline-tools\12.0'
$analyzerClasspath = Join-Path $analyzerRoot 'lib\apkanalyzer-classpath.jar'
if (-not (Test-Path -LiteralPath $analyzerClasspath -PathType Leaf)) {
    throw 'APK analyzer classpath is unavailable.'
}
$analyzerToolProperty = "-Dcom.android.sdklib.toolsdir=$analyzerRoot"
function Get-ApkDexCode(
    [string] $ClassName,
    [string] $Method
) {
    $arguments = @(
        $analyzerToolProperty,
        '-classpath',
        $analyzerClasspath,
        'com.android.tools.apk.analyzer.ApkAnalyzerCli',
        'dex',
        'code',
        '--class',
        $ClassName
    )
    if ($Method) { $arguments += @('--method', $Method) }
    $arguments += $apkPath
    $lines = @(& $javaExecutable @arguments 2>&1 |
        ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -or $lines.Count -lt 1) {
        throw "APK compiled-code inspection failed for $ClassName."
    }
    return [string]::Join("`n", $lines)
}

$dexPackages = @(& $javaExecutable $analyzerToolProperty `
    -classpath $analyzerClasspath `
    com.android.tools.apk.analyzer.ApkAnalyzerCli `
    dex packages $apkPath 2>&1 | ForEach-Object { [string]$_ })
if ($LASTEXITCODE -ne 0) { throw 'APK class inspection failed.' }
$gatewayBridgeClass = 'com.thepictureshop.net.GatewayDiscoveryBridge'
$gatewayBridgeClassPattern = '^C\s+.*\s' +
    [regex]::Escape($gatewayBridgeClass) + '\s*$'
$gatewayBridgeStartPattern = '^M\s+.*\s' +
    [regex]::Escape($gatewayBridgeClass) +
    '\s+void\s+start\(android\.content\.Context\)\s*$'
$gatewayBridgeStopPattern = '^M\s+.*\s' +
    [regex]::Escape($gatewayBridgeClass) + '\s+void\s+stop\(\)\s*$'
$gatewayBridgePublishPattern = '^M\s+.*\s' +
    [regex]::Escape($gatewayBridgeClass) +
    '\s+boolean\s+nativePublishDefaultIpv4\(' +
    'java\.lang\.String,java\.lang\.String,long\)\s*$'
$gatewayBridgeClearPattern = '^M\s+.*\s' +
    [regex]::Escape($gatewayBridgeClass) +
    '\s+void\s+nativeClearDefaultIpv4\(\)\s*$'
$gatewayBridgeClassLines = @($dexPackages | Where-Object {
    $_ -cmatch $gatewayBridgeClassPattern })
$gatewayBridgeStartLines = @($dexPackages | Where-Object {
    $_ -cmatch $gatewayBridgeStartPattern })
$gatewayBridgeStopLines = @($dexPackages | Where-Object {
    $_ -cmatch $gatewayBridgeStopPattern })
$gatewayBridgePublishLines = @($dexPackages | Where-Object {
    $_ -cmatch $gatewayBridgePublishPattern })
$gatewayBridgeClearLines = @($dexPackages | Where-Object {
    $_ -cmatch $gatewayBridgeClearPattern })
if ($gatewayBridgeClassLines.Count -ne 1 -or
        $gatewayBridgeStartLines.Count -ne 1 -or
        $gatewayBridgeStopLines.Count -ne 1 -or
        $gatewayBridgePublishLines.Count -ne 1 -or
        $gatewayBridgeClearLines.Count -ne 1) {
    throw 'APK is missing the exact Android gateway bridge Java/JNI ABI.'
}
$gatewayBridgeClassPackaged = $true

$loadLibrariesCode = Get-ApkDexCode `
    -ClassName 'org.love2d.android.GameActivity' `
    -Method 'loadLibraries()V'
$onDestroyCode = Get-ApkDexCode `
    -ClassName 'org.love2d.android.GameActivity' `
    -Method 'onDestroy()V'
$superLoadInstruction =
    'invoke-super {p0}, Lorg/libsdl/app/SDLActivity;->loadLibraries()V'
$gatewayStartInstruction =
    'invoke-static {p0}, Lcom/thepictureshop/net/GatewayDiscoveryBridge;->start(Landroid/content/Context;)V'
$gatewayStopInstruction =
    'invoke-static {}, Lcom/thepictureshop/net/GatewayDiscoveryBridge;->stop()V'
$superDestroyInstruction =
    'invoke-super {p0}, Lorg/libsdl/app/SDLActivity;->onDestroy()V'
$superLoadMatches = [regex]::Matches($loadLibrariesCode,
    [regex]::Escape($superLoadInstruction))
$gatewayStartMatches = [regex]::Matches($loadLibrariesCode,
    [regex]::Escape($gatewayStartInstruction))
$gatewayStopMatches = [regex]::Matches($onDestroyCode,
    [regex]::Escape($gatewayStopInstruction))
$superDestroyMatches = [regex]::Matches($onDestroyCode,
    [regex]::Escape($superDestroyInstruction))
if ($loadLibrariesCode -cnotmatch '(?m)^\.method public loadLibraries\(\)V$' -or
        $onDestroyCode -cnotmatch '(?m)^\.method protected onDestroy\(\)V$' -or
        $superLoadMatches.Count -ne 1 -or
        $gatewayStartMatches.Count -ne 1 -or
        $superLoadMatches[0].Index -ge $gatewayStartMatches[0].Index -or
        $gatewayStopMatches.Count -ne 1 -or
        $superDestroyMatches.Count -ne 1 -or
        $gatewayStopMatches[0].Index -ge $superDestroyMatches[0].Index) {
    throw 'APK GameActivity does not contain the exact gateway lifecycle hooks.'
}
$packagedGatewayLifecycleHooksVerified = $true

$gatewayImplementationClassPattern = '^C\s+.*\s' +
    '(?<name>com\.thepictureshop\.net\.GatewayDiscoveryBridge' +
    '(?:\$[A-Za-z0-9_$]+)?)\s*$'
$gatewayImplementationClasses = @($dexPackages | ForEach-Object {
    if ($_ -cmatch $gatewayImplementationClassPattern) {
        $Matches['name']
    }
} | Sort-Object -Unique)
$requiredGatewayImplementationClasses = @(
    'com.thepictureshop.net.GatewayDiscoveryBridge',
    'com.thepictureshop.net.GatewayDiscoveryBridge$Api26State',
    'com.thepictureshop.net.GatewayDiscoveryBridge$Candidate'
)
foreach ($requiredClass in $requiredGatewayImplementationClasses) {
    if ($gatewayImplementationClasses -cnotcontains $requiredClass) {
        throw "APK is missing a gateway implementation class: $requiredClass"
    }
}
$gatewayImplementationCodeParts = @($gatewayImplementationClasses |
    ForEach-Object { Get-ApkDexCode -ClassName $_ -Method $null })
$gatewayImplementationCode =
    [string]::Join("`n", $gatewayImplementationCodeParts)
foreach ($requiredReference in @(
    'Landroid/net/Network;->getNetworkHandle()J',
    'Landroid/net/ConnectivityManager;->registerDefaultNetworkCallback(Landroid/net/ConnectivityManager$NetworkCallback;)V',
    'Lcom/thepictureshop/net/GatewayDiscoveryBridge;->nativePublishDefaultIpv4(Ljava/lang/String;Ljava/lang/String;J)Z',
    'Lcom/thepictureshop/net/GatewayDiscoveryBridge;->nativeClearDefaultIpv4()V'
)) {
    if ($gatewayImplementationCode.IndexOf(
            $requiredReference, [StringComparison]::Ordinal) -lt 0) {
        throw "APK gateway implementation is missing a required reference: $requiredReference"
    }
}
$forbiddenGatewayCodePatterns = @(
    'Ljava/net/(?:Socket|DatagramSocket|ServerSocket|URLConnection|HttpURLConnection);',
    'Landroid/util/Log;',
    'Ljava/util/logging/',
    'L(?:okhttp3|org/slf4j|timber/log)/',
    'Ljava/io/PrintStream;',
    'Ljava/lang/System;->(?:out|err):'
)
foreach ($pattern in $forbiddenGatewayCodePatterns) {
    if ($gatewayImplementationCode -cmatch $pattern) {
        throw 'APK gateway implementation contains a forbidden socket or logging reference.'
    }
}
$usableCapabilitiesCode = Get-ApkDexCode `
    -ClassName 'com.thepictureshop.net.GatewayDiscoveryBridge$Api26State' `
    -Method 'usableCapabilities(Landroid/net/NetworkCapabilities;)Z'
$cellularRejectionPattern =
    '(?ms)^\s*const(?:/4|/16|/high16)? ' +
    '(?<transport>v[0-9]+), (?:0x0|0)\s*$' +
    '.*?^\s*invoke-virtual \{p0, \k<transport>\}, ' +
    'Landroid/net/NetworkCapabilities;->hasTransport\(I\)Z\s*$' +
    '\s*^\s*move-result (?<result>v[0-9]+)\s*$' +
    '\s*^\s*if-nez \k<result>,'
if ($usableCapabilitiesCode -cnotmatch $cellularRejectionPattern) {
    throw 'APK gateway implementation does not explicitly reject cellular transport.'
}
$packagedGatewayImplementationReferencesVerified = $true
$packagedGatewayCellularRejectionVerified = $true
$packagedGatewayForbiddenReferencesAbsent = $true
$dexPackages = $null
$loadLibrariesCode = $null
$onDestroyCode = $null
$gatewayImplementationCodeParts = $null
$gatewayImplementationCode = $null
$usableCapabilitiesCode = $null
$permissionDump = & $aapt dump permissions $apkPath | Out-String
if ($LASTEXITCODE -ne 0) { throw 'APK permission inspection failed' }
$internetPermission = [regex]::IsMatch(
    $permissionDump,
    "(?m)^uses-permission(?:-sdk-\d+)?: name='android\.permission\.INTERNET'\s*$"
)
$networkStatePermission = [regex]::IsMatch(
    $permissionDump,
    "(?m)^uses-permission(?:-sdk-\d+)?: name='android\.permission\.ACCESS_NETWORK_STATE'\s*$"
)
if ($requiresInternetPermission -and -not $internetPermission) {
    throw 'APK is missing required android.permission.INTERNET permission'
}
if (-not $requiresInternetPermission -and $internetPermission) {
    throw 'This APK must not request android.permission.INTERNET'
}
if ($requiresNetworkStatePermission -and -not $networkStatePermission) {
    throw 'APK is missing required android.permission.ACCESS_NETWORK_STATE permission'
}
if (-not $requiresNetworkStatePermission -and $networkStatePermission) {
    throw 'This APK must not request android.permission.ACCESS_NETWORK_STATE'
}
if ($null -ne $exactPermissions) {
    $actualPermissions = @([regex]::Matches(
        $permissionDump,
        "(?m)^uses-permission(?:-sdk-\d+)?: name='([^']+)'\s*$"
    ) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $generatedReceiverPermission =
        "$($config.applicationId).DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
    $allowedPermissions = @($exactPermissions + $generatedReceiverPermission |
        Sort-Object -Unique)
    if (Compare-Object $allowedPermissions $actualPermissions) {
        throw 'Engineering probe APK permissions do not exactly match its allowlist.'
    }
}
$zipalign = Join-Path $buildToolsRoot 'zipalign.exe'
& $zipalign -c -P 16 -v 4 $apkPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'APK ZIP alignment is not compatible with 16 KB page-size devices' }
$readelf = Join-Path $androidRoot 'ndk\25.2.9519653\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe'
$arm64Libraries = Get-ChildItem (Join-Path $loveAndroidRoot 'app\build\intermediates\merged_native_libs') -Recurse -Filter '*.so' |
    Where-Object { $_.FullName -match 'embedNoRecordDebug' -and $_.FullName -match 'arm64-v8a' }
if (-not $arm64Libraries) { throw 'No ARM64 libraries were available for the 16 KB ELF audit' }
foreach ($library in $arm64Libraries) {
    if ($library.Name -eq 'libc++_shared.so') { throw 'APK still contains NDK r25 libc++_shared.so' }
    $loadSegments = @(& $readelf -l $library.FullName | Where-Object { $_ -match '^  LOAD' })
    $badSegments = @($loadSegments | Where-Object { $_ -notmatch '0x(?:4000|8000|10000)$' })
    if (-not $loadSegments -or $badSegments.Count -gt 0) {
        throw "$($library.Name) is not 16 KB ELF-aligned"
    }
}

$adb = Join-Path $androidRoot 'platform-tools\adb.exe'
$devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" })
$authorizedDeviceSerials = @($devices | ForEach-Object { ($_ -split '\s+')[0] })
$deviceLaunchVerified = $false
$installedDeviceSerial = $null
if ($Install) {
    if ($DeviceSerial) {
        if ($authorizedDeviceSerials -notcontains $DeviceSerial) {
            throw "Requested Android device '$DeviceSerial' is not authorized or connected."
        }
        $installedDeviceSerial = $DeviceSerial
    }
    else {
        if ($authorizedDeviceSerials.Count -ne 1) {
            throw "Expected one authorized Android device or -DeviceSerial, found $($authorizedDeviceSerials.Count)"
        }
        $installedDeviceSerial = $authorizedDeviceSerials[0]
    }
    $adbTarget = @('-s', $installedDeviceSerial)
    & $adb @adbTarget install -r $apkPath
    if ($LASTEXITCODE -ne 0) { throw 'APK installation failed' }
    & $adb @adbTarget shell am force-stop $config.applicationId
    & $adb @adbTarget shell am start -W -n "$($config.applicationId)/org.love2d.android.GameActivity"
    if ($LASTEXITCODE -ne 0) { throw 'Installed APK did not launch' }
    for ($attempt = 1; $attempt -le 45; $attempt++) {
        $deviceProcessId = (& $adb @adbTarget shell pidof $config.applicationId | Out-String).Trim()
        $log = ''
        if ($deviceProcessId -cmatch '^[1-9][0-9]{0,9}$') {
            $log = (& $adb @adbTarget shell logcat `
                "--pid=$deviceProcessId" -d -t 4096 -v brief | Out-String)
        }
        if ($log -match '\[PICTURE SHOP\] Startup complete') { $deviceLaunchVerified = $true; break }
        if ($log -match 'FATAL EXCEPTION|stack traceback|Lua error') { throw 'Installed APK reported a startup error' }
        if (-not $deviceProcessId) { throw 'The Picture Shop process stopped during startup' }
        Start-Sleep -Seconds 1
    }
    if (-not $deviceLaunchVerified) { throw 'The installed app did not reach its startup marker' }
}

$report = [ordered]@{
    artifactKind = $artifactKind
    engineeringProbe = [bool]($engineeringProbeCount -gt 0)
    engineeringProbeRole = if ($EngineeringDirectTransportProbe) {
        $DirectTransportProbeRole
    } elseif ($EngineeringIpv6UdpProbe) {
        $Ipv6UdpProbeRole
    } else { $null }
    applicationId = $config.applicationId
    versionName = $config.versionName
    versionCode = $config.versionCode
    apk = $apkPath
    apkBytes = (Get-Item -LiteralPath $apkPath).Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash.ToLowerInvariant()
    signed = $true
    internetPermission = $internetPermission
    accessNetworkStatePermission = $networkStatePermission
    sixteenKbCompatible = $true
    embeddedLove = [ordered]@{
        sha256 = $resolvedPackageHash
        bytes = (Get-Item -LiteralPath $resolvedPackage).Length
    }
    nativeCrypto = [ordered]@{
        bundled = $true
        status = [string]$nativeCryptoReport.status
        productionReady = [bool]$nativeCryptoReport.productionReady
        buildReport = $nativeCryptoReportPath
        buildReportSha256 = Get-LowerSha256 -Path $nativeCryptoReportPath
        packagedArtifacts = $packagedNativeCrypto
    }
    androidGatewayDiscovery = [ordered]@{
        bundled = $true
        status = [string]$androidGatewayReport.status
        productionReady = [bool]$androidGatewayReport.productionReady
        abiVersion = [int]$androidGatewayReport.abiVersion
        minAndroidApi = [int]$androidGatewayReport.minAndroidApi
        networkTrafficSent = $false
        addressesRecorded = $false
        bridgeClass = $gatewayBridgeClass
        bridgeClassPackaged = $gatewayBridgeClassPackaged
        trackedBridgeSourceSha256 = $gatewayBridgeFinalTrackedSourceHash
        stagedBridgeSourceSha256 = $gatewayBridgeFinalStagedSourceHash
        nativeReportTrackedBridgeSourceSha256 =
            [string]$androidGatewayReport.inputs.javaBridgeSourceSha256
        trackedAndStagedSourceMatchNativeReport = $true
        trackedSourceStableThroughBuild = $true
        stagedSourceStableThroughBuild = $true
        packagedBridgeClassAndNativeMethodsVerified = $true
        packagedLifecycleHooksVerified =
            $packagedGatewayLifecycleHooksVerified
        packagedImplementationReferencesVerified =
            $packagedGatewayImplementationReferencesVerified
        packagedCellularRejectionVerified =
            $packagedGatewayCellularRejectionVerified
        packagedForbiddenSocketAndLoggingReferencesAbsent =
            $packagedGatewayForbiddenReferencesAbsent
        nativeArtifactSecurityMetadataVerified = $true
        buildReport = $androidGatewayReportPath
        buildReportSha256 = Get-LowerSha256 -Path $androidGatewayReportPath
        packagedArtifacts = $packagedAndroidGateway
    }
    connectedAndroidDevices = $devices.Count
    installedDeviceSerial = $installedDeviceSerial
    deviceLaunchVerified = $deviceLaunchVerified
}
[System.IO.File]::WriteAllText((Join-Path $artifactOutputRoot $reportFileName),($report | ConvertTo-Json -Depth 10) + "`n",[System.Text.UTF8Encoding]::new($false))
Write-Output "ANDROID_APK=$apkPath"
Write-Output "ANDROID_ARTIFACT_KIND=$artifactKind"
Write-Output "INTERNET_PERMISSION=$internetPermission"
Write-Output "ACCESS_NETWORK_STATE_PERMISSION=$networkStatePermission"
Write-Output 'NATIVE_CRYPTO_BUNDLED=True'
Write-Output "NATIVE_CRYPTO_PRODUCTION_READY=$($nativeCryptoReport.productionReady)"
Write-Output 'ANDROID_GATEWAY_BRIDGE_PACKAGED=True'
Write-Output 'ANDROID_GATEWAY_NETWORK_TRAFFIC_SENT=False'
Write-Output "ANDROID_GATEWAY_PRODUCTION_READY=$($androidGatewayReport.productionReady)"
Write-Output "CONNECTED_ANDROID_DEVICES=$($devices.Count)"
if ($installedDeviceSerial) { Write-Output "INSTALLED_DEVICE_SERIAL=$installedDeviceSerial" }
Write-Output "DEVICE_LAUNCH_VERIFIED=$deviceLaunchVerified"
