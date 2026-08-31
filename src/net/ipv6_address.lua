local Ipv6Address = {
    BYTE_LENGTH = 16,
    MAX_INPUT_LENGTH = 39,
}

-- This module deliberately accepts only the hexadecimal IPv6 notation used by
-- direct-player codes.  In particular, scoped addresses, endpoint notation,
-- and IPv4-embedded dotted notation must be handled by a different boundary.

local function prefixMatches(words, prefixWords, prefixLength)
    local completeWords = math.floor(prefixLength / 16)
    for index = 1, completeWords do
        if words[index] ~= prefixWords[index] then return false end
    end

    local remainingBits = prefixLength % 16
    if remainingBits == 0 then return true end
    local divisor = 2 ^ (16 - remainingBits)
    return math.floor(words[completeWords + 1] / divisor)
        == math.floor(prefixWords[completeWords + 1] / divisor)
end

local function special(prefix, prefixLength, words, reason, name)
    return {
        prefix = prefix,
        prefixLength = prefixLength,
        words = words,
        reason = reason,
        name = name,
    }
end

-- Entries are ordered from most-specific to least-specific.  The broad
-- 2001::/23 protocol-assignment block contains both the benchmarking and
-- ORCHIDv2 allocations, so those two must be tested first.
local SPECIAL_RANGES = {
    special("::", 128,
        { 0, 0, 0, 0, 0, 0, 0, 0 },
        "unspecified", "Unspecified address"),
    special("::1", 128,
        { 0, 0, 0, 0, 0, 0, 0, 1 },
        "loopback", "Loopback"),
    special("::ffff:0:0/96", 96,
        { 0, 0, 0, 0, 0, 0xffff, 0, 0 },
        "ipv4_mapped", "IPv4-mapped address"),
    special("::/96", 96,
        { 0, 0, 0, 0, 0, 0, 0, 0 },
        "ipv4_compatible", "Deprecated IPv4-compatible address"),
    special("100::/64", 64,
        { 0x0100, 0, 0, 0, 0, 0, 0, 0 },
        "discard_only", "Discard-Only Address Block"),
    special("2001:2::/48", 48,
        { 0x2001, 0x0002, 0, 0, 0, 0, 0, 0 },
        "benchmarking", "Benchmarking"),
    special("2001:20::/28", 28,
        { 0x2001, 0x0020, 0, 0, 0, 0, 0, 0 },
        "orchidv2", "ORCHIDv2"),
    special("2001:db8::/32", 32,
        { 0x2001, 0x0db8, 0, 0, 0, 0, 0, 0 },
        "documentation", "Documentation"),
    special("2001::/23", 23,
        { 0x2001, 0, 0, 0, 0, 0, 0, 0 },
        "protocol_assignment", "IETF Protocol Assignments"),
    special("2002::/16", 16,
        { 0x2002, 0, 0, 0, 0, 0, 0, 0 },
        "6to4", "6to4"),
    special("2620:4f:8000::/48", 48,
        { 0x2620, 0x004f, 0x8000, 0, 0, 0, 0, 0 },
        "special_service_as112", "Direct Delegation AS112 Service"),
    special("3ffe::/16", 16,
        { 0x3ffe, 0, 0, 0, 0, 0, 0, 0 },
        "returned_6bone", "6bone (returned to IANA)"),
    special("3fff::/20", 20,
        { 0x3fff, 0, 0, 0, 0, 0, 0, 0 },
        "documentation", "Documentation"),
    special("fc00::/7", 7,
        { 0xfc00, 0, 0, 0, 0, 0, 0, 0 },
        "unique_local", "Unique-Local"),
    special("fe80::/10", 10,
        { 0xfe80, 0, 0, 0, 0, 0, 0, 0 },
        "link_local", "Link-Local Unicast"),
    special("ff00::/8", 8,
        { 0xff00, 0, 0, 0, 0, 0, 0, 0 },
        "multicast", "Multicast"),
}

local GLOBAL_UNICAST = { 0x2000, 0, 0, 0, 0, 0, 0, 0 }

local function attachClassification(result)
    for _, range in ipairs(SPECIAL_RANGES) do
        if prefixMatches(result.words, range.words, range.prefixLength) then
            result.scope = "non_global"
            result.reason = range.reason
            result.name = range.name
            result.prefix = range.prefix
            result.prefixLength = range.prefixLength
            result.isGlobal = false
            result.directPlayerCandidate = false
            result.specialPurpose = true
            return result
        end
    end

    if prefixMatches(result.words, GLOBAL_UNICAST, 3) then
        result.scope = "global"
        result.reason = "global_unicast"
        result.name = "Global unicast"
        result.isGlobal = true
        result.directPlayerCandidate = true
        result.specialPurpose = false
        return result
    end

    result.scope = "non_global"
    result.reason = "not_global_unicast"
    result.name = "Not ordinary global unicast"
    result.isGlobal = false
    result.directPlayerCandidate = false
    result.specialPurpose = false
    return result
end

