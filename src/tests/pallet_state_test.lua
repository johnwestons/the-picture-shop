local Test = {}

function Test.run(context, check)
    local state = context.State.new()
    local job = context.jobs.createOffer({
        id = "DOMAIN-OWNERSHIP", company = "Domain Test Co.",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
    })
    context.jobs.accept(job)
    state.jobs.active[1] = job
    local pallet = job.pallets[1]
    pallet.location = "warehouse"
    pallet.status = "raw"
    pallet.world = { x = 400, y = 400, fromX = 400, fromY = 400,
        direction = "northwest", rotation = 1, spawnProgress = 1 }

    check("domain_pallet_single_owner_transition",
        context.PalletState.transition(state, pallet, "on_pallet_jack")
        and state.palletJack.carriedPalletId == pallet.id
        and context.PalletState.validate(state))
    check("domain_pallet_rejects_jack_to_cutter_claim",
        not context.PalletState.transition(state, pallet, "at_cutter", {
            cutterRadius = context.config.cutterPlacement.palletInputZoneRadius,
        })
        and pallet.location == "on_pallet_jack"
        and state.palletJack.carriedPalletId == pallet.id
        and context.PalletState.validate(state))

    local networkState = context.State.new()
    local networkJob = context.jobs.createOffer({
        id = "DOMAIN-NETWORK-JACK", company = "Network Jack Test Co.",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
    })
    context.jobs.accept(networkJob)
    networkState.jobs.active[1] = networkJob
    local networkPallet = networkJob.pallets[1]
    local jack = context.PalletJack.ensure(networkState, context.config.palletJack)
    networkPallet.location, networkPallet.status = "warehouse", "raw"
    networkPallet.world = {
        x = jack.x - 36, y = jack.y,
        fromX = jack.x - 36, fromY = jack.y,
        direction = "northwest", rotation = 1, spawnProgress = 1,
    }

    local mounted, mountCode = context.PalletJack.mount(
        networkState, context.config.palletJack, 2)
    local candidate = context.PalletJack.pickupCandidate(
        networkState, context.config.palletJack, networkPallet.id)
    local networkSnapshot = context.world.networkPalletJackSnapshot(networkState)
    check("domain_network_jack_owner_and_exact_candidate",
        mounted and mountCode == "mounted" and candidate
        and candidate.pallet == networkPallet
        and networkState.palletJack.operatorPlayerId == 2
        and networkSnapshot.operatorPlayerId == 2
        and networkSnapshot.candidatePalletId == networkPallet.id
        and networkSnapshot.frame == nil and networkSnapshot.palletFrame == nil)

    local intruderMounted, intruderCode = context.PalletJack.mount(
        networkState, context.config.palletJack, 3)
    local lifted, liftCode = context.PalletJack.lift(
        networkState, context.config.palletJack, networkPallet.id)
    check("domain_network_jack_rejects_intruder_and_lifts_exact_id",
        not intruderMounted and intruderCode == "busy"
        and lifted and liftCode == "lifted"
        and networkState.palletJack.carriedPalletId == networkPallet.id
        and networkPallet.location == "on_pallet_jack"
        and context.PalletState.validate(networkState))

    local wrongLower, wrongCode = context.PalletJack.lower(
        networkState, context.config.palletJack, function() return true end,
        500, 500, "ANOTHER-PALLET")
    local blockedLower, blockedCode = context.PalletJack.lower(
        networkState, context.config.palletJack, function() return false end,
        500, 500, networkPallet.id)
    check("domain_network_jack_lower_rejections_are_atomic",
        not wrongLower and wrongCode == "wrong_pallet"
        and not blockedLower and blockedCode == "blocked"
        and networkState.palletJack.carriedPalletId == networkPallet.id
        and networkPallet.location == "on_pallet_jack"
        and context.PalletState.validate(networkState))

    local lowered, lowerCode = context.PalletJack.lower(
        networkState, context.config.palletJack,
        function(x, y) return x == 500 and y == 500 end,
        500, 500, networkPallet.id)
    check("domain_network_jack_host_validated_lower_keeps_invariants",
        lowered and lowerCode == "lowered"
        and networkState.palletJack.carriedPalletId == nil
        and networkPallet.location == "warehouse"
        and networkPallet.world.x == 500 and networkPallet.world.y == 500
        and context.PalletState.validate(networkState))

    networkState.palletJack.x, networkState.palletJack.y = 560, 520
    networkPallet.world.x, networkPallet.world.y = 530, 520
    networkPallet.world.fromX, networkPallet.world.fromY = 530, 520
    context.PalletJack.lift(networkState, context.config.palletJack, networkPallet.id)
    local operator = {
        id = 2, x = 0, y = 0, facing = 1,
        animationDistance = 0, idleClock = 0, interactionClock = 0,
    }
    local beforeMove = networkState.palletJack.x
    local ownerUpdated = context.world.updateRemotePlayer(
        operator, 0.10, -1, 0, context.assets, networkState)
    local operatorX, operatorY = context.PalletJack.operatorPosition(
        networkState, context.config.palletJack)
    check("domain_network_jack_owner_input_moves_host_authority_and_attaches_operator",
        ownerUpdated and networkState.palletJack.x < beforeMove
        and operator.x == operatorX and operator.y == operatorY
        and networkPallet.world.x == networkState.palletJack.x
        and networkPallet.world.y == networkState.palletJack.y)

    local parked, parkCode = context.PalletJack.forceRelease(
        networkState, context.config.palletJack, 2)
    check("domain_network_jack_disconnect_parks_loaded_without_dropping",
        parked and parkCode == "parked_loaded"
        and not networkState.palletJack.operating
        and networkState.palletJack.operatorPlayerId == nil
        and networkState.palletJack.carriedPalletId == networkPallet.id
        and networkPallet.location == "on_pallet_jack"
        and context.PalletState.validate(networkState))

    local applied = context.world.applyNetworkPalletJackSnapshot(networkState, {
        x = 540, y = 510, direction = "east", operating = true, moving = false,
        operatorPlayerId = 3, carriedPalletId = networkPallet.id,
    })
    local malformedApplied = context.world.applyNetworkPalletJackSnapshot(networkState, {
        x = 540, y = 510, direction = "east", operating = false, moving = true,
    })
    check("domain_network_jack_snapshot_apply_is_owner_aware_and_strict",
        applied and not malformedApplied
        and networkState.palletJack.operatorPlayerId == 3
        and networkState.palletJack.x == 540 and networkState.palletJack.y == 510)

    context.world.placementSelection = nil
    local placementGrid = context.world.placementGridSnapshot(networkState, context.assets)
    local validPlacement
    for _, cell in ipairs(placementGrid and placementGrid.cells or {}) do
        if cell.valid then validPlacement = cell; break end
    end
    local readOnlyPlacement = validPlacement and context.world.selectPlacement(
        networkState, context.assets, validPlacement.x, validPlacement.y, true)
    check("domain_network_guest_pallet_grid_is_read_only",
        readOnlyPlacement and context.world.placementSelection == nil
        and networkState.message == "The host will validate the highlighted drop cell.")

    local orderingState = context.State.new()
    local orderingJob = context.jobs.createOffer({
        id = "DOMAIN-NETWORK-ORDERING", company = "Packet Order Test Co.",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
    })
    context.jobs.accept(orderingJob)
    orderingState.jobs.active[1] = orderingJob
    local orderingPallet = orderingJob.pallets[1]
    orderingPallet.location, orderingPallet.status = "warehouse", "raw"
    orderingPallet.world = {
        x = 420, y = 420, fromX = 420, fromY = 420,
        direction = "northwest", rotation = 1, spawnProgress = 1,
    }
    local loadedRealtime = {
        x = 500, y = 500, direction = "north", operating = true, moving = false,
        operatorPlayerId = 2, carriedPalletId = orderingPallet.id,
    }
    local earlyApplied, earlyCode = context.world.applyNetworkPalletJackSnapshot(
        orderingState, loadedRealtime)
    local durableLifted = context.PalletState.transition(
        orderingState, orderingPallet, "on_pallet_jack")
    local orderedApplied = context.world.applyNetworkPalletJackSnapshot(
        orderingState, loadedRealtime)
    local durableLowered = context.PalletState.transition(
        orderingState, orderingPallet, "warehouse", {
            world = {
                x = 540, y = 540, fromX = 540, fromY = 540,
                direction = "north", rotation = 1, spawnProgress = 1,
            },
        })
    local staleApplied, staleCode = context.world.applyNetworkPalletJackSnapshot(
        orderingState, loadedRealtime)
    check("domain_network_jack_cross_channel_ordering_waits_for_durable_state",
        not earlyApplied and earlyCode == "awaiting_durable"
        and durableLifted and orderedApplied and durableLowered
        and not staleApplied and staleCode == "awaiting_durable"
        and orderingState.palletJack.carriedPalletId == nil
        and orderingPallet.location == "warehouse"
        and context.PalletState.validate(orderingState))
end

return Test
