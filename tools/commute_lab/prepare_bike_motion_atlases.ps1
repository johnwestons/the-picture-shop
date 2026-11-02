param(
    [string]$StageRoot = 'assets/staging/commute-bike-v3',
    [string]$RuntimeRoot = 'assets/commute/bike',
    [string[]]$SelectedOutputs = @()
)

$ErrorActionPreference = 'Stop'
$node = Get-Command 'node.exe' -ErrorAction Stop
$script = Join-Path $PSScriptRoot 'prepare_bike_motion_atlases.mjs'
if (-not (Test-Path -LiteralPath $script)) { throw "Missing fast atlas preparation script: $script" }
$arguments = @($script, $StageRoot, $RuntimeRoot) + $SelectedOutputs
& $node.Source @arguments
if ($LASTEXITCODE -ne 0) { throw "Atlas preparation failed with exit code $LASTEXITCODE." }
