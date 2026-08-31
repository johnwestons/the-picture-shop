local IpScope = require("src.net.ip_scope")

local Reachability = {}
Reachability.__index = Reachability

Reachability.DEFAULT_MAX_LEASE_SECONDS = 24 * 60 * 60
Reachability.DEFAULT_REQUESTED_LEASE_SECONDS = 2 * 60 * 60
Reachability.DEFAULT_MANUAL_CANDIDATE_SECONDS = 15 * 60
Reachability.DEFAULT_ATTEMPT_TIMEOUT_SECONDS = 8

local UINT16_MAX = 65535

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function integerInRange(value, minimum, maximum)
    return finite(value) and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function validDuration(value, maximum)
    return integerInRange(value, 1, maximum)
end

local function usableLocalUnicast(value)
    local classification = IpScope.classify(value)
    return classification.isGlobal == true
        or classification.reason == "private_use"
        or classification.reason == "carrier_grade_nat"
        or classification.reason == "link_local"
end

local function copyCandidate(candidate)
    if not candidate then return nil end
    return {
        externalAddress = candidate.externalAddress,
        externalPort = candidate.externalPort,
        endpoint = candidate.endpoint,
        method = candidate.method,
        verified = candidate.verified == true,
        cleanupRequired = candidate.cleanupRequired == true,
        leaseSeconds = candidate.leaseSeconds,
        createdAt = candidate.createdAt,
        renewAt = candidate.renewAt,
        expiresAt = candidate.expiresAt,
    }
end

local function safeAdapterRequest(request)
    -- This explicit allowlist is a security boundary.  In particular, an
    -- invitation key or an entire caller-owned request table can never reach
    -- a discovery/mapping adapter by accident.
    return {
        internalAddress = request.internalAddress,
        internalPort = request.internalPort,
        gatewayAddress = request.gatewayAddress,
        suggestedExternalPort = request.suggestedExternalPort,
        requestedLifetime = request.requestedLifetime,
    }
end

local function sanitizeMethods(methods)
    if type(methods) ~= "table" then return nil, "invalid_methods" end

    local length, entries, names = #methods, {}, {}
    local count = 0
    for index in pairs(methods) do
        if not integerInRange(index, 1, length) then
            return nil, "invalid_methods"
        end
        count = count + 1
    end
    if count ~= length then return nil, "invalid_methods" end

    for index, adapter in ipairs(methods) do
        if type(adapter) ~= "table" or type(adapter.start) ~= "function" then
            return nil, "invalid_method_adapter"
        end
        local name = adapter.name
        if type(name) ~= "string" or #name < 1 or #name > 32
            or not name:match("^[a-z][a-z0-9_-]*$") or name == "manual"
        then
            return nil, "invalid_method_name"
        end
        if names[name] then return nil, "duplicate_method_name" end
        local attemptTimeout = adapter.attemptTimeoutSeconds
        if attemptTimeout ~= nil and attemptTimeout ~= false
            and (not finite(attemptTimeout) or attemptTimeout <= 0)
        then
            return nil, "invalid_method_timeout"
        end
        names[name] = true
        entries[index] = {
            name = name,
            adapter = adapter,
            -- `false` delegates exhaustion entirely to the adapter.  A
            -- positive value overrides the coordinator default for methods
            -- whose RFC retransmission schedules need a longer window.
            attemptTimeoutSeconds = attemptTimeout,
        }
    end
    return entries
end

local function sanitizeManualCandidate(value, defaultLifetime, maximumLifetime)
    if value == nil then return nil end
    if type(value) ~= "table" then return nil, "invalid_manual_candidate" end

    local isGlobal = IpScope.isGlobal(value.externalAddress)
    local port = value.externalPort
    local lifetime = value.lifetime or defaultLifetime
    if not isGlobal or not integerInRange(port, 1, UINT16_MAX)
        or not validDuration(lifetime, maximumLifetime)
    then
        return nil, "invalid_manual_candidate"
    end
    return {
        externalAddress = value.externalAddress,
        externalPort = port,
        lifetime = lifetime,
    }
end

local function validHandle(handle)
    return type(handle) == "table"
        and type(handle.update) == "function"
        and type(handle.renew) == "function"
        and type(handle.delete) == "function"
        and type(handle.close) == "function"
end

