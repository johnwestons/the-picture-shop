local Address = require("src.net.address")
local Codec = require("src.net.codec")
local Protocol = require("src.net.protocol")
local Transport = require("src.net.transport_enet")

local Session = {}
Session.__index = Session

local INPUT_INTERVAL = 1 / 20
local SNAPSHOT_INTERVAL = 1 / 12
local SHOP_STATE_INTERVAL = 0.25
local SHOP_STATE_FALLBACK_INTERVAL = 30
local INPUT_HOLD_TIMEOUT = 0.35
local CONNECT_TIMEOUT = 10
local TELEPORT_DISTANCE = 140
local CORRECTION_RATE = 12
local REMOTE_SMOOTH_RATE = 14
local INTERACTION_RATE_LIMIT = 0.20
local INTERACTION_TIMEOUT = 3
local WORKSHOP_TIMEOUT = 4

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

local function wireWorkshopView(resourceId, view)
    if type(view) ~= "table" then return view end
    if resourceId == "reception_customer" and type(view.quoteRows) == "table" then
        if not Codec.isArray(view.quoteRows) then
            view.quoteRows = Codec.array(view.quoteRows)
        end
    elseif resourceId == "skid_wrapper" and type(view.pallets) == "table" then
        if not Codec.isArray(view.pallets) then
            view.pallets = Codec.array(view.pallets)
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
        transportFactory = options.transportFactory or Transport,
        clock = options.clock or defaultClock,
        transport = nil,
        players = {},
        peerToId = {},
        idToPeer = {},
        pendingPeers = {},
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
        shopDirty = false,
        connectedAt = nil,
        ready = false,
        localTarget = nil,
        pendingShopSnapshot = nil,
        pendingShopState = nil,
        interactionRequestId = 0,
        pendingInteraction = nil,
        pendingHostInteractions = {},
        workshopRequestId = 0,
        pendingWorkshop = nil,
        activeWorkshop = nil,
        workshopRevisions = {},
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
    if self.transport then self.transport:close(code or 0, immediate == true) end
    self.transport = nil
end

function Session:_resetRuntime()
    self.players = {}
    self.peerToId = {}
    self.idToPeer = {}
    self.pendingPeers = {}
    self.pendingEvents = {}
    self.sessionId = nil
    self.localId = nil
    self.localName = nil
    self.localCharacter = nil
    self.localAddress = nil
    self.hostAddress = nil
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
    self.shopDirty = false
    self.connectedAt = nil
    self.ready = false
    self.localTarget = nil
    self.pendingShopSnapshot = nil
    self.pendingShopState = nil
    self.interactionRequestId = 0
    self.pendingInteraction = nil
    self.pendingHostInteractions = {}
    self.workshopRequestId = 0
    self.pendingWorkshop = nil
    self.activeWorkshop = nil
    self.workshopRevisions = {}
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
    self.status = tostring(message or "The LAN connection ended.")
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
        self:_broadcast("leave", {
            sessionId = self.sessionId,
            playerId = self.localId or 1,
            reason = reason,
            serverTick = self.serverTick,
        })
        self.transport:flush()
    end
    self:_closeTransport(0, false)
    self.mode, self.status = "offline", "Offline"
    self:_resetRuntime()
    return true
end

