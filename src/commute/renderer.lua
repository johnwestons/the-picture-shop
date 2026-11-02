-- Slim environment renderer adapted from Critter Party ground chunks and plant
-- billboards. It intentionally has no fauna, apartment or shop dependencies.
local M=require('src.commute.vendor.mathx')
local Surface=require('src.commute.vendor.terrain')
local Ground=require('src.commute.ground_textures')
local Vegetation=require('src.commute.vegetation')
local Flora=require('src.commute.flora')
local PlantSprites=require('src.commute.vendor.plant_sprites')
local PlantMotion=require('src.commute.vendor.plant_motion')
local BikeArt=require('src.commute.bike_art')
local WarehouseArt=require('src.commute.warehouse_art')
local BridgeArt=require('src.commute.bridge_art')
local Sites=require('src.commute.sites')
local Renderer={};Renderer.__index=Renderer
function Renderer.new(world)
    local self=setmetatable({world=world,ground=Ground.new(),chunks={},radius=64,clock=0,serial=0,
        calendar={month=5,totalDays=0}},Renderer)
    self.ground:prepare()
    self.vegetation=Vegetation.new(world)
    self.plantSprites=PlantSprites.new();self.plantMotion=PlantMotion.new(world)
    self.bikeArt=BikeArt.new()
    self.warehouseArt=WarehouseArt.new()
    self.bridgeArt=BridgeArt.new(world)
    self:buildRoadMeshes()
    return self
