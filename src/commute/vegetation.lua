-- Deterministic, patch-streamed town foliage adapted from Critter Party's
-- stable candidate IDs and habitat-weighted plant placement.
local M=require('src.commute.vendor.mathx')
local Candidates=require('src.commute.vendor.plant_candidates')
local Flora=require('src.commute.flora')
local Obstacles=require('src.commute.obstacles')
local Vegetation={};Vegetation.__index=Vegetation

local PATCH_SIZE=16
local CELL_SIZE=4
local MAX_PATCHES=256

local function countKeys(t)
    local n=0;for _ in pairs(t) do n=n+1 end;return n
end
local function presentedCopy(self,source,calendar,day)
    if source._presentationDay~=day then
        local value=Flora.present({id=source.id,kind=source.kind,x=source.x,z=source.z,
            h=source.h,scale=source.scale},self.seed,calendar)
        source._presentationDay=day
        source._presentationAge=value.age
        source._presentationPlantAge=value.plantAge
        source._presentationLifePhase=value.lifePhase
        source._presentationPhaseAge=value.phaseAge
        source._presentationAmount=value.amount
        source._presentationBiteAge=value.biteAge
        source._presentationEdible=value.edible
        source._presentationVigor=value.vigor
        source._presentationDrySite=value.drySite
        source._presentationVariant=value.visualVariant
    end
    return {id=source.id,kind=source.kind,x=source.x,z=source.z,h=source.h,scale=source.scale,
        age=source._presentationAge,plantAge=source._presentationPlantAge,
        lifePhase=source._presentationLifePhase,phaseAge=source._presentationPhaseAge,
        amount=source._presentationAmount,biteAge=source._presentationBiteAge,
        edible=source._presentationEdible,vigor=source._presentationVigor,
        drySite=source._presentationDrySite,visualVariant=source._presentationVariant}
end

local function insideBounds(world,x,z)
    local bounds=world.playableBounds
    if not bounds then return x>=0 and z>=0 and x<world.size and z<world.size end
    return x>=bounds.x0 and z>=bounds.z0 and x<=bounds.x1 and z<=bounds.z1
end

local function allowed(self,x,z,p)
    local world=self.world
    if not insideBounds(world,x,z) then return nil end
    if world.spawn and M.length(x-world.spawn.x,z-world.spawn.z)<6 then return nil end
    local h=world:height(x,z)
    if not M.finite(h) or h<=.4 then return nil end
    p.h=h
    if world.roads and world.roads.vegetationAllowed then
        local obstacleRadius=Obstacles.solidKind(p.kind) and Obstacles.shape(p,self.seed,nil) or nil
        if not world.roads:vegetationAllowed(x,z,obstacleRadius) then return nil end
    end
    return h
end

function Vegetation.new(world)
    assert(type(world)=='table' and type(world.height)=='function','vegetation needs a terrain world')
    local size=world.size or 512
    return setmetatable({world=world,seed=world.seed or 4261,size=size,
        patchSize=PATCH_SIZE,cellSize=CELL_SIZE,maxPatches=MAX_PATCHES,
        propWidth=math.ceil(size/CELL_SIZE),plan=world.plan,spawn=world.spawn,
        cellCount=math.ceil(size/CELL_SIZE),patchCount=math.ceil(size/PATCH_SIZE),
        _patches={},_tick=0,_generated=0},Vegetation)
end

