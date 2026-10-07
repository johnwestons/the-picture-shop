-- Network wire validation and codec regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.mismatchedMachineX = Context.machinePoses({
        cutter = { x = 641, y = 500, direction = "east",
            moving = true, inMotion = true },
    })
    Context.mismatchedMachineXPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.mismatchedMachineX,
    })
    Context.mismatchedMachineY = Context.machinePoses({
        cutter = { x = 640, y = 499, direction = "east",
            moving = true, inMotion = true },
    })
    Context.mismatchedMachineYPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.mismatchedMachineY,
    })
    Context.mismatchedMachineDirection = Context.machinePoses({
        cutter = { x = 640, y = 500, direction = "north",
            moving = true, inMotion = true },
    })
    Context.mismatchedMachineDirectionPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.mismatchedMachineDirection,
    })
    Context.mismatchedMachineMotion = Context.machinePoses({
        cutter = { x = 640, y = 500, direction = "east",
            moving = true, inMotion = false },
    })
    Context.mismatchedMachineMotionPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.mismatchedMachineMotion,
    })
    Context.unboundedMachinePose = Context.machinePoses()
    Context.unboundedMachinePose.cutter.x = math.huge
    Context.unboundedMachinePosePacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.unboundedMachinePose,
    })
    Context.check("network_protocol_pallet_jack_snapshot_is_strict_owner_aware_and_bounded",
        Context.palletJackEnvelope and Context.palletJackEnvelope.payload.serverTick == 43
        and Context.palletJackEnvelope.payload.jack.operatorPlayerId == 2
        and Context.palletJackEnvelope.payload.jack.carriedPalletId == "JOB-0001-P01"
        and Context.parkedLoadedEnvelope and not Context.parkedLoadedEnvelope.payload.jack.operating
        and Context.parkedLoadedEnvelope.payload.jack.operatorPlayerId == nil
        and Context.parkedLoadedEnvelope.payload.jack.carriedPalletId == "JOB-0001-P01"
        and #Context.palletJackPacket <= Context.Protocol.MAX_PACKET_BYTES
        and #Context.parkedLoadedPacket <= Context.Protocol.MAX_PACKET_BYTES
        and Context.missingJackOwner == nil and Context.parkedMovingJack == nil
        and Context.loadedCandidateJack == nil and Context.spoofedJack == nil
        and Context.invalidJackDirection == nil and Context.candidateOnParkedJack == nil
        and Context.invalidJackOwner == nil and Context.fractionalJackTick == nil)

    Context.check("network_protocol_machine_poses_are_complete_strict_and_jack_coherent",
        Context.relocatingEnvelope
        and Context.relocatingEnvelope.payload.machines.cutter.x == 640
        and Context.relocatingEnvelope.payload.machines.cutter.y == 500
        and Context.relocatingEnvelope.payload.machines.cutter.direction == "east"
        and Context.relocatingEnvelope.payload.machines.cutter.moving
        and Context.relocatingEnvelope.payload.machines.cutter.inMotion
        and not Context.relocatingEnvelope.payload.machines.wrapper.moving
        and not Context.relocatingEnvelope.payload.machines.windmill.moving
        and #Context.relocatingPacket <= Context.Protocol.MAX_PACKET_BYTES
        and Context.missingMachines == nil and Context.missingMachinePose == nil
        and Context.unknownMachinePacket == nil and Context.extraPoseFieldPacket == nil
        and Context.incompletePosePacket == nil and Context.invalidWrapperDirectionPacket == nil
        and Context.invalidWindmillDirectionPacket == nil and Context.invalidMotionFlagPacket == nil
        and Context.motionWithoutAttachmentPacket == nil and Context.twoMovingMachinesPacket == nil
        and Context.guestOwnedRelocationPacket ~= nil and Context.loadedRelocationPacket == nil
        and Context.candidateRelocationPacket == nil
        and Context.mismatchedMachineXPacket == nil and Context.mismatchedMachineYPacket == nil
        and Context.mismatchedMachineDirectionPacket == nil
        and Context.mismatchedMachineMotionPacket == nil and Context.unboundedMachinePosePacket == nil)

    Context.safeShopPacket = Context.Protocol.encode("shop_snapshot", {
        sessionId = "session-001",
        revision = 0,
        state = {
            inventory = { paper = 2500, stock = { shipping_cartons = 2 } },
            jobs = Context.Codec.array({ { id = "JOB-0001", status = "in_production" } }),
        },
        player = { x = 420, y = 520, character = "rabbit-worker" },
    })
    Context.safeShop = Context.safeShopPacket and Context.Protocol.decode(Context.safeShopPacket)
    Context.unsafeShopPacket = Context.Protocol.encode("shop_snapshot", {
        sessionId = "session-001",
        revision = 0,
        state = { callback = function() return "not data" end },
        player = { x = 1, y = 2 },
    })
    Context.unsafeShopEnvelope = Context.Protocol.make("shop_snapshot", {
        sessionId = "session-001",
        revision = 0,
        state = { callback = function() return "not data" end },
        player = { x = 1, y = 2 },
    })
    Context.chunk = string.rep("x", 110000)
    Context.oversizedShopPacket = Context.Protocol.encode("shop_snapshot", {
        sessionId = "session-001",
        revision = 0,
        state = { chunks = Context.Codec.array({ Context.chunk, Context.chunk, Context.chunk, Context.chunk, Context.chunk }) },
        player = { x = 1, y = 2 },
    })
    Context.unrevisionedShopPacket = Context.Protocol.encode("shop_snapshot", {
        sessionId = "session-001", state = {}, player = { x = 1, y = 2 },
    })
    Context.check("network_protocol_shop_snapshot_is_safe_and_separately_bounded",
        Context.safeShop and Context.safeShop.payload.state.inventory.paper == 2500
        and Context.safeShop.payload.revision == 0
        and Context.safeShop.payload.player.character == "rabbit-worker"
        and Context.Protocol.packetLimitFor("shop_snapshot") == Context.Protocol.MAX_SHOP_SNAPSHOT_BYTES
        and Context.unsafeShopPacket == nil and Context.unsafeShopEnvelope == nil
        and Context.oversizedShopPacket == nil and Context.unrevisionedShopPacket == nil)

    Context.safeStatePacket = Context.Protocol.encode("shop_state", {
        sessionId = "session-001",
        revision = 8,
        state = {
            inventory = { paper = 2250, stock = { shipping_cartons = 5 } },
            calendar = { year = 1, month = 1, day = 5, hour = 10, minute = 30 },
            jobs = { active = Context.Codec.array({ { id = "JOB-0002", status = "accepted" } }) },
        },
    })
    Context.safeState = Context.safeStatePacket and Context.Protocol.decode(Context.safeStatePacket)
    Context.invalidRevision = Context.Protocol.encode("shop_state", {
        sessionId = "session-001", revision = -1, state = {},
    })
    Context.extraStateField = Context.Protocol.encode("shop_state", {
        sessionId = "session-001", revision = 8, state = {}, player = {},
    })
    Context.unsafeStatePacket = Context.Protocol.encode("shop_state", {
        sessionId = "session-001", revision = 8,
        state = { callback = function() return "not data" end },
    })
    Context.oversizedStatePacket = Context.Protocol.encode("shop_state", {
        sessionId = "session-001", revision = 8,
        state = { chunks = Context.Codec.array({ Context.chunk, Context.chunk, Context.chunk, Context.chunk, Context.chunk }) },
    })
    Context.check("network_protocol_shop_state_is_revisioned_safe_and_snapshot_bounded",
        Context.safeState and Context.safeState.payload.revision == 8
        and Context.safeState.payload.state.inventory.paper == 2250
        and Context.Protocol.packetLimitFor("shop_state") == Context.Protocol.MAX_SHOP_SNAPSHOT_BYTES
        and Context.invalidRevision == nil and Context.extraStateField == nil
        and Context.unsafeStatePacket == nil and Context.oversizedStatePacket == nil)

    Context.liveState = Context.SaveSchema.snapshot(Context.context.state)
    Context.livePacket, Context.liveEncodeError = Context.Protocol.encode("shop_snapshot", {
        sessionId = "live-save-contract",
        revision = 0,
        state = Context.liveState,
        player = Context.context.world.snapshot(),
    })
    Context.liveEnvelope, Context.liveDecodeError = nil
    if Context.livePacket then Context.liveEnvelope, Context.liveDecodeError = Context.Protocol.decode(Context.livePacket) end
    Context.check("network_protocol_current_save_schema_round_trips_as_shop_snapshot",
        Context.livePacket ~= nil and #Context.livePacket <= Context.Protocol.MAX_SHOP_SNAPSHOT_BYTES
        and Context.liveEnvelope ~= nil and Context.liveEnvelope.payload.state.money == Context.liveState.money
        and type(Context.liveEnvelope.payload.state.inventory) == "table"
        and Context.liveEnvelope.payload.player.character == Context.context.world.player.character,
        tostring(Context.liveEncodeError or Context.liveDecodeError or (Context.livePacket and #Context.livePacket) or "unknown failure"))

    Context.spawnX, Context.spawnY = Context.context.world.resolveNetworkSpawn(
        Context.context.world.player.x, Context.context.world.player.y, 2,
        Context.context.assets, Context.context.state, { Context.context.world.player })
    Context.check("network_guest_spawn_resolver_returns_walkable_shop_position",
        type(Context.spawnX) == "number" and type(Context.spawnY) == "number"
        and Context.context.Navigation.isWalkable(Context.context.assets, Context.spawnX, Context.spawnY, {}))

    Context.routesCorrect = Context.Protocol.VERSION == 28 and Context.Protocol.CHANNEL_COUNT == 3
        and Context.Protocol.CHANNEL_CONTROL == 0 and Context.Protocol.CHANNEL_STATE == 1
        and Context.Protocol.CHANNEL_DURABLE == 2 and Context.Protocol.MAX_PLAYERS == 4
    Context.routeSummary = {}
    for _, kind in ipairs({
        "hello", "welcome", "radio_state", "interaction_request", "interaction_result",
        "workshop_acquire", "workshop_grant", "workshop_command", "workshop_result",
        "workshop_release", "leave", "error",
    }) do
        local channel, delivery = Context.Protocol.route(kind)
        Context.routeSummary[#Context.routeSummary + 1] = kind .. "=" .. tostring(channel) .. "/" .. tostring(delivery)
        Context.routesCorrect = Context.routesCorrect
            and channel == Context.Protocol.CHANNEL_CONTROL and delivery == "reliable"
    end
    for _, kind in ipairs({
        "input", "snapshot", "visitor_snapshot", "environment_snapshot", "workshop_snapshot",
        "pallet_jack_snapshot", "cutter_snapshot", "wrapper_snapshot", "windmill_snapshot", "ping", "pong",
    }) do
        local channel, delivery = Context.Protocol.route(kind)
        Context.routeSummary[#Context.routeSummary + 1] = kind .. "=" .. tostring(channel) .. "/" .. tostring(delivery)
        Context.routesCorrect = Context.routesCorrect
            and channel == Context.Protocol.CHANNEL_STATE and delivery == "unreliable"
    end
    Context.durableChannel, Context.durableDelivery = Context.Protocol.route("shop_state")
    Context.joinStateChannel, Context.joinStateDelivery = Context.Protocol.route("shop_snapshot")
    Context.routesCorrect = Context.routesCorrect
        and Context.durableChannel == Context.Protocol.CHANNEL_DURABLE and Context.durableDelivery == "reliable"
        and Context.joinStateChannel == Context.Protocol.CHANNEL_DURABLE and Context.joinStateDelivery == "reliable"
    for _, kind in ipairs({
        "workshop_acquire", "workshop_grant", "workshop_command", "workshop_result",
        "workshop_release", "workshop_snapshot", "pallet_jack_snapshot", "cutter_snapshot",
        "windmill_snapshot", "wrapper_snapshot",
    }) do
        Context.routesCorrect = Context.routesCorrect
            and Context.Protocol.packetLimitFor(kind) == Context.Protocol.MAX_PACKET_BYTES
    end
end

return Component
