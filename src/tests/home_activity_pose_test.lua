local PixelCanvas=require('src.tests.support.pixel_canvas')
local Pose=require("src.home_activity_pose")
local Residents=require("src.home_residents")
local Catalog=require("src.home_furniture_catalog")
local Furniture=require("src.home_furniture")
local Fixtures=require("src.tests.home_dining_test")
local Schema=require("src.save_schema")
local Test={}
local function capture(canvas,name)
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR");if not folder then return end
    local data=canvas:newImageData();local bytes=data:encode("png")
    local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
    bytes:release();data:release()
end
function Test.run(context,check)
    for _,example in ipairs({{"chair","sit"},{"chair","eat"},{"couch","watch"},{"couch","couchrest"},{"bed","nap"},{"guest_mat","matrest"}}) do
        local s,p=Fixtures.fresh();local kind,action=unpack(example)
        local canvas=PixelCanvas(960,678);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.13,.16,.18,1)
        for i,direction in ipairs(Catalog.DIRECTIONS) do
            local item={id=2,kind=kind,x=0,y=0,location="floor",direction=direction,condition=100}
            s.home.furniture.items={item};p.x,p.y,p.character=100,100,"rabbit-worker"
            s.home.residents.owner.activity={kind=action,furnitureId=2,target="furniture2",x=100,y=100}
            local pose=assert(Pose.get(s,p));local b=pose.bounds
            check("home_pose_"..kind..action..direction,b[1]<b[3] and b[2]<b[4] and pose.depth>item.y and p.x==100 and item.x==0
                and pose.direction==(kind=="couch" and action=="couchrest" and Catalog.rotate(direction,2) or direction))
            love.graphics.push();love.graphics.translate(120+((i-1)%4)*240,220+math.floor((i-1)/4)*300);love.graphics.scale(2)
            require("src.home_furniture_art").draw(item);Pose.draw(pose,p);Pose.drawForeground(pose)
            love.graphics.pop();love.graphics.setColor(1,1,1,1)
            love.graphics.printf(direction,((i-1)%4)*240,260+math.floor((i-1)/4)*300,240,"center")
        end
        love.graphics.pop();capture(canvas,"home-pose-"..kind.."-"..action);canvas:release()
    end
    local s,p=Fixtures.fresh();local chair=Fixtures.table(s,p,"chair")
    local target=assert(Furniture.targets(s,p)["furniture"..chair.id]);p.x,p.y=target.x,target.y
    local x,y=p.x,p.y;assert(Residents.command(s,p,"sit:furniture"..chair.id))
    local pose=assert(Pose.get(s,p))
    check("home_pose_sitting_uses_seat_not_approach",math.abs(pose.x-p.x)>2 or math.abs(pose.y-p.y)>2)
    check("home_pose_preserves_physical_position",p.x==x and p.y==y and s.home.residents.owner.activity.x==x and s.home.residents.owner.activity.y==y)
    local snapshot=Schema.snapshot(s);check("home_pose_no_new_saved_fields",Schema.validState(snapshot) and not snapshot.home.residents.owner.activity.pose)
    local replay=assert(Pose.get({home=snapshot.home},p))
    check("home_pose_snapshot_same_contact",replay.x==pose.x and replay.y==pose.y and replay.frame==pose.frame)
    require("src.shop_rooms").stand(p)
    check("home_pose_stand_keeps_home_approach",not p.resting and p.x==x and p.y==y)
    local shop={sceneId="break_room",resting=true,x=20,y=30,_restOrigin={x=10,y=15}}
    require("src.shop_rooms").stand(shop)
    check("home_pose_shop_get_up_keeps_existing_exit",shop.x==10 and shop.y==15 and not shop.resting)
    p.x=x+3;check("home_pose_moving_clears_visual_immediately",Pose.get(s,p)==nil)
    p.x=x;assert(Residents.command(s,p,"cancel"));check("home_pose_cancel_removes_visual",Pose.get(s,p)==nil)
    local g={id=2,sceneId="home",x=x,y=y,character="rabbit-worker"};assert(Residents.bind(s,g,string.rep("a",64),{p}))
    assert(Residents.command(s,g,"sit:furniture"..chair.id));local gp=assert(Pose.get(s,g))
    local display={id=2,sceneId="home",x=x,y=y,character="rabbit-worker"}
    local remote=assert(Pose.get({home=Schema.snapshot(s).home},display))
    check("home_pose_guest_without_private_key_uses_active_identity",remote.x==gp.x and remote.frame==gp.frame)
    local canvas=PixelCanvas(480,240);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.13,.16,.18,1)
    for i=1,6 do
        local copy=Schema.copy(gp);copy.x,copy.y=40+(i-1)*80,160;copy.item=nil
        Pose.draw(copy,{furColorway=i,overallsColorway=i})
    end
    love.graphics.pop();capture(canvas,"home-pose-colorways");canvas:release()
    g.sceneId="warehouse";check("home_pose_other_scene_uses_normal_avatar",Pose.get(s,g)==nil);g.sceneId="home"
    g.character="tan-cat";check("home_pose_other_character_preserves_own_art",Pose.get(s,g)==nil);g.character="rabbit-worker"
    Residents.recover(s);check("home_pose_recovery_clears_visual",Pose.get(s,g)==nil)
    assert(Residents.command(s,p,"sleepfloor:floor"));local floor=assert(Pose.get(s,p))
    check("home_pose_floor_sleep_needs_no_furniture",floor.kind=="sleeping" and not floor.item and floor.groundX==p.x)
    context.world.load(p);context.world._state=s
    context.world.updateNetworkPlayer(.1,1,0,context.assets,s)
    check("home_pose_walk_wakes_without_shop_teleport",math.abs(context.world.player.x-x)<30 and math.abs(context.world.player.y-y)<30 and not context.world.player.resting)
    Pose.release()
    canvas=PixelCanvas(240,120);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
    floor.x,floor.y=120,60;Pose.draw(floor,p);love.graphics.pop()
    local data=canvas:newImageData();local visible=false
    for i=30,210,5 do for j=10,110,5 do local _,_,_,a=data:getPixel(i,j);if a>.18 then visible=true end end end
    data:release();canvas:release();check("home_pose_renderer_reloads_after_release",visible)
end
return Test
