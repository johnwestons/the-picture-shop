local State = require("src.state")
local Schema = require("src.save_schema")
local Upgrades = require("src.warehouse_upgrades")
local Storage = require("src.pallet_storage")
local Forklift = require("src.forklift")
local PalletState = require("src.pallet_state")
local Jobs = require("src.jobs")
local Procurement = require("src.procurement")
local Config = require("src.config")
local Codec = require("src.net.codec")

local Test = {}
local function same(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not same(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
local function world(x, y)
    return { x=x, y=y, fromX=x, fromY=y, direction="northwest", rotation=1, spawnProgress=1 }
end
local function fixture()
    local state = State.new()
    state.money = 50000
    assert(Upgrades.purchase(state, "front_left", "storage", "SAVE-STORAGE", 0))
    assert(Upgrades.purchaseForklift(state, "SAVE-FORKLIFT", 0))
    Upgrades.update(state, 0)
    Upgrades.update(state, 0, { noticeDeliveredProjectId="WUP-0001", noticeCallId="CALL-1" })
    Upgrades.update(state, 2, { workerArrivedProjectId="WUP-0001" })
    Upgrades.update(state, 98)
    local rack = Storage.rackDefinition("front_left")
    state.storage.racks[rack.id] = rack
    local job = Jobs.createOffer({ id="WAREHOUSE-SAVE", company="Storage save fixture",
        sourceSize={width=20,height=16}, finishedSize={width=10,height=8},
        sheetCounts={500,1000,1500,500} })
    Jobs.accept(job)
    state.jobs.active = { job }
    for index, pallet in ipairs(job.pallets) do
        pallet.location, pallet.status, pallet.world = "warehouse", "raw", world(330+index*60, 420)
    end
    local pallets = job.pallets
    pallets[1].location, pallets[1].world = "rack", nil
    pallets[1].storage = { rackId=rack.id, row=1, column=2 }
    pallets[1].wrapped, pallets[1].status = true, "wrapped"
    pallets[1].remainingSheets, pallets[1].damagedSheets = 475, 25
    pallets[3].location, pallets[3].world = "stacked", Schema.copy(pallets[2].world)
    pallets[3].storage = { supportPalletId=pallets[2].id, level=2 }
    state.forklift.owned = true
    state.forklift.operating, state.forklift.operatorPlayerId = true, 2
    state.forklift.forkHeight, state.forklift.targetForkHeight, state.forklift.lifting = 0.6, 1, true
    state.forklift.carriedPalletId = pallets[4].id
    pallets[4].location, pallets[4].world = "on_forklift", world(state.forklift.x, state.forklift.y)
    return state, pallets
end
local function payload(state, version)
    return { version=version or Schema.VERSION, slot=2, createdAt=1, updatedAt=2,
        state=state, player={x=410,y=420} }
end

function Test.run(_, check)
    local fresh = State.new()
    check("warehouse_save_new_schema_and_safe_defaults",
        Schema.VERSION == 15 and Schema.validState(Schema.snapshot(fresh))
        and fresh.warehouse.bays.front_left.status == "locked"
        and fresh.warehouse.bays.front_right.status == "locked" and not fresh.warehouse.forkliftOwned
        and not fresh.forklift.owned and next(fresh.storage.racks) == nil)
    local old = Schema.snapshot(fresh)
    old.warehouse, old.storage, old.forklift = nil, nil, nil
    old.money, old.inventory.paper, old.inventory.stock.shipping_cartons = 9182, 1875, 37
    local oldJob = Jobs.createOffer({ id="OLD-WAREHOUSE-SAVE", company="Legacy test",
        sourceSize={width=20,height=16}, finishedSize={width=10,height=8}, sheetCounts={500} })
    Jobs.accept(oldJob)
    old.jobs.active = { oldJob }
    local oldPallet = oldJob.pallets[1]
    oldPallet.location, oldPallet.status, oldPallet.world = "warehouse", "raw", world(420, 470)
    local oldBefore = Schema.copy(old)
    local migrated = Schema.migrate(payload(old, 14))
    check("warehouse_save_v14_migration_keeps_money_stock_and_positions",
        migrated and migrated.version == 15 and migrated.state.money == 9182
        and migrated.state.inventory.paper == 1875 and migrated.state.inventory.stock.shipping_cartons == 37
        and same(migrated.state.jobs.active[1].pallets[1], oldBefore.jobs.active[1].pallets[1])
        and same(migrated.state.cutter, oldBefore.cutter)
        and same(migrated.state.palletJack, oldBefore.palletJack)
        and migrated.state.warehouse.bays.front_left.status == "locked"
        and not migrated.state.forklift.owned and not migrated.state.warehouse.forkliftOwned
        and #migrated.state.warehouse.receipts == 0 and same(old, oldBefore))
    local v1 = Schema.migrate({version=1,slot=1,createdAt=1,updatedAt=1,
        state={money=381,inventory={paper=125,prints=7}},player={x=400,y=450}})
    check("warehouse_save_oldest_migration_gets_unowned_defaults",
        v1 and v1.state.money == 381 and v1.state.inventory.paper == 125
        and v1.state.warehouse.bays.front_right.status == "locked" and not v1.state.forklift.owned)

    local state, pallets = fixture()
    local source = Schema.copy(state)
    local saved = Schema.snapshot(state)
    check("warehouse_save_full_storage_and_raised_cargo_snapshot_valid",
        saved and Schema.validState(saved) and Storage.validate(saved) and PalletState.validate(saved))
    check("warehouse_save_snapshot_stops_operator_and_lift_without_dropping_stock",
        not saved.forklift.operating and not saved.forklift.moving and not saved.forklift.lifting
        and saved.forklift.operatorPlayerId == nil and saved.forklift.forkHeight == 0.6
        and saved.forklift.targetForkHeight == 0.6 and saved.forklift.carriedPalletId == pallets[4].id
        and saved.jobs.active[1].pallets[4].location == "on_forklift" and same(source, state))
    check("warehouse_save_all_pallet_ownership_and_inventory_counts_survive",
        saved.jobs.active[1].pallets[1].location == "rack"
        and saved.jobs.active[1].pallets[1].storage.column == 2
        and saved.jobs.active[1].pallets[1].world == nil and saved.jobs.active[1].pallets[1].wrapped
        and saved.jobs.active[1].pallets[1].damagedSheets == 25
        and saved.jobs.active[1].pallets[3].location == "stacked"
        and saved.jobs.active[1].pallets[3].storage.supportPalletId == pallets[2].id
        and saved.inventory.rawPallets == 3 and saved.inventory.finishedPallets == 1)
    local limits = {maxBytes=512*1024,maxDepth=32,maxEntries=32768,maxStringBytes=128*1024,maxNumberBytes=32}
    local encoded = assert(Codec.encode(payload(saved), limits))
    local decoded = assert(Codec.decode(encoded, limits))
    local reopened = State.new()
    local loaded = State.applyLocalSave(reopened, decoded)
    check("warehouse_save_serialized_local_round_trip_preserves_every_new_domain",
        loaded and reopened.activeSlot == 2 and same(reopened.warehouse, saved.warehouse)
        and same(reopened.storage, saved.storage) and same(reopened.forklift, saved.forklift)
        and same(reopened.jobs.active[1].pallets, saved.jobs.active[1].pallets)
        and reopened.money == saved.money and Schema.validState(Schema.snapshot(reopened)))
    local rawReopened = State.new()
    local rawApplied, stopped = State.applyLocalSave(rawReopened, payload(source))
    check("warehouse_save_loading_live_vehicle_stops_at_exact_current_fork_height",
        rawApplied and stopped and not rawReopened.forklift.operating and not rawReopened.forklift.lifting
        and rawReopened.forklift.forkHeight == 0.6 and rawReopened.forklift.targetForkHeight == 0.6
        and rawReopened.forklift.carriedPalletId == pallets[4].id
        and source.forklift.operating and source.forklift.lifting)

    local receiptCopy = Schema.copy(saved)
    local paidAgain, _, replayCode = Upgrades.purchase(receiptCopy, "front_left", "storage", "SAVE-STORAGE", 1000)
    check("warehouse_save_upgrade_receipts_remain_idempotent_after_serialization",
        paidAgain and replayCode == "replayed" and receiptCopy.money == saved.money)
    local pending = State.new()
    pending.money = 10000
    Upgrades.purchase(pending, "front_right", "breakroom", "SAVE-PENDING", 0)
    Upgrades.update(pending, 0)
    local pendingSaved = Schema.snapshot(pending)
    local pendingLoaded = State.new()
    State.applyLocalSave(pendingLoaded, payload(pendingSaved))
    check("warehouse_save_pending_call_gate_survives_without_starting_build",
        Upgrades.pendingNotice(pendingLoaded).projectId == "WUP-0001"
        and not Upgrades.update(pendingLoaded, 240)
        and pendingLoaded.warehouse.projects[1].stage == 0)

    local corrupt = Schema.copy(saved)
    corrupt.warehouse.receipts[1].pricePaid = 1
    local target = State.new()
    target.money, target.screen, target.message, target.activeSlot = 321, "computer", "Keep this shop", 3
    local targetBefore = Schema.copy(target)
    check("warehouse_save_malformed_paid_upgrade_is_rejected_without_reset",
        not Schema.validState(corrupt) and Schema.snapshot(corrupt) == nil
        and Schema.migrate(payload(corrupt)) == nil and Schema.migrate(payload(corrupt,14)) == nil
        and not State.applySave(target, payload(corrupt)) and same(target, targetBefore))
    corrupt = Schema.copy(saved)
    corrupt.storage.revision = -1
    check("warehouse_save_malformed_registry_is_not_erased_on_load",
        not Schema.validState(corrupt) and Schema.snapshot(corrupt) == nil
        and not State.applyLocalSave(target, payload(corrupt)) and same(target, targetBefore))
    corrupt = Schema.copy(saved)
    local collision = corrupt.jobs.active[1].pallets[4]
    collision.location, collision.world = "rack", nil
    collision.storage = Schema.copy(corrupt.jobs.active[1].pallets[1].storage)
    corrupt.forklift.carriedPalletId = nil
    check("warehouse_save_duplicate_rack_slot_rejected_atomically",
        not Schema.validState(corrupt) and not State.applySave(target, payload(corrupt))
        and not State.applySharedUpdate(target, corrupt) and same(target, targetBefore))
    corrupt = Schema.copy(saved)
    corrupt.jobs.active[1].pallets[3].storage.supportPalletId = "MISSING-PALLET"
    check("warehouse_save_missing_stack_support_rejected",
        not Schema.validState(corrupt) and not State.applySave(target, payload(corrupt)) and same(target, targetBefore))
    corrupt = Schema.copy(saved)
    corrupt.forklift.carriedPalletId = "MISSING-CARGO"
    check("warehouse_save_missing_forklift_cargo_rejected",
        not Schema.validState(corrupt) and not State.applySave(target, payload(corrupt)) and same(target, targetBefore))
    corrupt = Schema.copy(saved)
    corrupt.forklift.forkHeight = 2
    check("warehouse_save_invalid_fork_height_never_normalizes_away_cargo",
        not Schema.validState(corrupt) and Schema.snapshot(corrupt) == nil
        and not State.applySave(target, payload(corrupt)) and same(target, targetBefore))
    corrupt = Schema.copy(saved)
    corrupt.warehouse = Upgrades.defaultState()
    check("warehouse_save_vehicle_ownership_requires_paid_entitlement",
        not Schema.validState(corrupt) and Schema.snapshot(corrupt) == nil
        and not State.applySave(target, payload(corrupt)) and same(target, targetBefore))
    corrupt = Schema.copy(saved)
    corrupt.palletJack.carriedPalletId = corrupt.jobs.active[1].pallets[1].id
    local storedBefore = Schema.copy(corrupt.jobs.active[1].pallets)
    check("warehouse_save_reconcile_does_not_steal_rack_stock_for_stale_jack_claim",
        not PalletState.reconcile(corrupt) and same(corrupt.jobs.active[1].pallets, storedBefore)
        and not Schema.validState(corrupt) and not State.applySave(target, payload(corrupt)))
    check("warehouse_save_valid_reconcile_preserves_all_new_locations",
        PalletState.reconcile(reopened) and same(reopened.jobs.active[1].pallets, saved.jobs.active[1].pallets))

    local guest = State.new()
    guest.activeSlot = 3
    local shared = State.applySharedSnapshot(guest, saved)
    check("warehouse_save_guest_receives_domains_without_local_save_authority",
        shared and guest.activeSlot == nil and same(guest.warehouse, saved.warehouse)
        and same(guest.storage, saved.storage) and guest.forklift.carriedPalletId == pallets[4].id)
    guest.screen, guest.message = "workshop_remote", "Rack open"
    local live = Schema.copy(source.forklift)
    live.x, live.y, live.direction, live.forkHeight = 710, 510, "east", 0.7
    live.operatorPlayerId = 3
    assert(Forklift.applySnapshot(guest, live, Config.forklift))
    local incoming = Schema.copy(saved)
    incoming.money = incoming.money + 50
    local applied = State.applySharedUpdate(guest, incoming)
    check("warehouse_save_guest_live_lift_survives_durable_update_with_matching_cargo",
        applied and guest.money == incoming.money and guest.activeSlot == nil
        and guest.screen == "workshop_remote" and guest.message == "Rack open"
        and guest.forklift.operating and guest.forklift.operatorPlayerId == 3 and guest.forklift.lifting
        and guest.forklift.forkHeight == 0.7 and guest.forklift.targetForkHeight == 1
        and guest.forklift.x == 710 and guest.jobs.active[1].pallets[4].world.x == 710
        and Schema.validState(guest))
    local storedUpdate = Schema.copy(saved)
    local newlyStored = storedUpdate.jobs.active[1].pallets[4]
    newlyStored.location, newlyStored.world = "rack", nil
    newlyStored.storage = { rackId="front_left-rack", row=2, column=4 }
    storedUpdate.forklift.carriedPalletId = nil
    local storedApplied = State.applySharedUpdate(guest, storedUpdate)
    check("warehouse_save_new_rack_ownership_wins_over_cached_live_forklift_load",
        storedApplied and not guest.forklift.operating and guest.forklift.carriedPalletId == nil
        and guest.jobs.active[1].pallets[4].location == "rack"
        and Storage.slots(guest,"front_left-rack")[2][4] == pallets[4].id
        and guest.screen == "workshop_remote" and guest.activeSlot == nil and Schema.validState(guest))
    local guestBefore = Schema.copy(guest)
    local forged = Schema.copy(storedUpdate)
    forged.jobs.active[1].pallets[1].storage.column = 99
    check("warehouse_save_malformed_shared_storage_cannot_partially_replace_guest",
        not State.applySharedSnapshot(guest, forged) and not State.applySharedUpdate(guest, forged)
        and same(guest, guestBefore))

    local movingBase = Schema.copy(saved)
    local base = movingBase.jobs.active[1].pallets[2]
    local baseBefore = Schema.copy(base)
    check("warehouse_save_canonical_transfers_cannot_move_supporting_base",
        not PalletState.transition(movingBase,base,"on_pallet_jack")
        and not PalletState.transition(movingBase,base,"outbound_truck")
        and not PalletState.transition(movingBase,base,"at_cutter")
        and not PalletState.transition(movingBase,base,"at_press") and same(base, baseBefore))
    local transfer = State.new()
    transfer.money = 20000
    assert(Upgrades.purchaseForklift(transfer,"TRANSFER-LIFT",0))
    transfer.forklift.owned = true
    transfer.jobs.active = { Schema.copy(oldJob) }
    local movable = transfer.jobs.active[1].pallets[1]
    local lifted = PalletState.transition(transfer,movable,"on_forklift")
    check("warehouse_save_forklift_floor_transition_assigns_single_owner",
        lifted and transfer.forklift.carriedPalletId == movable.id and movable.location == "on_forklift"
        and PalletState.validate(transfer))
    check("warehouse_save_forklift_floor_transition_releases_owner",
        PalletState.transition(transfer,movable,"warehouse",{world=world(530,490)})
        and transfer.forklift.carriedPalletId == nil and movable.world.x == 530 and PalletState.validate(transfer))
    check("warehouse_save_detached_transfer_cannot_claim_forklift",
        not PalletState.transitionDetached(movable,"on_forklift") and movable.location == "warehouse")

    local vendor = Schema.copy(saved)
    assert(Procurement.buy(vendor,1,1))
    local vendorPallet = vendor.procurement.orders[#vendor.procurement.orders].pallets[1]
    vendorPallet.location, vendorPallet.world = "rack", nil
    vendorPallet.storage = {rackId="front_left-rack",row=1,column=5}
    local vendorSaved = Schema.snapshot(vendor)
    local vendorLoaded = State.new()
    check("warehouse_save_vendor_stock_rack_ownership_round_trips",
        Schema.validState(vendorSaved) and State.applyLocalSave(vendorLoaded,payload(vendorSaved))
        and vendorLoaded.procurement.orders[1].pallets[1].location == "rack"
        and vendorLoaded.procurement.orders[1].pallets[1].storage.column == 5
        and vendorLoaded.procurement.orders[1].pallets[1].quantity == vendorPallet.quantity)

    local notice = Schema.copy(saved)
    notice.workPhone.incoming = {id="CALL-999",kind="construction_notice",caller="Construction service",
        role="SERVICE",subject="Construction appointment",message="Scheduled warehouse construction visit.",
        projectId="WUP-0001",bayId="front_left",optionId="storage",receivedAtHours=0,answered=false}
    check("warehouse_save_construction_phone_kind_is_valid_and_retains_project_metadata",
        Schema.validState(notice) and Schema.snapshot(notice).workPhone.incoming.projectId == "WUP-0001")
    notice.workPhone.incoming.bayId = "not-a-bay"
    check("warehouse_save_invalid_construction_phone_reference_shape_rejected", not Schema.validState(notice))

    local badSources = {
        {name="boolean_jack",mutate=function(s) s.palletJack=true end},
        {name="boolean_jack_with_rack",mutate=function(s)
            s.storage.racks["front_left-rack"]=Storage.rackDefinition("front_left");s.palletJack=true end},
        {name="boolean_forklift",mutate=function(s) s.forklift=true end},
        {name="boolean_jobs",mutate=function(s) s.jobs=true end},
        {name="boolean_active_jobs",mutate=function(s) s.jobs.active=true end},
        {name="sparse_active_jobs",mutate=function(s) s.jobs.active={[2]={pallets={}}} end},
        {name="boolean_job_record",mutate=function(s) s.jobs.active={true} end},
        {name="boolean_job_pallets",mutate=function(s) s.jobs.active={{pallets=true}} end},
        {name="boolean_job_pallet",mutate=function(s) s.jobs.active={{pallets={true}}} end},
        {name="boolean_completed_jobs",mutate=function(s) s.jobs.completed=true end},
        {name="boolean_procurement",mutate=function(s) s.procurement=true end},
        {name="boolean_orders",mutate=function(s) s.procurement.orders=true end},
        {name="boolean_order_record",mutate=function(s) s.procurement.orders={true} end},
        {name="boolean_vendor_pallets",mutate=function(s) s.procurement.orders={{pallets=true}} end},
        {name="boolean_vendor_pallet",mutate=function(s) s.procurement.orders={{pallets={true}}} end},
    }
    for _, case in ipairs(badSources) do
        local malformed, destination = State.new(), State.new()
        case.mutate(malformed)
        local prior, sourceBefore = Schema.copy(destination), Schema.copy(malformed)
        local rawOkay, rawAccepted = pcall(State.applySave,destination,payload(malformed))
        local localOkay, localAccepted = pcall(State.applyLocalSave,destination,payload(malformed))
        local snapshotOkay, normalized = pcall(Schema.snapshot,malformed)
        check("warehouse_save_raw_"..case.name.."_rejects_atomically_without_throw",
            rawOkay and not rawAccepted and localOkay and not localAccepted
            and snapshotOkay and normalized == nil and not Schema.validState(malformed)
            and same(destination,prior) and same(malformed,sourceBefore))
    end
    local seats = assert(Schema.snapshot(State.new()))
    seats.money=20000
    assert(Upgrades.purchaseForklift(seats,"SEAT-OWNERSHIP",0))
    seats.forklift.owned, seats.forklift.operating, seats.forklift.operatorPlayerId = true,true,2
    seats.palletJack.operating, seats.palletJack.operatorPlayerId = true,2
    local destination, seatsBefore = State.new(), Schema.copy(seats)
    local destinationBefore = Schema.copy(destination)
    check("warehouse_save_same_worker_cannot_own_both_vehicle_seats_without_cargo_or_racks",
        not Schema.validState(seats) and Schema.snapshot(seats)==nil
        and not State.applySave(destination,payload(seats)) and not State.applyLocalSave(destination,payload(seats))
        and not State.applySharedSnapshot(destination,seats) and not State.applySharedUpdate(destination,seats)
        and same(destination,destinationBefore) and same(seats,seatsBefore))
    check("warehouse_save_legacy_migration_cannot_hide_conflicting_live_seats",
        Schema.migrate(payload(seats,14))==nil and same(seats,seatsBefore))
    local conflictingRepair=Schema.copy(seats)
    conflictingRepair.jobs.active={Schema.copy(oldJob)}
    conflictingRepair.palletJack.carriedPalletId=conflictingRepair.jobs.active[1].pallets[1].id
    local repairBefore=Schema.copy(conflictingRepair)
    check("warehouse_save_reconcile_rejects_double_seat_before_repairing_cargo",
        not PalletState.reconcile(conflictingRepair) and same(conflictingRepair,repairBefore))
    seats.palletJack.operatorPlayerId=1
    local parked=Schema.snapshot(seats)
    check("warehouse_save_distinct_vehicle_operators_can_be_safely_parked",
        Schema.validState(seats) and parked and Schema.validState(parked)
        and not parked.palletJack.operating and parked.palletJack.operatorPlayerId==nil
        and not parked.forklift.operating and parked.forklift.operatorPlayerId==nil
        and State.applyLocalSave(destination,payload(seats)))
    local shortened=assert(Schema.snapshot(State.new()))
    shortened.money=20000
    assert(Upgrades.purchase(shortened,"front_left","floor","SHORTENED-BUILD",0))
    Upgrades.update(shortened,0)
    Upgrades.update(shortened,0,{noticeDeliveredProjectId="WUP-0001",noticeCallId="CALL-900"})
    Upgrades.update(shortened,2,{workerArrivedProjectId="WUP-0001"})
    local shortenedProject=shortened.warehouse.projects[1]
    shortenedProject.stage,shortenedProject.phase,shortenedProject.completedAtHours=4,"complete",26
    shortened.warehouse.bays.front_left.status="complete"
    local prior=Schema.copy(destination)
    check("warehouse_save_rejects_shortened_construction_before_loading_or_normalizing",
        not Schema.validState(shortened) and Schema.snapshot(shortened)==nil
        and not State.applySave(destination,payload(shortened)) and same(destination,prior))
end

return Test
