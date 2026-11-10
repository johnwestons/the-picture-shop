local State=require("src.state")
local Home=require("src.home")
local Calendar=require("src.business_calendar")
local Furniture=require("src.home_furniture")
local Surface=require("src.home_surfaces")
local Residents=require("src.home_residents")
local Sleep=require("src.home_sleep")
local Shopping=require("src.home_shopping")
local Schema=require("src.save_schema")
local Layout=require("src.home_layouts")
local Find=require("src.tests.home_tables_lamp_test").findSpot
local Test={}
local function time(s,h) s.calendar=Calendar.dateFromHours(h);s.calendar.elapsed=h%24/24*Calendar.secondsPerDay(s) end
local function fresh(id,preset)
    local s=State.new();s.home=Home.new({apartmentId=id,furnishingPreset=preset});s.home.weekend.phase="home";s.home.weekend.closedAtHours=44;time(s,44)
    local x,y=Layout.spawn(s,1);return s,{id=1,sceneId="home",x=x,y=y}
end
function Test.run(context,check)
    for _,id in ipairs(require("src.home_catalog").ORDER) do for _,preset in ipairs({"empty","modest"}) do
        local s,p=fresh(id,preset)
        for _,kind in ipairs({"desk","guest_mat"}) do check("home_desk_mat_all_rotations_"..id..preset..kind,Find(s,kind,{p})~=nil) end
        check("home_desk_mat_starters_unchanged_"..id..preset,#s.home.furniture.items==(preset=="empty" and 1 or 9))
    end end
    local s,p=fresh();local business=s.money
    for _,kind in ipairs({"desk","guest_mat"}) do
        local intent={productId=kind,quantity=1,requestId="desk-mat-"..kind,expectedRevision=s.home.revision}
        assert(Shopping.order(s,p,intent));assert(Shopping.order(s,p,intent))
    end
    check("home_desk_mat_household_checkout_once",s.home.balanceCents==14475 and s.money==business)
    time(s,46);assert(Shopping.advance(s));local parcel=assert(Shopping.target(p,s));p.x,p.y=parcel.x,parcel.y
    assert(Shopping.collect(s,p));check("home_desk_mat_two_delivered_once",#s.home.furniture.items==3 and not Shopping.collect(s,p))
    local desk,mat=s.home.furniture.items[2],s.home.furniture.items[3]
    local spot=assert(Find(s,"desk",{p},desk.id));desk.location="floor";desk.x,desk.y=spot.x,spot.y
    local laptop=s.home.furniture.items[1];local computer=assert(Layout.targets(p,s).computer);p.x,p.y=computer.x,computer.y
    assert(Furniture.command(s,p,"begin:"..laptop.id,{p}))
    p.x,p.y=desk.x+60,desk.y
    assert(Furniture.command(s,p,"attach:"..laptop.id..":"..laptop.editToken..":"..desk.id..":1:east",{p}))
    check("home_desk_laptop_remains_usable",Layout.targets(p,s).computer~=nil and Surface.pose(s,laptop).y<desk.y)
    s.home.inventory.desk_lamp=1;Furniture.materialize(s,false);local lamp=s.home.furniture.items[4]
    assert(Furniture.command(s,p,"begin:"..lamp.id,{p}))
    assert(Furniture.command(s,p,"attach:"..lamp.id..":"..lamp.editToken..":"..desk.id..":2:east",{p}))
    check("home_desk_laptop_and_lamp_separate_slots",laptop.slot~=lamp.slot and Surface.pose(s,laptop).x~=Surface.pose(s,lamp).x)
    spot=assert(Find(s,"guest_mat",{p},mat.id));mat.location="floor";mat.x,mat.y=spot.x,spot.y
    local target=assert(Furniture.targets(s,p)["furniture"..mat.id]);p.x,p.y=target.x,target.y
    local g={id=2,sceneId="home",x=p.x,y=p.y};assert(Residents.bind(s,g,string.rep("d",64),{p}))
    local gr=Residents.get(s,g);gr.energy=0
    assert(Residents.command(s,g,"matrest:furniture"..mat.id))
    check("home_mat_guest_rest_without_edit_permission",g.resting and not s.home.furniture.permissions.move)
    check("home_mat_single_occupant",not Residents.command(s,p,"sleepmat:furniture"..mat.id))
    check("home_mat_occupied_cannot_move",not Furniture.command(s,p,"begin:"..mat.id,{p,g}))
    Residents.advance(s,{p,g},46,47);time(s,47)
    check("home_mat_recovery_between_floor_and_couch",math.abs(gr.energy-29.3)<1e-6 and not gr.activity)
    assert(Residents.command(s,g,"alarm:0"));assert(Residents.command(s,g,"sleepmat:furniture"..mat.id))
    local revision=gr.revision
    check("home_mat_repeat_sleep_cannot_reset_timer",not Residents.command(s,g,"sleepmat:furniture"..mat.id) and gr.revision==revision)
    assert(Residents.command(s,p,"sleepfloor:floor"));check("home_mat_participates_in_shared_sleep",Sleep.status(s,{p,g}))
    local snapshot=Schema.snapshot(s);check("home_desk_mat_snapshot_valid",Schema.validState(snapshot))
    local shared=State.new();assert(State.applySharedSnapshot(shared,snapshot))
    check("home_mat_shared_vote_and_desk_attachments",Residents.get(shared,g).activity.kind=="sleepmat" and shared.home.furniture.items[1].parentId==desk.id)
    assert(context.save.save(3,s,{sceneId="home",x=p.x,y=p.y}));local saved=assert(context.save.load(3))
    check("home_desk_mat_disk_preserves_kinds",saved.state.home.furniture.items[2].kind=="desk" and saved.state.home.furniture.items[3].kind=="guest_mat")
    Residents.advance(s,{p,g},47,48);time(s,48)
    check("home_mat_own_alarm_stops_fast_time",not gr.activity and gr.lastAlarmAt==48 and s.home.residents.owner.activity and not Sleep.status(s,{p,g}))
    assert(Residents.command(s,p,"cancel"));time(s,92)
    assert(Residents.command(s,g,"workmat:furniture"..mat.id));Residents.advance(s,{p,g},92,103);time(s,103)
    check("home_mat_sunday_sleep_ends_monday_seven",not gr.activity and not Residents.command(s,g,"sleepmat:furniture"..mat.id))
    assert(Residents.command(s,g,"matrest:furniture"..mat.id));check("home_mat_monday_short_nap_available",gr.activity.kind=="matrest")
    local migrated=assert(Schema.migrate({version=36,slot=3,createdAt=1,updatedAt=2,state=Schema.snapshot(State.new()),player={x=300,y=400}}))
    check("home_desk_mat_v36_no_free_items",migrated.version==Schema.VERSION and #migrated.state.home.furniture.items==1 and migrated.state.home.balanceCents==30000)
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    if folder then
        local canvas=love.graphics.newCanvas(1024,600);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.17,.22,.24,1)
        for i,d in ipairs(require("src.home_furniture_catalog").DIRECTIONS) do
            local x,y=(i-1)%4*256+128,math.floor((i-1)/4)*300+230
            local parent={id=1,kind="desk",x=0,y=0,direction=d,location="floor"}
            local computer={id=2,kind="laptop",parentId=1,slot=1,direction="east",location="surface"}
            local light={id=3,kind="desk_lamp",parentId=1,slot=2,direction="east",location="surface",lit=true}
            local display={home={furniture={items={parent,computer,light}}}};local Art=require("src.home_furniture_art")
            love.graphics.push();love.graphics.translate(x,y);love.graphics.scale(2)
            Art.draw(parent);Art.draw(Surface.pose(display,computer));Art.draw(Surface.pose(display,light));love.graphics.pop()
            love.graphics.setColor(1,1,1,1);love.graphics.printf(d,x-100,y+40,200,"center")
        end
        love.graphics.pop();local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/home-desk-surfaces.png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
end
return Test
