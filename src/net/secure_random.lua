-- Secure random bytes for durable multiplayer identity material.
local Random = {}

local function appleRandomBytes(count)
    local loaded, ffi = pcall(require, "ffi")
    if not loaded or type(ffi) ~= "table" then return nil end

    pcall(ffi.cdef, "void arc4random_buf(void *buf, size_t nbytes);")
    local allocated, buffer = pcall(ffi.new, "unsigned char[?]", count)
    if not allocated then return nil end
    local generated = pcall(function()
        ffi.C.arc4random_buf(buffer, count)
    end)
    if not generated then return nil end
    local okay, bytes = pcall(ffi.string, buffer, count)
    return okay and type(bytes) == "string" and #bytes == count and bytes or nil
end

local function deviceRandomBytes(count)
    if type(io) ~= "table" or type(io.open) ~= "function" then return nil end
    local opened, file = pcall(io.open, "/dev/urandom", "rb")
    if not opened or not file then return nil end
    local readOkay, bytes = pcall(file.read, file, count)
    pcall(file.close, file)
    return readOkay and type(bytes) == "string" and #bytes == count and bytes or nil
end

function Random.bytes(count)
    count = tonumber(count)
    if not count or count ~= math.floor(count) or count < 1 or count > 1024 * 1024 then
        return nil, "Secure random byte count is invalid."
    end

    local nativeOkay, native = pcall(require, "src.net.crypto_native")
    if nativeOkay and type(native) == 'table' and type(native.randomBytes) == "function" then
        local okay, bytes = pcall(native.randomBytes, count)
        if okay and type(bytes) == "string" and #bytes == count then return bytes,nil,'native' end
    end

    local osName
    if love and love.system and type(love.system.getOS) == "function" then
        local okay, value = pcall(love.system.getOS)
        if okay then osName = value end
    end
    if osName == "iOS" then
        local bytes = appleRandomBytes(count)
        if bytes then return bytes,nil,'apple-system' end
        bytes=deviceRandomBytes(count)
        if bytes then return bytes,nil,'system-device' end
    end
    return nil, "Secure random byte generation is unavailable on this device."
end

return Random
