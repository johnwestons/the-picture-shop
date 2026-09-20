local RouterMappingAdapter = require("src.net.router_mapping_adapter")

local Test = {}

local function u16(value)
    return string.char(math.floor(value / 256) % 256, value % 256)
end

local function u32(value)
    return string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256)
end

local function ipv4Mapped(address)
    local values = {}
    for value in address:gmatch("%d+") do values[#values + 1] = tonumber(value) end
    return string.rep("\0", 10) .. "\255\255" .. string.char(unpack(values))
end

local function pcpResponse(request, lifetime, epoch, address, port)
    return string.char(2, 129, 0, 0) .. u32(lifetime) .. u32(epoch)
        .. string.rep("\0", 12)
        .. request:sub(25, 36) .. string.char(17, 0, 0, 0)
        .. request:sub(41, 42) .. u16(port) .. ipv4Mapped(address)
end

local function natExternalResponse(address, epoch)
    local values = {}
    for value in address:gmatch("%d+") do values[#values + 1] = tonumber(value) end
    return string.char(0, 128) .. u16(0) .. u32(epoch)
        .. string.char(unpack(values))
end

local function natMapResponse(request, externalPort, lifetime, epoch)
    return string.char(0, 129) .. u16(0) .. u32(epoch)
        .. request:sub(5, 6) .. u16(externalPort) .. u32(lifetime)
end

local function route(overrides)
    local value = {
        family = 4,
        platform = "Android",
        internalAddress = "192.168.50.20",
        gatewayAddress = "192.168.50.1",
        networkGeneration = "android-route-v2-0000000000000001-00000001",
        routeFingerprint = "route-v1-a1b2c3d4",
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
end

local function request()
    return {
        internalAddress = "192.168.50.20",
        internalPort = 22123,
        gatewayAddress = "192.168.50.1",
        suggestedExternalPort = 22123,
        requestedLifetime = 120,
    }
end

local function fakeSocketFactory(routeValue, log)
    local factory = { exactNetworkBinding = true, sockets = {} }
    function factory.open(selected)
        log[#log + 1] = { "open", selected.internalAddress,
            selected.gatewayAddress, selected.networkGeneration }
        local socket = { inbound = {}, sent = {}, closed = false }
        function socket:bindingProof()
            return {
                family = 4,
                internalAddress = routeValue.internalAddress,
                gatewayAddress = routeValue.gatewayAddress,
                networkGeneration = routeValue.networkGeneration,
                routeFingerprint = routeValue.routeFingerprint,
                exactNetworkBinding = true,
            }
        end
        function socket:sendto(packet, address, port)
            self.sent[#self.sent + 1] = {
                packet = packet, address = address, port = port,
            }
            log[#log + 1] = { "send", packet:byte(1), packet:byte(2),
                address, port }
            return #packet
        end
        function socket:receivefrom()
            local item = table.remove(self.inbound, 1)
            if not item then return nil, "timeout" end
            return item.packet, item.address, item.port
        end
        function socket:close()
            self.closed = true
            log[#log + 1] = { "close" }
            return true
        end
        factory.sockets[#factory.sockets + 1] = socket
        return socket
    end
    return factory
end

local function entropy(count)
    return string.rep(string.char(count), count)
end

local function adapterOptions(activeRoute, log)
    local socketFactory = fakeSocketFactory(activeRoute, log)
    return {
        route = activeRoute,
        socketFactory = socketFactory,
        randomBytes = entropy,
        randomUnit = function() return 0.5 end,
        revalidate = function(snapshot)
            if activeRoute.changed then return false, "network_changed" end
            return snapshot
        end,
    }, socketFactory
end

function Test.run(_, check)
    local pcpRoute, pcpLog = route(), {}
    local pcpOptions, pcpSockets = adapterOptions(pcpRoute, pcpLog)
    local methods = assert(RouterMappingAdapter.new(pcpOptions))
    local pcp = methods[1]
    local handle = assert(pcp:start(request()))
    check("router_mapping_adapter_constructor_is_side_effect_free",
        #pcpLog == 0 and #pcpSockets.sockets == 0
        and pcp.name == "pcp" and pcp.attemptTimeoutSeconds == false)

    local noEvent = handle:update(10)
    local pcpSocket = pcpSockets.sockets[1]
    local firstPcp = pcpSocket and pcpSocket.sent[1]
    check("router_mapping_adapter_binds_exact_route_before_sending_pcp",
        noEvent == nil and #pcpLog >= 2
        and pcpLog[1][1] == "open" and pcpLog[2][1] == "send"
        and firstPcp.address == pcpRoute.gatewayAddress
        and firstPcp.port == 5351 and firstPcp.packet:byte(1) == 2
        and firstPcp.packet:byte(2) == 1
        and firstPcp.packet:sub(25, 36) == string.rep(string.char(12), 12))

    pcpSocket.inbound[#pcpSocket.inbound + 1] = {
        packet = pcpResponse(firstPcp.packet, 120, 100, "8.8.8.8", 32123),
        address = "192.168.50.99", port = 5351,
    }
    pcpSocket.inbound[#pcpSocket.inbound + 1] = {
        packet = pcpResponse(firstPcp.packet, 120, 100, "8.8.8.8", 32123),
        address = pcpRoute.gatewayAddress, port = 5351,
    }
    local mapped = handle:update(11)
    check("router_mapping_adapter_discards_forged_source_and_accepts_exact_pcp_reply",
        mapped and mapped.kind == "mapped"
        and mapped.externalAddress == "8.8.8.8"
        and mapped.externalPort == 32123 and mapped.lifetime == 120)

    local renewed = handle:renew(70)
    handle:update(70)
    local renewal = pcpSocket.sent[2]
    check("router_mapping_adapter_renews_pcp_with_owned_nonce_and_assigned_endpoint",
        renewed and renewal and renewal.packet:sub(25, 36)
            == firstPcp.packet:sub(25, 36)
        and renewal.packet:sub(43, 44) == u16(32123)
        and renewal.packet:sub(57, 60) == string.char(8, 8, 8, 8))
    pcpSocket.inbound[#pcpSocket.inbound + 1] = {
        packet = pcpResponse(renewal.packet, 120, 159, "8.8.8.8", 32123),
        address = pcpRoute.gatewayAddress, port = 5351,
    }
    local renewedEvent = handle:update(71)
    local deletePending = handle:delete(72)
    handle:update(72)
    local deletion = pcpSocket.sent[3]
    pcpSocket.inbound[#pcpSocket.inbound + 1] = {
        packet = pcpResponse(deletion.packet, 0, 161, "0.0.0.0", 0),
        address = pcpRoute.gatewayAddress, port = 5351,
    }
    local deleted = handle:update(73)
    local pcpClosed = handle:close()
    check("router_mapping_adapter_renews_and_deletes_only_exact_owned_pcp_mapping",
        renewedEvent and renewedEvent.kind == "mapped"
        and deletePending == nil and deletion.packet:sub(5, 8) == u32(0)
        and deleted and deleted.kind == "deleted"
        and pcpClosed and pcpSocket.closed)

    local natRoute, natLog = route({
        networkGeneration = "android-route-v2-0000000000000002-00000001",
        routeFingerprint = "route-v1-11223344",
    }), {}
    local natOptions, natSockets = adapterOptions(natRoute, natLog)
    local natMethods = assert(RouterMappingAdapter.new(natOptions))
    local nat = natMethods[2]
    local natHandle = assert(nat:start(request()))
    natHandle:update(0)
    local natSocket = natSockets.sockets[1]
    local externalRequest = natSocket.sent[1]
    natSocket.inbound[#natSocket.inbound + 1] = {
        packet = natExternalResponse("1.1.1.1", 50),
        address = natRoute.gatewayAddress, port = 5351,
    }
    local externalEvent = natHandle:update(0.1)
    local stillSerialized = #natSocket.sent == 1
    natHandle:update(0.2)
    local mapRequest = natSocket.sent[2]
    natSocket.inbound[#natSocket.inbound + 1] = {
        packet = natMapResponse(mapRequest.packet, 40123, 120, 51),
        address = natRoute.gatewayAddress, port = 5351,
    }
    local natMapped = natHandle:update(0.3)
    check("router_mapping_adapter_serializes_nat_pmp_address_then_mapping",
        externalEvent == nil and stillSerialized
        and externalRequest.packet == string.char(0, 0)
        and mapRequest.packet:byte(2) == 1
        and natMapped and natMapped.kind == "mapped"
        and natMapped.externalAddress == "1.1.1.1"
        and natMapped.externalPort == 40123)

    natRoute.changed = true
    local sendsBeforeUnsafeDelete = #natSocket.sent
    local unsafeDelete = natHandle:delete(1)
    check("router_mapping_adapter_refuses_nat_pmp_deletion_after_network_generation_changes",
        unsafeDelete == false and #natSocket.sent == sendsBeforeUnsafeDelete
        and natHandle:close() == false)

    local cgnRoute, cgnLog = route({
        networkGeneration = "android-route-v2-0000000000000003-00000001",
        routeFingerprint = "route-v1-55667788",
    }), {}
    local cgnOptions, cgnSockets = adapterOptions(cgnRoute, cgnLog)
    local cgnHandle = assert((assert(RouterMappingAdapter.new(cgnOptions)))[2]
        :start(request()))
    cgnHandle:update(0)
    local cgnSocket = cgnSockets.sockets[1]
    cgnSocket.inbound[1] = {
        packet = natExternalResponse("100.64.10.2", 20),
        address = cgnRoute.gatewayAddress, port = 5351,
    }
    local cgnFailed = cgnHandle:update(0.1)
    check("router_mapping_adapter_stops_before_nat_pmp_mapping_behind_cgnat",
        cgnFailed and cgnFailed.kind == "failed" and #cgnSocket.sent == 1)

    local badRoute, badLog = route({
        networkGeneration = "android-route-v2-0000000000000004-00000001",
        routeFingerprint = "route-v1-99aabbcc",
    }), {}
    local badOptions, badSockets = adapterOptions(badRoute, badLog)
    badOptions.socketFactory = fakeSocketFactory(route({
        networkGeneration = "android-route-v2-0000000000000099-00000001",
        routeFingerprint = "route-v1-99aabbcc",
    }), badLog)
    local badHandle = assert((assert(RouterMappingAdapter.new(badOptions)))[1]
        :start(request()))
    local badEvent = badHandle:update(0)
    check("router_mapping_adapter_rejects_mismatched_socket_binding_proof_before_send",
        badEvent and badEvent.kind == "failed"
        and badOptions.socketFactory.sockets[1].closed
        and #badOptions.socketFactory.sockets[1].sent == 0)

    local versionRoute, versionLog = route({
        networkGeneration = "android-route-v2-0000000000000005-00000001",
        routeFingerprint = "route-v1-ddeeff00",
    }), {}
    local versionOptions, versionSockets = adapterOptions(versionRoute, versionLog)
    local versionHandle = assert((assert(RouterMappingAdapter.new(versionOptions)))[1]
        :start(request()))
    versionHandle:update(0)
    local versionSocket = versionSockets.sockets[1]
    versionSocket.inbound[1] = {
        packet = string.char(0, 0, 0, 1) .. u32(77),
        address = versionRoute.gatewayAddress,
        port = 5351,
    }
    local unsupported = versionHandle:update(0.1)
    check("router_mapping_adapter_recognizes_nat_pmp_version_reply_and_falls_back_without_delete",
        unsupported and unsupported.kind == "failed"
        and versionHandle:delete(0.1) == true
        and #versionSocket.sent == 1 and versionHandle:close())

    local publicRoute = route({
        internalAddress = "8.8.8.8",
        networkGeneration = "android-route-v2-0000000000000006-00000001",
        routeFingerprint = "route-v1-10203040",
    })
    local publicOptions = adapterOptions(publicRoute, {})
    local publicNat = (assert(RouterMappingAdapter.new(publicOptions)))[2]
    local publicRequest = request()
    publicRequest.internalAddress = publicRoute.internalAddress
    check("router_mapping_adapter_restricts_legacy_nat_pmp_to_rfc1918_source",
        publicNat:start(publicRequest) == nil)

    local windowsRoute = route({
        platform = "Windows",
        interfaceIndex = 7,
        networkGeneration = "windows-route-v2-0000000000000001",
        routeFingerprint = "route-v1-20304050",
    })
    local windowsOptions = adapterOptions(windowsRoute, {})
    local windowsMethods = RouterMappingAdapter.new(windowsOptions)
    local missingGeneration = route({
        platform = "Windows",
        interfaceIndex = 7,
        routeFingerprint = "route-v1-20304050",
    })
    missingGeneration.networkGeneration = nil
    local rejected, rejectedError = RouterMappingAdapter.new(
        adapterOptions(missingGeneration, {}))
    check("router_mapping_adapter_requires_windows_generation_before_mapping",
        windowsMethods ~= nil and #windowsMethods == 3
        and windowsMethods[3].name == "upnp_igd"
        and windowsMethods[3].attemptTimeoutSeconds == false and rejected == nil
        and rejectedError == "invalid_route")
end

return Test
