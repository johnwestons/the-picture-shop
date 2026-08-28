-- Host-owned authority for modal workshop interactions. Networking, screen
-- routing, and game-domain mutations stay outside this module: callers pass an
-- authoritative player plus strict resource callbacks.
local Authority = {}
Authority.__index = Authority

-- Resource callback contract:
--   canAcquire(player, hostContext, request) -> allowed, code?, message?
--   onAcquire(lease, player, hostContext, request)
--       -> accepted, code?, message?, publicData?, privateData?
--   command.normalize(arguments) -> normalizedArguments | nil, code?, message?
--   command.perform(lease, player, normalizedArguments, hostContext)
--       -> accepted, code?, message?, publicData?
--   onRelease(lease, player, reason, hostContext) -> accepted?, code?, message?
-- The caller supplies the authoritative player separately from the request;
-- exact request shapes intentionally have no client-claimable player field.

Authority.RESOURCE_ORDER = {
    "reception_customer",
    "office_computer",
    "skid_wrapper",
    "pallet_jack",
}

Authority.RESOURCES = {
    reception_customer = true,
    office_computer = true,
    skid_wrapper = true,
    pallet_jack = true,
}

Authority.ACTIONS = {
    reception_customer = {
        submit_quote = true,
        decline = true,
    },
    office_computer = {
        request_pickup = true,
    },
    skid_wrapper = {
        select_pallet = true,
        start_cycle = true,
    },
    pallet_jack = {
        lift_pallet = true,
        lower_pallet = true,
        park_jack = true,
    },
}

local UINT32_MAX = 4294967295
local MAX_PLAYER_ID = 4
local DEFAULT_LEASE_TIMEOUT = 10
local DEFAULT_REPLAY_LIMIT = 64
local MAX_FINGERPRINT_DEPTH = 4
local MAX_FINGERPRINT_ENTRIES = 32
local MAX_FINGERPRINT_STRING_BYTES = 512
local CLIENT_RELEASE_REASONS = { closed = true, cancelled = true }

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function integerInRange(value, minimum, maximum)
    return finite(value) and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
    return result
end

local function exactShape(value, required, optional)
    if type(value) ~= "table" then return false, "request must be a table" end
    local allowed = {}
    for _, field in ipairs(required) do allowed[field] = true end
    for _, field in ipairs(optional or {}) do allowed[field] = true end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then
            return false, "request has unknown field: " .. tostring(key)
        end
    end
    for _, field in ipairs(required) do
        if value[field] == nil then return false, "request is missing field: " .. field end
    end
    return true
end

local function playerIdentity(player)
    local id = type(player) == "table" and player.id or player
    if not integerInRange(id, 1, MAX_PLAYER_ID) then
        return nil, "player id must be an integer from 1 to 4"
    end
    return id, "player:" .. tostring(id)
end

local function validToken(value)
    return type(value) == "string" and #value >= 1 and #value <= 64
        and value:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$") ~= nil
end

local function defaultTokenGenerator(serial, resourceId, playerId)
    return string.format("lease-%08x-%s-%d", serial, resourceId, playerId)
end

