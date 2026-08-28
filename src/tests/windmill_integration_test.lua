local Test = {}
local PressArtworkCompositor = require("src.press_artwork_compositor")
local PressSetupGames = require("src.press_setup_games")

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
    local setupSequences = {
        chase = { "align", "align", "square", "square", "tighten", "tighten" },
        packing = { "layer", "layer", "layer", "smooth", "smooth", "clamp" },
        rollers = { "left_up", "left_up", "right_down", "right_down" },
        ink = { "key_1", "key_1", "key_2", "key_2", "key_2", "key_2", "key_3", "ductor" },
        feeder = { "pile", "pile", "suction", "suction", "suction", "blast", "test", "test", "test" },
        register = { "left", "left", "left", "down", "down", "test" },
    }
    local setupGamesComplete, controlSignatures = true, {}
    for task, sequence in pairs(setupSequences) do
        local game = PressSetupGames.new(task, { stockSpec = { grade = "cover", weight = 100 } })
        local complete, score = false, nil
        for _, action in ipairs(sequence) do complete, score = PressSetupGames.apply(game, action) end
        setupGamesComplete = setupGamesComplete and complete and score == 1
        local labels = {}
        for _, control in ipairs(PressSetupGames.controls(task)) do labels[#labels + 1] = control[2] end
        controlSignatures[table.concat(labels, "|")] = true
    end
    local signatureCount = 0
    for _ in pairs(controlSignatures) do signatureCount = signatureCount + 1 end
    local lightFeeder = PressSetupGames.new("feeder", { stockSpec = { grade = "text", weight = 50 } })
    local coverFeeder = PressSetupGames.new("feeder", { stockSpec = { grade = "cover", weight = 100 } })
    check("six_manual_based_press_setup_games_have_distinct_controls_and_solvable_scoring",
        setupGamesComplete and signatureCount == 6)
    check("feeder_setup_changes_pile_suction_and_air_targets_for_light_and_cover_stock",
        lightFeeder.target.pile ~= coverFeeder.target.pile
        and lightFeeder.target.suction ~= coverFeeder.target.suction
        and lightFeeder.target.blast ~= coverFeeder.target.blast)

    local compositorCases = {
        { finishedSize = { width = 6, height = 9 }, press = { artworkSize = { width = 5.4, height = 8.2 } } },
        { finishedSize = { width = 9, height = 6 }, press = { artworkSize = { width = 8, height = 4 } } },
        { finishedSize = { width = 6, height = 6 }, press = { artworkSize = { width = 4, height = 4 } } },
        { finishedSize = { width = 10, height = 15 }, press = { artworkSize = { width = 0.5, height = 0.5 } } },
        { finishedSize = { width = 5, height = 7 }, press = { artworkSize = { width = 12, height = 18 } } },
    }
    local compositorSafe = true
    for _, jobCase in ipairs(compositorCases) do
        for stage = 1, 4 do
            local layout = PressArtworkCompositor.layout(jobCase, stage, 0.7)
            local bounds = layout.bounds
            compositorSafe = compositorSafe and bounds.u0 >= 0.08 and bounds.u1 <= 0.92
                and bounds.v0 >= 0.14 and bounds.v1 <= 0.92
                and bounds.u0 < bounds.u1 and bounds.v0 < bounds.v1
            for _, corner in ipairs(layout.corners) do
                compositorSafe = compositorSafe and corner[1] >= 0 and corner[1] <= 1
                    and corner[2] >= 0 and corner[2] <= 1
            end
        end
    end
    check("press_artwork_compositor_clips_portrait_landscape_square_minimum_and_maximum_art",
        compositorSafe and PressArtworkCompositor.layout(compositorCases[1], 2, 1).reversed)

    local partialSetupState = context.State.new()
    local partialProcess = context.windmill.ensure(partialSetupState)
    partialProcess.proofQuality = 0.91
    partialProcess.setup = { chase = 0.96 }
    local partialMetrics = context.pressScreen.proofMetrics(partialSetupState)
    check("proof_display_tolerates_partial_setup_scores_from_older_saves",
        partialMetrics[1][2] == 0 and partialMetrics[2][2] == 0
        and partialMetrics[3][2] == 0.48 and partialMetrics[4][2] == 0
        and partialMetrics[5][2] == 0 and partialMetrics[6][2] == 0.91)

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
    context.pressScreen.enter(state)
    context.pressScreen.tab = "setup"
    local setupUiComplete = true
    for taskIndex, task in ipairs(context.windmill.setupTasks()) do
        local row, column = math.floor((taskIndex - 1) / 2), (taskIndex - 1) % 2
        local opened = context.pressScreen.mousepressed(state, 256 + column * 426, 235 + row * 112, 1)
        setupUiComplete = setupUiComplete and type(opened) == "table"
        local controls = PressSetupGames.controls(task)
        local controlWidth = math.floor((840 - 8 * (#controls - 1)) / #controls)
        for _, action in ipairs(setupSequences[task]) do
            local controlIndex
            for index, control in ipairs(controls) do
                if control[1] == action then controlIndex = index; break end
            end
            local controlX = 60 + (controlIndex - 1) * (controlWidth + 8) + controlWidth / 2
            local clicked = context.pressScreen.mousepressed(state, controlX, 598, 1)
            setupUiComplete = setupUiComplete and type(clicked) == "table"
        end
        setupUiComplete = setupUiComplete and context.windmill.ensure(state).setup[task] == 1
    end
    check("all_six_manual_based_setup_games_complete_through_the_visible_gui_buttons", setupUiComplete)
    context.pressScreen.enter(state)
    context.pressScreen.tab = "setup"
    local setupFooter = context.pressScreen.mousepressed(state, 480, 580, 1)
    check("setup_footer_routes_to_run_controls_with_specific_proof_feedback",
        setupFooter and context.pressScreen.tab == "run"
        and state.message == "Start the motor before proofing.")
    local readyBeforeMotor, beforeMotorReason = context.windmill.proofReadiness(state)
    local motorClick = context.pressScreen.mousepressed(state, 131, 367, 1)
    local readyBeforeFeeder, beforeFeederReason = context.windmill.proofReadiness(state)
    local feederClick = context.pressScreen.mousepressed(state, 303, 367, 1)
    local readyBeforeImpression, beforeImpressionReason = context.windmill.proofReadiness(state)
    local impressionClick = context.pressScreen.mousepressed(state, 475, 367, 1)
    local proofReady, proofReadyReason = context.windmill.proofReadiness(state)
    check("pull_proof_readiness_matches_motor_feeder_and_impression_controls",
        motorClick and feederClick and impressionClick
        and not readyBeforeMotor and beforeMotorReason == "Start the motor before proofing."
        and not readyBeforeFeeder and beforeFeederReason == "Turn the feeder on before proofing."
        and not readyBeforeImpression and beforeImpressionReason == "Turn impression on before proofing."
        and proofReady and proofReadyReason == "Ready to pull one proof sheet.")
    local proofClick = context.pressScreen.mousepressed(state, 303, 439, 1)
    local proofed, proofQuality = type(proofClick) == "table", context.windmill.ensure(state).proofQuality
    check("pull_proof_mouse_button_opens_the_proof_tab_and_consumes_one_sheet",
        proofed and context.pressScreen.tab == "proof" and proofQuality
        and context.windmill.ensure(state).counter == 1
        and context.windmill.ensure(state).feedRemaining == 1049)
    local beforeKeyboardProof = context.windmill.ensure(state).feedRemaining
    local keyboardProof = context.pressScreen.keypressed(state, "p")
    check("pull_proof_keyboard_path_uses_the_same_readiness_and_opens_proof",
        keyboardProof and context.pressScreen.tab == "proof"
        and context.windmill.ensure(state).feedRemaining == beforeKeyboardProof - 1)
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
    local initialDrying = firstColor and context.windmill.dryingStatus(multiState, multiJob, multiPallet)
    local heldDuringDrying = firstColor and multiPallet.press.status == "drying"
        and multiPallet.press.completedColors == 1 and multiPallet.press.availableSheets == 1025
        and multiPallet.finishedSheets == 1025
        and multiState.inventory.inProcessPallets == 1 and multiState.inventory.finishedPallets == 0
    context.businessCalendar.update(multiState,
        context.config.businessCalendar.secondsPerDay / 24)
    local halfwayDrying = context.windmill.dryingStatus(multiState, multiJob, multiPallet)
    local blockedHalfway = #context.windmill.candidates(multiState) == 0
    context.businessCalendar.update(multiState,
        context.config.businessCalendar.secondsPerDay / 24 + 0.01)
    local finishedDrying = context.windmill.dryingStatus(multiState, multiJob, multiPallet)
    local loadableAfterDrying = #context.windmill.candidates(multiState) == 1
    check("windmill_drying_progress_counts_down_and_unlocks_the_next_color",
        initialDrying and initialDrying.progress == 0 and initialDrying.remainingHours == 2
        and halfwayDrying and math.abs(halfwayDrying.progress - 0.5) < 0.001
        and math.abs(halfwayDrying.remainingHours - 1) < 0.001 and blockedHalfway
        and finishedDrying and finishedDrying.ready and finishedDrying.progress == 1
        and finishedDrying.remainingHours == 0 and loadableAfterDrying)
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
