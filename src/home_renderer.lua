local Preload=require("src.home_art_preload")
local Layout=require("src.home_layouts")
local Avatar=require("src.multiplayer_avatar_renderer")
local Renderer={REVEAL_RADIUS=88}
local cleanShader,wallShader
local openingFrame=false
local fixtureMeshes,meshFloor,meshId={},nil,nil
local Surface=require("src.home_surfaces")
local FurnitureArt=require("src.home_furniture_art")
local Dining=require("src.home_dining")
local Pose=require("src.home_activity_pose")
local Routine=require("src.home_routine_pose")
local Consumption=require("src.home_consumption_art")
local cleanSource=[[
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
    vec4 p=Texel(texture,uv);
    if(p.a<0.02) discard;
    if(p.a>0.94) p.a=1.0;
    return p*color;
}]]
local wallSource=[[
extern vec4 walls[24];
extern int wallCount;
extern vec4 actors[64];
extern float actorFeet[64];
extern int actorCount;
extern vec4 reveal;
extern bool overlayPass;
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
    vec4 p=Texel(texture,uv);
    if(p.a<0.02) discard;
    if(p.a>0.94) p.a=1.0;
    vec2 pos=uv*vec2(1536.0,1024.0);
    float depth=0.0;
    for(int i=0;i<24;i++) {
        if(i>=wallCount) break;
        vec4 w=walls[i];
        float dx=w.z-w.x;
        float t=abs(dx)<1.0 ? 0.5 : clamp((pos.x-w.x)/dx,0.0,1.0);
        float ground=mix(w.y,w.w,t);
        if(pos.x>=min(w.x,w.z)-18.0 && pos.x<=max(w.x,w.z)+18.0
            && pos.y>=ground-215.0 && pos.y<=ground+18.0) depth=max(depth,ground);
    }
    if(depth==0.0) depth=pos.y+160.0;
    if(overlayPass) {
        for(int i=0;i<64;i++) {
            if(i>=actorCount) break;
            vec4 a=actors[i];
            if(actorFeet[i]>=depth && pos.x>=a.x && pos.x<=a.z && pos.y>=a.y && pos.y<=a.w) discard;
        }
    }
    if(depth>=reveal.z-10.0) {
        float d=distance(pos,reveal.xy);
        p.a*=mix(0.06,1.0,smoothstep(reveal.w*0.72,reveal.w,d));
    }
    return p*color;
}]]
local function shaders()
    if not cleanShader then cleanShader=love.graphics.newShader(cleanSource) end
    if not wallShader then wallShader=love.graphics.newShader(wallSource) end
end
local function bounds(p)
    local x1,y1,x2,y2=math.huge,math.huge,-math.huge,-math.huge
    for i=1,#p,2 do x1=math.min(x1,p[i]);y1=math.min(y1,p[i+1]);x2=math.max(x2,p[i]);y2=math.max(y2,p[i+1]) end
    return {x1,y1,x2,y2}
