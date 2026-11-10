local State=require("src.state")
local Home=require("src.home")
local Layout=require("src.home_layouts")
local Furniture=require("src.home_furniture")
local Catalog=require("src.home_furniture_catalog")
local Footprint=require("src.floor_footprint")
local Schema=require("src.save_schema")
local Test={}
local function state(id)
    local s=State.new();s.home=Home.new({apartmentId=id,furnishingPreset="modest"});s.home.weekend.phase="home";s.home.weekend.closedAtHours=44
    local x,y=Layout.spawn(s,1);return s,{id=1,sceneId="home",x=x,y=y}
end
function Test.run(context,check)
    local oldPlayer=context.world.snapshot();local oldState=context.world._state
    require("src.tests.home_surfaces_test").run(context,check)
    require("src.tests.home_objects_test").run(context,check)
    require("src.tests.home_chores_test").run(context,check)
    require("src.tests.home_kitchen_test").run(context,check)
    require("src.tests.home_sleep_test").run(context,check)
    require("src.tests.home_tables_lamp_test").run(context,check)
    require("src.tests.home_desk_mat_test").run(context,check)
    require("src.tests.home_utilities_test").run(context,check)
    require("src.tests.home_dining_test").run(context,check)
    require("src.tests.home_activity_pose_test").run(context,check)
    require("src.tests.home_routine_pose_test").run(context,check)
    for _,id in ipairs(require("src.home_catalog").ORDER) do
        local s,p=state(id)
        check("home_furniture_"..id.."_starter_instances",#s.home.furniture.items==9 and s.home.inventory.bed==0 and s.home.inventory.chair==0 and Schema.validState(Schema.snapshot(s)))
        for _,item in ipairs(s.home.furniture.items) do
            local okay,why=true
            if item.location=="floor" then okay,why=Furniture.canPlace(s,item,{p}) end
            check("home_furniture_"..id.."_"..item.kind.."_routes",okay,why)
        end
        context.world.load(p);context.world._state=s
        local canvas=love.graphics.newCanvas(960,678);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        context.world.draw(context.assets,context.characterAssets,s,nil,nil,{})
        love.graphics.pop()
        local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
        if folder then
            local data=canvas:newImageData();local bytes=data:encode("png")
            local file=assert(io.open(folder.."/furniture-"..id..".png","wb"));file:write(bytes:getString());file:close()
            bytes:release();data:release()
        end
        canvas:release()
    end
    local s,p=state("brick-walkup");local bed=s.home.furniture.items[1]
    local blocking={id=bed.id,kind="bed",x=528,y=420,direction="southeast"}
    p.x,p.y=416,330
    check("home_furniture_route_guard_rejects_physically_clear_blockage",Furniture.canPlace(s,blocking,{p},true) and not Furniture.canPlace(s,blocking,{p}))
    assert(Furniture.command(s,p,"begin:"..bed.id,{p}));local originalX,originalY=bed.x,bed.y
    check("home_furniture_route_rejection_is_atomic",not Furniture.command(s,p,"place:"..bed.id..":"..bed.editToken..":c66r70:southeast",{p})
        and bed.x==originalX and bed.y==originalY)
    assert(Furniture.command(s,p,"cancel:"..bed.id..":"..bed.editToken,{p}))
    local Residents=require("src.home_residents");local napper={id=2,sceneId="home"}
    local approach=Furniture.approaches(bed)[1];p.x,p.y=approach.x,approach.y;napper.x,napper.y=p.x,p.y
    assert(Residents.bind(s,napper,string.rep("d",64),{p}));s.home.residents.owner.energy=0
    assert(Residents.command(s,p,"nap:furniture"..bed.id))
    check("home_furniture_occupied_bed_rejects_second_user",not Residents.command(s,napper,"nap:furniture"..bed.id))
    check("home_furniture_occupied_bed_cannot_move",not Furniture.command(s,p,"begin:"..bed.id,{p,napper}))
    Residents.advance(s,{p,napper},0,1)
    check("home_furniture_bed_recovers_more_than_floor",s.home.residents.owner.energy>62 and not s.home.residents.owner.activity)
    p.x,p.y=bed.x+80,bed.y
    assert(Furniture.command(s,p,"begin:"..bed.id,{p}));local token=bed.editToken
    check("home_furniture_editing_blocks_use",not Residents.command(s,p,"nap:furniture"..bed.id))
    local interrupted=Schema.copy(s);Residents.recover(interrupted)
    check("home_furniture_reload_recovery_keeps_object_releases_edit",not interrupted.home.furniture.items[1].editor
        and interrupted.home.furniture.items[1].x==bed.x and not interrupted.home.furniture.items[1].editExpiresAt)
    local before={x=bed.x,y=bed.y,direction=bed.direction}
    check("home_furniture_bad_commit_keeps_original",not Furniture.command(s,p,"place:"..bed.id..":"..token..":c0r0:east",{p}) and bed.x==before.x and bed.y==before.y)
    assert(Furniture.command(s,p,"cancel:"..bed.id..":"..token,{p}))
    check("home_furniture_cancel_releases_lock",not bed.editor and bed.x==before.x and bed.y==before.y)
    local guest={id=2,sceneId="home",x=p.x,y=p.y};assert(require("src.home_residents").bind(s,guest,string.rep("c",64),{p}))
    check("home_furniture_guest_default_denied",not Furniture.command(s,guest,"begin:"..bed.id,{p,guest}))
    assert(Furniture.command(s,p,"permission:move:1",{p,guest}))
    assert(Furniture.command(s,guest,"begin:"..bed.id,{p,guest}))
    check("home_furniture_one_editor_per_object",not Furniture.command(s,p,"begin:"..bed.id,{p,guest}))
    Furniture.recover(s,{p});check("home_furniture_disconnect_releases_lock",not bed.editor)
    assert(Furniture.command(s,p,"begin:"..bed.id,{p}));bed.editExpiresAt=0
    Furniture.recover(s,{p});check("home_furniture_abandoned_edit_expires",not bed.editor)
    assert(Furniture.command(s,p,"begin:"..bed.id,{p}));token=bed.editToken
    assert(Furniture.command(s,p,"store:"..bed.id..":"..token,{p}))
    check("home_furniture_store_keeps_identity_and_condition",bed.location=="storage" and bed.id==1 and bed.condition==100)
    assert(context.save.save(3,s,{x=p.x,y=p.y,sceneId="home"}))
    local reloaded=State.new();assert(State.applyLocalSave(reloaded,assert(context.save.load(3))))
    check("home_furniture_reload_does_not_mint_items",#reloaded.home.furniture.items==9 and reloaded.home.inventory.bed==0 and reloaded.home.furniture.items[1].location=="storage")
    assert(Furniture.command(s,p,"begin:"..bed.id,{p}));token=bed.editToken
    local money=s.home.balanceCents
    assert(Furniture.command(s,p,"sell:"..bed.id..":"..token,{p}))
    check("home_furniture_sale_credits_once",s.home.balanceCents==money+6000 and not Furniture.command(s,p,"sell:"..bed.id..":"..token,{p}) and #s.home.furniture.items==8)
    for _,direction in ipairs(Catalog.DIRECTIONS) do
        local shape=Furniture.footprint({kind="bed",x=300,y=300,direction=direction})
        local vertices=Footprint.vertices(shape);local grown=Footprint.expand(shape,{x=6,y=3})
        local valid=#vertices==8 and Footprint.penetration(shape,300,300)>0 and Footprint.segmentPenetrates(shape,100,300,500,300)
        for i=1,#vertices,2 do valid=valid and Footprint.penetration(grown,vertices[i],vertices[i+1])>0 end
        check("home_furniture_rotated_footprint_"..direction,valid)
    end
    local a=Furniture.footprint({kind="bed",x=300,y=300,direction="southeast"})
    local b=Furniture.footprint({kind="bed",x=390,y=345,direction="southeast"})
    check("home_furniture_rotated_empty_corners_remain_clear",not Footprint.overlaps(a,b) and Footprint.distanceSquared(a,b)>1)
    for _,kind in ipairs(Catalog.ORDER) do
        local canvas=love.graphics.newCanvas(960,600)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.12,.15,.17,1)
        for i,direction in ipairs(Catalog.DIRECTIONS) do
            local x,y=120+((i-1)%4)*240,210+math.floor((i-1)/4)*280
            love.graphics.push();love.graphics.translate(x,y);love.graphics.scale(1.6)
            require("src.home_furniture_art").draw({kind=kind,direction=direction,x=0,y=0,powered=kind=="old_tv"});love.graphics.pop()
            love.graphics.setColor(.9,.95,.9,1);love.graphics.printf(direction,x-115,y+60,230,"center")
        end
        love.graphics.pop()
        local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
        if folder then
            local data=canvas:newImageData();local bytes=data:encode("png")
            local file=assert(io.open(folder.."/furniture-"..kind.."-directions.png","wb"));file:write(bytes:getString());file:close()
            bytes:release();data:release()
        end
        canvas:release();check("home_furniture_all_views_render_"..kind,true)
    end
    local legacy={version=29,slot=3,createdAt=1,updatedAt=2,state=Schema.snapshot(State.new()),player={x=300,y=400}}
    legacy.state.home.furniture=nil;legacy.state.home.furnishingPreset="modest";legacy.state.home.inventory=Schema.copy(require("src.home_catalog").PRESETS.modest.contents)
    local migrated=assert(Schema.migrate(legacy))
    check("home_furniture_legacy_contents_materialize_once",migrated.version==Schema.VERSION and #migrated.state.home.furniture.items==9 and migrated.state.home.inventory.bed==0)
    local Shopping=require("src.home_shopping");local shop,purchaser=state("brick-walkup")
    local buyer={id=2,sceneId="home",x=purchaser.x,y=purchaser.y};Residents.bind(shop,buyer,string.rep("f",64),{purchaser})
    local intent={kind="home_order_furniture",productId="chair",quantity=1,requestId="furniture-guest",expectedRevision=shop.home.revision}
    check("home_furniture_guest_buy_permission_separate",not Shopping.order(shop,buyer,intent))
    assert(Furniture.command(shop,purchaser,"permission:purchase:1",{purchaser,buyer}));intent.expectedRevision=shop.home.revision
    assert(Shopping.order(shop,buyer,intent));local moneyAfter=shop.home.balanceCents
    check("home_furniture_purchase_does_not_use_food_budget",shop.home.shopping.guestSpentCents==0 and moneyAfter==27125)
    assert(Shopping.order(shop,buyer,intent));check("home_furniture_order_replay_single_charge",shop.home.balanceCents==moneyAfter)
    shop.calendar.elapsed=2/24*shop.calendar.secondsPerDay;assert(Shopping.advance(shop))
    assert(Shopping.collect(shop,buyer))
    local delivered=shop.home.furniture.items[10]
    check("home_furniture_delivery_creates_one_instance",#shop.home.furniture.items==10 and delivered.kind=="chair"
        and (delivered.location=="floor" or delivered.location=="storage")
        and shop.home.inventory.chair==0 and not Shopping.collect(shop,buyer))
    require("src.tests.support.home_furniture_runtime").run(context,check)
    require("src.tests.support.home_desk_mat_runtime").run(context,check)
    require("src.tests.support.home_utilities_runtime").run(context,check)
    assert(context.save.delete(3));context.world.load(oldPlayer);context.world._state=oldState
end
return Test
