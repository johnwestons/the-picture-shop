local Codec = require("src.net.codec")
local Protocol = require("src.net.protocol")
local Session = require("src.net.session")

local Test = {}

local function queuedTransport(network, mode)
    local transport = {
        mode = mode,
        inbound = {},
        closed = false,
    }

    local function record(direction, payload, channel, reliable)
        local envelope = Protocol.decode(payload)
        network.log[#network.log + 1] = {
            direction = direction,
            kind = envelope and envelope.type or "invalid",
            payload = payload,
            channel = channel,
            reliable = reliable == true,
        }
    end

    function transport:service(maxEvents)
        if self.serviceError then return nil, self.serviceError end
        local events = {}
        for _ = 1, math.min(tonumber(maxEvents) or 0, #self.inbound) do
            events[#events + 1] = table.remove(self.inbound, 1)
        end
        return events
    end

    function transport:send(peer, payload, channel, reliable)
        if self.closed or mode ~= "host" or peer ~= network.peer then
            return false, "fake peer is unavailable"
        end
        record("host_to_client", payload, channel, reliable)
        if network.client and not network.client.closed then
            network.client.inbound[#network.client.inbound + 1] = {
                type = "receive", peer = network.peer, data = payload, channel = channel,
            }
        end
        return true
    end

    function transport:sendToServer(payload, channel, reliable)
        if self.closed or mode ~= "client" or not network.host or network.host.closed then
            return false, "fake host is unavailable"
        end
        record("client_to_host", payload, channel, reliable)
        network.host.inbound[#network.host.inbound + 1] = {
            type = "receive", peer = network.peer, data = payload, channel = channel,
        }
        return true
    end

    function transport:broadcast(payload, channel, reliable)
        if self.closed or mode ~= "host" then return false, "fake host is unavailable" end
        record("host_broadcast", payload, channel, reliable)
        if network.client and not network.client.closed then
            network.client.inbound[#network.client.inbound + 1] = {
                type = "receive", peer = network.peer, data = payload, channel = channel,
            }
        end
        return true
    end

    function transport:disconnect(peer, code, immediate)
        if self.closed or mode ~= "host" or peer ~= network.peer then
            return false, "fake peer is unavailable"
        end
        network.disconnects[#network.disconnects + 1] = {
            code = code, immediate = immediate == true,
        }
        if network.client and not network.client.closed then
            network.client.inbound[#network.client.inbound + 1] = {
                type = "disconnect", peer = network.peer, code = code,
            }
        end
        return true
    end

    function transport:flush()
        network.flushes = network.flushes + 1
        return true
    end

    function transport:close(code, immediate)
        if self.closed then return true end
        self.closed = true
        network.closes[#network.closes + 1] = {
            mode = mode, code = code, immediate = immediate == true,
        }
        if mode == "client" and network.host and not network.host.closed then
            network.host.inbound[#network.host.inbound + 1] = {
                type = "disconnect", peer = network.peer, code = code,
            }
        elseif mode == "host" and network.client and not network.client.closed then
            network.client.inbound[#network.client.inbound + 1] = {
                type = "disconnect", peer = network.peer, code = code,
            }
        end
        return true
    end

    return transport
end

local function fakeNetwork()
    local network = {
        log = {},
        disconnects = {},
        closes = {},
        flushes = 0,
        peer = { id = "guest-peer" },
        factory = {},
    }

    function network.factory.createHost(options)
        network.hostOptions = options
        network.host = queuedTransport(network, "host")
        return network.host
    end

    function network.factory.createClient(endpoint, options)
        if not network.host then return nil, "fake host has not started" end
        network.clientEndpoint = endpoint
        network.clientOptions = options
        network.client = queuedTransport(network, "client")
        network.host.inbound[#network.host.inbound + 1] = {
            type = "connect", peer = network.peer,
        }
        network.client.inbound[#network.client.inbound + 1] = {
            type = "connect", peer = network.peer,
        }
        return network.client
    end

    function network:sendRawToHost(payload, channel, reliable)
        return self.client:sendToServer(payload, channel or Protocol.CHANNEL_STATE, reliable == true)
    end

    function network:messages(direction, kind)
        local matches = {}
        for _, item in ipairs(self.log) do
            if (not direction or item.direction == direction) and (not kind or item.kind == kind) then
                matches[#matches + 1] = item
            end
        end
        return matches
    end

    return network
end

local function captureHostNetwork()
    local network = {
        log = {},
        disconnects = {},
        closes = {},
        flushes = 0,
        factory = {},
        peers = {
            { id = "phone-worker-2" },
            { id = "phone-worker-3" },
            { id = "pc-worker-4" },
            { id = "tablet-worker-5" },
            { id = "phone-worker-6" },
            { id = "pc-worker-7" },
        },
    }

    local function record(direction, peer, payload, channel, reliable)
        local envelope = Protocol.decode(payload)
        network.log[#network.log + 1] = {
            direction = direction,
            peer = peer,
            kind = envelope and envelope.type or "invalid",
            payload = payload,
            channel = channel,
            reliable = reliable == true,
        }
    end

    function network.factory.createHost(options)
        network.hostOptions = options
        local transport = { closed = false, inbound = {} }
        function transport:service(maxEvents)
            local events = {}
            for _ = 1, math.min(tonumber(maxEvents) or 0, #self.inbound) do
                events[#events + 1] = table.remove(self.inbound, 1)
            end
            return events
        end
        function transport:send(peer, payload, channel, reliable)
            if self.closed then return false, "fake host is unavailable" end
            record("host_to_client", peer, payload, channel, reliable)
            return true
        end
        function transport:broadcast(payload, channel, reliable)
            if self.closed then return false, "fake host is unavailable" end
            record("host_broadcast", nil, payload, channel, reliable)
            return true
        end
        function transport:disconnect(peer, code, immediate)
            network.disconnects[#network.disconnects + 1] = {
                peer = peer,
                code = code,
                immediate = immediate == true,
            }
            return true
        end
        function transport:flush()
            network.flushes = network.flushes + 1
            return true
        end
        function transport:close(code, immediate)
            self.closed = true
            network.closes[#network.closes + 1] = {
                code = code,
                immediate = immediate == true,
            }
            return true
        end
        network.host = transport
        return transport
    end

    function network:queue(event)
        self.host.inbound[#self.host.inbound + 1] = event
    end

    function network:messages(direction, kind)
        local matches = {}
        for _, item in ipairs(self.log) do
            if (not direction or item.direction == direction)
                and (not kind or item.kind == kind)
            then
                matches[#matches + 1] = item
            end
        end
        return matches
    end

    return network
end

local function motionPlayer(x, y)
    return {
        x = x,
        y = y,
        velocityX = 0,
        velocityY = 0,
        intentX = 1,
        intentY = 0,
        moving = false,
        facing = 1,
        animationDistance = 0,
        character = "rabbit-worker",
    }
end

local function floatHeavyPlayerRecord(id, x, y)
    return {
        id = id,
        name = id == 1 and "LAN Host" or ("LAN Worker " .. tostring(id)),
        x = x or (420.12345678901235 + id * 0.9876543210987654),
        y = y or (520.98765432109872 - id * 0.12345678901234567),
        velocityX = 123.45678901234567,
        velocityY = -98.765432109876543,
        intentX = 0.70710678118654757,
        intentY = -0.70710678118654757,
        moving = true,
        facing = id % 2 == 0 and -1 or 1,
        animationDistance = 123456789.12345679 + id * 0.00000011920928955,
        character = "rabbit-worker",
        inputSequence = 4000000000 + id,
    }
end

local function applyFloatHeavyMotion(target, id)
    if type(target) ~= "table" then return target end
    local source = floatHeavyPlayerRecord(id)
    for _, field in ipairs({
        "x", "y", "velocityX", "velocityY", "intentX", "intentY", "moving",
        "facing", "animationDistance", "character", "inputSequence",
    }) do
        target[field] = source[field]
    end
    return target
end

local function visitorState(state, visible, x, y, character)
    return {
        state = state,
        visible = visible,
        x = x,
        y = y,
        waypoint = visible and 2 or 1,
        seatIndex = visible and 1 or 0,
        character = character or "business-cat",
        facing = 1,
        intentX = 0,
        intentY = 1,
        motionX = 0,
        motionY = 0,
        currentSpeed = 0,
        animationDistance = 0,
        animationClock = 0,
        idleClock = 0,
        waitTimer = 0,
        arrivalTimer = visible and 0 or 8,
        inMotion = state == "entering" or state == "exiting",
    }
end

local function palletJackState(overrides)
    local jack = {
        x = 560,
        y = 520,
        direction = "north",
        operating = false,
        moving = false,
    }
    for key, value in pairs(overrides or {}) do jack[key] = value end
    return jack
end

local function machinePoseState(overrides)
    local machines = {
        cutter = { x = 700, y = 420, direction = "northwest",
            moving = false, inMotion = false },
        wrapper = { x = 820, y = 360, direction = "northwest",
            moving = false, inMotion = false },
        windmill = { x = 850, y = 450, direction = "northwest",
            moving = false, inMotion = false },
    }
    for machine, fields in pairs(overrides or {}) do
        machines[machine] = machines[machine] or {}
        for key, value in pairs(fields) do machines[machine][key] = value end
    end
    return machines
end

local function cutterState(overrides)
    local view = {
        runtimeRevision = 1,
        step = "idle",
        phasePermille = 0,
        loaded = false,
        clamp = false,
        clampPermille = 0,
        bladePermille = 0,
        barrierClear = true,
        emergencyStopped = false,
        gaugeCentiInch = 0,
        programIndex = 1,
        memoryCentiInch = {},
        candidates = {
            { palletId = "JOB-CUT-P01", distancePixels = 24 },
        },
        genericSheets = 2500,
    }
    for key, value in pairs(overrides or {}) do view[key] = value end
    return view
end

local function windmillState(overrides)
    local view = {
        runtimeRevision = 1,
        status = "idle",
        speed = 2800,
        motor = false,
        feeder = false,
        impression = false,
        emergency = false,
        counter = 0,
        goodSheets = 0,
        spoilage = 0,
        targetSheets = 525,
        feedStart = 525,
        feedRemaining = 525,
        proofApproved = false,
        artworkVerified = false,
        setupPermille = { 0, 0, 0, 0, 0, 0 },
        candidates = {
            { palletId = "JOB-PRESS-P01", colorIndex = 1 },
        },
        serviceStep = "idle",
        servicePermille = 0,
        plateMarkerPermille = 0,
    }
    for key, value in pairs(overrides or {}) do view[key] = value end
    return view
end

local function eventNamed(events, name)
    for _, event in ipairs(events or {}) do
        if event.type == name then return event end
    end
end

local function decodedPayload(message)
    local envelope = message and Protocol.decode(message.payload)
    return envelope and envelope.payload
end

local function runCutterSafetyOrderingRegression(args)
    local client, host, network = args.client, args.host, args.network
    local previousWorkshopTick = client.lastWorkshopSnapshotRevision
    local grantRevision = client:workshopInfo().revision
    local preGrantSnapshot = Protocol.encode("workshop_snapshot", {
        sessionId = host.sessionId,
        revision = previousWorkshopTick + 1,
        resources = Codec.array({
            { resourceId = "reception_customer", revision = 0, occupied = false },
            { resourceId = "vendor", revision = 0, occupied = false },
            { resourceId = "truck", revision = 0, occupied = false },
            { resourceId = "work_phone", revision = 0, occupied = false },
            { resourceId = "warehouse", revision = 0, occupied = false },
            { resourceId = "office_computer", revision = 0, occupied = false },
            { resourceId = "cutter", revision = math.max(0, grantRevision - 1),
                occupied = false },
            { resourceId = "skid_wrapper", revision = 0, occupied = false },
            { resourceId = "pallet_jack", revision = 0, occupied = false },
            { resourceId = "windmill", revision = 0, occupied = false },
        }),
        wrapper = { step = "idle", progress = 0, cycleTime = 3,
            pallets = Codec.array({}) },
    })
    network.host:send(network.peer, preGrantSnapshot, Protocol.CHANNEL_STATE, false)
    client:update(0, args.clientContext)
    local preGrantEvents = client:drainEvents()
    args.check("multiplayer_session_stale_pregrant_snapshot_cannot_revoke_new_cutter_lease",
        eventNamed(preGrantEvents, "workshop_lost") == nil
        and client:workshopInfo() and client:workshopInfo().revision == grantRevision)

    local workshopCallStart = #args.workshopCalls
    local ordinaryPending = client:requestWorkshopCommand(
        "set_gauge", { gaugeCentiInch = 500 })
    local urgentWhilePending = client:requestWorkshopCommand("emergency_stop", {})
    local duplicateSafetyRejected = not client:requestWorkshopCommand(
        "set_barrier", { barrierClear = false })
    local safetyWires = network:messages("client_to_host", "workshop_command")
    local ordinarySafetyWire = decodedPayload(safetyWires[#safetyWires - 1])
    local emergencySafetyWire = decodedPayload(safetyWires[#safetyWires])
    host:update(0, args.hostContext)
    client:update(0, args.clientContext)
    local concurrentResults = client:drainEvents()
    local firstConcurrentCall = args.workshopCalls[workshopCallStart + 1]
    local secondConcurrentCall = args.workshopCalls[workshopCallStart + 2]
    local ordinaryResult, emergencyResult
    for _, event in ipairs(concurrentResults) do
        if event.type == "workshop_result" and event.action == "set_gauge" then
            ordinaryResult = event
        elseif event.type == "workshop_result" and event.action == "emergency_stop" then
            emergencyResult = event
        end
    end
    args.check("multiplayer_session_cutter_safety_preempts_ordinary_pending_command",
        ordinaryPending and urgentWhilePending and duplicateSafetyRejected
        and ordinarySafetyWire and ordinarySafetyWire.action == "set_gauge"
        and emergencySafetyWire and emergencySafetyWire.action == "emergency_stop"
        and ordinarySafetyWire.expectedRevision == emergencySafetyWire.expectedRevision
        and firstConcurrentCall and firstConcurrentCall.payload.action == "emergency_stop"
        and secondConcurrentCall and secondConcurrentCall.payload.action == "set_gauge"
        and ordinaryResult and ordinaryResult.accepted and not ordinaryResult.urgentSafety
        and emergencyResult and emergencyResult.accepted and emergencyResult.urgentSafety
        and client.pendingWorkshop == nil and client.pendingWorkshopSafety == nil
        and client:workshopInfo().revision == args.revision())

    local authoritativeRevision = args.revision()
    local previousCutterTick = client.lastCutterTick
    client.activeWorkshop.revision = authoritativeRevision - 1
    client.workshopRevisions.cutter = authoritativeRevision - 1
    local repairCutterPacket = Protocol.encode("cutter_snapshot", {
        sessionId = host.sessionId,
        serverTick = previousCutterTick + 1,
        resourceRevision = authoritativeRevision,
        view = args.view,
    })
    network.host:send(network.peer, repairCutterPacket, Protocol.CHANNEL_STATE, false)
    client:update(0, args.clientContext)
    local repairEvent = eventNamed(client:drainEvents(), "cutter_state")
    local staleRevision = math.max(0, authoritativeRevision - 1)
    local staleWorkshopPacket = Protocol.encode("workshop_snapshot", {
        sessionId = host.sessionId,
        revision = previousWorkshopTick + 2,
        resources = Codec.array({
            { resourceId = "reception_customer", revision = 0, occupied = false },
            { resourceId = "vendor", revision = 0, occupied = false },
            { resourceId = "truck", revision = 0, occupied = false },
            { resourceId = "office_computer", revision = 0, occupied = false },
            { resourceId = "cutter", revision = staleRevision, occupied = true,
                ownerPlayerId = client.localId },
            { resourceId = "skid_wrapper", revision = 0, occupied = false },
            { resourceId = "pallet_jack", revision = 0, occupied = false },
            { resourceId = "windmill", revision = 0, occupied = false },
        }),
        wrapper = { step = "idle", progress = 0, cycleTime = 3,
            pallets = Codec.array({}) },
    })
    network.host:send(network.peer, staleWorkshopPacket, Protocol.CHANNEL_STATE, false)
    client:update(0, args.clientContext)
    client:drainEvents()
    args.check("multiplayer_session_cutter_live_revision_repairs_and_stale_workshop_cannot_roll_back",
        repairEvent and repairEvent.resourceRevision == authoritativeRevision
        and client:workshopInfo().revision == authoritativeRevision
        and client.workshopRevisions.cutter == authoritativeRevision)
    client.lastCutterTick = previousCutterTick
    client.lastWorkshopSnapshotRevision = previousWorkshopTick
end

local function runWindmillSessionRegression(args)
    local client, host, network = args.client, args.host, args.network
    local hostContext, clientContext, check =
        args.hostContext, args.clientContext, args.check
    local view = windmillState()
    args.setView(view)
    hostContext.getWindmillSnapshot = function()
        return { resourceRevision = args.revision(), view = view }
    end

    local requested = client:requestWorkshopAcquire("windmill")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local grant = eventNamed(client:drainEvents(), "workshop_grant")
    local grantPackets = network:messages("host_to_client", "workshop_grant")
    local grantWire = decodedPayload(grantPackets[#grantPackets])
    local grantRevision = grant and grant.revision
    check("multiplayer_session_worker_acquires_host_owned_windmill_console",
        requested and grant and grant.granted and grant.resourceId == "windmill"
        and grant.leaseId == "lease-windmill-test"
        and grant.view and grant.view.status == "idle"
        and grantWire and grantWire.view
        and Codec.isArray(grantWire.view.setupPermille)
        and Codec.isArray(grantWire.view.candidates)
        and client:workshopInfo().revision == args.revision())

    local previousWorkshopTick = client.lastWorkshopSnapshotRevision
    local stalePregrant = Protocol.encode("workshop_snapshot", {
        sessionId = host.sessionId,
        revision = previousWorkshopTick + 1,
        resources = Codec.array({
            { resourceId = "reception_customer", revision = 0, occupied = false },
            { resourceId = "vendor", revision = 0, occupied = false },
            { resourceId = "truck", revision = 0, occupied = false },
            { resourceId = "office_computer", revision = 0, occupied = false },
            { resourceId = "cutter", revision = 0, occupied = false },
            { resourceId = "windmill", revision = math.max(0, grantRevision - 1),
                occupied = false },
            { resourceId = "skid_wrapper", revision = 0, occupied = false },
            { resourceId = "pallet_jack", revision = 0, occupied = false },
        }),
        wrapper = { step = "idle", progress = 0, cycleTime = 3,
            pallets = Codec.array({}) },
    })
    network.host:send(network.peer, stalePregrant, Protocol.CHANNEL_STATE, false)
    client:update(0, clientContext)
    local pregrantEvents = client:drainEvents()
    check("multiplayer_session_stale_pregrant_snapshot_cannot_revoke_new_windmill_lease",
        eventNamed(pregrantEvents, "workshop_lost") == nil
        and client:workshopInfo() and client:workshopInfo().revision == grantRevision)

    local wires = {}
    local function sendCommand(action, arguments)
        local before = #network:messages("client_to_host", "workshop_command")
        local sent = client:requestWorkshopCommand(action, arguments)
        host:update(0, hostContext)
        client:update(0, clientContext)
        local result = eventNamed(client:drainEvents(), "workshop_result")
        local packets = network:messages("client_to_host", "workshop_command")
        wires[#wires + 1] = decodedPayload(packets[before + 1])
        return sent and result and result.accepted
    end
    local commandsAccepted = sendCommand(
        "load_pallet", { palletId = "JOB-PRESS-P01", state = { forged = true } })
        and sendCommand("begin_setup", {
            setupTask = "chase", score = 1000, playerId = 2,
        })
        and sendCommand("setup_action", {
            setupAction = "align", score = 1000, accuracy = 1,
        })
        and sendCommand("process_plate", {
            plateId = "PLATE-PRESS-C01", accuracy = 1,
        })
        and sendCommand("toggle_motor", { motor = true, state = { forged = true } })
    local semanticWires = #wires == 5
        and wires[1].palletId == "JOB-PRESS-P01" and wires[1].state == nil
        and wires[2].setupTask == "chase"
        and wires[2].score == nil and wires[2].playerId == nil
        and wires[3].setupAction == "align"
        and wires[3].score == nil and wires[3].accuracy == nil
        and wires[4].plateId == "PLATE-PRESS-C01" and wires[4].accuracy == nil
        and wires[5].motor == nil and wires[5].state == nil
    for index = 2, #wires do
        semanticWires = semanticWires
            and wires[index - 1].commandId < wires[index].commandId
            and wires[index].expectedRevision == wires[index - 1].expectedRevision + 1
    end
    check("multiplayer_session_windmill_commands_use_closed_host_authored_shapes",
        commandsAccepted and semanticWires and view.palletId == "JOB-PRESS-P01"
        and view.setupTask == "chase" and view.setupPermille[1] == 250)

    local safetySeenBeforeSimulation = false
    hostContext.updateWorkshop = function()
        if args.resource() == "windmill" then
            safetySeenBeforeSimulation = view.emergency and not view.motor
                and not view.feeder and not view.impression
        end
    end
    local safetyWireStart = #network:messages("client_to_host", "workshop_command")
    local workshopCallStart = #args.workshopCalls
    local ordinaryPending = client:requestWorkshopCommand("speed_up", {})
    local safetyPending = client:requestWorkshopCommand("emergency_stop", {})
    local duplicateSafetyRejected = not client:requestWorkshopCommand("emergency_stop", {})
    local safetyPackets = network:messages("client_to_host", "workshop_command")
    local ordinaryWire = decodedPayload(safetyPackets[safetyWireStart + 1])
    local emergencyWire = decodedPayload(safetyPackets[safetyWireStart + 2])
    host:update(0, hostContext)
    client:update(0, clientContext)
    local safetyEvents = client:drainEvents()
    local firstSafetyCall = args.workshopCalls[workshopCallStart + 1]
    local secondSafetyCall = args.workshopCalls[workshopCallStart + 2]
    local ordinaryResult, emergencyResult
    for _, event in ipairs(safetyEvents) do
        if event.type == "workshop_result" and event.action == "speed_up" then
            ordinaryResult = event
        elseif event.type == "workshop_result" and event.action == "emergency_stop" then
            emergencyResult = event
        end
    end
    hostContext.updateWorkshop = nil
    check("multiplayer_session_windmill_emergency_uses_separate_preemptive_safety_lane",
        ordinaryPending and safetyPending and duplicateSafetyRejected
        and ordinaryWire and ordinaryWire.action == "speed_up"
        and emergencyWire and emergencyWire.action == "emergency_stop"
        and ordinaryWire.expectedRevision == emergencyWire.expectedRevision
        and firstSafetyCall and firstSafetyCall.payload.action == "emergency_stop"
        and secondSafetyCall and secondSafetyCall.payload.action == "speed_up"
        and ordinaryResult and ordinaryResult.accepted and not ordinaryResult.urgentSafety
        and emergencyResult and emergencyResult.accepted and emergencyResult.urgentSafety
        and client.pendingWorkshop == nil and client.pendingWorkshopSafety == nil
        and safetySeenBeforeSimulation)

    host:update(0.09, hostContext)
    client:update(0, clientContext)
    local stateEvent = eventNamed(client:drainEvents(), "windmill_state")
    local snapshotPackets = network:messages("host_to_client", "windmill_snapshot")
    local latestPacket = snapshotPackets[#snapshotPackets]
    local latestWire = decodedPayload(latestPacket)
    local liveTick = client.lastWindmillTick
    local stalePacket = Protocol.encode("windmill_snapshot", {
        sessionId = host.sessionId, serverTick = liveTick,
        resourceRevision = args.revision(), view = view,
    })
    local wrongSessionPacket = Protocol.encode("windmill_snapshot", {
        sessionId = "spoofed-session", serverTick = liveTick + 1,
        resourceRevision = args.revision(), view = view,
    })
    network.host:send(network.peer, stalePacket, Protocol.CHANNEL_STATE, false)
    network.host:send(network.peer, wrongSessionPacket, Protocol.CHANNEL_STATE, false)
    client:update(0, clientContext)
    local ignoredEvents = client:drainEvents()
    check("multiplayer_session_windmill_live_state_is_12hz_mtu_safe_and_monotonic",
        stateEvent and stateEvent.serverTick == liveTick
        and stateEvent.resourceRevision == args.revision() and stateEvent.view.emergency
        and latestWire and latestWire.view.status == "stopped"
        and Codec.isArray(latestWire.view.setupPermille)
        and Codec.isArray(latestWire.view.candidates)
        and latestPacket.channel == Protocol.CHANNEL_STATE and not latestPacket.reliable
        and #latestPacket.payload <= Protocol.MAX_PACKET_BYTES
        and eventNamed(ignoredEvents, "windmill_state") == nil
        and client.lastWindmillTick == liveTick)

    local currentRevision = args.revision()
    client.activeWorkshop.revision = currentRevision - 1
    client.workshopRevisions.windmill = currentRevision - 1
    local repairPacket = Protocol.encode("windmill_snapshot", {
        sessionId = host.sessionId, serverTick = liveTick + 1,
        resourceRevision = currentRevision, view = view,
    })
    network.host:send(network.peer, repairPacket, Protocol.CHANNEL_STATE, false)
    client:update(0, clientContext)
    local repaired = eventNamed(client:drainEvents(), "windmill_state")
    local staleWorkshop = Protocol.encode("workshop_snapshot", {
        sessionId = host.sessionId,
        revision = client.lastWorkshopSnapshotRevision + 1,
        resources = Codec.array({
            { resourceId = "reception_customer", revision = 0, occupied = false },
            { resourceId = "vendor", revision = 0, occupied = false },
            { resourceId = "truck", revision = 0, occupied = false },
            { resourceId = "office_computer", revision = 0, occupied = false },
            { resourceId = "cutter", revision = 0, occupied = false },
            { resourceId = "windmill", revision = currentRevision - 1,
                occupied = true, ownerPlayerId = client.localId },
            { resourceId = "skid_wrapper", revision = 0, occupied = false },
            { resourceId = "pallet_jack", revision = 0, occupied = false },
        }),
        wrapper = { step = "idle", progress = 0, cycleTime = 3,
            pallets = Codec.array({}) },
    })
    network.host:send(network.peer, staleWorkshop, Protocol.CHANNEL_STATE, false)
    client:update(0, clientContext)
    local staleWorkshopEvents = client:drainEvents()
    check("multiplayer_session_windmill_live_revision_repairs_and_stale_occupancy_cannot_rollback",
        repaired and repaired.resourceRevision == currentRevision
        and eventNamed(staleWorkshopEvents, "workshop_lost") == nil
        and client:workshopInfo().revision == currentRevision
        and client.workshopRevisions.windmill == currentRevision)

    local released = client:releaseWorkshop("closed")
    host:update(0, hostContext)
    check("multiplayer_session_worker_releases_windmill_console",
        released and client:workshopInfo() == nil
        and args.lease() == nil and args.resource() == nil)

    local reacquired = client:requestWorkshopAcquire("windmill")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local reacquiredGrant = eventNamed(client:drainEvents(), "workshop_grant")
    local mutationBeforeTimeout = args.mutation()
    local ordinaryTimeout = client:requestWorkshopCommand("toggle_feeder", {})
    local safetyTimeout = client:requestWorkshopCommand("emergency_stop", {})
    args.advanceClock(4.01)
    client:update(0, clientContext)
    local timeoutEvents = client:drainEvents()
    local timedOutOrdinary, timedOutSafety
    for _, event in ipairs(timeoutEvents) do
        if event.type == "workshop_result" and event.action == "toggle_feeder" then
            timedOutOrdinary = event
        elseif event.type == "workshop_result" and event.action == "emergency_stop" then
            timedOutSafety = event
        end
    end
    check("multiplayer_session_windmill_ordinary_and_safety_timeouts_clear_independently",
        reacquired and reacquiredGrant and reacquiredGrant.granted
        and ordinaryTimeout and safetyTimeout
        and timedOutOrdinary and not timedOutOrdinary.accepted
        and timedOutOrdinary.code == "timeout" and not timedOutOrdinary.urgentSafety
        and timedOutSafety and not timedOutSafety.accepted
        and timedOutSafety.code == "timeout" and timedOutSafety.urgentSafety
        and client.pendingWorkshop == nil and client.pendingWorkshopSafety == nil
        and client:workshopInfo() and client:workshopInfo().resourceId == "windmill")
    return mutationBeforeTimeout
end

local function runStaleWorkshopGrantRevisionRegression(check)
    local function pendingClient(knownRevision, requestId)
        local client = Session.new({ clock = function() return 100 end })
        client.mode = "client"
        client.ready = true
        client.sessionId = "grant-revision-test"
        client.localId = 2
        client.workshopRevisions.windmill = knownRevision
        client.pendingWorkshop = {
            operation = "acquire",
            requestId = requestId,
            resourceId = "windmill",
            sentAt = 100,
        }
        return client
    end

    local function deliver(client, requestId, revision, granted)
        local packet = Protocol.encode("workshop_grant", {
            sessionId = client.sessionId,
            requestId = requestId,
            resourceId = "windmill",
            granted = granted,
            leaseId = granted and ("lease-stale-" .. tostring(requestId)) or nil,
            code = granted and "granted" or "revision_conflict",
            message = granted and "Windmill control granted." or "Revision changed.",
            revision = revision,
        })
        local envelope = packet and Protocol.decode(packet)
        if envelope then client:_handleClientEnvelope(envelope) end
        return envelope, client:drainEvents()
    end

    local rejectionClient = pendingClient(9, 1)
    local rejectionEnvelope, rejectionEvents = deliver(rejectionClient, 1, 7, false)
    local rejection = eventNamed(rejectionEvents, "workshop_grant")

    local staleGrantClient = pendingClient(9, 2)
    local staleGrantEnvelope, staleGrantEvents = deliver(staleGrantClient, 2, 8, true)
    local staleGrant = eventNamed(staleGrantEvents, "workshop_grant")

    local currentGrantClient = pendingClient(9, 3)
    local currentGrantEnvelope, currentGrantEvents = deliver(currentGrantClient, 3, 9, true)
    local currentGrant = eventNamed(currentGrantEvents, "workshop_grant")

    check("multiplayer_session_stale_workshop_grants_and_rejections_never_roll_back_revision",
        rejectionEnvelope and rejection and not rejection.granted
        and rejectionClient.workshopRevisions.windmill == 9
        and rejectionClient.activeWorkshop == nil
        and staleGrantEnvelope and staleGrantClient.workshopRevisions.windmill == 9
        and staleGrantClient.activeWorkshop == nil
        and (staleGrant == nil or not staleGrant.granted)
        and currentGrantEnvelope and currentGrant and currentGrant.granted
        and currentGrantClient.activeWorkshop
        and currentGrantClient.activeWorkshop.leaseId == "lease-stale-3"
        and currentGrantClient.activeWorkshop.revision == 9)
end

local function runHudExperienceRegression(check)
    local client = Session.new({ clock = function() return 42 end })
    client.mode = "client"
    client.networkKind = "lan"
    client.ready = true
    client.status = "3/4 workers connected"
    client.localId = 3
    client.rtt = 52.4
    client.players = {
        [1] = { id = 1, name = "PC Host", character = "rabbit-worker" },
        [2] = { id = 2, name = "Press Worker", character = "rabbit-worker" },
        [3] = { id = 3, name = "Android Worker", character = "rabbit-worker" },
    }
    client.workshopResources = {
        { resourceId = "cutter", occupied = true, ownerPlayerId = 2 },
        { resourceId = "pallet_jack", occupied = false },
    }
    client.activeWorkshop = {
        resourceId = "pallet_jack", leaseId = "lease-ui", revision = 4,
    }
    client.pendingWorkshop = {
        operation = "command", resourceId = "pallet_jack",
        action = "move_machine", commandId = 7, sentAt = 42,
    }

    local hud = client:hudInfo()
    check("multiplayer_session_guest_hud_exposes_bounded_roster_authority_and_activity",
        hud.mode == "client" and hud.networkKind == "lan"
        and hud.localPlayerId == 3 and hud.playerCount == 3
        and #hud.players == 3
        and hud.players[1].playerId == 1 and hud.players[1].isHost
        and not hud.players[1].isLocal
        and hud.players[3].playerId == 3 and hud.players[3].isLocal
        and hud.players[1].peer == nil and hud.players[1].x == nil
        and hud.activeResourceId == "pallet_jack"
        and hud.pendingActivity.kind == "workshop_action"
        and hud.pendingActivity.resourceId == "pallet_jack"
        and hud.pendingActivity.action == "move_machine"
        and #hud.workshopResources == 2
        and hud.workshopResources[1].ownerPlayerId == 2)

    hud.players[1].name = "tampered"
    hud.workshopResources[1].occupied = false
    check("multiplayer_session_guest_hud_returns_detached_display_records",
        client.players[1].name == "PC Host"
        and client.workshopResources[1].occupied == true)

    client.pendingWorkshopSafety = {
        resourceId = "cutter", action = "emergency_stop", commandId = 8, sentAt = 42,
    }
    local urgentHud = client:hudInfo()
    check("multiplayer_session_guest_hud_prioritizes_urgent_safety_feedback",
        urgentHud.pendingActivity.kind == "urgent_safety"
        and urgentHud.pendingActivity.resourceId == "cutter"
        and urgentHud.pendingActivity.action == "emergency_stop")

    client:_resetRuntime()
    check("multiplayer_session_reset_clears_guest_hud_occupancy",
        #client.workshopResources == 0 and #client:hudInfo().workshopResources == 0)
end

local function runFourDeviceShardingRegression(check, clock, addressOptions)
    local network = captureHostNetwork()
    local host = Session.new({ transportFactory = network.factory, clock = clock })
    local context = {
        localPlayer = floatHeavyPlayerRecord(1),
        resolveGuestSpawn = function(hostX, hostY, guestIndex)
            return hostX + guestIndex * 7.1234567890123457,
                hostY - guestIndex * 3.9876543210987654
        end,
        getShopSnapshot = function()
            return {
                state = {
                    money = 2345,
                    inventory = { paper = 2500 },
                    jobs = { active = {}, completed = {} },
                },
                player = { x = 420.12345678901235, y = 520.98765432109872,
                    character = "rabbit-worker" },
            }
        end,
        moveRemote = function() end,
    }
    host:startHost({
        name = "LAN Host",
        character = "rabbit-worker",
        x = context.localPlayer.x,
        y = context.localPlayer.y,
        addressOptions = addressOptions,
    })
    host.sessionId = "four-device-shards"
    applyFloatHeavyMotion(host.players[1], 1)

    local function helloEnvelope(id)
        local packet = Protocol.encode("hello", {
            clientNonce = "float-worker-" .. tostring(id),
            name = "LAN Worker " .. tostring(id),
            character = "rabbit-worker",
        })
        return packet and Protocol.decode(packet)
    end

    for id = 2, 3 do
        host:_handleHostEnvelope(network.peers[id - 1], helloEnvelope(id), context)
        applyFloatHeavyMotion(host.players[id], id)
    end
    host:drainEvents()
    network.log = {}

    host:_handleHostEnvelope(network.peers[3], helloEnvelope(4), context)
    local fourthJoinEvents = host:drainEvents()
    local fourthJoined = eventNamed(fourthJoinEvents, "player_joined")
    local fourthJoinError = eventNamed(fourthJoinEvents, "error")
    local fourthWelcomes = network:messages("host_to_client", "welcome")
    local fourthShops = network:messages("host_to_client", "shop_snapshot")
    local fourthWelcome = decodedPayload(fourthWelcomes[1])
    check("multiplayer_session_fourth_float_heavy_worker_receives_mtu_safe_welcome",
        fourthJoined and fourthJoined.playerId == 4 and fourthJoinError == nil
        and host.players[4]
        and host.peerToId[network.peers[3]] == 4
        and host.idToPeer[4] == network.peers[3]
        and #fourthWelcomes == 1 and #fourthShops == 1
        and #fourthWelcomes[1].payload <= Protocol.MAX_PACKET_BYTES
        and fourthWelcome and fourthWelcome.playerId == 4
        and #fourthWelcome.players == 2
        and fourthWelcome.players[1].id == 1
        and fourthWelcome.players[2].id == 4
        and #network.disconnects == 0)

    applyFloatHeavyMotion(host.players[4], 4)
    local pendingSnapshotPeer = { id = "pending-no-hello" }
    host.pendingPeers[pendingSnapshotPeer] = clock()
    network.log = {}
    host:update(0.1, context)
    local allSnapshots = network:messages("host_to_client", "snapshot")
    local selectedSnapshots, snapshotsByPeer = {}, {}
    local pendingPeerReceivedSnapshot = false
    for _, message in ipairs(allSnapshots) do
        snapshotsByPeer[message.peer] = (snapshotsByPeer[message.peer] or 0) + 1
        if message.peer == network.peers[3] then
            selectedSnapshots[#selectedSnapshots + 1] = message
        elseif message.peer == pendingSnapshotPeer then
            pendingPeerReceivedSnapshot = true
        end
    end
    local shardTick, seenShardIds = nil, {}
    local shardsValid = #allSnapshots == 12
        and #selectedSnapshots == 4
        and snapshotsByPeer[network.peers[1]] == 4
        and snapshotsByPeer[network.peers[2]] == 4
        and snapshotsByPeer[network.peers[3]] == 4
        and not pendingPeerReceivedSnapshot
    for _, message in ipairs(selectedSnapshots) do
        local payload = decodedPayload(message)
        shardsValid = shardsValid and payload ~= nil
            and #payload.players == 1
            and #message.payload <= Protocol.MAX_PACKET_BYTES
            and message.channel == Protocol.CHANNEL_STATE
            and not message.reliable
        if payload then
            shardTick = shardTick or payload.serverTick
            local id = payload.players[1].id
            shardsValid = shardsValid
                and payload.serverTick == shardTick and not seenShardIds[id]
            seenShardIds[id] = true
        end
    end
    check("multiplayer_session_four_player_tick_emits_four_same_tick_snapshot_shards",
        shardsValid and shardTick == host.serverTick
        and seenShardIds[1] and seenShardIds[2] and seenShardIds[3] and seenShardIds[4])

    local mergeClient = Session.new({ clock = clock })
    mergeClient.mode = "client"
    mergeClient.sessionId = "merge-snapshot-shards"
    mergeClient.localId = 4
    mergeClient.ready = true
    mergeClient:_installRoster(Codec.array({
        floatHeavyPlayerRecord(1),
        floatHeavyPlayerRecord(4),
    }))

    local function deliverShard(record, tick)
        local packet = Protocol.encode("snapshot", {
            sessionId = mergeClient.sessionId,
            serverTick = tick,
            players = Codec.array({ record }),
        })
        local envelope = packet and Protocol.decode(packet)
        if not envelope then return false end
        mergeClient:_handleClientEnvelope(envelope)
        return true
    end

    local mergeDelivered = true
    for id = 1, 4 do
        mergeDelivered = deliverShard(floatHeavyPlayerRecord(
            id, 500 + id * 10.123456789012346, 600 + id * 0.9876543210987654), 70)
            and mergeDelivered
    end
    mergeDelivered = deliverShard(floatHeavyPlayerRecord(2, 620.25, 602.25), 71)
        and mergeDelivered
    mergeDelivered = deliverShard(floatHeavyPlayerRecord(1, 510.5, 601.5), 72)
        and mergeDelivered
    -- This is older than the latest global tick, but newer for player 3.
    mergeDelivered = deliverShard(floatHeavyPlayerRecord(3, 630.75, 603.75), 71)
        and mergeDelivered
    -- Player 2 already has tick 71; delayed tick 70 must not regress it.
    mergeDelivered = deliverShard(floatHeavyPlayerRecord(2, 99, 99), 70)
        and mergeDelivered
    check("multiplayer_session_client_merges_same_tick_shards_with_per_player_freshness",
        mergeDelivered
        and mergeClient.players[1] and mergeClient.players[2]
        and mergeClient.players[3] and mergeClient.players[4]
        and mergeClient.players[1]._targetX == 510.5
        and mergeClient.players[2]._targetX == 620.25
        and mergeClient.players[3]._targetX == 630.75
        and mergeClient.localTarget and mergeClient.localTarget.id == 4
        and mergeClient.lastServerTick == 72)

    local leavePacket = Protocol.encode("leave", {
        sessionId = mergeClient.sessionId,
        playerId = 3,
        reason = "Connection lost",
        serverTick = 73,
    })
    local leaveEnvelope = leavePacket and Protocol.decode(leavePacket)
    if leaveEnvelope then mergeClient:_handleClientEnvelope(leaveEnvelope) end
    local leaveEvents = mergeClient:drainEvents()
    local playerLeft = eventNamed(leaveEvents, "player_left")
    local tombstoneInstalled = playerLeft and playerLeft.playerId == 3
        and mergeClient.players[3] == nil
        and mergeClient.lastPlayerTicks[3] == 73
    local staleDepartedShardDelivered = deliverShard(
        floatHeavyPlayerRecord(3, 333, 333), 72)
    local staleDepartedShardBlocked = mergeClient.players[3] == nil
        and mergeClient.lastPlayerTicks[3] == 73
    local reusedIdShardDelivered = deliverShard(
        floatHeavyPlayerRecord(3, 734, 734), 74)
    check("multiplayer_session_leave_tombstone_blocks_delayed_shard_until_id_is_newer",
        leaveEnvelope and tombstoneInstalled and staleDepartedShardDelivered
        and staleDepartedShardBlocked and reusedIdShardDelivered
        and mergeClient.players[3]
        and mergeClient.players[3]._targetX == 734
        and mergeClient.lastPlayerTicks[3] == 74)

    local seedClient = Session.new({ clock = clock })
    seedClient.mode = "client"
    local seedHost = floatHeavyPlayerRecord(1, 501, 601)
    local seedSelf = floatHeavyPlayerRecord(4, 504, 604)
    local seedWelcomePacket = Protocol.encode("welcome", {
        sessionId = "welcome-seed-ticks",
        playerId = 4,
        serverTick = 80,
        players = Codec.array({ seedHost, seedSelf }),
    })
    local seedWelcome = seedWelcomePacket and Protocol.decode(seedWelcomePacket)
    if seedWelcome then seedClient:_handleClientEnvelope(seedWelcome) end
    seedClient.ready = seedWelcome ~= nil
    local function deliverSeedShard(record, tick)
        local packet = Protocol.encode("snapshot", {
            sessionId = seedClient.sessionId,
            serverTick = tick,
            players = Codec.array({ record }),
        })
        local envelope = packet and Protocol.decode(packet)
        if not envelope then return false end
        seedClient:_handleClientEnvelope(envelope)
        return true
    end
    local sameTickSeedDelivered = deliverSeedShard(
        floatHeavyPlayerRecord(1, 999, 999), 80)
    local sameTickSeedBlocked = seedClient.players[1]
        and seedClient.players[1].x == 501
        and seedClient.players[1]._targetX == 501
    local newerSeedDelivered = deliverSeedShard(
        floatHeavyPlayerRecord(1, 811, 611), 81)
    check("multiplayer_session_welcome_seeds_per_player_snapshot_ticks",
        seedWelcome and seedClient.lastPlayerTicks[4] == 80
        and sameTickSeedDelivered and sameTickSeedBlocked and newerSeedDelivered
        and seedClient.players[1]._targetX == 811
        and seedClient.lastPlayerTicks[1] == 81)

    host:stop("Four-device shard test complete")
end

local function runDirectAdmissionControls(options)
    local clock, check = options.clock, options.check
    local network = fakeNetwork()
    local host = Session.new({ transportFactory = network.factory, clock = clock })
    local client = Session.new({ transportFactory = network.factory, clock = clock })
    local snapshots = 0
    local context = {
        localPlayer = motionPlayer(400, 500),
        resolveGuestSpawn = function() return 430, 500 end,
        getShopSnapshot = function()
            snapshots = snapshots + 1
            return {
                state = { money = 777, inventory = {}, jobs = {} },
                player = { x = 400, y = 500, character = "rabbit-worker" },
            }
        end,
    }
    host:startHost({
        name = "Direct Approval Host", character = "rabbit-worker",
        networkKind = "direct", transportFactory = network.factory,
    })
    client:startClient("192.0.2.10:22122", {
        name = "PC Direct Guest", character = "rabbit-worker",
        networkKind = "direct", transportFactory = network.factory,
    })
    host:update(0, context)
    client:update(0, { localPlayer = motionPlayer(430, 500), inputX = 0, inputY = 0 })
    host:update(0, context)
    local request = eventNamed(host:drainEvents(), "join_requested")
    local hud = host:hudInfo()
    check("multiplayer_session_direct_request_discloses_no_save_before_host_decision",
        request and request.name == "PC Direct Guest"
        and snapshots == 0 and host.players[2] == nil
        and #network:messages("host_to_client", "welcome") == 0
        and #network:messages("host_to_client", "shop_snapshot") == 0
        and hud.canManage and hud.pendingJoinCount == 1
        and hud.pendingJoins[1].requestId == request.requestId
        and hud.pendingJoins[1].name == "PC Direct Guest"
        and hud.pendingJoins[1].peer == nil)

    local rejected, rejectionMessage = host:rejectJoin(request.requestId)
    local rejectionEvents = host:drainEvents()
    client:update(0, { localPlayer = motionPlayer(430, 500), inputX = 0, inputY = 0 })
    local clientEvents = client:drainEvents()
    check("multiplayer_session_direct_denial_closes_only_that_link_without_allocating_player",
        rejected and rejectionMessage:find("connection is closed", 1, true)
        and eventNamed(rejectionEvents, "join_rejected")
        and eventNamed(rejectionEvents, "direct_closed") == nil
        and eventNamed(clientEvents, "error")
        and not host.terminal and host.transport ~= nil and host.ready
        and host.players[1] ~= nil and host.players[2] == nil
        and host.peerToId[network.peer] == nil
        and #network:messages("host_to_client", "welcome") == 0
        and #network:messages("host_to_client", "shop_snapshot") == 0
        and not host:approveJoin(request.requestId))

    host:stop("Fresh Direct invitation test")
    client:stop("Fresh Direct invitation test")
    local freshNetwork = fakeNetwork()
    local freshClient = Session.new({ transportFactory = freshNetwork.factory, clock = clock })
    host:startHost({
        name = "Fresh Direct Host", character = "rabbit-worker",
        networkKind = "direct", transportFactory = freshNetwork.factory,
    })
    freshClient:startClient("192.0.2.11:22122", {
        name = "Android Direct Guest", character = "rabbit-worker",
        networkKind = "direct", transportFactory = freshNetwork.factory,
    })
    host:update(0, context)
    freshClient:update(0, { localPlayer = motionPlayer(430, 500), inputX = 0, inputY = 0 })
    host:update(0, context)
    local freshRequest = eventNamed(host:drainEvents(), "join_requested")
    local staleRejected = host:approveJoin(request.requestId) == false
    local freshApproved = freshRequest and host:approveJoin(freshRequest.requestId)
    host:update(0, context)
    freshClient:update(0, { localPlayer = motionPlayer(430, 500), inputX = 0, inputY = 0 })
    check("multiplayer_session_fresh_invite_uses_new_handle_and_approves_atomically",
        freshRequest and freshRequest.requestId > request.requestId
        and staleRejected and freshApproved and snapshots == 1
        and host.players[2] and host.players[2].name == "Android Direct Guest"
        and freshClient.ready)

    local cannotKickHost = host:kickPlayer(1) == false
    local kicked, kickMessage = host:kickPlayer(2)
    local kickEvents = host:drainEvents()
    local leftCount = 0
    for _, event in ipairs(kickEvents) do
        if event.type == "player_left" then leftCount = leftCount + 1 end
    end
    check("multiplayer_session_direct_kick_is_confirmable_host_only_and_link_scoped",
        cannotKickHost and kicked and kickMessage:find("removed", 1, true)
        and leftCount == 1 and eventNamed(kickEvents, "player_kicked")
        and eventNamed(kickEvents, "direct_closed") == nil
        and host.players[2] == nil and host.idToPeer[2] == nil
        and host.peerToId[freshNetwork.peer] == nil
        and not host.terminal and host.transport ~= nil and host.ready
        and #freshNetwork:messages("host_broadcast", "leave") == 0
        and #freshNetwork:messages("host_to_client", "leave") == 0
        and #freshNetwork:messages("host_to_client", "error") == 1)
    freshClient:stop("Kick test complete")
    host:stop("Kick test complete")

    local timeoutNetwork = fakeNetwork()
    local timeoutHost = Session.new({ transportFactory = timeoutNetwork.factory, clock = clock })
    local timeoutClient = Session.new({ transportFactory = timeoutNetwork.factory, clock = clock })
    timeoutHost:startHost({
        name = "Approval Timeout Host", character = "rabbit-worker", networkKind = "direct",
    })
    timeoutClient:startClient("192.0.2.12:22122", {
        name = "Waiting Direct Guest", character = "rabbit-worker", networkKind = "direct",
    })
    timeoutHost:update(0, context)
    timeoutClient:update(0, { localPlayer = motionPlayer(430, 500), inputX = 0, inputY = 0 })
    timeoutHost:update(0, context)
    local timeoutRequest = eventNamed(timeoutHost:drainEvents(), "join_requested")
    options.advanceClock(60.01)
    timeoutHost:update(0, context)
    local timeoutEvents = timeoutHost:drainEvents()
    check("multiplayer_session_direct_approval_timeout_denies_only_that_link",
        timeoutRequest and eventNamed(timeoutEvents, "join_expired")
        and eventNamed(timeoutEvents, "direct_closed") == nil
        and timeoutHost.players[2] == nil and timeoutHost:hudInfo().pendingJoinCount == 0
        and not timeoutHost.terminal and timeoutHost.transport ~= nil and timeoutHost.ready)
    timeoutClient:stop("Approval timeout complete")
    timeoutHost:stop("Approval timeout complete")

    local multiNetwork = captureHostNetwork()
    local multiHost = Session.new({ transportFactory = multiNetwork.factory, clock = clock })
    local multiSnapshots = 0
    local multiContext = {
        localPlayer = motionPlayer(400, 500),
        resolveGuestSpawn = function(hostX, hostY, guestIndex)
            return hostX + guestIndex * 10, hostY
        end,
        getShopSnapshot = function()
            multiSnapshots = multiSnapshots + 1
            return {
                state = { money = 888, inventory = {}, jobs = {} },
                player = { x = 400, y = 500, character = "rabbit-worker" },
            }
        end,
        moveRemote = function() end,
    }
    multiHost:startHost({
        name = "Multi Direct Host",
        character = "rabbit-worker",
        networkKind = "direct",
    })
    multiHost.sessionId = "multi-direct-session"
    multiHost:drainEvents()

    local function queueConnect(peer)
        multiNetwork:queue({ type = "connect", peer = peer })
    end

    local function queueHello(peer, workerNumber)
        local packet = assert(Protocol.encode("hello", {
            clientNonce = "multi-direct-nonce-" .. tostring(workerNumber),
            name = "Direct Worker " .. tostring(workerNumber),
            character = "rabbit-worker",
        }))
        local channel = Protocol.route("hello")
        multiNetwork:queue({
            type = "receive",
            peer = peer,
            data = packet,
            channel = channel,
        })
    end

    for index = 1, 3 do queueConnect(multiNetwork.peers[index]) end
    multiHost:update(0, multiContext)
    local generations = {}
    local generationCount = 0
    for index = 1, 3 do
        local pending = multiHost.pendingPeers[multiNetwork.peers[index]]
        if pending and not generations[pending.generation] then
            generations[pending.generation] = true
            generationCount = generationCount + 1
        end
    end
    check("multiplayer_session_direct_links_receive_distinct_single_use_generations",
        generationCount == 3 and multiHost.nextConnectionGeneration == 3
        and multiHost:hudInfo().playerCount == 1
        and not multiHost.terminal and multiHost.transport ~= nil)

    for index = 1, 3 do queueHello(multiNetwork.peers[index], index + 1) end
    multiHost:update(0, multiContext)
    local requestEvents = multiHost:drainEvents()
    local requestsByName, requestCount = {}, 0
    for _, event in ipairs(requestEvents) do
        if event.type == "join_requested" then
            requestsByName[event.name] = event
            requestCount = requestCount + 1
        end
    end
    local pendingHud = multiHost:hudInfo()
    check("multiplayer_session_direct_three_guests_wait_for_individual_approval_without_snapshot",
        requestCount == 3 and pendingHud.pendingJoinCount == 3
        and pendingHud.playerCount == 1 and multiSnapshots == 0
        and #multiNetwork:messages("host_to_client", "welcome") == 0
        and #multiNetwork:messages("host_to_client", "shop_snapshot") == 0)

    queueHello(multiNetwork.peers[2], 3)
    multiHost:update(0, multiContext)
    local replayEvents = multiHost:drainEvents()
    check("multiplayer_session_direct_generation_emits_only_one_approval_request",
        eventNamed(replayEvents, "join_requested") == nil
        and multiHost:hudInfo().pendingJoinCount == 3
        and multiHost.nextConnectionGeneration == 3 and multiSnapshots == 0)

    local deniedRequest = requestsByName["Direct Worker 2"]
    local denied = deniedRequest and multiHost:rejectJoin(deniedRequest.requestId)
    local deniedEvents = multiHost:drainEvents()
    check("multiplayer_session_direct_multi_guest_denial_is_link_scoped",
        denied and eventNamed(deniedEvents, "join_rejected")
        and eventNamed(deniedEvents, "direct_closed") == nil
        and multiHost.pendingPeers[multiNetwork.peers[1]] == nil
        and multiHost.pendingPeers[multiNetwork.peers[2]] ~= nil
        and multiHost.pendingPeers[multiNetwork.peers[3]] ~= nil
        and multiHost:hudInfo().pendingJoinCount == 2
        and multiHost:hudInfo().playerCount == 1
        and not multiHost.terminal and multiHost.transport ~= nil)

    local approvedSecond = multiHost:approveJoin(
        requestsByName["Direct Worker 3"].requestId)
    local approvedThird = multiHost:approveJoin(
        requestsByName["Direct Worker 4"].requestId)
    multiHost:update(0, multiContext)
    local firstJoinEvents = multiHost:drainEvents()
    local firstJoinCount = 0
    for _, event in ipairs(firstJoinEvents) do
        if event.type == "player_joined" then firstJoinCount = firstJoinCount + 1 end
    end
    check("multiplayer_session_direct_two_approved_guests_join_same_host",
        approvedSecond and approvedThird and firstJoinCount == 2
        and multiHost:hudInfo().playerCount == 3 and multiSnapshots == 2
        and multiHost.peerToId[multiNetwork.peers[2]] ~= nil
        and multiHost.peerToId[multiNetwork.peers[3]] ~= nil
        and #multiNetwork:messages("host_to_client", "welcome") == 2
        and #multiNetwork:messages("host_to_client", "shop_snapshot") == 2
        and not multiHost.terminal and multiHost.transport ~= nil)

    queueConnect(multiNetwork.peers[4])
    multiHost:update(0, multiContext)
    local fourthPending = multiHost.pendingPeers[multiNetwork.peers[4]]
    queueHello(multiNetwork.peers[4], 5)
    multiHost:update(0, multiContext)
    local fourthRequest = eventNamed(multiHost:drainEvents(), "join_requested")
    local fourthPreApprovalSnapshots = multiSnapshots
    local fourthApproved = fourthRequest and multiHost:approveJoin(fourthRequest.requestId)
    multiHost:update(0, multiContext)
    local fourthJoined = eventNamed(multiHost:drainEvents(), "player_joined")
    check("multiplayer_session_direct_fourth_player_joins_with_fresh_connection_generation",
        fourthPending and fourthPending.generation == 4
        and fourthPreApprovalSnapshots == 2
        and fourthApproved and fourthJoined and fourthJoined.playerId ~= 1
        and multiHost:hudInfo().playerCount == Protocol.MAX_PLAYERS
        and multiSnapshots == 3 and not multiHost.terminal and multiHost.transport ~= nil)

    queueConnect(multiNetwork.peers[5])
    multiHost:update(0, multiContext)
    queueHello(multiNetwork.peers[5], 6)
    multiHost:update(0, multiContext)
    local fullEvents = multiHost:drainEvents()
    check("multiplayer_session_direct_fifth_player_is_denied_without_closing_full_host",
        eventNamed(fullEvents, "join_rejected")
        and eventNamed(fullEvents, "join_requested") == nil
        and multiHost.pendingPeers[multiNetwork.peers[5]] == nil
        and multiHost.peerToId[multiNetwork.peers[5]] == nil
        and multiHost:hudInfo().playerCount == Protocol.MAX_PLAYERS
        and multiSnapshots == 3 and not multiHost.terminal and multiHost.transport ~= nil)

    local leaveCountBeforeKick = #multiNetwork:messages("host_to_client", "leave")
    local kickedId = multiHost.peerToId[multiNetwork.peers[2]]
    local kickedMulti = kickedId and multiHost:kickPlayer(kickedId)
    local kickedMultiEvents = multiHost:drainEvents()
    local leaveRecipients = {}
    local leaveMessages = multiNetwork:messages("host_to_client", "leave")
    for index = leaveCountBeforeKick + 1, #leaveMessages do
        leaveRecipients[leaveMessages[index].peer] = true
    end
    check("multiplayer_session_direct_multi_guest_kick_preserves_other_links",
        kickedMulti and eventNamed(kickedMultiEvents, "player_kicked")
        and eventNamed(kickedMultiEvents, "direct_closed") == nil
        and multiHost.peerToId[multiNetwork.peers[2]] == nil
        and multiHost.peerToId[multiNetwork.peers[3]] ~= nil
        and multiHost.peerToId[multiNetwork.peers[4]] ~= nil
        and #leaveMessages - leaveCountBeforeKick == 2
        and not leaveRecipients[multiNetwork.peers[2]]
        and leaveRecipients[multiNetwork.peers[3]]
        and leaveRecipients[multiNetwork.peers[4]]
        and multiHost:hudInfo().playerCount == 3
        and not multiHost.terminal and multiHost.transport ~= nil)

    local disconnectingPlayerId = multiHost.peerToId[multiNetwork.peers[3]]
    multiNetwork:queue({ type = "disconnect", peer = multiNetwork.peers[3] })
    multiHost:update(0, multiContext)
    local disconnectedEvents = multiHost:drainEvents()
    local disconnectedPlayer = eventNamed(disconnectedEvents, "player_left")
    check("multiplayer_session_direct_multi_guest_disconnect_preserves_other_links",
        disconnectedPlayer and disconnectedPlayer.playerId == disconnectingPlayerId
        and disconnectedPlayer.name == "Direct Worker 4"
        and disconnectedPlayer.reason == "Connection lost"
        and eventNamed(disconnectedEvents, "direct_closed") == nil
        and multiHost.peerToId[multiNetwork.peers[3]] == nil
        and multiHost.peerToId[multiNetwork.peers[4]] ~= nil
        and multiHost:hudInfo().playerCount == 2
        and not multiHost.terminal and multiHost.transport ~= nil)

    queueConnect(multiNetwork.peers[6])
    multiHost:update(0, multiContext)
    queueHello(multiNetwork.peers[6], 7)
    multiHost:update(0, multiContext)
    local lastRequest = eventNamed(multiHost:drainEvents(), "join_requested")
    local survivingPlayerId = multiHost.peerToId[multiNetwork.peers[4]]
    options.advanceClock(60.01)
    multiHost:update(0, multiContext)
    local multiTimeoutEvents = multiHost:drainEvents()
    check("multiplayer_session_direct_multi_guest_timeout_preserves_joined_player",
        lastRequest and eventNamed(multiTimeoutEvents, "join_expired")
        and eventNamed(multiTimeoutEvents, "direct_closed") == nil
        and multiHost.pendingPeers[multiNetwork.peers[6]] == nil
        and multiHost.peerToId[multiNetwork.peers[4]] == survivingPlayerId
        and multiHost.players[survivingPlayerId] ~= nil
        and multiHost:hudInfo().playerCount == 2
        and not multiHost.terminal and multiHost.transport ~= nil)
    multiHost:stop("Multi-guest Direct controls complete")
end

function Test.run(_, check)
    runStaleWorkshopGrantRevisionRegression(check)
    runHudExperienceRegression(check)
    local now = 100
    local clock = function() return now end
    local network = fakeNetwork()
    local host = Session.new({ transportFactory = network.factory, clock = clock })
    local client = Session.new({ transportFactory = network.factory, clock = clock })
    local hostPlayer = motionPlayer(400, 500)
    local guestPlayer = motionPlayer(428, 500)
    local moveCalls = {}
    local interactionCalls = {}
    local interactionMutations = 0
    local interactionX, interactionY, interactionRadius = 300, 285, 72
    local hostContext = {
        localPlayer = hostPlayer,
        resolveGuestSpawn = function()
            return 450, 510
        end,
        getShopSnapshot = function()
            return {
                state = {
                    money = 2345,
                    screen = "world",
                    inventory = { paper = 2500, prints = 12 },
                    jobs = { active = {}, completed = {} },
                },
                player = { x = 400, y = 500, character = "rabbit-worker" },
            }
        end,
        moveRemote = function(player, dt, inputX, inputY)
            moveCalls[#moveCalls + 1] = {
                id = player.id, dt = dt, inputX = inputX, inputY = inputY,
            }
            player.x = player.x + inputX * 100 * dt
            player.y = player.y + inputY * 100 * dt
            player.velocityX = inputX * 100
            player.velocityY = inputY * 100
            player.intentX, player.intentY = inputX, inputY
            player.moving = inputX ~= 0 or inputY ~= 0
            player.animationDistance = player.animationDistance
                + math.sqrt((inputX * 100 * dt) ^ 2 + (inputY * 100 * dt) ^ 2)
        end,
        performInteraction = function(player, targetKind, desiredState)
            interactionCalls[#interactionCalls + 1] = {
                player = player, x = player.x, y = player.y, targetKind = targetKind,
                desiredState = desiredState,
            }
            local dx, dy = player.x - interactionX, player.y - interactionY
            if dx * dx + dy * dy > interactionRadius * interactionRadius then
                return false, "out_of_range", "Move closer to the loading-bay wall switch."
            end
            interactionMutations = interactionMutations + 1
            return true, "accepted", "Opening the loading bay door..."
        end,
    }
    local clientContext = {
        localPlayer = guestPlayer,
        inputX = 0.75,
        inputY = -0.25,
    }
    local addressOptions = { socket = { dns = {
        gethostname = function() return "picture-shop-host" end,
        getaddrinfo = function() return { { addr = "192.168.1.50" } } end,
    } } }

    local hostStarted = host:startHost({
        name = "PC Host",
        character = "rabbit-worker",
        x = hostPlayer.x,
        y = hostPlayer.y,
        addressOptions = addressOptions,
    })
    host.sessionId = "session-test"
    local clientStarted = client:startClient("192.168.1.50:22122", {
        name = "Phone Guest",
        character = "rabbit-worker",
    })
    client.clientNonce = "nonce-test"
    check("multiplayer_session_fake_pair_starts_without_real_socket",
        hostStarted and clientStarted and host:isHost() and client:isClient()
        and network.hostOptions.maxGuests == 3 and network.hostOptions.channels == 3
        and network.clientOptions.channels == 3
        and network.clientEndpoint == "192.168.1.50:22122")

    client:update(0, clientContext)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local hostEvents = host:drainEvents()
    local clientEvents = client:drainEvents()
    local joined = eventNamed(hostEvents, "player_joined")
    local ready = eventNamed(clientEvents, "ready")
    local hello = network:messages("client_to_host", "hello")[1]
    local welcome = network:messages("host_to_client", "welcome")[1]
    local shopSnapshot = network:messages("host_to_client", "shop_snapshot")[1]
    check("multiplayer_session_hello_welcome_and_shop_snapshot_make_guest_ready",
        hello and hello.channel == Protocol.CHANNEL_CONTROL and hello.reliable
        and welcome and welcome.channel == Protocol.CHANNEL_CONTROL and welcome.reliable
        and shopSnapshot and shopSnapshot.channel == Protocol.CHANNEL_DURABLE and shopSnapshot.reliable
        and joined and joined.playerId == 2 and joined.name == "Phone Guest"
        and ready and ready.playerId == 2 and ready.state.money == 2345
        and ready.revision == 0 and client.lastShopRevision == 0
        and ready.hostPlayer.x == 400 and ready.spawn.x == 450 and ready.spawn.y == 510
        and client.ready and client.sessionId == "session-test")

    check("multiplayer_session_assigns_numeric_guest_id_and_shared_roster",
        host.localId == 1 and client.localId == 2
        and type(host.localId) == "number" and type(client.localId) == "number"
        and host.players[1].name == "PC Host" and host.players[2].name == "Phone Guest"
        and client.players[1].name == "PC Host" and client.players[2].name == "Phone Guest"
        and host.peerToId[network.peer] == 2 and host.idToPeer[2] == network.peer)

    moveCalls = {}
    client:update(0.05, clientContext)
    host:update(0.05, hostContext)
    local authoritativeGuest = host.players[2]
    local input = network:messages("client_to_host", "input")[1]
    check("multiplayer_session_host_accepts_guest_input_authoritatively",
        input and input.channel == Protocol.CHANNEL_STATE and not input.reliable
        and authoritativeGuest and authoritativeGuest.inputSequence == 1
        and authoritativeGuest.inputX == 0.75 and authoritativeGuest.inputY == -0.25
        and #moveCalls == 1 and moveCalls[1].id == 2
        and math.abs(authoritativeGuest.x - 453.75) < 0.0001
        and math.abs(authoritativeGuest.y - 508.75) < 0.0001,
        string.format("input=%s channel=%s reliable=%s seq=%s axes=%s,%s calls=%d pos=%s,%s",
            tostring(input and input.kind), tostring(input and input.channel),
            tostring(input and input.reliable),
            tostring(authoritativeGuest and authoritativeGuest.inputSequence),
            tostring(authoritativeGuest and authoritativeGuest.inputX),
            tostring(authoritativeGuest and authoritativeGuest.inputY),
            #moveCalls, tostring(authoritativeGuest and authoritativeGuest.x),
            tostring(authoritativeGuest and authoritativeGuest.y)))

    host:update(0.04, hostContext)
    client:update(0, clientContext)
    local authoritativeX, authoritativeY = host.players[2].x, host.players[2].y
    local snapshots = network:messages("host_to_client", "snapshot")
    local guestSnapshot, sharedSnapshotTick
    local snapshotShardsValid = #snapshots == 2
    for _, message in ipairs(snapshots) do
        local payload = decodedPayload(message)
        snapshotShardsValid = snapshotShardsValid and payload ~= nil
            and #payload.players == 1
            and #message.payload <= Protocol.MAX_PACKET_BYTES
        if payload then
            sharedSnapshotTick = sharedSnapshotTick or payload.serverTick
            snapshotShardsValid = snapshotShardsValid
                and payload.serverTick == sharedSnapshotTick
            if payload.players[1].id == 2 then guestSnapshot = payload end
        end
    end
    check("multiplayer_session_host_snapshot_returns_guest_motion_to_client",
        snapshotShardsValid and guestSnapshot
        and snapshots[1].channel == Protocol.CHANNEL_STATE
        and not snapshots[1].reliable and host.serverTick == 1 and client.lastServerTick == 1
        and client.localTarget and client.localTarget.id == 2
        and math.abs(client.localTarget.x - authoritativeX) < 0.0001
        and math.abs(client.localTarget.y - authoritativeY) < 0.0001)

    runFourDeviceShardingRegression(check, clock, addressOptions)

    local staleInput = Protocol.encode("input", {
        sessionId = host.sessionId,
        sequence = 1,
        moveX = -1,
        moveY = 1,
    })
    network:sendRawToHost(staleInput)
    host:update(0, hostContext)
    local wrongSessionInput = Protocol.encode("input", {
        sessionId = "spoofed-session",
        sequence = 99,
        moveX = -1,
        moveY = 1,
    })
    network:sendRawToHost(wrongSessionInput)
    host:update(0, hostContext)
    check("multiplayer_session_stale_and_spoofed_inputs_are_ignored",
        host.players[2].inputSequence == 1
        and host.players[2].inputX == 0.75 and host.players[2].inputY == -0.25)

    -- A guest USE request carries no coordinates. The callback must receive
    -- the peer-derived authoritative host player even when client prediction
    -- places the phone somewhere completely different.
    host.players[2].x, host.players[2].y = interactionX, interactionY
    guestPlayer.x, guestPlayer.y = 900, 620
    local requestedInteraction = client:requestInteraction("loadingBayDoor", "open")
    local firstInteractionRequest = network:messages("client_to_host", "interaction_request")[1]
    local firstWireRequest = decodedPayload(firstInteractionRequest)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local firstInteractionEvents = client:drainEvents()
    local firstInteractionResult = eventNamed(firstInteractionEvents, "interaction_result")
    local interactionResults = network:messages("host_to_client", "interaction_result")
    local firstWireResult = decodedPayload(interactionResults[1])
    check("multiplayer_session_guest_use_executes_at_authoritative_peer_position",
        requestedInteraction and firstInteractionRequest
        and firstInteractionRequest.channel == Protocol.CHANNEL_CONTROL
        and firstInteractionRequest.reliable
        and firstWireRequest and firstWireRequest.desiredState == "open"
        and #interactionCalls == 1
        and interactionCalls[1].player == host.players[2]
        and interactionCalls[1].x == interactionX and interactionCalls[1].y == interactionY
        and interactionCalls[1].x ~= guestPlayer.x and interactionCalls[1].y ~= guestPlayer.y
        and interactionCalls[1].targetKind == "loadingBayDoor"
        and interactionCalls[1].desiredState == "open"
        and interactionMutations == 1
        and firstInteractionResult and firstInteractionResult.accepted
        and firstInteractionResult.code == "accepted"
        and firstWireResult and firstWireResult.requestId == 1
        and interactionResults[1].channel == Protocol.CHANNEL_CONTROL
        and interactionResults[1].reliable
        and #network:messages("host_broadcast", "interaction_result") == 0)

    -- Reliable transport should already suppress duplicates, but the command
    -- itself is also idempotent: replay the exact packet and require the host
    -- to replay its cached result without invoking the world callback again.
    network:sendRawToHost(firstInteractionRequest.payload,
        Protocol.CHANNEL_CONTROL, true)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local duplicateEvents = client:drainEvents()
    interactionResults = network:messages("host_to_client", "interaction_result")
    local duplicateWireResult = decodedPayload(interactionResults[#interactionResults])
    check("multiplayer_session_duplicate_use_replays_result_without_reexecution",
        #interactionCalls == 1 and interactionMutations == 1
        and #interactionResults == 2
        and duplicateWireResult and firstWireResult
        and duplicateWireResult.requestId == firstWireResult.requestId
        and duplicateWireResult.accepted == firstWireResult.accepted
        and duplicateWireResult.code == firstWireResult.code
        and eventNamed(duplicateEvents, "interaction_result") == nil)

    -- A new request inside the host cooldown consumes its id and returns a
    -- stable rejection without entering the world callback.
    local rateRequest = client:requestInteraction("loadingBayDoor", "open")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local rateResult = eventNamed(client:drainEvents(), "interaction_result")
    check("multiplayer_session_unique_use_spam_is_rate_limited",
        rateRequest and rateResult and not rateResult.accepted
        and rateResult.requestId == 2 and rateResult.code == "rate_limited"
        and #interactionCalls == 1 and interactionMutations == 1
        and host.players[2].lastInteractionRequestId == 2)

    -- The phone now predicts itself at the switch while the host's player is
    -- far away. Only the latter is passed to performInteraction.
    now = now + 0.21
    host.players[2].x, host.players[2].y = 700, 600
    guestPlayer.x, guestPlayer.y = interactionX, interactionY
    local outOfRangeRequest = client:requestInteraction("loadingBayDoor", "open")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local outOfRangeResult = eventNamed(client:drainEvents(), "interaction_result")
    check("multiplayer_session_out_of_range_use_uses_host_position",
        outOfRangeRequest and outOfRangeResult and not outOfRangeResult.accepted
        and outOfRangeResult.requestId == 3 and outOfRangeResult.code == "out_of_range"
        and #interactionCalls == 2
        and interactionCalls[2].player == host.players[2]
        and interactionCalls[2].x == 700 and interactionCalls[2].y == 600
        and interactionCalls[2].x ~= guestPlayer.x and interactionCalls[2].y ~= guestPlayer.y
        and interactionMutations == 1)

    local staleInteractionPacket = Protocol.encode("interaction_request", {
        sessionId = host.sessionId, requestId = 2, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    network:sendRawToHost(staleInteractionPacket, Protocol.CHANNEL_CONTROL, true)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local staleInteractionEvents = client:drainEvents()
    interactionResults = network:messages("host_to_client", "interaction_result")
    local staleWireResult = decodedPayload(interactionResults[#interactionResults])
    check("multiplayer_session_stale_use_is_rejected_without_reexecution",
        staleWireResult and staleWireResult.requestId == 2
        and not staleWireResult.accepted and staleWireResult.code == "stale_request"
        and host.players[2].lastInteractionRequestId == 3
        and #interactionCalls == 2 and interactionMutations == 1
        and eventNamed(staleInteractionEvents, "interaction_result") == nil)

    local resultCountBeforeWrongSession = #interactionResults
    local wrongSessionInteraction = Protocol.encode("interaction_request", {
        sessionId = "spoofed-session", requestId = 4, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    network:sendRawToHost(wrongSessionInteraction, Protocol.CHANNEL_CONTROL, true)
    host:update(0, hostContext)
    check("multiplayer_session_wrong_session_use_is_ignored_without_consuming_id",
        #network:messages("host_to_client", "interaction_result")
            == resultCountBeforeWrongSession
        and host.players[2].lastInteractionRequestId == 3
        and #interactionCalls == 2 and interactionMutations == 1)

    now = now + 0.21
    host.players[2].x, host.players[2].y = interactionX, interactionY
    guestPlayer.x, guestPlayer.y = 900, 620
    local validAfterSpoof = client:requestInteraction("loadingBayDoor", "open")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local validAfterSpoofResult = eventNamed(client:drainEvents(), "interaction_result")
    check("multiplayer_session_valid_use_after_spoof_keeps_monotonic_sequence",
        validAfterSpoof and validAfterSpoofResult and validAfterSpoofResult.accepted
        and validAfterSpoofResult.requestId == 4
        and host.players[2].lastInteractionRequestId == 4
        and #interactionCalls == 3 and interactionMutations == 2)

    local duplicateAcceptedResult = Protocol.encode("interaction_result", {
        sessionId = host.sessionId, requestId = 4, targetKind = "loadingBayDoor",
        accepted = true, code = "accepted", message = "Opening the loading bay door...",
    })
    local wrongSessionResult = Protocol.encode("interaction_result", {
        sessionId = "spoofed-session", requestId = 5, targetKind = "loadingBayDoor",
        accepted = true, code = "accepted", message = "Opening the loading bay door...",
    })
    now = now + 0.21
    local pendingFifthRequest = client:requestInteraction("loadingBayDoor", "open")
    network.host:send(network.peer, duplicateAcceptedResult,
        Protocol.CHANNEL_CONTROL, true)
    network.host:send(network.peer, wrongSessionResult,
        Protocol.CHANNEL_CONTROL, true)
    client:update(0, clientContext)
    local ignoredResultEvents = client:drainEvents()
    check("multiplayer_session_guest_ignores_stale_and_wrong_session_results",
        pendingFifthRequest
        and eventNamed(ignoredResultEvents, "interaction_result") == nil
        and client.pendingInteraction and client.pendingInteraction.requestId == 5)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local fifthResult = eventNamed(client:drainEvents(), "interaction_result")
    check("multiplayer_session_matching_result_clears_only_its_pending_request",
        fifthResult and fifthResult.requestId == 5 and fifthResult.accepted
        and client.pendingInteraction == nil
        and host.players[2].lastInteractionRequestId == 5
        and #interactionCalls == 4 and interactionMutations == 3)

    local malformedInteraction = Codec.encode({
        version = Protocol.VERSION,
        type = "interaction_request",
        payload = {
            sessionId = host.sessionId, requestId = 5, targetKind = "loadingBayDoor",
            desiredState = "open", playerId = 2, x = interactionX, y = interactionY,
        },
    })
    now = now + 1.01
    local errorsBeforeSpoof = #network:messages("host_to_client", "error")
    network:sendRawToHost(malformedInteraction, Protocol.CHANNEL_CONTROL, true)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local malformedInteractionError = eventNamed(client:drainEvents(), "error")
    check("multiplayer_session_position_and_identity_spoof_returns_bad_packet",
        malformedInteractionError and malformedInteractionError.code == "bad_packet"
        and #network:messages("host_to_client", "error") == errorsBeforeSpoof + 1
        and host.players[2].lastInteractionRequestId == 5
        and #interactionCalls == 4 and interactionMutations == 3)

    now = now + 1.01
    local errorCountBeforeInvalid = #network:messages("host_to_client", "error")
    network:sendRawToHost("this-is-not-a-protocol-packet")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local invalidEvents = client:drainEvents()
    local invalidError = eventNamed(invalidEvents, "error")
    local errorPackets = network:messages("host_to_client", "error")
    check("multiplayer_session_invalid_packet_returns_bad_packet_error",
        invalidError and invalidError.code == "bad_packet"
        and #errorPackets == errorCountBeforeInvalid + 1
        and #errorPackets[#errorPackets].payload <= Protocol.MAX_PACKET_BYTES
        and errorPackets[#errorPackets].channel == Protocol.CHANNEL_CONTROL
        and errorPackets[#errorPackets].reliable)

    now = now + 1.01
    local wrongChannelCount = #errorPackets
    local wrongChannelInteraction = Protocol.encode("interaction_request", {
        sessionId = host.sessionId, requestId = 6, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    network:sendRawToHost(wrongChannelInteraction, Protocol.CHANNEL_STATE, true)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local wrongChannelError = eventNamed(client:drainEvents(), "error")
    check("multiplayer_session_guest_command_on_wrong_channel_is_rejected_before_execution",
        wrongChannelError and wrongChannelError.code == "bad_packet"
        and #network:messages("host_to_client", "error") == wrongChannelCount + 1
        and host.players[2].lastInteractionRequestId == 5
        and #interactionCalls == 4 and interactionMutations == 3)

    now = now + 1.01
    local oversizedCount = #network:messages("host_to_client", "error")
    network:sendRawToHost(string.rep("x", Protocol.MAX_PACKET_BYTES + 1),
        Protocol.CHANNEL_DURABLE, true)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local oversizedGuestError = eventNamed(client:drainEvents(), "error")
    check("multiplayer_session_guest_packets_are_capped_before_large_codec_decode",
        Protocol.MAX_PACKET_BYTES == 1200
        and oversizedGuestError and oversizedGuestError.code == "bad_packet"
        and #network:messages("host_to_client", "error") == oversizedCount + 1
        and host.players[2].lastInteractionRequestId == 5
        and #interactionCalls == 4 and interactionMutations == 3)

    local workshopRevision, workshopLease, workshopResource, workshopMutation = 0, nil, nil, 0
    local authoritativeCutter
    local workshopPallets = {}
    local workshopCalls, workshopTouches = {}, 0
    hostContext.touchWorkshop = function(player)
        if player and player.id == 2 then workshopTouches = workshopTouches + 1 end
    end
    hostContext.performWorkshop = function(player, operation, payload)
        workshopCalls[#workshopCalls + 1] = {
            player = player, operation = operation, payload = payload,
        }
        if operation == "workshop_acquire" then
            workshopRevision = workshopRevision + 1
            workshopResource = payload.resourceId
            local leases = {
                office_computer = "lease-office-test",
                skid_wrapper = "lease-wrapper-test",
                pallet_jack = "lease-jack-test",
                cutter = "lease-cutter-test",
                windmill = "lease-windmill-test",
            }
            workshopLease = leases[workshopResource] or "lease-workshop-test"
            local data = {}
            if workshopResource == "skid_wrapper" then
                data = {
                    step = "idle", progress = 0, cycleTime = 3,
                    plasticWrapRolls = 2, plasticWrapUses = 8,
                    pallets = workshopPallets,
                }
            elseif workshopResource == "cutter" then
                data = authoritativeCutter or cutterState()
            elseif workshopResource == "windmill" then
                data = hostContext.windmillTestView or windmillState()
            end
            return {
                accepted = true, code = "acquired", message = "Workshop console connected.",
                revision = workshopRevision, leaseId = workshopLease, data = data,
            }
        elseif operation == "workshop_command" then
            if payload.leaseId ~= workshopLease then
                return { accepted = false, code = "lease_not_found", message = "Lease missing.",
                    revision = workshopRevision }
            end
            workshopRevision, workshopMutation = workshopRevision + 1, workshopMutation + 1
            if workshopResource == "windmill" then
                local windmill = hostContext.windmillTestView or windmillState()
                hostContext.windmillTestView = windmill
                windmill.runtimeRevision = windmill.runtimeRevision + 1
                if payload.action == "load_pallet" then
                    windmill.jobId = "JOB-PRESS"
                    windmill.palletId = payload.palletId
                    windmill.colorIndex = 1
                    windmill.colorCount = 4
                    windmill.candidates = {}
                elseif payload.action == "begin_setup" then
                    windmill.status = "setup"
                    windmill.setupTask = payload.setupTask
                elseif payload.action == "setup_action" then
                    windmill.setupPermille[1] = 250
                elseif payload.action == "toggle_motor" then
                    windmill.motor = not windmill.motor
                elseif payload.action == "speed_up" then
                    windmill.speed = windmill.speed + 100
                elseif payload.action == "emergency_stop" then
                    windmill.status = "stopped"
                    windmill.motor = false
                    windmill.feeder = false
                    windmill.impression = false
                    windmill.emergency = true
                end
            end
            local data = workshopResource == "cutter"
                and (authoritativeCutter or cutterState())
                or workshopResource == "windmill"
                    and (hostContext.windmillTestView or windmillState()) or {}
            return {
                accepted = true, code = "pickup_requested", message = "Pickup requested.",
                revision = workshopRevision, data = data,
            }
        elseif operation == "workshop_release" then
            workshopRevision, workshopLease, workshopResource = workshopRevision + 1, nil, nil
            return { accepted = true, code = "released", message = "Released.",
                revision = workshopRevision }
        end
    end
    hostContext.getWorkshopSnapshot = function()
        return {
            resources = {
                { resourceId = "reception_customer", revision = 0, occupied = false },
                { resourceId = "vendor", revision = 0, occupied = false },
                { resourceId = "truck", revision = 0, occupied = false },
                { resourceId = "work_phone", revision = 0, occupied = false },
                { resourceId = "warehouse", revision = 0, occupied = false },
                { resourceId = "office_computer", revision = workshopRevision,
                    occupied = workshopLease ~= nil and workshopResource == "office_computer",
                    ownerPlayerId = workshopLease and workshopResource == "office_computer"
                        and 2 or nil },
                { resourceId = "skid_wrapper", revision = workshopRevision,
                    occupied = workshopLease ~= nil and workshopResource == "skid_wrapper",
                    ownerPlayerId = workshopLease and workshopResource == "skid_wrapper"
                        and 2 or nil },
                { resourceId = "pallet_jack", revision = workshopRevision,
                    occupied = workshopLease ~= nil and workshopResource == "pallet_jack",
                    ownerPlayerId = workshopLease and workshopResource == "pallet_jack"
                        and 2 or nil },
                { resourceId = "cutter", revision = workshopRevision,
                    occupied = workshopLease ~= nil and workshopResource == "cutter",
                    ownerPlayerId = workshopLease and workshopResource == "cutter"
                        and 2 or nil },
                { resourceId = "windmill", revision = workshopRevision,
                    occupied = workshopLease ~= nil and workshopResource == "windmill",
                    ownerPlayerId = workshopLease and workshopResource == "windmill"
                        and 2 or nil },
            },
            wrapper = {
                step = "idle", progress = 0, cycleTime = 3,
                pallets = workshopPallets,
            },
        }
    end

    local workshopRequested = client:requestWorkshopAcquire("office_computer")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local workshopGrant = eventNamed(client:drainEvents(), "workshop_grant")
    local acquireWire = decodedPayload(
        network:messages("client_to_host", "workshop_acquire")[1])
    local grantMessage = network:messages("host_to_client", "workshop_grant")[1]
    check("multiplayer_session_worker_acquires_host_owned_office_without_spoofable_identity",
        workshopRequested and workshopGrant and workshopGrant.granted
        and workshopGrant.leaseId == workshopLease
        and acquireWire and acquireWire.resourceId == "office_computer"
        and acquireWire.expectedRevision == 0
        and acquireWire.playerId == nil and acquireWire.x == nil and acquireWire.y == nil
        and workshopCalls[1] and workshopCalls[1].player == host.players[2]
        and grantMessage and grantMessage.channel == Protocol.CHANNEL_CONTROL
        and grantMessage.reliable and client:workshopInfo().revision == 1)

    local workshopCommanded = client:requestWorkshopCommand(
        "request_pickup", { jobId = "JOB-0001" })
    host:update(0, hostContext)
    client:update(0, clientContext)
    local workshopResult = eventNamed(client:drainEvents(), "workshop_result")
    local commandMessage = network:messages("client_to_host", "workshop_command")[1]
    local commandWire = decodedPayload(commandMessage)
    check("multiplayer_session_worker_command_is_semantic_reliable_and_updates_revision_once",
        workshopCommanded and workshopResult and workshopResult.accepted
        and workshopResult.action == "request_pickup" and workshopMutation == 1
        and commandWire and commandWire.jobId == "JOB-0001"
        and commandWire.expectedRevision == 1 and commandWire.state == nil
        and commandMessage.channel == Protocol.CHANNEL_CONTROL and commandMessage.reliable
        and client:workshopInfo().revision == 2 and workshopTouches > 0)

    local workshopReleased = client:releaseWorkshop("closed")
    host:update(0, hostContext)
    check("multiplayer_session_worker_release_clears_client_and_host_resource_ownership",
        workshopReleased and client:workshopInfo() == nil and workshopLease == nil
        and workshopRevision == 3 and workshopCalls[#workshopCalls].operation == "workshop_release")

    workshopPallets = {}
    local wrapperRequested = client:requestWorkshopAcquire("skid_wrapper")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local wrapperGrant = eventNamed(client:drainEvents(), "workshop_grant")
    host:update(0.09, hostContext)
    client:update(0, clientContext)
    local emptyWrapperSnapshot = eventNamed(client:drainEvents(), "workshop_snapshot")

    workshopPallets = {
        { palletId = "JOB-LIVE-P01", jobLabel = "Live Client · JOB-LIVE",
            packaging = "boxed", distance = 28 },
    }
    host:update(0.09, hostContext)
    client:update(0, clientContext)
    local liveWrapperSnapshot = eventNamed(client:drainEvents(), "workshop_snapshot")
    local workshopPackets = network:messages("host_to_client", "workshop_snapshot")
    local liveWorkshopWire = decodedPayload(workshopPackets[#workshopPackets])
    check("multiplayer_session_open_wrapper_receives_empty_to_eligible_live_pallet_update",
        wrapperRequested and wrapperGrant and wrapperGrant.granted
        and wrapperGrant.resourceId == "skid_wrapper"
        and wrapperGrant.view and #wrapperGrant.view.pallets == 0
        and emptyWrapperSnapshot and #emptyWrapperSnapshot.wrapper.pallets == 0
        and liveWrapperSnapshot and #liveWrapperSnapshot.wrapper.pallets == 1
        and liveWrapperSnapshot.wrapper.pallets[1].palletId == "JOB-LIVE-P01"
        and liveWrapperSnapshot.wrapper.pallets[1].packaging == "boxed"
        and liveWorkshopWire and #liveWorkshopWire.wrapper.pallets == 1
        and #workshopPackets[#workshopPackets].payload <= Protocol.MAX_PACKET_BYTES
        and client:workshopInfo() and client:workshopInfo().resourceId == "skid_wrapper")
    client:releaseWorkshop("closed")
    host:update(0, hostContext)

    local jackRequested = client:requestWorkshopAcquire("pallet_jack")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local jackGrant = eventNamed(client:drainEvents(), "workshop_grant")
    local jackInfo = client:workshopInfo()
    check("multiplayer_session_worker_acquires_host_owned_pallet_jack_control",
        jackRequested and jackGrant and jackGrant.granted
        and jackGrant.resourceId == "pallet_jack"
        and jackGrant.leaseId == "lease-jack-test"
        and jackGrant.view and next(jackGrant.view) == nil
        and jackInfo and jackInfo.resourceId == "pallet_jack"
        and jackInfo.leaseId == "lease-jack-test")

    local commandsBeforeJack = #network:messages("client_to_host", "workshop_command")
    local liftRequested = client:requestWorkshopCommand(
        "lift_pallet", { palletId = "JOB-LIFT-P01" })
    host:update(0, hostContext)
    client:update(0, clientContext)
    local liftResult = eventNamed(client:drainEvents(), "workshop_result")
    local commandPackets = network:messages("client_to_host", "workshop_command")
    local liftPacket = commandPackets[commandsBeforeJack + 1]
    local liftWire = decodedPayload(liftPacket)
    local liftRevision = liftResult and liftResult.revision

    local lowerRequested = client:requestWorkshopCommand(
        "lower_pallet", { palletId = "JOB-LIFT-P01" })
    host:update(0, hostContext)
    client:update(0, clientContext)
    local lowerResult = eventNamed(client:drainEvents(), "workshop_result")
    commandPackets = network:messages("client_to_host", "workshop_command")
    local lowerPacket = commandPackets[commandsBeforeJack + 2]
    local lowerWire = decodedPayload(lowerPacket)
    local lowerRevision = lowerResult and lowerResult.revision

    -- Even if a caller accidentally supplies an argument, the session emits
    -- the closed park command shape: no coordinates and no pallet identity.
    local parkRequested = client:requestWorkshopCommand(
        "park_jack", { palletId = "MUST-NOT-REACH-HOST", x = 999, y = 999 })
    host:update(0, hostContext)
    client:update(0, clientContext)
    local parkResult = eventNamed(client:drainEvents(), "workshop_result")
    commandPackets = network:messages("client_to_host", "workshop_command")
    local parkPacket = commandPackets[commandsBeforeJack + 3]
    local parkWire = decodedPayload(parkPacket)

    local jackCalls = {
        workshopCalls[#workshopCalls - 2],
        workshopCalls[#workshopCalls - 1],
        workshopCalls[#workshopCalls],
    }
    check("multiplayer_session_pallet_jack_commands_serialize_exact_lift_lower_and_park_intent",
        liftRequested and lowerRequested and parkRequested
        and liftResult and liftResult.accepted and liftResult.action == "lift_pallet"
        and lowerResult and lowerResult.accepted and lowerResult.action == "lower_pallet"
        and parkResult and parkResult.accepted and parkResult.action == "park_jack"
        and liftPacket and liftPacket.channel == Protocol.CHANNEL_CONTROL and liftPacket.reliable
        and lowerPacket and lowerPacket.channel == Protocol.CHANNEL_CONTROL and lowerPacket.reliable
        and parkPacket and parkPacket.channel == Protocol.CHANNEL_CONTROL and parkPacket.reliable
        and liftWire and liftWire.resourceId == "pallet_jack"
        and liftWire.leaseId == "lease-jack-test"
        and liftWire.action == "lift_pallet" and liftWire.palletId == "JOB-LIFT-P01"
        and lowerWire and lowerWire.resourceId == "pallet_jack"
        and lowerWire.leaseId == "lease-jack-test"
        and lowerWire.action == "lower_pallet" and lowerWire.palletId == "JOB-LIFT-P01"
        and lowerWire.expectedRevision == liftRevision
        and parkWire and parkWire.resourceId == "pallet_jack"
        and parkWire.leaseId == "lease-jack-test"
        and parkWire.action == "park_jack" and parkWire.palletId == nil
        and parkWire.x == nil and parkWire.y == nil
        and parkWire.expectedRevision == lowerRevision
        and liftWire.commandId < lowerWire.commandId
        and lowerWire.commandId < parkWire.commandId
        and jackCalls[1] and jackCalls[1].payload.action == "lift_pallet"
        and jackCalls[1].payload.palletId == "JOB-LIFT-P01"
        and jackCalls[2] and jackCalls[2].payload.action == "lower_pallet"
        and jackCalls[2].payload.palletId == "JOB-LIFT-P01"
        and jackCalls[3] and jackCalls[3].payload.action == "park_jack"
        and jackCalls[3].payload.palletId == nil)

    local jackReleased = client:releaseWorkshop("closed")
    host:update(0, hostContext)
    check("multiplayer_session_worker_releases_pallet_jack_after_parking",
        jackReleased and client:workshopInfo() == nil
        and workshopLease == nil and workshopResource == nil)

    authoritativeCutter = cutterState()
    hostContext.getCutterSnapshot = function()
        return {
            resourceRevision = workshopRevision,
            view = authoritativeCutter,
        }
    end
    local cutterRequested = client:requestWorkshopAcquire("cutter")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local cutterGrant = eventNamed(client:drainEvents(), "workshop_grant")
    local cutterGrantWireMessages = network:messages("host_to_client", "workshop_grant")
    local cutterGrantWire = decodedPayload(cutterGrantWireMessages[#cutterGrantWireMessages])

    runCutterSafetyOrderingRegression({
        client = client,
        host = host,
        network = network,
        hostContext = hostContext,
        clientContext = clientContext,
        view = authoritativeCutter,
        workshopCalls = workshopCalls,
        revision = function() return workshopRevision end,
        check = check,
    })

    local cutterWires = {}
    local function sendCutterCommand(action, arguments)
        local before = #network:messages("client_to_host", "workshop_command")
        local requested = client:requestWorkshopCommand(action, arguments)
        host:update(0, hostContext)
        client:update(0, clientContext)
        local result = eventNamed(client:drainEvents(), "workshop_result")
        local packets = network:messages("client_to_host", "workshop_command")
        cutterWires[#cutterWires + 1] = decodedPayload(packets[before + 1])
        return requested and result and result.accepted
    end

    local cutterCommandsAccepted = sendCutterCommand(
        "load_pallet", { palletId = "JOB-CUT-P01" })
        and sendCutterCommand("select_program", { programIndex = 4 })
        and sendCutterCommand("set_gauge", { gaugeCentiInch = 625 })
        and sendCutterCommand("set_clamp", { clamp = true })
        and sendCutterCommand("set_barrier", { barrierClear = false })
        and sendCutterCommand("guarded_cut", {
            palletId = "MUST-NOT-REACH-HOST", clamp = true,
        })

    host:update(0.09, hostContext)
    client:update(0, clientContext)
    local cutterStateEvent = eventNamed(client:drainEvents(), "cutter_state")
    local cutterPackets = network:messages("host_to_client", "cutter_snapshot")
    local latestCutterWire = decodedPayload(cutterPackets[#cutterPackets])
    local cutterTick = client.lastCutterTick
    local staleCutterPacket = Protocol.encode("cutter_snapshot", {
        sessionId = host.sessionId,
        serverTick = cutterTick,
        resourceRevision = workshopRevision,
        view = authoritativeCutter,
    })
    network.host:send(network.peer, staleCutterPacket, Protocol.CHANNEL_STATE, false)
    client:update(0, clientContext)
    local staleCutterEvent = eventNamed(client:drainEvents(), "cutter_state")

    check("multiplayer_session_cutter_commands_and_live_state_use_closed_revisioned_shapes",
        cutterRequested and cutterGrant and cutterGrant.granted
        and cutterGrant.resourceId == "cutter" and cutterGrant.view
        and #cutterGrant.view.candidates == 1
        and cutterGrantWire and cutterGrantWire.view
        and Codec.isArray(cutterGrantWire.view.memoryCentiInch)
        and Codec.isArray(cutterGrantWire.view.candidates)
        and cutterCommandsAccepted and #cutterWires == 6
        and cutterWires[1].palletId == "JOB-CUT-P01"
        and cutterWires[1].programIndex == nil
        and cutterWires[2].programIndex == 4 and cutterWires[2].palletId == nil
        and cutterWires[3].gaugeCentiInch == 625
        and cutterWires[4].clamp == true
        and cutterWires[5].barrierClear == false
        and cutterWires[6].palletId == nil and cutterWires[6].clamp == nil
        and cutterStateEvent and cutterStateEvent.serverTick == cutterTick
        and cutterStateEvent.resourceRevision == workshopRevision
        and cutterStateEvent.view.runtimeRevision == 1
        and latestCutterWire and latestCutterWire.serverTick == cutterTick
        and cutterPackets[#cutterPackets].channel == Protocol.CHANNEL_STATE
        and not cutterPackets[#cutterPackets].reliable
        and #cutterPackets[#cutterPackets].payload <= Protocol.MAX_PACKET_BYTES
        and staleCutterEvent == nil and client.lastCutterTick == cutterTick)

    local cutterReleased = client:releaseWorkshop("closed")
    host:update(0, hostContext)
    check("multiplayer_session_worker_releases_cutter_console",
        cutterReleased and client:workshopInfo() == nil
        and workshopLease == nil and workshopResource == nil)

    hostContext.windmillMutationBeforeTimeout = runWindmillSessionRegression({
        client = client,
        host = host,
        network = network,
        hostContext = hostContext,
        clientContext = clientContext,
        workshopCalls = workshopCalls,
        check = check,
        setView = function(value) hostContext.windmillTestView = value end,
        revision = function() return workshopRevision end,
        mutation = function() return workshopMutation end,
        lease = function() return workshopLease end,
        resource = function() return workshopResource end,
        advanceClock = function(seconds) now = now + seconds end,
    })

    client:stop("Guest signed off")
    host:update(0, hostContext)
    local leavePackets = network:messages("client_to_host", "leave")
    local hostLeaveBroadcasts = network:messages("host_broadcast", "leave")
    local hostLeaveDirect = network:messages("host_to_client", "leave")
    local finalHostEvents = host:drainEvents()
    local left = eventNamed(finalHostEvents, "player_left")
    local leftCount = 0
    for _, event in ipairs(finalHostEvents) do
        if event.type == "player_left" then leftCount = leftCount + 1 end
    end
    check("multiplayer_session_disconnect_leave_cleans_guest_once",
        #leavePackets == 1 and #hostLeaveBroadcasts == 0 and #hostLeaveDirect == 0
        and left and left.playerId == 2 and left.name == "Phone Guest"
        and left.reason == "Guest signed off"
        and leftCount == 1 and host.players[2] == nil
        and host.peerToId[network.peer] == nil and host.idToPeer[2] == nil
        and host:hudInfo().playerCount == 1 and not client:isActive()
        and workshopMutation == hostContext.windmillMutationBeforeTimeout)

    host:stop("Test complete")
    runDirectAdmissionControls({
        clock = clock,
        check = check,
        advanceClock = function(seconds) now = now + seconds end,
    })

    local expiryNetwork = fakeNetwork()
    local expiryHost = Session.new({ transportFactory = expiryNetwork.factory, clock = clock })
    expiryHost:startHost({ name = "Expiry Host", character = "rabbit-worker",
        addressOptions = addressOptions })
    expiryHost.pendingPeers[expiryNetwork.peer] = {
        peer = expiryNetwork.peer,
        connectedAt = now - 11,
        generation = 1,
        stage = "hello",
    }
    expiryHost:update(0, { localPlayer = motionPlayer(400, 500) })
    check("multiplayer_session_silent_prehello_peer_expires",
        expiryHost.pendingPeers[expiryNetwork.peer] == nil
        and #expiryNetwork.disconnects == 1 and expiryNetwork.disconnects[1].code == 3
        and #expiryNetwork:messages("host_to_client", "error") == 1)
    expiryHost:stop("Expiry test complete")

    local timeoutNetwork = fakeNetwork()
    local timeoutHost = Session.new({ transportFactory = timeoutNetwork.factory, clock = clock })
    local timeoutClient = Session.new({ transportFactory = timeoutNetwork.factory, clock = clock })
    timeoutHost:startHost({ name = "Timeout Host", character = "rabbit-worker",
        addressOptions = addressOptions })
    timeoutClient:startClient("192.168.1.50:22122", {
        name = "Timeout Guest", character = "rabbit-worker",
    })
    timeoutClient.sessionId, timeoutClient.localId, timeoutClient.ready = "timeout-test", 2, true
    timeoutClient.players[2] = motionPlayer(428, 500)
    local timeoutRequested = timeoutClient:requestInteraction("loadingBayDoor", "open")
    now = now + 3.01
    timeoutClient:update(0, { localPlayer = timeoutClient.players[2], inputX = 0, inputY = 0 })
    local timeoutResult = eventNamed(timeoutClient:drainEvents(), "interaction_result")
    check("multiplayer_session_unanswered_use_times_out_and_becomes_retryable",
        timeoutRequested and timeoutResult and not timeoutResult.accepted
        and timeoutResult.code == "timeout" and timeoutResult.requestId == 1
        and timeoutResult.targetKind == "loadingBayDoor"
        and timeoutClient.pendingInteraction == nil
        and timeoutClient:requestInteraction("loadingBayDoor", "open"))
    timeoutClient:stop("Timeout test complete")
    timeoutHost:stop("Timeout test complete")

    local failureNetwork = fakeNetwork()
    local failureHost = Session.new({ transportFactory = failureNetwork.factory, clock = clock })
    failureHost:startHost({ name = "Failure Host", character = "rabbit-worker",
        addressOptions = addressOptions })
    failureNetwork.host.serviceError = "synthetic ENet service failure"
    failureHost:update(0, { localPlayer = motionPlayer(400, 500) })
    local failureEvents = failureHost:drainEvents()
    local failureDisconnect = eventNamed(failureEvents, "disconnected")
    check("multiplayer_session_transport_service_failure_is_terminal",
        failureDisconnect and failureDisconnect.message:find("synthetic ENet", 1, true)
        and failureHost.terminal and not failureHost.ready and failureHost.transport == nil)
    failureHost:stop("Failure test complete")

    local disconnectNetwork = fakeNetwork()
    local disconnectHost = Session.new({ transportFactory = disconnectNetwork.factory, clock = clock })
    local disconnectClient = Session.new({ transportFactory = disconnectNetwork.factory, clock = clock })
    disconnectHost:startHost({ name = "Disconnect Host", character = "rabbit-worker",
        addressOptions = addressOptions })
    disconnectClient:startClient("192.168.1.50:22122", {
        name = "Disconnect Guest", character = "rabbit-worker",
    })
    disconnectClient.sessionId, disconnectClient.localId, disconnectClient.ready = "disconnect-test", 2, true
    disconnectClient.players[2] = motionPlayer(428, 500)
    disconnectNetwork.client.inbound = {
        { type = "disconnect", peer = disconnectNetwork.peer, code = 1 },
    }
    disconnectClient:update(0.05, { localPlayer = motionPlayer(428, 500), inputX = 1, inputY = 0 })
    local disconnectEvents = disconnectClient:drainEvents()
    local disconnectCount, errorCount = 0, 0
    for _, event in ipairs(disconnectEvents) do
        if event.type == "disconnected" then disconnectCount = disconnectCount + 1 end
        if event.type == "error" then errorCount = errorCount + 1 end
    end
    check("multiplayer_session_disconnect_does_not_queue_followup_send_error",
        disconnectCount == 1 and errorCount == 0 and disconnectClient.terminal
        and disconnectClient.transport == nil)
    disconnectClient:stop("Disconnect test complete")
    disconnectHost:stop("Disconnect test complete")

    local syncNetwork = fakeNetwork()
    local syncHost = Session.new({ transportFactory = syncNetwork.factory, clock = clock })
    local syncClient = Session.new({ transportFactory = syncNetwork.factory, clock = clock })
    local syncHostPlayer = motionPlayer(500, 520)
    local syncGuestPlayer = motionPlayer(530, 520)
    local authoritativeState = {
        money = 180,
        inventory = { paper = 40, prints = 0, stock = { shipping_cartons = 20 } },
        calendar = { year = 2026, month = 1, day = 3, weekday = 6,
            elapsed = 20, totalDays = 2 },
        jobs = { active = {}, completed = {}, declined = {} },
        clientEmails = { nextEmailId = 1, nextPromotionId = 1,
            pending = {}, inbox = {}, archive = {}, sentPromotions = {} },
    }
    local authoritativeVisitors = {
        customer = visitorState("entering", true, 580, 350, "business-cat"),
        vendor = visitorState("scheduled", false, 500, 300, "green-blazer-cat"),
    }
    local authoritativeEnvironment = {
        bayDoor = { state = "closed", progress = 0 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    }
    local authoritativePalletJack = palletJackState()
    local authoritativeMachinePoses = machinePoseState()
    local syncHostContext = {
        localPlayer = syncHostPlayer,
        resolveGuestSpawn = function() return 530, 520 end,
        getShopSnapshot = function()
            return {
                state = authoritativeState,
                player = { x = syncHostPlayer.x, y = syncHostPlayer.y,
                    character = syncHostPlayer.character },
            }
        end,
        getVisitorSnapshot = function() return authoritativeVisitors end,
        getEnvironmentSnapshot = function() return authoritativeEnvironment end,
        getPalletJackSnapshot = function() return authoritativePalletJack end,
        getMachinePoseSnapshot = function() return authoritativeMachinePoses end,
        moveRemote = function() end,
    }
    local syncClientContext = {
        localPlayer = syncGuestPlayer,
        inputX = 0,
        inputY = 0,
    }
    syncHost:startHost({ name = "State Host", character = "rabbit-worker",
        x = syncHostPlayer.x, y = syncHostPlayer.y, addressOptions = addressOptions })
    syncHost.sessionId = "shop-state-test"
    syncClient:startClient("192.168.1.50:22122", {
        name = "State Guest", character = "rabbit-worker",
    })
    syncClient.clientNonce = "shop-state-nonce"
    syncClient:update(0, syncClientContext)
    syncHost:update(0, syncHostContext)
    syncClient:update(0, syncClientContext)
    syncHost:drainEvents()
    syncClient:drainEvents()

    -- Let the host establish its comparison baseline, then prove that an
    -- unchanged normalized shop never consumes durable bandwidth or revisions.
    syncHost:update(1, syncHostContext)
    syncClient:update(0, syncClientContext)
    syncClient:drainEvents()
    local baselineStatePackets = #syncNetwork:messages("host_to_client", "shop_state")
    syncHost:update(1, syncHostContext)
    syncClient:update(0, syncClientContext)
    local unchangedEvents = syncClient:drainEvents()
    check("multiplayer_session_unchanged_shop_state_is_not_rebroadcast",
        #syncNetwork:messages("host_to_client", "shop_state") == baselineStatePackets
        and eventNamed(unchangedEvents, "shop_state") == nil)

    authoritativeState.money = 925
    authoritativeState.inventory.paper = 2375
    authoritativeState.inventory.prints = 18
    authoritativeState.calendar.day = 5
    authoritativeState.calendar.weekday = 1
    authoritativeState.calendar.totalDays = 4
    authoritativeState.jobs.active = {
        { id = "LAN-JOB-0001", company = "Cross-platform Customer", status = "accepted" },
    }
    authoritativeState.clientEmails.inbox = {
        { id = "EMAIL-0001", sender = "Cross-platform Customer", subject = "Print quote" },
    }
    authoritativeVisitors.customer.state = "waiting"
    authoritativeVisitors.customer.x = 612
    authoritativeVisitors.customer.y = 318
    authoritativeVisitors.customer.waypoint = 3
    authoritativeVisitors.customer.waitTimer = 22
    authoritativeVisitors.vendor.arrivalTimer = 9
    authoritativeEnvironment.bayDoor.state = "opening"
    authoritativeEnvironment.bayDoor.progress = 0.5
    authoritativeEnvironment.truck = {
        state = "parked_closed", jobId = "LAN-JOB-0001", mode = "delivery",
        backingProgress = 1, cargoProgress = 0,
    }
    authoritativePalletJack = palletJackState({
        x = 552,
        y = 490,
        direction = "west",
        operating = true,
        moving = true,
        operatorPlayerId = 2,
        carriedPalletId = "LAN-JOB-0001-P01",
    })
    syncHost:markShopDirty()
    syncHost:update(1, syncHostContext)
    syncClient:update(0, syncClientContext)
    local changedEvents = syncClient:drainEvents()
    local changed = eventNamed(changedEvents, "shop_state")
    local visitorChanged = eventNamed(changedEvents, "visitor_state")
    local environmentChanged = eventNamed(changedEvents, "environment_state")
    local palletJackChanged = eventNamed(changedEvents, "pallet_jack_state")
    local durablePackets = syncNetwork:messages("host_to_client", "shop_state")
    local visitorPackets = syncNetwork:messages("host_to_client", "visitor_snapshot")
    local environmentPackets = syncNetwork:messages("host_to_client", "environment_snapshot")
    local palletJackPackets = syncNetwork:messages("host_to_client", "pallet_jack_snapshot")
    check("multiplayer_session_host_broadcasts_authoritative_shop_state_to_guest",
        #durablePackets == baselineStatePackets + 1
        and durablePackets[#durablePackets].channel == Protocol.CHANNEL_DURABLE
        and durablePackets[#durablePackets].reliable
        and changed and changed.revision > 0
        and changed.state.money == 925
        and changed.state.inventory.paper == 2375
        and changed.state.inventory.prints == 18
        and changed.state.calendar.day == 5
        and changed.state.jobs.active[1].id == "LAN-JOB-0001"
        and changed.state.clientEmails.inbox[1].sender == "Cross-platform Customer"
        and syncClient.lastShopRevision == changed.revision)
    check("multiplayer_session_host_streams_customer_and_vendor_state_to_guest",
        #visitorPackets > 0
        and visitorPackets[#visitorPackets].channel == Protocol.CHANNEL_STATE
        and not visitorPackets[#visitorPackets].reliable
        and visitorChanged and visitorChanged.serverTick == syncHost.serverTick
        and visitorChanged.customer.state == "waiting"
        and visitorChanged.customer.x == 612 and visitorChanged.customer.y == 318
        and visitorChanged.customer.waitTimer == 22
        and visitorChanged.vendor.state == "scheduled"
        and visitorChanged.vendor.arrivalTimer == 9)
    check("multiplayer_session_host_streams_environment_state_to_guest",
        #environmentPackets > 0
        and environmentPackets[#environmentPackets].channel == Protocol.CHANNEL_STATE
        and not environmentPackets[#environmentPackets].reliable
        and environmentChanged and environmentChanged.serverTick == syncHost.serverTick
        and environmentChanged.bayDoor.state == "opening"
        and environmentChanged.bayDoor.progress == 0.5
        and environmentChanged.truck.state == "parked_closed"
        and environmentChanged.truck.jobId == "LAN-JOB-0001"
        and environmentChanged.truck.mode == "delivery"
        and environmentChanged.truck.backingProgress == 1
        and environmentChanged.truck.cargoProgress == 0
        and syncClient.lastEnvironmentTick == environmentChanged.serverTick)
    check("multiplayer_session_host_streams_authoritative_pallet_jack_state_to_guest",
        #palletJackPackets > 0
        and palletJackPackets[#palletJackPackets].channel == Protocol.CHANNEL_STATE
        and not palletJackPackets[#palletJackPackets].reliable
        and palletJackChanged and palletJackChanged.serverTick == syncHost.serverTick
        and palletJackChanged.serverTick == syncClient.lastServerTick
        and palletJackChanged.jack.x == 552 and palletJackChanged.jack.y == 490
        and palletJackChanged.jack.direction == "west"
        and palletJackChanged.jack.operating and palletJackChanged.jack.moving
        and palletJackChanged.jack.operatorPlayerId == 2
        and palletJackChanged.jack.carriedPalletId == "LAN-JOB-0001-P01"
        and palletJackChanged.jack.candidatePalletId == nil
        and palletJackChanged.machines.cutter.x == 700
        and palletJackChanged.machines.wrapper.x == 820
        and palletJackChanged.machines.windmill.x == 850
        and not palletJackChanged.machines.cutter.moving
        and syncClient.lastPalletJackTick == palletJackChanged.serverTick)

    authoritativePalletJack = palletJackState({
        x = 640, y = 508, direction = "east",
        operating = true, moving = true, operatorPlayerId = 1,
    })
    authoritativeMachinePoses = machinePoseState({
        cutter = { x = 640, y = 500, direction = "east",
            moving = true, inMotion = true },
    })
    syncHost:update(0.1, syncHostContext)
    syncClient:update(0, syncClientContext)
    local activeRelocationEvents = syncClient:drainEvents()
    local activeRelocation = eventNamed(activeRelocationEvents, "pallet_jack_state")

    authoritativePalletJack = palletJackState({
        x = 680, y = 542, direction = "northeast",
        operating = true, moving = false, operatorPlayerId = 1,
    })
    authoritativeMachinePoses = machinePoseState({
        cutter = { x = 680, y = 500, direction = "northeast",
            moving = false, inMotion = false },
    })
    syncHost:update(0.1, syncHostContext)
    syncClient:update(0, syncClientContext)
    local terminalRelocationEvents = syncClient:drainEvents()
    local terminalRelocation = eventNamed(terminalRelocationEvents, "pallet_jack_state")

    -- Terminal poses keep streaming after placement. This makes the final
    -- machine location self-healing even if the first unreliable terminal
    -- packet was dropped or crossed a reliable durable update.
    syncHost:update(0.1, syncHostContext)
    syncClient:update(0, syncClientContext)
    local repeatedTerminalEvents = syncClient:drainEvents()
    local repeatedTerminal = eventNamed(repeatedTerminalEvents, "pallet_jack_state")
    check("multiplayer_session_streams_active_and_repeated_terminal_machine_poses",
        activeRelocation and activeRelocation.machines.cutter.moving
        and activeRelocation.machines.cutter.inMotion
        and activeRelocation.machines.cutter.x == activeRelocation.jack.x
        and activeRelocation.machines.cutter.y == activeRelocation.jack.y - 8
        and activeRelocation.machines.cutter.direction == activeRelocation.jack.direction
        and terminalRelocation
        and terminalRelocation.serverTick > activeRelocation.serverTick
        and not terminalRelocation.machines.cutter.moving
        and not terminalRelocation.machines.cutter.inMotion
        and terminalRelocation.machines.cutter.x == 680
        and terminalRelocation.machines.cutter.y == 500
        and repeatedTerminal
        and repeatedTerminal.serverTick > terminalRelocation.serverTick
        and repeatedTerminal.machines.cutter.x == 680
        and repeatedTerminal.machines.cutter.y == 500
        and syncClient.lastPalletJackTick == repeatedTerminal.serverTick)

    local deliveredRevision = changed and changed.revision or 1
    local stalePacket = Protocol.encode("shop_state", {
        sessionId = syncHost.sessionId,
        revision = deliveredRevision,
        state = { money = 1, inventory = { paper = 1 } },
    })
    local wrongSessionPacket = Protocol.encode("shop_state", {
        sessionId = "other-shop",
        revision = deliveredRevision + 1,
        state = { money = 2, inventory = { paper = 2 } },
    })
    local staleVisitorPacket = Protocol.encode("visitor_snapshot", {
        sessionId = syncHost.sessionId,
        serverTick = visitorChanged and visitorChanged.serverTick or syncHost.serverTick,
        customer = visitorState("scheduled", false, 1, 1, "business-cat"),
        vendor = visitorState("waiting", true, 2, 2, "green-blazer-cat"),
    })
    local wrongSessionVisitorPacket = Protocol.encode("visitor_snapshot", {
        sessionId = "other-shop",
        serverTick = (visitorChanged and visitorChanged.serverTick or syncHost.serverTick) + 1,
        customer = authoritativeVisitors.customer,
        vendor = authoritativeVisitors.vendor,
    })
    local staleEnvironmentPacket = Protocol.encode("environment_snapshot", {
        sessionId = syncHost.sessionId,
        serverTick = syncClient.lastEnvironmentTick,
        bayDoor = { state = "closed", progress = 0 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    })
    local wrongSessionEnvironmentPacket = Protocol.encode("environment_snapshot", {
        sessionId = "other-shop",
        serverTick = syncClient.lastEnvironmentTick + 1,
        bayDoor = { state = "open", progress = 1 },
        truck = authoritativeEnvironment.truck,
    })
    local stalePalletJackPacket = Protocol.encode("pallet_jack_snapshot", {
        sessionId = syncHost.sessionId,
        serverTick = activeRelocation and activeRelocation.serverTick or syncHost.serverTick - 2,
        jack = palletJackState({
            x = 640, y = 508, direction = "east",
            operating = true, moving = true, operatorPlayerId = 1,
        }),
        machines = machinePoseState({
            cutter = { x = 640, y = 500, direction = "east",
                moving = true, inMotion = true },
        }),
    })
    local wrongSessionPalletJackPacket = Protocol.encode("pallet_jack_snapshot", {
        sessionId = "other-shop",
        serverTick = (repeatedTerminal and repeatedTerminal.serverTick
            or syncHost.serverTick) + 1,
        jack = palletJackState({
            x = 3, y = 4, operating = true, operatorPlayerId = 2,
        }),
        machines = machinePoseState(),
    })
    syncNetwork.host:send(syncNetwork.peer, stalePacket,
        Protocol.CHANNEL_DURABLE, true)
    syncNetwork.host:send(syncNetwork.peer, wrongSessionPacket,
        Protocol.CHANNEL_DURABLE, true)
    syncNetwork.host:send(syncNetwork.peer, staleVisitorPacket,
        Protocol.CHANNEL_STATE, false)
    syncNetwork.host:send(syncNetwork.peer, wrongSessionVisitorPacket,
        Protocol.CHANNEL_STATE, false)
    syncNetwork.host:send(syncNetwork.peer, staleEnvironmentPacket,
        Protocol.CHANNEL_STATE, false)
    syncNetwork.host:send(syncNetwork.peer, wrongSessionEnvironmentPacket,
        Protocol.CHANNEL_STATE, false)
    syncNetwork.host:send(syncNetwork.peer, stalePalletJackPacket,
        Protocol.CHANNEL_STATE, false)
    syncNetwork.host:send(syncNetwork.peer, wrongSessionPalletJackPacket,
        Protocol.CHANNEL_STATE, false)
    syncClient:update(0, syncClientContext)
    local rejectedStateEvents = syncClient:drainEvents()
    check("multiplayer_session_guest_ignores_stale_and_wrong_session_shop_state",
        eventNamed(rejectedStateEvents, "shop_state") == nil
        and syncClient.lastShopRevision == deliveredRevision)
    check("multiplayer_session_guest_ignores_stale_and_wrong_session_visitor_state",
        eventNamed(rejectedStateEvents, "visitor_state") == nil)
    check("multiplayer_session_guest_ignores_stale_and_wrong_session_environment_state",
        eventNamed(rejectedStateEvents, "environment_state") == nil
        and syncClient.lastEnvironmentTick == syncHost.serverTick)
    check("multiplayer_session_guest_ignores_stale_and_wrong_session_pallet_jack_state",
        eventNamed(rejectedStateEvents, "pallet_jack_state") == nil
        and syncClient.lastPalletJackTick == repeatedTerminal.serverTick)

    local forgedStatePacket = Protocol.encode("shop_state", {
        sessionId = syncHost.sessionId,
        revision = deliveredRevision + 100,
        state = { money = 999999, inventory = { paper = 999999 } },
    })
    local forgedMachinePacket = Protocol.encode("pallet_jack_snapshot", {
        sessionId = syncHost.sessionId,
        serverTick = syncHost.serverTick + 100,
        jack = palletJackState({
            x = 900, y = 708, direction = "east",
            operating = true, moving = true, operatorPlayerId = 1,
        }),
        machines = machinePoseState({
            cutter = { x = 900, y = 700, direction = "east",
                moving = true, inMotion = true },
        }),
    })
    syncNetwork:sendRawToHost(forgedStatePacket, Protocol.CHANNEL_DURABLE, true)
    syncNetwork:sendRawToHost(forgedMachinePacket, Protocol.CHANNEL_STATE, false)
    syncHost:update(0, syncHostContext)
    syncClient:update(0, syncClientContext)
    local rejectionEvents = syncClient:drainEvents()
    local rejected = eventNamed(rejectionEvents, "error")
    local forgedPackets = syncNetwork:messages("client_to_host", "shop_state")
    local forgedMachinePackets = syncNetwork:messages("client_to_host", "pallet_jack_snapshot")
    check("multiplayer_session_guest_cannot_mutate_authoritative_shop_state",
        #forgedPackets == 1
        and forgedPackets[1].channel == Protocol.CHANNEL_DURABLE
        and forgedPackets[1].reliable
        and #forgedMachinePackets == 1
        and forgedMachinePackets[1].channel == Protocol.CHANNEL_STATE
        and not forgedMachinePackets[1].reliable
        and rejected and rejected.code == "message_not_allowed"
        and authoritativeState.money == 925
        and authoritativeState.inventory.paper == 2375
        and authoritativeState.jobs.active[1].id == "LAN-JOB-0001"
        and authoritativeMachinePoses.cutter.x == 680
        and not authoritativeMachinePoses.cutter.moving)

    syncClient:stop("State sync test complete")
    syncHost:update(0, syncHostContext)
    syncHost:stop("State sync test complete")
end

return Test
