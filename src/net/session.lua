local Address = require("src.net.address")
local Codec = require("src.net.codec")
local Protocol = require("src.net.protocol")
local MachineResource = require("src.machine_resource_id")
local Transport = require("src.net.transport_enet")

local Session = {}
Session.__index = Session

local INPUT_INTERVAL = 1 / 20
local SNAPSHOT_INTERVAL = 1 / 12
local SHOP_STATE_INTERVAL = 0.25
local SHOP_STATE_FALLBACK_INTERVAL = 30
local INPUT_HOLD_TIMEOUT = 0.35
local CONNECT_TIMEOUT = 10
local DIRECT_APPROVAL_TIMEOUT = 60
local DIRECT_CLIENT_TIMEOUT = CONNECT_TIMEOUT + DIRECT_APPROVAL_TIMEOUT
local TELEPORT_DISTANCE = 140
local CORRECTION_RATE = 12
local REMOTE_SMOOTH_RATE = 14
local INTERACTION_RATE_LIMIT = 0.20
local INTERACTION_TIMEOUT = 3
local WORKSHOP_TIMEOUT = 4
local PROTOCOL_REJECTION_INTERVAL = 1
local NETWORK_CLEANUP_ERROR =
    "Network cleanup could not be verified; restart the game before starting another session."

local function urgentWorkshopSafety(resourceId, action, arguments)
    resourceId = MachineResource.parse(resourceId) or resourceId
    if action == "emergency_stop" then
        return resourceId == "cutter" or resourceId == "windmill"
    end
    return resourceId == "cutter" and action == "set_barrier"
        and type(arguments) == "table" and arguments.barrierClear == false
end

local function defaultClock()
    if love and love.timer and love.timer.getTime then return love.timer.getTime() end
    return os.clock()
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or 0
    return math.max(minimum, math.min(maximum, value))
end

