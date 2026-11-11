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
local SilhouetteStyle=require('src.commute.silhouette_style')
local BikePaintArt=require('src.commute.bike_paint_art')
local Bays=require('src.commute.parking_bays')
local DayNight=require('src.commute.day_night')
local Shadows=require('src.commute.shadows')
local Renderer={BUILD_BUDGET_SECONDS=.004,LOAD_BUDGET_SECONDS=.012,
    MOBILE_LOAD_BUDGET_SECONDS=.006,
    -- Preserve distant tree silhouettes while shortening low brush on phones.
    MOBILE_FOLIAGE_RADIUS=48,MOBILE_BRUSH_RADIUS=40,DESKTOP_FOLIAGE_RADIUS=96,
    MOBILE_VEGETATION_BUDGET_SECONDS=.0012,DESKTOP_VEGETATION_BUDGET_SECONDS=.002,
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
]]..SilhouetteStyle.shaderFunctions..[[
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=Texel(tex,uv)*color;
    if(surface.a<.02) discard;
    if(silhouetteMode) {
        if(silhouetteOutlineOnly && !silhouetteOutlinePixel(tex,uv)) discard;
        return vec4(silhouetteColor,silhouetteOutputAlpha(surface.a));
    }
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
local function setSilhouetteMode(shader,enabled,settings)
    SilhouetteStyle.send(shader,enabled,settings)
end
local function tileDistance(tile,x,z)
    local dx=math.max(tile.x0-x,0,x-tile.x1)
    local dz=math.max(tile.z0-z,0,z-tile.z1)
    return dx*dx+dz*dz
end
local function routePriority(tile,path)
    local best=math.huge
    local traveled=0
    for i=2,#path do
        local a,b=path[i-1],path[i]
        local dx,dz=b.x-a.x,b.z-a.z
        local span=math.sqrt(dx*dx+dz*dz)
        if span>0 then
            local u=math.max(0,math.min(1,((tile.centerX-a.x)*dx+(tile.centerZ-a.z)*dz)/(span*span)))
            local x,z=a.x+dx*u,a.z+dz*u
            local off=math.sqrt(tileDistance(tile,x,z))
            if off<30 then best=math.min(best,traveled+span*u+off*3) end
        end
        traveled=traveled+span
    end
    return best
end
local function depthBefore(a,b)return a.depth<b.depth end
local function normalizedVector(x,y,z)
    local inverse=1/math.sqrt(x*x+y*y+z*z)
    return {x*inverse,y*inverse,z*inverse}
end
local WATER_VIEW={0,.8,.6}

function Renderer.new(world,spawn,options)
    options=options or {}
    local mobile=options.mobile==true or love.system.getOS()=='Android'
    local terrainSpacing=mobile and TerrainMesh.MOBILE_SPACING or 1
    local self=setmetatable({world=world,ground=Ground.new({mobile=mobile}),chunks={},radius=64,clock=0,serial=0,
        mobile=mobile,terrainSpacing=terrainSpacing,
        calendar=world.calendar or {month=5,totalDays=0},viewportWidth=1280,viewportHeight=880,
        tireTracks=TireTracks.new(),bikeParticles=BikeParticles.new(),shadows=Shadows.new(),
        outsideSpriteShader=love.graphics.newShader(outsideSpriteShader()),
        tireTrackShader=love.graphics.newShader(tireTrackDepthShader()),
        outsideColorwaysShader=love.graphics.newShader(outsideDepthVertex..Colorways.blendShaderSource()..[[
#ifdef PIXEL
extern bool silhouetteMode;
extern vec3 silhouetteColor;
]]..SilhouetteStyle.shaderFunctions..[[
vec4 effect(vec4 color,Image texture,vec2 texture_coords,vec2 screen_coords) {
    vec4 pixel=Texel(texture,texture_coords)*color;
    if(pixel.a<.02) discard;
    if(silhouetteMode) {
        if(silhouetteOutlineOnly && !silhouetteOutlinePixel(texture,texture_coords)) discard;
        return vec4(silhouetteColor,silhouetteOutputAlpha(pixel.a));
    }
    return applyRabbitColorways(pixel);
}
#endif
]]),
        outsideBikePaintShader=love.graphics.newShader(outsideDepthVertex..BikePaintArt.source()..[[
#ifdef PIXEL
extern bool silhouetteMode;
extern vec3 silhouetteColor;
]]..SilhouetteStyle.shaderFunctions..[[
vec4 effect(vec4 color,Image texture,vec2 uv,vec2 pixel) {
    vec4 surface=bikePaintSurface(Texel(texture,uv),uv)*color;
    if(surface.a<.02) discard;
    if(silhouetteMode) {
        if(silhouetteOutlineOnly && !silhouetteOutlinePixel(texture,uv)) discard;
        return vec4(silhouetteColor,silhouetteOutputAlpha(surface.a));
    }
    return surface;
}
#endif
]])},Renderer)
    self.ground:prepare()
    self.vegetation=world.vegetation or Vegetation.new(world)
    world.vegetation=self.vegetation
    self.grassFields=GrassFields.new(world,{mobile=self.mobile})
    self.plantSprites=PlantSprites.new({mobile=mobile});self.plantMotion=PlantMotion.new(world)
    self.bikeArt=BikeArt.new()
    self.truckArt=TruckArt.new()
    self.structures=Structures.new(world)
    self.bridgeArt={piers=self.structures.piers} -- Review tools consume layout metadata only.
    self:buildRoadMeshes()
    self.terrain=TerrainMesh.new(world,{tileSize=24,spacing=terrainSpacing})
    self.visible={};self.drawTiles={};self.terrainVertices=0;self.terrainIndices=0
    local origin=spawn or world.spawn or {x=world.size*.5,z=world.size*.5}
    self.starter={x=origin.x,z=origin.z,radius=30}
    self.starterRemaining=0
    for _,tile in ipairs(self.terrain.tiles) do
        tile.starter=tileDistance(tile,origin.x,origin.z)<=self.starter.radius^2
        if tile.starter then self.starterRemaining=self.starterRemaining+1 end
        if options.priorityPath then tile.routePriority=routePriority(tile,options.priorityPath) end
    end
    table.sort(self.terrain.tiles,function(a,b)
        if options.priorityPath then
            if a.starter~=b.starter then return a.starter end
            if a.routePriority~=b.routePriority then return a.routePriority<b.routePriority end
        end
        local da,db=tileDistance(a,origin.x,origin.z),tileDistance(b,origin.x,origin.z)
        if da~=db then return da<db end
        if a.x0~=b.x0 then return a.x0<b.x0 end
        return a.z0<b.z0
    end)
    self.terrainStore=TerrainCache.store(world,terrainSpacing)
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
        local centerX,centerZ
        if site then centerX,centerZ=Bays.anchor(site) else centerX,centerZ=p.x,p.z end
        local yaw=site and site.yaw or 0
        local halfWidth=site and Bays.halfWidth(site) or Bays.HALF_WIDTH
        local nx,nz=math.cos(yaw),math.sin(yaw)
        local zx,zz=-math.sin(yaw),math.cos(yaw)
        local segment={a={x=centerX-zx*halfWidth,z=centerZ-zz*halfWidth,h=site and site.parking.h or p.h,nx=nx,nz=nz},
            b={x=centerX+zx*halfWidth,z=centerZ+zz*halfWidth,h=site and site.parking.h or p.h,nx=nx,nz=nz}}
        quad(segment,halfWidth*2+.4,.02,layers.shoulder,{.41,.39,.30},1)
        quad(segment,halfWidth*2,.04,layers.asphalt,{.23,.25,.24},1)
    end
    local sites=self.world.roads.sites and self.world.roads.sites.byId or {}
    for id,site in pairs(sites) do
        if site.localTruckParkingArea and site.localTruckApproach then
            for _,rect in ipairs({site.localTruckParkingArea,site.localTruckApproach}) do
                siteRect(site,rect,.34,.02,layers.shoulder,{.41,.39,.30})
                siteRect(site,rect,0,.04,layers.asphalt,{.23,.25,.24})
            end
            for _,rect in ipairs(site.localTruckAprons or {}) do
                siteRect(site,rect,.34,.02,layers.shoulder,{.41,.39,.30})
                siteRect(site,rect,0,.04,layers.asphalt,{.23,.25,.24})
            end
            for _,v in ipairs(require('src.commute.dock_apron_geometry').build(site))do
                layers.approach[#layers.approach+1]=v
            end
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
function Renderer:updateTireTracks(id,vehicle,world,dt,visual,vehicleKind)
    return self.tireTracks:update(id,vehicle,world or self.world,dt,visual,vehicleKind)
end
function Renderer:updateBikeParticles(entries,dt)
    self.bikeParticles:advance(dt)
    for _,entry in ipairs(entries) do
        self.bikeParticles:emit(entry.id,entry.vehicle or entry.bike,self.world,dt,
            entry.visual,entry.engine,entry.mounted,entry.vehicleKind)
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
        uncovered=t and t.total-t.completed or 0,resident=#(self.visible or {}),
        submitted=#(self.drawTiles or self.visible or {}),
        culled=math.max(0,#(self.visible or {})-#(self.drawTiles or self.visible or {})),
        starterReady=self:starterReady(),starterRemaining=self.starterRemaining or 0}
end
function Renderer:terrainCoverage(x,z)
    if not self.terrain or x<0 or z<0 or x>self.world.size or z>self.world.size then return false end
    -- Report resident ground independently of draw-list culling. Resident tiles
    -- stay available for complete map coverage and fast camera turns.
    for _,tile in ipairs(self.visible) do
        if x>=tile.x0 and x<=tile.x1 and z>=tile.z0 and z<=tile.z1 then return true end
    end
    return false
end
function Renderer:terrainDrawCoverage(x,z)
    if not self.terrain or x<0 or z<0 or x>self.world.size or z>self.world.size then return false end
    local dx,dz=x-(self.lastTerrainCameraX or 0),z-(self.lastTerrainCameraZ or 0)
    local radius=self.effectiveRadius or self.radius
    -- Beyond viewRadius the terrain shader is fully fogged to the horizon color,
    -- so the expected visible result is the background rather than a ground mesh.
    if dx*dx+dz*dz>=radius*radius then return true end
    for _,tile in ipairs(self.drawTiles or {}) do
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
function Renderer:updateTerrainDrawList(camera)
    local drawTiles=self.drawTiles or {}
    for i=#drawTiles,1,-1 do drawTiles[i]=nil end
    local centerX,centerZ=camera.centerX,camera.centerZ
    self.lastTerrainCameraX,self.lastTerrainCameraZ=centerX,centerZ
    local radius=math.max(0,self.effectiveRadius or self.radius)
    local radius2=radius*radius
    -- The ground shader has fully fogged terrain at viewRadius. A tile is
    -- omitted only when even its closest point is beyond that radius; resident
    -- meshes remain available for complete coverage checks and fast camera turns.
    for _,tile in ipairs(self.visible) do
        if tileDistance(tile,centerX,centerZ)<radius2 then
            tile.depth=camera:depth(tile.centerX,tile.centerZ,tile.height)
            drawTiles[#drawTiles+1]=tile
        end
    end
    table.sort(drawTiles,depthBefore)
    self.drawTiles=drawTiles
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
    local loadBudget=Renderer.LOAD_BUDGET_SECONDS
    if self.mobile then loadBudget=math.min(loadBudget,Renderer.MOBILE_LOAD_BUDGET_SECONDS) end
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
        until self.terrain.ready or love.timer.getTime()-started>=loadBudget
    end
    if not self.terrainCacheReady and not self.terrain.ready then
        local remaining=math.max(0,loadBudget-(love.timer.getTime()-started))
        self.terrain:step(remaining,function(tile,vertices,indices)
            if self.terrainCacheWritable then
                local okay,reason=TerrainCache.writeTile(self.terrainStore,tile,vertices,indices)
                if not okay then
                    self.terrainCacheWritable=false
                    self.terrainCacheFailure=reason
                end
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
    self.effectiveRadius=math.min(radius,require('src.video_settings').renderRadius())
    self:prepareTerrain()
    self.effectiveRadius=self:coverageRadius(camera)
    self:updateTerrainDrawList(camera)
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
    -- Coarse depth ordering is retained for submitted tiles; ground itself uses
    -- a depth buffer for occlusion within and between the larger static tiles.
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
        if self.vegetation.advanceVisible and self.vegetation:advanceVisible(
            centerX,centerZ,foliageRadius,{seconds=self.mobile and Renderer.MOBILE_VEGETATION_BUDGET_SECONDS
                or Renderer.DESKTOP_VEGETATION_BUDGET_SECONDS,clock=love.timer.getTime}) then
            -- Include the completed patch in the cached draw list next frame.
            self.visiblePropsClock=Renderer.PROPS_REFRESH_SECONDS
        end
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
    require('src.commute.headlight').send(s,camera,self.lightActor or {})
    local light=DayNight.sample(self.calendar)
    camera:send(s)
    s:send('groundDepthSpan',self:depthSpan())
    local viewRadius=self.effectiveRadius or self.radius
    s:send('viewRadius',viewRadius);s:send('detailStrength',.82)
    s:send('detailFadeStart',self.mobile and viewRadius*.42 or viewRadius*2)
    s:send('detailFadeEnd',self.mobile and viewRadius*.70 or viewRadius*3)
    s:send('cloudPhase',{t*.03,t*.023,t*.017});s:send('cloudStrength',.15)
    s:send('sunDirection',light.sunDirection);s:send('sunColor',light.sunColor)
    s:send('sunlight',light.sunlight);s:send('ambientLight',light.ambient)
    s:send('moonDirection',light.moonDirection);s:send('moonlight',light.moonlight)
    s:send('moonColor',{.58,.69,.94})
    s:send('fogColor',camera.firstPerson and light.horizon or light.sky)
    s:send('waterDetail',.85);s:send('wavePhase',{t*1.1,t*.7,t*.3});s:send('ripplePhase',{t,t*.8})
    s:send('waterView',WATER_VIEW)
    s:send('waterSunDirection',normalizedVector(light.sunDirection[1]+WATER_VIEW[1],
        light.sunDirection[2]+WATER_VIEW[2],light.sunDirection[3]+WATER_VIEW[3]))
    s:send('waterMoonDirection',normalizedVector(light.moonDirection[1]+WATER_VIEW[1],
        light.moonDirection[2]+WATER_VIEW[2],light.moonDirection[3]+WATER_VIEW[3]))
    s:send('waterRoughness',.5)
    if self.structures and self.structures.setLighting then self.structures:setLighting(light) end
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
    local foliageRadius=radius or self.effectiveRadius
    local brushRadius=math.min(foliageRadius,Renderer.MOBILE_BRUSH_RADIUS)
    local budget={maxPatches=2,seconds=self.mobile and Renderer.MOBILE_VEGETATION_BUDGET_SECONDS
        or Renderer.DESKTOP_VEGETATION_BUDGET_SECONDS,clock=love.timer.getTime}
    if self.mobile then
        budget.maxPropRadius=function(p)
            return Flora.canopy[p.kind] and foliageRadius or brushRadius
        end
    end
    local props=self.vegetation:visible(camera.centerX,camera.centerZ,foliageRadius,self.calendar,inView,budget)
    for _,p in ipairs(props) do p.scale=p.scale*Flora.scale(p);p.depth=camera:depth(p.x,p.z,p.h) end
    return props
end
-- Call during an already-presented loading screen. Interactive view switching
-- then reuses its shader, canvas and road-marking mesh without cold allocations.
function Renderer:prewarmViews()
    if self.bikeParticles then self.bikeParticles:prewarm() end
    if not self.firstPersonView then self.firstPersonView=require('src.commute.first_person_renderer').new(self) end
    return self.firstPersonView
end
function Renderer:drawOutsideActor(entry,camera,highlightStyle)
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
        setSilhouetteMode(self.outsideSpriteShader,silhouette,highlightStyle)
        setSilhouetteMode(self.outsideColorwaysShader,silhouette,highlightStyle)
        setSilhouetteMode(self.outsideBikePaintShader,silhouette,highlightStyle)
        if entry.npcCharacter then
            local characterArt=require('src.commute.npc_character_art')
            local shader=entry.characterId=='mechanic-raccoon'
                and self.outsideSpriteShader or self.outsideColorwaysShader
            shader:send('spriteDepth',spriteDepth);g.setShader(shader)
            characterArt.draw(self.characterAssets,p,entry.characterId,camera,self.world,self.clock)
        elseif entry.truck then
            self.outsideSpriteShader:send('spriteDepth',spriteDepth);g.setShader(self.outsideSpriteShader)
            self.truckArt:draw(p,camera,self.world,silhouette)
            if not silhouette then self.truckArt:drawSignals(p,camera,self.world,self.clock) end
        elseif entry.dismounting then
            self.outsideBikePaintShader:send('spriteDepth',spriteDepth);g.setShader(self.outsideBikePaintShader)
            self.bikeArt:draw(p,camera,self.world,true,entry.presentation)
            local presentation=require('src.commute.presentation')
            local rider=entry.actionActor or p
            self.outsideColorwaysShader:send('spriteDepth',spriteDepth);g.setShader(self.outsideColorwaysShader)
            presentation.world(self.characterAssets,rider,camera,self.world,
                entry.gear,entry.appearance,entry.presentation,self.clock,self.outsideColorwaysShader,
                self.outsideSpriteShader,spriteDepth,silhouette,highlightStyle)
        elseif entry.gear and not entry.gear.mounted then
            self.outsideColorwaysShader:send('spriteDepth',spriteDepth);g.setShader(self.outsideColorwaysShader)
            local presentation=require('src.commute.presentation')
            local authoredCrash=presentation.hasAuthoredCrash(entry.appearance)
                and (p.crash~=nil or entry.presentation and entry.presentation.pose=='crash')
            local x,y=camera:screen(p.x,p.z,height)
            local falling=not authoredCrash and presentation.beginFallPose(p,entry.presentation,camera,x,y)
            presentation.world(self.characterAssets,p,camera,self.world,
                entry.gear,entry.appearance,entry.presentation,self.clock,self.outsideColorwaysShader,
                self.outsideSpriteShader,spriteDepth,silhouette,highlightStyle)
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
        setSilhouetteMode(self.outsideSpriteShader,false,highlightStyle)
        setSilhouetteMode(self.outsideColorwaysShader,false,highlightStyle)
        setSilhouetteMode(self.outsideBikePaintShader,false,highlightStyle)
    end
end
function Renderer:drawTerrain(camera)
    local g=love.graphics
    g.setColor(1,1,1);g.setShader(self:shader(camera))
    for _,tile in ipairs(self.drawTiles or self.visible) do g.draw(tile.mesh) end
end
function Renderer:draw(camera,actor,actors,settings)
    camera=camera.shoulderView or camera
    if not self:starterReady() then self:drawLoading();return end
    local highlightStyle=SilhouetteStyle.resolve(settings)
    if not actors then actors={{actor=actor,localPlayer=true}} end
    self.lightActor=actor
    require('src.commute.local_lights').prepare(self,camera,actors,DayNight.sample(self.calendar).daylight)
    if camera.firstPerson then
        return self:prewarmViews():draw(self,camera,actor,actors,highlightStyle)
    end
    local g=love.graphics
    -- Reuse the prewarmed camera canvas: only one view renders at a time.
    -- Share the scene depth buffer so terrain, roads, structures and plant
    -- billboards occlude one another by their actual camera depth.
    local canvas=self:prewarmViews().canvas
    local foliageRadius=Renderer.foliageRadius(self.effectiveRadius,self.mobile)
    g.push('all');g.origin();g.setScissor();g.setShader();g.setBlendMode('alpha')
    local light=DayNight.sample(self.calendar)
    g.setCanvas({canvas,depth=true,stencil=true});g.clear(light.sky[1],light.sky[2],light.sky[3],1,0,1)
    g.setDepthMode('lequal',true);g.setMeshCullMode('none')
    self:drawTerrain(camera)
    for _,mesh in ipairs(self.roadMeshes) do g.draw(mesh) end
    self.shadows:draw(self,camera,actors,light)
    self.structures:drawOutsideDepth(camera,actor,self.effectiveRadius)
    self.structures:drawOutsidePropsDepth(camera,actor,self.effectiveRadius)
    self:drawGrass(camera,actor)
    self.tireTracks:draw(camera,self.tireTrackShader,self:depthSpan())
    local depthSpan=self:depthSpan()
    local actorX,actorY=camera:screen(actor.x,actor.z,actor.h or self.world:supportHeight(actor.x,actor.z))
    local plantMotion=self.plantMotion
    local plantMotionActive=not plantMotion.hasSway or plantMotion:hasSway()
    local viewportWidth,viewportHeight=self.viewportWidth or 1280,self.viewportHeight or 880
    -- Share depth across billboards and solid geometry so plants behind a
    -- building or actor cannot paint over it, and foreground foliage can occlude.
    g.setDepthMode('lequal',true);g.setShader(self.outsideSpriteShader)
    for _,p in ipairs(self.visibleProps or {}) do
        local x,y=camera:screen(p.x,p.z,p.h)
        local size=p.scale*camera.zoom
        local halfWidth=(128+256*PlantMotion.MAX_SWAY)*size+2
        -- Props are gathered by world radius, which is much larger than the
        -- viewport. Reject only when the full billboard (including maximum
        -- sway shear) lies beyond the scene canvas.
        if not (x+halfWidth<0 or x-halfWidth>viewportWidth
            or y+8*size<0 or y-248*size>viewportHeight) then
            local propRadius=p.foliageRadius or foliageRadius
            local fade=1-M.smooth((M.length(p.x-camera.centerX,p.z-camera.centerZ)-propRadius*.8)/(propRadius*.2))
            if Flora.canopy[p.kind] then
                if math.abs(x-actorX)<110*size+12*camera.zoom and y>actorY
                    and y-248*size<actorY then fade=fade*.22 end
            end
            self.outsideSpriteShader:send('spriteDepth',-camera:depth(p.x,p.z,p.h)/depthSpan)
            g.setColor(.91,.94,.87,fade)
            local sway=plantMotionActive and plantMotion:sway(p) or 0
            self.plantSprites:drawPlant(p,self.calendar,self.clock,x,y,size,sway)
        end
    end
    for _,entry in ipairs(actors) do self:drawOutsideActor(entry,camera,highlightStyle) end
    if self.bikeParticles then self.bikeParticles:draw(camera,self.effectiveRadius,depthSpan) end
    g.setShader();g.setDepthMode();g.setColor(.045,.075,.15,light.sceneShade)
    g.rectangle('fill',0,0,self.viewportWidth,self.viewportHeight)
    g.pop()
    -- The caller's viewport scissor is expressed in screen-space, but this
    -- canvas is composited beneath the commute view's nested transform. Reset
    -- it while drawing the full scene image, then restore it with pop('all').
    g.push('all');g.setScissor();g.setShader();g.setColor(1,1,1);g.setBlendMode('alpha','premultiplied')
    g.draw(canvas,0,0);g.pop()
    self:drawRoads(camera,true)
    -- Surface headlights are rendered in the shared terrain/structure shaders.
    g.setColor(1,1,1);g.setLineWidth(1)
end
function Renderer:release()
    if self.released then return end;self.released=true
    require('src.commute.local_lights').release(self.world)
    if self.shadows then self.shadows:release() end
    self.terrain=nil
    if self.firstPersonView then self.firstPersonView:release() end
    for _,chunk in pairs(self.chunks) do chunk.mesh:release() end
    self.chunks={};self.visible={};self.drawTiles={}
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
