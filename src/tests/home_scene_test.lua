local PixelCanvas=require('src.tests.support.pixel_canvas')
local Layout=require("src.home_layouts")
local State=require("src.state")
local Rooms=require("src.shop_rooms")
local Navigation=require("src.navigation")
local Catalog=require("src.home_catalog")
local Test={}
local function reachable(assets,sx,sy)
    local step=8
    local queue={{x=sx,y=sy,gx=0,gy=0}};local visited={["0:0"]=queue[1]};local head=1
    local offsets={{1,0},{-1,0},{0,1},{0,-1}}
    while head<=#queue do
        local p=queue[head];head=head+1
        for _,d in ipairs(offsets) do
            local gx,gy=p.gx+d[1],p.gy+d[2];local key=gx..":"..gy
            local x,y=sx+gx*step,sy+gy*step
            if not visited[key] and x>0 and x<960 and y>0 and y<678
                and Navigation.isWalkable(assets,x,y,{}) and Navigation.canTraverse(assets,p.x,p.y,x,y,{}) then
                local nextPoint={x=x,y=y,gx=gx,gy=gy,previous=p};visited[key]=nextPoint;queue[#queue+1]=nextPoint
            end
        end
    end
    return queue
end
local function routeTo(nodes,x,y)
    local nearest,dist=nil,math.huge
    for _,p in ipairs(nodes) do
        local d=(p.x-x)^2+(p.y-y)^2
        if d<dist then nearest,dist=p,d end
    end
    if dist>10^2 then return nil,math.sqrt(dist) end
    local result={};while nearest do table.insert(result,1,nearest);nearest=nearest.previous end
    return result
end
local function exportCanvas(canvas,name)
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    if not folder then return end
    local data=canvas:newImageData();local bytes=data:encode("png")
    local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
    bytes:release();data:release()
end
function Test.run(context,check)
    local World=context.world
    local savedPlayer={};for k,v in pairs(World.player) do savedPlayer[k]=v end
    local loader=require("src.image_loader");local streaming=loader.enabled;loader.setEnabled(false)
    for _,id in ipairs(Catalog.ORDER) do
        local state=State.new();state.home=assert(require("src.home").new({apartmentId=id}))
        state.screen="world"
        local assets=Rooms.assets(context.assets,"home",state)
        for index=1,4 do
            local x,y=Layout.spawn(state,index)
            check("home_scene_"..id.."_spawn_"..index,Navigation.isWalkable(assets,x,y,{}),x..","..y)
        end
        local sx,sy=Layout.spawn(state,1)
        local nodes=reachable(assets,sx,sy)
        check("home_scene_"..id.."_floor_connected",#nodes>300,"nodes="..#nodes)
        local targets={}
        for name,p in pairs(Layout.DATA[id].rooms) do targets["room_"..name]=p end
        for name,fixture in pairs(Layout.DATA[id].fixtures) do targets["fixture_"..name]=fixture.approach end
        targets.laptop=Layout.DATA[id].laptop.approach
        for name,p in pairs(targets) do
            local x,y=Layout.toWorld(unpack(p));local route,dist=routeTo(nodes,x,y)
            check("home_scene_"..id.."_reachable_"..name,Navigation.isWalkable(assets,x,y,{}) and route~=nil,
                string.format("target=%.1f,%.1f nearest=%s",x,y,tostring(dist)))
        end
        for i,wall in ipairs(Layout.DATA[id].walls) do
            local x,y=Layout.toWorld((wall[1]+wall[3])/2,(wall[2]+wall[4])/2)
            check("home_scene_"..id.."_wall_collision_"..i,not Navigation.isWalkable(assets,x,y,{}))
        end
        World.load({id=1,x=sx,y=sy,sceneId="home"})
        local beforeX=World.player.x
        for _=1,12 do World.updateNetworkPlayer(1/60,-1,0,context.assets,state) end
        check("home_scene_"..id.."_uses_player_controller",World.player.x<beforeX and World.player.animationDistance>0
            and Navigation.isWalkable(assets,World.player.x,World.player.y,{}))
        local guest={id=2,x=sx,y=sy,sceneId="home",facing=1}
        require("src.player_controller").reset(guest,{x=sx,y=sy},context.config.player)
        for _=1,12 do World.updateRemotePlayer(guest,1/60,-1,0,context.assets,state) end
        check("home_scene_"..id.."_guest_matches_local",math.abs(guest.x-World.player.x)<.001 and math.abs(guest.y-World.player.y)<.001)
        local target=Layout.targets(World.player,state).computer
        local access=World.validateNetworkWorkshopAccess({id=2,x=target.x,y=target.y,sceneId="home"},state,"office_computer")
        check("home_scene_"..id.."_laptop_access",access and not World.validateNetworkWorkshopAccess(
            {id=2,x=target.x,y=target.y,sceneId="home"},state,"cutter"))
        local canvas=PixelCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        World.draw(context.assets,context.characterAssets,state,nil,nil,{guest})
        love.graphics.pop()
        exportCanvas(canvas,"apartment-"..id);canvas:release()
        check("home_scene_"..id.."_renders_layers",true)
        local originalX,originalY=World.player.x,World.player.y
        local wall=Layout.DATA[id].walls[1]
        local revealX,revealY=Layout.toWorld((wall[1]+wall[3])/2,(wall[2]+wall[4])/2-45)
        local sampleX,sampleY=math.floor(revealX),math.floor(revealY-12)
        local function probe(near)
            World.player.x,World.player.y=near and revealX or 930,near and revealY or 660
            local c=PixelCanvas(960,678)
            love.graphics.push("all");love.graphics.setCanvas(c);love.graphics.clear()
            require("src.home_renderer").draw(World,context.assets,context.characterAssets,state,{},function()
                love.graphics.setColor(1,0,0,1);love.graphics.rectangle("fill",sampleX-4,sampleY-4,9,9)
            end)
            love.graphics.pop()
            local pixels=c:newImageData();local r,g,b=pixels:getPixel(sampleX,sampleY)
            pixels:release();c:release();return r-g-b
        end
        local near,far=probe(true),probe(false)
        check("home_scene_"..id.."_local_wall_reveal",near>.65 and near-far>.25,
            string.format("near %.3f / far %.3f",near,far))
        World.player.x,World.player.y=revealX,revealY
        local revealCanvas=PixelCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas(revealCanvas);love.graphics.clear()
        World.draw(context.assets,context.characterAssets,state,nil,nil,{})
        love.graphics.pop();exportCanvas(revealCanvas,"apartment-"..id.."-reveal");revealCanvas:release()
        World.player.x,World.player.y=originalX,originalY
        assert(context.save.queue(3,state,World.snapshot()));assert(context.save.flush())
        local saved=assert(context.save.load(3))
        check("home_scene_"..id.."_async_save_keeps_location",saved.player.sceneId=="home"
            and math.abs(saved.player.x-World.player.x)<.000001 and math.abs(saved.player.y-World.player.y)<.000001,
            tostring(saved.player.sceneId).." / "..tostring(saved.player.x).." / "..tostring(World.player.x))
        World.load(saved.player)
        check("home_scene_"..id.."_load_restores_location",World.player.sceneId=="home" and World.player.x==saved.player.x)
    end
    assert(context.save.delete(3))
    World.load(savedPlayer)
    context.assets.releaseApartment();require("src.home_renderer").clearCache();loader.setEnabled(streaming)
end
return Test
