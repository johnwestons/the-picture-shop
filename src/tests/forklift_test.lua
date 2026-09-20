local Test = {}
local Forklift = require("src.forklift")

local config = { spawnX = 0, spawnY = 0, speed = 100, loadedSpeed = 50,
    liftDuration = 4, lowerDuration = 2, travelHeight = 0.08, maxStepDistance = 2 }
local function near(a, b) return math.abs(a - b) < 0.000001 end
local function free() return true end
local function fresh(mounted)
    local state = { forklift = Forklift.defaultState(config) }
    state.forklift.owned = true
    if mounted ~= false then assert(Forklift.acquire(state, config, 1)) end
    return state
end
local function clone(value)
    local result = {}
    for key, item in pairs(value) do result[key] = item end
    return result
end

function Test.run(_, check)
    local function test(name, condition) check("forklift_" .. name, condition) end
    local state = { forklift = Forklift.defaultState(config) }
    test("default_unowned_parked_valid", Forklift.validState(state.forklift, config)
        and not state.forklift.owned and state.forklift.forkHeight == 0
        and not state.forklift.operating and Forklift.obstacle(state, config) == nil)
    local ok, code = Forklift.acquire(state, config, 1)
    test("unowned_cannot_acquire", not ok and code == "not_owned")
    state = fresh(false)
    for index, bad in ipairs({ 0, 5, 1.5, math.huge, 0 / 0, "1", false }) do
        test("invalid_operator_" .. index, not Forklift.acquire(state, config, bad))
    end
    test("acquire_owned", Forklift.acquire(state, config, 2)
        and Forklift.isOperator(state, config, 2))
    ok, code = Forklift.acquire(state, config, 2)
    test("repeat_acquire_idempotent", ok and code == "already_mounted")
    ok, code = Forklift.acquire(state, config, 3)
    test("second_operator_rejected", not ok and code == "busy"
        and state.forklift.operatorPlayerId == 2)
    test("wrong_operator_cannot_release", not Forklift.release(state, config, 3))
    test("wrong_operator_cannot_drive", not Forklift.move(state, 1, 0, 1, config, free, 3))
    test("wrong_operator_cannot_raise", not Forklift.setForkHeight(state, config, 3, 1))
    test("release_at_ground", Forklift.release(state, config, 2) and not state.forklift.operating)
    state.palletJack = { operating = true, operatorPlayerId = 1 }
    ok, code = Forklift.acquire(state, config, 1)
    test("operator_cannot_occupy_two_vehicles", not ok and code == "already_operating_vehicle")
    state.forklift.operating, state.forklift.operatorPlayerId = true, 1
    ok, code = Forklift.acquire(state, config, 1)
    test("repeat_acquire_cannot_bypass_conflicting_seat", not ok
        and code == "already_operating_vehicle"
        and state.forklift.operatorPlayerId == 1 and state.palletJack.operatorPlayerId == 1)

    local names = { "northwest", "north", "northeast", "east",
        "southeast", "south", "southwest", "west" }
    local vectors = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { 1, 0 },
        { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 } }
    for index, vector in ipairs(vectors) do
        state = fresh()
        local moved, _, distance = Forklift.move(state, vector[1], vector[2], 1, config, free, 1)
        test("heading_" .. names[index], moved and state.forklift.direction == names[index]
            and Forklift.frame(state, config) == index and near(distance, 100)
            and near(math.sqrt(state.forklift.x ^ 2 + state.forklift.y ^ 2), 100))
    end
    test("small_off_axis_input_keeps_cardinal_sector",
        Forklift.directionFor(1, 0.01) == "east"
        and Forklift.directionFor(-0.01, -1) == "north")
    test("zero_input_keeps_heading", Forklift.directionFor(0, 0, "southwest") == "southwest")
    state = fresh()
    Forklift.move(state, 0.5, 0, 1, config, free, 1)
    test("analog_strength_preserved", near(state.forklift.x, 50))
    test("collision_callback_required", not Forklift.move(state, 1, 0, 1, config, nil, 1))
    local xBefore = state.forklift.x
    Forklift.move(state, 1, 0, 1, config, function() return false end, 1)
    test("blocked_movement_stops_without_animation", state.forklift.x == xBefore
        and not state.forklift.moving and near(state.forklift.animationDistance, 50))
    state = fresh()
    local calls = 0
    Forklift.move(state, 1, 0, 1, config, function(x)
        calls = calls + 1
        return x < 9
    end, 1)
    test("collision_substeps_prevent_tunneling", calls == 5 and near(state.forklift.x, 8))
    test("moving_cannot_dismount", not Forklift.release(state, config, 1))
    test("moving_cannot_start_raise", not Forklift.setForkHeight(state, config, 1, 1))
    Forklift.move(state, 0, 0, 0.1, config, free, 1)
    test("stopped_can_dismount", Forklift.release(state, config, 1))
    local whole, split = fresh(), fresh()
    Forklift.move(whole, 1, 1, 1, config, free, 1)
    for _ = 1, 10 do Forklift.move(split, 1, 1, 0.1, config, free, 1) end
    test("movement_dt_partition", near(whole.forklift.x, split.forklift.x)
        and near(whole.forklift.y, split.forklift.y)
        and near(whole.forklift.animationDistance, split.forklift.animationDistance))

    state = fresh()
    test("raise_target_starts_without_teleport", Forklift.setForkHeight(state, config, 1, 1)
        and state.forklift.forkHeight == 0 and state.forklift.lifting)
    Forklift.update(state, 1, config)
    test("raising_interpolates_height", near(state.forklift.forkHeight, 0.25))
    local heightBefore = state.forklift.forkHeight
    ok, code = Forklift.setForkHeight(state, config, 1, 1)
    test("repeat_target_does_not_restart", ok and code == "already_targeted"
        and state.forklift.forkHeight == heightBefore)
    test("cannot_drive_during_lift", not Forklift.move(state, 1, 0, 1, config, free, 1))
    test("cannot_dismount_during_lift", not Forklift.release(state, config, 1))
    Forklift.update(state, 3, config)
    test("full_raise_exact_duration", state.forklift.forkHeight == 1 and not state.forklift.lifting)
    test("cannot_drive_when_raised_and_settled", not Forklift.move(state, 1, 0, 1, config, free, 1))
    test("cannot_dismount_when_raised_and_settled", not Forklift.release(state, config, 1))
    Forklift.setForkHeight(state, config, 1, 0)
    Forklift.update(state, 1, config)
    test("lowering_uses_own_duration", near(state.forklift.forkHeight, 0.5))
    Forklift.setForkHeight(state, config, 1, 1)
    test("lift_reversal_preserves_current_height", near(state.forklift.forkHeight, 0.5))
    Forklift.update(state, 1, config)
    test("reversal_progress_from_current_height", near(state.forklift.forkHeight, 0.75))
    Forklift.update(state, 100, config)
    test("large_update_saturates_not_overshoots", state.forklift.forkHeight == 1)
    whole, split = fresh(), fresh()
    Forklift.setForkHeight(whole, config, 1, 1)
    Forklift.setForkHeight(split, config, 1, 1)
    Forklift.update(whole, 2.8, config)
    for _ = 1, 28 do Forklift.update(split, 0.1, config) end
    test("lift_dt_partition", near(whole.forklift.forkHeight, split.forklift.forkHeight))
    for index, bad in ipairs({ -1, 1.1, math.huge, -math.huge, 0 / 0, "1" }) do
        test("invalid_height_" .. index, not Forklift.setForkHeight(state, config, 1, bad)
            and state.forklift.forkHeight == 1)
    end
    for index, bad in ipairs({ -1, math.huge, 0 / 0, "1" }) do
        test("invalid_dt_" .. index, not Forklift.update(state, bad, config))
    end

    state = fresh()
    local transfers = 0
    local function transfer(id, operation, view)
        transfers = transfers + 1
        return id == "P-1" and operation == "attach" and view.carriedPalletId == nil
    end
    test("cargo_requires_authoritative_transfer",
        not Forklift.attachCargo(state, config, 1, "P-1", nil))
    test("cargo_failed_transfer_atomic", not Forklift.attachCargo(state, config, 1, "P-1",
        function() return false, "occupied" end) and state.forklift.carriedPalletId == nil)
    state.palletJack = { carriedPalletId = "P-1" }
    test("cargo_cannot_duplicate_jack", not Forklift.attachCargo(state, config, 1, "P-1", transfer)
        and transfers == 0)
    state.palletJack.carriedPalletId = nil
    test("cargo_claim_exact_id", Forklift.attachCargo(state, config, 1, "P-1", transfer)
        and state.forklift.carriedPalletId == "P-1" and transfers == 1)
    test("cargo_repeat_claim_no_second_transfer",
        not Forklift.attachCargo(state, config, 1, "P-1", transfer) and transfers == 1)
    test("cargo_other_claim_rejected", not Forklift.attachCargo(state, config, 1, "P-2", transfer))
    test("loaded_ground_cannot_drag", not Forklift.move(state, 1, 0, 1, config, free, 1))
    Forklift.setForkHeight(state, config, 1, config.travelHeight)
    Forklift.update(state, config.liftDuration * config.travelHeight, config)
    test("travel_height_reached", near(state.forklift.forkHeight, 0.08) and not state.forklift.lifting)
    Forklift.move(state, 1, 0, 1, config, free, 1)
    test("loaded_driving_speed", near(state.forklift.x, 50))
    test("moving_cargo_transfer_rejected", not Forklift.detachCargo(state, config, 1, "P-1", free))
    Forklift.move(state, 0, 0, 0.1, config, free, 1)
    Forklift.setForkHeight(state, config, 1, 1)
    Forklift.update(state, 1, config)
    heightBefore = state.forklift.forkHeight
    test("lifting_cargo_transfer_rejected", not Forklift.detachCargo(state, config, 1, "P-1", free))
    test("disconnect_wrong_owner_rejected", not Forklift.forceRelease(state, config, 2))
    test("disconnect_retains_suspended_cargo", Forklift.forceRelease(state, config, 1)
        and state.forklift.carriedPalletId == "P-1"
        and state.forklift.forkHeight == heightBefore
        and state.forklift.targetForkHeight == heightBefore
        and not state.forklift.lifting and not state.forklift.operating)
    Forklift.update(state, 100, config)
    test("unattended_forks_do_not_animate", state.forklift.forkHeight == heightBefore)
    test("another_operator_can_recover", Forklift.acquire(state, config, 3))
    Forklift.setForkHeight(state, config, 3, 0)
    Forklift.update(state, 2, config)
    test("recovered_load_lowered", state.forklift.forkHeight == 0
        and state.forklift.carriedPalletId == "P-1")
    test("wrong_pallet_cannot_detach", not Forklift.detachCargo(state, config, 3, "P-2", free))
    test("rejected_detach_retains_cargo", not Forklift.detachCargo(state, config, 3, "P-1",
        function() return false, "blocked" end) and state.forklift.carriedPalletId == "P-1")
    test("cargo_detach_exact_id", Forklift.detachCargo(state, config, 3, "P-1", free)
        and state.forklift.carriedPalletId == nil)
    test("cargo_repeat_detach_rejected", not Forklift.detachCargo(state, config, 3, "P-1", free))

    state = fresh()
    local snapshot = Forklift.snapshot(state, config)
    test("snapshot_is_detached_copy", snapshot ~= state.forklift and Forklift.validState(snapshot, config))
    state.palletJack = { operating = true, operatorPlayerId = 1 }
    local liftBefore, jackBefore = state.forklift, state.palletJack
    local conflicting = clone(snapshot)
    conflicting.x = snapshot.x + 25
    ok, code = Forklift.applySnapshot(state, conflicting, config)
    test("snapshot_conflicting_operator_refused_without_mutation", not ok
        and code == "operator_conflict" and state.forklift == liftBefore
        and state.palletJack == jackBefore and state.forklift.x == snapshot.x
        and state.palletJack.operatorPlayerId == 1)
    state.palletJack.operatorPlayerId = 2
    test("snapshot_different_vehicle_operators_allowed", Forklift.applySnapshot(state, snapshot, config)
        and state.forklift.operatorPlayerId == 1 and state.palletJack.operatorPlayerId == 2)
    for index, key in ipairs({ "x", "y", "forkHeight", "targetForkHeight", "animationDistance" }) do
        for badIndex, bad in ipairs({ 0 / 0, math.huge, -math.huge, "0" }) do
            local invalid = clone(snapshot)
            invalid[key] = bad
            test("finite_snapshot_" .. index .. "_" .. badIndex,
                not Forklift.validState(invalid, config) and not Forklift.applySnapshot(state, invalid, config))
        end
    end
    local invalid = clone(snapshot)
    invalid.operatorPlayerId = 4.5
    test("fractional_snapshot_owner_rejected", not Forklift.validState(invalid, config))
    invalid = clone(snapshot)
    invalid.carriedPalletId = string.rep("x", 129)
    test("oversized_snapshot_pallet_rejected", not Forklift.validState(invalid, config))
    invalid = clone(snapshot)
    invalid.operating, invalid.moving, invalid.operatorPlayerId = false, true, nil
    test("parked_moving_snapshot_rejected", not Forklift.validState(invalid, config))
    invalid = clone(snapshot)
    invalid.forkHeight, invalid.targetForkHeight, invalid.moving = 1, 1, true
    test("elevated_driving_snapshot_rejected", not Forklift.validState(invalid, config))
    invalid = clone(snapshot)
    invalid.owned = false
    test("unowned_operator_snapshot_rejected", not Forklift.validState(invalid, config))
    snapshot.carriedPalletId = "P-SNAPSHOT"
    local before = state.forklift
    ok, code = Forklift.applySnapshot(state, snapshot, config)
    test("realtime_cargo_waits_for_durable", not ok and code == "awaiting_durable"
        and state.forklift == before and state.forklift.carriedPalletId == nil)
    state.jobs = { active = { { pallets = { { id = "P-SNAPSHOT", location = "on_forklift" } } } } }
    test("matching_durable_snapshot_applies", Forklift.applySnapshot(state, snapshot, config)
        and state.forklift.carriedPalletId == "P-SNAPSHOT")
    snapshot.carriedPalletId = nil
    ok, code = Forklift.applySnapshot(state, snapshot, config)
    test("old_snapshot_cannot_drop_durable_cargo", not ok and code == "awaiting_durable"
        and state.forklift.carriedPalletId == "P-SNAPSHOT")
    state.jobs.active[1].pallets[2] = { id = "P-DUPLICATE", location = "on_forklift" }
    snapshot.carriedPalletId = "P-SNAPSHOT"
    test("duplicate_durable_custody_rejected", not Forklift.applySnapshot(state, snapshot, config))

    state = { forklift = Forklift.defaultState(config), warehouse = { forkliftOwned = false } }
    local materialized = Forklift.defaultState(config)
    materialized.owned, materialized.x = true, 25
    before = state.forklift
    ok, code = Forklift.applySnapshot(state, materialized, config)
    test("realtime_cannot_materialize_before_durable_purchase", not ok and code == "awaiting_durable"
        and state.forklift == before and not state.forklift.owned and state.forklift.x == 0)
    state.warehouse.forkliftOwned = true
    ok, code = Forklift.applySnapshot(state, materialized, config)
    test("paid_entitlement_still_waits_for_durable_spawn", not ok and code == "awaiting_durable"
        and state.forklift == before and not state.forklift.owned)
    state.forklift.owned = true
    test("realtime_applies_after_durable_materialization", Forklift.applySnapshot(state, materialized, config)
        and state.forklift.owned and state.forklift.x == 25)
    local revoked = Forklift.defaultState(config)
    before = state.forklift
    ok, code = Forklift.applySnapshot(state, revoked, config)
    test("realtime_cannot_revoke_durable_vehicle", not ok and code == "awaiting_durable"
        and state.forklift == before and state.forklift.owned and state.forklift.x == 25)
    state.forklift = Forklift.defaultState(config)
    state.warehouse.forkliftOwned = false
    test("realtime_applies_after_durable_revocation", Forklift.applySnapshot(state, revoked, config)
        and not state.forklift.owned)
    state = fresh(false)
    state.warehouse = { forkliftOwned = false }
    before = state.forklift
    ok, code = Forklift.applySnapshot(state, materialized, config)
    test("owned_snapshot_requires_present_paid_entitlement", not ok and code == "awaiting_durable"
        and state.forklift == before and state.forklift.x == 0)
    state.warehouse = nil
    test("standalone_owned_fixture_needs_no_warehouse", Forklift.applySnapshot(state, materialized, config)
        and state.forklift.owned and state.forklift.x == 25)
    state = { forklift = { owned = "true" } }
    before = state.forklift
    ok, code = Forklift.applySnapshot(state, materialized, config)
    test("invalid_durable_ownership_not_repaired_by_realtime", not ok and code == "invalid_state"
        and state.forklift == before and state.forklift.owned == "true")

    local normalized = Forklift.normalize({ owned = true, x = math.huge, y = 0 / 0,
        forkHeight = 0.65, targetForkHeight = 1, lifting = true, operating = false,
        carriedPalletId = "P-RECOVER", moving = true, direction = "bad" }, config)
    test("normalize_invalid_coordinates_safely", normalized.x == 0 and normalized.y == 0
        and normalized.direction == "northwest" and Forklift.validState(normalized, config))
    test("normalize_parked_retains_height_and_cargo", normalized.forkHeight == 0.65
        and normalized.targetForkHeight == 0.65 and normalized.carriedPalletId == "P-RECOVER"
        and not normalized.lifting and not normalized.moving)
    state = fresh()
    local obstacle = Forklift.obstacle(state, config)
    test("operated_vehicle_still_has_collision_obstacle", obstacle and obstacle.halfWidth > 0)
    state.forklift.direction = "southeast"
    local dropX, dropY = Forklift.dropPosition(state, config)
    test("drop_anchor_tracks_fork_heading", dropX > state.forklift.x and dropY > state.forklift.y)
    local PalletJack = require("src.pallet_jack")
    local Config = require("src.config")
    state = fresh()
    local beforeLift = clone(state.forklift)
    local mounted, mountedCode = PalletJack.mount(state, Config.palletJack, 1)
    test("jack_mount_cannot_claim_active_forklift_operator", not mounted
        and mountedCode == "operating_forklift" and not state.palletJack.operating
        and state.forklift.operatorPlayerId == beforeLift.operatorPlayerId)
    test("different_worker_can_mount_jack_while_forklift_in_use", PalletJack.mount(state,Config.palletJack,2)
        and state.palletJack.operatorPlayerId == 2 and state.forklift.operatorPlayerId == 1)
end

return Test
