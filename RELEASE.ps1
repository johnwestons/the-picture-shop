param(
    [switch]$BuildApk
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'tools\release_gate.ps1') -BuildApk:$BuildApk
exit $LASTEXITCODE
