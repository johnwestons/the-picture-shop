-- Platform-neutral, fail-closed validation for local default-gateway data.
-- Discovery is read-only: it does not open sockets, send probes, or create a
-- router mapping.  Platform providers are deliberately narrow and injectable.
local IpScope = require("src.net.ip_scope")
local GatewayNative = require("src.net.gateway_native")

local GatewayDiscovery = {}

local MAX_INTERFACE_INDEX = 4294967295
local ALLOWED_NON_GLOBAL_REASONS = {
    private_use = true,
    carrier_grade_nat = true,
    link_local = true,
}

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

local function validInterfaceIndex(value)
    return type(value) == "number" and value == math.floor(value)
        and value >= 1 and value <= MAX_INTERFACE_INDEX
end

local function routeFingerprint(platform, internalAddress, gatewayAddress,
        interfaceIndex)
    local material = table.concat({
        "route-v1", platform, internalAddress, gatewayAddress,
        tostring(interfaceIndex),
    }, "\0")
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

    if family ~= 4 or routePrefixLength ~= 0 or
        not validInterfaceIndex(interfaceIndex) or
        not usableUnicast(internalAddress) or
        not usableUnicast(gatewayAddress) or
        internalAddress == gatewayAddress then
        return nil
    end

    return {
        family = 4,
        internalAddress = internalAddress,
        gatewayAddress = gatewayAddress,
        interfaceIndex = interfaceIndex,
        routePrefixLength = 0,
        platform = platform,
        routeFingerprint = routeFingerprint(
            platform, internalAddress, gatewayAddress, interfaceIndex),
    }
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
            return nil, "platform_bridge_unavailable"
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
        current.routeFingerprint ~= expected.routeFingerprint then
        return false, "network_changed"
    end
    return current
end

return GatewayDiscovery
