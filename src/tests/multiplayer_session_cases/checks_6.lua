-- Multiplayer session regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.authoritativePalletJack = Context.palletJackState({
        x = 640, y = 508, direction = "east",
        operating = true, moving = true, operatorPlayerId = 1,
    })
    Context.authoritativeMachinePoses = Context.machinePoseState({
        cutter = { x = 640, y = 500, direction = "east",
            moving = true, inMotion = true },
    })
    Context.syncHost:update(0.1, Context.syncHostContext)
    Context.syncClient:update(0, Context.syncClientContext)
    Context.activeRelocationEvents = Context.syncClient:drainEvents()
    Context.activeRelocation = Context.eventNamed(Context.activeRelocationEvents, "pallet_jack_state")

    Context.authoritativePalletJack = Context.palletJackState({
        x = 680, y = 542, direction = "northeast",
        operating = true, moving = false, operatorPlayerId = 1,
    })
    Context.authoritativeMachinePoses = Context.machinePoseState({
        cutter = { x = 680, y = 500, direction = "northeast",
            moving = false, inMotion = false },
    })
    Context.syncHost:update(0.1, Context.syncHostContext)
    Context.syncClient:update(0, Context.syncClientContext)
    Context.terminalRelocationEvents = Context.syncClient:drainEvents()
    Context.terminalRelocation = Context.eventNamed(Context.terminalRelocationEvents, "pallet_jack_state")

    -- Terminal poses keep streaming after placement. This makes the final
    -- machine location self-healing even if the first unreliable terminal
    -- packet was dropped or crossed a reliable durable update.
    Context.syncHost:update(0.1, Context.syncHostContext)
    Context.syncClient:update(0, Context.syncClientContext)
    Context.repeatedTerminalEvents = Context.syncClient:drainEvents()
    Context.repeatedTerminal = Context.eventNamed(Context.repeatedTerminalEvents, "pallet_jack_state")
    Context.check("multiplayer_session_streams_active_and_repeated_terminal_machine_poses",
        Context.activeRelocation and Context.activeRelocation.machines.cutter.moving
        and Context.activeRelocation.machines.cutter.inMotion
        and Context.activeRelocation.machines.cutter.x == Context.activeRelocation.jack.x
        and Context.activeRelocation.machines.cutter.y == Context.activeRelocation.jack.y - 8
        and Context.activeRelocation.machines.cutter.direction == Context.activeRelocation.jack.direction
        and Context.terminalRelocation
        and Context.terminalRelocation.serverTick > Context.activeRelocation.serverTick
        and not Context.terminalRelocation.machines.cutter.moving
        and not Context.terminalRelocation.machines.cutter.inMotion
        and Context.terminalRelocation.machines.cutter.x == 680
        and Context.terminalRelocation.machines.cutter.y == 500
        and Context.repeatedTerminal
        and Context.repeatedTerminal.serverTick > Context.terminalRelocation.serverTick
        and Context.repeatedTerminal.machines.cutter.x == 680
        and Context.repeatedTerminal.machines.cutter.y == 500
        and Context.syncClient.lastPalletJackTick == Context.repeatedTerminal.serverTick)

    Context.deliveredRevision = Context.changed and Context.changed.revision or 1
    Context.stalePacket = Context.Protocol.encode("shop_state", {
        sessionId = Context.syncHost.sessionId,
        revision = Context.deliveredRevision,
        state = { money = 1, inventory = { paper = 1 } },
    })
    Context.wrongSessionPacket = Context.Protocol.encode("shop_state", {
        sessionId = "other-shop",
        revision = Context.deliveredRevision + 1,
        state = { money = 2, inventory = { paper = 2 } },
    })
    Context.staleVisitorPacket = Context.Protocol.encode("visitor_snapshot", {
        sessionId = Context.syncHost.sessionId,
        serverTick = Context.visitorChanged and Context.visitorChanged.serverTick or Context.syncHost.serverTick,
        customer = Context.visitorState("scheduled", false, 1, 1, "business-cat"),
        vendor = Context.visitorState("waiting", true, 2, 2, "green-blazer-cat"),
    })
    Context.wrongSessionVisitorPacket = Context.Protocol.encode("visitor_snapshot", {
        sessionId = "other-shop",
        serverTick = (Context.visitorChanged and Context.visitorChanged.serverTick or Context.syncHost.serverTick) + 1,
        customer = Context.authoritativeVisitors.customer,
        vendor = Context.authoritativeVisitors.vendor,
    })
    Context.staleEnvironmentPacket = Context.Protocol.encode("environment_snapshot", {
        sessionId = Context.syncHost.sessionId,
        serverTick = Context.syncClient.lastEnvironmentTick,
        bayDoor = { state = "closed", progress = 0 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    })
    Context.wrongSessionEnvironmentPacket = Context.Protocol.encode("environment_snapshot", {
        sessionId = "other-shop",
        serverTick = Context.syncClient.lastEnvironmentTick + 1,
        bayDoor = { state = "open", progress = 1 },
        truck = Context.authoritativeEnvironment.truck,
    })
    Context.stalePalletJackPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = Context.syncHost.sessionId,
        serverTick = Context.activeRelocation and Context.activeRelocation.serverTick or Context.syncHost.serverTick - 2,
        jack = Context.palletJackState({
            x = 640, y = 508, direction = "east",
            operating = true, moving = true, operatorPlayerId = 1,
        }),
        machines = Context.machinePoseState({
            cutter = { x = 640, y = 500, direction = "east",
                moving = true, inMotion = true },
        }),
    })
    Context.wrongSessionPalletJackPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "other-shop",
        serverTick = (Context.repeatedTerminal and Context.repeatedTerminal.serverTick
            or Context.syncHost.serverTick) + 1,
        jack = Context.palletJackState({
            x = 3, y = 4, operating = true, operatorPlayerId = 2,
        }),
        machines = Context.machinePoseState(),
    })
    Context.syncNetwork.host:send(Context.syncNetwork.peer, Context.stalePacket,
        Context.Protocol.CHANNEL_DURABLE, true)
    Context.syncNetwork.host:send(Context.syncNetwork.peer, Context.wrongSessionPacket,
        Context.Protocol.CHANNEL_DURABLE, true)
    Context.syncNetwork.host:send(Context.syncNetwork.peer, Context.staleVisitorPacket,
        Context.Protocol.CHANNEL_STATE, false)
    Context.syncNetwork.host:send(Context.syncNetwork.peer, Context.wrongSessionVisitorPacket,
        Context.Protocol.CHANNEL_STATE, false)
    Context.syncNetwork.host:send(Context.syncNetwork.peer, Context.staleEnvironmentPacket,
        Context.Protocol.CHANNEL_STATE, false)
    Context.syncNetwork.host:send(Context.syncNetwork.peer, Context.wrongSessionEnvironmentPacket,
        Context.Protocol.CHANNEL_STATE, false)
    Context.syncNetwork.host:send(Context.syncNetwork.peer, Context.stalePalletJackPacket,
        Context.Protocol.CHANNEL_STATE, false)
    Context.syncNetwork.host:send(Context.syncNetwork.peer, Context.wrongSessionPalletJackPacket,
        Context.Protocol.CHANNEL_STATE, false)
    Context.syncClient:update(0, Context.syncClientContext)
    Context.rejectedStateEvents = Context.syncClient:drainEvents()
    Context.check("multiplayer_session_guest_ignores_stale_and_wrong_session_shop_state",
        Context.eventNamed(Context.rejectedStateEvents, "shop_state") == nil
        and Context.syncClient.lastShopRevision == Context.deliveredRevision)
    Context.check("multiplayer_session_guest_ignores_stale_and_wrong_session_visitor_state",
        Context.eventNamed(Context.rejectedStateEvents, "visitor_state") == nil)
    Context.check("multiplayer_session_guest_ignores_stale_and_wrong_session_environment_state",
        Context.eventNamed(Context.rejectedStateEvents, "environment_state") == nil
        and Context.syncClient.lastEnvironmentTick == Context.syncHost.serverTick)
    Context.check("multiplayer_session_guest_ignores_stale_and_wrong_session_pallet_jack_state",
        Context.eventNamed(Context.rejectedStateEvents, "pallet_jack_state") == nil
        and Context.syncClient.lastPalletJackTick == Context.repeatedTerminal.serverTick)

    Context.forgedStatePacket = Context.Protocol.encode("shop_state", {
        sessionId = Context.syncHost.sessionId,
        revision = Context.deliveredRevision + 100,
        state = { money = 999999, inventory = { paper = 999999 } },
    })
    Context.forgedMachinePacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = Context.syncHost.sessionId,
        serverTick = Context.syncHost.serverTick + 100,
        jack = Context.palletJackState({
            x = 900, y = 708, direction = "east",
            operating = true, moving = true, operatorPlayerId = 1,
        }),
        machines = Context.machinePoseState({
            cutter = { x = 900, y = 700, direction = "east",
                moving = true, inMotion = true },
        }),
    })
    Context.syncNetwork:sendRawToHost(Context.Protocol.encode("radio_state", {
        sessionId = Context.syncHost.sessionId, revision = 1000, trackIndex = 9,
        active = true, paused = false, muted = false, positionMs = 0,
    }), Context.Protocol.CHANNEL_CONTROL, true)
    Context.syncNetwork:sendRawToHost(Context.forgedStatePacket, Context.Protocol.CHANNEL_DURABLE, true)
    Context.syncNetwork:sendRawToHost(Context.forgedMachinePacket, Context.Protocol.CHANNEL_STATE, false)
    Context.syncHost:update(0, Context.syncHostContext)
    Context.syncClient:update(0, Context.syncClientContext)
    Context.rejectionEvents = Context.syncClient:drainEvents()
    Context.rejected = Context.eventNamed(Context.rejectionEvents, "error")
    Context.forgedPackets = Context.syncNetwork:messages("client_to_host", "shop_state")
    Context.forgedMachinePackets = Context.syncNetwork:messages("client_to_host", "pallet_jack_snapshot")
    Context.check("multiplayer_session_guest_cannot_mutate_authoritative_shop_state",
        #Context.forgedPackets == 1
        and Context.forgedPackets[1].channel == Context.Protocol.CHANNEL_DURABLE
        and Context.forgedPackets[1].reliable
        and #Context.forgedMachinePackets == 1
        and Context.forgedMachinePackets[1].channel == Context.Protocol.CHANNEL_STATE
        and not Context.forgedMachinePackets[1].reliable
        and #Context.syncNetwork:messages("client_to_host", "radio_state") == 1
        and Context.syncNetwork:messages("client_to_host", "radio_state")[1].reliable
        and Context.rejected and Context.rejected.code == "message_not_allowed"
        and Context.syncHost.radioState.trackIndex == 5
        and Context.authoritativeState.money == 925
        and Context.authoritativeState.inventory.paper == 2375
        and Context.authoritativeState.jobs.active[1].id == "LAN-JOB-0001"
        and Context.authoritativeMachinePoses.cutter.x == 680
        and not Context.authoritativeMachinePoses.cutter.moving)

    Context.syncClient:stop("State sync test complete")
    Context.syncHost:update(0, Context.syncHostContext)
    Context.syncHost:stop("State sync test complete")
end

return Component
