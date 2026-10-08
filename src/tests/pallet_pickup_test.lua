local Test = {}
local Config = require("src.config")
local State = require("src.state")
local Jobs = require("src.jobs")
local Jack = require("src.pallet_jack")
local Pickup = require("src.pallet_pickup")
local World = require("src.world")
local Input = require("src.input")

local function fixture(owner)
    local state = State.new()
    state.screen = "world"
    state.palletJack.x, state.palletJack.y = 500, 500
    state.palletJack.direction = "east"
    assert(Jack.mount(state, Config.palletJack, owner or 1))
    local job = Jobs.createOffer({ id = "PICKUP-CHOICE", company = "Pickup choice",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500, 500, 500 } })
    Jobs.accept(job)
    state.jobs.active = { job }
    for index, pallet in ipairs(job.pallets) do
        local x, y = 535, 500
        if index == 2 then x, y = 560, 480 elseif index == 3 then x = 900 end
        pallet.location, pallet.status = "warehouse", "raw"
        pallet.world = { x = x, y = y, fromX = x, fromY = y, spawnProgress = 1,
            direction = "east", rotation = 2 }
    end
    local player = { id = owner or 1, x = 442, y = 488 }
    return state, job.pallets, player
end

local function view(state, player, x, y)
    return Pickup.snapshot(state, Config.palletJack, player, x, y)
end

