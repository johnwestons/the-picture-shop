-- Budgeted terrain, vegetation and solid structures shared by both ride cameras.
local M=require('src.commute.vendor.mathx')
local TerrainMesh=require('src.commute.terrain_mesh')
local TerrainCache=require('src.commute.terrain_cache')
local Ground=require('src.commute.ground_textures')
local Vegetation=require('src.commute.vegetation')
local Flora=require('src.commute.flora')
local PlantSprites=require('src.commute.vendor.plant_sprites')
local PlantMotion=require('src.commute.vendor.plant_motion')
local BikeArt=require('src.commute.bike_art')
local TruckArt=require('src.commute.truck_art')
local Structures=require('src.commute.structures')
local FP=require('src.commute.first_person_camera')
local TireTracks=require('src.commute.tire_tracks')
local BikeParticles=require('src.commute.bike_particles')
local GrassFields=require('src.commute.grass_fields')
local Colorways=require('src.rabbit_colorways')
local BikePaintArt=require('src.commute.bike_paint_art')
local Renderer={BUILD_BUDGET_SECONDS=.004,LOAD_BUDGET_SECONDS=.012,
    MOBILE_FOLIAGE_RADIUS=72,DESKTOP_FOLIAGE_RADIUS=96,
    PROPS_REFRESH_SECONDS=.20,PROPS_REFRESH_DISTANCE=1.5,PROPS_REFRESH_TURN=4};Renderer.__index=Renderer
local outsideDepthVertex=[[
#ifdef VERTEX
extern float spriteDepth;
vec4 position(mat4 transform_projection,vec4 vertex_position) {
    vec4 clip=transform_projection*vertex_position;
    clip.z=spriteDepth*clip.w;
    return clip;
}
#endif
]]
local function outsideSpriteShader()
    return outsideDepthVertex..[[
#ifdef PIXEL
extern bool silhouetteMode;
extern vec3 silhouetteColor;
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=Texel(tex,uv)*color;
    if(surface.a<.02) discard;
    if(silhouetteMode) return vec4(silhouetteColor,surface.a);
    return surface;
}
#endif
]]
end
local function tireTrackDepthShader()
    return outsideDepthVertex..[[
#ifdef PIXEL
vec4 effect(vec4 color,Image texture,vec2 uv,vec2 pixel) { return color; }
#endif
]]
end
local function setSilhouetteMode(shader,enabled)
    if shader:hasUniform('silhouetteMode') then shader:send('silhouetteMode',enabled) end
    if shader:hasUniform('silhouetteColor') then shader:send('silhouetteColor',{1,.72,.08}) end
end
local function tileDistance(tile,x,z)
    local dx=math.max(tile.x0-x,0,x-tile.x1)
    local dz=math.max(tile.z0-z,0,z-tile.z1)
    return dx*dx+dz*dz
end

