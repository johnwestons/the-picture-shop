-- Frozen island-town terrain. Relief, rivers and habitats retain the current
-- town preset; its coast shape is seeded from Critter Party's island planner.
local M=require('src.commute.vendor.mathx')
local Config=require('src.commute.vendor.world_config')
local Inland=require('src.commute.town_terrain_v2')
local Island=require('src.commute.vendor.island_plan')
local V3={MODE='island-town-v3',COAST_SAMPLES=512,ISLAND_RADIUS=246,
    MIN_SHORE_RADIUS=221,MAX_SHORE_RADIUS=250,BOUNDS={x0=6,z0=6,x1=506,z1=506}}
local Plan={}
local function array(value,count)
    if type(value)~='table' or #value~=count then return false end
    for key in pairs(value) do if type(key)~='number' or key%1~=0 or key<1 or key>count then return false end end
    return true
end
local function q(value)return math.floor(value*1000+.5)/1000 end

function V3.shoreline(seed)
    local source=Island.new(seed,{size=512,center=256,radius=V3.ISLAND_RADIUS})
    local sourceSamples=source.coastSamples
    local mean=0
    for _,radius in ipairs(sourceSamples) do mean=mean+radius end
    mean=mean/math.max(1,#sourceSamples)
    local radii={}
    for i=1,V3.COAST_SAMPLES do
        local sample=sourceSamples[(i-1)*2+1] or 1
        local shaped=V3.ISLAND_RADIUS+M.clamp((sample/math.max(.001,mean)-1)*42,-24,4)
        radii[i]=q(M.clamp(shaped,V3.MIN_SHORE_RADIUS,V3.MAX_SHORE_RADIUS))
    end
    return radii
end

function V3.generate(seed,frame,shoreline)
    local terrain=Inland.generate(seed,frame)
    terrain.mode=V3.MODE
    terrain.shoreline=shoreline or V3.shoreline(seed)
    return terrain
end

function V3.valid(terrain)
    if type(terrain)~='table' or terrain.mode~=V3.MODE or not array(terrain.shoreline,V3.COAST_SAMPLES) then return false end
    local inland={}
    for key,value in pairs(terrain) do if key~='shoreline' then inland[key]=value end end
    inland.mode=Inland.MODE
    if not Inland.valid(inland) then return false end
    for _,radius in ipairs(terrain.shoreline) do
        if not M.finite(radius) or radius<V3.MIN_SHORE_RADIUS or radius>V3.MAX_SHORE_RADIUS then return false end
    end
    return true
end

local function shorelineBins(shoreline,config)
    local points,bins={},{}
    local c=config.center
    for i,radius in ipairs(shoreline) do
        local angle=(i-1)*math.pi*2/#shoreline
        points[i]={x=c+math.cos(angle)*radius,z=c+math.sin(angle)*radius}
    end
    local binWidth=math.ceil(config.size/64)+2
    for i,a in ipairs(points) do
        local b=points[i%#points+1]
        local segment={x=a.x,z=a.z,dx=b.x-a.x,dz=b.z-a.z,
            length2=(b.x-a.x)^2+(b.z-a.z)^2}
        for bx=math.max(0,math.floor((math.min(a.x,b.x)-48)/64)),
            math.min(math.floor(config.size/64),math.floor((math.max(a.x,b.x)+48)/64)) do
            for bz=math.max(0,math.floor((math.min(a.z,b.z)-48)/64)),
                math.min(math.floor(config.size/64),math.floor((math.max(a.z,b.z)+48)/64)) do
                local key=bz*binWidth+bx+1
                bins[key]=bins[key] or {};bins[key][#bins[key]+1]=segment
            end
        end
    end
    return points,bins,binWidth
end

local function insideRadius(shoreline,config,x,z)
    local dx,dz=x-config.center,z-config.center
    local distance=M.length(dx,dz)
    local angle=math.atan2(dz,dx)%(math.pi*2)
    local position=angle/(math.pi*2)*#shoreline
    local index=math.floor(position)
    local radius=M.lerp(shoreline[index+1],shoreline[(index+1)%#shoreline+1],position-index)
    return distance<radius
end

function V3.new(terrain,config)
    assert(V3.valid(terrain),'Invalid frozen v3 island-town terrain')
    config=config or {size=512,center=256,radius=V3.ISLAND_RADIUS}
    local inland={}
    for key,value in pairs(terrain) do if key~='shoreline' then inland[key]=value end end
    inland.mode=Inland.MODE
    local plan=Inland.new(inland,config)
    local original=getmetatable(plan).__index
    local originalRawHeight=original.rawHeight
    local originalLandHeight=original.landHeight
    local originalHabitat=original.habitat
    local originalWaterId=original.waterIdAt
    plan.townPreset=V3.MODE;plan.island=true;plan.shoreline=terrain.shoreline
    plan.shorePoints,plan.shoreBins,plan.shoreBinWidth=shorelineBins(terrain.shoreline,config)
    -- Call the captured raw-height implementation directly. The v2 height
    -- wrapper dispatches through self:rawHeight(), which would resolve back to
    -- this v3 plan and recurse after the island methods replace its metatable.
    plan.inlandHeight=function(x,z)return originalRawHeight(plan,x,z)end
    plan.inlandRawHeight=function(x,z)return originalRawHeight(plan,x,z)end
    plan.inlandLandHeight=function(x,z)return originalLandHeight(plan,x,z)end
    plan.inlandHabitat=function(x,z)return originalHabitat(plan,x,z)end
    plan.inlandWaterId=function(x,z)return originalWaterId(plan,x,z)end
    setmetatable(plan,{__index=function(self,key)return Plan[key] or original[key]end})
    plan.playableBounds={x0=V3.BOUNDS.x0,z0=V3.BOUNDS.z0,x1=V3.BOUNDS.x1,z1=V3.BOUNDS.z1}
    return plan
end

function Plan:shoreDistance(x,z)
    local c=self.config
    local inside=insideRadius(self.shoreline,c,x,z)
    local bx,bz=math.floor(x/64),math.floor(z/64)
    local list=self.shoreBins[bz*self.shoreBinWidth+bx+1]
    -- Coast segments are binned with a 48 m margin. No segment in this bin
    -- means the query is safely inland or deep offshore, so retain a distance
    -- large enough that inland hills are not flattened by the coast mask.
    local best=(self.config.size*2)^2
    if list then
        for _,segment in ipairs(list) do
            local u=segment.length2>1e-8 and M.clamp(((x-segment.x)*segment.dx+(z-segment.z)*segment.dz)/segment.length2,0,1) or 0
            local dx,dz=x-segment.x-segment.dx*u,z-segment.z-segment.dz*u
            best=math.min(best,dx*dx+dz*dz)
        end
    end
    local distance=math.sqrt(best)
    return inside and distance or -distance
end

function Plan:landHeight(x,z)
    x,z=M.clamp(x,0,self.config.size-.000001),M.clamp(z,0,self.config.size-.000001)
    local inland=self.inlandLandHeight(x,z)
    local shore=self:shoreDistance(x,z)*.28
    return M.clamp(math.min(inland,shore),-1.2,Config.HEIGHT_LIMIT)
end

function Plan:rawHeight(x,z)
    return self:height(x,z)
end

function Plan:height(x,z)
    if x<0 or z<0 or x>=self.config.size or z>=self.config.size then return -1.2 end
    return math.max(-1.2,math.min(self.inlandHeight(x,z),self:shoreDistance(x,z)*.28))
end

function Plan:waterIdAt(x,z)
    local id=self.inlandWaterId(x,z)
    if id then return id end
    if self:shoreDistance(x,z)<=0 and self:height(x,z)<.04 then return 'ocean' end
end

function Plan:habitat(x,z)
    if self:shoreDistance(x,z)<=0 then return 0,0,0 end
    return self.inlandHabitat(x,z)
end

return V3