function Vegetation:_makePatch(px,pz,yieldStep)
    local props={}
    local function add(p)
        if not p then return end
        local s=self.plan and self.plan.settings
        if s and p.kind~='rock' and p.kind~='stone' then
            local level=Flora.canopy[p.kind] and s.trees or s.brush
            local density=({0,.16,.52,1})[level]
            if s.excluded[p.kind] or M.hash(self.seed,p.id,397)>=density then return end
        end
        local height=allowed(self,p.x,p.z,p)
        if height then p.h=height;props[#props+1]=p end
    end
    local firstX,firstZ=px*(PATCH_SIZE/CELL_SIZE),pz*(PATCH_SIZE/CELL_SIZE)
    for iz=firstZ,math.min(self.cellCount-1,firstZ+PATCH_SIZE/CELL_SIZE-1) do
        for ix=firstX,math.min(self.cellCount-1,firstX+PATCH_SIZE/CELL_SIZE-1) do
            for slot=1,2 do
                add(Candidates.candidate(self,ix,iz,slot))
            end
            for slot=1,3 do add(Candidates.extraCandidate(self,ix,iz,slot)) end
            for slot=1,5 do add(Candidates.extraCandidate2(self,ix,iz,slot)) end
            for slot=1,8 do add(Candidates.extraCandidate3(self,ix,iz,slot)) end
            for slot=1,4 do add(Candidates.extraCandidate4(self,ix,iz,slot)) end
            if yieldStep then yieldStep() end
        end
    end
    table.sort(props,function(a,b) return a.id<b.id end)
    return props
end

function Vegetation:_evictIfNeeded()
    while countKeys(self._patches)>self.maxPatches do
        local oldestKey,oldest
        for key,patch in pairs(self._patches) do
            if not oldest or patch.used<oldest.used
                or (patch.used==oldest.used and key<oldestKey) then
                oldestKey,oldest=key,patch
            end
        end
        self._patches[oldestKey]=nil
    end
end

function Vegetation:_getPatch(px,pz)
    local key=px..':'..pz
    self._tick=self._tick+1
    local patch=self._patches[key]
    if patch then
        patch.used=self._tick
        return patch
    end
    if self._visibleJob and self._visibleJob.key==key then self._visibleJob=nil end
    patch={props=self:_makePatch(px,pz),used=self._tick}
    self._patches[key]=patch
    self._generated=self._generated+1
    self:_evictIfNeeded()
    return patch
end
function Vegetation:_resumeVisibleJob(maxSteps,clock,deadline)
    local job=self._visibleJob
    if not job then return false,0 end
    local steps=0
    while steps<(maxSteps or math.huge) and (not deadline or clock()<deadline) do
        local okay,props=coroutine.resume(job.thread)
        if not okay then self._visibleJob=nil;error(props) end
        steps=steps+1
        if coroutine.status(job.thread)=='dead' then
            if self._patches[job.key] then
                self._visibleJob=nil
                return false,steps
            end
            self._tick=self._tick+1
            self._patches[job.key]={props=props,used=self._tick}
            self._generated=self._generated+1
            self._visibleJob=nil
            self:_evictIfNeeded()
            return true,steps
        end
    end
    return false,steps
end
function Vegetation:advanceVisible(cx,cz,radius,budget)
    local job=self._visibleJob
    if not job then return false end
    local x0,z0=job.px*PATCH_SIZE,job.pz*PATCH_SIZE
    local x1,z1=math.min(self.size,x0+PATCH_SIZE),math.min(self.size,z0+PATCH_SIZE)
    local nearestX,nearestZ=M.clamp(cx,x0,x1),M.clamp(cz,z0,z1)
    if (nearestX-cx)^2+(nearestZ-cz)^2>radius*radius then
        self._visibleJob=nil
        return false
    end
    local clock=budget and budget.clock
    local started=clock and clock() or 0
    local deadline=clock and started+(budget.seconds or math.huge) or nil
    local completed=self:_resumeVisibleJob(budget and budget.maxSteps or 128,clock,deadline)
    if completed then
        self.pending=math.max(0,(self.pending or 0)-1)
        self.lastBuilt=(self.lastBuilt or 0)+1
    end
    return completed
end

function Vegetation:visible(cx,cz,radius,calendar,visible,budget)
    local result={}
    if not M.finite(cx) or not M.finite(cz) or not M.finite(radius) then return result end
    radius=math.max(0,radius)
    local radius2=radius*radius
    local minX=math.max(0,math.floor((cx-radius)/PATCH_SIZE))
    local maxX=math.min(self.patchCount-1,math.floor((cx+radius)/PATCH_SIZE))
    local minZ=math.max(0,math.floor((cz-radius)/PATCH_SIZE))
    local maxZ=math.min(self.patchCount-1,math.floor((cz+radius)/PATCH_SIZE))
    local presentationDay=calendar and calendar.totalDays or 0
    local needed={}
    for pz=minZ,maxZ do
        for px=minX,maxX do
            local x0,z0=px*PATCH_SIZE,pz*PATCH_SIZE
            local x1,z1=math.min(self.size,x0+PATCH_SIZE),math.min(self.size,z0+PATCH_SIZE)
            local nearestX=M.clamp(cx,x0,x1)
            local nearestZ=M.clamp(cz,z0,z1)
            if (nearestX-cx)^2+(nearestZ-cz)^2<=radius2
                and (not visible or visible((x0+x1)*.5,(z0+z1)*.5,24)) then
                needed[#needed+1]={px=px,pz=pz,distance=((x0+x1)*.5-cx)^2+((z0+z1)*.5-cz)^2}
            end
        end
    end
    -- A new view can request over a hundred patches. Generate nearby scenery
    -- first and carry the remaining work to later frames instead of blocking
    -- input while every candidate in the entire radius is sampled at once.
    table.sort(needed,function(a,b)
        if a.distance~=b.distance then return a.distance<b.distance end
        if a.pz~=b.pz then return a.pz<b.pz end
        return a.px<b.px
    end)
    local built,pending=0,0
    if budget then
        local neededKeys={}
        for _,entry in ipairs(needed) do neededKeys[entry.px..':'..entry.pz]=true end
        if self._visibleJob and not neededKeys[self._visibleJob.key] then self._visibleJob=nil end
        local clock=budget.clock
        local started=clock and clock() or 0
        local deadline=clock and started+(budget.seconds or math.huge) or nil
        local maxPatches=budget.maxPatches or math.huge
        local steps,maxSteps=0,budget.maxSteps or 128
        local function withinBudget()
            return built<maxPatches and steps<maxSteps and (not deadline or clock()<deadline)
        end
        while withinBudget() do
            local job=self._visibleJob
            if not job then
                local nextEntry
                for _,entry in ipairs(needed) do
                    if not self._patches[entry.px..':'..entry.pz] then nextEntry=entry;break end
                end
                if not nextEntry then break end
                local px,pz=nextEntry.px,nextEntry.pz
                local key=px..':'..pz
                job={key=key,px=px,pz=pz,thread=coroutine.create(function()
                    return self:_makePatch(px,pz,function() coroutine.yield() end)
                end)}
                self._visibleJob=job
            end
            if self._patches[job.key] then
                self._visibleJob=nil
            else
                local completed,used=self:_resumeVisibleJob(maxSteps-steps,clock,deadline)
                steps=steps+used
                if completed then built=built+1 else break end
            end
        end
    end
    for _,entry in ipairs(needed) do
        local key=entry.px..':'..entry.pz
        local patch=self._patches[key]
        if patch or not budget then
            if not patch then patch=self:_getPatch(entry.px,entry.pz)
            else self._tick=self._tick+1;patch.used=self._tick end
            for _,p in ipairs(patch.props) do
                local dx,dz=p.x-cx,p.z-cz
                local propRadius=radius
                if budget and budget.maxPropRadius then
                    propRadius=math.max(0,math.min(radius,budget.maxPropRadius(p) or radius))
                end
                if dx*dx+dz*dz<=propRadius*propRadius and (not visible or visible(p.x,p.z,12)) then
                    -- Renderer props add view depth and scale in place; hand
                    -- a copy so cached day-state stays immutable. Keep derived
                    -- fields on the raw candidate to avoid a second plant table.
                    local copy=presentedCopy(self,p,calendar,presentationDay)
                    if budget and budget.maxPropRadius then copy.foliageRadius=propRadius end
                    result[#result+1]=copy
                end
            end
        else
            pending=pending+1
        end
    end
    self.pending,self.lastBuilt=pending,built
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end

function Vegetation:stats()
    return {patches=countKeys(self._patches),generated=self._generated,
        pending=self.pending or 0,built=self.lastBuilt or 0}
end

-- Derive the same tree/log anchors even before their sprite patches stream in.
-- Do not load extra collision/foliage patches merely to decorate a grass tile.
function Vegetation:grassAnchors(x0,z0,x1,z1,step)
    local anchors={}
    local function add(p)
        if p and (Flora.canopy[p.kind] or p.kind=='log') and allowed(self,p.x,p.z,p) then
            anchors[#anchors+1]=p
        end
    end
    for iz=math.max(0,math.floor((z0-7)/CELL_SIZE)),math.min(self.cellCount-1,math.floor((z1+7)/CELL_SIZE)) do
        for ix=math.max(0,math.floor((x0-7)/CELL_SIZE)),math.min(self.cellCount-1,math.floor((x1+7)/CELL_SIZE)) do
            for slot=1,2 do add(Candidates.candidate(self,ix,iz,slot)) end
            add(Candidates.extraCandidate(self,ix,iz,1))
            for slot=1,2 do add(Candidates.extraCandidate2(self,ix,iz,slot)) end
            if step then step() end
        end
    end
    return anchors
end

function Vegetation:_solids(patch,calendar)
    local day=calendar and calendar.totalDays or 0
    if patch.solidDay==day then return patch.solids end
    local solids={}
    for _,p in ipairs(patch.props) do
        if Obstacles.solidKind(p.kind) then
            local radius,height=Obstacles.shape(p,self.seed,calendar)
            p.collisionRadius,p.collisionHeight=radius,height
            if radius then solids[#solids+1]=p end
        end
    end
    patch.solids,patch.solidDay=solids,day
    return solids
end

function Vegetation:sweepObstacles(x,z,nx,nz,radius,bottom,top,calendar,truckCos,truckSin)
    if not M.finite(x) or not M.finite(z) or not M.finite(nx) or not M.finite(nz)
        or not M.finite(radius) or radius<0 then return nil end
    -- Include neighbouring candidate patches whose solid footprint crosses
    -- the bike's path. This is independent of render frustum/upload budgets.
    local margin=radius+Obstacles.MAX_RADIUS
    local minX=math.max(0,math.floor((math.min(x,nx)-margin)/PATCH_SIZE))
    local maxX=math.min(self.patchCount-1,math.floor((math.max(x,nx)+margin)/PATCH_SIZE))
    local minZ=math.max(0,math.floor((math.min(z,nz)-margin)/PATCH_SIZE))
    local maxZ=math.min(self.patchCount-1,math.floor((math.max(z,nz)+margin)/PATCH_SIZE))
    local best,normalX,normalZ,kind,id
    for pz=minZ,maxZ do for px=minX,maxX do
        local solids=self:_solids(self:_getPatch(px,pz),calendar)
        for _,p in ipairs(solids) do
            local t,hx,hz=Obstacles.sweep(x,z,nx,nz,radius,p,bottom,top)
            if t and truckCos and not require('src.commute.truck_footprint').overlaps(
                nx,nz,truckCos,truckSin,p.x,p.z,p.x,p.z,p.collisionRadius) then t=nil end
            if t and (not best or t<best-1e-10 or math.abs(t-best)<=1e-10 and p.id<id) then
                best,normalX,normalZ,kind,id=t,hx,hz,p.kind,p.id
            end
        end
    end end
    return best,normalX,normalZ,kind,id
end

return Vegetation
