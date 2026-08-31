local INFO_MARKER =
    "TPS_ANDROID_GATEWAY_PROBE_INFO abi=2 readOnly=true networkTrafficSent=false"
local MODULES_MARKER = "TPS_ANDROID_GATEWAY_MODULES_OK"
local LIBRARY_MARKER = "TPS_ANDROID_GATEWAY_LIBRARY_OK"
local ABI_MARKER = "TPS_ANDROID_GATEWAY_ABI_OK"
local NATIVE_SNAPSHOT_MARKER = "TPS_ANDROID_GATEWAY_NATIVE_SNAPSHOT_OK"
local CALLBACK_HEALTHY_MARKER = "TPS_ANDROID_GATEWAY_CALLBACK_HEALTHY_OK"
local ROUTE_MARKER = "TPS_ANDROID_GATEWAY_ROUTE_OK"
local REVALIDATION_MARKER = "TPS_ANDROID_GATEWAY_REVALIDATION_OK"
local OK_MARKER = "TPS_ANDROID_GATEWAY_PROBE_OK"
local FAIL_MARKER = "TPS_ANDROID_GATEWAY_PROBE_FAIL"
local TIMEOUT_SECONDS = 20

local discovery
local provider
local finished = false
local deadline = 0
local libraryChecked = false
local nativeSnapshotReported = false
local callbackHealthyReported = false

local function finish(success)
    if finished then return end
    finished = true
    if success then
        print(INFO_MARKER)
        print(ROUTE_MARKER)
        print(REVALIDATION_MARKER)
        print(OK_MARKER)
        love.event.quit(0)
    else
        print(FAIL_MARKER)
        love.event.quit(1)
    end
end

local function validGeneration(value)
    return type(value) == "string"
        and value:match(
            "^android%-route%-v2%-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]" ..
            "[0-9a-f][0-9a-f][0-9a-f][0-9a-f]" ..
            "[0-9a-f][0-9a-f][0-9a-f][0-9a-f]" ..
            "[0-9a-f][0-9a-f][0-9a-f][0-9a-f]%-" ..
            "[0-9a-f][0-9a-f][0-9a-f][0-9a-f]" ..
            "[0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") ~= nil
end

local function validRouteFields(candidate)
    return type(candidate) == "table"
        and candidate.family == 4
        and type(candidate.internalAddress) == "string"
        and #candidate.internalAddress >= 7
        and #candidate.internalAddress <= 15
        and type(candidate.gatewayAddress) == "string"
        and #candidate.gatewayAddress >= 7
        and #candidate.gatewayAddress <= 15
        and candidate.internalAddress ~= candidate.gatewayAddress
        and candidate.routePrefixLength == 0
        and validGeneration(candidate.networkGeneration)
        and rawget(candidate, "interfaceIndex") == nil
        and rawget(candidate, "networkHandle") == nil
        and rawget(candidate, "networkHandleHigh") == nil
        and rawget(candidate, "networkHandleLow") == nil
        and rawget(candidate, "networkRevision") == nil
end

local function validProviderCandidate(candidate)
    return validRouteFields(candidate)
        and rawget(candidate, "platform") == nil
        and rawget(candidate, "routeFingerprint") == nil
end

local function validSnapshot(snapshot)
    return validRouteFields(snapshot)
        and snapshot.family == 4
        and snapshot.platform == "Android"
        and type(snapshot.routeFingerprint) == "string"
        and snapshot.routeFingerprint:match(
            "^route%-v1%-%x%x%x%x%x%x%x%x$") ~= nil
end

function love.load()
    local providerOk, loadedProvider = pcall(
        require, "src.net.gateway_android")
    local discoveryOk, loadedDiscovery = pcall(
        require, "src.net.gateway_discovery")
    if not providerOk or type(loadedProvider) ~= "table"
            or loadedProvider.expectedAbiVersion ~= 2
            or loadedProvider.readOnly ~= true
            or loadedProvider.networkTrafficSent ~= false
            or not discoveryOk or type(loadedDiscovery) ~= "table" then
        finish(false)
        return
    end
    provider = loadedProvider
    discovery = loadedDiscovery
    print(MODULES_MARKER)
    deadline = love.timer.getTime() + TIMEOUT_SECONDS
end

function love.update()
    if finished or not discovery then return end
    if love.timer.getTime() >= deadline then
        finish(false)
        return
    end

    local nativeCandidate = provider.discover()
    if not libraryChecked then
        libraryChecked = true
        local ffiOk, ffi = pcall(require, "ffi")
        local loadOk, library = false, nil
        if ffiOk and type(ffi) == "table" then
            loadOk, library = pcall(ffi.load, "tps_android_gateway")
        end
        if loadOk and library then
            print(LIBRARY_MARKER)
            local abiOk, abi = pcall(function()
                return tonumber(library.tps_android_gateway_abi_version())
            end)
            if abiOk and abi == 2 then print(ABI_MARKER) end
        end
    end
    if validProviderCandidate(nativeCandidate) and not nativeSnapshotReported then
        nativeSnapshotReported = true
        print(NATIVE_SNAPSHOT_MARKER)
    end

    -- Registration is asynchronous.  Treat an unavailable snapshot or a
    -- handoff during immediate revalidation as a retry until the fixed bound.
    local snapshot = discovery.discover({ platform = "Android" })
    if not validSnapshot(snapshot) then return end
    local current = discovery.revalidate(
        snapshot, { platform = "Android" })
    if not validSnapshot(current)
            or current.networkGeneration ~= snapshot.networkGeneration
            or current.routeFingerprint ~= snapshot.routeFingerprint then
        return
    end
    if not callbackHealthyReported then
        callbackHealthyReported = true
        print(CALLBACK_HEALTHY_MARKER)
    end
    finish(true)
end
