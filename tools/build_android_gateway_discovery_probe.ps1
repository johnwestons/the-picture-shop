[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$probeRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot `
    'output\native-route\probe\android'))
$stageRoot = [IO.Path]::GetFullPath((Join-Path $probeRoot 'love-stage'))
$packagePath = [IO.Path]::GetFullPath((Join-Path $probeRoot `
    'android-gateway-discovery-probe.love'))
$temporaryPackagePath = [IO.Path]::GetFullPath((Join-Path $probeRoot `
    'android-gateway-discovery-probe.tmp.love'))

function Assert-WithinProbeRoot([string] $Path) {
    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = $probeRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    if ($resolved -cne $probeRoot -and -not $resolved.StartsWith(
            $prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Android gateway probe path escapes its output root.'
    }
    return $resolved
}

function Remove-ProbeDirectory([string] $Path) {
    $resolved = Assert-WithinProbeRoot $Path
    if (-not (Test-Path -LiteralPath $resolved)) { return }
    $item = Get-Item -LiteralPath $resolved -Force
    if (-not $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Refusing to remove an unsafe Android gateway probe stage.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
Remove-ProbeDirectory $stageRoot
New-Item -ItemType Directory -Path $stageRoot | Out-Null

$sourceFiles = [ordered]@{
    'main.lua' = Join-Path $projectRoot `
        'tools\probes\android_gateway_discovery\main.lua'
    'conf.lua' = Join-Path $projectRoot `
        'tools\probes\android_gateway_discovery\conf.lua'
    'src\net\gateway_android.lua' = Join-Path $projectRoot `
        'src\net\gateway_android.lua'
    'src\net\gateway_discovery.lua' = Join-Path $projectRoot `
        'src\net\gateway_discovery.lua'
    'src\net\gateway_native.lua' = Join-Path $projectRoot `
        'src\net\gateway_native.lua'
    'src\net\ip_scope.lua' = Join-Path $projectRoot 'src\net\ip_scope.lua'
}
foreach ($relativePath in $sourceFiles.Keys) {
    $sourcePath = $sourceFiles[$relativePath]
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Android gateway probe source is missing: $sourcePath"
    }
    $destinationPath = Join-Path $stageRoot $relativePath
    New-Item -ItemType Directory -Path (Split-Path $destinationPath -Parent) `
        -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

$stagedMain = Get-Content -Raw -LiteralPath (Join-Path $stageRoot 'main.lua')
foreach ($requiredText in @(
    'provider.readOnly ~= true',
    'provider.networkTrafficSent ~= false',
    'loadedProvider.expectedAbiVersion ~= 2',
    'rawget(candidate, "interfaceIndex") == nil',
    'TPS_ANDROID_GATEWAY_MODULES_OK',
    'TPS_ANDROID_GATEWAY_LIBRARY_OK',
    'TPS_ANDROID_GATEWAY_ABI_OK',
    'TPS_ANDROID_GATEWAY_NATIVE_SNAPSHOT_OK',
    'TPS_ANDROID_GATEWAY_CALLBACK_HEALTHY_OK',
    'TPS_ANDROID_GATEWAY_ROUTE_OK',
    'TPS_ANDROID_GATEWAY_REVALIDATION_OK',
    'TPS_ANDROID_GATEWAY_PROBE_OK',
    'TPS_ANDROID_GATEWAY_PROBE_FAIL'
)) {
    if ($stagedMain -notmatch [regex]::Escape($requiredText)) {
        throw "Android gateway probe is missing a safety assertion: $requiredText"
    }
}

foreach ($oldPackage in @($packagePath, $temporaryPackagePath)) {
    if (Test-Path -LiteralPath $oldPackage) {
        $item = Get-Item -LiteralPath $oldPackage -Force
        if ($item.PSIsContainer -or
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Android gateway probe package target is unsafe.'
        }
        Remove-Item -LiteralPath $oldPackage -Force
    }
}
[IO.Compression.ZipFile]::CreateFromDirectory(
    $stageRoot,
    $temporaryPackagePath,
    [IO.Compression.CompressionLevel]::Optimal,
    $false)
Move-Item -LiteralPath $temporaryPackagePath -Destination $packagePath

$archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
try {
    $expectedEntries = @($sourceFiles.Keys | ForEach-Object {
        $_.Replace('\', '/')
    } | Sort-Object)
    $actualEntries = @($archive.Entries |
        Where-Object { $_.FullName -notmatch '/$' } |
        ForEach-Object { $_.FullName.Replace('\', '/') } |
        Sort-Object)
    if (Compare-Object $expectedEntries $actualEntries -CaseSensitive) {
        throw 'Android gateway probe package contains unexpected files.'
    }
} finally {
    $archive.Dispose()
}

& (Join-Path $PSScriptRoot 'build_android_apk.ps1') `
    -PackagePath $packagePath `
    -EngineeringGatewayDiscoveryProbe
if (-not $?) { throw 'Android gateway discovery probe APK build failed.' }

Write-Output "ANDROID_GATEWAY_DISCOVERY_PROBE_LOVE=$packagePath"
