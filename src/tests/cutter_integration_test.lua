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
        pallet.awaitingPalletReturn = false
        context.machine.reset(repeatState)
        check("six_lift_program_resumes", context.machine.load(repeatState)
            and context.machine.step == "repeat_ready")
        for completed = 2, 6 do
            check("six_lift_repeat_starts_" .. completed, context.machine.repeatLift(repeatState))
            context.machine.update(context.machine.transferTime + 0.01, repeatState)
            check("six_lift_requires_manual_cuts_" .. completed,
                context.machine.step == "loaded" and pallet.paper.status == "uncut")
            for cutNumber = 1, #pallet.paper.cuts do
                context.machine.selectProgram(cutNumber, repeatState)
                context.machine.rotate(repeatState)
                context.machine.setGauge(pallet.paper.cuts[cutNumber].gauge, repeatState)
                context.machine.position(repeatState)
                context.machine.update(context.machine.transferTime + 0.01, repeatState)
                context.machine.toggleClamp(repeatState)
                context.machine.keypressed("j", repeatState)
                context.machine.keypressed("k", repeatState)
                context.machine.update(0.01, repeatState)
                context.machine.update(context.machine.cycleTime + 0.01, repeatState)
                context.machine.keyreleased("j")
                context.machine.keyreleased("k")
            end
            check("six_lift_progress_" .. completed,
                pallet.completedLifts == completed
                and pallet.remainingSheets == 3000 - completed * 500
                and pallet.finishedSheets == completed * 500
                and pallet.lastLiftSheets == 500
                and context.machine.step == "cut_complete")
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
            if completed < 6 then
                check("six_lift_returns_to_pallet_" .. completed,
                    context.machine.unload(repeatState))
                context.machine.update(context.machine.transferTime + 0.01, repeatState)
                check("six_lift_ready_after_return_" .. completed,
                    context.machine.step == "repeat_ready" and not pallet.awaitingPalletReturn)
            end
        end
        context.machine.reset(repeatState)
    end
    verifySixLiftRepeatRun()

    local function verifyMultiplayerSafeMachineLifecycle()
        local saleState = context.State.new()
        local installedCutter = context.machineFleet.installed(saleState, "polar_115")
        local idleLeaseSaleAllowed, idleLeaseSaleReason = context.machine.validateSale(
            installedCutter, true)
        check("cutter_active_lease_blocks_installed_machine_sale",
            not idleLeaseSaleAllowed
            and idleLeaseSaleReason:find("active cutter console", 1, true) ~= nil)
        saleState.inventory.paper = 100
        context.machine.reset(saleState)
        check("cutter_generic_stock_loads_for_sale_contention_test",
            context.machine.load(saleState, "__generic_stock__"))
        check("cutter_generic_batch_blocks_relocation_without_active_lease",
            not context.world.beginCutterMove(saleState, false)
            and saleState.message:find("cutter batch", 1, true) ~= nil)
        check("cutter_generic_batch_blocks_rotation_without_active_lease",
            not context.world.rotateCutter(saleState, false)
            and saleState.message:find("cutter batch", 1, true) ~= nil)
        local activeSale, activeSaleReason = context.machineFleet.sell(
            saleState, installedCutter.id, "online")
        check("cutter_active_generic_batch_blocks_installed_machine_sale",
            not activeSale and activeSaleReason:find("cutter batch", 1, true) ~= nil
            and context.machineFleet.byId(saleState, installedCutter.id) == installedCutter)
        context.machine.reset(saleState)

        local coldState = context.State.new()
        local coldJob = jobs.createOffer({
            id = "JOB-COLD-CUTTER", company = "Cold State Co.",
            sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
            sheetCounts = { 500 },
        })
        jobs.accept(coldJob)
        coldState.jobs.active[1] = coldJob
        coldJob.pallets[1].location = "at_cutter"
        context.machine.reset(coldState)
        local coldDirection = coldState.cutter.direction
        check("cutter_persisted_pallet_blocks_rotation_after_cold_reset",
            not context.world.rotateCutter(coldState, false)
            and coldState.cutter.direction == coldDirection
            and coldState.message:find("clear the cutting bed", 1, true) ~= nil)

        local networkState = context.State.new()
        local networkJob = jobs.createOffer({
            id = "JOB-CUTTER-NETWORK", company = "Network Cutter Co.",
            sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
            sheetCounts = { 750 },
        })
        jobs.accept(networkJob)
        networkState.jobs.active[1] = networkJob
        local networkPallet = networkJob.pallets[1]
        local networkPaper = networkPallet.paper
        local anchorX, anchorY = context.CutterZones.inputAnchor(
            networkState, context.config.cutterPlacement)
        networkPallet.location = "warehouse"
        networkPallet.world = {
            x = anchorX, y = anchorY, direction = "northwest", rotation = 1,
            fromX = anchorX, fromY = anchorY, spawnProgress = 1,
        }

        context.machine.reset(networkState)
        local availableView = context.machine.networkView(networkState, true)
        check("cutter_network_view_idle_shape", availableView.step == "idle"
            and type(availableView.runtimeRevision) == "number"
            and type(availableView.phasePermille) == "number"
            and type(availableView.memoryCentiInch) == "table"
            and availableView.paper == nil)
        check("cutter_network_view_lists_load_candidates", type(availableView.candidates) == "table"
            and #availableView.candidates == 1
            and availableView.candidates[1].palletId == networkPallet.id
            and availableView.candidates[1].distancePixels == 0)

        networkState.inventory.paper = 100
        networkPallet.world.x, networkPallet.world.y = anchorX + 1000, anchorY + 1000
        local unstagedView = context.machine.networkView(networkState, true)
        check("cutter_network_view_does_not_offer_blocked_generic_stock",
            type(unstagedView.candidates) == "table" and #unstagedView.candidates == 0
            and unstagedView.genericSheets == nil)
        networkPallet.world.x, networkPallet.world.y = anchorX, anchorY

        local bulkStockState = context.State.new()
        bulkStockState.inventory.paper = 100001
        context.machine.reset(bulkStockState)
        local bulkStockView = context.machine.networkView(bulkStockState, true)
        check("cutter_network_view_clamps_bulk_generic_stock_to_wire_limit",
            bulkStockView.genericSheets == 100000)
        context.machine.reset(networkState)

        check("cutter_network_loads_named_candidate",
            context.machine.load(networkState, networkPallet.id))
        check("cutter_network_load_transition_not_durable",
            not context.machine.update(context.machine.transferTime + 0.01, networkState)
            and context.machine.step == "loaded")
        local activeView = context.machine.networkView(networkState, true)
        check("cutter_network_view_active_paper_shape", activeView.loaded
            and activeView.candidates == nil
            and activeView.paper
            and activeView.paper.palletId == networkPallet.id
            and activeView.paper.activeCut == 1
            and activeView.paper.cutCount == #networkPaper.cuts
            and activeView.paper.activeLift == 1
            and activeView.paper.requiredLifts == 2
            and activeView.paper.remainingSheets == 750
            and activeView.paper.selectedCut
            and activeView.paper.selectedCut.active)

        local preservedStep = context.machine.step
        local preservedRevision = context.machine.runtimeRevision
        check("cutter_open_preserves_live_runtime", context.machine.open(networkState)
            and context.machine.paper == networkPaper
            and context.machine.pallet == networkPallet
            and context.machine.step == preservedStep
            and context.machine.runtimeRevision == preservedRevision)
        networkState.screen = "world"
        context.input.keypressed("e", {
            state = networkState,
            assets = context.assets,
            world = {
                getInteraction = function() return { kind = "cutter" } end,
                faceInteraction = function() end,
            },
            machine = context.machine,
            machineScreen = { enter = function() end },
            isNetworkClient = function() return false end,
            networkInteraction = function() return false end,
        })
        check("cutter_local_console_reentry_preserves_live_runtime",
            networkState.screen == "machine" and networkState.machineType == "cutter"
            and context.machine.paper == networkPaper
            and context.machine.pallet == networkPallet
            and context.machine.step == preservedStep
            and context.machine.runtimeRevision == preservedRevision)
        context.machine.reset(networkState)
        check("cutter_reset_leaves_owned_pallet_recoverable",
            networkPallet.location == "at_cutter" and context.machine.paper == nil)
        check("cutter_open_restores_at_cutter_pallet", context.machine.open(networkState)
            and context.machine.paper == networkPaper
            and context.machine.pallet == networkPallet
            and context.machine.step == "loading")
        check("cutter_restored_pallet_finishes_safe_load",
            not context.machine.update(context.machine.transferTime + 0.01, networkState)
            and context.machine.step == "loaded")

        check("cutter_guarded_cut_requires_clamped_work", not context.machine.guardedCut(networkState)
            and context.machine.step == "loaded")
        local firstCut = networkPaper.cuts[1]
        context.machine.selectProgram(1, networkState)
        context.machine.rotate(networkState)
        context.machine.setGauge(firstCut.gauge, networkState)
        context.machine.position(networkState)
        context.machine.update(context.machine.transferTime + 0.01, networkState)
        context.machine.toggleClamp(networkState)
        context.machine.gauge = firstCut.gauge + 0.25
        check("cutter_guarded_cut_revalidates_host_gauge", not context.machine.guardedCut(networkState)
            and context.machine.step == "clamped")
        context.machine.gauge = firstCut.gauge
        context.machine.programIndex = 2
        check("cutter_guarded_cut_revalidates_host_program", not context.machine.guardedCut(networkState)
            and context.machine.step == "clamped")
        context.machine.programIndex = 1
        context.machine.setBarrier(false, networkState)
        check("cutter_guarded_cut_revalidates_host_safety", not context.machine.guardedCut(networkState)
            and context.machine.step == "blocked")

        local blockedPaper, blockedPallet = context.machine.paper, context.machine.pallet
        check("cutter_reset_safety_starts_without_orphaning", context.machine.resetSafety(networkState)
            and context.machine.step == "resetting"
            and context.machine.paper == blockedPaper
            and context.machine.pallet == blockedPallet
            and networkPallet.location == "at_cutter")
        check("cutter_reset_safety_resumes_loaded_work",
            not context.machine.update(0.36, networkState)
            and context.machine.step == "loaded"
            and context.machine.loaded
            and not context.machine.clamp
            and context.machine.barrierClear
            and not context.machine.emergencyStopped
            and context.machine.paper == blockedPaper
            and context.machine.pallet == blockedPallet)

        context.machine.position(networkState)
        context.machine.update(context.machine.transferTime + 0.01, networkState)
        context.machine.toggleClamp(networkState)
        context.machine.keypressed("j", networkState)
        check("cutter_release_operator_raises_stable_clamp",
            context.machine.releaseOperator(networkState)
            and not context.machine.leftDown and not context.machine.rightDown
            and not context.machine.clamp and context.machine.step == "positioned")
        check("cutter_release_operator_is_idempotent", not context.machine.releaseOperator(networkState))

        context.machine.toggleClamp(networkState)
        context.machine.keypressed("j", networkState)
        context.machine.keypressed("k", networkState)
        check("cutter_release_operator_does_not_abort_inflight_cut",
            context.machine.step == "armed"
            and context.machine.releaseOperator(networkState)
            and context.machine.step == "armed"
            and context.machine.clamp
            and not context.machine.leftDown and not context.machine.rightDown)
        check("cutter_cut_update_is_not_early",
            not context.machine.update(0.01, networkState) and context.machine.step == "cutting")
        context.machine.progress = context.machine.cycleTime - 0.005
        local activeCutBeforeStop = networkPaper.activeCut
        local preemptedDirty = context.serviceNetworkBeforeMachine(
            0.02, networkState, function()
                context.machine.emergencyStop(networkState)
            end)
        check("cutter_network_safety_is_serviced_before_near_complete_blade_frame",
            not preemptedDirty and context.machine.step == "blocked"
            and networkPaper.activeCut == activeCutBeforeStop)
        check("cutter_network_preempted_cut_resumes_safely",
            context.machine.resetSafety(networkState)
            and not context.machine.update(0.36, networkState)
            and context.machine.step == "loaded")
        context.machine.position(networkState)
        context.machine.update(context.machine.transferTime + 0.01, networkState)
        context.machine.toggleClamp(networkState)
        context.machine.guardedCut(networkState)
        context.machine.update(0.01, networkState)
        check("cutter_cut_update_reports_durable_milestone",
            context.machine.update(context.machine.cycleTime + 0.01, networkState)
            and networkPaper.activeCut == 2)
        check("cutter_cut_update_reports_milestone_once", not context.machine.update(0, networkState))

        local function finishRemainingCuts(firstNumber)
            local liftNumber = networkPallet.activeLift
            for cutNumber = firstNumber, #networkPaper.cuts do
                local cut = networkPaper.cuts[cutNumber]
                context.machine.selectProgram(cutNumber, networkState)
                context.machine.rotate(networkState)
                context.machine.setGauge(cut.gauge, networkState)
                context.machine.position(networkState)
                check("cutter_network_position_update_not_durable_" .. liftNumber .. "_" .. cutNumber,
                    not context.machine.update(context.machine.transferTime + 0.01, networkState))
                context.machine.toggleClamp(networkState)
                check("cutter_network_guarded_cut_accepted_" .. liftNumber .. "_" .. cutNumber,
                    context.machine.guardedCut(networkState))
                check("cutter_network_cut_arming_not_durable_" .. liftNumber .. "_" .. cutNumber,
                    not context.machine.update(0.01, networkState))
                check("cutter_network_cut_durable_" .. liftNumber .. "_" .. cutNumber,
                    context.machine.update(context.machine.cycleTime + 0.01, networkState))
                check("cutter_network_cut_durable_once_" .. liftNumber .. "_" .. cutNumber,
                    not context.machine.update(0, networkState))
            end
        end

        finishRemainingCuts(2)
        check("cutter_network_first_lift_complete", context.machine.step == "cut_complete"
            and networkPallet.completedLifts == 1 and networkPallet.remainingSheets == 250)
        context.machine.emergencyStop(networkState)
        check("cutter_reset_safety_preserves_complete_lift",
            context.machine.resetSafety(networkState)
            and context.machine.paper == networkPaper and context.machine.pallet == networkPallet)
        check("cutter_reset_safety_resumes_cut_complete",
            not context.machine.update(0.36, networkState)
            and context.machine.step == "cut_complete"
            and context.machine.loaded and networkPallet.location == "at_cutter")

        check("cutter_network_starts_lift_return", context.machine.unload(networkState)
            and context.machine.step == "lift_returning")
        check("cutter_lift_return_update_is_not_early",
            not context.machine.update(context.machine.transferTime / 2, networkState))
        check("cutter_lift_return_update_reports_durable_milestone",
            context.machine.update(context.machine.transferTime / 2 + 0.01, networkState)
            and context.machine.step == "repeat_ready"
            and not networkPallet.awaitingPalletReturn)
        check("cutter_lift_return_update_reports_milestone_once",
            not context.machine.update(0, networkState))

        context.machine.emergencyStop(networkState)
        check("cutter_repeat_ready_estop_resets_without_bogus_return",
            context.machine.resetSafety(networkState)
            and not context.machine.update(0.36, networkState)
            and context.machine.step == "repeat_ready"
            and not context.machine.loaded
            and not networkPallet.awaitingPalletReturn
            and networkPallet.remainingSheets == 250)

        context.machine.repeatLift(networkState)
        context.machine.update(context.machine.transferTime + 0.01, networkState)
        finishRemainingCuts(1)
        check("cutter_network_final_lift_complete", context.machine.step == "cut_complete"
            and networkPallet.completedLifts == 2 and networkPallet.remainingSheets == 0)
        context.machine.setOutputResolver(function(targetState, pallet)
            return context.world.findCutterOutput(targetState, context.assets, pallet and pallet.id)
        end)
        check("cutter_network_starts_final_unload", context.machine.unload(networkState)
            and context.machine.step == "unloading")
        check("cutter_unload_update_is_not_early",
            not context.machine.update(context.machine.transferTime / 2, networkState))
        check("cutter_unload_update_reports_durable_milestone",
            context.machine.update(context.machine.transferTime / 2 + 0.01, networkState)
            and context.machine.step == "finished"
            and networkPallet.location == "cutter_output")
        check("cutter_unload_update_reports_milestone_once", not context.machine.update(0, networkState))

        context.machine.emergencyStop(networkState)
        check("cutter_finished_estop_reset_does_not_resurrect_unloaded_pallet",
            context.machine.resetSafety(networkState)
            and not context.machine.update(0.36, networkState)
            and context.machine.step == "idle" and not context.machine.loaded
            and context.machine.paper == nil and context.machine.pallet == nil
            and networkPallet.location == "cutter_output")

        context.machine.setOutputResolver(nil)
        context.machine.reset(context.state)
    end
    verifyMultiplayerSafeMachineLifecycle()

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
    for _, orientation in ipairs({ 0, 90, 180, 270 }) do
        check("cutter_artwork_rotation_tracks_stock_" .. orientation,
            math.abs(context.machineScreen.artworkRotation({ orientation = orientation })
                - math.rad(orientation)) < 0.0001)
    end

    context.machine.reset(cutterState)
    check("cutter_table_starts_clear", not context.machine.loaded and context.machine.step == "idle")
    context.machineScreen.enter()
    check("cutter_load_button_opens_pallet_menu", context.machineScreen.keypressed(cutterState, "l")
        and context.machineScreen.hasModal()
        and #context.machineScreen.loadMenuOptions() == 1)
    check("cutter_load_menu_selects_named_pallet", context.machineScreen.keypressed(cutterState, "1")
        and context.machine.pallet == cutterJob.pallets[1])
    context.machine.update(context.machine.transferTime + 0.01, cutterState)
    check("cutter_load_animation", context.machine.step == "loaded" and context.machine.paper == trackedPaper)
    check("cutter_rejects_wrong_gauge", not context.machine.position(cutterState))
    context.machineScreen.enter()
    local gaugeInputX, gaugeInputY = context.machineScreen.gaugeInputCenter()
    check("cutter_gauge_requires_explicit_field_focus",
        not context.machineScreen.wantsTextInput()
        and context.machineScreen.mousepressed(cutterState, gaugeInputX, gaugeInputY, 1)
        and context.machineScreen.wantsTextInput())
    local typedGauge = string.format("%.2f", trackedPaper.cuts[1].gauge)
    for character in typedGauge:gmatch(".") do
        check("cutter_accepts_typed_character_" .. character,
            context.machineScreen.textinput(cutterState, character))
    end
    check("cutter_enter_commits_typed_gauge", context.machineScreen.keypressed(cutterState, "return")
        and math.abs(context.machine.gauge - trackedPaper.cuts[1].gauge) < 0.001)
    local firstGauge = trackedPaper.cuts[1].gauge
    check("cutter_autoset_rejects_unsaved_cut_memory",
        context.machine.selectProgram(2, cutterState)
        and not context.machine.autoGauge(cutterState))
    context.machine.selectProgram(1, cutterState)
    context.machine.setGauge(firstGauge, cutterState); context.machine.saveGauge(cutterState)
    context.machine.setGauge(firstGauge + 0.50, cutterState); context.machine.saveGauge(cutterState)
    context.machine.setGauge(firstGauge + 1.00, cutterState); context.machine.saveGauge(cutterState)
    context.machine.setGauge(firstGauge + 1.50, cutterState); context.machine.saveGauge(cutterState)
    context.machine.setGauge(firstGauge, cutterState); context.machine.saveGauge(cutterState)
    local cutOneMemory = context.machine.savedMeasurements(cutterState, 1)
    check("cutter_keeps_three_recent_measurements_per_cut", #cutOneMemory == 3
        and math.abs(cutOneMemory[1] - firstGauge) < 0.001
        and math.abs(cutOneMemory[2] - firstGauge - 1.50) < 0.001
        and math.abs(cutOneMemory[3] - firstGauge - 1.00) < 0.001)
    check("cutter_autoset_cycles_newest_first", context.machine.autoGauge(cutterState)
        and math.abs(context.machine.gauge - firstGauge) < 0.001
        and context.machine.autoGauge(cutterState)
        and math.abs(context.machine.gauge - firstGauge - 1.50) < 0.001
        and context.machine.autoGauge(cutterState)
        and math.abs(context.machine.gauge - firstGauge - 1.00) < 0.001
        and context.machine.autoGauge(cutterState)
        and math.abs(context.machine.gauge - firstGauge) < 0.001)
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
            check("cutter_manual_save_for_program_" .. cutNumber,
                context.machine.setGauge(trackedPaper.cuts[cutNumber].gauge, cutterState)
                and context.machine.saveGauge(cutterState))
            check("cutter_keyboard_auto_gauge_" .. cutNumber, context.machine.keypressed("g", cutterState))
        end
        check("cutter_auto_recalls_saved_program_" .. cutNumber,
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
        and context.machine.step == "cut_complete"
        and cutterJob.pallets[1].completedLifts == 1
        and cutterJob.pallets[1].remainingSheets == 250
        and cutterJob.pallets[1].finishedSheets == 500
        and cutterJob.pallets[1].programVerified)
    check("paper_tooltip_updates_size", context.machine.paperTooltip():find("12.50 x 9.50", 1, true) ~= nil)
    check("cutter_returns_each_lift_to_pallet", context.machine.keypressed("u", cutterState)
        and context.machine.step == "lift_returning")
    context.machine.update(context.machine.transferTime + 0.01, cutterState)
    check("cutter_next_lift_waits_after_pallet_return", context.machine.step == "repeat_ready"
        and cutterJob.pallets[1].remainingSheets == 250)
    check("cutter_repeat_lift_starts", context.machine.keypressed("t", cutterState)
        and context.machine.step == "loading")
    context.machine.update(context.machine.transferTime + 0.01, cutterState)
    check("cutter_repeat_lift_requires_manual_cutting", context.machine.step == "loaded"
        and trackedPaper.status == "uncut" and trackedPaper.activeCut == 1)
    for cutNumber = 1, 4 do
        context.machine.selectProgram(cutNumber, cutterState)
        context.machine.rotate(cutterState)
        context.machine.setGauge(trackedPaper.cuts[cutNumber].gauge, cutterState)
        context.machine.position(cutterState)
        context.machine.update(context.machine.transferTime + 0.01, cutterState)
        context.machine.toggleClamp(cutterState)
        context.machine.keypressed("j", cutterState)
        context.machine.keypressed("k", cutterState)
        context.machine.update(0.01, cutterState)
        context.machine.update(context.machine.cycleTime + 0.01, cutterState)
        context.machine.keyreleased("j")
        context.machine.keyreleased("k")
    end
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

    local cutterDirections = {
        "northwest", "north", "northeast", "east",
        "southeast", "south", "southwest", "west",
    }
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
    local expandedAnchorX, expandedAnchorY = context.CutterZones.inputAnchor(
        fartherState, context.config.cutterPlacement)
    fartherPallet.world.x, fartherPallet.world.y = expandedAnchorX + 110, expandedAnchorY
    fartherPallet.world.fromX, fartherPallet.world.fromY = fartherPallet.world.x, fartherPallet.world.y
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
    check("cutter_expanded_radius_detects_distant_pallet",
        context.config.cutterPlacement.palletInputZoneRadius >= 120
        and sortedInputs[2] and sortedInputs[2].pallet == fartherPallet)
    context.machine.reset(fartherState)
    context.machineScreen.enter()
    check("cutter_multi_pallet_menu_lists_every_candidate",
        context.machineScreen.keypressed(fartherState, "l")
        and #context.machineScreen.loadMenuOptions() == 2)
    check("cutter_multi_pallet_menu_can_choose_non_nearest",
        context.machineScreen.keypressed(fartherState, "2")
        and context.machine.pallet == fartherPallet
        and fartherPallet.location == "at_cutter"
        and nearerPallet.location == "warehouse")
    context.machine.reset(fartherState)

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
