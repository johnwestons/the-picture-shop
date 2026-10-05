-- Ordered IPv4 Direct-host lifecycle: discover route, bind encrypted listener,
-- create/renew a finite mapping, then publish an invitation.  Shutdown always
-- closes the game listener before requesting mapping deletion.
local DirectIpv4Listener = require("src.net.direct_ipv4_listener")
local GatewayDiscovery = require("src.net.gateway_discovery")
local IpScope = require("src.net.ip_scope")
local Reachability = require("src.net.reachability")
local RouterMappingAdapter = require("src.net.router_mapping_adapter")

local DirectIpv4Host = {
    productionReady = false,
}
DirectIpv4Host.__index = DirectIpv4Host

local ROUTE_REVALIDATE_INTERVAL_SECONDS = 1

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function defaultClock()
    if love and love.timer and type(love.timer.getTime) == "function" then
        return love.timer.getTime()
    end
    return os.clock()
end

local function validPort(value)
    return type(value) == "number" and value == math.floor(value)
        and value >= 1 and value <= 65535
end

local function failStart(self, message)
    self.state = "failed"
    self.lastError = message
    self.invitationCode = nil
    self.manualSetupPending = false
    if self.listener then
        local called, closed = pcall(self.listener.close, self.listener)
        if called and closed == true then
            self.listener = nil
        else
            self.state = "cleanup_required"
            self.closeOk = false
        end
    end
    return false, message
end

function DirectIpv4Host.new(options)
    options = type(options) == "table" and options or {}
    if DirectIpv4Host.productionReady ~= true
        and options.engineeringEnabled ~= true then
        return nil, "Direct IPv4 automatic hosting is not enabled in production."
    end
    local clock = options.clock or defaultClock
    local discoverRoute = options.discoverRoute or function()
        return GatewayDiscovery.discover(options.gatewayOptions)
    end
    local revalidateRoute = options.revalidateRoute or function(snapshot)
        return GatewayDiscovery.revalidate(snapshot, options.gatewayOptions)
    end
    if type(options.provider) ~= "table" or type(clock) ~= "function"
        or type(discoverRoute) ~= "function"
        or type(revalidateRoute) ~= "function" then
        return nil, "Direct IPv4 host options are invalid."
    end
    return setmetatable({
        options = options,
        clock = clock,
        discoverRoute = discoverRoute,
        revalidateRoute = revalidateRoute,
        state = "idle",
        listener = nil,
        reachability = nil,
        invitationCode = nil,
        manualSetupPending = false,
        manualDetails = nil,
        manualProposal = nil,
        manualRuleConfirmed = false,
        manualRouteInvalidated = false,
        lastError = nil,
        closeOk = nil,
        renewalCount = 0,
        mappingMethod = nil,
        cleanupReason = nil,
        listenerClosedBeforeCleanup = false,
        remoteVerified = false,
        attachedToSession = false,
        nextRouteCheckAt = nil,
    }, DirectIpv4Host)
end

