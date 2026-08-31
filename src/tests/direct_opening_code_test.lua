local DirectOpeningCode = require("src.net.direct_opening_code")

local Test = {}

local ISSUED_AT = 0x65010203
local HOST_ADDRESS = "2606:4700:4700::1111"
local GUEST_ADDRESS = "2001:4860:4860::8888"
local INVITATION_ID = string.char(
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
local MASTER_KEY = string.char(
    32, 33, 34, 35, 36, 37, 38, 39,
    40, 41, 42, 43, 44, 45, 46, 47,
    48, 49, 50, 51, 52, 53, 54, 55,
    56, 57, 58, 59, 60, 61, 62, 63)
local GUEST_NONCE = string.char(
    160, 161, 162, 163, 164, 165, 166, 167,
    168, 169, 170, 171, 172, 173, 174, 175)
local RESPONSE_TAG = string.char(
    192, 193, 194, 195, 196, 197, 198, 199,
    200, 201, 202, 203, 204, 205, 206, 207,
    208, 209, 210, 211, 212, 213, 214, 215,
    216, 217, 218, 219, 220, 221, 222, 223)

local HOST_VECTOR = "TPS2H."
    .. "AgEGAGUBAgMCWFZqJgZHAEcAAAAAAAAAAAAREQABAgMEBQYHCAkKCwwNDg8g"
    .. "ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-Pw"
local RESPONSE_VECTOR = "TPS2R."
    .. "AgIGAGUBAgMCWHAOIAFIYEhgAAAAAAAAAACIiAABAgMEBQYHCAkKCwwNDg-go"
    .. "aKjpKWmp6ipqqusra6vwMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t8"
local TRANSCRIPT_HEX = "545053322d524553504f4e53452d7631"
    .. "02010600650102030258566a26064700470000000000000000001111"
    .. "000102030405060708090a0b0c0d0e0f"
    .. "02020600650102030258700e20014860486000000000000000008888"
    .. "000102030405060708090a0b0c0d0e0f"
    .. "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf"

local BASE64URL_ALPHABET =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

local function bytesToHex(value)
    local encoded = {}
    for index = 1, #value do
        encoded[index] = string.format("%02x", value:byte(index))
    end
    return table.concat(encoded)
end

-- Deliberately independent test encoder, used to construct malformed but
-- canonically encoded payloads without depending on production internals.
local function encodeBase64Url(bytes)
    local encoded = {}
    local outputIndex = 1
    for offset = 1, #bytes, 3 do
        local first = bytes:byte(offset)
        local second = bytes:byte(offset + 1)
        local third = bytes:byte(offset + 2)
        local value = first * 65536 + (second or 0) * 256 + (third or 0)
        local positions = {
            math.floor(value / 262144) % 64,
            math.floor(value / 4096) % 64,
            math.floor(value / 64) % 64,
            value % 64,
        }
        local count = third and 4 or (second and 3 or 2)
        for position = 1, count do
            local alphabetIndex = positions[position] + 1
            encoded[outputIndex] = BASE64URL_ALPHABET:sub(
                alphabetIndex, alphabetIndex)
            outputIndex = outputIndex + 1
        end
    end
    return table.concat(encoded)
end

local function replaceByte(value, offset, byte)
    return value:sub(1, offset - 1) .. string.char(byte) .. value:sub(offset + 1)
end

local function hostFields(overrides)
    local fields = {
        issuedAt = ISSUED_AT,
        lifetime = 600,
        port = 22122,
        address = HOST_ADDRESS,
        invitationId = INVITATION_ID,
        masterKey = MASTER_KEY,
    }
    for key, value in pairs(overrides or {}) do fields[key] = value end
    return fields
end

local function responseFields(overrides)
    local fields = {
        issuedAt = ISSUED_AT,
        lifetime = 600,
        port = 28686,
        address = GUEST_ADDRESS,
        invitationId = INVITATION_ID,
        guestNonce = GUEST_NONCE,
        responseTag = RESPONSE_TAG,
    }
    for key, value in pairs(overrides or {}) do fields[key] = value end
    return fields
end

local function hostRejected(code, nowOrOptions, maybeOptions)
    local parsed, errorMessage = DirectOpeningCode.parseHost(
        code, nowOrOptions or ISSUED_AT, maybeOptions)
    return parsed == nil and type(errorMessage) == "string" and errorMessage ~= ""
end

local function responseRejected(code)
    local parsed, errorMessage = DirectOpeningCode.parseResponse(code)
    return parsed == nil and type(errorMessage) == "string" and errorMessage ~= ""
end

local function hostCodeForBytes(bytes)
    return DirectOpeningCode.HOST_PREFIX .. encodeBase64Url(bytes)
end

local function responseCodeForBytes(bytes)
    return DirectOpeningCode.RESPONSE_PREFIX .. encodeBase64Url(bytes)
end

function Test.run(_, check)
    local hostCode, hostEncodeError = DirectOpeningCode.encodeHost(hostFields())
    local parsedHost, hostParseError = DirectOpeningCode.parseHost(
        hostCode, { now = ISSUED_AT, clockSkew = 0 })
    check("direct_opening_host_matches_fixed_binary_vector",
        hostEncodeError == nil and hostParseError == nil
        and hostCode == HOST_VECTOR and #parsedHost.bytes == 76
        and parsedHost.kind == "host" and parsedHost.version == 2
        and parsedHost.issuedAt == ISSUED_AT and parsedHost.lifetime == 600
        and parsedHost.port == 22122 and parsedHost.hostPort == 22122
        and parsedHost.address == HOST_ADDRESS
        and parsedHost.hostAddress == HOST_ADDRESS
        and parsedHost.invitationId == INVITATION_ID
        and parsedHost.masterKey == MASTER_KEY)

    local responseCode, responseEncodeError = DirectOpeningCode.encodeResponse(
        responseFields())
    local parsedResponse, responseParseError =
        DirectOpeningCode.parseResponse(responseCode)
    check("direct_opening_response_matches_fixed_binary_vector",
        responseEncodeError == nil and responseParseError == nil
        and responseCode == RESPONSE_VECTOR and #parsedResponse.bytes == 92
        and parsedResponse.kind == "response" and parsedResponse.version == 2
        and parsedResponse.issuedAt == ISSUED_AT
        and parsedResponse.lifetime == 600
        and parsedResponse.port == 28686 and parsedResponse.guestPort == 28686
        and parsedResponse.address == GUEST_ADDRESS
        and parsedResponse.guestAddress == GUEST_ADDRESS
        and parsedResponse.invitationId == INVITATION_ID
        and parsedResponse.guestNonce == GUEST_NONCE
        and parsedResponse.responseTag == RESPONSE_TAG)

    local transcript, transcriptError = DirectOpeningCode.responseTranscript(
        parsedHost, responseFields({ responseTag = nil }))
    local transcriptFromCodes = DirectOpeningCode.responseTranscript(
        HOST_VECTOR, RESPONSE_VECTOR)
    check("direct_opening_response_transcript_is_domain_and_exact_slices",
        transcriptError == nil and #transcript == 120
        and bytesToHex(transcript) == TRANSCRIPT_HEX
        and transcriptFromCodes == transcript)

    local observed = {}
    local verified, verifyError = DirectOpeningCode.verifyResponse(
        parsedHost, parsedResponse, function(key, message, tag)
            observed.key, observed.message, observed.tag = key, message, tag
            return key == MASTER_KEY and message == transcript and tag == RESPONSE_TAG
        end)
    check("direct_opening_verification_injects_key_transcript_and_tag",
        verifyError == nil and verified and verified.guestPort == 28686
        and observed.key == MASTER_KEY and observed.message == transcript
        and observed.tag == RESPONSE_TAG)

    local matched, matchError = DirectOpeningCode.matchResponse(
        parsedHost, parsedResponse)
    check("direct_opening_matching_accepts_the_three_host_echo_fields",
        matchError == nil and matched and matched.invitationId == INVITATION_ID)

    local defaultFields = hostFields()
    defaultFields.lifetime = nil
    local defaultCode = DirectOpeningCode.encodeHost(defaultFields)
    local defaultParsed = DirectOpeningCode.parseHost(defaultCode, ISSUED_AT, {
        clockSkew = 0,
    })
    local maximumCode = DirectOpeningCode.encodeHost(hostFields({ lifetime = 900 }))
    check("direct_opening_lifetime_defaults_to_ten_and_caps_at_fifteen_minutes",
        defaultParsed and defaultParsed.lifetime == 600
        and maximumCode ~= nil
        and DirectOpeningCode.encodeHost(hostFields({ lifetime = 901 })) == nil
        and DirectOpeningCode.encodeHost(hostFields({ lifetime = 0 })) == nil)

    local canonicalizedCode = DirectOpeningCode.encodeHost(hostFields({
        address = "2606:4700:4700:0:0:0:0:1111",
    }))
    local canonicalized = DirectOpeningCode.parseHost(canonicalizedCode, ISSUED_AT)
    check("direct_opening_binary_ipv6_encoding_canonicalizes_text_input",
        canonicalizedCode == HOST_VECTOR
        and canonicalized and canonicalized.address == HOST_ADDRESS)

    local aliasHost = hostFields()
    aliasHost.port = nil
    aliasHost.address = nil
    aliasHost.hostPort = 22122
    aliasHost.hostAddress = HOST_ADDRESS
    local aliasResponse = responseFields()
    aliasResponse.port = nil
    aliasResponse.address = nil
    aliasResponse.guestPort = 28686
    aliasResponse.guestAddress = GUEST_ADDRESS
    check("direct_opening_semantic_address_and_port_aliases_are_supported",
        DirectOpeningCode.encodeHost(aliasHost) == HOST_VECTOR
        and DirectOpeningCode.encodeResponse(aliasResponse) == RESPONSE_VECTOR
        and DirectOpeningCode.encodeHost(hostFields({ hostPort = 1 })) == nil
        and DirectOpeningCode.encodeResponse(responseFields({ guestPort = 1 })) == nil)

    local invalidHostFields = {
        hostFields({ issuedAt = -1 }),
        hostFields({ issuedAt = 0x100000000 }),
        hostFields({ issuedAt = 1.5 }),
        hostFields({ port = 0 }),
        hostFields({ port = 65536 }),
        hostFields({ port = 1.5 }),
        hostFields({ address = "fd00::1" }),
        hostFields({ address = "fe80::1" }),
        hostFields({ address = "2001:db8::1" }),
        hostFields({ invitationId = INVITATION_ID:sub(1, 15) }),
        hostFields({ masterKey = MASTER_KEY:sub(1, 31) }),
    }
    local hostFieldsRejected = true
    for _, fields in ipairs(invalidHostFields) do
        local code, errorMessage = DirectOpeningCode.encodeHost(fields)
        hostFieldsRejected = hostFieldsRejected and code == nil
            and type(errorMessage) == "string"
    end
    check("direct_opening_host_encoder_enforces_ranges_lengths_and_public_ipv6",
        hostFieldsRejected)

    local invalidResponseFields = {
        responseFields({ issuedAt = -1 }),
        responseFields({ lifetime = 0 }),
        responseFields({ lifetime = 901 }),
        responseFields({ port = 0 }),
        responseFields({ address = "::1" }),
        responseFields({ invitationId = INVITATION_ID:sub(1, 15) }),
        responseFields({ guestNonce = GUEST_NONCE:sub(1, 15) }),
        responseFields({ responseTag = RESPONSE_TAG:sub(1, 31) }),
    }
    local responseFieldsRejected = true
    for _, fields in ipairs(invalidResponseFields) do
        local code, errorMessage = DirectOpeningCode.encodeResponse(fields)
        responseFieldsRejected = responseFieldsRejected and code == nil
            and type(errorMessage) == "string"
    end
    check("direct_opening_response_encoder_enforces_ranges_lengths_and_public_ipv6",
        responseFieldsRejected)

    local hostBytes = parsedHost.bytes
    local malformedHostBytes = {
        replaceByte(hostBytes, 1, 3),
        replaceByte(hostBytes, 2, 2),
        replaceByte(hostBytes, 3, 4),
        replaceByte(hostBytes, 4, 1),
        replaceByte(replaceByte(hostBytes, 9, 0), 10, 0),
        replaceByte(replaceByte(hostBytes, 9, 3), 10, 133),
        replaceByte(replaceByte(hostBytes, 11, 0), 12, 0),
        hostBytes:sub(1, 12) .. string.char(0xfd)
            .. hostBytes:sub(14),
    }
    local malformedHostRejected = true
    for _, bytes in ipairs(malformedHostBytes) do
        malformedHostRejected = malformedHostRejected
            and hostRejected(hostCodeForBytes(bytes))
    end
    check("direct_opening_host_parser_rejects_header_flags_and_invalid_fields",
        malformedHostRejected)

    local responseBytes = parsedResponse.bytes
    local malformedResponseBytes = {
        replaceByte(responseBytes, 1, 3),
        replaceByte(responseBytes, 2, 1),
        replaceByte(responseBytes, 3, 4),
        replaceByte(responseBytes, 4, 1),
        replaceByte(replaceByte(responseBytes, 9, 0), 10, 0),
        replaceByte(replaceByte(responseBytes, 11, 0), 12, 0),
        responseBytes:sub(1, 12) .. string.char(0xfd)
            .. responseBytes:sub(14),
    }
    local malformedResponseRejected = true
    for _, bytes in ipairs(malformedResponseBytes) do
        malformedResponseRejected = malformedResponseRejected
            and responseRejected(responseCodeForBytes(bytes))
    end
    check("direct_opening_response_parser_rejects_header_flags_and_invalid_fields",
        malformedResponseRejected)

    check("direct_opening_parsers_enforce_exact_prefix_and_payload_lengths",
        hostRejected(HOST_VECTOR:sub(1, -2))
        and hostRejected(HOST_VECTOR .. "A")
        and hostRejected("TPS2R." .. HOST_VECTOR:sub(7))
        and hostRejected("tps2h." .. HOST_VECTOR:sub(7))
        and hostRejected(hostCodeForBytes(hostBytes:sub(1, -2)))
        and hostRejected(hostCodeForBytes(hostBytes .. "\0"))
        and responseRejected(RESPONSE_VECTOR:sub(1, -2))
        and responseRejected(RESPONSE_VECTOR .. "A")
        and responseRejected("TPS2H." .. RESPONSE_VECTOR:sub(7))
        and responseRejected(responseCodeForBytes(responseBytes:sub(1, -2)))
        and responseRejected(responseCodeForBytes(responseBytes .. "\0")))

    local paddedHost = DirectOpeningCode.parseHost(
        string.rep(" ", 16) .. HOST_VECTOR .. string.rep("\t", 16), ISSUED_AT)
    local paddedResponse = DirectOpeningCode.parseResponse(
        "\r\n" .. RESPONSE_VECTOR .. "\t ")
    check("direct_opening_only_allows_bounded_outer_whitespace",
        paddedHost and paddedResponse
        and hostRejected(string.rep(" ", 33) .. HOST_VECTOR)
        and responseRejected(RESPONSE_VECTOR .. string.rep("\t", 33))
        and hostRejected(HOST_VECTOR:sub(1, 20) .. " " .. HOST_VECTOR:sub(21))
        and responseRejected(RESPONSE_VECTOR:sub(1, 20)
            .. "\n" .. RESPONSE_VECTOR:sub(21)))

    local noncanonicalHost = HOST_VECTOR:sub(1, -2) .. "x"
    local noncanonicalResponse = RESPONSE_VECTOR:sub(1, -2) .. "9"
    check("direct_opening_rejects_padding_alphabet_and_noncanonical_low_bits",
        hostRejected(HOST_VECTOR .. "==")
        and responseRejected(RESPONSE_VECTOR .. "=")
        and hostRejected(HOST_VECTOR:sub(1, 30) .. "+" .. HOST_VECTOR:sub(32))
        and responseRejected(RESPONSE_VECTOR:sub(1, 30)
            .. "/" .. RESPONSE_VECTOR:sub(32))
        and hostRejected(noncanonicalHost)
        and responseRejected(noncanonicalResponse))

    local timeCode = DirectOpeningCode.encodeHost(hostFields({
        issuedAt = 1000,
        lifetime = 600,
    }))
    local exactStart = DirectOpeningCode.parseHost(timeCode, {
        now = 1000, clockSkew = 0,
    })
    local exactEnd = DirectOpeningCode.parseHost(timeCode, {
        now = 1600, clockSkew = 0,
    })
    local futureBoundary = DirectOpeningCode.parseHost(timeCode, {
        now = 700,
    })
    local expiryBoundary = DirectOpeningCode.parseHost(timeCode, {
        now = 1900,
    })
    check("direct_opening_host_time_validation_has_explicit_skew_boundaries",
        exactStart and exactEnd and futureBoundary and expiryBoundary
        and hostRejected(timeCode, { now = 999, clockSkew = 0 })
        and hostRejected(timeCode, { now = 699 })
        and hostRejected(timeCode, { now = 1601, clockSkew = 0 })
        and DirectOpeningCode.parseHost(timeCode, {
            now = 999, clockSkew = 0, futureSkew = 1,
        }) ~= nil
        and DirectOpeningCode.parseHost(timeCode, {
            now = 1601, clockSkew = 0, expiryGrace = 1,
        }) ~= nil)

    check("direct_opening_rejects_invalid_clock_validation_options",
        hostRejected(timeCode, { now = -1 })
        and hostRejected(timeCode, { now = 1000, clockSkew = -1 })
        and hostRejected(timeCode, { now = 1000, clockSkew = 901 })
        and hostRejected(timeCode, { now = 1000, futureSkew = 901 })
        and hostRejected(timeCode, { now = 1000, expiryGrace = 1.5 }))

    local mismatchedResponses = {
        responseFields({ issuedAt = ISSUED_AT + 1 }),
        responseFields({ lifetime = 599 }),
        responseFields({ invitationId = string.rep("x", 16) }),
    }
    local mismatchesRejected = true
    for _, fields in ipairs(mismatchedResponses) do
        local code = DirectOpeningCode.encodeResponse(fields)
        local value, errorMessage = DirectOpeningCode.matchResponse(HOST_VECTOR, code)
        mismatchesRejected = mismatchesRejected and value == nil
            and type(errorMessage) == "string"
            and errorMessage:find(MASTER_KEY, 1, true) == nil
            and errorMessage:find(HOST_ADDRESS, 1, true) == nil
    end
    check("direct_opening_response_echo_must_match_host_invitation",
        mismatchesRejected)

    local callbackSecret = "native-verifier-detail-must-not-leak"
    local missingVerification, missingVerificationError =
        DirectOpeningCode.verifyResponse(parsedHost, parsedResponse)
    local falseVerification, falseVerificationError =
        DirectOpeningCode.verifyResponse(parsedHost, parsedResponse, function()
            return false
        end)
    local truthyVerification, truthyVerificationError =
        DirectOpeningCode.verifyResponse(parsedHost, parsedResponse, function()
            return "true"
        end)
    local failedVerification, failedVerificationError =
        DirectOpeningCode.verifyResponse(parsedHost, parsedResponse, function()
            error(callbackSecret)
        end)
    check("direct_opening_tag_verifier_is_required_strict_and_fail_closed",
        missingVerification == nil
        and missingVerificationError:find("required", 1, true)
        and falseVerification == nil and type(falseVerificationError) == "string"
        and truthyVerification == nil and type(truthyVerificationError) == "string"
        and failedVerification == nil and type(failedVerificationError) == "string"
        and failedVerificationError:find(callbackSecret, 1, true) == nil)

    local mutatedTagCode = DirectOpeningCode.encodeResponse(responseFields({
        responseTag = RESPONSE_TAG:sub(1, 31) .. "x",
    }))
    local mutatedTagVerified = DirectOpeningCode.verifyResponse(
        parsedHost, mutatedTagCode, function(_, _, tag)
            return tag == RESPONSE_TAG
        end)
    check("direct_opening_response_tag_mutation_fails_injected_verification",
        mutatedTagVerified == nil)

    local redactedHost = DirectOpeningCode.redact(HOST_VECTOR)
    local redactedHostTable = DirectOpeningCode.redact(parsedHost)
    local redactedResponse = DirectOpeningCode.redact(RESPONSE_VECTOR)
    local redactedResponseTable = DirectOpeningCode.redact(parsedResponse)
    local redactedMalformed = DirectOpeningCode.redact("untrusted")
    check("direct_opening_redaction_is_opaque_for_valid_and_malformed_input",
        redactedHost == "TPS2H.<redacted>"
        and redactedHostTable == redactedHost
        and redactedResponse == "TPS2R.<redacted>"
        and redactedResponseTable == redactedResponse
        and redactedMalformed == "TPS2.<redacted>"
        and redactedHost:find(HOST_ADDRESS, 1, true) == nil
        and redactedHost:find(MASTER_KEY, 1, true) == nil
        and redactedResponse:find(GUEST_ADDRESS, 1, true) == nil
        and redactedResponse:find(RESPONSE_TAG, 1, true) == nil)
end

return Test
