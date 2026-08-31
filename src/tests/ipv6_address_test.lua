local Ipv6Address = require("src.net.ipv6_address")

local Test = {}

local function parsesAs(input, expected)
    local parsed, parseError = Ipv6Address.parse(input)
    return parseError == nil and parsed ~= nil and parsed.address == expected
        and type(parsed.bytes) == "string" and #parsed.bytes == 16
        and type(parsed.words) == "table" and #parsed.words == 8
end

local function hasReason(input, expectedReason, expectedPrefix)
    local global, result = Ipv6Address.isGlobal(input)
    return global == false and result.scope == "non_global"
        and result.reason == expectedReason
        and result.directPlayerCandidate == false
        and (expectedPrefix == nil or result.prefix == expectedPrefix)
end

local function allGlobal(addresses)
    for _, address in ipairs(addresses) do
        local global, result = Ipv6Address.isGlobal(address)
        if not global or result.scope ~= "global"
            or result.reason ~= "global_unicast"
            or result.directPlayerCandidate ~= true
            or result.specialPurpose ~= false
        then
            return false
        end
    end
    return true
end

function Test.run(_, check)
    check("ipv6_address_expands_and_emits_rfc5952_canonical_text",
        parsesAs("2001:0DB8:0000:0000:0001:0000:0000:0001",
            "2001:db8::1:0:0:1")
        and parsesAs("2001:db8::0001", "2001:db8::1")
        and parsesAs("0:0:0:0:0:0:0:0", "::")
        and parsesAs("0:0:0:0:0:0:0:1", "::1")
        and parsesAs("2001:db8:0:0:0:0:0:0", "2001:db8::")
        and parsesAs("1:2:3:4:5:6:7:8", "1:2:3:4:5:6:7:8"))

    check("ipv6_address_compresses_longest_zero_run_and_uses_leftmost_tie",
        parsesAs("2001:0:0:1:0:0:1:1", "2001::1:0:0:1:1")
        and parsesAs("2001:0:0:1:0:0:0:1", "2001:0:0:1::1")
        and parsesAs("2001:db8:0:1:0:1:0:1", "2001:db8:0:1:0:1:0:1")
        and parsesAs("0:0:1:0:0:1:0:0", "::1:0:0:1:0:0"))

    local noncanonical, noncanonicalError = Ipv6Address.parse(
        "2001:0DB8:0000:0000:0000:0000:0000:0001")
    check("ipv6_address_returns_canonical_form_for_callers_that_require_code_canonicality",
        noncanonicalError == nil and noncanonical ~= nil
        and noncanonical.address == "2001:db8::1"
        and noncanonical.address ~= "2001:0DB8:0000:0000:0000:0000:0000:0001")

    local expectedBytes = string.char(
        0x20, 0x01, 0x0d, 0xb8,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 1)
    local parsedBytesAddress = Ipv6Address.parse("2001:db8::1")
    local fromBytes, fromBytesError = Ipv6Address.fromBytes(expectedBytes)
    check("ipv6_address_bytes_are_network_order_and_round_trip_exactly",
        parsedBytesAddress ~= nil and parsedBytesAddress.bytes == expectedBytes
        and fromBytesError == nil and fromBytes.address == "2001:db8::1"
        and fromBytes.bytes == expectedBytes
        and fromBytes.words[1] == 0x2001 and fromBytes.words[2] == 0x0db8
        and fromBytes.words[3] == 0 and fromBytes.words[8] == 1)

    local roundTripInputs = {
        "::", "::1", "100::", "2000::", "2001:2::",
        "2001:20:ffff:ffff:ffff:ffff:ffff:ffff",
        "2001:db8::dead:beef", "2002::1", "3fff:fff::1",
        "fc00::1", "febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff", "ffff::1",
    }
    local everyRoundTrip = true
    for _, input in ipairs(roundTripInputs) do
        local first = Ipv6Address.parse(input)
        local second = first and Ipv6Address.fromBytes(first.bytes)
        everyRoundTrip = everyRoundTrip and first ~= nil and second ~= nil
            and second.address == first.address and second.bytes == first.bytes
            and second.reason == first.reason and second.isGlobal == first.isGlobal
    end
    check("ipv6_address_binary_round_trips_preserve_canonical_value_and_classification",
        everyRoundTrip)

    local deterministicRoundTrips = true
    for sample = 0, 255 do
        local generated = {}
        for byteIndex = 1, 16 do
            generated[byteIndex] = string.char(
                (sample * 73 + byteIndex * 151 + sample * byteIndex * 19) % 256)
        end
        local inputBytes = table.concat(generated)
        local binaryParsed = Ipv6Address.fromBytes(inputBytes)
        local textParsed = binaryParsed and Ipv6Address.parse(binaryParsed.address)
        deterministicRoundTrips = deterministicRoundTrips
            and binaryParsed ~= nil and textParsed ~= nil
            and #binaryParsed.address <= Ipv6Address.MAX_INPUT_LENGTH
            and binaryParsed.address == binaryParsed.address:lower()
            and textParsed.bytes == inputBytes
            and textParsed.address == binaryParsed.address
            and textParsed.reason == binaryParsed.reason
    end
    check("ipv6_address_deterministic_binary_corpus_round_trips_canonical_text",
        deterministicRoundTrips)

    local malformed = {
        { nil, "not_text" },
        { 42, "not_text" },
        { "", "empty" },
        { " 2001:db8::1", "whitespace" },
        { "2001:db8::1 ", "whitespace" },
        { "2001:db8 ::1", "whitespace" },
        { "2001:db8::1\n", "control_character" },
        { "2001:db8::1\0", "control_character" },
        { "fe80::1%wlan0", "zone_id" },
        { "[2001:db8::1]", "bracket_or_port" },
        { "[2001:db8::1]:22122", "bracket_or_port" },
        { "::ffff:192.0.2.1", "ipv4_embedded" },
        { "::192.0.2.1", "ipv4_embedded" },
        { "+2001:db8::1", "leading_plus" },
        { "2001:+db8::1", "leading_plus" },
        { "2001:db8::g", "invalid_character" },
        { "2001:db8::1/64", "invalid_character" },
        { "2001::db8::1", "multiple_compression" },
        { ":::1", "multiple_compression" },
        { "2001:::1", "multiple_compression" },
        { "00000::", "group_too_long" },
        { "1:2:3:4:5:6:7", "invalid_group_count" },
        { "1:2:3:4:5:6:7:8:9", "invalid_group_count" },
        { "1:2:3:4:5:6:7:8::", "invalid_group_count" },
        { "1:2:3:4:5:6::7:8", "invalid_group_count" },
        { ":1:2:3:4:5:6:7", "empty_group" },
        { "1:2:3:4:5:6:7:", "empty_group" },
        { string.rep("1", Ipv6Address.MAX_INPUT_LENGTH + 1), "too_long" },
    }
    local allMalformedRejected = true
    local malformedFailure
    for _, case in ipairs(malformed) do
        local parsed, parseError = Ipv6Address.parse(case[1])
        local global, classification = Ipv6Address.isGlobal(case[1])
        local accepted = parsed == nil and parseError == case[2]
            and global == false and classification.scope == "invalid"
            and classification.reason == case[2]
            and classification.directPlayerCandidate == false
        if not accepted and not malformedFailure then
            malformedFailure = tostring(case[1]) .. " expected=" .. case[2]
                .. " parse=" .. tostring(parseError)
                .. " classify=" .. tostring(classification.reason)
        end
        allMalformedRejected = allMalformedRejected and accepted
    end
    check("ipv6_address_rejects_bounded_malformed_corpus_with_stable_reasons",
        allMalformedRejected, malformedFailure)

    local tableParsed, tableParseError = Ipv6Address.parse({})
    local tableGlobal, tableClassification = Ipv6Address.isGlobal({})
    check("ipv6_address_distinguishes_non_text_parse_input_from_invalid_parsed_tables",
        tableParsed == nil and tableParseError == "not_text"
        and tableGlobal == false and tableClassification.scope == "invalid"
        and tableClassification.reason == "invalid_parsed_value")

    local badBytesCases = {
        { nil, "bytes_not_string" },
        { {}, "bytes_not_string" },
        { "", "invalid_byte_length" },
        { string.rep("\0", 15), "invalid_byte_length" },
        { string.rep("\0", 17), "invalid_byte_length" },
    }
    local badBytesRejected = true
    for _, case in ipairs(badBytesCases) do
        local parsed, parseError = Ipv6Address.fromBytes(case[1])
        badBytesRejected = badBytesRejected and parsed == nil and parseError == case[2]
    end
    check("ipv6_address_from_bytes_requires_exactly_sixteen_binary_bytes",
        badBytesRejected)

    check("ipv6_address_classifies_unspecified_loopback_and_embedded_ipv4",
        hasReason("::", "unspecified", "::")
        and hasReason("::1", "loopback", "::1")
        and hasReason("::ffff:c000:201", "ipv4_mapped", "::ffff:0:0/96")
        and hasReason("::2", "ipv4_compatible", "::/96"))

    check("ipv6_address_classifies_multicast_link_local_and_unique_local_boundaries",
        hasReason("ff00::", "multicast", "ff00::/8")
        and hasReason("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
            "multicast", "ff00::/8")
        and hasReason("fe80::", "link_local", "fe80::/10")
        and hasReason("febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
            "link_local", "fe80::/10")
        and hasReason("fc00::", "unique_local", "fc00::/7")
        and hasReason("fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
            "unique_local", "fc00::/7")
        and hasReason("fe7f:ffff::", "not_global_unicast")
        and hasReason("fec0::", "not_global_unicast"))

    check("ipv6_address_classifies_discard_only_block_exactly",
        hasReason("100::", "discard_only", "100::/64")
        and hasReason("100:0:0:0:ffff:ffff:ffff:ffff",
            "discard_only", "100::/64")
        and hasReason("ff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
            "not_global_unicast")
        and hasReason("100:0:0:1::", "not_global_unicast"))

    check("ipv6_address_classifies_benchmarking_more_specifically_than_protocol_block",
        hasReason("2001:2::", "benchmarking", "2001:2::/48")
        and hasReason("2001:2:0:ffff:ffff:ffff:ffff:ffff",
            "benchmarking", "2001:2::/48")
        and hasReason("2001:2:1::", "protocol_assignment", "2001::/23"))

    check("ipv6_address_classifies_orchidv2_more_specifically_than_protocol_block",
        hasReason("2001:20::", "orchidv2", "2001:20::/28")
        and hasReason("2001:2f:ffff:ffff:ffff:ffff:ffff:ffff",
            "orchidv2", "2001:20::/28")
        and hasReason("2001:1f:ffff::", "protocol_assignment", "2001::/23")
        and hasReason("2001:30::", "protocol_assignment", "2001::/23"))

    check("ipv6_address_classifies_ietf_protocol_assignment_boundaries",
        hasReason("2001::", "protocol_assignment", "2001::/23")
        and hasReason("2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff",
            "protocol_assignment", "2001::/23")
        and Ipv6Address.isGlobal("2001:200::") == true)

    check("ipv6_address_classifies_documentation_ranges_and_boundaries",
        hasReason("2001:db8::", "documentation", "2001:db8::/32")
        and hasReason("2001:db8:ffff:ffff:ffff:ffff:ffff:ffff",
            "documentation", "2001:db8::/32")
        and Ipv6Address.isGlobal("2001:db7:ffff::") == true
        and Ipv6Address.isGlobal("2001:db9::") == true
        and hasReason("3fff::", "documentation", "3fff::/20")
        and hasReason("3fff:fff:ffff:ffff:ffff:ffff:ffff:ffff",
            "documentation", "3fff::/20")
        and Ipv6Address.isGlobal("3ffd:ffff::") == true
        and Ipv6Address.isGlobal("3fff:1000::") == true)

    check("ipv6_address_classifies_6to4_transition_block_exactly",
        hasReason("2002::", "6to4", "2002::/16")
        and hasReason("2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
            "6to4", "2002::/16")
        and Ipv6Address.isGlobal("2001:ffff::") == true
        and Ipv6Address.isGlobal("2003::") == true)

    check("ipv6_address_excludes_returned_6bone_and_direct_delegation_as112",
        hasReason("3ffe::", "returned_6bone", "3ffe::/16")
        and hasReason("3ffe:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
            "returned_6bone", "3ffe::/16")
        and Ipv6Address.isGlobal("3ffd:ffff::") == true
        and hasReason("2620:4f:8000::", "special_service_as112",
            "2620:4f:8000::/48")
        and hasReason("2620:4f:8000:ffff:ffff:ffff:ffff:ffff",
            "special_service_as112", "2620:4f:8000::/48")
        and Ipv6Address.isGlobal("2620:4f:7fff:ffff::") == true
        and Ipv6Address.isGlobal("2620:4f:8001::") == true)

    check("ipv6_address_accepts_only_ordinary_2000_prefix_global_unicast_candidates",
        allGlobal({
            "2000::", "2001:200::", "2001:db7:ffff::", "2003::",
            "2400::1", "2a00:1450:4009:80b::200e", "3ffd:ffff::",
            "3fff:1000::",
        })
        and hasReason("1fff:ffff::", "not_global_unicast")
        and hasReason("4000::", "not_global_unicast"))

    local endpointFromText, endpointTextError = Ipv6Address.endpoint(
        "2001:0DB8:0:0:0:0:0:1", 22122)
    local endpointParsed = Ipv6Address.parse("2a00::1")
    local endpointFromParsed, endpointParsedError = Ipv6Address.endpoint(endpointParsed, 65535)
    check("ipv6_address_formats_unambiguous_canonical_endpoints",
        endpointTextError == nil and endpointFromText == "[2001:db8::1]:22122"
        and endpointParsedError == nil and endpointFromParsed == "[2a00::1]:65535")

    local badPorts = {
        { nil, "port_not_number" },
        { "22122", "port_not_number" },
        { 0 / 0, "port_not_number" },
        { 1.5, "port_not_integer" },
        { 0, "port_out_of_range" },
        { 65536, "port_out_of_range" },
    }
    local badPortsRejected = true
    for _, case in ipairs(badPorts) do
        local endpoint, endpointError = Ipv6Address.endpoint("2001:db8::1", case[1])
        badPortsRejected = badPortsRejected
            and endpoint == nil and endpointError == case[2]
    end
    local badParsedEndpoint, badParsedError = Ipv6Address.endpoint({}, 22122)
    check("ipv6_address_endpoint_rejects_invalid_ports_and_untrusted_parsed_values",
        badPortsRejected and badParsedEndpoint == nil
        and badParsedError == "invalid_parsed_value")

    local spoofed = {
        address = "2001:db8::1",
        bytes = Ipv6Address.parse("2a00::1").bytes,
        isGlobal = false,
    }
    local spoofedGlobal, normalizedSpoofed = Ipv6Address.isGlobal(spoofed)
    check("ipv6_address_revalidates_binary_value_instead_of_trusting_table_fields",
        spoofedGlobal == true and normalizedSpoofed.address == "2a00::1"
        and normalizedSpoofed.isGlobal == true)
end

return Test
