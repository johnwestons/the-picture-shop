local Test = {}
local Storage = require("src.pallet_storage")
local Upgrades = require("src.warehouse_upgrades")
local Jobs = require("src.jobs")

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function same(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, item in pairs(left) do if not same(item, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
local function setup(context, vehicleKind)
    local state = context.State and context.State.new() or { jobs={active={}}, procurement={orders={}} }
    state.money, state.warehouse, state.storage = 50000, Upgrades.defaultState(), Storage.defaultState()
    assert(Upgrades.purchase(state, "front_left", "storage", "RACK-PURCHASE", 0))
    assert(Upgrades.purchaseForklift(state, "FORKLIFT-PURCHASE", 0))
    Upgrades.update(state, 0)
    Upgrades.update(state, 0, { noticeDeliveredProjectId="WUP-0001", noticeCallId="CALL-1" })
    Upgrades.update(state, 2, { workerArrivedProjectId="WUP-0001" })
    Upgrades.update(state, 98)
    local rack = Storage.rackDefinition("front_left")
    state.storage.racks[rack.id] = rack
    local job = Jobs.createOffer({ id="STORAGE-TEST", company="Storage test",
        sourceSize={width=20,height=16}, finishedSize={width=10,height=8}, sheetCounts={500,1000,1500} })
    Jobs.accept(job)
    state.jobs.active, state.procurement.orders = {job}, {}
    for index, pallet in ipairs(job.pallets) do
        pallet.location, pallet.status = "warehouse", "raw"
        pallet.world = {x=400+index*40,y=400,direction="northwest",rotation=1,spawnProgress=1}
    end
    state.palletJack = {x=500,y=400,direction="northwest",operating=false,moving=false}
    state.forklift = {x=500,y=400,direction="northwest",owned=true,operating=false,moving=false,forkHeight=0}
    local vehicle = vehicleKind == "forklift" and state.forklift or state.palletJack
    vehicle.operating, vehicle.operatorPlayerId, vehicle.carriedPalletId = true, 1, job.pallets[1].id
    job.pallets[1].location = vehicleKind == "forklift" and "on_forklift" or "on_pallet_jack"
    return state, job.pallets, vehicle
end
local function intent(state, action, pallet, kind, row, column)
    return {requestId="TRANSFER-"..state.storage.revision,expectedRevision=state.storage.revision,
        action=action,vehicle=kind or "pallet_jack",palletId=pallet.id,
        rackId="front_left-rack",row=row or 1,column=column or 1}
end
local function access()
    return {playerId=1,near=true,aligned=true,clear=true,stackable=true,compatible=true}
end
local function stackIntent(state, action, pallet, support)
    return {requestId="STACK-"..state.storage.revision,expectedRevision=state.storage.revision,
        action=action,vehicle="forklift",palletId=pallet.id,supportPalletId=support.id}
end

function Test.run(context, check)
    check("storage_legacy_defaults_are_locked_empty", Storage.normalize(nil).revision == 0
        and next(Storage.normalize(nil).racks) == nil and Storage.rackDefinition("unknown") == nil)
    local state, pallets, vehicle = setup(context)
    local pallet, paper = pallets[1], pallets[1].paper
    pallet.wrapped, pallet.packaging, pallet.remainingSheets, pallet.damagedSheets = true, "boxed", 460, 40
    pallet.press = {completedColors=2,dryUntilHours=180,goodSheets=460,passHistory={{color="cyan"}}}
    local stockBefore = copy(pallet)
    local request = intent(state, "store", pallet)
    local okay, code = Storage.apply(state, request, access())
    check("storage_lower_jack_stores_real_pallet_identity", okay and code == "store"
        and pallet == state.jobs.active[1].pallets[1] and pallet.paper == paper
        and pallet.location == "rack" and pallet.storage.row == 1 and pallet.storage.column == 1
        and vehicle.carriedPalletId == nil and Storage.slots(state,"front_left-rack")[1][1] == pallet.id
        and state.storage.revision == 1 and state.storage.racks["front_left-rack"].revision == 1
        and Storage.validate(state))
    local afterStore = copy(state)
    local replayed, replayCode = Storage.apply(state, request, access())
    check("storage_replayed_transfer_never_duplicates_stock", replayed and replayCode == "replayed"
        and same(state, afterStore) and #state.jobs.active[1].pallets == 3)
    local conflict = copy(request); conflict.column = 2
    local conflictOkay, conflictCode = Storage.apply(state, conflict, access())
    check("storage_request_id_conflict_is_atomic", not conflictOkay and conflictCode == "request_conflict"
        and same(state, afterStore))
    local retrieved = Storage.retrieve(state, intent(state,"retrieve",pallet), access())
    local restored = copy(pallet)
    restored.location, restored.storage, restored.world = stockBefore.location, stockBefore.storage, stockBefore.world
    check("storage_round_trip_preserves_all_paper_wrap_print_counts", retrieved
        and pallet.location == "on_pallet_jack" and pallet.paper == paper
        and vehicle.carriedPalletId == pallet.id and same(restored, stockBefore)
        and Storage.validate(state))

    for column = 1, 5 do
        local current, loads = setup(context)
        check("storage_lower_column_"..column.."_works", Storage.store(current,intent(current,"store",loads[1],nil,1,column),access())
            and Storage.slots(current,"front_left-rack")[1][column] == loads[1].id
            and Storage.retrieve(current,intent(current,"retrieve",loads[1],nil,1,column),access())
            and Storage.validate(current))
    end

    local cases = {
        {name="upper_requires_physical_forklift",code="forklift_required",request=function(r) r.row=2 end},
        {name="out_of_range",code="out_of_range",context=function(c) c.near=false end},
        {name="bad_alignment",code="not_aligned",context=function(c) c.aligned=false end},
        {name="blocked_access",code="blocked",context=function(c) c.clear=false end},
        {name="unvalidated_context",code="out_of_range",context=function(c) c.near=nil end},
        {name="not_vehicle_owner",code="not_operator",context=function(c) c.playerId=2 end},
        {name="moving_vehicle",code="vehicle_not_stationary",state=function(s) s.palletJack.moving=true end},
        {name="parked_vehicle",code="not_operator",state=function(s) s.palletJack.operating=false end},
        {name="two_vehicle_operator",code="invalid_state",state=function(s) s.forklift.operating=true; s.forklift.operatorPlayerId=1 end},
        {name="stale_revision",code="stale_revision",request=function(r) r.expectedRevision=1 end},
        {name="missing_revision",code="invalid_request",request=function(r) r.expectedRevision=nil end},
        {name="row_zero",code="invalid_request",request=function(r) r.row=0 end},
        {name="row_three",code="invalid_request",request=function(r) r.row=3 end},
        {name="column_six",code="invalid_request",request=function(r) r.column=6 end},
        {name="fractional_slot",code="invalid_request",request=function(r) r.column=1.5 end},
        {name="nonfinite_revision",code="invalid_request",request=function(r) r.expectedRevision=math.huge end},
        {name="unexpected_field",code="invalid_request",request=function(r) r.sheets=999 end},
        {name="missing_pallet",code="missing_pallet",request=function(r) r.palletId="MISSING" end},
        {name="floor_pallet_is_not_teleported",code="not_vehicle_cargo",request=function(r,s) r.palletId=s.jobs.active[1].pallets[2].id end},
        {name="incomplete_bay",code="rack_unavailable",state=function(s) s.warehouse.bays.front_left.status="building" end},
        {name="nonstorage_bay",code="rack_unavailable",state=function(s) s.warehouse.bays.front_left.optionId="floor" end},
        {name="unknown_rack",code="rack_unavailable",request=function(r) r.rackId="front_right-rack" end},
    }
    for _, case in ipairs(cases) do
        local current, loads = setup(context)
        local nextRequest, validated = intent(current,"store",loads[1]), access()
        if case.request then case.request(nextRequest,current) end
        if case.context then case.context(validated) end
        if case.state then case.state(current) end
        local before = copy(current)
        local accepted, reason = Storage.apply(current,nextRequest,validated)
        check("storage_rejects_"..case.name.."_atomically", not accepted and reason == case.code and same(current,before))
    end

    local upper, upperPallets, lift = setup(context,"forklift")
    local upperRequest = intent(upper,"store",upperPallets[1],"forklift",2,5)
    local tooLow, heightCode = Storage.apply(upper,upperRequest,access())
    lift.forkHeight, lift.lifting = 1, true
    local movingLift, liftingCode = Storage.apply(upper,upperRequest,access())
    lift.lifting = false
    local storedUpper = Storage.apply(upper,upperRequest,access())
    local recoveredUpper = Storage.apply(upper,intent(upper,"retrieve",upperPallets[1],"forklift",2,5),access())
    check("storage_upper_row_waits_for_fork_raise_then_roundtrips", not tooLow and heightCode == "wrong_fork_height"
        and not movingLift and liftingCode == "lift_in_progress" and storedUpper and recoveredUpper
        and upperPallets[1].location == "on_forklift" and lift.carriedPalletId == upperPallets[1].id
        and Storage.validate(upper))
    upper.warehouse.forkliftOwned = false
    local noEntitlement, entitlementCode = Storage.apply(upper,intent(upper,"store",upperPallets[1],"forklift",2,1),access())
    check("storage_forklift_must_be_purchased", not noEntitlement and entitlementCode == "forklift_not_owned")

    local occupied, occupiedPallets, jack = setup(context)
    assert(Storage.apply(occupied,intent(occupied,"store",occupiedPallets[1]),access()))
    occupiedPallets[2].location, jack.carriedPalletId = "on_pallet_jack", occupiedPallets[2].id
    local occupiedBefore = copy(occupied)
    local race, raceCode = Storage.apply(occupied,intent(occupied,"store",occupiedPallets[2]),access())
    check("storage_slot_race_rejects_without_losing_either_load", not race and raceCode == "slot_occupied"
        and same(occupied,occupiedBefore))
    local loadedRetrieve, loadedCode = Storage.apply(occupied,intent(occupied,"retrieve",occupiedPallets[1]),access())
    check("storage_cannot_retrieve_onto_loaded_vehicle", not loadedRetrieve and loadedCode == "vehicle_loaded"
        and same(occupied,occupiedBefore))

    local vendor, vendorLoads = setup(context)
    local vendorPallet = {id="PO-STORAGE-PALLET",kind="vendor_product",quantity=12,unit="rolls",
        productId="stretch_film",location="on_pallet_jack",status="purchased",world={x=500,y=400},wrapped=true}
    vendorLoads[1].location, vendor.palletJack.carriedPalletId = "warehouse", vendorPallet.id
    vendor.procurement.orders[1] = {id="PO-STORAGE",pallets={vendorPallet}}
    check("storage_procurement_pallet_uses_same_inventory", Storage.apply(vendor,intent(vendor,"store",vendorPallet),access())
        and Storage.apply(vendor,intent(vendor,"retrieve",vendorPallet),access())
        and vendor.procurement.orders[1].pallets[1] == vendorPallet and vendorPallet.quantity == 12
        and vendorPallet.wrapped and Storage.validate(vendor))

    local stacked, stackPallets, stackLift = setup(context,"forklift")
    stackLift.forkHeight = 1
    local top, base = stackPallets[1], stackPallets[2]
    local stackRequest = stackIntent(stacked,"stack",top,base)
    local stackDone = Storage.stack(stacked,stackRequest,access())
    check("storage_floor_stack_keeps_exact_support_and_pallet", stackDone and top.location == "stacked"
        and top.storage.supportPalletId == base.id and top.storage.level == 2
        and top.world.x == base.world.x and Storage.isSupporting(stacked,base.id) and Storage.validate(stacked))
    top.world.x = top.world.x + 1
    check("storage_validation_rejects_drifted_stack_position", not Storage.validate(stacked))
    top.world.x = base.world.x
    local blockedBase, baseCode = Storage.apply(stacked,stackIntent(stacked,"unstack",base,top),access())
    check("storage_base_cannot_be_removed_while_supporting", not blockedBase and baseCode == "supporting_pallet"
        and base.location == "warehouse" and top.location == "stacked")
    local unstacked = Storage.unstack(stacked,stackIntent(stacked,"unstack",top,base),access())
    check("storage_unstack_round_trip_restores_forklift_owner", unstacked and top.location == "on_forklift"
        and top.storage == nil and stackLift.carriedPalletId == top.id and not Storage.isSupporting(stacked,base.id)
        and Storage.validate(stacked))

    for _, failure in ipairs({{field="stackable",code="not_stackable"},{field="compatible",code="incompatible_footprint"}}) do
        local current, loads, currentLift = setup(context,"forklift")
        currentLift.forkHeight = 1
        local validated = access(); validated[failure.field] = false
        local before = copy(current)
        local allowed, failureCode = Storage.apply(current,stackIntent(current,"stack",loads[1],loads[2]),validated)
        check("storage_stack_rejects_"..failure.field, not allowed and failureCode == failure.code and same(current,before))
    end

    local invalid, invalidLoads = setup(context)
    local duplicate = copy(invalidLoads[2]); duplicate.id = invalidLoads[1].id
    invalid.jobs.active[1].pallets[4] = duplicate
    check("storage_validation_rejects_duplicate_ids", not Storage.validate(invalid))
    invalid.jobs.active[1].pallets[4] = nil
    invalidLoads[2].location, invalidLoads[3].location = "rack", "rack"
    invalidLoads[2].storage = {rackId="front_left-rack",row=1,column=2}
    invalidLoads[3].storage = copy(invalidLoads[2].storage)
    check("storage_validation_rejects_duplicate_slot_owners", not Storage.validate(invalid))
    invalidLoads[2].location, invalidLoads[3].location = "stacked", "stacked"
    invalidLoads[2].storage = {supportPalletId=invalidLoads[3].id,level=2}
    invalidLoads[3].storage = {supportPalletId=invalidLoads[2].id,level=2}
    check("storage_validation_rejects_stack_cycles", not Storage.validate(invalid))
    invalidLoads[3].location, invalidLoads[3].storage = "warehouse", nil
    invalidLoads[1].location, invalid.palletJack.carriedPalletId = "stacked", nil
    invalidLoads[1].storage = {supportPalletId=invalidLoads[2].id,level=2}
    check("storage_validation_rejects_three_high_stacks", not Storage.validate(invalid))
    invalidLoads[1].location, invalidLoads[1].storage = "warehouse", nil
    invalidLoads[2].storage.supportPalletId = "MISSING"
    check("storage_validation_rejects_missing_stack_support", not Storage.validate(invalid))
    invalidLoads[2].location, invalidLoads[2].storage = "on_forklift", nil
    check("storage_validation_rejects_orphaned_forklift_load", not Storage.validate(invalid))
    invalidLoads[2].location, invalidLoads[2].storage = "warehouse", {rackId="front_left-rack",row=1,column=1}
    check("storage_schema_rejects_stale_placement_metadata", not Storage.validate(invalid)
        and select(2,Storage.normalizePlacement(invalidLoads[2])) ~= nil)
    local badRegistry = Storage.defaultState(); badRegistry.revision = -1
    check("storage_schema_rejects_invalid_revision", Storage.normalize(badRegistry) == nil)
    badRegistry = Storage.defaultState(); badRegistry.racks["front_left-rack"] = {id="front_left-rack",bayId="front_left",revision=0,slots={}}
    check("storage_schema_never_accepts_second_inventory", Storage.normalize(badRegistry) == nil)
    local normalized = Storage.normalize(state.storage)
    check("storage_schema_preserves_replay_receipts_without_alias", normalized ~= state.storage and same(normalized,state.storage))
    local bounded, boundedPallets = setup(context)
    for index=1,Storage.MAX_RECEIPTS+4 do
        local action = index % 2 == 1 and "store" or "retrieve"
        assert(Storage.apply(bounded,intent(bounded,action,boundedPallets[1]),access()))
    end
    check("storage_receipt_ledger_is_bounded_and_valid", #bounded.storage.appliedRequests == Storage.MAX_RECEIPTS
        and bounded.storage.revision == Storage.MAX_RECEIPTS+4 and Storage.normalize(bounded.storage) ~= nil
        and Storage.validate(bounded))
    local evicted = {requestId="TRANSFER-0",expectedRevision=0,action="store",vehicle="pallet_jack",
        palletId=boundedPallets[1].id,rackId="front_left-rack",row=1,column=1}
    local boundedBefore = copy(bounded)
    local oldAllowed, oldReason = Storage.apply(bounded,evicted,access())
    check("storage_evicted_old_request_still_cannot_reapply", not oldAllowed and oldReason == "stale_revision"
        and same(bounded,boundedBefore))
    local wrongSlot, wrongSlotLoads = setup(context)
    assert(Storage.apply(wrongSlot,intent(wrongSlot,"store",wrongSlotLoads[1]),access()))
    local wrongSlotBefore = copy(wrongSlot)
    local wrongAllowed, wrongReason = Storage.apply(wrongSlot,intent(wrongSlot,"retrieve",wrongSlotLoads[1],nil,1,2),access())
    check("storage_retrieve_rejects_incorrect_selected_slot", not wrongAllowed and wrongReason == "wrong_slot"
        and same(wrongSlot,wrongSlotBefore))
    local lowerFork, lowerLoads, lowerLift = setup(context,"forklift")
    check("storage_forklift_lower_row_roundtrip", Storage.apply(lowerFork,intent(lowerFork,"store",lowerLoads[1],"forklift"),access())
        and Storage.apply(lowerFork,intent(lowerFork,"retrieve",lowerLoads[1],"forklift"),access())
        and lowerLift.carriedPalletId == lowerLoads[1].id and Storage.validate(lowerFork))
    lowerLift.targetForkHeight = 1
    local targetAllowed, targetReason = Storage.apply(lowerFork,intent(lowerFork,"store",lowerLoads[1],"forklift"),access())
    check("storage_forklift_unsettled_target_cannot_transfer", not targetAllowed and targetReason == "wrong_fork_height")
    local pending, pendingLoads = setup(context)
    assert(Storage.apply(pending,intent(pending,"store",pendingLoads[1]),access()))
    pending.warehouse.bays.front_left.status = "building"
    check("storage_schema_rejects_stock_in_incomplete_rack", not Storage.validate(pending))
    local crossVehicle, crossLoads = setup(context)
    crossVehicle.forklift.carriedPalletId = crossLoads[1].id
    check("storage_schema_rejects_cross_vehicle_double_claim", not Storage.validate(crossVehicle))
    local fresh = {jobs={active={}},procurement={orders={}}}
    local missingStorageBefore = copy(fresh)
    local missingAllowed = Storage.apply(fresh,{requestId="NO-STATE",expectedRevision=0,action="store",
        vehicle="pallet_jack",palletId="MISSING",rackId="front_left-rack",row=1,column=1},access())
    check("storage_invalid_request_never_creates_default_state", not missingAllowed and same(fresh,missingStorageBefore))
    local saturated, saturatedLoads = setup(context)
    saturated.storage.revision = 2147483647
    local saturatedBefore = copy(saturated)
    local saturatedOkay, saturatedCode = Storage.apply(saturated,intent(saturated,"store",saturatedLoads[1]),access())
    check("storage_revision_ceiling_rejects_before_stock_mutation", not saturatedOkay
        and saturatedCode == "revision_exhausted" and same(saturated,saturatedBefore) and Storage.validate(saturated))
    for _, field in ipairs({"palletJack","forklift"}) do
        local malformed = setup(context)
        malformed[field] = true
        local called, valid = pcall(Storage.validate,malformed)
        check("storage_invalid_"..field.."_record_returns_false_without_throw", called and not valid)
    end
    local seats = setup(context)
    seats.forklift.operating, seats.forklift.operatorPlayerId = true, seats.palletJack.operatorPlayerId
    check("storage_live_ownership_rejects_worker_in_both_vehicle_seats", not Storage.validate(seats))
end

return Test
