-- A fixed, bounded view of the real loading apron. It owns no simulation and
-- never instantiates the full terrain/grass/structure renderer.
local Camera=require('src.commute.camera')
local Ground=require('src.commute.ground_textures')
local Surface=require('src.commute.vendor.terrain')
local Loader=require('src.image_loader')
local Traffic=require('src.commute.delivery_traffic')
local ActorArt=require('src.dock_actor_art')
local Weather=require('src.outdoor_weather')
local Programs=require('src.dock_shaders')
local View={SIZE=256,DEPTH=16,HALF_WIDTH=9,REFRESH=1/24,ROWS=12,COLUMNS=16,MAX_ACTORS=24}
View.__index=View
local function copy(p)local out={};for k,v in pairs(p or {})do out[k]=v end;return out end
function View.new(town,context)
    return setmetatable({town=town,context=context,stage='world',strips={},structures={},row=0,samples={},
        actorArt=ActorArt.new(),admitted={},fades={},pending={},
        stats={renders=0,steps=0,rows=0,actorCount=0,vertices=0,maxStepMs=0,maxRenderMs=0},lastRender=-math.huge},View)
end
function View:inside(p,padding)
    if not p or type(p.x)~='number' or type(p.z)~='number' or not self.site then return false end
    local x,z=self.site:toLocal(p.x,p.z)
    local forward=(x-self.dockX)*self.site.scale.x
    local side=z*self.site.scale.z
    padding=padding or 0
    return forward>=-padding and forward<=View.DEPTH+padding and math.abs(side)<=View.HALF_WIDTH+padding
end
function View:worldPoint(forward,side)
    return self.site:toWorld(self.dockX+forward/self.site.scale.x,side/self.site.scale.z,0)
end
function View:crosses(a,b,padding)
    local ax,az=self.site:toLocal(a.x,a.z);local bx,bz=self.site:toLocal(b.x,b.z)
    ax,bx=(ax-self.dockX)*self.site.scale.x,(bx-self.dockX)*self.site.scale.x
    az,bz=az*self.site.scale.z,bz*self.site.scale.z
    local lo,hi=0,1;padding=padding or 0
    local function axis(start,finish,minimum,maximum)
        local delta=finish-start
        if math.abs(delta)<.000001 then return start>=minimum and start<=maximum end
        local first,last=(minimum-start)/delta,(maximum-start)/delta
        if first>last then first,last=last,first end
        lo,hi=math.max(lo,first),math.min(hi,last);return lo<=hi
    end
    return axis(ax,bx,-padding,View.DEPTH+padding)
        and axis(az,bz,-View.HALF_WIDTH-padding,View.HALF_WIDTH+padding)
end
local function setup(self,world)
    self.preparation=nil
    self.world=world;self.site=world.sites and world.sites.byId.warehouse
    if not self.site then self.error='No warehouse exterior placement';return end
    self.dockX=self.site.localFoundation.maxX
    local x,z,h=self:worldPoint(8.5,0)
    self.camera=Camera.new({x=x,z=z,h=h},world)
    self.camera:setViewport(View.SIZE,View.SIZE)
    self.camera.yaw=-90-math.deg(self.site.yaw);self.camera.tilt=42
    self.camera.zoom=.62;self.camera.targetZoom=.62
    self.camera.focusHeight=self.site.h
    self.depthSpan=math.max(1,(world.size or 512)*100+(world.maxHeight or 84)*100)
    self.stage='canvas'
end
function View:sample(row,column)
    local forward=row/View.ROWS*View.DEPTH
    local side=-View.HALF_WIDTH+column/View.COLUMNS*View.HALF_WIDTH*2
    local x,z=self:worldPoint(forward,side)
    local h,kind=self.world:supportHeight(x,z)
    local r,g,b,_,gw,dw,lw,coverage,gv,sv,lv=Surface.surface(self.world,x,z,{height=h,slope=0})
    if self.site:hardscapeDistance(x,z)<=.05 or kind=='road' or kind=='bridge' then
        r,g,b,gw,dw,lw,coverage=.23,.25,.24,0,0,0,0
    elseif kind=='sidewalk' then r,g,b,gw,dw,lw,coverage=.56,.54,.47,0,0,0,0 end
    return {x,z,h,0,1,0,(x-self.site.x)/4,(z-self.site.z)/4,
        (x-self.site.x)/4,(z-self.site.z)/4,(self.site.x/4)%2,(self.site.z/4)%2,
        r,g,b,1,gw,dw,lw,coverage,gv,sv,lv,-h}
