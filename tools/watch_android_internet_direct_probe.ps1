[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$HostSerial,
    [Parameter(Mandatory=$true)][string]$ClientSerial,
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$ExpiresUtc
)

$ErrorActionPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

if ($HostSerial -notmatch '^[A-Za-z0-9._:-]{1,128}$' -or
        $ClientSerial -notmatch '^[A-Za-z0-9._:-]{1,128}$' -or
        $HostSerial -ceq $ClientSerial -or $RunId -notmatch '^[0-9a-f]{32}$') {
    exit 2
}
$expiresAt = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse($ExpiresUtc,[ref]$expiresAt) -or
        $expiresAt -le [DateTimeOffset]::UtcNow -or
        $expiresAt -gt [DateTimeOffset]::UtcNow.AddMinutes(15)) {
    exit 2
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$adb = Join-Path $projectRoot 'output\mobile\tooling\android-sdk\platform-tools\adb.exe'
$statePath = Join-Path $projectRoot `
    'output\native-crypto\probe\android\internet-direct\active-state.json'
$hostPackage = 'com.thepictureshop.direct_probe.host'
$clientPackage = 'com.thepictureshop.direct_probe.client'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { exit 2 }

while ([DateTimeOffset]::UtcNow -lt $expiresAt) {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { exit 0 }
    $active = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    if ([string]$active.runId -cne $RunId) { exit 0 }
    Start-Sleep -Seconds 10
}

# This watchdog never trusts state for a mutation target. It retries the fixed
# diagnostic IDs briefly so a transient ADB interruption does not turn the
# expiry cleanup into a single best-effort packet.
$cleanupDeadline = [DateTimeOffset]::UtcNow.AddMinutes(2)
do {
    & $adb -s $HostSerial shell am force-stop $hostPackage *> $null
    & $adb -s $ClientSerial shell am force-stop $clientPackage *> $null
    & $adb -s $HostSerial uninstall $hostPackage *> $null
    & $adb -s $ClientSerial uninstall $clientPackage *> $null

    $hostState = (& $adb -s $HostSerial get-state 2>&1 | Out-String).Trim()
    $hostOnline = $LASTEXITCODE -eq 0 -and $hostState -ceq 'device'
    $clientState = (& $adb -s $ClientSerial get-state 2>&1 | Out-String).Trim()
    $clientOnline = $LASTEXITCODE -eq 0 -and $clientState -ceq 'device'
    $hostList = (& $adb -s $HostSerial shell pm list packages --user 0 `
        $hostPackage 2>&1 | Out-String).Trim()
    $hostAbsent = $LASTEXITCODE -eq 0 -and [string]::IsNullOrWhiteSpace($hostList)
    $clientList = (& $adb -s $ClientSerial shell pm list packages --user 0 `
        $clientPackage 2>&1 | Out-String).Trim()
    $clientAbsent = $LASTEXITCODE -eq 0 -and [string]::IsNullOrWhiteSpace($clientList)
    if ($hostOnline -and $clientOnline -and $hostAbsent -and $clientAbsent) { exit 0 }
    Start-Sleep -Seconds 5
} while ([DateTimeOffset]::UtcNow -lt $cleanupDeadline)
exit 0
