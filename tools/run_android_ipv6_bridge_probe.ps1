[CmdletBinding()]
param(
    [ValidateScript({ $_ -eq 0 -or ($_ -ge 20000 -and $_ -le 60999) })]
    [int]$Port = 0,
    [ValidateRange(45,120)][int]$TimeoutSeconds = 75
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$runner = Join-Path $PSScriptRoot 'run_android_ipv6_simultaneous_probe.ps1'
& $runner -Port $Port -TimeoutSeconds $TimeoutSeconds -EncryptedBridge
exit $LASTEXITCODE
