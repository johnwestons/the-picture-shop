[CmdletBinding()]
param(
    [string[]] $DeviceSerials,
    [switch] $Install,
    [switch] $Launch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Launch -and -not $Install) {
    throw '-Launch requires -Install.'
}

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'output\mobile'))
$reportPath = [IO.Path]::GetFullPath((Join-Path $outputRoot `
    'device-tests\lan-acceptance-preflight.json'))
$adb = [IO.Path]::GetFullPath((Join-Path $outputRoot `
    'tooling\android-sdk\platform-tools\adb.exe'))
$apkReportPath = [IO.Path]::GetFullPath((Join-Path $outputRoot `
    'apk-report.json'))
$configPath = [IO.Path]::GetFullPath((Join-Path $projectRoot `
    'mobile\config.json'))

function Assert-RegularFile([string] $Path, [string] $Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing."
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must not be a reparse point."
    }
}

function Assert-Serial([string] $Serial) {
    if ([string]::IsNullOrWhiteSpace($Serial) -or
            $Serial -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
        throw 'An Android device serial is invalid.'
    }
}

function Get-ConnectedSerials {
    $serials = @(& $adb devices 2>$null | Select-Object -Skip 1 |
        ForEach-Object {
            if ([string]$_ -cmatch '^([^\s]+)\s+device$') { $Matches[1] }
        })
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate Android devices.' }
    return @($serials | Sort-Object -Unique)
}

function Get-PackageVersion([string] $Serial, [string] $ApplicationId) {
    $text = (& $adb '-s' $Serial 'shell' 'dumpsys' 'package' `
        $ApplicationId 2>$null | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect $Serial." }
    $nameMatch = [regex]::Match($text, '(?m)^\s*versionName=([^\r\n]+)')
    $codeMatch = [regex]::Match($text, '(?m)^\s*versionCode=([0-9]+)')
    if (-not $nameMatch.Success -or -not $codeMatch.Success) {
        return $null
    }
    return [ordered]@{
        versionName = $nameMatch.Groups[1].Value.Trim()
        versionCode = [int]$codeMatch.Groups[1].Value
    }
}

function Get-SaveManifest([string] $Serial, [string] $ApplicationId) {
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($slot in 1..3) {
        foreach ($suffix in @('.lua', '.lua.bak')) {
            $relative = "files/save/the-picture-shop/saves/slot$slot$suffix"
            $hashLine = (& $adb '-s' $Serial 'shell' 'run-as' `
                $ApplicationId 'sha256sum' $relative 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) { continue }
            if ($hashLine -cnotmatch '^([0-9a-f]{64})\s+') {
                throw "A save checksum from $Serial was malformed."
            }
            $hash = $Matches[1]
            $sizeText = (& $adb '-s' $Serial 'shell' 'run-as' `
                $ApplicationId 'stat' '-c' '%s' $relative 2>$null |
                Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or $sizeText -cnotmatch '^[0-9]+$') {
                throw "A save size from $Serial was malformed."
            }
            $items.Add([ordered]@{
                path = $relative
                bytes = [int64]$sizeText
                sha256 = $hash
            })
        }
    }
    return @($items)
}

function Get-DeviceRecord([string] $Serial, [string] $ApplicationId) {
    $model = (& $adb '-s' $Serial 'shell' 'getprop' `
        'ro.product.model' 2>$null | Out-String).Trim()
    $android = (& $adb '-s' $Serial 'shell' 'getprop' `
        'ro.build.version.release' 2>$null | Out-String).Trim()
    if (-not $model -or -not $android) {
        throw "Could not read device identity for $Serial."
    }
    return [ordered]@{
        serial = $Serial
        model = $model
        androidVersion = $android
        installedPackage = Get-PackageVersion $Serial $ApplicationId
        saves = @(Get-SaveManifest $Serial $ApplicationId)
    }
}

function Get-SaveFingerprint([object] $Record) {
    return (@($Record.saves) | ConvertTo-Json -Depth 4 -Compress)
}

function Write-Evidence([object] $Evidence) {
    $prefix = $outputRoot.TrimEnd('\') + '\'
    if (-not $reportPath.StartsWith(
            $prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Device-test report escaped the mobile output directory.'
    }
    $parent = Split-Path -Parent $reportPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [IO.File]::WriteAllText(
        $reportPath,
        (($Evidence | ConvertTo-Json -Depth 10) + [Environment]::NewLine),
        [Text.UTF8Encoding]::new($false))
}

Assert-RegularFile $adb 'Android platform tool'
Assert-RegularFile $apkReportPath 'Android APK report'
Assert-RegularFile $configPath 'Mobile configuration'

$apkReport = Get-Content -Raw -LiteralPath $apkReportPath | ConvertFrom-Json
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$apkPath = [IO.Path]::GetFullPath([string]$apkReport.apk)
Assert-RegularFile $apkPath 'Android APK'
if (-not $apkPath.StartsWith(
        ($outputRoot.TrimEnd('\') + '\'),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Android APK escaped the mobile output directory.'
}
$actualApkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath `
    $apkPath).Hash.ToLowerInvariant()
if ($actualApkHash -cne [string]$apkReport.sha256 -or
        [int64](Get-Item -LiteralPath $apkPath).Length -ne
            [int64]$apkReport.apkBytes -or
        [string]$apkReport.versionName -cne [string]$config.versionName -or
        [int]$apkReport.versionCode -ne [int]$config.versionCode -or
        [string]$apkReport.applicationId -cne [string]$config.applicationId -or
        $apkReport.signed -ne $true -or
        $apkReport.sixteenKbCompatible -ne $true) {
    throw 'Android APK no longer matches its verified build contract.'
}

$connected = @(Get-ConnectedSerials)
$requestedSerials = @($DeviceSerials | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_)
})
$selected = $null
if ($requestedSerials.Count -gt 0) {
    $selected = @($requestedSerials | ForEach-Object { ([string]$_).Trim() } |
            Sort-Object -Unique)
} else {
    $selected = @($connected)
}
if ($selected.Count -lt 1) { throw 'No authorized Android device is connected.' }
foreach ($serial in $selected) {
    Assert-Serial $serial
    if ($connected -cnotcontains $serial) {
        throw "Selected Android device $serial is not connected and authorized."
    }
}

