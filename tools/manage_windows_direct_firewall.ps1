[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
param(
    [ValidateSet('Status','Add','Remove','SelfTest')]
    [string]$Action = 'Status'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ruleName = 'ThePictureShop.Engineering.Direct.UDP.57842.57844'
$ruleDisplayName = 'The Picture Shop Direct engineering test (UDP 57842 and 57844)'
$ruleGroup = 'The Picture Shop Engineering'
$ruleDescription = 'Owned by manage_windows_direct_firewall.ps1; exact two-guest engineering Direct rule.'
$programPath = [System.IO.Path]::GetFullPath('C:\Program Files\LOVE\lovec.exe')
$directPorts = @('57842','57844')
$directPortList = $directPorts -join ','

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SingleValue {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory=$true)][string]$Expected,
        [switch]$CaseSensitive
    )
    $items = @($Value)
    if ($items.Count -ne 1) { return $false }
    $comparison = [System.StringComparison]::OrdinalIgnoreCase
    if ($CaseSensitive) {
        $comparison = [System.StringComparison]::Ordinal
    }
    return [string]::Equals([string]$items[0],$Expected,$comparison)
}

function Test-UdpProtocol {
    param([AllowNull()]$Value)
    return (Test-SingleValue -Value $Value -Expected 'UDP') -or
        (Test-SingleValue -Value $Value -Expected '17')
}

function Get-PortTokens {
    param([AllowNull()]$Value)
    $tokens = @()
    foreach ($rawValue in @($Value | ForEach-Object { [string]$_ })) {
        foreach ($partValue in $rawValue.Split(',')) {
            $part = $partValue.Trim()
            if (-not [string]::IsNullOrWhiteSpace($part)) { $tokens += $part }
        }
    }
    return @($tokens)
}

function Test-ExactDirectPortSet {
    param([AllowNull()]$Value)
    $tokens = @(Get-PortTokens $Value)
    if ($tokens.Count -ne $directPorts.Count) { return $false }
    foreach ($expected in $directPorts) {
        if (@($tokens | Where-Object { $_ -ceq $expected }).Count -ne 1) {
            return $false
        }
    }
    return $true
}

function Test-OneAllowedProfile {
    param([AllowNull()]$Value)
    foreach ($candidate in @('Public','Private','Domain')) {
        if (Test-SingleValue -Value $Value -Expected $candidate) {
            return $true
        }
    }
    return $false
}

function Test-ProfileApplies {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory=$true)][string]$Expected
    )
    $raw = (@($Value) | ForEach-Object { [string]$_ }) -join ','
    foreach ($candidate in $raw.Split(',')) {
        $trimmed = $candidate.Trim()
        if ($trimmed -ieq 'Any' -or $trimmed -ieq $Expected) {
            return $true
        }
    }
    return $false
}

function Convert-NetworkCategory {
    param([Parameter(Mandatory=$true)]$Category)
    $value = [string]$Category
    if ($value -eq 'DomainAuthenticated') { return 'Domain' }
    if ($value -in @('Public','Private')) { return $value }
    throw 'The active Wi-Fi profile has an unsupported category.'
}

function Get-ActiveWifiContext {
    $candidates = @()
    foreach ($connection in @(Get-NetConnectionProfile -ErrorAction Stop)) {
        if ([string]$connection.IPv6Connectivity -ne 'Internet') { continue }
        $adapter = Get-NetAdapter -InterfaceIndex $connection.InterfaceIndex `
            -IncludeHidden -ErrorAction Stop
        $wireless = ([int]$adapter.NdisPhysicalMedium -eq 9) -or
            ([string]$adapter.PhysicalMediaType -match '802\.11|Wireless')
        if ($adapter.Status -ne 'Up' -or -not $wireless) { continue }
        $alias = [string]$adapter.Name
        if ([string]::IsNullOrWhiteSpace($alias) -or
                $alias -match '[*?\[\]]') {
            throw 'The active Wi-Fi interface name cannot be scoped exactly.'
        }
        $candidates += [pscustomobject]@{
            InterfaceIndex = [int]$connection.InterfaceIndex
            InterfaceAlias = $alias
            FirewallProfile = Convert-NetworkCategory `
                -Category $connection.NetworkCategory
        }
    }
    if ($candidates.Count -ne 1) {
        throw 'Exactly one active Wi-Fi connection with IPv6 Internet access is required.'
    }
    return $candidates[0]
}

