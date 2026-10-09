local Fleet = require("src.machine_fleet")
local SaveSchema = require("src.save_schema")
local Rooms = require("src.shop_rooms")
local Test = {}
local kinds = { "cutter", "wrapper", "windmill" }

local function fixture(context, index, channel)
    local state = context.State.new()
    state.screen, state.money = "world", 1000000
    if index == 3 then assert(Fleet.buy(state, "dealer", 3)) end
    local bought, unit = Fleet.buy(state, channel, index)
    assert(bought)
    if channel == "online" then
        local received
        received, unit = Fleet.unloadDelivery(state, unit.id, unit.machineId, 1)
        assert(received)
    end
    assert(unit.world)
    if index == 1 then context.machine.forId(unit.id).reset(state) end
    if index == 2 then context.wrapper.forId(unit.id).reset(state) end
    local jack = context.PalletJack.ensure(state, context.config.palletJack)
    jack.x, jack.y, jack.direction = unit.world.x, unit.world.y + 8, unit.world.direction
    assert(context.PalletJack.mount(state, context.config.palletJack, 1))
    local x, y = context.PalletJack.operatorPosition(state, context.config.palletJack)
    context.world.load({ id = 1, x = x, y = y, sceneId = "warehouse", character = "rabbit-worker" })
    context.world.update(0, 0, 0, context.assets, state, unit.world.x, unit.world.y)
    return state, unit
end

local function capture(context, state, name)
    local directory = os.getenv("PICTURE_SHOP_MACHINE_TRANSPORT_CAPTURE_DIR")
    if not directory then return end
    local canvas = love.graphics.newCanvas(context.config.baseWidth, context.config.baseHeight)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    context.world.draw(context.assets, context.characterAssets, state)
    love.graphics.pop()
    local pixels = canvas:newImageData()
    local encoded = pixels:encode("png")
    local file = assert(io.open(directory .. "/" .. name .. ".png", "wb"))
    file:write(encoded:getString())
    file:close()
    encoded:release()
    pixels:release()
    canvas:release()
end

local function controlLoop(context, check, index, channel)
    local state, unit = fixture(context, index, channel)
    local kind, pose = kinds[index], unit.world
    local prefix = "purchased_machine_" .. kind .. "_" .. channel .. "_"
    local original = { x = state[kind].x, y = state[kind].y, direction = state[kind].direction }
    local before = { x = pose.x, y = pose.y, direction = pose.direction }
    local selected = context.world.interactionAt(pose.x, pose.y)
    check(prefix .. "target_is_exact_owned_unit",
        selected and selected.target.machineId == unit.id and selected.target.relocatable ~= false)
    local nearest = context.world.nearbyMachineMove(state)
    check(prefix .. "move_action_resolves_nearest_unit", nearest and nearest.target.machineId == unit.id)
    local input, saves = {}, 0
    for key, value in pairs(context.inputContext) do input[key] = value end
    input.state, input.isNetworkClient = state, function() return false end
    input.saveCurrent = function() saves = saves + 1 end
    local mobile = { state = state, World = context.world,
        warehouseControls = { ownsLift = function() return false end },
        multiplayer = { isClient = function() return false end } }
    require("src.runtime.keyboard_mobile").install(mobile)
    local function hasAction(actions, key)
        for _, action in ipairs(actions) do if action.key == key then return true end end
        return false
    end
    -- The jack is often the selected target while driving, so MOVE also needs
    -- to find the nearby purchased unit without a hovered machine target.
    context.world.selectedInteraction = { kind = "palletJack", target = {} }
    check(prefix .. "mobile_host_move_button_available", hasAction(mobile.extraMobileActions(), "m"))
    state.palletJack.operatorPlayerId, context.world.player.id = 2, 2
    mobile.multiplayer = { isClient = function() return true end,
        workshopInfo = function() return { resourceId = "pallet_jack" } end }
    check(prefix .. "mobile_guest_move_button_available", hasAction(mobile.extraMobileActions(), "m"))
    state.palletJack.operatorPlayerId, context.world.player.id = 1, 1
    mobile.multiplayer.isClient = function() return false end
    context.world.selectedInteraction = selected
    context.input.keypressed("q", input)
    check(prefix .. "turning_unattached_unit_cannot_rotate_original",
        state[kind].direction == original.direction and pose.direction == before.direction and saves == 0)
    context.world.selectedInteraction = { kind = ({"cutter","skidWrapper","windmill"})[index],
        target = { machineId = Fleet.installedUnits(state, unit.modelId)[1].id }, hovered = false }
    context.input.keypressed("m", input)
    check(prefix .. "move_key_lifts_purchased_unit",
        pose.moving and not state[kind].moving and context.world.movingMachine(state) == kind,
        state.message)
    local key, label = mobile.primaryMobileAction()
    check(prefix .. "mobile_place_and_turn_buttons_available",
        key == "e" and label == "PLACE" and hasAction(mobile.extraMobileActions(), "q"))
    check(prefix .. "attached_machine_suppresses_pallet_pickup",
        context.world.palletPickupSnapshot(state).selected == nil
        and context.world.networkPalletJackSnapshot(state).candidatePalletId == nil)
    local sold = Fleet.sell(state, unit.id, "online")
    check(prefix .. "cannot_sell_while_attached", not sold)
    check(prefix .. "cannot_operate_while_attached", not Fleet.canOperate(state, unit.modelId, unit.id))
    check(prefix .. "original_remains_a_placement_obstacle",
        not context.world.isPalletPlacementClear(state, context.assets, original.x, original.y))
    context.world.update(0.2, 1, 0, context.assets, state)
    check(prefix .. "jack_drives_attached_unit", pose.x ~= before.x or pose.y ~= before.y)
    context.input.keypressed("q", input)
    check(prefix .. "turn_key_rotates_purchased_unit", pose.direction ~= before.direction)
    local snapshot = assert(SaveSchema.snapshot(state))
    local committed = Fleet.byId(snapshot, unit.id).world
    check(prefix .. "save_during_transport_retains_committed_position",
        committed.x == before.x and committed.y == before.y and committed.direction == before.direction
        and not committed.moving and not committed.inMotion and committed._relocationOrigin == nil)
    local roomPlayer = { id = 1, x = Rooms.roomEntrance.x, y = Rooms.roomEntrance.y, sceneId = "warehouse" }
    local entered, entryCode = Rooms.transition(roomPlayer, state, "front_left")
    check(prefix .. "cannot_carry_machine_into_another_room", not entered and entryCode == "park_first")
    capture(context, state, kind .. "-" .. channel .. "-carrying")
    local grid = context.world.placementGridSnapshot(state, context.assets)
    local cell = grid and grid.selected
    if not cell then
        for _, candidate in ipairs(grid and grid.cells or {}) do if candidate.valid then cell = candidate; break end end
    end
    check(prefix .. "has_valid_placement_cell", cell ~= nil)
    context.world.selectPlacement(state, context.assets, cell.x, cell.y)
    context.input.keypressed("e", input)
    check(prefix .. "place_key_commits_exact_unit",
        not pose.moving and pose.x == cell.x and pose.y == cell.y and pose._relocationOrigin == nil
        and saves == 3, state.message)
    check(prefix .. "original_machine_never_moves",
        state[kind].x == original.x and state[kind].y == original.y
        and state[kind].direction == original.direction and not state[kind].moving)
    local payload, resumed = SaveSchema.newPayload(1, 1), context.State.new()
    payload.state = assert(SaveSchema.snapshot(state))
    local loaded = context.State.applyLocalSave(resumed, payload)
    local restored = Fleet.byId(resumed, unit.id)
    check(prefix .. "placed_position_survives_reload",
        loaded and restored and restored.world.x == pose.x and restored.world.y == pose.y
        and restored.world.direction == pose.direction and not restored.world.moving)
    capture(context, state, kind .. "-" .. channel .. "-placed")
    context.world.releaseNetworkPalletJack(context.world.player, state, true)