function DirectIpv4Host:start(port, startOptions)
    if self.state ~= "idle" then return false, "Direct IPv4 host is already active." end
    startOptions = type(startOptions) == "table" and startOptions or {}
    self.renewalCount = 0
    self.mappingMethod = nil
    self.cleanupReason = nil
    self.listenerClosedBeforeCleanup = false
    self.remoteVerified = false
    self.attachedToSession = false
    self.manualSetupPending = false
    self.manualDetails = nil
    self.manualProposal = nil
    self.manualRuleConfirmed = false
    self.manualRouteInvalidated = false
    self.nextRouteCheckAt = nil
    local routeOk, route = pcall(self.discoverRoute)
    if not routeOk or type(route) ~= "table" then
        return failStart(self, "A safe IPv4 default route is unavailable.")
    end
    local listener, listenerError = DirectIpv4Listener.open({
        route = route,
        port = port,
        provider = self.options.provider,
        baseFactory = self.options.baseFactory,
        enet = self.options.enet,
        clock = self.clock,
        handshakeTimeout = self.options.handshakeTimeout,
        maxGuests = self.options.maxGuests,
        channels = self.options.channels,
    })
    if listener then self.listener = listener end
    if not listener or listenerError then
        return failStart(self, listenerError)
    end
    -- Keep ownership immediately after the socket is bound. Every later
    -- setup failure must either close it successfully or leave it available
    -- for stop() to retry and report as unverified cleanup.
    local methods = {}
    if self.options.manualOnly ~= true then
        local methodsError
        methods, methodsError = RouterMappingAdapter.new({
            route = route,
            socketFactory = self.options.socketFactory,
            upnpTransportFactory = self.options.upnpTransportFactory,
            randomBytes = self.options.provider.randomBytes,
            randomUnit = self.options.randomUnit,
            revalidate = self.revalidateRoute,
        })
        if not methods then
            return failStart(self, methodsError
                or "Exact-network router mapping is unavailable.")
        end
    end
    local reachability, reachabilityError = Reachability.new({
        methods = methods,
        clock = self.clock,
        maxLeaseSeconds = self.options.maxLeaseSeconds,
        requestedLeaseSeconds = self.options.requestedLeaseSeconds,
        attemptTimeoutSeconds = self.options.attemptTimeoutSeconds,
        renewFraction = self.options.renewFraction,
    })
    if not reachability then
        return failStart(self, reachabilityError
            or "Router mapping coordination is unavailable.")
    end
    local request, requestError = listener:mappingRequest(
        startOptions.requestedLifetime or self.options.requestedLeaseSeconds,
        startOptions.suggestedExternalPort)
    if not request then
        return failStart(self, requestError)
    end
    request.now = startOptions.now
    request.manualCandidate = startOptions.manualCandidate
    local started = reachability:start(request)
    if not started then
        return failStart(self, "Router mapping could not start.")
    end

    self.reachability = reachability
    self.state = "mapping"
    self.lastError = nil
    return true
end

function DirectIpv4Host:startManualSetup(port, endpoint)
    if self.state ~= "idle" then
        return false, "Direct IPv4 host is already active."
    end
    endpoint = type(endpoint) == "table" and endpoint or {}
    local externalAddress = endpoint.externalAddress
    local externalPort = endpoint.externalPort
    local lifetime = endpoint.lifetimeSeconds or 15 * 60
    if not IpScope.isGlobal(externalAddress) or not validPort(port)
        or not validPort(externalPort)
        or type(lifetime) ~= "number" or lifetime ~= math.floor(lifetime)
        or lifetime < 1 or lifetime > 24 * 60 * 60 then
        return false, "Manual IPv4 endpoint is invalid."
    end

    local routeOk, route = pcall(self.discoverRoute)
    if not routeOk or type(route) ~= "table" then
        return false, "A safe IPv4 default route is unavailable."
    end
    local listener, listenerError = DirectIpv4Listener.open({
        route = route,
        port = port,
        provider = self.options.provider,
        baseFactory = self.options.baseFactory,
        enet = self.options.enet,
        clock = self.clock,
        handshakeTimeout = self.options.handshakeTimeout,
        maxGuests = self.options.maxGuests,
        channels = self.options.channels,
    })
    if listener then self.listener = listener end
    if not listener or listenerError then
        return failStart(self, listenerError or "Secure IPv4 listener could not start.")
    end

    self.manualProposal = {
        externalAddress = externalAddress,
        externalPort = externalPort,
    }
    self.manualRouteInvalidated = false
    self.nextRouteCheckAt = nil
    self.manualDetails = {
        internalAddress = listener.route.internalAddress,
        internalPort = listener.port,
        externalAddress = externalAddress,
        externalPort = externalPort,
        lifetimeSeconds = lifetime,
    }
    self.manualSetupPending = true
    self.manualRuleConfirmed = false
    self.mappingMethod = "manual"
    self.lastError = nil
    self.state = "manual_setup"
    return true, self:manualSetupDetails()
