param(
    [ValidateRange(60,300)][int]$PhaseTimeoutSeconds = 180,
    [switch]$PreflightOnly,
    [switch]$PacketCaptureValidation,
    [ValidateSet(1,2)][int]$AndroidGuestCount = 1
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ($AndroidGuestCount -eq 2 -and $PacketCaptureValidation) {
    throw 'Two-guest packet-capture validation is not available until its two-port recovery contract is installed.'
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mobileOutputRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $projectRoot 'output\mobile'))
$baseReportPath = Join-Path $mobileOutputRoot 'build-report.json'
$adb = Join-Path $mobileOutputRoot 'tooling\android-sdk\platform-tools\adb.exe'
$builder = Join-Path $PSScriptRoot 'build_android_apk.ps1'
$probeMain = Join-Path $PSScriptRoot 'probes\android_direct_gameplay\main.lua'
$loveConsole = 'C:\Program Files\LOVE\lovec.exe'
$windowsCrypto = Join-Path $projectRoot `
    'output\native-crypto\build\windows-x64\tps_crypto.dll'
$providerSource = Join-Path $projectRoot 'src\net\crypto_native.lua'
$evidenceRoot = Join-Path $projectRoot 'output\native-crypto\device-tests'
$reportStem = if ($AndroidGuestCount -eq 2) {
    'pc_two_android_direct_gameplay_report'
} elseif ($PacketCaptureValidation) {
    'pc_android_direct_packet_capture_report'
} else {
    'pc_android_direct_gameplay_report'
}
$evidencePath = Join-Path $evidenceRoot "$reportStem.json"
$pendingPath = Join-Path $evidenceRoot "$reportStem.pending.json"
$captureRecoveryPaths = @(
    (Join-Path $evidenceRoot `
        'pc_android_direct_packet_capture_filter_recovery.json'),
    (Join-Path $evidenceRoot `
        'pc_android_direct_packet_capture_recovery.json')
)
$guestPackage = 'com.thepictureshop.direct_probe.client'
$androidSaveRoot = 'files/save/the-picture-shop/probe'
$directPort = 57842
$directPorts = $AndroidGuestCount -eq 2 ? @(57842,57844) : @(57842)
$temporaryParent = [System.IO.Path]::GetFullPath(
    (Join-Path ([System.IO.Path]::GetTempPath()) `
        'ThePictureShop\pc-android-direct-gameplay'))
$initialWorkingDirectory = [System.IO.Path]::GetFullPath(
    $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.Path)
$externalCaptureFallbackPaths = @(
    [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'PktMon.etl'))
    [System.IO.Path]::GetFullPath((Join-Path $initialWorkingDirectory 'PktMon.etl'))
) | Select-Object -Unique
$loveSaveParent = [System.IO.Path]::GetFullPath(
    (Join-Path $env:APPDATA 'LOVE'))

$runId = [Guid]::NewGuid().ToString('N')
$pcIdentity = "the-picture-shop-pc-probe-$runId"
$pcPlayerCanary = 'TPSPC' + $runId.Substring(0,19)
$androidPlayerCanary = 'TPSAND' + $runId.Substring(14,18)
$androidPlayerCanaries = if ($AndroidGuestCount -eq 2) {
    @(
        ('TPSA' + $runId.Substring(0,20)),
        ('TPSB' + $runId.Substring(12,20))
    )
} else {
    @($androidPlayerCanary)
}
$pcSaveRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $loveSaveParent $pcIdentity))
$temporaryRoot = $null
$guestDevice = $null
$guestInterface = $null
$guestAddress = $null
$guestContexts = @()
$pcAddress = $null
$pcInterfaceIndex = $null
$pcProcessContext = $null
$androidMarkerLogBaseline = ''
$androidMarkerProcessId = $null
$runMutex = $null
$mutexOwned = $false
$stage = 'initialization'
$failureStage = $null
$failureClass = $null
$failureExceptionType = $null
$failure = $null
$preflightPassed = $false
$androidInstalled = $false
$androidPackageAbsent = $false
$pcProcessExited = $true
$pcIdentityRemoved = $false
$temporaryArtifactsRemoved = $false
$cleanupVerified = $false
$preserveExistingPendingReport = $false
$routesRevalidated = $false
$multiTopologyRouteMix = $false
$multiTopologyUniqueAddresses = $false
$multiTopologySharedPcSource = $false
$multiTopologyAtLeastOneDistinctPrefix = $false
$artifactSafetyVerified = $false
$windowsFirewallReady = $false
$kickResult = $null
$gracefulResult = $null
$multiGuestResult = $null
$captureFilterName = 'TPS_' + $runId.Substring(0,20)
$captureFilterFingerprint = $null
$captureFilterAddAttempted = $false
$captureFilterMayRemain = $false
$captureFilterSnapshot = $null
$captureActive = $false
$captureEverStarted = $false
$captureStartAttempted = $false
$captureFilterOwned = $false
$captureStopped = $true
$captureFilterRemoved = $true
$captureArtifactsRemoved = $true
$captureOutputContained = $false
$captureExternalArtifactDetected = $false
$captureEncodedCanaries = $false
$captureResult = $null
$captureEtlPath = $null
$capturePcapPath = $null
$captureSensitivePatterns = [System.Collections.Generic.List[object]]::new()
$captureInvitationIds = [System.Collections.Generic.List[object]]::new()
$reportSensitiveValues = [System.Collections.Generic.List[string]]::new()

function Get-LowerSha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-LowerSha256Text {
    param([Parameter(Mandatory=$true)][string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash($bytes)
        try {
            return ([Convert]::ToHexString($digest)).ToLowerInvariant()
        } finally {
            [Array]::Clear($digest,0,$digest.Length)
        }
    } finally {
        [Array]::Clear($bytes,0,$bytes.Length)
        $sha.Dispose()
    }
}

$captureFilterFingerprint = Get-LowerSha256Text -Value $captureFilterName

if (-not ('TpsCaptureByteSearch' -as [type])) {
    Add-Type -TypeDefinition @'
using System;

public static class TpsCaptureByteSearch
{
    public static bool Contains(byte[] source, byte[] pattern)
    {
        if (source == null || pattern == null || pattern.Length == 0 ||
            pattern.Length > source.Length) return false;
        byte first = pattern[0];
        int limit = source.Length - pattern.Length;
        for (int offset = 0; offset <= limit; offset++) {
            if (source[offset] != first) continue;
            int index = 1;
            while (index < pattern.Length &&
                   source[offset + index] == pattern[index]) index++;
            if (index == pattern.Length) return true;
        }
        return false;
    }

    public static int Count(byte[] source, byte[] pattern)
    {
        if (source == null || pattern == null || pattern.Length == 0 ||
            pattern.Length > source.Length) return 0;
        int matches = 0;
        int limit = source.Length - pattern.Length;
        for (int offset = 0; offset <= limit; offset++) {
            int index = 0;
            while (index < pattern.Length &&
                   source[offset + index] == pattern[index]) index++;
            if (index == pattern.Length) matches++;
        }
        return matches;
    }
}
'@
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-PktMon {
    param(
        [Parameter(Mandatory=$true)][string[]]$CommandArguments,
        [string]$WorkingDirectory
    )
    if ($WorkingDirectory) {
        $workingRoot = [IO.Path]::GetFullPath($WorkingDirectory)
        if (-not (Test-Path -LiteralPath $workingRoot -PathType Container)) {
            throw 'The private packet-capture working directory is unavailable.'
        }
        $workingItem = Get-Item -LiteralPath $workingRoot -Force
        if (($workingItem.Attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'The private packet-capture working directory is unsafe.'
        }
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = "$env:SystemRoot\System32\PktMon.exe"
        $startInfo.WorkingDirectory = $workingRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in $CommandArguments) {
            $startInfo.ArgumentList.Add([string]$argument)
        }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) {
                throw 'Windows Packet Monitor could not be launched.'
            }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $stdout = $stdoutTask.GetAwaiter().GetResult().TrimEnd()
            $stderr = $stderrTask.GetAwaiter().GetResult().TrimEnd()
            $parts = @($stdout,$stderr) | Where-Object { $_ }
            return [pscustomobject]@{
                exitCode = $process.ExitCode
                output = [string]($parts -join "`n")
            }
        } finally {
            $process.Dispose()
        }
    }
    $commandOutput = @(& "$env:SystemRoot\System32\PktMon.exe" `
        @CommandArguments 2>&1) -join "`n"
    return [pscustomobject]@{
        exitCode = $LASTEXITCODE
        output = [string]$commandOutput
    }
}

function Test-ExternalCaptureFallbackAbsent {
    $absent = $true
    foreach ($path in $externalCaptureFallbackPaths) {
        if (Test-Path -LiteralPath $path) {
            $absent = $false
            $script:captureExternalArtifactDetected = $true
        }
    }
    return $absent
}

function Get-OptionalPropertyValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory=$true)][string]$Name,
        $Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    return $property ? $property.Value : $Default
}

function Test-CapturePendingUnresolved {
    param([Parameter(Mandatory=$true)]$Report)
    if ((Get-OptionalPropertyValue -InputObject $Report -Name 'artifactKind') `
            -cne 'windows-android-direct-packet-capture-engineering-probe' -or
            (Get-OptionalPropertyValue -InputObject $Report -Name 'result') `
            -cne 'failed') {
        return $true
    }
    $packet = Get-OptionalPropertyValue -InputObject $Report `
        -Name 'packetCapture'
    $cleanup = Get-OptionalPropertyValue -InputObject $Report -Name 'cleanup'
    if ($null -eq $packet -or $null -eq $cleanup) { return $true }
    $filterMayRemain = [bool](Get-OptionalPropertyValue `
        -InputObject $packet -Name 'filterMayRemain' -Default $false)
    $rawRetained = [bool](Get-OptionalPropertyValue `
        -InputObject $packet -Name 'rawCaptureRetained' -Default $true)
    $endpointRetained = [bool](Get-OptionalPropertyValue `
        -InputObject $packet -Name 'endpointRetained' -Default $true)
    $stopped = (Get-OptionalPropertyValue -InputObject $cleanup `
        -Name 'packetCaptureStopped' -Default $false) -eq $true
    $filterRemoved = (Get-OptionalPropertyValue -InputObject $cleanup `
        -Name 'packetCaptureFilterRemoved' -Default $false) -eq $true
    $artifactsRemoved = (Get-OptionalPropertyValue -InputObject $cleanup `
        -Name 'packetCaptureArtifactsRemoved' -Default $false) -eq $true
    $temporaryRemoved = (Get-OptionalPropertyValue -InputObject $cleanup `
        -Name 'sensitiveTemporaryArtifactsRemoved' -Default $false) -eq $true
    return $filterMayRemain -or $rawRetained -or $endpointRetained -or
        -not $stopped -or -not $filterRemoved -or -not $artifactsRemoved -or
        -not $temporaryRemoved
}

function Get-BoundCaptureRecoveryPaths {
    param([Parameter(Mandatory=$true)][string]$PendingReportPath)
    $pendingHash = (Get-FileHash -Algorithm SHA256 `
        -LiteralPath $PendingReportPath).Hash.ToLowerInvariant()
    $matches = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $captureRecoveryPaths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $before = (Get-FileHash -Algorithm SHA256 `
                -LiteralPath $path).Hash
            $recovery = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
            $after = (Get-FileHash -Algorithm SHA256 `
                -LiteralPath $path).Hash
            $privacy = Get-OptionalPropertyValue -InputObject $recovery `
                -Name 'privacy'
            $cleanup = Get-OptionalPropertyValue -InputObject $recovery `
                -Name 'cleanup'
            $kind = Get-OptionalPropertyValue -InputObject $recovery `
                -Name 'artifactKind'
            $bound = $before -ceq $after -and
                $kind -in @('windows-direct-orphan-filter-recovery',
                    'windows-direct-packet-capture-recovery') -and
                (Get-OptionalPropertyValue -InputObject $recovery `
                    -Name 'result') -ceq 'recovered' -and
                (Get-OptionalPropertyValue -InputObject $recovery `
                    -Name 'sourcePendingSha256') -ceq $pendingHash -and
                (Get-OptionalPropertyValue -InputObject $privacy `
                    -Name 'rawCaptureRetained' -Default $true) -eq $false -and
                (Get-OptionalPropertyValue -InputObject $cleanup `
                    -Name 'packetCaptureStopped' -Default $false) -eq $true -and
                (Get-OptionalPropertyValue -InputObject $cleanup `
                    -Name 'packetCaptureFilterRemoved' -Default $false) -eq $true -and
                (Get-OptionalPropertyValue -InputObject $cleanup `
                    -Name 'packetCaptureArtifactsRemoved' -Default $false) -eq $true -and
                (Get-OptionalPropertyValue -InputObject $cleanup `
                    -Name 'outsideFallbackAbsent' -Default $false) -eq $true -and
                (Get-OptionalPropertyValue -InputObject $cleanup `
                    -Name 'verified' -Default $false) -eq $true
            if ($bound) { $matches.Add($path) }
        } catch {
            continue
        }
    }
    return @($matches)
}

function Write-AtomicJsonReport {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)]$Value
    )
    $directory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw 'The report directory is unavailable.'
    }
    $temporary = Join-Path $directory (
        ([IO.Path]::GetFileName($Path)) + ".$runId.tmp")
    if (Test-Path -LiteralPath $temporary) {
        throw 'The atomic report staging path was not empty.'
    }
    try {
        [IO.File]::WriteAllText($temporary,
            ($Value | ConvertTo-Json -Depth 10) + "`n",
            [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary,[IO.Path]::GetFullPath($Path),$true)
    } finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Add-ReportSensitiveValue {
    param([AllowNull()][string]$Value)
    if (-not [string]::IsNullOrEmpty($Value) -and
            -not $reportSensitiveValues.Contains($Value)) {
        $reportSensitiveValues.Add($Value)
    }
}

function Assert-ReportSecretFree {
    param([Parameter(Mandatory=$true)]$Value)
    $json = $Value | ConvertTo-Json -Depth 10
    if ($json -match 'TPS2[HR][A-Za-z0-9_.-]{8,}') {
        throw 'A Direct invitation code appeared in the redacted report.'
    }
    foreach ($sensitive in $reportSensitiveValues) {
        if ($sensitive -and $json.Contains($sensitive)) {
            throw 'A private Direct runtime value appeared in the redacted report.'
        }
    }
    return $true
}

function Release-ProbeMutex {
    if ($script:mutexOwned -and $script:runMutex) {
        $script:runMutex.ReleaseMutex()
        $script:mutexOwned = $false
    }
    if ($script:runMutex) {
        $script:runMutex.Dispose()
        $script:runMutex = $null
    }
}

function Normalize-PktMonText {
    param([AllowEmptyString()][string]$Value)
    return (($Value -replace "`r`n","`n").Trim())
}

function Get-PktMonFilterRowCount {
    param([AllowEmptyString()][string]$Value)
    return @(Get-PktMonFilterRows -Value $Value).Count
}

function Get-PktMonFilterRows {
    param([AllowEmptyString()][string]$Value)
    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($Value,
            '(?im)^\s*(?:filter\s+)?\d+(?:\s+|[.:)]|-)[^\r\n]*$')) {
        $rows.Add($match.Value)
    }
    return @($rows)
}

function Get-PktMonFilterRowNames {
    param([AllowEmptyString()][string]$Value)
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [regex]::Split($Value,'\r?\n')) {
        $match = [regex]::Match($line,
            ('^\s*(?:filter\s+)?\d+' +
             '(?:\s*[:.)-]\s*|\s+)' +
             '(?:name\s*[:=]\s*)?' +
             '(?<name><empty>|[A-Za-z0-9_.-]+)(?:\s|$)'),
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            $names.Add($match.Groups['name'].Value)
        }
    }
    return @($names)
}

function Test-PktMonInactiveStatus {
    param([Parameter(Mandatory=$true)]$Status)
    return $Status.exitCode -eq 0 -and $Status.output -match
        '(?im)^[^\r\n]*(?:not\s+running|stopped|inactive|no\s+active)[^\r\n]*$'
}

function Test-PktMonOwnedActiveStatus {
    param(
        [Parameter(Mandatory=$true)]$Status,
        [Parameter(Mandatory=$true)][string]$ExpectedLogPath
    )
    $full = [IO.Path]::GetFullPath($ExpectedLogPath)
    $inactive = $Status.output -match
        '(?im)^[^\r\n]*(?:not\s+running|stopped|inactive|no\s+active)[^\r\n]*$'
    $mentionsAnyEtl = $Status.output -match '(?i)\.etl(?:\s|$|["''])'
    $expectedPathIfShown = -not $mentionsAnyEtl -or
        $Status.output.IndexOf($full,
            [StringComparison]::OrdinalIgnoreCase) -ge 0
    return $Status.exitCode -eq 0 -and -not $inactive -and
        $Status.output -match '(?im)logger\s+name\s*:\s*pktmon\s*$' -and
        $Status.output -match '(?i)packet\s+capture' -and
        $Status.output -match '(?i)all\s+packets' -and
        $Status.output -match '(?i)\bnics\b|network\s+adapters?' -and
        $expectedPathIfShown
}

