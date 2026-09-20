[CmdletBinding()]
param(
    [ValidateSet('Run','Cleanup')]
    [string]$Action = 'Run'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$probePort = 59281
$mappingPort = 5351
$leaseSeconds = 120
$filterName = 'TPS_PUBLIC_IPV4_UDP_5351'
$firewallRuleName = 'ThePictureShop.Engineering.PublicIpv4Probe.UDP.59281'
$kitRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$manifestPath = Join-Path $kitRoot 'manifest.json'
$hostRunner = Join-Path $kitRoot 'run_host.ps1'
$resultPath = Join-Path $kitRoot 'last-mapping-traffic-result.txt'
$pktmonPath = Join-Path $env:SystemRoot 'System32\PktMon.exe'
$filterOwned = $false
$filterSnapshot = $null
$captureStarted = $false
$captureEverStarted = $false
$captureStopped = $true
$filterRemoved = $true
$counterSchemaRecognized = $false
$txObserved = $false
$rxObserved = $false
$hostOutcome = 'launcher_error'
$firewallRuleRemoved = $false
$probeInfrastructureFailure = $false

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedSelf {
    $arguments = '-NoExit -NoProfile -ExecutionPolicy Bypass -File "' +
        $PSCommandPath.Replace('"','""') + '" -Action ' + $Action
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
        -ArgumentList $arguments -WindowStyle Normal -Wait -PassThru
    exit $process.ExitCode
}

function Assert-WithinKit([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $kitRoot.TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'A packaged path escaped the acceptance-kit directory.'
    }
    return $full
}

function Assert-PackageIntegrity {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'The host manifest is missing.'
    }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $manifest.kind -cne 'host' -or
            $manifest.probePort -ne $probePort -or
            $manifest.leaseSeconds -ne $leaseSeconds) {
        throw 'The host manifest contract is invalid.'
    }
    foreach ($property in $manifest.files.PSObject.Properties) {
        $relative = ([string]$property.Name).Replace('/','\')
        if ($relative -match '(^|\\)\.\.(\\|$)') {
            throw 'The host manifest contains an unsafe path.'
        }
        $full = Assert-WithinKit (Join-Path $kitRoot $relative)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw 'A packaged host file is missing.'
        }
        $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).
            Hash.ToLowerInvariant()
        if ($actual -cne [string]$property.Value) {
            throw 'A packaged host file failed its integrity check.'
        }
    }
    if (-not (Test-Path -LiteralPath $hostRunner -PathType Leaf)) {
        throw 'The guarded Host mapping launcher is missing.'
    }
}

function Invoke-PktMon {
    param([Parameter(Mandatory=$true)][string[]]$CommandArguments)
    $output = @(& $pktmonPath @CommandArguments 2>&1) -join "`n"
    return [pscustomobject]@{
        exitCode = $LASTEXITCODE
        output = [string]$output
    }
}

function Normalize-PktMonText {
    param([AllowEmptyString()][string]$Value)
    return (($Value -replace "`r`n","`n").Trim())
}

function Get-PktMonFilterRows {
    param([AllowEmptyString()][string]$Value)
    $rows = @()
    foreach ($match in [regex]::Matches($Value,
            '(?im)^\s*(?:filter\s+)?\d+(?:\s+|[.:)]|-)[^\r\n]*$')) {
        $rows += $match.Value
    }
    return @($rows)
}

function Get-PktMonFilterRowNames {
    param([AllowEmptyString()][string]$Value)
    $names = @()
    foreach ($line in [regex]::Split($Value,'\r?\n')) {
        $match = [regex]::Match($line,
            ('^\s*(?:filter\s+)?\d+' +
             '(?:\s*[:.)-]\s*|\s+)' +
             '(?:name\s*[:=]\s*)?' +
             '(?<name><empty>|[A-Za-z0-9_.-]+)(?:\s|$)'),
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) { $names += $match.Groups['name'].Value }
    }
    return @($names)
}

function Test-PktMonInactiveStatus($Status) {
    return $Status.exitCode -eq 0 -and $Status.output -match
        '(?im)^[^\r\n]*(?:not\s+running|stopped|inactive|no\s+active)[^\r\n]*$'
}

