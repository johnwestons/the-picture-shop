[CmdletBinding()]
param(
    [ValidateSet('Inspect','Recover')]
    [string]$Action = 'Inspect'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem
$recoverRequested = $Action -ieq 'Recover'

$legacyFilterName = 'TPSDirectCapture'
$legacyFilterRetirementUtc = [DateTimeOffset]::Parse(
    '2026-08-31T07:30:00Z',
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::RoundtripKind).UtcDateTime
$projectRoot = Split-Path $PSScriptRoot -Parent
$pendingReport = Join-Path $projectRoot `
    'output\native-crypto\device-tests\pc_android_direct_packet_capture_report.pending.json'
$recoveryReport = Join-Path $projectRoot `
    'output\native-crypto\device-tests\pc_android_direct_packet_capture_recovery.json'
$rootFallbackPath = [IO.Path]::GetFullPath(
    (Join-Path $projectRoot 'PktMon.etl'))
$captureParent = [IO.Path]::GetFullPath((Join-Path `
    ([IO.Path]::GetTempPath()) 'ThePictureShop\pc-android-direct-gameplay'))
$mutexName = 'Local\ThePictureShopPcAndroidDirectGameplayProbe'
$pktmon = Join-Path $env:SystemRoot 'System32\PktMon.exe'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-PktMonInternal {
    param(
        [Parameter(Mandatory=$true)][string[]]$CommandArguments,
        [string]$WorkingDirectory
    )
    if ($WorkingDirectory) {
        $workingRoot = [IO.Path]::GetFullPath($WorkingDirectory)
        if (-not (Test-Path -LiteralPath $workingRoot -PathType Container)) {
            throw 'private_capture_working_directory_missing'
        }
        $workingItem = Get-Item -LiteralPath $workingRoot -Force
        if (($workingItem.Attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'private_capture_working_directory_unsafe'
        }
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $pktmon
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
            if (-not $process.Start()) { throw 'pktmon_launch_failed' }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $stdout = $stdoutTask.GetAwaiter().GetResult().TrimEnd()
            $stderr = $stderrTask.GetAwaiter().GetResult().TrimEnd()
            return [pscustomobject]@{
                exitCode = $process.ExitCode
                output = [string](@($stdout,$stderr) |
                    Where-Object { $_ } | Join-String -Separator "`n")
            }
        } finally {
            $process.Dispose()
        }
    }
    $commandOutput = @(& $pktmon @CommandArguments 2>&1) -join "`n"
    return [pscustomobject]@{
        exitCode = $LASTEXITCODE
        output = [string]$commandOutput
    }
}

function Get-FilterRowCount {
    param([AllowEmptyString()][string]$Value)
    return ([regex]::Matches($Value,
        '(?im)^\s*(?:filter\s+)?\d+(?:\s+|[.:)]|-)')).Count
}

