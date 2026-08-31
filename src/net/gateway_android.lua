-- Narrow LuaJIT FFI boundary for Android's atomic default-IPv4-gateway
-- snapshot.  ConnectivityManager, LinkProperties, and their mutable platform
-- objects stay behind the native bridge; Lua receives only two bounded IPv4
-- strings, the exact Android Network handle split into two uint32 values, and
-- a process-local route revision.
local IpScope = require("src.net.ip_scope")

local GatewayAndroid = {
    expectedAbiVersion = 2,
    readOnly = true,
    networkTrafficSent = false,
}

local ADDRESS_BYTES = 16
local MAX_UINT32 = 4294967295
local ffi
local nativeLibrary
local loadAttempted = false

local function detectedPlatform()
    if love and love.system and type(love.system.getOS) == "function" then
        local ok, platform = pcall(love.system.getOS)
        if ok and type(platform) == "string" then return platform end
    end
    if jit and type(jit.os) == "string" then return jit.os end
    return nil
end

local function bindLibrary()
    if loadAttempted then return nativeLibrary, ffi end
    loadAttempted = true

    -- Never load an Android JNI bridge into a desktop process.  Tests use the
    -- injected invoke function below and therefore do not need the library.
    if detectedPlatform() ~= "Android" then return nil end

    local ffiOk, ffiModule = pcall(require, "ffi")
    if not ffiOk or type(ffiModule) ~= "table" then return nil end
    ffi = ffiModule
    local cdefOk = pcall(ffi.cdef, [[
        uint32_t tps_android_gateway_abi_version(void);
        int32_t tps_android_gateway_default_ipv4(
            char source[16],
            char gateway[16],
            uint32_t *network_handle_high,
            uint32_t *network_handle_low,
            uint32_t *route_revision);
    ]])
    if not cdefOk then return nil end

    local loadOk, library = pcall(ffi.load, "tps_android_gateway")
    if not loadOk or not library then return nil end
    local verifyOk, abi = pcall(function()
        return tonumber(library.tps_android_gateway_abi_version())
    end)
    if not verifyOk or abi ~= GatewayAndroid.expectedAbiVersion then return nil end

    local symbolOk, symbol = pcall(function()
        return library.tps_android_gateway_default_ipv4
    end)
    if not symbolOk or symbol == nil then return nil end
    nativeLibrary = library
    return nativeLibrary, ffi
end

local function decodeBoundedCString(buffer, ffiModule)
    local raw = ffiModule.string(buffer, ADDRESS_BYTES)
    local terminator = raw:find("\0", 1, true)
    if not terminator then return nil end
    return raw:sub(1, terminator - 1)
end

local function defaultInvoke()
    local library, ffiModule = bindLibrary()
    if not library or not ffiModule then return nil end

    local source = ffiModule.new("char[16]")
    local gateway = ffiModule.new("char[16]")
    local networkHandleHigh = ffiModule.new("uint32_t[1]")
    local networkHandleLow = ffiModule.new("uint32_t[1]")
    local routeRevision = ffiModule.new("uint32_t[1]")
    local result = tonumber(library.tps_android_gateway_default_ipv4(
        source, gateway, networkHandleHigh, networkHandleLow, routeRevision))
    if result ~= 0 then return result end
    return result,
        decodeBoundedCString(source, ffiModule),
        decodeBoundedCString(gateway, ffiModule),
        tonumber(networkHandleHigh[0]),
        tonumber(networkHandleLow[0]),
        tonumber(routeRevision[0])
end

local function boundedUnsignedInteger(value)
    return type(value) == "number" and value == math.floor(value)
        and value >= 0 and value <= MAX_UINT32
end

local function uint32Hex(value)
    -- Every formatted operand stays below 2^16.  This avoids converting the
    -- 64-bit Android Network handle to a Lua number, which would lose exact
    -- integer precision on LuaJIT's default numeric type.
    local high = math.floor(value / 65536)
    local low = value % 65536
    return string.format("%04x%04x", high, low)
end

local function networkGeneration(handleHigh, handleLow, revision)
    return "android-route-v2-" .. uint32Hex(handleHigh) ..
        uint32Hex(handleLow) .. "-" .. uint32Hex(revision)
end

function GatewayAndroid.discover(options)
    options = type(options) == "table" and options or {}
    local invoke = rawget(options, "invoke") or defaultInvoke
    if type(invoke) ~= "function" then
        return nil, "android_gateway_unavailable"
    end

    local ok, result, source, gateway, networkHandleHigh, networkHandleLow,
        routeRevision =
        pcall(invoke)
    if not ok or result ~= 0 then
        -- Native status values and exception text are intentionally not
        -- surfaced.  They may describe the device, active network, or VPN.
        return nil, "android_gateway_unavailable"
    end
    if not IpScope.parse(source) or not IpScope.parse(gateway)
        or not boundedUnsignedInteger(networkHandleHigh)
        or not boundedUnsignedInteger(networkHandleLow)
        or (networkHandleHigh == 0 and networkHandleLow == 0)
        or not boundedUnsignedInteger(routeRevision)
        or routeRevision == 0
    then
        return nil, "invalid_android_route"
    end

    return {
        family = 4,
        internalAddress = source,
        gatewayAddress = gateway,
        routePrefixLength = 0,
        networkGeneration = networkGeneration(
            networkHandleHigh, networkHandleLow, routeRevision),
    }
end

return GatewayAndroid