function Session:startHost(options)
    options = options or {}
    if self:isActive() then self:stop("Starting another session") end
    local port = tonumber(options.port) or Address.DEFAULT_PORT
    local transport, errorMessage = self.transportFactory.createHost({
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
    self.port = port
    self.sessionId = identifier("s", self.clock)
    self.localId = 1
    self.localName = tostring(options.name or "LAN Host")
    self.localCharacter = tostring(options.character or "rabbit-worker")
    self.localAddress = Address.detectLanAddress(options.addressOptions or {})
    self.players[1] = newPlayer({
        id = 1, name = self.localName, character = self.localCharacter,
        x = tonumber(options.x) or 0, y = tonumber(options.y) or 0,
    })
    self.ready = true
    self.status = "Hosting on " .. tostring(self.localAddress or "local network")
    self:_queue("host_started", {
        address = self.localAddress,
        port = self.port,
        sessionId = self.sessionId,
    })
    return true
end

function Session:startClient(address, options)
    options = options or {}
    if self:isActive() then self:stop("Starting another session") end
    local parsed, addressError = Address.parse(address, options.port)
    if not parsed then return false, addressError end
    local transport, errorMessage = self.transportFactory.createClient(parsed.endpoint, {
        channels = Protocol.CHANNEL_COUNT,
        enet = options.enet,
    })
    if not transport then return false, errorMessage end
    self:_resetRuntime()
    self.transport = transport
    self.mode = "client"
    self.port = parsed.port
    self.hostAddress = parsed.host
    self.localName = tostring(options.name or "LAN Worker")
    self.localCharacter = tostring(options.character or "rabbit-worker")
    self.clientNonce = identifier("n", self.clock)
    self.connectedAt = self.clock()
    self.status = "Connecting to " .. parsed.endpoint
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
    for _, item in ipairs(queued) do
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

function Session:_hostWelcome(peer, hello, context)
    if self.peerToId[peer] then
        self:_sendError(peer, "already_joined", "This peer already joined the shop.")
        return
    end
    if countEntries(self.players) >= Protocol.MAX_PLAYERS then
        self:_sendError(peer, "shop_full", "This shop already has four workers.")
        self.transport:disconnect(peer, 4, false)
        return
    end

    local id, index = self:_nextPlayerId()
    if not id then return end
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
    self.pendingPeers[peer] = nil

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
        return
    end
    self.status = tostring(countEntries(self.players)) .. "/4 workers connected"
    self:_queue("player_joined", { playerId = id, name = player.name })
end

function Session:_removePeer(peer, reason)
    self.pendingPeers[peer] = nil
    local id = self.peerToId[peer]
    if not id then return false end
    local player = self.players[id]
    self.peerToId[peer], self.idToPeer[id], self.players[id] = nil, nil, nil
    self:_broadcast("leave", {
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
        self:_hostWelcome(peer, envelope, context)
        return
    end
    local id = self.peerToId[peer]
    if not id then
        self:_sendError(peer, "hello_required", "Send a compatible hello before gameplay data.")
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
        for _, pending in ipairs(self.pendingHostWorkshop) do
            if pending.peer == peer then return end
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
        self.transport:disconnect(peer, 0, false)
    else
        self:_sendError(peer, "message_not_allowed",
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
            self.workshopRevisions[payload.resourceId] = payload.revision
            if payload.granted then
                self.activeWorkshop = {
                    resourceId = payload.resourceId,
                    leaseId = payload.leaseId,
                    revision = payload.revision,
                }
            end
            self:_queue("workshop_grant", {
                requestId = payload.requestId,
                resourceId = payload.resourceId,
                granted = payload.granted,
                leaseId = payload.leaseId,
                revision = payload.revision,
                code = payload.code,
                message = payload.message,
                view = payload.view,
            })
        end
    elseif envelope.type == "workshop_result" then
        local pending = self.pendingWorkshop
        local active = self.activeWorkshop
        if self.ready and payload.sessionId == self.sessionId and pending and active
            and pending.operation == "command"
            and payload.commandId == pending.commandId
            and payload.resourceId == active.resourceId
            and payload.action == pending.action
        then
            self.pendingWorkshop = nil
            active.revision = payload.revision
            self.workshopRevisions[payload.resourceId] = payload.revision
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
            local activeRecord
            for _, record in ipairs(payload.resources) do
                self.workshopRevisions[record.resourceId] = record.revision
                if self.activeWorkshop and record.resourceId == self.activeWorkshop.resourceId then
                    activeRecord = record
                    if record.occupied and record.ownerPlayerId == self.localId then
                        self.activeWorkshop.revision = record.revision
                    end
                end
            end
            if self.activeWorkshop and (not activeRecord or not activeRecord.occupied
                or activeRecord.ownerPlayerId ~= self.localId)
            then
                local lost = self.activeWorkshop
                self.activeWorkshop, self.pendingWorkshop = nil, nil
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
        self:_queue("error", { code = payload.code, message = payload.message })
    end
end

function Session:_service(context)
    if not self.transport or self.terminal then return false end
    local events, serviceError = self.transport:service(Protocol.MAX_EVENTS_PER_UPDATE)
    if serviceError then
        self:_markDisconnected("Network transport failed: " .. tostring(serviceError))
        self:_closeTransport(2, true)
        return false
    end
    for _, event in ipairs(events or {}) do
        if self.mode == "host" then
            if event.type == "connect" then
                self.pendingPeers[event.peer] = self.clock()
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
                    self:_sendError(event.peer, "bad_packet", decodeError)
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
                self.status = "Connected; waiting for host approval"
            elseif event.type == "disconnect" then
                self:_markDisconnected("The host connection ended.")
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
    for peer, connectedAt in pairs(self.pendingPeers) do
        if now - connectedAt > CONNECT_TIMEOUT then expiredPeers[#expiredPeers + 1] = peer end
    end
    for _, peer in ipairs(expiredPeers) do
        self.pendingPeers[peer] = nil
        self:_sendError(peer, "hello_timeout", "The client did not complete the LAN hello in time.")
        self.transport:disconnect(peer, 3, false)
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
            local palletJackOk, palletJackError = self:_broadcastJoined(
                "pallet_jack_snapshot", {
                    sessionId = self.sessionId,
                    serverTick = self.serverTick,
                    jack = palletJack,
                    machines = machinePoses,
                })
            if not palletJackOk then self:_queue("error", { message = palletJackError }) end
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
        if not self.ready and self.connectedAt and self.clock() - self.connectedAt > CONNECT_TIMEOUT then
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
    if self.pendingWorkshop then
        return false, "Waiting for the host to answer the previous workshop action."
    end
    arguments = type(arguments) == "table" and arguments or {}
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
    elseif action == "request_pickup" then request.jobId = arguments.jobId
    elseif action == "select_pallet" or action == "start_cycle"
        or action == "lift_pallet" or action == "lower_pallet"
    then
        request.palletId = arguments.palletId
    end
    local ok, errorMessage = self:_sendToServer("workshop_command", request)
    if not ok then return false, errorMessage end
    self.pendingWorkshop = {
        operation = "command",
        commandId = request.commandId,
        resourceId = request.resourceId,
        action = request.action,
        sentAt = self.clock(),
    }
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
    self.activeWorkshop, self.pendingWorkshop = nil, nil
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
    return {
        mode = self.mode,
        status = self.status,
        playerCount = countEntries(self.players),
        address = self.localAddress,
        port = self.port,
        rtt = self.rtt,
    }
end

return Session
