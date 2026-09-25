local Test = {}
local Jobs = require("src.jobs")
local Fleet = require("src.machine_fleet")
local PalletState = require("src.pallet_state")
local CutterZones = require("src.cutter_zones")
local SaveSchema = require("src.save_schema")

local function job(id, press)
    local offer = Jobs.createOffer({
        id = id, company = "Concurrent equipment test",
        sourceSize = { width = press and 10 or 20, height = press and 15 or 16 },
        finishedSize = { width = press and 5 or 10, height = press and 7 or 8 },
        sheetCounts = { 500 },
        press = press and { colors = 1, coverage = 0.35,
            artworkSize = { width = 4, height = 6 },
            colorSequence = { "Black" }, requestedCopies = { 500 } } or nil,
    })
    Jobs.accept(offer)
    return offer
end

function Test.run(context, check)
    local state = context.State.new()
    state.money = 100000
    local bought, duplicate = Fleet.buy(state, "dealer", 1)
    local cutters = Fleet.installedUnits(state, "polar_115")
    check("duplicate_cutter_purchase_creates_separate_operable_floor_unit",
        bought and duplicate.status == "installed" and duplicate.world
        and #cutters == 2 and duplicate.world.x ~= state.cutter.x
        and Fleet.canOperate(state, "polar_115", duplicate.id))
    check("duplicate_cutter_is_on_walkable_floor",
        context.Navigation.isAreaWalkable(context.assets,
            duplicate.world.x, duplicate.world.y,
            context.config.cutterPlacement.collisionHalfWidth,
            context.config.cutterPlacement.collisionHalfHeight))
    context.world.load({ x = duplicate.world.x, y = duplicate.world.y })
    context.world.update(0, 0, 0, context.assets, state,
        duplicate.world.x, duplicate.world.y)
    local selected = context.world.interactionAt(duplicate.world.x, duplicate.world.y)
    check("second_cutter_has_own_floor_interaction",
        selected and selected.kind == "cutter"
        and selected.target.machineId == duplicate.id)
    check("warehouse_draws_purchased_duplicate_machine",
        pcall(context.world.draw, context.assets, context.characterAssets, state))
    state.screen = "world"
    local inputContext = {}
    for key, value in pairs(context.inputContext) do inputContext[key] = value end
    inputContext.state = state
    inputContext.saveCurrent = function() return true end
    context.input.keypressed("e", inputContext)
    check("second_cutter_opens_its_own_controls",
        state.screen == "machine" and state.machineId == duplicate.id
        and context.machine.forId(duplicate.id).step == "idle",
        tostring(state.screen) .. " / " .. tostring(state.machineId)
            .. " / " .. tostring(context.machine.forId(duplicate.id).step))
    context.input.closeScreen(inputContext)

    context.machine.reset()
    for index, unit in ipairs(cutters) do
        local offer = job("MULTI-CUT-" .. index)
        state.jobs.active[#state.jobs.active + 1] = offer
        local pallet = offer.pallets[1]
        pallet.location = "warehouse"
        state.screen, state.machineId = "machine", unit.id
        context.machine.select(unit.id, state)
        local x, y = CutterZones.inputAnchor(state, context.config.cutterPlacement)
        pallet.world = { x = x, y = y, direction = "northwest" }
        check("duplicate_cutter_loads_own_pallet_" .. index,
            context.machine.load(state, pallet.id) and pallet.cutterMachineId == unit.id)
    end
    context.machine.updateAll(1, state)
    check("two_cutters_advance_distinct_batches_together",
        context.machine.forId(cutters[1].id).step == "loaded"
        and context.machine.forId(cutters[2].id).step == "loaded"
        and context.machine.forId(cutters[1].id).pallet
            ~= context.machine.forId(cutters[2].id).pallet
        and PalletState.validate(state))
    local soldBusyCutter = Fleet.sell(state, cutters[2].id, "online")
    check("busy_duplicate_cutter_cannot_be_sold",
        not soldBusyCutter and Fleet.byId(state, cutters[2].id) ~= nil)
    state.screen, state.machineId = "machine", cutters[2].id
    context.machine.select(cutters[2].id, state)
    local gaugeSet = context.machine.setGauge(5, state)
    local gaugeSaved = gaugeSet and context.machine.saveGauge(state)
    context.machine.select(cutters[1].id, state)
    check("duplicate_cutter_keeps_own_program_memory",
        gaugeSaved and #context.machine.savedMeasurements(state, 1) == 0
        and cutters[2].memory and cutters[2].memory["1"][1] == 5)
    local bothPositioned = true
    for _, unit in ipairs(cutters) do
        state.screen, state.machineId = "machine", unit.id
        context.machine.select(unit.id, state)
        local cut = context.machine.paper.cuts[1]
        bothPositioned = context.machine.selectProgram(1, state)
            and context.machine.rotate(state)
            and context.machine.setGauge(cut.gauge, state)
            and context.machine.position(state) and bothPositioned
    end
    context.machine.updateAll(context.machine.transferTime + 0.01, state)
    for _, unit in ipairs(cutters) do
        state.machineId = unit.id
        context.machine.select(unit.id, state)
        context.machine.toggleClamp(state)
        context.machine.keypressed("j", state)
        context.machine.keypressed("k", state)
    end
    context.machine.updateAll(0.01, state)
    context.machine.updateAll(context.machine.cycleTime + 0.01, state)
    check("two_cutters_complete_first_cut_and_wear_separately",
        bothPositioned and cutters[1].cycles == 1 and cutters[2].cycles == 1)
    state.screen, state.machineId = "world", nil
    local cutterSnapshot = SaveSchema.snapshot(state)
    local restoredCutters = context.State.new()
    local cutterRestored = cutterSnapshot
        and context.State.applySave(restoredCutters, { state = cutterSnapshot, slot = 1 })
    check("two_cutter_pallets_survive_save_reload",
        cutterRestored and #Fleet.installedUnits(restoredCutters, "polar_115") == 2
        and restoredCutters.jobs.active[1].pallets[1].cutterMachineId == cutters[1].id
        and restoredCutters.jobs.active[2].pallets[1].cutterMachineId == cutters[2].id)
    context.machine.reset()

    local wrapperState = context.State.new()
    wrapperState.money = 100000
    local boughtWrapper, secondWrapper = Fleet.buy(wrapperState, "dealer", 2)
    local wrappers = Fleet.installedUnits(wrapperState, "skid_wrapper")
    wrapperState.inventory.plasticWrapUses = 10
    context.wrapper.clearInstances()
    wrapperState.screen = "world"
    context.world.load({ x = secondWrapper.world.x, y = secondWrapper.world.y })
    context.world.update(0, 0, 0, context.assets, wrapperState,
        secondWrapper.world.x, secondWrapper.world.y)
    local wrapperInteraction = context.world.interactionAt(
        secondWrapper.world.x, secondWrapper.world.y)
    check("second_wrapper_has_own_floor_interaction",
        wrapperInteraction and wrapperInteraction.kind == "skidWrapper"
        and wrapperInteraction.target.machineId == secondWrapper.id)
    local wrapperInputContext = {}
    for key, value in pairs(context.inputContext) do wrapperInputContext[key] = value end
    wrapperInputContext.state = wrapperState
    wrapperInputContext.saveCurrent = function() return true end
    context.input.keypressed("e", wrapperInputContext)
    check("second_wrapper_opens_its_own_controls",
        wrapperState.screen == "machine" and wrapperState.machineId == secondWrapper.id)
    context.input.closeScreen(wrapperInputContext)
    for index, unit in ipairs(wrappers) do
        local offer = job("MULTI-WRAP-" .. index)
        wrapperState.jobs.active[#wrapperState.jobs.active + 1] = offer
        local pallet = offer.pallets[1]
        pallet.location, pallet.status = "warehouse", "cut"
        local point = unit.world or wrapperState.wrapper
        pallet.world = { x = point.x, y = point.y, direction = "northwest" }
        wrapperState.screen, wrapperState.machineId = "machine", unit.id
        context.wrapper.select(unit.id, wrapperState)
        check("duplicate_wrapper_starts_own_job_" .. index, context.wrapper.start(wrapperState))
    end
    context.wrapper.updateAll(3.1, wrapperState)
    check("two_wrappers_finish_together_and_wear_separately",
        boughtWrapper and secondWrapper.world
        and context.wrapper.forId(wrappers[1].id).pallet.wrapped
        and context.wrapper.forId(wrappers[2].id).pallet.wrapped
        and wrappers[1].cycles == 1 and wrappers[2].cycles == 1)
    context.wrapper.clearInstances()

    local pressState = context.State.new()
    pressState.money = 100000
    local firstBought = Fleet.buy(pressState, "dealer", 3)
    local secondBought = Fleet.buy(pressState, "dealer", 3)
    local presses = Fleet.installedUnits(pressState, "heidelberg_10x15")
    check("two_windmills_install_on_separate_floor_positions",
        firstBought and secondBought and #presses == 2 and presses[2].world
        and presses[2].world.x ~= pressState.windmill.x)
    pressState.screen = "world"
    context.world.load({ x = presses[2].world.x, y = presses[2].world.y })
    context.world.update(0, 0, 0, context.assets, pressState,
        presses[2].world.x, presses[2].world.y)
    local pressInteraction = context.world.interactionAt(
        presses[2].world.x, presses[2].world.y)
    check("second_windmill_has_own_floor_interaction",
        pressInteraction and pressInteraction.kind == "windmill"
        and pressInteraction.target.machineId == presses[2].id)
    local pressOpenContext = {}
    for key, value in pairs(context.inputContext) do pressOpenContext[key] = value end
    pressOpenContext.state = pressState
    pressOpenContext.saveCurrent = function() return true end
    context.input.keypressed("e", pressOpenContext)
    check("second_windmill_opens_its_own_controls",
        pressState.screen == "press" and pressState.machineId == presses[2].id
        and type(presses[2].world.process) == "table")
    context.input.closeScreen(pressOpenContext)
    for index, unit in ipairs(presses) do
        local offer = job("MULTI-PRESS-" .. index, true)
        pressState.jobs.active[#pressState.jobs.active + 1] = offer
        local pallet = offer.pallets[1]
        pallet.location, pallet.status = "at_press", "press_setup"
        pallet.pressMachineId = unit.id
        local point = unit.world or pressState.windmill
        pallet.world = { x = point.x, y = point.y, direction = "northwest" }
        pallet.press = { status = "production", goodSheets = 0, spoilage = 0 }
        pressState.screen, pressState.machineId = "press", unit.id
        local process = context.windmill.ensure(pressState)
        process.jobId, process.palletId, process.colorIndex = offer.id, pallet.id, 1
        process.status, process.motor, process.feeder, process.impression =
            "production", true, true, true
        process.targetSheets, process.feedRemaining = 500, 500
        process.setup = { chase = 1, packing = 1, rollers = 1,
            ink = 1, feeder = 1, register = 1 }
    end
    pressState.screen, pressState.machineId = "press", presses[1].id
    local pressInputContext = {}
    for key, value in pairs(context.inputContext) do pressInputContext[key] = value end
    pressInputContext.state = pressState
    pressInputContext.saveCurrent = function() return true end
    local leftPress = context.input.closeScreen(pressInputContext)
    check("operator_can_leave_running_windmill_for_second_unit",
        leftPress and pressState.screen == "world"
        and pressState.windmill.process.status == "production")
    local soldBusyPress = Fleet.sell(pressState, presses[2].id, "online")
    check("busy_duplicate_windmill_cannot_be_sold",
        not soldBusyPress and Fleet.byId(pressState, presses[2].id) ~= nil)
    local liveSnapshot = SaveSchema.snapshot(pressState)
    local localReload = context.State.new()
    local locallyRestored = liveSnapshot and context.State.applyLocalSave(
        localReload, { state = liveSnapshot, slot = 1 })
    local localPresses = locallyRestored
        and Fleet.installedUnits(localReload, "heidelberg_10x15") or {}
    check("local_reload_safely_stops_both_running_windmills",
        locallyRestored and #localPresses == 2
        and localReload.windmill.process.status ~= "production"
        and localPresses[2].world.process.status ~= "production"
        and not localReload.windmill.process.motor
        and not localPresses[2].world.process.motor)
    local changed = context.windmill.updateAll(1, pressState)
    check("two_windmills_produce_concurrently_and_wear_separately",
        changed and presses[1].cycles > 0 and presses[2].cycles > 0
        and pressState.windmill.process.counter > 0
        and presses[2].world.process.counter > 0
        and PalletState.validate(pressState))
    pressState.screen, pressState.machineId = "world", nil
    local pressSnapshot = SaveSchema.snapshot(pressState)
    local restoredPresses = context.State.new()
    local pressRestored = pressSnapshot
        and context.State.applySave(restoredPresses, { state = pressSnapshot, slot = 1 })
    local restoredUnits = pressRestored
        and Fleet.installedUnits(restoredPresses, "heidelberg_10x15") or {}
    check("two_windmill_jobs_survive_save_reload",
        pressRestored and #restoredUnits == 2
        and restoredUnits[1].cycles > 0 and restoredUnits[2].cycles > 0
        and restoredUnits[2].world.process.counter > 0
        and restoredPresses.jobs.active[2].pallets[1].pressMachineId == presses[2].id)

    local catalogState = context.State.new()
    catalogState.money = 100000
    local extras = {}
    for _, offerIndex in ipairs({ 1, 2, 3 }) do
        local purchased, item = Fleet.buy(catalogState, "dealer", offerIndex)
        if purchased then extras[#extras + 1] = item end
    end
    local owned = Fleet.owned(catalogState)
    context.computerScreen.enter(catalogState)
    local dropdownX, dropdownY = context.computerScreen.dropdownCenter()
    context.computerScreen.mousepressed(catalogState, dropdownX, dropdownY, 1)
    local websiteX, websiteY = context.computerScreen.tabCenter("www")
    context.computerScreen.mousepressed(catalogState, websiteX, websiteY, 1)
    local machinesX, machinesY = context.computerScreen.wwwSiteCenter(5)
    context.computerScreen.mousepressed(catalogState, machinesX, machinesY, 1)
    local nextX, nextY = context.computerScreen.machinePageCenter("next")
    context.computerScreen.mousepressed(catalogState, nextX, nextY, 1)
    check("machine_catalog_paginates_all_purchased_units",
        #extras == 3 and #owned == 5 and context.computerScreen.machinePage == 2)
    local sellX, sellY = context.computerScreen.machineSellCenter(1)
    local sold = context.computerScreen.mousepressed(catalogState, sellX, sellY, 1)
    check("machine_catalog_can_reach_fifth_unit",
        sold and sold.action == "machine_sold"
        and sold.sale.machine.id == owned[5].id)
end

return Test
