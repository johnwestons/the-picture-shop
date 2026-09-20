local GatewayDiscovery = require("src.net.gateway_discovery")
local GatewayNative = require("src.net.gateway_native")
local GatewayAndroid = require("src.net.gateway_android")

local Test = {}

local function route(overrides)
    local value = {
        family = 4,
        internalAddress = "192.168.1.50",
        gatewayAddress = "192.168.1.1",
        interfaceIndex = 7,
        routePrefixLength = 0,
        networkGeneration = "windows-route-v2-0000000000000001",
        ignoredProviderField = "must-not-cross-boundary",
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
end

local function provider(value)
    return function() return value end
end

local function androidRoute(overrides)
    local value = {
        family = 4,
        internalAddress = "192.168.1.50",
        gatewayAddress = "192.168.1.1",
        routePrefixLength = 0,
        networkGeneration =
            "android-route-v2-0000000000000001-00000001",
        ignoredProviderField = "must-not-cross-boundary",
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
end

function Test.run(_, check)
    local native, nativeError = GatewayNative.discover({
        invoke = function()
            return 0, "192.168.1.50", "192.168.1.1", 7,
                0x1234abcd, 0x89abcdef
        end,
    })
    check("gateway_native_exposes_only_the_bounded_ipv4_route_contract",
        nativeError == nil and native.family == 4
        and native.internalAddress == "192.168.1.50"
        and native.gatewayAddress == "192.168.1.1"
        and native.interfaceIndex == 7 and native.routePrefixLength == 0
        and native.networkGeneration ==
            "windows-route-v2-1234abcd89abcdef"
        and native.ignoredProviderField == nil
        and native.generationHigh == nil and native.generationLow == nil
        and GatewayNative.expectedAbiVersion == 2
        and GatewayNative.readOnly == true
        and GatewayNative.networkTrafficSent == false)

    local thrown, thrownError = GatewayNative.discover({
        invoke = function() error("invitation-secret-must-not-escape") end,
    })
    local badNative, badNativeError = GatewayNative.discover({
        invoke = function()
            return 0, "192.168.001.50", "192.168.1.1", 7, 0, 1
        end,
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

    local invalidNativeGenerations = true
    for _, generation in ipairs({
        { 0, 0 }, { -1, 1 }, { 1, -1 }, { 1.5, 1 }, { 1, 1.5 },
        { 4294967296, 1 }, { 1, 4294967296 },
    }) do
        local invalid, invalidError = GatewayNative.discover({
            invoke = function()
                return 0, "192.168.1.50", "192.168.1.1", 7,
                    generation[1], generation[2]
            end,
        })
        invalidNativeGenerations = invalidNativeGenerations
            and invalid == nil and invalidError == "invalid_native_route"
    end
    check("gateway_native_rejects_zero_fractional_and_out_of_range_generations",
        invalidNativeGenerations)

    local androidNative, androidNativeError = GatewayAndroid.discover({
        invoke = function()
            return 0, "100.64.1.2", "10.0.0.1",
                0x1234abcd, 0x89abcdef, 0x01020304
        end,
    })
    check("gateway_android_exposes_only_the_atomic_bounded_route_and_generation",
        androidNativeError == nil and androidNative.family == 4
        and androidNative.internalAddress == "100.64.1.2"
        and androidNative.gatewayAddress == "10.0.0.1"
        and androidNative.interfaceIndex == nil
        and androidNative.routePrefixLength == 0
        and androidNative.networkGeneration ==
            "android-route-v2-1234abcd89abcdef-01020304"
        and androidNative.networkHandleHigh == nil
        and androidNative.networkHandleLow == nil
        and androidNative.routeRevision == nil
        and GatewayAndroid.expectedAbiVersion == 2
        and GatewayAndroid.readOnly == true
        and GatewayAndroid.networkTrafficSent == false)

    local highZero = GatewayAndroid.discover({
        invoke = function()
            return 0, "192.168.1.2", "192.168.1.1", 0, 1, 1
        end,
    })
    local lowZero = GatewayAndroid.discover({
        invoke = function()
            return 0, "192.168.1.2", "192.168.1.1", 1, 0, 1
        end,
    })
    check("gateway_android_preserves_each_uint32_handle_half_exactly",
        highZero ~= nil and highZero.networkGeneration ==
            "android-route-v2-0000000000000001-00000001"
        and lowZero ~= nil and lowZero.networkGeneration ==
            "android-route-v2-0000000100000000-00000001")

    local androidStatusesFailClosed = true
    for _, status in ipairs({ -1, -2, -3, -99 }) do
        local statusRoute, statusError = GatewayAndroid.discover({
            invoke = function()
                return status, "invitation-secret", "raw-vpn-name",
                    1, 2, 7
            end,
        })
        androidStatusesFailClosed = androidStatusesFailClosed
            and statusRoute == nil
            and statusError == "android_gateway_unavailable"
            and not statusError:find("secret", 1, true)
            and not statusError:find("vpn", 1, true)
    end
    local androidThrown, androidThrownError = GatewayAndroid.discover({
        invoke = function() error("private-network-details") end,
    })
    check("gateway_android_sanitizes_every_native_failure_status_and_exception",
        androidStatusesFailClosed and androidThrown == nil
        and androidThrownError == "android_gateway_unavailable"
        and not androidThrownError:find("private", 1, true))

    local invalidAndroidNative = {
        { 0, "192.168.001.2", "192.168.1.1", 1, 2, 1 },
        { 0, "192.168.1.2", "192.168.001.1", 1, 2, 1 },
        { 0, "192.168.1.2", "192.168.1.1", 0, 0, 1 },
        { 0, "192.168.1.2", "192.168.1.1", -1, 2, 1 },
        { 0, "192.168.1.2", "192.168.1.1", 1.5, 2, 1 },
        { 0, "192.168.1.2", "192.168.1.1", 4294967296, 2, 1 },
        { 0, "192.168.1.2", "192.168.1.1", 1, -1, 1 },
        { 0, "192.168.1.2", "192.168.1.1", 1, 1.5, 1 },
        { 0, "192.168.1.2", "192.168.1.1", 1, 4294967296, 1 },
        { 0, "192.168.1.2", "192.168.1.1", 1, 2, 0 },
        { 0, "192.168.1.2", "192.168.1.1", 1, 2, -1 },
        { 0, "192.168.1.2", "192.168.1.1", 1, 2, 1.5 },
        { 0, "192.168.1.2", "192.168.1.1", 1, 2, 4294967296 },
    }
    local invalidAndroidNativeRejected = true
    for _, values in ipairs(invalidAndroidNative) do
        local invalidRoute, invalidError = GatewayAndroid.discover({
            invoke = function()
                return values[1], values[2], values[3], values[4], values[5],
                    values[6]
            end,
        })
        invalidAndroidNativeRejected = invalidAndroidNativeRejected
            and invalidRoute == nil and invalidError == "invalid_android_route"
    end
    check("gateway_android_rejects_noncanonical_or_out_of_range_success_output",
        invalidAndroidNativeRejected)

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
        and snapshot.networkGeneration ==
            "windows-route-v2-0000000000000001"
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

    local missingWindowsGeneration = route()
    missingWindowsGeneration.networkGeneration = nil
    local invalidCandidates = {
        false,
        {},
        route({ family = 6 }),
        route({ routePrefixLength = 24 }),
        route({ interfaceIndex = 0 }),
        route({ interfaceIndex = -1 }),
        route({ interfaceIndex = 1.5 }),
        route({ interfaceIndex = 4294967296 }),
        missingWindowsGeneration,
        route({ networkGeneration = false }),
        route({ networkGeneration = "windows-route-v2-0000000000000000" }),
        route({ networkGeneration = "windows-route-v2-000000000000000A" }),
        route({ networkGeneration = "windows-route-v1-0000000000000001" }),
        route({ networkGeneration = "windows-route-v2-000000000000001" }),
        route({ networkGeneration =
            "windows-route-v2-0000000000000001-extra" }),
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
    check("gateway_discovery_fails_closed_without_an_available_platform_provider",
        android == nil and androidError == "gateway_discovery_unavailable"
        and unsupported == nil and unsupportedError == "unsupported_platform")

    local androidSnapshot, androidSnapshotError = GatewayDiscovery.discover({
        platform = "Android",
        provider = provider(androidRoute()),
    })
    check("gateway_discovery_accepts_an_allowlisted_android_network_generation",
        androidSnapshotError == nil and androidSnapshot ~= nil
        and androidSnapshot.platform == "Android"
        and androidSnapshot.interfaceIndex == nil
        and androidSnapshot.networkGeneration ==
            "android-route-v2-0000000000000001-00000001"
        and type(androidSnapshot.routeFingerprint) == "string"
        and androidSnapshot.routeFingerprint:match(
            "^route%-v1%-%x%x%x%x%x%x%x%x$") ~= nil
        and androidSnapshot.ignoredProviderField == nil)

    local missingAndroidGeneration = androidRoute()
    missingAndroidGeneration.networkGeneration = nil
    local invalidAndroidGenerations = {
        missingAndroidGeneration,
        androidRoute({ networkGeneration = false }),
        androidRoute({
            networkGeneration =
                "android-route-v2-0000000000000000-00000001",
        }),
        androidRoute({
            networkGeneration =
                "android-route-v2-0000000000000001-00000000",
        }),
        androidRoute({ networkGeneration = "android-route-v2-1-1" }),
        androidRoute({
            networkGeneration =
                "android-route-v2-000000000000000g-00000001",
        }),
        androidRoute({
            networkGeneration =
                "android-route-v2-000000000000000A-00000001",
        }),
        androidRoute({
            networkGeneration =
                "android-route-v1-0000000000000001-00000001",
        }),
        androidRoute({
            networkGeneration =
                "android-route-v2-0000000000000001-00000001-extra",
        }),
        androidRoute({
            networkGeneration =
                "android-route-v2-0000000000000001_00000001",
        }),
        androidRoute({ interfaceIndex = 7 }),
        androidRoute({ internalAddress = "169.254.1.2" }),
    }
    local invalidAndroidGenerationsRejected = true
    for _, value in ipairs(invalidAndroidGenerations) do
        local invalidAndroid, invalidAndroidError = GatewayDiscovery.discover({
            platform = "Android",
            provider = provider(value),
        })
        invalidAndroidGenerationsRejected = invalidAndroidGenerationsRejected
            and invalidAndroid == nil
            and invalidAndroidError == "invalid_default_route"
    end
    check("gateway_discovery_rejects_invalid_android_generations_and_link_local_sources",
        invalidAndroidGenerationsRejected)

    local androidActive = androidRoute()
    local androidOptions = {
        platform = "Android",
        provider = function() return androidActive end,
    }
    local androidOriginal = GatewayDiscovery.discover(androidOptions)
    local androidUnchanged, androidUnchangedError =
        GatewayDiscovery.revalidate(androidOriginal, androidOptions)
    androidActive = androidRoute({
        networkGeneration =
            "android-route-v2-0000000000000002-00000001",
    })
    local androidHandleChanged, androidHandleChangedError =
        GatewayDiscovery.revalidate(androidOriginal, androidOptions)
    androidActive = androidRoute({
        networkGeneration =
            "android-route-v2-0000000000000001-00000002",
    })
    local androidRevisionChanged, androidRevisionChangedError =
        GatewayDiscovery.revalidate(androidOriginal, androidOptions)
    check("gateway_discovery_invalidates_the_same_android_tuple_on_a_new_network_handle",
        androidUnchangedError == nil and androidUnchanged ~= nil
        and androidUnchanged.routeFingerprint ==
            androidOriginal.routeFingerprint
        and androidHandleChanged == false
        and androidHandleChangedError == "network_changed")
    check("gateway_discovery_invalidates_the_same_android_network_on_a_new_route_revision",
        androidRevisionChanged == false
        and androidRevisionChangedError == "network_changed")

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

    local windowsGenerationOne = route({
        networkGeneration = "windows-route-v2-0000000000000001",
    })
    local windowsGenerationTwo = route({
        networkGeneration = "windows-route-v2-0000000000000002",
    })
    local windowsOriginal = GatewayDiscovery.discover({
        platform = "Windows", provider = provider(windowsGenerationOne),
    })
    local windowsStillCurrent, windowsGenerationError =
        GatewayDiscovery.revalidate(windowsOriginal, {
            platform = "Windows", provider = provider(windowsGenerationTwo),
        })
    check("gateway_discovery_invalidates_the_same_windows_tuple_on_an_os_network_change",
        windowsStillCurrent == false
        and windowsGenerationError == "network_changed"
        and windowsOriginal.networkGeneration ==
            "windows-route-v2-0000000000000001")
end

return Test
