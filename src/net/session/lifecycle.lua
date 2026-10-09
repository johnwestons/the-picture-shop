-- Session construction, reset, startup, and shutdown.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Session.new(options)
        options = options or {}
        return setmetatable({
            mode = "offline",
            status = "Offline",
            networkKind = "lan",
            transportFactory = options.transportFactory or Runtime.Transport,
            clock = options.clock or Runtime.defaultClock,
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
            port = Runtime.Address.DEFAULT_PORT,
            serverTick = 0,
            lastServerTick = -1,
            lastFightTick = -1,
            fightMatches = {},
            lastPlayerTicks = {},
            inputSequence = 0,
            inputAccumulator = 0,
            snapshotAccumulator = 0,
            shopStateAccumulator = 0,
            shopFallbackAccumulator = 0,
            shopRevision = 0,
            lastShopRevision = -1,
            radioRevision = 0,
            radioState = { trackIndex = 1, active = false, paused = true, muted = false, positionMs = 0 },
            lastRadioRevision = -1,
            lastVisitorTick = -1,
            lastEnvironmentTick = -1,
            lastEmployeeTick = -1,
            lastPalletJackTick = -1,
            lastForkliftTick = -1,
            lastCutterTick = -1,
            lastWindmillTick = -1,
            lastMachineTicks = {},
            shopDirty = false,
            connectedAt = nil,
            ready = false,
            requireHostApproval = false,
            clientConnectTimeout = Runtime.CONNECT_TIMEOUT,
            disconnectReason = nil,
            localTarget = nil,
            pendingShopSnapshot = nil,
            pendingShopState = nil,
            interactionRequestId = 0,
            pendingInteraction = nil,
            pendingHostInteractions = {},
            nextHighFiveRequestId = 0,
            highFiveClientRequestId = 0,
            pendingHostHighFiveRequests = {},
            pendingHostHighFiveResponses = {},
            pendingHighFives = {},
            highFiveOffers = {},
            activeHighFives = {},
            highFiveOutgoing = nil,
            highFiveNotice = nil,
            workshopRequestId = 0,
            pendingWorkshop = nil,
            pendingWorkshopSafety = nil,
            activeWorkshop = nil,
            workshopRevisions = {},
            workshopResources = {},
            pendingHostWorkshop = {},
            lastWorkshopSnapshotRevision = -1,
        }, Runtime.Session)
    end

    function Runtime.Session:_queue(eventType, values)
        local event = values or {}
        event.type = eventType
        self.pendingEvents[#self.pendingEvents + 1] = event
    end

    function Runtime.Session:drainEvents()
        local events = self.pendingEvents
        self.pendingEvents = {}
        return events
    end

    function Runtime.Session:isHost() return self.mode == "host" end
    function Runtime.Session:isClient() return self.mode == "client" end
    function Runtime.Session:isActive() return self.mode ~= "offline" end

    function Runtime.Session:_closeTransport(code, immediate)
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
        return false, Runtime.NETWORK_CLEANUP_ERROR
    end

    function Runtime.Session:_resetRuntime()
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
        self.lastFightTick = -1
        self.fightMatches = {}
        self.lastPlayerTicks = {}
        self.inputSequence = 0
        self.inputAccumulator = 0
        self.snapshotAccumulator = 0
        self.shopStateAccumulator = 0
        self.shopFallbackAccumulator = 0
        self.shopRevision = 0
        self.lastShopRevision = -1
        self.radioRevision = 0
        self.radioState = { trackIndex = 1, active = false, paused = true, muted = false, positionMs = 0 }
        self.lastRadioRevision = -1
        self.lastVisitorTick = -1
        self.lastEnvironmentTick = -1
        self.lastEmployeeTick = -1
        self.lastPalletJackTick = -1
        self.lastForkliftTick = -1
        self.lastCutterTick = -1
        self.lastWindmillTick = -1
        self.lastMachineTicks = {}
        self.shopDirty = false
        self.connectedAt = nil
        self.ready = false
        self.requireHostApproval = false
        self.clientConnectTimeout = Runtime.CONNECT_TIMEOUT
        self.disconnectReason = nil
        self.localTarget = nil
        self.pendingShopSnapshot = nil
        self.pendingShopState = nil
        self.interactionRequestId = 0
        self.pendingInteraction = nil
        self.pendingHostInteractions = {}
        self.nextHighFiveRequestId = 0
        self.highFiveClientRequestId = 0
        self.pendingHostHighFiveRequests = {}
        self.pendingHostHighFiveResponses = {}
        self.pendingHighFives = {}
        self.highFiveOffers = {}
        self.activeHighFives = {}
        self.highFiveOutgoing = nil
        self.highFiveNotice = nil
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

    function Runtime.Session:_markDisconnected(message)
        if self.terminal then return false end
        self.terminal = true
        self.ready = false
        self.connectedAt = nil
        self.status = tostring(message or "The multiplayer connection ended.")
        self:_queue("disconnected", { message = self.status })
        return true
    end

    function Runtime.Session:stop(reason)
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

    function Runtime.Session:startHost(options)
        options = options or {}
        if self:isActive() then
            local stopped, stopError = self:stop("Starting another session")
            if not stopped then return false, stopError end
        elseif self.transport then
            local cleaned, cleanupError = self:_closeTransport(0, true)
            if not cleaned then return false, cleanupError end
        end
        local port = tonumber(options.port) or Runtime.Address.DEFAULT_PORT
        local transportFactory = options.transportFactory or self.transportFactory
        if type(transportFactory) ~= "table"
            or type(transportFactory.createHost) ~= "function" then
            return false, "Network transport is unavailable."
        end
        local transport, errorMessage = transportFactory.createHost({
            port = port,
            bind = options.bind or "*",
            maxGuests = Runtime.Protocol.MAX_PLAYERS - 1,
            channels = Runtime.Protocol.CHANNEL_COUNT,
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
        self.sessionId = Runtime.identifier("s", self.clock)
        self.localId = 1
        self.localName = tostring(options.name or "LAN Host")
        self.localCharacter = tostring(options.character or "rabbit-worker")
        self.localFurColorway = tonumber(options.furColorway) or 1
        self.localOverallsColorway = tonumber(options.overallsColorway) or 1
        self.localAddress = self.networkKind == "lan"
            and Runtime.Address.detectLanAddress(options.addressOptions or {}) or nil
        self.players[1] = Runtime.newPlayer({
            id = 1, name = self.localName, character = self.localCharacter,
            furColorway = self.localFurColorway, overallsColorway = self.localOverallsColorway,
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

    function Runtime.Session:startClient(address, options)
        options = options or {}
        if self:isActive() then
            local stopped, stopError = self:stop("Starting another session")
            if not stopped then return false, stopError end
        elseif self.transport then
            local cleaned, cleanupError = self:_closeTransport(0, true)
            if not cleaned then return false, cleanupError end
        end
        local parsed, addressError = Runtime.Address.parse(address, options.port)
        if not parsed then return false, addressError end
        local transportFactory = options.transportFactory or self.transportFactory
        if type(transportFactory) ~= "table"
            or type(transportFactory.createClient) ~= "function" then
            return false, "Network transport is unavailable."
        end
        local transport, errorMessage = transportFactory.createClient(parsed.endpoint, {
            channels = Runtime.Protocol.CHANNEL_COUNT,
            enet = options.enet,
        })
        if not transport then return false, errorMessage end
        self:_resetRuntime()
        self.transport = transport
        self.mode = "client"
        self.networkKind = options.networkKind == "direct" and "direct" or "lan"
        self.clientConnectTimeout = self.networkKind == "direct"
            and Runtime.DIRECT_CLIENT_TIMEOUT or Runtime.CONNECT_TIMEOUT
        self.port = parsed.port
        self.hostAddress = parsed.host
        self.localName = tostring(options.name or "LAN Worker")
        self.localCharacter = tostring(options.character or "rabbit-worker")
        self.localFurColorway = tonumber(options.furColorway) or 1
        self.localOverallsColorway = tonumber(options.overallsColorway) or 1
        self.clientNonce = Runtime.identifier("n", self.clock)
        self.connectedAt = self.clock()
        self.status = self.networkKind == "direct"
            and "Connecting to the Direct Internet host"
            or ("Connecting to " .. parsed.endpoint)
        return true
    end
end

return Component