end

function DirectIpv4Host:_consumeEvents()
    for _, event in ipairs(self.reachability:drainEvents()) do
        if event.kind == "candidate_ready" and event.candidate then
            self.mappingMethod = event.candidate.method
            if self.state == "stopping" or self.listener.closed then
                self.invitationCode = nil
            elseif event.candidate.method == "manual" and not self.manualRuleConfirmed then
                -- The endpoint is a player-supplied claim. Bind securely now,
                -- but do not publish an invitation until the UDP rule is confirmed.
                self.manualSetupPending = true
                self.manualDetails = {
                    internalAddress = self.listener.route.internalAddress,
                    internalPort = self.listener.port,
                    externalAddress = event.candidate.externalAddress,
                    externalPort = event.candidate.externalPort,
                    expiresAt = event.candidate.expiresAt,
                    lifetimeSeconds = event.candidate.leaseSeconds,
                }
                self.state = "manual_setup"
            else
                local code = self.listener:publish(event.candidate)
                if code then
                    self.invitationCode = code
                    self.manualSetupPending = false
                    self.state = "ready"
                else
                    local stopCalled, stopped, cleanupRequired =
                        pcall(self.stop, self)
                    if not stopCalled or stopped ~= true
                        or cleanupRequired == true then
                        self.state = "cleanup_required"
                        self.closeOk = false
                    else
                        self.state = "failed"
                    end
                    self.lastError = "The mapped IPv4 endpoint could not be published."
                end
            end
        elseif event.kind == "candidate_invalidated" then
            self.invitationCode = nil
            self.listener:unpublish()
            if event.method == "manual" then self.manualSetupPending = false end
            if self.state ~= "stopping" then self.state = "mapping" end
        elseif event.kind == "lease_renewed" and event.candidate then
            self.renewalCount = self.renewalCount + 1
            self.mappingMethod = event.candidate.method
        elseif event.kind == "cleanup_complete" then
            self.cleanupReason = event.reason
        elseif event.kind == "unavailable" then
            self.invitationCode = nil
            self.listener:unpublish()
            local listenerClosed = self.listener:close()
            self.listenerClosedBeforeCleanup = listenerClosed == true
            if event.cleanupRequired == true or not listenerClosed then
                self.state = "cleanup_required"
                self.closeOk = false
            else
                self.state = "unavailable"
            end
        elseif event.kind == "cleanup_required" then
            self.invitationCode = nil
            self.listener:unpublish()
            local listenerClosed = self.listener:close()
            self.listenerClosedBeforeCleanup = listenerClosed == true
            self.state = "cleanup_required"
            self.closeOk = false
        elseif event.kind == "stopped" then
            if event.cleanupRequired == true then
                self.state = "cleanup_required"
                self.closeOk = false
            else
                self.state = "stopped"
                self.closeOk = true
            end
        end
    end
end

local routeMatches

local function closeInvalidatedManualListener(self)
    if not self.listener then
        self.listenerClosedBeforeCleanup = true
        return true
    end
    pcall(self.listener.unpublish, self.listener)
    local called, closed = pcall(self.listener.close, self.listener)
    self.listenerClosedBeforeCleanup = called and closed == true
    self.closeOk = self.listenerClosedBeforeCleanup
    return self.listenerClosedBeforeCleanup
end