function Get-RuleDescriptor {
    param([Parameter(Mandatory=$true)]$Rule)
    $applicationFilters = @($Rule | Get-NetFirewallApplicationFilter `
        -ErrorAction Stop)
    $portFilters = @($Rule | Get-NetFirewallPortFilter `
        -ErrorAction Stop)
    $addressFilters = @($Rule | Get-NetFirewallAddressFilter `
        -ErrorAction Stop)
    $interfaceFilters = @($Rule | Get-NetFirewallInterfaceFilter `
        -ErrorAction Stop)
    $interfaceTypeFilters = @($Rule | Get-NetFirewallInterfaceTypeFilter `
        -ErrorAction Stop)
    $serviceFilters = @($Rule | Get-NetFirewallServiceFilter `
        -ErrorAction Stop)
    return [pscustomobject]@{
        Name = @([string]$Rule.Name)
        DisplayName = @([string]$Rule.DisplayName)
        Group = @([string]$Rule.Group)
        Description = @([string]$Rule.Description)
        Enabled = @([string]$Rule.Enabled)
        Direction = @([string]$Rule.Direction)
        Action = @([string]$Rule.Action)
        Profile = @([string]$Rule.Profile)
        EdgeTraversalPolicy = @([string]$Rule.EdgeTraversalPolicy)
        PrimaryStatus = @([string]$Rule.PrimaryStatus)
        Program = @($applicationFilters | ForEach-Object { [string]$_.Program })
        Protocol = @($portFilters | ForEach-Object { [string]$_.Protocol })
        LocalPort = @($portFilters | ForEach-Object { [string]$_.LocalPort })
        RemotePort = @($portFilters | ForEach-Object { [string]$_.RemotePort })
        LocalAddress = @($addressFilters | ForEach-Object { [string]$_.LocalAddress })
        RemoteAddress = @($addressFilters | ForEach-Object { [string]$_.RemoteAddress })
        InterfaceAlias = @($interfaceFilters | ForEach-Object {
            [string]$_.InterfaceAlias
        })
        InterfaceType = @($interfaceTypeFilters | ForEach-Object {
            [string]$_.InterfaceType
        })
        Service = @($serviceFilters | ForEach-Object { [string]$_.Service })
    }
}

