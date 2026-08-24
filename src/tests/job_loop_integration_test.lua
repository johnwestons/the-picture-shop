local Test = {}

function Test.run(context, check, jobs)
    local function verifyFullJobLoop()
    local fullLoopState = context.State.new()
    fullLoopState.screen = "world"
    local fullLoopOffer = jobs.createOffer({
        id = "JOB-FULL-LOOP",
        company = "Complete Workflow Co.",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
        packaging = "flat",
    })
    local fullLoopStartingCash = fullLoopState.money
    check("full_loop_accepts_job", context.jobService.acceptOffer(fullLoopState, fullLoopOffer, 100)
        and fullLoopState.accountsReceivable == 150
        and fullLoopState.money == fullLoopStartingCash)
    check("full_loop_receives_inbound_pallet", context.PalletLogistics.unload(
        fullLoopState, fullLoopOffer.id, fullLoopOffer.pallets[1].id,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin))
    local fullLoopPallet = fullLoopOffer.pallets[1]
    local inputX, inputY = context.CutterZones.inputAnchor(fullLoopState, context.config.cutterPlacement)
    check("full_loop_lifts_inbound_pallet",
        context.PalletState.transition(fullLoopState, fullLoopPallet, "on_pallet_jack"))
    check("full_loop_stages_cutter_input", context.PalletState.transition(
        fullLoopState, fullLoopPallet, "warehouse", { world = {
            x = inputX, y = inputY, direction = "northwest", rotation = 1,
            fromX = inputX, fromY = inputY, spawnProgress = 1,
        } }))

    context.machine.reset(fullLoopState)
    check("full_loop_loads_cutter", context.machine.load(fullLoopState))
    context.machine.update(context.machine.transferTime + 0.01, fullLoopState)
    for cutNumber = 1, 4 do
        context.machine.selectProgram(cutNumber, fullLoopState)
        context.machine.keypressed("q", fullLoopState)
        context.machine.autoGauge(fullLoopState)
        check("full_loop_positions_cut_" .. cutNumber, context.machine.position(fullLoopState))
        context.machine.update(context.machine.transferTime + 0.01, fullLoopState)
        context.machine.toggleClamp(fullLoopState)
        context.machine.keypressed("j", fullLoopState)
        context.machine.keypressed("k", fullLoopState)
        context.machine.keyreleased("j")
        context.machine.keyreleased("k")
        context.machine.update(0.01, fullLoopState)
        context.machine.update(context.machine.cycleTime + 0.05, fullLoopState)
    end
    check("full_loop_finishes_cutting", fullLoopPallet.paper.status == "complete"
        and fullLoopPallet.remainingSheets == 0
        and fullLoopPallet.completedLifts == 1
        and fullLoopPallet.lastLiftSheets == 500
        and context.machine.step == "cut_complete")
    context.machine.keypressed("u", fullLoopState)
    context.machine.update(context.machine.transferTime + 0.01, fullLoopState)
    check("full_loop_returns_cut_pallet", fullLoopPallet.location == "cutter_output"
        and fullLoopPallet.status == "cut"
        and fullLoopPallet.remainingSheets == 0
        and fullLoopPallet.finishedSheets == 500)

    local wrapWorld = {
        x = fullLoopState.wrapper.x - 60, y = fullLoopState.wrapper.y,
        direction = "northwest", rotation = 1,
        fromX = fullLoopState.wrapper.x - 60, fromY = fullLoopState.wrapper.y, spawnProgress = 1,
    }
    check("full_loop_lifts_cut_pallet",
        context.PalletState.transition(fullLoopState, fullLoopPallet, "on_pallet_jack"))
    check("full_loop_stages_wrapper", context.PalletState.transition(
        fullLoopState, fullLoopPallet, "warehouse", { world = wrapWorld }))
    context.wrapper.reset(fullLoopState)
    check("full_loop_starts_wrapping", context.wrapper.start(fullLoopState))
    context.wrapper.update(context.wrapper.cycleTime + 0.01, fullLoopState)
    check("full_loop_finishes_wrapping", fullLoopPallet.status == "wrapped"
        and fullLoopPallet.wrapped
        and fullLoopState.inventory.plasticWrapUses == 10)

    context.computerScreen.enter(fullLoopState)
    fullLoopState.screen = "computer"
    local fullLoopSaveCalls = 0
    local fullLoopInput = {}
    for key, value in pairs(context.inputContext) do fullLoopInput[key] = value end
    fullLoopInput.state = fullLoopState
    fullLoopInput.saveCurrent = function() fullLoopSaveCalls = fullLoopSaveCalls + 1; return true end
    local pickupX, pickupY = context.computerScreen.completeCenter()
    check("full_loop_requests_pickup", context.input.mousepressed(
        pickupX, pickupY, 1, fullLoopInput)
        and fullLoopOffer.status == "ready_for_pickup"
        and fullLoopOffer.pickup.status == "awaiting_schedule"
        and fullLoopSaveCalls == 1)

    context.world.load()
    fullLoopState.screen = "world"
    local pickupScheduledSave = context.world.update(
        context.config.truck.scheduleDelay + 0.1, 0, 0, context.assets, fullLoopState)
    check("full_loop_pickup_truck_scheduled", pickupScheduledSave
        and context.world.truckSnapshot().mode == "pickup"
        and context.world.truckSnapshot().state == "waiting_for_bay"
        and fullLoopOffer.status == "pickup_in_progress", string.format(
            "save=%s mode=%s truck=%s job=%s pickup=%s",
            tostring(pickupScheduledSave), tostring(context.world.truckSnapshot().mode),
            tostring(context.world.truckSnapshot().state), tostring(fullLoopOffer.status),
            tostring(fullLoopOffer.pickup and fullLoopOffer.pickup.status)))
    context.world.update(context.config.loadingBay.duration + 0.1, 0, 0, context.assets, fullLoopState)
    context.world.update(context.config.truck.backingDuration + 0.1, 0, 0, context.assets, fullLoopState)
    check("full_loop_pickup_truck_parked", context.world.truckSnapshot().state == "parked_closed"
        and fullLoopOffer.pickup.status == "at_bay")
    context.world.toggleTruckCargoDoor(fullLoopState)
    context.world.update(context.config.truck.cargoDuration + 0.1, 0, 0, context.assets, fullLoopState)
    check("full_loop_pickup_cargo_open", context.world.truckSnapshot().state == "cargo_open"
        and fullLoopOffer.pickup.status == "cargo_open")

    fullLoopState.screen = "truck_inventory"
    local loadX, loadY = context.truckInventoryScreen.unloadButtonCenter(1)
    check("full_loop_manifest_loads_pallet", context.input.mousepressed(
        loadX, loadY, 1, fullLoopInput)
        and fullLoopPallet.location == "outbound_truck"
        and fullLoopPallet.world == nil
        and fullLoopOffer.pickup.status == "loaded"
        and fullLoopState.inventory.finishedPallets == 0
        and fullLoopSaveCalls == 2)
    check("full_loop_pickup_checkpoint_saves", context.save.save(
        3, fullLoopState, { x = 500, y = 455 }))
    local savedPickup = context.save.load(3)
    check("full_loop_pickup_checkpoint_round_trip", savedPickup
        and savedPickup.state.jobs.active[1].status == "pickup_in_progress"
        and savedPickup.state.jobs.active[1].pickup.status == "loaded"
        and savedPickup.state.jobs.active[1].pallets[1].location == "outbound_truck"
        and savedPickup.state.inventory.finishedPallets == 0
        and savedPickup.state.accountsReceivable == 150)
    context.save.delete(3)
    local pickupDoorX, pickupDoorY = context.truckInventoryScreen.closeDoorCenter()
    check("full_loop_closes_loaded_pickup", context.input.mousepressed(
        pickupDoorX, pickupDoorY, 1, fullLoopInput)
        and fullLoopState.screen == "world"
        and context.world.truckSnapshot().state == "cargo_closing"
        and fullLoopSaveCalls == 3)
    context.world.update(context.config.truck.cargoDuration + 0.1, 0, 0, context.assets, fullLoopState)
    local pickupCompletedSave = context.world.update(
        context.config.truck.backingDuration + 0.1, 0, 0, context.assets, fullLoopState)
    check("full_loop_pickup_archives_and_pays", pickupCompletedSave
        and context.world.truckSnapshot().state == "absent"
        and #fullLoopState.jobs.active == 0
        and #fullLoopState.jobs.completed == 1
        and fullLoopState.jobs.completed[1] == fullLoopOffer
        and fullLoopOffer.status == "completed"
        and fullLoopPallet.location == "none"
        and fullLoopPallet.status == "picked_up"
        and fullLoopState.accountsReceivable == 0
        and fullLoopState.money == fullLoopStartingCash + 150)
    local cashAfterPickup = fullLoopState.money
    check("full_loop_payment_cannot_repeat", not context.jobService.completePickup(
        fullLoopState, fullLoopOffer.id, 999)
        and fullLoopState.money == cashAfterPickup)
    context.computerScreen.enter(fullLoopState)
    local fullLoopCompletedX, fullLoopCompletedY = context.computerScreen.tabCenter("completed")
    context.computerScreen.mousepressed(fullLoopState, fullLoopCompletedX, fullLoopCompletedY, 1)
    local completedRowX, completedRowY = context.computerScreen.rowCenter(1)
    local completedSelection = context.computerScreen.mousepressed(
        fullLoopState, completedRowX, completedRowY, 1)
    check("full_loop_completed_job_visible", completedSelection
        and completedSelection.job == fullLoopOffer
        and fullLoopOffer.paymentAmount == 150
        and fullLoopOffer.paidAt ~= nil)
    context.world.update(context.config.loadingBay.duration + 0.1, 0, 0, context.assets, fullLoopState)
    context.wrapper.reset(fullLoopState)
    context.machine.reset(fullLoopState)
    context.world.load()
    context.world.update(10, 0, 0, context.assets, context.state)
    end
    verifyFullJobLoop()
end

return Test