function Test-EmptyFilterList($Listed) {
    return $Listed.exitCode -eq 0 -and
        $Listed.output -match '(?im)^\s*none\.?\s*$' -and
        @(Get-PktMonFilterRows $Listed.output).Count -eq 0
}

function Test-ExactOwnedFilterList($Listed) {
    if ($Listed.exitCode -ne 0) { return $false }
    $rows = @(Get-PktMonFilterRows $Listed.output)
    $names = @(Get-PktMonFilterRowNames $Listed.output)
    return $rows.Count -eq 1 -and $names.Count -eq 1 -and
        $names[0] -ceq $filterName -and
        $rows[0] -match '(?i)\bIPv4\b' -and
        $rows[0] -match '(?i)\bUDP\b' -and
        $rows[0] -match '(?<!\d)5351(?!\d)'
}

function Assert-PktMonPreflight {
    if (-not (Test-Path -LiteralPath $pktmonPath -PathType Leaf)) {
        throw 'Windows Packet Monitor is unavailable.'
    }
    $status = Invoke-PktMon @('status')
    if (-not (Test-PktMonInactiveStatus $status)) {
        throw 'Another Windows Packet Monitor session may already be active.'
    }
    $filters = Invoke-PktMon @('filter','list')
    if (-not (Test-EmptyFilterList $filters)) {
        throw 'Windows Packet Monitor already has filters; they were not changed.'
    }
    $packetLogs = @(Get-ChildItem -LiteralPath $kitRoot -File `
        -Filter 'PktMon*.etl')
    if ($packetLogs.Count -ne 0) {
        throw 'A packet-log file is already present in the Host folder.'
    }
}

function Get-DirectionToken([string]$Value) {
    $token = ($Value -replace '[^A-Za-z]','').ToLowerInvariant()
    if ($token -in @('tx','out','send','sent','egress','transmit',
            'packetsout','bytesout','outpackets','outbytes','packetstx',
            'bytestx','transmitpackets','transmitbytes','sendpackets',
            'sentpackets')) { return 'tx' }
    if ($token -in @('rx','in','receive','received','ingress',
            'packetsin','bytesin','inpackets','inbytes','packetsrx',
            'bytesrx','receivepackets','receivebytes','receivedpackets')) {
        return 'rx'
    }
    return $null
}

function Get-NumericDirectionToken($Value) {
    if (-not (Test-NumericValue $Value)) { return $null }
    $tag = [int]$Value
    if ($tag -in @(2,4,6)) { return 'tx' }
    if ($tag -in @(1,3,5)) { return 'rx' }
    return $null
}

function Test-MetricName([string]$Value) {
    $token = ($Value -replace '[^A-Za-z]','').ToLowerInvariant()
    return $token -in @('packet','packets','packetcount','byte','bytes',
        'bytecount','count','value','total')
}

function Test-NumericValue($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or
        $Value -is [decimal]
}

function Test-PositiveMetricValue($Value,[bool]$AllowBareNumber,
        [int]$Depth = 0) {
    if ($Depth -gt 32 -or $null -eq $Value) { return $false }
    if (Test-NumericValue $Value) {
        return $AllowBareNumber -and [double]$Value -gt 0
    }
    if ($Value -is [string] -or $Value -is [bool]) { return $false }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in @($Value)) {
            if (Test-PositiveMetricValue $item $AllowBareNumber ($Depth + 1)) {
                return $true
            }
        }
        return $false
    }
    foreach ($property in $Value.PSObject.Properties) {
        $metric = Test-MetricName $property.Name
        if (Test-PositiveMetricValue $property.Value $metric ($Depth + 1)) {
            return $true
        }
    }
    return $false
}

function Visit-CounterJson($Value,[AllowNull()][string]$Direction,
        $Summary,[int]$Depth = 0) {
    if ($Depth -gt 32 -or $null -eq $Value -or $Value -is [string] -or
            (Test-NumericValue $Value) -or $Value -is [bool]) { return }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in @($Value)) {
            Visit-CounterJson $item $Direction $Summary ($Depth + 1)
        }
        return
    }
    $localDirection = $Direction
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -match ('^(?i:direction|directionname|' +
                'directiontag|dirtag|name|countername)$')) {
            $candidate = if ($property.Value -is [string]) {
                Get-DirectionToken ([string]$property.Value)
            } else {
                Get-NumericDirectionToken $property.Value
            }
            if ($candidate) { $localDirection = $candidate }
        }
    }
    foreach ($property in $Value.PSObject.Properties) {
        $propertyDirection = Get-DirectionToken $property.Name
        if ($propertyDirection) {
            $Summary.Recognized = $true
            $positive = Test-PositiveMetricValue $property.Value $true
            if ($propertyDirection -eq 'tx' -and $positive) {
                $Summary.Tx = $true
            } elseif ($propertyDirection -eq 'rx' -and $positive) {
                $Summary.Rx = $true
            }
        } elseif ($localDirection -and (Test-MetricName $property.Name)) {
            $Summary.Recognized = $true
            $positive = Test-PositiveMetricValue $property.Value $true
            if ($localDirection -eq 'tx' -and $positive) {
                $Summary.Tx = $true
            } elseif ($localDirection -eq 'rx' -and $positive) {
                $Summary.Rx = $true
            }
        }
        $nextDirection = $localDirection
        if ($propertyDirection) { $nextDirection = $propertyDirection }
        Visit-CounterJson $property.Value $nextDirection $Summary ($Depth + 1)
    }
}

function Get-CounterSummary([string]$JsonText) {
    if ([string]::IsNullOrWhiteSpace($JsonText) -or
            [Text.Encoding]::UTF8.GetByteCount($JsonText) -gt 4MB) {
        throw 'Packet Monitor returned an invalid counter summary.'
    }
    $parsed = $JsonText | ConvertFrom-Json -ErrorAction Stop
    $summary = [pscustomobject]@{
        Recognized = $false
        Tx = $false
        Rx = $false
    }
    Visit-CounterJson $parsed $null $summary
    return $summary
}

function Get-HostOutcome {
    $hostResult = Join-Path $kitRoot 'last-host-result.txt'
    if (-not (Test-Path -LiteralPath $hostResult -PathType Leaf)) {
        return 'launcher_error'
    }
    $lines = @(Get-Content -LiteralPath $hostResult)
    if ($lines -contains 'TPS_PUBLIC_IPV4_TRAFFIC=PASS') { return 'pass' }
    if ($lines -contains 'TPS_PUBLIC_IPV4_TRAFFIC=FAIL') {
        foreach ($line in $lines) {
            if ($line -match '^REASON=([a-z_]+)$') { return $matches[1] }
        }
    }
    return 'launcher_error'
}

function Get-BooleanMarker([bool]$Value) {
    if ($Value) { return 'True' }
    return 'False'
}

function Write-SafeResult([bool]$Success,[string]$Reason) {
    $statusMarker = if ($Success) { 'PASS' } else { 'FAIL' }
    $lines = @()
    $lines += ('TPS_MAPPING_TRAFFIC_CHECK=' + $statusMarker)
    if (-not $Success) { $lines += ('REASON=' + $Reason) }
    $lines += ('HOST_MAPPING_OUTCOME=' + $hostOutcome)
    $lines += 'COUNTERS_ONLY=True'
    $lines += 'PACKET_LOGGING=False'
    $lines += ('UDP_5351_NIC_TX_OBSERVED=' +
        (Get-BooleanMarker $txObserved))
    $lines += ('UDP_5351_NIC_RX_OBSERVED=' +
        (Get-BooleanMarker $rxObserved))
    $lines += ('COUNTER_SCHEMA_RECOGNIZED=' +
        (Get-BooleanMarker $counterSchemaRecognized))
    $lines += ('PKTMON_STOPPED=' +
        (Get-BooleanMarker $captureStopped))
    $lines += ('PKTMON_FILTER_REMOVED=' +
        (Get-BooleanMarker $filterRemoved))
    $lines += ('TEMPORARY_FIREWALL_RULE_REMOVED=' +
        (Get-BooleanMarker $firewallRuleRemoved))
    $lines += 'PACKET_CONTENTS_RETAINED=False'
    $lines += 'NETWORK_DETAILS_RETAINED=False'
    foreach ($line in $lines) {
        if ($line -notmatch '^[A-Z0-9_]+=(?:PASS|FAIL|True|False|[a-z_]+)$') {
            throw 'The traffic-check result was not privacy safe.'
        }
    }
    $safeLines = [string[]]$lines
    [IO.File]::WriteAllLines($resultPath,$safeLines,
        [Text.UTF8Encoding]::new($false))
    $safeLines | Write-Output
}

if (-not (Test-IsElevated)) { Invoke-ElevatedSelf }
Assert-PackageIntegrity

if ($Action -eq 'Cleanup') {
    $listed = Invoke-PktMon @('filter','list')
    if (Test-EmptyFilterList $listed) {
        Write-Output 'PKTMON_FILTER_REMOVED=True'
        exit 0
    }
    if (-not (Test-ExactOwnedFilterList $listed)) {
        throw 'Packet Monitor contains filters not proven to belong to this test.'
    }
    $status = Invoke-PktMon @('status')
    $confirmationText = if (Test-PktMonInactiveStatus $status) {
        'CLEAN MAPPING TRAFFIC FILTER'
    } else {
        'STOP AND CLEAN MAPPING TRAFFIC CHECK'
    }
    $confirmation = Read-Host "Type $confirmationText"
    if ($confirmation -cne $confirmationText) {
        throw 'Packet Monitor cleanup was not authorized.'
    }
    if (-not (Test-PktMonInactiveStatus $status)) {
        $stopped = Invoke-PktMon @('stop')
        if ($stopped.exitCode -ne 0 -or
                -not (Test-PktMonInactiveStatus (Invoke-PktMon @('status')))) {
            throw 'The owned Packet Monitor session could not be stopped.'
        }
    }
    $removed = Invoke-PktMon @('filter','remove')
    if ($removed.exitCode -ne 0 -or
            -not (Test-EmptyFilterList (Invoke-PktMon @('filter','list')))) {
        throw 'The owned Packet Monitor filter could not be removed.'
    }
    Write-Output 'PKTMON_STOPPED=True'
    Write-Output 'PKTMON_FILTER_REMOVED=True'
    exit 0
}

if (Test-Path -LiteralPath $resultPath) {
    Remove-Item -LiteralPath $resultPath -Force
}

$priorLocation = Get-Location
try {
    Set-Location -LiteralPath $kitRoot
    Assert-PktMonPreflight

    $added = Invoke-PktMon @('filter','add',$filterName,'-d','IPv4',
        '-t','UDP','-p',[string]$mappingPort)
    if ($added.exitCode -ne 0) {
        throw 'The temporary UDP 5351 counter filter could not be added.'
    }
    $script:filterOwned = $true
    $script:filterRemoved = $false
    $listed = Invoke-PktMon @('filter','list')
    if (-not (Test-ExactOwnedFilterList $listed)) {
        throw 'The temporary UDP 5351 counter filter could not be verified.'
    }
    $script:filterSnapshot = Normalize-PktMonText $listed.output

    $started = Invoke-PktMon @('start','--capture','--counters-only',
        '--comp','nics','--type','all')
    if ($started.exitCode -ne 0) {
        throw 'The counters-only Packet Monitor session could not start.'
    }
    $script:captureStarted = $true
    $script:captureEverStarted = $true
    $script:captureStopped = $false

    $initial = Invoke-PktMon @('counters','--json')
    if ($initial.exitCode -ne 0) {
        throw 'The counters-only Packet Monitor session was not readable.'
    }
    Get-CounterSummary $initial.output | Out-Null
    # Starting PktMon can briefly notify Windows that network components
    # changed. Let that settle before the probe captures its fail-closed
    # route generation and exact socket binding.
    Start-Sleep -Milliseconds 3000

    try {
        & $hostRunner -Action Traffic
    } catch {
        # A canonical traffic-role failure such as mapping_timeout is an
        # expected diagnostic outcome. Get-HostOutcome validates it below.
    }
    $script:hostOutcome = Get-HostOutcome
} catch {
    $script:probeInfrastructureFailure = $true
} finally {
    if ($captureStarted) {
        try {
            $beforeCounters = Invoke-PktMon @('filter','list')
            if ($beforeCounters.exitCode -ne 0 -or
                    (Normalize-PktMonText $beforeCounters.output) -cne
                        $filterSnapshot) {
                throw 'Packet Monitor filters changed during the traffic check.'
            }
            $counters = Invoke-PktMon @('counters','--json')
            if ($counters.exitCode -ne 0) {
                throw 'Packet Monitor counters could not be read.'
            }
            $summary = Get-CounterSummary $counters.output
            $script:counterSchemaRecognized = $summary.Recognized -eq $true
            $script:txObserved = $summary.Tx -eq $true
            $script:rxObserved = $summary.Rx -eq $true
        } catch {
            $script:probeInfrastructureFailure = $true
        }
        try {
            $stopped = Invoke-PktMon @('stop')
            if ($stopped.exitCode -ne 0 -or
                    -not (Test-PktMonInactiveStatus (
                        Invoke-PktMon @('status')))) {
                throw 'The counters-only Packet Monitor session could not be stopped.'
            }
            $script:captureStopped = $true
            $script:captureStarted = $false
        } catch {
            $script:probeInfrastructureFailure = $true
        }
    }
    if ($filterOwned -and $captureStopped) {
        try {
            $afterStop = Invoke-PktMon @('filter','list')
            if ($afterStop.exitCode -ne 0 -or
                    (Normalize-PktMonText $afterStop.output) -cne
                        $filterSnapshot) {
                throw 'Packet Monitor filters changed; no filters were removed.'
            }
            $removed = Invoke-PktMon @('filter','remove')
            if ($removed.exitCode -ne 0 -or
                    -not (Test-EmptyFilterList (
                        Invoke-PktMon @('filter','list')))) {
                throw 'The owned Packet Monitor filter could not be removed.'
            }
            $script:filterOwned = $false
            $script:filterRemoved = $true
        } catch {
            $script:probeInfrastructureFailure = $true
        }
    }
    try {
        $ownedFirewallRules = @(Get-NetFirewallRule `
            -PolicyStore PersistentStore -ErrorAction Stop |
            Where-Object { [string]$_.Name -ceq $firewallRuleName })
        $script:firewallRuleRemoved = $ownedFirewallRules.Count -eq 0
        if (-not $firewallRuleRemoved) {
            $script:probeInfrastructureFailure = $true
        }
    } catch {
        $script:firewallRuleRemoved = $false
        $script:probeInfrastructureFailure = $true
    }
    try {
        $packetLogs = @(Get-ChildItem -LiteralPath $kitRoot -File `
            -Filter 'PktMon*.etl')
        if ($packetLogs.Count -ne 0) {
            throw 'Counters-only mode unexpectedly created a packet log.'
        }
    } catch {
        $script:probeInfrastructureFailure = $true
    } finally {
        Set-Location -LiteralPath $priorLocation
    }
}

$failureReason = $null
if (-not $firewallRuleRemoved) {
    $failureReason = 'firewall_cleanup_failed'
} elseif (-not $captureStopped -or -not $filterRemoved) {
    $failureReason = 'packet_monitor_cleanup_failed'
} elseif (-not $captureEverStarted) {
    $failureReason = 'packet_monitor_preflight_failed'
} elseif (-not $counterSchemaRecognized) {
    $failureReason = 'counter_schema_unsupported'
} elseif ($hostOutcome -eq 'launcher_error') {
    $failureReason = 'host_launcher_failed'
} elseif ($probeInfrastructureFailure) {
    $failureReason = 'traffic_probe_failed'
}

if ($failureReason) {
    Write-SafeResult $false $failureReason
    exit 1
}
Write-SafeResult $true ''
exit 0
