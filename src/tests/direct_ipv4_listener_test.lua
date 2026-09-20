local DirectInvite = require("src.net.direct_invite")
local DirectIpv4Listener = require("src.net.direct_ipv4_listener")

local Test = {}

local function route()
    return {
        family = 4,
        platform = "Windows",
        internalAddress = "192.168.10.20",
        gatewayAddress = "192.168.10.1",
        interfaceIndex = 7,
        networkGeneration = "windows-route-v2-0000000000000001",
        routeFingerprint = "route-v1-12345678",
    }
end

local function provider(log)
    return {
        productionReady = true,
        randomBytes = function(count)
            log[#log + 1] = { "entropy", count }
            return string.rep("k", count)
        end,
        admissionToken = function(key)
            return key == string.rep("k", 32) and 12345 or nil
        end,
        newInitiator = function() return {} end,
        newResponder = function() return {} end,
    }
end

local function baseFactory(log)
    local factory = {}
    function factory.createHost(options)
        log[#log + 1] = { "bind", options.bind, options.port }
        local transport = {
            endpoint = options.bind .. ":" .. tostring(options.port),
            channels = options.channels,
            maxGuests = options.maxGuests,
            peerCapacity = 12,
            closed = false,
        }
        function transport:poll() return nil end
        function transport:send() return true end
        function transport:disconnect() return true end
        function transport:close()
            self.closed = true
            log[#log + 1] = { "close" }
            return true
        end
        return transport
    end
    function factory.createClient(address, options)
        log[#log + 1] = { "connect", address, options and options.connectData }
        return nil, "not used"
    end
    return factory
end

function Test.run(_, check)
    local log = {}
    local missingGeneration = route()
    missingGeneration.networkGeneration = nil
    local invalidListener = DirectIpv4Listener.open({
        route = missingGeneration,
        port = 22123,
        provider = provider(log),
        baseFactory = baseFactory(log),
    })
    check("direct_ipv4_listener_requires_the_windows_network_generation",
        invalidListener == nil and #log == 0)

    local listener, listenerError = DirectIpv4Listener.open({
        route = route(),
        port = 22123,
        provider = provider(log),
        baseFactory = baseFactory(log),
        clock = function() return 0 end,
    })
    check("direct_ipv4_listener_creates_encrypted_exact_address_listener_before_mapping",
        listenerError == nil and listener
        and log[1][1] == "entropy" and log[2][1] == "bind"
        and log[2][2] == "192.168.10.20" and log[2][3] == 22123
        and listener:invitation() == nil
        and DirectIpv4Listener.IPV6_POLICY == "separate_authenticated_listener")

    local mapping = listener and listener:mappingRequest(600, 0)
    check("direct_ipv4_listener_mapping_request_contains_route_and_port_but_no_secret",
        mapping and mapping.internalAddress == "192.168.10.20"
        and mapping.internalPort == 22123
        and mapping.gatewayAddress == "192.168.10.1"
        and mapping.suggestedExternalPort == 0
        and mapping.requestedLifetime == 600
        and mapping.key == nil and mapping.psk == nil and mapping.invitation == nil)

    local invalidPublished = listener:publish({
        externalAddress = "100.64.1.2", externalPort = 40000, method = "pcp",
    })
    local code = listener:publish({
        externalAddress = "8.8.4.4", externalPort = 40000, method = "pcp",
    })
    local parsed = DirectInvite.parse(code)
    check("direct_ipv4_listener_publishes_only_global_router_selected_endpoint_after_binding",
        invalidPublished == nil and parsed
        and parsed.endpoint == "8.8.4.4:40000"
        and parsed.psk == string.rep("k", 32)
        and listener:invitation() == code)

    local prepared = listener:transportFactory()
    local wildcard = prepared.createHost({ bind = "*", port = 22123 })
    local secureHost = prepared.createHost({
        bind = "192.168.10.20", port = 22123,
    })
    local secondTake = prepared.createHost({
        bind = "192.168.10.20", port = 22123,
    })
    check("direct_ipv4_listener_handoff_never_rebinds_wildcard_or_duplicates_listener",
        wildcard == nil and secureHost and secondTake == nil
        and listener:close() and secureHost.closed)
    secureHost:close()

    local clientLog = {}
    local client, endpoint = DirectIpv4Listener.clientFactory(code, {
        provider = provider(clientLog),
        baseFactory = baseFactory(clientLog),
        clock = function() return 0 end,
    })
    local rejectedIpv6 = DirectIpv4Listener.clientFactory(
        "TPS1|example.com:40000|" .. string.rep("6b", 32), {
            provider = provider({}), baseFactory = baseFactory({}),
        })
    check("direct_ipv4_listener_client_uses_only_global_ipv4_and_separate_ipv6_path",
        client and endpoint == "8.8.4.4:40000" and rejectedIpv6 == nil)
    if client then client.close() end

    local failLog = {}
    local failingBase = baseFactory(failLog)
    failingBase.createHost = function(options)
        failLog[#failLog + 1] = { "bind", "*", options.port }
        return {
            endpoint = "*:" .. tostring(options.port),
            poll = function() end,
            send = function() end,
            disconnect = function() end,
            close = function() return true end,
        }
    end
    local wildcardListener = DirectIpv4Listener.open({
        route = route(), port = 22123, provider = provider(failLog),
        baseFactory = failingBase,
    })
    check("direct_ipv4_listener_rejects_base_transport_that_did_not_bind_exact_address",
        wildcardListener == nil)
end

return Test
