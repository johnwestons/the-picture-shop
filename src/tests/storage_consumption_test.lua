local Test = {}
local State = require("src.state")
local Schema = require("src.save_schema")
local Procurement = require("src.procurement")
local Fleet = require("src.machine_fleet")
local PalletState = require("src.pallet_state")
local Storage = require("src.pallet_storage")
local Upgrades = require("src.warehouse_upgrades")
local Config = require("src.config")

local function same(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not same(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
local function fresh()
    local state = State.new()
    state.money, state.inventory.stock.maintenance_kit = 50000, 0
    Fleet.ensure(state)
    return state
end
local function delivered(state, category, item)
    local okay, order = Procurement.buy(state, category or 4, item or 1)
    assert(okay)
    assert(Procurement.unload(state, order.id, order.pallets[1].id,
        Config.palletLogistics.spawnPoints, Config.palletLogistics.unloadOrigin))
    local pallet = order.pallets[1]
    pallet.world.spawnProgress = 1
    return pallet
end
local function shelf(state, pallet, column)
    if state.warehouse.bays.front_left.status == "locked" then
        assert(Upgrades.purchase(state, "front_left", "storage", "CONSUMPTION-RACK", 0))
        Upgrades.update(state, 0)
        Upgrades.update(state, 0, {noticeDeliveredProjectId="WUP-0001",noticeCallId="CALL-1"})
        Upgrades.update(state, 2, {workerArrivedProjectId="WUP-0001"})
        Upgrades.update(state, 98)
        state.storage.racks["front_left-rack"] = Storage.rackDefinition("front_left")
    end
    pallet.location, pallet.world = "rack", nil
    pallet.storage = {rackId="front_left-rack",row=1,column=column or 1}
    assert(PalletState.validate(state))
end
local function machine(state, kind)
    return assert(Fleet.installed(state, kind or "skid_wrapper"))
end
local function finish(state, kind)
    local item = machine(state, kind)
    if kind == "polar_115" then return Fleet.completeCutterLubrication(state, item.id, {score=1}) end
    local scores = {}
    for _, task in ipairs(Fleet.maintenancePlan(state,item.id).tasks) do scores[task.id] = 1 end
    return Fleet.completeMaintenance(state, item.id, scores)
end

function Test.run(_, check)
    local floor = fresh()
    local pallet = delivered(floor)
    pallet.quantity, floor.inventory.stock.maintenance_kit = 3, 3
    local world = pallet.world
    check("storage_consumption_floor_partial_preserves_identity_and_position",
        Procurement.consumePhysicalProduct(floor,"maintenance_kit",1)
        and pallet.remainingQuantity == 2 and pallet.quantity == 3
        and pallet.location == "warehouse" and pallet.world == world
        and floor.inventory.stock.maintenance_kit == 3 and PalletState.validate(floor))
    check("storage_consumption_floor_exhaustion_uses_canonical_transition",
        Procurement.consumePhysicalProduct(floor,"maintenance_kit",2)
        and pallet.remainingQuantity == 0 and pallet.location == "none" and pallet.status == "consumed"
        and pallet.world == nil and PalletState.validate(floor))
    local exhausted = Schema.copy(floor)
    check("storage_consumption_exhausted_physical_stock_cannot_be_reused",
        not Procurement.consumePhysicalProduct(floor,"maintenance_kit",1) and same(floor,exhausted))

    local insufficient = fresh()
    delivered(insufficient)
    local before = Schema.copy(insufficient)
    check("storage_consumption_insufficient_quantity_never_partially_debits",
        not Procurement.consumePhysicalProduct(insufficient,"maintenance_kit",2) and same(insufficient,before))
    for _, amount in ipairs({-1,math.huge,0/0,"1"}) do
        check("storage_consumption_rejects_invalid_quantity_"..tostring(amount),
            not Procurement.consumePhysicalProduct(insufficient,"maintenance_kit",amount) and same(insufficient,before))
    end

    for _, kind in ipairs({"skid_wrapper","polar_115"}) do
        local stored = fresh()
        local kit = delivered(stored)
        shelf(stored,kit)
        local original = Schema.copy(stored)
        local okay, reason = finish(stored,kind)
        check("storage_consumption_"..kind.."_rejects_rack_kit_without_service_or_stock_change",
            not okay and type(reason)=="string" and reason:find("Retrieve",1,true)
            and same(stored,original) and kit.remainingQuantity == nil and Storage.validate(stored))
        check("storage_consumption_"..kind.."_repeated_denial_stays_atomic",
            not finish(stored,kind) and same(stored,original))
    end

    for _, location in ipairs({"stacked","on_forklift","on_pallet_jack"}) do
        local inaccessible = fresh()
        local kit = delivered(inaccessible)
        if location == "stacked" then
            local base = delivered(inaccessible,3,1)
            kit.storage, kit.world = {supportPalletId=base.id,level=2}, Schema.copy(base.world)
        elseif location == "on_forklift" then
            assert(Upgrades.purchaseForklift(inaccessible,"CONSUMPTION-FORKLIFT",0))
            inaccessible.forklift.owned, inaccessible.forklift.carriedPalletId = true,kit.id
        else inaccessible.palletJack.carriedPalletId = kit.id end
        kit.location = location
        assert(PalletState.validate(inaccessible))
        local original = Schema.copy(inaccessible)
        check("storage_consumption_rejects_"..location.."_kit_without_mutation",
            not finish(inaccessible) and same(inaccessible,original) and PalletState.validate(inaccessible))
    end

    local supporting = fresh()
    local base, top = delivered(supporting), delivered(supporting,3,1)
    top.location, top.storage, top.world = "stacked", {supportPalletId=base.id,level=2}, Schema.copy(base.world)
    assert(PalletState.validate(supporting))
    local supportedBefore = Schema.copy(supporting)
    check("storage_consumption_supporting_kit_is_not_decremented_or_despawned",
        not Procurement.consumePhysicalProduct(supporting,"maintenance_kit",1)
        and not finish(supporting) and same(supporting,supportedBefore) and PalletState.validate(supporting))

    local mixed = fresh()
    local blocked, accessible = delivered(mixed), delivered(mixed)
    shelf(mixed,blocked)
    local mixedBefore = Schema.copy(mixed)
    check("storage_consumption_mixed_accessibility_cannot_bypass_physical_reservation",
        not Procurement.consumePhysicalProduct(mixed,"maintenance_kit",2,{allowAbstract=true})
        and same(mixed,mixedBefore))
    check("storage_consumption_mixed_accessibility_uses_only_floor_allocation",
        finish(mixed) and mixed.inventory.stock.maintenance_kit == 1
        and accessible.location == "none" and accessible.remainingQuantity == 0
        and blocked.location == "rack" and blocked.remainingQuantity == nil and PalletState.validate(mixed))
    local mixedAfter = Schema.copy(mixed)
    check("storage_consumption_duplicate_completion_cannot_consume_remaining_shelf_kit",
        not finish(mixed) and same(mixed,mixedAfter))

    for _, kind in ipairs({"skid_wrapper","polar_115"}) do
        local legacy = fresh()
        legacy.inventory.stock.maintenance_kit = 1
        check("storage_consumption_"..kind.."_preserves_abstract_only_starter_kits",
            finish(legacy,kind) and legacy.inventory.stock.maintenance_kit == 0
            and machine(legacy,kind).maintenance.serviceCount == 1)
        local once = Schema.copy(legacy)
        check("storage_consumption_"..kind.."_empty_duplicate_completion_is_atomic",
            not finish(legacy,kind) and same(legacy,once))
    end
    local combined = fresh()
    local stored = delivered(combined)
    shelf(combined,stored)
    combined.inventory.stock.maintenance_kit = 2
    check("storage_consumption_real_abstract_remainder_does_not_touch_shelved_kit",
        finish(combined) and combined.inventory.stock.maintenance_kit == 1
        and stored.location == "rack" and stored.remainingQuantity == nil and PalletState.validate(combined))
    local combinedAfter = Schema.copy(combined)
    check("storage_consumption_abstract_remainder_is_not_invented_on_retry",
        not finish(combined) and same(combined,combinedAfter))
    local inbound = fresh()
    inbound.inventory.stock.maintenance_kit = 1
    assert(Procurement.buy(inbound,4,1))
    check("storage_consumption_undelivered_order_does_not_reserve_legacy_stock",
        finish(inbound) and inbound.inventory.stock.maintenance_kit == 0
        and inbound.procurement.orders[1].pallets[1].location == "awaiting_delivery")

    local multi = fresh()
    local first, second = delivered(multi), delivered(multi)
    check("storage_consumption_multiple_floor_pallets_deplete_as_one_request",
        Procurement.consumePhysicalProduct(multi,"maintenance_kit",2)
        and first.location == "none" and second.location == "none"
        and first.remainingQuantity == 0 and second.remainingQuantity == 0 and PalletState.validate(multi))
    local rollback = fresh()
    local a, b = delivered(rollback), delivered(rollback)
    local rollbackBefore, firstWorld = Schema.copy(rollback), a.world
    local transition, calls = PalletState.transition, 0
    PalletState.transition = function(...)
        calls = calls + 1
        if calls == 2 then return false,"injected refusal" end
        return transition(...)
    end
    local okay, reason = Procurement.consumePhysicalProduct(rollback,"maintenance_kit",2)
    PalletState.transition = transition
    check("storage_consumption_late_transition_refusal_rolls_back_all_allocations",
        not okay and reason == "injected refusal" and calls == 2
        and same(rollback,rollbackBefore) and a.world == firstWorld and b.remainingQuantity == nil)
end

return Test