function Reachability.new(options)
    options = options or {}
    if type(options) ~= "table" then return nil, "invalid_options" end

    local methods, methodsError = sanitizeMethods(options.methods or {})
    if not methods then return nil, methodsError end

    local clock = options.clock or os.clock
    local maxLease = options.maxLeaseSeconds
        or Reachability.DEFAULT_MAX_LEASE_SECONDS
    if not integerInRange(maxLease, 1, 4294967295) then
        return nil, "invalid_max_lease"
    end

    local requestedLease = options.requestedLeaseSeconds
        or math.min(Reachability.DEFAULT_REQUESTED_LEASE_SECONDS, maxLease)
    local manualLifetime = options.manualCandidateSeconds
        or math.min(Reachability.DEFAULT_MANUAL_CANDIDATE_SECONDS, maxLease)
    local attemptTimeout = options.attemptTimeoutSeconds
        or Reachability.DEFAULT_ATTEMPT_TIMEOUT_SECONDS
    local renewFraction = options.renewFraction or 0.5
    if type(clock) ~= "function" then return nil, "invalid_clock" end
    if not validDuration(requestedLease, maxLease) then
        return nil, "invalid_requested_lease"
    end
    if not validDuration(manualLifetime, maxLease) then
        return nil, "invalid_manual_lifetime"
    end
    if not finite(attemptTimeout) or attemptTimeout <= 0 then
        return nil, "invalid_attempt_timeout"
    end
    if not finite(renewFraction) or renewFraction <= 0 or renewFraction >= 1 then
        return nil, "invalid_renew_fraction"
    end

    return setmetatable({
        methods = methods,
        clock = clock,
        maxLeaseSeconds = maxLease,
        requestedLeaseSeconds = requestedLease,
        manualCandidateSeconds = manualLifetime,
        attemptTimeoutSeconds = attemptTimeout,
        renewFraction = renewFraction,
        _status = "idle",
        _methodIndex = 0,
        _active = nil,
        _candidate = nil,
        _request = nil,
        _manualCandidate = nil,
        _lastNow = nil,
        _events = {},
        _stopped = false,
        _stopResult = true,
        _stopRequested = false,
        _residualCleanupRequired = false,
        _cleanupKind = nil,
    }, Reachability)
end

