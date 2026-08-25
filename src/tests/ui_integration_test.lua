local Test = {}

function Test.run(context, check)
    -- Title actions share one mouse/keyboard path. Exercise them against the
    -- smoke identity so the player's real save directory is never touched.
    context.save.delete(3)
    local occupiedState = context.State.new()
    occupiedState.money = 777
    check("title_occupied_slot_setup", context.save.save(3, occupiedState, { x = 333, y = 444 }))
    local occupiedBytes = love.filesystem.read("saves/slot3.lua")
    local titleStarts = {}
    local function captureTitleStart(startPayload, mode)
        local event = { payload = startPayload, mode = mode }
        titleStarts[#titleStarts + 1] = event
        if mode == "new" then
            event.saved = context.save.save(startPayload.slot, startPayload.state, startPayload.player)
        end
    end

    context.state.screen = "title"
    context.title.enter(captureTitleStart)
    context.input.keypressed("down", context.inputContext)
    check("title_keyboard_down_selects", context.title.selected == 2)
    context.input.keypressed("s", context.inputContext)
    check("title_keyboard_s_selects", context.title.selected == 3)
    context.input.keypressed("down", context.inputContext)
    check("title_keyboard_down_wraps", context.title.selected == 1)
    context.input.keypressed("up", context.inputContext)
    check("title_keyboard_up_wraps", context.title.selected == 3)
    context.input.keypressed("w", context.inputContext)
    check("title_keyboard_w_selects", context.title.selected == 2)
    context.input.keypressed("s", context.inputContext)

    local newX, newY = context.title.buttonCenter("new")
    local confirmX, confirmY = context.title.buttonCenter("yes")
    local cancelX, cancelY = context.title.buttonCenter("no")
    check("title_mouse_new_requires_overwrite_confirmation",
        context.input.mousepressed(newX, newY, 1, context.inputContext)
        and context.title.mode == "overwrite-confirm"
        and #titleStarts == 0
        and love.filesystem.read("saves/slot3.lua") == occupiedBytes)
    context.input.mousereleased(newX, newY, 1, context.inputContext)
    check("title_mouse_overwrite_cancel_preserves_bytes",
        context.input.mousepressed(cancelX, cancelY, 1, context.inputContext)
        and context.title.mode == "normal"
        and #titleStarts == 0
        and love.filesystem.read("saves/slot3.lua") == occupiedBytes)
    context.input.mousereleased(cancelX, cancelY, 1, context.inputContext)

    context.input.keypressed("n", context.inputContext)
    check("title_keyboard_new_requires_overwrite_confirmation",
        context.title.mode == "overwrite-confirm" and #titleStarts == 0)
    context.input.keypressed("n", context.inputContext)
    check("title_keyboard_overwrite_cancel_preserves_bytes",
        context.title.mode == "normal"
        and #titleStarts == 0
        and love.filesystem.read("saves/slot3.lua") == occupiedBytes)

    context.input.mousepressed(newX, newY, 1, context.inputContext)
    check("title_mouse_overwrite_confirmation_starts",
        context.input.mousepressed(confirmX, confirmY, 1, context.inputContext)
        and #titleStarts == 1
        and titleStarts[1].mode == "new"
        and titleStarts[1].saved
        and context.save.load(3).state.money == 180)
    context.input.mousereleased(confirmX, confirmY, 1, context.inputContext)

    occupiedState.money = 888
    context.save.save(3, occupiedState, { x = 333, y = 444 })
    context.title.enter(captureTitleStart)
    context.input.keypressed("up", context.inputContext)
    context.input.keypressed("n", context.inputContext)
    context.input.keypressed("y", context.inputContext)
    check("title_keyboard_overwrite_confirmation_starts",
        #titleStarts == 2
        and titleStarts[2].mode == "new"
        and titleStarts[2].saved
        and context.save.load(3).state.money == 180)

    context.save.delete(3)
    context.title.enter(captureTitleStart)
    context.input.keypressed("up", context.inputContext)
    context.input.keypressed("n", context.inputContext)
    check("title_empty_slot_new_starts_immediately",
        #titleStarts == 3
        and titleStarts[3].mode == "new"
        and titleStarts[3].saved
        and context.save.load(3) ~= nil)

    context.title.enter(captureTitleStart)
    context.input.keypressed("up", context.inputContext)
    context.input.keypressed("c", context.inputContext)
    check("title_keyboard_c_continues",
        #titleStarts == 4 and titleStarts[4].mode == "continue" and titleStarts[4].payload.slot == 3)
    context.title.enter(captureTitleStart)
    context.input.keypressed("up", context.inputContext)
    context.input.keypressed("return", context.inputContext)
    check("title_keyboard_enter_continues",
        #titleStarts == 5 and titleStarts[5].mode == "continue" and titleStarts[5].payload.slot == 3)

    local beforeDeleteCancel = love.filesystem.read("saves/slot3.lua")
    context.title.enter(captureTitleStart)
    context.input.keypressed("up", context.inputContext)
    context.input.keypressed("d", context.inputContext)
    check("title_keyboard_delete_requires_confirmation", context.title.mode == "delete-confirm")
    context.input.keypressed("n", context.inputContext)
    check("title_keyboard_delete_cancel_preserves_bytes",
        context.title.mode == "normal"
        and love.filesystem.read("saves/slot3.lua") == beforeDeleteCancel)
    context.input.keypressed("d", context.inputContext)
    context.input.keypressed("y", context.inputContext)
    check("title_keyboard_delete_confirmation_removes_slot",
        context.title.mode == "normal" and love.filesystem.getInfo("saves/slot3.lua") == nil)

    context.state.screen = "world"
    local reception = context.world.customerSnapshot()
    context.world.player.x, context.world.player.y = reception.x, reception.y + 28
    context.world.update(0, 0, 0, context.assets, context.state)
    local paperworkInteraction = context.world.getInteraction()
    local paperworkCustomer = context.world.customerSnapshot()
    check("paperwork_customer_selected", paperworkInteraction
        and paperworkInteraction.kind == "customer", string.format(
            "selected=%s customer=%s at %.1f,%.1f player=%.1f,%.1f",
            paperworkInteraction and paperworkInteraction.kind or "nil",
            paperworkCustomer.state, paperworkCustomer.x, paperworkCustomer.y,
            context.world.player.x, context.world.player.y))
    context.input.keypressed("e", context.inputContext)
    check("paperwork_popup_opens", context.state.screen == "job_offer"
        and context.state.currentOffer ~= nil
        and context.world.customerSnapshot().state == "reviewing")
    local popupAcceptX, popupAcceptY = context.jobOfferScreen.buttonCenter("accept")
    check("paperwork_mouse_accept", context.input.mousepressed(
        popupAcceptX, popupAcceptY, 1, context.inputContext))
    check("paperwork_mouse_accept_flow", context.state.screen == "world"
        and context.state.currentOffer == nil
        and #context.state.jobs.active == 1
        and context.world.customerSnapshot().state == "exiting"
        and context.world.customerSnapshot().decision == "accepted")

    context.world.player.x, context.world.player.y = 500, 235
    context.world.update(0, 0, 0, context.assets, context.state)
    check("computer_world_interaction_selected", context.world.getInteraction()
        and context.world.getInteraction().kind == "computer")
    context.input.keypressed("e", context.inputContext)
    check("computer_opens_from_world", context.state.screen == "computer")
    local liveInventoryX, liveInventoryY = context.computerScreen.tabCenter("inventory")
    check("computer_live_mouse_tab", context.input.mousepressed(
        liveInventoryX, liveInventoryY, 1, context.inputContext)
        and context.computerScreen.tab == "inventory")
    local liveCloseX, liveCloseY = context.computerScreen.closeCenter()
    check("computer_live_mouse_close", context.input.mousepressed(
        liveCloseX, liveCloseY, 1, context.inputContext)
        and context.state.screen == "world")
    context.input.keypressed("e", context.inputContext)
    check("computer_render_ready", context.state.screen == "computer"
        and #context.state.jobs.active == 1)
    check("computer_final_close", context.input.mousepressed(
        liveCloseX, liveCloseY, 1, context.inputContext)
        and context.state.screen == "world")

    context.world.player.x, context.world.player.y = 300, 335
    context.world.update(context.config.truck.scheduleDelay + 0.1, 0, 0, context.assets, context.state)
    check("accepted_job_waits_for_promised_delivery", context.world.truckSnapshot().state == "absent"
        and context.state.jobs.active[1].delivery.status == "pending_arrival")
    local inboundDelay = context.state.jobs.active[1].delivery.service.delayHours
    context.businessCalendar.update(context.state,
        inboundDelay / 24 * context.config.businessCalendar.secondsPerDay + 0.01)
    context.world.update(context.config.truck.scheduleDelay + 0.1, 0, 0, context.assets, context.state)
    check("accepted_job_schedules_truck", context.world.truckSnapshot().state == "waiting_for_bay"
        and context.world.truckSnapshot().jobId == context.state.jobs.active[1].id
        and context.state.jobs.active[1].delivery.status == "scheduled")
    check("truck_auto_opens_bay", context.world.bayDoorSnapshot().state == "opening")
    context.world.update(context.config.loadingBay.duration + 0.1, 0, 0, context.assets, context.state)
    check("truck_backs_after_bay_opens", context.world.bayDoorSnapshot().state == "open"
        and context.world.truckSnapshot().state == "backing")
    context.world.update(context.config.truck.backingDuration + 0.1, 0, 0, context.assets, context.state)
    check("truck_parks_for_accepted_job", context.world.truckSnapshot().state == "parked_closed"
        and context.state.jobs.active[1].delivery.status == "at_bay")
    check("occupied_bay_cannot_close", not context.world.toggleBayDoor(context.state)
        and context.world.bayDoorSnapshot().state == "open")
    if os.getenv("PICTURE_SHOP_TRUCK_DOCK_PREVIEW") == "1" then return end

    context.world.player.x = context.config.truck.interaction.x
    context.world.player.y = context.config.truck.interaction.y + 36
    context.world.update(0, 0, 0, context.assets, context.state)
    check("truck_cargo_world_interaction_selected", context.world.getInteraction()
        and context.world.getInteraction().kind == "truckCargoDoor")
    context.input.keypressed("e", context.inputContext)
    check("truck_cargo_world_opening", context.world.truckSnapshot().state == "cargo_opening")
    context.world.update(context.config.truck.cargoDuration + 0.1, 0, 0, context.assets, context.state)
    check("truck_cargo_world_open", context.world.truckSnapshot().state == "cargo_open"
        and context.world.truckSnapshot().cargoFrame == context.config.truck.cargoFrameCount)
    context.world.update(0, 0, 0, context.assets, context.state)
    context.input.keypressed("e", context.inputContext)
    check("truck_inventory_opens", context.state.screen == "truck_inventory")
    if os.getenv("PICTURE_SHOP_TRUCK_INVENTORY_PREVIEW") == "1" then return end
    local unload1X, unload1Y = context.truckInventoryScreen.unloadButtonCenter(1)
    local unload2X, unload2Y = context.truckInventoryScreen.unloadButtonCenter(2)
    check("truck_inventory_unload_first", context.input.mousepressed(
        unload1X, unload1Y, 1, context.inputContext))
    check("first_pallet_spawns", #context.world.palletsSnapshot(context.state) == 1
        and context.state.jobs.active[1].pallets[1].location == "warehouse"
        and context.state.inventory.rawPallets == 1)
    context.world.update(context.config.palletLogistics.unloadDuration + 0.1,
        0, 0, context.assets, context.state)
    local firstPhysical = context.world.palletsSnapshot(context.state)[1]
    local palletTooltip = context.world.palletTooltipAt(context.state, firstPhysical.x, firstPhysical.y - 30)
    check("physical_pallet_tooltip", palletTooltip
        and palletTooltip.title:find(context.state.jobs.active[1].company, 1, true)
        and palletTooltip.line1:find("1,000 sheets", 1, true)
        and palletTooltip.line2:find("JOB-0001-P01-PAPER", 1, true))
    check("truck_inventory_unload_second", context.input.mousepressed(
        unload2X, unload2Y, 1, context.inputContext))
    context.world.update(context.config.palletLogistics.unloadDuration + 0.1,
        0, 0, context.assets, context.state)
    check("all_pallets_received", #context.world.palletsSnapshot(context.state) == 2
        and context.state.jobs.active[1].status == "in_production"
        and context.state.jobs.active[1].delivery.status == "received"
        and context.state.inventory.rawPallets == 2)
    local closeDoorX, closeDoorY = context.truckInventoryScreen.closeDoorCenter()
    check("truck_inventory_close_empty_cargo", context.input.mousepressed(
        closeDoorX, closeDoorY, 1, context.inputContext)
        and context.state.screen == "world"
        and context.world.truckSnapshot().state == "cargo_closing")
    context.world.update(context.config.truck.cargoDuration + 0.1, 0, 0, context.assets, context.state)
    check("empty_truck_departs", context.world.truckSnapshot().state == "departing")
    context.world.update(context.config.truck.backingDuration + 0.1, 0, 0, context.assets, context.state)
    check("truck_departed_and_bay_closing", context.world.truckSnapshot().state == "absent"
        and context.world.bayDoorSnapshot().state == "closing")
    context.world.update(context.config.loadingBay.duration + 0.1, 0, 0, context.assets, context.state)
    check("bay_auto_closes_after_delivery", context.world.bayDoorSnapshot().state == "closed")
    check("pallets_render_ready", context.state.screen == "world"
        and #context.world.palletsSnapshot(context.state) == 2)
    check("loose_and_carried_pallet_scale_match",
        context.config.palletLogistics.drawScale
            == context.config.palletJack.drawScale * context.config.palletJack.carriedPalletArtRatio)

    local jackStart = context.world.palletJackSnapshot(context.state)
    context.world.player.x, context.world.player.y = jackStart.x, jackStart.y + 38
    context.world.update(0, 0, 0, context.assets, context.state)
    check("pallet_jack_interaction_selected", context.world.getInteraction()
        and context.world.getInteraction().kind == "palletJack")
    context.input.keypressed("e", context.inputContext)
    check("pallet_jack_mount", context.world.palletJackSnapshot(context.state).operating)
    local operatorX, operatorY = context.PalletJack.operatorPosition(context.state, context.config.palletJack)
    check("pallet_jack_operator_stands_at_handle", context.world.player.x == operatorX
        and context.world.player.y == operatorY
        and math.abs(operatorX - jackStart.x) >= context.config.palletJack.obstacleRadius)
    local beforeDriveX = context.world.palletJackSnapshot(context.state).x
    context.world.update(0.15, -1, 0, context.assets, context.state)
    check("pallet_jack_empty_drive", context.world.palletJackSnapshot(context.state).x < beforeDriveX
        and context.world.palletJackSnapshot(context.state).direction == "west"
        and context.world.palletJackSnapshot(context.state).frame == 8
        and context.world.palletJackSnapshot(context.state).moving
        and context.world.player.moving)
    context.world.update(0.04, 1, 0, context.assets, context.state)
    check("pallet_jack_faces_east", context.world.palletJackSnapshot(context.state).direction == "east"
        and context.world.palletJackSnapshot(context.state).frame == 4)
    context.world.update(0.04, 0, -1, context.assets, context.state)
    check("pallet_jack_faces_north", context.world.palletJackSnapshot(context.state).direction == "north"
        and context.world.palletJackSnapshot(context.state).frame == 2)
    context.world.update(0.04, 0, 1, context.assets, context.state)
    check("pallet_jack_faces_south", context.world.palletJackSnapshot(context.state).direction == "south"
        and context.world.palletJackSnapshot(context.state).frame == 6)
    context.world.update(0.04, -1, -1, context.assets, context.state)
    check("pallet_jack_faces_northwest", context.world.palletJackSnapshot(context.state).direction == "northwest"
        and context.world.palletJackSnapshot(context.state).frame == 1)
    context.world.update(0.04, 1, -1, context.assets, context.state)
    check("pallet_jack_faces_northeast", context.world.palletJackSnapshot(context.state).direction == "northeast"
        and context.world.palletJackSnapshot(context.state).frame == 3)
    context.world.update(0.04, 1, 1, context.assets, context.state)
    check("pallet_jack_faces_southeast", context.world.palletJackSnapshot(context.state).direction == "southeast"
        and context.world.palletJackSnapshot(context.state).frame == 5)
    context.world.update(0.04, -1, 1, context.assets, context.state)
    check("pallet_jack_faces_southwest", context.world.palletJackSnapshot(context.state).direction == "southwest"
        and context.world.palletJackSnapshot(context.state).frame == 7)

    local pickupTarget = context.world.palletsSnapshot(context.state)[1]
    context.state.palletJack.x = pickupTarget.x - 48
    context.state.palletJack.y = pickupTarget.y
    context.world.update(0, 0, 0, context.assets, context.state)
    context.input.keypressed("e", context.inputContext)
    check("pallet_jack_lifts_pallet", context.world.palletJackSnapshot(context.state).carriedPalletId
        == pickupTarget.pallet.id
        and pickupTarget.pallet.location == "on_pallet_jack"
        and #context.world.palletsSnapshot(context.state) == 1)
    context.state.palletJack.x, context.state.palletJack.y = 520, 500
    context.world.player.x, context.world.player.y = 520, 504
    context.world.update(0.18, 0, -1, context.assets, context.state)
    local loadedJack = context.world.palletJackSnapshot(context.state)
    check("pallet_jack_loaded_drive", loadedJack.direction == "north"
        and loadedJack.frame == 2 and loadedJack.palletFrame == 1
        and loadedJack.y < 500
        and pickupTarget.pallet.world.x == loadedJack.x
        and pickupTarget.pallet.world.y == loadedJack.y)
    local carriedTooltip = context.world.palletTooltipAt(context.state, loadedJack.x, loadedJack.y - 40)
    check("carried_pallet_tooltip", carriedTooltip
        and carriedTooltip.title:find(pickupTarget.pallet.id, 1, true))
    if os.getenv("PICTURE_SHOP_PALLET_JACK_PREVIEW") == "1" then return end
    context.world.update(0, 0, 0, context.assets, context.state)
    context.input.keypressed("e", context.inputContext)
    check("pallet_jack_lowers_pallet", context.world.palletJackSnapshot(context.state).carriedPalletId == nil
        and pickupTarget.pallet.location == "warehouse"
        and #context.world.palletsSnapshot(context.state) == 2
        and pickupTarget.pallet.world.direction == "north"
        and pickupTarget.pallet.world.rotation == 1)
    context.state.palletJack.direction = "southeast"
    context.world.update(0, 0, 0, context.assets, context.state)
    check("dropped_pallet_keeps_last_direction", pickupTarget.pallet.world.direction == "north"
        and pickupTarget.pallet.world.rotation == 1)
    context.input.keypressed("f", context.inputContext)
    check("pallet_jack_parks", not context.world.palletJackSnapshot(context.state).operating)
    context.state.wrapper.x = context.config.wrapperPlacement.spawnX
    context.state.wrapper.y = context.config.wrapperPlacement.spawnY
    context.state.wrapper.direction = "northwest"
    context.state.wrapper.moving, context.state.wrapper.inMotion = false, false
    context.state.palletJack.operating = true
    context.state.palletJack.carriedPalletId = nil
    context.state.palletJack.x, context.state.palletJack.y = context.state.wrapper.x, context.state.wrapper.y
    check("wrapper_relocation_motion_setup", context.world.beginWrapperMove(context.state))
    local wrapperBeforeMove = context.world.wrapperSnapshot(context.state)
    context.world.update(0.10, 1, 0, context.assets, context.state)
    check("wrapper_full_footprint_move_and_operator_walk", context.world.wrapperSnapshot(context.state).x > wrapperBeforeMove.x
        and context.world.wrapperSnapshot(context.state).inMotion
        and context.world.player.moving)
    check("wrapper_relocation_motion_place", context.world.placeWrapper(context.state))
    local parkedJack = context.world.palletJackSnapshot(context.state)
    context.world.parkPalletJack(context.state)
    context.world.player.x, context.world.player.y = parkedJack.x, parkedJack.y
    context.world.update(0.25, 1, 0, context.assets, context.state)
    check("player_can_escape_pallet_jack_overlap", context.world.player.x > parkedJack.x)
    local overlapPallet = context.world.palletsSnapshot(context.state)[1]
    context.world.player.x, context.world.player.y = overlapPallet.x, overlapPallet.y
    context.world.update(0.25, -1, 0, context.assets, context.state)
    check("player_can_escape_pallet_overlap", context.world.player.x < overlapPallet.x)
    context.state.cutter.x = context.config.cutterPlacement.spawnX
    context.state.cutter.y = context.config.cutterPlacement.spawnY
    context.state.cutter.direction = "northwest"
    context.state.cutter.moving = false
    context.state.palletJack.operating = true
    context.state.palletJack.carriedPalletId = nil
    context.state.palletJack.x, context.state.palletJack.y = context.state.cutter.x, context.state.cutter.y
    context.world.player.x = context.state.cutter.x
    context.world.player.y = context.state.cutter.y + 70
    context.world.update(0, 0, 0, context.assets, context.state)
    check("cutter_relocate_prompt_requires_active_jack", context.world.getInteraction()
        and context.world.prompt():find("RELOCATE CUTTER", 1, true))
    context.input.keypressed("m", context.inputContext)
    check("cutter_relocation_begins", context.world.cutterSnapshot(context.state).moving)
    local cutterBeforeMove = context.world.cutterSnapshot(context.state)
    context.world.update(0.15, -1, 0, context.assets, context.state)
    check("cutter_relocation_moves", context.world.cutterSnapshot(context.state).x < cutterBeforeMove.x
        and context.world.cutterSnapshot(context.state).inMotion
        and context.world.player.moving)
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_north", context.world.cutterSnapshot(context.state).frame == 2)
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_northeast", context.world.cutterSnapshot(context.state).frame == 3)
    if os.getenv("PICTURE_SHOP_CUTTER_PLACEMENT_PREVIEW") == "1" then return end
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_east", context.world.cutterSnapshot(context.state).frame == 4)
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_southeast", context.world.cutterSnapshot(context.state).frame == 5)
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_south", context.world.cutterSnapshot(context.state).frame == 6)
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_southwest", context.world.cutterSnapshot(context.state).frame == 7)
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_west", context.world.cutterSnapshot(context.state).frame == 8)
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_northwest", context.world.cutterSnapshot(context.state).frame == 1)
    context.input.keypressed("e", context.inputContext)
    check("cutter_relocation_places", not context.world.cutterSnapshot(context.state).moving)
    context.state.money = math.max(context.state.money or 0, 10000)
    local windmillOrdered, windmillOrder = context.machineFleet.orderOnline(context.state, 3)
    local windmillInstalled = windmillOrdered and context.machineFleet.unloadDelivery(
        context.state, windmillOrder.id, windmillOrder.machineId, os.time())
    check("windmill_relocation_test_machine_installed", windmillInstalled
        and context.machineFleet.isInstalled(context.state, "heidelberg_10x15"))
    context.state.windmill.x = context.config.windmillPlacement.spawnX
    context.state.windmill.y = context.config.windmillPlacement.spawnY
    context.state.windmill.direction = "northwest"
    context.state.windmill.moving, context.state.windmill.inMotion = false, false
    context.windmill.ensure(context.state).status = "idle"
    context.windmill.ensure(context.state).palletId = nil
    context.state.palletJack.operating = true
    context.state.palletJack.carriedPalletId = nil
    context.state.palletJack.x, context.state.palletJack.y = context.state.windmill.x, context.state.windmill.y
    check("windmill_relocation_begins_with_empty_jack", context.world.beginWindmillMove(context.state))
    local windmillBeforeMove = context.world.windmillSnapshot(context.state)
    context.world.update(0.1, 0, -1, context.assets, context.state)
    local windmillAfterMove = context.world.windmillSnapshot(context.state)
    local windmillRotated = context.world.rotateWindmill(context.state)
    local windmillDirection = context.world.windmillSnapshot(context.state).direction
    check("windmill_moves_on_jack_and_rotates", windmillAfterMove.y < windmillBeforeMove.y
        and windmillAfterMove.inMotion and windmillRotated and windmillDirection == "northeast",
        string.format("before=%.2f after=%.2f motion=%s rotated=%s direction=%s",
            windmillBeforeMove.y, windmillAfterMove.y, tostring(windmillAfterMove.inMotion),
            tostring(windmillRotated), tostring(windmillDirection)))
    check("windmill_relocation_places", context.world.placeWindmill(context.state)
        and not context.world.windmillSnapshot(context.state).moving)
    if os.getenv("PICTURE_SHOP_COMPUTER_CALENDAR_PREVIEW") == "1" then
        context.state.screen = "computer"
        context.computerScreen.enter(context.state)
        local x, y = context.computerScreen.tabCenter("calendar")
        context.computerScreen.mousepressed(context.state, x, y, 1)
    elseif os.getenv("PICTURE_SHOP_COMPUTER_INVENTORY_PREVIEW") == "1" then
        context.state.screen = "computer"
        context.state.money = 2400
        context.computerScreen.enter(context.state)
        local x, y = context.computerScreen.tabCenter("inventory")
        context.computerScreen.mousepressed(context.state, x, y, 1)
    elseif os.getenv("PICTURE_SHOP_COMPUTER_EMAIL_PREVIEW") == "1" then
        local emailJob = context.jobs.createOffer({
            id = "EMAIL-PREVIEW", company = "Blue Ridge Packaging",
            sourceSize = { width = 25, height = 19 }, finishedSize = { width = 12.5, height = 9.5 },
            sheetCounts = { 1000, 750 }, packaging = "boxed", requestChannel = "email",
            deliveryService = context.jobService.deliveryServiceFor({ id = "EMAIL-PREVIEW" }, 1),
        })
        context.state.clientEmails.inbox = { {
            id = "EMAIL-PREVIEW", sender = emailJob.company,
            subject = "Request for another cutting job",
            body = "Please review this work order and send us your quote.",
            sourceJobId = "JOB-0001", readyAtHours = 0, receivedAtHours = 0, job = emailJob,
        } }
        context.state.screen = "computer"
        context.computerScreen.enter(context.state)
        local x, y = context.computerScreen.tabCenter("email")
        context.computerScreen.mousepressed(context.state, x, y, 1)
    elseif os.getenv("PICTURE_SHOP_TITLE_PREVIEW") == "1" then
        context.state.screen = "title"
    elseif os.getenv("PICTURE_SHOP_CUTTER_PREVIEW") == "1" then
        context.state.screen = "machine"
        context.machine.reset(context.state)
        context.machine.load(context.state)
        context.machine.update(context.machine.transferTime + 0.01, context.state)
        context.machine.setGauge(context.machine.paper.cuts[1].gauge, context.state)
        context.machine.saveGauge(context.state)
        context.machine.autoGauge(context.state)
        context.machine.keypressed("q", context.state)
        context.machine.position(context.state)
        context.machine.update(context.machine.transferTime + 0.01, context.state)
        context.machine.toggleClamp(context.state)
        context.machine.update(0.3, context.state)
    elseif os.getenv("PICTURE_SHOP_VENDOR_PREVIEW") == "1" then
        context.state.screen = "vendor"
        context.state.vendorCategory = 3
    end
end

return Test
