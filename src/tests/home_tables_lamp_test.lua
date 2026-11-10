local State=require("src.state")
local Home=require("src.home")
local Layout=require("src.home_layouts")
local Furniture=require("src.home_furniture")
local Catalog=require("src.home_furniture_catalog")
local Surface=require("src.home_surfaces")
local Objects=require("src.home_objects")
local Residents=require("src.home_residents")
local Shopping=require("src.home_shopping")
local Schema=require("src.save_schema")
local Calendar=require("src.business_calendar")
local Test={}
local kinds={"bedside_table","coffee_table","desk_lamp"}
local function time(s,h) s.calendar=Calendar.dateFromHours(h);s.calendar.elapsed=h%24/24*Calendar.secondsPerDay(s) end
local function fresh(id,preset)
    local s=State.new();s.home=Home.new({apartmentId=id,furnishingPreset=preset});s.home.weekend.phase="home";s.home.weekend.closedAtHours=44;time(s,44)
    local x,y=Layout.spawn(s,1);return s,{id=1,sceneId="home",x=x,y=y}
end
function Test.findSpot(s,kind,people,id)
    for y=192,552,24 do for x=160,800,32 do
        local c={id=id or 100,kind=kind,location="floor",x=x,y=y,direction="east"};local fits=true
        for _,p in ipairs(people or {}) do
            if p.sceneId=="home" and (x-p.x)^2+(y-p.y)^2>160^2 then fits=false;break end
        end
        for _,d in ipairs(Catalog.DIRECTIONS) do c.direction=d;if not Furniture.canPlace(s,c,people,true) then fits=false;break end end
        if fits then
            for _,d in ipairs(Catalog.DIRECTIONS) do c.direction=d;if not Furniture.canPlace(s,c,people) then fits=false;break end end
            if fits then c.direction="southeast";return c end
        end
    end end
