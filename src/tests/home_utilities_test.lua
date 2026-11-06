local State=require("src.state")
local Home=require("src.home")
local Layout=require("src.home_layouts")
local Furniture=require("src.home_furniture")
local Objects=require("src.home_objects")
local Utilities=require("src.home_utilities")
local Residents=require("src.home_residents")
local Shopping=require("src.home_shopping")
local Schema=require("src.save_schema")
local Calendar=require("src.business_calendar")
local Test={}
local kinds={"wardrobe","cabinet","old_tv","trash_can"}
local function time(s,h) s.calendar=Calendar.dateFromHours(h);s.calendar.elapsed=h%24/24*Calendar.secondsPerDay(s) end
local function fresh(id,preset)
    local s=State.new();s.home=Home.new({apartmentId=id,furnishingPreset=preset});s.home.weekend.phase="home";s.home.weekend.closedAtHours=44;time(s,44)
    local x,y=Layout.spawn(s,1);return s,{id=1,sceneId="home",x=x,y=y}
end
local function near(s,p,item)
    local t=assert(Furniture.targets(s,p)["furniture"..item.id]);p.x,p.y=t.x,t.y
end
local function object(s,p,item,action,food)
    return Objects.command(s,p,"object:"..action..":"..item.id..":"..item.revision..(food and ":"..food or ""))
end
local function place(s,p,item)
    local spot=assert(require("src.tests.home_tables_lamp_test").findSpot(s,item.kind,{p},item.id))
    item.location="floor";item.x,item.y=spot.x,spot.y;return item