local function checkSelection(check)
    local state, pallets, player = fixture()
    local nearest = view(state, player)
    check("pickup_default_uses_fork_range_even_beyond_operator_reach",
        nearest.selected.pallet == pallets[1] and #nearest.candidates == 2
        and (pallets[1].world.x - player.x) ^ 2 + (pallets[1].world.y - player.y) ^ 2
            > Config.palletLogistics.interactionRadius ^ 2)
    local hovered = view(state, player, 560, 444)
    check("pickup_hover_selects_desired_eligible_pallet_in_overlapping_hit_areas",
        hovered.hovered and hovered.selected.pallet == pallets[2]
        and hovered.byId[pallets[1].id] and hovered.byId[pallets[2].id]
        and not hovered.byId[pallets[3].id])
    local label = view(state, player, 560, 383)
    check("pickup_lift_label_is_also_a_click_and_touch_target",
        label.hovered and label.selected.pallet == pallets[2])
    local distant = view(state, player, 900, 464)
    check("pickup_hover_cannot_expand_authoritative_fork_range",
        not distant.hovered and distant.selected.pallet == pallets[1])
    state.palletJack.candidatePalletId = pallets[3].id
    check("pickup_stale_network_hint_does_not_replace_nearest_eligible_pallet",
        view(state, player).selected.pallet == pallets[1])
    pallets[2].world.x, pallets[2].world.y = 465, 500
    check("pickup_equal_distance_is_deterministic",
        view(state, player).selected.pallet == pallets[1])

    local machine = { kind = "cutter", hovered = true, target = { prompt = "E: use cutter" } }
    check("pickup_default_takes_priority_over_nearby_machine_prompt",
        Pickup.interaction(nearest, player, machine).target.item.pallet == pallets[1])
    check("pickup_deliberate_pointer_use_of_other_controls_remains_available",
        Pickup.interaction(view(state, player, 400, 390), player, machine) == machine)
    check("pickup_hover_wins_over_machine_and_paperwork_overlap",
        Pickup.interaction(hovered, player, machine).target.item.pallet == pallets[2])

    state, pallets, player = fixture()
    state.employment.staff = {{ id = "PICKUP-WORKER", visible = true, reserved = true,
        assignment = { machineId = "MCH-0001", palletId = pallets[1].id } }}
    local reserved = view(state, player, 535, 464)
    check("pickup_reserved_pallet_is_not_highlighted_or_selected",
        not reserved.byId[pallets[1].id] and reserved.selected.pallet == pallets[2])
    state.employment.staff = {}
    pallets[3].location, pallets[3].storage = "stacked", { supportPalletId = pallets[1].id, level = 2 }
    check("pickup_supporting_base_and_upper_stack_are_not_selectable",
        #view(state, player).candidates == 1 and view(state, player).selected.pallet == pallets[2])
    state, pallets, player = fixture()
    check("pickup_other_worker_has_no_highlight_or_fork_selection",
        not view(state, { id = 2, x = 500, y = 500 }).selected)
    player.sceneId = "front_left"
    check("pickup_other_room_has_no_warehouse_highlight", not view(state, player).selected)
    player.sceneId = nil
    state.cutter.moving = true
    check("pickup_attached_machine_suppresses_lift_selection", not view(state, player).selected)
    state.cutter.moving = false
    assert(Jack.lift(state, Config.palletJack, pallets[1].id))
    check("pickup_loaded_jack_has_no_lift_highlights", not view(state, player).selected)
end

local function checkControls(check)
    local previousPlayer = {}
    for key, value in pairs(World.player) do previousPlayer[key] = value end
    local previousState, previousSelection = World._state, World.selectedInteraction
    local state, pallets, player = fixture()
    for key, value in pairs(player) do World.player[key] = value end
    World.player.sceneId = "warehouse"
    World._state = state
    state.cutter.x, state.cutter.y = 442, 488
    local selected = World.interactionAt()
    check("pickup_world_selection_prioritizes_nearest_pallet_over_nearby_cutter",
        selected.kind == "palletJack" and selected.target.pickup
        and selected.target.item.pallet == pallets[1])
    selected = World.interactionAt(560, 444)
    check("pickup_world_pointer_and_highlight_agree_on_exact_pallet",
        selected.hovered and selected.target.item.pallet == pallets[2]
        and World.palletPickupSnapshot(state, 560, 444).selected.pallet == pallets[2])
    local tooltip = World.palletTooltipAt(state, 560, 444)
    check("pickup_overlapping_pallet_tooltip_follows_highlight", tooltip.title:find(pallets[2].id, 1, true))
    local saves = 0
    local inputContext = { state = state, world = World, assets = {},
        saveCurrent = function() saves = saves + 1 end }
    check("pickup_keyboard_l_lifts_the_highlighted_desired_pallet",
        Input.keypressed("l", inputContext) and state.palletJack.carriedPalletId == pallets[2].id
        and saves == 1)
    local lowerRequested = false
    Input.keypressed("l", { state = state, assets = {},
        world = { player = player, getInteraction = function()
            return { kind = "palletWorkOrder", hovered = true, target = { item = { pallet = pallets[1] } } }
        end, handlePalletJack = function(_, _, palletId)
            lowerRequested = palletId == nil
            return false
        end } })
    check("pickup_loaded_fork_control_lowers_even_when_other_pallet_is_hovered", lowerRequested)

    state, pallets, player = fixture()
    inputContext.state, World._state = state, state
    World.interactionAt()
    Input.keypressed("e", inputContext)
    check("pickup_use_action_defaults_to_nearest_eligible_pallet",
        state.palletJack.carriedPalletId == pallets[1].id)

    state, pallets, player = fixture()
    inputContext.state, World._state = state, state
    local placements, pickupCommands = 0, {}
    inputContext.hud = { hitTest = function() return nil end }
    inputContext.worldPointerCoordinates = function(x, y) return x + 300, y + 200 end
    local inputWorld = {
        player = World.player, palletAt = World.palletAt,
        palletPickupSnapshot = World.palletPickupSnapshot, handlePalletJack = World.handlePalletJack,
        selectPlacement = function() placements = placements + 1; return true end,
    }
    inputContext.world = inputWorld
    check("pickup_camera_transformed_tap_lifts_before_placement_selection",
        Input.mousepressed(260, 244, 1, inputContext) and placements == 0
        and state.palletJack.carriedPalletId == pallets[2].id)

    state, pallets, player = fixture(2)
    World.player.id, inputContext.state, World._state = 2, state, state
    inputContext.isNetworkClient = function() return true end
    inputContext.palletJackControl = function(action, chosen)
        pickupCommands[#pickupCommands + 1] = { action, chosen.target.item.pallet.id }
        return true
    end
    check("pickup_guest_tap_requests_exact_pallet_without_local_mutation",
        Input.mousepressed(260, 244, 1, inputContext) and pickupCommands[1][1] == "lift"
        and pickupCommands[1][2] == pallets[2].id and not state.palletJack.carriedPalletId)
    local runtime = { state = state, World = World, Config = Config, PalletJack = Jack }
    require("src.runtime.pallet_controls").install(runtime)
    selected = World.interactionAt(560, 444, true)
    local command, args = runtime.palletJackCommandFor("use", selected)
    check("pickup_guest_keyboard_command_uses_highlighted_exact_id",
        command == "lift_pallet" and args.palletId == pallets[2].id)
    command, args = runtime.palletJackCommandFor("lift")
    check("pickup_lift_command_without_pointer_defaults_to_nearest",
        command == "lift_pallet" and args.palletId == pallets[1].id)
    state.employment.staff = {{ id = "PICKUP-RACE", visible = true, reserved = true,
        assignment = { machineId = "MCH-0001", palletId = pallets[2].id } }}
    local accepted, reason = World.liftNetworkPallet(player, state, pallets[2].id)
    check("pickup_host_revalidates_exact_selection_after_employee_reservation",
        not accepted and reason == "employee_reserved" and not state.palletJack.carriedPalletId)
    state.employment.staff = {}
    runtime.multiplayer = { isClient = function() return true end }
    runtime.warehouseControls = { ownsLift = function() return false end }
    require("src.runtime.keyboard_mobile").install(runtime)
    local key, label = runtime.primaryMobileAction()
    check("pickup_mobile_primary_button_is_dedicated_nearest_lift",
        key == "l" and label == "LIFT")
    accepted = World.liftNetworkPallet(player, state, pallets[2].id)
    check("pickup_host_accepts_guest_desired_pallet_when_still_eligible",
        accepted and state.palletJack.carriedPalletId == pallets[2].id)

    for key in pairs(World.player) do World.player[key] = nil end
    for key, value in pairs(previousPlayer) do World.player[key] = value end
    World._state, World.selectedInteraction = previousState, previousSelection
end

local function checkRendering(context, check)
    local state, _, player = fixture()
    local previousPlayer = {}
    for key, value in pairs(World.player) do previousPlayer[key] = value end
    for key, value in pairs(player) do World.player[key] = value end
    World.player.sceneId = "warehouse"
    local canvas = love.graphics.newCanvas(Config.baseWidth, Config.baseHeight)
    love.graphics.push("all")
    love.graphics.setCanvas({ canvas, stencil = true })
    love.graphics.origin()
    love.graphics.clear()
    local rendered, renderError = pcall(World.draw, context.assets, context.characterAssets, state, 560, 444)
    love.graphics.pop()
    check("pickup_eligible_and_selected_world_highlights_render", rendered, tostring(renderError))
    local reviewPath = os.getenv("PICTURE_SHOP_PICKUP_REVIEW_PATH")
    if reviewPath and rendered then
        local data = canvas:newImageData()
        local png = data:encode("png")
        local file = assert(io.open(reviewPath, "wb"))
        file:write(png:getString()); file:close()
        png:release(); data:release()
    end
    canvas:release()
    for key in pairs(World.player) do World.player[key] = nil end
    for key, value in pairs(previousPlayer) do World.player[key] = value end
end

function Test.run(context, check)
    checkSelection(check)
    checkControls(check)
    checkRendering(context, check)
end

return Test
