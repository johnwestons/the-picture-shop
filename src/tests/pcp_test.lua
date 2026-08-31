local Pcp = require("src.net.pcp")

local Test = {}

local function u16(value)
    return string.char(math.floor(value / 256) % 256, value % 256)
end

local function u32(value)
    return string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256)
end

local function hex(data)
    return (data:gsub(".", function(value) return string.format("%02x", value:byte()) end))
end

local function mapped(a, b, c, d)
    return string.rep("\0", 10) .. "\255\255" .. string.char(a, b, c, d)
end

local function announceResponse(overrides)
    overrides = overrides or {}
    return string.char(
        overrides.version or 2,
        overrides.responseOpcode or 128,
        overrides.reservedByte or 0,
        overrides.resultCode or 0)
        .. u32(overrides.lifetime or 0)
        .. u32(overrides.epoch or 0)
        .. (overrides.reserved or string.rep("\0", 12))
        .. (overrides.options or "")
end

local function mapResponse(context, overrides)
    overrides = overrides or {}
    return string.char(
        overrides.version or 2,
        overrides.responseOpcode or 129,
        overrides.headerReserved or 0,
        overrides.resultCode or 0)
        .. u32(overrides.lifetime == nil and 7200 or overrides.lifetime)
        .. u32(overrides.epoch or 100)
        .. (overrides.headerTail or string.rep("\0", 12))
        .. (overrides.nonce or context.nonce)
        .. string.char(overrides.protocol or context.protocol, 0, 0, 0)
        .. u16(overrides.internalPort or context.internalPort)
        .. u16(overrides.externalPort == nil and 22122 or overrides.externalPort)
        .. (overrides.externalAddress or mapped(8, 8, 4, 4))
        .. (overrides.options or "")
end

local function rejected(decoder, value, expected)
    local parsed, errorMessage = decoder(value, expected)
    return parsed == nil and type(errorMessage) == "string" and errorMessage ~= ""
end