end
function Test.run(context,check)
    for _,id in ipairs(require("src.home_catalog").ORDER) do for _,preset in ipairs({"empty","modest"}) do
        local s,p=fresh(id,preset)
        for _,kind in ipairs(kinds) do check("home_utilities_clear_rotations_"..id..preset..kind,require("src.tests.home_tables_lamp_test").findSpot(s,kind,{p})~=nil) end
        check("home_utilities_no_free_starter_extras_"..id..preset,#s.home.furniture.items==(preset=="empty" and 1 or 9))
    end end
    local s,p=fresh();local business=s.money
    for _,kind in ipairs(kinds) do
        local q={productId=kind,quantity=1,requestId="utility-"..kind,expectedRevision=s.home.revision}
        assert(Shopping.order(s,p,q));assert(Shopping.order(s,p,q))
    end
    check("home_utilities_checkout_household_once",s.home.balanceCents==7250 and s.money==business)
    time(s,46);assert(Shopping.advance(s));local parcel=assert(Shopping.target(p,s));p.x,p.y=parcel.x,parcel.y
    assert(Shopping.collect(s,p));check("home_utilities_delivery_once",#s.home.furniture.items==5 and not Shopping.collect(s,p))
    local wardrobe,cabinet,tv,bin=unpack(s.home.furniture.items,2)
    for _,item in ipairs({wardrobe,cabinet,tv,bin}) do place(s,p,item) end
    local g={id=2,sceneId="home",x=p.x,y=p.y};assert(Residents.bind(s,g,string.rep("e",64),{p}))
    local c=require("src.home_chores").ensure(s);c.laundry.clean=2;near(s,g,wardrobe)
    local command="object:stow:"..wardrobe.id..":"..wardrobe.revision
    assert(Objects.command(s,g,command))
    check("home_wardrobe_guest_transfer_replay_conserves_bundles",wardrobe.contents.clean==1 and c.laundry.clean==1 and not Objects.command(s,g,command))
    local gr=Residents.get(s,g);gr.hygiene=0;assert(Residents.command(s,g,"change:furniture"..wardrobe.id))
    near(s,p,wardrobe)
    check("home_wardrobe_changing_locks_contents_and_placement",not object(s,p,wardrobe,"retrieve") and not Furniture.command(s,p,"begin:"..wardrobe.id,{p,g}))
    Residents.advance(s,{p,g},46,46+2/60);time(s,46+2/60)
    check("home_wardrobe_change_consumes_one_real_bundle",wardrobe.contents.clean==0 and c.laundry.clean==1 and gr.hygiene>34 and gr.hygiene<=35)
    assert(object(s,p,wardrobe,"stow"));assert(object(s,p,wardrobe,"retrieve"))
    check("home_wardrobe_round_trip_conserves_clothes",c.laundry.clean==1 and wardrobe.contents.clean==0)
    wardrobe.contents.clean=8;c.laundry.clean=64
    check("home_wardrobe_capacity_and_sale_overflow_rejected",not object(s,p,wardrobe,"stow") and not Objects.canSell(s,wardrobe))
    c.laundry.clean=0;assert(Furniture.command(s,p,"begin:"..wardrobe.id,{p,g}));assert(Furniture.command(s,p,"sell:"..wardrobe.id..":"..wardrobe.editToken,{p,g}))
    check("home_wardrobe_sale_returns_existing_clothes",c.laundry.clean==8)
    near(s,p,cabinet);s.home.inventory.bread=2
    assert(object(s,p,cabinet,"put","bread"));local revision=cabinet.revision
    assert(object(s,p,cabinet,"take","bread"))
    check("home_cabinet_food_round_trip_and_stale_command",s.home.inventory.bread==2 and cabinet.contents.bread==0
        and not Objects.command(s,p,"object:take:"..cabinet.id..":"..revision..":bread"))
    cabinet.contents.bread=32;check("home_cabinet_capacity",not object(s,p,cabinet,"put","bread"))
    near(s,g,bin);c.trash=10;assert(object(s,g,bin,"stow"));assert(object(s,g,bin,"stow"))
    check("home_trash_can_collects_without_destroying_waste",c.trash==0 and bin.contents.trash==10)
    assert(object(s,g,bin,"retrieve"));check("home_trash_can_bag_returns_for_door_disposal",c.trash==8 and bin.contents.trash==2)
    g.x,g.y=Layout.spawn(s,1);assert(Residents.command(s,g,"trash:floor"))
    local at=Calendar.absoluteHours(s);Residents.advance(s,{p,g},at,at+5/60);time(s,at+5/60)
    check("home_trash_can_disposal_only_removes_bagged_batch",c.trash==0 and bin.contents.trash==2)
    near(s,p,bin);assert(Furniture.command(s,p,"begin:"..bin.id,{p,g}));assert(Furniture.command(s,p,"sell:"..bin.id..":"..bin.editToken,{p,g}))
    check("home_trash_can_sale_returns_contained_waste",c.trash==2)
    near(s,p,tv);assert(object(s,p,tv,"on"));local onRevision=tv.revision
    for _,a in ipairs(Furniture.approaches(tv)) do if Utilities.visibleTV(s,{x=a.x,y=a.y},tv,tv) then p.x,p.y=a.x,a.y;break end end
    assert(Residents.command(s,p,"watch:furniture"..tv.id))
    check("home_tv_watch_is_rest_without_sleep_vote",p.resting and not require("src.home_sleep").status(s,{p}))
    near(s,g,tv);check("home_tv_watched_object_cannot_move",not Furniture.command(s,p,"begin:"..tv.id,{p,g}))
    assert(object(s,g,tv,"off"));Residents.advance(s,{p,g},Calendar.absoluteHours(s),Calendar.absoluteHours(s))
    check("home_tv_switch_off_interrupts_viewer",not s.home.residents.owner.activity and not p.resting
        and not Objects.command(s,g,"object:on:"..tv.id..":"..onRevision))
    local bogus=Schema.copy(tv);bogus.kind="cabinet";check("home_tv_power_state_restricted_to_television",not Objects.valid(bogus))
    bogus=Schema.copy(wardrobe);bogus.contents={clean=9};check("home_wardrobe_saved_capacity_enforced",not Objects.valid(bogus))
    bogus=Schema.copy(bin);bogus.contents={trash=0,clean=1};check("home_trash_can_rejects_wrong_saved_contents",not Objects.valid(bogus))
    assert(object(s,g,tv,"on"));local behind={x=tv.x-80,y=tv.y-40}
    check("home_tv_rejects_behind_screen",not Utilities.visibleTV(s,behind,tv,tv))
    local far={x=tv.x+200,y=tv.y+100};check("home_tv_rejects_distant_viewer",not Utilities.visibleTV(s,far,tv,tv))
    s.home.inventory.chair=1;Furniture.materialize(s,false);local chair=s.home.furniture.items[#s.home.furniture.items]
    local found=false
    for y=tv.y-60,tv.y+60,6 do for x=tv.x-96,tv.x+96,8 do
        if not found then
            local seat={id=chair.id,kind="chair",location="floor",direction="southeast",x=x,y=y}
            if Furniture.canPlace(s,seat,{},true) and Utilities.visibleTV(s,p,seat,tv) and Furniture.canPlace(s,seat,{}) then chair.x,chair.y=x,y;chair.location="floor";found=true end
        end
    end end
    assert(found);near(s,g,chair);assert(Residents.command(s,g,"watch:furniture"..chair.id))
    for _,a in ipairs(Furniture.approaches(tv)) do if Utilities.visibleTV(s,{x=a.x,y=a.y},tv,tv) then p.x,p.y=a.x,a.y;break end end
    assert(Residents.command(s,p,"watch:furniture"..tv.id))
    check("home_tv_multiple_viewers_keep_independent_seats",Residents.get(s,g).activity.tvId==tv.id and s.home.residents.owner.activity.tvId==tv.id)
    local watching=Schema.snapshot(s);check("home_tv_watch_snapshot_valid",Schema.validState(watching))
    local invalidWatch=Schema.copy(watching);invalidWatch.home.residents.owner.activity.tvId=0/0
    check("home_tv_invalid_saved_reference_rejected",not Schema.validState(invalidWatch))
    assert(Residents.command(s,p,"cancel"));assert(Residents.command(s,g,"cancel"))
    local wallState,wallPlayer=fresh();local testTV={id=100,kind="old_tv",location="floor",direction="south",powered=true,x=320,y=330}
    wallPlayer.x,wallPlayer.y=320,360
    check("home_tv_wall_blocks_nearby_viewer",not Utilities.visibleTV(wallState,wallPlayer,testTV,testTV))
    p.x,p.y=Layout.spawn(s,1)
    s.home.inventory.bedside_table=1;Furniture.materialize(s,false);local tableItem=place(s,p,s.home.furniture.items[#s.home.furniture.items])
    near(s,p,tv);assert(Furniture.command(s,p,"begin:"..tv.id,{p,g}));p.x,p.y=tableItem.x+50,tableItem.y
    assert(Furniture.command(s,p,"attach:"..tv.id..":"..tv.editToken..":"..tableItem.id..":1:east",{p,g}))
    check("home_tv_surface_keeps_power_and_parent_rotation",require("src.home_surfaces").pose(s,tv).powered and tv.parentId==tableItem.id)
    local snapshot=Schema.snapshot(s);check("home_utilities_snapshot_valid",Schema.validState(snapshot))
    local shared=State.new();assert(State.applySharedSnapshot(shared,snapshot))
    check("home_utilities_shared_contents_and_power",require("src.home_surfaces").find(shared,tv.id).powered and require("src.home_surfaces").find(shared,cabinet.id).contents.bread==32)
    assert(context.save.save(3,s,{sceneId="home",x=p.x,y=p.y}));local saved=assert(context.save.load(3))
    check("home_utilities_disk_contents_and_power",require("src.home_surfaces").find(saved.state,tv.id).powered and saved.state.home.chores.trash==2)
    local migrated=assert(Schema.migrate({version=37,slot=3,createdAt=1,updatedAt=2,state=Schema.snapshot(State.new()),player={x=300,y=400}}))
    check("home_utilities_v37_no_free_items",migrated.version==Schema.VERSION and #migrated.state.home.furniture.items==1 and migrated.state.home.balanceCents==30000)
end
return Test
