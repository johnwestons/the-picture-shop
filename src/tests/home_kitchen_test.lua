local State=require("src.state")
local Home=require("src.home")
local Layout=require("src.home_layouts")
local Furniture=require("src.home_furniture")
local Residents=require("src.home_residents")
local Cooking=require("src.home_cooking")
local Calendar=require("src.business_calendar")
local Schema=require("src.save_schema")
local Objects=require("src.home_objects")
local Test={}
local function time(s,h) s.calendar=Calendar.dateFromHours(h);s.calendar.elapsed=h%24/24*Calendar.secondsPerDay(s) end
local function fresh(id,preset)
    local s=State.new();s.home=Home.new({apartmentId=id or "brick-walkup",furnishingPreset=preset or "empty"})
    s.home.weekend.phase="home";s.home.weekend.closedAtHours=44;time(s,44)
    local x,y=Layout.spawn(s,1);return s,{id=1,sceneId="home",x=x,y=y}
end
local function advance(s,people,min)
    local first=Calendar.absoluteHours(s);Residents.advance(s,people,first,first+min/60);time(s,first+min/60)
end
local function install(s,p,kind,x,y)
    s.home.inventory[kind]=1;Furniture.materialize(s,false);local item=s.home.furniture.items[#s.home.furniture.items]
    item.location="floor";item.x,item.y=x,y
    assert(Furniture.canPlace(s,item,{}))
    local target=Furniture.targets(s,p)["furniture"..item.id]
    if target then p.x,p.y=target.x,target.y end
    return item
end
local function stock(s) s.home.inventory.bread=10;s.home.inventory.vegetables=10 end
function Test.run(context,check)
    for _,id in ipairs(require("src.home_catalog").ORDER) do
        for _,preset in ipairs({"empty","modest"}) do
            local s,p=fresh(id,preset);local x,y=Layout.kitchenPower(s)
            for _,d in ipairs(require("src.home_furniture_catalog").DIRECTIONS) do
                local c={id=100,kind="stove",x=x,y=y,direction=d}
                local good,why=Furniture.canPlace(s,c,{p})
                check("home_kitchen_power_routes_"..id.."_"..preset.."_"..d,good,why)
            end
            check("home_kitchen_no_new_starter_gifts_"..id..preset,#s.home.furniture.items==(preset=="empty" and 1 or 9))
            local c={id=100,kind="stove",x=x+8,y=y,direction="south"}
            check("home_kitchen_stove_cannot_install_off_power_"..id..preset,not Furniture.canPlace(s,c,{},true))
        end
    end
    local s,p=fresh();stock(s);local stove=install(s,p,"stove",Layout.kitchenPower(s))
    local g={id=2,sceneId="home",x=p.x,y=p.y};assert(Residents.bind(s,g,string.rep("e",64),{p}))
    assert(Residents.command(s,p,"cook:furniture"..stove.id));local owner=s.home.residents.owner
    check("home_kitchen_cooking_debits_ingredients_and_creates_mess_once",s.home.inventory.bread==9 and s.home.inventory.vegetables==8
        and s.home.chores.dishes==2 and s.home.chores.trash==1 and not Residents.command(s,p,"cook:furniture"..stove.id))
    check("home_kitchen_stove_excludes_other_resident",not Residents.command(s,g,"cook:furniture"..stove.id))
    check("home_kitchen_cooking_blocks_stove_move",not Furniture.command(s,p,"begin:"..stove.id,{p,g}))
    advance(s,{p,g},10);local command="season:"..owner.revision;assert(Residents.command(s,p,command))
    check("home_kitchen_timing_is_host_clock_and_once",owner.activity.cookQuality==3 and not Residents.command(s,p,command))
    check("home_kitchen_cook_activity_shared_snapshot_valid",Schema.validState(Schema.snapshot(s)))
    local shared=State.new();assert(State.applySharedSnapshot(shared,Schema.snapshot(s)))
    check("home_kitchen_quality_and_reservation_replicate",shared.home.residents.owner.activity.cookQuality==3 and Cooking.reserved(shared,"good_meal")==2)
    assert(context.save.save(3,s,{x=p.x,y=p.y,sceneId="home"}))
    local loaded=State.new();assert(State.applyLocalSave(loaded,assert(context.save.load(3))));Residents.recover(loaded)
    check("home_kitchen_reload_does_not_mint_food_or_refund_ingredients",not loaded.home.residents.owner.activity and loaded.home.inventory.bread==9
        and (loaded.home.inventory.good_meal or 0)==0 and Cooking.reserved(loaded,"good_meal")==0)
    advance(s,{p,g},10)
    check("home_kitchen_completed_batch_yields_two_quality_portions",s.home.inventory.good_meal==2 and not owner.activity and Cooking.reserved(s,"good_meal")==0)
    advance(s,{p,g},1);check("home_kitchen_completed_batch_not_repeated",s.home.inventory.good_meal==2)
    owner.hunger=0;assert(Residents.command(s,p,"goodmeal:floor"));advance(s,{p,g},15)
    check("home_kitchen_quality_food_consumed_once_and_restores_hunger",s.home.inventory.good_meal==1 and owner.hunger>74 and owner.hunger<75)
    assert(Residents.command(s,p,"cook:furniture"..stove.id));assert(Residents.command(s,p,"season:"..owner.revision));advance(s,{p,g},20)
    check("home_kitchen_early_timing_still_produces_edible_portions",s.home.inventory.plain_meal==2)
    assert(Residents.command(s,p,"cook:furniture"..stove.id));p.x=p.x+25;advance(s,{p,g},20)
    check("home_kitchen_movement_cancels_without_free_food",not owner.activity and s.home.inventory.plain_meal==2 and s.home.inventory.bread==7)
    local target=Furniture.targets(s,p)["furniture"..stove.id];p.x,p.y=target.x,target.y
    s.home.inventory.vegetables=0;local bread=s.home.inventory.bread;local mess=s.home.chores.dishes
    check("home_kitchen_missing_ingredient_is_atomic",not Residents.command(s,p,"cook:furniture"..stove.id) and s.home.inventory.bread==bread and s.home.chores.dishes==mess)
    stock(s);s.home.inventory.good_meal=9999
    check("home_kitchen_full_output_storage_prevents_start",not Residents.command(s,p,"cook:furniture"..stove.id) and s.home.inventory.bread==10)
    s.home.inventory.good_meal=9998;assert(Residents.command(s,p,"cook:furniture"..stove.id))
    check("home_kitchen_pending_output_reserves_all_quality_outcomes",not Cooking.hasRoom(s,"good_meal",1) and Cooking.hasRoom(s,"bread",1))
    local bad=Schema.copy(s.home);bad.inventory.good_meal=9999
    check("home_kitchen_overbooked_snapshot_rejected",not Home.valid(bad))
    bad=Schema.copy(s.home);bad.residents.owner.activity.cookQuality=4
    check("home_kitchen_invalid_quality_rejected",not Home.valid(bad))
    assert(Residents.command(s,p,"cancel"));check("home_kitchen_cancel_releases_reservation",Cooking.hasRoom(s,"good_meal",2))
    for _,timing in ipairs({0,3,5,8,10}) do
        local a,pa=fresh();stock(a);pa.x,pa.y=Layout.toWorld(unpack(Layout.get(a).fixtures.sink.approach))
        assert(Residents.command(a,pa,"prepare:sink"));advance(a,{pa},timing)
        if timing<10 then assert(Residents.command(a,pa,"season:"..a.home.residents.owner.revision)) end
        advance(a,{pa},10-timing)
        local food=timing==5 and "good_sandwich" or (timing==3 or timing==8) and "sandwich" or "rough_sandwich"
        check("home_kitchen_sandwich_timing_"..timing,a.home.inventory[food]==2 and a.home.inventory.bread==9 and a.home.inventory.vegetables==9)
    end
    for _,kind in ipairs({"countertop","kitchen_table"}) do
        local a,pa=fresh();stock(a);local tableItem=install(a,pa,kind,320,456)
        assert(Residents.command(a,pa,"prepare:furniture"..tableItem.id));advance(a,{pa},10)
        check("home_kitchen_prep_on_purchased_"..kind,a.home.inventory.rough_sandwich==2)
        a.home.inventory.cup=1;Furniture.materialize(a,false);local cup=a.home.furniture.items[#a.home.furniture.items]
        assert(Furniture.command(a,pa,"begin:"..cup.id,{pa}))
        assert(Furniture.command(a,pa,"attach:"..cup.id..":"..cup.editToken..":"..tableItem.id..":1:east",{pa}))
        check("home_kitchen_small_object_on_"..kind,Home.valid(a.home) and cup.parentId==tableItem.id)
    end
    local a,pa=fresh();stock(a);local fridge=install(a,pa,"refrigerator",768,492)
    assert(Objects.command(a,pa,"object:put:"..fridge.id..":"..fridge.revision..":vegetables"))
    check("home_kitchen_full_fridge_stores_raw_ingredients",fridge.contents.vegetables==1 and a.home.inventory.vegetables==9 and Objects.capacity(fridge)==60)
    assert(Objects.command(a,pa,"object:take:"..fridge.id..":"..fridge.revision..":vegetables"))
    check("home_kitchen_fridge_transfer_conserves_ingredients",fridge.contents.vegetables==0 and a.home.inventory.vegetables==10 and Home.valid(a.home))
    local guest={id=2,sceneId="home",x=pa.x,y=pa.y};assert(Residents.bind(a,guest,string.rep("a",64),{pa}))
    a.home.inventory.sandwich=9998;fridge.contents.sandwich=1
    pa.x,pa.y=Layout.toWorld(unpack(Layout.get(a).fixtures.sink.approach));assert(Residents.command(a,pa,"prepare:sink"))
    check("home_kitchen_reserved_output_blocks_fridge_transfer",not Objects.command(a,guest,"object:take:"..fridge.id..":"..fridge.revision..":sandwich")
        and fridge.contents.sandwich==1 and a.home.inventory.sandwich==9998)
    check("home_kitchen_reserved_output_blocks_filled_fridge_sale",not Objects.canSell(a,fridge))
    local Shopping=require("src.home_shopping")
    assert(Shopping.order(a,pa,{productId="sandwich",quantity=1,requestId="reserved-sandwich",expectedRevision=a.home.revision}))
    time(a,45);assert(Shopping.advance(a));local delivery=Shopping.target(guest,a);guest.x,guest.y=delivery.x,delivery.y
    check("home_kitchen_reserved_output_keeps_delivery_waiting",not Shopping.collect(a,guest) and Shopping.waiting(a)==1 and a.home.inventory.sandwich==9998)
    advance(a,{pa,guest},1)
    assert(Shopping.collect(a,guest))
    check("home_kitchen_completed_batch_releases_unused_quality_reservations",a.home.inventory.rough_sandwich==2 and a.home.inventory.sandwich==9999)
    -- Reset the comparison fixture after the completed capacity scenario.
    a,pa=fresh();stock(a)
    local b,pb=fresh();stock(b);pa.x,pa.y=Layout.toWorld(unpack(Layout.get(a).fixtures.sink.approach));pb.x,pb.y=pa.x,pa.y
    assert(Residents.command(a,pa,"prepare:sink"));assert(Residents.command(b,pb,"prepare:sink"))
    advance(a,{pa},60);for _=1,60 do advance(b,{pb},1) end
    check("home_kitchen_large_step_matches_short_steps",a.home.inventory.rough_sandwich==2 and b.home.inventory.rough_sandwich==2
        and math.abs(a.home.residents.owner.hunger-b.home.residents.owner.hunger)<1e-7)
    a,pa=fresh();a.home.balanceCents=100000
    for _,kind in ipairs({"refrigerator","countertop","kitchen_table"}) do
        assert(Shopping.order(a,pa,{productId=kind,quantity=1,requestId="kitchen-"..kind,expectedRevision=a.home.revision}))
    end
    time(a,46);assert(Shopping.advance(a));local delivery=Shopping.target(pa,a);pa.x,pa.y=delivery.x,delivery.y
    local collected,collectMessage=Shopping.collect(a,pa);assert(collected,collectMessage);local found={}
    for _,item in ipairs(a.home.furniture.items) do found[item.kind]=true end
    local repeated=Shopping.collect(a,pa)
    local valid=Home.valid(a.home)
    check("home_kitchen_all_new_furniture_delivers_once",found.refrigerator and found.countertop and found.kitchen_table
        and #a.home.furniture.items==4 and not repeated and valid,
        ("storage=%s/%s/%s items=%d retry=%s valid=%s message=%s"):format(tostring(found.refrigerator),
            tostring(found.countertop),tostring(found.kitchen_table),#a.home.furniture.items,tostring(repeated),tostring(valid),tostring(collectMessage)))
    local migrated=assert(Schema.migrate({version=33,slot=3,createdAt=1,updatedAt=2,state=Schema.snapshot(State.new()),player={x=300,y=400}}))
    check("home_kitchen_legacy_migration_no_free_ingredients",migrated.version==39 and (migrated.state.home.inventory.bread or 0)==0)
end
return Test
