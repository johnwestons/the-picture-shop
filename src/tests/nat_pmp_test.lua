local NatPmp = require("src.net.nat_pmp")

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

local function externalResponse(overrides)
    overrides = overrides or {}
    return string.char(overrides.version or 0, overrides.opcode or 128)
        .. u16(overrides.resultCode or 0)
        .. u32(overrides.epoch or 0)
        .. (overrides.address or string.char(8, 8, 4, 4))
end

local function udpResponse(overrides)
    overrides = overrides or {}
    return string.char(overrides.version or 0, overrides.opcode or 129)
        .. u16(overrides.resultCode or 0)
        .. u32(overrides.epoch or 0)
        .. u16(overrides.internalPort == nil and 22122 or overrides.internalPort)
        .. u16(overrides.externalPort == nil and 40000 or overrides.externalPort)
        .. u32(overrides.lifetime == nil and 7200 or overrides.lifetime)
end

local function rejected(decoder, value, expected)
    local parsed, errorMessage = decoder(value, expected)
    return parsed == nil and type(errorMessage) == "string" and errorMessage ~= ""
end

function Test.run(_, check)
    local addressRequest, addressContext = NatPmp.encodeExternalAddressRequest()
    check("nat_pmp_external_address_request_matches_rfc6886_wire_layout",
        hex(addressRequest) == "0000"
        and addressContext.opcode == NatPmp.OPCODE_EXTERNAL_ADDRESS)

    local addressResponse = NatPmp.decodeExternalAddressResponse(externalResponse({ epoch = 42 }))
    check("nat_pmp_external_address_response_decodes_address_result_and_epoch",
        addressResponse and addressResponse.success
        and addressResponse.resultName == "SUCCESS" and addressResponse.resultKnown
        and addressResponse.externalAddress == "8.8.4.4" and addressResponse.epoch == 42)

    local knownAddressError = NatPmp.decodeExternalAddressResponse(externalResponse({
        resultCode = 2,
        address = string.char(203, 0, 113, 9),
    }))
    local unknownAddressError = NatPmp.decodeExternalAddressResponse(externalResponse({
        resultCode = 500,
        address = string.char(1, 2, 3, 4),
    }))
    check("nat_pmp_external_address_errors_ignore_undefined_address_and_unknown_codes_are_fatal",
        knownAddressError and knownAddressError.fatal and not knownAddressError.success
        and knownAddressError.resultName == "NOT_AUTHORIZED"
        and knownAddressError.externalAddress == nil
        and unknownAddressError and unknownAddressError.fatal
        and not unknownAddressError.resultKnown and unknownAddressError.resultName == "UNKNOWN"
        and unknownAddressError.externalAddress == nil)

    local malformedAddresses = {
        "",
        externalResponse():sub(1, 11),
        externalResponse() .. "x",
        externalResponse({ version = 1 }),
        externalResponse({ opcode = 129 }),
        externalResponse({ address = "\0\0\0\0" }),
    }
    local malformedAddressRejected = rejected(NatPmp.decodeExternalAddressResponse, nil)
    for _, value in ipairs(malformedAddresses) do
        malformedAddressRejected = malformedAddressRejected
            and rejected(NatPmp.decodeExternalAddressResponse, value)
    end
    check("nat_pmp_external_address_decoder_rejects_malformed_packets",
        malformedAddressRejected)

    local udpRequest, udpContext = NatPmp.encodeUdpMappingRequest({
        internalPort = 22122,
        suggestedExternalPort = 22122,
        lifetime = 7200,
    })
    check("nat_pmp_udp_mapping_request_matches_rfc6886_wire_layout",
        #udpRequest == 12 and udpContext.requestedLifetime == 7200
        and hex(udpRequest) == "00010000566a566a00001c20")

    local deleteRequest, deleteContext = NatPmp.encodeUdpMappingRequest({
        internalPort = 22122,
        suggestedExternalPort = 0,
        lifetime = 0,
    })
    check("nat_pmp_udp_deletion_uses_zero_external_port_and_lifetime",
        hex(deleteRequest) == "00010000566a000000000000"
        and deleteContext.requestedLifetime == 0)

    local invalidRequests = {
        {},
        { internalPort = 0, lifetime = 1 },
        { internalPort = 0, lifetime = 0 },
        { internalPort = 65536, lifetime = 1 },
        { internalPort = 1, suggestedExternalPort = -1, lifetime = 1 },
        { internalPort = 1, suggestedExternalPort = 1, lifetime = 0 },
        { internalPort = 1, lifetime = 1 / 0 },
        { internalPort = 1, lifetime = 0 / 0 },
        { internalPort = 1, lifetime = 1.5 },
    }
    local nilEncoded, nilEncodeError = NatPmp.encodeUdpMappingRequest(nil)
    local invalidRequestsRejected = nilEncoded == nil and type(nilEncodeError) == "string"
    for _, value in ipairs(invalidRequests) do
        local encoded, errorMessage = NatPmp.encodeUdpMappingRequest(value)
        invalidRequestsRejected = invalidRequestsRejected
            and encoded == nil and type(errorMessage) == "string" and errorMessage ~= ""
    end
    check("nat_pmp_udp_encoder_rejects_invalid_nonfinite_and_unsafe_deletion_fields",
        invalidRequestsRejected)

    local decodedMapping = NatPmp.decodeUdpMappingResponse(udpResponse({
        epoch = 9001,
        lifetime = 4294967295,
    }), udpContext)
    check("nat_pmp_udp_response_matches_internal_port_and_caps_absurd_lifetime",
        decodedMapping and decodedMapping.success and decodedMapping.epoch == 9001
        and decodedMapping.internalPort == 22122 and decodedMapping.externalPort == 40000
        and decodedMapping.wireLifetime == 4294967295
        and decodedMapping.lifetime == NatPmp.DEFAULT_MAX_LIFETIME
        and decodedMapping.lifetimeCapped)

    local decodedDeletion = NatPmp.decodeUdpMappingResponse(udpResponse({
        internalPort = 22122,
        externalPort = 0,
        lifetime = 0,
    }), deleteContext)
    check("nat_pmp_udp_deletion_response_requires_zero_mapping",
        decodedDeletion and decodedDeletion.success
        and decodedDeletion.externalPort == 0 and decodedDeletion.lifetime == 0
        and rejected(NatPmp.decodeUdpMappingResponse, udpResponse({
            internalPort = 22122, externalPort = 1, lifetime = 0,
        }), deleteContext))

    local malformedMappings = {
        udpResponse():sub(1, 15),
        udpResponse() .. "x",
        udpResponse({ version = 1 }),
        udpResponse({ opcode = 130 }),
        udpResponse({ internalPort = 22123 }),
        udpResponse({ externalPort = 0 }),
        udpResponse({ lifetime = 0 }),
    }
    local malformedMappingsRejected = rejected(
        NatPmp.decodeUdpMappingResponse, udpResponse(), nil)
    for _, value in ipairs(malformedMappings) do
        malformedMappingsRejected = malformedMappingsRejected
            and rejected(NatPmp.decodeUdpMappingResponse, value, udpContext)
    end
    check("nat_pmp_udp_decoder_rejects_malformed_unmatched_or_empty_successes",
        malformedMappingsRejected)

    local knownMapError = NatPmp.decodeUdpMappingResponse(udpResponse({
        resultCode = 4,
        externalPort = 0,
        lifetime = 0,
    }), udpContext)
    local unknownMapError = NatPmp.decodeUdpMappingResponse(udpResponse({
        resultCode = 65000,
        externalPort = 0,
        lifetime = 0,
    }), udpContext)
    local echoedMapError = NatPmp.decodeUdpMappingResponse(udpResponse({
        resultCode = 4,
        externalPort = 40000,
        lifetime = 7200,
    }), udpContext)
    check("nat_pmp_udp_result_codes_are_fatal_and_failed_fields_never_become_mappings",
        knownMapError and knownMapError.fatal and knownMapError.resultKnown
        and knownMapError.resultName == "OUT_OF_RESOURCES"
        and unknownMapError and unknownMapError.fatal and not unknownMapError.resultKnown
        and unknownMapError.resultName == "UNKNOWN"
        and echoedMapError and echoedMapError.fatal
        and echoedMapError.externalPort == nil
        and echoedMapError.wireLifetime == nil and echoedMapError.lifetime == nil)

    local firstEpoch = NatPmp.checkEpoch(nil, 1000, 500)
    local steadyEpoch = NatPmp.checkEpoch(firstEpoch.state, 1009, 510)
    local toleranceEdge = NatPmp.checkEpoch(steadyEpoch.state, 1015, 520)
    local resetEpoch = NatPmp.checkEpoch(steadyEpoch.state, 5, 520)
    local badClock, badClockError = NatPmp.checkEpoch(steadyEpoch.state, 1010, 499)
    check("nat_pmp_epoch_validation_uses_rfc6886_seven_eighths_restart_rule",
        firstEpoch.valid and steadyEpoch.valid and toleranceEdge.valid
        and resetEpoch.resetSuspected
        and resetEpoch.reason == "server_time_below_expected"
        and badClock == nil and badClockError:find("backwards", 1, true))

    local validSource = NatPmp.validateResponseSource(
        "192.168.1.1", 5351, "192.168.1.1")
    local badAddress = NatPmp.validateResponseSource(
        "192.168.1.2", 5351, "192.168.1.1")
    local badPort = NatPmp.validateResponseSource(
        "192.168.1.1", 5350, "192.168.1.1")
    local badText = NatPmp.validateResponseSource(
        "192.168.001.1", 5351, "192.168.1.1")
    check("nat_pmp_response_source_must_match_the_queried_gateway_and_port",
        validSource == true and badAddress == false and badPort == false and badText == false)
end

return Test