function Get-FilterRowNames {
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

function Normalize-PktMonText {
    param([AllowEmptyString()][string]$Value)
    return (($Value -replace "`r`n","`n").Trim())
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

function Test-PathWithin {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Parent
    )
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($Parent).TrimEnd('\')
    return $full.StartsWith($root + '\',
        [StringComparison]::OrdinalIgnoreCase)
}

function Write-SafeResult {
    param([Parameter(Mandatory=$true)]$Value)
    $Value | ConvertTo-Json -Depth 5 -Compress | Write-Output
}

$runMutex = $null
$mutexOwned = $false
$recoveryCaptureStopped = $false
$recoveryFilterRemoved = $false
$recoveryArtifactsRemoved = $false
$recoveryFilterRemovalAttempted = $false
$outsideFallbackPresent = $false
try {
    if (-not (Test-IsAdministrator)) {
        if ($recoverRequested) {
            Write-SafeResult ([ordered]@{
                recover = 'blocked'
                reason = 'administrator_required'
            })
        } else {
            Write-SafeResult ([ordered]@{
                inspect = 'blocked'
                reason = 'administrator_required'
            })
        }
        return
    }
    if (-not (Test-Path -LiteralPath $pktmon -PathType Leaf)) {
        throw 'pktmon_unavailable'
    }

    $runMutex = [Threading.Mutex]::new($false,$mutexName)
    try {
        $mutexOwned = $runMutex.WaitOne(0)
    } catch [Threading.AbandonedMutexException] {
        $mutexOwned = $true
    }
    if (-not $mutexOwned) { throw 'probe_still_running' }

    if (-not (Test-Path -LiteralPath $pendingReport -PathType Leaf)) {
        throw 'pending_report_missing'
    }
    $pendingHashBefore = (Get-FileHash -Algorithm SHA256 `
        -LiteralPath $pendingReport).Hash.ToLowerInvariant()
    $report = Get-Content -Raw -LiteralPath $pendingReport | ConvertFrom-Json
    $pendingHash = (Get-FileHash -Algorithm SHA256 `
        -LiteralPath $pendingReport).Hash.ToLowerInvariant()
    if ($pendingHashBefore -cne $pendingHash) {
        throw 'pending_report_changed'
    }
    $pendingBaseMatched = $report.schemaVersion -in @(2,3) -and
        $report.artifactKind -ceq
            'windows-android-direct-packet-capture-engineering-probe' -and
        $report.result -ceq 'failed' -and
        $report.packetCapture.requested -eq $true
    $legacyPendingContract = $report.schemaVersion -eq 2 -and
        $report.failureStage -ceq 'start_private_packet_capture' -and
        $report.cleanup.packetCaptureStopped -eq $false -and
        $report.cleanup.packetCaptureFilterRemoved -eq $false -and
        $report.cleanup.packetCaptureArtifactsRemoved -eq $false -and
        $report.cleanup.sensitiveTemporaryArtifactsRemoved -eq $false -and
        $report.packetCapture.rawCaptureRetained -eq $true
    $futureFailureStages = @(
        'start_private_packet_capture',
        'full_game_kick_session',
        'verify_packet_capture_canaries',
        'complete_private_packet_capture',
        'full_game_graceful_session',
        'packet_capture_cleanup',
        'cleanup'
    )
    $futurePendingContract = $report.schemaVersion -eq 3 -and
        $report.failureStage -cin $futureFailureStages -and
        $report.packetCapture.outputContract -ceq
            'private-working-directory-pktmon-etl-v1' -and
        $report.packetCapture.rawCaptureRetained -eq $true -and
        $report.packetCapture.endpointRetained -eq $true -and
        $report.cleanup.verified -eq $false -and
        ($report.cleanup.packetCaptureStopped -eq $false -or
         $report.cleanup.packetCaptureFilterRemoved -eq $false -or
         $report.cleanup.packetCaptureArtifactsRemoved -eq $false -or
         $report.cleanup.sensitiveTemporaryArtifactsRemoved -eq $false)
    $pendingMatched = $pendingBaseMatched -and
        ($legacyPendingContract -xor $futurePendingContract)
    if (-not $pendingMatched) { throw 'pending_report_state_mismatch' }
    $outsideFallbackPresent = Test-Path -LiteralPath $rootFallbackPath

    $allDirectories = @()
    if (Test-Path -LiteralPath $captureParent -PathType Container) {
        $captureParentItem = Get-Item -LiteralPath $captureParent -Force
        if (($captureParentItem.Attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'private_capture_parent_not_safe'
        }
        $allDirectories = @(Get-ChildItem -LiteralPath $captureParent `
            -Directory -Force)
    }
    $captureDirectories = @($allDirectories | Where-Object {
        $_.Name -match '^[0-9a-f]{32}$' -and
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
    })
    if ($allDirectories.Count -ne 1 -or $captureDirectories.Count -ne 1) {
        throw 'private_capture_directory_not_unique'
    }

    $captureDirectory = $captureDirectories[0]
    $uniqueFilterName = 'TPS_' +
        $captureDirectory.Name.Substring(0,20)
    $reportFilterOwnershipMatched = $report.schemaVersion -eq 2
    $reportFilterAbsentContractMatched = $false
    $reportFilterContractMatched = $report.schemaVersion -eq 2
    if ($report.schemaVersion -eq 3) {
        $packetProperties = $report.packetCapture.PSObject.Properties
        $fingerprintProperty =
            $packetProperties['filterOwnershipSha256']
        $schemeProperty =
            $packetProperties['filterOwnershipFingerprintScheme']
        $filterMayRemainProperty = $packetProperties['filterMayRemain']
        $expectedFingerprint = Get-LowerSha256Text -Value $uniqueFilterName
        $reportFilterOwnershipMatched = $fingerprintProperty -and
            ([string]$fingerprintProperty.Value) -cmatch '^[0-9a-f]{64}$' -and
            ([string]$fingerprintProperty.Value) -ceq $expectedFingerprint -and
            $schemeProperty -and $schemeProperty.Value -ceq
                'sha256-canonical-filter-name-v1' -and
            $filterMayRemainProperty -and
                $filterMayRemainProperty.Value -eq $true
        $reportFilterAbsentContractMatched = $filterMayRemainProperty -and
            $filterMayRemainProperty.Value -eq $false -and
            -not $fingerprintProperty -and -not $schemeProperty -and
            $report.cleanup.packetCaptureFilterRemoved -eq $true
        $reportFilterContractMatched = $reportFilterOwnershipMatched -or
            $reportFilterAbsentContractMatched
        $expectedFingerprint = $null
    }
    $treeItems = @(Get-ChildItem -LiteralPath $captureDirectory.FullName `
        -Recurse -Force)
    $treeSafe = @($treeItems | Where-Object {
        -not (Test-PathWithin -Path $_.FullName `
            -Parent $captureDirectory.FullName) -or
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    }).Count -eq 0
    if (-not $treeSafe) { throw 'private_capture_tree_not_safe' }

    $pcPackage = Join-Path $captureDirectory.FullName 'pc-host.love'
    $guestPackage = Join-Path $captureDirectory.FullName 'android-guest.love'
    $basePackage = Join-Path $captureDirectory.FullName 'base.love'
    $buildReport = Join-Path $captureDirectory.FullName `
        'mobile\artifacts\direct-transport-probe-client-apk-report.json'
    $packageMarkersPresent =
        (Test-Path -LiteralPath $pcPackage -PathType Leaf) -and
        (Test-Path -LiteralPath $guestPackage -PathType Leaf) -and
        (Test-Path -LiteralPath $basePackage -PathType Leaf) -and
        (Test-Path -LiteralPath $buildReport -PathType Leaf)
    if (-not $packageMarkersPresent) { throw 'private_probe_markers_missing' }

    $archiveIdentityMatched = $false
    $archiveProbeConfigMatched = $false
    $archive = [IO.Compression.ZipFile]::OpenRead($pcPackage)
    try {
        $confEntries = @($archive.Entries | Where-Object {
            $_.FullName -ceq 'conf.lua'
        })
        $configEntries = @($archive.Entries | Where-Object {
            $_.FullName -ceq 'direct_gameplay_probe_config.lua'
        })
        if ($confEntries.Count -eq 1) {
            $reader = [IO.StreamReader]::new($confEntries[0].Open())
            try { $confText = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $expectedIdentity = 'the-picture-shop-pc-probe-' +
                $captureDirectory.Name
            $archiveIdentityMatched = ([regex]::Matches($confText,
                [regex]::Escape('t.identity = "' + $expectedIdentity + '"'))).Count -eq 1
        }
        if ($configEntries.Count -eq 1) {
            $reader = [IO.StreamReader]::new($configEntries[0].Open())
            try { $configText = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $expectedCanary = 'TPSPC' + $captureDirectory.Name.Substring(0,19)
            $archiveProbeConfigMatched = $configText -match
                ('(?s)^return\s*\{\s*role\s*=\s*"host",\s*' +
                 'playerName\s*=\s*"' + [regex]::Escape($expectedCanary) +
                 '",\s*\}\s*$')
        }
    } finally {
        $archive.Dispose()
    }
    if (-not $archiveIdentityMatched -or -not $archiveProbeConfigMatched) {
        throw 'private_probe_identity_mismatch'
    }

    $etlLeaf = $report.schemaVersion -eq 3 ? 'PktMon.etl' : 'direct-private.etl'
    $etlPath = [IO.Path]::GetFullPath(
        (Join-Path $captureDirectory.FullName $etlLeaf))
    $pcapPath = [IO.Path]::GetFullPath(
        (Join-Path $captureDirectory.FullName 'direct-private.pcapng'))
    if (-not (Test-PathWithin -Path $etlPath -Parent $captureDirectory.FullName) -or
            -not (Test-PathWithin -Path $pcapPath -Parent $captureDirectory.FullName)) {
        throw 'private_capture_path_not_contained'
    }

    $etlPresent = Test-Path -LiteralPath $etlPath -PathType Leaf
    $pcapPresent = Test-Path -LiteralPath $pcapPath -PathType Leaf
    $status = Invoke-PktMonInternal -CommandArguments @('status')
    $filters = Invoke-PktMonInternal -CommandArguments @('filter','list')
    $inactivePattern =
        '(?im)^[^\r\n]*(?:not\s+running|stopped|inactive|no\s+active)[^\r\n]*$'
    $statusInactive = $status.exitCode -eq 0 -and
        $status.output -match $inactivePattern
    $statusNotInactive = $status.exitCode -eq 0 -and -not $statusInactive
    $statusFullPathMatch = $status.exitCode -eq 0 -and
        $status.output.IndexOf($etlPath,
            [StringComparison]::OrdinalIgnoreCase) -ge 0
    $statusMentionsQualifiedEtl = $status.exitCode -eq 0 -and
        $status.output -match
            '(?i)(?:[A-Z]:\\|[/\\])[^\r\n]*\.etl(?:\s|$|["''])'
    $statusUnqualifiedLeafMatch = $status.exitCode -eq 0 -and
        -not $statusMentionsQualifiedEtl -and
        $status.output -match
            ('(?i)(?<![A-Za-z0-9_.-])' +
             [regex]::Escape($etlLeaf) + '(?![A-Za-z0-9_.-])')
    $statusFileNameMatch = $statusFullPathMatch -or
        $statusUnqualifiedLeafMatch
    $statusMentionsAnyEtl = $status.exitCode -eq 0 -and
        $status.output -match '(?i)\.etl(?:\s|$|["''])'
    $statusLoggerMatched = $status.exitCode -eq 0 -and
        $status.output -match '(?im)logger\s+name\s*:\s*pktmon\s*$'
    $statusMemoryModeMatched = $status.exitCode -eq 0 -and
        $status.output -match '(?im)(?:logging|log)\s+mode\s*:\s*memory\s*$'
    $statusFileSizeMatched = $status.exitCode -eq 0 -and
        $status.output -match '(?im)(?:max(?:imum)?\s+)?file\s+size\s*:\s*64\s*(?:mb)?\s*$'
    $statusPacketCaptureMatched = $status.exitCode -eq 0 -and
        $status.output -match '(?i)packet\s+capture'
    $statusAllPacketsMatched = $status.exitCode -eq 0 -and
        $status.output -match '(?i)all\s+packets'
    $statusNicsMatched = $status.exitCode -eq 0 -and
        $status.output -match '(?i)\bnics\b|network\s+adapters?'
    $statusCaptureConfigurationMatched = $statusLoggerMatched -and
        $statusMemoryModeMatched -and $statusFileSizeMatched -and
        $statusPacketCaptureMatched -and $statusAllPacketsMatched -and
        $statusNicsMatched

    $completedValue = $report.completedAtUtc
    $completedUtc = if ($completedValue -is [DateTime]) {
        $completedValue.ToUniversalTime()
    } else {
        [DateTime]::Parse([string]$completedValue,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    }

    $filterRowNames = @()
    if ($filters.exitCode -eq 0) {
        $filterRowNames = @(Get-FilterRowNames -Value $filters.output)
    }
    $filterRowCount = if ($filters.exitCode -eq 0) {
        Get-FilterRowCount -Value $filters.output
    } else { -1 }
    $legacyFilterAllowed = $report.schemaVersion -eq 2 -and
        $completedUtc -lt $legacyFilterRetirementUtc
    $filterIdentityClass = if ($filterRowCount -eq 1 -and
            $filterRowNames.Count -eq $filterRowCount -and
            $filterRowNames[0] -ceq $uniqueFilterName) {
        'derived_unique'
    } elseif ($filterRowCount -eq 1 -and
            $filterRowNames.Count -eq $filterRowCount -and
            $filterRowNames[0] -ceq $legacyFilterName -and
            $legacyFilterAllowed) {
        'legacy_pre_retirement'
    } else { 'unrecognized' }
    $filterName = if ($filterIdentityClass -in @(
            'derived_unique','legacy_pre_retirement')) {
        $filterRowNames[0]
    } else { $null }
    $ownedFilterMentions = if ($filterName) { 1 } else { 0 }
    $filterIpv6Matched = $filters.exitCode -eq 0 -and
        $filters.output -match '(?i)\bIPv6\b'
    $filterUdpMatched = $filters.exitCode -eq 0 -and
        $filters.output -match '(?i)\bUDP\b'
    $filterPortMatched = $filters.exitCode -eq 0 -and
        $filters.output -match '(?<!\d)57842(?!\d)'
    $exclusiveOwnedFilter = $filters.exitCode -eq 0 -and
        $filterRowCount -eq 1 -and $ownedFilterMentions -eq 1 -and
        $filters.output -notmatch '(?im)^\s*none\.?\s*$' -and
        $filterIpv6Matched -and $filterUdpMatched -and $filterPortMatched -and
        $reportFilterOwnershipMatched
    $filterListEmpty = $filters.exitCode -eq 0 -and
        $filterRowCount -eq 0 -and
        $filters.output -match '(?im)^\s*none\.?\s*$'

    $pendingAgeMinutes = ([DateTime]::UtcNow - $completedUtc).TotalMinutes
    $artifactAgeMinutes = ([DateTime]::UtcNow -
        (Get-Item -LiteralPath $buildReport).LastWriteTimeUtc).TotalMinutes
    $recentPendingReport = $pendingAgeMinutes -ge -5 -and
        $pendingAgeMinutes -le 120
    $recentRunArtifact = $artifactAgeMinutes -ge -5 -and
        $artifactAgeMinutes -le 120

    $recoveryClass = 'ambiguous'
    if (-not $outsideFallbackPresent -and
            $statusInactive -and $exclusiveOwnedFilter -and
            $recentPendingReport -and $recentRunArtifact -and
            $archiveIdentityMatched -and $archiveProbeConfigMatched) {
        $recoveryClass = 'inactive_owned_filter'
    } elseif (-not $outsideFallbackPresent -and
            $statusInactive -and $filterListEmpty -and
            ($report.schemaVersion -eq 2 -or
                $reportFilterAbsentContractMatched) -and
            $recentPendingReport -and $recentRunArtifact -and
            $archiveIdentityMatched -and $archiveProbeConfigMatched) {
        # This supports an idempotent retry after the owned global filter was
        # removed but a later verification or private-tree deletion failed.
        # No global PktMon mutation is necessary in this state.
        $recoveryClass = 'inactive_no_filter_private_tree'
    } elseif (-not $outsideFallbackPresent -and
            $statusNotInactive -and $exclusiveOwnedFilter -and
            $statusFullPathMatch -and $statusCaptureConfigurationMatched -and
            $recentPendingReport -and $recentRunArtifact -and
            $archiveIdentityMatched -and $archiveProbeConfigMatched) {
        $recoveryClass = 'active_exact_path'
    } elseif (-not $outsideFallbackPresent -and
            $statusNotInactive -and $exclusiveOwnedFilter -and
            $statusLoggerMatched -and $statusPacketCaptureMatched -and
            $statusAllPacketsMatched -and $statusNicsMatched -and
            -not $statusMentionsAnyEtl -and
            $recentPendingReport -and $recentRunArtifact -and
            $archiveIdentityMatched -and $archiveProbeConfigMatched) {
        $recoveryClass = 'active_owned_context'
    }

    if ($recoverRequested) {
        if ($outsideFallbackPresent) {
            throw 'uncontained_capture_artifact_present'
        }
        if ($recoveryClass -notin @(
                'active_exact_path','active_owned_context','inactive_owned_filter',
                'inactive_no_filter_private_tree')) {
            throw 'recovery_ownership_not_proven'
        }

        $filterSnapshot = Normalize-PktMonText -Value $filters.output
        $verifyStatus = Invoke-PktMonInternal -CommandArguments @('status')
        $verifyFilters = Invoke-PktMonInternal -CommandArguments @('filter','list')
        $verifyInactive = $verifyStatus.exitCode -eq 0 -and
            $verifyStatus.output -match $inactivePattern
        $verifyNotInactive = $verifyStatus.exitCode -eq 0 -and
            -not $verifyInactive
        $verifyActiveStructure = $verifyNotInactive -and
            $verifyStatus.output -match
                '(?im)logger\s+name\s*:\s*pktmon\s*$' -and
            $verifyStatus.output -match '(?i)packet\s+capture' -and
            $verifyStatus.output -match '(?i)all\s+packets' -and
            $verifyStatus.output -match
                '(?i)\bnics\b|network\s+adapters?'
        $verifyMentionsAnyEtl = $verifyStatus.exitCode -eq 0 -and
            $verifyStatus.output -match '(?i)\.etl(?:\s|$|["''])'
        $verifyExpectedPath = $verifyStatus.exitCode -eq 0 -and
            $verifyStatus.output.IndexOf($etlPath,
                [StringComparison]::OrdinalIgnoreCase) -ge 0
        $verifyFullConfiguration = $verifyActiveStructure -and
            $verifyStatus.output -match
                '(?im)(?:logging|log)\s+mode\s*:\s*memory\s*$' -and
            $verifyStatus.output -match
                '(?im)(?:max(?:imum)?\s+)?file\s+size\s*:\s*64\s*(?:mb)?\s*$'
        $verifyFilterUnchanged = $verifyFilters.exitCode -eq 0 -and
            (Normalize-PktMonText -Value $verifyFilters.output) -ceq
                $filterSnapshot
        $verifyClassMatched = switch ($recoveryClass) {
            'inactive_owned_filter' { $verifyInactive; break }
            'inactive_no_filter_private_tree' { $verifyInactive; break }
            'active_exact_path' {
                $verifyActiveStructure -and $verifyExpectedPath -and
                    $verifyFullConfiguration
                break
            }
            'active_owned_context' {
                $verifyActiveStructure -and -not $verifyMentionsAnyEtl
                break
            }
            default { $false }
        }
        if (-not $verifyFilterUnchanged -or -not $verifyClassMatched) {
            throw 'recovery_state_changed'
        }

        $stopOutputCompatible = $verifyInactive
        if (-not $verifyInactive) {
            $stopped = Invoke-PktMonInternal -CommandArguments @('stop') `
                -WorkingDirectory $captureDirectory.FullName
            if ($stopped.exitCode -ne 0) { throw 'owned_capture_stop_failed' }
            $stopFullPathMatched = $stopped.output.IndexOf($etlPath,
                [StringComparison]::OrdinalIgnoreCase) -ge 0
            $stopMentionsAnyEtl = $stopped.output -match
                '(?i)\.etl(?:\s|$|["''])'
            $stopMentionsQualifiedEtl = $stopped.output -match
                '(?i)(?:[A-Z]:\\|[/\\])[^\r\n]*\.etl(?:\s|$|["''])'
            $stopUnqualifiedLeafMatched = -not $stopMentionsQualifiedEtl -and
                $stopped.output -match
                    ('(?i)(?<![A-Za-z0-9_.-])' +
                     [regex]::Escape($etlLeaf) + '(?![A-Za-z0-9_.-])')
            $stopOutputCompatible = -not $stopMentionsAnyEtl -or
                $stopFullPathMatched -or $stopUnqualifiedLeafMatched
        }
        $stoppedStatus = Invoke-PktMonInternal -CommandArguments @('status') `
            -WorkingDirectory $captureDirectory.FullName
        if ($stoppedStatus.exitCode -ne 0 -or
                $stoppedStatus.output -notmatch $inactivePattern) {
            throw 'owned_capture_stop_unverified'
        }
        $recoveryCaptureStopped = $true

        $captureFilesSafe = $true
        $stoppedEtlSafe = $false
        foreach ($capturePath in @($etlPath,$pcapPath)) {
            if (Test-Path -LiteralPath $capturePath) {
                if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) {
                    $captureFilesSafe = $false
                    break
                }
                $captureItem = Get-Item -LiteralPath $capturePath -Force
                $itemSafe =
                    (Test-PathWithin -Path $captureItem.FullName `
                        -Parent $captureDirectory.FullName) -and
                    ($captureItem.Attributes -band
                        [IO.FileAttributes]::ReparsePoint) -eq 0
                if (-not $itemSafe) {
                    $captureFilesSafe = $false
                    break
                }
                if ($capturePath -ceq $etlPath) { $stoppedEtlSafe = $true }
            }
        }
        if (-not $captureFilesSafe -or
                (-not $verifyInactive -and
                 (-not $stoppedEtlSafe -or
                  -not $stopOutputCompatible)) -or
                (Test-Path -LiteralPath $rootFallbackPath)) {
            throw 'owned_capture_output_unverified'
        }

        $afterStopFilters = Invoke-PktMonInternal `
            -CommandArguments @('filter','list')
        if ($afterStopFilters.exitCode -ne 0 -or
                (Normalize-PktMonText -Value $afterStopFilters.output) -cne
                    $filterSnapshot) {
            throw 'owned_filter_changed'
        }

        if ($recoveryClass -ceq 'inactive_no_filter_private_tree') {
            if (-not $filterListEmpty -or
                    $afterStopFilters.output -notmatch
                        '(?im)^\s*none\.?\s*$' -or
                    (Get-FilterRowCount -Value $afterStopFilters.output) -ne 0) {
                throw 'owned_filter_changed'
            }
            $recoveryFilterRemoved = $true
        } else {
            # PktMon's remove command is global. Recheck both the stopped state
            # and the byte-normalized sole owned filter immediately before it.
            $statusBeforeRemoval = Invoke-PktMonInternal `
                -CommandArguments @('status')
            $filtersBeforeRemoval = Invoke-PktMonInternal `
                -CommandArguments @('filter','list')
            if ($statusBeforeRemoval.exitCode -ne 0 -or
                    $statusBeforeRemoval.output -notmatch $inactivePattern -or
                    $filtersBeforeRemoval.exitCode -ne 0 -or
                    (Normalize-PktMonText -Value $filtersBeforeRemoval.output) -cne
                        $filterSnapshot) {
                throw 'owned_filter_changed'
            }

            $recoveryFilterRemovalAttempted = $true
            $removed = Invoke-PktMonInternal `
                -CommandArguments @('filter','remove')
            if ($removed.exitCode -ne 0) {
                throw 'owned_filter_removal_failed'
            }
            $emptyFilters = Invoke-PktMonInternal `
                -CommandArguments @('filter','list')
            if ($emptyFilters.exitCode -ne 0 -or
                    $emptyFilters.output -notmatch '(?im)^\s*none\.?\s*$' -or
                    (Get-FilterRowCount -Value $emptyFilters.output) -ne 0 -or
                    $emptyFilters.output -match [regex]::Escape($filterName)) {
                throw 'owned_filter_removal_unverified'
            }
            $recoveryFilterRemoved = $true
        }

        $currentRoot = Get-Item -LiteralPath $captureDirectory.FullName -Force
        if ($currentRoot.FullName -cne $captureDirectory.FullName -or
                -not (Test-PathWithin -Path $currentRoot.FullName `
                    -Parent $captureParent) -or
                $currentRoot.Name -cne $captureDirectory.Name -or
                $currentRoot.Name -notmatch '^[0-9a-f]{32}$' -or
                ($currentRoot.Attributes -band
                    [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'private_capture_tree_changed'
        }
        $currentItems = @(Get-ChildItem -LiteralPath $currentRoot.FullName `
            -Recurse -Force)
        if (@($currentItems | Where-Object {
                -not (Test-PathWithin -Path $_.FullName -Parent $currentRoot.FullName) -or
                ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
            }).Count -ne 0) {
            throw 'private_capture_tree_changed'
        }
        $confirmArchive = [IO.Compression.ZipFile]::OpenRead($pcPackage)
        try {
            $confirmEntries = @($confirmArchive.Entries | Where-Object {
                $_.FullName -ceq 'conf.lua'
            })
            if ($confirmEntries.Count -ne 1) {
                throw 'private_capture_tree_changed'
            }
            $confirmReader = [IO.StreamReader]::new($confirmEntries[0].Open())
            try {
                $confirmText = $confirmReader.ReadToEnd()
            } finally {
                $confirmReader.Dispose()
            }
            $confirmIdentity = 't.identity = "the-picture-shop-pc-probe-' +
                $captureDirectory.Name + '"'
            if (([regex]::Matches($confirmText,
                    [regex]::Escape($confirmIdentity))).Count -ne 1) {
                throw 'private_capture_tree_changed'
            }
        } finally {
            $confirmArchive.Dispose()
        }

        # The archive scan above can take time. Recheck both global capture
        # state and the parent boundary at the last possible moment before the
        # recursive private-tree deletion.
        $finalParent = Get-Item -LiteralPath $captureParent -Force
        if ($finalParent.FullName -cne $captureParent -or
                ($finalParent.Attributes -band
                    [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'private_capture_parent_not_safe'
        }
        $finalStatus = Invoke-PktMonInternal -CommandArguments @('status')
        $finalFilters = Invoke-PktMonInternal -CommandArguments @('filter','list')
        $finalPendingHash = (Get-FileHash -Algorithm SHA256 `
            -LiteralPath $pendingReport).Hash.ToLowerInvariant()
        if ($finalStatus.exitCode -ne 0 -or
                $finalStatus.output -notmatch $inactivePattern -or
                $finalFilters.exitCode -ne 0 -or
                $finalFilters.output -notmatch '(?im)^\s*none\.?\s*$' -or
                (Get-FilterRowCount -Value $finalFilters.output) -ne 0 -or
                $finalPendingHash -cne $pendingHash -or
                (Test-Path -LiteralPath $rootFallbackPath)) {
            throw 'private_capture_delete_precondition_changed'
        }

        Remove-Item -LiteralPath $captureDirectory.FullName -Recurse -Force
        if (Test-Path -LiteralPath $captureDirectory.FullName) {
            throw 'private_capture_cleanup_failed'
        }
        $recoveryArtifactsRemoved = $true

        $recoveryEvidence = [ordered]@{
            schemaVersion = 2
            artifactKind = 'windows-direct-packet-capture-recovery'
            completedAtUtc = [DateTime]::UtcNow.ToString('o')
            result = 'recovered'
            sourceFailureStage = [string]$report.failureStage
            sourcePendingSha256 = $pendingHash
            productionReady = $false
            privacy = [ordered]@{
                endpointRecorded = $false
                deviceSerialRecorded = $false
                invitationCodesRecorded = $false
                keysOrPacketsRecorded = $false
                rawLogsRecorded = $false
                rawCaptureRetained = $false
                packetEndpointsRetained = $false
            }
            cleanup = [ordered]@{
                packetCaptureStopped = $recoveryCaptureStopped
                packetCaptureFilterRemoved = $recoveryFilterRemoved
                packetCaptureArtifactsRemoved = $recoveryArtifactsRemoved
                outsideFallbackAbsent = $true
                verified = $recoveryCaptureStopped -and
                    $recoveryFilterRemoved -and $recoveryArtifactsRemoved
            }
        }
        [IO.File]::WriteAllText($recoveryReport,
            ($recoveryEvidence | ConvertTo-Json -Depth 8) + "`n",
            [Text.UTF8Encoding]::new($false))
        Write-SafeResult ([ordered]@{
            recover = 'passed'
            packetCaptureStopped = $recoveryCaptureStopped
            packetCaptureFilterRemoved = $recoveryFilterRemoved
            packetCaptureArtifactsRemoved = $recoveryArtifactsRemoved
            outsideFallbackAbsent = $true
            rawCaptureRetained = $false
        })
        return
    }

    Write-SafeResult ([ordered]@{
        inspect = 'passed'
        pendingStateMatched = $pendingMatched
        probeLockFree = $mutexOwned
        privateCaptureDirectoryCount = $captureDirectories.Count
        privateCaptureTreeSafe = $treeSafe
        privateProbeMarkersPresent = $packageMarkersPresent
        privateProbeIdentityMatched = $archiveIdentityMatched
        privateProbeConfigMatched = $archiveProbeConfigMatched
        captureEtlPresent = $etlPresent
        capturePcapPresent = $pcapPresent
        outsideFallbackPresent = $outsideFallbackPresent
        pktMonStatusReadable = $status.exitCode -eq 0
        pktMonNotInactive = $statusNotInactive
        pktMonInactive = $statusInactive
        statusExpectedFullPathMatch = $statusFullPathMatch
        statusExpectedFileNameMatch = $statusFileNameMatch
        statusMentionsAnyEtl = $statusMentionsAnyEtl
        statusLoggerMatched = $statusLoggerMatched
        statusMemoryModeMatched = $statusMemoryModeMatched
        statusFileSizeMatched = $statusFileSizeMatched
        statusPacketCaptureMatched = $statusPacketCaptureMatched
        statusAllPacketsMatched = $statusAllPacketsMatched
        statusNicsMatched = $statusNicsMatched
        statusCaptureConfigurationMatched = $statusCaptureConfigurationMatched
        filterListReadable = $filters.exitCode -eq 0
        filterRowCount = $filterRowCount
        ownedFilterMentions = $ownedFilterMentions
        filterIdentityClass = $filterIdentityClass
        reportFilterContractMatched = $reportFilterContractMatched
        reportFilterOwnershipMatched = $reportFilterOwnershipMatched
        reportFilterAbsentContractMatched =
            $reportFilterAbsentContractMatched
        filterIpv6Matched = $filterIpv6Matched
        filterUdpMatched = $filterUdpMatched
        filterPortMatched = $filterPortMatched
        exclusiveOwnedFilter = $exclusiveOwnedFilter
        filterListEmpty = $filterListEmpty
        recentPendingReport = $recentPendingReport
        recentRunArtifact = $recentRunArtifact
        recoveryClass = $recoveryClass
    })
} catch {
    $safeReason = switch -Regex ($_.Exception.Message) {
        '^pktmon_unavailable$' { 'pktmon_unavailable'; break }
        '^probe_still_running$' { 'probe_still_running'; break }
        '^pending_report_missing$' { 'pending_report_missing'; break }
        '^pending_report_state_mismatch$' { 'pending_report_state_mismatch'; break }
        '^pending_report_changed$' { 'pending_report_changed'; break }
        '^private_capture_working_directory_(?:missing|unsafe)$' {
            $_.Exception.Message; break
        }
        '^pktmon_launch_failed$' { 'pktmon_launch_failed'; break }
        '^private_capture_directory_not_unique$' {
            'private_capture_directory_not_unique'; break
        }
        '^private_capture_parent_not_safe$' {
            'private_capture_parent_not_safe'; break
        }
        '^private_capture_path_not_contained$' {
            'private_capture_path_not_contained'; break
        }
        '^private_capture_tree_not_safe$' {
            'private_capture_tree_not_safe'; break
        }
        '^private_probe_markers_missing$' {
            'private_probe_markers_missing'; break
        }
        '^private_probe_identity_mismatch$' {
            'private_probe_identity_mismatch'; break
        }
        '^recovery_ownership_not_proven$' {
            'recovery_ownership_not_proven'; break
        }
        '^recovery_state_changed$' { 'recovery_state_changed'; break }
        '^owned_capture_stop_failed$' { 'owned_capture_stop_failed'; break }
        '^owned_capture_stop_unverified$' {
            'owned_capture_stop_unverified'; break
        }
        '^owned_capture_output_unverified$' {
            'owned_capture_output_unverified'; break
        }
        '^uncontained_capture_artifact_present$' {
            'uncontained_capture_artifact_present'; break
        }
        '^owned_filter_changed$' { 'owned_filter_changed'; break }
        '^owned_filter_removal_failed$' {
            'owned_filter_removal_failed'; break
        }
        '^owned_filter_removal_unverified$' {
            'owned_filter_removal_unverified'; break
        }
        '^private_capture_tree_changed$' {
            'private_capture_tree_changed'; break
        }
        '^private_capture_cleanup_failed$' {
            'private_capture_cleanup_failed'; break
        }
        '^private_capture_delete_precondition_changed$' {
            'private_capture_delete_precondition_changed'; break
        }
        default { 'inspection_failed' }
    }
    if ($recoverRequested) {
        Write-SafeResult ([ordered]@{
            recover = 'failed'
            reason = $safeReason
            exceptionType = $_.Exception.GetType().Name
            packetCaptureStopped = $recoveryCaptureStopped
            packetCaptureFilterRemovalAttempted =
                $recoveryFilterRemovalAttempted
            packetCaptureFilterRemoved = $recoveryFilterRemoved
            packetCaptureArtifactsRemoved = $recoveryArtifactsRemoved
            rawCaptureMayRemain = -not $recoveryArtifactsRemoved
        })
    } else {
        Write-SafeResult ([ordered]@{
            inspect = 'failed'
            reason = $safeReason
            exceptionType = $_.Exception.GetType().Name
        })
    }
} finally {
    if ($mutexOwned -and $runMutex) { $runMutex.ReleaseMutex() }
    if ($runMutex) { $runMutex.Dispose() }
}
