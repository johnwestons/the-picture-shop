local State=require("src.state")
local Home=require("src.home")
local Layout=require("src.home_layouts")
local Catalog=require("src.home_furniture_catalog")
local Furniture=require("src.home_furniture")
local Surface=require("src.home_surfaces")
local Residents=require("src.home_residents")
local Dining=require("src.home_dining")
local Schema=require("src.save_schema")
local Calendar=require("src.business_calendar")
local Test={}
local function time(s,h) s.calendar=Calendar.dateFromHours(h);s.calendar.elapsed=h%24/24*Calendar.secondsPerDay(s) end
function Test.fresh(id)
    local s=State.new();s.home=Home.new({apartmentId=id});s.home.weekend.phase="home";s.home.weekend.closedAtHours=44;time(s,44)
    local x,y=Layout.spawn(s,1);return s,{id=1,sceneId="home",x=x,y=y}
end
function Test.table(s,p,kind)
    s.home.inventory[kind or "kitchen_table"]=1;Furniture.materialize(s,false)
    local item=s.home.furniture.items[#s.home.furniture.items]
    local spot=assert(require("src.tests.home_tables_lamp_test").findSpot(s,item.kind,{p},item.id))
    item.x,item.y,item.location=spot.x,spot.y,"floor";return item
end
function Test.seat(s,parent,id,slot,kind)
    for y=parent.y-48,parent.y+48,6 do for x=parent.x-80,parent.x+80,8 do
        for _,direction in ipairs(Catalog.DIRECTIONS) do
            local item={id=id,kind=kind or "chair",x=x,y=y,location="floor",direction=direction}
            if Furniture.canPlace(s,item,{},true) and Dining.seatReaches(s,item,parent.id,slot or 1) and Furniture.canPlace(s,item,{}) then return item end
        end
    end end
end
function Test.near(s,p,parentId)
    local Navigation=require("src.navigation");local obstacles=Furniture.obstacles(s)
    local assets={getData=function() return Layout.mask(s.home.apartmentId) end}
    for _,a in ipairs(Surface.approaches(s,{location="surface",parentId=parentId})) do
        if Navigation.isWalkable(assets,a.x,a.y,obstacles) then p.x,p.y=a.x,a.y;return end
    end
    error("No serving approach")
end
function Test.serve(s,p,parentId,slot,food)
    return Residents.command(s,p,"dine:serve:"..parentId..":"..slot..":"..food..":"..s.home.dining.revision)
end
function Test.run(context,check)
    for _,id in ipairs(require("src.home_catalog").ORDER) do
        local s,p=Test.fresh(id);local tableItem=Test.table(s,p)
        for _,direction in ipairs(Catalog.DIRECTIONS) do
            tableItem.direction=direction
            check("home_dining_aligned_chair_"..id..direction,Test.seat(s,tableItem,100)~=nil)
        end
    end
    local s,p=Test.fresh();local tableItem=Test.table(s,p);local g={id=2,sceneId="home",x=p.x,y=p.y}
    assert(Residents.bind(s,g,string.rep("f",64),{p}))
    s.home.inventory.basic_meal=3;s.home.inventory.good_meal=1;s.home.inventory.bottled_drink=1
    Test.near(s,p,tableItem.id);g.x,g.y=p.x,p.y
    local serve="dine:serve:"..tableItem.id..":1:basic_meal:"..s.home.dining.revision
    assert(Residents.command(s,g,serve));check("home_dining_guest_serve_once",s.home.inventory.basic_meal==2 and #s.home.dining.items==1 and not Residents.command(s,g,serve))
    check("home_dining_meal_blocks_object_slot",not Surface.canAttach(s,{kind="cup",id=-1},tableItem.id,1,p))
    check("home_dining_cannot_serve_on_occupied_slot",not Test.serve(s,p,tableItem.id,1,"good_meal") and s.home.inventory.good_meal==1)
    assert(Test.serve(s,p,tableItem.id,2,"good_meal"));assert(Test.serve(s,p,tableItem.id,3,"bottled_drink"))
    local meal=s.home.dining.items[1];local pose=Dining.pose(s,meal);local oldX,oldY=pose.x,pose.y
    tableItem.direction="east";pose=Dining.pose(s,meal)
    check("home_dining_portions_follow_table_rotation",pose.x~=oldX or pose.y~=oldY)
    tableItem.direction="southeast"
    s.home.inventory.chair=1;Furniture.materialize(s,false);local chair=s.home.furniture.items[#s.home.furniture.items]
    local seat=assert(Test.seat(s,tableItem,chair.id));chair.x,chair.y,chair.direction,chair.location=seat.x,seat.y,seat.direction,"floor"
    local original=chair.direction;chair.direction=Catalog.rotate(original,4)
    check("home_dining_chair_must_face_surface",not Dining.seatReaches(s,chair,tableItem.id,1));chair.direction=original
    local target=assert(Furniture.targets(s,p)["furniture"..chair.id]);p.x,p.y=target.x,target.y
    local eat="dine:eat:"..meal.id..":"..chair.id..":"..s.home.dining.revision
    assert(Residents.command(s,p,eat));check("home_dining_eating_debits_served_not_pantry",#s.home.dining.items==2 and s.home.inventory.basic_meal==2
        and s.home.residents.owner.activity.diningParentId==tableItem.id and #Dining.children(s,tableItem.id)==3)
    check("home_dining_same_portion_cannot_feed_guest",not Residents.command(s,g,eat) and not Residents.get(s,g).activity)
    check("home_dining_eating_holds_surface_slot",not Surface.canAttach(s,{kind="cup",id=-1},tableItem.id,1,g))
    Test.near(s,g,tableItem.id)
    assert(Furniture.command(s,p,"permission:move:1",{p,g}))
    check("home_dining_eating_blocks_table_edit",not Furniture.command(s,g,"begin:"..tableItem.id,{p,g}))
    local snapshot=Schema.snapshot(s);check("home_dining_active_and_served_snapshot_valid",Schema.validState(snapshot))
    local remote=State.new();assert(State.applySharedSnapshot(remote,snapshot))
    check("home_dining_shared_snapshot_keeps_portion_and_seat",#remote.home.dining.items==2 and remote.home.residents.owner.activity.furnitureId==chair.id)
    assert(context.save.save(3,s,{sceneId="home",x=p.x,y=p.y}));local reloaded=State.new();assert(State.applyLocalSave(reloaded,assert(context.save.load(3))));Residents.recover(reloaded)
    check("home_dining_reload_keeps_uneaten_no_refund_for_started_meal",#reloaded.home.dining.items==2 and reloaded.home.inventory.basic_meal==2 and not reloaded.home.residents.owner.activity)
    assert(Residents.command(s,p,"cancel"));check("home_dining_cancel_clears_plate_without_food_refund",#Dining.children(s,tableItem.id)==2 and s.home.inventory.basic_meal==2)
    local bad=Schema.copy(s.home);bad.dining.items[2].slot=bad.dining.items[1].slot;check("home_dining_rejects_duplicate_saved_slot",not Home.valid(bad))
    bad=Schema.copy(s.home);bad.dining.items[1].food="vegetables";check("home_dining_raw_ingredients_not_servings",not Home.valid(bad))
    s.home.inventory.good_meal=10000
    Test.near(s,p,tableItem.id);assert(Furniture.command(s,p,"begin:"..tableItem.id,{p,g}))
    local store="store:"..tableItem.id..":"..tableItem.editToken
    check("home_dining_full_pantry_blocks_packing_without_loss",not Furniture.command(s,p,store,{p,g}) and #s.home.dining.items==2 and tableItem.location=="floor")
    s.home.inventory.good_meal=0;assert(Furniture.command(s,p,store,{p,g}))
    check("home_dining_pack_returns_real_food_once",#s.home.dining.items==0 and s.home.inventory.good_meal==1 and s.home.inventory.bottled_drink==1 and not Furniture.command(s,p,store,{p,g}))
    Test.near(s,p,0)
    check("home_dining_starter_laptop_keeps_counter_slot",not Test.serve(s,p,0,1,"basic_meal"))
    assert(Test.serve(s,p,0,2,"basic_meal"));meal=s.home.dining.items[1]
    local back="dine:return:"..meal.id..":"..s.home.dining.revision
    assert(Residents.command(s,p,back));check("home_dining_counter_return_once",s.home.inventory.basic_meal==2 and not Residents.command(s,p,back))
    assert(Test.serve(s,p,0,2,"basic_meal"));meal=s.home.dining.items[1]
    assert(Residents.command(s,p,"dine:eat:"..meal.id..":0:"..s.home.dining.revision))
    check("home_dining_standing_counter_meal",s.home.residents.owner.activity.diningParentId==0 and Schema.validState(Schema.snapshot(s)))
    local sale,sp=Test.fresh();local low=Test.table(sale,sp,"coffee_table")
    check("home_dining_couch_can_reach_low_table",Test.seat(sale,low,100,1,"couch")~=nil)
    sale.home.inventory.pizza_slice=1;Test.near(sale,sp,low.id);assert(Test.serve(sale,sp,low.id,1,"pizza_slice"))
    local balance=sale.home.balanceCents;assert(Furniture.command(sale,sp,"begin:"..low.id,{sp}))
    local sell="sell:"..low.id..":"..low.editToken;assert(Furniture.command(sale,sp,sell,{sp}))
    check("home_dining_sale_returns_portion_and_credits_once",sale.home.inventory.pizza_slice==1 and #sale.home.dining.items==0
        and sale.home.balanceCents==balance+1600 and not Furniture.command(sale,sp,sell,{sp}))
    sp.x,sp.y=0,0
    check("home_dining_cannot_serve_from_across_apartment",not Test.serve(sale,sp,0,2,"pizza_slice") and sale.home.inventory.pizza_slice==1)
    local legacy=Schema.snapshot(State.new());legacy.home.dining=nil
    local migrated=assert(Schema.migrate({version=38,slot=3,createdAt=1,updatedAt=2,state=legacy,player={x=300,y=400}}))
    check("home_dining_legacy_migration_empty_no_free_food",migrated.version==Schema.VERSION and #migrated.state.home.dining.items==0 and migrated.state.home.balanceCents==30000)
    for _,command in ipairs({"dine:serve:00:1:basic_meal:0","dine:serve:0:4:basic_meal:0","dine:serve:0:1:vegetables:0","dine:eat:0:0:0","dine:return:1:01"}) do
        check("home_dining_reject_bad_command_"..command,not Residents.validCommand(command))
    end
end
return Test