function DirectIpv4Host:update(now)
    if self.state == "cleanup_required" and self.listener
        and self.listenerClosedBeforeCleanup ~= true then
        local stopCalled, stopped = pcall(self.stop, self)
        if not stopCalled or stopped ~= true then
            self.state = "cleanup_required"
            self.closeOk = false
        end
        -- Do not renew or otherwise touch the router mapping until the
        -- listener close is verified. stop() will start mapping cleanup once
        -- that prerequisite succeeds; the next update can then drive it.
        return self.state, self.lastError
    end
    local currentTime = now
    if not finite(currentTime) then
        local clockCalled, clockValue = pcall(self.clock)
        if clockCalled and finite(clockValue) then currentTime = clockValue end
    end

    if finite(currentTime) and self.listener
        and self.state == "manual_setup" and self.manualSetupPending then
        if self.nextRouteCheckAt == nil
            or currentTime >= self.nextRouteCheckAt then
            self.nextRouteCheckAt = currentTime + ROUTE_REVALIDATE_INTERVAL_SECONDS
            if self.manualRouteInvalidated then
                closeInvalidatedManualListener(self)
                return self.state, self.lastError
            end
            if not routeMatches(self) then
                self.manualRouteInvalidated = true
                self.lastError = "The IPv4 network changed during manual router setup. No invitation was published."
                closeInvalidatedManualListener(self)
                return self.state, self.lastError
            end
        end
        return self.state, self.lastError
    end

    if finite(currentTime) and self.listener
        and (self.state == "mapping" or self.state == "ready")
        and (self.nextRouteCheckAt == nil
            or currentTime >= self.nextRouteCheckAt) then
        self.nextRouteCheckAt = currentTime + ROUTE_REVALIDATE_INTERVAL_SECONDS
        if not routeMatches(self) then
            self.invitationCode = nil
            self.listener:unpublish()
            local stopCalled, stopped = pcall(self.stop, self)
            if not stopCalled or stopped ~= true then
                self.state = "cleanup_required"
                self.closeOk = false
            else
                self.state = "failed"
            end
            self.lastError = "The IPv4 network changed; Direct hosting was stopped safely."
            return self.state, self.lastError
        end
    end

    if not self.reachability then return self.state, self.lastError end

    local ok = self.reachability:update(currentTime)
    if not ok then
        self.invitationCode = nil
        if self.listener then self.listener:unpublish() end
        local stopCalled, stopped = pcall(self.stop, self)
        if not stopCalled or stopped ~= true then
            self.state = "cleanup_required"
            self.closeOk = false
        else
            self.state = "failed"
        end
        self.lastError = "Router mapping update failed; Direct hosting was stopped safely."
        return self.state, self.lastError
    end
    self:_consumeEvents()
    return self.state, self.lastError
end

function DirectIpv4Host:invitation()
    return self.state == "ready" and self.invitationCode or nil
end

function DirectIpv4Host:manualSetupDetails()
    if type(self.manualDetails) ~= "table" then
        return nil
    end
    local details = self.manualDetails
    return {
        internalAddress = details.internalAddress,
        internalPort = details.internalPort,
        externalAddress = details.externalAddress,
        externalPort = details.externalPort,
        expiresAt = details.expiresAt,
        lifetimeSeconds = details.lifetimeSeconds,
    }
end

function DirectIpv4Host:manualCleanupDetails()
    local snapshot = self.reachability and self.reachability:snapshot() or nil
    local reachabilityCleanup = snapshot ~= nil
        and snapshot.cleanupKind == "manual"
        and snapshot.cleanupRequired == true
    local confirmedRuleCleanup = self.manualRuleConfirmed == true
        and self.state == "cleanup_required"
    if not reachabilityCleanup and not confirmedRuleCleanup then
        return nil
    end
    if self.listenerClosedBeforeCleanup ~= true
        or type(self.manualDetails) ~= "table" then
        return nil
    end
    local details = self.manualDetails
    return {
        internalAddress = details.internalAddress,
        internalPort = details.internalPort,
        externalAddress = details.externalAddress,
        externalPort = details.externalPort,
    }
end

routeMatches = function(self)
    local route = self.listener and self.listener.route
    if not route then return false end
    local called, currentRoute = pcall(self.revalidateRoute, route)
    return called and type(currentRoute) == "table"
        and currentRoute.family == route.family
        and currentRoute.platform == route.platform
        and currentRoute.internalAddress == route.internalAddress
        and currentRoute.gatewayAddress == route.gatewayAddress
        and currentRoute.interfaceIndex == route.interfaceIndex
        and currentRoute.routePrefixLength == route.routePrefixLength
        and currentRoute.networkGeneration == route.networkGeneration
        and currentRoute.routeFingerprint == route.routeFingerprint
