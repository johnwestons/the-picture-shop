param([string] $Output='assets/commute/truck/turntables')

# Kept as the old command entry point. The current capture uses the full-resolution
# truck panels and writes both unbranded 64-angle views.
& (Join-Path $PSScriptRoot 'capture_truck_turntables.ps1') -Output $Output
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
