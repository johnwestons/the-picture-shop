[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$mobileRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'output\mobile'))
$deviceTestRoot = [IO.Path]::GetFullPath((Join-Path $mobileRoot 'device-tests'))
$preflightPath = [IO.Path]::GetFullPath((Join-Path $deviceTestRoot `
    'lan-acceptance-preflight.json'))
$adb = [IO.Path]::GetFullPath((Join-Path $mobileRoot `
    'tooling\android-sdk\platform-tools\adb.exe'))
$applicationId = 'com.thepictureshop.game'
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssZ')
$backupRoot = $null
$allowedSave = '^files/save/the-picture-shop/saves/slot[1-3]\.lua(?:\.bak)?$'

function Assert-WithinRoot([string] $Path, [string] $Root) {
    $full = [IO.Path]::GetFullPath($Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $prefix = $rootFull + '\'
    if ($full -cne $rootFull -and -not $full.StartsWith(
            $prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Save backup path escaped its guarded output directory.'
    }
    return $full
}

function Assert-RegularFile([string] $Path, [string] $Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing."
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must not be a reparse point."
    }
}

function Export-Save(
    [string] $Serial,
    [string] $RelativePath,
    [string] $Destination
) {
    if ($Serial -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' -or
            $RelativePath -cnotmatch $allowedSave) {
        throw 'The save export request is outside the allowlist.'
    }
    $destinationFull = Assert-WithinRoot $Destination $backupRoot
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $adb
    $info.Arguments = "-s $Serial exec-out run-as $applicationId cat $RelativePath"
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Could not start the save export.' }
    try {
        $file = [IO.FileStream]::new(
            $destinationFull,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None)
        try {
            $copy = $process.StandardOutput.BaseStream.CopyToAsync($file)
            $errorRead = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $copy.GetAwaiter().GetResult() | Out-Null
            $errorText = $errorRead.GetAwaiter().GetResult()
        } finally {
            $file.Dispose()
        }
        if ($process.ExitCode -ne 0) {
            [IO.File]::Delete($destinationFull)
            throw "Save export failed without changing the phone: $errorText"
        }
    } finally {
        $process.Dispose()
    }
}

Assert-RegularFile $adb 'Android platform tool'
Assert-RegularFile $preflightPath 'LAN device preflight report'
$preflight = Get-Content -Raw -LiteralPath $preflightPath | ConvertFrom-Json
if ($preflight.status -cne 'inventory_only' -or
        $preflight.installRequested -ne $false -or
        [int]$preflight.selectedDeviceCount -lt 1) {
    throw 'A fresh non-installing device preflight is required before backup.'
}
$targetVersion = [string]$preflight.apk.versionName
if ($targetVersion -cnotmatch '^[0-9A-Za-z.-]{1,64}$') {
    throw 'The preflight target version is unsafe for a backup folder name.'
}
$backupRoot = [IO.Path]::GetFullPath((Join-Path $deviceTestRoot `
    "save-backups\$stamp-pre-$targetVersion"))
Assert-WithinRoot $backupRoot $deviceTestRoot | Out-Null

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$manifestDevices = [System.Collections.Generic.List[object]]::new()
foreach ($device in @($preflight.before)) {
    $serial = [string]$device.serial
    if ($serial -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
        throw 'The preflight contains an invalid device serial.'
    }
    $deviceRoot = Assert-WithinRoot (Join-Path $backupRoot $serial) $backupRoot
    New-Item -ItemType Directory -Path $deviceRoot -Force | Out-Null
    $saved = [System.Collections.Generic.List[object]]::new()
    foreach ($save in @($device.saves)) {
        $relative = [string]$save.path
        if ($relative -cnotmatch $allowedSave) {
            throw 'The preflight contains a save outside the allowlist.'
        }
        $destination = Assert-WithinRoot (
            Join-Path $deviceRoot ([IO.Path]::GetFileName($relative))) $backupRoot
        Export-Save $serial $relative $destination
        $actualBytes = [int64](Get-Item -LiteralPath $destination).Length
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath `
            $destination).Hash.ToLowerInvariant()
        if ($actualBytes -ne [int64]$save.bytes -or
                $actualHash -cne [string]$save.sha256) {
            throw 'A local save backup does not match the phone checksum.'
        }
        $saved.Add([ordered]@{
            source = $relative
            file = "$serial/$([IO.Path]::GetFileName($relative))"
            bytes = $actualBytes
            sha256 = $actualHash
        })
    }
    $manifestDevices.Add([ordered]@{
        serial = $serial
        model = [string]$device.model
        saves = @($saved)
    })
}

$manifest = [ordered]@{
    schemaVersion = 1
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    sourcePreflightCreatedAtUtc = [string]$preflight.createdAtUtc
    applicationId = $applicationId
    phoneDataChanged = $false
    devices = @($manifestDevices)
}
$manifestPath = Assert-WithinRoot (Join-Path $backupRoot 'manifest.json') `
    $backupRoot
[IO.File]::WriteAllText(
    $manifestPath,
    (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false))

Write-Output "ANDROID_SAVE_BACKUP=PASS devices=$($manifestDevices.Count)"
Write-Output "BACKUP_ROOT=$backupRoot"
Write-Output "MANIFEST=$manifestPath"
