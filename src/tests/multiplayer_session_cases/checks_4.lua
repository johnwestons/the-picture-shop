-- Multiplayer session regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.client:update(0, Context.clientContext)
    Context.cutterGrant = Context.eventNamed(Context.client:drainEvents(), "workshop_grant")
    Context.cutterGrantWireMessages = Context.network:messages("host_to_client", "workshop_grant")
    Context.cutterGrantWire = Context.decodedPayload(Context.cutterGrantWireMessages[#Context.cutterGrantWireMessages])

    Context.runCutterSafetyOrderingRegression({
        client = Context.client,
        host = Context.host,
        network = Context.network,
        hostContext = Context.hostContext,
        clientContext = Context.clientContext,
        view = Context.authoritativeCutter,
        workshopCalls = Context.workshopCalls,
        revision = function() return Context.workshopRevision end,
        check = Context.check,
    })

    Context.cutterWires = {}
    function Context.sendCutterCommand(action, arguments)
        local before = #Context.network:messages("client_to_host", "workshop_command")
        local requested = Context.client:requestWorkshopCommand(action, arguments)
        Context.host:update(0, Context.hostContext)
        Context.client:update(0, Context.clientContext)
        local result = Context.eventNamed(Context.client:drainEvents(), "workshop_result")
        local packets = Context.network:messages("client_to_host", "workshop_command")
        Context.cutterWires[#Context.cutterWires + 1] = Context.decodedPayload(packets[before + 1])
        return requested and result and result.accepted
    end

    Context.cutterCommandsAccepted = Context.sendCutterCommand(
        "load_pallet", { palletId = "JOB-CUT-P01" })
        and Context.sendCutterCommand("select_program", { programIndex = 4 })
        and Context.sendCutterCommand("set_gauge", { gaugeCentiInch = 625 })
        and Context.sendCutterCommand("set_clamp", { clamp = true })
        and Context.sendCutterCommand("set_barrier", { barrierClear = false })
        and Context.sendCutterCommand("guarded_cut", {
            palletId = "MUST-NOT-REACH-HOST", clamp = true,
        })

    Context.host:update(0.09, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.cutterStateEvent = Context.eventNamed(Context.client:drainEvents(), "cutter_state")
    Context.cutterPackets = Context.network:messages("host_to_client", "cutter_snapshot")
    Context.latestCutterWire = Context.decodedPayload(Context.cutterPackets[#Context.cutterPackets])
    Context.cutterTick = Context.client.lastCutterTick
    Context.staleCutterPacket = Context.Protocol.encode("cutter_snapshot", {
        sessionId = Context.host.sessionId,
        serverTick = Context.cutterTick,
        resourceRevision = Context.workshopRevision,
        view = Context.authoritativeCutter,
    })
    Context.network.host:send(Context.network.peer, Context.staleCutterPacket, Context.Protocol.CHANNEL_STATE, false)
    Context.client:update(0, Context.clientContext)
    Context.staleCutterEvent = Context.eventNamed(Context.client:drainEvents(), "cutter_state")

    Context.check("multiplayer_session_cutter_commands_and_live_state_use_closed_revisioned_shapes",
        Context.cutterRequested and Context.cutterGrant and Context.cutterGrant.granted
        and Context.cutterGrant.resourceId == "cutter" and Context.cutterGrant.view
        and #Context.cutterGrant.view.candidates == 1
        and Context.cutterGrantWire and Context.cutterGrantWire.view
        and Context.Codec.isArray(Context.cutterGrantWire.view.memoryCentiInch)
        and Context.Codec.isArray(Context.cutterGrantWire.view.candidates)
        and Context.cutterCommandsAccepted and #Context.cutterWires == 6
        and Context.cutterWires[1].palletId == "JOB-CUT-P01"
        and Context.cutterWires[1].programIndex == nil
        and Context.cutterWires[2].programIndex == 4 and Context.cutterWires[2].palletId == nil
        and Context.cutterWires[3].gaugeCentiInch == 625
        and Context.cutterWires[4].clamp == true
        and Context.cutterWires[5].barrierClear == false
        and Context.cutterWires[6].palletId == nil and Context.cutterWires[6].clamp == nil
        and Context.cutterStateEvent and Context.cutterStateEvent.serverTick == Context.cutterTick
        and Context.cutterStateEvent.resourceRevision == Context.workshopRevision
        and Context.cutterStateEvent.view.runtimeRevision == 1
        and Context.latestCutterWire and Context.latestCutterWire.serverTick == Context.cutterTick
        and Context.cutterPackets[#Context.cutterPackets].channel == Context.Protocol.CHANNEL_STATE
        and not Context.cutterPackets[#Context.cutterPackets].reliable
        and #Context.cutterPackets[#Context.cutterPackets].payload <= Context.Protocol.MAX_PACKET_BYTES
        and Context.staleCutterEvent == nil and Context.client.lastCutterTick == Context.cutterTick)

    Context.cutterReleased = Context.client:releaseWorkshop("closed")
    Context.host:update(0, Context.hostContext)
    Context.check("multiplayer_session_worker_releases_cutter_console",
        Context.cutterReleased and Context.client:workshopInfo() == nil
        and Context.workshopLease == nil and Context.workshopResource == nil)

    Context.hostContext.windmillMutationBeforeTimeout = Context.runWindmillSessionRegression({
        client = Context.client,
        host = Context.host,
        network = Context.network,
        hostContext = Context.hostContext,
        clientContext = Context.clientContext,
        workshopCalls = Context.workshopCalls,
        check = Context.check,
        setView = function(value) Context.hostContext.windmillTestView = value end,
        revision = function() return Context.workshopRevision end,
        mutation = function() return Context.workshopMutation end,
        lease = function() return Context.workshopLease end,
        resource = function() return Context.workshopResource end,
        advanceClock = function(seconds) Context.now = Context.now + seconds end,
    })

    Context.client:stop("Guest signed off")
    Context.host:update(0, Context.hostContext)
    Context.leavePackets = Context.network:messages("client_to_host", "leave")
    Context.hostLeaveBroadcasts = Context.network:messages("host_broadcast", "leave")
    Context.hostLeaveDirect = Context.network:messages("host_to_client", "leave")
    Context.finalHostEvents = Context.host:drainEvents()
    Context.left = Context.eventNamed(Context.finalHostEvents, "player_left")
    Context.leftCount = 0
    for _, event in ipairs(Context.finalHostEvents) do
        if event.type == "player_left" then Context.leftCount = Context.leftCount + 1 end
    end
    Context.check("multiplayer_session_disconnect_leave_cleans_guest_once",
        #Context.leavePackets == 1 and #Context.hostLeaveBroadcasts == 0 and #Context.hostLeaveDirect == 0
        and Context.left and Context.left.playerId == 2 and Context.left.name == "Phone Guest"
        and Context.left.reason == "Guest signed off"
        and Context.leftCount == 1 and Context.host.players[2] == nil
        and Context.host.peerToId[Context.network.peer] == nil and Context.host.idToPeer[2] == nil
        and Context.host:hudInfo().playerCount == 1 and not Context.client:isActive()
        and Context.workshopMutation == Context.hostContext.windmillMutationBeforeTimeout)

    Context.host:stop("Test complete")
    Context.runDirectAdmissionControls({
        clock = Context.clock,
        check = Context.check,
        advanceClock = function(seconds) Context.now = Context.now + seconds end,
    })

    Context.expiryNetwork = Context.fakeNetwork()
    Context.expiryHost = Context.Session.new({ transportFactory = Context.expiryNetwork.factory, clock = Context.clock })
    Context.expiryHost:startHost({ name = "Expiry Host", character = "rabbit-worker",
        addressOptions = Context.addressOptions })
    Context.expiryHost.pendingPeers[Context.expiryNetwork.peer] = {
        peer = Context.expiryNetwork.peer,
        connectedAt = Context.now - 11,
        generation = 1,
        stage = "hello",
    }
    Context.expiryHost:update(0, { localPlayer = Context.motionPlayer(400, 500) })
    Context.check("multiplayer_session_silent_prehello_peer_expires",
        Context.expiryHost.pendingPeers[Context.expiryNetwork.peer] == nil
        and #Context.expiryNetwork.disconnects == 1 and Context.expiryNetwork.disconnects[1].code == 3
        and #Context.expiryNetwork:messages("host_to_client", "error") == 1)
    Context.expiryHost:stop("Expiry test complete")

    Context.timeoutNetwork = Context.fakeNetwork()
    Context.timeoutHost = Context.Session.new({ transportFactory = Context.timeoutNetwork.factory, clock = Context.clock })
    Context.timeoutClient = Context.Session.new({ transportFactory = Context.timeoutNetwork.factory, clock = Context.clock })
    Context.timeoutHost:startHost({ name = "Timeout Host", character = "rabbit-worker",
        addressOptions = Context.addressOptions })
    Context.timeoutClient:startClient("192.168.1.50:22122", {
        name = "Timeout Guest", character = "rabbit-worker",
    })
    Context.timeoutClient.sessionId, Context.timeoutClient.localId, Context.timeoutClient.ready = "timeout-test", 2, true
    Context.timeoutClient.players[2] = Context.motionPlayer(428, 500)
    Context.timeoutRequested = Context.timeoutClient:requestInteraction("loadingBayDoor", "open")
    Context.now = Context.now + 3.01
    Context.timeoutClient:update(0, { localPlayer = Context.timeoutClient.players[2], inputX = 0, inputY = 0 })
    Context.timeoutResult = Context.eventNamed(Context.timeoutClient:drainEvents(), "interaction_result")
    Context.check("multiplayer_session_unanswered_use_times_out_and_becomes_retryable",
        Context.timeoutRequested and Context.timeoutResult and not Context.timeoutResult.accepted
        and Context.timeoutResult.code == "timeout" and Context.timeoutResult.requestId == 1
        and Context.timeoutResult.targetKind == "loadingBayDoor"
        and Context.timeoutClient.pendingInteraction == nil
        and Context.timeoutClient:requestInteraction("loadingBayDoor", "open"))
    Context.timeoutClient:stop("Timeout test complete")
    Context.timeoutHost:stop("Timeout test complete")

    Context.failureNetwork = Context.fakeNetwork()
    Context.failureHost = Context.Session.new({ transportFactory = Context.failureNetwork.factory, clock = Context.clock })
    Context.failureHost:startHost({ name = "Failure Host", character = "rabbit-worker",
        addressOptions = Context.addressOptions })
    Context.failureNetwork.host.serviceError = "synthetic ENet service failure"
    Context.failureHost:update(0, { localPlayer = Context.motionPlayer(400, 500) })
    Context.failureEvents = Context.failureHost:drainEvents()
    Context.failureDisconnect = Context.eventNamed(Context.failureEvents, "disconnected")
    Context.check("multiplayer_session_transport_service_failure_is_terminal",
        Context.failureDisconnect and Context.failureDisconnect.message:find("synthetic ENet", 1, true)
        and Context.failureHost.terminal and not Context.failureHost.ready and Context.failureHost.transport == nil)
    Context.failureHost:stop("Failure test complete")

    Context.disconnectNetwork = Context.fakeNetwork()
    Context.disconnectHost = Context.Session.new({ transportFactory = Context.disconnectNetwork.factory, clock = Context.clock })
    Context.disconnectClient = Context.Session.new({ transportFactory = Context.disconnectNetwork.factory, clock = Context.clock })
    Context.disconnectHost:startHost({ name = "Disconnect Host", character = "rabbit-worker",
        addressOptions = Context.addressOptions })
    Context.disconnectClient:startClient("192.168.1.50:22122", {
        name = "Disconnect Guest", character = "rabbit-worker",
    })
    Context.disconnectClient.sessionId, Context.disconnectClient.localId, Context.disconnectClient.ready = "disconnect-test", 2, true
    Context.disconnectClient.players[2] = Context.motionPlayer(428, 500)
    Context.disconnectNetwork.client.inbound = {
        { type = "disconnect", peer = Context.disconnectNetwork.peer, code = 1 },
    }
    Context.disconnectClient:update(0.05, { localPlayer = Context.motionPlayer(428, 500), inputX = 1, inputY = 0 })
    Context.disconnectEvents = Context.disconnectClient:drainEvents()
    Context.disconnectCount, Context.errorCount = 0, 0
    for _, event in ipairs(Context.disconnectEvents) do
        if event.type == "disconnected" then Context.disconnectCount = Context.disconnectCount + 1 end
        if event.type == "error" then Context.errorCount = Context.errorCount + 1 end
    end
end

return Component
