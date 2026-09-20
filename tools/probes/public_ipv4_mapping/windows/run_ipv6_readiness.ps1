[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-GlobalIpv6Address([string]$Text) {
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Text,[ref]$parsed) -or
            $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetworkV6 -or
            $parsed.Equals([Net.IPAddress]::IPv6Any) -or
            $parsed.Equals([Net.IPAddress]::IPv6Loopback) -or
            $parsed.IsIPv6LinkLocal -or $parsed.IsIPv6Multicast -or
            $parsed.IsIPv4MappedToIPv6) {
        return $false
    }
    $bytes = $parsed.GetAddressBytes()
    if (($bytes[0] -band 0xfe) -eq 0xfc) { return $false } # unique-local fc00::/7
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and
            $bytes[2] -eq 0x0d -and $bytes[3] -eq 0xb8) {
        return $false # documentation-only 2001:db8::/32
    }
    return $true
}

$routeReady = $false
$addressReady = $false
try {
    $interfaces = @(Get-NetIPInterface -AddressFamily IPv6 -ErrorAction Stop |
        Where-Object { $_.ConnectionState -eq 'Connected' })
    $routes = @(Get-NetRoute -AddressFamily IPv6 -DestinationPrefix '::/0' `
        -PolicyStore ActiveStore -ErrorAction Stop)
    $indexes = @{}
    foreach ($route in $routes) {
        foreach ($interface in $interfaces) {
            if ($route.InterfaceIndex -eq $interface.InterfaceIndex) {
                $indexes[[int]$route.InterfaceIndex] = $true
                $routeReady = $true
            }
        }
    }
    if ($routeReady) {
        foreach ($address in @(Get-NetIPAddress -AddressFamily IPv6 `
                -AddressState Preferred -ErrorAction Stop)) {
            if ($indexes.ContainsKey([int]$address.InterfaceIndex) -and
                    -not $address.SkipAsSource -and
                    (Test-GlobalIpv6Address ([string]$address.IPAddress))) {
                $addressReady = $true
                break
            }
        }
    }
} catch {
    $routeReady = $false
    $addressReady = $false
}

$ready = $routeReady -and $addressReady
Write-Output ('TPS_IPV6_LOCAL_READINESS=' + $(if ($ready) { 'PASS' } else { 'FAIL' }))
Write-Output ('GLOBAL_IPV6_ADDRESS_PRESENT=' + $(if ($addressReady) { 'True' } else { 'False' }))
Write-Output ('IPV6_DEFAULT_ROUTE_PRESENT=' + $(if ($routeReady) { 'True' } else { 'False' }))
Write-Output 'INBOUND_REACHABILITY_PROVEN=False'
Write-Output 'NETWORK_TRAFFIC_SENT=False'
Write-Output 'NETWORK_DETAILS_RETAINED=False'
if (-not $ready) { exit 1 }
