local DirectInvite = require("src.net.direct_invite")

local Test = {}

local function entropyFixture()
    local bytes = {}
    for value = 0, DirectInvite.KEY_BYTES - 1 do
        bytes[#bytes + 1] = string.char(value)
    end
    return table.concat(bytes)
end

local function fixedRandom(value, calls)
    return function(requestedBytes)
        calls[#calls + 1] = requestedBytes
        return value
    end
end

local function rejected(code)
    local parsed, errorMessage = DirectInvite.parse(code)
    return parsed == nil and type(errorMessage) == "string" and errorMessage ~= ""
end

function Test.run(_, check)
    local entropy = entropyFixture()
    local expectedHex = "000102030405060708090a0b0c0d0e0f"
        .. "101112131415161718191a1b1c1d1e1f"
    local calls = {}
    local code, createError = DirectInvite.create(
        "Example.COM:22122", fixedRandom(entropy, calls))
    local parsed, parseError = DirectInvite.parse(code)
    check("direct_invite_secure_entropy_round_trips_in_canonical_format",
        createError == nil and parseError == nil
        and code == "TPS1|example.com:22122|" .. expectedHex
        and #calls == 1 and calls[1] == 32
        and parsed.version == "TPS1"
        and parsed.endpoint == "example.com:22122"
        and parsed.host == "example.com" and parsed.port == 22122
        and parsed.psk == entropy and #parsed.psk == 32)

    local splitCalls = {}
    local splitKey, splitKeyError = DirectInvite.generateKey(
        fixedRandom(entropy, splitCalls))
    local splitCode, splitEncodeError = DirectInvite.encode(
        "Example.COM:22122", splitKey)
    check("direct_invite_generates_key_before_mapping_then_encodes_final_endpoint",
        splitKeyError == nil and splitEncodeError == nil
        and splitKey == entropy and #splitCalls == 1
        and splitCalls[1] == DirectInvite.KEY_BYTES
        and splitCode == code)

    local invalidSplitKey, invalidSplitKeyError = DirectInvite.generateKey(nil)
    local shortEncoded, shortEncodeError = DirectInvite.encode(
        "example.com:22122", entropy:sub(1, 31))
    local nonTextEncoded, nonTextEncodeError = DirectInvite.encode(
        "example.com:22122", {})
    check("direct_invite_split_lifecycle_rejects_missing_rng_and_invalid_keys",
        invalidSplitKey == nil and invalidSplitKeyError:find("secure random", 1, true)
        and shortEncoded == nil and shortEncodeError:find("exactly 32 bytes", 1, true)
        and nonTextEncoded == nil and nonTextEncodeError:find("exactly 32 bytes", 1, true))

    local padded = DirectInvite.parse(" \t" .. code .. " \r\n")
    check("direct_invite_trims_whitespace_only_at_outer_edges",
        padded and padded.endpoint == parsed.endpoint and padded.psk == entropy
        and rejected("TPS1| example.com:22122|" .. expectedHex)
        and rejected("TPS1|example.com:22122 |" .. expectedHex)
        and rejected("TPS1|example.com:22122|" .. expectedHex:sub(1, 20)
            .. " " .. expectedHex:sub(21)))

    local missingCode, missingError = DirectInvite.create("example.com:22122")
    local shortCode, shortError = DirectInvite.create(
        "example.com:22122", function() return entropy:sub(1, 31) end)
    local longCode, longError = DirectInvite.create(
        "example.com:22122", function() return entropy .. "x" end)
    local nonTextCode, nonTextError = DirectInvite.create(
        "example.com:22122", function() return {} end)
    local providerSecret = "provider-must-not-leak"
    local failedCode, failedError = DirectInvite.create(
        "example.com:22122", function() error(providerSecret) end)
    check("direct_invite_requires_exact_operating_system_random_bytes",
        missingCode == nil and missingError:find("secure random", 1, true)
        and shortCode == nil and shortError:find("exactly 32 bytes", 1, true)
        and longCode == nil and longError:find("exactly 32 bytes", 1, true)
        and nonTextCode == nil and nonTextError:find("exactly 32 bytes", 1, true)
        and failedCode == nil and failedError:find(providerSecret, 1, true) == nil)

    local invalidEndpointCode, invalidEndpointError = DirectInvite.create(
        "https://example.com/game", fixedRandom(entropy, {}))
    check("direct_invite_create_rejects_invalid_endpoint_before_rng",
        invalidEndpointCode == nil and type(invalidEndpointError) == "string")

    local secretHex = string.rep("de", 32)
    local validPrefix = "TPS1|game.example:22122|"
    local malformedCodes = {
        42,
        "",
        "TPS1",
        "TPS1|game.example:22122",
        validPrefix .. secretHex .. "|extra",
        "TPS1||" .. secretHex,
        string.rep("x", DirectInvite.MAX_CODE_LENGTH + 33),
    }
    local malformedRejected = rejected(nil)
    for _, malformed in ipairs(malformedCodes) do
        malformedRejected = malformedRejected and rejected(malformed)
    end
    check("direct_invite_rejects_malformed_and_overlong_codes", malformedRejected)

    check("direct_invite_rejects_unknown_versions_and_urls",
        rejected("TPS2|game.example:22122|" .. secretHex)
        and rejected("tps1|game.example:22122|" .. secretHex)
        and rejected("TPS1|https://game.example:22122|" .. secretHex)
        and rejected("https://game.example/TPS1|game.example:22122|" .. secretHex))

    check("direct_invite_rejects_controls_anywhere_inside_the_code",
        rejected("TPS1|game.example:\n22122|" .. secretHex)
        and rejected("TPS1|game.example:22122|" .. secretHex:sub(1, 24)
            .. "\0" .. secretHex:sub(25))
        and rejected("TPS1|game.example:22122|" .. secretHex:sub(1, 24)
            .. "\127" .. secretHex:sub(25)))

    local invalidEndpoints = {
        "game.example",
        "GAME.example:22122",
        "game.example:022122",
        "game example:22122",
        "999.1.1.1:22122",
        "224.0.0.1:22122",
        "game.example:0",
        "game.example:65536",
        "game.example:22:122",
        "user@game.example:22122",
    }
    local endpointsRejected = true
    for _, endpoint in ipairs(invalidEndpoints) do
        endpointsRejected = endpointsRejected
            and rejected("TPS1|" .. endpoint .. "|" .. secretHex)
    end
    check("direct_invite_rejects_invalid_or_noncanonical_endpoints", endpointsRejected)

    local invalidKeys = {
        secretHex:sub(1, 63),
        secretHex .. "0",
        secretHex:upper(),
        secretHex:sub(1, 63) .. "g",
        string.rep("-", 64),
    }
    local keysRejected, errorsHideKey = true, true
    for _, key in ipairs(invalidKeys) do
        local value, errorMessage = DirectInvite.parse(validPrefix .. key)
        keysRejected = keysRejected and value == nil
        errorsHideKey = errorsHideKey and type(errorMessage) == "string"
            and errorMessage:find(key, 1, true) == nil
    end
    check("direct_invite_rejects_non_lowercase_or_wrong_length_keys",
        keysRejected and errorsHideKey)

    local redactedCode = DirectInvite.redact(code)
    local redactedParsed = DirectInvite.redact(parsed)
    local redactedMalformed = DirectInvite.redact(validPrefix .. secretHex .. "x")
    check("direct_invite_redaction_never_includes_key_material",
        redactedCode == "TPS1|example.com:22122|<redacted>"
        and redactedParsed == redactedCode
        and redactedCode:find(expectedHex, 1, true) == nil
        and redactedCode:find(entropy, 1, true) == nil
        and redactedMalformed == "TPS1|<invalid-endpoint>|<redacted>"
        and redactedMalformed:find(secretHex, 1, true) == nil)
end

return Test
