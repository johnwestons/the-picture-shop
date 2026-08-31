local Address = require("src.net.address")

local DirectInvite = {
    VERSION = "TPS1",
    KEY_BYTES = 32,
}

DirectInvite.KEY_HEX_LENGTH = DirectInvite.KEY_BYTES * 2
DirectInvite.MAX_CODE_LENGTH = #DirectInvite.VERSION + 1
    + Address.MAX_INPUT_LENGTH + 1 + DirectInvite.KEY_HEX_LENGTH

local MAX_OUTER_WHITESPACE_BYTES = 32
local REDACTED_KEY = "<redacted>"
local INVALID_ENDPOINT = "<invalid-endpoint>"

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function bytesToHex(value)
    local encoded = {}
    for index = 1, #value do
        encoded[index] = string.format("%02x", value:byte(index))
    end
    return table.concat(encoded)
end

local function hexToBytes(value)
    local decoded = {}
    for index = 1, #value, 2 do
        decoded[#decoded + 1] = string.char(tonumber(value:sub(index, index + 1), 16))
    end
    return table.concat(decoded)
end

local function canonicalAddress(endpoint)
    if type(endpoint) ~= "string" then return nil end
    local parsed = Address.parse(endpoint)
    if not parsed then return nil end
    return parsed
end

function DirectInvite.generateKey(randomBytes)
    if type(randomBytes) ~= "function" then
        return nil, "A secure random byte provider is required."
    end

    -- The caller must inject an operating-system CSPRNG. Deliberately do not
    -- fall back to math.random or another predictable source.
    local succeeded, psk = pcall(randomBytes, DirectInvite.KEY_BYTES)
    if not succeeded or type(psk) ~= "string" or #psk ~= DirectInvite.KEY_BYTES then
        return nil, "The secure random byte provider did not return exactly 32 bytes."
    end
    return psk
end

function DirectInvite.encode(endpoint, psk)
    local address = canonicalAddress(endpoint)
    if not address then return nil, "Invitation endpoint is invalid." end
    if type(psk) ~= "string" or #psk ~= DirectInvite.KEY_BYTES then
        return nil, "Invitation key must contain exactly 32 bytes."
    end

    return DirectInvite.VERSION .. "|" .. address.endpoint .. "|" .. bytesToHex(psk)
end

function DirectInvite.create(endpoint, randomBytes)
    local address = canonicalAddress(endpoint)
    if not address then return nil, "Invitation endpoint is invalid." end

    -- Validate the endpoint before consuming entropy, then let reachability
    -- callers use generateKey/encode separately: listener first, mapping
    -- second, and only then the final public invitation.
    local psk, keyError = DirectInvite.generateKey(randomBytes)
    if not psk then return nil, keyError end
    return DirectInvite.encode(address.endpoint, psk)
end

function DirectInvite.parse(code)
    if type(code) ~= "string" then return nil, "Invitation code must be text." end
    if #code > DirectInvite.MAX_CODE_LENGTH + MAX_OUTER_WHITESPACE_BYTES then
        return nil, "Invitation code is too long."
    end

    code = trim(code)
    if code == "" then return nil, "Invitation code is required." end
    if #code > DirectInvite.MAX_CODE_LENGTH then
        return nil, "Invitation code is too long."
    end
    if code:find("[%z\1-\31\127]") then
        return nil, "Invitation code contains control characters."
    end

    local version, endpoint, keyHex = code:match("^([^|]+)|([^|]+)|([^|]+)$")
    if not version then return nil, "Invitation code format is invalid." end
    if version ~= DirectInvite.VERSION then
        return nil, "Invitation code version is unsupported."
    end

    local address = canonicalAddress(endpoint)
    -- Parsing may normalize user-entered addresses. Invitations may not: one
    -- canonical spelling prevents ambiguous codes and signature confusion.
    if not address or address.endpoint ~= endpoint then
        return nil, "Invitation endpoint is invalid."
    end
    if #keyHex ~= DirectInvite.KEY_HEX_LENGTH or not keyHex:match("^[0-9a-f]+$") then
        return nil, "Invitation key is invalid."
    end

    return {
        version = DirectInvite.VERSION,
        endpoint = address.endpoint,
        host = address.host,
        port = address.port,
        isIPv4 = address.isIPv4,
        isLoopback = address.isLoopback,
        isPrivate = address.isPrivate,
        psk = hexToBytes(keyHex),
    }
end

function DirectInvite.redact(value)
    local endpoint
    if type(value) == "string" then
        local parsed = DirectInvite.parse(value)
        endpoint = parsed and parsed.endpoint or nil
    elseif type(value) == "table" and type(value.endpoint) == "string" then
        local address = canonicalAddress(value.endpoint)
        if address and address.endpoint == value.endpoint then endpoint = address.endpoint end
    end

    return DirectInvite.VERSION .. "|" .. (endpoint or INVALID_ENDPOINT)
        .. "|" .. REDACTED_KEY
end

return DirectInvite
