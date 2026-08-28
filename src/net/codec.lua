local Codec = {}

local ARRAY_METATABLE = {}
local DEFAULT_LIMITS = {
    maxBytes = 4096,
    maxDepth = 12,
    maxEntries = 512,
    maxStringBytes = 1024,
    maxNumberBytes = 32,
}

Codec.DEFAULT_LIMITS = {
    maxBytes = DEFAULT_LIMITS.maxBytes,
    maxDepth = DEFAULT_LIMITS.maxDepth,
    maxEntries = DEFAULT_LIMITS.maxEntries,
    maxStringBytes = DEFAULT_LIMITS.maxStringBytes,
    maxNumberBytes = DEFAULT_LIMITS.maxNumberBytes,
}

local function resolveLimits(overrides)
    local limits = {}
    for name, defaultValue in pairs(DEFAULT_LIMITS) do
        local value = overrides and overrides[name] or defaultValue
        if type(value) ~= "number" or value ~= math.floor(value) or value < 1 then
            return nil, "invalid codec limit: " .. name
        end
        limits[name] = value
    end
    if overrides then
        for name in pairs(overrides) do
            if DEFAULT_LIMITS[name] == nil then
                return nil, "unknown codec limit: " .. tostring(name)
            end
        end
    end
    return limits
end

