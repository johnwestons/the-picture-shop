[CmdletBinding()]
param(
    [ValidateSet('Preflight','Map','Traffic','Cleanup','RemoveAccidentalRules')]
    [string]$Action = 'Preflight'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$probePort = 59281
$leaseSeconds = 120
$ruleName = 'ThePictureShop.Engineering.PublicIpv4Probe.UDP.59281'
$ruleGroup = 'The Picture Shop Engineering'
$ruleDescription = 'Owned by the public IPv4 acceptance kit; exact temporary UDP probe rule.'
$kitRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$loveConsole = Join-Path $kitRoot 'runtime\lovec.exe'
$probePackage = Join-Path $kitRoot 'public-ipv4-probe.love'
$manifestPath = Join-Path $kitRoot 'manifest.json'
$resultPath = Join-Path $kitRoot 'last-host-result.txt'
$ruleCreated = $false

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
    foreach ($required in @(
        $loveConsole,$probePackage,
        (Join-Path $kitRoot 'tps_crypto.dll'),
        (Join-Path $kitRoot 'tps_route.dll'))) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw 'A required host component is missing.'
        }
    }
}

function Get-PortTokens($Value) {
    $tokens = @()
    foreach ($raw in @($Value | ForEach-Object { [string]$_ })) {
        foreach ($part in $raw -split '[,\s]+') {
            if (-not [string]::IsNullOrWhiteSpace($part)) {
                $tokens += $part.Trim()
            }
        }
    }
    return @($tokens)
}

function Test-PortApplies($Value) {
    foreach ($token in @(Get-PortTokens $Value)) {
        if ($token -ieq 'Any' -or $token -ceq [string]$probePort) {
            return $true
        }
        $range = [regex]::Match($token,'^(\d{1,5})-(\d{1,5})$')
        if ($range.Success -and
                [int]$range.Groups[1].Value -le $probePort -and
                $probePort -le [int]$range.Groups[2].Value) {
            return $true
        }
    }
    return $false
}

