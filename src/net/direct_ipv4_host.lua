-- Ordered IPv4 Direct-host lifecycle: discover route, bind encrypted listener,
-- create/renew a finite mapping, then publish an invitation.  Shutdown always
-- closes the game listener before requesting mapping deletion.
local DirectIpv4Listener = require("src.net.direct_ipv4_listener")
local GatewayDiscovery = require("src.net.gateway_discovery")
local Reachability = require("src.net.reachability")
local RouterMappingAdapter = require("src.net.router_mapping_adapter")

local DirectIpv4Host = {
    productionReady = false,
}
DirectIpv4Host.__index = DirectIpv4Host

local function defaultClock()
    if love and love.timer and type(love.timer.getTime) == "function" then
        return love.timer.getTime()
    end
    return os.clock()
end

function DirectIpv4Host.new(options)
    options = type(options) == "table" and options or {}
    if options.engineeringEnabled ~= true then
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
        lastError = nil,
        closeOk = nil,
        renewalCount = 0,
        mappingMethod = nil,
        cleanupReason = nil,
        listenerClosedBeforeCleanup = false,
        remoteVerified = false,
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
    local routeOk, route = pcall(self.discoverRoute)
    if not routeOk or type(route) ~= "table" then
        self.state = "failed"
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
    if not listener then
        self.state = "failed"
        self.lastError = listenerError
        return false, listenerError
    end

    local methods, methodsError = RouterMappingAdapter.new({
        route = route,
        socketFactory = self.options.socketFactory,
        upnpTransportFactory = self.options.upnpTransportFactory,
        randomBytes = self.options.provider.randomBytes,
        randomUnit = self.options.randomUnit,
        revalidate = self.revalidateRoute,
    })
    if not methods then
        listener:close()
        self.state = "failed"
        self.lastError = methodsError
        return false, "Exact-network router mapping is unavailable."
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
        listener:close()
        self.state = "failed"
        self.lastError = reachabilityError
        return false, "Router mapping coordination is unavailable."
    end
    local request, requestError = listener:mappingRequest(
        startOptions.requestedLifetime or self.options.requestedLeaseSeconds,
        startOptions.suggestedExternalPort)
    if not request then
        listener:close()
        self.state = "failed"
        self.lastError = requestError
        return false, requestError
    end
    request.now = startOptions.now
    request.manualCandidate = startOptions.manualCandidate
    local started = reachability:start(request)
    if not started then
        listener:close()
        self.state = "failed"
        self.lastError = "Router mapping could not start."
        return false, self.lastError
    end

    self.listener = listener
    self.reachability = reachability
    self.state = "mapping"
    self.lastError = nil
    return true
end

function DirectIpv4Host:_consumeEvents()
    for _, event in ipairs(self.reachability:drainEvents()) do
        if event.kind == "candidate_ready" and event.candidate then
            local code = self.listener:publish(event.candidate)
            if code then
                self.invitationCode = code
                self.mappingMethod = event.candidate.method
                self.state = "ready"
            else
                self.invitationCode = nil
                self.listener:close()
                self.reachability:stop()
                self.state = "failed"
                self.lastError = "The mapped IPv4 endpoint could not be published."
            end
        elseif event.kind == "candidate_invalidated" then
            self.invitationCode = nil
            self.listener:unpublish()
            if self.state ~= "stopping" then self.state = "mapping" end
        elseif event.kind == "lease_renewed" and event.candidate then
            self.renewalCount = self.renewalCount + 1
            self.mappingMethod = event.candidate.method
        elseif event.kind == "cleanup_complete" then
            self.cleanupReason = event.reason
        elseif event.kind == "unavailable" then
            self.invitationCode = nil
            self.listener:unpublish()
            self.listener:close()
            self.state = "unavailable"
        elseif event.kind == "cleanup_required" then
            self.state = "cleanup_required"
        elseif event.kind == "stopped" then
            self.state = "stopped"
            self.closeOk = true
        end
    end
end

function DirectIpv4Host:update(now)
    if not self.reachability then return self.state, self.lastError end
    local ok = self.reachability:update(now)
    if not ok then
        self.state = "failed"
        self.lastError = "Router mapping update failed."
    end
    self:_consumeEvents()
    return self.state, self.lastError
end

function DirectIpv4Host:invitation()
    return self.state == "ready" and self.invitationCode or nil
end

function DirectIpv4Host:transportFactory()
    if self.state ~= "ready" or not self.listener then return nil end
    return self.listener:transportFactory()
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
    return {
        state = self.state,
        renewalCount = self.renewalCount,
        mappingMethod = self.mappingMethod,
        cleanupReason = self.cleanupReason,
        listenerClosedBeforeCleanup = self.listenerClosedBeforeCleanup,
        remoteVerified = self.remoteVerified,
        cleanupRequired = self.state == "cleanup_required",
    }
end

function DirectIpv4Host:stop()
    if self.state == "stopped" then return self.closeOk == true, false end
    self.invitationCode = nil
    local listenerOk = self.listener == nil or self.listener:close()
    if not listenerOk then
        self.state = "cleanup_required"
        self.closeOk = false
        return false, true
    end
    if not self.reachability then
        self.state = "stopped"
        self.closeOk = true
        return true, false
    end
    self.listenerClosedBeforeCleanup = listenerOk == true
    self.state = "stopping"
    local stopped, cleanupRequired = self.reachability:stop()
    self:_consumeEvents()
    self.closeOk = stopped == true and cleanupRequired ~= true
    return self.closeOk, cleanupRequired == true
end

return DirectIpv4Host
