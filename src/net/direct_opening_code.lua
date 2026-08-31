local Ipv6Address = require("src.net.ipv6_address")

local DirectOpeningCode = {
    VERSION = 2,
    ADDRESS_FAMILY = 6,
    HOST_PREFIX = "TPS2H.",
    RESPONSE_PREFIX = "TPS2R.",
    HOST_BYTES = 76,
    RESPONSE_BYTES = 92,
    RESPONSE_PREFIX_BYTES = 60,
    INVITATION_ID_BYTES = 16,
    MASTER_KEY_BYTES = 32,
    GUEST_NONCE_BYTES = 16,
    RESPONSE_TAG_BYTES = 32,
    DEFAULT_LIFETIME = 10 * 60,
    MAX_LIFETIME = 15 * 60,
    DEFAULT_CLOCK_SKEW = 5 * 60,
    MAX_CLOCK_SKEW = 15 * 60,
}

local HOST_HEADER = string.char(0x02, 0x01, 0x06, 0x00)
local RESPONSE_HEADER = string.char(0x02, 0x02, 0x06, 0x00)
local RESPONSE_DOMAIN = "TPS2-RESPONSE-v1"
local MAX_OUTER_WHITESPACE_BYTES = 32
local BASE64URL_ALPHABET =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

local BASE64URL_VALUES = {}
for index = 1, #BASE64URL_ALPHABET do
    BASE64URL_VALUES[BASE64URL_ALPHABET:sub(index, index)] = index - 1
end

local function isIntegerInRange(value, minimum, maximum)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value == math.floor(value)
        and value >= minimum
        and value <= maximum
end

local function fixedBytes(value, length)
    return type(value) == "string" and #value == length
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function putU16(value)
    return string.char(math.floor(value / 256) % 256, value % 256)
end

local function putU32(value)
    return string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256)
end

local function getU16(bytes, offset)
    local first, second = bytes:byte(offset, offset + 1)
    return first * 256 + second
end

local function getU32(bytes, offset)
    local first, second, third, fourth = bytes:byte(offset, offset + 3)
    return first * 16777216 + second * 65536 + third * 256 + fourth
end

local function encodeBase64Url(bytes)
    local encoded = {}
    local outputIndex = 1

    for offset = 1, #bytes, 3 do
        local first = bytes:byte(offset)
        local second = bytes:byte(offset + 1)
        local third = bytes:byte(offset + 2)
        local value = first * 65536 + (second or 0) * 256 + (third or 0)

        encoded[outputIndex] = BASE64URL_ALPHABET:sub(
            math.floor(value / 262144) % 64 + 1,
            math.floor(value / 262144) % 64 + 1)
        encoded[outputIndex + 1] = BASE64URL_ALPHABET:sub(
            math.floor(value / 4096) % 64 + 1,
            math.floor(value / 4096) % 64 + 1)
        outputIndex = outputIndex + 2

        if second then
            encoded[outputIndex] = BASE64URL_ALPHABET:sub(
                math.floor(value / 64) % 64 + 1,
                math.floor(value / 64) % 64 + 1)
            outputIndex = outputIndex + 1
        end
        if third then
            encoded[outputIndex] = BASE64URL_ALPHABET:sub(
                value % 64 + 1, value % 64 + 1)
            outputIndex = outputIndex + 1
        end
    end

    return table.concat(encoded)
end

