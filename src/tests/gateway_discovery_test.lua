local GatewayDiscovery = require("src.net.gateway_discovery")
local GatewayNative = require("src.net.gateway_native")

local Test = {}

local function route(overrides)
    local value = {
        family = 4,
        internalAddress = "192.168.1.50",
        gatewayAddress = "192.168.1.1",
        interfaceIndex = 7,
        routePrefixLength = 0,
        ignoredProviderField = "must-not-cross-boundary",
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
end

local function provider(value)
    return function() return value end
end

function Test.run(_, check)
    local native, nativeError = GatewayNative.discover({
        invoke = function()
            return 0, "192.168.1.50", "192.168.1.1", 7
        end,
    })
    check("gateway_native_exposes_only_the_bounded_ipv4_route_contract",
        nativeError == nil and native.family == 4
        and native.internalAddress == "192.168.1.50"
        and native.gatewayAddress == "192.168.1.1"
        and native.interfaceIndex == 7 and native.routePrefixLength == 0
        and native.ignoredProviderField == nil
        and GatewayNative.readOnly == true
        and GatewayNative.networkTrafficSent == false)

    local thrown, thrownError = GatewayNative.discover({
        invoke = function() error("invitation-secret-must-not-escape") end,
    })
    local badNative, badNativeError = GatewayNative.discover({
        invoke = function() return 0, "192.168.001.50", "192.168.1.1", 7 end,
    })
    local unavailable, unavailableError = GatewayNative.discover({
        invoke = function() return -2, "private", "provider", 9 end,
    })
    check("gateway_native_sanitizes_provider_failures_and_noncanonical_output",
        thrown == nil and thrownError == "native_route_unavailable"
        and badNative == nil and badNativeError == "invalid_native_route"
        and unavailable == nil and unavailableError == "native_route_unavailable"
        and not thrownError:find("secret", 1, true)
        and not unavailableError:find("provider", 1, true))

    local candidate = route()
    setmetatable(candidate, {
        __index = function() error("unexpected provider field access") end,
    })
    local snapshot, snapshotError = GatewayDiscovery.discover({
        platform = "Windows",
        provider = provider(candidate),
    })
    check("gateway_discovery_returns_an_atomic_allowlisted_route_snapshot",
        snapshotError == nil and snapshot.family == 4
        and snapshot.internalAddress == "192.168.1.50"
        and snapshot.gatewayAddress == "192.168.1.1"
        and snapshot.interfaceIndex == 7 and snapshot.routePrefixLength == 0
        and snapshot.platform == "Windows"
        and type(snapshot.routeFingerprint) == "string"
        and snapshot.routeFingerprint:match(
            "^route%-v1%-%x%x%x%x%x%x%x%x$") ~= nil
        and not snapshot.routeFingerprint:find("192.168", 1, true)
        and snapshot.ignoredProviderField == nil)

    local acceptedKinds = true
    for _, value in ipairs({
        route({ internalAddress = "8.8.8.8", gatewayAddress = "1.1.1.1" }),
        route({ internalAddress = "100.64.0.2", gatewayAddress = "10.0.0.1" }),
        route({
            internalAddress = "169.254.10.2",
            gatewayAddress = "169.254.10.1",
        }),
    }) do
        local discovered, discoveryError = GatewayDiscovery.discover({
            platform = "Windows",
            provider = provider(value),
        })
        acceptedKinds = acceptedKinds and discovered ~= nil
            and discoveryError == nil
    end
    check("gateway_discovery_accepts_only_canonical_usable_unicast_route_pairs",
        acceptedKinds)

    local invalidCandidates = {
        false,
        {},
        route({ family = 6 }),
        route({ routePrefixLength = 24 }),
        route({ interfaceIndex = 0 }),
        route({ interfaceIndex = -1 }),
        route({ interfaceIndex = 1.5 }),
        route({ interfaceIndex = 4294967296 }),
        route({ internalAddress = "0.0.0.0" }),
        route({ internalAddress = "127.0.0.1" }),
        route({ gatewayAddress = "224.0.0.1" }),
        route({ gatewayAddress = "192.0.2.1" }),
        route({ gatewayAddress = "192.168.001.1" }),
        route({ gatewayAddress = "192.168.1.50" }),
    }
    local invalidRejected = true
    for _, value in ipairs(invalidCandidates) do
        local discovered, discoveryError = GatewayDiscovery.discover({
            platform = "Windows",
            provider = provider(value),
        })
        invalidRejected = invalidRejected and discovered == nil
            and (discoveryError == "invalid_default_route" or
                discoveryError == "gateway_discovery_unavailable")
    end
    check("gateway_discovery_rejects_malformed_special_and_nondefault_routes",
        invalidRejected)

    local failed, failedError = GatewayDiscovery.discover({
        platform = "Windows",
        provider = function()
            error("reply-code-and-player-name-must-never-escape")
        end,
    })
    local returnedNil, returnedNilError = GatewayDiscovery.discover({
        platform = "Windows",
        provider = function() return nil, "raw-system-error" end,
    })
    check("gateway_discovery_never_surfaces_platform_errors_or_secret_text",
        failed == nil and failedError == "gateway_discovery_unavailable"
        and returnedNil == nil
        and returnedNilError == "gateway_discovery_unavailable"
        and not failedError:find("reply", 1, true)
        and not returnedNilError:find("system", 1, true))

    local android, androidError = GatewayDiscovery.discover({
        platform = "Android",
    })
    local unsupported, unsupportedError = GatewayDiscovery.discover({
        platform = "Linux",
    })
    check("gateway_discovery_fails_closed_without_a_platform_bridge",
        android == nil and androidError == "platform_bridge_unavailable"
        and unsupported == nil and unsupportedError == "unsupported_platform")

    local active = route()
    local discoveryOptions = {
        platform = "Windows",
        provider = function() return active end,
    }
    local original = GatewayDiscovery.discover(discoveryOptions)
    local unchanged, unchangedError = GatewayDiscovery.revalidate(
        original, discoveryOptions)
    active = route({ gatewayAddress = "192.168.1.254" })
    local changed, changedError = GatewayDiscovery.revalidate(
        original, discoveryOptions)
    local tampered = {}
    for key, value in pairs(original) do tampered[key] = value end
    tampered.routeFingerprint = "route-v1-00000000"
    local invalidSnapshot, invalidSnapshotError =
        GatewayDiscovery.revalidate(tampered, discoveryOptions)
    check("gateway_discovery_revalidation_detects_route_changes_and_tampering",
        unchangedError == nil and unchanged ~= nil
        and unchanged.routeFingerprint == original.routeFingerprint
        and changed == false and changedError == "network_changed"
        and invalidSnapshot == nil
        and invalidSnapshotError == "invalid_snapshot")
end

return Test