end

local function guards(context, check)
    local state, unit = fixture(context, 1, "dealer")
    local worker = context.world.player
    local attached, code = context.world.beginNetworkMachineMove(worker, state, 2, false, unit.id)
    check("purchased_machine_rejects_wrong_model_id", not attached and code == "machine_unavailable")
    attached, code = context.world.beginNetworkMachineMove(worker, state, 1, true, unit.id)
    check("purchased_machine_rejects_occupied_unit_console", not attached and code == "console_busy")
    local offer = assert(context.jobs.createOffer({company="Busy original cutter",sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts={500}}))
    local pallet = offer.pallets[1]
    pallet.location, pallet.cutterMachineId = "at_cutter", unit.id
    state.jobs.active = { offer }
    attached, code = context.world.beginNetworkMachineMove(worker, state, 1, false, unit.id)
    check("purchased_machine_rejects_its_loaded_paper", not attached and code == "machine_busy")
    pallet.cutterMachineId = "MCH-0001"
    attached = context.world.beginNetworkMachineMove(worker, state, 1, false, unit.id)
    check("purchased_machine_can_move_while_another_cutter_has_paper", attached)
    local other = { id = 2, x = worker.x, y = worker.y }
    local rotated, rotationCode = context.world.rotateNetworkMachine(other, state)
    check("purchased_machine_only_jack_owner_can_control", not rotated and rotationCode == "not_owner")
    local invalidPoses = context.world.networkMachinePoseSnapshot(state)
    invalidPoses.cutter.machineId = "MCH-9999"
    local invalidJack = context.world.networkPalletJackSnapshot(state)
    invalidJack.operatorPlayerId = 2
    local applied = context.world.applyNetworkPalletJackSnapshot(state, invalidJack, invalidPoses)
    check("purchased_machine_unknown_snapshot_id_cannot_mutate_ownership",
        not applied and state.palletJack.operatorPlayerId == 1 and unit.world.moving)
    context.world.update(0.2, 1, 0, context.assets, state)
    local recovered = context.world.recoverNetworkMachineMove(state, context.assets, worker)
    check("purchased_machine_disconnect_recovery_releases_attachment",
        recovered and not unit.world.moving and unit.world._relocationOrigin == nil
        and Fleet.byId(state, unit.id) == unit and unit.status == "installed")
    context.world.releaseNetworkPalletJack(worker, state, true)
end

function Test.run(context, check)
    for index = 1, 3 do
        for _, channel in ipairs({ "dealer", "online" }) do controlLoop(context, check, index, channel) end
    end
    guards(context, check)
    context.world.load()
    context.world.player.id = 1
end

return Test