function Assert-PktMonCapturePreflight {
    if (-not (Test-IsAdministrator)) {
        throw 'Packet-capture validation requires an Administrator PowerShell window.'
    }
    if (-not (Test-Path -LiteralPath "$env:SystemRoot\System32\PktMon.exe" `
            -PathType Leaf)) {
        throw 'Windows Packet Monitor is unavailable.'
    }
    if (-not (Test-ExternalCaptureFallbackAbsent)) {
        throw 'An uncontained Windows packet-capture artifact requires recovery.'
    }
    $status = Invoke-PktMon -CommandArguments @('status')
    if (-not (Test-PktMonInactiveStatus -Status $status)) {
        throw 'Another Windows packet capture may already be active.'
    }
    $filters = Invoke-PktMon -CommandArguments @('filter','list')
    if ($filters.exitCode -ne 0 -or
            $filters.output -notmatch '(?im)^\s*none\.?\s*$' -or
            (Get-PktMonFilterRowCount -Value $filters.output) -ne 0) {
        throw 'Windows Packet Monitor already has filters; they will not be changed.'
    }
    return $true
}

function Add-CapturePattern {
    param(
        [Parameter(Mandatory=$true)][ValidateSet(
            'invitation_secret','invitation_code','player_name','gameplay_plaintext')]
        [string]$Category,
        [Parameter(Mandatory=$true)][byte[]]$Bytes
    )
    if ($Bytes.Length -lt 4) { throw 'Capture privacy pattern is too short.' }
    $copy = [byte[]]::new($Bytes.Length)
    [Array]::Copy($Bytes,$copy,$Bytes.Length)
    $captureSensitivePatterns.Add([pscustomobject]@{
        category = $Category
        bytes = $copy
    })
}

function ConvertFrom-DirectBase64Url {
    param([Parameter(Mandatory=$true)][string]$Value)
    if ($Value -notmatch '^[A-Za-z0-9_-]+$') {
        throw 'Private Direct code encoding was invalid.'
    }
    $base64 = $Value.Replace('-','+').Replace('_','/')
    $base64 += '=' * ((4 - ($base64.Length % 4)) % 4)
    try {
        return [Convert]::FromBase64String($base64)
    } catch {
        throw 'Private Direct code encoding could not be decoded.'
    }
}

function Get-DirectHostInvitationMaterial {
    param([Parameter(Mandatory=$true)][string]$HostCode)
    if (-not $HostCode.StartsWith('TPS2H.')) {
        throw 'Private Direct host material had the wrong kind.'
    }
    $hostBytes = ConvertFrom-DirectBase64Url -Value $HostCode.Substring(6)
    if ($hostBytes.Length -ne 76 -or $hostBytes[0] -ne 2 -or
            $hostBytes[1] -ne 1 -or $hostBytes[2] -ne 6 -or
            $hostBytes[3] -ne 0) {
        [Array]::Clear($hostBytes,0,$hostBytes.Length)
        throw 'Private Direct host material had the wrong shape.'
    }
    $masterKey = [byte[]]::new(32)
    $invitationId = [byte[]]::new(16)
    $addressBytes = [byte[]]::new(16)
    $port = ([int]$hostBytes[10] -shl 8) -bor [int]$hostBytes[11]
    [Array]::Copy($hostBytes,12,$addressBytes,0,16)
    [Array]::Copy($hostBytes,44,$masterKey,0,32)
    [Array]::Copy($hostBytes,28,$invitationId,0,16)
    [Array]::Clear($hostBytes,0,$hostBytes.Length)
    return [pscustomobject]@{
        port = $port
        addressBytes = $addressBytes
        invitationId = $invitationId
        masterKey = $masterKey
    }
}

function Test-BytesEqual {
    param(
        [Parameter(Mandatory=$true)][byte[]]$First,
        [Parameter(Mandatory=$true)][byte[]]$Second
    )
    return [Security.Cryptography.CryptographicOperations]::FixedTimeEquals(
        $First,$Second)
}

function Test-DirectHostInvitationEndpoint {
    param(
        [Parameter(Mandatory=$true)]$Material,
        [Parameter(Mandatory=$true)][string]$ExpectedAddress,
        [Parameter(Mandatory=$true)][ValidateRange(1,65535)][int]$ExpectedPort
    )
    $expectedBytes = [System.Net.IPAddress]::Parse($ExpectedAddress).GetAddressBytes()
    try {
        return $Material.port -eq $ExpectedPort -and
            (Test-BytesEqual -First $Material.addressBytes -Second $expectedBytes)
    } finally {
        [Array]::Clear($expectedBytes,0,$expectedBytes.Length)
    }
}

function Register-CaptureInvitationMaterial {
    param(
        [Parameter(Mandatory=$true)][string]$HostCode,
        [Parameter(Mandatory=$true)][string]$ResponseCode
    )
    if (-not $PacketCaptureValidation -or -not $captureActive) { return }
    if (-not $HostCode.StartsWith('TPS2H.') -or
            -not $ResponseCode.StartsWith('TPS2R.')) {
        throw 'Private Direct opening material had the wrong kind.'
    }
    $material = Get-DirectHostInvitationMaterial -HostCode $HostCode
    $masterKey = $material.masterKey
    $invitationId = $material.invitationId
    try {
        $captureInvitationIds.Add($invitationId)
        Add-CapturePattern -Category invitation_secret -Bytes $masterKey
        $keyBase64 = [Convert]::ToBase64String($masterKey)
        $keyBase64Url = $keyBase64.TrimEnd('=').Replace('+','-').Replace('/','_')
        $keyHex = [Convert]::ToHexString($masterKey)
        Add-CapturePattern -Category invitation_secret `
            -Bytes ([Text.Encoding]::ASCII.GetBytes($keyBase64Url))
        Add-CapturePattern -Category invitation_secret `
            -Bytes ([Text.Encoding]::ASCII.GetBytes($keyBase64))
        Add-CapturePattern -Category invitation_secret `
            -Bytes ([Text.Encoding]::ASCII.GetBytes($keyBase64.TrimEnd('=')))
        Add-CapturePattern -Category invitation_secret `
            -Bytes ([Text.Encoding]::ASCII.GetBytes($keyHex))
        Add-CapturePattern -Category invitation_secret `
            -Bytes ([Text.Encoding]::ASCII.GetBytes($keyHex.ToLowerInvariant()))
        Add-CapturePattern -Category invitation_code `
            -Bytes ([Text.Encoding]::ASCII.GetBytes($HostCode))
        Add-CapturePattern -Category invitation_code `
            -Bytes ([Text.Encoding]::ASCII.GetBytes($ResponseCode))
    } finally {
        [Array]::Clear($material.addressBytes,0,$material.addressBytes.Length)
        [Array]::Clear($masterKey,0,$masterKey.Length)
    }
}

function Clear-CapturePatterns {
    foreach ($entry in $captureSensitivePatterns) {
        if ($entry.bytes) { [Array]::Clear($entry.bytes,0,$entry.bytes.Length) }
    }
    $captureSensitivePatterns.Clear()
    foreach ($invitationId in $captureInvitationIds) {
        if ($invitationId) { [Array]::Clear($invitationId,0,$invitationId.Length) }
    }
    $captureInvitationIds.Clear()
}

function Start-DirectPacketCapture {
    if (-not $PacketCaptureValidation) { return }
    Assert-PktMonCapturePreflight | Out-Null
    if (-not $temporaryRoot) {
        throw 'The private capture directory is unavailable.'
    }
    Assert-SafeTemporaryRoot -Path $temporaryRoot | Out-Null
    if ($captureFilterName -cnotmatch '^TPS_[0-9a-f]{20}$' -or
            $captureFilterName.Length -ne 24 -or
            [Text.Encoding]::ASCII.GetByteCount($captureFilterName) -ne 24) {
        throw 'The private Direct packet filter identity was invalid.'
    }
    $script:captureEtlPath = Join-Path $temporaryRoot 'PktMon.etl'
    $script:capturePcapPath = Join-Path $temporaryRoot 'direct-private.pcapng'
    foreach ($path in @($script:captureEtlPath,$script:capturePcapPath)) {
        if (-not (Test-PathContainedBy -Path $path -Parent $temporaryRoot) -or
                (Test-Path -LiteralPath $path)) {
            throw 'The private capture path was not empty and contained.'
        }
    }
    Add-CapturePattern -Category player_name `
        -Bytes ([Text.Encoding]::ASCII.GetBytes($pcPlayerCanary))
    Add-CapturePattern -Category player_name `
        -Bytes ([Text.Encoding]::ASCII.GetBytes($androidPlayerCanary))
    Add-CapturePattern -Category gameplay_plaintext `
        -Bytes ([Text.Encoding]::ASCII.GetBytes('loadingBayDoor'))
    Add-CapturePattern -Category gameplay_plaintext `
        -Bytes ([Text.Encoding]::ASCII.GetBytes('emergency_stop'))

    $script:captureFilterAddAttempted = $true
    $script:captureFilterMayRemain = $true
    $script:captureFilterRemoved = $false
    $added = Invoke-PktMon -CommandArguments @(
        'filter','add',$captureFilterName,'-d','IPv6','-t','UDP','-p',
        [string]$directPort)
    if ($added.exitCode -ne 0) {
        throw 'The private Direct packet filter could not be installed.'
    }
    $script:captureFilterOwned = $true
    $listed = Invoke-PktMon -CommandArguments @('filter','list')
    $listedNames = @()
    $listedRows = @()
    if ($listed.exitCode -eq 0) {
        $listedNames = @(Get-PktMonFilterRowNames -Value $listed.output)
        $listedRows = @(Get-PktMonFilterRows -Value $listed.output)
    }
    $listedRowCount = if ($listed.exitCode -eq 0) {
        $listedRows.Count
    } else { -1 }
    $listedRowIpv6Matched = $listedRows.Count -eq 1 -and
        $listedRows[0] -match '(?i)\bIPv6\b'
    $listedRowUdpMatched = $listedRows.Count -eq 1 -and
        $listedRows[0] -match '(?i)\bUDP\b'
    $listedRowPortMatched = $listedRows.Count -eq 1 -and
        $listedRows[0] -match '(?<!\d)57842(?!\d)'
    if ($listed.exitCode -eq 0 -and $listedRowCount -eq 1 -and
            $listedNames.Count -eq $listedRowCount -and
            $listedNames[0] -ceq $captureFilterName) {
        # Store the exact owned snapshot as soon as the unique row identity is
        # proven, so a later detail-verification failure remains cleanable.
        $script:captureFilterSnapshot = Normalize-PktMonText `
            -Value $listed.output
    }
    if (-not $script:captureFilterSnapshot -or
            $listed.output -match '(?im)^\s*none\.?\s*$' -or
            $listedRowCount -ne 1 -or
            $listedNames.Count -ne $listedRowCount -or
            -not $listedRowIpv6Matched -or
            -not $listedRowUdpMatched -or
            -not $listedRowPortMatched) {
        throw 'The private Direct packet filter could not be verified.'
    }
    $script:captureStartAttempted = $true
    $script:captureStopped = $false
    $script:captureArtifactsRemoved = $false
    if (-not (Test-ExternalCaptureFallbackAbsent)) {
        throw 'An uncontained Windows packet-capture artifact requires recovery.'
    }
    $started = Invoke-PktMon -CommandArguments @(
        'start','--capture','--comp','nics','--type','all','--pkt-size','0',
        '--flags','0x010','--file-name','PktMon.etl',
        '--file-size','64','--log-mode','memory') `
        -WorkingDirectory $temporaryRoot
    if ($started.exitCode -ne 0) {
        throw 'The bounded Direct packet capture could not start.'
    }
    $script:captureActive = $true
    $script:captureEverStarted = $true
    $script:captureStopped = $false
    $status = Invoke-PktMon -CommandArguments @('status') `
        -WorkingDirectory $temporaryRoot
    $filtersAfterStart = Invoke-PktMon -CommandArguments @('filter','list') `
        -WorkingDirectory $temporaryRoot
    if (-not (Test-PktMonOwnedActiveStatus -Status $status `
            -ExpectedLogPath $script:captureEtlPath) -or
            -not (Test-ExternalCaptureFallbackAbsent) -or
            $filtersAfterStart.exitCode -ne 0 -or
            (Normalize-PktMonText -Value $filtersAfterStart.output) -cne
                $script:captureFilterSnapshot) {
        throw 'The bounded Direct capture could not be verified as exclusive.'
    }
}

function Assert-DirectCapturePrivacy {
    if (-not (Test-Path -LiteralPath $capturePcapPath -PathType Leaf) -or
            -not (Test-PathContainedBy -Path $capturePcapPath `
                -Parent $temporaryRoot)) {
        throw 'The private packet capture was not produced.'
    }
    $captureItem = Get-Item -LiteralPath $capturePcapPath -Force
    if (($captureItem.Attributes -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'The private packet capture output was unsafe.'
    }
    $captureBytes = [IO.File]::ReadAllBytes($capturePcapPath)
    try {
        if ($captureBytes.Length -lt 128) {
            throw 'The private packet capture contained no usable Direct traffic.'
        }
        $hostFrame = [byte[]]@(
            [byte][char]'T',[byte][char]'P',[byte][char]'S',[byte][char]'B',
            1,1,1,0)
        $guestFrame = [byte[]]@(
            [byte][char]'T',[byte][char]'P',[byte][char]'S',[byte][char]'B',
            1,1,2,0)
        if ($captureInvitationIds.Count -ne 1) {
            throw 'The capture did not retain exactly one private invitation context.'
        }
        $hostInvitationFrame = [byte[]]::new(24)
        $guestInvitationFrame = [byte[]]::new(24)
        [Array]::Copy($hostFrame,0,$hostInvitationFrame,0,8)
        [Array]::Copy($guestFrame,0,$guestInvitationFrame,0,8)
        [Array]::Copy($captureInvitationIds[0],0,$hostInvitationFrame,8,16)
        [Array]::Copy($captureInvitationIds[0],0,$guestInvitationFrame,8,16)
        if ([TpsCaptureByteSearch]::Count(
                $captureBytes,$hostInvitationFrame) -lt 2 -or
                [TpsCaptureByteSearch]::Count(
                    $captureBytes,$guestInvitationFrame) -lt 2) {
            throw 'The capture did not contain Direct bridge frames in both directions.'
        }
        foreach ($entry in $captureSensitivePatterns) {
            if ([TpsCaptureByteSearch]::Contains($captureBytes,$entry.bytes)) {
                throw "Captured Direct traffic exposed $($entry.category.Replace('_',' '))."
            }
        }
        return [pscustomobject]@{
            bidirectionalDirectBridgeFrames = $true
            invitationSecretRepresentationsAbsent = $true
            playerNamesAbsent = $true
            shopGameplayPlaintextAbsent = $true
        }
    } finally {
        [Array]::Clear($captureBytes,0,$captureBytes.Length)
    }
}

function Complete-DirectPacketCapture {
    param([switch]$RequireEvidence)
    $analysis = $null
    $completionError = $null
    $filtersSafeForRemoval = $true
    try {
        if ($captureActive) {
            $ownedStatus = Invoke-PktMon -CommandArguments @('status') `
                -WorkingDirectory $temporaryRoot
            if (-not (Test-PktMonOwnedActiveStatus -Status $ownedStatus `
                    -ExpectedLogPath $captureEtlPath)) {
                throw 'The active packet capture could not be proven to belong to this run.'
            }
            $beforeStopFilters = Invoke-PktMon `
                -CommandArguments @('filter','list') `
                -WorkingDirectory $temporaryRoot
            $filtersSafeForRemoval = $beforeStopFilters.exitCode -eq 0 -and
                (Normalize-PktMonText -Value $beforeStopFilters.output) -ceq
                    $captureFilterSnapshot
            $stopped = Invoke-PktMon -CommandArguments @('stop') `
                -WorkingDirectory $temporaryRoot
            if ($stopped.exitCode -ne 0) {
                throw 'The owned Direct packet capture could not be stopped.'
            }
            $inactiveStatus = Invoke-PktMon -CommandArguments @('status') `
                -WorkingDirectory $temporaryRoot
            if (-not (Test-PktMonInactiveStatus -Status $inactiveStatus)) {
                throw 'Windows did not verify that the owned packet capture stopped.'
            }
            $script:captureActive = $false
            $script:captureStopped = $true
            $stopOutputFullPathMatched = $stopped.output.IndexOf($captureEtlPath,
                [StringComparison]::OrdinalIgnoreCase) -ge 0
            $stopMentionsAnyEtl = $stopped.output -match
                '(?i)\.etl(?:\s|$|["''])'
            $stopMentionsQualifiedEtl = $stopped.output -match
                '(?i)(?:[A-Z]:\\|[/\\])[^\r\n]*\.etl(?:\s|$|["''])'
            $stopOutputLeafMatched = -not $stopMentionsQualifiedEtl -and
                $stopped.output -match
                    '(?i)(?<![A-Za-z0-9_.-])PktMon\.etl(?![A-Za-z0-9_.-])'
            $stopOutputPathCompatible = -not $stopMentionsAnyEtl -or
                $stopOutputFullPathMatched -or $stopOutputLeafMatched
            $captureEtlSafe = $stopOutputPathCompatible -and
                (Test-Path -LiteralPath $captureEtlPath -PathType Leaf) -and
                (Test-PathContainedBy -Path $captureEtlPath `
                    -Parent $temporaryRoot) -and
                ((Get-Item -LiteralPath $captureEtlPath -Force).Attributes `
                    -band [IO.FileAttributes]::ReparsePoint) -eq 0
            if (-not $captureEtlSafe) {
                throw 'The stopped Direct capture output could not be proven private.'
            }
            $script:captureOutputContained = $captureEtlSafe -and
                (Test-ExternalCaptureFallbackAbsent)
            if (-not $script:captureOutputContained) {
                throw 'The stopped Direct capture output was not fully contained.'
            }
            $afterStopFilters = Invoke-PktMon `
                -CommandArguments @('filter','list') `
                -WorkingDirectory $temporaryRoot
            $filtersSafeForRemoval = $filtersSafeForRemoval -and
                $afterStopFilters.exitCode -eq 0 -and
                (Normalize-PktMonText -Value $afterStopFilters.output) -ceq
                    $captureFilterSnapshot
        } elseif (-not $captureEverStarted -and -not $captureStopped) {
            $inactiveStatus = Invoke-PktMon -CommandArguments @('status')
            if (-not (Test-PktMonInactiveStatus -Status $inactiveStatus)) {
                throw 'Windows packet-capture state could not be verified as inactive.'
            }
            $script:captureStopped = $true
        }
        if (-not $filtersSafeForRemoval) {
            throw 'Packet filters changed during capture; all filters were retained.'
        }
        if ($RequireEvidence) {
            if (-not $captureEtlPath -or
                    -not (Test-Path -LiteralPath $captureEtlPath -PathType Leaf)) {
                throw 'The private Direct capture log was unavailable.'
            }
            $converted = Invoke-PktMon -CommandArguments @(
                'etl2pcap','PktMon.etl','--out','direct-private.pcapng') `
                -WorkingDirectory $temporaryRoot
            if ($converted.exitCode -ne 0) {
                throw 'The private Direct capture could not be converted for review.'
            }
            $analysis = Assert-DirectCapturePrivacy
        }
    } catch {
        $completionError = $_
    } finally {
        if (-not $captureActive -and $captureStopped -and
                $captureFilterOwned -and $filtersSafeForRemoval) {
            $statusBeforeRemoval = Invoke-PktMon -CommandArguments @('status') `
                -WorkingDirectory $temporaryRoot
            if (Test-PktMonInactiveStatus -Status $statusBeforeRemoval) {
                $listed = Invoke-PktMon -CommandArguments @('filter','list') `
                    -WorkingDirectory $temporaryRoot
                $currentSnapshot = $listed.exitCode -eq 0 `
                    ? (Normalize-PktMonText -Value $listed.output) : $null
                if ($currentSnapshot -and
                        $currentSnapshot -ceq $captureFilterSnapshot) {
                    $removed = Invoke-PktMon `
                        -CommandArguments @('filter','remove') `
                        -WorkingDirectory $temporaryRoot
                    $empty = Invoke-PktMon `
                        -CommandArguments @('filter','list') `
                        -WorkingDirectory $temporaryRoot
                    if ($removed.exitCode -eq 0) {
                        $script:captureFilterOwned = $false
                    }
                    if ($removed.exitCode -eq 0 -and $empty.exitCode -eq 0 -and
                            $empty.output -match '(?im)^\s*none\.?\s*$' -and
                            (Get-PktMonFilterRowCount -Value $empty.output) -eq 0) {
                        $script:captureFilterRemoved = $true
                        $script:captureFilterMayRemain = $false
                    } elseif (-not $completionError) {
                        $completionError = [System.InvalidOperationException]::new(
                            'The owned Direct packet filter could not be removed safely.')
                    }
                } elseif (-not $completionError) {
                    $completionError = [System.InvalidOperationException]::new(
                        'Packet filters changed during capture; no global filters were removed.')
                }
            } elseif (-not $completionError) {
                $completionError = [System.InvalidOperationException]::new(
                    'Another packet capture became active; no global filters were removed.')
            }
        }
        if (-not $captureActive -and $captureStopped) {
            foreach ($path in @($captureEtlPath,$capturePcapPath)) {
                if ($path -and (Test-Path -LiteralPath $path)) {
                    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                }
            }
            $script:captureArtifactsRemoved =
                (-not $captureEtlPath -or -not (Test-Path -LiteralPath $captureEtlPath)) -and
                (-not $capturePcapPath -or -not (Test-Path -LiteralPath $capturePcapPath)) -and
                (Test-ExternalCaptureFallbackAbsent)
            Clear-CapturePatterns
        } else {
            $script:captureArtifactsRemoved = $false
        }
    }
    if ($completionError) { throw $completionError }
    return $analysis
}

function Test-PathContainedBy {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Parent
    )
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\')
    return $full.StartsWith($root + '\',
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePoint {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Boundary
    )
    $full = [System.IO.Path]::GetFullPath($Path)
    $limit = [System.IO.Path]::GetFullPath($Boundary).TrimEnd('\')
    $candidate = $full
    while ($candidate -and -not (Test-Path -LiteralPath $candidate)) {
        $candidate = Split-Path $candidate -Parent
    }
    while ($candidate -and ($candidate -ceq $limit -or
            $candidate.StartsWith($limit + '\',
                [System.StringComparison]::OrdinalIgnoreCase))) {
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band
                [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'A protected probe path contains a reparse point.'
        }
        if ($candidate -ceq $limit) { break }
        $candidate = Split-Path $candidate -Parent
    }
}

function Assert-SafeTemporaryRoot {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-PathContainedBy -Path $full -Parent $temporaryParent) -or
            (Split-Path $full -Leaf) -notmatch '^[0-9a-f]{32}$') {
        throw 'Refusing an unexpected probe temporary path.'
    }
    Assert-NoReparsePoint -Path $full -Boundary `
        ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\'))
    return $full
}

function Assert-SafePcSaveRoot {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-PathContainedBy -Path $full -Parent $loveSaveParent) -or
            (Split-Path $full -Leaf) -notmatch
                '^the-picture-shop-pc-probe-[0-9a-f]{32}$') {
        throw 'Refusing an unexpected isolated PC save path.'
    }
    Assert-NoReparsePoint -Path $full -Boundary $loveSaveParent
    return $full
}

function Remove-SafeTree {
    param(
        [AllowNull()][string]$Path,
        [Parameter(Mandatory=$true)][ValidateSet('temporary','pc-save')]
        [string]$Kind
    )
    if (-not $Path) { return }
    $full = if ($Kind -ceq 'temporary') {
        Assert-SafeTemporaryRoot -Path $Path
    } else {
        Assert-SafePcSaveRoot -Path $Path
    }
    if (-not (Test-Path -LiteralPath $full)) { return }
    $links = @(Get-ChildItem -LiteralPath $full -Recurse -Force |
        Where-Object {
            ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        })
    if ($links.Count -ne 0) {
        throw 'Refusing to remove a probe tree containing a reparse point.'
    }
    Remove-Item -LiteralPath $full -Recurse -Force
    if (Test-Path -LiteralPath $full) {
        throw 'A protected probe tree could not be removed.'
    }
}

function Invoke-AdbBestEffort {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string[]]$CommandArguments
    )
    try {
        $text = (& $adb -s $Serial @CommandArguments 2>&1 | Out-String).Trim()
        return [pscustomobject]@{ exitCode = $LASTEXITCODE; output = $text }
    } catch {
        # ADB can briefly reject a command while Android is switching app
        # process state.  Best-effort callers receive a bounded generic status;
        # no native exception text (which may contain a serial) is retained.
        return [pscustomobject]@{ exitCode = -1; output = '' }
    }
}

function Invoke-AdbText {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string[]]$CommandArguments
    )
    $result = Invoke-AdbBestEffort -Serial $Serial `
        -CommandArguments $CommandArguments
    if ($result.exitCode -ne 0) { throw 'An Android probe command failed.' }
    return $result.output
}

