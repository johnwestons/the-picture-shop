-- Large, seed-stable tall-grass fields. Dense comb sections share a root and
-- move together; static world-space meshes are bent by the vertex shader.
-- Adapted from Critter Party/src/grass_fields.lua, 2026-11-04.
local M=require('src.commute.vendor.mathx')
local Terrain=require('src.commute.vendor.terrain')
local Placement=require('src.commute.grass_placement')
local Fields={PATCH_SIZE=8,FAR_VIEW_RADIUS=32,MAX_CACHE_ENTRIES=196,MAX_MESH_BYTES=12*1024*1024,
    BUILDS_PER_FRAME=2,BUILD_SECONDS=.0025,STEPS_PER_FRAME=192,GRID=9}
Fields.__index=Fields

local FORMAT={
    {'VertexPosition','float',2},
    {'WorldHeight','float',1},
    {'GrassHeight','float',1},
    {'WindPhase','float',1},
    {'VertexColor','float',4},
}
local seasonTint={
    spring={1.00,1.10,.76},
    summer={1,1,1},
    autumn={1.38,.91,.51},
    winter={1.30,1.08,.76},
}

local function pushBlade(vertices,indices,x,z,ground,height,width,direction,lean,color,windPhase,seed,token)
    local dx,dz=math.cos(direction),math.sin(direction)
    local tangentX,tangentZ=-dz,dx
    local steps={0,.34+M.hash(seed+2467,token,89)*.12,
        .66+M.hash(seed+2473,token,97)*.17,1}
    local widths={1,.68+M.hash(seed+2489,token,101)*.28,
        .36+M.hash(seed+2503,token,103)*.30,
        .05+M.hash(seed+2521,token,107)*.18}
    local offsets={0}
    for step=2,3 do
        offsets[step]=(math.floor(M.hash(seed+2441,token,step)*3)-1)*width*.20
    end
    offsets[4]=(math.floor(M.hash(seed+2459,token,83)*3)-1)*width*.14
    local middleShade=.84+M.hash(seed+2531,token,109)*.28
    local tipShade=.92+M.hash(seed+2539,token,113)*.28
    local vertexColors={{color[1]*.66,color[2]*.72,color[3]*.60,1},
        {M.clamp(color[1]*middleShade,0,1),M.clamp(color[2]*middleShade,0,1),
            M.clamp(color[3]*middleShade,0,1),1},
        {M.clamp(color[1]*tipShade,0,1),M.clamp(color[2]*tipShade,0,1),
            M.clamp(color[3]*tipShade,0,1),1}}
    -- Three flat, tapered bands give each blade a stepped pixel-art silhouette.
    for segment=1,3 do
        local low,high=steps[segment],steps[segment+1]
        local lowWidth,highWidth=width*widths[segment],width*widths[segment+1]
        local lowX=x+dx*lean*low+tangentX*offsets[segment]
        local lowZ=z+dz*lean*low+tangentZ*offsets[segment]
        local highX=x+dx*lean*high+tangentX*offsets[segment+1]
        local highZ=z+dz*lean*high+tangentZ*offsets[segment+1]
        local lowSideX,lowSideZ=-dz*lowWidth*.5,dx*lowWidth*.5
        local highSideX,highSideZ=-dz*highWidth*.5,dx*highWidth*.5
        local lowHeight,highHeight=height*low,height*high
        local bandColor=vertexColors[segment]
        local first=#vertices+1
        vertices[first]={lowX-lowSideX,lowZ-lowSideZ,ground+lowHeight,lowHeight,
            windPhase,bandColor[1],bandColor[2],bandColor[3],bandColor[4]}
        vertices[first+1]={lowX+lowSideX,lowZ+lowSideZ,ground+lowHeight,lowHeight,
            windPhase,bandColor[1],bandColor[2],bandColor[3],bandColor[4]}
        vertices[first+2]={highX+highSideX,highZ+highSideZ,ground+highHeight,highHeight,
            windPhase,bandColor[1],bandColor[2],bandColor[3],bandColor[4]}
        vertices[first+3]={highX-highSideX,highZ-highSideZ,ground+highHeight,highHeight,
            windPhase,bandColor[1],bandColor[2],bandColor[3],bandColor[4]}
        indices[#indices+1]=first;indices[#indices+1]=first+1;indices[#indices+1]=first+2
        indices[#indices+1]=first;indices[#indices+1]=first+2;indices[#indices+1]=first+3
    end
end

local function pushCombSection(vertices,indices,x,z,ground,height,width,direction,lean,
    bladeCount,color,seed,token,windPhase,world)
    local spineColor={color[1]*.74,color[2]*.78,color[3]*.66}
    pushBlade(vertices,indices,x,z,ground,height*.14,width*1.08,direction,lean*.24,
        spineColor,windPhase,seed,token+31)
    local tangentX,tangentZ=-math.sin(direction),math.cos(direction)
    local spacing=width/bladeCount
    for blade=1,bladeCount do
        local bladeToken=token+blade*173
        local lateral=((blade-.5)/bladeCount-.5)*width
            +(M.hash(seed+2273,bladeToken,63)-.5)*spacing*.68
        local rootX=x+tangentX*lateral
        local rootZ=z+tangentZ*lateral
        local variation=M.hash(seed+2281,bladeToken,61)
        local lengthScale
        if variation<.28 then lengthScale=.32+variation*.93
        elseif variation>.82 then lengthScale=.93+(variation-.82)*1.50
        else lengthScale=.58+(variation-.28)*.73 end
        local length=height*lengthScale
        local bladeWidth=spacing*(1.05+M.hash(seed+2293,bladeToken,67)*.65)
        local directionJitter=(M.hash(seed+2309,bladeToken,69)-.5)*.06
        local individualLean=lean+(.5-M.hash(seed+2317,bladeToken,73))*.20
        local shade=.82+M.hash(seed+2333,bladeToken,71)*.40
        local bladeWindPhase=windPhase+(M.hash(seed+2347,bladeToken,79)-.5)*.38
        local bladeColor={
            M.clamp(color[1]*shade,0,1),
            M.clamp(color[2]*shade,0,1),
            M.clamp(color[3]*shade,0,1),
        }
        pushBlade(vertices,indices,rootX,rootZ,world:height(rootX,rootZ)+.018,length,bladeWidth,
            direction+directionJitter,individualLean,bladeColor,bladeWindPhase,seed,bladeToken)
    end
end

local function collectAnchors(world,x0,z0,x1,z1)
    return world.vegetation and world.vegetation:grassAnchors(x0,z0,x1,z1,coroutine.yield) or {}
end

local function anchorInfluence(x,z,anchors)
    local best=0
    for _,anchor in ipairs(anchors) do
        local distance=M.length(x-anchor.x,z-anchor.z)
        local inner,outer
        if anchor.kind=='log' then
            inner=1.0+anchor.radius*.65
            outer=4.2+anchor.radius
        else
            inner=.42+anchor.radius*.55
            outer=2.8+anchor.radius*1.2
        end
        local ring=M.smooth((distance-inner)/.55)
            *(1-M.smooth((distance-outer)/1.55))
        best=math.max(best,ring)
    end
    return best
end

local function buildPatch(world,tx,tz,key)
    local seed=world.seed or 1
    local x0,z0=tx*Fields.PATCH_SIZE,tz*Fields.PATCH_SIZE
    local centerX,centerZ=x0+Fields.PATCH_SIZE*.5,z0+Fields.PATCH_SIZE*.5
    if centerX>=world.size or centerZ>=world.size then return nil end

    local height=world:height(centerX,centerZ)
    if height<.42 then return nil end
    local _,_,_,_,centerGrassWeight=Terrain.surface(world,centerX,centerZ)

    local hx=world:height(centerX+.4,centerZ)-world:height(centerX-.4,centerZ)
    local hz=world:height(centerX,centerZ+.4)-world:height(centerX,centerZ-.4)
    local slope=math.sqrt(hx*hx+hz*hz)/.8
    if slope>.62 then return nil end

    -- World-space masks keep field edges continuous across mesh tiles. The
    -- broad mask picks meadow regions; a shorter-scale mask forms local islands.
    local fieldNoise=M.noise(seed+1807,centerX*.038,centerZ*.038)
    local fieldStrength=M.smooth((fieldNoise-.45)/.26)
    local anchors=collectAnchors(world,x0,z0,x0+Fields.PATCH_SIZE,z0+Fields.PATCH_SIZE)
    if centerGrassWeight<.06 and #anchors==0 then return nil end

    local vertices,indices,sections={},{},{}
    local spacing=Fields.PATCH_SIZE/Fields.GRID
    local bladeCount=0
    for gx=0,Fields.GRID-1 do for gz=0,Fields.GRID-1 do
        coroutine.yield()
        local roll=M.hash(seed+2053,key+gx*37,gz*53+7)
        local offsetX=.03+M.hash(seed+2063,key+gx*67,gz*79+11)*.94
        local offsetZ=.03+M.hash(seed+2081,key+gx*89,gz*97+13)*.94
        local x=x0+(gx+offsetX)*spacing
        local z=z0+(gz+offsetZ)*spacing
        local ground,localGrassWeight=Placement.sample(world,x,z)
        if ground then
            local landmark=anchorInfluence(x,z,anchors)
            local localCanopy,_,localRockiness=Terrain.habitat(world,x,z)
            localRockiness=localRockiness or 0
            local localMoisture=M.noise(seed+137,x*.105,z*.105)
            local localCommunity=world.plan and world.plan.plantCommunity
                and world.plan:plantCommunity(x,z) or nil
            local suitableCommunity=not localCommunity or localCommunity=='sunny-opening'
                or localCommunity=='shrub-edge' or localCommunity=='woodland-understory'
                or localCommunity=='river-margin'
            if suitableCommunity and localRockiness<.78
                and (localGrassWeight>.045 or landmark>.28) then
                local broadNoise=M.noise(seed+1807,x*.038,z*.038)
                local clusterNoise=M.noise(seed+2371,x*.13,z*.13)
                local fineNoise=M.noise(seed+2417,x*.43,z*.43)
                local localField=M.smooth((broadNoise-.45)/.26)
                local clusterStrength=M.smooth((clusterNoise-.42)/.26)
                local fieldCoverage=math.max(localField*clusterStrength,landmark*.82)
                local openness=M.clamp((.98-localCanopy)/.82,0,1)
                local groundFactor=M.clamp((localGrassWeight-.045)/.52,0,1)
                if landmark>.28 then
                    openness=math.max(openness,.42*landmark)
                    groundFactor=math.max(groundFactor,.46*landmark)
                end
                local fineFactor=.78+fineNoise*.44
                local communityFactor=localCommunity=='woodland-understory' and .72
                    or localCommunity=='river-margin' and .66
                    or localCommunity=='shrub-edge' and .90 or 1
                local density=M.clamp(fieldCoverage*openness*groundFactor
                    *3.4*fineFactor*communityFactor,0,.94)
                if roll<density then
                    local areaDirection=M.noise(seed+2111,x*.065,z*.065)
                    local tuftVariation=(M.hash(seed+2159,key+gx*103,gz*107+17)-.5)*.08
                    local direction=.42+(areaDirection-.5)*.70+tuftVariation
                    local sectionWidth=.92+M.hash(seed+2129,key+gx*109,gz*113+19)*.90
                    local strands=7+math.floor(M.hash(seed+2137,key+gx*127,gz*131+23)*10)
                    local token=key+gx*149+gz*157
                    local length=(.58+M.hash(seed+2161,token,37)*.78)*(.82+localMoisture*.28)*.72
                    local lean=.03+M.hash(seed+2203,token,43)*.28
                    local windPhase=M.hash(seed+2341,token,83)*math.pi*2
                    local palette={
                        .13+M.hash(seed+2213,token,47)*.18,
                        .26+M.hash(seed+2221,token,53)*.25,
                        .09+M.hash(seed+2237,token,59)*.10,
                    }
                    local firstVertex=#vertices+1
                    pushCombSection(vertices,indices,x,z,ground+.018,length,sectionWidth,
                        direction,lean,strands,palette,seed,token,windPhase,world)
                    sections[#sections+1]={x=x,z=z,h=ground,blades=strands,firstVertex=firstVertex,lastVertex=#vertices}
                    bladeCount=bladeCount+strands
                end
            end
        end
    end end
    if bladeCount==0 then return nil end
    local mesh=love.graphics.newMesh(FORMAT,vertices,'triangles','static')
    mesh:setVertexMap(indices)
    return {key=key,tx=tx,tz=tz,x0=x0,z0=z0,
        x=centerX,z=centerZ,height=height,mesh=mesh,
        bytes=#vertices*36+#indices*4,bladeCount=bladeCount,fieldStrength=fieldStrength,
        sections=sections,vertices=#vertices,indices=#indices}
end

function Fields.new(world)
    local columns=math.ceil(world.size/Fields.PATCH_SIZE)
    return setmetatable({world=world,columns=columns,cache={},cacheCount=0,
        meshBytes=0,frame=0,buildsThisFrame=0,generated=0,
        shader=love.graphics.newShader(love.filesystem.read('src/commute/perspective.glsl')..'\n'
            ..love.filesystem.read('src/commute/grass_fields.glsl'))},Fields)
end

local function cacheKey(self,tx,tz)
    return tz*self.columns+tx+1
end

function Fields:_entry(tx,tz)
    if tx<0 or tz<0 or tx>=self.columns or tz>=self.columns then return nil end
    local key=cacheKey(self,tx,tz)
    local entry=self.cache[key]
    if entry then
        entry.used=self.frame
        return entry
    end
    if self.buildsThisFrame>=Fields.BUILDS_PER_FRAME or self.stepsThisFrame>=Fields.STEPS_PER_FRAME then return nil end
    if love.timer.getTime()-self.buildStarted>=Fields.BUILD_SECONDS then return nil end
    if self.job and self.job.key~=key then return nil end
    if not self.job then
        self.job={key=key,tx=tx,tz=tz,thread=coroutine.create(function()return buildPatch(self.world,tx,tz,key)end)}
    end
    -- Yield between anchor cells and individual comb sections. A dense tile
    -- cannot monopolize an interactive frame; upload only its completed mesh.
    while self.stepsThisFrame<Fields.STEPS_PER_FRAME
        and love.timer.getTime()-self.buildStarted<Fields.BUILD_SECONDS do
        self.stepsThisFrame=self.stepsThisFrame+1
        local okay,patch=coroutine.resume(self.job.thread);assert(okay,patch)
        if coroutine.status(self.job.thread)=='dead' then
            self.job=nil;self.generated=self.generated+1;self.buildsThisFrame=self.buildsThisFrame+1
            entry={patch=patch,used=self.frame,key=key}
            self.cache[key]=entry;self.cacheCount=self.cacheCount+1
            if patch then self.meshBytes=self.meshBytes+patch.bytes end
            self:_trim();return entry
        end
    end
    return nil
end

function Fields:_trim()
    while self.cacheCount>Fields.MAX_CACHE_ENTRIES or self.meshBytes>Fields.MAX_MESH_BYTES do
        local oldest,stamp=nil,math.huge
        for key,entry in pairs(self.cache) do
            if entry.used<stamp or entry.used==stamp and (not oldest or key<oldest) then oldest,stamp=key,entry.used end
        end
        if not oldest then break end
        local entry=self.cache[oldest]
        if entry.patch then
            self.meshBytes=math.max(0,self.meshBytes-entry.patch.bytes)
            entry.patch.mesh:release()
        end
        self.cache[oldest]=nil;self.cacheCount=self.cacheCount-1
    end
end

function Fields:collect(x0,z0,x1,z1,camera,maxDistance)
    self.frame=self.frame+1;self.buildsThisFrame=0;self.stepsThisFrame=0
    self.buildStarted=love.timer.getTime()
    local maxDistance2=maxDistance and maxDistance>0 and maxDistance*maxDistance or math.huge
    local tx0=math.max(0,math.floor(x0/Fields.PATCH_SIZE))
    local tz0=math.max(0,math.floor(z0/Fields.PATCH_SIZE))
    local tx1=math.min(self.columns-1,math.floor(x1/Fields.PATCH_SIZE))
    local tz1=math.min(self.columns-1,math.floor(z1/Fields.PATCH_SIZE))
    local centerTX,centerTZ=math.floor(camera.centerX/Fields.PATCH_SIZE),math.floor(camera.centerZ/Fields.PATCH_SIZE)
    if self.job and (self.job.tx<tx0 or self.job.tx>tx1 or self.job.tz<tz0 or self.job.tz>tz1
        or ((self.job.tx+.5)*Fields.PATCH_SIZE-camera.centerX)^2
            +((self.job.tz+.5)*Fields.PATCH_SIZE-camera.centerZ)^2>maxDistance2) then self.job=nil end
    local function inRange(tx,tz)
        local x,z=(tx+.5)*Fields.PATCH_SIZE,(tz+.5)*Fields.PATCH_SIZE
        local dx,dz=x-camera.centerX,z-camera.centerZ
        return dx*dx+dz*dz<=maxDistance2
    end
    local maxRing=math.max(math.abs(tx0-centerTX),math.abs(tx1-centerTX),
        math.abs(tz0-centerTZ),math.abs(tz1-centerTZ))
    -- Build nearby tiles first and spread initialization over a few frames.
    for ring=0,maxRing do
        for dx=-ring,ring do for dz=-ring,ring do
            if math.max(math.abs(dx),math.abs(dz))==ring then
                local tx,tz=centerTX+dx,centerTZ+dz
                if tx>=tx0 and tx<=tx1 and tz>=tz0 and tz<=tz1 and inRange(tx,tz) then
                    self:_entry(tx,tz)
                    if self.buildsThisFrame>=Fields.BUILDS_PER_FRAME then break end
                end
            end
        end
        if self.buildsThisFrame>=Fields.BUILDS_PER_FRAME then break end
    end
    end
    local visible={}
    for tx=tx0,tx1 do for tz=tz0,tz1 do
        if inRange(tx,tz) then
            local entry=self.cache[cacheKey(self,tx,tz)]
            if entry then
                entry.used=self.frame
                if entry.patch then visible[#visible+1]=entry.patch end
            end
        end
    end end
    self:_trim()
    self.buildMs=(love.timer.getTime()-self.buildStarted)*1000
    self.visibleCount=#visible
    return visible
end

function Fields:prepareDraw(camera,time,season,radius,depthSpan,actor)
    camera:send(self.shader)
    self.shader:send('grassTime',time or 0)
    self.shader:send('seasonTint',seasonTint[season] or seasonTint.summer)
    self.shader:send('windStrength',1)
    self.shader:send('windDirection',{.91,.41})
    self.shader:send('grassRadius',radius or Fields.FAR_VIEW_RADIUS)
    self.shader:send('groundDepthSpan',depthSpan or 51200)
    require('src.commute.headlight').send(self.shader,camera,actor or {})
end

function Fields:stats()
    return {patches=self.cacheCount,meshBytes=self.meshBytes,generated=self.generated,
        built=self.buildsThisFrame,steps=self.stepsThisFrame or 0,pending=self.job~=nil,
        buildMs=self.buildMs or 0,visible=self.visibleCount or 0}
end

function Fields:drawPatch(patch)
    love.graphics.draw(patch.mesh)
end

function Fields:release()
    for _,entry in pairs(self.cache) do
        if entry.patch and entry.patch.mesh then entry.patch.mesh:release() end
    end
    self.cache={};self.cacheCount=0;self.meshBytes=0;self.job=nil
    if self.shader then self.shader:release();self.shader=nil end
end

return Fields