function Renderer.new(world,spawn)
    local self=setmetatable({world=world,ground=Ground.new(),chunks={},radius=64,clock=0,serial=0,
        mobile=love.system.getOS()=='Android',
        calendar=world.calendar or {month=5,totalDays=0},viewportWidth=1280,viewportHeight=880,
        tireTracks=TireTracks.new(),bikeParticles=BikeParticles.new(),
        outsideSpriteShader=love.graphics.newShader(outsideSpriteShader()),
        tireTrackShader=love.graphics.newShader(tireTrackDepthShader()),
        outsideColorwaysShader=love.graphics.newShader(outsideDepthVertex..Colorways.blendShaderSource()..[[
#ifdef PIXEL
extern bool silhouetteMode;
extern vec3 silhouetteColor;
vec4 effect(vec4 color,Image texture,vec2 texture_coords,vec2 screen_coords) {
    vec4 pixel=Texel(texture,texture_coords)*color;
    if(pixel.a<.02) discard;
    if(silhouetteMode) return vec4(silhouetteColor,pixel.a);
    return applyRabbitColorways(pixel);
}
#endif
]]),
        outsideBikePaintShader=love.graphics.newShader(outsideDepthVertex..BikePaintArt.source()..[[
#ifdef PIXEL
extern bool silhouetteMode;
extern vec3 silhouetteColor;
vec4 effect(vec4 color,Image texture,vec2 uv,vec2 pixel) {
    vec4 surface=bikePaintSurface(Texel(texture,uv),uv)*color;
    if(surface.a<.02) discard;
    if(silhouetteMode) return vec4(silhouetteColor,surface.a);
    return surface;
}
#endif
]])},Renderer)
    self.ground:prepare()
    self.vegetation=world.vegetation or Vegetation.new(world)
    world.vegetation=self.vegetation
    self.grassFields=GrassFields.new(world)
    self.plantSprites=PlantSprites.new();self.plantMotion=PlantMotion.new(world)
    self.bikeArt=BikeArt.new()
    self.truckArt=TruckArt.new()
    self.structures=Structures.new(world)
    self.bridgeArt={piers=self.structures.piers} -- Review tools consume layout metadata only.
    self:buildRoadMeshes()
    self.terrain=TerrainMesh.new(world,{tileSize=24,spacing=1})
    self.visible={};self.terrainVertices=0;self.terrainIndices=0
    local origin=spawn or world.spawn or {x=world.size*.5,z=world.size*.5}
    self.starter={x=origin.x,z=origin.z,radius=30}
    self.starterRemaining=0
    for _,tile in ipairs(self.terrain.tiles) do
        tile.starter=tileDistance(tile,origin.x,origin.z)<=self.starter.radius^2
        if tile.starter then self.starterRemaining=self.starterRemaining+1 end
    end
    table.sort(self.terrain.tiles,function(a,b)
        local da,db=tileDistance(a,origin.x,origin.z),tileDistance(b,origin.x,origin.z)
        if da~=db then return da<db end
        if a.x0~=b.x0 then return a.x0<b.x0 end
        return a.z0<b.z0
    end)
    self.terrainStore=TerrainCache.store(world)
    self.terrainCacheReady=TerrainCache.available(self.terrainStore)
    self.terrainCacheWritable=self.terrainStore~=nil and not self.terrainCacheReady
    return self
end
function Renderer.foliageRadius(viewRadius,mobile)
    local limit=mobile and Renderer.MOBILE_FOLIAGE_RADIUS or Renderer.DESKTOP_FOLIAGE_RADIUS
    return math.min(viewRadius or limit,limit)