function Get-ConnectedSerials {
    $serials = @(& $adb devices | Select-Object -Skip 1 |
        Where-Object { $_ -match "\tdevice$" } |
        ForEach-Object { ($_ -split '\s+')[0] })
    foreach ($serial in $serials) {
        if ($serial -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
            throw 'An attached Android device has an unsafe identifier.'
        }
    }
    return @($serials)
}

function Test-CellularInterface {
    param([AllowNull()][string]$Name)
    return $null -ne $Name -and
        $Name -match '^(?:rmnet|ccmni|pdp|wwan)[A-Za-z0-9_.-]*$'
}

function Get-DefaultIpv6Interface {
    param([Parameter(Mandatory=$true)][string]$Serial)
    $route = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-6','route','get','2001:db8::1')
    if ($route.exitCode -ne 0) { return $null }
    $match = [regex]::Match(
        $route.output,'(?:^|\s)dev\s+([A-Za-z0-9_.-]+)(?:\s|$)')
    return $match.Success ? $match.Groups[1].Value : $null
}

function Get-WifiIpv4 {
    param([Parameter(Mandatory=$true)][string]$Serial)
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-o','-4','addr','show','dev','wlan0')
    if ($query.exitCode -ne 0) { return $null }
    $match = [regex]::Match($query.output,'\binet\s+([0-9]+(?:\.[0-9]+){3})/')
    return $match.Success ? $match.Groups[1].Value : $null
}

function Test-GlobalIpv6 {
    param([Parameter(Mandatory=$true)][string]$Address)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address,[ref]$parsed) -or
            $parsed.AddressFamily -ne
                [System.Net.Sockets.AddressFamily]::InterNetworkV6 -or
            [System.Net.IPAddress]::IsLoopback($parsed) -or
            $parsed.IsIPv6LinkLocal -or $parsed.IsIPv6SiteLocal -or
            $parsed.IsIPv6Multicast) {
        return $false
    }
    $bytes = $parsed.GetAddressBytes()
    if ($bytes.Length -ne 16 -or (($bytes[0] -band 0xe0) -ne 0x20)) {
        return $false
    }
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and
            ($bytes[2] -eq 0x00 -or $bytes[2] -eq 0x01)) { return $false }
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and
            $bytes[2] -eq 0x0d -and $bytes[3] -eq 0xb8) { return $false }
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x02) { return $false }
    if ($bytes[0] -eq 0x3f -and $bytes[1] -eq 0xfe) { return $false }
    if ($bytes[0] -eq 0x3f -and $bytes[1] -eq 0xff -and
            ($bytes[2] -band 0xf0) -eq 0x00) { return $false }
    return $true
}

function Get-StableGlobalIpv6 {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Interface
    )
    if ($Interface -notmatch '^[A-Za-z0-9_.-]+$') { return $null }
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-6','-o','addr','show','dev',$Interface,'scope','global')
    if ($query.exitCode -ne 0) { return $null }
    foreach ($line in @($query.output -split "`r?`n")) {
        $match = [regex]::Match(
            $line,'\binet6\s+([0-9A-Fa-f:]+)/([0-9]{1,3})\b')
        if ($match.Success -and $line -notmatch
                '(?:^|\s)(?:temporary|tentative|optimistic|dadfailed|deprecated)(?:\s|$)' -and
                (Test-GlobalIpv6 -Address $match.Groups[1].Value)) {
            return $match.Groups[1].Value.ToLowerInvariant()
        }
    }
    return $null
}

function Test-CurrentAndroidIpv6 {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Interface,
        [Parameter(Mandatory=$true)][string]$Address
    )
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-6','-o','addr','show','dev',$Interface,'scope','global')
    if ($query.exitCode -ne 0) { return $false }
    $expected = [System.Net.IPAddress]::Parse($Address)
    foreach ($line in @($query.output -split "`r?`n")) {
        $match = [regex]::Match(
            $line,'\binet6\s+([0-9A-Fa-f:]+)/[0-9]{1,3}\b')
        $candidate = $null
        if ($match.Success -and $line -notmatch
                '(?:^|\s)(?:tentative|optimistic|dadfailed|deprecated)(?:\s|$)' -and
                [System.Net.IPAddress]::TryParse(
                    $match.Groups[1].Value,[ref]$candidate) -and
                $expected.Equals($candidate)) {
            return $true
        }
    }
    return $false
}

function Resolve-AndroidIpv6Source {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$ExpectedInterface
    )
    if (-not (Test-GlobalIpv6 -Address $Destination) -or
            $ExpectedInterface -notmatch '^[A-Za-z0-9_.-]+$') { return $null }
    $route = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ip','-6','route','get',$Destination)
    if ($route.exitCode -ne 0) { return $null }
    $interfaceMatch = [regex]::Match(
        $route.output,'(?:^|\s)dev\s+([A-Za-z0-9_.-]+)(?:\s|$)')
    $sourceMatch = [regex]::Match(
        $route.output,'(?:^|\s)src\s+([0-9A-Fa-f:]+)(?:\s|$)')
    if (-not $interfaceMatch.Success -or -not $sourceMatch.Success -or
            $interfaceMatch.Groups[1].Value -cne $ExpectedInterface) {
        return $null
    }
    $source = $sourceMatch.Groups[1].Value.ToLowerInvariant()
    if (-not (Test-CurrentAndroidIpv6 -Serial $Serial `
            -Interface $ExpectedInterface -Address $source)) { return $null }
    return $source
}

function Resolve-PcIpv6Source {
    param(
        [Parameter(Mandatory=$true)][string]$Destination,
        [ValidateRange(1,65535)][int]$Port = $directPort
    )
    if (-not (Test-GlobalIpv6 -Address $Destination)) { return $null }
    $socket = [System.Net.Sockets.Socket]::new(
        [System.Net.Sockets.AddressFamily]::InterNetworkV6,
        [System.Net.Sockets.SocketType]::Dgram,
        [System.Net.Sockets.ProtocolType]::Udp)
    try {
        $socket.Connect([System.Net.IPEndPoint]::new(
            [System.Net.IPAddress]::Parse($Destination),$Port))
        $local = [System.Net.IPEndPoint]$socket.LocalEndPoint
        $address = $local.Address.ToString().Split('%')[0].ToLowerInvariant()
        return (Test-GlobalIpv6 -Address $address) ? $address : $null
    } catch {
        return $null
    } finally {
        $socket.Dispose()
    }
}

function Get-PcWifiInterfaceIndex {
    param([Parameter(Mandatory=$true)][string]$Address)
    $expected = [System.Net.IPAddress]::Parse($Address)
    $addressMatches = @(Get-NetIPAddress -AddressFamily IPv6 -ErrorAction Stop |
        Where-Object {
            $candidate = $null
            [System.Net.IPAddress]::TryParse(
                ([string]$_.IPAddress).Split('%')[0],[ref]$candidate) -and
                $expected.Equals($candidate) -and $_.AddressState -eq 'Preferred'
        })
    if ($addressMatches.Count -ne 1) { return $null }
    $adapter = Get-NetAdapter -InterfaceIndex $addressMatches[0].InterfaceIndex `
        -IncludeHidden -ErrorAction Stop
    $wireless = ([int]$adapter.NdisPhysicalMedium -eq 9) -or
        ([string]$adapter.PhysicalMediaType -match '802\.11|Wireless')
    if ($adapter.Status -ne 'Up' -or -not $wireless) { return $null }
    return [int]$addressMatches[0].InterfaceIndex
}

function Test-DifferentIpv6Prefixes {
    param(
        [Parameter(Mandatory=$true)][string]$First,
        [Parameter(Mandatory=$true)][string]$Second
    )
    $a = [System.Net.IPAddress]::Parse($First).GetAddressBytes()
    $b = [System.Net.IPAddress]::Parse($Second).GetAddressBytes()
    for ($index = 0; $index -lt 8; $index++) {
        if ($a[$index] -ne $b[$index]) { return $true }
    }
    return $false
}

function Test-SameIpv6Address {
    param(
        [Parameter(Mandatory=$true)][string]$First,
        [Parameter(Mandatory=$true)][string]$Second
    )
    $a = $null
    $b = $null
    return [System.Net.IPAddress]::TryParse($First,[ref]$a) -and
        [System.Net.IPAddress]::TryParse($Second,[ref]$b) -and
        $a.AddressFamily -eq
            [System.Net.Sockets.AddressFamily]::InterNetworkV6 -and
        $b.AddressFamily -eq
            [System.Net.Sockets.AddressFamily]::InterNetworkV6 -and
        $a.Equals($b)
}

function Test-PcPortAvailable {
    param([ValidateRange(1,65535)][int]$Port = $directPort)
    $socket = [System.Net.Sockets.Socket]::new(
        [System.Net.Sockets.AddressFamily]::InterNetworkV6,
        [System.Net.Sockets.SocketType]::Dgram,
        [System.Net.Sockets.ProtocolType]::Udp)
    try {
        $socket.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IPv6,
            [System.Net.Sockets.SocketOptionName]::IPv6Only,$true)
        $socket.Bind([System.Net.IPEndPoint]::new(
            [System.Net.IPAddress]::IPv6Any,$Port))
        return $true
    } catch {
        return $false
    } finally {
        $socket.Dispose()
    }
}

function Test-AndroidPortAvailable {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [ValidateRange(1,65535)][int]$Port = $directPort
    )
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','ss','-lun')
    if ($query.exitCode -ne 0 -or
            $query.output -match 'not found|Permission denied|Cannot open') {
        $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
            'shell','netstat','-anu')
    }
    if ($query.exitCode -ne 0) {
        throw 'Android could not prove that the probe port is free.'
    }
    return $query.output -notmatch "(?m):$Port(?:\s|$)"
}

