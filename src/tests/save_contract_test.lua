local SaveSchema = require("src.save_schema")

local Test = {}

function Test.run(context, check)
    local slot = 2
    context.save.delete(slot)
    local fresh = context.save.newGame(slot)
    check("domain_save_exact_defaults", fresh.slot == slot
        and fresh.version == context.save.VERSION
        and fresh.state.inventory.plasticWrapRolls == 1
        and fresh.state.inventory.plasticWrapUses == 11
        and fresh.state.inventory.stock.shipping_cartons == 20
        and next(fresh.state.cutterMemory) == nil
        and #fresh.state.machines.items == 2
        and #fresh.state.machines.deliveries == 0
        and fresh.state.machines.nextDeliveryId == 1
        and fresh.state.machines.items[1].id == "MCH-0001"
        and fresh.state.wrapper.direction == context.config.wrapperPlacement.defaultDirection)

    fresh.state.money = 432
    fresh.state.wrapper.x = fresh.state.wrapper.x + 17
    check("domain_save_round_trip_write", context.save.save(slot, fresh.state, fresh.player))
    local loaded = context.save.load(slot)
    check("domain_save_round_trip_read", loaded
        and loaded.state.money == 432
        and loaded.state.wrapper.x == fresh.state.wrapper.x)

    local printJob = context.jobs.createOffer({
        id = "SAVE-PRINT-001", company = "Saved Print Client",
        sourceSize = { width = 10, height = 15 }, finishedSize = { width = 5, height = 7 },
        sheetCounts = { 1050 }, packaging = "flat", artworkKey = "ad-photos",
        artwork = { key = "ad-photos", displayName = "Client Photo Card",
            fileName = "client-photo-card.png", suppliedBy = "client", orientation = "portrait" },
        stockSpec = { suppliedBy = "client", grade = "cover", weight = 80,
            finish = "uncoated", color = "white", grain = "long",
            description = "80 lb uncoated cover" },
        press = { colors = 1, coverage = 0.35, artworkSize = { width = 4.25, height = 6.25 },
            colorSequence = { "Black" }, requestedCopies = { 1000 } },
    })
    local printState = context.State.new()
    printState.money = 432
    printState.windmill.tutorialComplete = true
    printState.jobs.active = { printJob }
    printJob.status = "in_production"
    local printPallet = printJob.pallets[1]
    printPallet.location = "warehouse"
    printPallet.world = { x = 520, y = 480, direction = "northwest", spawnProgress = 1 }
    check("domain_uncut_print_pallet_save", context.save.save(slot, printState, fresh.player))
    local rawPrintLoaded = context.save.load(slot)
    check("domain_uncut_print_pallet_reconciles_as_raw", rawPrintLoaded
        and rawPrintLoaded.state.inventory.rawPallets == 1
        and rawPrintLoaded.state.inventory.inProcessPallets == 0
        and rawPrintLoaded.state.inventory.finishedPallets == 0)
    printPallet.location, printPallet.status = "at_press", "press_setup"
    printPallet.world = { x = printState.windmill.x, y = printState.windmill.y, direction = "northwest" }
    printPallet.remainingSheets, printPallet.finishedSheets = 0, printPallet.initialSheets
    printPallet.paper.status = "complete"
    printPallet.press.status, printPallet.press.goodSheets = "production", 420
    printPallet.press.availableSheets = 629
    printState.windmill.process = {
        status = "production", speed = 3000, motor = true, feeder = true, impression = true,
        emergency = false, setup = { chase = 0.96, packing = 0.94 }, counter = 431,
        goodSheets = 420, spoilage = 11, sheetAccumulator = 0.25, animationClock = 2,
        jobId = printJob.id, palletId = printPallet.id, colorIndex = 1,
        proofQuality = 0.93, proofApproved = true, artworkVerified = true,
        targetSheets = 1000, feedStart = 1050, feedRemaining = 619,
    }
    check("domain_print_save_round_trip_write", context.save.save(slot, printState, fresh.player))
    local printLoaded = context.save.load(slot)
    local loadedJob = printLoaded and printLoaded.state.jobs.active[1]
    local loadedPallet = loadedJob and loadedJob.pallets[1]
    check("domain_print_save_round_trip_read", loadedJob and loadedPallet
        and loadedJob.artwork.key == "ad-photos"
        and loadedJob.stockSpec.weight == 80
        and loadedJob.press.requestedCopies[1] == 1000
        and loadedJob.press.orderedQuantity == 1000
        and loadedJob.press.suppliedSheets == 1050
        and loadedJob.press.spoilageAllowance == 50
        and loadedPallet.requestedCopies == 1000
        and loadedPallet.press.requiredGoodSheets == 1000
        and loadedPallet.press.availableSheets == 629
        and printLoaded.state.windmill.process.feedRemaining == 619
        and printLoaded.state.windmill.tutorialComplete == true
        and printLoaded.state.inventory.inProcessPallets == 1
        and printLoaded.state.inventory.finishedPallets == 0)

    printPallet.location, printPallet.status = "press_output", "printed"
    printPallet.press.status, printPallet.press.completedColors = "complete", 1
    printPallet.press.goodSheets, printPallet.press.availableSheets = 1000, 1000
    printState.windmill.process = nil
    check("domain_completed_print_pallet_save", context.save.save(slot, printState, fresh.player))
    local completedPrintLoaded = context.save.load(slot)
    check("domain_press_output_reconciles_as_finished", completedPrintLoaded
        and completedPrintLoaded.state.inventory.rawPallets == 0
        and completedPrintLoaded.state.inventory.inProcessPallets == 0
        and completedPrintLoaded.state.inventory.finishedPallets == 1)

    local invalidPrint = context.State.new()
    invalidPrint.jobs.active = { printJob }
    invalidPrint.jobs.active[1].press.requestedCopies = "not-a-list"
    check("domain_save_rejects_invalid_print_contract",
        not context.save.save(slot, invalidPrint, fresh.player)
        and context.save.load(slot).state.jobs.active[1].id == "SAVE-PRINT-001")

    local invalid = context.State.new()
    invalid.jobs.active = { { id = "BROKEN", pallets = "not-a-list" } }
    check("domain_save_rejects_invalid_nested_state", not context.save.save(slot, invalid, fresh.player)
        and context.save.load(slot).state.money == 432)

    local ownershipJob = context.jobs.createOffer({
        id = "SAVE-OWNERSHIP-001", company = "Ownership Test Client",
        sourceSize = { width = 10, height = 15 }, finishedSize = { width = 5, height = 7 },
        sheetCounts = { 1050, 1050 }, packaging = "flat",
        press = { colors = 1, coverage = 0.35, artworkSize = { width = 4.25, height = 6.25 },
            colorSequence = { "Black" }, requestedCopies = { 1000, 1000 } },
    })
    ownershipJob.status = "in_production"
    local ownershipState = context.State.new()
    ownershipState.jobs.active = { ownershipJob }
    ownershipJob.pallets[1].location, ownershipJob.pallets[1].world = "warehouse", nil
    check("domain_save_rejects_physical_pallet_without_floor_position",
        not context.save.save(slot, ownershipState, fresh.player))
    for index, pallet in ipairs(ownershipJob.pallets) do
        pallet.location = "at_press"
        pallet.world = { x = 820 + index * 12, y = 440 + index * 8,
            direction = "northwest", spawnProgress = 1 }
    end
    check("domain_save_rejects_multiple_windmill_owned_pallets",
        not context.save.save(slot, ownershipState, fresh.player))

    local hostState = context.State.new()
    hostState.money = 925
    hostState.inventory.paper = 2375
    hostState.inventory.prints = 18
    hostState.inventory.stock.shipping_cartons = 5
    hostState.calendar = {
        year = 2026, month = 1, day = 5, weekday = 1, elapsed = 45, totalDays = 4,
    }
    local sharedJob = context.jobs.createOffer({
        id = "LAN-SHARED-001", company = "Cross-platform Customer",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 }, packaging = "flat",
    })
    context.jobs.accept(sharedJob, 123)
    hostState.jobs.active = { sharedJob }
    hostState.nextJobId = 2
    hostState.clientEmails.nextEmailId = 2
    hostState.clientEmails.inbox = {
        {
            id = "EMAIL-LAN-001",
            sender = "Cross-platform Customer",
            subject = "Print quote",
            body = "Please quote our next run.",
            sourceJobId = sharedJob.id,
            readyAtHours = 96,
            receivedAtHours = 97,
            job = sharedJob,
        },
    }
    local sharedSnapshot = SaveSchema.snapshot(hostState)
    local guestState = context.State.new()
    guestState.activeSlot = 3
    guestState.money = 1
    guestState.inventory.paper = 1
    guestState.calendar.day = 1
    local sharedApplied = context.State.applySharedSnapshot(guestState, sharedSnapshot)
    local guestPaper = guestState.inventory.paper
    local guestJobId = guestState.jobs.active[1] and guestState.jobs.active[1].id
    sharedSnapshot.inventory.paper = 0
    sharedSnapshot.jobs.active[1].id = "MUTATED-AFTER-APPLY"
    check("domain_guest_applies_detached_host_authoritative_shop_snapshot",
        sharedApplied and guestState.activeSlot == nil and guestState.screen == "world"
        and guestState.money == 925 and guestPaper == 2375
        and guestState.inventory.paper == 2375 and guestState.inventory.prints == 18
        and guestState.inventory.stock.shipping_cartons == 5
        and guestState.calendar.year == 2026 and guestState.calendar.day == 5
        and guestState.calendar.totalDays == 4
        and guestJobId == "LAN-SHARED-001"
        and guestState.jobs.active[1].id == "LAN-SHARED-001"
        and guestState.jobs.active[1].status == "awaiting_delivery"
        and guestState.clientEmails.inbox[1].sender == "Cross-platform Customer")

    check("domain_guest_rejects_non_table_shared_shop_snapshot_without_mutation",
        not context.State.applySharedSnapshot(guestState, "forged-state")
        and guestState.money == 925 and guestState.activeSlot == nil)

    hostState.money = 1110
    hostState.inventory.paper = 2125
    hostState.inventory.prints = 44
    hostState.calendar.day = 6
    hostState.calendar.weekday = 2
    hostState.calendar.totalDays = 5
    local sharedUpdate = SaveSchema.snapshot(hostState)
    local localOffer = { id = "LOCAL-PANEL-OFFER" }
    guestState.screen = "computer"
    guestState.message = "Reviewing the host shop"
    guestState.currentOffer = localOffer
    guestState.activeSlot = 2
    guestState.palletJack.x, guestState.palletJack.y = 612, 488
    guestState.palletJack.direction = "east"
    guestState.palletJack.operating = true
    guestState.palletJack.operatorPlayerId = 3
    guestState.palletJack.moving = true
    check("domain_guest_live_update_preserves_local_ui_and_replaces_durable_state",
        context.State.applySharedUpdate(guestState, sharedUpdate)
        and guestState.money == 1110 and guestState.inventory.paper == 2125
        and guestState.inventory.prints == 44 and guestState.calendar.day == 6
        and guestState.jobs.active[1].id == "LAN-SHARED-001"
        and guestState.screen == "computer"
        and guestState.message == "Reviewing the host shop"
        and guestState.currentOffer == localOffer and guestState.activeSlot == nil
        and guestState.palletJack.x == 612 and guestState.palletJack.y == 488
        and guestState.palletJack.direction == "east"
        and guestState.palletJack.operating and guestState.palletJack.moving
        and guestState.palletJack.operatorPlayerId == 3)

    local invalidSemanticUpdate = SaveSchema.snapshot(hostState)
    invalidSemanticUpdate.money = -1
    invalidSemanticUpdate.calendar.day = 99
    check("domain_guest_rejects_invalid_semantic_live_update_atomically",
        not context.State.applySharedUpdate(guestState, invalidSemanticUpdate)
        and guestState.money == 1110 and guestState.inventory.paper == 2125
        and guestState.calendar.day == 6 and guestState.screen == "computer"
        and guestState.currentOffer == localOffer and guestState.activeSlot == nil)
    context.save.delete(slot)
end

return Test