local function finiteNumber(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function canonicalNumber(value)
    if not finiteNumber(value) then return nil, "numbers must be finite" end
    if value == 0 then return "0" end
    local encoded = string.format("%.17g", value)
    if #encoded == 0 then return nil, "number could not be encoded" end
    return encoded
end

local function validNumberToken(value)
    return value:match("^%-?%d+$")
        or value:match("^%-?%d+%.%d+$")
        or value:match("^%-?%d+[eE][+%-]?%d+$")
        or value:match("^%-?%d+%.%d+[eE][+%-]?%d+$")
end

local function classifyTable(value)
    local metatable = getmetatable(value)
    if metatable ~= nil and metatable ~= ARRAY_METATABLE then
        return nil, "tables with metatables are not supported"
    end

    local count, maximumIndex = 0, 0
    local onlyArrayKeys, onlyMapKeys = true, true
    for key in next, value do
        count = count + 1
        if type(key) == "number" and key >= 1 and key == math.floor(key) then
            maximumIndex = math.max(maximumIndex, key)
            onlyMapKeys = false
        elseif type(key) == "string" then
            onlyArrayKeys = false
        else
            return nil, "table keys must be strings or contiguous positive integers"
        end
    end

    if metatable == ARRAY_METATABLE then
        if not onlyArrayKeys or maximumIndex ~= count then
            return nil, "marked arrays must have contiguous positive integer keys"
        end
        return "array", count
    end
    if count > 0 and onlyArrayKeys and maximumIndex == count then return "array", count end
    if onlyMapKeys then return "map", count end
    return nil, "tables must be either arrays or string-keyed maps"
end

function Codec.array(values)
    values = values or {}
    if type(values) ~= "table" then error("Codec.array expects a table", 2) end
    if getmetatable(values) ~= nil then error("Codec.array expects a table without a metatable", 2) end
    return setmetatable(values, ARRAY_METATABLE)
end

function Codec.isArray(value)
    if type(value) ~= "table" then return false end
    local kind = classifyTable(value)
    return kind == "array"
end

local function append(state, value)
    if state.bytes + #value > state.limits.maxBytes then
        return nil, "encoded value exceeds maxBytes"
    end
    state.bytes = state.bytes + #value
    state.parts[#state.parts + 1] = value
    return true
end

local encodeValue

encodeValue = function(value, state, depth)
    local valueType = type(value)
    if valueType == "boolean" then
        return append(state, value and "t" or "f")
    elseif valueType == "number" then
        local encoded, numberError = canonicalNumber(value)
        if not encoded then return nil, numberError end
        if #encoded > state.limits.maxNumberBytes then return nil, "number exceeds maxNumberBytes" end
        local ok, appendError = append(state, "d" .. tostring(#encoded) .. ":")
        if not ok then return nil, appendError end
        return append(state, encoded)
    elseif valueType == "string" then
        if #value > state.limits.maxStringBytes then return nil, "string exceeds maxStringBytes" end
        local ok, appendError = append(state, "s" .. tostring(#value) .. ":")
        if not ok then return nil, appendError end
        return append(state, value)
    elseif valueType ~= "table" then
        return nil, "unsupported value type: " .. valueType
    end

    if depth > state.limits.maxDepth then return nil, "table nesting exceeds maxDepth" end
    if state.active[value] then return nil, "cyclic tables are not supported" end
    local kind, countOrError = classifyTable(value)
    if not kind then return nil, countOrError end
    local count = countOrError
    if state.entries + count > state.limits.maxEntries then
        return nil, "table entries exceed maxEntries"
    end
    state.entries = state.entries + count
    state.active[value] = true

    local ok, encodeError = append(state, (kind == "array" and "a" or "m") .. tostring(count) .. ":")
    if ok and kind == "array" then
        for index = 1, count do
            ok, encodeError = encodeValue(value[index], state, depth + 1)
            if not ok then break end
        end
    elseif ok then
        local keys = {}
        for key in next, value do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            ok, encodeError = encodeValue(key, state, depth + 1)
            if not ok then break end
            ok, encodeError = encodeValue(value[key], state, depth + 1)
            if not ok then break end
        end
    end
    state.active[value] = nil
    return ok, encodeError
end

function Codec.encode(value, overrides)
    local limits, limitError = resolveLimits(overrides)
    if not limits then return nil, limitError end
    local state = {
        limits = limits,
        parts = {},
        bytes = 0,
        entries = 0,
        active = {},
    }
    local ok, encodeError = encodeValue(value, state, 1)
    if not ok then return nil, encodeError end
    return table.concat(state.parts)
end

local function readUnsigned(state, label)
    local startPosition = state.position
    local separator = startPosition
    while separator <= state.length and state.data:byte(separator) ~= 58 do
        local byte = state.data:byte(separator)
        if byte < 48 or byte > 57 then return nil, label .. " must be an unsigned integer" end
        separator = separator + 1
    end
    if separator > state.length then return nil, "truncated " .. label end
    if separator == startPosition then return nil, "missing " .. label end
    local token = state.data:sub(startPosition, separator - 1)
    if #token > 1 and token:sub(1, 1) == "0" then return nil, "non-canonical " .. label end
    local value = tonumber(token)
    if not value or value ~= math.floor(value) then return nil, "invalid " .. label end
    state.position = separator + 1
    return value
end

local decodeValue

decodeValue = function(state, depth)
    if state.position > state.length then return nil, "truncated value" end
    local tag = state.data:sub(state.position, state.position)
    state.position = state.position + 1
    if tag == "t" then return true end
    if tag == "f" then return false end

    if tag == "s" then
        local length, lengthError = readUnsigned(state, "string length")
        if not length then return nil, lengthError end
        if length > state.limits.maxStringBytes then return nil, "string exceeds maxStringBytes" end
        local finalPosition = state.position + length - 1
        if finalPosition > state.length then return nil, "truncated string" end
        local value = state.data:sub(state.position, finalPosition)
        state.position = finalPosition + 1
        return value
    elseif tag == "d" then
        local length, lengthError = readUnsigned(state, "number length")
        if not length then return nil, lengthError end
        if length > state.limits.maxNumberBytes then return nil, "number exceeds maxNumberBytes" end
        local finalPosition = state.position + length - 1
        if finalPosition > state.length then return nil, "truncated number" end
        local token = state.data:sub(state.position, finalPosition)
        state.position = finalPosition + 1
        if not validNumberToken(token) then return nil, "invalid number" end
        local value = tonumber(token)
        if not value or not finiteNumber(value) then return nil, "number must be finite" end
        local canonical = canonicalNumber(value)
        if canonical ~= token then return nil, "non-canonical number" end
        return value
    elseif tag ~= "a" and tag ~= "m" then
        return nil, "unknown value tag"
    end

    if depth > state.limits.maxDepth then return nil, "table nesting exceeds maxDepth" end
    local count, countError = readUnsigned(state, "table entry count")
    if not count then return nil, countError end
    if state.entries + count > state.limits.maxEntries then
        return nil, "table entries exceed maxEntries"
    end
    state.entries = state.entries + count

    if tag == "a" then
        local result = setmetatable({}, ARRAY_METATABLE)
        for index = 1, count do
            local value, valueError = decodeValue(state, depth + 1)
            if valueError then return nil, valueError end
            result[index] = value
        end
        return result
    end

    local result, previousKey = {}, nil
    for _ = 1, count do
        local key, keyError = decodeValue(state, depth + 1)
        if keyError then return nil, keyError end
        if type(key) ~= "string" then return nil, "map keys must be strings" end
        if previousKey and key <= previousKey then return nil, "map keys are not in canonical order" end
        previousKey = key
        local value, valueError = decodeValue(state, depth + 1)
        if valueError then return nil, valueError end
        result[key] = value
    end
    return result
end

function Codec.decode(data, overrides)
    if type(data) ~= "string" then return nil, "encoded value must be a string" end
    local limits, limitError = resolveLimits(overrides)
    if not limits then return nil, limitError end
    if #data > limits.maxBytes then return nil, "encoded value exceeds maxBytes" end
    if #data == 0 then return nil, "encoded value is empty" end
    local state = {
        data = data,
        length = #data,
        position = 1,
        limits = limits,
        entries = 0,
    }
    local value, decodeError = decodeValue(state, 1)
    if decodeError then return nil, decodeError end
    if state.position ~= state.length + 1 then return nil, "trailing encoded data" end
    return value
end

return Codec
