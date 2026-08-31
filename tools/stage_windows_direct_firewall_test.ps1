[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
param(
    [ValidateSet('Status','Prepare','Restore','SelfTest')]
    [string]$Action = 'Status'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ownedRuleName = 'ThePictureShop.Engineering.Direct.UDP.57842.57844'
$programPath = [IO.Path]::GetFullPath('C:\Program Files\LOVE\lovec.exe')
$directPorts = @('57842','57844')
$ownedHelper = Join-Path $PSScriptRoot 'manage_windows_direct_firewall.ps1'
$programDataPath = [IO.Path]::GetFullPath(
    [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::CommonApplicationData))
$journalRoot = Join-Path $programDataPath `
    'ThePictureShopEngineeringFirewallStage'
$journalPath = Join-Path $journalRoot 'windows-direct-firewall-stage-v1.json'
$mutexName = 'Global\ThePictureShop.WindowsDirectFirewallStage.v1'
$journalContract = 'tps_windows_direct_firewall_stage_v1'
$administratorSid = [Security.Principal.SecurityIdentifier]::new(
    [Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid,$null)
$systemSid = [Security.Principal.SecurityIdentifier]::new(
    [Security.Principal.WellKnownSidType]::LocalSystemSid,$null)
$currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-ElevatedMutation {
    if (-not (Test-IsElevated)) {
        throw 'Prepare and Restore require an already-elevated PowerShell process.'
    }
}

function New-JournalAccessRule {
    param(
        [Parameter(Mandatory=$true)]
        [Security.Principal.SecurityIdentifier]$Identity,
        [Parameter(Mandatory=$true)]
        [Security.AccessControl.FileSystemRights]$Rights,
        [switch]$Directory
    )
    $inheritance = $Directory ?
        ([Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit') :
        [Security.AccessControl.InheritanceFlags]::None
    return [Security.AccessControl.FileSystemAccessRule]::new(
        $Identity,$Rights,$inheritance,
        [Security.AccessControl.PropagationFlags]::None,
        [Security.AccessControl.AccessControlType]::Allow)
}

function Set-SecureJournalDirectoryAcl {
    param([Parameter(Mandatory=$true)][string]$Path)
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner($administratorSid)
    $acl.AddAccessRule((New-JournalAccessRule -Identity $administratorSid `
        -Rights FullControl -Directory))
    $acl.AddAccessRule((New-JournalAccessRule -Identity $systemSid `
        -Rights FullControl -Directory))
    $acl.AddAccessRule((New-JournalAccessRule -Identity $currentUserSid `
        -Rights ReadAndExecute -Directory))
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Set-SecureJournalFileAcl {
    param([Parameter(Mandatory=$true)][string]$Path)
    $acl = [Security.AccessControl.FileSecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner($administratorSid)
    $acl.AddAccessRule((New-JournalAccessRule -Identity $administratorSid `
        -Rights FullControl))
    $acl.AddAccessRule((New-JournalAccessRule -Identity $systemSid `
        -Rights FullControl))
    $acl.AddAccessRule((New-JournalAccessRule -Identity $currentUserSid `
        -Rights ReadAndExecute))
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Assert-SecureJournalAcl {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ValidateSet('Directory','File')]
        [string]$Kind
    )
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $owner = ([Security.Principal.NTAccount]$acl.Owner).Translate(
        [Security.Principal.SecurityIdentifier])
    if ($owner.Value -cne $administratorSid.Value -or
            -not $acl.AreAccessRulesProtected) {
        throw 'The firewall recovery journal owner or inheritance is unsafe.'
    }
    $rules = @($acl.GetAccessRules($true,$true,
        [Security.Principal.SecurityIdentifier]))
    $seenAdministrator = $false
    $seenSystem = $false
    $seenCurrentUser = $false
    $writeMask = [Security.AccessControl.FileSystemRights]::WriteData -bor
        [Security.AccessControl.FileSystemRights]::CreateFiles -bor
        [Security.AccessControl.FileSystemRights]::AppendData -bor
        [Security.AccessControl.FileSystemRights]::CreateDirectories -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership -bor
        [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes
    foreach ($rule in $rules) {
        if ($rule.AccessControlType -ne
                [Security.AccessControl.AccessControlType]::Allow) {
            throw 'The firewall recovery journal has an unexpected deny rule.'
        }
        $sid = ([Security.Principal.SecurityIdentifier]$rule.IdentityReference).Value
        if ($sid -ceq $administratorSid.Value -or $sid -ceq $systemSid.Value) {
            if (($rule.FileSystemRights -band
                    [Security.AccessControl.FileSystemRights]::FullControl) -ne
                    [Security.AccessControl.FileSystemRights]::FullControl) {
                throw 'The firewall recovery journal lacks required recovery access.'
            }
            if ($sid -ceq $administratorSid.Value) { $seenAdministrator = $true }
            if ($sid -ceq $systemSid.Value) { $seenSystem = $true }
            continue
        }
        if ($sid -ceq $currentUserSid.Value) {
            if (($rule.FileSystemRights -band $writeMask) -ne 0 -or
                    ($rule.FileSystemRights -band
                        [Security.AccessControl.FileSystemRights]::ReadAndExecute) -ne
                        [Security.AccessControl.FileSystemRights]::ReadAndExecute) {
                throw 'The standard user can modify the firewall recovery journal.'
            }
            $seenCurrentUser = $true
            continue
        }
        throw 'The firewall recovery journal grants access to an unexpected identity.'
    }
    if (-not $seenAdministrator -or -not $seenSystem -or
            -not $seenCurrentUser) {
        throw 'The firewall recovery journal ACL is incomplete.'
    }
    if ($Kind -eq 'Directory') {
        $item = Get-Item -LiteralPath $Path -Force
        if (-not $item.PSIsContainer) {
            throw 'The firewall recovery journal root is not a directory.'
        }
    }
    return $true
}

function Test-JournalRootPresentAndSecure {
    $base = Get-Item -LiteralPath $programDataPath -Force -ErrorAction Stop
    if (-not $base.PSIsContainer -or
            ($base.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            [IO.Path]::GetFullPath($base.FullName).TrimEnd('\') -cne
                $programDataPath.TrimEnd('\')) {
        throw 'The ProgramData recovery base is unsafe.'
    }
    if (-not (Test-Path -LiteralPath $journalRoot)) { return $false }
    $root = Get-Item -LiteralPath $journalRoot -Force -ErrorAction Stop
    if (-not $root.PSIsContainer -or
            ($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            [IO.Path]::GetFullPath($root.Parent.FullName).TrimEnd('\') -cne
                $programDataPath.TrimEnd('\')) {
        throw 'The firewall recovery journal root is unsafe.'
    }
    Assert-SecureJournalAcl -Path $journalRoot -Kind Directory | Out-Null
    return $true
}

function Initialize-SecureJournalRoot {
    if (Test-JournalRootPresentAndSecure) { return }
    Assert-ElevatedMutation
    New-Item -ItemType Directory -Path $journalRoot -ErrorAction Stop | Out-Null
    Set-SecureJournalDirectoryAcl $journalRoot
    Assert-SecureJournalAcl -Path $journalRoot -Kind Directory | Out-Null
    if (@(Get-ChildItem -LiteralPath $journalRoot -Force -ErrorAction Stop).Count -ne 0) {
        throw 'The new firewall recovery journal root was not empty.'
    }
}

function Assert-SecureJournalFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-JournalRootPresentAndSecure)) {
        throw 'The firewall recovery journal root is missing.'
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            [IO.Path]::GetFullPath($item.Directory.FullName).TrimEnd('\') -cne
                [IO.Path]::GetFullPath($journalRoot).TrimEnd('\')) {
        throw 'The firewall recovery journal file is unsafe.'
    }
    Assert-SecureJournalAcl -Path $Path -Kind File | Out-Null
    return $true
}

function Get-Sha256Text {
    param([Parameter(Mandatory=$true)][string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    } finally {
        [Array]::Clear($bytes,0,$bytes.Length)
    }
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
            throw 'The active Wi-Fi interface cannot be scoped exactly.'
        }
        $profile = Convert-NetworkCategory $connection.NetworkCategory
        $firewallProfile = Get-NetFirewallProfile -Name $profile `
            -PolicyStore ActiveStore -ErrorAction Stop
        if (@($firewallProfile).Count -ne 1 -or
                [string]$firewallProfile.Enabled -ne 'True') {
            throw 'Windows Firewall is not enabled for the active Wi-Fi profile.'
        }
        $candidates += [pscustomobject]@{
            Alias = $alias
            Profile = $profile
            InterfaceIndex = [int]$connection.InterfaceIndex
        }
    }
    if ($candidates.Count -ne 1) {
        throw 'Exactly one active Wi-Fi connection with IPv6 Internet access is required.'
    }
    $context = $candidates[0]
    $contextText = @(
        $context.Alias.ToLowerInvariant(),
        $context.Profile.ToLowerInvariant(),
        [string]$context.InterfaceIndex,
        'firewall=true') -join "`n"
    $context | Add-Member -NotePropertyName Hash -NotePropertyValue `
        (Get-Sha256Text $contextText)
    return $context
}

function Get-NormalizedTokens {
    param(
        [AllowNull()]$Value,
        [switch]$SplitComma
    )
    $tokens = @()
    foreach ($raw in @($Value | ForEach-Object { [string]$_ })) {
        $parts = $SplitComma ? $raw.Split(',') : @($raw)
        foreach ($part in $parts) {
            $trimmed = $part.Trim()
            if (-not [string]::IsNullOrEmpty($trimmed)) {
                $tokens += $trimmed.ToLowerInvariant()
            }
        }
    }
    return @($tokens | Sort-Object -Unique)
}

function Get-SingleFilter {
    param(
        [Parameter(Mandatory=$true)]$Rule,
        [Parameter(Mandatory=$true)][ValidateSet(
            'Application','Port','Address','Interface','InterfaceType','Service')]
        [string]$Kind
    )
    $filters = switch ($Kind) {
        'Application' { @($Rule | Get-NetFirewallApplicationFilter -ErrorAction Stop) }
        'Port' { @($Rule | Get-NetFirewallPortFilter -ErrorAction Stop) }
        'Address' { @($Rule | Get-NetFirewallAddressFilter -ErrorAction Stop) }
        'Interface' { @($Rule | Get-NetFirewallInterfaceFilter -ErrorAction Stop) }
        'InterfaceType' { @($Rule | Get-NetFirewallInterfaceTypeFilter -ErrorAction Stop) }
        'Service' { @($Rule | Get-NetFirewallServiceFilter -ErrorAction Stop) }
    }
    if ($filters.Count -ne 1) {
        throw "A LÖVE firewall rule has an ambiguous $Kind filter."
    }
    return $filters[0]
}

function Get-RuleRecord {
    param([Parameter(Mandatory=$true)]$Rule)
    $application = Get-SingleFilter -Rule $Rule -Kind Application
    $port = Get-SingleFilter -Rule $Rule -Kind Port
    $address = Get-SingleFilter -Rule $Rule -Kind Address
    $interface = Get-SingleFilter -Rule $Rule -Kind Interface
    $interfaceType = Get-SingleFilter -Rule $Rule -Kind InterfaceType
    $service = Get-SingleFilter -Rule $Rule -Kind Service
    return [pscustomobject][ordered]@{
        Name = [string]$Rule.Name
        Source = [string]$Rule.PolicyStoreSource
        SourceType = [string]$Rule.PolicyStoreSourceType
        Enabled = [string]$Rule.Enabled
        Direction = [string]$Rule.Direction
        Action = [string]$Rule.Action
        Profile = @(Get-NormalizedTokens $Rule.Profile -SplitComma)
        Edge = [string]$Rule.EdgeTraversalPolicy
        Program = [IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables([string]$application.Program))
        Protocol = @(Get-NormalizedTokens $port.Protocol -SplitComma)
        LocalPort = @(Get-NormalizedTokens $port.LocalPort -SplitComma)
        RemotePort = @(Get-NormalizedTokens $port.RemotePort -SplitComma)
        LocalAddress = @(Get-NormalizedTokens $address.LocalAddress -SplitComma)
        RemoteAddress = @(Get-NormalizedTokens $address.RemoteAddress -SplitComma)
        InterfaceAlias = @(Get-NormalizedTokens $interface.InterfaceAlias)
        InterfaceType = @(Get-NormalizedTokens $interfaceType.InterfaceType -SplitComma)
        Service = @(Get-NormalizedTokens $service.Service -SplitComma)
    }
}

function Get-RuleHash {
    param(
        [Parameter(Mandatory=$true)]$Record,
        [switch]$IncludeEnabled
    )
    $canonical = [ordered]@{
        name = ([string]$Record.Name).ToLowerInvariant()
        source = ([string]$Record.Source).ToLowerInvariant()
        sourceType = ([string]$Record.SourceType).ToLowerInvariant()
        direction = ([string]$Record.Direction).ToLowerInvariant()
        action = ([string]$Record.Action).ToLowerInvariant()
        profile = @($Record.Profile)
        edge = ([string]$Record.Edge).ToLowerInvariant()
        program = ([string]$Record.Program).ToLowerInvariant()
        protocol = @($Record.Protocol)
        localPort = @($Record.LocalPort)
        remotePort = @($Record.RemotePort)
        localAddress = @($Record.LocalAddress)
        remoteAddress = @($Record.RemoteAddress)
        interfaceAlias = @($Record.InterfaceAlias)
        interfaceType = @($Record.InterfaceType)
        service = @($Record.Service)
    }
    if ($IncludeEnabled) {
        $canonical.enabled = ([string]$Record.Enabled).ToLowerInvariant()
    }
    return Get-Sha256Text ($canonical | ConvertTo-Json -Compress -Depth 5)
}

function Get-ProgramRuleRecords {
    $records = [ordered]@{}
    $filters = @(Get-NetFirewallApplicationFilter -Program $programPath `
        -PolicyStore ActiveStore -ErrorAction Stop)
    foreach ($filter in $filters) {
        $rules = @($filter | Get-NetFirewallRule -ErrorAction Stop)
        if ($rules.Count -ne 1) {
            throw 'A LÖVE application filter did not map to exactly one effective rule.'
        }
        $record = Get-RuleRecord $rules[0]
        if (-not [string]::Equals($record.Program,$programPath,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw 'A LÖVE application filter resolved to a different executable.'
        }
        $key = $record.Name.ToLowerInvariant()
        if ($records.Contains($key)) {
            if ((Get-RuleHash $records[$key] -IncludeEnabled) -cne
                    (Get-RuleHash $record -IncludeEnabled)) {
                throw 'Duplicate effective LÖVE firewall-rule identities disagree.'
            }
            continue
        }
        $records[$key] = $record
    }
    return @($records.Values)
}

function Test-ProfileApplies {
    param($Record,$Context)
    return 'any' -in $Record.Profile -or
        $Context.Profile.ToLowerInvariant() -in $Record.Profile
}

function Test-InterfaceApplies {
    param($Record,$Context)
    if ('any' -notin $Record.InterfaceType -and
            'wireless' -notin $Record.InterfaceType) {
        return $false
    }
    if ('any' -in $Record.InterfaceAlias) { return $true }
    foreach ($alias in $Record.InterfaceAlias) {
        try {
            $pattern = [Management.Automation.WildcardPattern]::new(
                $alias,[Management.Automation.WildcardOptions]::IgnoreCase)
            if ($pattern.IsMatch($Context.Alias)) { return $true }
        } catch [Management.Automation.WildcardPatternException] {
            throw 'A LÖVE firewall rule has an invalid interface pattern.'
        }
    }
    return $false
}

function Test-PortSetAdmitsDirect {
    param([Parameter(Mandatory=$true)]$Tokens)
    foreach ($port in $directPorts) {
        if (Test-PortSetCoversPort -Tokens $Tokens -Port ([int]$port)) {
            return $true
        }
    }
    return $false
}

function Test-PortSetCoversPort {
    param(
        [Parameter(Mandatory=$true)]$Tokens,
        [Parameter(Mandatory=$true)][ValidateRange(1,65535)][int]$Port
    )
    foreach ($token in @($Tokens)) {
        if ($token -eq 'any') { return $true }
        if ($token -match '^\d+$') {
            if ([int]$token -eq $Port) { return $true }
            continue
        }
        $range = [regex]::Match($token,'^(\d{1,5})-(\d{1,5})$')
        if ($range.Success) {
            $lower = [int]$range.Groups[1].Value
            $upper = [int]$range.Groups[2].Value
            if ($lower -gt $upper -or $upper -gt 65535) {
                throw 'A LÖVE firewall rule has an invalid port range.'
            }
            if ($lower -le $Port -and $Port -le $upper) { return $true }
            continue
        }
        throw 'A LÖVE UDP firewall rule uses an unclassified local-port token.'
    }
    return $false
}

function Test-PortSetContainsAllDirect {
    param([Parameter(Mandatory=$true)]$Tokens)
    foreach ($port in $directPorts) {
        if (-not (Test-PortSetCoversPort -Tokens $Tokens -Port ([int]$port))) {
            return $false
        }
    }
    return $true
}

function Test-RemoteSetAdmitsInternetIpv6 {
    param([Parameter(Mandatory=$true)]$Tokens)
    foreach ($token in @($Tokens)) {
        if ($token -in @('any','internet','internet6')) { return $true }
        if ($token -in @(
                'internet4','localsubnet','localsubnet4','localsubnet6')) {
            continue
        }
        if ($token -match ':') {
            if ($token -match '^(?:fe[89ab]|f[cd])' -or
                    $token -match '^ff') {
                continue
            }
            return $true
        }
        if ($token -match '^\d+(?:\.\d+){3}(?:/\d+)?$' -or
                $token -match '^\d+(?:\.\d+){3}-\d+(?:\.\d+){3}$') {
            continue
        }
        throw 'A LÖVE firewall rule uses an unclassified remote-address token.'
    }
    return $false
}

function Test-RemoteSetContainsInternetIpv6Scope {
    param([Parameter(Mandatory=$true)]$Tokens)
    return @($Tokens | Where-Object {
        $_ -in @('any','internet','internet6')
    }).Count -gt 0
}

function Test-ExactDirectScope {
    param($Record,$Context)
    $required = @($directPorts | Sort-Object)
    $actual = @($Record.LocalPort | Sort-Object)
    return $Record.Protocol.Count -eq 1 -and
        $Record.Protocol[0] -in @('udp','17') -and
        $actual.Count -eq $required.Count -and
        @($required | Where-Object { $_ -notin $actual }).Count -eq 0 -and
        $Record.RemotePort.Count -eq 1 -and $Record.RemotePort[0] -eq 'any' -and
        $Record.LocalAddress.Count -eq 1 -and $Record.LocalAddress[0] -eq 'any' -and
        $Record.RemoteAddress.Count -eq 1 -and
        $Record.RemoteAddress[0] -eq 'internet6' -and
        $Record.Profile.Count -eq 1 -and
        $Record.Profile[0] -eq $Context.Profile.ToLowerInvariant() -and
        $Record.InterfaceAlias.Count -eq 1 -and
        $Record.InterfaceAlias[0] -eq $Context.Alias.ToLowerInvariant() -and
        $Record.InterfaceType.Count -eq 1 -and
        $Record.InterfaceType[0] -eq 'wireless' -and
        ([string]$Record.Edge).ToLowerInvariant() -eq 'block' -and
        $Record.Service.Count -eq 1 -and $Record.Service[0] -eq 'any'
}

function Get-RuleDisposition {
    param($Record,$Context)
    if ([string]$Record.Enabled -ne 'True' -or
            [string]$Record.Direction -ne 'Inbound' -or
            [string]$Record.Action -ne 'Allow' -or
            -not (Test-ProfileApplies $Record $Context)) {
        return 'irrelevant'
    }
    if ($Record.Protocol.Count -ne 1) {
        throw 'A relevant LÖVE rule has an ambiguous protocol.'
    }
    $protocol = $Record.Protocol[0]
    if ($protocol -notin @('any','udp','17')) { return 'irrelevant' }
    if (-not (Test-PortSetAdmitsDirect $Record.LocalPort)) { return 'irrelevant' }
    if (-not (Test-InterfaceApplies $Record $Context)) { return 'irrelevant' }
    if (-not (Test-RemoteSetAdmitsInternetIpv6 $Record.RemoteAddress)) {
        return 'irrelevant'
    }
    if (Test-ExactDirectScope $Record $Context) { return 'exact' }
    if ($protocol -eq 'any') { return 'unsafe_protocol_any' }
    $safelySuppressibleBroadRule =
        (Test-PortSetContainsAllDirect $Record.LocalPort) -and
        $Record.RemotePort.Count -eq 1 -and $Record.RemotePort[0] -eq 'any' -and
        $Record.LocalAddress.Count -eq 1 -and
            $Record.LocalAddress[0] -eq 'any' -and
        (Test-RemoteSetContainsInternetIpv6Scope $Record.RemoteAddress) -and
        $Record.Service.Count -eq 1 -and $Record.Service[0] -eq 'any'
    if (-not $safelySuppressibleBroadRule) {
        return 'unsafe_narrow_or_unclassified'
    }
    if ([string]$Record.SourceType -ne 'Local' -or
            [string]$Record.Source -ne 'PersistentStore') {
        return 'unsafe_nonlocal'
    }
    return 'safe_broad_udp'
}

function Get-OwnedStatus {
    $lines = @(& $ownedHelper -Action Status)
    return [pscustomobject]@{
        ExactActive = 'TPS_WINDOWS_DIRECT_FIREWALL_STATUS=EXACT_ACTIVE' -in $lines
        BroadObserved = 'BROAD_LOVE_RULE_OBSERVED=True' -in $lines
    }
}

function Assert-JournalShape {
    param([Parameter(Mandatory=$true)]$Journal)
    if ([int]$Journal.schemaVersion -ne 1 -or
            [string]$Journal.contract -cne $journalContract -or
            [string]$Journal.programPathHash -cne
                (Get-Sha256Text $programPath.ToLowerInvariant()) -or
            [string]$Journal.contextHash -notmatch '^[0-9a-f]{64}$') {
        throw 'The firewall recovery journal is invalid.'
    }
    if ($Journal.ownedRuleWasPresent -isnot [bool]) {
        throw 'The firewall recovery journal has an invalid ownership flag.'
    }
    if ($Journal.ownedRuleCreatedByTransaction -isnot [bool] -or
            ([bool]$Journal.ownedRuleWasPresent -and
                [bool]$Journal.ownedRuleCreatedByTransaction)) {
        throw 'The firewall recovery journal has an invalid creation flag.'
    }
    $rules = @($Journal.rules)
    $candidates = @($Journal.candidateNames)
    if ($rules.Count -gt 64 -or $candidates.Count -gt 64) {
        throw 'The firewall recovery journal exceeds its bounded contract.'
    }
    $known = @{}
    $flaggedCandidates = @{}
    foreach ($rule in $rules) {
        $name = [string]$rule.name
        if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 1024 -or
                $name -match '[\r\n]' -or
                $rule.candidate -isnot [bool] -or
                [string]$rule.structuralHash -notmatch '^[0-9a-f]{64}$' -or
                [string]$rule.fullHash -notmatch '^[0-9a-f]{64}$') {
            throw 'The firewall recovery journal contains an invalid rule record.'
        }
        $key = $name.ToLowerInvariant()
        if ($known.ContainsKey($key)) {
            throw 'The firewall recovery journal contains duplicate rules.'
        }
        $known[$key] = $true
        if ([bool]$rule.candidate) {
            if ([string]$rule.source -cne 'PersistentStore' -or
                    [string]$rule.sourceType -cne 'Local' -or
                    [string]$rule.enabled -cne 'True') {
                throw 'A recovery candidate was not an originally enabled local persistent rule.'
            }
            $flaggedCandidates[$key] = $true
        }
    }
    $namedCandidates = @{}
    foreach ($candidate in $candidates) {
        $name = [string]$candidate
        $key = $name.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 1024 -or
                $name -match '[\r\n]' -or -not $known.ContainsKey($key) -or
                $namedCandidates.ContainsKey($key)) {
            throw 'The firewall recovery journal names an unknown candidate.'
        }
        $namedCandidates[$key] = $true
    }
    if ($namedCandidates.Count -ne $flaggedCandidates.Count) {
        throw 'The firewall recovery journal candidate sets disagree.'
    }
    foreach ($key in $namedCandidates.Keys) {
        if (-not $flaggedCandidates.ContainsKey($key)) {
            throw 'The firewall recovery journal candidate sets disagree.'
        }
    }
    return $true
}