end
function Test.run(context,check)
    for _,id in ipairs(require("src.home_catalog").ORDER) do for _,preset in ipairs({"empty","modest"}) do
        local s,p=fresh(id,preset)
        check("home_tables_no_starter_extras_"..id..preset,#s.home.furniture.items==(preset=="empty" and 1 or 9))
        for _,kind in ipairs(kinds) do
            check("home_tables_all_rotations_have_clear_routes_"..id..preset..kind,Test.findSpot(s,kind,{p})~=nil)
        end
    end end
    local s,p=fresh();local money=s.home.balanceCents;local business=s.money
    for _,kind in ipairs(kinds) do
        local intent={productId=kind,quantity=1,requestId="tables-"..kind,expectedRevision=s.home.revision}
        assert(Shopping.order(s,p,intent));assert(Shopping.order(s,p,intent))
    end
    -- $85 of furniture plus the 15% delivery fee, despite duplicate requests.
    check("home_tables_three_orders_debit_household_once",#s.home.shopping.orders==3 and s.home.balanceCents==money-9775 and s.money==business)
    time(s,46);assert(Shopping.advance(s));local parcel=Shopping.target(p,s);p.x,p.y=parcel.x,parcel.y
    assert(Shopping.collect(s,p));check("home_tables_all_deliver_once",#s.home.furniture.items==4 and not Shopping.collect(s,p))
    local tableItem=s.home.furniture.items[2];local lamp=s.home.furniture.items[4]
    local spot=assert(Test.findSpot(s,"bedside_table",{p},tableItem.id));tableItem.location="floor";tableItem.x,tableItem.y=spot.x,spot.y
    lamp.location="storage";p.x,p.y=tableItem.x+60,tableItem.y
    assert(Furniture.command(s,p,"begin:"..lamp.id,{p}))
    local attach="attach:"..lamp.id..":"..lamp.editToken..":"..tableItem.id..":1:east"
    assert(Furniture.command(s,p,attach,{p}))
    check("home_tables_lamp_attach_replay_safe",lamp.parentId==tableItem.id and lamp.location=="surface" and not Furniture.command(s,p,attach,{p}))
    local target=assert(Furniture.targets(s,p)["furniture"..lamp.id]);p.x,p.y=target.x,target.y
    local guest={id=2,sceneId="home",x=p.x,y=p.y};assert(Residents.bind(s,guest,string.rep("b",64),{p}))
    local on="object:on:"..lamp.id..":"..lamp.revision
    assert(Objects.command(s,guest,on))
    check("home_tables_guest_can_switch_lamp_without_move_permission",lamp.lit and not s.home.furniture.permissions.move and not Objects.command(s,guest,on))
    for _,d in ipairs(Catalog.DIRECTIONS) do
        tableItem.direction=d;local pose=Surface.pose(s,lamp)
        check("home_tables_lit_surface_pose_follows_parent_"..d,pose.lit and pose.direction==d and pose.y<tableItem.y and lamp.x==0 and lamp.y==0)
    end
    tableItem.direction="southeast";local revision=lamp.revision
    guest.x,guest.y=0,0
    check("home_tables_distant_lamp_switch_rejected",not Objects.command(s,guest,"object:off:"..lamp.id..":"..revision) and lamp.lit and lamp.revision==revision)
    target=Furniture.targets(s,p)["furniture"..lamp.id];p.x,p.y=target.x,target.y
    assert(Furniture.command(s,p,"begin:"..tableItem.id,{p}))
    check("home_tables_parent_edit_blocks_light_switch",not Objects.command(s,p,"object:off:"..lamp.id..":"..revision) and lamp.lit)
    assert(Furniture.command(s,p,"cancel:"..tableItem.id..":"..tableItem.editToken,{p}))
    local snapshot=Schema.snapshot(s);check("home_tables_new_catalog_snapshot_valid",snapshot and Schema.validState(snapshot))
    local remote=State.new();assert(State.applySharedSnapshot(remote,snapshot))
    check("home_tables_shared_snapshot_preserves_lit_lamp_and_support",Surface.find(remote,lamp.id).lit and Surface.pose(remote,Surface.find(remote,lamp.id)).lit)
    assert(context.save.save(3,s,{x=p.x,y=p.y,sceneId="home"}))
    local loaded=assert(context.save.load(3));check("home_tables_disk_keeps_lit_state_and_parent",loaded.state.home.furniture.items[4].lit
        and loaded.state.home.furniture.items[4].parentId==tableItem.id)
    local before=s.home.balanceCents;assert(Furniture.command(s,p,"begin:"..tableItem.id,{p}))
    assert(Furniture.command(s,p,"sell:"..tableItem.id..":"..tableItem.editToken,{p}))
    check("home_tables_sell_support_keeps_lamp_and_single_credit",lamp.location=="storage" and not lamp.parentId and lamp.lit
        and s.home.balanceCents==before+1200 and #s.home.furniture.items==3)
    local invalid=Schema.copy(lamp);invalid.kind="coffee_table"
    check("home_tables_non_lamp_cannot_keep_light_state",not Objects.valid(invalid))
    local old=State.new();local migrated=assert(Schema.migrate({version=35,slot=3,createdAt=1,updatedAt=2,state=Schema.snapshot(old),player={x=300,y=400}}))
    check("home_tables_v35_migration_no_free_furniture",migrated.version==Schema.VERSION and #migrated.state.home.furniture.items==1 and migrated.state.home.balanceCents==30000)
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    if folder then for _,kind in ipairs(kinds) do
        local canvas=love.graphics.newCanvas(1024,600);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.17,.22,.24,1)
        for i,d in ipairs(Catalog.DIRECTIONS) do
            local x,y=(i-1)%4*256+128,math.floor((i-1)/4)*300+230
            local item={kind=kind,x=x,y=y,direction=d,lit=kind=="desk_lamp"}
            love.graphics.setColor(.35,.5,.5,1);love.graphics.line(x-25,y,x+25,y);love.graphics.line(x,y-12,x,y+12)
            love.graphics.push();love.graphics.translate(x,y);love.graphics.scale(2);item.x,item.y=0,0
            require("src.home_furniture_art").draw(item)
            if kind~="desk_lamp" then
                local parent={id=101,kind=kind,x=0,y=0,direction=d,location="floor"}
                local child={id=102,kind="desk_lamp",parentId=101,slot=1,direction="east",location="surface",lit=true,contents={}}
                require("src.home_furniture_art").draw(Surface.pose({home={furniture={items={parent,child}}}},child))
            end
            love.graphics.pop();love.graphics.setColor(1,1,1,1);love.graphics.printf(d,x-100,y+40,200,"center")
        end
        love.graphics.pop();local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/home-"..kind.."-directions.png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end end
end
return Test
