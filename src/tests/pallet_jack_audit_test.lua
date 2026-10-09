local Test = {}
local Config = require("src.config")
local Jack = require("src.pallet_jack")
local State = require("src.state")
local Jobs = require("src.jobs")
local World = require("src.world")

local function fixture(owner)
    local state = State.new()
    state.palletJack.x, state.palletJack.y = 500, 500
    state.palletJack.direction = "east"
    assert(Jack.mount(state, Config.palletJack, owner or 1))
    local job = Jobs.createOffer({ id = "JACK-AUDIT", company = "Jack Audit",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500, 500, 500 } })
    Jobs.accept(job)
    state.jobs.active[1] = job
    for index, pallet in ipairs(job.pallets) do
        pallet.location, pallet.status = "warehouse", "raw"
        pallet.world = { x = 500 + index * 10, y = 500, fromX = 500 + index * 10,
            fromY = 500, direction = "east", rotation = 2, spawnProgress = 1 }
    end
    return state, job.pallets
end

local function drive(state, x, y)
    for _ = 1, 30 do
        Jack.move(state, x, y, 1 / 60, Config.palletJack, function() return true end)
    end
end

local function snapshot(state, owner, direction)
    return { x = state.palletJack.x, y = state.palletJack.y,
        direction = direction or "east", operating = owner ~= nil,
        moving = false, operatorPlayerId = owner }
end

local function checkLocalRelocation(check)
    local Machine, Wrapper = require("src.machine"), require("src.wrapper")
    local Assets = require("src.assets")
    for _, spec in ipairs({
        { "cutter", "beginCutterMove", "rotateCutter" },
        { "wrapper", "beginWrapperMove", "rotateWrapper" },
        { "windmill", "beginWindmillMove", "rotateWindmill" },
    }) do
        local state = State.new()
        Machine.reset(state)
        Wrapper.reset(state)
        if spec[1] == "windmill" then
            state.money = 100000
            assert(require("src.machine_fleet").buy(state, "dealer", 3))
        end
        local machine = state[spec[1]]
        World.load()
        World.player.id = 1
        state.palletJack.x, state.palletJack.y = machine.x, machine.y
        assert(Jack.mount(state, Config.palletJack, 1))
        Jack.move(state, 1, 0, .1, Config.palletJack, function() return true end)
        local approachDistance = Jack.animationDistance(state, Config.palletJack)
        assert(World[spec[2]](state))
        local attachedX, attachedY = state.palletJack.x, state.palletJack.y
        Jack.move(state, 0, 0, .1, Config.palletJack, function() return true end)
        check("jack_local_" .. spec[1] .. "_attachment_stops_approach_momentum",
            not state.palletJack.moving and state.palletJack.x == attachedX
            and state.palletJack.y == attachedY
            and Jack.animationDistance(state, Config.palletJack) == approachDistance)
        World.update(.1, 1, 0, Assets, state)
        local distance = state.palletJack.x - attachedX
        check("jack_local_" .. spec[1] .. "_gait_tracks_machine_travel",
            distance > 0 and math.abs(Jack.animationDistance(state, Config.palletJack)
                - approachDistance - distance) < .0001)
        assert(World[spec[3]](state))
        local operatorX, operatorY = Jack.operatorPosition(state, Config.palletJack)
        check("jack_local_" .. spec[1] .. "_rotation_keeps_operator_at_handle",
            state.palletJack.direction == machine.direction and not state.palletJack.moving
            and World.player.x == operatorX and World.player.y == operatorY)
    end
end