function Reachability:_queue(kind, fields)
    local event = { kind = kind }
    for key, value in pairs(fields or {}) do event[key] = value end
    self._events[#self._events + 1] = event
end

function Reachability:_queueCandidate(kind, candidate)
    self:_queue(kind, { candidate = copyCandidate(candidate) })
end

function Reachability:drainEvents()
    local events = self._events
    self._events = {}
    return events
end

function Reachability:status()
    return self._status
end

function Reachability:candidate()
    return copyCandidate(self._candidate)
end

function Reachability:snapshot()
    local active = self._active
    return {
        status = self._status,
        method = active and active.method.name
            or (self._candidate and self._candidate.method or nil),
        cleanupRequired = self._residualCleanupRequired == true,
        cleanupKind = self._cleanupKind,
        cleanupExpiresAt = active and active.cleanupStarted
            and active.mappingExpiresAt or nil,
        candidate = copyCandidate(self._candidate),
    }
end

function Reachability:_readNow(value)
    local now = value
    if now == nil then
        local called, clockValue = pcall(self.clock)
        if not called then return nil, "invalid_time" end
        now = clockValue
    end
    if not finite(now) or now < 0 then return nil, "invalid_time" end
    if self._lastNow ~= nil and now < self._lastNow then
        return nil, "time_went_backwards"
    end
    return now
end

function Reachability:_closeActive()
    local active = self._active
    if not active then return true end
    local handle = active.handle
    local called, result = pcall(handle.close, handle)
    if not called or result == false then return false end
    self._active = nil
    return true
end

function Reachability:_finalizeStopped(success)
    self._request = nil
    self._manualCandidate = nil
    self._candidate = nil
    self._status = "stopped"
    self._stopped = true
    self._stopRequested = true
    self._stopResult = success == true
        and self._residualCleanupRequired ~= true
    self:_queue("stopped", {
        cleanupRequired = self._residualCleanupRequired == true,
    })
    return self._stopResult, self._residualCleanupRequired
end

function Reachability:_continueAfterCleanup(now, continuation)
    if continuation == "stop" or self._stopRequested then
        self:_finalizeStopped(true)
    else
        self:_startNext(now)
    end
end

function Reachability:_finishAutomaticCleanup(now, completionReason)
    local active = self._active
    if not active then return false end
    local continuation = active.cleanupContinuation
    active.mappingGone = true

    if not self:_closeActive() then
        self._residualCleanupRequired = true
        self._cleanupKind = "automatic"
        self._status = "cleanup_required"
        if not active.closeFailureReported then
            active.closeFailureReported = true
            self:_queue("cleanup_required", { method = active.method.name })
        end
        return false
    end

    self._residualCleanupRequired = false
    self._cleanupKind = nil
    self:_queue("cleanup_complete", {
        method = active.method.name,
        reason = completionReason,
    })
    self:_continueAfterCleanup(now, continuation)
    return true
end

function Reachability:_requestAutomaticDeletion(now)
    local active = self._active
    if not active then return "failed" end
    active.deletionRequested = true
    active.deleteAttempts = (active.deleteAttempts or 0) + 1
    local called, result = pcall(active.handle.delete, active.handle, now)
    if called and result == true then
        -- Literal true is reserved for an exact, validated deletion
        -- acknowledgement (or adapter proof that no mapping was created).
        return "acknowledged"
    end
    if not called or result == false then return "failed" end
    -- nil is the normal asynchronous result: the adapter owns retransmission
    -- and later emits only an exact `deleted` acknowledgement from update().
    return "pending"
end

function Reachability:_beginAutomaticCleanup(now, reason, continuation)
    local active = self._active
    if not active then return false end
    if active.cleanupStarted then
        if continuation == "stop" then active.cleanupContinuation = "stop" end
        return false
    end

    if self._candidate then
        active.mappingExpiresAt = active.mappingExpiresAt
            or self._candidate.expiresAt
        self:_queue("candidate_invalidated", {
            method = active.method.name,
            reason = reason,
            cleanupRequired = true,
        })
        self._candidate = nil
    end

    active.cleanupStarted = true
    active.cleanupReason = reason
    active.cleanupContinuation = continuation or "fallback"
    self._residualCleanupRequired = true
    self._cleanupKind = "automatic"
    self._status = "cleaning"
    self:_queue("cleanup_started", {
        method = active.method.name,
        reason = reason,
    })

    local deletion = self:_requestAutomaticDeletion(now)
    if active.mappingExpiresAt and now >= active.mappingExpiresAt then
        return self:_finishAutomaticCleanup(now, "lease_expired")
    end
    if deletion == "acknowledged" then
        return self:_finishAutomaticCleanup(now, "deletion_acknowledged")
    end
    if deletion == "failed" then
        self._status = "cleanup_required"
        active.cleanupFailureReported = true
        self:_queue("cleanup_required", { method = active.method.name })
    end
    return false
end

function Reachability:_processCleanupUpdate(active, now)
    if self._active ~= active then return end
    if active.mappingGone then
        self:_finishAutomaticCleanup(now, "mapping_gone")
        return
    end
    if active.mappingExpiresAt and now >= active.mappingExpiresAt then
        self:_finishAutomaticCleanup(now, "lease_expired")
        return
    end

    local called, event = pcall(active.handle.update, active.handle, now)
    if not called then
        self._status = "cleanup_required"
        if not active.cleanupFailureReported then
            active.cleanupFailureReported = true
            self:_queue("cleanup_required", { method = active.method.name })
        end
        return
    end
    if event == nil then return end

    -- The adapter may emit `deleted` only after source, transaction fields,
    -- protocol, internal port, and lifetime-zero semantics all match the
    -- exact mapping owned by this handle.
    if type(event) == "table" and event.kind == "deleted" then
        self:_finishAutomaticCleanup(now, "deletion_acknowledged")
        return
    end

    if type(event) == "table" and event.kind == "mapped" then
        -- A delayed creation response can arrive after cleanup began.  Never
        -- expose it as a candidate; record its finite lease and put a fresh
        -- deletion request after that late response.
        if validDuration(event.lifetime, self.maxLeaseSeconds) then
            active.mappingExpiresAt = now + event.lifetime
            active.cleanupFailureReported = false
            local deletion = self:_requestAutomaticDeletion(now)
            if deletion == "acknowledged" then
                self:_finishAutomaticCleanup(now, "deletion_acknowledged")
            elseif deletion == "failed" then
                self._status = "cleanup_required"
                active.cleanupFailureReported = true
                self:_queue("cleanup_required", { method = active.method.name })
            else
                self._status = "cleaning"
            end
        else
            self._status = "cleanup_required"
            if not active.cleanupFailureReported then
                active.cleanupFailureReported = true
                self:_queue("cleanup_required", { method = active.method.name })
            end
        end
        return
    end

    -- No failure or unrelated event is permission to overlap mappings.  The
    -- active handle remains open until an exact delete acknowledgement or its
    -- recorded lease expiry.
    self._status = "cleanup_required"
    if not active.cleanupFailureReported then
        active.cleanupFailureReported = true
        self:_queue("cleanup_required", { method = active.method.name })
    end
end

function Reachability:_activateManual(now)
    local manual = self._manualCandidate
    self._request = nil
    self._manualCandidate = nil
    if not manual then
        self._status = "unavailable"
        self:_queue("unavailable", { cleanupRequired = false })
        return
    end

    self._candidate = {
        externalAddress = manual.externalAddress,
        externalPort = manual.externalPort,
        endpoint = manual.externalAddress .. ":" .. tostring(manual.externalPort),
        method = "manual",
        verified = false,
        cleanupRequired = true,
        leaseSeconds = manual.lifetime,
        createdAt = now,
        renewAt = nil,
        expiresAt = now + manual.lifetime,
    }
    self._residualCleanupRequired = true
    self._cleanupKind = "manual"
    self._status = "manual"
    self:_queueCandidate("candidate_ready", self._candidate)
end

function Reachability:_startNext(now)
    while self._methodIndex < #self.methods do
        self._methodIndex = self._methodIndex + 1
        local method = self.methods[self._methodIndex]
        self._status = "probing"
        self:_queue("method_started", { method = method.name })

        -- Adapter construction is a hard safety boundary: start() MUST be
        -- side-effect-free and MUST NOT transmit a discovery or mapping
        -- packet.  Network I/O may begin only after a complete handle has
        -- been returned, through handle:update().  Consequently, a thrown
        -- constructor or invalid handle cannot leave an unowned mapping.
        local called, handle = pcall(
            method.adapter.start, method.adapter, safeAdapterRequest(self._request))
        if not called or type(handle) ~= "table" then
            self:_queue("method_failed", {
                method = method.name,
                reason = "start_failed",
            })
        else
            self._active = {
                method = method,
                handle = handle,
                startedAt = now,
                renewalPending = false,
            }
            local timeout = method.attemptTimeoutSeconds
            if timeout == nil then timeout = self.attemptTimeoutSeconds end
            if timeout == false then
                self._active.deadlineAt = nil
            else
                self._active.deadlineAt = now + timeout
            end
            if validHandle(handle) then return end

            self:_queue("method_failed", {
                method = method.name,
                reason = "invalid_adapter_handle",
            })
            -- start() was side-effect-free by contract, so this is local
            -- handle disposal, not router mapping deletion.
            if type(handle.close) == "function" then
                pcall(handle.close, handle)
            end
            self._active = nil
        end
    end
    self:_activateManual(now)
end

function Reachability:_failCurrent(now, reason)
    local active = self._active
    if not active then return end
    local methodName = active.method.name
    if self._candidate then
        self:_queue("candidate_invalidated", {
            method = methodName,
            reason = reason,
            cleanupRequired = true,
        })
        self._candidate = nil
    end
    self:_queue("method_failed", { method = methodName, reason = reason })
    self:_beginAutomaticCleanup(now, reason, "fallback")
end

function Reachability:_activateMapped(event, now)
    local active = self._active
    if not active then return false end

    local validLifetime = validDuration(event.lifetime, self.maxLeaseSeconds)
    if validLifetime then active.mappingExpiresAt = now + event.lifetime end
    local isGlobal = IpScope.isGlobal(event.externalAddress)
    if not isGlobal or not integerInRange(event.externalPort, 1, UINT16_MAX)
        or not validLifetime
    then
        self:_failCurrent(now, "invalid_mapping")
        return false
    end

    local previous = self._candidate
    local sameEndpoint = previous
        and previous.externalAddress == event.externalAddress
        and previous.externalPort == event.externalPort
    if previous and not sameEndpoint then
        self:_queue("candidate_invalidated", {
            method = active.method.name,
            reason = "endpoint_changed",
            cleanupRequired = false,
        })
    end
    self._candidate = {
        externalAddress = event.externalAddress,
        externalPort = event.externalPort,
        endpoint = event.externalAddress .. ":" .. tostring(event.externalPort),
        method = active.method.name,
        -- A successful router mapping is not an inbound reachability test.
        -- Preserve proof only when a renewal keeps the exact endpoint; a new
        -- endpoint must pass markVerified after an end-to-end remote probe.
        verified = (sameEndpoint and previous.verified == true) or false,
        cleanupRequired = false,
        leaseSeconds = event.lifetime,
        createdAt = now,
        renewAt = now + event.lifetime * self.renewFraction,
        expiresAt = now + event.lifetime,
    }
    active.deadlineAt = nil
    active.renewalPending = false
    self._status = "mapped"
    self:_queueCandidate(sameEndpoint and "lease_renewed" or "candidate_ready",
        self._candidate)
    return true
end

function Reachability:_processMethodEvent(event, now)
    if type(event) ~= "table" or type(event.kind) ~= "string" then
        self:_failCurrent(now, "invalid_method_event")
        return
    end
    if event.kind == "mapped" then
        self:_activateMapped(event, now)
    elseif event.kind == "failed" then
        self:_failCurrent(now, "method_failed")
    elseif event.kind == "exhausted" then
        self:_failCurrent(now, "attempt_exhausted")
    elseif event.kind == "expired" then
        -- This event is emitted only by the adapter that owns the mapping.
        -- Record the known expiry so fallback does not need a delete ack.
        local active = self._active
        if active then active.mappingExpiresAt = now end
        self:_failCurrent(now, "lease_expired")
    elseif event.kind == "epoch_reset" then
        self:_failCurrent(now, "epoch_reset")
    else
        self:_failCurrent(now, "invalid_method_event")
    end
end

function Reachability:start(request)
    if self._status == "probing" or self._status == "mapped"
        or self._status == "manual" or self._status == "cleaning"
        or self._active ~= nil
    then
        return false, "already_active"
    end
    if self._residualCleanupRequired then return false, "cleanup_required" end
    if type(request) ~= "table" then return false, "invalid_request" end

    local internal = IpScope.parse(request.internalAddress)
    local gateway = nil
    if request.gatewayAddress ~= nil then
        gateway = IpScope.parse(request.gatewayAddress)
        if not gateway or not usableLocalUnicast(gateway.address) then
            return false, "invalid_gateway_address"
        end
    end
    if not internal or not usableLocalUnicast(internal.address) then
        return false, "invalid_internal_address"
    end
    if not integerInRange(request.internalPort, 1, UINT16_MAX) then
        return false, "invalid_internal_port"
    end
    local suggestedPort = request.suggestedExternalPort
    if suggestedPort == nil then suggestedPort = request.internalPort end
    if not integerInRange(suggestedPort, 0, UINT16_MAX) then
        return false, "invalid_external_port"
    end
    local requestedLifetime = request.requestedLifetime
        or self.requestedLeaseSeconds
    if not validDuration(requestedLifetime, self.maxLeaseSeconds) then
        return false, "invalid_requested_lease"
    end
    local manual, manualError = sanitizeManualCandidate(
        request.manualCandidate, self.manualCandidateSeconds, self.maxLeaseSeconds)
    if manualError then return false, manualError end

    local now, timeError = self:_readNow(request.now)
    if not now then return false, timeError end
    self._lastNow = now
    self._events = {}
    self._stopped = false
    self._stopResult = true
    self._stopRequested = false
    self._methodIndex = 0
    self._candidate = nil
    self._cleanupKind = nil
    self._request = {
        internalAddress = internal.address,
        internalPort = request.internalPort,
        gatewayAddress = gateway and gateway.address or nil,
        suggestedExternalPort = suggestedPort,
        requestedLifetime = requestedLifetime,
    }
    self._manualCandidate = manual
    self:_startNext(now)
    return true
end

function Reachability:update(value)
    local now, timeError = self:_readNow(value)
    if not now then return false, timeError end
    self._lastNow = now

    if self._status == "manual" then
        if self._candidate and now >= self._candidate.expiresAt then
            self:_queue("candidate_invalidated", {
                method = "manual",
                reason = "lease_expired",
                cleanupRequired = true,
            })
            self._candidate = nil
            self._status = "unavailable"
            self:_queue("unavailable", { cleanupRequired = true })
        end
        return true
    end

    local active = self._active
    if not active then return true end
    if active.cleanupStarted then
        self:_processCleanupUpdate(active, now)
        return true
    end
    if self._candidate and now >= self._candidate.expiresAt then
        self:_failCurrent(now, "lease_expired")
        return true
    end

    if self._candidate and not active.renewalPending
        and now >= self._candidate.renewAt
    then
        local called, result = pcall(active.handle.renew, active.handle, now)
        if not called or result == false then
            self:_failCurrent(now, "renew_failed")
            return true
        end
        active.renewalPending = true
        self:_queue("renewal_started", { method = active.method.name })
    end

    local called, event = pcall(active.handle.update, active.handle, now)
    if not called then
        self:_failCurrent(now, "adapter_error")
        return true
    end
    if event ~= nil then
        self:_processMethodEvent(event, now)
    elseif self._active == active and not self._candidate
        and active.deadlineAt ~= nil and now >= active.deadlineAt
    then
        self:_failCurrent(now, "attempt_timeout")
    end
    return true
end

function Reachability:markVerified(externalAddress, externalPort, value)
    local candidate = self._candidate
    if not candidate then return false, "no_candidate" end
    local now, timeError = self:_readNow(value)
    if not now then return false, timeError end
    self._lastNow = now
    if now >= candidate.expiresAt then return false, "candidate_expired" end
    if self._status ~= "mapped" and self._status ~= "manual" then
        return false, "candidate_inactive"
    end
    if candidate.externalAddress ~= externalAddress
        or candidate.externalPort ~= externalPort
    then
        return false, "candidate_mismatch"
    end
    if not candidate.verified then
        candidate.verified = true
        self:_queueCandidate("candidate_verified", candidate)
    end
    return true
end

function Reachability:acknowledgeCleanup()
    if not self._residualCleanupRequired then return true end
    if self._cleanupKind == "manual" then
        return false, "use_acknowledge_manual_cleanup"
    end
    -- Automatic PCP/NAT-PMP/UPnP cleanup can never be waived by a button or
    -- caller acknowledgement.  It completes only through the exact adapter
    -- acknowledgement or the recorded finite lease expiry.
    return false, "automatic_cleanup_cannot_be_acknowledged"
end

function Reachability:acknowledgeManualCleanup()
    if not self._residualCleanupRequired then return true end
    if self._cleanupKind ~= "manual" then
        return false, "automatic_cleanup_cannot_be_acknowledged"
    end
    if self._active or self._candidate then return false, "still_active" end
    self._residualCleanupRequired = false
    self._cleanupKind = nil
    if self._stopped then self._stopResult = true end
    self:_queue("manual_cleanup_acknowledged")
    return true
end

function Reachability:stop()
    if self._stopped then
        return self._stopResult, self._residualCleanupRequired
    end

    local now = self:_readNow()
    if not now then now = self._lastNow or 0 else self._lastNow = now end
    self._stopRequested = true
    self._manualCandidate = nil

    local active = self._active
    if active then
        if self._candidate then
            self:_queue("candidate_invalidated", {
                method = active.method.name,
                reason = "stopped",
                cleanupRequired = true,
            })
            self._candidate = nil
        end
        if active.cleanupStarted then
            active.cleanupContinuation = "stop"
        else
            self:_beginAutomaticCleanup(now, "stopped", "stop")
        end
        if self._stopped then
            return self._stopResult, self._residualCleanupRequired
        end
        self._stopResult = false
        return false, true
    end

    if self._candidate then
        local method = self._candidate.method
        local manualCleanup = self._candidate.cleanupRequired == true
        self:_queue("candidate_invalidated", {
            method = method,
            reason = "stopped",
            cleanupRequired = manualCleanup,
        })
        self._candidate = nil
        if manualCleanup then
            self._residualCleanupRequired = true
            self._cleanupKind = "manual"
        end
    end

    return self:_finalizeStopped(not self._residualCleanupRequired)
end

return Reachability
