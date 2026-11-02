-- Deterministic, patch-streamed town foliage adapted from Critter Party's
-- stable candidate IDs and habitat-weighted plant placement.
local M=require('src.commute.vendor.mathx')
local Candidates=require('src.commute.vendor.plant_candidates')
local Flora=require('src.commute.flora')
local Vegetation={};Vegetation.__index=Vegetation

local PATCH_SIZE=16
local CELL_SIZE=4
local MAX_PATCHES=256

local function countKeys(t)
    local n=0;for _ in pairs(t) do n=n+1 end;return n
end

local function insideBounds(world,x,z)
    local bounds=world.playableBounds
    if not bounds then return x>=0 and z>=0 and x<world.size and z<world.size end
    return x>=bounds.x0 and z>=bounds.z0 and x<=bounds.x1 and z<=bounds.z1
end

local function allowed(self,x,z)
    local world=self.world
    if not insideBounds(world,x,z) then return nil end
    if world.spawn and M.length(x-world.spawn.x,z-world.spawn.z)<6 then return nil end
    local h=world:height(x,z)
    if not M.finite(h) or h<=.4 then return nil end
    if world.roads and world.roads.vegetationAllowed
        and not world.roads:vegetationAllowed(x,z) then return nil end
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

function Vegetation:_makePatch(px,pz)
    local props={}
    local function add(p)
        if not p then return end
        local height=allowed(self,p.x,p.z)
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
    patch={props=self:_makePatch(px,pz),used=self._tick}
    self._patches[key]=patch
    self._generated=self._generated+1
    self:_evictIfNeeded()
    return patch
end

function Vegetation:visible(cx,cz,radius,calendar,visible)
    local result={}
    if not M.finite(cx) or not M.finite(cz) or not M.finite(radius) then return result end
    radius=math.max(0,radius)
    local radius2=radius*radius
    local minX=math.max(0,math.floor((cx-radius)/PATCH_SIZE))
    local maxX=math.min(self.patchCount-1,math.floor((cx+radius)/PATCH_SIZE))
    local minZ=math.max(0,math.floor((cz-radius)/PATCH_SIZE))
    local maxZ=math.min(self.patchCount-1,math.floor((cz+radius)/PATCH_SIZE))
    for pz=minZ,maxZ do
        for px=minX,maxX do
            local x0,z0=px*PATCH_SIZE,pz*PATCH_SIZE
            local x1,z1=math.min(self.size,x0+PATCH_SIZE),math.min(self.size,z0+PATCH_SIZE)
            local nearestX=M.clamp(cx,x0,x1)
            local nearestZ=M.clamp(cz,z0,z1)
            if (nearestX-cx)^2+(nearestZ-cz)^2<=radius2
                and (not visible or visible((x0+x1)*.5,(z0+z1)*.5,24)) then
                local patch=self:_getPatch(px,pz)
                for _,p in ipairs(patch.props) do
                    local dx,dz=p.x-cx,p.z-cz
                    if dx*dx+dz*dz<=radius2 and (not visible or visible(p.x,p.z,12)) then
                        result[#result+1]=Flora.present({id=p.id,kind=p.kind,x=p.x,z=p.z,h=p.h,scale=p.scale},self.seed,calendar)
                    end
                end
            end
        end
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end

function Vegetation:stats()
    return {patches=countKeys(self._patches),generated=self._generated}
end

return Vegetation