local function decodeBase64Url(encoded)
    if type(encoded) ~= "string" or encoded == "" then return nil end
    if encoded:find("[^A-Za-z0-9_%-]") or #encoded % 4 == 1 then return nil end

    local decoded = {}
    local outputIndex = 1
    for offset = 1, #encoded, 4 do
        local remaining = math.min(4, #encoded - offset + 1)
        if remaining == 1 then return nil end

        local first = BASE64URL_VALUES[encoded:sub(offset, offset)]
        local second = BASE64URL_VALUES[encoded:sub(offset + 1, offset + 1)]
        local third = remaining >= 3
            and BASE64URL_VALUES[encoded:sub(offset + 2, offset + 2)] or 0
        local fourth = remaining == 4
            and BASE64URL_VALUES[encoded:sub(offset + 3, offset + 3)] or 0
        if first == nil or second == nil or third == nil or fourth == nil then
            return nil
        end

        local value = first * 262144 + second * 4096 + third * 64 + fourth
        decoded[outputIndex] = string.char(math.floor(value / 65536) % 256)
        outputIndex = outputIndex + 1
        if remaining >= 3 then
            decoded[outputIndex] = string.char(math.floor(value / 256) % 256)
            outputIndex = outputIndex + 1
        end
        if remaining == 4 then
            decoded[outputIndex] = string.char(value % 256)
            outputIndex = outputIndex + 1
        end
    end

    local bytes = table.concat(decoded)
    -- This also rejects alternate encodings whose unused low bits are set.
    if encodeBase64Url(bytes) ~= encoded then return nil end
    return bytes
end

local function publicAddress(value)
    local parsed
    if type(value) == "string" then
        parsed = Ipv6Address.parse(value)
    elseif type(value) == "table" and type(value.bytes) == "string" then
        parsed = Ipv6Address.fromBytes(value.bytes)
    end
    if not parsed or parsed.isGlobal ~= true or not fixedBytes(parsed.bytes, 16) then
        return nil
    end
    return parsed
end

local function hostAddress(fields)
    if type(fields) ~= "table" then return nil end
    return publicAddress(fields.address or fields.hostAddress)
end

local function responseAddress(fields)
    if type(fields) ~= "table" then return nil end
    return publicAddress(fields.address or fields.guestAddress)
end

local function hostPort(fields)
    if type(fields) ~= "table" then return nil end
    return fields.port or fields.hostPort
end

local function responsePort(fields)
    if type(fields) ~= "table" then return nil end
    return fields.port or fields.guestPort
end

local function aliasesAgree(fields, primary, alias)
    return fields[primary] == nil or fields[alias] == nil
        or fields[primary] == fields[alias]
end

local function serializeHost(fields)
    if type(fields) ~= "table"
        or not aliasesAgree(fields, "port", "hostPort")
        or not aliasesAgree(fields, "address", "hostAddress") then
        return nil, "Host opening fields are invalid."
    end

    local lifetime = fields.lifetime
    if lifetime == nil then lifetime = DirectOpeningCode.DEFAULT_LIFETIME end
    local port = hostPort(fields)
    local address = hostAddress(fields)
    if not isIntegerInRange(fields.issuedAt, 0, 0xffffffff)
        or not isIntegerInRange(lifetime, 1, DirectOpeningCode.MAX_LIFETIME)
        or not isIntegerInRange(port, 1, 0xffff)
        or not address
        or not fixedBytes(fields.invitationId, DirectOpeningCode.INVITATION_ID_BYTES)
        or not fixedBytes(fields.masterKey, DirectOpeningCode.MASTER_KEY_BYTES) then
        return nil, "Host opening fields are invalid."
    end

    return HOST_HEADER
        .. putU32(fields.issuedAt)
        .. putU16(lifetime)
        .. putU16(port)
        .. address.bytes
        .. fields.invitationId
        .. fields.masterKey
end

local function serializeResponsePrefix(fields)
    if type(fields) ~= "table"
        or not aliasesAgree(fields, "port", "guestPort")
        or not aliasesAgree(fields, "address", "guestAddress") then
        return nil, "Response opening fields are invalid."
    end

    local port = responsePort(fields)
    local address = responseAddress(fields)
    if not isIntegerInRange(fields.issuedAt, 0, 0xffffffff)
        or not isIntegerInRange(fields.lifetime, 1, DirectOpeningCode.MAX_LIFETIME)
        or not isIntegerInRange(port, 1, 0xffff)
        or not address
        or not fixedBytes(fields.invitationId, DirectOpeningCode.INVITATION_ID_BYTES)
        or not fixedBytes(fields.guestNonce, DirectOpeningCode.GUEST_NONCE_BYTES) then
        return nil, "Response opening fields are invalid."
    end

    return RESPONSE_HEADER
        .. putU32(fields.issuedAt)
        .. putU16(fields.lifetime)
        .. putU16(port)
        .. address.bytes
        .. fields.invitationId
        .. fields.guestNonce
end

local function parseHostBytes(bytes)
    if not fixedBytes(bytes, DirectOpeningCode.HOST_BYTES)
        or bytes:sub(1, 4) ~= HOST_HEADER then
        return nil, "Host opening code is invalid."
    end

    local lifetime = getU16(bytes, 9)
    local port = getU16(bytes, 11)
    local address = Ipv6Address.fromBytes(bytes:sub(13, 28))
    if lifetime < 1 or lifetime > DirectOpeningCode.MAX_LIFETIME
        or port < 1
        or not address or address.isGlobal ~= true then
        return nil, "Host opening code is invalid."
    end

    return {
        kind = "host",
        version = DirectOpeningCode.VERSION,
        issuedAt = getU32(bytes, 5),
        lifetime = lifetime,
        port = port,
        hostPort = port,
        address = address.address,
        hostAddress = address.address,
        addressBytes = address.bytes,
        invitationId = bytes:sub(29, 44),
        masterKey = bytes:sub(45, 76),
        bytes = bytes,
    }
end

local function parseResponseBytes(bytes)
    if not fixedBytes(bytes, DirectOpeningCode.RESPONSE_BYTES)
        or bytes:sub(1, 4) ~= RESPONSE_HEADER then
        return nil, "Response opening code is invalid."
    end

    local lifetime = getU16(bytes, 9)
    local port = getU16(bytes, 11)
    local address = Ipv6Address.fromBytes(bytes:sub(13, 28))
    if lifetime < 1 or lifetime > DirectOpeningCode.MAX_LIFETIME
        or port < 1
        or not address or address.isGlobal ~= true then
        return nil, "Response opening code is invalid."
    end

    return {
        kind = "response",
        version = DirectOpeningCode.VERSION,
        issuedAt = getU32(bytes, 5),
        lifetime = lifetime,
        port = port,
        guestPort = port,
        address = address.address,
        guestAddress = address.address,
        addressBytes = address.bytes,
        invitationId = bytes:sub(29, 44),
        guestNonce = bytes:sub(45, 60),
        responseTag = bytes:sub(61, 92),
        bytes = bytes,
    }
end

local function decodeCode(code, prefix, byteLength, invalidMessage)
    if type(code) ~= "string" then return nil, invalidMessage end
    local encodedLength = math.floor((byteLength * 8 + 5) / 6)
    local exactLength = #prefix + encodedLength
    if #code > exactLength + MAX_OUTER_WHITESPACE_BYTES then
        return nil, invalidMessage
    end

    code = trim(code)
    if #code ~= exactLength or code:sub(1, #prefix) ~= prefix then
        return nil, invalidMessage
    end
    local encoded = code:sub(#prefix + 1)
    local bytes = decodeBase64Url(encoded)
    if not bytes or #bytes ~= byteLength then return nil, invalidMessage end
    return bytes
end

local function timeValidation(nowOrOptions, maybeOptions)
    local options
    local now
    if type(nowOrOptions) == "table" then
        if maybeOptions ~= nil then return nil end
        options = nowOrOptions
        now = options.now
    elseif type(nowOrOptions) == "number" or nowOrOptions == nil then
        now = nowOrOptions
        options = maybeOptions or {}
        if type(options) ~= "table" then return nil end
    else
        return nil
    end

    if now == nil then
        local succeeded, current = pcall(os.time)
        if not succeeded then return nil end
        now = current
    end

    local clockSkew = options.clockSkew
    if clockSkew == nil then clockSkew = DirectOpeningCode.DEFAULT_CLOCK_SKEW end
    local futureSkew = options.futureSkew
    if futureSkew == nil then futureSkew = clockSkew end
    local expiryGrace = options.expiryGrace
    if expiryGrace == nil then expiryGrace = clockSkew end

    if not isIntegerInRange(now, 0, 0xffffffff)
        or not isIntegerInRange(clockSkew, 0, DirectOpeningCode.MAX_CLOCK_SKEW)
        or not isIntegerInRange(futureSkew, 0, DirectOpeningCode.MAX_CLOCK_SKEW)
        or not isIntegerInRange(expiryGrace, 0, DirectOpeningCode.MAX_CLOCK_SKEW) then
        return nil
    end

    return {
        now = now,
        futureSkew = futureSkew,
        expiryGrace = expiryGrace,
    }
end

function DirectOpeningCode.encodeHost(fields)
    local bytes, errorMessage = serializeHost(fields)
    if not bytes then return nil, errorMessage end
    return DirectOpeningCode.HOST_PREFIX .. encodeBase64Url(bytes)
end

function DirectOpeningCode.parseHost(code, nowOrOptions, maybeOptions)
    local bytes, decodeError = decodeCode(
        code,
        DirectOpeningCode.HOST_PREFIX,
        DirectOpeningCode.HOST_BYTES,
        "Host opening code is invalid.")
    if not bytes then return nil, decodeError end

    local parsed, parseError = parseHostBytes(bytes)
    if not parsed then return nil, parseError end
    local validation = timeValidation(nowOrOptions, maybeOptions)
    if not validation then
        return nil, "Host opening code validation options are invalid."
    end
    if parsed.issuedAt > validation.now + validation.futureSkew then
        return nil, "Host opening code is not yet valid."
    end
    if validation.now > parsed.issuedAt + parsed.lifetime + validation.expiryGrace then
        return nil, "Host opening code has expired."
    end
    return parsed
end

function DirectOpeningCode.encodeResponse(fields)
    local prefix, errorMessage = serializeResponsePrefix(fields)
    if not prefix then return nil, errorMessage end
    if not fixedBytes(fields.responseTag, DirectOpeningCode.RESPONSE_TAG_BYTES) then
        return nil, "Response opening fields are invalid."
    end
    local bytes = prefix .. fields.responseTag
    return DirectOpeningCode.RESPONSE_PREFIX .. encodeBase64Url(bytes)
end

function DirectOpeningCode.parseResponse(code)
    local bytes, decodeError = decodeCode(
        code,
        DirectOpeningCode.RESPONSE_PREFIX,
        DirectOpeningCode.RESPONSE_BYTES,
        "Response opening code is invalid.")
    if not bytes then return nil, decodeError end
    return parseResponseBytes(bytes)
end

local function normalizedHost(value)
    if type(value) == "string" then
        local bytes
        if #value == DirectOpeningCode.HOST_BYTES then
            bytes = value
        else
            bytes = decodeCode(
                value,
                DirectOpeningCode.HOST_PREFIX,
                DirectOpeningCode.HOST_BYTES,
                "Host opening code is invalid.")
        end
        if not bytes then return nil, "Host opening code is invalid." end
        return parseHostBytes(bytes)
    elseif type(value) == "table" then
        if fixedBytes(value.bytes, DirectOpeningCode.HOST_BYTES) then
            return parseHostBytes(value.bytes)
        end
        local bytes = serializeHost(value)
        if not bytes then return nil, "Host opening code is invalid." end
        return parseHostBytes(bytes)
    end
    return nil, "Host opening code is invalid."
end

local function normalizedResponse(value)
    if type(value) == "string" then
        local bytes
        if #value == DirectOpeningCode.RESPONSE_BYTES then
            bytes = value
        else
            bytes = decodeCode(
                value,
                DirectOpeningCode.RESPONSE_PREFIX,
                DirectOpeningCode.RESPONSE_BYTES,
                "Response opening code is invalid.")
        end
        if not bytes then return nil, "Response opening code is invalid." end
        return parseResponseBytes(bytes)
    elseif type(value) == "table" then
        if fixedBytes(value.bytes, DirectOpeningCode.RESPONSE_BYTES) then
            return parseResponseBytes(value.bytes)
        end
        local prefix = serializeResponsePrefix(value)
        if not prefix or not fixedBytes(
            value.responseTag, DirectOpeningCode.RESPONSE_TAG_BYTES) then
            return nil, "Response opening code is invalid."
        end
        return parseResponseBytes(prefix .. value.responseTag)
    end
    return nil, "Response opening code is invalid."
end

local function normalizedResponsePrefix(value)
    if type(value) == "string" then
        if #value == DirectOpeningCode.RESPONSE_PREFIX_BYTES then
            local placeholder = value .. string.rep("\0", DirectOpeningCode.RESPONSE_TAG_BYTES)
            local parsed = parseResponseBytes(placeholder)
            return parsed and value or nil
        end
        local parsed = normalizedResponse(value)
        return parsed and parsed.bytes:sub(1, DirectOpeningCode.RESPONSE_PREFIX_BYTES) or nil
    elseif type(value) == "table" then
        if fixedBytes(value.bytes, DirectOpeningCode.RESPONSE_BYTES) then
            local parsed = parseResponseBytes(value.bytes)
            return parsed and parsed.bytes:sub(1, DirectOpeningCode.RESPONSE_PREFIX_BYTES) or nil
        end
        return serializeResponsePrefix(value)
    end
    return nil
end

function DirectOpeningCode.responseTranscript(host, responseWithoutTag)
    local parsedHost = normalizedHost(host)
    local responsePrefix = normalizedResponsePrefix(responseWithoutTag)
    if not parsedHost or not responsePrefix then
        return nil, "Opening-code response transcript inputs are invalid."
    end
    return RESPONSE_DOMAIN
        .. parsedHost.bytes:sub(1, 44)
        .. responsePrefix:sub(1, DirectOpeningCode.RESPONSE_PREFIX_BYTES)
end

function DirectOpeningCode.matchResponse(host, response)
    -- Echo matching is only a structural preflight. It does not authenticate
    -- the response; production callers must use verifyResponse instead.
    local parsedHost = normalizedHost(host)
    local parsedResponse = normalizedResponse(response)
    if not parsedHost or not parsedResponse then
        return nil, "Opening-code response is invalid."
    end
    if parsedResponse.issuedAt ~= parsedHost.issuedAt
        or parsedResponse.lifetime ~= parsedHost.lifetime
        or parsedResponse.invitationId ~= parsedHost.invitationId then
        return nil, "Opening-code response does not match."
    end
    return parsedResponse
end

function DirectOpeningCode.verifyResponse(host, response, verifyTag)
    if type(verifyTag) ~= "function" then
        return nil, "A response tag verifier is required."
    end

    local parsedHost = normalizedHost(host)
    local parsedResponse = normalizedResponse(response)
    if not parsedHost or not parsedResponse then
        return nil, "Opening-code response is invalid."
    end
    if parsedResponse.issuedAt ~= parsedHost.issuedAt
        or parsedResponse.lifetime ~= parsedHost.lifetime
        or parsedResponse.invitationId ~= parsedHost.invitationId then
        return nil, "Opening-code response does not match."
    end

    local transcript = RESPONSE_DOMAIN
        .. parsedHost.bytes:sub(1, 44)
        .. parsedResponse.bytes:sub(1, DirectOpeningCode.RESPONSE_PREFIX_BYTES)
    local succeeded, verified = pcall(
        verifyTag, parsedHost.masterKey, transcript, parsedResponse.responseTag)
    if not succeeded or verified ~= true then
        return nil, "Opening-code response authentication failed."
    end
    return parsedResponse
end

function DirectOpeningCode.redact(value)
    if type(value) == "table" then
        if value.kind == "host" or value.masterKey ~= nil then
            return DirectOpeningCode.HOST_PREFIX .. "<redacted>"
        elseif value.kind == "response" or value.responseTag ~= nil then
            return DirectOpeningCode.RESPONSE_PREFIX .. "<redacted>"
        end
    elseif type(value) == "string" then
        local candidate = trim(value)
        if candidate:sub(1, #DirectOpeningCode.HOST_PREFIX)
            == DirectOpeningCode.HOST_PREFIX then
            return DirectOpeningCode.HOST_PREFIX .. "<redacted>"
        elseif candidate:sub(1, #DirectOpeningCode.RESPONSE_PREFIX)
            == DirectOpeningCode.RESPONSE_PREFIX then
            return DirectOpeningCode.RESPONSE_PREFIX .. "<redacted>"
        end
    end
    return "TPS2.<redacted>"
end

return DirectOpeningCode
