[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildScript = Join-Path $PSScriptRoot 'build_native_crypto.ps1'
$buildRoot = Join-Path $repoRoot 'output/native-crypto/build/windows-x64'
$library = Join-Path $buildRoot 'tps_crypto.dll'
$buildReport = Join-Path $buildRoot 'native_crypto_report.json'
$reproReport = Join-Path $buildRoot 'native_crypto_reproducibility.json'

function Invoke-CleanBuild {
    & $buildScript
    if ($LASTEXITCODE -ne 0) { throw 'Native provider build failed.' }
    if (-not (Test-Path -LiteralPath $library -PathType Leaf) -or
        -not (Test-Path -LiteralPath $buildReport -PathType Leaf)) {
        throw 'Native provider build did not produce the required evidence.'
    }
}

Invoke-CleanBuild
$firstBytes = [IO.File]::ReadAllBytes($library)
$firstHash = (Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant()
$firstBuild = Get-Content -LiteralPath $buildReport -Raw | ConvertFrom-Json
if ([int]$firstBuild.abiVersion -ne 3 -or
        $firstBuild.status -cne 'engineering-candidate-non-production' -or
        $firstBuild.productionReady -ne $false -or
        [int]$firstBuild.artifacts.library.exportCount -ne 24 -or
        $firstBuild.checks.exactAbiExportSurface -cne 'pass' -or
        $firstBuild.checks.responseAuthenticationConformance -cne 'pass' -or
        $firstBuild.checks.simultaneousOpeningConformance -cne 'pass' -or
        $firstBuild.checks.bridgeFragmentAuthenticationConformance -cne 'pass') {
    throw 'First reproducibility build did not report the required ABI v3 engineering candidate.'
}

Invoke-CleanBuild
$secondBytes = [IO.File]::ReadAllBytes($library)
$secondHash = (Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant()
$secondBuild = Get-Content -LiteralPath $buildReport -Raw | ConvertFrom-Json
if ([int]$secondBuild.abiVersion -ne 3 -or
        $secondBuild.status -cne 'engineering-candidate-non-production' -or
        $secondBuild.productionReady -ne $false -or
        [int]$secondBuild.artifacts.library.exportCount -ne 24 -or
        $secondBuild.checks.exactAbiExportSurface -cne 'pass' -or
        $secondBuild.checks.responseAuthenticationConformance -cne 'pass' -or
        $secondBuild.checks.simultaneousOpeningConformance -cne 'pass' -or
        $secondBuild.checks.bridgeFragmentAuthenticationConformance -cne 'pass') {
    throw 'Second reproducibility build did not report the required ABI v3 engineering candidate.'
}

$identical = $firstBytes.Length -eq $secondBytes.Length -and
    [Linq.Enumerable]::SequenceEqual([byte[]] $firstBytes, [byte[]] $secondBytes)
if (-not $identical) {
    throw "Native provider is not reproducible: $firstHash != $secondHash"
}
$firstInputs = $firstBuild.inputs | ConvertTo-Json -Depth 8 -Compress
$secondInputs = $secondBuild.inputs | ConvertTo-Json -Depth 8 -Compress
if ($firstInputs -ne $secondInputs) {
    throw 'Native provider inputs changed between reproducibility builds.'
}

$report = [ordered]@{
    schemaVersion = 1
    status = 'pass'
    productionReady = $false
    abiVersion = 3
    target = 'x86_64-windows-gnu'
    cleanBuilds = 2
    byteForByteIdentical = $true
    length = $secondBytes.Length
    firstSha256 = $firstHash
    secondSha256 = $secondHash
    inputs = $secondBuild.inputs
}
$json = $report | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($reproReport, $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))

Write-Output 'TPS_NATIVE_CRYPTO_REPRODUCIBLE_OK'
Write-Output $secondHash
Write-Output $reproReport
