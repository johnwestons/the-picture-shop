local State=require("src.state")
local Home=require("src.home")
local Furniture=require("src.home_furniture")
local Surface=require("src.home_surfaces")
local Layout=require("src.home_layouts")
local Schema=require("src.save_schema")
local Residents=require("src.home_residents")
local Test={}
function Test.run(context,check)
    local s=State.new();s.home=Home.new({furnishingPreset="modest"});s.home.weekend.phase="home";s.home.weekend.closedAtHours=44
    local byKind={};for _,item in ipairs(s.home.furniture.items) do byKind[item.kind]=item end
    local desk,laptop,clock,cup=byKind.small_desk,byKind.laptop,byKind.clock,byKind.cup
    local p={id=1,sceneId="home",x=desk.x+65,y=desk.y};local guest={id=2,sceneId="home",x=p.x,y=p.y}
    Residents.bind(s,guest,string.rep("a",64),{p});local people={p,guest}
    check("home_surface_modest_contents_attached",#Surface.children(s,desk.id)==3 and laptop.slot==1 and clock.slot==2 and cup.slot==3 and Furniture.valid(s.home.furniture))
    local targets=Furniture.targets(s,p)
    check("home_surface_objects_and_serving_surfaces_offer_routines",targets["furniture"..clock.id] and targets["furniture"..desk.id] and targets["furniture"..cup.id])
    local pose=Surface.pose(s,laptop);local relativeX,relativeY=pose.x-desk.x,pose.y-desk.y
    local beforeDirection=pose.direction;local oldX,oldY,oldDirection=desk.x,desk.y,desk.direction
    -- Poses are derived for every real direction, with no drifting child coordinates.
    for _,direction in ipairs(require("src.home_furniture_catalog").DIRECTIONS) do
        desk.direction=direction;local a=Surface.pose(s,laptop);local b=Surface.pose(s,clock)
        check("home_surface_rotates_with_support_"..direction,a.direction==direction and a.x~=b.x and laptop.x==0 and clock.x==0)
    end
    desk.direction=oldDirection;desk.x=desk.x+8;desk.y=desk.y+6
    pose=Surface.pose(s,laptop)
    check("home_surface_follows_support_translation",math.abs(pose.x-desk.x-relativeX)<1e-8 and math.abs(pose.y-desk.y-relativeY)<1e-8 and pose.direction==beforeDirection)
    desk.x,desk.y=oldX,oldY
    assert(Furniture.command(s,p,"permission:move:1",people))
    assert(Furniture.command(s,p,"begin:"..laptop.id,people));local token=laptop.editToken
    check("home_surface_child_edit_blocks_parent",not Furniture.command(s,guest,"begin:"..desk.id,people))
    local okay=Furniture.command(s,p,"attach:"..laptop.id..":"..token..":"..desk.id..":2:east",people)
    check("home_surface_rejects_occupied_slot_atomically",not okay and laptop.parentId==desk.id and laptop.slot==1 and laptop.editToken==token)
    assert(Furniture.command(s,p,"cancel:"..laptop.id..":"..token,people))
    assert(Furniture.command(s,p,"begin:"..desk.id,people));token=desk.editToken
    check("home_surface_parent_edit_blocks_child_and_laptop_access",not Furniture.command(s,guest,"begin:"..laptop.id,people) and not Surface.computer(s,p))
    assert(Furniture.command(s,p,"store:"..desk.id..":"..token,people))
    check("home_surface_store_keeps_contents_once",desk.location=="storage" and laptop.location=="storage" and clock.location=="storage" and cup.location=="storage"
        and #s.home.furniture.items==9 and not laptop.parentId and Furniture.valid(s.home.furniture))
    check("home_surface_stored_laptop_has_no_ghost_access",not Surface.computer(s,p) and not context.world.validateNetworkWorkshopAccess(p,s,"office_computer"))
    p.x,p.y=Layout.toWorld(unpack(Layout.get(s).laptop.approach))
    assert(Furniture.command(s,p,"begin:"..laptop.id,people));token=laptop.editToken
    local attach="attach:"..laptop.id..":"..token..":0:1:east"
    assert(Furniture.command(s,p,attach,people))
    check("home_surface_counter_attach_replay_safe",laptop.parentId==0 and laptop.slot==1 and not Furniture.command(s,p,attach,people)
        and Surface.computer(s,p).furnitureId==laptop.id and context.world.validateNetworkWorkshopAccess(p,s,"office_computer"))
    local guestMoney=s.home.balanceCents
    check("home_surface_guest_sale_permission_is_separate",not Furniture.command(s,guest,"sell:"..laptop.id..":"..token,people) and s.home.balanceCents==guestMoney)
    local saved=Schema.snapshot(s);local restored=State.new();assert(State.applySharedSnapshot(restored,saved))
    check("home_surface_shared_snapshot_preserves_attachments",Surface.find(restored,laptop.id).parentId==0 and #restored.home.furniture.items==9)
    assert(context.save.save(3,s,{x=p.x,y=p.y,sceneId="home"}))
    local loaded=State.new();assert(State.applyLocalSave(loaded,assert(context.save.load(3))))
    check("home_surface_disk_reload_preserves_parent_slot",Surface.find(loaded,laptop.id).slot==1 and Surface.find(loaded,laptop.id).parentId==0 and Surface.computer(loaded,p))
    for name,mutate in pairs({orphan=function(d) d.items[8].parentId=999 end,
        cycle=function(d) d.items[8].parentId=8 end,unsupported=function(d) d.items[8].parentId=1 end,
        slot=function(d) d.items[8].slot=4 end,nonzero_position=function(d) d.items[8].x=8 end,
        duplicate_slot=function(d) local c=d.items[9];c.location="surface";c.parentId=0;c.slot=1;c.x=0;c.y=0 end}) do
        local data=Schema.copy(s.home.furniture);mutate(data)
        check("home_surface_invalid_"..name,not Furniture.valid(data))
    end
    check("home_surface_protocol_bounded",Furniture.decode("attach:8:1:0:1:east") and not Furniture.decode("attach:08:1:0:1:east")
        and not Furniture.decode("attach:8:1:0:4:east") and not Furniture.decode("attach:8:1:0:1:other"))
    local sale=State.new();sale.home=Home.new({furnishingPreset="modest"});sale.home.weekend.phase="home";sale.home.weekend.closedAtHours=44
    local saleDesk=sale.home.furniture.items[5];local seller={id=1,sceneId="home",x=saleDesk.x+60,y=saleDesk.y}
    local funds=sale.home.balanceCents;assert(Furniture.command(sale,seller,"begin:"..saleDesk.id,{seller}))
    local saleCommand="sell:"..saleDesk.id..":"..saleDesk.editToken
    assert(Furniture.command(sale,seller,saleCommand,{seller}))
    local contentsKept=true;for _,child in ipairs(sale.home.furniture.items) do if child.kind=="clock" or child.kind=="laptop" or child.kind=="cup" then contentsKept=contentsKept and child.location=="storage" and not child.parentId end end
    check("home_surface_selling_parent_keeps_owned_contents",contentsKept and #sale.home.furniture.items==8 and sale.home.balanceCents==funds+2400
        and not Furniture.command(sale,seller,saleCommand,{seller}) and Furniture.valid(sale.home.furniture))
    -- A version-30 save owns bed/chair instances and inventory counts for the rest.
    local legacy=State.new();legacy.home=Home.new({furnishingPreset="modest"})
    local data=legacy.home.furniture
    for i=#data.items,3,-1 do local item=data.items[i];legacy.home.inventory[item.kind]=(legacy.home.inventory[item.kind] or 0)+1;table.remove(data.items,i) end
    data.version=1;data.nextId=3
    local payload={version=30,slot=3,createdAt=1,updatedAt=2,state=Schema.snapshot(legacy),player={x=300,y=400}}
    local migrated=assert(Schema.migrate(payload));local again=assert(Schema.migrate(migrated))
    check("home_surface_v30_migration_keeps_existing_poses_and_counts",migrated.version==39 and migrated.state.home.furniture.version==3
        and #migrated.state.home.furniture.items==9 and #again.state.home.furniture.items==9 and migrated.state.home.inventory.laptop==0
        and migrated.state.home.furniture.items[1].x==data.items[1].x and migrated.state.home.furniture.items[8].parentId==0)
    local couch=byKind.couch;local approach=Furniture.targets(s,p)["furniture"..couch.id];p.x,p.y=approach.x,approach.y
    s.home.residents.owner.energy=0;assert(Residents.command(s,p,"couchrest:furniture"..couch.id))
    guest.x,guest.y=p.x,p.y
    check("home_surface_couch_sleep_exclusive",not Residents.command(s,guest,"couchrest:furniture"..couch.id))
    Residents.advance(s,people,0,1)
    check("home_surface_couch_rest_recovers_less_than_bed",s.home.residents.owner.energy>38 and s.home.residents.owner.energy<43)
end
return Test
