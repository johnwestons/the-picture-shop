-- Platform-neutral, fail-closed validation for local default-gateway data.
-- Discovery is read-only: it does not open sockets, send probes, or create a
-- router mapping.  Platform providers are deliberately narrow and injectable.
local IpScope = require("src.net.ip_scope")
local GatewayNative = require("src.net.gateway_native")
local GatewayAndroid = require("src.net.gateway_android")

local GatewayDiscovery = {}

local MAX_INTERFACE_INDEX = 4294967295
local ALLOWED_NON_GLOBAL_REASONS = {
    private_use = true,
    carrier_grade_nat = true,
    link_local = true,
}
local ANDROID_GENERATION_PREFIX = "android-route-v2-"

local function detectedPlatform()
    if love and love.system and type(love.system.getOS) == "function" then
        local ok, platform = pcall(love.system.getOS)
        if ok and type(platform) == "string" then return platform end
    end
    if jit and type(jit.os) == "string" then return jit.os end
    return nil
end

local function usableUnicast(address)
    if not IpScope.parse(address) then return false end
    local classification = IpScope.classify(address)
    return classification.isGlobal == true or
        ALLOWED_NON_GLOBAL_REASONS[classification.reason] == true
end

local function usableInternalUnicast(address, platform)
    if not usableUnicast(address) then return false end
    if platform ~= "Android" then return true end
    -- A link-local source cannot provide cross-network hosting.  A link-local
    -- next-hop gateway remains valid, so this stricter rule applies only to
    -- the selected Android source address.
    return IpScope.classify(address).reason ~= "link_local"
end

local function validInterfaceIndex(value)
    return type(value) == "number" and value == math.floor(value)
        and value >= 1 and value <= MAX_INTERFACE_INDEX
end

local function validAndroidGeneration(value)
    if type(value) ~= "string"
        or #value ~= #ANDROID_GENERATION_PREFIX + 25
        or value:sub(1, #ANDROID_GENERATION_PREFIX) ~=
            ANDROID_GENERATION_PREFIX then
        return false
    end
    local suffix = value:sub(#ANDROID_GENERATION_PREFIX + 1)
    local handle = suffix:sub(1, 16)
    local separator = suffix:sub(17, 17)
    local revision = suffix:sub(18, 25)
    return separator == "-"
        and handle ~= "0000000000000000"
        and revision ~= "00000000"
        and handle:match("^[0-9a-f]+$") ~= nil
        and revision:match("^[0-9a-f]+$") ~= nil
end

local function routeFingerprint(platform, internalAddress, gatewayAddress,
        interfaceIndex, networkGeneration)
    local fields
    if platform == "Android" then
        fields = {
            "route-v1", platform, internalAddress, gatewayAddress,
            "android-network-generation", networkGeneration,
        }
    else
        -- Preserve the exact Windows fingerprint material.
        fields = {
            "route-v1", platform, internalAddress, gatewayAddress,
            tostring(interfaceIndex),
        }
    end
    local material = table.concat(fields, "\0")
    local hash = 5381
    for index = 1, #material do
        hash = (hash * 33 + material:byte(index)) % 4294967296
    end
    local high = math.floor(hash / 65536)
    local low = hash % 65536
    return string.format("route-v1-%04x%04x", high, low)
end

local function normalizeCandidate(candidate, platform)
    if type(candidate) ~= "table" then return nil end
    local family = rawget(candidate, "family")
    local internalAddress = rawget(candidate, "internalAddress")
    local gatewayAddress = rawget(candidate, "gatewayAddress")
    local interfaceIndex = rawget(candidate, "interfaceIndex")
    local routePrefixLength = rawget(candidate, "routePrefixLength")
    local networkGeneration = rawget(candidate, "networkGeneration")

    if family ~= 4 or routePrefixLength ~= 0 or
        not usableInternalUnicast(internalAddress, platform) or
        not usableUnicast(gatewayAddress) or
        internalAddress == gatewayAddress then
        return nil
    end
    if platform == "Android" then
        if interfaceIndex ~= nil or
            not validAndroidGeneration(networkGeneration) then
            return nil
        end
    elseif not validInterfaceIndex(interfaceIndex) then
        return nil
    end

    local normalized = {
        family = 4,
        internalAddress = internalAddress,
        gatewayAddress = gatewayAddress,
        routePrefixLength = 0,
        platform = platform,
        routeFingerprint = routeFingerprint(
            platform, internalAddress, gatewayAddress, interfaceIndex,
            networkGeneration),
    }
    if platform == "Android" then
        normalized.networkGeneration = networkGeneration
    else
        normalized.interfaceIndex = interfaceIndex
    end
    return normalized
end

local function providerFunction(provider)
    if type(provider) == "function" then return provider end
    if type(provider) == "table" then
        local discover = rawget(provider, "discover")
        if type(discover) == "function" then
            return function() return discover() end
        end
    end
    return nil
end

function GatewayDiscovery.discover(options)
    options = type(options) == "table" and options or {}
    local requestedPlatform = rawget(options, "platform")
    local platform = requestedPlatform == nil and detectedPlatform()
        or requestedPlatform
    if platform ~= "Windows" and platform ~= "Android" then
        return nil, "unsupported_platform"
    end

    local provider = rawget(options, "provider")
    if provider == nil then
        if platform == "Windows" then
            provider = GatewayNative
        else
            provider = GatewayAndroid
        end
    end
    local discover = providerFunction(provider)
    if not discover then return nil, "gateway_discovery_unavailable" end

    local ok, candidate = pcall(discover)
    if not ok or candidate == nil then
        return nil, "gateway_discovery_unavailable"
    end
    local normalized = normalizeCandidate(candidate, platform)
    if not normalized then return nil, "invalid_default_route" end
    return normalized
end

local function normalizeSnapshot(snapshot)
    if type(snapshot) ~= "table" then return nil end
    local platform = rawget(snapshot, "platform")
    if platform ~= "Windows" and platform ~= "Android" then return nil end
    local normalized = normalizeCandidate(snapshot, platform)
    if not normalized or rawget(snapshot, "routeFingerprint") ~=
            normalized.routeFingerprint then
        return nil
    end
    return normalized
end

function GatewayDiscovery.revalidate(snapshot, options)
    local expected = normalizeSnapshot(snapshot)
    if not expected then return nil, "invalid_snapshot" end

    local current = GatewayDiscovery.discover(options)
    if not current or
        current.family ~= expected.family or
        current.internalAddress ~= expected.internalAddress or
        current.gatewayAddress ~= expected.gatewayAddress or
        current.interfaceIndex ~= expected.interfaceIndex or
        current.routePrefixLength ~= expected.routePrefixLength or
        current.platform ~= expected.platform or
        current.networkGeneration ~= expected.networkGeneration or
        current.routeFingerprint ~= expected.routeFingerprint then
        return false, "network_changed"
    end
    return current
end

return GatewayDiscovery