local function checkClientUpdate(check)
    local state = fixture(2)
    local actor, localPlayer = { id = 2 }, { id = 3 }
    local client = {
        state = state, Config = Config, PalletJack = Jack,
        World = { player = localPlayer, updatePalletJackPresentation = World.updatePalletJackPresentation },
        handleMultiplayerEvents = function() end,
        multiplayer = { isActive = function() return true end, isHost = function() return false end,
            isClient = function() return true end, update = function() end,
            ballSnapshot = function() return {} end,
            highFiveAnimationFor = function() end, remotePlayers = function() return { actor } end },
    }
    require("src.runtime.multiplayer_update").install(client)
    assert(Jack.applySnapshot(state, snapshot(state, 2, "north"), Config.palletJack))
    state.screen = "computer"
    client.updateMultiplayer(1 / 60, 0, 0)
    local first = Jack.visualPose(state, Config.palletJack)
    check("jack_client_update_advances_observer_even_in_menu", first.heading ~= 0
        and actor.x == first.x + first.operatorX and actor.y == first.y + first.operatorY)
    client.updateMultiplayer(1 / 60, 0, 0, 2)
    check("jack_client_update_does_not_double_advance_predicted_turn",
        Jack.visualPose(state, Config.palletJack).heading == first.heading)
    localPlayer.id = 2
    client.updateMultiplayer(1 / 60, 0, 0)
    local nextPose = Jack.visualPose(state, Config.palletJack)
    check("jack_client_update_aligns_local_operator_after_snapshot",
        localPlayer.x == nextPose.x + nextPose.operatorX and localPlayer.y == nextPose.y + nextPose.operatorY)
end

