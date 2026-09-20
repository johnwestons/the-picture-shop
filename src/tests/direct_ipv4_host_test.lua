local DirectIpv4Host = require("src.net.direct_ipv4_host")

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

local function mapped(address)
    local bytes = {}
    for value in address:gmatch("%d+") do bytes[#bytes + 1] = tonumber(value) end
    return string.rep("\0", 10) .. "\255\255" .. string.char(unpack(bytes))
end

local function pcpResponse(request, lifetime, epoch, address, port)
    return string.char(2, 129, 0, 0) .. u32(lifetime) .. u32(epoch)
        .. string.rep("\0", 12) .. request:sub(25, 36)
        .. string.char(17, 0, 0, 0) .. request:sub(41, 42)
        .. u16(port) .. mapped(address)
end

local function route()
    return {
        family = 4,
        platform = "Android",
        internalAddress = "192.168.70.20",
        gatewayAddress = "192.168.70.1",
        networkGeneration = "android-route-v2-0000000000000007-00000001",
        routeFingerprint = "route-v1-abcdef12",
    }
end

local function provider(log)
    return {
        productionReady = true,
        randomBytes = function(count)
            log[#log + 1] = { "entropy", count }
            return string.rep(string.char(count), count)
        end,
        admissionToken = function() return 123 end,
        newInitiator = function() return {} end,
        newResponder = function() return {} end,
    }
end

local function baseFactory(log)
    local factory = {}
    function factory.createHost(options)
        log[#log + 1] = { "listener_bind", options.bind, options.port }
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
            if self.closed then return true end
            self.closed = true
            log[#log + 1] = { "listener_close" }
            return true
        end
        return transport
    end
    function factory.createClient() return nil end
    return factory
end

local function mappingSocketFactory(routeValue, log)
    local factory = { exactNetworkBinding = true, sockets = {} }
    function factory.open()
        log[#log + 1] = { "mapping_socket_open" }
        local socket = { sent = {}, inbound = {}, closed = false }
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
            self.sent[#self.sent + 1] = packet
            log[#log + 1] = { "mapping_send", packet, address, port }
            return #packet
        end
        function socket:receivefrom()
            local item = table.remove(self.inbound, 1)
            if not item then return nil, "timeout" end
            return item.packet, routeValue.gatewayAddress, 5351
        end
        function socket:close()
            self.closed = true
            log[#log + 1] = { "mapping_socket_close" }
            return true
        end
        factory.sockets[#factory.sockets + 1] = socket
        return socket
    end
    return factory
end

local function eventIndex(log, name, start)
    for index = start or 1, #log do
        if log[index][1] == name then return index end
    end
    return nil
end

function Test.run(_, check)
    local now, log, activeRoute = 0, {}, route()
    local sockets = mappingSocketFactory(activeRoute, log)
    local productionHost = DirectIpv4Host.new({
        provider = provider({}),
        clock = function() return 0 end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function(snapshot) return snapshot end,
    })
    check("direct_ipv4_host_remains_behind_explicit_nonproduction_gate",
        productionHost == nil and DirectIpv4Host.productionReady == false)
    local host = assert(DirectIpv4Host.new({
        engineeringEnabled = true,
        provider = provider(log),
        baseFactory = baseFactory(log),
        socketFactory = sockets,
        clock = function() return now end,
        randomUnit = function() return 0.5 end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function(snapshot) return snapshot end,
        requestedLeaseSeconds = 120,
    }))
    local started = host:start(22123, { now = 0, requestedLifetime = 120 })
    local bindIndex = eventIndex(log, "listener_bind")
    local mappingOpenBeforeUpdate = eventIndex(log, "mapping_socket_open")
    host:update(0)
    local openIndex = eventIndex(log, "mapping_socket_open")
    local sendIndex = eventIndex(log, "mapping_send")
    local socket = sockets.sockets[1]
    local createRequest = socket.sent[1]
    check("direct_ipv4_host_orders_secure_listener_before_exact_mapping_socket_and_packet",
        started and bindIndex and mappingOpenBeforeUpdate == nil
        and openIndex and sendIndex and bindIndex < openIndex and openIndex < sendIndex
        and host:invitation() == nil)

    socket.inbound[1] = {
        packet = pcpResponse(createRequest, 120, 10, "8.8.8.8", 40123),
    }
    now = 1
    local readyState = host:update(now)
    local code = host:invitation()
    check("direct_ipv4_host_publishes_only_after_global_mapping_response",
        readyState == "ready" and type(code) == "string"
        and code:find("TPS1|8.8.8.8:40123|", 1, true) == 1)

    now = 2
    local verified = host:markVerified(now)
    check("direct_ipv4_host_marks_the_current_candidate_only_after_remote_proof",
        verified and host:status().remoteVerified == true)

    local factory = host:transportFactory()
    local transport = factory.createHost({
        bind = activeRoute.internalAddress,
        port = 22123,
    })
    now = 61
    host:update(now)
    local renewalSendIndex = eventIndex(log, "mapping_send", sendIndex + 1)
    local renewalRequest = socket.sent[2]
    socket.inbound[1] = {
        packet = pcpResponse(renewalRequest, 120, 71, "8.8.8.8", 40123),
    }
    now = 62
    host:update(now)
    local renewedStatus = host:status()
    check("direct_ipv4_host_exposes_mapping_renewal_for_acceptance_probes",
        renewedStatus.state == "ready" and renewedStatus.renewalCount == 1
        and renewedStatus.mappingMethod == "pcp"
        and renewedStatus.cleanupReason == nil
        and renewedStatus.listenerClosedBeforeCleanup == false
        and renewedStatus.remoteVerified == true)
    check("direct_ipv4_host_safe_status_omits_endpoint_and_invitation",
        renewedStatus.externalAddress == nil
        and renewedStatus.externalPort == nil
        and renewedStatus.invitationCode == nil)

    local stopped, cleanupRequired = host:stop()
    local closeIndex = eventIndex(log, "listener_close")
    now = 63
    host:update(now)
    local deleteIndex = eventIndex(log, "mapping_send", renewalSendIndex + 1)
    local deletionRequest = socket.sent[3]
    check("direct_ipv4_host_shutdown_closes_handed_listener_before_mapping_deletion",
        transport and transport.closed and stopped == false
        and cleanupRequired == true and host:invitation() == nil
        and closeIndex and deleteIndex and closeIndex < deleteIndex
        and deletionRequest:sub(5, 8) == u32(0))

    socket.inbound[1] = {
        packet = pcpResponse(deletionRequest, 0, 73, "0.0.0.0", 0),
    }
    now = 64
    local finalState = host:update(now)
    local finalStop, finalCleanup = host:stop()
    local finalStatus = host:status()
    check("direct_ipv4_host_waits_for_exact_delete_ack_before_final_cleanup",
        finalState == "stopped" and finalStop and finalCleanup == false
        and socket.closed
        and finalStatus.listenerClosedBeforeCleanup == true
        and finalStatus.cleanupReason == "deletion_acknowledged")
end

return Test