$before = @($selected | ForEach-Object {
    Get-DeviceRecord $_ ([string]$apkReport.applicationId)
})
$after = $null

if ($Install) {
    if ($selected.Count -lt 2) {
        throw 'LAN physical acceptance requires at least two selected phones.'
    }
    foreach ($serial in $selected) {
        & $adb '-s' $serial 'install' '-r' $apkPath | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "APK installation failed on $serial." }
    }
    $after = @($selected | ForEach-Object {
        Get-DeviceRecord $_ ([string]$apkReport.applicationId)
    })
    for ($index = 0; $index -lt $before.Count; $index++) {
        $version = $after[$index].installedPackage
        if ($null -eq $version -or
                [string]$version.versionName -cne [string]$apkReport.versionName -or
                [int]$version.versionCode -ne [int]$apkReport.versionCode) {
            throw "Installed package verification failed on $($selected[$index])."
        }
        if ((Get-SaveFingerprint $before[$index]) -cne
                (Get-SaveFingerprint $after[$index])) {
            throw "Save files changed during installation on $($selected[$index])."
        }
        if ($Launch) {
            & $adb '-s' $selected[$index] 'shell' 'am' 'force-stop' `
                ([string]$apkReport.applicationId) *> $null
            & $adb '-s' $selected[$index] 'shell' 'am' 'start' '-W' '-n' `
                "$($apkReport.applicationId)/org.love2d.android.GameActivity" |
                Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "Game launch failed on $($selected[$index])."
            }
        }
    }
}

$evidence = [ordered]@{
    schemaVersion = 1
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    installRequested = [bool]$Install
    launchRequested = [bool]$Launch
    apk = [ordered]@{
        versionName = [string]$apkReport.versionName
        versionCode = [int]$apkReport.versionCode
        bytes = [int64]$apkReport.apkBytes
        sha256 = $actualApkHash
    }
    connectedDeviceCount = $connected.Count
    selectedDeviceCount = $selected.Count
    before = $before
    after = $after
    saveFilesPreserved = if ($Install) { $true } else { $null }
    status = if ($Install) { 'installed_verified' } else { 'inventory_only' }
}
Write-Evidence $evidence

Write-Output "LAN_DEVICE_PREFLIGHT=PASS status=$($evidence.status) devices=$($selected.Count)"
Write-Output "APK_SHA256=$actualApkHash"
Write-Output "REPORT=$reportPath"
