local IpScope = require("src.net.ip_scope")

local NatPmp = {
    VERSION = 0,
    SERVER_PORT = 5351,
    CLIENT_ANNOUNCE_PORT = 5350,
    DEFAULT_MAX_LIFETIME = 24 * 60 * 60,
    OPCODE_EXTERNAL_ADDRESS = 0,
    OPCODE_MAP_UDP = 1,
}

local UINT16_MAX = 65535
local UINT32_MAX = 4294967295

NatPmp.RESULT_CODES = {
    [0] = "SUCCESS",
    [1] = "UNSUPPORTED_VERSION",
    [2] = "NOT_AUTHORIZED",
    [3] = "NETWORK_FAILURE",
    [4] = "OUT_OF_RESOURCES",
    [5] = "UNSUPPORTED_OPCODE",
}

local function integerInRange(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
        and value ~= math.huge and value ~= -math.huge
end

local function finiteNonnegative(value)
    return type(value) == "number" and value >= 0
        and value == value and value ~= math.huge
end

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

local function readU16(data, position)
    local high, low = data:byte(position, position + 1)
    return high * 256 + low
end

local function readU32(data, position)
    local a, b, c, d = data:byte(position, position + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end

local function decodeIpv4(data, position)
    local a, b, c, d = data:byte(position, position + 3)
    return table.concat({ a, b, c, d }, ".")
end

local function normalizeLifetimeLimit(value)
    value = value == nil and NatPmp.DEFAULT_MAX_LIFETIME or value
    if not integerInRange(value, 1, UINT32_MAX) then
        return nil, "invalid NAT-PMP lifetime limit"
    end
    return value
end

local function parseHeader(data, expectedOpcode, expectedLength, lifetimeLimit)
    if type(data) ~= "string" then return nil, "NAT-PMP response must be bytes" end
    if #data ~= expectedLength then return nil, "invalid NAT-PMP response length" end
    if data:byte(1) ~= NatPmp.VERSION then return nil, "unsupported NAT-PMP response version" end
    if data:byte(2) ~= 128 + expectedOpcode then
        return nil, "NAT-PMP response opcode does not match request"
    end
    local limit, limitError = normalizeLifetimeLimit(lifetimeLimit)
    if not limit then return nil, limitError end
    local resultCode = readU16(data, 3)
    return {
        version = NatPmp.VERSION,
        opcode = expectedOpcode,
        resultCode = resultCode,
        resultName = NatPmp.RESULT_CODES[resultCode] or "UNKNOWN",
        resultKnown = NatPmp.RESULT_CODES[resultCode] ~= nil,
        success = resultCode == 0,
        fatal = resultCode ~= 0,
        epoch = readU32(data, 5),
        lifetimeLimit = limit,
    }
end

function NatPmp.encodeExternalAddressRequest()
    return string.char(NatPmp.VERSION, NatPmp.OPCODE_EXTERNAL_ADDRESS), {
        opcode = NatPmp.OPCODE_EXTERNAL_ADDRESS,
    }
end

function NatPmp.decodeExternalAddressResponse(data)
    local response, responseError = parseHeader(
        data, NatPmp.OPCODE_EXTERNAL_ADDRESS, 12, NatPmp.DEFAULT_MAX_LIFETIME)
    if not response then return nil, responseError end
    if response.success then
        response.externalAddress = decodeIpv4(data, 9)
        if response.externalAddress == "0.0.0.0" then
            return nil, "successful NAT-PMP response has no external address"
        end
    else
        -- RFC 6886 declares this field undefined on errors and requires
        -- clients to ignore it, including values from non-conforming peers.
        response.externalAddress = nil
    end
    response.lifetimeLimit = nil
    return response
end

function NatPmp.encodeUdpMappingRequest(request)
    if type(request) ~= "table" then
        return nil, "NAT-PMP UDP mapping request must be a table"
    end
    local internalPort = request.internalPort
    local suggestedExternalPort = request.suggestedExternalPort or 0
    local lifetime = request.lifetime
    -- NAT-PMP uses internal port zero with lifetime zero as a broad delete.
    -- Direct Play owns one UDP port, so never permit that wider operation.
    if not integerInRange(internalPort, 1, UINT16_MAX) then
        return nil, "invalid NAT-PMP internal port"
    end
    if not integerInRange(suggestedExternalPort, 0, UINT16_MAX) then
        return nil, "invalid NAT-PMP suggested external port"
    end
    if not integerInRange(lifetime, 0, UINT32_MAX) then
        return nil, "invalid NAT-PMP requested lifetime"
    end
    if lifetime == 0 and suggestedExternalPort ~= 0 then
        return nil, "NAT-PMP deletion requires suggested external port zero"
    end

    local packet = string.char(NatPmp.VERSION, NatPmp.OPCODE_MAP_UDP, 0, 0)
        .. u16(internalPort)
        .. u16(suggestedExternalPort)
        .. u32(lifetime)
    return packet, {
        opcode = NatPmp.OPCODE_MAP_UDP,
        internalPort = internalPort,
        suggestedExternalPort = suggestedExternalPort,
        requestedLifetime = lifetime,
    }
end

function NatPmp.decodeUdpMappingResponse(data, expected, lifetimeLimit)
    if type(expected) ~= "table"
        or not integerInRange(expected.internalPort, 1, UINT16_MAX)
        or not integerInRange(expected.requestedLifetime, 0, UINT32_MAX)
    then
        return nil, "valid expected NAT-PMP UDP request context is required"
    end
    local response, responseError = parseHeader(
        data, NatPmp.OPCODE_MAP_UDP, 16, lifetimeLimit)
    if not response then return nil, responseError end

    local internalPort = readU16(data, 9)
    local externalPort = readU16(data, 11)
    local wireLifetime = readU32(data, 13)
    if internalPort ~= expected.internalPort then
        return nil, "NAT-PMP UDP response does not match request"
    end
    if response.success and expected.requestedLifetime > 0
        and (externalPort == 0 or wireLifetime == 0)
    then
        return nil, "successful NAT-PMP mapping response has no mapping"
    end
    if response.success and expected.requestedLifetime == 0
        and (externalPort ~= 0 or wireLifetime ~= 0)
    then
        return nil, "successful NAT-PMP deletion response is malformed"
    end
    response.internalPort = internalPort
    -- Failure fields are not a granted mapping.  Some gateways echo or leave
    -- them non-zero, so accept the result code but never expose those fields
    -- through the successful-mapping interface.
    response.externalPort = response.success and externalPort or nil
    response.wireLifetime = response.success and wireLifetime or nil
    response.lifetime = response.success
        and math.min(wireLifetime, response.lifetimeLimit) or nil
    response.lifetimeCapped = response.success
        and wireLifetime > response.lifetimeLimit or false
    response.lifetimeLimit = nil
    return response
end

function NatPmp.checkEpoch(previous, serverTime, clientTime)
    if not integerInRange(serverTime, 0, UINT32_MAX) then
        return nil, "invalid NAT-PMP server epoch"
    end
    if not finiteNonnegative(clientTime) then return nil, "invalid NAT-PMP client time" end

    local state = { serverTime = serverTime, clientTime = clientTime }
    if previous == nil then
        return { valid = true, resetSuspected = false, reason = "first_response", state = state }
    end
    if type(previous) ~= "table"
        or not integerInRange(previous.serverTime, 0, UINT32_MAX)
        or not finiteNonnegative(previous.clientTime)
    then
        return nil, "invalid previous NAT-PMP epoch state"
    end
    if clientTime < previous.clientTime then
        return nil, "NAT-PMP client clock went backwards"
    end

    local elapsed = math.floor(clientTime - previous.clientTime)
    local conservativeExpected = previous.serverTime + math.floor(elapsed * 7 / 8)
    local resetSuspected = serverTime + 2 < conservativeExpected
    return {
        valid = not resetSuspected,
        resetSuspected = resetSuspected,
        reason = resetSuspected and "server_time_below_expected" or "within_tolerance",
        expectedMinimum = math.max(0, conservativeExpected - 2),
        state = state,
    }
end

function NatPmp.validateResponseSource(sourceAddress, sourcePort, gatewayAddress)
    local source = IpScope.parse(sourceAddress)
    local expected = IpScope.parse(gatewayAddress)
    if not source or not expected then return false, "invalid NAT-PMP response source" end
    if sourcePort ~= NatPmp.SERVER_PORT or source.address ~= expected.address then
        return false, "NAT-PMP response source does not match gateway"
    end
    return true
end

return NatPmp