end
function Renderer:buildRoadMeshes()
    local layers={shoulder={},asphalt={}}
    local function quad(s,width,height,layer,color,coverage)
        local a,b=s.a,s.b;local w=width*.5
        local points={{a.x+a.nx*w,a.z+a.nz*w,a.h},{b.x+b.nx*w,b.z+b.nz*w,b.h},
            {b.x-b.nx*w,b.z-b.nz*w,b.h},{a.x-a.nx*w,a.z-a.nz*w,a.h}}
        for _,index in ipairs({1,2,3,1,3,4}) do
            local p=points[index];local x,z=p[1],p[2]
            layer[#layer+1]={x,z,p[3]+height,0,1,0,x/4,z/4,x/4,z/4,0,0,
                color[1],color[2],color[3],1,0,1,0,coverage,0,1,0,0}
        end
    end
    for _,s in ipairs(self.world.roads.segments) do
        if not s.bridge then
            quad(s,s.width+1,.02,layers.shoulder,{.41,.39,.30},1)
            quad(s,s.width,.035,layers.asphalt,{.23,.25,.24},1)
        end
    end
    for _,p in pairs(self.world.roads.destinations) do
        local segment={a={x=p.x,z=p.z-4,h=p.h,nx=1,nz=0},b={x=p.x,z=p.z+4,h=p.h,nx=1,nz=0}}
        quad(segment,8.4,.02,layers.shoulder,{.41,.39,.30},1)
        quad(segment,8,.04,layers.asphalt,{.23,.25,.24},1)
    end
    self.roadMeshes={}
    for _,name in ipairs({'shoulder','asphalt'}) do self.roadMeshes[#self.roadMeshes+1]=love.graphics.newMesh(Ground.FORMAT,layers[name],'triangles','static') end
end
function Renderer:build(cx,cz)
    local world=self.world;local vertices,indices={},{};local x0,z0=cx*6,cz*6
    for ix=0,12 do for iz=0,12 do
        local x,z=x0+ix*.5,z0+iz*.5
        local r,g,b,kind,gw,dw,lw,coverage,gv,sv,lv=Surface.surface(world,x,z)
        local h=world:height(x,z)
        local roadDistance,segment,support=world.roads:sample(x,z)
        -- Riverbanks can protrude through a deck in a depth-tested view.
        -- Keep the terrain mesh below the authoritative bridge surface.
        if segment and segment.bridge and roadDistance<=segment.width*.5 then h=math.min(h,support-.08) end
        local nx,nz=world:height(x-.5,z)-world:height(x+.5,z),world:height(x,z-.5)-world:height(x,z+.5)
        local len=math.sqrt(nx*nx+nz*nz+1)
        local u,v=(x-x0)/4,(z-z0)/4
        vertices[#vertices+1]={x,z,math.max(0,h),nx/len,1/len,nz/len,u,v,u,v,(x0/4)%2,(z0/4)%2,r,g,b,1,gw,dw,lw,coverage,gv,sv,lv,-h}
    end end
    for ix=0,11 do for iz=0,11 do
        local a=ix*13+iz+1;local b=a+13;local c=a+1;local d=b+1
        for _,i in ipairs({a,b,c,d,c,b}) do indices[#indices+1]=i end
    end end
    local mesh=love.graphics.newMesh(Ground.FORMAT,vertices,'triangles','static');mesh:setVertexMap(indices)
    local chunk={mesh=mesh,cx=cx,cz=cz,last=self.serial};self.chunks[cx..':'..cz]=chunk;return chunk
end
function Renderer:prepare(camera,dt)
    self.clock=self.clock+dt;self.serial=self.serial+1
    local radius=math.max(self.radius,camera.firstPerson and 96 or 35/camera.zoom);radius=math.min(radius,96)
    self.effectiveRadius=radius
    local needed={}
    for cx=math.floor((camera.centerX-radius)/6),math.floor((camera.centerX+radius)/6) do
        for cz=math.floor((camera.centerZ-radius)/6),math.floor((camera.centerZ+radius)/6) do
            local x,z=cx*6+3,cz*6+3
            local distance=M.length(x-camera.centerX,z-camera.centerZ)
            if distance<radius+5 and x>=0 and z>=0 and x<self.world.size and z<self.world.size then
                needed[#needed+1]={cx=cx,cz=cz,distance=distance}
            end
        end
    end
    table.sort(needed,function(a,b)return a.distance<b.distance end)
    local built=0;local start=love.timer.getTime();self.visible={};self.pending=0
    for _,n in ipairs(needed) do
        local key=n.cx..':'..n.cz;local chunk=self.chunks[key]
        if not chunk and built<10 and (built==0 or love.timer.getTime()-start<.006) then chunk=self:build(n.cx,n.cz);built=built+1 end
        if chunk then chunk.last=self.serial;self.visible[#self.visible+1]=chunk else self.pending=self.pending+1 end
    end
    self.buildMs=(love.timer.getTime()-start)*1000
    for key,chunk in pairs(self.chunks) do
        if self.serial-chunk.last>120 then chunk.mesh:release();self.chunks[key]=nil end
    end
    table.sort(self.visible,function(a,b)return camera:depth(a.cx*6+3,a.cz*6+3)<camera:depth(b.cx*6+3,b.cz*6+3) end)
    self.plantMotion:update(dt)
    self.visibleProps=self:props(camera)
    self.plantSprites:prepare(self.visibleProps,self.calendar,self.clock)
end
function Renderer:shader(camera)
    local s=self.ground.shader;local t=self.clock
    camera:send(s)
    s:send('viewRadius',self.effectiveRadius or self.radius);s:send('detailStrength',.82)
    s:send('cloudPhase',{t*.03,t*.023,t*.017});s:send('cloudStrength',.15)
    s:send('sunDirection',{-.4,.8,-.3});s:send('sunColor',{1,.86,.66});s:send('sunlight',.45);s:send('ambientLight',.65)
    s:send('waterDetail',.85);s:send('wavePhase',{t*1.1,t*.7,t*.3});s:send('ripplePhase',{t,t*.8})
    s:send('waterView',{0,.8,.6});s:send('waterRoughness',.5)
    local _,tint,litter=Flora.season(self.calendar)
    s:send('seasonTint',tint);s:send('litterSeasonShift',litter)
    return s
end
local function strip(camera,s,width,hOffset)
    local w=width*.5;local a,b=s.a,s.b
    local ax,ay=camera:screen(a.x+a.nx*w,a.z+a.nz*w,a.h+hOffset)
    local bx,by=camera:screen(b.x+b.nx*w,b.z+b.nz*w,b.h+hOffset)
    local cx,cy=camera:screen(b.x-b.nx*w,b.z-b.nz*w,b.h+hOffset)
    local dx,dy=camera:screen(a.x-a.nx*w,a.z-a.nz*w,a.h+hOffset)
    love.graphics.polygon('fill',ax,ay,bx,by,cx,cy,dx,dy)
end
function Renderer:drawRoads(camera)
    local g=love.graphics
    g.setColor(1,1,1);g.setShader(self.ground.shader)
    for _,mesh in ipairs(self.roadMeshes) do g.draw(mesh) end
    g.setShader()
    for _,s in ipairs(self.world.roads.segments) do
        if M.length(s.a.x-camera.centerX,s.a.z-camera.centerZ)<self.effectiveRadius then
            if not s.bridge then
                if s.width>5.5 and math.floor(s.distance/4)%2==0 then
                    g.setColor(.72,.67,.42,.72);strip(camera,s,.09,.05)
                end
            end
        end
    end
    for id,p in pairs(self.world.roads.destinations) do
        if M.length(p.x-camera.centerX,p.z-camera.centerZ)<self.effectiveRadius then
            g.setColor(.76,.72,.56,.8);g.setLineWidth(math.max(1,2*camera.zoom))
            for offset=-2,2,2 do
                local ax,ay=camera:screen(p.x-3.7,p.z+offset,p.h+.07)
                local bx,by=camera:screen(p.x-1.6,p.z+offset,p.h+.07)
                g.line(ax,ay,bx,by)
            end
            local x,y=camera:screen(p.x,p.z,p.h+.1);g.setColor(.85,.8,.53);g.circle('line',x,y,12*camera.zoom)
            g.setColor(.94,.91,.76);g.print(p.label,x+14,y-18)
        end
    end
    self.bridgeArt:drawDeck(camera,self.effectiveRadius)
    g.setLineWidth(1)
end
function Renderer:props(camera)
    local inView
    if camera.firstPerson then
        local projection=require('src.commute.first_person_camera')
        inView=function(x,z,padding)return projection.inView(camera,x,z,padding) end
    end
    local props=self.vegetation:visible(camera.centerX,camera.centerZ,self.effectiveRadius,self.calendar,inView)
    for _,p in ipairs(props) do
        p.scale=p.scale*Flora.scale(p);p.depth=camera:depth(p.x,p.z,p.h)
    end
    return props
end
function Renderer:headlight(camera,bike)
    if not bike.headlight then return end
    local g=love.graphics
    local function point(forward,side)
        local x=bike.x+math.cos(bike.heading)*forward-math.sin(bike.heading)*side
        local z=bike.z+math.sin(bike.heading)*forward+math.cos(bike.heading)*side
        return camera:screen(x,z,self.world:supportHeight(x,z)+.08)
    end
    local length=9
    for d=1,9 do
        local x=bike.x+math.cos(bike.heading)*d;local z=bike.z+math.sin(bike.heading)*d
        if self.world.roads:blocked(self.world,x,z) then length=d;break end
    end
    for layer=4,1,-1 do
        local reach=length*(.5+layer*.125);local spread=.25+layer*.36
        local ax,ay=point(.65,0);local bx,by=point(reach,-spread);local cx,cy=point(reach,spread)
        g.setColor(1,.94,.62,.035);g.polygon('fill',ax,ay,bx,by,cx,cy)
    end
    g.setColor(1,1,1)
end
function Renderer:draw(camera,actor,actors)
    if camera.firstPerson then
        if not self.firstPersonView then self.firstPersonView=require('src.commute.first_person_renderer').new(self) end
        return self.firstPersonView:draw(self,camera,actor,actors)
    end
    local g=love.graphics;g.clear(.22,.27,.26)
    g.setColor(1,1,1);g.setShader(self:shader(camera))
    for _,chunk in ipairs(self.visible or {}) do g.draw(chunk.mesh) end
    g.setShader()
    -- Supports are scenery behind the elevated road plane. Let the asphalt
    -- cover the upper part of each sprite so no pier can draw across the lane.
    self.bridgeArt:drawPiers(camera,self.effectiveRadius)
    self:drawRoads(camera)
    if actors then
        for _,entry in ipairs(actors) do if not entry.gear then self:headlight(camera,entry.actor) end end
    else self:headlight(camera,actor) end
    local props={};for _,p in ipairs(self.visibleProps or {}) do props[#props+1]=p end
    local site=Sites.warehouse
    if M.length(site.x-camera.centerX,site.z-camera.centerZ)<self.effectiveRadius+12 then
        props[#props+1]={warehouse=true,depth=camera:depth(site.x,site.z,site.h)}
    end
    for _,piece in ipairs(self.bridgeArt:visibleSides(camera,self.effectiveRadius)) do props[#props+1]=piece end
    for _,cap in ipairs(self.bridgeArt:visibleCaps(camera,self.effectiveRadius)) do props[#props+1]=cap end
    for _,post in ipairs(self.bridgeArt:visibleEndPosts(camera,self.effectiveRadius)) do props[#props+1]=post end
    if actors then
        for _,entry in ipairs(actors) do
            local p=entry.actor;entry.depth=camera:depth(p.x,p.z,p.h or self.world:supportHeight(p.x,p.z))
            props[#props+1]=entry
        end
    else props[#props+1]={actor=actor,depth=camera:depth(actor.x,actor.z,actor.h or 0)} end
    table.sort(props,function(a,b)return a.depth<b.depth end)
    for _,p in ipairs(props) do
        if p.actor then
            if p.gear and not p.gear.mounted then
                local a=p.actor;local x,y=camera:screen(a.x,a.z,a.h or self.world:supportHeight(a.x,a.z))
                local pose=p.presentation and p.presentation.pose or require('src.commute.gear').pose(p.gear)
                if pose=='normal_idle' and self.characterAssets then
                    require('src.commute.normal_art').draw(self.characterAssets,a,camera,self.world,p.appearance,p.presentation,self.clock)
                else require('src.commute.presentation').foot(x,y,camera.zoom*.7,p.gear,a.distance,a.speed,p.presentation) end
            else self.bikeArt:draw(p.actor,camera,self.world,p.bikeOnly,p.presentation) end
        elseif p.warehouse then self.warehouseArt:draw(camera,actor,self.world)
        elseif p.bridgeSide then
            local fade=1-M.smooth((M.length(p.center.x-camera.centerX,p.center.z-camera.centerZ)
                -self.effectiveRadius*.8)/(self.effectiveRadius*.2))
            self.bridgeArt:drawSide(p,camera,fade)
        elseif p.bridgeCap then
            local fade=1-M.smooth((M.length(p.center.x-camera.centerX,p.center.z-camera.centerZ)
                -self.effectiveRadius*.8)/(self.effectiveRadius*.2))
            self.bridgeArt:drawCap(p,camera,fade)
        elseif p.bridgeEndPost then
            local fade=1-M.smooth((M.length(p.x-camera.centerX,p.z-camera.centerZ)
                -self.effectiveRadius*.8)/(self.effectiveRadius*.2))
            self.bridgeArt:drawEndPost(p,camera,fade)
        else
            local x,y=camera:screen(p.x,p.z,p.h)
            local fade=1-M.smooth((M.length(p.x-camera.centerX,p.z-camera.centerZ)-self.effectiveRadius*.8)/(self.effectiveRadius*.2))
            -- Preserve rider readability through nearby foreground canopy.
            if Flora.canopy[p.kind] then
                local ax,ay=camera:screen(actor.x,actor.z,actor.h or 0)
                local size=p.scale*camera.zoom
                if math.abs(x-ax)<110*size+12*camera.zoom and y>ay
                    and y-248*size<ay then fade=fade*.22 end
            end
            g.setColor(.91,.94,.87,fade);local s=p.scale*camera.zoom
            self.plantSprites:drawPlant(p,self.calendar,self.clock,x,y,s,self.plantMotion:sway(p))
        end
    end
    g.setColor(1,1,1);g.setLineWidth(1)
end
function Renderer:release()
    if self.firstPersonView then self.firstPersonView:release() end
    for _,chunk in pairs(self.chunks) do chunk.mesh:release() end
    self.plantSprites:release()
    self.bikeArt:release()
    self.warehouseArt:release()
    self.bridgeArt:release()
    for _,mesh in ipairs(self.roadMeshes) do mesh:release() end
    self.ground:release()
end
return Renderer
