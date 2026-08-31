local IpScope = {
    MAX_INPUT_LENGTH = 15,
}

-- This table follows the IANA IPv4 Special-Purpose Address Registry
-- (last updated 2025-10-09) plus the IPv4 multicast block from the IANA
-- IPv4 Address Space registry.  `isGlobal` is intentionally stricter than
-- IANA's `Globally Reachable` column: it means an ordinary public-unicast
-- address that could identify a player's host.  Protocol anycast and other
-- special-service addresses are therefore never globally usable here.

local function addressNumber(a, b, c, d)
    return ((a * 256 + b) * 256 + c) * 256 + d
end

local function entry(address, prefixLength, reason, name,
        ianaGloballyReachable, reservedByProtocol)
    local a, b, c, d = address:match("^([0-9]+)%.([0-9]+)%.([0-9]+)%.([0-9]+)$")
    local first = addressNumber(tonumber(a), tonumber(b), tonumber(c), tonumber(d))
    local size = 2 ^ (32 - prefixLength)
    return {
        first = first,
        last = first + size - 1,
        prefix = address .. "/" .. tostring(prefixLength),
        prefixLength = prefixLength,
        reason = reason,
        name = name,
        ianaGloballyReachable = ianaGloballyReachable,
        reservedByProtocol = reservedByProtocol == true,
    }
end

local SPECIAL_RANGES = {
    entry("0.0.0.0", 32, "unspecified", "This host on this network", false, true),
    entry("255.255.255.255", 32, "limited_broadcast", "Limited Broadcast", false, true),
    entry("192.0.0.8", 32, "protocol_assignment_dummy", "IPv4 dummy address", false, false),
    entry("192.0.0.9", 32, "protocol_assignment_pcp_anycast",
        "Port Control Protocol Anycast", true, false),
    entry("192.0.0.10", 32, "protocol_assignment_turn_anycast",
        "Traversal Using Relays around NAT Anycast", true, false),
    entry("192.0.0.170", 32, "protocol_assignment_nat64_discovery",
        "NAT64/DNS64 Discovery", false, true),
    entry("192.0.0.171", 32, "protocol_assignment_nat64_discovery",
        "NAT64/DNS64 Discovery", false, true),
    entry("192.88.99.2", 32, "deprecated_6a44_anycast",
        "6a44-relay anycast address", false, false),

    entry("192.0.0.0", 29, "protocol_assignment_service_continuity",
        "IPv4 Service Continuity Prefix", false, false),

    entry("100.64.0.0", 10, "carrier_grade_nat", "Shared Address Space", false, false),
    entry("172.16.0.0", 12, "private_use", "Private-Use", false, false),

    entry("169.254.0.0", 16, "link_local", "Link Local", false, true),
    entry("192.168.0.0", 16, "private_use", "Private-Use", false, false),

    entry("192.0.0.0", 24, "protocol_assignment", "IETF Protocol Assignments", false, false),
    entry("192.0.2.0", 24, "documentation", "Documentation (TEST-NET-1)", false, false),
    entry("192.31.196.0", 24, "special_service_as112", "AS112-v4", true, false),
    entry("192.52.193.0", 24, "special_service_amt", "AMT", true, false),
    entry("192.88.99.0", 24, "deprecated_6to4", "Deprecated (6to4 Relay Anycast)", nil, false),
    entry("192.175.48.0", 24, "special_service_as112",
        "Direct Delegation AS112 Service", true, false),
    entry("198.51.100.0", 24, "documentation", "Documentation (TEST-NET-2)", false, false),
    entry("203.0.113.0", 24, "documentation", "Documentation (TEST-NET-3)", false, false),

    entry("198.18.0.0", 15, "benchmarking", "Benchmarking", false, false),

    entry("0.0.0.0", 8, "this_network", "This network", false, true),
    entry("10.0.0.0", 8, "private_use", "Private-Use", false, false),
    entry("127.0.0.0", 8, "loopback", "Loopback", false, true),

    entry("224.0.0.0", 4, "multicast", "IPv4 Multicast", false, true),
    entry("240.0.0.0", 4, "reserved", "Reserved", false, true),
}

table.sort(SPECIAL_RANGES, function(left, right)
    if left.prefixLength == right.prefixLength then return left.first < right.first end
    return left.prefixLength > right.prefixLength
end)

local function invalid(reason)
    return {
        scope = "invalid",
        reason = reason,
        isGlobal = false,
        specialPurpose = false,
    }
end

function IpScope.parse(value)
    if type(value) ~= "string" then return nil, "not_text" end
    if #value > IpScope.MAX_INPUT_LENGTH then return nil, "too_long" end

    local a, b, c, d = value:match(
        "^([0-9]+)%.([0-9]+)%.([0-9]+)%.([0-9]+)$")
    if not a then return nil, "invalid_format" end

    local parts = { a, b, c, d }
    local octets = {}
    for index, part in ipairs(parts) do
        if #part > 1 and part:sub(1, 1) == "0" then
            return nil, "non_canonical"
        end
        local octet = tonumber(part)
        if not octet or octet > 255 then return nil, "octet_out_of_range" end
        octets[index] = octet
    end

    return {
        address = value,
        octets = octets,
        number = addressNumber(octets[1], octets[2], octets[3], octets[4]),
    }
end

function IpScope.classify(value)
    local parsed, parseReason = IpScope.parse(value)
    if not parsed then return invalid(parseReason) end

    for _, special in ipairs(SPECIAL_RANGES) do
        if parsed.number >= special.first and parsed.number <= special.last then
            return {
                address = parsed.address,
                octets = parsed.octets,
                scope = "non_global",
                reason = special.reason,
                name = special.name,
                prefix = special.prefix,
                isGlobal = false,
                specialPurpose = true,
                ianaGloballyReachable = special.ianaGloballyReachable,
                reservedByProtocol = special.reservedByProtocol,
            }
        end
    end

    return {
        address = parsed.address,
        octets = parsed.octets,
        scope = "global",
        reason = "public_unicast",
        name = "Public unicast",
        isGlobal = true,
        specialPurpose = false,
    }
end

function IpScope.isGlobal(value)
    local classification = IpScope.classify(value)
    return classification.isGlobal, classification
end

return IpScope