function Test.run(_, check)
    local announce, announceContext = Pcp.encodeAnnounceRequest("192.168.1.134")
    check("pcp_announce_request_matches_rfc6887_wire_layout",
        #announce == 24 and announceContext.opcode == Pcp.OPCODE_ANNOUNCE
        and hex(announce) == "020000000000000000000000000000000000ffffc0a80186")

    local nonce = string.char(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
    local mapRequest, context = Pcp.encodeMapRequest({
        clientAddress = "192.168.1.134",
        nonce = nonce,
        protocol = Pcp.PROTOCOL_UDP,
        internalPort = 22122,
        suggestedExternalPort = 22122,
        suggestedExternalAddress = "0.0.0.0",
        lifetime = 7200,
    })
    check("pcp_map_request_matches_rfc6887_wire_layout",
        #mapRequest == 60 and context.nonce == nonce
        and context.requestedLifetime == 7200
        and hex(mapRequest) == "0201000000001c2000000000000000000000ffffc0a80186"
            .. "000102030405060708090a0b11000000566a566a"
            .. "00000000000000000000ffff00000000")

    local invalidRequests = {
        {},
        { clientAddress = "192.168.001.2", nonce = nonce, internalPort = 1, lifetime = 1 },
        { clientAddress = "192.168.1.2", nonce = nonce:sub(1, 11), internalPort = 1, lifetime = 1 },
        { clientAddress = "192.168.1.2", nonce = nonce .. "x", internalPort = 1, lifetime = 1 },
        { clientAddress = "192.168.1.2", nonce = nonce, internalPort = 0, lifetime = 1 },
        { clientAddress = "192.168.1.2", nonce = nonce, internalPort = 65536, lifetime = 1 },
        { clientAddress = "192.168.1.2", nonce = nonce, internalPort = 1, lifetime = 1 / 0 },
        { clientAddress = "192.168.1.2", nonce = nonce, internalPort = 1, lifetime = 0 / 0 },
        { clientAddress = "192.168.1.2", nonce = nonce, protocol = 0, internalPort = 1, lifetime = 0 },
        { clientAddress = "192.168.1.2", nonce = nonce, protocol = 6, internalPort = 1, lifetime = 1 },
        { clientAddress = "192.168.1.2", nonce = nonce, internalPort = 1,
            suggestedExternalPort = 1, lifetime = 0 },
        { clientAddress = "192.168.1.2", nonce = nonce, internalPort = 1,
            suggestedExternalAddress = "8.8.4.4", lifetime = 0 },
    }
    local nilEncoded, nilEncodeError = Pcp.encodeMapRequest(nil)
    local invalidRejected = nilEncoded == nil and type(nilEncodeError) == "string"
    local errorsHideNonce = true
    for _, value in ipairs(invalidRequests) do
        local encoded, errorMessage = Pcp.encodeMapRequest(value)
        invalidRejected = invalidRejected and encoded == nil and type(errorMessage) == "string"
        errorsHideNonce = errorsHideNonce and errorMessage:find(nonce, 1, true) == nil
    end
    local badAnnounce, badAnnounceError = Pcp.encodeAnnounceRequest("example.com")
    check("pcp_encoder_rejects_noncanonical_unbounded_or_nonfinite_fields",
        invalidRejected and errorsHideNonce and badAnnounce == nil
        and type(badAnnounceError) == "string")

    local option = string.char(128, 77) .. u16(3) .. "abc\0"
    local decodedAnnounce = Pcp.decodeAnnounceResponse(announceResponse({
        reservedByte = 99,
        reserved = string.rep("r", 12),
        lifetime = 123,
        epoch = 456,
        options = option,
    }))
    check("pcp_announce_response_ignores_reserved_fields_and_boundedly_parses_options",
        decodedAnnounce and decodedAnnounce.success
        and decodedAnnounce.epoch == 456
        and decodedAnnounce.wireLifetime == 123
        and decodedAnnounce.lifetime == 0 and decodedAnnounce.lifetimeIgnored
        and #decodedAnnounce.options == 1
        and decodedAnnounce.options[1].code == 128
        and decodedAnnounce.options[1].optional
        and decodedAnnounce.options[1].data == "abc")

    local malformedAnnounces = {
        "",
        announceResponse():sub(1, 23),
        announceResponse() .. "x",
        string.rep("\0", Pcp.MAX_PACKET_BYTES + 4),
        announceResponse({ version = 1 }),
        announceResponse({ responseOpcode = 0 }),
        announceResponse({ responseOpcode = 129 }),
        announceResponse({ options = string.char(128, 0, 0, 4) .. "x" }),
        announceResponse({ options = string.char(128, 0, 0, 3) .. "abcx" }),
    }
    local malformedAnnouncesRejected = rejected(Pcp.decodeAnnounceResponse, nil)
    for _, value in ipairs(malformedAnnounces) do
        malformedAnnouncesRejected = malformedAnnouncesRejected
            and rejected(Pcp.decodeAnnounceResponse, value)
    end
    check("pcp_announce_decoder_rejects_malformed_or_unmatched_packets",
        malformedAnnouncesRejected)

    local decodedMap = Pcp.decodeMapResponse(mapResponse(context, {
        lifetime = 4294967295,
        epoch = 9001,
        externalPort = 40000,
    }), context)
    check("pcp_map_response_matches_nonce_protocol_port_and_caps_absurd_lifetime",
        decodedMap and decodedMap.success and decodedMap.resultName == "SUCCESS"
        and decodedMap.resultKnown and decodedMap.epoch == 9001
        and decodedMap.nonce == nonce and decodedMap.protocol == 17
        and decodedMap.internalPort == 22122 and decodedMap.externalPort == 40000
        and decodedMap.externalAddress == "8.8.4.4"
        and decodedMap.wireLifetime == 4294967295
        and decodedMap.lifetime == Pcp.DEFAULT_MAX_LIFETIME
        and decodedMap.lifetimeCapped)

    local mismatches = {
        mapResponse(context, { nonce = string.rep("n", 12) }),
        mapResponse(context, { protocol = 6 }),
        mapResponse(context, { internalPort = 22123 }),
        mapResponse(context, { responseOpcode = 130 }),
        mapResponse(context, { externalAddress = string.rep("\0", 16) }),
        mapResponse(context):sub(1, 59),
    }
    local mismatchesRejected = rejected(Pcp.decodeMapResponse, mapResponse(context), nil)
    for _, value in ipairs(mismatches) do
        mismatchesRejected = mismatchesRejected and rejected(Pcp.decodeMapResponse, value, context)
    end
    local mismatchValue, mismatchError = Pcp.decodeMapResponse(mismatches[1], context)
    check("pcp_map_decoder_rejects_unmatched_and_non_ipv4_responses_without_leaking_nonce",
        mismatchesRejected and mismatchValue == nil
        and mismatchError:find(nonce, 1, true) == nil)

    local knownError = Pcp.decodeMapResponse(mapResponse(context, {
        resultCode = 8,
        lifetime = 30,
        externalPort = context.suggestedExternalPort,
        externalAddress = mapped(0, 0, 0, 0),
    }), context)
    local unknownError = Pcp.decodeMapResponse(mapResponse(context, {
        resultCode = 200,
        lifetime = 1800,
        externalPort = context.suggestedExternalPort,
        externalAddress = mapped(0, 0, 0, 0),
    }), context)
    check("pcp_map_decoder_returns_known_and_future_result_codes_as_failures",
        knownError and not knownError.success and knownError.resultKnown
        and knownError.resultName == "NO_RESOURCES" and knownError.lifetime == 30
        and knownError.externalPort == nil and knownError.externalAddress == nil
        and unknownError and not unknownError.success and not unknownError.resultKnown
        and unknownError.resultName == "UNKNOWN" and unknownError.resultCode == 200
        and unknownError.externalPort == nil and unknownError.externalAddress == nil)

    local deletePacket, deleteContext = Pcp.encodeMapRequest({
        clientAddress = "192.168.1.134",
        nonce = string.rep("d", 12),
        protocol = Pcp.PROTOCOL_UDP,
        internalPort = 22122,
        suggestedExternalPort = 0,
        suggestedExternalAddress = "0.0.0.0",
        lifetime = 0,
    })
    local deletion = Pcp.decodeMapResponse(mapResponse(deleteContext, {
        lifetime = 0,
        externalPort = 0,
        externalAddress = mapped(0, 0, 0, 0),
    }), deleteContext)
    local invalidCreations = {
        mapResponse(context, { lifetime = 0 }),
        mapResponse(context, { externalPort = 0 }),
        mapResponse(context, { externalAddress = mapped(0, 0, 0, 0) }),
    }
    local invalidCreationRejected = true
    for _, value in ipairs(invalidCreations) do
        invalidCreationRejected = invalidCreationRejected
            and rejected(Pcp.decodeMapResponse, value, context)
    end
    check("pcp_map_success_requires_live_mapping_and_deletion_requires_exact_zero_endpoint",
        #deletePacket == 60 and deletion and deletion.success
        and deletion.wireLifetime == 0 and deletion.externalPort == 0
        and deletion.externalAddress == "0.0.0.0"
        and invalidCreationRejected
        and rejected(Pcp.decodeMapResponse, mapResponse(deleteContext, {
            lifetime = 1,
            externalPort = 0,
            externalAddress = mapped(0, 0, 0, 0),
        }), deleteContext)
        and rejected(Pcp.decodeMapResponse, mapResponse(deleteContext, {
            lifetime = 0,
            externalPort = 1,
            externalAddress = mapped(0, 0, 0, 0),
        }), deleteContext)
        and rejected(Pcp.decodeMapResponse, mapResponse(deleteContext, {
            lifetime = 0,
            externalPort = 0,
            externalAddress = mapped(1, 1, 1, 1),
        }), deleteContext))

    local unknownMandatoryOption = string.char(42, 9) .. u16(0)
    local unknownOptionalOption = string.char(200, 9) .. u16(0)
    local optionResponse = Pcp.decodeMapResponse(mapResponse(context, {
        options = unknownMandatoryOption .. unknownOptionalOption,
    }), context)
    check("pcp_client_ignores_well_formed_unknown_response_options_as_required",
        optionResponse and #optionResponse.options == 2
        and not optionResponse.options[1].optional
        and optionResponse.options[2].optional)

    local firstEpoch = Pcp.checkEpoch(nil, 1000, 500)
    local steadyEpoch = Pcp.checkEpoch(firstEpoch.state, 1010, 510)
    local reorderedEpoch = Pcp.checkEpoch(steadyEpoch.state, 1009, 510)
    local reversedEpoch = Pcp.checkEpoch(steadyEpoch.state, 5, 511)
    local stalledEpoch = Pcp.checkEpoch(steadyEpoch.state, 1010, 610)
    local badClock, badClockError = Pcp.checkEpoch(steadyEpoch.state, 1011, 509)
    check("pcp_epoch_validation_detects_state_loss_with_rfc6887_tolerances",
        firstEpoch.valid and steadyEpoch.valid and reorderedEpoch.valid
        and reversedEpoch.resetSuspected and reversedEpoch.reason == "server_time_reversed"
        and stalledEpoch.resetSuspected and stalledEpoch.reason == "clock_delta_anomaly"
        and badClock == nil and badClockError:find("backwards", 1, true))

    local validSource = Pcp.validateResponseSource("192.168.1.1", 5351, "192.168.1.1")
    local badAddress = Pcp.validateResponseSource("192.168.1.2", 5351, "192.168.1.1")
    local badPort = Pcp.validateResponseSource("192.168.1.1", 5350, "192.168.1.1")
    local badText = Pcp.validateResponseSource("192.168.001.1", 5351, "192.168.1.1")
    check("pcp_response_source_must_match_the_queried_server_and_port",
        validSource == true and badAddress == false and badPort == false and badText == false)
end

return Test