function Test-WindowsFirewallReady {
    param(
        [Parameter(Mandatory=$true)][string]$Program,
        [Parameter(Mandatory=$true)][int]$InterfaceIndex,
        [Parameter(Mandatory=$true)][int[]]$Ports,
        [switch]$RequireExactPortSet
    )
    if ($RequireExactPortSet) {
      try {
        $networkProfile = Get-NetConnectionProfile -InterfaceIndex $InterfaceIndex `
            -ErrorAction Stop
        $category = [string]$networkProfile.NetworkCategory
        $filters = @(Get-NetFirewallApplicationFilter -Program $Program `
            -PolicyStore ActiveStore -ErrorAction Stop)
        $adapter = Get-NetAdapter -InterfaceIndex $InterfaceIndex `
            -IncludeHidden -ErrorAction Stop
        $interfaceAlias = [string]$adapter.Name
        $activeProfile = Get-NetFirewallProfile -Name $category `
            -PolicyStore ActiveStore -ErrorAction Stop
        if ([string]$activeProfile.Enabled -ne 'True') { return $false }
        $required = @($Ports | Sort-Object -Unique | ForEach-Object { [string]$_ })
        $foundExactRule = $false
        foreach ($filter in $filters) {
            $rules = @($filter | Get-NetFirewallRule -ErrorAction Stop)
            if ($rules.Count -ne 1) { return $false }
            foreach ($rule in $rules) {
                if ($rule.Enabled -ne 'True' -or $rule.Direction -ne 'Inbound' -or
                        $rule.Action -ne 'Allow') {
                    continue
                }
                $profiles = @(([string]$rule.Profile).Split(',') |
                    ForEach-Object { $_.Trim() })
                if ('Any' -notin $profiles -and $category -notin $profiles) {
                    continue
                }
                $portFilters = @($rule | Get-NetFirewallPortFilter `
                    -ErrorAction Stop)
                if ($portFilters.Count -ne 1) { return $false }
                $protocol = [string]$portFilters[0].Protocol
                if ($protocol -notin @('Any','UDP','17')) { continue }
                $localPorts = @($portFilters[0].LocalPort | ForEach-Object {
                    ([string]$_).Split(',')
                } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
                $admitsRequiredPort = $false
                foreach ($localPort in $localPorts) {
                    if ($localPort -ceq 'Any') {
                        $admitsRequiredPort = $true
                        break
                    }
                    if ($localPort -match '^\d+$') {
                        if ($localPort -in $required) {
                            $admitsRequiredPort = $true
                            break
                        }
                        continue
                    }
                    if ($localPort -match '^(\d+)-(\d+)$') {
                        $lower = [int]$Matches[1]
                        $upper = [int]$Matches[2]
                        if ($lower -gt $upper) { return $false }
                        if (@($Ports | Where-Object {
                                $_ -ge $lower -and $_ -le $upper
                            }).Count -gt 0) {
                            $admitsRequiredPort = $true
                            break
                        }
                        continue
                    }
                    return $false
                }
                if (-not $admitsRequiredPort) { continue }

                $interfaceFilters = @($rule | Get-NetFirewallInterfaceFilter `
                    -ErrorAction Stop)
                $interfaceTypeFilters = @($rule |
                    Get-NetFirewallInterfaceTypeFilter -ErrorAction Stop)
                if ($interfaceFilters.Count -ne 1 -or
                        $interfaceTypeFilters.Count -ne 1) {
                    return $false
                }
                $aliases = @($interfaceFilters[0].InterfaceAlias |
                    ForEach-Object { [string]$_ })
                $types = @($interfaceTypeFilters[0].InterfaceType |
                    ForEach-Object { [string]$_ })
                $aliasApplies = 'Any' -in $aliases -or $interfaceAlias -in $aliases
                if (-not $aliasApplies) {
                    foreach ($alias in $aliases) {
                        if ($alias -and
                                [System.Management.Automation.WildcardPattern]::new(
                                    $alias,
                                    [System.Management.Automation.WildcardOptions]::IgnoreCase
                                ).IsMatch($interfaceAlias)) {
                            $aliasApplies = $true
                            break
                        }
                    }
                }
                $typeApplies = 'Any' -in $types -or 'Wireless' -in $types
                if (-not $aliasApplies -or -not $typeApplies) { continue }

                $addressFilters = @($rule | Get-NetFirewallAddressFilter `
                    -ErrorAction Stop)
                if ($addressFilters.Count -ne 1) {
                    return $false
                }

                $localAddresses = @($addressFilters[0].LocalAddress |
                    ForEach-Object { [string]$_ })
                $remoteAddresses = @($addressFilters[0].RemoteAddress |
                    ForEach-Object { ([string]$_).Split(',') } |
                    ForEach-Object { $_.Trim() })
                $admitsInternetIpv6 = $false
                foreach ($remoteAddress in $remoteAddresses) {
                    if ($remoteAddress -in @('Any','Internet','Internet6')) {
                        $admitsInternetIpv6 = $true
                        break
                    }
                    if ($remoteAddress -in @(
                            'Internet4','LocalSubnet','LocalSubnet4','LocalSubnet6')) {
                        continue
                    }
                    if ($remoteAddress -match ':') {
                        if ($remoteAddress -match '(?i)^(?:fe[89ab]|f[cd])') {
                            continue
                        }
                        $admitsInternetIpv6 = $true
                        break
                    }
                    if ($remoteAddress -notmatch '^\d+(?:\.\d+){3}(?:/\d+)?$' -and
                            $remoteAddress -notmatch
                                '^\d+(?:\.\d+){3}-\d+(?:\.\d+){3}$') {
                        return $false
                    }
                }
                if (-not $admitsInternetIpv6) { continue }

                $exact = $protocol -in @('UDP','17') -and
                    $profiles.Count -eq 1 -and $profiles[0] -ceq $category -and
                    $aliases.Count -eq 1 -and
                    $aliases[0] -ceq $interfaceAlias -and
                    $types.Count -eq 1 -and $types[0] -ceq 'Wireless' -and
                    [string]$rule.EdgeTraversalPolicy -ceq 'Block' -and
                    $localAddresses.Count -eq 1 -and
                    $localAddresses[0] -ceq 'Any' -and
                    $remoteAddresses.Count -eq 1 -and
                    $remoteAddresses[0] -ceq 'Internet6' -and
                    $localPorts.Count -eq $required.Count -and
                    @($required | Where-Object {
                        $_ -notin $localPorts
                    }).Count -eq 0
                if (-not $exact) { return $false }
                $foundExactRule = $true
            }
        }
        return $foundExactRule
      } catch {
        return $false
      }
    }
    $networkProfile = Get-NetConnectionProfile -InterfaceIndex $InterfaceIndex `
        -ErrorAction Stop
    $category = [string]$networkProfile.NetworkCategory
    $filters = @(Get-NetFirewallApplicationFilter -Program $Program `
        -ErrorAction SilentlyContinue)
    foreach ($requiredPort in $Ports) {
        $covered = $false
        foreach ($filter in $filters) {
            $rule = $filter | Get-NetFirewallRule -ErrorAction SilentlyContinue
            if (-not $rule -or $rule.Enabled -ne 'True' -or
                    $rule.Direction -ne 'Inbound' -or $rule.Action -ne 'Allow') {
                continue
            }
            $profiles = [string]$rule.Profile
            if ($profiles -ne 'Any' -and $profiles -notmatch
                    "(?:^|,\s*)$([regex]::Escape($category))(?:,|$)") {
                continue
            }
            $port = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            if (-not $port -or
                    ([string]$port.Protocol -notin @('Any','UDP','17'))) {
                continue
            }
            $localPorts = @(([string]$port.LocalPort).Split(',') |
                ForEach-Object { $_.Trim() })
            if ('Any' -in $localPorts -or [string]$requiredPort -in $localPorts) {
                $covered = $true
                break
            }
        }
        if (-not $covered) { return $false }
    }
    return $true
}

function Test-NoConcurrentEngineeringApp {
    param([Parameter(Mandatory=$true)][string[]]$Serials)
    foreach ($serial in $Serials) {
        foreach ($package in @(
                'com.thepictureshop.direct_probe.host',
                'com.thepictureshop.direct_probe.client')) {
            $query = Invoke-AdbBestEffort -Serial $serial -CommandArguments @(
                'shell','pidof',$package)
            if ($query.exitCode -eq 0 -and $query.output -match '^\d+$') {
                return $false
            }
        }
    }
    return $true
}

function Copy-VerifiedBasePackage {
    param([Parameter(Mandatory=$true)][string]$Destination)
    $rawBefore = [System.IO.File]::ReadAllText($baseReportPath)
    $report = $rawBefore | ConvertFrom-Json
    $source = [System.IO.Path]::GetFullPath([string]$report.package)
    if (-not (Test-PathContainedBy -Path $source -Parent $mobileOutputRoot) -or
            -not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw 'The mobile build report references an unsafe package.'
    }
    $item = Get-Item -LiteralPath $source
    if ([long]$report.packageBytes -ne $item.Length -or
            ([string]$report.sha256).ToLowerInvariant() -cne
                (Get-LowerSha256 -Path $source)) {
        throw 'The mobile package does not match its build report.'
    }
    $inputStream = [System.IO.File]::Open($source,[System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
    try {
        $output = [System.IO.File]::Open($Destination,
            [System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None)
        try { $inputStream.CopyTo($output) } finally { $output.Dispose() }
    } finally {
        $inputStream.Dispose()
    }
    $rawAfter = [System.IO.File]::ReadAllText($baseReportPath)
    if ($rawAfter -cne $rawBefore -or
            (Get-LowerSha256 -Path $Destination) -cne
                ([string]$report.sha256).ToLowerInvariant() -or
            (Get-Item -LiteralPath $Destination).Length -ne
                [long]$report.packageBytes) {
        throw 'The mobile package changed while the probe snapshot was created.'
    }
    return [pscustomobject]@{
        sha256 = ([string]$report.sha256).ToLowerInvariant()
        bytes = [long]$report.packageBytes
    }
}

function New-ProbeLove {
    param(
        [Parameter(Mandatory=$true)][string]$BaseSnapshot,
        [Parameter(Mandatory=$true)][ValidateSet('host','guest')][string]$Role,
        [Parameter(Mandatory=$true)][string]$OutputPath,
        [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9]{16,24}$')]
        [string]$PlayerName,
        [AllowNull()][string]$Identity,
        [ValidatePattern('^[a-z0-9-]+$')][string]$InstanceTag = $Role,
        [ValidateRange(0,2)][int]$GuestOrdinal = 0,
        [int[]]$DirectPorts = @($directPort),
        [string[]]$ExpectedGuestNames = @()
    )
    $script:stage = "create_${Role}_probe_extract"
    $stageRoot = Join-Path $temporaryRoot "package-$InstanceTag"
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($BaseSnapshot,$stageRoot)
    $script:stage = "create_${Role}_probe_overlay"
    Copy-Item -LiteralPath $probeMain -Destination `
        (Join-Path $stageRoot 'main.lua') -Force
    $script:stage = "create_${Role}_probe_config"
    if ($DirectPorts.Count -lt 1 -or $DirectPorts.Count -gt 2 -or
            @($DirectPorts | Where-Object { $_ -notin @(57842,57844) }).Count -gt 0) {
        throw 'The engineering Direct port configuration was invalid.'
    }
    foreach ($name in $ExpectedGuestNames) {
        if ($name -notmatch '^[A-Za-z0-9]{16,24}$') {
            throw 'An expected Android player canary was invalid.'
        }
    }
    $portLiteral = (@($DirectPorts | ForEach-Object { [string]$_ }) -join ', ')
    $guestNameLiteral = (@($ExpectedGuestNames | ForEach-Object {
        "`"$_`""
    }) -join ', ')
    $multiLiteral = $AndroidGuestCount -eq 2 ? 'true' : 'false'
    $config = "return {`n    role = `"$Role`",`n" +
        "    playerName = `"$PlayerName`",`n" +
        "    multiGuest = $multiLiteral,`n" +
        "    guestOrdinal = $GuestOrdinal,`n" +
        "    directPorts = { $portLiteral },`n" +
        "    expectedGuestNames = { $guestNameLiteral },`n}`n"
    $script:stage = "create_${Role}_probe_config_write"
    [System.IO.File]::WriteAllText(
        (Join-Path $stageRoot 'direct_gameplay_probe_config.lua'),$config,
        [System.Text.UTF8Encoding]::new($false))
    if ($Identity) {
        $script:stage = "create_${Role}_probe_identity"
        if ($Identity -notmatch
                '^the-picture-shop-pc-probe-[0-9a-f]{32}$') {
            throw 'Invalid isolated PC save identity.'
        }
        $confPath = Join-Path $stageRoot 'conf.lua'
        $conf = [System.IO.File]::ReadAllText($confPath)
        $replacement = 't.identity = "' + $Identity + '"'
        $updated = [regex]::Replace($conf,
            't\.identity\s*=\s*"the-picture-shop"',$replacement)
        if ($updated -ceq $conf -or
                ([regex]::Matches($updated,[regex]::Escape($Identity))).Count -ne 1) {
            throw 'The PC probe could not isolate its save identity.'
        }
        [System.IO.File]::WriteAllText($confPath,$updated,
            [System.Text.UTF8Encoding]::new($false))
    }
    $script:stage = "create_${Role}_probe_archive"
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stageRoot,$OutputPath,
        [System.IO.Compression.CompressionLevel]::Optimal,$false)
    return [pscustomobject]@{
        path = $OutputPath
        sha256 = Get-LowerSha256 -Path $OutputPath
        bytes = (Get-Item -LiteralPath $OutputPath).Length
    }
}

function Build-AndroidGuestApk {
    param(
        [Parameter(Mandatory=$true)]$GuestLove,
        [ValidatePattern('^[a-z0-9-]+$')][string]$InstanceTag = 'guest'
    )
    $sensitiveRoot = Join-Path $temporaryRoot "mobile-$InstanceTag"
    $buildOutput = (& $builder -PackagePath $GuestLove.path `
        -EngineeringDirectTransportProbe -DirectTransportProbeRole client `
        -SensitiveBuildRoot $sensitiveRoot 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw 'The isolated Android guest package build failed.'
    }
    $reportPath = Join-Path $sensitiveRoot `
        'artifacts\direct-transport-probe-client-apk-report.json'
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        throw 'The isolated Android build report is missing.'
    }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $apk = [System.IO.Path]::GetFullPath([string]$report.apk)
    if (-not (Test-PathContainedBy -Path $apk -Parent $sensitiveRoot) -or
            -not (Test-Path -LiteralPath $apk -PathType Leaf) -or
            $report.applicationId -cne $guestPackage -or
            $report.engineeringProbe -ne $true -or
            $report.engineeringProbeRole -cne 'client' -or
            $report.signed -ne $true -or $report.internetPermission -ne $true -or
            $report.sixteenKbCompatible -ne $true -or
            $report.nativeCrypto.productionReady -ne $false -or
            ([string]$report.embeddedLove.sha256).ToLowerInvariant() -cne
                $GuestLove.sha256 -or
            [long]$report.embeddedLove.bytes -ne [long]$GuestLove.bytes -or
            ([string]$report.sha256).ToLowerInvariant() -cne
                (Get-LowerSha256 -Path $apk)) {
        throw 'The isolated Android guest artifact failed verification.'
    }
    return [pscustomobject]@{ path = $apk; report = $report }
}

function Test-PackageAbsent {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Package
    )
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','pm','list','packages','--user','0',$Package)
    return $query.exitCode -eq 0 -and [string]::IsNullOrWhiteSpace($query.output)
}

function Install-AndroidGuest {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Apk
    )
    Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','am','force-stop',$guestPackage) | Out-Null
    Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'uninstall',$guestPackage) | Out-Null
    $result = Invoke-AdbText -Serial $Serial -CommandArguments @(
        'install','-r',$Apk)
    if ($result -notmatch '(?m)^Success\s*$') {
        throw 'The isolated Android guest did not install.'
    }
    $runAs = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','run-as',$guestPackage,'id')
    if ($runAs.exitCode -ne 0) {
        throw 'The isolated Android guest does not allow private probe control.'
    }
}

function Clear-AndroidGuest {
    param([Parameter(Mandatory=$true)][string]$Serial)
    Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','am','force-stop',$guestPackage) | Out-Null
    $result = Invoke-AdbText -Serial $Serial -CommandArguments @(
        'shell','pm','clear',$guestPackage)
    if ($result -notmatch 'Success') {
        throw 'The isolated Android guest data could not be cleared.'
    }
}

function Start-AndroidGuest {
    param([Parameter(Mandatory=$true)][string]$Serial)
    Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','am','force-stop',$guestPackage) | Out-Null
    $result = Invoke-AdbText -Serial $Serial -CommandArguments @(
        'shell','am','start','-W','-n',
        "$guestPackage/org.love2d.android.GameActivity")
    if ($result -match 'Error:|Exception') {
        throw 'The isolated Android guest did not launch.'
    }
}

function Get-AndroidGuestProcessId {
    param([Parameter(Mandatory=$true)][string]$Serial)
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','pidof',$guestPackage)
    if ($query.exitCode -ne 0 -or $query.output -notmatch '^\d+$') {
        return $null
    }
    return [string]$query.output
}

function Wait-StableAndroidGuestProcessId {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [int]$TimeoutSeconds = 10
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $previous = $null
    $consecutive = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        $current = Get-AndroidGuestProcessId -Serial $Serial
        if ($current) {
            if ($current -ceq $previous) {
                $consecutive++
            } else {
                $previous = $current
                $consecutive = 1
            }
            if ($consecutive -ge 2) { return $current }
        } else {
            $previous = $null
            $consecutive = 0
        }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

function Wait-AndroidGuestLogBaseline {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$ExpectedProcessId,
        [int]$TimeoutSeconds = 10
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $currentPid = Get-AndroidGuestProcessId -Serial $Serial
        if ($currentPid -and $currentPid -ceq $ExpectedProcessId) {
            $log = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
                'logcat',"--pid=$ExpectedProcessId",'-d','-v','brief')
            if ($log.exitCode -eq 0) {
                # An empty current-process log is a valid baseline.  The
                # structured result keeps it distinct from a failed ADB call.
                return [pscustomobject]@{
                    captured = $true
                    text = $null -eq $log.output ? '' : [string]$log.output
                }
            }
        }
        Start-Sleep -Milliseconds 250
    }
    return [pscustomobject]@{ captured = $false; text = '' }
}

function Test-AndroidGuestRunning {
    param([Parameter(Mandatory=$true)][string]$Serial)
    return $null -ne (Get-AndroidGuestProcessId -Serial $Serial)
}

function Get-AndroidGuestLog {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][ValidatePattern('^\d+$')]
        [string]$ExpectedProcessId
    )
    $log = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'logcat',"--pid=$ExpectedProcessId",'-d','-v','brief')
    if ($log.exitCode -ne 0 -or $null -eq $log.output) {
        return [pscustomobject]@{ captured = $false; text = '' }
    }
    return [pscustomobject]@{
        captured = $true
        text = [string]$log.output
    }
}

function Android-PrivatePath {
    param([Parameter(Mandatory=$true)][string]$Name)
    if ($Name -notmatch '^[a-z0-9-]+$') { throw 'Unsafe private marker name.' }
    return "$androidSaveRoot/$Name.txt"
}

function Read-AndroidPrivateFile {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $path = Android-PrivatePath -Name $Name
    $exists = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','run-as',$guestPackage,'ls',$path)
    if ($exists.exitCode -ne 0) { return $null }
    $query = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'exec-out','run-as',$guestPackage,'cat',$path)
    return $query.exitCode -eq 0 ? $query.output : $null
}

function Remove-AndroidPrivateFile {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Name
    )
    Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','run-as',$guestPackage,'rm','-f',
        (Android-PrivatePath -Name $Name)) | Out-Null
}

function Write-AndroidPrivateValue {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Value,
        [switch]$Address
    )
    if ($Address) {
        if (-not (Test-GlobalIpv6 -Address $Value) -or $Value.Length -gt 39) {
            throw 'A private Android address failed validation.'
        }
    } elseif ($Value.Length -lt 1 -or $Value.Length -gt 160 -or
            $Value -match '[^A-Za-z0-9_.-]') {
        throw 'A private Android control value failed validation.'
    }
    $path = Android-PrivatePath -Name $Name
    $temporaryPath = "$androidSaveRoot/$Name.tmp"
    $mkdir = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','run-as',$guestPackage,'mkdir','-p',$androidSaveRoot)
    if ($mkdir.exitCode -ne 0) { throw 'Android private storage is unavailable.' }
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $adb
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in @('-s',$Serial,'shell','run-as',$guestPackage,
            'dd',"of=$temporaryPath")) {
        $psi.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::Start($psi)
    try {
        $process.StandardInput.Write($Value)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $process.StandardOutput.ReadToEnd() | Out-Null
        $process.StandardError.ReadToEnd() | Out-Null
        if ($process.ExitCode -ne 0) {
            throw 'A private Android control transfer failed.'
        }
    } finally {
        $process.Dispose()
    }
    $move = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
        'shell','run-as',$guestPackage,'mv','-f',$temporaryPath,$path)
    if ($move.exitCode -ne 0) { throw 'Android private control publish failed.' }
}

function Pc-PrivatePath {
    param([Parameter(Mandatory=$true)][string]$Name)
    if ($Name -notmatch '^[a-z0-9-]+$') { throw 'Unsafe private marker name.' }
    return Join-Path $pcSaveRoot "probe\$Name.txt"
}

function Read-PcPrivateFile {
    param([Parameter(Mandatory=$true)][string]$Name)
    $path = Pc-PrivatePath -Name $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return [System.IO.File]::ReadAllText($path)
    } catch [System.IO.IOException] {
        # LÖVE may still hold the newly published marker for a fraction of a
        # frame.  Treat that as not-yet-visible and retry inside the waiter.
        return $null
    }
}

function Remove-PcPrivateFile {
    param([Parameter(Mandatory=$true)][string]$Name)
    $path = Pc-PrivatePath -Name $Name
    try {
        Remove-Item -LiteralPath $path -Force -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        # Inbox controls are one-shot; the PC host may consume the file in the
        # same frame that cleanup attempts to remove it.
    }
}

function Write-PcPrivateValue {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Value,
        [switch]$Address
    )
    if ($Address) {
        if (-not (Test-GlobalIpv6 -Address $Value) -or $Value.Length -gt 39) {
            throw 'A private PC address failed validation.'
        }
    } elseif ($Value.Length -lt 1 -or $Value.Length -gt 160 -or
            $Value -match '[^A-Za-z0-9_.-]') {
        throw 'A private PC control value failed validation.'
    }
    Assert-SafePcSaveRoot -Path $pcSaveRoot | Out-Null
    $directory = Join-Path $pcSaveRoot 'probe'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $path = Pc-PrivatePath -Name $Name
    $temporaryPath = "$path.tmp"
    [System.IO.File]::WriteAllText($temporaryPath,$Value,
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temporaryPath,$path,$true)
}

function Start-PcHost {
    param([Parameter(Mandatory=$true)][string]$PackagePath)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $loveConsole
    $psi.WorkingDirectory = $projectRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.ArgumentList.Add($PackagePath)
    foreach ($name in @('PICTURE_SHOP_SMOKE','PICTURE_SHOP_MOBILE',
            'PICTURE_SHOP_LAN_LOOPBACK','PICTURE_SHOP_SMOKE_REPORT')) {
        $psi.Environment.Remove($name) | Out-Null
    }
    $psi.Environment['TPS_CRYPTO_LIBRARY'] = $windowsCrypto
    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process) { throw 'The isolated PC host did not launch.' }
    return [pscustomobject]@{
        process = $process
        stdout = $process.StandardOutput.ReadToEndAsync()
        stderr = $process.StandardError.ReadToEndAsync()
    }
}

function Stop-PcHost {
    param([AllowNull()]$Context)
    if (-not $Context) {
        return [pscustomobject]@{ exited = $true; log = '' }
    }
    $process = $Context.process
    try {
        if (-not $process.HasExited) {
            $process.CloseMainWindow() | Out-Null
            if (-not $process.WaitForExit(5000)) {
                if (-not $process.HasExited) {
                    try { $process.Kill() } catch [System.InvalidOperationException] {}
                }
                if (-not $process.WaitForExit(5000)) {
                    throw 'The isolated PC host did not stop within the cleanup bound.'
                }
            }
        }
        if (-not $process.HasExited) {
            throw 'The isolated PC host did not exit cleanly.'
        }
        $stdout = $Context.stdout.GetAwaiter().GetResult()
        $stderr = $Context.stderr.GetAwaiter().GetResult()
        return [pscustomobject]@{
            exited = $process.HasExited
            log = ([string]$stdout + "`n" + [string]$stderr)
        }
    } finally {
        $process.Dispose()
    }
}

function Wait-PcValue {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int]$TimeoutSeconds,
        [switch]$Code
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $value = Read-PcPrivateFile -Name $Name
        if ($null -ne $value) {
            $value = $value.Trim()
            if ($Code -and ($value -notmatch
                    '^TPS2[HR][A-Za-z0-9_.-]{8,157}$')) {
                throw 'The PC host produced an invalid private code.'
            }
            return $value
        }
        if ($null -ne (Read-PcPrivateFile -Name 'failure')) {
            $script:stage = "$($script:stage)_internal_failure"
            throw 'The PC host reached its internal timeout.'
        }
        if (-not $pcProcessContext -or $pcProcessContext.process.HasExited) {
            $script:stage = "$($script:stage)_process_stopped"
            throw 'The isolated PC host stopped unexpectedly.'
        }
        Start-Sleep -Milliseconds 200
    }
    $script:stage = "$($script:stage)_timeout"
    throw 'Timed out waiting for a PC host milestone.'
}

function Assert-PcMarkerAbsent {
    param([Parameter(Mandatory=$true)][string]$Name)
    if ($null -ne (Read-PcPrivateFile -Name $Name)) {
        throw 'A PC host milestone appeared before its triggering action.'
    }
    if (-not $pcProcessContext -or $pcProcessContext.process.HasExited) {
        throw 'The isolated PC host stopped before the triggering action.'
    }
    return $true
}

function Wait-AndroidValue {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int]$TimeoutSeconds,
        [switch]$Code
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $sawUnavailablePid = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($script:androidMarkerProcessId) {
            $pinnedCurrentPid = Get-AndroidGuestProcessId -Serial $Serial
            if (-not $pinnedCurrentPid) {
                $sawUnavailablePid = $true
                Start-Sleep -Milliseconds 200
                continue
            }
            if ($pinnedCurrentPid -cne $script:androidMarkerProcessId) {
                $script:stage = "$($script:stage)_process_replaced"
                throw 'The isolated Android guest process changed unexpectedly.'
            }
        }
        $value = Read-AndroidPrivateFile -Serial $Serial -Name $Name
        if ($null -ne $value) {
            $value = $value.Trim()
            if ($Code -and $value -notmatch
                    '^TPS2[HR][A-Za-z0-9_.-]{8,157}$') {
                throw 'The Android guest produced an invalid private code.'
            }
            return $value
        }
        if ($null -ne (Read-AndroidPrivateFile -Serial $Serial -Name 'failure')) {
            $script:stage = "$($script:stage)_internal_failure"
            throw 'The Android guest reached its internal timeout.'
        }
        $currentPid = Get-AndroidGuestProcessId -Serial $Serial
        if (-not $currentPid) {
            $sawUnavailablePid = $true
            Start-Sleep -Milliseconds 200
            continue
        }
        if ($script:androidMarkerProcessId -and
                $currentPid -cne $script:androidMarkerProcessId) {
            $script:stage = "$($script:stage)_process_replaced"
            throw 'The isolated Android guest process changed unexpectedly.'
        }
        Start-Sleep -Milliseconds 200
    }
    $script:stage += $sawUnavailablePid ? '_adb_or_process_timeout' : '_timeout'
    throw 'Timed out waiting for an Android guest milestone.'
}

function Wait-PcMarker {
    param([string]$Name,[int]$TimeoutSeconds = $PhaseTimeoutSeconds)
    Wait-PcValue -Name $Name -TimeoutSeconds $TimeoutSeconds | Out-Null
    return $true
}

function Wait-AndroidMarker {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$TimeoutSeconds = $PhaseTimeoutSeconds
    )
    if ($Name -notmatch '^[a-z0-9-]+$') {
        throw 'Unsafe Android marker name.'
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $consoleMarker = "[TPS DIRECT GAMEPLAY] $Name role=guest"
    $baselineCount = [regex]::Matches(
        [string]$script:androidMarkerLogBaseline,
        [regex]::Escape($consoleMarker)).Count
    $sawUnavailablePid = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        $currentPid = Get-AndroidGuestProcessId -Serial $Serial
        if (-not $currentPid) {
            $sawUnavailablePid = $true
            Start-Sleep -Milliseconds 300
            continue
        }
        if (-not $script:androidMarkerProcessId -or
                $currentPid -cne $script:androidMarkerProcessId) {
            $script:stage = "$($script:stage)_process_replaced"
            throw 'The isolated Android guest process changed unexpectedly.'
        }
        if ($null -ne (Read-AndroidPrivateFile -Serial $Serial -Name $Name)) {
            return $true
        }
        $logCapture = Get-AndroidGuestLog -Serial $Serial `
            -ExpectedProcessId $script:androidMarkerProcessId
        if ($logCapture.captured) {
            $currentCount = [regex]::Matches(
                $logCapture.text,[regex]::Escape($consoleMarker)).Count
            if ($currentCount -gt $baselineCount) {
                return $true
            }
        }
        if ($null -ne (Read-AndroidPrivateFile -Serial $Serial -Name 'failure')) {
            $script:stage = "$($script:stage)_internal_failure"
            throw 'The Android guest reached its internal timeout.'
        }
        Start-Sleep -Milliseconds 300
    }
    $script:stage += $sawUnavailablePid ? '_adb_or_process_timeout' : '_timeout'
    throw 'Timed out waiting for an Android guest marker.'
}

function Wait-AndroidPrivateConsumed {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$TimeoutSeconds = 20
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $sawHealthFailure = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        $path = Android-PrivatePath -Name $Name
        $presence = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
            'shell','run-as',$guestPackage,'test','-f',$path)
        $currentPid = Get-AndroidGuestProcessId -Serial $Serial
        if (-not $currentPid) {
            $sawHealthFailure = $true
            Start-Sleep -Milliseconds 100
            continue
        }
        if (-not $script:androidMarkerProcessId -or
                $currentPid -cne $script:androidMarkerProcessId) {
            $script:stage = "$($script:stage)_process_replaced"
            throw 'The isolated Android guest process changed unexpectedly.'
        }
        if ($presence.exitCode -eq 1) {
            $runAs = Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
                'shell','run-as',$guestPackage,'id')
            if ($runAs.exitCode -eq 0) {
                return $true
            }
            $sawHealthFailure = $true
        } elseif ($presence.exitCode -ne 0) {
            $sawHealthFailure = $true
        }
        Start-Sleep -Milliseconds 100
    }
    $script:stage += $sawHealthFailure ? '_adb_health_timeout' : '_timeout'
    throw 'The Android guest did not consume private control.'
}

function Set-AndroidMarkerContext {
    param([Parameter(Mandatory=$true)]$Context)
    $script:androidMarkerProcessId = [string]$Context.processId
    $script:androidMarkerLogBaseline = [string]$Context.logBaseline
}

function Start-AndroidGuestContext {
    param([Parameter(Mandatory=$true)]$Context)
    Clear-AndroidGuest -Serial $Context.serial
    Start-AndroidGuest -Serial $Context.serial
    $script:androidMarkerProcessId = $null
    $script:androidMarkerLogBaseline = ''
    Wait-AndroidValue -Serial $Context.serial -Name 'app-loaded' `
        -TimeoutSeconds $PhaseTimeoutSeconds | Out-Null
    $processId = Wait-StableAndroidGuestProcessId -Serial $Context.serial `
        -TimeoutSeconds 10
    if (-not $processId) {
        throw 'An isolated Android guest process could not be pinned.'
    }
    $baseline = Wait-AndroidGuestLogBaseline -Serial $Context.serial `
        -ExpectedProcessId $processId -TimeoutSeconds 10
    if (-not $baseline.captured) {
        throw 'An isolated Android guest log baseline could not be captured.'
    }
    $Context.processId = [string]$processId
    $Context.logBaseline = [string]$baseline.text
    Set-AndroidMarkerContext -Context $Context
}

function Wait-AndroidContextValue {
    param(
        [Parameter(Mandatory=$true)]$Context,
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$TimeoutSeconds = $PhaseTimeoutSeconds,
        [switch]$Code
    )
    Set-AndroidMarkerContext -Context $Context
    return Wait-AndroidValue -Serial $Context.serial -Name $Name `
        -TimeoutSeconds $TimeoutSeconds -Code:$Code
}

function Wait-AndroidContextMarker {
    param(
        [Parameter(Mandatory=$true)]$Context,
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$TimeoutSeconds = $PhaseTimeoutSeconds
    )
    Set-AndroidMarkerContext -Context $Context
    return Wait-AndroidMarker -Serial $Context.serial -Name $Name `
        -TimeoutSeconds $TimeoutSeconds
}

function Wait-AndroidContextPrivateConsumed {
    param(
        [Parameter(Mandatory=$true)]$Context,
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$TimeoutSeconds = 20
    )
    Set-AndroidMarkerContext -Context $Context
    return Wait-AndroidPrivateConsumed -Serial $Context.serial -Name $Name `
        -TimeoutSeconds $TimeoutSeconds
}

function Wait-AndroidContextExitMarker {
    param(
        [Parameter(Mandatory=$true)]$Context,
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$TimeoutSeconds = 30
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($null -ne (Read-AndroidPrivateFile -Serial $Context.serial `
                    -Name $Name)) {
            return $true
        }
        $currentPid = Get-AndroidGuestProcessId -Serial $Context.serial
        if ($currentPid -and $currentPid -cne [string]$Context.processId) {
            $script:stage = "$($script:stage)_process_replaced"
            throw 'The isolated Android guest process changed unexpectedly.'
        }
        Start-Sleep -Milliseconds 100
    }
    $script:stage = "$($script:stage)_exit_marker_timeout"
    throw 'Timed out waiting for an Android guest exit milestone.'
}

