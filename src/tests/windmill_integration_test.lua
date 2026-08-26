local Test = {}

local function makePressJob()
    return require("src.jobs").createOffer({
        id = "PRESS-TEST-001", company = "Windmill Test Client",
        sourceSize = { width = 10, height = 15 }, finishedSize = { width = 5, height = 7 },
        sheetCounts = { 1050 }, packaging = "flat", difficulty = "easy", artworkKey = "flower",
        press = { colors = 1, coverage = 0.35, artworkSize = { width = 4.25, height = 6.25 },
            colorSequence = { "Black" }, requestedCopies = { 1000 } },
        details = { stockDescription = "80 lb uncoated cover" },
    })
end

function Test.run(context, check)
    local state = context.State.new()
    state.money = 20000
    local bought, machine = context.machineFleet.buy(state, "dealer", 3)
    check("windmill_can_be_purchased_as_the_first_installed_press", bought and machine
        and machine.modelId == "heidelberg_10x15" and machine.status == "installed")

    context.computerScreen.enter(state)
    local stockX, stockY = context.computerScreen.tabCenter("inventory")
    context.computerScreen.mousepressed(state, stockX, stockY, 1)
    local nextX, nextY = context.computerScreen.retailPageCenter("next")
    local paged = context.computerScreen.mousepressed(state, nextX, nextY, 1)
    local plateKitX, plateKitY = context.computerScreen.retailButtonCenter(2)
    local plateKitOrder = context.computerScreen.mousepressed(state, plateKitX, plateKitY, 1)
    check("office_computer_paginates_to_all_press_supply_products", paged and paged.page == 2
        and plateKitOrder and plateKitOrder.action == "supply_order"
        and plateKitOrder.order.item == "plate_room_kit")

    local job = makePressJob()
    job.status = "in_progress"
    state.jobs.active = { job }
    local pallet = job.pallets[1]
    pallet.location, pallet.status = "cutter_output", "cut"
    pallet.world = { x = state.windmill.x - 60, y = state.windmill.y + 30,
        direction = state.windmill.direction, spawnProgress = 1 }
    pallet.paper.status, pallet.remainingSheets, pallet.finishedSheets = "complete", 0, pallet.initialSheets
    state.inventory.inProcessPallets, state.inventory.finishedPallets = 1, 0

    local stock = state.inventory.stock
    stock.raw_press_plates, stock.negative_film, stock.plate_adhesive, stock.plate_chemistry = 1, 1, 1, 1
    stock.black_ink, stock.tympan_sheets, stock.press_wash = 2, 2, 2
    local plateStarted, plate = context.plateService.beginInHouse(state, job, 1)
    for _, action in ipairs({ "expose", "wash", "dry", "mount" }) do
        context.plateService.process(plate, action, 0.98)
    end
    check("windmill_plate_room_tracks_unique_plate_and_four_real_process_steps", plateStarted
        and plate.id == "PRESS-TEST-001-PLATE-01" and plate.status == "ready"
        and plate.mounted and plate.quality == 0.98 and job.press.actual.inHousePlates == 1)

    local loaded = context.windmill.load(state, pallet.id)
    for _, task in ipairs(context.windmill.setupTasks()) do
        context.windmill.completeSetup(state, task, 0.98)
    end
    context.windmill.control(state, "motor")
    context.windmill.control(state, "feeder")
    context.windmill.control(state, "impression")
    local proofed, proofQuality = context.windmill.takeProof(state)
    local verified = context.windmill.verifyArtwork(state)
    local approved = context.windmill.approveProof(state)
    local started = context.windmill.startProduction(state)
    local finishedPass = context.windmill.update(10, state)
    local unloaded = context.windmill.cleanAndUnload(state)
    check("windmill_full_operator_loop_runs_setup_proof_production_and_cleanup", loaded and proofed
        and proofQuality >= 0.82 and verified and approved and started and finishedPass and unloaded
        and pallet.press.status == "complete" and pallet.location == "press_output"
        and pallet.status == "printed" and job.press.actual.impressions >= 1001
        and pallet.finishedSheets == 1000 and pallet.press.availableSheets == 1000
        and state.inventory.inProcessPallets == 0 and state.inventory.finishedPallets == 1
        and job.press.actual.inkUnits == 1 and job.press.actual.tympanSheets == 1
        and job.press.actual.washUnits == 1)

    local multiState = context.State.new()
    multiState.money = 20000
    context.machineFleet.buy(multiState, "dealer", 3)
    local multiJob = context.jobs.createOffer({
        id = "PRESS-TEST-MULTI", company = "Two Color Test Client",
        sourceSize = { width = 10, height = 15 }, finishedSize = { width = 5, height = 7 },
        sheetCounts = { 1050 }, packaging = "flat", artworkKey = "ad-pizza",
        stockSpec = { suppliedBy = "client", grade = "cover", weight = 80,
            finish = "uncoated", color = "white", grain = "long",
            description = "80 lb uncoated cover" },
        press = { colors = 2, coverage = 0.4, artworkSize = { width = 4.25, height = 6.25 },
            colorSequence = { "Red", "Black" }, requestedCopies = { 1000 } },
    })
    multiJob.status, multiState.jobs.active = "in_production", { multiJob }
    local multiPallet = multiJob.pallets[1]
    multiPallet.location, multiPallet.status = "cutter_output", "cut"
    multiPallet.world = { x = multiState.windmill.x - 60, y = multiState.windmill.y + 30,
        direction = multiState.windmill.direction, spawnProgress = 1 }
    multiPallet.paper.status, multiPallet.remainingSheets = "complete", 0
    multiPallet.finishedSheets = multiPallet.initialSheets
    multiState.inventory.inProcessPallets, multiState.inventory.finishedPallets = 1, 0
    multiState.inventory.stock.color_ink, multiState.inventory.stock.black_ink = 1, 1
    multiState.inventory.stock.tympan_sheets, multiState.inventory.stock.press_wash = 2, 2
    for _, multiPlate in ipairs(context.plateService.ensureJob(multiJob)) do
        multiPlate.status, multiPlate.quality, multiPlate.mounted = "ready", 0.98, true
    end
    local function runColorPass()
        if not context.windmill.load(multiState, multiPallet.id) then return false end
        local target = context.windmill.ensure(multiState).targetSheets
        for _, task in ipairs(context.windmill.setupTasks()) do
            if not context.windmill.completeSetup(multiState, task, 0.98) then return false end
        end
        if not context.windmill.control(multiState, "motor") then return false end
        if not context.windmill.control(multiState, "feeder") then return false end
        if not context.windmill.control(multiState, "impression") then return false end
        if not context.windmill.takeProof(multiState) then return false end
        if not context.windmill.verifyArtwork(multiState) then return false end
        if not context.windmill.approveProof(multiState) then return false end
        if not context.windmill.startProduction(multiState) then return false end
        if not context.windmill.update(10, multiState) then return false end
        if not context.windmill.cleanAndUnload(multiState) then return false end
        return true, target
    end
    local firstColor, firstTarget = runColorPass()
    local heldDuringDrying = firstColor and multiPallet.press.status == "drying"
        and multiPallet.press.completedColors == 1 and multiPallet.press.availableSheets == 1025
        and multiPallet.finishedSheets == 1025
        and multiState.inventory.inProcessPallets == 1 and multiState.inventory.finishedPallets == 0
    context.businessCalendar.update(multiState,
        context.config.businessCalendar.secondsPerDay * 2 / 24 + 0.01)
    local secondColor, secondTarget = runColorPass()
    check("windmill_multicolor_reserves_stock_between_passes_and_finishes_exact_order",
        firstColor and secondColor and firstTarget == 1025 and secondTarget == 1000
        and heldDuringDrying and multiPallet.press.status == "complete"
        and multiPallet.press.completedColors == 2 and #multiPallet.press.passHistory == 2
        and multiPallet.finishedSheets == 1000 and multiPallet.press.availableSheets == 1000
        and multiState.inventory.inProcessPallets == 0 and multiState.inventory.finishedPallets == 1)

    job.status = "completed"
    local scheduled = context.jobService.scheduleRepeatEmail(state, job)
    local pending = state.clientEmails.pending[1]
    check("completed_press_clients_can_request_repeat_print_work_by_email", scheduled and pending
        and pending.job.press and pending.job.press.colors == 1
        and pending.subject == "Request for another print job")

    local conditionBefore = context.machineFleet.condition(machine)
    machine.variables.gripperTiming, machine.variables.safetyCircuit = 30, 30
    local booked = context.machineMaintenance.requestWindmillTechnician(state)
    context.businessCalendar.update(state, context.config.businessCalendar.secondsPerDay)
    local serviced = context.machineMaintenance.updateWindmillTechnician(state)
    context.Technician.update(0, state, false)
    context.Technician.update(20, state, false)
    context.Technician.update(context.config.technician.serviceDuration, state, false)
    check("windmill_field_technician_restores_timing_lubrication_and_safety", booked and serviced
        and machine.variables.gripperTiming >= 88 and machine.variables.safetyCircuit >= 88
        and context.machineFleet.condition(machine) > conditionBefore - 25
        and #context.machineFleet.serviceInbox(state) == 1)
end

return Test