function Get-ActiveRouteContext {
    $interfaces = @{}
    foreach ($interface in @(Get-NetIPInterface -AddressFamily IPv4 `
            -PolicyStore ActiveStore -ErrorAction Stop)) {
        $interfaces[[int]$interface.InterfaceIndex] = $interface
    }
    $candidates = @()
    foreach ($route in @(Get-NetRoute -AddressFamily IPv4 `
            -DestinationPrefix '0.0.0.0/0' -PolicyStore ActiveStore `
            -ErrorAction Stop)) {
        if ([string]$route.NextHop -eq '0.0.0.0') { continue }
        $interface = $interfaces[[int]$route.InterfaceIndex]
        if ($null -eq $interface -or [string]$interface.ConnectionState -ne
                'Connected') { continue }
        $candidates += [pscustomobject]@{
            Route = $route
            Interface = $interface
            Score = [long]$route.RouteMetric + [long]$interface.InterfaceMetric
        }
    }
    if ($candidates.Count -lt 1) {
        throw 'No active indirect IPv4 default route is available.'
    }
    $ordered = @($candidates | Sort-Object Score,
        @{Expression={[int]$_.Route.InterfaceIndex}})
    $best = $ordered[0]
    if (@($ordered | Where-Object { $_.Score -eq $best.Score }).Count -ne 1) {
        throw 'The active IPv4 default route is ambiguous.'
    }
    $adapter = Get-NetAdapter -InterfaceIndex $best.Route.InterfaceIndex `
        -IncludeHidden -ErrorAction Stop
    if ([string]$adapter.Status -ne 'Up' -or
            [string]::IsNullOrWhiteSpace([string]$adapter.Name) -or
            [string]$adapter.Name -match '[*?\[\]]') {
        throw 'The selected network interface cannot be scoped safely.'
    }
    $profiles = @(Get-NetConnectionProfile -InterfaceIndex `
        $best.Route.InterfaceIndex -ErrorAction Stop)
    if ($profiles.Count -ne 1) {
        throw 'The selected interface does not have one firewall profile.'
    }
    $profile = [string]$profiles[0].NetworkCategory
    if ($profile -eq 'DomainAuthenticated') { $profile = 'Domain' }
    if ($profile -notin @('Private','Public','Domain')) {
        throw 'The selected firewall profile is unsupported.'
    }
    $firewall = Get-NetFirewallProfile -Name $profile `
        -PolicyStore ActiveStore -ErrorAction Stop
    if ([string]$firewall.Enabled -ne 'True' -or
            [string]$firewall.DefaultInboundAction -ne 'Block') {
        throw 'The active Windows Firewall profile must remain enabled with unsolicited inbound traffic blocked.'
    }
    return [pscustomobject]@{
        InterfaceAlias = [string]$adapter.Name
        Profile = $profile
    }
}

function Get-OwnedRule {
    return @(Get-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore `
        -ErrorAction SilentlyContinue)
}

function Get-AccidentalProbeRules {
    $probeSuffix = '\The Picture Shop Public IPv4 Remote Test' +
        '\Host\runtime\lovec.exe'
    $matches = @()
    foreach ($rule in @(Get-NetFirewallRule -PolicyStore PersistentStore `
            -Direction Inbound -Action Allow -ErrorAction Stop)) {
        if ([string]$rule.PolicyStoreSourceType -ine 'Local' -or
                [string]$rule.EdgeTraversalPolicy -ine 'DeferToUser' -or
                [string]$rule.Name -notmatch `
                '^(TCP|UDP) Query User\{[0-9A-Fa-f-]{36}\}') {
            continue
        }
        $application = @($rule | Get-NetFirewallApplicationFilter `
            -ErrorAction Stop)
        $service = @($rule | Get-NetFirewallServiceFilter -ErrorAction Stop)
        $port = @($rule | Get-NetFirewallPortFilter -ErrorAction Stop)
        if ($application.Count -ne 1 -or $service.Count -ne 1 -or
                $port.Count -ne 1) {
            continue
        }
        $program = [string]$application[0].Program
        if (-not $program.EndsWith($probeSuffix,
                [StringComparison]::OrdinalIgnoreCase) -or
                [string]$service[0].Service -ine 'Any' -or
                [string]$port[0].Protocol -notin @('TCP','6','UDP','17') -or
                [string]$port[0].LocalPort -ine 'Any') {
            continue
        }
        $matches += $rule
    }
    return @($matches)
}

function Remove-AccidentalProbeRules {
    $rules = @(Get-AccidentalProbeRules)
    foreach ($rule in $rules) {
        Remove-NetFirewallRule -Name ([string]$rule.Name) `
            -PolicyStore PersistentStore -ErrorAction Stop
    }
    if ((@(Get-AccidentalProbeRules)).Count -ne 0) {
        throw 'An accidental test firewall rule could not be removed.'
    }
    return $rules.Count
}

function Test-OwnedRule($Rule) {
    if ($null -eq $Rule -or [string]$Rule.Name -cne $ruleName -or
            [string]$Rule.Group -cne $ruleGroup -or
            [string]$Rule.Description -cne $ruleDescription) {
        return $false
    }
    if ([string]$Rule.Enabled -ne 'True' -or
            [string]$Rule.Direction -ne 'Inbound' -or
            [string]$Rule.Action -ne 'Allow' -or
            [string]$Rule.EdgeTraversalPolicy -ne 'Block' -or
            [string]$Rule.Profile -notin @('Private','Public','Domain')) {
        return $false
    }
    $application = @($Rule | Get-NetFirewallApplicationFilter `
        -ErrorAction Stop)
    $service = @($Rule | Get-NetFirewallServiceFilter -ErrorAction Stop)
    $port = @($Rule | Get-NetFirewallPortFilter -ErrorAction Stop)
    $address = @($Rule | Get-NetFirewallAddressFilter -ErrorAction Stop)
    $interface = @($Rule | Get-NetFirewallInterfaceFilter -ErrorAction Stop)
    if ($application.Count -ne 1 -or $service.Count -ne 1 -or
            $port.Count -ne 1 -or $address.Count -ne 1 -or
            $interface.Count -ne 1) {
        return $false
    }
    $aliases = @($interface[0].InterfaceAlias | ForEach-Object { [string]$_ })
    $remoteAddresses = @($address[0].RemoteAddress |
        ForEach-Object { [string]$_ })
    return [string]$application[0].Program -ieq $loveConsole -and
        [string]$service[0].Service -ieq 'Any' -and
        [string]$port[0].Protocol -in @('UDP','17') -and
        [string]$port[0].LocalPort -ceq [string]$probePort -and
        [string]$port[0].RemotePort -ieq 'Any' -and
        [string]$address[0].LocalAddress -ieq 'Any' -and
        $remoteAddresses.Count -eq 1 -and
        $remoteAddresses[0] -ieq 'Internet' -and
        $aliases.Count -eq 1 -and
        -not [string]::IsNullOrWhiteSpace($aliases[0]) -and
        $aliases[0] -notmatch '[*?\[\]]'
}

function Test-RuleProfileApplies($Value,[string]$Profile) {
    foreach ($token in @(([string]$Value) -split '[,\s]+')) {
        if ($token -ieq 'Any' -or $token -ieq $Profile) {
            return $true
        }
    }
    return $false
}

function Test-RuleInterfaceApplies($Value,[string]$InterfaceAlias) {
    $aliases = @($Value | ForEach-Object { [string]$_ })
    if ($aliases.Count -eq 0) { return $true }
    foreach ($alias in $aliases) {
        if ([string]::IsNullOrWhiteSpace($alias) -or $alias -ieq 'Any' -or
                $alias -ieq $InterfaceAlias) {
            return $true
        }
    }
    return $false
}

function Test-RuleAllowsInternet($Value) {
    foreach ($token in @(Get-PortTokens $Value)) {
        if ($token -ieq 'Any' -or $token -ieq 'Internet' -or
                $token -ceq '0.0.0.0/0') {
            return $true
        }
    }
    return $false
}

function Assert-NoBroadExistingRule($Context) {
    foreach ($rule in @(Get-NetFirewallRule -PolicyStore ActiveStore `
            -Direction Inbound -Action Allow -Enabled True -ErrorAction Stop)) {
        if ([string]$rule.Name -ceq $ruleName) { continue }
        if (-not (Test-RuleProfileApplies $rule.Profile $Context.Profile)) {
            continue
        }
        $packageFamily = ''
        $policyAppId = ''
        if ($rule.PSObject.Properties.Name -contains 'PackageFamilyName') {
            $packageFamily = [string]$rule.PackageFamilyName
        }
        if ($rule.PSObject.Properties.Name -contains 'PolicyAppId') {
            $policyAppId = [string]$rule.PolicyAppId
        }
        # Store/AppContainer and policy-app rules can report Program=Any and
        # LocalPort=Any even though they cannot authorize this desktop binary.
        if (-not [string]::IsNullOrWhiteSpace($packageFamily) -or
                -not [string]::IsNullOrWhiteSpace($policyAppId)) {
            continue
        }
        $application = @($rule | Get-NetFirewallApplicationFilter `
            -ErrorAction Stop)
        $service = @($rule | Get-NetFirewallServiceFilter -ErrorAction Stop)
        $port = @($rule | Get-NetFirewallPortFilter -ErrorAction Stop)
        $address = @($rule | Get-NetFirewallAddressFilter -ErrorAction Stop)
        $interface = @($rule | Get-NetFirewallInterfaceFilter `
            -ErrorAction Stop)
        if ($application.Count -ne 1 -or $service.Count -ne 1 -or
                $port.Count -ne 1 -or $address.Count -ne 1 -or
                $interface.Count -ne 1) { continue }
        $program = [string]$application[0].Program
        if ($program -ine 'Any' -and $program -ine $loveConsole) { continue }
        $applicationPackage = ''
        if ($application[0].PSObject.Properties.Name -contains 'Package') {
            $applicationPackage = [string]$application[0].Package
        }
        # Older Windows versions expose the AppContainer identifier only on
        # the application filter, not as Rule.PackageFamilyName.
        if (-not [string]::IsNullOrWhiteSpace($applicationPackage)) {
            continue
        }
        if ([string]$service[0].Service -ine 'Any') { continue }
        if ([string]$port[0].Protocol -notin @('Any','UDP','17')) { continue }
        if (-not (Test-PortApplies $port[0].LocalPort)) { continue }
        if (-not (Test-RuleAllowsInternet $address[0].RemoteAddress)) {
            continue
        }
        if (-not (Test-RuleInterfaceApplies $interface[0].InterfaceAlias `
                $Context.InterfaceAlias)) {
            continue
        }
        if ($program -ieq $loveConsole) {
            throw ('Windows has a broad inbound rule for this exact test ' +
                'executable. Close this attempt, use a fresh extraction in ' +
                'a different folder, and choose Cancel if Windows asks to ' +
                'allow lovec.exe through the firewall during preflight.')
        }
        throw ('A genuine global inbound firewall rule covers the probe ' +
            'port on the active network. Do not disable or remove it ' +
            'without reviewing that rule first.')
    }
}

function Add-TemporaryFirewallRule($Context) {
    if ((@(Get-OwnedRule)).Count -ne 0) {
        throw 'A previous owned probe rule remains. Run Cleanup first.'
    }
    Assert-NoBroadExistingRule $Context
    $created = New-NetFirewallRule -Name $ruleName `
        -DisplayName 'The Picture Shop temporary public IPv4 acceptance test' `
        -Group $ruleGroup -Description $ruleDescription -Enabled True `
        -Direction Inbound -Action Allow -Profile $Context.Profile `
        -Program $loveConsole -Protocol UDP -LocalPort $probePort `
        -RemotePort Any -RemoteAddress Internet `
        -InterfaceAlias $Context.InterfaceAlias -EdgeTraversalPolicy Block `
        -PolicyStore PersistentStore -ErrorAction Stop
    if (-not (Test-OwnedRule $created)) {
        throw 'The temporary firewall rule failed exact validation.'
    }
    $createdInterface = @($created | Get-NetFirewallInterfaceFilter `
        -ErrorAction Stop)
    $createdAliases = @($createdInterface[0].InterfaceAlias |
        ForEach-Object { [string]$_ })
    if ($createdAliases.Count -ne 1 -or
            $createdAliases[0] -ine [string]$Context.InterfaceAlias -or
            [string]$created.Profile -ine [string]$Context.Profile) {
        throw 'The temporary firewall rule escaped the selected network.'
    }
    $script:ruleCreated = $true
}

