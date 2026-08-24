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
    economy.jobs.declined[1] = jobs.createOffer({
        id = "JOB-0097", company = "Declined Save Co.",
        sourceSize = { width = 16, height = 12 }, finishedSize = { width = 8, height = 6 },
        sheetCounts = { 500 }, packaging = "boxed",
    })
    jobs.decline(economy.jobs.declined[1])
    economy.accountsReceivable = economy.jobs.active[1].quote.totalPrice
    economy.nextJobId = 100
    economy.shopProgress.completedCuts = 9
    economy.inventory.plasticWrapRolls = 3
    economy.inventory.plasticWrapUses = 7
    economy.inventory.stock.shipping_cartons = 18
    economy.cutterMemory = { ["1"] = { 12.5, 12, 11.5 }, ["2"] = { 9.5 } }
    economy.cutter.x = 590
    economy.cutter.y = 430
    economy.cutter.direction = "southeast"
    economy.palletJack.x = 612
    economy.palletJack.y = 498
    economy.palletJack.direction = "southeast"
    economy.palletJack.operating = true
    economy.palletJack.carriedPalletId = "JOB-0099-P01"
    economy.wrapper.x = 705
    economy.wrapper.y = 455
    economy.wrapper.direction = "northeast"
    economy.vendorCategory = 4
    check("save_procurement_setup", context.procurement.buy(economy, 1, 1))
    local savedPlayer = { x = 701, y = 502 }
    check("save_write_v3", context.save.save(1, economy, savedPlayer))
    local loaded = context.save.load(1)
    check("save_round_trip", loaded and loaded.state.money == economy.money)
    check("save_jobs_round_trip", loaded
        and loaded.version == context.save.VERSION
        and loaded.state.jobs.active[1].id == "JOB-0099"
        and loaded.state.jobs.active[1].pallets[1].remainingSheets == 1200
        and loaded.state.jobs.completed[1].id == "JOB-0098"
        and loaded.state.jobs.declined[1].id == "JOB-0097")
    check("save_finance_round_trip", loaded
        and loaded.state.accountsReceivable == 450
        and loaded.state.nextJobId == 100)
    check("save_inventory_round_trip", loaded
        and loaded.state.inventory.plasticWrapRolls == 3
        and loaded.state.inventory.plasticWrapUses == 7
        and loaded.state.inventory.stock.shipping_cartons == 18
        and loaded.state.inventory.rawPallets == 1
        and loaded.state.shopProgress.completedCuts == 9)
    check("save_pallet_jack_round_trip", loaded
        and loaded.state.palletJack.x == 612
        and loaded.state.palletJack.y == 498
        and loaded.state.palletJack.direction == "southeast"
        and loaded.state.palletJack.carriedPalletId == "JOB-0099-P01"
        and loaded.state.jobs.active[1].pallets[1].location == "on_pallet_jack")
    check("save_cutter_placement_round_trip", loaded
        and loaded.state.cutter.x == 590
        and loaded.state.cutter.y == 430
        and loaded.state.cutter.direction == "southeast")
    check("save_cutter_measurement_memory_round_trip", loaded
        and #loaded.state.cutterMemory["1"] == 3
        and loaded.state.cutterMemory["1"][1] == 12.5
        and loaded.state.cutterMemory["2"][1] == 9.5)
    check("save_wrapper_placement_round_trip", loaded
        and loaded.state.wrapper.x == 705
        and loaded.state.wrapper.y == 455
        and loaded.state.wrapper.direction == "northeast")
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
    context.save.delete(1)

    context.save.delete(2)
    local v3State = context.State.new()
    v3State.money = 303
    check("save_v3_migration_fixture", context.save.save(2, v3State, { x = 430, y = 530 }))
    local v3Source = love.filesystem.read("saves/slot2.lua")
    local versionReplacements, memoryReplacements
    v3Source, versionReplacements = v3Source:gsub('%["version"%]%s*=%s*4', '["version"] = 3', 1)
    v3Source, memoryReplacements = v3Source:gsub('%s*%["cutterMemory"%]%s*=%s*{%s*},', '', 1)
    check("save_v3_fixture_removes_new_memory_field",
        versionReplacements == 1 and memoryReplacements == 1
        and love.filesystem.write("saves/slot2.lua", v3Source))
    local migratedV3 = context.save.load(2)
    check("save_v3_migration", migratedV3
        and migratedV3.version == context.save.VERSION
        and migratedV3.state.money == 303
        and next(migratedV3.state.cutterMemory) == nil
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
