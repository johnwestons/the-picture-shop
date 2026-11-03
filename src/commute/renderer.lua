-- Budgeted terrain, vegetation and solid structures shared by both ride cameras.
local M=require('src.commute.vendor.mathx')
local TerrainMesh=require('src.commute.terrain_mesh')
local Ground=require('src.commute.ground_textures')
local Vegetation=require('src.commute.vegetation')
local Flora=require('src.commute.flora')
local PlantSprites=require('src.commute.vendor.plant_sprites')
local PlantMotion=require('src.commute.vendor.plant_motion')
local BikeArt=require('src.commute.bike_art')
local Structures=require('src.commute.structures')
local FP=require('src.commute.first_person_camera')
local Renderer={BUILD_BUDGET_SECONDS=.004,LOAD_BUDGET_SECONDS=.012};Renderer.__index=Renderer
function Renderer.new(world)
    local self=setmetatable({world=world,ground=Ground.new(),chunks={},radius=64,clock=0,serial=0,
        calendar=world.calendar or {month=5,totalDays=0},viewportWidth=1280,viewportHeight=880,
        outsideSpriteShader=love.graphics.newShader([[
#ifdef VERTEX
extern float spriteDepth;
vec4 position(mat4 transform_projection,vec4 vertex_position) {
    vec4 clip=transform_projection*vertex_position;
    clip.z=spriteDepth*clip.w;
    return clip;
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=Texel(tex,uv)*color;
    if(surface.a<.02) discard;
    return surface;
}
#endif
]])},Renderer)
    self.ground:prepare()
    self.vegetation=world.vegetation or Vegetation.new(world)
    world.vegetation=self.vegetation
    self.plantSprites=PlantSprites.new();self.plantMotion=PlantMotion.new(world)
    self.bikeArt=BikeArt.new()
    self.structures=Structures.new(world)
    self.bridgeArt={piers=self.structures.piers} -- Review tools consume layout metadata only.
    self:buildRoadMeshes()
    self.terrain=TerrainMesh.new(world,{tileSize=24,spacing=1})
    self.visible={};self.terrainVertices=0;self.terrainIndices=0
    return self
end
function Renderer:buildRoadMeshes()
    local layers={shoulder={},asphalt={},dirt={}}
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
            if s.surface=='dirt' then
                quad(s,s.width+.5,.025,layers.dirt,{.35,.29,.19},1)
                quad(s,s.width,.04,layers.dirt,{.47,.37,.23},1)
            else
                quad(s,s.width+1,.02,layers.shoulder,{.41,.39,.30},1)
                quad(s,s.width,.035,layers.asphalt,{.23,.25,.24},1)
            end
        end
    end
    for _,p in pairs(self.world.roads.destinations) do
        local segment={a={x=p.x,z=p.z-4,h=p.h,nx=1,nz=0},b={x=p.x,z=p.z+4,h=p.h,nx=1,nz=0}}
        quad(segment,8.4,.02,layers.shoulder,{.41,.39,.30},1)
        quad(segment,8,.04,layers.asphalt,{.23,.25,.24},1)
    end
    self.roadMeshes={}
    for _,name in ipairs({'shoulder','asphalt','dirt'}) do
        if #layers[name]>0 then self.roadMeshes[#self.roadMeshes+1]=love.graphics.newMesh(Ground.FORMAT,layers[name],'triangles','static') end
    end
    local markings,stats=require('src.commute.road_markings').build(self.world)
    self.roadMarkingStats=stats
    if #markings>0 then self.roadMeshes[#self.roadMeshes+1]=love.graphics.newMesh(Ground.FORMAT,markings,'triangles','static') end
end
-- Build the complete ground once, while the loading screen is visible. Camera
-- motion never changes this mesh set, its resolution, or its residency.
function Renderer:terrainReady()
    return self.terrain~=nil and self.terrain.ready==true
end
function Renderer:depthSpan()
    return math.max(1,(self.world.size or 512)*100+(self.world.maxHeight or 84)*100)
end
function Renderer:resizeViewport(width,height)
    width,height=math.max(1,math.floor(width+.5)),math.max(1,math.floor(height+.5))
    if width==self.viewportWidth and height==self.viewportHeight then return false end
    self.viewportWidth,self.viewportHeight=width,height
    if self.firstPersonView then self.firstPersonView:resizeViewport(width,height) end
    if self.structures then self.structures:resizeViewport(width,height) end
    return true