local function fingerprintValue(value, depth, seen, budget)
    local kind = type(value)
    if kind == "nil" then return "z" end
    if kind == "boolean" then return value and "b1" or "b0" end
    if kind == "number" then
        if not finite(value) then return nil, "request contains a non-finite number" end
        return "n" .. string.format("%.17g", value)
    end
    if kind == "string" then
        if #value > MAX_FINGERPRINT_STRING_BYTES then
            return nil, "request string exceeds the authority limit"
        end
        return "s" .. tostring(#value) .. ":" .. value
    end
    if kind ~= "table" then return nil, "request contains an unsupported value" end
    if depth >= MAX_FINGERPRINT_DEPTH then return nil, "request is nested too deeply" end
    if seen[value] then return nil, "request contains a table cycle" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        if type(key) ~= "string" then
            seen[value] = nil
            return nil, "request tables require string keys"
        end
        budget.count = budget.count + 1
        if budget.count > MAX_FINGERPRINT_ENTRIES then
            seen[value] = nil
            return nil, "request has too many fields"
        end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local parts = { "t{" }
    for _, key in ipairs(keys) do
        local encodedKey = "s" .. tostring(#key) .. ":" .. key
        local encodedValue, encodeError = fingerprintValue(
            value[key], depth + 1, seen, budget)
        if not encodedValue then
            seen[value] = nil
            return nil, encodeError
        end
        parts[#parts + 1] = encodedKey
        parts[#parts + 1] = "="
        parts[#parts + 1] = encodedValue
        parts[#parts + 1] = ";"
    end
    parts[#parts + 1] = "}"
    seen[value] = nil
    return table.concat(parts)
end

local function requestFingerprint(operation, request)
    local encoded, encodeError = fingerprintValue(request, 0, {}, { count = 0 })
    if not encoded then return nil, encodeError end
    return operation .. ":" .. encoded
end

local function publicLease(lease)
    if not lease then return nil end
    return {
        leaseId = lease.leaseId,
        resourceId = lease.resourceId,
        ownerPlayerId = lease.ownerPlayerId,
        acquiredAt = lease.acquiredAt,
        lastSeenAt = lease.lastSeenAt,
        revision = lease.revision,
    }
end

local function baseResult(operation, request, accepted, code, message, revision)
    return {
        operation = operation,
        requestId = request and request.requestId or 0,
        resourceId = request and request.resourceId or "unknown",
        accepted = accepted == true,
        code = tostring(code or (accepted and "accepted" or "rejected")),
        message = tostring(message or (accepted
            and "The workshop request was accepted."
            or "The workshop request was rejected.")),
        revision = math.max(0, math.floor(tonumber(revision) or 0)),
    }
end

local function attachLease(result, lease, data)
    if lease then result.leaseId = lease.leaseId end
    if data ~= nil then result.data = copy(data) end
    return result
end

local function callbackFailure(operation, request, revision)
    return baseResult(operation, request, false, "internal_error",
        "The host could not complete that workshop request.", revision)
end

function Authority.new(options)
    options = options or {}
    local clock = options.clock or function() return os.clock() end
    local tokenGenerator = options.tokenGenerator or defaultTokenGenerator
    local leaseTimeout = tonumber(options.leaseTimeout) or DEFAULT_LEASE_TIMEOUT
    local replayLimit = tonumber(options.replayLimit) or DEFAULT_REPLAY_LIMIT
    assert(type(clock) == "function", "workshop authority clock must be a function")
    assert(type(tokenGenerator) == "function",
        "workshop authority token generator must be a function")
    assert(finite(leaseTimeout) and leaseTimeout > 0,
        "workshop authority lease timeout must be positive")
    assert(integerInRange(replayLimit, 1, 1024),
        "workshop authority replay limit must be an integer from 1 to 1024")

    local resources = options.resources or {}
    assert(type(resources) == "table", "workshop authority resources must be a table")
    for resourceId, spec in pairs(resources) do
        assert(Authority.RESOURCES[resourceId],
            "unsupported workshop resource: " .. tostring(resourceId))
        assert(type(spec) == "table", resourceId .. " resource spec must be a table")
        assert(type(spec.canAcquire) == "function",
            resourceId .. " must provide canAcquire")
        assert(spec.onAcquire == nil or type(spec.onAcquire) == "function",
            resourceId .. " onAcquire must be a function")
        assert(spec.onRelease == nil or type(spec.onRelease) == "function",
            resourceId .. " onRelease must be a function")
        assert(spec.commands == nil or type(spec.commands) == "table",
            resourceId .. " commands must be a table")
        for action, command in pairs(spec.commands or {}) do
            assert(Authority.ACTIONS[resourceId][action],
                "unsupported " .. resourceId .. " action: " .. tostring(action))
            assert(type(command) == "table" and type(command.normalize) == "function"
                and type(command.perform) == "function",
                resourceId .. "." .. action .. " requires normalize and perform callbacks")
        end
    end

    local revisions = {}
    for _, resourceId in ipairs(Authority.RESOURCE_ORDER) do revisions[resourceId] = 0 end
    return setmetatable({
        clock = clock,
        tokenGenerator = tokenGenerator,
        leaseTimeout = leaseTimeout,
        replayLimit = replayLimit,
        resources = resources,
        revisions = revisions,
        leasesByResource = {},
        leasesByPlayer = {},
        leasesById = {},
        replayByPlayer = {},
        tokenSerial = 0,
    }, Authority)
end

function Authority:_ledger(playerKey)
    local ledger = self.replayByPlayer[playerKey]
    if not ledger then
        ledger = { highestId = 0, entries = {}, order = {} }
        self.replayByPlayer[playerKey] = ledger
    end
    return ledger
end

function Authority:_checkReplay(playerKey, requestId, fingerprint, operation, request)
    local ledger = self:_ledger(playerKey)
    local entry = ledger.entries[requestId]
    if entry then
        if entry.fingerprint == fingerprint then return copy(entry.result), true end
        return baseResult(operation, request, false, "request_id_reused",
            "That request ID was already used for different workshop data.",
            self.revisions[request.resourceId] or 0), true
    end
    if requestId <= ledger.highestId then
        return baseResult(operation, request, false, "stale_request",
            "That workshop request is stale.", self.revisions[request.resourceId] or 0), true
    end
    return nil, false
end

function Authority:_remember(playerKey, requestId, fingerprint, result)
    local ledger = self:_ledger(playerKey)
    ledger.highestId = math.max(ledger.highestId, requestId)
    ledger.entries[requestId] = { fingerprint = fingerprint, result = copy(result) }
    ledger.order[#ledger.order + 1] = requestId
    while #ledger.order > self.replayLimit do
        local expired = table.remove(ledger.order, 1)
        ledger.entries[expired] = nil
    end
    return copy(result)
end

function Authority:_rejectNew(playerKey, operation, request, fingerprint, code, message)
    local result = baseResult(operation, request, false, code, message,
        self.revisions[request.resourceId] or 0)
    return self:_remember(playerKey, request.requestId, fingerprint, result)
end

function Authority:_validateCommon(player, request, required, optional)
    local playerId, playerKeyOrError = playerIdentity(player)
    if not playerId then return nil, nil, playerKeyOrError end
    local shaped, shapeError = exactShape(request, required, optional)
    if not shaped then return nil, nil, shapeError end
    if not integerInRange(request.requestId, 1, UINT32_MAX) then
        return nil, nil, "requestId must be a positive 32-bit integer"
    end
    if not Authority.RESOURCES[request.resourceId] then
        return nil, nil, "resourceId is not allowed"
    end
    return playerId, playerKeyOrError
end

function Authority:_newLeaseId(resourceId, playerId)
    self.tokenSerial = self.tokenSerial + 1
    local called, token = pcall(self.tokenGenerator, self.tokenSerial,
        resourceId, playerId, self.clock())
    if not called or not validToken(token) or self.leasesById[token] then return nil end
    return token
end

function Authority:acquire(player, request, context)
    local playerId, playerKey, validationError = self:_validateCommon(
        player, request, { "requestId", "resourceId" })
    if not playerId then
        return baseResult("acquire", type(request) == "table" and request or nil,
            false, "invalid_request", validationError, 0)
    end
    local fingerprint, fingerprintError = requestFingerprint("acquire", request)
    if not fingerprint then
        return baseResult("acquire", request, false, "invalid_request",
            fingerprintError, self.revisions[request.resourceId])
    end
    local replay, handled = self:_checkReplay(playerKey, request.requestId,
        fingerprint, "acquire", request)
    if handled then return replay end

    local owned = self.leasesByPlayer[playerKey]
    if owned then
        if owned.resourceId == request.resourceId then
            owned.lastSeenAt = self.clock()
            local result = attachLease(baseResult("acquire", request, true,
                "already_owned", "This worker already controls that resource.",
                owned.revision), owned, owned.publicData)
            return self:_remember(playerKey, request.requestId, fingerprint, result)
        end
        return self:_rejectNew(playerKey, "acquire", request, fingerprint,
            "player_busy", "Close the current workstation before using another one.")
    end
    local occupied = self.leasesByResource[request.resourceId]
    if occupied then
        return self:_rejectNew(playerKey, "acquire", request, fingerprint,
            "resource_busy", "Another worker is using that resource.")
    end
    local spec = self.resources[request.resourceId]
    if not spec then
        return self:_rejectNew(playerKey, "acquire", request, fingerprint,
            "unavailable", "That workshop resource is not enabled by this host.")
    end

    local called, allowed, code, message = pcall(
        spec.canAcquire, player, context, copy(request))
    if not called then
        local result = callbackFailure("acquire", request,
            self.revisions[request.resourceId])
        return self:_remember(playerKey, request.requestId, fingerprint, result)
    end
    if allowed ~= true then
        return self:_rejectNew(playerKey, "acquire", request, fingerprint,
            code or "out_of_range", message or "Move closer to use that resource.")
    end

    local leaseId = self:_newLeaseId(request.resourceId, playerId)
    if not leaseId then
        local result = callbackFailure("acquire", request,
            self.revisions[request.resourceId])
        return self:_remember(playerKey, request.requestId, fingerprint, result)
    end
    local now = self.clock()
    local lease = {
        leaseId = leaseId,
        resourceId = request.resourceId,
        ownerPlayerId = playerId,
        ownerKey = playerKey,
        player = player,
        acquiredAt = now,
        lastSeenAt = now,
        revision = self.revisions[request.resourceId] + 1,
    }
    local publicData, privateData
    if spec.onAcquire then
        local acquireCalled, acquired, acquireCode, acquireMessage,
            acquirePublic, acquirePrivate = pcall(
                spec.onAcquire, lease, player, context, copy(request))
        if not acquireCalled then
            local result = callbackFailure("acquire", request,
                self.revisions[request.resourceId])
            return self:_remember(playerKey, request.requestId, fingerprint, result)
        end
        if acquired ~= true then
            return self:_rejectNew(playerKey, "acquire", request, fingerprint,
                acquireCode or "unavailable",
                acquireMessage or "That resource could not be opened.")
        end
        code, message = acquireCode, acquireMessage
        publicData, privateData = acquirePublic, acquirePrivate
    end
    lease.publicData = copy(publicData)
    lease.private = privateData
    self.revisions[request.resourceId] = lease.revision
    self.leasesByResource[request.resourceId] = lease
    self.leasesByPlayer[playerKey] = lease
    self.leasesById[leaseId] = lease
    local result = attachLease(baseResult("acquire", request, true,
        code or "acquired", message or "Workshop control granted.",
        lease.revision), lease, publicData)
    return self:_remember(playerKey, request.requestId, fingerprint, result)
end

function Authority:command(player, request, context)
    local playerId, playerKey, validationError = self:_validateCommon(player, request,
        { "requestId", "resourceId", "leaseId", "action", "args" },
        { "expectedRevision" })
    if not playerId then
        return baseResult("command", type(request) == "table" and request or nil,
            false, "invalid_request", validationError, 0)
    end
    if not validToken(request.leaseId) or type(request.action) ~= "string"
        or type(request.args) ~= "table"
        or (request.expectedRevision ~= nil
            and not integerInRange(request.expectedRevision, 0, UINT32_MAX))
    then
        return baseResult("command", request, false, "invalid_request",
            "Command fields are invalid.", self.revisions[request.resourceId])
    end
    local fingerprint, fingerprintError = requestFingerprint("command", request)
    if not fingerprint then
        return baseResult("command", request, false, "invalid_request",
            fingerprintError, self.revisions[request.resourceId])
    end
    local replay, handled = self:_checkReplay(playerKey, request.requestId,
        fingerprint, "command", request)
    if handled then return replay end

    if not Authority.ACTIONS[request.resourceId][request.action] then
        return self:_rejectNew(playerKey, "command", request, fingerprint,
            "action_not_allowed", "That action is not allowed for this resource.")
    end
    local spec = self.resources[request.resourceId]
    local commandSpec = spec and spec.commands and spec.commands[request.action]
    if not commandSpec then
        return self:_rejectNew(playerKey, "command", request, fingerprint,
            "unavailable", "That workshop action is not enabled by this host.")
    end
    local normalizedCalled, normalized, normalizeCode, normalizeMessage = pcall(
        commandSpec.normalize, copy(request.args))
    if not normalizedCalled then
        local result = callbackFailure("command", request,
            self.revisions[request.resourceId])
        return self:_remember(playerKey, request.requestId, fingerprint, result)
    end
    if type(normalized) ~= "table" then
        return self:_rejectNew(playerKey, "command", request, fingerprint,
            normalizeCode or "invalid_arguments",
            normalizeMessage or "That workshop action has invalid arguments.")
    end

    local lease = self.leasesById[request.leaseId]
    if not lease or lease.resourceId ~= request.resourceId then
        return self:_rejectNew(playerKey, "command", request, fingerprint,
            "lease_not_found", "That workshop lease is no longer active.")
    end
    if lease.ownerKey ~= playerKey or lease.ownerPlayerId ~= playerId then
        return self:_rejectNew(playerKey, "command", request, fingerprint,
            "not_owner", "Another worker owns that workshop lease.")
    end
    if request.expectedRevision ~= nil
        and request.expectedRevision ~= self.revisions[request.resourceId]
    then
        return self:_rejectNew(playerKey, "command", request, fingerprint,
            "revision_conflict", "The resource changed; refresh before trying again.")
    end
    lease.lastSeenAt = self.clock()
    local performed, accepted, code, message, data = pcall(
        commandSpec.perform, lease, player, normalized, context)
    if not performed then
        local result = callbackFailure("command", request,
            self.revisions[request.resourceId])
        return self:_remember(playerKey, request.requestId, fingerprint, result)
    end
    if accepted == true then
        self.revisions[request.resourceId] = self.revisions[request.resourceId] + 1
        lease.revision = self.revisions[request.resourceId]
        if data ~= nil then lease.publicData = copy(data) end
    end
    local result = attachLease(baseResult("command", request, accepted,
        code or (accepted and "accepted" or "rejected"),
        message or (accepted and "Workshop action completed."
            or "The host rejected that workshop action."),
        self.revisions[request.resourceId]), lease, data)
    return self:_remember(playerKey, request.requestId, fingerprint, result)
end

function Authority:_endLease(lease, reason, context)
    local spec = self.resources[lease.resourceId]
    local cleanupAccepted, cleanupCode, cleanupMessage = true, nil, nil
    if spec and spec.onRelease then
        local called, accepted, code, message = pcall(
            spec.onRelease, lease, lease.player, reason, context)
        if not called then
            cleanupAccepted, cleanupCode, cleanupMessage = false, "internal_error",
                "The resource cleanup callback failed."
        elseif accepted == false then
            cleanupAccepted, cleanupCode, cleanupMessage = false,
                code or "cleanup_failed", message or "The resource could not clean up normally."
        end
    end
    self.leasesByResource[lease.resourceId] = nil
    self.leasesByPlayer[lease.ownerKey] = nil
    self.leasesById[lease.leaseId] = nil
    self.revisions[lease.resourceId] = self.revisions[lease.resourceId] + 1
    lease.revision = self.revisions[lease.resourceId]
    return {
        type = "lease_released",
        resourceId = lease.resourceId,
        leaseId = lease.leaseId,
        ownerPlayerId = lease.ownerPlayerId,
        revision = lease.revision,
        reason = tostring(reason or "released"),
        cleanupAccepted = cleanupAccepted,
        code = cleanupCode,
        message = cleanupMessage,
    }
end

function Authority:release(player, request, context)
    local _, playerKey, validationError = self:_validateCommon(player, request,
        { "requestId", "resourceId", "leaseId" }, { "reason" })
    if not playerKey then
        return baseResult("release", type(request) == "table" and request or nil,
            false, "invalid_request", validationError, 0)
    end
    if not validToken(request.leaseId)
        or (request.reason ~= nil and not CLIENT_RELEASE_REASONS[request.reason])
    then
        return baseResult("release", request, false, "invalid_request",
            "Release fields are invalid.", self.revisions[request.resourceId])
    end
    local fingerprint, fingerprintError = requestFingerprint("release", request)
    if not fingerprint then
        return baseResult("release", request, false, "invalid_request",
            fingerprintError, self.revisions[request.resourceId])
    end
    local replay, handled = self:_checkReplay(playerKey, request.requestId,
        fingerprint, "release", request)
    if handled then return replay end
    local lease = self.leasesById[request.leaseId]
    if not lease or lease.resourceId ~= request.resourceId then
        return self:_rejectNew(playerKey, "release", request, fingerprint,
            "lease_not_found", "That workshop lease is no longer active.")
    end
    if lease.ownerKey ~= playerKey then
        return self:_rejectNew(playerKey, "release", request, fingerprint,
            "not_owner", "Another worker owns that workshop lease.")
    end
    local event = self:_endLease(lease, request.reason or "closed", context)
    local code = event.cleanupAccepted and "released" or "released_with_cleanup_error"
    local message = event.cleanupAccepted and "Workshop control released."
        or tostring(event.message or "Workshop control released, but cleanup needs attention.")
    local result = attachLease(baseResult("release", request, true, code, message,
        event.revision), lease)
    result.reason = event.reason
    return self:_remember(playerKey, request.requestId, fingerprint, result)
end

function Authority:touchPlayer(player)
    local _, playerKey = playerIdentity(player)
    if not playerKey then return false end
    local lease = self.leasesByPlayer[playerKey]
    if not lease then return false end
    lease.lastSeenAt = self.clock()
    return true
end

function Authority:update(context)
    local now = self.clock()
    local expired = {}
    for _, resourceId in ipairs(Authority.RESOURCE_ORDER) do
        local lease = self.leasesByResource[resourceId]
        if lease and now - lease.lastSeenAt >= self.leaseTimeout then
            expired[#expired + 1] = lease
        end
    end
    local events = {}
    for _, lease in ipairs(expired) do
        events[#events + 1] = self:_endLease(lease, "timeout", context)
    end
    return events
end

function Authority:cleanupPlayer(player, reason, context)
    local _, playerKey = playerIdentity(player)
    if not playerKey then return {} end
    local events = {}
    local lease = self.leasesByPlayer[playerKey]
    if lease then
        events[1] = self:_endLease(lease, reason or "disconnected", context)
    end
    self.replayByPlayer[playerKey] = nil
    return events
end

function Authority:leaseForResource(resourceId)
    if not Authority.RESOURCES[resourceId] then return nil end
    return publicLease(self.leasesByResource[resourceId])
end

function Authority:leaseForPlayer(player)
    local _, playerKey = playerIdentity(player)
    if not playerKey then return nil end
    return publicLease(self.leasesByPlayer[playerKey])
end

function Authority:resourceRevision(resourceId)
    return Authority.RESOURCES[resourceId] and self.revisions[resourceId] or nil
end

function Authority:snapshot()
    local resources = {}
    for _, resourceId in ipairs(Authority.RESOURCE_ORDER) do
        local lease = self.leasesByResource[resourceId]
        resources[#resources + 1] = {
            resourceId = resourceId,
            revision = self.revisions[resourceId],
            occupied = lease ~= nil,
        }
        if lease then resources[#resources].ownerPlayerId = lease.ownerPlayerId end
    end
    return resources
end

return Authority