function Test.run(_, check)
    local reserved, pallets = fixture()
    reserved.employment.staff = {{ id = "WORKER-AUDIT", name = "Audit Worker",
        visible = true, reserved = true,
        assignment = { machineId = "MCH-0001", palletId = pallets[1].id } }}
    local candidate = Jack.pickupCandidate(reserved, Config.palletJack)
    check("jack_pickup_skips_nearest_employee_reserved_pallet",
        candidate and candidate.pallet == pallets[2])
    local lifted, reason = Jack.lift(reserved, Config.palletJack, pallets[1].id)
    check("jack_explicit_reserved_pickup_has_clear_reason",
        not lifted and reason == "employee_reserved" and not reserved.palletJack.carriedPalletId)

    local stacked, stackPallets = fixture()
    stackPallets[3].location = "stacked"
    stackPallets[3].storage = { supportPalletId = stackPallets[1].id, level = 2 }
    stackPallets[3].world.x = stackPallets[1].world.x
    stackPallets[3].world.fromX = stackPallets[1].world.x
    check("jack_stack_fixture_is_valid", require("src.pallet_state").validate(stacked))
    local available = Jack.pickupCandidate(stacked, Config.palletJack)
    check("jack_pickup_skips_supporting_pallet_and_upper_stack",
        available and available.pallet == stackPallets[2])
    local baseLifted, baseReason = Jack.lift(stacked, Config.palletJack, stackPallets[1].id)
    check("jack_supporting_pallet_pickup_has_clear_reason",
        not baseLifted and baseReason == "supporting_pallet")
    local used = Jack.use(stacked, Config.palletJack, function() return true end)
    check("jack_use_lifts_next_available_pallet", used
        and stacked.palletJack.carriedPalletId == stackPallets[2].id)

    local owned, ownedPallets = fixture(2)
    local intruderUsed, intruderReason = Jack.use(owned, Config.palletJack,
        function() return true end, nil, nil, 3)
    check("jack_non_owner_cannot_use_to_lift", not intruderUsed and intruderReason == "not_owner"
        and not owned.palletJack.carriedPalletId and owned.palletJack.operatorPlayerId == 2)
    assert(Jack.lift(owned, Config.palletJack, ownedPallets[1].id))
    local intruderLowered = Jack.use(owned, Config.palletJack,
        function() return true end, 550, 500, 3)
    check("jack_non_owner_cannot_use_to_lower", not intruderLowered
        and owned.palletJack.carriedPalletId == ownedPallets[1].id)
    assert(Jack.lower(owned, Config.palletJack, function() return true end, 800, 800))
    owned.palletJack.x = 900
    local intruderParked = Jack.use(owned, Config.palletJack, nil, nil, nil, 3)
    check("jack_non_owner_cannot_use_to_park", not intruderParked and owned.palletJack.operating)

    local moving = fixture()
    drive(moving, 1, 0)
    local handoff = snapshot(moving, 2, "north")
    assert(Jack.applySnapshot(moving, handoff, Config.palletJack))
    local pose = Jack.visualPose(moving, Config.palletJack)
    check("jack_new_owner_snapshot_starts_at_current_heading",
        math.abs(pose.heading - math.pi * 1.5) < .0001)
    Jack.move(moving, 0, 0, .1, Config.palletJack, function() return true end)
    check("jack_snapshot_handoff_clears_previous_owner_momentum",
        moving.palletJack.x == handoff.x and moving.palletJack.y == handoff.y
        and not moving.palletJack.moving)

    drive(moving, 1, 0)
    local teleport = snapshot(moving, 2, "west")
    teleport.x = teleport.x + 200
    assert(Jack.applySnapshot(moving, teleport, Config.palletJack))
    Jack.move(moving, 0, 0, .1, Config.palletJack, function() return true end)
    check("jack_snapshot_relocation_does_not_inherit_motion_or_stride",
        moving.palletJack.x == teleport.x and Jack.animationDistance(moving, Config.palletJack) == 0)
    local invalid = snapshot(moving, 2)
    invalid.x = math.huge
    local invalidApplied = Jack.applySnapshot(moving, invalid, Config.palletJack)
    check("jack_nonfinite_snapshot_rejected_atomically",
        not invalidApplied and moving.palletJack.x == teleport.x)

    local observer = fixture(2)
    local turn = snapshot(observer, 2, "north")
    turn.moving = true
    assert(Jack.applySnapshot(observer, turn, Config.palletJack))
    local actor = { id = 2, x = 0, y = 0 }
    local beforeHeading = Jack.visualPose(observer, Config.palletJack).heading
    World.updatePalletJackPresentation(observer, 1 / 60, { actor })
    local afterHeading = Jack.visualPose(observer, Config.palletJack).heading
    local operatorX, operatorY = Jack.operatorPosition(observer, Config.palletJack)
    check("jack_observer_turn_advances_without_changing_authoritative_position",
        math.abs(afterHeading - beforeHeading) > .01
        and math.abs(afterHeading - beforeHeading) <= Config.palletJack.turnRadiansPerSecond / 60 + .0001
        and observer.palletJack.x == turn.x and observer.palletJack.y == turn.y)
    check("jack_observer_operator_tracks_interpolated_handle",
        actor.x == operatorX and actor.y == operatorY and actor.moving)
    for _ = 1, 20 do World.updatePalletJackPresentation(observer, 1 / 60, { actor }) end
    check("jack_observer_turn_finishes_at_snapshot_heading",
        math.abs(math.sin(Jack.visualPose(observer, Config.palletJack).heading) + 1) < .0001)

    local stopped = fixture()
    drive(stopped, 1, 0)
    local stopX, stopY = stopped.palletJack.x, stopped.palletJack.y
    Jack.stop(stopped, Config.palletJack)
    Jack.move(stopped, 0, 0, .1, Config.palletJack, function() return true end)
    check("jack_explicit_stop_clears_inertia", stopped.palletJack.x == stopX
        and stopped.palletJack.y == stopY and not stopped.palletJack.moving)

    local shared, uninterrupted = State.new(), State.new()
    for _, state in ipairs({ shared, uninterrupted }) do
        Jack.mount(state, Config.palletJack, 2)
        Jack.move(state, 1, 0, .1, Config.palletJack, function() return true end)
    end
    local sharedPose = Jack.visualPose(shared, Config.palletJack)
    local durable = require("src.save_schema").snapshot(shared)
    assert(State.applySharedUpdate(shared, durable))
    local restoredPose = Jack.visualPose(shared, Config.palletJack)
    check("jack_durable_refresh_preserves_turn_and_stride",
        restoredPose.heading == sharedPose.heading and restoredPose.distance == sharedPose.distance)
    for _, state in ipairs({ shared, uninterrupted }) do
        Jack.move(state, 0, 0, 1 / 60, Config.palletJack, function() return true end)
    end
    check("jack_durable_refresh_preserves_predicted_braking",
        shared.palletJack.x == uninterrupted.palletJack.x
        and shared.palletJack.y == uninterrupted.palletJack.y)
    checkClientUpdate(check)
    checkLocalRelocation(check)
end

return Test