function Assert-NativeOpeningMarkers {
    param([Parameter(Mandatory=$true)][string]$Serial)
    foreach ($marker in @(
            'opening-native-next','opening-native-receive',
            'opening-native-accepted')) {
        $script:stage = "opening_pc_$marker"
        Wait-PcMarker -Name $marker -TimeoutSeconds 20 | Out-Null
        $script:stage = "opening_android_$marker"
        Wait-AndroidMarker -Serial $Serial -Name $marker `
            -TimeoutSeconds 20 | Out-Null
    }
    return $true
}

function Assert-IndexedNativeOpeningMarkers {
    param(
        [Parameter(Mandatory=$true)]$Context,
        [Parameter(Mandatory=$true)][ValidateRange(1,2)][int]$Ordinal
    )
    foreach ($suffix in @('native-next','native-receive','native-accepted')) {
        $marker = "opening-$Ordinal-$suffix"
        $script:stage = "opening_pc_$marker"
        Wait-PcMarker -Name $marker -TimeoutSeconds 20 | Out-Null
        $script:stage = "opening_android_$marker"
        Wait-AndroidContextMarker -Context $Context -Name $marker `
            -TimeoutSeconds 20 | Out-Null
    }
    return $true
}

function Assert-LogsSecretFree {
    param(
        [Parameter(Mandatory=$true)][string[]]$Logs,
        [Parameter(Mandatory=$true)][string[]]$Secrets
    )
    foreach ($log in $Logs) {
        if ([string]::IsNullOrEmpty($log)) { continue }
        if ($log -match 'TPS2[HR][A-Za-z0-9_.-]{8,}' -or
                $log -match '(?i)\b(?:key|psk|nonce)\s*[=:]\s*[0-9a-f]{24,}\b') {
            throw 'A Direct credential appeared in process logs.'
        }
        foreach ($secret in $Secrets) {
            if ($secret -and $log.Contains($secret)) {
                throw 'Private Direct material appeared in process logs.'
            }
        }
    }
    return $true
}

function Get-SecretByteRepresentations {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    if ($Bytes.Length -lt 4) {
        throw 'A decoded Direct secret was too short for log scanning.'
    }
    $base64 = [Convert]::ToBase64String($Bytes)
    $base64Url = $base64.TrimEnd('=').Replace('+','-').Replace('/','_')
    $hex = [Convert]::ToHexString($Bytes)
    $values = [System.Collections.Generic.List[string]]::new()
    foreach ($value in @(
            [Text.Encoding]::Latin1.GetString($Bytes),
            $base64,$base64.TrimEnd('='),$base64Url,
            $base64.Replace('+','-').Replace('/','_'),
            $hex,$hex.ToLowerInvariant())) {
        if (-not [string]::IsNullOrEmpty($value) -and
                -not $values.Contains($value)) {
            $values.Add($value)
        }
    }
    try {
        $utf8 = [Text.UTF8Encoding]::new($false,$true).GetString($Bytes)
        if (-not [string]::IsNullOrEmpty($utf8) -and
                -not $values.Contains($utf8)) {
            $values.Add($utf8)
        }
    } catch [Text.DecoderFallbackException] {
        # Random secret bytes commonly are not valid UTF-8. Latin-1 above is
        # the lossless raw-byte representation used for the mandatory scan.
    }
    return @($values)
}

