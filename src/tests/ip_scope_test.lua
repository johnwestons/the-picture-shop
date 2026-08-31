local IpScope = require("src.net.ip_scope")

local Test = {}

local function hasClassification(address, scope, reason, prefix)
    local result = IpScope.classify(address)
    return result.scope == scope and result.reason == reason
        and result.prefix == prefix and result.address == address
end

local function everyAddressHasReason(addresses, reason)
    for _, address in ipairs(addresses) do
        local result = IpScope.classify(address)
        if result.scope ~= "non_global" or result.reason ~= reason
            or result.isGlobal ~= false
        then
            return false
        end
    end
    return true
end

function Test.run(_, check)
    local parsed, parseError = IpScope.parse("8.8.4.4")
    check("ip_scope_strict_parser_accepts_canonical_ipv4",
        parseError == nil and parsed.address == "8.8.4.4"
        and parsed.number == 134743044
        and parsed.octets[1] == 8 and parsed.octets[2] == 8
        and parsed.octets[3] == 4 and parsed.octets[4] == 4)

    local invalid = {
        42,
        "",
        " 8.8.8.8",
        "8.8.8.8 ",
        "008.8.8.8",
        "8.08.8.8",
        "8.8.8.008",
        "8.8.8",
        "8.8.8.8.8",
        "8..8.8",
        "256.8.8.8",
        "-1.8.8.8",
        "+1.8.8.8",
        "1e1.8.8.8",
        "example.com",
        "8.8.8.8:22122",
        "8.8.8.8\n",
        string.rep("1", IpScope.MAX_INPUT_LENGTH + 1),
    }
    local nilParsed, nilError = IpScope.parse(nil)
    local nilClassification = IpScope.classify(nil)
    local nilGlobal, nilPredicateResult = IpScope.isGlobal(nil)
    local invalidRejected = nilParsed == nil and nilError == "not_text"
        and nilClassification.scope == "invalid"
        and nilClassification.reason == nilError
        and nilGlobal == false and nilPredicateResult.reason == nilError
    for _, value in ipairs(invalid) do
        local valueParsed, errorReason = IpScope.parse(value)
        local classification = IpScope.classify(value)
        local global, predicateResult = IpScope.isGlobal(value)
        invalidRejected = invalidRejected and valueParsed == nil
            and type(errorReason) == "string"
            and classification.scope == "invalid"
            and classification.reason == errorReason
            and classification.isGlobal == false
            and global == false and predicateResult.reason == errorReason
    end
    check("ip_scope_strict_parser_rejects_noncanonical_and_unbounded_input",
        invalidRejected)

    local publicAddresses = {
        "1.0.0.0",
        "9.255.255.255",
        "11.0.0.0",
        "100.63.255.255",
        "100.128.0.0",
        "126.255.255.255",
        "128.0.0.0",
        "169.253.255.255",
        "169.255.0.0",
        "172.15.255.255",
        "172.32.0.0",
        "192.0.1.255",
        "192.0.3.0",
        "198.17.255.255",
        "198.20.0.0",
        "223.255.255.255",
    }
    local publicAccepted = true
    for _, address in ipairs(publicAddresses) do
        local global, result = IpScope.isGlobal(address)
        publicAccepted = publicAccepted and global == true
            and result.scope == "global"
            and result.reason == "public_unicast"
            and result.specialPurpose == false
    end
    check("ip_scope_accepts_only_ordinary_public_unicast_as_global", publicAccepted)

    check("ip_scope_classifies_all_rfc1918_private_boundaries",
        everyAddressHasReason({
            "10.0.0.0", "10.255.255.255",
            "172.16.0.0", "172.31.255.255",
            "192.168.0.0", "192.168.255.255",
        }, "private_use"))

    check("ip_scope_classifies_carrier_grade_nat_shared_space_exactly",
        everyAddressHasReason({ "100.64.0.0", "100.127.255.255" }, "carrier_grade_nat")
        and IpScope.classify("100.63.255.255").isGlobal
        and IpScope.classify("100.128.0.0").isGlobal)

    check("ip_scope_classifies_nonroutable_local_ranges",
        everyAddressHasReason({ "127.0.0.0", "127.255.255.255" }, "loopback")
        and everyAddressHasReason({ "169.254.0.0", "169.254.255.255" }, "link_local")
        and hasClassification("0.0.0.0", "non_global", "unspecified", "0.0.0.0/32")
        and hasClassification("0.0.0.1", "non_global", "this_network", "0.0.0.0/8"))

    local pcp = IpScope.classify("192.0.0.9")
    local turn = IpScope.classify("192.0.0.10")
    check("ip_scope_rejects_protocol_assignments_even_when_iana_marks_them_reachable",
        hasClassification("192.0.0.1", "non_global",
            "protocol_assignment_service_continuity", "192.0.0.0/29")
        and hasClassification("192.0.0.8", "non_global",
            "protocol_assignment_dummy", "192.0.0.8/32")
        and pcp.reason == "protocol_assignment_pcp_anycast"
        and pcp.ianaGloballyReachable == true and pcp.isGlobal == false
        and turn.reason == "protocol_assignment_turn_anycast"
        and turn.ianaGloballyReachable == true and turn.isGlobal == false
        and hasClassification("192.0.0.11", "non_global",
            "protocol_assignment", "192.0.0.0/24")
        and everyAddressHasReason({ "192.0.0.170", "192.0.0.171" },
            "protocol_assignment_nat64_discovery"))

    check("ip_scope_classifies_documentation_and_benchmarking_ranges",
        everyAddressHasReason({
            "192.0.2.0", "192.0.2.255",
            "198.51.100.0", "198.51.100.255",
            "203.0.113.0", "203.0.113.255",
        }, "documentation")
        and everyAddressHasReason({ "198.18.0.0", "198.19.255.255" }, "benchmarking"))

    check("ip_scope_classifies_reachable_special_services_as_non_player_endpoints",
        everyAddressHasReason({ "192.31.196.1", "192.175.48.254" }, "special_service_as112")
        and everyAddressHasReason({ "192.52.193.1" }, "special_service_amt")
        and IpScope.classify("192.31.196.1").ianaGloballyReachable == true
        and IpScope.classify("192.52.193.1").ianaGloballyReachable == true)

    check("ip_scope_classifies_deprecated_transition_addresses",
        hasClassification("192.88.99.1", "non_global",
            "deprecated_6to4", "192.88.99.0/24")
        and hasClassification("192.88.99.2", "non_global",
            "deprecated_6a44_anycast", "192.88.99.2/32"))

    check("ip_scope_classifies_multicast_reserved_and_limited_broadcast",
        everyAddressHasReason({ "224.0.0.0", "239.255.255.255" }, "multicast")
        and everyAddressHasReason({ "240.0.0.0", "255.255.255.254" }, "reserved")
        and hasClassification("255.255.255.255", "non_global",
            "limited_broadcast", "255.255.255.255/32"))
end

return Test