end
function Renderer:buildRoadMeshes()
    local layers={shoulder={},asphalt={},dirt={},approach={}}
    local function vertex(layer,x,z,h,height,color,coverage)
        layer[#layer+1]={x,z,h+height,0,1,0,x/4,z/4,x/4,z/4,0,0,
            color[1],color[2],color[3],1,0,1,0,coverage,0,1,0,0}
    end
    local function quad(s,width,height,layer,color,coverage)
        local a,b=s.a,s.b;local w=width*.5
        local points={{a.x+a.nx*w,a.z+a.nz*w,a.h},{b.x+b.nx*w,b.z+b.nz*w,b.h},
            {b.x-b.nx*w,b.z-b.nz*w,b.h},{a.x-a.nx*w,a.z-a.nz*w,a.h}}
        for _,index in ipairs({1,2,3,1,3,4}) do
            local p=points[index];local x,z=p[1],p[2]
            vertex(layer,x,z,p[3],height,color,coverage)
        end
    end
    local function disk(junction,radius,height,layer,color,coverage)
        local x,z,h=junction.x,junction.z,junction.h
        local function rim(angle)
            local dx,dz=math.cos(angle)*radius,math.sin(angle)*radius
            vertex(layer,x+dx,z+dz,h+dx*junction.gx+dz*junction.gz,height,color,coverage)
        end
        local steps=24
        for i=0,steps-1 do
            local a=i*math.pi*2/steps;local b=(i+1)*math.pi*2/steps
            vertex(layer,x,z,h,height,color,coverage)
            rim(a)
            rim(b)
        end
    end
    local function siteRect(site,r,padding,height,layer,color)
        local x0,x1,z0,z1=r.minX-padding,r.maxX+padding,r.minZ-padding,r.maxZ+padding
        local points={}
        for _,localPoint in ipairs({{x0,z0},{x1,z0},{x1,z1},{x0,z1}}) do
            local x,z,h=site:toWorld(localPoint[1],localPoint[2],0)
            points[#points+1]={x=x,z=z,h=h}
        end
        for _,index in ipairs({1,2,3,1,3,4}) do
            local p=points[index];vertex(layer,p.x,p.z,p.h,height,color,1)
        end
    end
    local function siteLine(site,a,b,width,height,layer,color)
        local ax,az,ah=site:toWorld(a[1],a[2],0)
        local bx,bz,bh=site:toWorld(b[1],b[2],0)
        local dx,dz=bx-ax,bz-az;local length=M.length(dx,dz)
        if length<1e-5 then return end
        quad({a={x=ax,z=az,h=ah,nx=-dz/length,nz=dx/length},
            b={x=bx,z=bz,h=bh,nx=-dz/length,nz=dx/length}},width,height,layer,color,1)
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
    for _,junction in ipairs(self.world.roads.junctions or {}) do
        disk(junction,junction.outerRadius,.02,layers.shoulder,{.41,.39,.30},1)
        disk(junction,junction.radius,.04,layers.asphalt,{.23,.25,.24},1)
    end
    for id,p in pairs(self.world.roads.destinations) do
        local site=self.world.roads.sites and self.world.roads.sites.byId and self.world.roads.sites.byId[id]
        local center=site and site.parking or p
        local yaw=site and site.yaw or 0
        local nx,nz=math.cos(yaw),math.sin(yaw)
        local zx,zz=-math.sin(yaw),math.cos(yaw)
        local segment={a={x=center.x-zx*4,z=center.z-zz*4,h=center.h or p.h,nx=nx,nz=nz},
            b={x=center.x+zx*4,z=center.z+zz*4,h=center.h or p.h,nx=nx,nz=nz}}
        quad(segment,8.4,.02,layers.shoulder,{.41,.39,.30},1)
        quad(segment,8,.04,layers.asphalt,{.23,.25,.24},1)
    end
    local sites=self.world.roads.sites and self.world.roads.sites.byId or {}
    for id,site in pairs(sites) do
        if site.localTruckParkingArea and site.localTruckApproach then
            for _,rect in ipairs({site.localTruckParkingArea,site.localTruckApproach}) do
                siteRect(site,rect,.34,.02,layers.shoulder,{.41,.39,.30})
                siteRect(site,rect,0,.04,layers.asphalt,{.23,.25,.24})
            end
            local area=site.localTruckParkingArea;local inset=.16
            local z0,z1=area.minZ+inset,area.maxZ-inset
            local x0,x1=area.minX+inset,area.maxX-inset
            local mark={.95,.70,.24}
            siteLine(site,{x0,z0},{x1,z0},.075,.065,layers.approach,mark)
            siteLine(site,{x0,z1},{x1,z1},.075,.065,layers.approach,mark)
            siteLine(site,{x0,z0},{x0,z1},.11,.065,layers.approach,mark)
            siteLine(site,{x1,z0},{x1,z1},.075,.065,layers.approach,mark)
        end
        if self.world.roads.destinations[id] then
            local a,b=site.threshold,site.parking
            local dx,dz=b.x-a.x,b.z-a.z;local length=M.length(dx,dz)
            if length>.1 then
                local nx,nz=-dz/length,dx/length
                local segment={a={x=a.x,z=a.z,h=a.h,nx=nx,nz=nz},
                    b={x=b.x,z=b.z,h=b.h,nx=nx,nz=nz}}
                quad(segment,3.4,.025,layers.approach,{.48,.46,.39},1)
            end
        end
    end
    self.roadMeshes={}
    for _,name in ipairs({'shoulder','asphalt','dirt','approach'}) do
        if #layers[name]>0 then self.roadMeshes[#self.roadMeshes+1]=love.graphics.newMesh(Ground.FORMAT,layers[name],'triangles','static') end
    end
    local markings,stats=require('src.commute.road_markings').build(self.world)
    self.roadMarkingStats=stats
    if #markings>0 then self.roadMeshes[#self.roadMeshes+1]=love.graphics.newMesh(Ground.FORMAT,markings,'triangles','static') end
end
-- Build or upload local tiles first, then fill the town while the player moves.
-- Completed tiles remain resident for this trip and are released on return.
function Renderer:terrainReady()
    return self.terrain~=nil and self.terrain.ready==true
end
function Renderer:starterReady()
    return self.terrain~=nil and (self.starterRemaining==nil and self:terrainReady()
        or self.starterRemaining==0)
end
function Renderer:depthSpan()
    return math.max(1,(self.world.size or 512)*100+(self.world.maxHeight or 84)*100)
end
function Renderer:updateTireTracks(id,bike,world,dt,visual)
    return self.tireTracks:update(id,bike,world or self.world,dt,visual)
end
function Renderer:updateBikeParticles(entries,dt)
    self.bikeParticles:advance(dt)
    for _,entry in ipairs(entries) do
        self.bikeParticles:emit(entry.id,entry.bike,self.world,dt,entry.visual,entry.engine,entry.mounted)
    end
end
function Renderer:resizeViewport(width,height)
    width,height=math.max(1,math.floor(width+.5)),math.max(1,math.floor(height+.5))
    if width==self.viewportWidth and height==self.viewportHeight then return false end
    self.viewportWidth,self.viewportHeight=width,height
    self.visibleProps=nil
    if self.firstPersonView then self.firstPersonView:resizeViewport(width,height) end
    if self.structures then self.structures:resizeViewport(width,height) end
    return true
end
function Renderer:terrainStats()
    local t=self.terrain
    return {ready=self:terrainReady(),completed=t and t.completed or 0,total=t and t.total or 0,
        vertices=self.terrainVertices or 0,meshBytes=(self.terrainVertices or 0)*96+(self.terrainIndices or 0)*4,
        uncovered=t and t.total-t.completed or 0,submitted=#(self.visible or {}),
        starterReady=self:starterReady(),starterRemaining=self.starterRemaining or 0}
end
function Renderer:terrainCoverage(x,z)
    if not self.terrain or x<0 or z<0 or x>self.world.size or z>self.world.size then return false end
    -- Every resident tile is submitted in both views. This intentionally avoids
    -- horizontal-cone/radius tests, which miss steep/downward camera footprints.
    for _,tile in ipairs(self.visible) do
        if x>=tile.x0 and x<=tile.x1 and z>=tile.z0 and z<=tile.z1 then return true end
    end
    return false
end
function Renderer:coverageRadius(camera)
    if self:terrainReady() then return self.effectiveRadius end
    local nearest=self.effectiveRadius^2
    for _,tile in ipairs(self.terrain.tiles) do
        if not tile.ready then
            nearest=math.min(nearest,tileDistance(tile,camera.centerX,camera.centerZ))
        end
    end
    return math.max(1,math.min(self.effectiveRadius,math.sqrt(nearest)))
end
function Renderer:uploadTerrainTile(tile,vertices,indices,fromCache)
    local mesh
    if fromCache then
        mesh=love.graphics.newMesh(Ground.FORMAT,vertices.vertexCount,'triangles','static')
        mesh:setVertices(vertices.vertices)
        mesh:setVertexMap(vertices.indices,'uint32')
        tile.vertexCount,tile.indexCount=vertices.vertexCount,vertices.indexCount
    else
        mesh=love.graphics.newMesh(Ground.FORMAT,vertices,'triangles','static')
        mesh:setVertexMap(indices)
    end
    tile.mesh=mesh
    tile.height=tile.height or self.world:supportHeight(tile.centerX,tile.centerZ)
    self.chunks[tile.key]=tile;self.visible[#self.visible+1]=tile
    self.terrainVertices=self.terrainVertices+tile.vertexCount
    self.terrainIndices=self.terrainIndices+tile.indexCount
    if tile.starter then self.starterRemaining=self.starterRemaining-1 end
end
function Renderer:prepareTerrain()
    if self:terrainReady() then self.buildMs=0;self.pending=0;return end
    local started=love.timer.getTime()
    if self.terrainCacheReady then
        repeat
            local tile=self.terrain.tiles[self.terrain.completed+1]
            local data=TerrainCache.readTile(self.terrainStore,tile,true)
            if not data then
                self.terrainCacheReady=false;self.terrainCacheWritable=true
                break
            end
            self:uploadTerrainTile(tile,data,nil,true)
            tile.ready=true
            self.terrain.vertexCount=self.terrain.vertexCount+tile.vertexCount
            self.terrain.indexCount=self.terrain.indexCount+tile.indexCount
            self.terrain.completed=self.terrain.completed+1
            self.terrain.ready=self.terrain.completed==self.terrain.total
        until self.terrain.ready or love.timer.getTime()-started>=Renderer.LOAD_BUDGET_SECONDS
    end
    if not self.terrainCacheReady and not self.terrain.ready then
        local remaining=math.max(0,Renderer.LOAD_BUDGET_SECONDS-(love.timer.getTime()-started))
        self.terrain:step(remaining,function(tile,vertices,indices)
            if self.terrainCacheWritable then
                local okay=TerrainCache.writeTile(self.terrainStore,tile,vertices,indices)
                if not okay then self.terrainCacheWritable=false end
            end
            self:uploadTerrainTile(tile,vertices,indices,false)
        end,love.timer.getTime)
        if self.terrain.ready and self.terrainCacheWritable then
            TerrainCache.complete(self.terrainStore,self.terrain)
        end
    end
    self.pending=self.terrain.total-self.terrain.completed
    self.buildMs=(love.timer.getTime()-started)*1000
end
function Renderer:prepare(camera,dt)
    camera=camera.shoulderView or camera
    self.world.calendar=self.calendar
    self.clock=self.clock+dt;self.serial=self.serial+1
    local radius=math.max(self.radius,camera.firstPerson and 96 or 35/camera.zoom)
    self.effectiveRadius=math.min(radius,96)
    self:prepareTerrain()
    self.effectiveRadius=self:coverageRadius(camera)
    -- Let the player walk on local ground while the rest of the tiles upload.
    -- Vegetation can appear after terrain finishes; it never gates the reveal.
    if not self:terrainReady() then
        self.visibleGrass={};self.visibleProps={}
        return
    end
    if self.grassFields then
        local r=math.min(self.effectiveRadius,GrassFields.FAR_VIEW_RADIUS)
        self.visibleGrass=self.grassFields:collect(camera.centerX-r,camera.centerZ-r,
            camera.centerX+r,camera.centerZ+r,camera,r)
    end
    -- Coarse painter ordering is retained for tool compatibility; ground itself
    -- uses a depth buffer, including occlusion within each larger static tile.
    for _,tile in ipairs(self.visible) do
        tile.depth=camera:depth(tile.centerX,tile.centerZ,tile.height)
    end
    table.sort(self.visible,function(a,b)return a.depth<b.depth end)
    self.plantMotion:update(dt)
    local foliageRadius=Renderer.foliageRadius(self.effectiveRadius,self.mobile)
    local elapsed=(self.visiblePropsClock or Renderer.PROPS_REFRESH_SECONDS)+dt
    local centerX,centerZ=camera.centerX,camera.centerZ
    local moved=not self.visiblePropsX or not self.visiblePropsZ
        or (centerX-self.visiblePropsX)^2+(centerZ-self.visiblePropsZ)^2
            >=Renderer.PROPS_REFRESH_DISTANCE^2
    local yaw=camera.yaw
    local turned=camera.firstPerson and yaw and self.visiblePropsYaw
        and math.abs((yaw-self.visiblePropsYaw+180)%360-180)>=Renderer.PROPS_REFRESH_TURN
    local calendar=self.calendar or {}
    local seasonChanged=self.visiblePropsDay~=(calendar.totalDays or 0)
        or self.visiblePropsMonth~=(calendar.month or 5)
    local radiusChanged=self.visiblePropsRadius~=foliageRadius
    local viewChanged=self.visiblePropsFirstPerson~=(camera.firstPerson==true)
    local refreshProps=not self.visibleProps or moved or turned or seasonChanged
        or radiusChanged or viewChanged or elapsed>=Renderer.PROPS_REFRESH_SECONDS
    if refreshProps then
        self.visibleProps=self:props(camera,foliageRadius)
        self.visiblePropsX,self.visiblePropsZ=centerX,centerZ
        self.visiblePropsYaw=yaw
        self.visiblePropsRadius=foliageRadius
        self.visiblePropsDay,self.visiblePropsMonth=calendar.totalDays or 0,calendar.month or 5
        self.visiblePropsFirstPerson=camera.firstPerson==true
        self.visiblePropsClock=0
    else
        self.visiblePropsClock=elapsed
    end
    self.plantSpriteClock=(self.plantSpriteClock or Renderer.PROPS_REFRESH_SECONDS)+dt
    if refreshProps or self.plantSpriteClock>=Renderer.PROPS_REFRESH_SECONDS then
        self.plantSprites:prepare(self.visibleProps,self.calendar,self.clock)
        self.plantSpriteClock=0
    end
end

function Renderer:drawGrass(camera,actor)
    if not self.grassFields then return end
    local g=love.graphics
    local season=Flora.season(self.calendar)
    self.grassFields:prepareDraw(camera,self.clock,season,
        math.min(self.effectiveRadius,GrassFields.FAR_VIEW_RADIUS),self:depthSpan(),actor)
    -- Grass is geometry in the shared scene; let nearer blades occlude later
    -- billboards, with the local player's silhouette pass preserving visibility.
    g.setDepthMode('lequal',true);g.setShader(self.grassFields.shader);g.setColor(.91,.94,.87,1)
    for _,patch in ipairs(self.visibleGrass or {}) do self.grassFields:drawPatch(patch) end
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
            local x,y=camera:screen(p.x,p.z,p.h+.1);g.setColor(.85,.8,.53);g.circle('line',x,y,12*camera.zoom)
            g.setColor(.94,.91,.76);g.print(p.label,x+14,y-18)
        end
    end
    g.setLineWidth(1)
end
function Renderer:props(camera,radius)
    local inView
    if camera.firstPerson then
        inView=function(x,z,padding)return FP.inView(camera,x,z,padding) end
    end
    local props=self.vegetation:visible(camera.centerX,camera.centerZ,radius or self.effectiveRadius,self.calendar,inView,
        {maxPatches=2,seconds=.002,clock=love.timer.getTime})
    for _,p in ipairs(props) do
        p.scale=p.scale*Flora.scale(p);p.depth=camera:depth(p.x,p.z,p.h)
    end
    return props
end
function Renderer:headlight(camera,bike)
    if not bike.headlight then return end
    local g=love.graphics
    local Headlight=require('src.commute.headlight')
    local sourceX,sourceZ,sourceHeight=Headlight.position(bike)
    local length,spread=Headlight.parameters(bike)
    local heading=bike.heading or 0
    local function point(forward,side,raised)
        local x=sourceX+math.cos(heading)*forward-math.sin(heading)*side
        local z=sourceZ+math.sin(heading)*forward+math.cos(heading)*side
        local height=raised and sourceHeight or self.world:supportHeight(x,z)+.05
        return camera:screen(x,z,height)
    end
    for d=1,length do
        local x=sourceX+math.cos(heading)*d;local z=sourceZ+math.sin(heading)*d
        if self.world.roads:blocked(self.world,x,z) then length=d;break end
    end
    local ax,ay=point(0,0,true)
    for layer=5,1,-1 do
        local reach=length*(.42+layer*.116);local width=.15+reach*spread
        local bx,by=point(reach,-width,false);local cx,cy=point(reach,width,false)
        local alpha=(bike.headlightHighBeam and .046 or .038)*(1-layer*.075)
        if bike.headlightHighBeam then g.setColor(.94,.91,.75,alpha)
        else g.setColor(1,.88,.61,alpha) end
        g.polygon('fill',ax,ay,bx,by,cx,cy)
    end
    g.setColor(1,1,1)
end
-- Call during an already-presented loading screen. Interactive view switching
-- then reuses its shader, canvas and road-marking mesh without cold allocations.
function Renderer:prewarmViews()
    if self.bikeParticles then self.bikeParticles:prewarm() end
    if not self.firstPersonView then self.firstPersonView=require('src.commute.first_person_renderer').new(self) end
    return self.firstPersonView
end
function Renderer:drawOutsideActor(entry,camera)
    local g=love.graphics
    local p=entry.actor
    local support,kind=self.world:supportHeight(p.x,p.z)
    local actorHeight=p.h or support
    local height=actorHeight
    if kind=='road' or kind=='trail' then height=math.max(height,support+.055) end
    local grounded=(not entry.presentation or entry.presentation.grounded~=false)
        and p.grounded~=false
    local mountedBike=not entry.bikeOnly and not entry.dismounting
        and (entry.bike or entry.gear and entry.gear.mounted)
    local bikeHeight=entry.presentation and entry.presentation.h or actorHeight
    if entry.truck and grounded then
        local depthBias=self.truckArt:groundedDepthBias(p,camera,actorHeight,self.world)
        height=math.max(height,support+depthBias+.055)
    elseif mountedBike and grounded and bikeHeight-support<.4 then
        -- Match depth to the lowest authored tire pixels for this pose and
        -- camera angle. The scene actor entries mark bikes directly; mounted
        -- players do not carry gear on the bike entry.
        local depthBias=self.bikeArt:groundedDepthBias(p,camera,bikeHeight,entry.presentation)
        height=math.max(height,support+depthBias+.055)
    elseif mountedBike then
        height=bikeHeight
    end
    local spriteDepth=-camera:depth(p.x,p.z,height)/self:depthSpan()
    local function drawPass(silhouette)
        -- The reverse depth pass draws only actor pixels hidden by nearer
        -- geometry, leaving the ordinary sprite fully depth-correct.
        g.push('all');g.setDepthMode(silhouette and 'greater' or 'lequal',not silhouette)
        g.setColor(1,1,1,1)
        setSilhouetteMode(self.outsideSpriteShader,silhouette)
        setSilhouetteMode(self.outsideColorwaysShader,silhouette)
        setSilhouetteMode(self.outsideBikePaintShader,silhouette)
        if entry.truck then
            self.outsideSpriteShader:send('spriteDepth',spriteDepth);g.setShader(self.outsideSpriteShader)
            self.truckArt:draw(p,camera,self.world)
            self.truckArt:drawSignals(p,camera,self.world,self.clock)
        elseif entry.dismounting then
            self.outsideBikePaintShader:send('spriteDepth',spriteDepth);g.setShader(self.outsideBikePaintShader)
            self.bikeArt:draw(p,camera,self.world,true,entry.presentation)
            local presentation=require('src.commute.presentation')
            local rider=entry.actionActor or p
            self.outsideColorwaysShader:send('spriteDepth',spriteDepth);g.setShader(self.outsideColorwaysShader)
            presentation.world(self.characterAssets,rider,camera,self.world,
                entry.gear,entry.appearance,entry.presentation,self.clock,self.outsideColorwaysShader,
                self.outsideSpriteShader,spriteDepth,silhouette)
        elseif entry.gear and not entry.gear.mounted then
            self.outsideColorwaysShader:send('spriteDepth',spriteDepth);g.setShader(self.outsideColorwaysShader)
            local presentation=require('src.commute.presentation')
            local authoredCrash=presentation.hasAuthoredCrash(entry.appearance)
                and (p.crash~=nil or entry.presentation and entry.presentation.pose=='crash')
            local x,y=camera:screen(p.x,p.z,height)
            local falling=not authoredCrash and presentation.beginFallPose(p,entry.presentation,camera,x,y)
            presentation.world(self.characterAssets,p,camera,self.world,
                entry.gear,entry.appearance,entry.presentation,self.clock,self.outsideColorwaysShader,
                self.outsideSpriteShader,spriteDepth,silhouette)
            if falling then g.pop() end
        else
            self.outsideBikePaintShader:send('spriteDepth',spriteDepth);g.setShader(self.outsideBikePaintShader)
            self.bikeArt:draw(p,camera,self.world,entry.bikeOnly,entry.presentation)
        end
        g.pop()
    end
    drawPass(false)
    if entry.localPlayer then
        drawPass(true)
        setSilhouetteMode(self.outsideSpriteShader,false)
        setSilhouetteMode(self.outsideColorwaysShader,false)
        setSilhouetteMode(self.outsideBikePaintShader,false)
    end
end
function Renderer:draw(camera,actor,actors)
    camera=camera.shoulderView or camera
    if not self:starterReady() then self:drawLoading();return end
    if not actors then actors={{actor=actor,localPlayer=true}} end
    if camera.firstPerson then
        return self:prewarmViews():draw(self,camera,actor,actors)
    end
    local g=love.graphics
    -- Reuse the prewarmed camera canvas: only one view renders at a time.
    -- Share the scene depth buffer so terrain, roads, structures and plant
    -- billboards occlude one another by their actual camera depth.
    local canvas=self:prewarmViews().canvas
    local foliageRadius=Renderer.foliageRadius(self.effectiveRadius,self.mobile)
    g.push('all');g.origin();g.setScissor();g.setShader();g.setBlendMode('alpha')
    g.setCanvas({canvas,depth=true});g.clear(.22,.27,.26,1,0,1)
    g.setDepthMode('lequal',true);g.setMeshCullMode('none')
    g.setColor(1,1,1);g.setShader(self:shader(camera))
    for _,tile in ipairs(self.visible) do g.draw(tile.mesh) end
    for _,mesh in ipairs(self.roadMeshes) do g.draw(mesh) end
    self.structures:drawOutsideDepth(camera,actor,self.effectiveRadius)
    self.structures:drawOutsidePropsDepth(camera,actor,self.effectiveRadius)
    self:drawGrass(camera,actor)
    self.tireTracks:draw(camera,self.tireTrackShader,self:depthSpan())
    local depthSpan=self:depthSpan()
    local actorX,actorY=camera:screen(actor.x,actor.z,actor.h or self.world:supportHeight(actor.x,actor.z))
    -- Share depth across billboards and solid geometry so plants behind a
    -- building or actor cannot paint over it, and foreground foliage can occlude.
    g.setDepthMode('lequal',true);g.setShader(self.outsideSpriteShader)
    for _,p in ipairs(self.visibleProps or {}) do
        local x,y=camera:screen(p.x,p.z,p.h)
        local fade=1-M.smooth((M.length(p.x-camera.centerX,p.z-camera.centerZ)-foliageRadius*.8)/(foliageRadius*.2))
        if Flora.canopy[p.kind] then
            local size=p.scale*camera.zoom
            if math.abs(x-actorX)<110*size+12*camera.zoom and y>actorY
                and y-248*size<actorY then fade=fade*.22 end
        end
        self.outsideSpriteShader:send('spriteDepth',-camera:depth(p.x,p.z,p.h)/depthSpan)
        g.setColor(.91,.94,.87,fade)
        self.plantSprites:drawPlant(p,self.calendar,self.clock,x,y,p.scale*camera.zoom,self.plantMotion:sway(p))
    end
    for _,entry in ipairs(actors) do self:drawOutsideActor(entry,camera) end
    if self.bikeParticles then self.bikeParticles:draw(camera,self.effectiveRadius,depthSpan) end
    g.pop()
    g.push('all');g.setShader();g.setColor(1,1,1);g.setBlendMode('alpha','premultiplied')
    g.draw(canvas,0,0);g.pop()
    self:drawRoads(camera,true)
    for _,entry in ipairs(actors) do if not entry.gear then self:headlight(camera,entry.actor) end end
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
    if self.truckArt then self.truckArt:release() end
    if self.bikeParticles then self.bikeParticles:release() end
    if self.grassFields then self.grassFields:release() end
    self.structures:release()
    if self.outsideSpriteShader then self.outsideSpriteShader:release() end
    if self.outsideColorwaysShader then self.outsideColorwaysShader:release() end
    if self.outsideBikePaintShader then self.outsideBikePaintShader:release() end
    if self.tireTrackShader then self.tireTrackShader:release() end
    for _,mesh in ipairs(self.roadMeshes) do mesh:release() end
    self.ground:release()
end
return Renderer