local function canonicalAddress(words)
    local bestStart, bestLength
    local index = 1
    while index <= 8 do
        if words[index] == 0 then
            local finish = index
            while finish <= 8 and words[finish] == 0 do finish = finish + 1 end
            local length = finish - index
            -- RFC 5952 compresses the longest run of at least two zero words,
            -- choosing the first run when lengths tie.
            if length >= 2 and (not bestLength or length > bestLength) then
                bestStart, bestLength = index, length
            end
            index = finish
        else
            index = index + 1
        end
    end

    local groups = {}
    for wordIndex = 1, 8 do
        groups[wordIndex] = string.format("%x", words[wordIndex])
    end
    if not bestStart then return table.concat(groups, ":") end

    local before, after = {}, {}
    for wordIndex = 1, bestStart - 1 do before[#before + 1] = groups[wordIndex] end
    for wordIndex = bestStart + bestLength, 8 do
        after[#after + 1] = groups[wordIndex]
    end
    if #before == 0 and #after == 0 then return "::" end
    if #before == 0 then return "::" .. table.concat(after, ":") end
    if #after == 0 then return table.concat(before, ":") .. "::" end
    return table.concat(before, ":") .. "::" .. table.concat(after, ":")
end

local function resultFromWords(words)
    local bytes = {}
    for index = 1, 8 do
        local word = words[index]
        bytes[#bytes + 1] = string.char(math.floor(word / 256), word % 256)
    end
    return attachClassification({
        address = canonicalAddress(words),
        bytes = table.concat(bytes),
        words = words,
    })
end

local function parseGroups(part, target)
    if part == "" then return true end
    if part:sub(1, 1) == ":" or part:sub(-1) == ":"
        or part:find("::", 1, true)
    then
        return nil, "empty_group"
    end

    local start = 1
    while true do
        local colon = part:find(":", start, true)
        local group = colon and part:sub(start, colon - 1) or part:sub(start)
        if #group > 4 then return nil, "group_too_long" end
        if group == "" then return nil, "empty_group" end
        if not group:match("^[0-9A-Fa-f]+$") then return nil, "invalid_hex_group" end
        target[#target + 1] = tonumber(group, 16)
        if not colon then break end
        start = colon + 1
    end
    return true
end

function Ipv6Address.parse(text)
    if type(text) ~= "string" then return nil, "not_text" end
    if #text > Ipv6Address.MAX_INPUT_LENGTH then return nil, "too_long" end
    if text == "" then return nil, "empty" end
    if text:find("[%z\1-\31\127]") then return nil, "control_character" end
    if text:find("%s") then return nil, "whitespace" end
    if text:find("%%") then return nil, "zone_id" end
    if text:find("[%[%]]") then return nil, "bracket_or_port" end
    if text:find("%.") then return nil, "ipv4_embedded" end
    if text:find("%+") then return nil, "leading_plus" end
    if text:find("[^0-9A-Fa-f:]") then return nil, "invalid_character" end
    if text:find(":::", 1, true) then return nil, "multiple_compression" end

    local compression = text:find("::", 1, true)
    if compression and text:find("::", compression + 2, true) then
        return nil, "multiple_compression"
    end

    local words = {}
    if compression then
        local leftWords, rightWords = {}, {}
        local leftOk, leftError = parseGroups(text:sub(1, compression - 1), leftWords)
        if not leftOk then return nil, leftError end
        local rightOk, rightError = parseGroups(text:sub(compression + 2), rightWords)
        if not rightOk then return nil, rightError end
        if #leftWords + #rightWords >= 8 then return nil, "invalid_group_count" end

        for _, word in ipairs(leftWords) do words[#words + 1] = word end
        for _ = 1, 8 - #leftWords - #rightWords do words[#words + 1] = 0 end
        for _, word in ipairs(rightWords) do words[#words + 1] = word end
    else
        local ok, parseError = parseGroups(text, words)
        if not ok then return nil, parseError end
        if #words ~= 8 then return nil, "invalid_group_count" end
    end

    return resultFromWords(words)
end

function Ipv6Address.fromBytes(bytes)
    if type(bytes) ~= "string" then return nil, "bytes_not_string" end
    if #bytes ~= Ipv6Address.BYTE_LENGTH then return nil, "invalid_byte_length" end

    local words = {}
    for index = 1, 8 do
        local high, low = bytes:byte(index * 2 - 1, index * 2)
        words[index] = high * 256 + low
    end
    return resultFromWords(words)
end

local function normalized(value)
    if type(value) == "string" then return Ipv6Address.parse(value) end
    if type(value) ~= "table" then return Ipv6Address.parse(value) end
    if type(value.bytes) == "string" then return Ipv6Address.fromBytes(value.bytes) end
    if type(value.address) == "string" then return Ipv6Address.parse(value.address) end
    return nil, "invalid_parsed_value"
end

local function invalid(reason)
    return {
        scope = "invalid",
        reason = reason,
        isGlobal = false,
        directPlayerCandidate = false,
        specialPurpose = false,
    }
end

function Ipv6Address.classify(value)
    local parsed, parseError = normalized(value)
    return parsed or invalid(parseError)
end

function Ipv6Address.isGlobal(value)
    local result = Ipv6Address.classify(value)
    return result.isGlobal, result
end

function Ipv6Address.endpoint(value, port)
    if type(port) ~= "number" or port ~= port then return nil, "port_not_number" end
    if port ~= math.floor(port) then return nil, "port_not_integer" end
    if port < 1 or port > 65535 then return nil, "port_out_of_range" end

    local parsed, parseError = normalized(value)
    if not parsed then return nil, parseError end
    return "[" .. parsed.address .. "]:" .. tostring(port)
end

return Ipv6Address