function Read-Journal {
    if (-not (Test-JournalRootPresentAndSecure)) { return $null }
    if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf)) {
        return $null
    }
    Assert-SecureJournalFile $journalPath | Out-Null
    $item = Get-Item -LiteralPath $journalPath -Force
    if ($item.Length -le 0 -or $item.Length -gt 131072 -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The firewall recovery journal is unsafe to read.'
    }
    $journal = Get-Content -LiteralPath $journalPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -Depth 8
    Assert-JournalShape $journal | Out-Null
    return $journal
}

function Write-Journal {
    param(
        [Parameter(Mandatory=$true)]$Journal,
        [switch]$Replace
    )
    Initialize-SecureJournalRoot
    $exists = Test-Path -LiteralPath $journalPath
    if ((-not $Replace -and $exists) -or ($Replace -and -not $exists)) {
        throw ($Replace ? 'The firewall recovery journal disappeared before update.' :
            'A firewall recovery journal already exists; Restore it first.')
    }
    if ($exists) { Assert-SecureJournalFile $journalPath | Out-Null }
    $temporary = Join-Path $journalRoot (
        '.windows-direct-firewall-stage-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $Journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary `
            -Encoding UTF8NoBOM -NoNewline
        Set-SecureJournalFileAcl $temporary
        Assert-SecureJournalFile $temporary | Out-Null
        [IO.File]::Move($temporary,$journalPath,[bool]$Replace)
        Assert-SecureJournalFile $journalPath | Out-Null
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Get-SnapshotEntry {
    param($Record,[bool]$Candidate)
    return [pscustomobject][ordered]@{
        name = $Record.Name
        source = $Record.Source
        sourceType = $Record.SourceType
        enabled = [string]$Record.Enabled
        structuralHash = Get-RuleHash $Record
        fullHash = Get-RuleHash $Record -IncludeEnabled
        candidate = $Candidate
    }
}

function Get-RecordMap {
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Records = @()
    )
    $map = @{}
    foreach ($record in @($Records)) {
        $key = $record.Name.ToLowerInvariant()
        if ($map.ContainsKey($key)) { throw 'Duplicate firewall rule identity.' }
        $map[$key] = $record
    }
    return $map
}

function Test-SnapshotRestored {
    param($Journal)
    $context = Get-ActiveWifiContext
    if ($context.Hash -cne [string]$Journal.contextHash) { return $false }
    $current = Get-RecordMap (Get-ProgramRuleRecords)
    $original = @($Journal.rules)
    if ($current.Count -ne $original.Count) { return $false }
    foreach ($entry in $original) {
        $key = ([string]$entry.name).ToLowerInvariant()
        if (-not $current.ContainsKey($key) -or
                (Get-RuleHash $current[$key] -IncludeEnabled) -cne
                    [string]$entry.fullHash) {
            return $false
        }
    }
    return $true
}

function Test-PreparedSnapshot {
    param($Journal,$Context)
    if ($Context.Hash -cne [string]$Journal.contextHash -or
            -not (Get-OwnedStatus).ExactActive) {
        return $false
    }
    $current = Get-RecordMap (Get-ProgramRuleRecords)
    $original = @($Journal.rules)
    $expectedCount = $original.Count + ([bool]$Journal.ownedRuleWasPresent ? 0 : 1)
    if ($current.Count -ne $expectedCount) { return $false }
    $originalNames = @{}
    foreach ($entry in $original) {
        $key = ([string]$entry.name).ToLowerInvariant()
        $originalNames[$key] = $true
        if (-not $current.ContainsKey($key)) { return $false }
        $record = $current[$key]
        if ((Get-RuleHash $record) -cne [string]$entry.structuralHash) {
            return $false
        }
        if ([bool]$entry.candidate) {
            if ([string]$record.Enabled -ne 'False') { return $false }
        } elseif ((Get-RuleHash $record -IncludeEnabled) -cne
                [string]$entry.fullHash) {
            # This protects the unrelated TCP and LAN-only rules as well as
            # every other original LÖVE rule before the physical test starts.
            return $false
        }
    }
    $ownedKey = $ownedRuleName.ToLowerInvariant()
    foreach ($key in $current.Keys) {
        if (-not $originalNames.ContainsKey($key) -and $key -cne $ownedKey) {
            return $false
        }
    }
    if (-not $current.ContainsKey($ownedKey)) { return $false }
    foreach ($record in $current.Values) {
        if ((Get-RuleDisposition $record $Context) -in @(
                'safe_broad_udp','unsafe_protocol_any','unsafe_nonlocal',
                'unsafe_narrow_or_unclassified')) {
            return $false
        }
    }
    return $true
}

function Invoke-RestoreCore {
    param([Parameter(Mandatory=$true)]$Journal)
    $errors = [Collections.Generic.List[string]]::new()
    $records = $null
    try {
        $records = Get-RecordMap (Get-ProgramRuleRecords)
    } catch {
        $errors.Add('effective_rule_enumeration_failed')
        $records = @{}
    }
    $journalEntries = @{}
    foreach ($entry in @($Journal.rules)) {
        $journalEntries[([string]$entry.name).ToLowerInvariant()] = $entry
    }
    foreach ($candidateName in @($Journal.candidateNames)) {
        $key = ([string]$candidateName).ToLowerInvariant()
        $entry = $journalEntries[$key]
        try {
            if (-not $records.ContainsKey($key)) {
                throw 'The original broad UDP rule is missing.'
            }
            $record = $records[$key]
            if ((Get-RuleHash $record) -cne [string]$entry.structuralHash) {
                throw 'The original broad UDP rule changed while staged.'
            }
            if ([string]$record.Enabled -ne 'True') {
                Enable-NetFirewallRule -Name ([string]$entry.name) `
                    -PolicyStore PersistentStore -ErrorAction Stop
            }
        } catch {
            $errors.Add('broad_udp_restore_failed')
        }
    }
    if ($errors.Count -eq 0 -and @($Journal.candidateNames).Count -gt 0) {
        try {
            $enabledRecords = Get-RecordMap (Get-ProgramRuleRecords)
            foreach ($candidateName in @($Journal.candidateNames)) {
                $key = ([string]$candidateName).ToLowerInvariant()
                $entry = $journalEntries[$key]
                if (-not $enabledRecords.ContainsKey($key) -or
                        (Get-RuleHash $enabledRecords[$key] -IncludeEnabled) -cne
                            [string]$entry.fullHash) {
                    throw 'An original broad UDP rule was not verified re-enabled.'
                }
            }
        } catch {
            $errors.Add('broad_udp_restore_verification_failed')
        }
    }
    if ($errors.Count -eq 0 -and
            [bool]$Journal.ownedRuleCreatedByTransaction) {
        try {
            & $ownedHelper -Action Remove | Out-Null
        } catch {
            $errors.Add('owned_exact_removal_failed')
        }
    }
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        $restored = $false
        do {
            try { $restored = Test-SnapshotRestored $Journal } catch { $restored = $false }
            if (-not $restored) { Start-Sleep -Milliseconds 200 }
        } while (-not $restored -and [DateTime]::UtcNow -lt $deadline)
        if (-not $restored) { $errors.Add('original_snapshot_not_restored') }
    } catch {
        $errors.Add('restore_verification_failed')
    }
    if ($errors.Count -eq 0) {
        Remove-Item -LiteralPath $journalPath -Force -ErrorAction Stop
        return $true
    }
    throw ('Firewall restoration is incomplete: ' +
        (@($errors | Sort-Object -Unique) -join ', ') +
        '. Run this helper again with -Action Restore.')
}

function Invoke-Prepare {
    Assert-ElevatedMutation
    if (-not $PSCmdlet.ShouldProcess(
            'The exact LÖVE Direct UDP firewall scope',
            'Journal state, add the owned exact rule, and temporarily disable only verified broader UDP rules')) {
        Write-Output 'TPS_WINDOWS_DIRECT_FIREWALL_STAGE=NO_CHANGE'
        return
    }
    if (-not (Test-Path -LiteralPath $ownedHelper -PathType Leaf) -or
            -not (Test-Path -LiteralPath $programPath -PathType Leaf)) {
        throw 'The reviewed firewall helper or exact LÖVE executable is missing.'
    }
    if (Read-Journal) {
        throw 'A previous firewall stage needs Restore before a new test.'
    }
    $context = Get-ActiveWifiContext
    $records = @(Get-ProgramRuleRecords)
    $candidateNames = [Collections.Generic.List[string]]::new()
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($record in $records) {
        $disposition = Get-RuleDisposition $record $context
        if ($disposition -in @(
                'unsafe_protocol_any','unsafe_nonlocal',
                'unsafe_narrow_or_unclassified')) {
            throw 'An applicable LÖVE rule cannot be suppressed without changing unrelated policy.'
        }
        $candidate = $disposition -eq 'safe_broad_udp'
        if ($candidate) { $candidateNames.Add($record.Name) }
        $entries.Add((Get-SnapshotEntry $record $candidate))
    }
    $ownedOriginal = @($records | Where-Object {
        [string]$_.Name -ceq $ownedRuleName
    })
    if ($ownedOriginal.Count -gt 1) {
        throw 'The owned exact firewall-rule identity is ambiguous.'
    }
    $journal = [pscustomobject][ordered]@{
        schemaVersion = 1
        contract = $journalContract
        createdUtc = [DateTime]::UtcNow.ToString('o')
        programPathHash = Get-Sha256Text $programPath.ToLowerInvariant()
        contextHash = $context.Hash
        profile = $context.Profile
        ownedRuleWasPresent = $ownedOriginal.Count -eq 1
        ownedRuleCreatedByTransaction = $false
        rules = @($entries)
        candidateNames = @($candidateNames)
    }
    Assert-JournalShape $journal | Out-Null
    Write-Journal $journal
    try {
        $addResult = @(& $ownedHelper -Action Add)
        $created = @($addResult | Where-Object {
            $_ -ceq 'TPS_WINDOWS_DIRECT_FIREWALL_ADD=CREATED'
        }).Count -eq 1
        $alreadyPresent = @($addResult | Where-Object {
            $_ -ceq 'TPS_WINDOWS_DIRECT_FIREWALL_ADD=ALREADY_PRESENT'
        }).Count -eq 1
        if ([int]$created + [int]$alreadyPresent -ne 1) {
            throw 'The owned firewall helper returned an unrecognized Add result.'
        }
        if ($created) {
            if ([bool]$journal.ownedRuleWasPresent) {
                throw 'The owned exact rule changed during firewall staging.'
            }
            $journal.ownedRuleCreatedByTransaction = $true
            Assert-JournalShape $journal | Out-Null
            Write-Journal $journal -Replace
        } elseif (-not [bool]$journal.ownedRuleWasPresent) {
            throw 'Another process added the owned exact rule during firewall staging.'
        }
        foreach ($name in $candidateNames) {
            $fresh = @(Get-ProgramRuleRecords | Where-Object {
                [string]$_.Name -ceq $name
            })
            $entry = @($entries | Where-Object { [string]$_.name -ceq $name })
            if ($fresh.Count -ne 1 -or $entry.Count -ne 1 -or
                    (Get-RuleHash $fresh[0]) -cne $entry[0].structuralHash -or
                    [string]$fresh[0].Enabled -ne 'True') {
                throw 'A broad UDP rule changed before it could be staged.'
            }
            Disable-NetFirewallRule -Name $name -PolicyStore PersistentStore `
                -ErrorAction Stop
        }
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        $prepared = $false
        do {
            try {
                $prepared = Test-PreparedSnapshot $journal $context
            } catch {
                $prepared = $false
            }
            if (-not $prepared) { Start-Sleep -Milliseconds 200 }
        } while (-not $prepared -and [DateTime]::UtcNow -lt $deadline)
        if (-not $prepared) {
            throw 'The exact staged firewall state could not be verified.'
        }
    } catch {
        $prepareError = $_.Exception.Message
        try { Invoke-RestoreCore $journal | Out-Null } catch {
            throw "$prepareError Automatic firewall restoration also failed: $($_.Exception.Message)"
        }
        throw $prepareError
    }
    Write-Output 'TPS_WINDOWS_DIRECT_FIREWALL_STAGE=PREPARED'
    Write-Output "BROAD_UDP_RULES_TEMPORARILY_DISABLED=$($candidateNames.Count)"
    Write-Output 'TCP_RULES_CHANGED=False'
    Write-Output 'RECOVERY_JOURNAL_PRESENT=True'
}

function Invoke-Restore {
    Assert-ElevatedMutation
    if (-not $PSCmdlet.ShouldProcess(
            'The journaled LÖVE firewall rules',
            'Restore the original snapshot and remove only a transaction-created exact rule')) {
        Write-Output 'TPS_WINDOWS_DIRECT_FIREWALL_RESTORE=NO_CHANGE'
        return
    }
    $journal = Read-Journal
    if (-not $journal) {
        Write-Output 'TPS_WINDOWS_DIRECT_FIREWALL_RESTORE=ALREADY_RESTORED'
        return
    }
    Invoke-RestoreCore $journal | Out-Null
    Write-Output 'TPS_WINDOWS_DIRECT_FIREWALL_RESTORE=PASSED'
    Write-Output 'ORIGINAL_RULE_SNAPSHOT_RESTORED=True'
    Write-Output 'RECOVERY_JOURNAL_PRESENT=False'
}

function Invoke-Status {
    $journal = Read-Journal
    $status = 'UNSTAGED'
    $broadCount = -1
    $exactActive = $false
    try {
        $context = Get-ActiveWifiContext
        $records = @(Get-ProgramRuleRecords)
        $broadCount = @($records | Where-Object {
            (Get-RuleDisposition $_ $context) -in @(
                'safe_broad_udp','unsafe_protocol_any','unsafe_nonlocal',
                'unsafe_narrow_or_unclassified')
        }).Count
        $exactActive = (Get-OwnedStatus).ExactActive
        if ($journal) {
            $status = (Test-PreparedSnapshot $journal $context) ?
                'PREPARED' : 'PENDING_RECOVERY'
        }
    } catch {
        $status = $journal ? 'PENDING_RECOVERY' : 'UNAVAILABLE'
    }
    Write-Output "TPS_WINDOWS_DIRECT_FIREWALL_STAGE_STATUS=$status"
    Write-Output "RECOVERY_JOURNAL_PRESENT=$($null -ne $journal)"
    Write-Output "OWNED_EXACT_ACTIVE=$exactActive"
    Write-Output "ENABLED_RELEVANT_BROAD_UDP_RULE_COUNT=$broadCount"
}

function Invoke-SelfTest {
    $context = [pscustomobject]@{ Alias='Test Wi-Fi'; Profile='Public' }
    $exact = [pscustomobject][ordered]@{
        Name=$ownedRuleName; Source='PersistentStore'; SourceType='Local'
        Enabled='True'; Direction='Inbound'; Action='Allow'; Profile=@('public')
        Edge='Block'; Program=$programPath; Protocol=@('udp')
        LocalPort=@('57842','57844'); RemotePort=@('any')
        LocalAddress=@('any'); RemoteAddress=@('internet6')
        InterfaceAlias=@('test wi-fi'); InterfaceType=@('wireless')
        Service=@('any')
    }
    $checks = 0
    function Assert-Check([bool]$Condition,[string]$Name) {
        if (-not $Condition) { throw "Firewall-stage self-test failed: $Name" }
        $script:selfTestChecks++
    }
    $script:selfTestChecks = 0
    Assert-Check (Test-ExactDirectScope $exact $context) 'exact-scope'
    Assert-Check ((Get-RuleDisposition $exact $context) -eq 'exact') 'exact-disposition'
    $broad = $exact.PSObject.Copy()
    $broad.LocalPort = @('any')
    $broad.RemoteAddress = @('any')
    $broad.InterfaceAlias = @('any')
    $broad.InterfaceType = @('any')
    $broad.Edge = 'DeferToUser'
    Assert-Check ((Get-RuleDisposition $broad $context) -eq 'safe_broad_udp') `
        'detect-safe-broad-udp'
    $tcp = $broad.PSObject.Copy(); $tcp.Protocol = @('tcp')
    Assert-Check ((Get-RuleDisposition $tcp $context) -eq 'irrelevant') 'ignore-tcp'
    $lan = $broad.PSObject.Copy(); $lan.RemoteAddress = @('localsubnet6')
    Assert-Check ((Get-RuleDisposition $lan $context) -eq 'irrelevant') 'ignore-lan-only'
    $otherPort = $broad.PSObject.Copy(); $otherPort.LocalPort = @('22122')
    Assert-Check ((Get-RuleDisposition $otherPort $context) -eq 'irrelevant') `
        'ignore-other-port'
    $oneDirectPort = $broad.PSObject.Copy()
    $oneDirectPort.LocalPort = @('57842')
    Assert-Check ((Get-RuleDisposition $oneDirectPort $context) -eq
        'unsafe_narrow_or_unclassified') 'do-not-disable-one-port-rule'
    $onePublicSource = $broad.PSObject.Copy()
    $onePublicSource.RemoteAddress = @('2001:db8::1')
    Assert-Check ((Get-RuleDisposition $onePublicSource $context) -eq
        'unsafe_narrow_or_unclassified') 'do-not-disable-one-source-rule'
    $sourcePortRestricted = $broad.PSObject.Copy()
    $sourcePortRestricted.RemotePort = @('443')
    Assert-Check ((Get-RuleDisposition $sourcePortRestricted $context) -eq
        'unsafe_narrow_or_unclassified') 'do-not-disable-source-port-rule'
    $ipv4LocalOnly = $broad.PSObject.Copy()
    $ipv4LocalOnly.LocalAddress = @('192.0.2.1')
    Assert-Check ((Get-RuleDisposition $ipv4LocalOnly $context) -eq
        'unsafe_narrow_or_unclassified') 'do-not-disable-ipv4-local-rule'
    $serviceRestricted = $broad.PSObject.Copy()
    $serviceRestricted.Service = @('example-service')
    Assert-Check ((Get-RuleDisposition $serviceRestricted $context) -eq
        'unsafe_narrow_or_unclassified') 'do-not-disable-service-rule'
    $anyProtocol = $broad.PSObject.Copy(); $anyProtocol.Protocol = @('any')
    Assert-Check ((Get-RuleDisposition $anyProtocol $context) -eq
        'unsafe_protocol_any') 'reject-any-protocol'
    $nonlocal = $broad.PSObject.Copy(); $nonlocal.SourceType = 'GroupPolicy'
    Assert-Check ((Get-RuleDisposition $nonlocal $context) -eq
        'unsafe_nonlocal') 'reject-nonlocal'
    $candidateEntry = Get-SnapshotEntry $broad $true
    $validJournal = [pscustomobject][ordered]@{
        schemaVersion=1; contract=$journalContract; createdUtc='self-test'
        programPathHash=Get-Sha256Text $programPath.ToLowerInvariant()
        contextHash=('0' * 64); profile='Public'; ownedRuleWasPresent=$false
        ownedRuleCreatedByTransaction=$false
        rules=@($candidateEntry); candidateNames=@($broad.Name)
    }
    Assert-Check ([bool](Assert-JournalShape $validJournal)) 'accept-valid-journal'
    $invalidJournal = $validJournal | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $invalidJournal.candidateNames = @()
    $rejectedMismatch = $false
    try { Assert-JournalShape $invalidJournal | Out-Null } catch {
        $rejectedMismatch = $true
    }
    Assert-Check $rejectedMismatch 'reject-mismatched-candidate-sets'
    Assert-Check ((Get-RecordMap -Records @()).Count -eq 0) `
        'accept-empty-original-rule-snapshot'
    $structureBefore = Get-RuleHash $broad
    $fullBefore = Get-RuleHash $broad -IncludeEnabled
    $broad.Enabled = 'False'
    Assert-Check ((Get-RuleHash $broad) -ceq $structureBefore -and
        (Get-RuleHash $broad -IncludeEnabled) -cne $fullBefore) `
        'enabled-state-hash-separation'
    $checks = $script:selfTestChecks
    Remove-Variable -Name selfTestChecks -Scope Script -ErrorAction SilentlyContinue
    Write-Output "TPS_WINDOWS_DIRECT_FIREWALL_STAGE_SELF_TEST=PASS CHECKS=$checks"
}

if ($Action -eq 'SelfTest') {
    Invoke-SelfTest
    return
}

$mutex = [Threading.Mutex]::new($false,$mutexName)
$acquired = $false
try {
    try {
        $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds(15))
    } catch [Threading.AbandonedMutexException] {
        $acquired = $true
    }
    if (-not $acquired) {
        throw 'Another Windows Direct firewall-stage operation is active.'
    }
    switch ($Action) {
        'Status' { Invoke-Status }
        'Prepare' { Invoke-Prepare }
        'Restore' { Invoke-Restore }
    }
} finally {
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