local function countEntries(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

local function directDisplayName(value)
    if type(value) ~= "string" or #value < 1 or #value > Protocol.MAX_NAME_BYTES then
        return nil
    end
    -- Direct join names are self-asserted and cross an Internet trust boundary.
    -- Keep the first approval UI deliberately ASCII-only so malformed UTF-8,
    -- bidi controls, and invisible formatting cannot spoof another worker.
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 32 or byte > 126 then return nil end
    end
    return value
end

local function sameHello(left, right)
    return type(left) == "table" and type(right) == "table"
        and left.clientNonce == right.clientNonce
        and left.name == right.name
        and left.character == right.character
end

local function removePeerItems(items, peer)
    local kept = {}
    for _, item in ipairs(items or {}) do
        if item.peer ~= peer then kept[#kept + 1] = item end
    end
    return kept
end

local function wireWorkshopView(resourceId, view)
    if type(view) ~= "table" then return view end
    resourceId = MachineResource.parse(resourceId) or resourceId
    if resourceId == "reception_customer" and type(view.quoteRows) == "table" then
        if not Codec.isArray(view.quoteRows) then
            view.quoteRows = Codec.array(view.quoteRows)
        end
    elseif (resourceId == "vendor" or resourceId == "truck")
        and type(view.items) == "table"
    then
        if not Codec.isArray(view.items) then view.items = Codec.array(view.items) end
    elseif resourceId == "skid_wrapper" and type(view.pallets) == "table" then
        if not Codec.isArray(view.pallets) then
            view.pallets = Codec.array(view.pallets)
        end
    elseif resourceId == "cutter" then
        if type(view.memoryCentiInch) == "table"
            and not Codec.isArray(view.memoryCentiInch)
        then
            view.memoryCentiInch = Codec.array(view.memoryCentiInch)
        end
        if type(view.candidates) == "table" and not Codec.isArray(view.candidates) then
            view.candidates = Codec.array(view.candidates)
        end
        if type(view.serviceItems) == "table" and not Codec.isArray(view.serviceItems) then
            view.serviceItems = Codec.array(view.serviceItems)
        end
    elseif resourceId == "windmill" then
        if type(view.setupPermille) == "table" and not Codec.isArray(view.setupPermille) then
            view.setupPermille = Codec.array(view.setupPermille)
        end
        if type(view.candidates) == "table" and not Codec.isArray(view.candidates) then
            view.candidates = Codec.array(view.candidates)
        end
    end
    return view
end

local function identifier(prefix, clock)
    local seconds = math.floor((clock() or 0) * 1000) % 0x7fffffff
    local random = math.random(0, 0x7fffffff)
    return string.format("%s%08x%08x", prefix, seconds, random)
end

local function newPlayer(record)
    record = record or {}
    return {
        id = tonumber(record.id),
        name = record.name or "Worker",
        character = record.character or "rabbit-worker",
        x = tonumber(record.x) or 0,
        y = tonumber(record.y) or 0,
        speed = tonumber(record.speed) or 0,
        velocityX = tonumber(record.velocityX) or 0,
        velocityY = tonumber(record.velocityY) or 0,
        intentX = tonumber(record.intentX) or 1,
        intentY = tonumber(record.intentY) or 0,
        moving = record.moving == true,
        facing = record.facing == -1 and -1 or 1,
        animationDistance = tonumber(record.animationDistance) or 0,
        idleClock = tonumber(record.idleClock) or 0,
        interactionClock = 0,
        lastInteractionRequestId = 0,
        lastInteractionResult = nil,
        lastInteractionFingerprint = nil,
        lastInteractionAt = -math.huge,
        lastInteractionDuplicateReplyAt = -math.huge,
        lastInteractionRejectReplyAt = -math.huge,
        inputSequence = tonumber(record.inputSequence) or 0,
        _targetX = tonumber(record.x) or 0,
        _targetY = tonumber(record.y) or 0,
    }
end

local function copyMotion(target, source, includePosition)
    if not target or not source then return end
    if includePosition then
        if finite(source.x) then target.x = source.x end
        if finite(source.y) then target.y = source.y end
    end
    if finite(source.velocityX) then target.velocityX = source.velocityX end
    if finite(source.velocityY) then target.velocityY = source.velocityY end
    if finite(source.intentX) then target.intentX = source.intentX end
    if finite(source.intentY) then target.intentY = source.intentY end
    if finite(source.animationDistance) then target.animationDistance = source.animationDistance end
    if source.facing == -1 or source.facing == 1 then target.facing = source.facing end
    if type(source.moving) == "boolean" then target.moving = source.moving end
    if type(source.character) == "string" then target.character = source.character end
end

local function playerRecord(player)
    return {
        id = tonumber(player.id),
        name = tostring(player.name or "Worker"),
        x = tonumber(player.x) or 0,
        y = tonumber(player.y) or 0,
        velocityX = tonumber(player.velocityX) or 0,
        velocityY = tonumber(player.velocityY) or 0,
        intentX = tonumber(player.intentX) or 0,
        intentY = tonumber(player.intentY) or 0,
        moving = player.moving == true,
        facing = player.facing == -1 and -1 or 1,
        animationDistance = tonumber(player.animationDistance) or 0,
        character = tostring(player.character or "rabbit-worker"),
        inputSequence = tonumber(player.inputSequence) or 0,
    }
end

function Session.new(options)
    options = options or {}
    return setmetatable({
        mode = "offline",
        status = "Offline",
        networkKind = "lan",
        transportFactory = options.transportFactory or Transport,
        clock = options.clock or defaultClock,
        transport = nil,
        players = {},
        peerToId = {},
        idToPeer = {},
        pendingPeers = {},
        approvalRequests = {},
        protocolRejectionAt = {},
        nextConnectionGeneration = 0,
        nextJoinRequestId = 0,
        pendingEvents = {},
        sessionId = nil,
        localId = nil,
        localName = nil,
        localCharacter = nil,
        localAddress = nil,
        port = Address.DEFAULT_PORT,
        serverTick = 0,
        lastServerTick = -1,
        lastPlayerTicks = {},
        inputSequence = 0,
        inputAccumulator = 0,
        snapshotAccumulator = 0,
        shopStateAccumulator = 0,
        shopFallbackAccumulator = 0,
        shopRevision = 0,
        lastShopRevision = -1,
        lastVisitorTick = -1,
        lastEnvironmentTick = -1,
        lastPalletJackTick = -1,
        lastForkliftTick = -1,
        lastCutterTick = -1,
        lastWindmillTick = -1,
        lastMachineTicks = {},
        shopDirty = false,
        connectedAt = nil,
        ready = false,
        requireHostApproval = false,
        clientConnectTimeout = CONNECT_TIMEOUT,
        disconnectReason = nil,
        localTarget = nil,
        pendingShopSnapshot = nil,
        pendingShopState = nil,
        interactionRequestId = 0,
        pendingInteraction = nil,
        pendingHostInteractions = {},
        workshopRequestId = 0,
        pendingWorkshop = nil,
        pendingWorkshopSafety = nil,
        activeWorkshop = nil,
        workshopRevisions = {},
        workshopResources = {},
        pendingHostWorkshop = {},
        lastWorkshopSnapshotRevision = -1,
    }, Session)
end

function Session:_queue(eventType, values)
    local event = values or {}
    event.type = eventType
    self.pendingEvents[#self.pendingEvents + 1] = event
end

function Session:drainEvents()
    local events = self.pendingEvents
    self.pendingEvents = {}
    return events
end

function Session:isHost() return self.mode == "host" end
function Session:isClient() return self.mode == "client" end
function Session:isActive() return self.mode ~= "offline" end

function Session:_closeTransport(code, immediate)
    local transport = self.transport
    if not transport then return true end
    local called, cleaned = pcall(transport.close, transport,
        code or 0, immediate == true)
    if called and cleaned == true then
        self.transport = nil
        return true
    end
    -- Keep the owner reachable. A failed close cannot be upgraded to success
    -- merely because a later idempotent call observes an already-closed wrapper.
    return false, NETWORK_CLEANUP_ERROR
end

function Session:_resetRuntime()
    self.players = {}
    self.peerToId = {}
    self.idToPeer = {}
    self.pendingPeers = {}
    self.approvalRequests = {}
    self.protocolRejectionAt = {}
    self.pendingEvents = {}
    self.sessionId = nil
    self.localId = nil
    self.localName = nil
    self.localCharacter = nil
    self.localAddress = nil
    self.hostAddress = nil
    self.networkKind = "lan"
    self.serverTick = 0
    self.lastServerTick = -1
    self.lastPlayerTicks = {}
    self.inputSequence = 0
    self.inputAccumulator = 0
    self.snapshotAccumulator = 0
    self.shopStateAccumulator = 0
    self.shopFallbackAccumulator = 0
    self.shopRevision = 0
    self.lastShopRevision = -1
    self.lastVisitorTick = -1
    self.lastEnvironmentTick = -1
    self.lastPalletJackTick = -1
    self.lastForkliftTick = -1
    self.lastCutterTick = -1
    self.lastWindmillTick = -1
    self.lastMachineTicks = {}
    self.shopDirty = false
    self.connectedAt = nil
    self.ready = false
    self.requireHostApproval = false
    self.clientConnectTimeout = CONNECT_TIMEOUT
    self.disconnectReason = nil
    self.localTarget = nil
    self.pendingShopSnapshot = nil
    self.pendingShopState = nil
    self.interactionRequestId = 0
    self.pendingInteraction = nil
    self.pendingHostInteractions = {}
    self.workshopRequestId = 0
    self.pendingWorkshop = nil
    self.pendingWorkshopSafety = nil
    self.activeWorkshop = nil
    self.workshopRevisions = {}
    self.workshopResources = {}
    self.pendingHostWorkshop = {}
    self.lastWorkshopSnapshotRevision = -1
    self.clientNonce = nil
    self.rtt = nil
    self.pendingPing = {}
    self.terminal = false
end

function Session:_markDisconnected(message)
    if self.terminal then return false end
    self.terminal = true
    self.ready = false
    self.connectedAt = nil
    self.status = tostring(message or "The multiplayer connection ended.")
    self:_queue("disconnected", { message = self.status })
    return true
end

function Session:stop(reason)
    reason = tostring(reason or "Session closed")
    if self.transport and self.mode == "client" and self.sessionId and self.localId then
        self:_sendToServer("leave", {
            sessionId = self.sessionId,
            playerId = self.localId,
            reason = reason,
            serverTick = math.max(0, self.lastServerTick),
        })
        self.transport:flush()
    elseif self.transport and self.mode == "host" and self.sessionId then
        self:_broadcastJoined("leave", {
            sessionId = self.sessionId,
            playerId = self.localId or 1,
            reason = reason,
            serverTick = self.serverTick,
        })
        self.transport:flush()
    end
    local cleaned, cleanupError = self:_closeTransport(0, false)
    self.mode, self.status = "offline", "Offline"
    self:_resetRuntime()
    return cleaned, cleanupError
end

function Session:startHost(options)
    options = options or {}
    if self:isActive() then
        local stopped, stopError = self:stop("Starting another session")
        if not stopped then return false, stopError end
    elseif self.transport then
        local cleaned, cleanupError = self:_closeTransport(0, true)
        if not cleaned then return false, cleanupError end
    end
    local port = tonumber(options.port) or Address.DEFAULT_PORT
    local transportFactory = options.transportFactory or self.transportFactory
    if type(transportFactory) ~= "table"
        or type(transportFactory.createHost) ~= "function" then
        return false, "Network transport is unavailable."
    end
    local transport, errorMessage = transportFactory.createHost({
        port = port,
        bind = options.bind or "*",
        maxGuests = Protocol.MAX_PLAYERS - 1,
        channels = Protocol.CHANNEL_COUNT,
        enet = options.enet,
    })
    if not transport then return false, errorMessage end
    self:_resetRuntime()
    self.transport = transport
    self.mode = "host"
    self.networkKind = options.networkKind == "direct" and "direct" or "lan"
    -- Internet Direct always requires a final, in-game host decision. This is
    -- intentionally not controlled by a caller option: no production path may
    -- silently auto-admit an Internet peer and disclose the host save.
    self.requireHostApproval = self.networkKind == "direct"
    self.port = port
    self.sessionId = identifier("s", self.clock)
    self.localId = 1
    self.localName = tostring(options.name or "LAN Host")
    self.localCharacter = tostring(options.character or "rabbit-worker")
    self.localAddress = self.networkKind == "lan"
        and Address.detectLanAddress(options.addressOptions or {}) or nil
    self.players[1] = newPlayer({
        id = 1, name = self.localName, character = self.localCharacter,
        x = tonumber(options.x) or 0, y = tonumber(options.y) or 0,
    })
    self.ready = true
    self.status = self.networkKind == "direct"
        and "Hosting a Direct Internet shop"
        or ("Hosting on " .. tostring(self.localAddress or "local network"))
    self:_queue("host_started", {
        address = self.localAddress,
        port = self.port,
        sessionId = self.sessionId,
        networkKind = self.networkKind,
    })
    return true
end

function Session:startClient(address, options)
    options = options or {}
    if self:isActive() then
        local stopped, stopError = self:stop("Starting another session")
        if not stopped then return false, stopError end
    elseif self.transport then
        local cleaned, cleanupError = self:_closeTransport(0, true)
        if not cleaned then return false, cleanupError end
    end
    local parsed, addressError = Address.parse(address, options.port)
    if not parsed then return false, addressError end
    local transportFactory = options.transportFactory or self.transportFactory
    if type(transportFactory) ~= "table"
        or type(transportFactory.createClient) ~= "function" then
        return false, "Network transport is unavailable."
    end
    local transport, errorMessage = transportFactory.createClient(parsed.endpoint, {
        channels = Protocol.CHANNEL_COUNT,
        enet = options.enet,
    })
    if not transport then return false, errorMessage end
    self:_resetRuntime()
    self.transport = transport
    self.mode = "client"
    self.networkKind = options.networkKind == "direct" and "direct" or "lan"
    self.clientConnectTimeout = self.networkKind == "direct"
        and DIRECT_CLIENT_TIMEOUT or CONNECT_TIMEOUT
    self.port = parsed.port
    self.hostAddress = parsed.host
    self.localName = tostring(options.name or "LAN Worker")
    self.localCharacter = tostring(options.character or "rabbit-worker")
    self.clientNonce = identifier("n", self.clock)
    self.connectedAt = self.clock()
    self.status = self.networkKind == "direct"
        and "Connecting to the Direct Internet host"
        or ("Connecting to " .. parsed.endpoint)
    return true
end

function Session:_encode(kind, payload)
    return Protocol.encode(kind, payload)
end

function Session:_route(kind)
    local channel, delivery = Protocol.route(kind)
    return channel, delivery == "reliable"
end

function Session:_send(peer, kind, payload)
    local encoded, encodeError = self:_encode(kind, payload)
    if not encoded then return false, encodeError end
    local channel, reliable = self:_route(kind)
    return self.transport:send(peer, encoded, channel, reliable)
end

function Session:_sendToServer(kind, payload)
    if not self.transport then return false, "Transport is unavailable." end
    local encoded, encodeError = self:_encode(kind, payload)
    if not encoded then return false, encodeError end
    local channel, reliable = self:_route(kind)
    return self.transport:sendToServer(encoded, channel, reliable)
end

function Session:_broadcast(kind, payload)
    if not self.transport then return false, "Transport is unavailable." end
    local encoded, encodeError = self:_encode(kind, payload)
    if not encoded then return false, encodeError end
    local channel, reliable = self:_route(kind)
    return self.transport:broadcast(encoded, channel, reliable)
end

-- Full shop snapshots contain the player's entire durable save state. Send
-- them only to peers that completed the hello/welcome handshake; ENet's host
-- broadcast also includes sockets still waiting in pendingPeers.
function Session:_broadcastJoined(kind, payload)
    if not self.transport then return false, "Transport is unavailable.", 0 end
    local encoded, encodeError = self:_encode(kind, payload)
    if not encoded then return false, encodeError, 0 end
    local channel, reliable = self:_route(kind)
    local sent = 0
    for _, peer in pairs(self.idToPeer) do
        local ok, sendError = self.transport:send(peer, encoded, channel, reliable)
        if not ok then return false, sendError, sent end
        sent = sent + 1
    end
    return true, nil, sent
end

function Session:_sendError(peer, code, message)
    return self:_send(peer, "error", {
        code = tostring(code or "network_error"),
        message = tostring(message or "The network request was rejected."),
        sessionId = self.sessionId,
    })
end

function Session:_sendProtocolRejection(peer, code, message)
    -- Malformed and host-only packet families share one reply token so an
    -- abusive peer cannot rotate error codes into a reliable-response flood.
    -- Consume the token before attempting the send; a failed send must not
    -- grant another immediate attempt.
    if not peer or (not self.pendingPeers[peer] and not self.peerToId[peer]) then
        return false, "Network peer is no longer active."
    end
    local now = self.clock()
    if not finite(now) then return false, "Network clock is unavailable." end
    local previous = self.protocolRejectionAt[peer]
    if previous ~= nil then
        if not finite(previous) or now < previous
            or now - previous < PROTOCOL_REJECTION_INTERVAL
        then
            return false, "Protocol rejection reply is rate limited."
        end
    end
    self.protocolRejectionAt[peer] = now
    return self:_sendError(peer, code, message)
end

function Session:_sendInteractionResult(peer, request, accepted, code, message)
    return self:_send(peer, "interaction_result", {
        sessionId = self.sessionId,
        requestId = request.requestId,
        targetKind = request.targetKind,
        accepted = accepted == true,
        code = tostring(code or "rejected"),
        message = tostring(message or "The host rejected that interaction."),
    })
end

function Session:_processHostInteractions(context)
    local queued = self.pendingHostInteractions
    self.pendingHostInteractions = {}
    for _, item in ipairs(queued) do
        local peer, request = item.peer, item.request
        local id = self.peerToId[peer]
        local player = id and self.players[id]
        if player and id == item.playerId and request.sessionId == self.sessionId then
            local lastId = player.lastInteractionRequestId or 0
            local now = self.clock()
            local fingerprint = tostring(request.targetKind) .. ":" .. tostring(request.desiredState)
            if request.requestId == lastId and player.lastInteractionResult
                and player.lastInteractionFingerprint ~= fingerprint
            then
                if now - (player.lastInteractionRejectReplyAt or -math.huge)
                    >= INTERACTION_RATE_LIMIT
                then
                    self:_sendInteractionResult(peer, request, false, "request_id_reused",
                        "That request ID was already used for a different interaction.")
                    player.lastInteractionRejectReplyAt = now
                end
            elseif request.requestId == lastId and player.lastInteractionResult then
                if now - (player.lastInteractionDuplicateReplyAt or -math.huge)
                    >= INTERACTION_RATE_LIMIT
                then
                    self:_send(peer, "interaction_result", player.lastInteractionResult)
                    player.lastInteractionDuplicateReplyAt = now
                end
            elseif request.requestId < lastId then
                if now - (player.lastInteractionRejectReplyAt or -math.huge)
                    >= INTERACTION_RATE_LIMIT
                then
                    self:_sendInteractionResult(peer, request, false, "stale_request",
                        "That interaction request is stale.")
                    player.lastInteractionRejectReplyAt = now
                end
            else
                local accepted, code, message = false, "unavailable",
                    "The host cannot process that interaction right now."
                if now - (player.lastInteractionAt or -math.huge) < INTERACTION_RATE_LIMIT then
                    code = "rate_limited"
                    message = "Please wait a moment before using the switch again."
                elseif context and type(context.performInteraction) == "function" then
                    local called, result, resultCode, resultMessage = pcall(
                        context.performInteraction, player, request.targetKind,
                        request.desiredState)
                    if called then
                        accepted = result == true
                        code = tostring(resultCode or (accepted and "accepted" or "rejected"))
                        message = tostring(resultMessage or (accepted
                            and "The host accepted the interaction."
                            or "The host rejected the interaction."))
                    else
                        code = "internal_error"
                        message = "The host could not complete that interaction."
                    end
                end
                player.lastInteractionRequestId = request.requestId
                player.lastInteractionFingerprint = fingerprint
                player.lastInteractionAt = now
                player.lastInteractionResult = {
                    sessionId = self.sessionId,
                    requestId = request.requestId,
                    targetKind = request.targetKind,
                    accepted = accepted,
                    code = code,
                    message = message,
                }
                local shouldReply = code ~= "rate_limited"
                    or now - (player.lastInteractionRejectReplyAt or -math.huge)
                        >= INTERACTION_RATE_LIMIT
                if shouldReply then
                    local ok, sendError = self:_send(peer, "interaction_result",
                        player.lastInteractionResult)
                    if code == "rate_limited" then player.lastInteractionRejectReplyAt = now end
                    if not ok then self:_queue("error", { message = sendError }) end
                end
            end
        end
    end
end

function Session:_processHostWorkshop(context)
    local queued = self.pendingHostWorkshop
    self.pendingHostWorkshop = {}
    local ordered = {}
    for _, item in ipairs(queued) do
        local payload = item.payload
        if item.operation == "workshop_command"
            and urgentWorkshopSafety(payload.resourceId, payload.action, payload)
        then
            ordered[#ordered + 1] = item
        end
    end
    for _, item in ipairs(queued) do
        local payload = item.payload
        if item.operation ~= "workshop_command"
            or not urgentWorkshopSafety(payload.resourceId, payload.action, payload)
        then
            ordered[#ordered + 1] = item
        end
    end
    for _, item in ipairs(ordered) do
        local peer, payload = item.peer, item.payload
        local id = self.peerToId[peer]
        local player = id and self.players[id]
        if player and id == item.playerId and payload.sessionId == self.sessionId then
            local result
            if context and type(context.performWorkshop) == "function" then
                local called, value = pcall(context.performWorkshop,
                    player, item.operation, payload)
                if called and type(value) == "table" then result = value end
            end
            result = result or {
                accepted = false,
                code = "internal_error",
                message = "The host could not complete that workshop request.",
                revision = 0,
            }
            if item.operation == "workshop_acquire" then
                local response = {
                    sessionId = self.sessionId,
                    requestId = payload.requestId,
                    resourceId = payload.resourceId,
                    granted = result.accepted == true,
                    code = tostring(result.code or "rejected"),
                    message = tostring(result.message or "The workshop request was rejected."),
                    revision = math.max(0, math.floor(tonumber(result.revision) or 0)),
                }
                if response.granted then response.leaseId = result.leaseId end
                if result.data ~= nil then
                    response.view = wireWorkshopView(payload.resourceId, result.data)
                end
                local ok, sendError = self:_send(peer, "workshop_grant", response)
                if not ok then self:_queue("error", { message = sendError }) end
            elseif item.operation == "workshop_command" then
                local response = {
                    sessionId = self.sessionId,
                    commandId = payload.commandId,
                    resourceId = payload.resourceId,
                    action = payload.action,
                    accepted = result.accepted == true,
                    code = tostring(result.code or "rejected"),
                    message = tostring(result.message or "The workshop action was rejected."),
                    revision = math.max(0, math.floor(tonumber(result.revision) or 0)),
                }
                if result.data ~= nil then
                    response.view = wireWorkshopView(payload.resourceId, result.data)
                end
                local ok, sendError = self:_send(peer, "workshop_result", response)
                if not ok then self:_queue("error", { message = sendError }) end
            elseif item.operation == "workshop_release" and result.accepted ~= true then
                self:_sendError(peer, tostring(result.code or "release_failed"),
                    tostring(result.message or "Workshop control could not be released cleanly."))
            end
        end
    end
end

function Session:_records()
    local ids = {}
    for id in pairs(self.players) do ids[#ids + 1] = id end
    table.sort(ids)
    local records = {}
    for _, id in ipairs(ids) do records[#records + 1] = playerRecord(self.players[id]) end
    return records
end

function Session:_syncLocalPlayer(localPlayer)
    local player = self.localId and self.players[self.localId]
    if not player or not localPlayer then return end
    copyMotion(player, localPlayer, true)
    player.name = self.localName or player.name
    player.character = localPlayer.character or self.localCharacter or player.character
end

function Session:_nextPlayerId()
    for index = 2, Protocol.MAX_PLAYERS do
        if not self.players[index] then return index, index end
    end
end

function Session:_nextRuntimeHandle(field)
    local current = self[field]
    if type(current) ~= "number" or current ~= math.floor(current)
        or current < 0 or current >= 9007199254740991
    then
        return nil
    end
    current = current + 1
    self[field] = current
    return current
end

function Session:_discardPendingPeer(peer)
    local pending = self.pendingPeers[peer]
    self.pendingPeers[peer] = nil
    if type(pending) == "table" and pending.requestId then
        if self.approvalRequests[pending.requestId] == pending then
            self.approvalRequests[pending.requestId] = nil
        end
    end
    return pending
end

function Session:_purgePeerWork(peer)
    self.pendingHostInteractions = removePeerItems(self.pendingHostInteractions, peer)
    self.pendingHostWorkshop = removePeerItems(self.pendingHostWorkshop, peer)
end

function Session:_rejectDirectPending(peer, code, guestMessage, hostMessage, eventType)
    local pending = self:_discardPendingPeer(peer)
    if not pending then return false end
    self.protocolRejectionAt[peer] = nil
    self:_purgePeerWork(peer)
    if self.transport then
        self:_sendError(peer, tostring(code or "join_rejected"),
            tostring(guestMessage or "The host did not admit this Direct connection."))
        self.transport:flush()
        self.transport:disconnect(peer, 7, false)
    end
    self:_queue(eventType or "join_rejected", {
        requestId = type(pending) == "table" and pending.requestId or nil,
        name = type(pending) == "table" and pending.name or nil,
    })
    self.status = tostring(hostMessage or "Direct join request closed safely.")
    return true
end

function Session:_queueDirectApproval(peer, hello)
    local pending = self.pendingPeers[peer]
    if type(pending) ~= "table" or pending.stage ~= "hello" then return false end
    local name = directDisplayName(hello and hello.payload and hello.payload.name)
    if not name then
        return self:_rejectDirectPending(peer, "invalid_join",
            "That Direct player name cannot be displayed safely.",
            "One Direct join was rejected because its player name was invalid.")
    end
    if countEntries(self.players) >= Protocol.MAX_PLAYERS then
        return self:_rejectDirectPending(peer, "shop_full",
            "This Direct shop already has four workers.",
            "Direct join declined because the shop is full.")
    end
    local requestId = self:_nextRuntimeHandle("nextJoinRequestId")
    if not requestId then
        return self:_rejectDirectPending(peer, "join_unavailable",
            "The Direct invitation cannot accept this request.",
            "That Direct join could not be tracked safely.")
    end
    local now = self.clock()
    if not finite(now) then
        return self:_rejectDirectPending(peer, "join_unavailable",
            "The Direct invitation cannot accept this request.",
            "That Direct join was declined because its approval clock was unavailable.")
    end
    pending.stage = "approval"
    pending.requestId = requestId
    pending.requestedAt = now
    pending.hello = {
        type = "hello",
        payload = {
            clientNonce = hello.payload.clientNonce,
            name = name,
            character = hello.payload.character,
        },
    }
    pending.name = name
    pending.character = hello.payload.character
    self.approvalRequests[requestId] = pending
    self.status = "Direct worker waiting for host approval"
    self:_queue("join_requested", {
        requestId = requestId,
        name = name,
        character = pending.character,
        expiresIn = DIRECT_APPROVAL_TIMEOUT,
    })
    return true
end

function Session:approveJoin(requestId)
    if not self:isHost() or self.networkKind ~= "direct" or self.terminal then
        return false, "No Direct join request is available."
    end
    if type(requestId) ~= "number" or requestId ~= math.floor(requestId) then
        return false, "That Direct join request is no longer available."
    end
    local pending = self.approvalRequests[requestId]
    if type(pending) ~= "table" or pending.stage ~= "approval"
        or self.pendingPeers[pending.peer] ~= pending
    then
        return false, "That Direct join request is no longer available."
    end
    local now = self.clock()
    if not finite(now) or now < pending.requestedAt
        or now - pending.requestedAt > DIRECT_APPROVAL_TIMEOUT
    then
        self:_rejectDirectPending(pending.peer, "approval_timeout",
            "The host did not approve this Direct request in time.",
            "One Direct approval timed out; the host remains open.", "join_expired")
        return false, "That Direct join request expired."
    end
    if countEntries(self.players) >= Protocol.MAX_PLAYERS then
        self:_rejectDirectPending(pending.peer, "shop_full",
            "This Direct shop already has four workers.",
            "One Direct join was declined because the shop is full.")
        return false, "The Direct shop is full."
    end
    pending.decision = "approved"
    self.status = "Approving Direct worker"
    return true, "Worker approved. Finishing the encrypted join."
end

function Session:rejectJoin(requestId)
    if not self:isHost() or self.networkKind ~= "direct" or self.terminal then
        return false, "No Direct join request is available."
    end
    local pending = type(requestId) == "number" and self.approvalRequests[requestId] or nil
    if type(pending) ~= "table" or self.pendingPeers[pending.peer] ~= pending then
        return false, "That Direct join request is no longer available."
    end
    self:_rejectDirectPending(pending.peer, "join_rejected",
        "The host declined this Direct join request.",
        "One Direct join was declined; the host remains open.")
    return true, "Join declined. That Direct connection is closed."
end

function Session:kickPlayer(playerId)
    if not self:isHost() or self.networkKind ~= "direct" or self.terminal then
        return false, "Direct player controls are unavailable."
    end
    if type(playerId) ~= "number" or playerId ~= math.floor(playerId)
        or playerId == self.localId
    then
        return false, "The host cannot be removed."
    end
    local peer = self.idToPeer[playerId]
    local player = peer and self.players[playerId] or nil
    if not peer or not player then return false, "That worker is no longer connected." end
    self:_purgePeerWork(peer)
    self:_removePeer(peer, "Removed by the host")
    if self.transport then
        self:_sendError(peer, "kicked",
            "The host removed this worker. A fresh Direct invitation is required.")
        self.transport:flush()
        self.transport:disconnect(peer, 7, false)
    end
    self:_queue("player_kicked", { playerId = playerId, name = player.name })
    return true, tostring(player.name or "Worker") .. " was removed."
end

function Session:_hostWelcome(peer, hello, context)
    if self.peerToId[peer] then
        self:_sendProtocolRejection(
            peer, "already_joined", "This peer already joined the shop.")
        return false
    end
    local pending = self.pendingPeers[peer]
    if self.requireHostApproval and (type(pending) ~= "table"
        or pending.stage ~= "approval" or pending.decision ~= "approved"
        or pending.hello ~= hello)
    then
        self:_sendError(peer, "approval_required",
            "The Direct host must approve this join before shop data is available.")
        return false
    end
    if countEntries(self.players) >= Protocol.MAX_PLAYERS then
        self:_sendError(peer, "shop_full", "This shop already has four workers.")
        self.transport:disconnect(peer, 4, false)
        self:_discardPendingPeer(peer)
        self.protocolRejectionAt[peer] = nil
        return false
    end

    local id, index = self:_nextPlayerId()
    if not id then
        self:_sendError(peer, "shop_full", "This shop already has four workers.")
        self.transport:disconnect(peer, 4, false)
        self:_discardPendingPeer(peer)
        self.protocolRejectionAt[peer] = nil
        return false
    end
    local host = self.players[1] or newPlayer({ x = 0, y = 0 })
    local offsets = { { 28, 0 }, { -28, 0 }, { 0, 28 } }
    local offset = offsets[(index or 2) - 1] or { 0, 0 }
    local spawnX, spawnY = host.x + offset[1], host.y + offset[2]
    if context and type(context.resolveGuestSpawn) == "function" then
        local resolved, candidateX, candidateY = pcall(context.resolveGuestSpawn,
            host.x, host.y, index, self.players)
        if resolved and finite(candidateX) and finite(candidateY) then
            spawnX, spawnY = candidateX, candidateY
        end
    end
    local player = newPlayer({
        id = id,
        name = hello.payload.name,
        character = hello.payload.character,
        x = spawnX,
        y = spawnY,
    })
    player.lastInputAt = self.clock()
    player.lastInputSequence = -1
    player.inputX, player.inputY = 0, 0
    self.players[id] = player
    self.peerToId[peer] = id
    self.idToPeer[id] = peer
    self:_discardPendingPeer(peer)

    -- The joining worker needs its own spawn plus the host immediately. Other
    -- workers arrive through the next sharded motion tick. Keeping this roster
    -- bounded prevents real-world floating-point poses from exceeding the
    -- realtime packet ceiling when the fourth worker joins.
    local welcomePlayers = Codec.array({
        playerRecord(host),
        playerRecord(player),
    })
    local welcomeOk, welcomeError = self:_send(peer, "welcome", {
        sessionId = self.sessionId,
        playerId = id,
        serverTick = self.serverTick,
        players = welcomePlayers,
    })
    local shop = context and context.getShopSnapshot and context.getShopSnapshot() or nil
    local shopOk, shopError
    if welcomeOk and type(shop) == "table" and type(shop.state) == "table"
        and type(shop.player) == "table"
    then
        shopOk, shopError = self:_send(peer, "shop_snapshot", {
            sessionId = self.sessionId,
            revision = self.shopRevision,
            state = shop.state,
            player = shop.player,
        })
    else
        shopError = shopError or "The host could not prepare a safe shop snapshot."
    end
    if not welcomeOk or not shopOk then
        self:_queue("error", { message = tostring(welcomeError or shopError) })
        self:_sendError(peer, "snapshot_failed", tostring(welcomeError or shopError))
        self.transport:disconnect(peer, 5, false)
        self.players[id], self.peerToId[peer], self.idToPeer[id] = nil, nil, nil
        self.protocolRejectionAt[peer] = nil
        self.status = tostring(countEntries(self.players)) .. "/4 workers connected"
        return false
    end
    self.status = tostring(countEntries(self.players)) .. "/4 workers connected"
    self:_queue("player_joined", { playerId = id, name = player.name })
    return true
end

function Session:_removePeer(peer, reason)
    if peer then self.protocolRejectionAt[peer] = nil end
    local pending = self:_discardPendingPeer(peer)
    self:_purgePeerWork(peer)
    local id = self.peerToId[peer]
    if not id then
        if type(pending) == "table" and pending.stage == "approval" then
            self:_queue("join_cancelled", {
                requestId = pending.requestId,
                name = pending.name,
            })
        end
        if pending ~= nil and self.networkKind == "direct" then
            self.status = countEntries(self.approvalRequests) > 0
                and "Direct worker waiting for host approval"
                or (tostring(countEntries(self.players)) .. "/4 workers connected")
        end
        return pending ~= nil
    end
    local player = self.players[id]
    self.peerToId[peer], self.idToPeer[id], self.players[id] = nil, nil, nil
    self:_broadcastJoined("leave", {
        sessionId = self.sessionId,
        playerId = id,
        reason = tostring(reason or "Disconnected"),
        serverTick = self.serverTick,
    })
    self.status = tostring(countEntries(self.players)) .. "/4 workers connected"
    self:_queue("player_left", { playerId = id, name = player and player.name, reason = reason })
    return true
end

function Session:_handleHostEnvelope(peer, envelope, context)
    if envelope.type == "hello" then
        if self.networkKind ~= "direct" then
            self:_hostWelcome(peer, envelope, context)
            return
        end
        local joinedId = self.peerToId[peer]
        if joinedId then
            self:kickPlayer(joinedId)
            return
        end
        local pending = self.pendingPeers[peer]
        if type(pending) ~= "table" then
            if self.transport then self.transport:disconnect(peer, 7, true) end
            return
        end
        if pending.stage == "hello" then
            self:_queueDirectApproval(peer, envelope)
        elseif pending.stage == "approval" then
            -- ENet reliable delivery does not duplicate messages. Still ignore
            -- an exact replay defensively and revoke on any attempted rewrite.
            if not sameHello(pending.hello and pending.hello.payload, envelope.payload) then
                self:_rejectDirectPending(peer, "invalid_join",
                    "The Direct join request changed while awaiting approval.",
                    "One Direct join was rejected because its request changed.")
            end
        else
            self:_rejectDirectPending(peer, "invalid_join",
                "The Direct join request is not valid.",
                "One invalid Direct join was rejected.")
        end
        return
    end
    local id = self.peerToId[peer]
    if not id then
        if self.networkKind == "direct" and self.pendingPeers[peer] then
            self:_rejectDirectPending(peer, "approval_required",
                "Wait for host approval before sending gameplay data.",
                "One Direct join sent gameplay data before approval and was rejected.")
        else
            self:_sendProtocolRejection(
                peer, "hello_required", "Send a compatible hello before gameplay data.")
        end
        return
    end
    local payload = envelope.payload
    if payload.sessionId == self.sessionId and context
        and type(context.touchWorkshop) == "function"
    then
        context.touchWorkshop(self.players[id])
    end
    if envelope.type == "input" then
        if payload.sessionId ~= self.sessionId then return end
        local player = self.players[id]
        if not player or payload.sequence <= (player.lastInputSequence or -1) then return end
        player.lastInputSequence = payload.sequence
        player.inputSequence = payload.sequence
        player.inputX, player.inputY = payload.moveX, payload.moveY
        player.lastInputAt = self.clock()
    elseif envelope.type == "interaction_request" then
        if payload.sessionId ~= self.sessionId then return end
        for _, pending in ipairs(self.pendingHostInteractions) do
            if pending.peer == peer then return end
        end
        self.pendingHostInteractions[#self.pendingHostInteractions + 1] = {
            peer = peer,
            playerId = id,
            request = payload,
        }
    elseif envelope.type == "workshop_acquire"
        or envelope.type == "workshop_command"
        or envelope.type == "workshop_release"
    then
        if payload.sessionId ~= self.sessionId then return end
        local incomingSafety = envelope.type == "workshop_command"
            and urgentWorkshopSafety(payload.resourceId, payload.action, payload)
        for _, pending in ipairs(self.pendingHostWorkshop) do
            if pending.peer == peer then
                local queuedSafety = pending.operation == "workshop_command"
                    and urgentWorkshopSafety(
                        pending.payload.resourceId, pending.payload.action, pending.payload)
                if not incomingSafety or queuedSafety then return end
            end
        end
        self.pendingHostWorkshop[#self.pendingHostWorkshop + 1] = {
            peer = peer,
            playerId = id,
            operation = envelope.type,
            payload = payload,
        }
    elseif envelope.type == "ping" and payload.sessionId == self.sessionId then
        self:_send(peer, "pong", { sessionId = self.sessionId, nonce = payload.nonce })
    elseif envelope.type == "leave" and payload.sessionId == self.sessionId then
        self:_removePeer(peer, payload.reason)
        if self.transport then self.transport:disconnect(peer, 0, false) end
    else
        self:_sendProtocolRejection(peer, "message_not_allowed",
            "Guests may send only input, workshop, interaction, ping, or leave messages.")
    end
end

function Session:_installRoster(records, serverTick)
    local installed = {}
    local ticks = {}
    for _, record in ipairs(records or {}) do
        installed[record.id] = newPlayer(record)
        if serverTick ~= nil then ticks[record.id] = serverTick end
    end
    self.players = installed
    self.lastPlayerTicks = ticks
end

function Session:_acceptShopState(payload)
    if not self.ready or payload.sessionId ~= self.sessionId
        or payload.revision <= self.lastShopRevision
    then
        return false
    end
    self.lastShopRevision = payload.revision
    self:_queue("shop_state", {
        revision = payload.revision,
        state = payload.state,
    })
    return true
end

function Session:_acceptInitialShopSnapshot(payload)
    if self.ready or not self.sessionId or payload.sessionId ~= self.sessionId then return false end
    local spawn = self.players[self.localId] and playerRecord(self.players[self.localId])
    if not spawn then
        self:_queue("error", { message = "The host snapshot did not include this worker." })
        return false
    end
    self.lastShopRevision = payload.revision
    self.ready = true
    self.status = "Connected to the host"
    self:_queue("ready", {
        state = payload.state,
        hostPlayer = payload.player,
        spawn = spawn,
        playerId = self.localId,
        revision = payload.revision,
    })
    local pending = self.pendingShopState
    self.pendingShopState = nil
    if pending and pending.sessionId == self.sessionId then self:_acceptShopState(pending) end
    return true
end

function Session:_bufferShopState(payload)
    local pending = self.pendingShopState
    if not pending or payload.revision > pending.revision then self.pendingShopState = payload end
end

function Session:_applySnapshot(payload)
    if payload.sessionId ~= self.sessionId then return end
    self.lastServerTick = math.max(self.lastServerTick, payload.serverTick)
    for _, record in ipairs(payload.players or {}) do
        local previousTick = self.lastPlayerTicks[record.id] or -1
        if payload.serverTick > previousTick then
            self.lastPlayerTicks[record.id] = payload.serverTick
            local player = self.players[record.id]
            if not player then
                player = newPlayer(record)
                self.players[record.id] = player
            end
            player.name, player.character = record.name, record.character
            player._targetX, player._targetY = record.x, record.y
            player._targetRecord = record
            if record.id == self.localId then
                self.localTarget = record
            elseif (player.x - record.x) ^ 2 + (player.y - record.y) ^ 2
                > TELEPORT_DISTANCE * TELEPORT_DISTANCE
            then
                copyMotion(player, record, true)
            end
        end
    end
end

function Session:_handleClientEnvelope(envelope)
    local payload = envelope.payload
    if envelope.type == "welcome" then
        self.sessionId = payload.sessionId
        self.localId = payload.playerId
        self.lastServerTick = payload.serverTick - 1
        self:_installRoster(payload.players, payload.serverTick)
        self.status = "Receiving the host shop..."
        local pending = self.pendingShopSnapshot
        self.pendingShopSnapshot = nil
        if pending and pending.sessionId == self.sessionId then
            self:_acceptInitialShopSnapshot(pending)
        end
    elseif envelope.type == "shop_snapshot" then
        if not self.sessionId then
            self.pendingShopSnapshot = payload
        elseif payload.sessionId == self.sessionId then
            self:_acceptInitialShopSnapshot(payload)
        end
    elseif envelope.type == "shop_state" then
        if not self.sessionId or not self.ready then
            self:_bufferShopState(payload)
        elseif payload.sessionId == self.sessionId then
            self:_acceptShopState(payload)
        end
    elseif envelope.type == "snapshot" then
        if self.ready then self:_applySnapshot(payload) end
    elseif envelope.type == "visitor_snapshot" then
        if self.ready and payload.sessionId == self.sessionId
            and payload.serverTick > self.lastVisitorTick
        then
            self.lastVisitorTick = payload.serverTick
            self:_queue("visitor_state", {
                serverTick = payload.serverTick,
                customer = payload.customer,
                vendor = payload.vendor,
            })
        end
    elseif envelope.type == "environment_snapshot" then
        if self.ready and payload.sessionId == self.sessionId
            and payload.serverTick > self.lastEnvironmentTick
        then
            self.lastEnvironmentTick = payload.serverTick
            self:_queue("environment_state", {
                serverTick = payload.serverTick,
                bayDoor = payload.bayDoor,
                truck = payload.truck,
            })
        end
    elseif envelope.type == "pallet_jack_snapshot" then
        if self.ready and payload.sessionId == self.sessionId
            and payload.serverTick > self.lastPalletJackTick
        then
            self.lastPalletJackTick = payload.serverTick
            self:_queue("pallet_jack_state", {
                serverTick = payload.serverTick,
                jack = payload.jack,
                machines = payload.machines,
            })
        end
    elseif envelope.type == "forklift_snapshot" then
        if self.ready and payload.sessionId == self.sessionId
            and payload.serverTick > self.lastForkliftTick
        then
            self.lastForkliftTick = payload.serverTick
            self:_queue("forklift_state", {
                serverTick = payload.serverTick,
                forklift = payload.forklift,
            })
        end
    elseif envelope.type == "cutter_snapshot" then
        local resourceId = payload.resourceId or "cutter"
        local lastTick = resourceId == "cutter" and self.lastCutterTick
            or (self.lastMachineTicks[resourceId] or -1)
        if self.ready and payload.sessionId == self.sessionId
            and payload.serverTick > lastTick
        then
            if resourceId == "cutter" then self.lastCutterTick = payload.serverTick
            else self.lastMachineTicks[resourceId] = payload.serverTick end
            self.workshopRevisions[resourceId] = math.max(
                self.workshopRevisions[resourceId] or 0, payload.resourceRevision)
            if self.activeWorkshop and self.activeWorkshop.resourceId == resourceId then
                self.activeWorkshop.revision = math.max(
                    self.activeWorkshop.revision, payload.resourceRevision)
            end
            self:_queue("cutter_state", {
                serverTick = payload.serverTick,
                resourceId = resourceId,
                resourceRevision = payload.resourceRevision,
                view = payload.view,
            })
        end
    elseif envelope.type == "windmill_snapshot" then
        local resourceId = payload.resourceId or "windmill"
        local lastTick = resourceId == "windmill" and self.lastWindmillTick
            or (self.lastMachineTicks[resourceId] or -1)
        if self.ready and payload.sessionId == self.sessionId
            and payload.serverTick > lastTick
        then
            if resourceId == "windmill" then self.lastWindmillTick = payload.serverTick
            else self.lastMachineTicks[resourceId] = payload.serverTick end
            self.workshopRevisions[resourceId] = math.max(
                self.workshopRevisions[resourceId] or 0, payload.resourceRevision)
            if self.activeWorkshop and self.activeWorkshop.resourceId == resourceId then
                self.activeWorkshop.revision = math.max(
                    self.activeWorkshop.revision, payload.resourceRevision)
            end
            self:_queue("windmill_state", {
                serverTick = payload.serverTick,
                resourceId = resourceId,
                resourceRevision = payload.resourceRevision,
                view = payload.view,
            })
        end
    elseif envelope.type == "wrapper_snapshot" then
        local resourceId = payload.resourceId
        if self.ready and payload.sessionId == self.sessionId
            and payload.serverTick > (self.lastMachineTicks[resourceId] or -1)
        then
            self.lastMachineTicks[resourceId] = payload.serverTick
            self.workshopRevisions[resourceId] = math.max(
                self.workshopRevisions[resourceId] or 0, payload.resourceRevision)
            if self.activeWorkshop and self.activeWorkshop.resourceId == resourceId then
                self.activeWorkshop.revision = math.max(
                    self.activeWorkshop.revision, payload.resourceRevision)
            end
            self:_queue("wrapper_state", {
                serverTick = payload.serverTick,
                resourceId = resourceId,
                resourceRevision = payload.resourceRevision,
                view = payload.view,
            })
        end
    elseif envelope.type == "interaction_result" then
        local pending = self.pendingInteraction
        if self.ready and payload.sessionId == self.sessionId and pending
            and payload.requestId == pending.requestId
            and payload.targetKind == pending.targetKind
        then
            self.pendingInteraction = nil
            self:_queue("interaction_result", {
                requestId = payload.requestId,
                targetKind = payload.targetKind,
                accepted = payload.accepted,
                code = payload.code,
                message = payload.message,
            })
        end
    elseif envelope.type == "workshop_grant" then
        local pending = self.pendingWorkshop
        if self.ready and payload.sessionId == self.sessionId and pending
            and pending.operation == "acquire"
            and payload.requestId == pending.requestId
            and payload.resourceId == pending.resourceId
        then
            self.pendingWorkshop = nil
            local knownRevision = self.workshopRevisions[payload.resourceId] or 0
            local staleGrant = payload.granted and payload.revision < knownRevision
            local granted = payload.granted and not staleGrant
            local acceptedRevision = math.max(knownRevision, payload.revision)
            self.workshopRevisions[payload.resourceId] = acceptedRevision
            if granted then
                self.activeWorkshop = {
                    resourceId = payload.resourceId,
                    leaseId = payload.leaseId,
                    revision = acceptedRevision,
                }
            end
            self:_queue("workshop_grant", {
                requestId = payload.requestId,
                resourceId = payload.resourceId,
                granted = granted,
                leaseId = granted and payload.leaseId or nil,
                revision = acceptedRevision,
                code = staleGrant and "stale_grant" or payload.code,
                message = staleGrant
                    and "Workshop state changed before the control grant arrived. Try again."
                    or payload.message,
                view = granted and payload.view or nil,
            })
        end
    elseif envelope.type == "workshop_result" then
        local pending = self.pendingWorkshop
        local pendingSafety = self.pendingWorkshopSafety
        local active = self.activeWorkshop
        if self.ready and payload.sessionId == self.sessionId and pendingSafety and active
            and payload.commandId == pendingSafety.commandId
            and payload.resourceId == active.resourceId
            and payload.action == pendingSafety.action
        then
            self.pendingWorkshopSafety = nil
            active.revision = math.max(active.revision, payload.revision)
            self.workshopRevisions[payload.resourceId] = math.max(
                self.workshopRevisions[payload.resourceId] or 0, payload.revision)
            self:_queue("workshop_result", {
                commandId = payload.commandId,
                resourceId = payload.resourceId,
                action = payload.action,
                accepted = payload.accepted,
                revision = payload.revision,
                code = payload.code,
                message = payload.message,
                view = payload.view,
                urgentSafety = true,
            })
        elseif self.ready and payload.sessionId == self.sessionId and pending and active
            and pending.operation == "command"
            and payload.commandId == pending.commandId
            and payload.resourceId == active.resourceId
            and payload.action == pending.action
        then
            self.pendingWorkshop = nil
            active.revision = math.max(active.revision, payload.revision)
            self.workshopRevisions[payload.resourceId] = math.max(
                self.workshopRevisions[payload.resourceId] or 0, payload.revision)
            self:_queue("workshop_result", {
                commandId = payload.commandId,
                resourceId = payload.resourceId,
                action = payload.action,
                accepted = payload.accepted,
                revision = payload.revision,
                code = payload.code,
                message = payload.message,
                view = payload.view,
            })
        end
    elseif envelope.type == "workshop_snapshot" then
        if self.ready and payload.sessionId == self.sessionId
            and payload.revision > self.lastWorkshopSnapshotRevision
        then
            self.lastWorkshopSnapshotRevision = payload.revision
            local activeRecord, activeRecordAuthoritative
            local workshopResources = {}
            for _, record in ipairs(payload.resources) do
                self.workshopRevisions[record.resourceId] = math.max(
                    self.workshopRevisions[record.resourceId] or 0, record.revision)
                workshopResources[#workshopResources + 1] = {
                    resourceId = record.resourceId,
                    occupied = record.occupied == true,
                    ownerPlayerId = record.occupied and record.ownerPlayerId or nil,
                }
                if self.activeWorkshop and record.resourceId == self.activeWorkshop.resourceId then
                    activeRecord = record
                    activeRecordAuthoritative = record.revision >= self.activeWorkshop.revision
                    if activeRecordAuthoritative
                        and record.occupied and record.ownerPlayerId == self.localId
                    then
                        self.activeWorkshop.revision = math.max(
                            self.activeWorkshop.revision, record.revision)
                    end
                end
            end
            self.workshopResources = workshopResources
            if self.activeWorkshop and activeRecordAuthoritative
                and (not activeRecord.occupied or activeRecord.ownerPlayerId ~= self.localId)
            then
                local lost = self.activeWorkshop
                self.activeWorkshop, self.pendingWorkshop, self.pendingWorkshopSafety = nil, nil, nil
                self:_queue("workshop_lost", {
                    resourceId = lost.resourceId,
                    message = "The host device released this workshop control.",
                })
            end
            self:_queue("workshop_snapshot", {
                revision = payload.revision,
                resources = payload.resources,
                wrapper = payload.wrapper,
            })
        end
    elseif envelope.type == "pong" then
        local sentAt = self.pendingPing and self.pendingPing[payload.nonce]
        if sentAt then
            self.rtt = math.max(0, (self.clock() - sentAt) * 1000)
            self.pendingPing[payload.nonce] = nil
        end
    elseif envelope.type == "leave" then
        if payload.sessionId ~= self.sessionId then return end
        if payload.playerId == 1 then
            self:_markDisconnected(payload.reason or "The host closed the shop.")
        else
            self.players[payload.playerId] = nil
            self.lastPlayerTicks[payload.playerId] = math.max(
                self.lastPlayerTicks[payload.playerId] or -1,
                payload.serverTick or self.lastServerTick)
            self:_queue("player_left", { playerId = payload.playerId, reason = payload.reason })
        end
    elseif envelope.type == "error" then
        self.status = payload.message
        if self.networkKind == "direct" and (payload.code == "join_rejected"
            or payload.code == "approval_timeout" or payload.code == "kicked"
            or payload.code == "invalid_join" or payload.code == "approval_required")
        then
            self.disconnectReason = payload.message
        end
        self:_queue("error", { code = payload.code, message = payload.message })
    end
end

function Session:_service(context)
    if not self.transport or self.terminal then return false end
    local events, serviceError = self.transport:service(Protocol.MAX_EVENTS_PER_UPDATE)
    if serviceError then
        self.protocolRejectionAt = {}
        self:_markDisconnected("Network transport failed: " .. tostring(serviceError))
        self:_closeTransport(2, true)
        return false
    end
    for _, event in ipairs(events or {}) do
        if self.mode == "host" then
            if event.type == "connect" then
                local now = self.clock()
                local generation = self:_nextRuntimeHandle("nextConnectionGeneration")
                if not event.peer or not finite(now) or not generation then
                    if event.peer then self.transport:disconnect(event.peer, 7, true) end
                elseif self.pendingPeers[event.peer] or self.peerToId[event.peer] then
                    -- One authenticated link generation may create only one
                    -- Session admission. A fresh single-use invitation arrives
                    -- as a distinct link after the prior generation is gone.
                    self.transport:disconnect(event.peer, 7, true)
                else
                    self.protocolRejectionAt[event.peer] = nil
                    self.pendingPeers[event.peer] = {
                        peer = event.peer,
                        connectedAt = now,
                        generation = generation,
                        stage = "hello",
                    }
                end
            elseif event.type == "disconnect" then
                self:_removePeer(event.peer, "Connection lost")
            elseif event.type == "receive" then
                local packet = event.data or event.payload
                local channel = tonumber(event.channel)
                local envelope, decodeError
                if type(packet) ~= "string" then
                    decodeError = "protocol: packet must be a string"
                elseif channel == nil or channel < 0 or channel >= Protocol.CHANNEL_COUNT
                    or channel ~= math.floor(channel)
                then
                    decodeError = "protocol: packet arrived on an invalid channel"
                elseif #packet > Protocol.MAX_PACKET_BYTES then
                    -- Guests have no legal durable/save-sized message. Reject
                    -- before the expensive large-codec decode path.
                    decodeError = "protocol: guest packet exceeds maximum size"
                else
                    envelope, decodeError = Protocol.decode(packet)
                    if envelope then
                        local expectedChannel = Protocol.route(envelope)
                        if channel ~= expectedChannel then
                            local wrongKind = envelope.type
                            envelope = nil
                            decodeError = "protocol: " .. tostring(wrongKind)
                                .. " arrived on the wrong channel"
                        end
                    end
                end
                if not envelope then
                    if self.networkKind == "direct" and self.pendingPeers[event.peer] then
                        self:_rejectDirectPending(event.peer, "invalid_join",
                            "The Direct join request was not valid.",
                            "One invalid Direct join was rejected.")
                    else
                        self:_sendProtocolRejection(event.peer, "bad_packet", decodeError)
                    end
                else
                    self:_handleHostEnvelope(event.peer, envelope, context)
                end
            end
        else
            if event.type == "connect" then
                local ok, helloError = self:_sendToServer("hello", {
                    clientNonce = self.clientNonce,
                    name = self.localName,
                    character = self.localCharacter,
                })
                if not ok then self:_queue("error", { message = helloError }) end
                self.connectedAt = self.clock()
                self.status = "Connected; waiting for host approval"
                if self.networkKind == "direct" and ok then
                    self:_queue("approval_waiting", {
                        message = "Encrypted request sent. Waiting for the host to approve this player.",
                    })
                end
            elseif event.type == "disconnect" then
                self:_markDisconnected(self.disconnectReason or "The host connection ended.")
            elseif event.type == "receive" then
                local packet = event.data or event.payload
                local channel = tonumber(event.channel)
                local envelope, decodeError
                if type(packet) ~= "string" then
                    decodeError = "protocol: packet must be a string"
                elseif channel == nil or channel < 0 or channel >= Protocol.CHANNEL_COUNT
                    or channel ~= math.floor(channel)
                then
                    decodeError = "protocol: packet arrived on an invalid channel"
                else
                    local limit = channel == Protocol.CHANNEL_DURABLE
                        and Protocol.MAX_SHOP_SNAPSHOT_BYTES or Protocol.MAX_PACKET_BYTES
                    if #packet > limit then
                        decodeError = "protocol: host packet exceeds channel size limit"
                    else
                        envelope, decodeError = Protocol.decode(packet)
                        if envelope then
                            local expectedChannel = Protocol.route(envelope)
                            if channel ~= expectedChannel then
                                envelope = nil
                                decodeError = "protocol: host packet arrived on the wrong channel"
                            end
                        end
                    end
                end
                if not envelope then
                    self:_queue("error", { message = "Host sent an invalid packet: " .. tostring(decodeError) })
                else
                    self:_handleClientEnvelope(envelope)
                end
            end
        end
        if self.terminal then break end
    end
    if self.terminal then self:_closeTransport(1, true) end
    return not self.terminal
end

function Session:_updateHost(dt, context)
    self:_syncLocalPlayer(context and context.localPlayer)
    if context and type(context.touchWorkshop) == "function" and self.players[self.localId] then
        context.touchWorkshop(self.players[self.localId])
    end
    local now = self.clock()
    local expiredPeers = {}
    local approvedPeers = {}
    for peer, pending in pairs(self.pendingPeers) do
        local connectedAt = type(pending) == "table" and pending.connectedAt or pending
        local stage = type(pending) == "table" and pending.stage or "hello"
        local requestedAt = type(pending) == "table" and pending.requestedAt or nil
        if not finite(now) or not finite(connectedAt) or now < connectedAt
            or (stage == "approval" and (not finite(requestedAt) or now < requestedAt))
        then
            expiredPeers[#expiredPeers + 1] = { peer = peer, stage = stage, invalidClock = true }
        elseif stage == "approval" and now - requestedAt > DIRECT_APPROVAL_TIMEOUT then
            expiredPeers[#expiredPeers + 1] = { peer = peer, stage = stage }
        elseif stage == "hello" and now - connectedAt > CONNECT_TIMEOUT then
            expiredPeers[#expiredPeers + 1] = { peer = peer, stage = stage }
        elseif stage == "approval" and pending.decision == "approved" then
            approvedPeers[#approvedPeers + 1] = { peer = peer, pending = pending }
        end
    end
    for _, expired in ipairs(expiredPeers) do
        local peer = expired.peer
        if self.networkKind == "direct" then
            local approval = expired.stage == "approval"
            self:_rejectDirectPending(peer,
                approval and "approval_timeout" or "hello_timeout",
                approval and "The host did not approve this Direct request in time."
                    or "The Direct join request did not finish in time.",
                approval and "One Direct approval timed out; the host remains open."
                    or "One Direct join timed out; the host remains open.",
                approval and "join_expired" or "join_cancelled")
        else
            self:_discardPendingPeer(peer)
            self.protocolRejectionAt[peer] = nil
            self:_sendError(peer, "hello_timeout", "The client did not complete the LAN hello in time.")
            self.transport:disconnect(peer, 3, false)
        end
    end
    for _, approved in ipairs(approvedPeers) do
        local pending = approved.pending
        if self.pendingPeers[approved.peer] == pending
            and self.approvalRequests[pending.requestId] == pending
            and pending.decision == "approved"
        then
            self:_hostWelcome(approved.peer, pending.hello, context)
        end
    end
    for id, player in pairs(self.players) do
        if id ~= self.localId then
            local inputX, inputY = player.inputX or 0, player.inputY or 0
            if now - (player.lastInputAt or 0) > INPUT_HOLD_TIMEOUT then inputX, inputY = 0, 0 end
            if context and context.moveRemote then
                context.moveRemote(player, dt, inputX, inputY)
            end
        end
    end
    -- Requests are resolved only after this frame's authoritative remote
    -- movement, reducing false range failures near an interaction boundary.
    self:_processHostInteractions(context)
    self:_processHostWorkshop(context)
    if context and type(context.updateWorkshop) == "function" then
        context.updateWorkshop()
    end
    self.snapshotAccumulator = self.snapshotAccumulator + dt
    if self.snapshotAccumulator >= SNAPSHOT_INTERVAL then
        self.snapshotAccumulator = self.snapshotAccumulator % SNAPSHOT_INTERVAL
        self.serverTick = self.serverTick + 1
        -- Motion is intentionally sent as one player per packet. Every shard
        -- shares the tick, and clients merge them by player id. This keeps four
        -- real, full-precision poses under the 1,200-byte unreliable limit.
        for _, record in ipairs(self:_records()) do
            local ok, errorMessage = self:_broadcastJoined("snapshot", {
                sessionId = self.sessionId,
                serverTick = self.serverTick,
                players = Codec.array({ record }),
            })
            if not ok then
                self:_queue("error", { message = errorMessage })
                break
            end
        end
        local visitors = context and context.getVisitorSnapshot
            and context.getVisitorSnapshot() or nil
        if type(visitors) == "table" and type(visitors.customer) == "table"
            and type(visitors.vendor) == "table"
        then
            local visitorsOk, visitorsError = self:_broadcastJoined("visitor_snapshot", {
                sessionId = self.sessionId,
                serverTick = self.serverTick,
                customer = visitors.customer,
                vendor = visitors.vendor,
            })
            if not visitorsOk then self:_queue("error", { message = visitorsError }) end
        end
        local environment = context and context.getEnvironmentSnapshot
            and context.getEnvironmentSnapshot() or nil
        if type(environment) == "table" and type(environment.bayDoor) == "table"
            and type(environment.truck) == "table"
        then
            local environmentOk, environmentError = self:_broadcastJoined(
                "environment_snapshot", {
                    sessionId = self.sessionId,
                    serverTick = self.serverTick,
                    bayDoor = environment.bayDoor,
                    truck = environment.truck,
                })
            if not environmentOk then self:_queue("error", { message = environmentError }) end
        end
        local palletJack = context and context.getPalletJackSnapshot
            and context.getPalletJackSnapshot() or nil
        local machinePoses = context and context.getMachinePoseSnapshot
            and context.getMachinePoseSnapshot() or nil
        if type(palletJack) == "table" and type(machinePoses) == "table" then
            local palletJackOk, palletJackError, palletJackRecipients = self:_broadcastJoined(
                "pallet_jack_snapshot", {
                    sessionId = self.sessionId,
                    serverTick = self.serverTick,
                    jack = palletJack,
                    machines = machinePoses,
                })
            if os.getenv("PICTURE_SHOP_ACCEPTANCE_HOST_SLOT") then
                local relocationSignature = table.concat({
                    tostring(palletJack.operating == true),
                    tostring(palletJack.operatorPlayerId or "none"),
                    tostring(machinePoses.cutter and machinePoses.cutter.moving == true),
                    tostring(machinePoses.wrapper and machinePoses.wrapper.moving == true),
                    tostring(machinePoses.windmill and machinePoses.windmill.moving == true),
                    tostring(palletJackOk == true),
                    tostring(palletJackRecipients or 0),
                    tostring(palletJackError or "none"),
                }, ":")
                if relocationSignature ~= self._acceptanceRelocationSendSignature then
                    self._acceptanceRelocationSendSignature = relocationSignature
                    print(string.format(
                        "[ACCEPTANCE HOST] SNAPSHOT jack=%s owner=%s cutter=%s wrapper=%s windmill=%s sent=%s recipients=%s error=%s",
                        tostring(palletJack.operating == true),
                        tostring(palletJack.operatorPlayerId or "none"),
                        tostring(machinePoses.cutter and machinePoses.cutter.moving == true),
                        tostring(machinePoses.wrapper and machinePoses.wrapper.moving == true),
                        tostring(machinePoses.windmill and machinePoses.windmill.moving == true),
                        tostring(palletJackOk == true), tostring(palletJackRecipients or 0),
                        tostring(palletJackError or "none")))
                    io.flush()
                end
            end
            if not palletJackOk then self:_queue("error", { message = palletJackError }) end
        end
        local forklift = context and context.getForkliftSnapshot
            and context.getForkliftSnapshot() or nil
        if type(forklift) == "table" then
            local liftOk, liftError = self:_broadcastJoined("forklift_snapshot", {
                sessionId = self.sessionId, serverTick = self.serverTick, forklift = forklift,
            })
            if not liftOk then self:_queue("error", { message = liftError }) end
        end
        local cutter = context and context.getCutterSnapshot
            and context.getCutterSnapshot() or nil
        local cutterSnapshots = cutter and (cutter.view and { cutter } or cutter) or {}
        for _, item in ipairs(cutterSnapshots) do
            if type(item.view) == "table" then
                local resourceId = item.resourceId or "cutter"
                local cutterOk, cutterError = self:_broadcastJoined("cutter_snapshot", {
                    sessionId = self.sessionId,
                    serverTick = self.serverTick,
                    resourceId = resourceId,
                    resourceRevision = item.resourceRevision,
                    view = wireWorkshopView(resourceId, item.view),
                })
                if not cutterOk then self:_queue("error", { message = cutterError }) end
            end
        end
        local windmill = context and context.getWindmillSnapshot
            and context.getWindmillSnapshot() or nil
        local windmillSnapshots = windmill and (windmill.view and { windmill } or windmill) or {}
        for _, item in ipairs(windmillSnapshots) do
            if type(item.view) == "table" then
                local resourceId = item.resourceId or "windmill"
                local windmillOk, windmillError = self:_broadcastJoined("windmill_snapshot", {
                    sessionId = self.sessionId,
                    serverTick = self.serverTick,
                    resourceId = resourceId,
                    resourceRevision = item.resourceRevision,
                    view = wireWorkshopView(resourceId, item.view),
                })
                if not windmillOk then self:_queue("error", { message = windmillError }) end
            end
        end
        local wrappers = context and context.getWrapperSnapshots
            and context.getWrapperSnapshots() or {}
        for _, item in ipairs(wrappers) do
            if type(item.view) == "table" then
                local wrapperOk, wrapperError = self:_broadcastJoined("wrapper_snapshot", {
                    sessionId = self.sessionId,
                    serverTick = self.serverTick,
                    resourceId = item.resourceId,
                    resourceRevision = item.resourceRevision,
                    view = wireWorkshopView(item.resourceId, item.view),
                })
                if not wrapperOk then self:_queue("error", { message = wrapperError }) end
            end
        end
        local workshop = context and context.getWorkshopSnapshot
            and context.getWorkshopSnapshot() or nil
        if type(workshop) == "table" and type(workshop.resources) == "table"
            and type(workshop.wrapper) == "table"
        then
            local workshopOk, workshopError = self:_broadcastJoined(
                "workshop_snapshot", {
                    sessionId = self.sessionId,
                    revision = self.serverTick,
                    resources = workshop.resources,
                    wrapper = wireWorkshopView("skid_wrapper", workshop.wrapper),
                })
            if not workshopOk then self:_queue("error", { message = workshopError }) end
        end
    end


    self.shopStateAccumulator = math.min(
        SHOP_STATE_INTERVAL, self.shopStateAccumulator + dt)
    self.shopFallbackAccumulator = self.shopFallbackAccumulator + dt
    if self.shopFallbackAccumulator >= SHOP_STATE_FALLBACK_INTERVAL then self.shopDirty = true end
    if self.shopDirty and self.shopStateAccumulator >= SHOP_STATE_INTERVAL then
        local shop = context and context.getShopSnapshot and context.getShopSnapshot() or nil
        if type(shop) ~= "table" or type(shop.state) ~= "table" then
            self:_queue("error", { message = "The host could not prepare a durable shop update." })
            self.shopStateAccumulator = 0
        else
            local revision = self.shopRevision + 1
            local stateOk, stateError, recipientCount = self:_broadcastJoined("shop_state", {
                sessionId = self.sessionId,
                revision = revision,
                state = shop.state,
            })
            self.shopStateAccumulator = 0
            if stateOk then
                if recipientCount > 0 then self.shopRevision = revision end
                self.shopDirty = false
                self.shopFallbackAccumulator = 0
            else
                self:_queue("error", { message = stateError })
            end
        end
    end
end

function Session:_sendClientInput(dt, context)
    if not self.ready or not self.sessionId then return end
    self.inputAccumulator = self.inputAccumulator + dt
    if self.inputAccumulator < INPUT_INTERVAL then return end
    self.inputAccumulator = self.inputAccumulator % INPUT_INTERVAL
    self.inputSequence = self.inputSequence + 1
    local ok, errorMessage = self:_sendToServer("input", {
        sessionId = self.sessionId,
        sequence = self.inputSequence,
        moveX = clamp(context and context.inputX, -1, 1),
        moveY = clamp(context and context.inputY, -1, 1),
    })
    if not ok then self:_queue("error", { message = errorMessage }) end
end

function Session:_updateClientVisuals(dt, localPlayer)
    if not self.ready then return end
    if localPlayer and self.localTarget then
        local dx = self.localTarget.x - localPlayer.x
        local dy = self.localTarget.y - localPlayer.y
        local distanceSquared = dx * dx + dy * dy
        if distanceSquared > TELEPORT_DISTANCE * TELEPORT_DISTANCE then
            localPlayer.x, localPlayer.y = self.localTarget.x, self.localTarget.y
        else
            local alpha = math.min(1, math.max(0, dt) * CORRECTION_RATE)
            localPlayer.x, localPlayer.y = localPlayer.x + dx * alpha, localPlayer.y + dy * alpha
        end
    end
    local alpha = math.min(1, math.max(0, dt) * REMOTE_SMOOTH_RATE)
    for id, player in pairs(self.players) do
        if id ~= self.localId and player._targetRecord then
            local startX, startY = player.x, player.y
            player.x = player.x + (player._targetX - player.x) * alpha
            player.y = player.y + (player._targetY - player.y) * alpha
            local dx, dy = player.x - startX, player.y - startY
            local distance = math.sqrt(dx * dx + dy * dy)
            copyMotion(player, player._targetRecord, false)
            if distance > 0.001 then
                player.animationDistance = (player.animationDistance or 0) + distance
                player.idleClock = 0
                player.moving = true
            else
                player.idleClock = (player.idleClock or 0) + dt
                player.moving = player._targetRecord.moving == true
            end
        end
    end
end

function Session:update(dt, context)
    if not self:isActive() or self.terminal then return end
    dt = math.max(0, math.min(tonumber(dt) or 0, 0.25))
    if self.mode == "host" then self:_syncLocalPlayer(context and context.localPlayer) end
    if not self:_service(context) then return end
    if self.mode == "host" then
        self:_updateHost(dt, context)
    else
        if self.pendingInteraction
            and self.clock() - self.pendingInteraction.sentAt > INTERACTION_TIMEOUT
        then
            local timedOut = self.pendingInteraction
            self.pendingInteraction = nil
            self:_queue("interaction_result", {
                requestId = timedOut.requestId,
                targetKind = timedOut.targetKind,
                accepted = false,
                code = "timeout",
                message = "The host device did not answer. The switch is safe to try again.",
            })
        end
        if self.pendingWorkshop
            and self.clock() - self.pendingWorkshop.sentAt > WORKSHOP_TIMEOUT
        then
            local timedOut = self.pendingWorkshop
            self.pendingWorkshop = nil
            if timedOut.operation == "acquire" then
                self:_queue("workshop_grant", {
                    requestId = timedOut.requestId,
                    resourceId = timedOut.resourceId,
                    granted = false,
                    code = "timeout",
                    message = "The host device did not answer the workshop request.",
                    revision = self.workshopRevisions[timedOut.resourceId] or 0,
                })
            else
                self:_queue("workshop_result", {
                    commandId = timedOut.commandId,
                    resourceId = timedOut.resourceId,
                    action = timedOut.action,
                    accepted = false,
                    code = "timeout",
                    message = "The host device did not answer the workshop action.",
                    revision = self.workshopRevisions[timedOut.resourceId] or 0,
                })
            end
        end
        if self.pendingWorkshopSafety
            and self.clock() - self.pendingWorkshopSafety.sentAt > WORKSHOP_TIMEOUT
        then
            local timedOut = self.pendingWorkshopSafety
            self.pendingWorkshopSafety = nil
            self:_queue("workshop_result", {
                commandId = timedOut.commandId,
                resourceId = timedOut.resourceId,
                action = timedOut.action,
                accepted = false,
                code = "timeout",
                message = "The host did not answer the urgent workshop safety action.",
                revision = self.workshopRevisions[timedOut.resourceId] or 0,
                urgentSafety = true,
            })
        end
        if not self.ready and self.connectedAt
            and self.clock() - self.connectedAt > self.clientConnectTimeout
        then
            self:_markDisconnected("Connection timed out. Check the host address and host-device network access.")
            self:_closeTransport(1, true)
            return
        end
        self:_sendClientInput(dt, context)
        self:_updateClientVisuals(dt, context and context.localPlayer)
    end
end

function Session:sendNeutralInput()
    if not self:isClient() or self.terminal or not self.ready or not self.sessionId then return false end
    self.inputSequence = self.inputSequence + 1
    return self:_sendToServer("input", {
        sessionId = self.sessionId,
        sequence = self.inputSequence,
        moveX = 0,
        moveY = 0,
    })
end

function Session:requestInteraction(targetKind, desiredState)
    if not self:isClient() or self.terminal or not self.ready or not self.sessionId then
        return false, "This worker device is not ready to interact with the host shop."
    end
    if self.pendingInteraction then
        return false, "Waiting for the host to answer the previous request."
    end
    self.interactionRequestId = self.interactionRequestId + 1
    local request = {
        sessionId = self.sessionId,
        requestId = self.interactionRequestId,
        targetKind = targetKind,
        desiredState = desiredState,
    }
    local ok, errorMessage = self:_sendToServer("interaction_request", request)
    if not ok then return false, errorMessage end
    self.pendingInteraction = {
        requestId = request.requestId,
        targetKind = request.targetKind,
        desiredState = request.desiredState,
        sentAt = self.clock(),
    }
    return true
end

function Session:requestWorkshopAcquire(resourceId)
    if not self:isClient() or self.terminal or not self.ready or not self.sessionId then
        return false, "This worker device is not ready to use the host shop."
    end
    if self.pendingWorkshop then
        return false, "Waiting for the host to answer the previous workshop request."
    end
    if self.activeWorkshop then
        return false, "Close the current remote console before using another one."
    end
    self.workshopRequestId = self.workshopRequestId + 1
    local request = {
        sessionId = self.sessionId,
        requestId = self.workshopRequestId,
        resourceId = resourceId,
        expectedRevision = self.workshopRevisions[resourceId] or 0,
    }
    local ok, errorMessage = self:_sendToServer("workshop_acquire", request)
    if not ok then return false, errorMessage end
    self.pendingWorkshop = {
        operation = "acquire",
        requestId = request.requestId,
        resourceId = resourceId,
        sentAt = self.clock(),
    }
    return true
end

function Session:requestWorkshopCommand(action, arguments)
    local active = self.activeWorkshop
    if not self:isClient() or self.terminal or not self.ready or not self.sessionId
        or not active
    then
        return false, "No host-authorized workshop console is open."
    end
    arguments = type(arguments) == "table" and arguments or {}
    local urgentSafety = urgentWorkshopSafety(active.resourceId, action, arguments)
    if self.pendingWorkshopSafety then
        return false, "Waiting for the host to confirm the urgent workshop safety action."
    end
    if self.pendingWorkshop and not urgentSafety then
        return false, "Waiting for the host to answer the previous workshop action."
    end
    self.workshopRequestId = self.workshopRequestId + 1
    local request = {
        sessionId = self.sessionId,
        commandId = self.workshopRequestId,
        leaseId = active.leaseId,
        resourceId = active.resourceId,
        action = action,
        expectedRevision = active.revision,
    }
    if action == "submit_quote" then request.amount = arguments.amount
    elseif action == "purchase_stock" or action == "purchase_machine"
        or action == "move_item" or action == "service_view"
        or action == "service_tool" or action == "service_point"
        or action == "remove_blade_bolt" or action == "service_target"
    then
        request.itemIndex = arguments.itemIndex
    elseif action == "request_pickup" then request.jobId = arguments.jobId
    elseif action == "office_action" then request.officeIntent = arguments.officeIntent
    elseif action == "warehouse_action" then request.warehouseIntent = arguments.warehouseIntent
    elseif action == "phone_answer" or action == "phone_respond" or action == "phone_dismiss" then
        request.callId = arguments.callId
    elseif action == "select_pallet" or action == "start_cycle"
        or action == "lift_pallet" or action == "lower_pallet"
        or action == "load_pallet"
    then
        request.palletId = arguments.palletId
    elseif action == "select_program" then
        request.programIndex = arguments.programIndex
    elseif action == "set_gauge" then
        request.gaugeCentiInch = arguments.gaugeCentiInch
    elseif action == "set_clamp" then
        request.clamp = arguments.clamp
    elseif action == "set_barrier" then
        request.barrierClear = arguments.barrierClear
    elseif action == "set_weekly_technician" then
        request.enabled = arguments.enabled
    elseif action == "move_machine" then
        request.machineIndex = arguments.machineIndex
    elseif action == "place_machine" then
        request.placementCell = arguments.placementCell
    elseif action == "order_plate" or action == "begin_plate" or action == "process_plate" then
        request.plateId = arguments.plateId
    elseif action == "begin_setup" then
        request.setupTask = arguments.setupTask
    elseif action == "setup_action" then
        request.setupAction = arguments.setupAction
    end
    local ok, errorMessage = self:_sendToServer("workshop_command", request)
    if not ok then return false, errorMessage end
    local pending = {
        operation = "command",
        commandId = request.commandId,
        resourceId = request.resourceId,
        action = request.action,
        sentAt = self.clock(),
    }
    if urgentSafety then
        self.pendingWorkshopSafety = pending
    else
        self.pendingWorkshop = pending
    end
    return true
end

function Session:releaseWorkshop(reason)
    local active = self.activeWorkshop
    if not self:isClient() or self.terminal or not self.ready or not self.sessionId
        or not active
    then
        return false
    end
    self.workshopRequestId = self.workshopRequestId + 1
    local request = {
        sessionId = self.sessionId,
        requestId = self.workshopRequestId,
        leaseId = active.leaseId,
        resourceId = active.resourceId,
        reason = reason == "cancelled" and "cancelled" or "closed",
    }
    local ok, errorMessage = self:_sendToServer("workshop_release", request)
    if not ok then return false, errorMessage end
    self.activeWorkshop, self.pendingWorkshop, self.pendingWorkshopSafety = nil, nil, nil
    return true
end

function Session:workshopInfo()
    if not self.activeWorkshop then return nil end
    return {
        resourceId = self.activeWorkshop.resourceId,
        leaseId = self.activeWorkshop.leaseId,
        revision = self.activeWorkshop.revision,
    }
end

function Session:markShopDirty(urgent)
    if not self:isHost() or self.terminal then return false end
    self.shopDirty = true
    if urgent == true then self.shopStateAccumulator = SHOP_STATE_INTERVAL end
    return true
end

function Session:remotePlayers()
    local result = {}
    for id, player in pairs(self.players) do
        if id ~= self.localId then result[#result + 1] = player end
    end
    table.sort(result, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return result
end

function Session:hudInfo()
    local pendingJoins = {}
    if self:isHost() and self.networkKind == "direct" and not self.terminal then
        local now = self.clock()
        for requestId, pending in pairs(self.approvalRequests) do
            if type(pending) == "table" and pending.stage == "approval" then
                local remaining = finite(now) and finite(pending.requestedAt)
                    and math.max(0, DIRECT_APPROVAL_TIMEOUT - (now - pending.requestedAt)) or 0
                pendingJoins[#pendingJoins + 1] = {
                    requestId = requestId,
                    name = pending.name,
                    character = pending.character,
                    expiresIn = math.floor(remaining + 0.5),
                }
            end
        end
        table.sort(pendingJoins, function(left, right)
            return left.requestId < right.requestId
        end)
    end
    local connectedGuests = {}
    if self:isHost() and self.networkKind == "direct" then
        for id, player in pairs(self.players) do
            if id ~= self.localId then
                connectedGuests[#connectedGuests + 1] = {
                    playerId = id,
                    name = tostring(player.name or "Worker"),
                    character = tostring(player.character or "rabbit-worker"),
                }
            end
        end
        table.sort(connectedGuests, function(left, right)
            return left.playerId < right.playerId
        end)
    end
    local players = {}
    for id, player in pairs(self.players) do
        players[#players + 1] = {
            playerId = id,
            name = tostring(player.name or "Worker"),
            isHost = id == 1,
            isLocal = id == self.localId,
        }
    end
    table.sort(players, function(left, right)
        return left.playerId < right.playerId
    end)
    local pendingActivity
    if self.pendingWorkshopSafety then
        pendingActivity = {
            kind = "urgent_safety",
            resourceId = self.pendingWorkshopSafety.resourceId,
            action = self.pendingWorkshopSafety.action,
        }
    elseif self.pendingWorkshop then
        pendingActivity = {
            kind = self.pendingWorkshop.operation == "acquire"
                and "workshop_acquire" or "workshop_action",
            resourceId = self.pendingWorkshop.resourceId,
            action = self.pendingWorkshop.action,
        }
    elseif self.pendingInteraction then
        pendingActivity = {
            kind = "interaction",
            targetKind = self.pendingInteraction.targetKind,
        }
    end
    local workshopResources = {}
    for _, resource in ipairs(self.workshopResources or {}) do
        workshopResources[#workshopResources + 1] = {
            resourceId = resource.resourceId,
            occupied = resource.occupied == true,
            ownerPlayerId = resource.occupied and resource.ownerPlayerId or nil,
        }
    end
    return {
        mode = self.mode,
        networkKind = self.networkKind,
        status = self.status,
        playerCount = countEntries(self.players),
        address = self.localAddress,
        port = self.port,
        rtt = self.rtt,
        canManage = self:isHost() and self.networkKind == "direct" and not self.terminal,
        pendingJoinCount = #pendingJoins,
        pendingJoins = pendingJoins,
        connectedGuests = connectedGuests,
        localPlayerId = self.localId,
        players = players,
        activeResourceId = self.activeWorkshop and self.activeWorkshop.resourceId or nil,
        pendingActivity = pendingActivity,
        workshopResources = workshopResources,
    }
end

return Session
