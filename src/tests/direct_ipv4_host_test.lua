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
        routePrefixLength = 24,
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
    local routeRevalidationCount = 0
    local sockets = mappingSocketFactory(activeRoute, log)
    local productionHost = DirectIpv4Host.new({
        provider = provider({}),
        clock = function() return 0 end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function(snapshot) return snapshot end,
    })
    check("direct_ipv4_host_remains_behind_explicit_nonproduction_gate",
        productionHost == nil and DirectIpv4Host.productionReady == false)
    DirectIpv4Host.productionReady = true
    local explicitlyReadyHost = DirectIpv4Host.new({
        provider = provider({}),
        clock = function() return 0 end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function(snapshot) return snapshot end,
    })
    DirectIpv4Host.productionReady = false
    check("direct_ipv4_host_accepts_app_construction_only_after_explicit_readiness",
        explicitlyReadyHost ~= nil and DirectIpv4Host.productionReady == false)
    local host = assert(DirectIpv4Host.new({
        engineeringEnabled = true,
        provider = provider(log),
        baseFactory = baseFactory(log),
        socketFactory = sockets,
        clock = function() return now end,
        randomUnit = function() return 0.5 end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function(snapshot)
            routeRevalidationCount = routeRevalidationCount + 1
            return snapshot
        end,
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

    local attachedOptions, transport
    local compositeController = {
        attachFactory = function(_, factory, createOptions)
            attachedOptions = createOptions
            transport = factory.createHost(createOptions)
            if not transport then return nil, "test_attach_failed" end
            return { index = 1 }
        end,
    }
    local revalidationsBeforeAttach = routeRevalidationCount
    local attachedHandle, attachError = host:attachToSession(compositeController)
    local duplicateHandle, duplicateError = host:attachToSession(compositeController)
    check("direct_ipv4_host_attaches_only_to_its_revalidated_exact_listener_endpoint",
        attachedHandle and attachedOptions
        and attachedOptions.bind == activeRoute.internalAddress
        and attachedOptions.port == 22123
        and attachedOptions.channels == 3
        and routeRevalidationCount == revalidationsBeforeAttach + 1
        and transport and transport.endpoint == activeRoute.internalAddress .. ":22123"
        and host:status().attachedToSession == true
        and duplicateHandle == nil
        and duplicateError == "Direct IPv4 listener is already attached to a session."
        and attachError == nil)
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
        and renewedStatus.attachedToSession == true
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

    local manualNow, manualLog = 0, {}
    local manualHost = assert(DirectIpv4Host.new({
        engineeringEnabled = true,
        manualOnly = true,
        provider = provider(manualLog),
        baseFactory = baseFactory(manualLog),
        clock = function() return manualNow end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function(snapshot) return snapshot end,
    }))
    local manualStarted = manualHost:startManualSetup(22129, {
        externalAddress = "8.8.8.8",
        externalPort = 40129,
        lifetimeSeconds = 120,
    })
    local manualState = manualHost:update(manualNow)
    local manualDetails = manualHost:manualSetupDetails()
    local manualInvitation = manualHost:invitation()
    local manualConfirmed, manualCode = manualHost:confirmManualSetup(manualNow)
    local publishedManualInvitation = manualHost:invitation()
    local earlyManualAck, earlyManualAckError =
        manualHost:acknowledgeManualCleanup()
    local manualStop, manualCleanupRequired = manualHost:stop()
    local pendingManualStatus = manualHost:status()
    local retryStop, retryCleanupRequired = manualHost:stop()
    local manualAck = manualHost:acknowledgeManualCleanup()
    local finishedManualStatus = manualHost:status()
    check("direct_ipv4_manual_cleanup_requires_closed_listener_and_explicit_ack",
        manualStarted and manualState == "manual_setup"
        and manualDetails and manualDetails.internalAddress == activeRoute.internalAddress
        and manualDetails.internalPort == 22129
        and manualDetails.externalAddress == "8.8.8.8"
        and manualDetails.externalPort == 40129
        and manualInvitation == nil
        and manualHost:invitation() == nil
        and manualConfirmed and type(manualCode) == "string"
        and manualCode:find("TPS1|8.8.8.8:40129|", 1, true) == 1
        and publishedManualInvitation == manualCode
        and not earlyManualAck and earlyManualAckError == "host_must_stop_first"
        and manualStop == false and manualCleanupRequired == true
        and pendingManualStatus.state == "cleanup_required"
        and pendingManualStatus.cleanupRequired == true
        and pendingManualStatus.cleanupKind == "manual"
        and pendingManualStatus.listenerClosedBeforeCleanup == true
        and not retryStop and retryCleanupRequired
        and manualAck == true
        and finishedManualStatus.state == "stopped"
        and finishedManualStatus.cleanupRequired == false
        and eventIndex(manualLog, "mapping_socket_open") == nil,
        "started=" .. tostring(manualStarted)
            .. " state=" .. tostring(manualState)
            .. " details=" .. tostring(manualDetails ~= nil)
            .. " invite=" .. tostring(manualInvitation)
            .. " confirmed=" .. tostring(manualConfirmed)
            .. " earlyAck=" .. tostring(earlyManualAck)
            .. "/" .. tostring(earlyManualAckError)
            .. " stop=" .. tostring(manualStop)
            .. "/" .. tostring(manualCleanupRequired)
            .. " pending=" .. tostring(pendingManualStatus.state)
            .. "/" .. tostring(pendingManualStatus.cleanupKind)
            .. "/" .. tostring(pendingManualStatus.listenerClosedBeforeCleanup)
            .. " retry=" .. tostring(retryStop)
            .. "/" .. tostring(retryCleanupRequired)
            .. " ack=" .. tostring(manualAck)
            .. " final=" .. tostring(finishedManualStatus.state)
            .. "/" .. tostring(finishedManualStatus.cleanupRequired))

    local expiringNow, expiringLog = 0, {}
    local expiringManualHost = assert(DirectIpv4Host.new({
        engineeringEnabled = true,
        manualOnly = true,
        provider = provider(expiringLog),
        baseFactory = baseFactory(expiringLog),
        clock = function() return expiringNow end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function(snapshot) return snapshot end,
    }))
    local expiringStarted = expiringManualHost:startManualSetup(22131, {
        externalAddress = "8.8.4.4",
        externalPort = 40131,
        lifetimeSeconds = 1,
    })
    expiringManualHost:update(expiringNow)
    local expiringConfirmed = expiringManualHost:confirmManualSetup(expiringNow)
    expiringNow = 1
    local expiredState = expiringManualHost:update(expiringNow)
    local expiredStatus = expiringManualHost:status()
    local expiredStop, expiredCleanup = expiringManualHost:stop()
    local expiredCleanupDetails = expiringManualHost:manualCleanupDetails()
    local expiredAck = expiringManualHost:acknowledgeManualCleanup()
    check("direct_ipv4_manual_expiry_revokes_invite_and_retains_cleanup_obligation",
        expiringStarted and expiringConfirmed and expiredState == "cleanup_required"
        and expiringManualHost:invitation() == nil
        and expiredStatus.cleanupRequired == true
        and expiredStatus.cleanupKind == "manual"
        and expiredStatus.listenerClosedBeforeCleanup == true
        and not expiredStop and expiredCleanup
        and expiredCleanupDetails
        and expiredCleanupDetails.internalAddress == activeRoute.internalAddress
        and expiredAck == true
        and expiringManualHost:status().cleanupRequired == false
        and eventIndex(expiringLog, "mapping_socket_open") == nil)

    local routeChangedNow, routeChanged = 0, false
    local routeChangeLog = {}
    local routeChangeHost = assert(DirectIpv4Host.new({
        engineeringEnabled = true,
        manualOnly = true,
        provider = provider(routeChangeLog),
        baseFactory = baseFactory(routeChangeLog),
        clock = function() return routeChangedNow end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function(snapshot)
            if not routeChanged then return snapshot end
            local changed = route()
            changed.networkGeneration = "android-route-v2-0000000000000008-00000001"
            changed.routeFingerprint = "route-v1-fedcba98"
            return changed
        end,
    }))
    local routeChangeStarted = routeChangeHost:startManualSetup(22132, {
        externalAddress = "8.8.8.8",
        externalPort = 40132,
        lifetimeSeconds = 120,
    })
    local routeChangeConfirmed = routeChangeHost:confirmManualSetup(0)
    routeChanged = true
    routeChangedNow = 1
    local routeChangeState, routeChangeError = routeChangeHost:update(routeChangedNow)
    local routeChangeCleanup = routeChangeHost:manualCleanupDetails()
    local routeChangeAck = routeChangeHost:acknowledgeManualCleanup()
    check("direct_ipv4_manual_host_revokes_invitation_and_requires_rule_cleanup_after_route_change",
        routeChangeStarted and routeChangeConfirmed
        and routeChangeState == "cleanup_required"
        and routeChangeError == "The IPv4 network changed; Direct hosting was stopped safely."
        and routeChangeHost:invitation() == nil
        and routeChangeHost.listener.closed == true
        and routeChangeCleanup
        and routeChangeCleanup.externalPort == 40132
        and routeChangeAck == true
        and routeChangeHost:status().cleanupRequired == false
        and eventIndex(routeChangeLog, "mapping_socket_open") == nil)

    local autoRouteNow, autoRouteChanged = 0, false
    local autoRouteLog = {}
    local autoRouteSockets = mappingSocketFactory(activeRoute, autoRouteLog)
    local autoRouteHost = assert(DirectIpv4Host.new({
        engineeringEnabled = true,
        provider = provider(autoRouteLog),
        baseFactory = baseFactory(autoRouteLog),
        socketFactory = autoRouteSockets,
        clock = function() return autoRouteNow end,
        randomUnit = function() return 0.5 end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function(snapshot)
            if autoRouteChanged then return nil, "network_changed" end
            return snapshot
        end,
        requestedLeaseSeconds = 120,
    }))
    local autoRouteStarted = autoRouteHost:start(22134,
        { now = 0, requestedLifetime = 120 })
    autoRouteHost:update(0)
    local autoRouteSocket = autoRouteSockets.sockets[1]
    local autoCreateRequest = autoRouteSocket.sent[1]
    autoRouteSocket.inbound[1] = {
        packet = pcpResponse(autoCreateRequest, 120, 10, "8.8.8.8", 40134),
    }
    autoRouteNow = 1
    local autoRouteReady = autoRouteHost:update(autoRouteNow)
    autoRouteChanged = true
    autoRouteNow = 2
    local autoRouteState = autoRouteHost:update(autoRouteNow)
    local autoListenerClose = eventIndex(autoRouteLog, "listener_close")
    local autoCreateSend = eventIndex(autoRouteLog, "mapping_send")
    local autoDeleteSend = autoCreateSend
        and eventIndex(autoRouteLog, "mapping_send", autoCreateSend + 1)
    autoRouteChanged = false
    autoRouteNow = 121
    local autoLeaseExpiredState = autoRouteHost:update(autoRouteNow)
    local autoRouteStop, autoRouteCleanup = autoRouteHost:stop()
    check("direct_ipv4_automatic_host_closes_on_route_change_and_retains_finite_mapping_cleanup",
        autoRouteStarted and autoRouteReady == "ready"
        and autoRouteState == "cleanup_required"
        and autoRouteHost:invitation() == nil
        and autoRouteHost.listener.closed == true
        and autoListenerClose and not autoDeleteSend
        and autoRouteHost:status().cleanupRequired == false
        and autoLeaseExpiredState == "stopped"
        and autoRouteStop == true and autoRouteCleanup == false
        and autoRouteSocket.closed == true)

    local staleHost = assert(DirectIpv4Host.new({
        engineeringEnabled = true,
        manualOnly = true,
        provider = provider({}),
        baseFactory = baseFactory({}),
        clock = function() return 0 end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function()
            local changed = route()
            changed.routePrefixLength = 25
            return changed
        end,
    }))
    local staleStarted = staleHost:startManualSetup(22133, {
        externalAddress = "8.8.8.8",
        externalPort = 40133,
        lifetimeSeconds = 120,
    })
    local staleListener = staleHost.listener
    local staleListenerClose = staleListener.close
    local staleCloseAttempts = 0
    function staleListener:close(...)
        staleCloseAttempts = staleCloseAttempts + 1
        if staleCloseAttempts == 1 then return false end
        return staleListenerClose(self, ...)
    end
    staleHost:update(0)
    local staleFirstStatus = staleHost:status()
    staleHost:update(0.5)
    local staleCloseRetryWasThrottled = staleCloseAttempts == 1
    staleHost:update(1)
    local staleRouteStatus = staleHost:status()
    local staleListenerClosedBeforeConfirm = staleListener.closed == true
    local staleCloseAttemptsAfterRetry = staleCloseAttempts
    local staleConfirmed, staleError = staleHost:confirmManualSetup(0)
    local staleCleanupDetails = staleHost:manualCleanupDetails()
    local staleCleanup = staleHost:acknowledgeManualCleanup()
    check("direct_ipv4_manual_setup_retries_unverified_route_change_close_and_preserves_rule_cleanup_choice",
        staleStarted and staleConfirmed == false
        and staleError == "network_changed"
        and staleFirstStatus.manualRouteInvalidated == true
        and staleFirstStatus.listenerClosedBeforeCleanup == false
        and staleCloseRetryWasThrottled
        and staleCloseAttemptsAfterRetry == 2
        and staleRouteStatus.manualRouteInvalidated == true
        and staleListenerClosedBeforeConfirm
        and staleHost:invitation() == nil
        and staleHost:status().listenerClosedBeforeCleanup == true
        and staleCleanupDetails
        and staleCleanupDetails.externalPort == 40133
        and staleCleanup == true)

    local confirmStaleHost = assert(DirectIpv4Host.new({
        engineeringEnabled = true,
        manualOnly = true,
        provider = provider({}),
        baseFactory = baseFactory({}),
        clock = function() return 0 end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function()
            local changed = route()
            changed.routePrefixLength = 25
            return changed
        end,
    }))
    local confirmStaleStarted = confirmStaleHost:startManualSetup(22132, {
        externalAddress = "8.8.8.8",
        externalPort = 40132,
        lifetimeSeconds = 120,
    })
    local confirmStaleListener = confirmStaleHost.listener
    local confirmStale, confirmStaleError = confirmStaleHost:confirmManualSetup(0)
    local confirmStaleCleanup = confirmStaleHost:manualCleanupDetails()
    local confirmStaleAcknowledged = confirmStaleHost:acknowledgeManualCleanup()
    check("direct_ipv4_manual_confirmation_revalidates_route_before_any_update_tick",
        confirmStaleStarted and confirmStale == false
        and confirmStaleError == "network_changed"
        and confirmStaleHost:status().manualRouteInvalidated == true
        and confirmStaleListener.closed == true
        and confirmStaleHost:invitation() == nil
        and confirmStaleCleanup and confirmStaleCleanup.externalPort == 40132
        and confirmStaleAcknowledged == true)

    local failedCloseLog = {}
    local failedCloseFactory = baseFactory(failedCloseLog)
    local createHost = failedCloseFactory.createHost
    function failedCloseFactory.createHost(options)
        local transport = createHost(options)
        local closeCount = 0
        function transport:close()
            closeCount = closeCount + 1
            if closeCount == 1 then
                failedCloseLog[#failedCloseLog + 1] = { "listener_close_unverified" }
                return false
            end
            return true
        end
        return transport
    end
    local setupFailureHost = assert(DirectIpv4Host.new({
        engineeringEnabled = true,
        manualOnly = true,
        provider = provider(failedCloseLog),
        baseFactory = failedCloseFactory,
        clock = function() return 0 end,
        discoverRoute = function() return activeRoute end,
        revalidateRoute = function(snapshot) return snapshot end,
        maxLeaseSeconds = 0,
    }))
    local setupFailed, setupError = setupFailureHost:start(22135)
    local retainedListener = setupFailureHost.listener
    local retainedTransport = retainedListener and retainedListener.transport
    local retryCleanup, retryCleanupKind = setupFailureHost:stop()
    check("direct_ipv4_failed_setup_retains_unverified_listener_ownership",
        setupFailed == false and type(setupError) == "string"
        and setupFailureHost:status().state == "cleanup_required"
        and retainedListener ~= nil and retainedListener.closed == true
        and retainedListener.closeOk == false and retainedTransport ~= nil
        and retryCleanup == false and retryCleanupKind == true
        and setupFailureHost.listener == retainedListener
        and setupFailureHost.listener.transport == retainedTransport)

    local publishLog, publishNow = {}, 0
    local publishRoute = route()
    local publishSockets = mappingSocketFactory(publishRoute, publishLog)
    local publishHost = assert(DirectIpv4Host.new({
        engineeringEnabled = true,
        provider = provider(publishLog),
        baseFactory = baseFactory(publishLog),
        socketFactory = publishSockets,
        clock = function() return publishNow end,
        discoverRoute = function() return publishRoute end,
        revalidateRoute = function(snapshot) return snapshot end,
        requestedLeaseSeconds = 120,
    }))
    local publishStarted = publishHost:start(22136,
        { now = 0, requestedLifetime = 120 })
    publishHost:update(0)
    local publishSocket = publishSockets.sockets[1]
    local publishRequest = publishSocket and publishSocket.sent[1]
    local publishListener = publishHost.listener
    local originalTransportClose = publishListener.transport.close
    local transportCloseAttempts = 0
    function publishListener.transport:close(...)
        transportCloseAttempts = transportCloseAttempts + 1
        if transportCloseAttempts <= 4 then
            publishLog[#publishLog + 1] = { "listener_close_unverified" }
            return false
        end
        return originalTransportClose(self, ...)
    end
    function publishListener:publish()
        return nil, "injected_publish_failure"
    end
    publishSocket.inbound[1] = {
        packet = pcpResponse(publishRequest, 120, 10, "8.8.8.8", 40136),
    }
    publishNow = 1
    local publishFailureState = publishHost:update(publishNow)
    local failedCloseIndex = eventIndex(publishLog, "listener_close_unverified")
    local failedRetryStop, failedRetryCleanup = publishHost:stop()
    publishNow = 70
    publishHost:update(publishNow)
    publishHost:update(publishNow)
    local mappingTrafficBeforeCloseRetry = publishSocket.sent[2] ~= nil
    local retryStop, retryCleanup = publishHost:stop()
    local verifiedCloseIndex = eventIndex(publishLog, "listener_close")
    local firstMappingSendIndex = eventIndex(publishLog, "mapping_send")
    local deleteRequestIndex = firstMappingSendIndex
        and eventIndex(publishLog, "mapping_send", firstMappingSendIndex + 1)
    publishNow = 71
    publishHost:update(publishNow)
    deleteRequestIndex = firstMappingSendIndex
        and eventIndex(publishLog, "mapping_send", firstMappingSendIndex + 1)
    local deleteRequest = publishSocket.sent[2]
    check("direct_ipv4_failed_publication_blocks_mapping_traffic_until_listener_close",
        publishStarted and publishRequest and publishFailureState == "cleanup_required"
        and publishHost:invitation() == nil
        and failedCloseIndex and not mappingTrafficBeforeCloseRetry
        and failedRetryStop == false and failedRetryCleanup == true
        and retryStop == false and retryCleanup == true
        and transportCloseAttempts == 5 and verifiedCloseIndex
        and deleteRequestIndex and verifiedCloseIndex < deleteRequestIndex
        and deleteRequest and deleteRequest:sub(5, 8) == u32(0))
    publishSocket.inbound[1] = {
        packet = pcpResponse(deleteRequest, 0, 80, "0.0.0.0", 0),
    }
    publishNow = 72
    local publishFinalState = publishHost:update(publishNow)
    local publishFinalStop, publishFinalCleanup = publishHost:stop()
    check("direct_ipv4_failed_publication_finishes_mapping_cleanup_after_ack",
        publishFinalState == "stopped" and publishFinalStop
        and publishFinalCleanup == false and publishSocket.closed
        and publishHost:status().listenerClosedBeforeCleanup == true)
end

return Test