end

function DirectIpv4Host:confirmManualSetup(now)
    if self.state ~= "manual_setup" or not self.manualSetupPending
        or not self.manualProposal or not self.listener then
        return false, "manual_setup_not_pending"
    end

    -- Record the user's assertion before doing any operation which may fail:
    -- after this point cleanup must require explicit router-rule removal.
    self.manualRuleConfirmed = true
    if self.manualRouteInvalidated or not routeMatches(self) then
        self.manualRouteInvalidated = true
        self.lastError = "The IPv4 network changed during manual router setup. No invitation was published."
        closeInvalidatedManualListener(self)
        self:stop()
        return false, "network_changed"
    end
    local lifetime = self.manualDetails.lifetimeSeconds or 15 * 60
    local reachability, reachabilityError = Reachability.new({
        methods = {},
        clock = self.clock,
        maxLeaseSeconds = self.options.maxLeaseSeconds,
        manualCandidateSeconds = lifetime,
    })
    if not reachability then
        self:stop()
        return false, reachabilityError or "manual_reachability_unavailable"
    end
    local request, requestError = self.listener:mappingRequest(
        lifetime, self.manualProposal.externalPort)
    if not request then
        self:stop()
        return false, requestError or "manual_endpoint_unavailable"
    end
    request.now = now
    request.manualCandidate = {
        externalAddress = self.manualProposal.externalAddress,
        externalPort = self.manualProposal.externalPort,
        lifetime = lifetime,
    }
    self.reachability = reachability
    self.manualSetupPending = false
    local started, startError = reachability:start(request)
    if not started then
        self:stop()
        return false, startError or "manual_endpoint_unavailable"
    end
    if not routeMatches(self) then
        self:stop()
        return false, "network_changed"
    end
    self:_consumeEvents()
    if self.state ~= "ready" or type(self.invitationCode) ~= "string" then
        self:stop()
        return false, "manual_invitation_unavailable"
    end
    return true, self.invitationCode
end

function DirectIpv4Host:requireManualCleanup()
    if self.state ~= "manual_setup" or not self.manualSetupPending
        or type(self.manualDetails) ~= "table" then
        return false, "manual_setup_not_pending"
    end
    -- Used only when a player cancels after adding the router rule but before
    -- asking us to publish an invitation.
    self.manualRuleConfirmed = true
    self.manualSetupPending = false
    return true
end

function DirectIpv4Host:transportFactory()
    if self.state ~= "ready" or not self.listener then return nil end
    return self.listener:transportFactory()
end

function DirectIpv4Host:attachToSession(compositeController)
    if self.state ~= "ready" or not self.listener then
        return nil, "Direct IPv4 host is not ready."
    end
    if self.attachedToSession then
        return nil, "Direct IPv4 listener is already attached to a session."
    end
    if type(compositeController) ~= "table"
        or type(compositeController.attachFactory) ~= "function" then
        return nil, "Direct IPv4 host session is unavailable."
    end

    local route = self.listener.route
    if not routeMatches(self) then
        self.invitationCode = nil
        self.listener:unpublish()
        self:stop()
        return nil, "The IPv4 network changed before the host could attach."
    end

    local factory = self:transportFactory()
    if not factory then return nil, "Secure IPv4 listener is unavailable." end
    local channels = self.options.channels or 3
    local attached, attachError = compositeController:attachFactory(factory, {
        bind = route.internalAddress,
        port = self.listener.port,
        channels = channels,
    })
    if not attached then
        self.invitationCode = nil
        self.listener:unpublish()
        self:stop()
        return nil, attachError or "The IPv4 listener could not attach to the Direct session."
    end
    self.attachedToSession = true
    return attached
