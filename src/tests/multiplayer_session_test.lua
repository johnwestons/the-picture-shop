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
    local Context = {
        check = check,
        Codec = Codec,
        Protocol = Protocol,
        Session = Session,
        fakeNetwork = fakeNetwork,
        motionPlayer = motionPlayer,
        visitorState = visitorState,
        palletJackState = palletJackState,
        machinePoseState = machinePoseState,
        cutterState = cutterState,
        windmillState = windmillState,
        eventNamed = eventNamed,
        decodedPayload = decodedPayload,
        runCutterSafetyOrderingRegression = runCutterSafetyOrderingRegression,
        runWindmillSessionRegression = runWindmillSessionRegression,
        runStaleWorkshopGrantRevisionRegression = runStaleWorkshopGrantRevisionRegression,
        runHudExperienceRegression = runHudExperienceRegression,
        runFourDeviceShardingRegression = runFourDeviceShardingRegression,
        runDirectAdmissionControls = runDirectAdmissionControls,
    }
    require("src.tests.multiplayer_session_cases.checks_1").run(Context)
    require("src.tests.multiplayer_session_cases.checks_2").run(Context)
    require("src.tests.multiplayer_session_cases.checks_3").run(Context)
    require("src.tests.multiplayer_session_cases.checks_4").run(Context)
    require("src.tests.multiplayer_session_cases.checks_5").run(Context)
    require("src.tests.multiplayer_session_cases.checks_6").run(Context)

end

return Test
