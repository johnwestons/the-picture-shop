local State=require("src.state")
local Home=require("src.home")
local Layout=require("src.home_layouts")
local Furniture=require("src.home_furniture")
local Objects=require("src.home_objects")
local Residents=require("src.home_residents")
local Calendar=require("src.business_calendar")
local Schema=require("src.save_schema")
local Test={}
function Test.run(context,check)
    local s=State.new();s.home=Home.new({furnishingPreset="modest"});s.home.weekend.phase="home";s.home.weekend.closedAtHours=44
    local byKind={};for _,item in ipairs(s.home.furniture.items) do byKind[item.kind]=item end
    local p={id=1,sceneId="home",x=0,y=0};local guest={id=2,sceneId="home",x=0,y=0}
    assert(Residents.bind(s,guest,string.rep("b",64),{p}));local people={p,guest}
    local function near(item,actor)
        actor=actor or p;local t=assert(Furniture.targets(s,actor)["furniture"..item.id]);actor.x,actor.y=t.x,t.y
    end
    local function sink(actor,id)
        actor=actor or p;actor.x,actor.y=Layout.toWorld(unpack(Layout.get(s).fixtures[id or "sink"].approach))
    end
    local function command(action,item,food,actor)
        return Residents.command(s,actor or p,"object:"..action..":"..item.id..":"..item.revision..(food and ":"..food or ""))
    end
    local function advance(minutes,actors)
        local first=Calendar.absoluteHours(s);local last=first+minutes/60
        Residents.advance(s,actors or people,first,last)
        s.calendar=Calendar.dateFromHours(last);s.calendar.elapsed=(last%24)/24*Calendar.secondsPerDay(s)
    end
    local fridge,lamp,cup=byKind.mini_fridge,byKind.floor_lamp,byKind.cup
    local money=s.home.balanceCents;near(fridge)
    local put="object:put:"..fridge.id..":"..fridge.revision..":basic_meal"
    assert(Residents.command(s,p,put))
    check("home_objects_fridge_moves_real_portion",fridge.contents.basic_meal==1 and s.home.inventory.basic_meal==3 and s.home.balanceCents==money)
    check("home_objects_stale_transfer_does_not_duplicate",not Residents.command(s,p,put) and fridge.contents.basic_meal==1 and s.home.inventory.basic_meal==3)
    assert(command("take",fridge,"basic_meal"))
    check("home_objects_take_returns_same_portion",fridge.contents.basic_meal==0 and s.home.inventory.basic_meal==4)
    fridge.contents.basic_meal=24;local revision=fridge.revision
    check("home_objects_capacity_rejection_atomic",not command("put",fridge,"basic_meal") and fridge.revision==revision and s.home.inventory.basic_meal==4)
    fridge.contents.basic_meal=2
    assert(Furniture.command(s,p,"begin:"..fridge.id,people))
    check("home_objects_cannot_use_fridge_under_edit",not command("take",fridge,"basic_meal"))
    assert(Furniture.command(s,p,"store:"..fridge.id..":"..fridge.editToken,people))
    check("home_objects_packed_fridge_retains_food",fridge.contents.basic_meal==2 and not command("take",fridge,"basic_meal"))
    s.home.inventory.basic_meal=9999
    assert(Furniture.command(s,p,"begin:"..fridge.id,people));local sell="sell:"..fridge.id..":"..fridge.editToken
    check("home_objects_full_pantry_prevents_filled_sale",not Furniture.command(s,p,sell,people) and Furniture.find(s,fridge.id) and s.home.balanceCents==money)
    s.home.inventory.basic_meal=4
    assert(Furniture.command(s,p,sell,people))
    check("home_objects_filled_sale_returns_food_once",s.home.inventory.basic_meal==6 and s.home.balanceCents==money+3200 and not Furniture.command(s,p,sell,people))
    near(lamp,guest)
    local on="object:on:"..lamp.id..":"..lamp.revision
    assert(Residents.command(s,guest,on))
    check("home_objects_guest_can_use_lamp_without_rearrange_permission",lamp.lit and not s.home.furniture.permissions.move and not Residents.command(s,guest,on))
    assert(command("off",lamp,nil,guest));check("home_objects_lamp_has_explicit_off",lamp.lit==false)
    near(cup);assert(command("pickup",cup))
    check("home_objects_pickup_reserves_specific_cup",Objects.held(s,p)==cup and not Objects.held(s,guest) and cup.parentId==nil and cup.x==0 and cup.y==0
        and Schema.validState(Schema.snapshot(s)))
    check("home_objects_other_resident_cannot_take_held_cup",not command("pickup",cup,nil,guest) and not command("away",cup,nil,guest))
    check("home_objects_carried_cup_cannot_be_sold_or_edited",not Furniture.command(s,p,"begin:"..cup.id,people))
    local cupTarget="furniture"..cup.id
    p.x,p.y=0,0
    check("home_objects_fill_requires_sink_distance",not Residents.command(s,p,"cupfill:"..cupTarget) and not cup.contents.water)
    sink();assert(Residents.command(s,p,"cupfill:"..cupTarget))
    sink(guest)
    check("home_objects_cup_fill_reserves_actual_sink",not Residents.command(s,guest,"wash:sink") and not command("away",cup))
    p.x=p.x-20;advance(2)
    check("home_objects_moving_cancels_fill_without_water",not s.home.residents.owner.activity and not cup.contents.water)
    sink();assert(Residents.command(s,p,"cupfill:"..cupTarget));advance(1)
    check("home_objects_fill_completes_once",cup.contents.water==1 and cup.contents.dirty==false and not s.home.residents.owner.activity)
    s.home.residents.owner.thirst=0
    assert(Residents.command(s,p,"cupdrink:"..cupTarget))
    check("home_objects_drinking_consumes_water_at_start",cup.contents.water==0 and cup.contents.dirty and not Residents.command(s,p,"cupdrink:"..cupTarget))
    advance(2)
    check("home_objects_cup_drink_restores_thirst",s.home.residents.owner.thirst>74 and s.home.residents.owner.thirst<76)
    check("home_objects_empty_dirty_cup_cannot_refill_or_drink",not Residents.command(s,p,"cupdrink:"..cupTarget) and not Residents.command(s,p,"cupfill:"..cupTarget))
    assert(Residents.command(s,p,"cupwash:"..cupTarget));advance(2)
    check("home_objects_wash_cleans_without_creating_water",cup.contents.dirty==false and cup.contents.water==0)
    assert(Residents.command(s,guest,"wash:sink"))
    check("home_objects_existing_sink_user_blocks_cup_fill",not Residents.command(s,p,"cupfill:"..cupTarget))
    sink(p,"basin");assert(Residents.command(s,p,"cupfill:"..cupTarget));advance(1)
    check("home_objects_other_sink_can_work_concurrently",cup.contents.water==1 and s.home.residents[guest.homeResidentId].activity~=nil)
    assert(Residents.command(s,guest,"cancel"))
    near(lamp);assert(command("on",lamp))
    assert(context.save.save(3,s,{x=p.x,y=p.y,sceneId="home"}))
    local shared=State.new();assert(State.applySharedSnapshot(shared,Schema.snapshot(s)))
    check("home_objects_shared_state_keeps_held_cup_and_lamp",Objects.held(shared,p) and Furniture.find(shared,lamp.id).lit)
    local resumed=State.new();assert(State.applyLocalSave(resumed,assert(context.save.load(3))))
    Residents.recover(resumed)
    check("home_objects_reload_recovers_cup_safely",Furniture.find(resumed,cup.id).location=="storage" and Furniture.find(resumed,cup.id).contents.water==1 and Furniture.find(resumed,lamp.id).lit)
    p.x,p.y=0,0
    check("home_objects_setdown_requires_surface_distance",not command("setdown",cup) and cup.location=="carried")
    p.x,p.y=Layout.toWorld(unpack(Layout.get(s).laptop.approach))
    assert(command("setdown",cup));local oldRevision=cup.revision
    check("home_objects_setdown_preserves_full_cup",cup.location=="surface" and cup.parentId==0 and cup.contents.water==1 and not cup.holderId)
    assert(command("pickup",cup));check("home_objects_pickup_existing_water_no_duplicate",cup.revision==oldRevision+1 and cup.contents.water==1)
    advance(0,{guest})
    check("home_objects_disconnect_releases_cup_to_storage",cup.location=="storage" and not cup.holderId and cup.contents.water==1)
    for name,mutate in pairs({unknown_food=function(i) i.contents.bogus=1 end,negative=function(i) i.contents.basic_meal=-1 end,
        excess=function(i) i.contents.basic_meal=25 end,not_food=function(i) i.contents.cup=1 end}) do
        local item={kind="mini_fridge",contents={}};mutate(item);check("home_objects_invalid_container_"..name,not Objects.valid(item))
    end
    check("home_objects_invalid_cup_and_lamp_state",not Objects.valid({kind="cup",contents={water=2}}) and not Objects.valid({kind="cup",contents={dirty=1}})
        and not Objects.valid({kind="bed",contents={},lit=true}))
    check("home_objects_command_validation",Objects.decode("object:put:4:0:basic_meal") and not Objects.decode("object:put:04:0:basic_meal")
        and not Objects.decode("object:put:4:0:cup") and not Objects.decode("object:on:4:0:basic_meal") and not Objects.decode("object:toggle:4:0"))
    local invalid=Schema.copy(s.home);local duplicate=Schema.copy(cup);cup=nil
    local first=Furniture.find({home=invalid},9);first.location="carried";first.holderId="owner"
    duplicate.id=invalid.furniture.nextId;invalid.furniture.nextId=duplicate.id+1;duplicate.location="carried";duplicate.holderId="owner"
    invalid.furniture.items[#invalid.furniture.items+1]=duplicate
    check("home_objects_one_carried_cup_per_resident",not Home.valid(invalid))
    local legacy=State.new();legacy.home=Home.new({furnishingPreset="modest"});legacy.home.furniture.version=2
    local migrated=assert(Schema.migrate({version=31,slot=3,createdAt=1,updatedAt=2,state=Schema.snapshot(legacy),player={x=300,y=400}}))
    check("home_objects_v31_migration_keeps_placements_and_empty_contents",migrated.version==Schema.VERSION and migrated.state.home.furniture.version==3
        and #migrated.state.home.furniture.items==9 and migrated.state.home.furniture.items[8].parentId==5
        and next(migrated.state.home.furniture.items[4].contents)==nil)
end
return Test