end

function DirectIpv4Host:markVerified(now)
    if self.state ~= "ready" or not self.reachability then return false end
    local candidate = self.reachability:candidate()
    if not candidate then return false end
    local verified = self.reachability:markVerified(
        candidate.externalAddress, candidate.externalPort, now)
    if verified then self.remoteVerified = true end
    self:_consumeEvents()
    return verified == true
end

function DirectIpv4Host:status()
    local reachability = self.reachability
        and self.reachability:snapshot() or nil
    local manualCleanup = reachability ~= nil
        and reachability.cleanupKind == "manual"
        and reachability.cleanupRequired == true
        or self.manualRuleConfirmed == true and self.state == "cleanup_required"
    return {
        state = self.state,
        renewalCount = self.renewalCount,
        mappingMethod = self.mappingMethod,
        manualSetupPending = self.manualSetupPending == true,
        manualRuleConfirmed = self.manualRuleConfirmed == true,
        manualRouteInvalidated = self.manualRouteInvalidated == true,
        cleanupReason = self.cleanupReason,
        listenerClosedBeforeCleanup = self.listenerClosedBeforeCleanup,
        remoteVerified = self.remoteVerified,
        attachedToSession = self.attachedToSession,
        cleanupRequired = manualCleanup or reachability ~= nil
            and reachability.cleanupRequired == true
            or self.state == "cleanup_required",
        cleanupKind = manualCleanup and "manual"
            or reachability and reachability.cleanupKind or nil,
    }
end

function DirectIpv4Host:acknowledgeManualCleanup()
    local snapshot = self.reachability and self.reachability:snapshot() or nil
    local reachabilityCleanup = snapshot ~= nil
        and snapshot.cleanupKind == "manual"
        and snapshot.cleanupRequired == true
    if not reachabilityCleanup and not self.manualRuleConfirmed then
        return false, "manual_cleanup_not_required"
    end
    if self.state ~= "cleanup_required" then
        return false, "host_must_stop_first"
    end
    if snapshot and snapshot.cleanupKind ~= nil and snapshot.cleanupKind ~= "manual" then
        return false, "automatic_cleanup_cannot_be_acknowledged"
    end
    if snapshot and (snapshot.status ~= "stopped" or snapshot.candidate ~= nil) then
        return false, "host_must_stop_first"
    end
    if self.listenerClosedBeforeCleanup ~= true then
        return false, "listener_close_unverified"
    end

    if reachabilityCleanup then
        local acknowledged, acknowledgmentError =
            self.reachability:acknowledgeManualCleanup()
        if not acknowledged then return false, acknowledgmentError end
        local final = self.reachability:snapshot()
        if final.status ~= "stopped" or final.cleanupRequired then
            return false, "manual_cleanup_unverified"
        end
    end
    self.state = "stopped"
    self.closeOk = true
    self.manualDetails = nil
    self.manualProposal = nil
    self.manualRuleConfirmed = false
    return true
end

function DirectIpv4Host:stop()
    if self.state == "stopped" then return self.closeOk == true, false end
    self.invitationCode = nil
    self.manualSetupPending = false
    local listenerOk = self.listener == nil or self.listener:close()
    if not listenerOk then
        self.state = "cleanup_required"
        self.closeOk = false
        return false, true
    end
    self.listenerClosedBeforeCleanup = true
    if not self.reachability then
        if self.manualRuleConfirmed then
            self.state = "cleanup_required"
            self.closeOk = false
            return false, true
        end
        self.state = "stopped"
        self.closeOk = true
        return true, false
    end
    self.state = "stopping"
    local stopped, cleanupRequired = self.reachability:stop()
    self:_consumeEvents()
    if self.manualRuleConfirmed then
        self.state = "cleanup_required"
        self.closeOk = false
        return false, true
    end
    self.closeOk = stopped == true and cleanupRequired ~= true
    return self.closeOk, cleanupRequired == true
end

return DirectIpv4Host
