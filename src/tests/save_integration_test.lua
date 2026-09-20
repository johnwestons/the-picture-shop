local Test = {}

function Test.run(context, check, economy, jobs)
    local payload = context.save.newGame(1)
    economy.jobs.active[1] = jobs.createOffer({
        id = "JOB-0099",
        company = "Saved Job Co.",
        sourceSize = { width = 20, height = 20 },
        finishedSize = { width = 10, height = 10 },
        sheetCounts = { 1200 },
    })
    jobs.accept(economy.jobs.active[1])
    economy.jobs.active[1].pallets[1].location = "on_pallet_jack"
    economy.jobs.active[1].pallets[1].world = {
        x = 612, y = 498, direction = "southeast", rotation = 4,
        fromX = 612, fromY = 498, spawnProgress = 1,
    }
    economy.jobs.completed[1] = jobs.createOffer({
        id = "JOB-0098", company = "Completed Save Co.",
        sourceSize = { width = 18, height = 12 }, finishedSize = { width = 9, height = 6 },
        sheetCounts = { 500 }, packaging = "flat",
    })
    jobs.accept(economy.jobs.completed[1])
    economy.jobs.completed[1].status = "completed"
    check("save_repeat_email_setup", context.jobService.scheduleRepeatEmail(
        economy, economy.jobs.completed[1]))
    economy.jobs.declined[1] = jobs.createOffer({
        id = "JOB-0097", company = "Declined Save Co.",
        sourceSize = { width = 16, height = 12 }, finishedSize = { width = 8, height = 6 },
        sheetCounts = { 500 }, packaging = "boxed",
    })
    jobs.decline(economy.jobs.declined[1])
    economy.accountsReceivable = economy.jobs.active[1].quote.totalPrice
    economy.nextJobId = 100
    economy.shopProgress.completedCuts = 9
    economy.reputation.score = 37
    economy.reputation.completedJobs = 4
    economy.reputation.spoiledSheets = 500
    economy.reputation.spoilClaims = 230
    economy.inventory.plasticWrapRolls = 3
    economy.inventory.plasticWrapUses = 7
    economy.inventory.stock.shipping_cartons = 18
    economy.cutterMemory = { ["1"] = { 12.5, 12, 11.5 }, ["2"] = { 9.5 } }
    economy.cutter.x = 590
    economy.cutter.y = 430
    economy.cutter.direction = "east"
    economy.palletJack.x = 612
    economy.palletJack.y = 498
    economy.palletJack.direction = "south"
    economy.palletJack.operating = true
    economy.palletJack.carriedPalletId = "JOB-0099-P01"
    economy.wrapper.x = 705
    economy.wrapper.y = 455
    economy.wrapper.direction = "northeast"
    economy.vendorCategory = 4
    context.machineFleet.recordUse(economy, "polar_115", 12)
    context.businessCalendar.update(economy, 31 * context.config.businessCalendar.secondsPerDay)
    economy.money = 10000
    local machineOrdered, machineDelivery = context.machineFleet.orderOnline(economy, 1)
    check("save_machine_delivery_setup", machineOrdered
        and machineDelivery.machineId == "MCH-0003"
        and machineDelivery.delivery.status == "awaiting_delivery")
    check("save_procurement_setup", context.procurement.buy(economy, 1, 1))
    local savedPlayer = { x = 701, y = 502 }
    local schema = require("src.save_schema")
    local snapshot = schema.snapshot(economy)
    local palletValid, palletErrors = context.PalletState.validate(snapshot)
    check("save_write_v3", context.save.save(1, economy, savedPlayer),
        string.format("schema=%s pallets=%s errors=%s phone=%s/%s/%s",
            tostring(schema.validState(snapshot)), tostring(palletValid),
            table.concat(palletErrors or {}, "; "),
            tostring(snapshot.workPhone and snapshot.workPhone.nextCallId),
            tostring(snapshot.workPhone and snapshot.workPhone.nextCallAtHours),
            tostring(snapshot.workPhone and #snapshot.workPhone.history)))
    local loaded = context.save.load(1)
    check("save_round_trip", loaded and loaded.state.money == economy.money)
    check("save_jobs_round_trip", loaded
        and loaded.version == context.save.VERSION
        and loaded.state.jobs.active[1].id == "JOB-0099"
        and loaded.state.jobs.active[1].pallets[1].remainingSheets == 1200
        and loaded.state.jobs.completed[1].id == "JOB-0098"
        and loaded.state.jobs.declined[1].id == "JOB-0097")
    check("save_repeat_email_round_trip", loaded
        and #loaded.state.clientEmails.pending == 1
        and loaded.state.clientEmails.pending[1].sender == "Completed Save Co."
        and loaded.state.clientEmails.pending[1].job.requestChannel == "email")
    check("save_finance_round_trip", loaded
        and loaded.state.accountsReceivable == 450
        and loaded.state.nextJobId == 100
        and loaded.state.calendar.month == 2
        and loaded.state.calendar.day == 1
        and loaded.state.bills.balance == 1650
        and loaded.state.bills.ledger[1].status == "unpaid")
    check("save_inventory_round_trip", loaded
        and loaded.state.inventory.plasticWrapRolls == 3
        and loaded.state.inventory.plasticWrapUses == 7
        and loaded.state.inventory.stock.shipping_cartons == 18
        and loaded.state.inventory.rawPallets == 1
        and loaded.state.shopProgress.completedCuts == 9)
    check("save_reputation_round_trip", loaded
        and loaded.state.reputation.score == 37
        and loaded.state.reputation.completedJobs == 4
        and loaded.state.reputation.spoiledSheets == 500
        and loaded.state.reputation.spoilClaims == 230)
    check("save_pallet_jack_round_trip", loaded
        and loaded.state.palletJack.x == 612
        and loaded.state.palletJack.y == 498
        and loaded.state.palletJack.direction == "south"
        and loaded.state.palletJack.carriedPalletId == "JOB-0099-P01"
        and loaded.state.jobs.active[1].pallets[1].location == "on_pallet_jack")
    check("save_cutter_placement_round_trip", loaded
        and loaded.state.cutter.x == 590
        and loaded.state.cutter.y == 430
        and loaded.state.cutter.direction == "east")
    check("save_cutter_measurement_memory_round_trip", loaded
        and #loaded.state.cutterMemory["1"] == 3
        and loaded.state.cutterMemory["1"][1] == 12.5
        and loaded.state.cutterMemory["2"][1] == 9.5)
    check("save_wrapper_placement_round_trip", loaded
        and loaded.state.wrapper.x == 705
        and loaded.state.wrapper.y == 455
        and loaded.state.wrapper.direction == "northeast")
    check("save_machine_condition_round_trip", loaded
        and loaded.state.machines.items[1].id == "MCH-0001"
        and loaded.state.machines.items[1].cycles == 12
        and loaded.state.machines.items[1].variables.bladeSharpness < 100
        and context.machineFleet.validState(loaded.state.machines))
    check("save_pending_machine_delivery_round_trip", loaded
        and loaded.state.machines.nextDeliveryId == 2
        and loaded.state.machines.deliveries[1].id == machineDelivery.id
        and loaded.state.machines.deliveries[1].machineId == "MCH-0003"
        and loaded.state.machines.deliveries[1].item.id == "MCH-0003"
        and context.machineFleet.nextInbound(loaded.state).id == machineDelivery.id)
    check("save_procurement_round_trip", loaded
        and loaded.state.vendorCategory == 4
        and loaded.state.procurement.nextOrderId == 2
        and loaded.state.procurement.orders[1].id == "PO-0001")
    check("save_player_round_trip", loaded and loaded.player.x == 701 and loaded.player.y == 502)
    local appliedRoundTrip = context.State.new()
    check("save_state_apply_round_trip", context.State.applySave(appliedRoundTrip, loaded)
        and appliedRoundTrip.wrapper.x == 705
        and appliedRoundTrip.wrapper.direction == "northeast"
        and appliedRoundTrip.inventory.plasticWrapUses == 7
        and appliedRoundTrip.cutterMemory["1"][3] == 11.5
        and appliedRoundTrip.palletJack.carriedPalletId == "JOB-0099-P01"
        and appliedRoundTrip.jobs.active[1].pallets[1].location == "on_pallet_jack")
    check("save_state_apply_restores_pending_machine_delivery",
        context.machineFleet.nextInbound(appliedRoundTrip).machineId == "MCH-0003")
    context.save.delete(1)

    context.save.delete(2)
    local v3State = context.State.new()
    v3State.money = 303
    check("save_v3_migration_fixture", context.save.save(2, v3State, { x = 430, y = 530 }))
    local v3Source = love.filesystem.read("saves/slot2.lua")
    local versionReplacements, memoryReplacements
    v3Source, versionReplacements = v3Source:gsub(
        '%["version"%]%s*=%s*' .. tostring(context.save.VERSION), '["version"] = 3', 1)
    v3Source, memoryReplacements = v3Source:gsub('%s*%["cutterMemory"%]%s*=%s*{%s*},', '', 1)
    check("save_v3_fixture_removes_new_memory_field",
        versionReplacements == 1 and memoryReplacements == 1
        and love.filesystem.write("saves/slot2.lua", v3Source))
    local migratedV3 = context.save.load(2)
    check("save_v3_migration", migratedV3
        and migratedV3.version == context.save.VERSION
        and migratedV3.state.money == 303
        and next(migratedV3.state.cutterMemory) == nil
        and #migratedV3.state.machines.items == 2
        and migratedV3.player.x == 430)
    context.save.delete(2)

    love.filesystem.createDirectory("saves")
    love.filesystem.write("saves/slot2.lua", [[{
        version = 1,
        slot = 2,
        createdAt = 10,
        updatedAt = 20,
        state = {
            money = 321,
            inventory = { paper = 12, prints = 3 },
            shopProgress = { completedCuts = 7 },
        },
        player = { x = 444, y = 555 },
    }]])
    local migrated = context.save.load(2)
    check("save_v1_migration", migrated
        and migrated.version == context.save.VERSION
        and migrated.state.money == 321
        and migrated.state.inventory.paper == 12
        and migrated.state.inventory.rawPallets == 0
        and migrated.state.inventory.plasticWrapRolls == 1
        and migrated.state.inventory.plasticWrapUses == 11
        and migrated.state.wrapper.x == context.config.wrapperPlacement.spawnX
        and migrated.state.wrapper.direction == context.config.wrapperPlacement.defaultDirection
        and #migrated.state.machines.items == 2
        and #migrated.state.jobs.active == 0
        and migrated.player.x == 444)
    context.save.delete(2)

    love.filesystem.write("saves/slot2.lua", [[{
        version = 2,
        slot = 2,
        createdAt = 30,
        updatedAt = 40,
        state = {
            money = 222,
            inventory = { paper = 8, prints = 2, rawPallets = 7, inProcessPallets = 6, finishedPallets = 5 },
            shopProgress = { completedCuts = 4 },
            jobs = { active = {}, completed = {}, declined = {} },
            nextJobId = 4,
            accountsReceivable = 15,
            procurement = { orders = {}, nextOrderId = 2 },
            vendorCategory = 3,
            cutter = { x = 610, y = 420, direction = "southwest", moving = false },
            palletJack = { x = 600, y = 500, direction = "northeast", operating = false, moving = false },
        },
        player = { x = 410, y = 520 },
    }]])
    local migratedV2 = context.save.load(2)
    check("save_v2_migration", migratedV2
        and migratedV2.version == context.save.VERSION
        and migratedV2.state.money == 222
        and migratedV2.state.inventory.plasticWrapRolls == 1
        and migratedV2.state.inventory.plasticWrapUses == 11
        and migratedV2.state.inventory.rawPallets == 0
        and migratedV2.state.wrapper.x == context.config.wrapperPlacement.spawnX
        and migratedV2.state.wrapper.direction == context.config.wrapperPlacement.defaultDirection
        and migratedV2.state.cutter.direction == "southwest"
        and migratedV2.player.y == 520)
    context.save.delete(2)

    local legacyPrintJob = [[{
        id = "JOB-0012",
        company = "Legacy Print Client",
        sourceSize = { width = 10, height = 15 },
        finishedSize = { width = 5, height = 7 },
        artworkKey = "flower",
        details = { stockDescription = "80 lb gloss cover", grainDirection = "Grain long" },
        difficulty = "easy",
        packaging = "flat",
        status = "in_production",
        quote = {
            palletCount = 1, totalSheets = 1050, totalLifts = 3, totalPrice = 450,
            recommendedPrice = 450,
            pallets = { { number = 1, sheetCount = 1050, requiredLifts = 3, price = 450 } },
        },
        press = {
            colors = 1, coverage = 0.35, artworkSize = { width = 4.25, height = 6.25 },
            colorSequence = { "Black" },
        },
        pallets = { {
            id = "JOB-0012-P01", number = 1, initialSheets = 1050,
            remainingSheets = 0, finishedSheets = 1050, damagedSheets = 0,
            requiredLifts = 3, completedLifts = 3, activeLift = 3, lastLiftSheets = 50,
            programVerified = true, awaitingPalletReturn = false,
            status = "press_setup", location = "at_press", packaging = "flat", wrapped = false,
            world = { x = 855, y = 450, direction = "northwest" },
            press = { status = "production", completedColors = 0, goodSheets = 420, spoilage = 11 },
        } },
    }]]
    local v12Source = string.format([[{
        version = 12,
        slot = 2,
        createdAt = 50,
        updatedAt = 60,
        state = {
            money = 612,
            inventory = { paper = 8, prints = 2 },
            shopProgress = { completedCuts = 4 },
            jobs = { active = { %s }, completed = {}, declined = {} },
            nextJobId = 13,
            accountsReceivable = 450,
            clientEmails = {
                nextEmailId = 2, nextPromotionId = 1,
                pending = { {
                    id = "EMAIL-0001", sender = "Legacy Print Client",
                    subject = "Repeat print request", body = "Please quote the attached repeat work.",
                    sourceJobId = "JOB-0011", readyAtHours = 72, job = %s,
                } },
                inbox = {}, archive = {}, sentPromotions = {},
            },
            windmill = {
                x = 855, y = 450, direction = "northwest", moving = false, inMotion = false,
                process = {
                    status = "production", speed = 3000, motor = true, feeder = true,
                    impression = true, emergency = false, setup = { chase = 0.95 },
                    counter = 431, goodSheets = 420, spoilage = 11,
                    sheetAccumulator = 0.25, animationClock = 2,
                    jobId = "JOB-0012", palletId = "JOB-0012-P01", colorIndex = 1,
                    proofQuality = 0.93, proofApproved = true,
                },
            },
        },
        player = { x = 420, y = 520 },
    }]], legacyPrintJob, legacyPrintJob)
    love.filesystem.createDirectory("saves")
    check("save_v12_print_fixture_write", love.filesystem.write("saves/slot2.lua", v12Source))
    local migratedV12 = context.save.load(2)
    local migratedPrint = migratedV12 and migratedV12.state.jobs.active[1]
    local migratedPrintPallet = migratedPrint and migratedPrint.pallets[1]
    check("save_v12_print_job_migration", migratedPrint and migratedPrintPallet
        and migratedV12.version == context.save.VERSION
        and migratedPrint.artwork.key == "flower"
        and migratedPrint.artwork.fileName == "flower.png"
        and migratedPrint.stockSpec.weight == 80
        and migratedPrint.stockSpec.finish == "gloss"
        and migratedPrint.press.requestedCopies[1] == 1050
        and migratedPrint.press.orderedQuantity == 1050
        and migratedPrint.press.suppliedSheets == 1050
        and migratedPrint.press.spoilageAllowance == 0
        and migratedPrintPallet.requestedCopies == 1050
        and migratedPrintPallet.press.requiredGoodSheets == 1050
        and migratedPrintPallet.press.availableSheets == 1050
        and type(migratedPrintPallet.press.passHistory) == "table"
        and migratedV12.state.inventory.inProcessPallets == 1)
    local migratedEmailJob = migratedV12 and migratedV12.state.clientEmails.pending[1]
        and migratedV12.state.clientEmails.pending[1].job
    check("save_v12_embedded_email_print_job_migration", migratedEmailJob
        and migratedEmailJob.artwork.key == "flower"
        and migratedEmailJob.stockSpec.description == "80 lb gloss cover"
        and migratedEmailJob.press.requestedCopies[1] == 1050
        and migratedEmailJob.pallets[1].press.requiredGoodSheets == 1050)
    check("save_v12_windmill_process_migration", migratedV12
        and migratedV12.state.windmill.process.status == "production"
        and migratedV12.state.windmill.process.goodSheets == 420
        and migratedV12.state.windmill.process.proofQuality == 0.93
        and migratedV12.state.windmill.process.targetSheets == 1050
        and migratedV12.state.windmill.process.feedStart == 1050
        and migratedV12.state.windmill.process.feedRemaining == 619
        and migratedV12.state.windmill.process.artworkVerified
        and migratedV12.state.windmill.process.jobId == "JOB-0012")
    context.save.delete(2)

    local multiState = context.State.new()
    local multiJob = jobs.createOffer({
        id = "JOB-LEGACY-MULTI", company = "Legacy Multicolor Client",
        sourceSize = { width = 10, height = 15 }, finishedSize = { width = 5, height = 7 },
        sheetCounts = { 1050, 1050 }, packaging = "flat", artworkKey = "ad-pizza",
        press = { colors = 2, coverage = 0.4, artworkSize = { width = 4.25, height = 6.25 },
            colorSequence = { "Red", "Black" }, requestedCopies = { 1000, 1000 } },
    })
    multiJob.status = "in_production"
    multiState.jobs.active = { multiJob }
    local firstPassPallet, priorPassPallet = multiJob.pallets[1], multiJob.pallets[2]
    firstPassPallet.location, firstPassPallet.status = "at_press", "press_setup"
    firstPassPallet.world = { x = multiState.windmill.x, y = multiState.windmill.y,
        direction = "northwest", spawnProgress = 1 }
    firstPassPallet.paper.status, firstPassPallet.remainingSheets = "complete", 0
    firstPassPallet.finishedSheets = 1050
    firstPassPallet.press.status, firstPassPallet.press.goodSheets = "production", 420
    firstPassPallet.press.availableSheets = 1050
    priorPassPallet.location, priorPassPallet.status = "press_output", "cut"
    priorPassPallet.world = { x = multiState.windmill.x + 84, y = multiState.windmill.y + 42,
        direction = "northwest", spawnProgress = 1 }
    priorPassPallet.paper.status, priorPassPallet.remainingSheets = "complete", 0
    priorPassPallet.finishedSheets = 1025
    priorPassPallet.press.status, priorPassPallet.press.completedColors = "drying", 1
    priorPassPallet.press.goodSheets, priorPassPallet.press.availableSheets = 1025, 1025
    multiState.windmill.process = {
        status = "production", speed = 3000, motor = true, feeder = true, impression = true,
        emergency = false, setup = { chase = 0.95 }, counter = 431, goodSheets = 420,
        spoilage = 11, sheetAccumulator = 0.25, animationClock = 2,
        jobId = multiJob.id, palletId = firstPassPallet.id, colorIndex = 1,
        proofQuality = 0.93, proofApproved = true, artworkVerified = true,
        targetSheets = 1025, feedStart = 1050, feedRemaining = 619,
    }
    check("save_v12_multicolor_fixture", context.save.save(2, multiState, { x = 420, y = 520 }))
    local multiSource = love.filesystem.read("saves/slot2.lua")
    local multiVersionReplacements, availableReplacements, targetReplacements
    multiSource, multiVersionReplacements = multiSource:gsub(
        '%["version"%]%s*=%s*' .. tostring(context.save.VERSION), '["version"] = 12', 1)
    multiSource, availableReplacements = multiSource:gsub(
        '%s*%["availableSheets"%]%s*=%s*%d+%s*,', '')
    multiSource, targetReplacements = multiSource:gsub(
        '%s*%["targetSheets"%]%s*=%s*%d+%s*,', '', 1)
    check("save_v12_multicolor_fixture_removes_derived_fields",
        multiVersionReplacements == 1 and availableReplacements == 2 and targetReplacements == 1
        and love.filesystem.write("saves/slot2.lua", multiSource))
    local migratedMulti = context.save.load(2)
    local migratedMultiJob = migratedMulti and migratedMulti.state.jobs.active[1]
    check("save_v12_multicolor_preserves_physical_stock_and_pass_reserve", migratedMultiJob
        and migratedMultiJob.pallets[1].press.availableSheets == 1050
        and migratedMultiJob.pallets[2].press.availableSheets == 1025
        and migratedMulti.state.windmill.process.targetSheets == 1025
        and migratedMulti.state.windmill.process.palletId == migratedMultiJob.pallets[1].id)
    context.save.delete(2)

    for slot = 1, context.save.SLOT_COUNT do
        context.save.delete(slot)
        local fresh = context.save.newGame(slot)
        check("save_slot_" .. slot .. "_new_defaults", fresh
            and fresh.version == context.save.VERSION
            and fresh.slot == slot
            and fresh.state.money == 180
            and fresh.state.inventory.paper == 40
            and fresh.state.inventory.plasticWrapRolls == 1
            and fresh.state.inventory.plasticWrapUses == 11
            and fresh.state.inventory.stock.shipping_cartons == 20
            and next(fresh.state.cutterMemory) == nil
            and #fresh.state.machines.items == 2
            and fresh.state.wrapper.x == context.config.wrapperPlacement.spawnX
            and fresh.state.wrapper.y == context.config.wrapperPlacement.spawnY
            and fresh.state.wrapper.direction == context.config.wrapperPlacement.defaultDirection)
        fresh.state.money = 180 + slot
        fresh.state.wrapper.x = context.config.wrapperPlacement.spawnX + slot
        check("save_slot_" .. slot .. "_write", context.save.save(slot, fresh.state, fresh.player))
        local slotListing = context.save.listSlots()[slot]
        local slotLoaded = context.save.load(slot)
        check("save_slot_" .. slot .. "_load_and_list", slotLoaded
            and not slotListing.empty
            and slotListing.money == 180 + slot
            and slotLoaded.state.wrapper.x == context.config.wrapperPlacement.spawnX + slot)
        check("save_slot_" .. slot .. "_delete", context.save.delete(slot)
            and context.save.listSlots()[slot].empty)
    end

    local invalidNested = context.State.new()
    invalidNested.jobs.active = { { id = "BROKEN-JOB", pallets = "not-a-list" } }
    local preservedState = context.State.new()
    preservedState.money = 515
    check("save_invalid_write_setup", context.save.save(1, preservedState, { x = 1, y = 1 }))
    local beforeInvalidWrite = love.filesystem.read("saves/slot1.lua")
    check("save_nested_validation_rejects_invalid_job",
        not context.save.save(1, invalidNested, { x = 1, y = 1 })
        and love.filesystem.read("saves/slot1.lua") == beforeInvalidWrite
        and context.save.load(1).state.money == 515)

    local writable, writableError = context.save.preflightWritable(1)
    local probeArtifactFound = false
    for _, item in ipairs(love.filesystem.getDirectoryItems("saves") or {}) do
        if item:find(".host-write-probe-", 1, true) then probeArtifactFound = true end
    end
    check("save_host_preflight_is_non_destructive_and_cleans_probe",
        writable == true and writableError == nil and not probeArtifactFound
        and love.filesystem.read("saves/slot1.lua") == beforeInvalidWrite
        and context.save.load(1).state.money == 515)
    check("save_host_preflight_rejects_invalid_slot_without_writing",
        context.save.preflightWritable(0) == false
        and love.filesystem.read("saves/slot1.lua") == beforeInvalidWrite)

    local originalCreateDirectory = love.filesystem.createDirectory
    local failedPreflight, failedPreflightMessage
    local protected = pcall(function()
        love.filesystem.createDirectory = function(path)
            if path == "saves" then return false, "synthetic directory failure" end
            return originalCreateDirectory(path)
        end
        failedPreflight, failedPreflightMessage = context.save.preflightWritable(1)
    end)
    love.filesystem.createDirectory = originalCreateDirectory
    check("save_host_preflight_reports_private_directory_failure_without_slot_damage",
        protected and failedPreflight == false
        and type(failedPreflightMessage) == "string"
        and failedPreflightMessage:find("private save folder", 1, true) ~= nil
        and love.filesystem.read("saves/slot1.lua") == beforeInvalidWrite)
    context.save.delete(1)

    local backupState = context.State.new()
    backupState.money = 111
    check("save_backup_first_primary", context.save.save(1, backupState, { x = 101, y = 201 }))
    backupState.money = 222
    check("save_backup_second_primary", context.save.save(1, backupState, { x = 102, y = 202 }))
    check("save_last_known_good_backup_created", love.filesystem.getInfo("saves/slot1.lua.bak") ~= nil)
    love.filesystem.write("saves/slot1.lua", "{")
    local recoveredBackup, backupStatus = context.save.load(1)
    check("save_truncated_primary_recovers_backup", recoveredBackup
        and backupStatus == "recovered"
        and recoveredBackup.recoverySource == "backup"
        and recoveredBackup.state.money == 111
        and context.save.listSlots()[1].recovered)
    local restoredBackup = context.save.load(1)
    check("save_backup_recovery_restores_primary", restoredBackup and restoredBackup.state.money == 111)

    local temporaryState = context.State.new()
    temporaryState.money = 333
    check("save_temporary_recovery_setup", context.save.save(1, temporaryState, { x = 103, y = 203 }))
    local validTemporaryBytes = love.filesystem.read("saves/slot1.lua")
    love.filesystem.write("saves/slot1.lua.tmp", validTemporaryBytes)
    love.filesystem.write("saves/slot1.lua", "truncated")
    love.filesystem.remove("saves/slot1.lua.bak")
    local recoveredTemporary, temporaryStatus = context.save.load(1)
    check("save_invalid_primary_recovers_valid_temporary", recoveredTemporary
        and temporaryStatus == "recovered"
        and recoveredTemporary.recoverySource == "temporary"
        and recoveredTemporary.state.money == 333
        and context.save.load(1).state.money == 333)
    context.save.delete(1)

    love.filesystem.createDirectory("saves")
    love.filesystem.write("saves/slot1.lua", "{")
    love.filesystem.write("saves/slot1.lua.tmp", "also invalid")
    love.filesystem.write("saves/slot1.lua.bak", "still invalid")
    local corruptedListing = context.save.listSlots()[1]
    local corruptedPayload, corruptedStatus = context.save.load(1)
    check("save_unrecoverable_slot_is_visible", corruptedPayload == nil
        and corruptedStatus == "corrupted"
        and corruptedListing.corrupted
        and not corruptedListing.empty)
    local corruptedBytes = love.filesystem.read("saves/slot1.lua")
    local corruptStarts = 0
    context.state.screen = "title"
    context.title.enter(function() corruptStarts = corruptStarts + 1 end)
    context.input.keypressed("c", context.inputContext)
    check("title_corrupted_slot_cannot_continue", corruptStarts == 0
        and context.title.message:find("damaged", 1, true) ~= nil)
    context.input.keypressed("n", context.inputContext)
    check("title_corrupted_slot_requires_overwrite_confirmation",
        context.title.mode == "overwrite-confirm" and corruptStarts == 0)
    context.input.keypressed("n", context.inputContext)
    check("title_corrupted_overwrite_cancel_preserves_bytes",
        context.title.mode == "normal"
        and love.filesystem.read("saves/slot1.lua") == corruptedBytes)
    love.filesystem.write("saves/slot1.lua.bak.tmp", "invalid backup temporary")
    check("save_delete_removes_all_recovery_files", context.save.delete(1)
        and love.filesystem.getInfo("saves/slot1.lua") == nil
        and love.filesystem.getInfo("saves/slot1.lua.tmp") == nil
        and love.filesystem.getInfo("saves/slot1.lua.bak") == nil
        and love.filesystem.getInfo("saves/slot1.lua.bak.tmp") == nil)

end

return Test