end
function View:buildRow()
    local row=self.row
    for _,r in ipairs({row,row+1})do
        if not self.samples[r] then
            local values={};for column=0,View.COLUMNS do values[column]=self:sample(r,column)end
            self.samples[r]=values
        end
    end
    local vertices={}
    for column=0,View.COLUMNS-1 do
        local a,b=self.samples[row][column],self.samples[row+1][column]
        local c,d=self.samples[row][column+1],self.samples[row+1][column+1]
        for _,v in ipairs({a,b,c,d,c,b})do vertices[#vertices+1]=v end
    end
    self.strips[#self.strips+1]=love.graphics.newMesh(Ground.FORMAT,vertices,'triangles','static')
    self.samples[row]=nil;self.row=row+1
    self.stats.rows=self.row;self.stats.vertices=self.stats.vertices+#vertices
    if self.row>=View.ROWS then self.stage='paint';self.samples={}end
end
function View:step(context)
    if self.error or self.stage=='ready' then return end
    self.context=context or self.context
    local started=love.timer.getTime();local phase=self.stage
    if phase=='world'then self.worldStep=(self.worldStep or 0)+1;phase=phase..self.worldStep end
    self.stats.steps=self.stats.steps+1
    if self.stage=='world' then
        local existing=self.context and self.context._commute and self.context._commute.world
        if not existing or existing.townId~=self.town.id then existing=Traffic.cachedWorld(self.town)end
        if existing and existing.townId==self.town.id then setup(self,existing)
        else
            self.preparation=self.preparation or require('src.commute.town').beginWorld(self.town)
            local okay,result=coroutine.resume(self.preparation)
            if not okay then self.error=tostring(result);self.stats.error=self.error
            elseif coroutine.status(self.preparation)=='dead' then setup(self,result);self.preparation=nil end
        end
    elseif self.stage=='canvas' then
        self.canvas=love.graphics.newCanvas(View.SIZE,View.SIZE,{dpiscale=1})
        self.canvas:setFilter('linear','linear')
        local programs=Programs.prepare()
        self.spriteShader,self.structureShader=programs.sprite,programs.structure
        self.stage='ground'
    elseif self.stage=='ground' then
        self.ground=Ground.new({mobile=true,shader=Programs.prepare().ground});self.stage='terrain'
    elseif self.stage=='terrain' then self:buildRow()
    elseif self.stage=='paint' then
        -- Reuse the exact parking/road paint builder on a restricted set of
        -- segments/sites. No town-wide road or structure meshes are created.
        local roads=self.world.roads
        local localRoads={segments={},paths={},destinations={warehouse=roads.destinations.warehouse},
            sites={byId={warehouse=self.site}}}
        for _,segment in ipairs(roads.segments)do
            if self:crosses(segment.a,segment.b,6) then
                localRoads.segments[#localRoads.segments+1]=segment
            end
        end
        for _,path in ipairs(roads.paths or {})do
            for index=2,#path.points do
                if self:crosses(path.points[index-1],path.points[index],6)then
                    localRoads.paths[#localRoads.paths+1]=path;break
                end
            end
        end
        self.localInfrastructure={fixtures={},walks={},rails={}}
        for _,f in ipairs(self.world.infrastructure and self.world.infrastructure.fixtures or {})do
            if self:inside(f,2)then table.insert(self.localInfrastructure.fixtures,f)end
        end
        for _,walk in ipairs(self.world.infrastructure and self.world.infrastructure.walks or {})do
            if self:inside(walk,6)then table.insert(self.localInfrastructure.walks,walk)end
        end
        for _,rail in ipairs(self.world.infrastructure and self.world.infrastructure.rails or {})do
            if self:crosses({x=rail.ax,z=rail.az},{x=rail.bx,z=rail.bz},1)then
                table.insert(self.localInfrastructure.rails,rail)
            end
        end
        local world=setmetatable({roads=localRoads,infrastructure=self.localInfrastructure},{__index=self.world})
        world.supportHeight=function(_,x,z)return self.world:supportHeight(x,z)end
        local vertices=require('src.commute.road_markings').build(world)
        for _,v in ipairs(require('src.commute.dock_apron_geometry').build(self.site))do vertices[#vertices+1]=v end
        if #vertices>0 then self.paint=love.graphics.newMesh(Ground.FORMAT,vertices,'triangles','static')end
        self.stage='props';self.siteIndex=1;self.structures={}
    elseif self.stage=='props' then
        local site=self.world.sites.all[self.siteIndex]
        self.siteIndex=self.siteIndex+1
        if not site then
            self.stage='fixtures';self.fixtureIndex=1;self.fixtureItems={}
            for _,kind in ipairs({'walks','rails','fixtures'})do
                for _,item in ipairs(self.localInfrastructure[kind])do
                    table.insert(self.fixtureItems,{kind=kind,item=item})
                end
            end
        elseif site~=self.site and self:inside({x=site.x,z=site.z},math.max(site.design.width,site.design.depth)) then
            local model=require('src.commute.structure_geometry').build(site)
            local format=require('src.commute.structures').FORMAT
            self.structures[#self.structures+1]=love.graphics.newMesh(format,model.vertices,'triangles','static')
        end
    elseif self.stage=='fixtures' then
        local entry=self.fixtureItems[self.fixtureIndex];self.fixtureIndex=self.fixtureIndex+1
        if not entry then self.fixtureItems=nil;self.localInfrastructure=nil;self.stage='plants'
        else
            local plan={fixtures={},walks={},rails={}};plan[entry.kind]={entry.item}
            for _,model in ipairs(require('src.commute.infrastructure_geometry').build(plan))do
                self.structures[#self.structures+1]=love.graphics.newMesh(require('src.commute.structures').FORMAT,
                    model.vertices,'triangles','static')
            end
        end
    elseif self.stage=='plants' then
        self.vegetation=self.world.vegetation or require('src.commute.vegetation').new(self.world)
        self.plants=require('src.commute.vendor.plant_sprites').new({mobile=true})
        self.props={};self.propRefresh=0;self.stage='ready'
    end
    self.stats.maxStepMs=math.max(self.stats.maxStepMs,(love.timer.getTime()-started)*1000)
    self.stats.phaseMs=self.stats.phaseMs or {}
    self.stats.phaseMs[phase]=math.max(self.stats.phaseMs[phase] or 0,(love.timer.getTime()-started)*1000)
end
function View:collect(state,players,warehouseTruck)
    local result,seen={},{}
    local function add(entry)
        local p=entry.actor
        if not self:inside(p,entry.truck and 4 or 1)then return end
        if entry.phase=='offmap' or entry.phase=='city' then return end
        -- The detailed rear cargo view is the same truck, not an extra vehicle.
        if entry.truck and warehouseTruck and warehouseTruck:isVisible() then
            local dock=self.site.truckParking
            if entry.shipmentId==warehouseTruck.jobId
                or entry.phase=='at_bay' and dock and (p.x-dock.x)^2+(p.z-dock.z)^2<4 then return end
        end
        local key=entry.id or p.trafficId or tostring(p)
        if seen[key]then return end;seen[key]=true
        if #result<View.MAX_ACTORS then result[#result+1]=entry end
    end
    for _,entry in ipairs(Traffic.physicalActors(state))do add(entry)end
    local trip=state.home and state.home.commute
    for _,agent in ipairs(trip and trip.aiMotorcycles or {})do
        if agent.bike then add({id='ai:'..agent.id,actor=agent.bike,bike=true})end
    end
    local playersById={};for _,p in ipairs(players or {})do playersById[p.id]=p end
    for id,part in pairs(trip and trip.participants or {})do
        local player=playersById[part.slot]
        local r=require('src.commute.runtime').visualRider(part,player,trip.token)
        if r then
            if r.bike and (not r.gear.mounted or part.interior or part.arrived)then
                add({id='bike:'..id,actor=r.bike,bike=true,bikeOnly=true})
            end
            if not part.interior and not part.arrived and (not player or player.sceneId=='commute') then
                local actor=r.vehicle=='truck' and r.truck or r.gear.mounted and r.bike or r.ped
                actor=copy(actor)
                -- visualRider already resolves the realtime/interpolated pose,
                -- including heading and walk distance. Keep that presentation.
                add({id='player:'..id,actor=actor,truck=r.vehicle=='truck',bike=r.gear.mounted and r.vehicle~='truck',
                    gear=r.gear,appearance=part.appearance or player or {},presentation=part.presentation})
            end
        end
    end
    local company=state.employment and state.employment.companyTruck
    for _,key in ipairs({'truck','keiTruck'})do
        local truck=trip and trip[key]
        local away=company and company.deliveryRun and (company.vehicleModel=='kei' and key=='keiTruck'
            or company.vehicleModel~='kei' and key=='truck')
        if truck and not truck.driver and not away then add({id='parked:'..key,actor=truck,truck=true})end
    end
    table.sort(result,function(a,b)return self.camera:depth(a.actor.x,a.actor.z,a.actor.h or self.site.h)
        <self.camera:depth(b.actor.x,b.actor.z,b.actor.h or self.site.h)end)
    self.stats.actorCount=#result
    self.visibleCharacters={}
    local live={}
    for _,entry in ipairs(result)do
        live[entry.id]=true
        if not entry.truck and not entry.bike then
            local character=entry.appearance and entry.appearance.character or 'rabbit-worker'
            self.visibleCharacters[character]=true
            if entry.gear and entry.gear.outfit=='geared' then self.visibleCharacters['suited-rider']=true end
        end
    end
    for id in pairs(self.admitted)do if not live[id]then self.admitted[id]=nil;self.fades[id]=nil end end
    return result
end
function View:prepareProps(state,now)
    if not self.plants then return end
    if now>=(self.propRefresh or 0)then
        local x,z=self:worldPoint(7.5,0)
        local props=self.vegetation:visible(x,z,12,state.calendar,
            function(px,pz,padding)return self:inside({x=px,z=pz},math.min(2,padding or 0))end,
            {maxPatches=1,seconds=.0005,clock=love.timer.getTime})
        table.sort(props,function(a,b)return (a.x-x)^2+(a.z-z)^2<(b.x-x)^2+(b.z-z)^2 end)
        self.props={}
        for _,p in ipairs(props)do
            if #self.props>=12 then break end
            p.scale=p.scale*require('src.commute.flora').scale(p)
            self.props[#self.props+1]=p
        end
        self.propRefresh=now+.25
    end
    local used=false
    local budget={canUpload=function()return not used end,claim=function()used=true;return true end}
    self.plants:prepare(self.props,state.calendar,0,nil,nil,budget)
    self.stats.propCount=#self.props
end
function View:shade(state)
    local daylight,raining=Weather.sample(state);local s=self.ground.shader
    self.camera:send(s);self:clipShader(s);s:send('groundDepthSpan',self.depthSpan)
    s:send('viewRadius',30);s:send('detailStrength',.78)
    s:send('detailFadeStart',28);s:send('detailFadeEnd',35)
    s:send('sunlight',daylight*.45);s:send('ambientLight',.16+daylight*.49)
    s:send('sunColor',{1,.86,.66});s:send('cloudStrength',raining and .2 or .05)
    s:send('seasonTint',{1,1,1});s:send('waterDetail',0)
    return daylight,raining
end
function View:clipShader(shader)
    local x,z=self:worldPoint(0,0)
    shader:send('dockOriginDelta',{x-self.camera.centerX,z-self.camera.centerZ})
    shader:send('dockForward',{math.cos(self.site.yaw),math.sin(self.site.yaw)})
    shader:send('dockExtent',{View.DEPTH,View.HALF_WIDTH})
end
function View:render(state,characters,players,warehouseTruck)
    if not self.canvas or not self.ground or #self.strips==0 then return false end
    local now=love.timer.getTime()
    if now-self.lastRender<View.REFRESH then return true end
    local started=now;self.lastRender=now;self.actorArt:beginRefresh()
    local g=love.graphics
    -- A single atlas is decoded and uploaded through the bounded shared loader.
    if not self.ground.ready then
        local path=self.ground.atlasPath;self.pending[path]=true
        local image,reason=Loader.load(path)
        if image then
            self.pending[path]=nil;image:setFilter('linear','linear');image:setWrap('clamp','clamp')
            self.ground.atlas:release();self.ground.atlas=image;self.ground.images.atlas=image
            self.ground.shader:send('materialAtlas',image);self.ground.ready=true
        elseif reason~='pending' then self.pending[path]=nil end
    end
    local actors=self:collect(state,players,warehouseTruck)
    self:prepareProps(state,now)
    g.push('all');g.origin();g.setScissor();g.setShader();g.setBlendMode('alpha')
    g.setCanvas({self.canvas,depth=true})
    local day,rain=self:shade(state)
    self.stats.daylight,self.stats.raining=day,rain
    g.clear(.12+.20*day,.17+.25*day,.23+.27*day,1,0,1)
    g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setShader(self.ground.shader)
    g.setColor(1,1,1,1)
    for _,mesh in ipairs(self.strips)do g.draw(mesh)end
    if self.paint then g.draw(self.paint)end
    if #self.structures>0 then
        self.camera:send(self.structureShader)
        self:clipShader(self.structureShader)
        self.structureShader:send('groundDepthSpan',self.depthSpan);self.structureShader:send('structureRadius',28)
        g.setShader(self.structureShader)
        g.setColor(.25+.75*day,.30+.70*day,.42+.58*day,1)
        for _,mesh in ipairs(self.structures)do g.draw(mesh)end
    end
    if self.plants then
        self.propAdmission=self.propAdmission or {}
        local admitted=false
        for _,p in ipairs(self.props)do
            if not self.propAdmission[p.id] and not admitted then self.propAdmission[p.id]=now;admitted=true end
            if self.propAdmission[p.id] then
                self.spriteShader:send('spriteDepth',-self.camera:depth(p.x,p.z,p.h)/self.depthSpan)
                self.spriteShader:send('furEnabled',0);self.spriteShader:send('overallsEnabled',0)
                self.spriteShader:send('exteriorTint',{.25+.75*day,.30+.70*day,.42+.58*day})
                self.spriteShader:send('exteriorOpacity',math.min(1,(now-self.propAdmission[p.id])/.2))
                g.setShader(self.spriteShader)
                local x,y=self.camera:screen(p.x,p.z,p.h)
                self.plants:drawPlant(p,state.calendar,0,x,y,p.scale*self.camera.zoom,0)
            end
        end
    end
    local admitted=false
    for _,entry in ipairs(actors)do
        local id=entry.id
        if not self.admitted[id] and not admitted then self.admitted[id]=true;admitted=true end
        if self.admitted[id] then
            local p=entry.actor;local h=p.h or self.world:supportHeight(p.x,p.z)
            -- Bias vehicle depth to its near tire line, using the same physical
            -- footprint as the road renderer so the ground cannot erase wheels.
            local depthH=h+.06
            if entry.truck then
                local art=require('src.commute.truck_art')
                depthH=h+art.groundedDepthBias(art,p,self.camera,h,self.world)+.055
            elseif entry.bike then
                local art=require('src.commute.bike_art')
                depthH=h+art.groundedDepthBias(art,p,self.camera,h,entry.presentation)+.055
            end
            self.spriteShader:send('spriteDepth',-self.camera:depth(p.x,p.z,depthH)/self.depthSpan)
            self.spriteShader:send('furEnabled',0);self.spriteShader:send('overallsEnabled',0)
            self.spriteShader:send('exteriorTint',{.25+.75*day,.30+.70*day,.42+.58*day})
            self.spriteShader:send('exteriorOpacity',self.fades[id] and math.min(1,(now-self.fades[id])/.18) or 0)
            g.setShader(self.spriteShader)
            local ready
            if entry.truck or entry.bike then ready=self.actorArt:vehicle(entry,self.camera,self.world)
            elseif characters then
                ready=self.actorArt:person(entry,self.camera,self.world,characters,now)
            end
            if ready and not self.fades[id]then self.fades[id]=now end
        end
    end
    if rain then
        g.setShader();g.setDepthMode();g.setColor(.70,.82,.91,.30);g.setLineWidth(.75)
        for index=1,10 do
            local x=(index*37+now*9)%View.SIZE;local y=(index*53+now*90)%View.SIZE
            g.line(x,y,x-2,y+6)
        end
    end
    g.pop()
    self.stats.renders=self.stats.renders+1
    self.stats.actorTextureBytes=self.actorArt.bytes
    self.stats.plantTextureBytes=self.plants and self.plants.bytes or 0
    self.stats.maxRenderMs=math.max(self.stats.maxRenderMs,(love.timer.getTime()-started)*1000)
    return true
end
function View:draw(a)
    if not self.canvas or self.stats.renders==0 or self.row<View.ROWS then return false end
    local now=love.timer.getTime();self.presentedAt=self.presentedAt or now
    local vertices={}
    for _,index in ipairs({1,2,3,1,3,4})do
        local uv=({{0,0},{1,0},{1,1},{0,1}})[index];local p=a[index]
        vertices[#vertices+1]={p.x,p.y,uv[1],uv[2],1,1,1,1}
    end
    if not self.mesh then self.mesh=love.graphics.newMesh(vertices,'triangles','dynamic')
    else self.mesh:setVertices(vertices)end
    self.mesh:setTexture(self.canvas)
    love.graphics.setColor(1,1,1,math.min(1,(now-self.presentedAt)/.25));love.graphics.draw(self.mesh)
    return true
end
function View:pause()
    self.actorArt:pause()
    for path in pairs(self.pending)do Loader.cancel(path)end;self.pending={}
    if self.plants then
        for path in pairs(self.plants.requests)do Loader.cancel(path)end;self.plants.requests={}
    end
end
function View:release()
    self:pause();self.actorArt:release()
    for _,mesh in ipairs(self.strips)do mesh:release()end
    for _,mesh in ipairs(self.structures or {})do mesh:release()end
    for _,name in ipairs({'canvas','mesh','paint'})do
        if self[name]then self[name]:release()end
    end
    if self.ground then self.ground:release()end
    if self.plants then self.plants:release()end
end
return View