end
local function meshes(id,entry,image)
    if meshId==id and meshFloor==image then return end
    for _,mesh in pairs(fixtureMeshes) do mesh:release() end
    fixtureMeshes={};meshId,meshFloor=id,image
    for name,fixture in pairs(entry.fixtures) do
        local vertices={}
        for _,triangle in ipairs(love.math.triangulate(fixture.outline)) do
            for i=1,6,2 do
                local x,y=triangle[i],triangle[i+1]
                vertices[#vertices+1]={x,y,x/1536,y/1024,1,1,1,1}
            end
        end
        local mesh=love.graphics.newMesh(vertices,"triangles","static")
        mesh:setTexture(image);fixtureMeshes[name]=mesh
    end
end
function Renderer.clearCache()
    Preload.reset();openingFrame=false
    Pose.release()
    Routine.release()
    require("src.home_furniture_art").release()
    require("src.home_food_art").release()
    require("src.home_held_art").release()
    for _,mesh in pairs(fixtureMeshes) do mesh:release() end
    fixtureMeshes={};meshId,meshFloor=nil,nil
end
function Renderer.draw(world,assets,characters,state,remotePlayers,drawLocal)
    Preload.beginFrame()
    local art,reason=assets.getApartment(state.home.apartmentId)
    love.graphics.push("all")
    love.graphics.setColor(.025,.035,.045,1);love.graphics.rectangle("fill",0,0,960,678)
    local Food=require("src.home_food_art")
    local prepareFoodShader=require("src.image_loader").enabled and not Food.shaderReady()
    if not art or not art.floor or not art.wall or prepareFoodShader then
        love.graphics.setColor(1,1,1,1)
        love.graphics.printf(reason and "Apartment art could not load: "..reason or "Opening apartment...",80,300,800,"center")
        -- The preceding frame has already shown the ordinary opening panel.
        -- Compile this cached program here, before the first household action.
        if prepareFoodShader and openingFrame then Food.prewarmShader() end
        openingFrame=true
        Preload.wait();love.graphics.pop();return
    end
    openingFrame=false
    shaders()
    local entry=Layout.get(state)
    meshes(state.home.apartmentId,entry,art.floor)
    local walls={}
    for _,list in ipairs({entry.walls,entry.perimeter}) do for _,line in ipairs(list) do walls[#walls+1]=line end end
    wallShader:send("wallCount",#walls);wallShader:send("walls",unpack(walls))
    local localPose=Pose.get(state,world.player) or Routine.get(state,world.player)
    local px,py=Layout.toSource(localPose and localPose.groundX or world.player.x,localPose and localPose.groundY or world.player.y)
    wallShader:send("reveal",{px,py-48,py,Renderer.REVEAL_RADIUS/Layout.SCALE})
    local actors,rects,feet={},{},{}
    local function occluder(rect,depth) rects[#rects+1]=rect;feet[#feet+1]=depth end
    local function groupBounds(rect,children,parentId)
        for _,child in ipairs(children) do
            local b=FurnitureArt.bounds(Surface.pose(state,child))
            b[1],b[2]=Layout.toSource(b[1],b[2]);b[3],b[4]=Layout.toSource(b[3],b[4])
            rect[1],rect[2]=math.min(rect[1],b[1]),math.min(rect[2],b[2])
            rect[3],rect[4]=math.max(rect[3],b[3]),math.max(rect[4],b[4])
        end
        for _,meal in ipairs(Dining.children(state,parentId)) do
            local pose=Dining.pose(state,meal);local x,y=Layout.toSource(pose.x,pose.y-4);local radius=14/Layout.SCALE
            rect[1],rect[2]=math.min(rect[1],x-radius),math.min(rect[2],y-radius)
            rect[3],rect[4]=math.max(rect[3],x+radius),math.max(rect[4],y+radius)
        end
        return rect
    end
    local function drawChildren(children,parentId)
        for _,child in ipairs(children) do FurnitureArt.draw(Surface.pose(state,child)) end
        Dining.draw(state,parentId)
    end
    for name,fixture in pairs(entry.fixtures) do
        local mesh=fixtureMeshes[name]
        local children=name=="sink" and Surface.children(state,0) or {}
        occluder(groupBounds(bounds(fixture.outline),children,name=="sink" and 0 or -1),fixture.y)
        actors[#actors+1]={y=fixture.y,order=name,draw=function()
            love.graphics.setShader(cleanShader);love.graphics.setColor(1,1,1,1)
            love.graphics.draw(mesh,Layout.X,Layout.Y,0,Layout.SCALE,Layout.SCALE)
            require("src.home_chores_art").fixture(state,name)
            drawChildren(children,name=="sink" and 0 or -1)
        end}
    end
    local function player(actor,localPlayer)
        local pose=localPlayer and localPose or Pose.get(state,actor) or Routine.get(state,actor)
        local x,y=Layout.toSource(actor.x,actor.y)
        if pose then
            local b=pose.bounds;local x1,y1=Layout.toSource(b[1],b[2]);local x2,y2=Layout.toSource(b[3],b[4])
            x,y=Layout.toSource(pose.x,pose.depth);occluder({x1,y1,x2,y2},y)
        else occluder({x-50,y-180,x+50,y+10},y) end
        actors[#actors+1]={y=y,order="player"..tostring(actor.id or 1),draw=function()
            love.graphics.setShader()
            if pose then
                if pose.routine then
                    if not Routine.draw(pose,actor,characters) then
                        if localPlayer then drawLocal() else Avatar.draw(characters,{actor},state) end
                    end
                elseif Pose.draw(pose,actor) then Pose.drawForeground(pose)
                elseif localPlayer then drawLocal() else Avatar.draw(characters,{actor},state) end
                if not localPlayer then
                    Avatar.drawLabel({id=actor.id,name=actor.name,x=pose.x,y=pose.bounds[2]+79})
                end
            elseif localPlayer then drawLocal() else Avatar.draw(characters,{actor},state) end
            local resident=require("src.home_residents").display(state,actor)
            local activity=resident and resident.activity
            if pose and pose.routine then -- The routine draws its own held props.
            elseif activity and Consumption.draw(state,activity,actor,pose) then
            else
                -- Guest rendering can use the resident's replicated active player ID;
                -- command authority still uses only its authenticated resident ID.
                local heldPlayer={id=actor.id or 1,homeResidentId=actor.homeResidentId}
                if resident and heldPlayer.id~=1 and not heldPlayer.homeResidentId then
                    for id,row in pairs(state.home.residents) do if row==resident then heldPlayer.homeResidentId=id;break end end
                end
                local held=require("src.home_objects").held(state,heldPlayer)
                if held then FurnitureArt.draw({kind="cup",direction="southeast",x=actor.x+12,y=actor.y-22,contents=held.contents}) end
            end
        end}
    end
    player(world.player,true)
    for _,item in ipairs(state.home.furniture and state.home.furniture.items or {}) do
        if item.location=="floor" then
            local rect=require("src.home_furniture_art").bounds(item)
            rect[1],rect[2]=Layout.toSource(rect[1],rect[2]);rect[3],rect[4]=Layout.toSource(rect[3],rect[4])
            local _,depth=Layout.toSource(item.x,item.y+require("src.home_furniture").footprint(item).halfHeight)
            local children=Surface.children(state,item.id)
            occluder(groupBounds(rect,children,item.id),depth)
            actors[#actors+1]={y=depth,order="furniture"..item.id,draw=function() FurnitureArt.draw(item);Routine.furniture(state,item);drawChildren(children,item.id) end}
        end
    end
    for _,actor in ipairs(remotePlayers or {}) do if actor.sceneId=="home" then player(actor,false) end end
    local delivery=require("src.home_shopping").target(world.player,state)
    if delivery then
        local x,y=Layout.toSource(delivery.x,delivery.y)
        occluder({x-30,y-65,x+30,y+10},y)
        actors[#actors+1]={y=y,order="delivery",draw=function() require("src.home_food_art").draw(1,delivery.x,delivery.y-13,34) end}
    end
    table.sort(actors,function(a,b) if a.y==b.y then return a.order<b.order end;return a.y<b.y end)
    wallShader:send("actorCount",#rects);wallShader:send("actors",unpack(rects));wallShader:send("actorFeet",unpack(feet))
    love.graphics.setColor(1,1,1,1);love.graphics.setShader(cleanShader)
    love.graphics.draw(art.floor,Layout.X,Layout.Y,0,Layout.SCALE,Layout.SCALE)
    require("src.home_chores_art").floor(state)
    love.graphics.setShader(wallShader);wallShader:send("overlayPass",false)
    love.graphics.draw(art.wall,Layout.X,Layout.Y,0,Layout.SCALE,Layout.SCALE)
    for _,actor in ipairs(actors) do actor.draw() end
    love.graphics.setColor(1,1,1,1);love.graphics.setShader(wallShader);wallShader:send("overlayPass",true)
    love.graphics.draw(art.wall,Layout.X,Layout.Y,0,Layout.SCALE,Layout.SCALE)
    love.graphics.pop()
    Preload.endFrame()
end
return Renderer
