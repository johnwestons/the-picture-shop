param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$probeRoot = Join-Path $projectRoot 'output\native-crypto\probe\android'
$stageRoot = Join-Path $probeRoot 'love-stage'
$packagePath = Join-Path $probeRoot 'native-crypto-probe.love'
$temporaryPackagePath = Join-Path $probeRoot 'native-crypto-probe.tmp.love'

function Reset-ProbeStage {
    $resolvedProbeRoot = [System.IO.Path]::GetFullPath($probeRoot).TrimEnd('\') + '\'
    $resolvedStage = [System.IO.Path]::GetFullPath($stageRoot)
    if (-not $resolvedStage.StartsWith($resolvedProbeRoot,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to reset a probe stage outside its output root: $resolvedStage"
    }
    if (Test-Path -LiteralPath $resolvedStage) {
        $stageItem = Get-Item -LiteralPath $resolvedStage -Force
        if (($stageItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to reset a reparse-point probe stage: $resolvedStage"
        }
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
    New-Item -ItemType Directory -Path $resolvedStage -Force | Out-Null
}

New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
Reset-ProbeStage

$sourceFiles = [ordered]@{
    'main.lua' = Join-Path $projectRoot 'native\crypto\tests\love_provider\main.lua'
    'conf.lua' = Join-Path $projectRoot 'native\crypto\tests\love_provider\conf.lua'
    'src\net\crypto_native.lua' = Join-Path $projectRoot 'src\net\crypto_native.lua'
}
foreach ($relativePath in $sourceFiles.Keys) {
    $sourcePath = $sourceFiles[$relativePath]
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Native-crypto probe source is missing: $sourcePath"
    }
    $destinationPath = Join-Path $stageRoot $relativePath
    New-Item -ItemType Directory -Path (Split-Path $destinationPath -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

$stagedMain = Get-Content -Raw -LiteralPath (Join-Path $stageRoot 'main.lua')
foreach ($requiredText in @(
    'provider.engineeringOnly == true',
    'provider.productionReady == false',
    'provider.responseTag',
    'provider.newOpeningHost',
    'TPS_ANDROID_CRYPTO_PROBE_OK',
    'TPS_ANDROID_CRYPTO_PROBE_FAIL'
)) {
    if ($stagedMain -notmatch [regex]::Escape($requiredText)) {
        throw "Native-crypto probe is missing its safety assertion or result marker: $requiredText"
    }
}

foreach ($oldPackage in @($packagePath,$temporaryPackagePath)) {
    if (Test-Path -LiteralPath $oldPackage) {
        Remove-Item -LiteralPath $oldPackage -Force
    }
}
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $stageRoot,
    $temporaryPackagePath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)
Move-Item -LiteralPath $temporaryPackagePath -Destination $packagePath

$packageArchive = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
try {
    $expectedEntries = @('conf.lua','main.lua','src/net/crypto_native.lua') | Sort-Object
    $actualEntries = @($packageArchive.Entries |
        Where-Object { $_.FullName -notmatch '/$' } |
        ForEach-Object { $_.FullName.Replace('\','/') } |
        Sort-Object)
    if (Compare-Object $expectedEntries $actualEntries) {
        throw 'Engineering probe package does not contain exactly the intended Lua files.'
    }
}
finally {
    $packageArchive.Dispose()
}

& (Join-Path $PSScriptRoot 'build_android_apk.ps1') `
    -PackagePath $packagePath `
    -EngineeringNativeCryptoProbe
if (-not $?) {
    throw 'Engineering native-crypto probe APK build failed.'
}

Write-Output "ANDROID_NATIVE_CRYPTO_PROBE_LOVE=$packagePath"