function Invoke-GameplaySession {
    param(
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$PcLove,
        [Parameter(Mandatory=$true)][ValidateSet('kick','graceful')]
        [string]$Ending
    )
    $hostCode = $null
    $responseCode = $null
    $androidLogBefore = ''
    $androidLogAfter = ''
    $androidFinalLogCaptured = $false
    $pcLog = ''
    $sessionSucceeded = $false
    $nativeOpening = $false
    $hostApproval = $false
    $snapshotApplied = $false
    $directHud = $false
    $bayInteraction = $false
    $cutterAction = $false
    $movement = $false
    $hostDisconnect = $false
    $hostKick = $false
    $guestKicked = $false
    $guestGraceful = $false
    $sessionIsCaptured = [bool]$captureActive
    $encodedPlayerCanary = -not $sessionIsCaptured
    $encodedLoadingBayPlaintext = -not $sessionIsCaptured
    $encodedCutterPlaintext = -not $sessionIsCaptured
    try {
        $script:androidMarkerLogBaseline = ''
        $script:androidMarkerProcessId = $null
        $script:stage = "${Ending}_session_reset"
        Remove-SafeTree -Path $pcSaveRoot -Kind pc-save
        Clear-AndroidGuest -Serial $Serial
        $script:stage = "${Ending}_session_launch"
        $script:pcProcessContext = Start-PcHost -PackagePath $PcLove
        $script:pcProcessExited = $false
        Start-AndroidGuest -Serial $Serial

        $script:stage = "${Ending}_wait_pc_app_loaded"
        Wait-PcMarker -Name 'app-loaded' | Out-Null
        $script:stage = "${Ending}_wait_android_app_loaded"
        # This first marker is file-only after pm clear.  Once present, pin the
        # new process and its existing PID-scoped log as the console baseline.
        Wait-AndroidValue -Serial $Serial -Name 'app-loaded' `
            -TimeoutSeconds $PhaseTimeoutSeconds | Out-Null
        $script:stage = "${Ending}_pin_android_process"
        $script:androidMarkerProcessId = Wait-StableAndroidGuestProcessId `
            -Serial $Serial -TimeoutSeconds 10
        if (-not $script:androidMarkerProcessId) {
            throw 'The isolated Android guest process could not be pinned.'
        }
        $script:stage = "${Ending}_capture_android_log_baseline"
        $baseline = Wait-AndroidGuestLogBaseline -Serial $Serial `
            -ExpectedProcessId $script:androidMarkerProcessId -TimeoutSeconds 10
        if (-not $baseline.captured) {
            throw 'The isolated Android guest log baseline could not be captured.'
        }
        $script:androidMarkerLogBaseline = [string]$baseline.text
        $script:stage = "${Ending}_inject_private_addresses"
        Write-PcPrivateValue -Name 'inbox-local-address' `
            -Value $script:pcAddress -Address
        Write-AndroidPrivateValue -Serial $Serial `
            -Name 'inbox-local-address' -Value $script:guestAddress -Address

        $script:stage = "${Ending}_exchange_host_code"
        $hostCode = Wait-PcValue -Name 'host-code' `
            -TimeoutSeconds $PhaseTimeoutSeconds -Code
        if ($hostCode -notmatch '^TPS2H') {
            throw 'The PC host produced the wrong private code kind.'
        }
        Remove-PcPrivateFile -Name 'host-code'
        Write-AndroidPrivateValue -Serial $Serial `
            -Name 'inbox-host-code' -Value $hostCode
        $script:stage = "${Ending}_exchange_response_code"
        $responseCode = Wait-AndroidValue -Serial $Serial `
            -Name 'response-code' -TimeoutSeconds $PhaseTimeoutSeconds -Code
        if ($responseCode -notmatch '^TPS2R') {
            throw 'The Android guest produced the wrong private code kind.'
        }
        Register-CaptureInvitationMaterial -HostCode $hostCode `
            -ResponseCode $responseCode
        Remove-AndroidPrivateFile -Serial $Serial -Name 'response-code'
        Write-PcPrivateValue -Name 'inbox-response-code' -Value $responseCode

        $script:stage = "${Ending}_wait_host_approval"
        Wait-PcMarker -Name 'host-approved' | Out-Null
        $hostApproval = $true
        Wait-PcMarker -Name 'session-ready' | Out-Null
        Wait-AndroidMarker -Serial $Serial -Name 'session-ready' | Out-Null
        Wait-PcMarker -Name 'hud-direct-two' | Out-Null
        Wait-AndroidMarker -Serial $Serial -Name 'hud-direct-two' | Out-Null
        $directHud = $true
        $script:stage = "${Ending}_wait_snapshot_applied"
        Wait-AndroidMarker -Serial $Serial -Name 'snapshot-applied' | Out-Null
        $snapshotApplied = $true
        $script:stage = "${Ending}_wait_loading_bay_interaction"
        Wait-AndroidMarker -Serial $Serial -Name 'bay-interaction' | Out-Null
        $bayInteraction = $true
        $script:stage = "${Ending}_wait_cutter_action"
        Wait-AndroidMarker -Serial $Serial -Name 'cutter-action' | Out-Null
        $cutterAction = $true
        $script:stage = "${Ending}_wait_android_movement"
        Wait-AndroidMarker -Serial $Serial -Name 'movement' | Out-Null
        $script:stage = "${Ending}_wait_pc_movement"
        Wait-PcMarker -Name 'movement' | Out-Null
        $script:stage = "${Ending}_wait_android_complete"
        Wait-AndroidMarker -Serial $Serial -Name 'client-complete' | Out-Null
        $script:stage = "${Ending}_wait_pc_complete"
        Wait-PcMarker -Name 'host-complete' | Out-Null
        $movement = $true
        $script:stage = "${Ending}_verify_native_opening"
        $nativeOpening = Assert-NativeOpeningMarkers -Serial $Serial
        if ($sessionIsCaptured) {
            $script:stage = "${Ending}_verify_encoded_player_canaries"
            Wait-PcMarker -Name 'encoded-player-canary' -TimeoutSeconds 20 | Out-Null
            Wait-AndroidMarker -Serial $Serial -Name 'encoded-player-canary' `
                -TimeoutSeconds 20 | Out-Null
            $encodedPlayerCanary = $true
            $script:stage = "${Ending}_verify_encoded_loading_bay_plaintext"
            Wait-PcMarker -Name 'encoded-loading-bay-plaintext' `
                -TimeoutSeconds 20 | Out-Null
            Wait-AndroidMarker -Serial $Serial `
                -Name 'encoded-loading-bay-plaintext' -TimeoutSeconds 20 | Out-Null
            $encodedLoadingBayPlaintext = $true
            $script:stage = "${Ending}_verify_encoded_cutter_plaintext"
            Wait-PcMarker -Name 'encoded-cutter-plaintext' `
                -TimeoutSeconds 20 | Out-Null
            Wait-AndroidMarker -Serial $Serial `
                -Name 'encoded-cutter-plaintext' -TimeoutSeconds 20 | Out-Null
            $encodedCutterPlaintext = $true
        }

        $beforeCapture = Get-AndroidGuestLog -Serial $Serial `
            -ExpectedProcessId $script:androidMarkerProcessId
        if (-not $beforeCapture.captured) {
            throw 'The isolated Android guest log could not be captured.'
        }
        $androidLogBefore = [string]$beforeCapture.text
        if ($Ending -ceq 'kick') {
            $script:stage = 'kick_arm_guest'
            Write-AndroidPrivateValue -Serial $Serial `
                -Name 'inbox-kick' -Value 'kick'
            Wait-AndroidPrivateConsumed -Serial $Serial -Name 'inbox-kick' | Out-Null
            $script:stage = 'kick_host_hud_remove'
            Write-PcPrivateValue -Name 'inbox-kick' -Value 'kick'
            Wait-PcMarker -Name 'host-kick' -TimeoutSeconds 30 | Out-Null
            $hostKick = $true
            Wait-AndroidMarker -Serial $Serial -Name 'guest-kicked' `
                -TimeoutSeconds 30 | Out-Null
            $guestKicked = $true
            Wait-PcMarker -Name 'host-disconnect' -TimeoutSeconds 30 | Out-Null
            $hostDisconnect = $true
        } else {
            $script:stage = 'graceful_guest_exit'
            Write-AndroidPrivateValue -Serial $Serial `
                -Name 'inbox-disconnect' -Value 'quit'
            Wait-AndroidMarker -Serial $Serial -Name 'client-graceful-exit' `
                -TimeoutSeconds 30 | Out-Null
            $guestGraceful = $true
            Wait-PcMarker -Name 'host-disconnect' -TimeoutSeconds 30 | Out-Null
            $hostDisconnect = $true
        }
        $sessionSucceeded = $true
    } finally {
        $afterCapture = if ($script:androidMarkerProcessId) {
            Get-AndroidGuestLog -Serial $Serial `
                -ExpectedProcessId $script:androidMarkerProcessId
        } else {
            [pscustomobject]@{ captured = $false; text = '' }
        }
        $androidFinalLogCaptured = [bool]$afterCapture.captured
        $androidLogAfter = [string]$afterCapture.text
        Invoke-AdbBestEffort -Serial $Serial -CommandArguments @(
            'shell','am','force-stop',$guestPackage) | Out-Null
        if ($script:pcProcessContext) {
            $stopped = Stop-PcHost -Context $script:pcProcessContext
            $pcLog = $stopped.log
            $script:pcProcessExited = [bool]$stopped.exited
            $script:pcProcessContext = $null
        }
        if ($script:stage -match '^opening_android_(opening-[a-z-]+)') {
            $safeMarker = $Matches[1]
            $safeConsolePattern = [regex]::Escape(
                "[TPS DIRECT GAMEPLAY] $safeMarker role=guest")
            $script:stage += (($androidLogBefore + "`n" + $androidLogAfter) `
                -match $safeConsolePattern) ? '_console_present' : '_console_absent'
        }
        foreach ($name in @('host-code','inbox-response-code','inbox-kick')) {
            Remove-PcPrivateFile -Name $name
        }
        foreach ($name in @('response-code','inbox-host-code','inbox-kick',
                'inbox-disconnect')) {
            Remove-AndroidPrivateFile -Serial $Serial -Name $name
        }
        Remove-SafeTree -Path $pcSaveRoot -Kind pc-save
        try {
            if (-not $androidFinalLogCaptured) {
                throw 'The final pinned Android guest log could not be captured.'
            }
            Assert-LogsSecretFree `
                -Logs @($pcLog,$androidLogBefore,$androidLogAfter) `
                -Secrets @($hostCode,$responseCode,$script:pcAddress,
                    $script:guestAddress,$Serial) | Out-Null
        } finally {
            $script:androidMarkerLogBaseline = ''
            $script:androidMarkerProcessId = $null
            $hostCode = $null
            $responseCode = $null
        }
    }
    if (-not $sessionSucceeded) {
        throw 'The gameplay session did not complete.'
    }
    return [pscustomobject]@{
        twoCodePlayerFlow = $true
        explicitHostApproval = $hostApproval
        nativeOpening = $nativeOpening
        snapshotApplied = $snapshotApplied
        directHudTwo = $directHud
        bayInteraction = $bayInteraction
        cutterAction = $cutterAction
        movement = $movement
        hostDisconnect = $hostDisconnect
        hostKick = $hostKick
        guestKicked = $guestKicked
        guestGraceful = $guestGraceful
        logsSecretFree = $true
        encodedPlayerCanary = $encodedPlayerCanary
        encodedLoadingBayPlaintext = $encodedLoadingBayPlaintext
        encodedCutterPlaintext = $encodedCutterPlaintext
    }
}

function Invoke-TwoGuestGameplaySession {
    param(
        [Parameter(Mandatory=$true)][object[]]$Guests,
        [Parameter(Mandatory=$true)][string]$PcLove
    )
    if ($Guests.Count -ne 2) {
        throw 'Exactly two private Android guest contexts are required.'
    }
    $hostCodeFirst = $null
    $hostCodeSecond = $null
    $responseCodeFirst = $null
    $responseCodeSecond = $null
    $firstMaterial = $null
    $secondMaterial = $null
    $pcLog = ''
    $androidLogs = [System.Collections.Generic.List[string]]::new()
    $finalAndroidLogCaptureCount = 0
    $sessionSucceeded = $false
    $freshInvitations = $false
    $explicitApprovals = $false
    $nativeOpenings = $false
    $snapshots = $false
    $movements = $false
    $threePlayerHud = $false
    $firstGuestKicked = $false
    $secondGuestSurvived = $false
    $secondGuestGraceful = $false
    $hostReturnedToOne = $false
    try {
        $script:stage = 'multi_session_reset'
        Remove-SafeTree -Path $pcSaveRoot -Kind pc-save
        foreach ($context in $Guests) {
            Clear-AndroidGuest -Serial $context.serial
        }

        $script:stage = 'multi_session_launch_pc'
        $script:pcProcessContext = Start-PcHost -PackagePath $PcLove
        $script:pcProcessExited = $false
        Wait-PcMarker -Name 'app-loaded' | Out-Null

        $script:stage = 'multi_first_guest_launch'
        Start-AndroidGuestContext -Context $Guests[0]
        Write-PcPrivateValue -Name 'inbox-local-address' `
            -Value $Guests[0].pcAddress -Address
        Write-AndroidPrivateValue -Serial $Guests[0].serial `
            -Name 'inbox-local-address' -Value $Guests[0].address -Address

        $script:stage = 'multi_first_exchange_host_code'
        $hostCodeFirst = Wait-PcValue -Name 'host-code-1' `
            -TimeoutSeconds $PhaseTimeoutSeconds -Code
        if ($hostCodeFirst -notmatch '^TPS2H') {
            throw 'The PC host produced the wrong first private code kind.'
        }
        Add-ReportSensitiveValue -Value $hostCodeFirst
        Remove-PcPrivateFile -Name 'host-code-1'
        Write-AndroidPrivateValue -Serial $Guests[0].serial `
            -Name 'inbox-host-code-1' -Value $hostCodeFirst

        $script:stage = 'multi_first_exchange_response_code'
        $responseCodeFirst = Wait-AndroidContextValue -Context $Guests[0] `
            -Name 'response-code-1' -TimeoutSeconds $PhaseTimeoutSeconds -Code
        if ($responseCodeFirst -notmatch '^TPS2R') {
            throw 'The first Android guest produced the wrong private code kind.'
        }
        Add-ReportSensitiveValue -Value $responseCodeFirst
        Remove-AndroidPrivateFile -Serial $Guests[0].serial -Name 'response-code-1'
        Write-PcPrivateValue -Name 'inbox-response-code-1' `
            -Value $responseCodeFirst

        $firstMaterial = Get-DirectHostInvitationMaterial -HostCode $hostCodeFirst
        if (-not (Test-DirectHostInvitationEndpoint -Material $firstMaterial `
                    -ExpectedAddress $Guests[0].pcAddress `
                    -ExpectedPort $Guests[0].port)) {
            throw 'The first Direct invitation did not encode the verified endpoint.'
        }
        $script:stage = 'multi_first_wait_explicit_approval'
        Wait-AndroidContextMarker -Context $Guests[0] `
            -Name 'approval-waiting-1' | Out-Null
        Wait-PcMarker -Name 'approval-pending-1' | Out-Null
        Write-PcPrivateValue -Name 'inbox-approve-1' -Value 'approve'
        Wait-PcMarker -Name 'host-approved-1' | Out-Null

        $script:stage = 'multi_first_gameplay'
        Wait-PcMarker -Name 'session-ready-1' | Out-Null
        Wait-PcMarker -Name 'hud-direct-two-1' | Out-Null
        Wait-AndroidContextMarker -Context $Guests[0] `
            -Name 'session-ready-1' | Out-Null
        Wait-AndroidContextMarker -Context $Guests[0] `
            -Name 'hud-direct-two-1' | Out-Null
        Wait-AndroidContextMarker -Context $Guests[0] `
            -Name 'snapshot-applied-1' | Out-Null
        Wait-AndroidContextMarker -Context $Guests[0] `
            -Name 'bay-interaction-1' | Out-Null
        Wait-AndroidContextMarker -Context $Guests[0] `
            -Name 'cutter-action-1' | Out-Null
        Wait-AndroidContextMarker -Context $Guests[0] `
            -Name 'movement-1' | Out-Null
        Wait-AndroidContextMarker -Context $Guests[0] `
            -Name 'client-complete-1' | Out-Null
        Wait-PcMarker -Name 'host-observed-movement-1' | Out-Null
        Assert-IndexedNativeOpeningMarkers -Context $Guests[0] -Ordinal 1 | Out-Null

        $script:stage = 'multi_second_guest_launch'
        Start-AndroidGuestContext -Context $Guests[1]
        Write-AndroidPrivateValue -Serial $Guests[1].serial `
            -Name 'inbox-local-address' -Value $Guests[1].address -Address
        Write-PcPrivateValue -Name 'inbox-local-address-2' `
            -Value $Guests[1].pcAddress -Address
        Write-PcPrivateValue -Name 'inbox-invite-2' -Value 'invite'

        $script:stage = 'multi_second_exchange_host_code'
        $hostCodeSecond = Wait-PcValue -Name 'host-code-2' `
            -TimeoutSeconds $PhaseTimeoutSeconds -Code
        if ($hostCodeSecond -notmatch '^TPS2H') {
            throw 'The PC host produced the wrong second private code kind.'
        }
        Add-ReportSensitiveValue -Value $hostCodeSecond
        Remove-PcPrivateFile -Name 'host-code-2'
        Write-AndroidPrivateValue -Serial $Guests[1].serial `
            -Name 'inbox-host-code-2' -Value $hostCodeSecond

        $script:stage = 'multi_second_exchange_response_code'
        $responseCodeSecond = Wait-AndroidContextValue -Context $Guests[1] `
            -Name 'response-code-2' -TimeoutSeconds $PhaseTimeoutSeconds -Code
        if ($responseCodeSecond -notmatch '^TPS2R') {
            throw 'The second Android guest produced the wrong private code kind.'
        }
        Add-ReportSensitiveValue -Value $responseCodeSecond
        Remove-AndroidPrivateFile -Serial $Guests[1].serial -Name 'response-code-2'
        Write-PcPrivateValue -Name 'inbox-response-code-2' `
            -Value $responseCodeSecond

        $secondMaterial = Get-DirectHostInvitationMaterial -HostCode $hostCodeSecond
        if (-not (Test-DirectHostInvitationEndpoint -Material $secondMaterial `
                    -ExpectedAddress $Guests[1].pcAddress `
                    -ExpectedPort $Guests[1].port)) {
            throw 'The second Direct invitation did not encode the verified endpoint.'
        }
        if ($hostCodeFirst -ceq $hostCodeSecond -or
                $responseCodeFirst -ceq $responseCodeSecond -or
                (Test-BytesEqual -First $firstMaterial.invitationId `
                    -Second $secondMaterial.invitationId) -or
                (Test-BytesEqual -First $firstMaterial.masterKey `
                    -Second $secondMaterial.masterKey)) {
            throw 'The second Direct invitation did not use fresh private material.'
        }
        $freshInvitations = $true

        $script:stage = 'multi_second_wait_explicit_approval'
        Wait-AndroidContextMarker -Context $Guests[1] `
            -Name 'approval-waiting-2' | Out-Null
        Wait-PcMarker -Name 'approval-pending-2' | Out-Null
        Write-PcPrivateValue -Name 'inbox-approve-2' -Value 'approve'
        Wait-PcMarker -Name 'host-approved-2' | Out-Null
        $explicitApprovals = $true

        $script:stage = 'multi_three_player_gameplay'
        Wait-PcMarker -Name 'session-ready-2' | Out-Null
        Wait-PcMarker -Name 'host-hud-three' | Out-Null
        foreach ($context in $Guests) {
            Wait-AndroidContextMarker -Context $context `
                -Name "hud-direct-three-$($context.ordinal)" | Out-Null
        }
        Wait-AndroidContextMarker -Context $Guests[1] `
            -Name 'session-ready-2' | Out-Null
        Wait-AndroidContextMarker -Context $Guests[1] `
            -Name 'snapshot-applied-2' | Out-Null
        Wait-AndroidContextMarker -Context $Guests[1] `
            -Name 'movement-2' | Out-Null
        Wait-AndroidContextMarker -Context $Guests[1] `
            -Name 'client-complete-2' | Out-Null
        Wait-PcMarker -Name 'host-observed-movement-2' | Out-Null
        Assert-IndexedNativeOpeningMarkers -Context $Guests[1] -Ordinal 2 | Out-Null
        $nativeOpenings = $true
        $snapshots = $true
        $movements = $true
        $threePlayerHud = $true

        $firstLogCapture = Get-AndroidGuestLog -Serial $Guests[0].serial `
            -ExpectedProcessId $Guests[0].processId
        if (-not $firstLogCapture.captured) {
            throw 'The first pinned Android guest log could not be captured.'
        }
        $androidLogs.Add([string]$firstLogCapture.text)
        $script:stage = 'multi_kick_first_guest_arm'
        Write-AndroidPrivateValue -Serial $Guests[0].serial `
            -Name 'inbox-kick' -Value 'kick'
        Wait-AndroidContextPrivateConsumed -Context $Guests[0] `
            -Name 'inbox-kick' | Out-Null
        $script:stage = 'multi_kick_first_guest_host_control'
        Write-PcPrivateValue -Name 'inbox-kick-1' -Value 'kick'
        Wait-PcMarker -Name 'host-kick-1' -TimeoutSeconds 30 | Out-Null
        Wait-AndroidContextMarker -Context $Guests[0] `
            -Name 'guest-kicked-1' -TimeoutSeconds 30 | Out-Null
        $firstGuestKicked = $true

        $script:stage = 'multi_verify_surviving_guest'
        Wait-PcMarker -Name 'host-survivor-two' -TimeoutSeconds 30 | Out-Null
        Wait-AndroidContextMarker -Context $Guests[1] `
            -Name 'guest-survivor-two' -TimeoutSeconds 30 | Out-Null
        $secondGuestSurvived = $true

        $secondLogCapture = Get-AndroidGuestLog -Serial $Guests[1].serial `
            -ExpectedProcessId $Guests[1].processId
        if (-not $secondLogCapture.captured) {
            throw 'The second pinned Android guest log could not be captured.'
        }
        $androidLogs.Add([string]$secondLogCapture.text)
        $script:stage = 'multi_survivor_graceful_exit'
        Assert-PcMarkerAbsent -Name 'host-final-one' | Out-Null
        Write-AndroidPrivateValue -Serial $Guests[1].serial `
            -Name 'inbox-disconnect' -Value 'quit'
        Wait-AndroidContextExitMarker -Context $Guests[1] `
            -Name 'session-stop-confirmed-2' -TimeoutSeconds 30 | Out-Null
        Wait-AndroidContextExitMarker -Context $Guests[1] `
            -Name 'app-quit-confirmed-2' -TimeoutSeconds 30 | Out-Null
        Wait-AndroidContextExitMarker -Context $Guests[1] `
            -Name 'client-graceful-exit-2' -TimeoutSeconds 30 | Out-Null
        $secondGuestGraceful = $true
        Wait-PcMarker -Name 'host-final-one' -TimeoutSeconds 30 | Out-Null
        $hostReturnedToOne = $true
        $sessionSucceeded = $true
    } finally {
        foreach ($context in $Guests) {
            $finalLogCapture = if ($context.processId) {
                Get-AndroidGuestLog -Serial $context.serial `
                    -ExpectedProcessId $context.processId
            } else {
                [pscustomobject]@{ captured = $false; text = '' }
            }
            if ($finalLogCapture.captured) {
                $finalAndroidLogCaptureCount++
                $androidLogs.Add([string]$finalLogCapture.text)
            }
            Invoke-AdbBestEffort -Serial $context.serial -CommandArguments @(
                'shell','am','force-stop',$guestPackage) | Out-Null
        }
        if ($script:pcProcessContext) {
            $stopped = Stop-PcHost -Context $script:pcProcessContext
            $pcLog = $stopped.log
            $script:pcProcessExited = [bool]$stopped.exited
            $script:pcProcessContext = $null
        }
        foreach ($name in @(
                'host-code-1','host-code-2','inbox-response-code-1',
                'inbox-response-code-2','inbox-approve-1','inbox-approve-2',
                'inbox-invite-2','inbox-local-address-2','inbox-kick-1')) {
            Remove-PcPrivateFile -Name $name
        }
        foreach ($context in $Guests) {
            foreach ($name in @(
                    "response-code-$($context.ordinal)",
                    "inbox-host-code-$($context.ordinal)",'inbox-kick',
                    'inbox-disconnect')) {
                Remove-AndroidPrivateFile -Serial $context.serial -Name $name
            }
        }
        $secretValues = @(
            $hostCodeFirst,$hostCodeSecond,$responseCodeFirst,$responseCodeSecond,
            $pcPlayerCanary
        ) + @($Guests | ForEach-Object {
            @($_.serial,$_.address,$_.pcAddress,$_.playerName)
        })
        foreach ($material in @($firstMaterial,$secondMaterial)) {
            if ($material) {
                $secretValues += @(Get-SecretByteRepresentations `
                    -Bytes $material.invitationId)
                $secretValues += @(Get-SecretByteRepresentations `
                    -Bytes $material.masterKey)
            }
        }
        Remove-SafeTree -Path $pcSaveRoot -Kind pc-save
        foreach ($material in @($firstMaterial,$secondMaterial)) {
            if ($material) {
                [Array]::Clear($material.addressBytes,0,$material.addressBytes.Length)
                [Array]::Clear($material.invitationId,0,$material.invitationId.Length)
                [Array]::Clear($material.masterKey,0,$material.masterKey.Length)
            }
        }
        $script:androidMarkerLogBaseline = ''
        $script:androidMarkerProcessId = $null
        try {
            if ($sessionSucceeded -and $finalAndroidLogCaptureCount -ne 2) {
                throw 'Both final pinned Android guest logs were not captured.'
            }
            Assert-LogsSecretFree -Logs (@($pcLog) + @($androidLogs)) `
                -Secrets @($secretValues) | Out-Null
        } finally {
            $secretValues = $null
            $hostCodeFirst = $null
            $hostCodeSecond = $null
            $responseCodeFirst = $null
            $responseCodeSecond = $null
        }
    }
    if (-not $sessionSucceeded) {
        throw 'The two-guest gameplay session did not complete.'
    }
    return [pscustomobject]@{
        sequentialFreshInvitations = $freshInvitations
        explicitHostApprovals = $explicitApprovals
        authenticatedNativeOpenings = $nativeOpenings
        snapshotsAppliedToBothGuests = $snapshots
        hostObservedBothGuestMovements = $movements
        threePlayerHudEverywhere = $threePlayerHud
        firstGuestHudKick = $firstGuestKicked
        secondGuestSurvivedKick = $secondGuestSurvived
        secondGuestGracefulExit = $secondGuestGraceful
        hostReturnedToOneOfFour = $hostReturnedToOne
        logsSecretFree = $true
    }
}

function Get-FailureClass {
    param([Parameter(Mandatory=$true)][string]$FailureStage)
    if ($FailureStage -match 'lock|concurrent') { return 'concurrent_probe' }
    if ($FailureStage -match 'packet_capture') { return 'packet_capture_validation' }
    if ($FailureStage -match 'opening') { return 'authenticated_opening' }
    if ($FailureStage -match 'select|route|network|firewall|port') {
        return 'network_preflight'
    }
    if ($FailureStage -match 'artifact|package|build|install') {
        return 'artifact_verification'
    }
    if ($FailureStage -match 'kick') { return 'host_removal_acceptance' }
    if ($FailureStage -match 'graceful') { return 'disconnect_acceptance' }
    if ($FailureStage -match 'session|approval|invite|gameplay|snapshot|movement|hud') {
        return 'gameplay_acceptance'
    }
    if ($FailureStage -match 'cleanup') { return 'cleanup_verification' }
    return 'probe_failure'
}

try {
    $stage = 'prepare_evidence_directory'
    New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
    $stage = 'verify_required_artifacts'
    foreach ($required in @($baseReportPath,$adb,$builder,$probeMain,$loveConsole,
            $windowsCrypto,$providerSource)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw 'A required PC/Android Direct probe artifact is missing.'
        }
    }

    $stage = 'acquire_exclusive_probe_lock'
    $runMutex = [System.Threading.Mutex]::new($false,
        'Local\ThePictureShopPcAndroidDirectGameplayProbe')
    try {
        $mutexOwned = $runMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $mutexOwned = $true
    }
    if (-not $mutexOwned) { throw 'Another Direct gameplay probe is active.' }

    if (-not $PreflightOnly) {
        $boundRecoveryPaths = @()
        if ($PacketCaptureValidation -and
                (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
            try {
                $existingPendingHashBefore = (Get-FileHash -Algorithm SHA256 `
                    -LiteralPath $pendingPath).Hash.ToLowerInvariant()
                $existingPending = Get-Content -Raw -LiteralPath $pendingPath |
                    ConvertFrom-Json
                $existingPendingHash = (Get-FileHash -Algorithm SHA256 `
                    -LiteralPath $pendingPath).Hash.ToLowerInvariant()
                if ($existingPendingHashBefore -cne $existingPendingHash) {
                    $preserveExistingPendingReport = $true
                    throw 'The prior packet-capture report changed during review.'
                }
                if (Test-CapturePendingUnresolved -Report $existingPending) {
                    $boundRecoveryPaths = @(
                        Get-BoundCaptureRecoveryPaths `
                            -PendingReportPath $pendingPath)
                    if ($boundRecoveryPaths.Count -lt 1) {
                        $preserveExistingPendingReport = $true
                        throw 'The prior packet-capture recovery evidence must be preserved.'
                    }
                }
                $existingPendingHashFinal = (Get-FileHash -Algorithm SHA256 `
                    -LiteralPath $pendingPath).Hash.ToLowerInvariant()
                if ($existingPendingHashFinal -cne $existingPendingHash) {
                    $preserveExistingPendingReport = $true
                    throw 'The prior packet-capture report changed before retirement.'
                }
            } catch {
                if (-not $preserveExistingPendingReport) {
                    $preserveExistingPendingReport = $true
                }
                throw
            }
        }
        foreach ($old in @($evidencePath,$pendingPath)) {
            if (Test-Path -LiteralPath $old) {
                Remove-Item -LiteralPath $old -Force
            }
        }
        foreach ($resolvedRecovery in $boundRecoveryPaths) {
            if (Test-Path -LiteralPath $resolvedRecovery -PathType Leaf) {
                Remove-Item -LiteralPath $resolvedRecovery -Force
            }
        }
    }

    $stage = 'verify_provider_gate'
    $providerText = [System.IO.File]::ReadAllText($providerSource)
    if ($providerText -notmatch 'productionReady\s*=\s*false' -or
            $providerText -match 'productionReady\s*=\s*true') {
        throw 'The normal Direct provider gate is not closed.'
    }

    $stage = $AndroidGuestCount -eq 2 `
        ? 'select_two_global_ipv6_guests' : 'select_unique_cellular_guest'
    $serials = @(Get-ConnectedSerials)
    if ($serials.Count -lt 1) { throw 'No authorized Android device is attached.' }
    if ($AndroidGuestCount -eq 2 -and $serials.Count -ne 2) {
        throw 'Exactly two authorized Android devices must be attached for the two-guest probe.'
    }
    if (-not (Test-NoConcurrentEngineeringApp -Serials $serials)) {
        $stage = 'concurrent_engineering_probe'
        throw 'Another engineering Direct app is active.'
    }
    $candidates = @()
    foreach ($serial in $serials) {
        $interface = Get-DefaultIpv6Interface -Serial $serial
        if ($AndroidGuestCount -eq 2) {
            $routeScope = if (Test-CellularInterface -Name $interface) {
                'cellular'
            } elseif ($interface -match '^wlan[A-Za-z0-9_.-]*$') {
                'wifi'
            } else {
                $null
            }
            if ($routeScope) {
                $candidate = Get-StableGlobalIpv6 -Serial $serial `
                    -Interface $interface
                if ($candidate) {
                    $candidates += [pscustomobject]@{
                        serial = $serial
                        interface = $interface
                        candidate = $candidate
                        routeScope = $routeScope
                    }
                }
            }
        } elseif ((Test-CellularInterface -Name $interface) -and
                -not (Get-WifiIpv4 -Serial $serial)) {
            $candidate = Get-StableGlobalIpv6 -Serial $serial `
                -Interface $interface
            if ($candidate) {
                $candidates += [pscustomobject]@{
                    serial = $serial
                    interface = $interface
                    candidate = $candidate
                }
            }
        }
    }
    if ($AndroidGuestCount -eq 2) {
        if ($candidates.Count -ne 2) {
            throw 'Both attached Android devices need a stable global IPv6 route.'
        }
        $wifiCandidates = @($candidates | Where-Object { $_.routeScope -ceq 'wifi' })
        $cellularCandidates = @($candidates |
            Where-Object { $_.routeScope -ceq 'cellular' })
        if ($wifiCandidates.Count -ne 1 -or $cellularCandidates.Count -ne 1) {
            throw 'The two-guest probe requires one Wi-Fi and one cellular Android route.'
        }
        $candidates = @($wifiCandidates[0],$cellularCandidates[0])
        if (Test-SameIpv6Address -First $candidates[0].candidate `
                -Second $candidates[1].candidate) {
            throw 'The two Android routes did not expose unique global IPv6 addresses.'
        }
        $multiTopologyRouteMix = $true
        $stage = 'verify_two_guest_routes'
        for ($index = 0; $index -lt 2; $index++) {
            $candidate = $candidates[$index]
            $port = $directPorts[$index]
            $hostSource = Resolve-PcIpv6Source `
                -Destination $candidate.candidate -Port $port
            $interfaceIndex = if ($hostSource) {
                Get-PcWifiInterfaceIndex -Address $hostSource
            } else { $null }
            $androidSource = if ($hostSource) {
                Resolve-AndroidIpv6Source -Serial $candidate.serial `
                    -Destination $hostSource -ExpectedInterface $candidate.interface
            } else { $null }
            $hostCheck = if ($androidSource) {
                Resolve-PcIpv6Source -Destination $androidSource -Port $port
            } else { $null }
            $androidCheck = if ($hostCheck) {
                Resolve-AndroidIpv6Source -Serial $candidate.serial `
                    -Destination $hostCheck -ExpectedInterface $candidate.interface
            } else { $null }
            if (-not $hostSource -or $null -eq $interfaceIndex -or
                    -not $androidSource -or $hostCheck -cne $hostSource -or
                    $androidCheck -cne $androidSource) {
                throw 'A two-guest Direct route was not stable and bidirectional.'
            }
            $guestContexts += [pscustomobject]@{
                ordinal = $index + 1
                serial = $candidate.serial
                interface = $candidate.interface
                routeScope = $candidate.routeScope
                candidate = $candidate.candidate
                address = $androidSource
                pcAddress = $hostSource
                pcInterfaceIndex = [int]$interfaceIndex
                port = [int]$port
                playerName = $androidPlayerCanaries[$index]
                processId = $null
                logBaseline = ''
                apk = $null
            }
        }
        $multiTopologySharedPcSource =
            (Test-SameIpv6Address -First $guestContexts[0].pcAddress `
                -Second $guestContexts[1].pcAddress) -and
            $guestContexts[0].pcInterfaceIndex -eq
                $guestContexts[1].pcInterfaceIndex
        $multiTopologyUniqueAddresses =
            -not (Test-SameIpv6Address -First $guestContexts[0].address `
                -Second $guestContexts[1].address)
        $multiTopologyAtLeastOneDistinctPrefix = @($guestContexts |
            Where-Object {
                Test-DifferentIpv6Prefixes -First $_.pcAddress -Second $_.address
            }).Count -ge 1
        if (-not $multiTopologySharedPcSource -or
                -not $multiTopologyUniqueAddresses -or
                -not $multiTopologyAtLeastOneDistinctPrefix) {
            throw 'The two-guest topology did not meet the isolated route requirements.'
        }
        $pcAddress = $guestContexts[0].pcAddress
        $pcInterfaceIndex = $guestContexts[0].pcInterfaceIndex
        foreach ($context in $guestContexts) {
            foreach ($sensitive in @(
                    $context.serial,$context.candidate,$context.address,
                    $context.pcAddress,$context.playerName)) {
                Add-ReportSensitiveValue -Value $sensitive
            }
            if (-not (Test-PcPortAvailable -Port $context.port) -or
                    -not (Test-AndroidPortAvailable -Serial $context.serial `
                        -Port $context.port)) {
                $stage = 'verify_direct_ports'
                throw 'A two-guest Direct gameplay probe port is already in use.'
            }
        }
        Add-ReportSensitiveValue -Value $pcPlayerCanary
    } else {
        if ($candidates.Count -ne 1) {
            throw 'Exactly one attached cellular-only Android guest is required.'
        }
        $guestDevice = $candidates[0].serial
        $guestInterface = $candidates[0].interface
        $guestCandidate = $candidates[0].candidate

        $stage = 'verify_wifi_cellular_routes'
        $pcAddress = Resolve-PcIpv6Source -Destination $guestCandidate
        $pcInterfaceIndex = if ($pcAddress) {
            Get-PcWifiInterfaceIndex -Address $pcAddress
        } else { $null }
        $guestAddress = if ($pcAddress) {
            Resolve-AndroidIpv6Source -Serial $guestDevice `
                -Destination $pcAddress -ExpectedInterface $guestInterface
        } else { $null }
        $pcCheck = if ($guestAddress) {
            Resolve-PcIpv6Source -Destination $guestAddress
        } else { $null }
        $guestCheck = if ($pcCheck) {
            Resolve-AndroidIpv6Source -Serial $guestDevice `
                -Destination $pcCheck -ExpectedInterface $guestInterface
        } else { $null }
        if (-not $pcAddress -or $null -eq $pcInterfaceIndex -or
                -not $guestAddress -or $pcCheck -cne $pcAddress -or
                $guestCheck -cne $guestAddress -or
                -not (Test-DifferentIpv6Prefixes -First $pcAddress `
                    -Second $guestAddress)) {
            throw 'The PC Wi-Fi and Android cellular routes are not stable and distinct.'
        }
        if (-not (Test-PcPortAvailable) -or
                -not (Test-AndroidPortAvailable -Serial $guestDevice)) {
            $stage = 'verify_direct_port'
            throw 'The Direct gameplay probe port is already in use.'
        }
    }
    $windowsFirewallReady = Test-WindowsFirewallReady -Program $loveConsole `
        -InterfaceIndex $pcInterfaceIndex -Ports $directPorts `
        -RequireExactPortSet:($AndroidGuestCount -eq 2)
    if (-not $windowsFirewallReady) {
        $stage = 'verify_windows_firewall'
        throw 'Windows Firewall has no applicable inbound Direct probe allowance.'
    }
    if ($PacketCaptureValidation) {
        $stage = 'verify_packet_capture_preconditions'
        Assert-PktMonCapturePreflight | Out-Null
    }
    $preflightPassed = $true

    if (-not $PreflightOnly) {
        $stage = 'create_isolated_artifacts'
        New-Item -ItemType Directory -Path $temporaryParent -Force | Out-Null
        $temporaryRoot = Join-Path $temporaryParent $runId
        Assert-SafeTemporaryRoot -Path $temporaryRoot | Out-Null
        New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
        $stage = 'snapshot_base_package'
        $baseSnapshot = Join-Path $temporaryRoot 'base.love'
        $baseArtifact = Copy-VerifiedBasePackage -Destination $baseSnapshot
        $stage = 'create_pc_probe_package'
        $pcLove = New-ProbeLove -BaseSnapshot $baseSnapshot -Role host `
            -OutputPath (Join-Path $temporaryRoot 'pc-host.love') `
            -PlayerName $pcPlayerCanary `
            -Identity $pcIdentity -InstanceTag 'host' `
            -DirectPorts $directPorts `
            -ExpectedGuestNames ($AndroidGuestCount -eq 2 `
                ? $androidPlayerCanaries : @())
        if ($AndroidGuestCount -eq 2) {
            $guestLoveHashes = [System.Collections.Generic.List[string]]::new()
            foreach ($context in $guestContexts) {
                $stage = "create_android_probe_package_$($context.ordinal)"
                $guestLove = New-ProbeLove -BaseSnapshot $baseSnapshot `
                    -Role guest `
                    -OutputPath (Join-Path $temporaryRoot `
                        "android-guest-$($context.ordinal).love") `
                    -PlayerName $context.playerName -Identity $null `
                    -InstanceTag "guest-$($context.ordinal)" `
                    -GuestOrdinal $context.ordinal -DirectPorts $directPorts
                $guestLoveHashes.Add([string]$guestLove.sha256)
                $stage = "build_android_probe_package_$($context.ordinal)"
                $androidArtifact = Build-AndroidGuestApk `
                    -GuestLove $guestLove `
                    -InstanceTag "guest-$($context.ordinal)"
                $context.apk = $androidArtifact.path
            }
            if (@($guestLoveHashes | Sort-Object -Unique).Count -ne 2) {
                throw 'The two Android guest probe packages were not distinct.'
            }
            $guestLoveHashes.Clear()
        } else {
            $stage = 'create_android_probe_package'
            $guestLove = New-ProbeLove -BaseSnapshot $baseSnapshot -Role guest `
                -OutputPath (Join-Path $temporaryRoot 'android-guest.love') `
                -PlayerName $androidPlayerCanary `
                -Identity $null
            $stage = 'build_android_probe_package'
            $androidArtifact = Build-AndroidGuestApk -GuestLove $guestLove
        }
        $artifactSafetyVerified = $true

        $stage = $AndroidGuestCount -eq 2 `
            ? 'install_two_isolated_android_guests' `
            : 'install_isolated_android_guest'
        if ($AndroidGuestCount -eq 2) {
            foreach ($context in $guestContexts) {
                Install-AndroidGuest -Serial $context.serial -Apk $context.apk
            }
        } else {
            Install-AndroidGuest -Serial $guestDevice -Apk $androidArtifact.path
        }
        $androidInstalled = $true

        $stage = 'revalidate_routes_after_build'
        if ($AndroidGuestCount -eq 2) {
            foreach ($context in $guestContexts) {
                $pcAfter = Resolve-PcIpv6Source -Destination $context.address `
                    -Port $context.port
                $guestAfter = Resolve-AndroidIpv6Source `
                    -Serial $context.serial -Destination $context.pcAddress `
                    -ExpectedInterface $context.interface
                if ($pcAfter -cne $context.pcAddress -or
                        $guestAfter -cne $context.address -or
                        -not (Test-PcPortAvailable -Port $context.port) -or
                        -not (Test-AndroidPortAvailable -Serial $context.serial `
                            -Port $context.port)) {
                    throw 'A required two-guest route changed during the isolated build.'
                }
            }
        } else {
            $pcAfter = Resolve-PcIpv6Source -Destination $guestAddress
            $guestAfter = Resolve-AndroidIpv6Source -Serial $guestDevice `
                -Destination $pcAddress -ExpectedInterface $guestInterface
            if ($pcAfter -cne $pcAddress -or $guestAfter -cne $guestAddress -or
                    -not (Test-PcPortAvailable) -or
                    -not (Test-AndroidPortAvailable -Serial $guestDevice)) {
                throw 'The required routes changed during the isolated build.'
            }
        }
        $routesRevalidated = $true

        if ($PacketCaptureValidation) {
            $stage = 'start_private_packet_capture'
            Start-DirectPacketCapture
        }

        if ($AndroidGuestCount -eq 2) {
            $stage = 'full_game_two_guest_session'
            $multiGuestResult = Invoke-TwoGuestGameplaySession `
                -Guests $guestContexts -PcLove $pcLove.path
        } else {
            $stage = 'full_game_kick_session'
            $kickResult = Invoke-GameplaySession -Serial $guestDevice `
                -PcLove $pcLove.path -Ending kick
            if ($PacketCaptureValidation) {
                $captureEncodedCanaries = $kickResult.encodedPlayerCanary -and
                    $kickResult.encodedLoadingBayPlaintext -and
                    $kickResult.encodedCutterPlaintext
                if (-not $captureEncodedCanaries) {
                    $stage = 'verify_packet_capture_canaries'
                    throw 'The disposable game flow did not encode every capture canary.'
                }
                $stage = 'complete_private_packet_capture'
                $captureResult = Complete-DirectPacketCapture -RequireEvidence
            }

            $stage = 'full_game_graceful_session'
            $gracefulResult = Invoke-GameplaySession -Serial $guestDevice `
                -PcLove $pcLove.path -Ending graceful
        }
    }
} catch {
    $failure = $_
    $failureStage = $stage
    $failureClass = Get-FailureClass -FailureStage $stage
    $failureExceptionType = $_.Exception.GetType().Name
} finally {
    $stageBeforeCleanup = $stage
    $captureCleanupFailure = $null
    try {
        if ($PacketCaptureValidation -and
                ($captureActive -or $captureFilterOwned -or
                    $captureFilterMayRemain -or
                    ($captureEtlPath -and (Test-Path -LiteralPath $captureEtlPath)) -or
                    ($capturePcapPath -and (Test-Path -LiteralPath $capturePcapPath)))) {
            try {
                Complete-DirectPacketCapture | Out-Null
            } catch {
                $captureCleanupFailure = $_
            }
        }
        if ($pcProcessContext) {
            $stopped = Stop-PcHost -Context $pcProcessContext
            $pcProcessExited = [bool]$stopped.exited
            $pcProcessContext = $null
        }
        if ($AndroidGuestCount -eq 2 -and -not $PreflightOnly) {
            $allAndroidPackagesAbsent = $true
            foreach ($context in $guestContexts) {
                try {
                    Invoke-AdbBestEffort -Serial $context.serial `
                        -CommandArguments @(
                            'shell','am','force-stop',$guestPackage) | Out-Null
                    Invoke-AdbBestEffort -Serial $context.serial `
                        -CommandArguments @(
                            'uninstall',$guestPackage) | Out-Null
                    if (-not (Test-PackageAbsent -Serial $context.serial `
                                -Package $guestPackage)) {
                        $allAndroidPackagesAbsent = $false
                    }
                } catch {
                    $allAndroidPackagesAbsent = $false
                }
            }
            $androidPackageAbsent = $allAndroidPackagesAbsent
        } elseif ($guestDevice -and -not $PreflightOnly) {
            Invoke-AdbBestEffort -Serial $guestDevice -CommandArguments @(
                'shell','am','force-stop',$guestPackage) | Out-Null
            Invoke-AdbBestEffort -Serial $guestDevice -CommandArguments @(
                'uninstall',$guestPackage) | Out-Null
            $androidPackageAbsent = Test-PackageAbsent -Serial $guestDevice `
                -Package $guestPackage
        } else {
            $androidPackageAbsent = $true
        }
        Remove-SafeTree -Path $pcSaveRoot -Kind pc-save
        $pcIdentityRemoved = -not (Test-Path -LiteralPath $pcSaveRoot)
        if ($temporaryRoot -and
                (-not $PacketCaptureValidation -or
                    (-not $captureActive -and $captureStopped))) {
            Remove-SafeTree -Path $temporaryRoot -Kind temporary
        }
        $temporaryArtifactsRemoved = -not $temporaryRoot -or
            -not (Test-Path -LiteralPath $temporaryRoot)
        if ($PacketCaptureValidation -and $captureStopped -and
                $temporaryRoot -and $temporaryArtifactsRemoved -and
                (Test-ExternalCaptureFallbackAbsent)) {
            $captureArtifactsRemoved = $true
        }
        if ($PacketCaptureValidation -and
                -not (Test-ExternalCaptureFallbackAbsent)) {
            $captureArtifactsRemoved = $false
        }
        $cleanupVerified = $androidPackageAbsent -and $pcProcessExited -and
            $pcIdentityRemoved -and $temporaryArtifactsRemoved -and
            $captureStopped -and $captureFilterRemoved -and
            $captureArtifactsRemoved -and
            (-not $captureStartAttempted -or $captureOutputContained) -and
            -not $captureExternalArtifactDetected -and
            -not $captureCleanupFailure
        if ($captureCleanupFailure -and -not $failure) {
            $failure = $captureCleanupFailure
            $failureStage = 'packet_capture_cleanup'
            $failureClass = 'cleanup_verification'
            $failureExceptionType = $captureCleanupFailure.Exception.GetType().Name
        } elseif (-not $cleanupVerified -and -not $failure) {
            $failure = [System.Exception]::new(
                'Direct gameplay probe cleanup could not be verified.')
            $failureStage = 'cleanup'
            $failureClass = 'cleanup_verification'
            $failureExceptionType = $failure.GetType().Name
        }
    } catch {
        $cleanupVerified = $false
        if (-not $failure) {
            $failure = $_
            $failureStage = 'cleanup'
            $failureClass = 'cleanup_verification'
            $failureExceptionType = $_.Exception.GetType().Name
        }
    }
    $pcAddress = $null
    $guestAddress = $null
    $guestDevice = $null
    foreach ($context in $guestContexts) {
        foreach ($propertyName in @(
                'serial','interface','candidate','address','pcAddress',
                'playerName','processId','logBaseline','apk')) {
            $context.$propertyName = $null
        }
    }
    $pcPlayerCanary = $null
    $androidPlayerCanary = $null
    $androidPlayerCanaries = @()
}

if ($PreflightOnly) {
    $reportSensitiveValues.Clear()
    Release-ProbeMutex
    if ($failure) {
        throw "PC/Android Direct preflight failed at stage '$failureStage'."
    }
    Write-Output ($AndroidGuestCount -eq 2 `
        ? 'PC_TWO_ANDROID_DIRECT_PREFLIGHT=PASS' `
        : 'PC_ANDROID_DIRECT_PREFLIGHT=PASS')
    Write-Output 'PRODUCTION_READY=False'
    return
}

$gameplayAccepted = if ($AndroidGuestCount -eq 2) {
    [bool]($multiGuestResult -and
        $multiGuestResult.sequentialFreshInvitations -and
        $multiGuestResult.explicitHostApprovals -and
        $multiGuestResult.authenticatedNativeOpenings -and
        $multiGuestResult.snapshotsAppliedToBothGuests -and
        $multiGuestResult.hostObservedBothGuestMovements -and
        $multiGuestResult.threePlayerHudEverywhere -and
        $multiGuestResult.firstGuestHudKick -and
        $multiGuestResult.secondGuestSurvivedKick -and
        $multiGuestResult.secondGuestGracefulExit -and
        $multiGuestResult.hostReturnedToOneOfFour -and
        $multiGuestResult.logsSecretFree)
} else {
    [bool]($kickResult -and $gracefulResult)
}
$passed = $null -eq $failure -and $cleanupVerified -and
    $artifactSafetyVerified -and $routesRevalidated -and $gameplayAccepted -and
    (-not $PacketCaptureValidation -or
        ($captureResult -and $captureEncodedCanaries -and
            $captureResult.bidirectionalDirectBridgeFrames -and
            $captureResult.invitationSecretRepresentationsAbsent -and
            $captureResult.playerNamesAbsent -and
            $captureResult.shopGameplayPlaintextAbsent))
$captureResidualPossible = [bool]($PacketCaptureValidation -and
    ($captureExternalArtifactDetected -or
        ($captureStartAttempted -and
            (-not $captureStopped -or -not $captureArtifactsRemoved -or
                -not $captureOutputContained))))
$report = [ordered]@{
    schemaVersion = if ($AndroidGuestCount -eq 2) { 2 } `
        elseif ($PacketCaptureValidation) { 3 } else { 1 }
    artifactKind = if ($AndroidGuestCount -eq 2) {
        'windows-two-android-direct-gameplay-engineering-probe'
    } elseif ($PacketCaptureValidation) {
        'windows-android-direct-packet-capture-engineering-probe'
    } else {
        'windows-android-direct-gameplay-engineering-probe'
    }
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    result = $passed ? 'passed' : 'failed'
    failureStage = $passed ? $null : $failureStage
    failureClass = $passed ? $null : $failureClass
    failureExceptionType = $passed ? $null : $failureExceptionType
    productionReady = $false
    engineeringOnly = $true
    topology = if ($AndroidGuestCount -eq 2) {
        [ordered]@{
            androidGuestCount = 2
            androidGlobalIpv6CandidateCount = 2
            acceptanceTopologyOneWifiOneCellularGuest =
                [bool]$multiTopologyRouteMix
            uniqueAndroidAddresses = [bool]$multiTopologyUniqueAddresses
            sharedVerifiedPcWifiSource = [bool]$multiTopologySharedPcSource
            atLeastOneGuestOnDistinctIpv6Prefix =
                [bool]$multiTopologyAtLeastOneDistinctPrefix
            exactDirectPortCount = $directPorts.Count
            sourcesRevalidatedAfterBuild = [bool]$routesRevalidated
            exactTwoPortWindowsFirewallPreflight = [bool]$windowsFirewallReady
            firewallRulesMutatedByProbe = $false
        }
    } else {
        [ordered]@{
            pcRole = 'host'
            pcRoute = 'wifi_global_ipv6'
            androidRole = 'guest'
            androidRoute = 'cellular_global_ipv6'
            distinctIpv6Prefixes = [bool]$preflightPassed
            sourcesRevalidatedAfterBuild = [bool]$routesRevalidated
            windowsFirewallPreflight = [bool]$windowsFirewallReady
        }
    }
    privacy = [ordered]@{
        endpointRecorded = $false
        deviceSerialRecorded = $false
        invitationCodesRecorded = $false
        keysOrPacketsRecorded = $captureResidualPossible
        rawLogsRecorded = $false
        processLogsSecretFree = if ($AndroidGuestCount -eq 2) {
            [bool]($multiGuestResult -and $multiGuestResult.logsSecretFree)
        } else {
            [bool]($kickResult -and $gracefulResult -and
                $kickResult.logsSecretFree -and $gracefulResult.logsSecretFree)
        }
        packetCaptureRetained = $captureResidualPossible
        packetEndpointsRetained = $captureResidualPossible
    }
    acceptance = if ($AndroidGuestCount -eq 2) {
        [ordered]@{
            sequentialFreshInvitations = [bool]($multiGuestResult -and
                $multiGuestResult.sequentialFreshInvitations)
            explicitHostApprovalForEachGuest = [bool]($multiGuestResult -and
                $multiGuestResult.explicitHostApprovals)
            authenticatedNativeOpeningForEachGuest = [bool]($multiGuestResult -and
                $multiGuestResult.authenticatedNativeOpenings)
            protocolSnapshotAppliedToBothGuests = [bool]($multiGuestResult -and
                $multiGuestResult.snapshotsAppliedToBothGuests)
            hostObservedBothGuestMovements = [bool]($multiGuestResult -and
                $multiGuestResult.hostObservedBothGuestMovements)
            directHudThreeOfFourEverywhere = [bool]($multiGuestResult -and
                $multiGuestResult.threePlayerHudEverywhere)
            firstGuestKickedByUniqueCanary = [bool]($multiGuestResult -and
                $multiGuestResult.firstGuestHudKick)
            secondGuestActiveAfterKickAtTwoOfFour = [bool]($multiGuestResult -and
                $multiGuestResult.secondGuestSurvivedKick)
            survivingGuestGracefulExit = [bool]($multiGuestResult -and
                $multiGuestResult.secondGuestGracefulExit)
            hostReturnedToOneOfFour = [bool]($multiGuestResult -and
                $multiGuestResult.hostReturnedToOneOfFour)
        }
    } else { [ordered]@{
        twoFreshTwoCodePlayerFlows = [bool]($kickResult -and $gracefulResult)
        explicitHostApproval = [bool]($kickResult -and $gracefulResult -and
            $kickResult.explicitHostApproval -and
            $gracefulResult.explicitHostApproval)
        authenticatedNativeOpening = [bool]($kickResult -and $gracefulResult -and
            $kickResult.nativeOpening -and $gracefulResult.nativeOpening)
        protocolSnapshotApplied = [bool]($kickResult -and $gracefulResult -and
            $kickResult.snapshotApplied -and $gracefulResult.snapshotApplied)
        directHudTwoOfFour = [bool]($kickResult -and $gracefulResult -and
            $kickResult.directHudTwo -and $gracefulResult.directHudTwo)
        remoteMovement = [bool]($kickResult -and $gracefulResult -and
            $kickResult.movement -and $gracefulResult.movement)
        loadingBayInteraction = [bool]($kickResult -and $gracefulResult -and
            $kickResult.bayInteraction -and $gracefulResult.bayInteraction)
        remoteCutterSafetyAction = [bool]($kickResult -and $gracefulResult -and
            $kickResult.cutterAction -and $gracefulResult.cutterAction)
        hostHudKick = [bool]($kickResult -and $kickResult.hostKick)
        androidGuestObservedKick = [bool]($kickResult -and $kickResult.guestKicked)
        hostObservedKickDisconnect = [bool]($kickResult -and
            $kickResult.hostDisconnect)
        androidGuestGracefulExit = [bool]($gracefulResult -and
            $gracefulResult.guestGraceful)
        hostObservedGracefulDisconnect = [bool]($gracefulResult -and
            $gracefulResult.hostDisconnect)
    } }
    serviceIndependence = [ordered]@{
        accountRequired = $false
        matchmakingServiceUsed = $false
        relayServiceUsed = $false
        thirdPartyGameplayServiceUsed = $false
    }
    packetCapture = [ordered]@{
        requested = [bool]$PacketCaptureValidation
        tool = $PacketCaptureValidation ? 'windows_pktmon' : $null
        filterAddAttempted = [bool]($PacketCaptureValidation -and
            $captureFilterAddAttempted)
        filterMayRemain = [bool]($PacketCaptureValidation -and
            $captureFilterMayRemain -and -not $captureFilterRemoved)
        filterOwnershipFingerprintScheme =
            ($PacketCaptureValidation -and $captureFilterMayRemain -and
             -not $captureFilterRemoved) `
                ? 'sha256-canonical-filter-name-v1' : $null
        filterOwnershipSha256 =
            ($PacketCaptureValidation -and $captureFilterMayRemain -and
             -not $captureFilterRemoved) `
                ? $captureFilterFingerprint : $null
        nicOnly = [bool]($PacketCaptureValidation -and $captureResult)
        ipv6UdpDirectPortOnly = [bool]($PacketCaptureValidation -and $captureResult)
        fullPacketBytesRequested = [bool]($PacketCaptureValidation -and $captureResult)
        outputContract = $PacketCaptureValidation `
            ? 'private-working-directory-pktmon-etl-v1' : $null
        outputContained = [bool]($PacketCaptureValidation -and
            $captureOutputContained -and -not $captureExternalArtifactDetected)
        outsideFallbackDetected = [bool]($PacketCaptureValidation -and
            $captureExternalArtifactDetected)
        encodedCanariesConfirmed = [bool]$captureEncodedCanaries
        bidirectionalDirectBridgeFrames = [bool]($captureResult -and
            $captureResult.bidirectionalDirectBridgeFrames)
        invitationSecretRepresentationsAbsent = [bool]($captureResult -and
            $captureResult.invitationSecretRepresentationsAbsent)
        playerNamesAbsent = [bool]($captureResult -and
            $captureResult.playerNamesAbsent)
        shopGameplayPlaintextAbsent = [bool]($captureResult -and
            $captureResult.shopGameplayPlaintextAbsent)
        rawCaptureRetained = $captureResidualPossible
        endpointRetained = $captureResidualPossible
    }
    artifactSafety = [ordered]@{
        isolatedPcSaveIdentity = [bool]$artifactSafetyVerified
        isolatedAndroidApplicationId = [bool]$artifactSafetyVerified
        normalProviderGateClosed = [bool]$artifactSafetyVerified
        productionGateUnchanged = $true
    }
    cleanup = [ordered]@{
        androidEngineeringPackageAbsent = [bool]$androidPackageAbsent
        pcHostProcessExited = [bool]$pcProcessExited
        isolatedPcSaveRemoved = [bool]$pcIdentityRemoved
        packetCaptureStopped = [bool]$captureStopped
        packetCaptureFilterRemoved = [bool]$captureFilterRemoved
        packetCaptureArtifactsRemoved = [bool]$captureArtifactsRemoved
        outsideFallbackAbsent = [bool](-not $captureExternalArtifactDetected)
        sensitiveTemporaryArtifactsRemoved = [bool]$temporaryArtifactsRemoved
        verified = [bool]$cleanupVerified
    }
}

$target = $passed ? $evidencePath : $pendingPath
try {
    Assert-ReportSecretFree -Value $report | Out-Null
    if (-not ($preserveExistingPendingReport -and -not $passed)) {
        Write-AtomicJsonReport -Path $target -Value $report
    }
} finally {
    $reportSensitiveValues.Clear()
    Release-ProbeMutex
}

if (-not $passed) {
    throw "PC/Android Direct gameplay acceptance failed at stage '$failureStage'."
}

if ($AndroidGuestCount -eq 2) {
    Write-Output 'PC_TWO_ANDROID_DIRECT_GAMEPLAY=PASS'
    Write-Output 'SEQUENTIAL_FRESH_INVITATIONS=True'
    Write-Output 'EXPLICIT_HOST_APPROVAL_FOR_EACH_GUEST=True'
    Write-Output 'THREE_PLAYER_HUD_EVERYWHERE=True'
    Write-Output 'FIRST_GUEST_HUD_KICK=True'
    Write-Output 'SECOND_GUEST_SURVIVED_KICK=True'
    Write-Output 'SURVIVING_GUEST_GRACEFUL_DISCONNECT=True'
    Write-Output 'HOST_RETURNED_TO_ONE_OF_FOUR=True'
} else {
    Write-Output 'PC_ANDROID_DIRECT_GAMEPLAY=PASS'
    Write-Output 'EXPLICIT_HOST_APPROVAL=True'
    Write-Output 'HOST_HUD_KICK=True'
    Write-Output 'GUEST_GRACEFUL_DISCONNECT=True'
}
Write-Output 'PROCESS_LOGS_SECRET_FREE=True'
if ($PacketCaptureValidation) {
    Write-Output 'PACKET_CAPTURE_PRIVACY=PASS'
    Write-Output 'RAW_PACKET_CAPTURE_RETAINED=False'
}
Write-Output 'PRODUCTION_READY=False'
Write-Output "REPORT=$evidencePath"
