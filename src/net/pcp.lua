local IpScope = require("src.net.ip_scope")

local Pcp = {
    VERSION = 2,
    SERVER_PORT = 5351,
    CLIENT_ANNOUNCE_PORT = 5350,
    MAX_PACKET_BYTES = 1100,
    DEFAULT_MAX_LIFETIME = 24 * 60 * 60,
    OPCODE_ANNOUNCE = 0,
    OPCODE_MAP = 1,
    PROTOCOL_UDP = 17,
    NONCE_BYTES = 12,
}

local UINT16_MAX = 65535
local UINT32_MAX = 4294967295
local IPV4_MAPPED_PREFIX = string.rep("\0", 10) .. "\255\255"

Pcp.RESULT_CODES = {
    [0] = "SUCCESS",
    [1] = "UNSUPP_VERSION",
    [2] = "NOT_AUTHORIZED",
    [3] = "MALFORMED_REQUEST",
    [4] = "UNSUPP_OPCODE",
    [5] = "UNSUPP_OPTION",
    [6] = "MALFORMED_OPTION",
    [7] = "NETWORK_FAILURE",
    [8] = "NO_RESOURCES",
    [9] = "UNSUPP_PROTOCOL",
    [10] = "USER_EX_QUOTA",
    [11] = "CANNOT_PROVIDE_EXTERNAL",
    [12] = "ADDRESS_MISMATCH",
    [13] = "EXCESSIVE_REMOTE_PEERS",
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

local function encodeMappedIpv4(address)
    local parsed = IpScope.parse(address)
    if not parsed then return nil, "PCP address must be canonical IPv4 text" end
    return IPV4_MAPPED_PREFIX .. string.char(
        parsed.octets[1], parsed.octets[2], parsed.octets[3], parsed.octets[4])
end

local function decodeMappedIpv4(data, position)
    local encoded = data:sub(position, position + 15)
    if #encoded ~= 16 then return nil, "truncated PCP IPv4 address" end
    if encoded:sub(1, 12) ~= IPV4_MAPPED_PREFIX then
        return nil, "PCP response address is not IPv4-mapped"
    end
    local a, b, c, d = encoded:byte(13, 16)
    return table.concat({ a, b, c, d }, ".")
end

local function normalizeLifetimeLimit(value)
    value = value == nil and Pcp.DEFAULT_MAX_LIFETIME or value
    if not integerInRange(value, 1, UINT32_MAX) then
        return nil, "invalid PCP lifetime limit"
    end
    return value
end

local function boundedLifetime(wireLifetime, limit)
    return math.min(wireLifetime, limit), wireLifetime > limit
end

local function parseOptions(data, position)
    local options = {}
    while position <= #data do
        if #data - position + 1 < 4 then
            return nil, "truncated PCP option header"
        end
        local code = data:byte(position)
        local length = readU16(data, position + 2)
        local dataStart = position + 4
        local dataEnd = dataStart + length - 1
        if dataEnd > #data then return nil, "truncated PCP option data" end
        local paddingLength = (4 - (length % 4)) % 4
        local paddingEnd = dataEnd + paddingLength
        if paddingEnd > #data then return nil, "truncated PCP option padding" end
        if paddingLength > 0
            and data:sub(dataEnd + 1, paddingEnd) ~= string.rep("\0", paddingLength)
        then
            return nil, "non-zero PCP option padding"
        end
        options[#options + 1] = {
            code = code,
            optional = code >= 128,
            data = length == 0 and "" or data:sub(dataStart, dataEnd),
        }
        position = paddingEnd + 1
    end
    return options
end

local function parseCommonResponse(data, expectedOpcode, lifetimeLimit)
    if type(data) ~= "string" then return nil, "PCP response must be bytes" end
    if #data < 24 then return nil, "PCP response is shorter than 24 bytes" end
    if #data > Pcp.MAX_PACKET_BYTES then return nil, "PCP response exceeds 1100 bytes" end
    if #data % 4 ~= 0 then return nil, "PCP response length is not a multiple of four" end
    if data:byte(1) ~= Pcp.VERSION then return nil, "unsupported PCP response version" end

    local responseAndOpcode = data:byte(2)
    if responseAndOpcode < 128 then return nil, "PCP packet is not a response" end
    local opcode = responseAndOpcode - 128
    if opcode ~= expectedOpcode then return nil, "PCP response opcode does not match request" end

    local limit, limitError = normalizeLifetimeLimit(lifetimeLimit)
    if not limit then return nil, limitError end
    local resultCode = data:byte(4)
    local wireLifetime = readU32(data, 5)
    local lifetime, lifetimeCapped = boundedLifetime(wireLifetime, limit)
    return {
        version = Pcp.VERSION,
        opcode = opcode,
        resultCode = resultCode,
        resultName = Pcp.RESULT_CODES[resultCode] or "UNKNOWN",
        resultKnown = Pcp.RESULT_CODES[resultCode] ~= nil,
        success = resultCode == 0,
        wireLifetime = wireLifetime,
        lifetime = lifetime,
        lifetimeCapped = lifetimeCapped,
        epoch = readU32(data, 9),
    }
end

function Pcp.encodeAnnounceRequest(clientAddress)
    local mappedAddress, addressError = encodeMappedIpv4(clientAddress)
    if not mappedAddress then return nil, addressError end
    local packet = string.char(Pcp.VERSION, Pcp.OPCODE_ANNOUNCE, 0, 0)
        .. u32(0) .. mappedAddress
    return packet, {
        opcode = Pcp.OPCODE_ANNOUNCE,
        clientAddress = clientAddress,
    }
end

function Pcp.encodeMapRequest(request)
    if type(request) ~= "table" then return nil, "PCP MAP request must be a table" end
    local clientAddress, addressError = encodeMappedIpv4(request.clientAddress)
    if not clientAddress then return nil, addressError end
    local suggestedAddress, suggestedAddressError = encodeMappedIpv4(
        request.suggestedExternalAddress or "0.0.0.0")
    if not suggestedAddress then return nil, suggestedAddressError end
    if type(request.nonce) ~= "string" or #request.nonce ~= Pcp.NONCE_BYTES then
        return nil, "PCP mapping nonce must be exactly 12 bytes"
    end

    local protocol = request.protocol == nil and Pcp.PROTOCOL_UDP or request.protocol
    local internalPort = request.internalPort
    local suggestedExternalPort = request.suggestedExternalPort or 0
    local lifetime = request.lifetime
    -- This client intentionally exposes only an exact UDP-port mapping.
    -- Supporting protocol 0 or internal port 0 would make a caller bug able
    -- to request/delete a wildcard or DMZ-style mapping.
    if protocol ~= Pcp.PROTOCOL_UDP then
        return nil, "PCP Direct Play mappings require UDP"
    end
    if not integerInRange(internalPort, 1, UINT16_MAX) then
        return nil, "invalid PCP internal port"
    end
    if not integerInRange(suggestedExternalPort, 0, UINT16_MAX) then
        return nil, "invalid PCP suggested external port"
    end
    if not integerInRange(lifetime, 0, UINT32_MAX) then
        return nil, "invalid PCP requested lifetime"
    end
    if lifetime == 0 and (suggestedExternalPort ~= 0
        or (request.suggestedExternalAddress or "0.0.0.0") ~= "0.0.0.0")
    then
        return nil, "PCP deletion requires a zero suggested endpoint"
    end

    local packet = string.char(Pcp.VERSION, Pcp.OPCODE_MAP, 0, 0)
        .. u32(lifetime)
        .. clientAddress
        .. request.nonce
        .. string.char(protocol, 0, 0, 0)
        .. u16(internalPort)
        .. u16(suggestedExternalPort)
        .. suggestedAddress
    return packet, {
        opcode = Pcp.OPCODE_MAP,
        clientAddress = request.clientAddress,
        nonce = request.nonce,
        protocol = protocol,
        internalPort = internalPort,
        suggestedExternalPort = suggestedExternalPort,
        suggestedExternalAddress = request.suggestedExternalAddress or "0.0.0.0",
        requestedLifetime = lifetime,
    }
end

function Pcp.decodeAnnounceResponse(data, lifetimeLimit)
    local response, responseError = parseCommonResponse(
        data, Pcp.OPCODE_ANNOUNCE, lifetimeLimit)
    if not response then return nil, responseError end
    local options, optionsError = parseOptions(data, 25)
    if not options then return nil, optionsError end
    response.options = options
    response.lifetimeIgnored = true
    response.lifetime = 0
    response.lifetimeCapped = false
    return response
end

function Pcp.decodeMapResponse(data, expected, lifetimeLimit)
    if type(expected) ~= "table" then
        return nil, "expected PCP MAP request context is required"
    end
    if type(expected.nonce) ~= "string" or #expected.nonce ~= Pcp.NONCE_BYTES
        or expected.protocol ~= Pcp.PROTOCOL_UDP
        or not integerInRange(expected.internalPort, 1, UINT16_MAX)
        or not integerInRange(expected.requestedLifetime, 0, UINT32_MAX)
    then
        return nil, "invalid expected PCP MAP request context"
    end
    local response, responseError = parseCommonResponse(data, Pcp.OPCODE_MAP, lifetimeLimit)
    if not response then return nil, responseError end
    if #data < 60 then return nil, "PCP MAP response is shorter than 60 bytes" end

    local nonce = data:sub(25, 36)
    local protocol = data:byte(37)
    local internalPort = readU16(data, 41)
    if nonce ~= expected.nonce or protocol ~= expected.protocol
        or internalPort ~= expected.internalPort
    then
        return nil, "PCP MAP response does not match request"
    end

    local externalAddress, addressError = decodeMappedIpv4(data, 45)
    if not externalAddress then return nil, addressError end
    local options, optionsError = parseOptions(data, 61)
    if not options then return nil, optionsError end

    local externalPort = readU16(data, 43)
    if response.success and expected.requestedLifetime > 0
        and (response.wireLifetime == 0 or externalPort == 0
            or externalAddress == "0.0.0.0")
    then
        return nil, "successful PCP MAP response has no usable mapping"
    end
    if response.success and expected.requestedLifetime == 0
        and (response.wireLifetime ~= 0 or externalPort ~= 0
            or externalAddress ~= "0.0.0.0")
    then
        return nil, "successful PCP MAP deletion response is malformed"
    end

    response.nonce = nonce
    response.protocol = protocol
    response.internalPort = internalPort
    -- Error responses echo request fields.  Do not expose those echoes using
    -- the names a caller would use to advertise a successfully mapped endpoint.
    response.externalPort = response.success and externalPort or nil
    response.externalAddress = response.success and externalAddress or nil
    response.options = options
    return response
end

function Pcp.checkEpoch(previous, serverTime, clientTime)
    if not integerInRange(serverTime, 0, UINT32_MAX) then
        return nil, "invalid PCP server epoch"
    end
    if not finiteNonnegative(clientTime) then return nil, "invalid PCP client time" end

    local state = { serverTime = serverTime, clientTime = clientTime }
    if previous == nil then
        return { valid = true, resetSuspected = false, reason = "first_response", state = state }
    end
    if type(previous) ~= "table"
        or not integerInRange(previous.serverTime, 0, UINT32_MAX)
        or not finiteNonnegative(previous.clientTime)
    then
        return nil, "invalid previous PCP epoch state"
    end
    if clientTime < previous.clientTime then return nil, "PCP client clock went backwards" end

    local valid, reason = true, "within_tolerance"
    if previous.serverTime > serverTime + 1 then
        valid, reason = false, "server_time_reversed"
    else
        local clientDelta = math.floor(clientTime - previous.clientTime)
        -- A one-second reversal is explicitly tolerated for packet reordering.
        local serverDelta = math.max(0, serverTime - previous.serverTime)
        if clientDelta + 2 < serverDelta - math.floor(serverDelta / 16)
            or serverDelta + 2 < clientDelta - math.floor(clientDelta / 16)
        then
            valid, reason = false, "clock_delta_anomaly"
        end
    end
    return { valid = valid, resetSuspected = not valid, reason = reason, state = state }
end

function Pcp.validateResponseSource(sourceAddress, sourcePort, serverAddress)
    local source = IpScope.parse(sourceAddress)
    local expected = IpScope.parse(serverAddress)
    if not source or not expected then return false, "invalid PCP response source" end
    if sourcePort ~= Pcp.SERVER_PORT or source.address ~= expected.address then
        return false, "PCP response source does not match server"
    end
    return true
end

return Pcp