end
function Renderer:terrainStats()
    local t=self.terrain
    return {ready=self:terrainReady(),completed=t and t.completed or 0,total=t and t.total or 0,
        vertices=self.terrainVertices or 0,meshBytes=(self.terrainVertices or 0)*96+(self.terrainIndices or 0)*4,
        uncovered=t and t.total-t.completed or 0,submitted=self:terrainReady() and #(self.visible or {}) or 0}
end
function Renderer:terrainCoverage(x,z)
    if not self:terrainReady() or x<0 or z<0 or x>self.world.size or z>self.world.size then return false end
    -- Every resident tile is submitted in both views. This intentionally avoids
    -- horizontal-cone/radius tests, which miss steep/downward camera footprints.
    for _,tile in ipairs(self.visible) do
        if x>=tile.x0 and x<=tile.x1 and z>=tile.z0 and z<=tile.z1 then return true end
    end
    return false
end
function Renderer:prepareTerrain()
    if self:terrainReady() then self.buildMs=0;self.pending=0;return end
    local started=love.timer.getTime()
    self.terrain:step(Renderer.LOAD_BUDGET_SECONDS,function(tile,vertices,indices)
        local mesh=love.graphics.newMesh(Ground.FORMAT,vertices,'triangles','static')
        mesh:setVertexMap(indices);tile.mesh=mesh
        self.chunks[tile.key]=tile;self.visible[#self.visible+1]=tile
        self.terrainVertices=self.terrainVertices+#vertices;self.terrainIndices=self.terrainIndices+#indices
    end,love.timer.getTime)
    self.pending=self.terrain.total-self.terrain.completed
    self.buildMs=(love.timer.getTime()-started)*1000
end
function Renderer:prepare(camera,dt)
    self.world.calendar=self.calendar
    self.clock=self.clock+dt;self.serial=self.serial+1
    local radius=math.max(self.radius,camera.firstPerson and 96 or 35/camera.zoom)
    self.effectiveRadius=math.min(radius,96)
    self:prepareTerrain()
    if not self:terrainReady() then self.visibleProps={};return end
    -- Coarse painter ordering is retained for tool compatibility; ground itself
    -- uses a depth buffer, including occlusion within each larger static tile.
    for _,tile in ipairs(self.visible) do
        tile.depth=camera:depth(tile.centerX,tile.centerZ,tile.height)
    end
    table.sort(self.visible,function(a,b)return a.depth<b.depth end)
    self.plantMotion:update(dt)
    self.visibleProps=self:props(camera)
    self.plantSprites:prepare(self.visibleProps,self.calendar,self.clock)
end
function Renderer:drawLoading()
    local g=love.graphics;local stats=self:terrainStats()
    g.push('all');g.setShader();g.clear(.025,.04,.035,1)
    g.setColor(.95,.89,.70);g.printf('Preparing your town...',20,self.viewportHeight*.46,self.viewportWidth-40,'center')
    g.setColor(.75,.82,.76)
    g.printf(('Preparing terrain %d%%'):format(math.floor(stats.completed/math.max(1,stats.total)*100)),
        20,self.viewportHeight*.50,self.viewportWidth-40,'center')
    g.pop()
end
function Renderer:shader(camera)
    local s=self.ground.shader;local t=self.clock
    camera:send(s)
    s:send('groundDepthSpan',self:depthSpan())
    s:send('viewRadius',self.effectiveRadius or self.radius);s:send('detailStrength',.82)
    s:send('cloudPhase',{t*.03,t*.023,t*.017});s:send('cloudStrength',.15)
    s:send('sunDirection',{-.4,.8,-.3});s:send('sunColor',{1,.86,.66});s:send('sunlight',.45);s:send('ambientLight',.65)
    s:send('waterDetail',.85);s:send('wavePhase',{t*1.1,t*.7,t*.3});s:send('ripplePhase',{t,t*.8})
    s:send('waterView',{0,.8,.6});s:send('waterRoughness',.5)
    local _,tint,litter=Flora.season(self.calendar)
    s:send('seasonTint',tint);s:send('litterSeasonShift',litter)
    return s
end
function Renderer:drawRoads(camera,skipMeshes)
    local g=love.graphics
    g.setColor(1,1,1)
    if not skipMeshes then
        g.setShader(self.ground.shader)
        for _,mesh in ipairs(self.roadMeshes) do g.draw(mesh) end
        g.setShader()
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
    g.setLineWidth(1)
end
function Renderer:props(camera)
    local inView
    if camera.firstPerson then
        inView=function(x,z,padding)return FP.inView(camera,x,z,padding) end
    end
    local props=self.vegetation:visible(camera.centerX,camera.centerZ,self.effectiveRadius,self.calendar,inView,
        {maxPatches=2,seconds=.002,clock=love.timer.getTime})
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
-- Call during an already-presented loading screen. Interactive view switching
-- then reuses its shader, canvas and road-marking mesh without cold allocations.
function Renderer:prewarmViews()
    if not self.firstPersonView then self.firstPersonView=require('src.commute.first_person_renderer').new(self) end
    return self.firstPersonView
end
function Renderer:draw(camera,actor,actors)
    if not self:terrainReady() then self:drawLoading();return end
    if camera.firstPerson then
        return self:prewarmViews():draw(self,camera,actor,actors)
    end
    local g=love.graphics
    -- Reuse the prewarmed camera canvas: only one view renders at a time.
    -- Share the scene depth buffer so terrain, roads, structures and plant
    -- billboards occlude one another by their actual camera depth.
    local canvas=self:prewarmViews().canvas
    g.push('all');g.origin();g.setScissor();g.setShader();g.setBlendMode('alpha')
    g.setCanvas({canvas,depth=true});g.clear(.22,.27,.26,1,0,1)
    g.setDepthMode('lequal',true);g.setMeshCullMode('none')
    g.setColor(1,1,1);g.setShader(self:shader(camera))
    for _,tile in ipairs(self.visible) do g.draw(tile.mesh) end
    for _,mesh in ipairs(self.roadMeshes) do g.draw(mesh) end
    self.structures:drawOutsideDepth(camera,actor,self.effectiveRadius)
    local depthSpan=self:depthSpan()
    local actorX,actorY=camera:screen(actor.x,actor.z,actor.h or self.world:supportHeight(actor.x,actor.z))
    g.setDepthMode('lequal',true);g.setShader(self.outsideSpriteShader)
    for _,p in ipairs(self.visibleProps or {}) do
        local x,y=camera:screen(p.x,p.z,p.h)
        local fade=1-M.smooth((M.length(p.x-camera.centerX,p.z-camera.centerZ)-self.effectiveRadius*.8)/(self.effectiveRadius*.2))
        if Flora.canopy[p.kind] then
            local size=p.scale*camera.zoom
            if math.abs(x-actorX)<110*size+12*camera.zoom and y>actorY
                and y-248*size<actorY then fade=fade*.22 end
        end
        self.outsideSpriteShader:send('spriteDepth',-camera:depth(p.x,p.z,p.h)/depthSpan)
        g.setColor(.91,.94,.87,fade)
        self.plantSprites:drawPlant(p,self.calendar,self.clock,x,y,p.scale*camera.zoom,self.plantMotion:sway(p))
    end
    g.pop()
    g.push('all');g.setShader();g.setColor(1,1,1);g.setBlendMode('alpha','premultiplied')
    g.draw(canvas,0,0);g.pop()
    self:drawRoads(camera,true)
    if actors then
        for _,entry in ipairs(actors) do if not entry.gear then self:headlight(camera,entry.actor) end end
    else self:headlight(camera,actor) end
    local props={}
    for _,piece in ipairs(self.structures:visible(camera,self.effectiveRadius,'props')) do props[#props+1]=piece end
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
                local presentation=require('src.commute.presentation')
                local falling=presentation.beginFallPose(a,p.presentation,camera,x,y)
                if not presentation.world(self.characterAssets,a,camera,self.world,
                    p.gear,p.appearance,p.presentation,self.clock) then
                    presentation.foot(x,y,camera.zoom,p.gear,a.distance,a.speed,p.presentation,p.appearance)
                end
                if falling then g.pop() end
            else self.bikeArt:draw(p.actor,camera,self.world,p.bikeOnly,p.presentation,p.localPlayer==true) end
        elseif p.structure then self.structures:drawOutside(p,camera,actor,self.effectiveRadius)
        end
    end
    g.setColor(1,1,1);g.setLineWidth(1)
end
function Renderer:release()
    if self.released then return end;self.released=true
    self.terrain=nil
    if self.firstPersonView then self.firstPersonView:release() end
    for _,chunk in pairs(self.chunks) do chunk.mesh:release() end
    self.chunks={};self.visible={}
    self.plantSprites:release()
    self.bikeArt:release()
    self.structures:release()
    if self.outsideSpriteShader then self.outsideSpriteShader:release() end
    for _,mesh in ipairs(self.roadMeshes) do mesh:release() end
    self.ground:release()
end
return Renderer
