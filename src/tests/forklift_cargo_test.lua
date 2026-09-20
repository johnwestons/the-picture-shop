local Test = {}
local Cargo = require("src.forklift_cargo")
local Forklift = require("src.forklift")
local PalletState = require("src.pallet_state")
local Storage = require("src.pallet_storage")
local Upgrades = require("src.warehouse_upgrades")
local config = {spawnX=400,spawnY=400,forkOffsetX=56,forkOffsetY=32}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function same(left,right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right or left ~= left and right ~= right end
    for key,item in pairs(left) do if not same(item,right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
local function free() return true end
local function fresh(vendor)
    local state = {money=20000,jobs={active={}},procurement={orders={}},
        warehouse=Upgrades.defaultState(),storage=Storage.defaultState(),
        palletJack={operating=false,moving=false},forklift=Forklift.defaultState(config)}
    assert(Upgrades.purchaseForklift(state,"CARGO-FORKLIFT",0))
    state.forklift.owned = true
    assert(Forklift.acquire(state,config,1))
    local x,y = Forklift.dropPosition(state,config)
    local pallet = {id="CARGO-PALLET",location="warehouse",status="raw",
        world={x=x,y=y,fromX=x,fromY=y,rotation=1,direction="northwest",spawnProgress=1,custom="kept"},
        quantity=500,remainingQuantity=430,remainingSheets=430,damagedSheets=70,
        wrapped=true,packaging="boxed",paper={status="complete",custom={1,2,3}},
        press={completedColors=2,dryUntilHours=180,passHistory={{color="cyan"}}}}
    local owner = {id="CARGO-OWNER",pallets={pallet}}
    if vendor then state.procurement.orders[1] = owner else state.jobs.active[1] = owner end
    assert(PalletState.validate(state))
    return state,pallet
end
local function direct(state,id,action,options,operator,settings,view)
    return Cargo.callback(state,settings or config,operator or 1,options or {validateWorld=free})(
        id or "CARGO-PALLET",action or "attach",view or copy(state.forklift))
end
local function load(state,pallet,options)
    return Forklift.attachCargo(state,config,1,pallet.id,Cargo.callback(state,config,1,options or {validateWorld=free}))
end
local function unload(state,pallet,options)
    return Forklift.detachCargo(state,config,1,pallet.id,Cargo.callback(state,config,1,options or {validateWorld=free}))
end

function Test.run(_,check)
    local function test(name,condition) check("forklift_cargo_"..name,condition) end
    for _,vendor in ipairs({false,true}) do
        local state,pallet = fresh(vendor)
        local before,paper,press = copy(pallet),pallet.paper,pallet.press
        local seen
        local loaded = load(state,pallet,{validateWorld=function(query)
            seen=copy(query)
            query.vehicle.x,query.pallet.paper.custom[1]=99999,99999
            return true
        end})
        test((vendor and "vendor" or "customer").."_pickup_uses_single_real_pallet",loaded
            and state.forklift.carriedPalletId==pallet.id and pallet.location=="on_forklift"
            and PalletState.find(state,pallet.id).pallet==pallet and pallet.paper==paper and pallet.press==press
            and pallet.world.x==state.forklift.x and pallet.world.y==state.forklift.y
            and state.forklift.x==400 and pallet.paper.custom[1]==1 and PalletState.validate(state))
        test((vendor and "vendor" or "customer").."_validator_receives_true_identity",seen
            and seen.vendor==vendor and seen.palletId==pallet.id and seen.playerId==1
            and seen.action=="attach" and seen.pallet.location=="warehouse" and seen.forkX==344 and seen.forkY==368)
        local loadedBefore = copy(state)
        test((vendor and "vendor" or "customer").."_repeat_pickup_has_no_second_transfer",
            not load(state,pallet,{validateWorld=function() error("must not call") end}) and same(state,loadedBefore))
        local dropped = unload(state,pallet)
        local after = copy(pallet)
        after.world=before.world
        test((vendor and "vendor" or "customer").."_round_trip_preserves_stock_wrap_damage_and_print",dropped
            and state.forklift.carriedPalletId==nil and pallet.location=="warehouse"
            and same(after,before) and pallet.world.x==344 and pallet.world.y==368
            and pallet.world.custom=="kept" and PalletState.validate(state))
        local droppedBefore = copy(state)
        test((vendor and "vendor" or "customer").."_repeat_drop_is_atomic",not unload(state,pallet) and same(state,droppedBefore))
    end

    for _,location in ipairs({"warehouse","cutter_output","press_output"}) do
        local state,pallet=fresh()
        pallet.location=location
        test("customer_"..location.."_floor_pickup",load(state,pallet) and PalletState.validate(state))
    end
    for _,location in ipairs({"cutter_output","press_output","at_cutter","at_press","awaiting_delivery","outbound_truck","none"}) do
        local state,pallet=fresh(true)
        pallet.location=location
        local before=copy(state)
        local okay,reason=direct(state)
        test("vendor_"..location.."_not_floor_stock",not okay and reason=="not_floor_stock" and same(state,before))
    end
    for _,location in ipairs({"at_cutter","at_press","awaiting_delivery","outbound_truck","none"}) do
        local state,pallet=fresh()
        pallet.location=location
        local before=copy(state)
        local okay,reason=direct(state)
        test("customer_"..location.."_not_floor_stock",not okay and reason=="not_floor_stock" and same(state,before))
    end

    local cases = {
        {name="wrong_action",action="store",code="invalid_action"},
        {name="missing_id",id="MISSING",code="missing_pallet"},
        {name="control_character_id",id="bad\nID",code="invalid_pallet"},
        {name="oversized_id",id=string.rep("p",129),code="invalid_pallet"},
        {name="invalid_operator",operator=5,code="invalid_operator"},
        {name="wrong_operator",operator=2,code="not_owner"},
        {name="validator_required",options={},code="world_validator_required"},
        {name="drop_resolver_type",options={validateWorld=free,dropPosition=true},code="invalid_drop_resolver"},
        {name="validator_refusal",options={validateWorld=function() return false,"wall" end},code="wall"},
        {name="validator_requires_boolean",options={validateWorld=function() return 1 end},code="blocked"},
        {name="validator_error",options={validateWorld=function() error("world broken") end},code="world_validation_failed"},
        {name="bad_pickup_radius",settings={floorPickupRadius=-1},code="invalid_transfer_config"},
        {name="bad_drop_radius",settings={floorDropRadius=math.huge},code="invalid_transfer_config"},
        {name="moving",state=function(s) s.forklift.moving=true end,code="not_stationary"},
        {name="lifting",state=function(s) s.forklift.lifting=true; s.forklift.targetForkHeight=1 end,code="not_stationary"},
        {name="raised",state=function(s) s.forklift.forkHeight=1; s.forklift.targetForkHeight=1 end,code="lower_forks_first"},
        {name="travel_height",state=function(s) s.forklift.forkHeight=.08; s.forklift.targetForkHeight=.08 end,code="lower_forks_first"},
        {name="parked",state=function(s) s.forklift.operating=false; s.forklift.operatorPlayerId=nil end,code="not_owner"},
        {name="vehicle_not_materialized",state=function(s) s.forklift=Forklift.defaultState(config) end,code="not_owned"},
        {name="no_paid_entitlement",state=function(s) s.warehouse=Upgrades.defaultState() end,code="not_owned"},
        {name="stale_vehicle",view=function(v) v.x=v.x+1 end,code="stale_vehicle"},
        {name="outside_pickup_reach",state=function(_,p) p.world.x=p.world.x+25 end,code="out_of_range"},
        {name="nonfinite_floor_position",state=function(_,p) p.world.x=math.huge end,code="invalid_pallet_position"},
        {name="outsize_floor_position",state=function(_,p) p.world.x=1000001 end,code="invalid_pallet_position"},
        {name="floor_stock_still_unloading",state=function(_,p) p.world.spawnProgress=.5 end,code="pallet_in_motion"},
        {name="invalid_vehicle_container",state=function(s) s.forklift=42 end,code="invalid_state"},
        {name="invalid_jack_container",state=function(s) s.palletJack=42 end,code="invalid_state"},
        {name="malformed_jobs",state=function(s) s.jobs.active=42 end,code="invalid_state"},
        {name="duplicate_identity",state=function(s,p) s.jobs.active[1].pallets[2]=copy(p) end,code="invalid_state"},
        {name="same_operator_both_vehicles",state=function(s) s.palletJack.operating=true; s.palletJack.operatorPlayerId=1 end,code="invalid_state"},
        {name="jack_custody",state=function(s,p) p.location="on_pallet_jack"; s.palletJack.carriedPalletId=p.id end,code="not_floor_stock"},
        {name="supporting_floor_base",state=function(s,p)
            local top=copy(p); top.id="CARGO-TOP"; top.location="stacked"; top.storage={supportPalletId=p.id,level=2}
            s.jobs.active[1].pallets[2]=top
        end,code="supporting_pallet"},
    }
    for _,case in ipairs(cases) do
        local state,pallet=fresh()
        if case.state then case.state(state,pallet) end
        local view=copy(state.forklift)
        if case.view then case.view(view) end
        local before,world=copy(state),pallet.world
        local called,okay,reason=pcall(direct,state,case.id,case.action,case.options,case.operator,case.settings,view)
        test("reject_"..case.name.."_atomic",called and not okay and reason==case.code and same(state,before) and pallet.world==world)
    end

    local stacked,base=fresh()
    local top=copy(base)
    top.id,top.location,top.storage="CARGO-TOP","stacked",{supportPalletId=base.id,level=2}
    stacked.jobs.active[1].pallets[2]=top
    local stackedBefore=copy(stacked)
    local picked,pickCode=direct(stacked,top.id)
    test("stacked_upper_cannot_bypass_stack_transfer",not picked and pickCode=="not_floor_stock" and same(stacked,stackedBefore))

    local shelved,shelfPallet=fresh()
    assert(Upgrades.purchase(shelved,"front_left","storage","CARGO-RACK",0))
    Upgrades.update(shelved,0)
    Upgrades.update(shelved,0,{noticeDeliveredProjectId="WUP-0001",noticeCallId="CALL-1"})
    Upgrades.update(shelved,2,{workerArrivedProjectId="WUP-0001"})
    Upgrades.update(shelved,98)
    shelved.storage.racks["front_left-rack"]=Storage.rackDefinition("front_left")
    shelfPallet.location,shelfPallet.world="rack",nil
    shelfPallet.storage={rackId="front_left-rack",row=1,column=1}
    assert(PalletState.validate(shelved))
    local shelfBefore=copy(shelved)
    picked,pickCode=direct(shelved)
    test("rack_pallet_cannot_bypass_slot_transfer",not picked and pickCode=="not_floor_stock" and same(shelved,shelfBefore))

    local state,pallet=fresh()
    pallet.world.x=pallet.world.x+24
    test("exact_pickup_radius_boundary_allowed",load(state,pallet))
    local before=copy(state)
    local okay,reason=unload(state,pallet,{validateWorld=free,dropPosition=function(x,y) return x+25,y end})
    test("drop_resolver_cannot_teleport",not okay and reason=="out_of_range" and same(state,before))
    okay,reason=unload(state,pallet,{validateWorld=free,dropPosition=function() return math.huge,0 end})
    test("drop_resolver_nonfinite_atomic",not okay and reason=="invalid_target" and same(state,before))
    okay,reason=unload(state,pallet,{validateWorld=free,dropPosition=function() error("bad resolver") end})
    test("drop_resolver_error_atomic",not okay and reason=="drop_resolution_failed" and same(state,before))
    okay,reason=unload(state,pallet,{validateWorld=function() return false,"occupied" end})
    test("occupied_drop_retains_actual_cargo",not okay and reason=="occupied" and same(state,before))
    okay,reason=unload(state,pallet,{validateWorld=free,dropPosition=function(x,y,view) view.x=1; return x+24,y end})
    test("bounded_drop_adjustment_allowed_without_pose_change",okay and reason=="detached"
        and pallet.world.x==368 and state.forklift.x==400 and PalletState.validate(state))

    state,pallet=fresh()
    local transition=PalletState.transition
    PalletState.transition=function(s,p,target,options)
        -- Simulate canonical postcondition refusal, including a replacement
        -- rollback table, to verify this adapter retains the old reference.
        p.world=copy(p.world)
        return false,"canonical_refusal"
    end
    before=copy(state)
    local originalWorld=pallet.world
    local called
    called,okay,reason=pcall(load,state,pallet)
    PalletState.transition=transition
    test("canonical_refusal_restores_exact_world_reference",called and not okay and reason=="canonical_refusal"
        and same(state,before) and pallet.world==originalWorld)

    state,pallet=fresh()
    test("sync_empty_is_read_only",not Cargo.sync(state,config) and pallet.location=="warehouse")
    assert(load(state,pallet))
    local world,paper=pallet.world,pallet.paper
    test("sync_identical_pose_idempotent",not Cargo.sync(state,config) and pallet.world==world)
    assert(Forklift.setForkHeight(state,config,1,.08))
    Forklift.update(state,1,config)
    local moved=Forklift.move(state,1,0,.5,config,free,1)
    test("real_movement_precedes_canonical_sync",moved and state.forklift.x>world.x)
    okay,reason=Cargo.sync(state,config)
    test("sync_moves_real_carried_stock_not_duplicate",okay and reason=="synced" and pallet.world==world
        and pallet.paper==paper and world.x==state.forklift.x and world.y==state.forklift.y
        and world.fromX==world.x and world.fromY==world.y and world.direction=="east" and world.rotation==2
        and world.spawnProgress==1 and world.custom=="kept" and PalletState.validate(state))
    local names={"northwest","north","northeast","east","southeast","south","southwest","west"}
    local rotations={1,1,2,2,4,4,3,3}
    for index,name in ipairs(names) do
        state.forklift.direction=name
        Cargo.sync(state,config)
        test("sync_heading_"..name,world.direction==name and world.rotation==rotations[index])
    end
    Forklift.move(state,0,0,.1,config,free,1)
    Forklift.setForkHeight(state,config,1,1)
    Forklift.update(state,3,config)
    Forklift.forceRelease(state,config,1)
    state.forklift.x=state.forklift.x+1
    test("sync_disconnected_raised_load_keeps_custody",Cargo.sync(state,config)
        and pallet.location=="on_forklift" and state.forklift.carriedPalletId==pallet.id
        and state.forklift.forkHeight==1 and not state.forklift.operating)
    before=copy(state)
    state.forklift.carriedPalletId="MISSING"
    local invalid=copy(state)
    okay,reason=Cargo.sync(state,config)
    test("sync_invalid_custody_never_repairs_or_discards",not okay and reason=="invalid_state" and same(state,invalid))
end

return Test