function Test-OwnedNarrowDescriptor {
    param([Parameter(Mandatory=$true)]$Descriptor)
    if (-not (Test-SingleValue $Descriptor.Name $ruleName -CaseSensitive) -or
            -not (Test-SingleValue $Descriptor.DisplayName $ruleDisplayName `
                -CaseSensitive) -or
            -not (Test-SingleValue $Descriptor.Group $ruleGroup `
                -CaseSensitive) -or
            -not (Test-SingleValue $Descriptor.Description $ruleDescription `
                -CaseSensitive) -or
            -not (Test-SingleValue $Descriptor.Program $programPath) -or
            -not (Test-SingleValue $Descriptor.Direction 'Inbound') -or
            -not (Test-SingleValue $Descriptor.Action 'Allow') -or
            -not (Test-UdpProtocol $Descriptor.Protocol) -or
            -not (Test-ExactDirectPortSet $Descriptor.LocalPort) -or
            -not (Test-SingleValue $Descriptor.RemotePort 'Any') -or
            -not (Test-SingleValue $Descriptor.LocalAddress 'Any') -or
            -not (Test-SingleValue $Descriptor.RemoteAddress 'Internet6') -or
            -not (Test-SingleValue $Descriptor.InterfaceType 'Wireless') -or
            -not (Test-SingleValue $Descriptor.EdgeTraversalPolicy 'Block') -or
            -not (Test-SingleValue $Descriptor.Service 'Any') -or
            -not (Test-OneAllowedProfile $Descriptor.Profile)) {
        return $false
    }
    $aliases = @($Descriptor.InterfaceAlias)
    return $aliases.Count -eq 1 -and
        -not [string]::IsNullOrWhiteSpace([string]$aliases[0]) -and
        [string]$aliases[0] -ine 'Any' -and
        [string]$aliases[0] -notmatch '[*?\[\]]'
}

function Test-ExactDescriptorForContext {
    param(
        [Parameter(Mandatory=$true)]$Descriptor,
        [Parameter(Mandatory=$true)]$Context
    )
    return (Test-OwnedNarrowDescriptor $Descriptor) -and
        (Test-SingleValue $Descriptor.Enabled 'True') -and
        (Test-SingleValue $Descriptor.PrimaryStatus 'OK') -and
        (Test-SingleValue $Descriptor.Profile $Context.FirewallProfile) -and
        (Test-SingleValue $Descriptor.InterfaceAlias $Context.InterfaceAlias)
}

function Test-BroadLoveDescriptor {
    param(
        [Parameter(Mandatory=$true)]$Descriptor,
        [AllowNull()]$Context
    )
    if (-not (Test-SingleValue $Descriptor.Program $programPath) -or
            -not (Test-SingleValue $Descriptor.Enabled 'True') -or
            -not (Test-SingleValue $Descriptor.Direction 'Inbound') -or
            -not (Test-SingleValue $Descriptor.Action 'Allow')) {
        return $false
    }
    $protocolIsBroadUdp = (Test-UdpProtocol $Descriptor.Protocol) -or
        (Test-SingleValue $Descriptor.Protocol 'Any')
    if (-not $protocolIsBroadUdp) { return $false }
    if (-not (Test-PortIncludesDirect $Descriptor.LocalPort) -or
            -not (Test-PortIncludesDirect $Descriptor.RemotePort)) {
        return $false
    }
    if ($null -ne $Context -and -not (Test-ProfileApplies `
            $Descriptor.Profile $Context.FirewallProfile)) {
        return $false
    }
    if (-not (Test-SingleValue $Descriptor.LocalAddress 'Any') -or
            -not (Test-InternetIpv6Scope $Descriptor.RemoteAddress) -or
            -not (Test-WirelessInterfaceApplies `
                $Descriptor.InterfaceAlias $Descriptor.InterfaceType $Context)) {
        return $false
    }
    if ($null -ne $Context -and
            (Test-ExactSecurityScopeForContext $Descriptor $Context)) {
        return $false
    }
    return $true
}

function Test-PortIncludesDirect {
    param([AllowNull()]$Value)
    foreach ($part in @(Get-PortTokens $Value)) {
        if ($part -ieq 'Any' -or $part -in $directPorts) { return $true }
        $range = [regex]::Match($part,'^(\d{1,5})-(\d{1,5})$')
        if ($range.Success) {
            $lower = [int]$range.Groups[1].Value
            $upper = [int]$range.Groups[2].Value
            foreach ($directPort in $directPorts) {
                if ($lower -le [int]$directPort -and
                        [int]$directPort -le $upper) {
                    return $true
                }
            }
        }
    }
    return $false
}

function Test-InternetIpv6Scope {
    param([AllowNull()]$Value)
    foreach ($rawValue in @($Value | ForEach-Object { [string]$_ })) {
        foreach ($partValue in $rawValue.Split(',')) {
            if ($partValue.Trim() -in @('Any','Internet','Internet6')) {
                return $true
            }
        }
    }
    return $false
}

function Test-WirelessInterfaceApplies {
    param(
        [AllowNull()]$Aliases,
        [AllowNull()]$Types,
        [AllowNull()]$Context
    )
    $typeApplies = (Test-SingleValue $Types 'Any') -or
        (Test-SingleValue $Types 'Wireless')
    if (-not $typeApplies) { return $false }
    if ($null -eq $Context) { return $true }
    foreach ($rawAlias in @($Aliases | ForEach-Object { [string]$_ })) {
        if ($rawAlias -ieq 'Any') { return $true }
        try {
            if ([System.Management.Automation.WildcardPattern]::new(
                    $rawAlias,
                    [System.Management.Automation.WildcardOptions]::IgnoreCase).
                    IsMatch([string]$Context.InterfaceAlias)) {
                return $true
            }
        } catch [System.Management.Automation.WildcardPatternException] {
            continue
        }
    }
    return $false
}

function Test-ExactSecurityScopeForContext {
    param(
        [Parameter(Mandatory=$true)]$Descriptor,
        [Parameter(Mandatory=$true)]$Context
    )
    return (Test-UdpProtocol $Descriptor.Protocol) -and
        (Test-ExactDirectPortSet $Descriptor.LocalPort) -and
        (Test-SingleValue $Descriptor.RemotePort 'Any') -and
        (Test-SingleValue $Descriptor.LocalAddress 'Any') -and
        (Test-SingleValue $Descriptor.RemoteAddress 'Internet6') -and
        (Test-SingleValue $Descriptor.Profile $Context.FirewallProfile) -and
        (Test-SingleValue $Descriptor.InterfaceAlias $Context.InterfaceAlias) -and
        (Test-SingleValue $Descriptor.InterfaceType 'Wireless') -and
        (Test-SingleValue $Descriptor.EdgeTraversalPolicy 'Block')
}

function Get-RulesByOwnedName {
    param([Parameter(Mandatory=$true)][string]$PolicyStore)
    return @(Get-NetFirewallRule -PolicyStore $PolicyStore -ErrorAction Stop |
        Where-Object { [string]$_.Name -ieq $ruleName })
}

function Get-BroadLoveRuleCount {
    param([AllowNull()]$Context)
    $count = 0
    $filters = @(Get-NetFirewallApplicationFilter -PolicyStore ActiveStore `
        -ErrorAction Stop | Where-Object {
            [string]$_.Program -ieq $programPath
        })
    foreach ($applicationFilter in $filters) {
        foreach ($candidateRule in @($applicationFilter | Get-NetFirewallRule `
                -ErrorAction Stop)) {
            if (Test-BroadLoveDescriptor `
                    (Get-RuleDescriptor $candidateRule) $Context) {
                $count++
            }
        }
    }
    return $count
}

function Test-ActiveFirewallProfileEnabled {
    param([Parameter(Mandatory=$true)]$Context)
    $activeProfile = Get-NetFirewallProfile -Name $Context.FirewallProfile `
        -PolicyStore ActiveStore -ErrorAction Stop
    return [string]$activeProfile.Enabled -eq 'True'
}

function Assert-ElevatedMutation {
    if (-not (Test-IsElevated)) {
        throw 'Add and Remove require an already-elevated PowerShell window. Status and SelfTest do not.'
    }
}

function Write-BroadRuleCaveat {
    param([int]$Count)
    Write-Output "BROAD_LOVE_RULE_OBSERVED=$($Count -gt 0)"
    if ($Count -gt 0) {
        Write-Output ('BROAD_RULE_CAVEAT=An existing LOVE rule allows more than UDP ' +
            '57842 and 57844. This helper will not change user-owned or Windows-owned rules; ' +
            'the narrow rule cannot reduce that separate allowance.')
    } else {
        Write-Output 'BROAD_RULE_CAVEAT=None observed for the active Wi-Fi profile.'
    }
}

function Invoke-Status {
    $wifiContext = $null
    try {
        $wifiContext = Get-ActiveWifiContext
    } catch {
        $wifiContext = $null
    }
    $activeProfileEnabled = $false
    if ($wifiContext) {
        $activeProfileEnabled = Test-ActiveFirewallProfileEnabled $wifiContext
    }
    $persistentRules = @(Get-RulesByOwnedName -PolicyStore PersistentStore)
    $activeRules = @(Get-RulesByOwnedName -PolicyStore ActiveStore)
    $broadCount = Get-BroadLoveRuleCount -Context $wifiContext

    $status = 'ABSENT'
    $exactForContext = $false
    $ownedAndNarrow = $false
    if ($persistentRules.Count -gt 1 -or $activeRules.Count -gt 1) {
        $status = 'RESERVED_NAME_CONFLICT'
    } elseif ($persistentRules.Count -eq 1) {
        $persistentDescriptor = Get-RuleDescriptor $persistentRules[0]
        $ownedAndNarrow = Test-OwnedNarrowDescriptor $persistentDescriptor
        if (-not $ownedAndNarrow) {
            $status = 'RESERVED_NAME_MISMATCH'
        } elseif ($null -eq $wifiContext) {
            $status = 'OWNED_RULE_WIFI_UNAVAILABLE'
        } elseif ($activeRules.Count -ne 1) {
            $status = 'OWNED_RULE_NOT_ACTIVE'
        } else {
            $descriptorMatchesContext = Test-ExactDescriptorForContext `
                (Get-RuleDescriptor $activeRules[0]) $wifiContext
            if ($descriptorMatchesContext -and $activeProfileEnabled) {
                $exactForContext = $true
                $status = 'EXACT_ACTIVE'
            } elseif ($descriptorMatchesContext) {
                $status = 'OWNED_RULE_FIREWALL_DISABLED'
            } else {
                $status = 'OWNED_RULE_WRONG_CONTEXT'
            }
        }
    } elseif ($activeRules.Count -gt 0) {
        $status = 'RESERVED_NAME_NOT_LOCAL'
    }

    Write-Output "TPS_WINDOWS_DIRECT_FIREWALL_STATUS=$status"
    Write-Output "OWNED_NARROW_RULE_PRESENT=$ownedAndNarrow"
    Write-Output "EXACT_RULE_ACTIVE=$exactForContext"
    if ($wifiContext) {
        Write-Output "ACTIVE_WIFI_INTERFACE=$($wifiContext.InterfaceAlias)"
        Write-Output "ACTIVE_WIFI_PROFILE=$($wifiContext.FirewallProfile)"
        Write-Output "ACTIVE_FIREWALL_PROFILE_ENABLED=$activeProfileEnabled"
    } else {
        Write-Output 'ACTIVE_WIFI_CONTEXT=UNAVAILABLE'
        Write-Output ('WIFI_CONTEXT_GUIDANCE=Connect exactly one Wi-Fi interface with ' +
            'IPv6 Internet access, then rerun Status or Add.')
    }
    Write-BroadRuleCaveat -Count $broadCount
}