function Remove-TemporaryFirewallRule {
    $rules = @(Get-OwnedRule)
    if ($rules.Count -eq 0) {
        $script:ruleCreated = $false
        return
    }
    if ($rules.Count -ne 1 -or -not (Test-OwnedRule $rules[0])) {
        throw 'The owned firewall rule changed and was not removed automatically.'
    }
    Remove-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore `
        -ErrorAction Stop
    if ((@(Get-OwnedRule)).Count -ne 0) {
        throw 'The temporary firewall rule could not be removed.'
    }
    $script:ruleCreated = $false
}

function Invoke-Probe([string]$Role,[string]$ArmedValue) {
    if (Test-Path -LiteralPath $resultPath) {
        Remove-Item -LiteralPath $resultPath -Force
    }
    $priorRole = $env:TPS_PUBLIC_IPV4_PROBE_ROLE
    $priorArmed = $env:TPS_PUBLIC_IPV4_PROBE_ARMED
    $priorResult = $env:TPS_PUBLIC_IPV4_PROBE_RESULT
    try {
        $env:TPS_PUBLIC_IPV4_PROBE_ROLE = $Role
        $env:TPS_PUBLIC_IPV4_PROBE_ARMED = $ArmedValue
        $env:TPS_PUBLIC_IPV4_PROBE_RESULT = $resultPath
        & $loveConsole $probePackage | Out-Null
        $exitCode = $LASTEXITCODE
    } finally {
        $env:TPS_PUBLIC_IPV4_PROBE_ROLE = $priorRole
        $env:TPS_PUBLIC_IPV4_PROBE_ARMED = $priorArmed
        $env:TPS_PUBLIC_IPV4_PROBE_RESULT = $priorResult
    }
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw 'The host probe ended without a safe result.'
    }
    $result = @(Get-Content -LiteralPath $resultPath)
    foreach ($line in $result) {
        if ($line -notmatch '^[A-Z0-9_]+=(PASS|FAIL|True|False|[a-z_]+|[0-9]+)$') {
            throw 'The host probe result contained an unexpected value.'
        }
        Write-Output $line
    }
    if ($exitCode -ne 0 -or
            $result -notcontains "TPS_PUBLIC_IPV4_$($Role.ToUpper())=PASS") {
        throw 'The host probe did not pass.'
    }
}

if ($Action -in @('Map','Traffic','Cleanup','RemoveAccidentalRules') -and
        -not (Test-IsElevated)) {
    Invoke-ElevatedSelf
}

Assert-PackageIntegrity

if ($Action -eq 'RemoveAccidentalRules') {
    $confirmation = Read-Host ('Type REMOVE ACCIDENTAL TEST RULES to ' +
        'remove only Windows-generated firewall rules for this test')
    if ($confirmation -cne 'REMOVE ACCIDENTAL TEST RULES') {
        throw 'Accidental-rule cleanup was not authorized.'
    }
    $removed = Remove-AccidentalProbeRules
    Write-Output "ACCIDENTAL_TEST_FIREWALL_RULES_REMOVED=$removed"
    Write-Output 'ACCIDENTAL_TEST_FIREWALL_RULES_ABSENT=True'
    exit 0
}

if ($Action -eq 'Cleanup') {
    $confirmation = Read-Host 'Type CLEANUP to remove only the owned probe firewall rule'
    if ($confirmation -cne 'CLEANUP') { throw 'Cleanup was not authorized.' }
    Remove-TemporaryFirewallRule
    Write-Output 'TEMPORARY_FIREWALL_RULE_REMOVED=True'
    exit 0
}

if ($Action -eq 'Preflight') {
    Invoke-Probe -Role 'preflight' -ArmedValue ''
    exit 0
}

$wan = Read-Host 'After checking the router admin page, type PUBLIC IPV4 CONFIRMED'
if ($wan -cne 'PUBLIC IPV4 CONFIRMED') {
    throw 'The router WAN address was not confirmed as public IPv4.'
}
$mapping = Read-Host 'Type MAP to authorize one temporary two-minute router mapping'
if ($mapping -cne 'MAP') { throw 'Router mapping was not authorized.' }

$context = Get-ActiveRouteContext
try {
    Add-TemporaryFirewallRule $context
    Write-Output 'BROAD_PROBE_FIREWALL_RULE_ABSENT=True'
    Write-Output 'TEMPORARY_FIREWALL_RULE_ACTIVE=True'
    $probeRole = if ($Action -eq 'Traffic') { 'traffic' } else { 'host' }
    Invoke-Probe -Role $probeRole `
        -ArmedValue 'ALLOW_TEMPORARY_ROUTER_MAPPING'
} finally {
    if ($ruleCreated -or (@(Get-OwnedRule)).Count -gt 0) {
        Remove-TemporaryFirewallRule
        Write-Output 'TEMPORARY_FIREWALL_RULE_REMOVED=True'
    }
}
