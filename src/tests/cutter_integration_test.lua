local Test = {}

function Test.run(context, check, jobs)
    local function verifySixLiftRepeatRun()
        local repeatState = context.State.new()
        local repeatJob = jobs.createOffer({
            id = "JOB-SIX-LIFTS", company = "Six Lift Co.",
            sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
            sheetCounts = { 3000 },
        })
        jobs.accept(repeatJob)
        repeatState.jobs.active[1] = repeatJob
        context.PalletLogistics.unload(repeatState, repeatJob.id, repeatJob.pallets[1].id,
            context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin)
        local pallet = repeatJob.pallets[1]
        local anchorX, anchorY = context.CutterZones.inputAnchor(repeatState, context.config.cutterPlacement)
        pallet.world.x, pallet.world.y = anchorX, anchorY
        pallet.world.fromX, pallet.world.fromY = anchorX, anchorY
        context.PalletState.transition(repeatState, pallet, "at_cutter", {
            status = "in_process", cutterRadius = context.config.cutterPlacement.palletInputZoneRadius,
        })
        pallet.paper.status = "complete"
        pallet.paper.activeCut = #pallet.paper.cuts + 1
        pallet.paper.currentSize.width = pallet.paper.finishedSize.width
        pallet.paper.currentSize.height = pallet.paper.finishedSize.height
        pallet.completedLifts, pallet.remainingSheets, pallet.finishedSheets = 1, 2500, 500
        pallet.activeLift, pallet.lastLiftSheets, pallet.programVerified = 2, 500, true
        context.machine.reset(repeatState)
        check("six_lift_program_resumes", context.machine.load(repeatState)
            and context.machine.step == "repeat_ready")
        for completed = 2, 6 do
            check("six_lift_repeat_starts_" .. completed, context.machine.repeatLift(repeatState))
            context.machine.update(context.machine.repeatCycleTime + 0.01, repeatState)
            check("six_lift_progress_" .. completed,
                pallet.completedLifts == completed
                and pallet.remainingSheets == 3000 - completed * 500
                and pallet.finishedSheets == completed * 500
                and pallet.lastLiftSheets == 500
                and context.machine.step == (completed == 6 and "cut_complete" or "repeat_ready"))
            if completed == 3 then
                check("six_lift_checkpoint_write", context.save.save(3, repeatState, { x = 400, y = 400 }))
                local checkpoint = context.save.load(3)
                local savedPallet = checkpoint and checkpoint.state.jobs.active[1].pallets[1]
                check("six_lift_checkpoint_round_trip", savedPallet
                    and savedPallet.completedLifts == 3
                    and savedPallet.activeLift == 4
                    and savedPallet.remainingSheets == 1500
                    and savedPallet.finishedSheets == 1500
                    and savedPallet.lastLiftSheets == 500
                    and savedPallet.programVerified
                    and checkpoint.state.inventory.inProcessPallets == 1
                    and checkpoint.state.inventory.finishedPallets == 0)
                context.save.delete(3)
            end
        end
        context.machine.reset(repeatState)
    end
    verifySixLiftRepeatRun()

    local cutterState = context.State.new()
    cutterState.screen = "machine"
    local cutterJob = jobs.createOffer({
        id = "JOB-CUTTER",
        company = "Cutter Test Co.",
        difficulty = "hard",
        sourceSize = { width = 25, height = 19 },
        finishedSize = { width = 12.5, height = 9.5 },
        sheetCounts = { 750 },
    })
    jobs.accept(cutterJob)
    cutterJob.pallets[1].location = "warehouse"
    cutterJob.pallets[1].world = {
        x = cutterState.cutter.x + 82,
        y = cutterState.cutter.y + 42,
        direction = "northwest",
        rotation = 1,
        fromX = cutterState.cutter.x + 82,
        fromY = cutterState.cutter.y + 42,
        spawnProgress = 1,
    }
    cutterState.jobs.active[1] = cutterJob
    local trackedPaper = cutterJob.pallets[1].paper
    check("paper_unique_id", trackedPaper.id == "JOB-CUTTER-P01-PAPER"
        and trackedPaper.artworkId == "ART-JOB-CUTTER"
        and #trackedPaper.cuts == 4)
    check("hard_job_asymmetric_margins", trackedPaper.margins.left ~= trackedPaper.margins.right
        or trackedPaper.margins.top ~= trackedPaper.margins.bottom)

    context.machine.reset(cutterState)
    check("cutter_table_starts_clear", not context.machine.loaded and context.machine.step == "idle")
    check("cutter_load", context.machine.load(cutterState))
    context.machine.update(context.machine.transferTime + 0.01, cutterState)
    check("cutter_load_animation", context.machine.step == "loaded" and context.machine.paper == trackedPaper)
    check("cutter_rejects_wrong_gauge", not context.machine.position(cutterState))
    context.machineScreen.enter()
    local typedGauge = string.format("%.2f", trackedPaper.cuts[1].gauge)
    for character in typedGauge:gmatch(".") do
        check("cutter_accepts_typed_character_" .. character,
            context.machineScreen.textinput(cutterState, character))
    end
    check("cutter_enter_commits_typed_gauge", context.machineScreen.keypressed(cutterState, "return")
        and math.abs(context.machine.gauge - trackedPaper.cuts[1].gauge) < 0.001)
    local expectedBedOrientations = { 90, 0, 270, 180 }

    for cutNumber = 1, 4 do
        check("cutter_select_program_" .. cutNumber, context.machine.selectProgram(cutNumber, cutterState))
        check("cutter_front_edge_orientation_" .. cutNumber,
            trackedPaper.cuts[cutNumber].orientation == expectedBedOrientations[cutNumber])
        if cutNumber == 1 then
            check("cutter_keyboard_rotate_" .. cutNumber, context.machine.keypressed("q", cutterState))
            local autoX, autoY = context.machineScreen.buttonCenter("auto")
            check("cutter_mouse_auto_gauge", context.machineScreen.mousepressed(cutterState, autoX, autoY, 1))
            context.machineScreen.mousereleased(cutterState, autoX, autoY, 1)
        else
            check("cutter_keyboard_rotate_" .. cutNumber, context.machine.keypressed("q", cutterState))
            check("cutter_keyboard_auto_gauge_" .. cutNumber, context.machine.keypressed("g", cutterState))
        end
        check("cutter_auto_selects_next_program_" .. cutNumber,
            context.machine.programIndex == cutNumber
            and math.abs(context.machine.gauge - trackedPaper.cuts[cutNumber].gauge) < 0.001)
        check("cutter_position_" .. cutNumber, context.machine.keypressed("p", cutterState))
        context.machine.update(context.machine.transferTime + 0.01, cutterState)
        check("cutter_position_animation_" .. cutNumber, context.machine.step == "positioned")
        check("cutter_clamp_" .. cutNumber, context.machine.keypressed("space", cutterState))
        context.machine.update(0.3, cutterState)
        if cutNumber == 1 then
            local leftX, leftY = context.machineScreen.buttonCenter("cut_left")
            local rightX, rightY = context.machineScreen.buttonCenter("cut_right")
            check("cutter_mouse_left_control", context.machineScreen.mousepressed(cutterState, leftX, leftY, 1))
            context.machineScreen.mousereleased(cutterState, leftX, leftY, 1)
            check("cutter_mouse_right_control", context.machineScreen.mousepressed(cutterState, rightX, rightY, 1))
            context.machineScreen.mousereleased(cutterState, rightX, rightY, 1)
        else
            context.machine.keypressed("j", cutterState)
            context.machine.keypressed("k", cutterState)
            context.machine.keyreleased("j")
            context.machine.keyreleased("k")
        end
        context.machine.update(0.01, cutterState)
        context.machine.update(context.machine.cycleTime + 0.05, cutterState)
        check("cutter_applies_margin_" .. cutNumber, trackedPaper.activeCut == cutNumber + 1)
    end
    check("cutter_manual_lift_verifies_program", trackedPaper.status == "complete"
        and trackedPaper.currentSize.width == 12.5
        and trackedPaper.currentSize.height == 9.5
        and context.machine.step == "repeat_ready"
        and cutterJob.pallets[1].completedLifts == 1
        and cutterJob.pallets[1].remainingSheets == 250
        and cutterJob.pallets[1].finishedSheets == 500
        and cutterJob.pallets[1].programVerified)
    check("paper_tooltip_updates_size", context.machine.paperTooltip():find("12.50 x 9.50", 1, true) ~= nil)
    check("cutter_blocks_early_unload_between_lifts", not context.machine.keypressed("u", cutterState)
        and context.machine.step == "repeat_ready"
        and cutterJob.pallets[1].remainingSheets == 250)
    check("cutter_repeat_lift_starts", context.machine.keypressed("t", cutterState)
        and context.machine.step == "repeat_producing")
    context.machine.update(context.machine.repeatCycleTime + 0.01, cutterState)
    check("cutter_partial_final_lift_completes", context.machine.step == "cut_complete"
        and cutterJob.pallets[1].completedLifts == 2
        and cutterJob.pallets[1].remainingSheets == 0
        and cutterJob.pallets[1].finishedSheets == 750
        and cutterJob.pallets[1].lastLiftSheets == 250
        and cutterJob.pallets[1].activeLift == 2)
    local finishedBeforeBlockedOutput = cutterState.inventory.finishedPallets
    context.machine.setOutputResolver(function()
        return nil, "No clear cutter output zone is available. Move pallets or equipment away from the cutter."
    end)
    check("cutter_full_output_zone_blocks_unload", not context.machine.keypressed("u", cutterState)
        and context.machine.step == "cut_complete"
        and cutterJob.pallets[1].location == "at_cutter"
        and cutterState.inventory.finishedPallets == finishedBeforeBlockedOutput)
    context.machine.reset(cutterState)
    check("cutter_completed_pallet_resumes_after_console_exit", context.machine.load(cutterState)
        and context.machine.step == "cut_complete"
        and context.machine.paper == trackedPaper
        and cutterJob.pallets[1].location == "at_cutter"
        and cutterState.inventory.inProcessPallets == 1)
    context.machine.setOutputResolver(function(targetState, pallet)
        return context.world.findCutterOutput(targetState, context.assets, pallet and pallet.id)
    end)
    check("cutter_unload", context.machine.keypressed("u", cutterState))
    context.machine.update(context.machine.transferTime + 0.01, cutterState)
    check("cutter_returns_to_pallet", context.machine.step == "finished"
        and cutterJob.pallets[1].status == "cut"
        and cutterJob.pallets[1].location == "cutter_output"
        and cutterState.inventory.finishedPallets == 1)
    check("cutter_output_is_safe_floor", context.world.isPalletPlacementClear(
        cutterState, context.assets,
        cutterJob.pallets[1].world.x, cutterJob.pallets[1].world.y, cutterJob.pallets[1].id))

    context.machine.reset(cutterState)
    cutterJob.pallets[1].paper.status = "uncut"
    cutterJob.pallets[1].paper.activeCut = 1
    cutterJob.pallets[1].paper.orientation = 0
    cutterJob.pallets[1].paper.currentSize = {
        width = cutterJob.pallets[1].paper.sourceSize.width,
        height = cutterJob.pallets[1].paper.sourceSize.height,
    }
    cutterJob.pallets[1].paper.history = {}
    cutterJob.pallets[1].remainingSheets = cutterJob.pallets[1].initialSheets
    cutterJob.pallets[1].finishedSheets = 0
    cutterJob.pallets[1].completedLifts = 0
    cutterJob.pallets[1].activeLift = 1
    cutterJob.pallets[1].lastLiftSheets = 0
    cutterJob.pallets[1].programVerified = false
    cutterJob.pallets[1].location = "warehouse"
    context.machine.load(cutterState)
    context.machine.update(context.machine.transferTime + 0.01, cutterState)
    context.machine.autoGauge(cutterState)
    context.machine.keypressed("q", cutterState)
    context.machine.position(cutterState)
    context.machine.update(context.machine.transferTime + 0.01, cutterState)
    context.machine.toggleClamp(cutterState)
    context.machine.setBarrier(false, cutterState)
    context.machine.keypressed("j", cutterState)
    context.machine.keypressed("k", cutterState)
    check("cutter_barrier_blocks", context.machine.step == "blocked")
    context.machine.reset(context.state)

    local function ownershipState(id, x, y)
        local testState = context.State.new()
        local testJob = jobs.createOffer({
            id = id,
            company = "Ownership Test Co.",
            sourceSize = { width = 20, height = 16 },
            finishedSize = { width = 10, height = 8 },
            sheetCounts = { 500 },
        })
        jobs.accept(testJob)
        local pallet = testJob.pallets[1]
        pallet.location = "warehouse"
        pallet.world = { x = x, y = y, direction = "northwest", rotation = 1,
            fromX = x, fromY = y, spawnProgress = 1 }
        testState.jobs.active[1] = testJob
        return testState, testJob, pallet
    end

    local cutterDirections = { "northwest", "northeast", "southwest", "southeast" }
    for _, direction in ipairs(cutterDirections) do
        local orientedState, _, orientedPallet = ownershipState("JOB-INPUT-" .. direction, 0, 0)
        orientedState.cutter.direction = direction
        local anchorX, anchorY = context.CutterZones.inputAnchor(
            orientedState, context.config.cutterPlacement)
        orientedPallet.world.x, orientedPallet.world.y = anchorX, anchorY
        orientedPallet.world.fromX, orientedPallet.world.fromY = anchorX, anchorY
        local candidates = context.PalletState.cutterCandidates(
            orientedState, context.config.cutterPlacement.palletInputZoneRadius)
        check("cutter_input_zone_" .. direction, candidates[1]
            and candidates[1].pallet == orientedPallet)
    end

    local fartherState, fartherJob, fartherPallet = ownershipState(
        "JOB-INPUT-FARTHER", context.config.cutterPlacement.spawnX + 116,
        context.config.cutterPlacement.spawnY + 38)
    local nearerJob = jobs.createOffer({
        id = "JOB-INPUT-NEARER", company = "Nearest Input Co.",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
    })
    jobs.accept(nearerJob)
    local nearerPallet = nearerJob.pallets[1]
    nearerPallet.location = "warehouse"
    nearerPallet.world = {
        x = fartherState.cutter.x + 80, y = fartherState.cutter.y + 38,
        direction = "northwest", rotation = 1,
        fromX = fartherState.cutter.x + 80, fromY = fartherState.cutter.y + 38,
        spawnProgress = 1,
    }
    fartherState.jobs.active[1], fartherState.jobs.active[2] = fartherJob, nearerJob
    local sortedInputs = context.PalletState.cutterCandidates(
        fartherState, context.config.cutterPlacement.palletInputZoneRadius)
    check("cutter_selects_nearest_input_pallet", sortedInputs[1]
        and sortedInputs[1].pallet == nearerPallet
        and sortedInputs[2].pallet == fartherPallet)

    local outputZoneState = context.State.new()
    local cutterLocations = {
        { x = context.config.cutterPlacement.spawnX, y = context.config.cutterPlacement.spawnY },
        { x = 520, y = 460 },
    }
    for locationIndex, location in ipairs(cutterLocations) do
        outputZoneState.cutter.x, outputZoneState.cutter.y = location.x, location.y
        for _, direction in ipairs(cutterDirections) do
            outputZoneState.cutter.direction = direction
            local output = context.world.findCutterOutput(outputZoneState, context.assets)
            check(string.format("cutter_output_safe_location_%d_%s", locationIndex, direction), output
                and context.world.isPalletPlacementClear(
                    outputZoneState, context.assets, output.x, output.y))
        end
    end

    local blockedPreferredState, _, outputBlocker = ownershipState("JOB-OUTPUT-BLOCKER", 0, 0)
    local preferredOutput = context.CutterZones.outputCandidates(
        blockedPreferredState, context.config.cutterPlacement)[1]
    outputBlocker.world.x, outputBlocker.world.y = preferredOutput.x, preferredOutput.y
    outputBlocker.world.fromX, outputBlocker.world.fromY = preferredOutput.x, preferredOutput.y
    local alternateOutput = context.world.findCutterOutput(blockedPreferredState, context.assets)
    check("cutter_output_avoids_occupied_preferred_zone", alternateOutput
        and (alternateOutput.x ~= preferredOutput.x or alternateOutput.y ~= preferredOutput.y)
        and context.world.isPalletPlacementClear(
            blockedPreferredState, context.assets, alternateOutput.x, alternateOutput.y))

    local farState, _, farPallet = ownershipState("JOB-FAR", 40, 620)
    context.machine.reset(farState)
    check("cutter_rejects_far_floor_pallet", not context.machine.load(farState)
        and farPallet.location == "warehouse"
        and farState.palletJack.carriedPalletId == nil)
    check("cutter_far_rejection_preserves_invariants", context.PalletState.validate(farState))

    local carriedState, _, carriedPallet = ownershipState(
        "JOB-CARRIED", context.config.cutterPlacement.spawnX + 70, context.config.cutterPlacement.spawnY + 30)
    check("pallet_transition_to_jack", context.PalletState.transition(carriedState, carriedPallet, "on_pallet_jack"))
    context.machine.reset(carriedState)
    check("cutter_rejects_pallet_owned_by_jack", not context.machine.load(carriedState)
        and carriedPallet.location == "on_pallet_jack"
        and carriedState.palletJack.carriedPalletId == carriedPallet.id
        and context.machine.pallet == nil)
    check("cutter_carried_rejection_preserves_invariants", context.PalletState.validate(carriedState))

    local stagedState, _, stagedPallet = ownershipState(
        "JOB-STAGED", context.config.cutterPlacement.spawnX + 72, context.config.cutterPlacement.spawnY + 28)
    context.machine.reset(stagedState)
    check("cutter_accepts_nearby_floor_pallet", context.machine.load(stagedState)
        and stagedPallet.location == "at_cutter"
        and stagedPallet.status == "in_process"
        and stagedState.palletJack.carriedPalletId == nil)
    check("cutter_load_preserves_single_owner", context.PalletState.validate(stagedState))
    context.machine.reset(stagedState)
    check("cutter_reopens_its_owned_pallet", context.machine.load(stagedState)
        and stagedPallet.location == "at_cutter"
        and stagedState.inventory.inProcessPallets == 1
        and context.PalletState.validate(stagedState))
    context.machine.reset(stagedState)

    local illegalState = context.State.new()
    local illegalJob = jobs.createOffer({
        id = "JOB-ILLEGAL", company = "Illegal Transition Co.",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
    })
    jobs.accept(illegalJob)
    illegalState.jobs.active[1] = illegalJob
    local illegalPallet = illegalJob.pallets[1]
    check("pallet_illegal_transition_rejected",
        not context.PalletState.transition(illegalState, illegalPallet, "at_cutter", {
            cutterRadius = context.config.cutterPlacement.palletInputZoneRadius,
        })
        and illegalPallet.location == "awaiting_delivery"
        and illegalPallet.world == nil
        and illegalState.palletJack.carriedPalletId == nil)

    local contestedState, _, firstCutterPallet = ownershipState(
        "JOB-FIRST-CUTTER", context.config.cutterPlacement.spawnX + 60, context.config.cutterPlacement.spawnY + 20)
    local secondJob = jobs.createOffer({
        id = "JOB-SECOND-CUTTER", company = "Second Cutter Co.",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
    })
    jobs.accept(secondJob)
    local secondCutterPallet = secondJob.pallets[1]
    secondCutterPallet.location = "warehouse"
    secondCutterPallet.world = { x = contestedState.cutter.x + 80, y = contestedState.cutter.y + 20,
        direction = "northwest", rotation = 1, fromX = contestedState.cutter.x + 80,
        fromY = contestedState.cutter.y + 20, spawnProgress = 1 }
    contestedState.jobs.active[2] = secondJob
    check("pallet_first_cutter_owner", context.PalletState.transition(
        contestedState, firstCutterPallet, "at_cutter",
        { status = "in_process", cutterRadius = context.config.cutterPlacement.palletInputZoneRadius }))
    check("pallet_second_cutter_owner_rejected", not context.PalletState.transition(
        contestedState, secondCutterPallet, "at_cutter",
        { status = "in_process", cutterRadius = context.config.cutterPlacement.palletInputZoneRadius })
        and secondCutterPallet.location == "warehouse"
        and secondCutterPallet.status == "raw"
        and context.PalletState.validate(contestedState))

    local legacyOwnershipState, _, legacyOwnershipPallet = ownershipState(
        "JOB-LEGACY-OWNER", context.config.cutterPlacement.spawnX + 50, context.config.cutterPlacement.spawnY + 20)
    legacyOwnershipPallet.location = "at_cutter"
    legacyOwnershipPallet.status = "in_process"
    legacyOwnershipState.palletJack.carriedPalletId = legacyOwnershipPallet.id
    check("pallet_legacy_double_owner_detected", not context.PalletState.validate(legacyOwnershipState))
    check("pallet_legacy_double_owner_reconciled", context.PalletState.reconcile(legacyOwnershipState)
        and legacyOwnershipPallet.location == "at_cutter"
        and legacyOwnershipState.palletJack.carriedPalletId == nil
        and context.PalletState.validate(legacyOwnershipState))

end

return Test