function Add-OwnedRule {
    param([Parameter(Mandatory=$true)]$Invocation)
    Assert-ElevatedMutation
    if (-not (Test-Path -LiteralPath $programPath -PathType Leaf)) {
        throw 'The exact LOVE console executable is not installed at the expected path.'
    }
    $wifiContext = Get-ActiveWifiContext
    if (-not (Test-ActiveFirewallProfileEnabled $wifiContext)) {
        throw 'Windows Firewall is disabled for the active Wi-Fi profile; the helper will not weaken this configuration.'
    }
    $persistentBefore = @(Get-RulesByOwnedName -PolicyStore PersistentStore)
    $activeBefore = @(Get-RulesByOwnedName -PolicyStore ActiveStore)
    if ($persistentBefore.Count -gt 1 -or $activeBefore.Count -gt 1) {
        throw 'The reserved firewall-rule name has a conflict; no rule was changed.'
    }
    if ($persistentBefore.Count -eq 1) {
        $alreadyExact = (Test-ExactDescriptorForContext `
            (Get-RuleDescriptor $persistentBefore[0]) $wifiContext) -and
            $activeBefore.Count -eq 1 -and
            (Test-ExactDescriptorForContext `
                (Get-RuleDescriptor $activeBefore[0]) $wifiContext)
        if (-not $alreadyExact) {
            throw 'The reserved firewall-rule name exists but is not the exact owned rule; no rule was changed.'
        }
        Write-Output 'TPS_WINDOWS_DIRECT_FIREWALL_ADD=ALREADY_PRESENT'
        Write-BroadRuleCaveat -Count (Get-BroadLoveRuleCount $wifiContext)
        return
    }
    if ($activeBefore.Count -ne 0) {
        throw 'The reserved firewall-rule name is supplied by another policy; no rule was changed.'
    }
    if (-not $Invocation.ShouldProcess($ruleName,
            'Create the exact engineering Direct firewall rule')) {
        Write-Output 'TPS_WINDOWS_DIRECT_FIREWALL_ADD=NO_CHANGE'
        return
    }

    $created = $false
    try {
        New-NetFirewallRule -PolicyStore PersistentStore -Name $ruleName `
            -DisplayName $ruleDisplayName -Group $ruleGroup `
            -Description $ruleDescription -Enabled True -Direction Inbound `
            -Action Allow -Profile $wifiContext.FirewallProfile `
            -Program $programPath -Protocol UDP -LocalPort $directPorts `
            -RemoteAddress Internet6 -InterfaceAlias $wifiContext.InterfaceAlias `
            -InterfaceType Wireless -EdgeTraversalPolicy Block | Out-Null
        $created = $true
        $persistentAfter = @(Get-RulesByOwnedName -PolicyStore PersistentStore)
        $activeAfter = @(Get-RulesByOwnedName -PolicyStore ActiveStore)
        if ($persistentAfter.Count -ne 1 -or $activeAfter.Count -ne 1 -or
                -not (Test-ExactDescriptorForContext `
                    (Get-RuleDescriptor $persistentAfter[0]) $wifiContext) -or
                -not (Test-ExactDescriptorForContext `
                    (Get-RuleDescriptor $activeAfter[0]) $wifiContext)) {
            throw 'The created rule did not become the exact active rule.'
        }
    } catch {
        if ($created) {
            $rollback = @(Get-RulesByOwnedName -PolicyStore PersistentStore)
            if ($rollback.Count -eq 1 -and
                    (Test-OwnedNarrowDescriptor `
                        (Get-RuleDescriptor $rollback[0]))) {
                Remove-NetFirewallRule -Name $ruleName `
                    -PolicyStore PersistentStore -Confirm:$false
            }
        }
        throw
    }
    Write-Output 'TPS_WINDOWS_DIRECT_FIREWALL_ADD=CREATED'
    Write-Output 'RULE_SCOPE=lovec.exe UDP 57842 and 57844, active Wi-Fi profile/interface, Internet IPv6 only'
    Write-BroadRuleCaveat -Count (Get-BroadLoveRuleCount $wifiContext)
}

function Remove-OwnedRule {
    param([Parameter(Mandatory=$true)]$Invocation)
    Assert-ElevatedMutation
    $persistentRules = @(Get-RulesByOwnedName -PolicyStore PersistentStore)
    $activeRules = @(Get-RulesByOwnedName -PolicyStore ActiveStore)
    if ($persistentRules.Count -eq 0) {
        if ($activeRules.Count -gt 0) {
            throw 'The reserved rule name is supplied by another policy; no rule was changed.'
        }
        Write-Output 'TPS_WINDOWS_DIRECT_FIREWALL_REMOVE=ALREADY_ABSENT'
        Write-BroadRuleCaveat -Count (Get-BroadLoveRuleCount -Context $null)
        return
    }
    if ($persistentRules.Count -ne 1 -or $activeRules.Count -gt 1) {
        throw 'The reserved firewall-rule name has a conflict; no rule was changed.'
    }
    $descriptor = Get-RuleDescriptor $persistentRules[0]
    if (-not (Test-OwnedNarrowDescriptor $descriptor)) {
        throw 'The reserved firewall-rule name is not the exact owned narrow rule; no rule was changed.'
    }
    if (-not $Invocation.ShouldProcess($ruleName,
            'Remove the validated owned engineering Direct firewall rule')) {
        Write-Output 'TPS_WINDOWS_DIRECT_FIREWALL_REMOVE=NO_CHANGE'
        return
    }
    Remove-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore `
        -Confirm:$false
    if (@(Get-RulesByOwnedName -PolicyStore PersistentStore).Count -ne 0 -or
            @(Get-RulesByOwnedName -PolicyStore ActiveStore).Count -ne 0) {
        throw 'The owned firewall rule could not be verified absent.'
    }
    Write-Output 'TPS_WINDOWS_DIRECT_FIREWALL_REMOVE=REMOVED'
    Write-Output 'OTHER_FIREWALL_RULES_CHANGED=False'
    Write-BroadRuleCaveat -Count (Get-BroadLoveRuleCount -Context $null)
}

function Copy-TestDescriptor {
    param([Parameter(Mandatory=$true)]$Source)
    $copy = [ordered]@{}
    foreach ($property in $Source.PSObject.Properties) {
        $copy[$property.Name] = @($property.Value)
    }
    return [pscustomobject]$copy
}

function Invoke-SelfTest {
    $testContext = [pscustomobject]@{
        InterfaceAlias = 'Test Wi-Fi'
        FirewallProfile = 'Public'
    }
    $exact = [pscustomobject]@{
        Name = @($ruleName); DisplayName = @($ruleDisplayName)
        Group = @($ruleGroup); Description = @($ruleDescription)
        Enabled = @('True'); Direction = @('Inbound'); Action = @('Allow')
        Profile = @('Public'); EdgeTraversalPolicy = @('Block')
        PrimaryStatus = @('OK'); Program = @($programPath)
        Protocol = @('UDP'); LocalPort = @($directPorts); RemotePort = @('Any')
        LocalAddress = @('Any'); RemoteAddress = @('Internet6')
        InterfaceAlias = @('Test Wi-Fi'); InterfaceType = @('Wireless')
        Service = @('Any')
    }
    $counter = [pscustomobject]@{ Value = 0 }
    function Assert-Test {
        param([bool]$Condition,[string]$Name)
        if (-not $Condition) { throw "Firewall self-test failed: $Name" }
        $counter.Value++
    }
    Assert-Test (Test-OwnedNarrowDescriptor $exact) 'exact-owned'
    Assert-Test (Test-ExactDescriptorForContext $exact $testContext) 'exact-context'
    Assert-Test (-not (Test-BroadLoveDescriptor $exact $testContext)) 'exact-not-broad'
    $reversedPorts = Copy-TestDescriptor $exact
    $reversedPorts.LocalPort = @('57844','57842')
    Assert-Test (Test-ExactDirectPortSet $reversedPorts.LocalPort) `
        'accept-exact-port-set-in-any-order'
    $missingSecondPort = Copy-TestDescriptor $exact
    $missingSecondPort.LocalPort = @('57842')
    Assert-Test (-not (Test-OwnedNarrowDescriptor $missingSecondPort)) `
        'reject-missing-second-port'
    $wrongPort = Copy-TestDescriptor $exact
    $wrongPort.LocalPort = @('Any')
    Assert-Test (-not (Test-OwnedNarrowDescriptor $wrongPort)) 'reject-any-port'
    Assert-Test (Test-BroadLoveDescriptor $wrongPort $testContext) 'detect-broad-port'
    $wrongProgram = Copy-TestDescriptor $exact
    $wrongProgram.Program = @('C:\Other\lovec.exe')
    Assert-Test (-not (Test-OwnedNarrowDescriptor $wrongProgram)) 'reject-program'
    $wrongOwner = Copy-TestDescriptor $exact
    $wrongOwner.Group = @('Other')
    Assert-Test (-not (Test-OwnedNarrowDescriptor $wrongOwner)) 'reject-owner'
    $wrongInterface = Copy-TestDescriptor $exact
    $wrongInterface.InterfaceAlias = @('Other Wi-Fi')
    Assert-Test (-not (Test-ExactDescriptorForContext `
        $wrongInterface $testContext)) 'reject-wrong-interface'
    Assert-Test (Test-OwnedNarrowDescriptor $wrongInterface) `
        'permit-safe-old-interface-removal'
    $anyInterface = Copy-TestDescriptor $exact
    $anyInterface.InterfaceAlias = @('Any')
    Assert-Test (-not (Test-OwnedNarrowDescriptor $anyInterface)) `
        'reject-any-interface'
    $wrongScope = Copy-TestDescriptor $exact
    $wrongScope.RemoteAddress = @('Any')
    Assert-Test (-not (Test-OwnedNarrowDescriptor $wrongScope)) 'reject-any-address'
    $wrongProfile = Copy-TestDescriptor $exact
    $wrongProfile.Profile = @('Any')
    Assert-Test (-not (Test-OwnedNarrowDescriptor $wrongProfile)) 'reject-any-profile'
    $portRange = Copy-TestDescriptor $exact
    $portRange.LocalPort = @('57000-58000')
    Assert-Test (Test-BroadLoveDescriptor $portRange $testContext) `
        'detect-containing-port-range'
    $portList = Copy-TestDescriptor $exact
    $portList.LocalPort = @('80,57842')
    Assert-Test (Test-BroadLoveDescriptor $portList $testContext) `
        'detect-containing-port-list'
    $anyProtocol = Copy-TestDescriptor $exact
    $anyProtocol.Protocol = @('Any')
    Assert-Test (Test-BroadLoveDescriptor $anyProtocol $testContext) `
        'detect-any-protocol'
    $broadInterface = Copy-TestDescriptor $exact
    $broadInterface.InterfaceAlias = @('Any')
    Assert-Test (Test-BroadLoveDescriptor $broadInterface $testContext) `
        'detect-any-interface'
    $unrelatedInterface = Copy-TestDescriptor $wrongPort
    $unrelatedInterface.InterfaceAlias = @('Other Wi-Fi')
    Assert-Test (-not (Test-BroadLoveDescriptor `
        $unrelatedInterface $testContext)) 'ignore-other-interface'
    $localSubnetOnly = Copy-TestDescriptor $wrongPort
    $localSubnetOnly.RemoteAddress = @('LocalSubnet6')
    Assert-Test (-not (Test-BroadLoveDescriptor `
        $localSubnetOnly $testContext)) 'ignore-local-subnet-only'
    $sameScopeOtherOwner = Copy-TestDescriptor $exact
    $sameScopeOtherOwner.Group = @('Other')
    Assert-Test (-not (Test-BroadLoveDescriptor `
        $sameScopeOtherOwner $testContext)) 'equivalent-scope-not-broad'
    $anyRemote = Copy-TestDescriptor $exact
    $anyRemote.RemoteAddress = @('Any')
    Assert-Test (Test-BroadLoveDescriptor $anyRemote $testContext) `
        'detect-any-remote-address'
    Write-Output ("TPS_WINDOWS_DIRECT_FIREWALL_SELF_TEST=PASS CHECKS=" +
        $counter.Value)
}

switch ($Action) {
    'Status' { Invoke-Status }
    'Add' { Add-OwnedRule -Invocation $PSCmdlet }
    'Remove' { Remove-OwnedRule -Invocation $PSCmdlet }
    'SelfTest' { Invoke-SelfTest }
}
