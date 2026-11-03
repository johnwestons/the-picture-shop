-- Reusable local building designs and independent world placements, in metres.
local M=require('src.commute.vendor.mathx')
local Codec=require('src.net.codec')
local Sites={DESIGN_VERSION=1,GRADE_APRON=10,MECHANIC_NAME='Majic Blue'}
local Site={};Site.__index=Site
local Registry={};Registry.__index=Registry
local function rect(x0,x1,z0,z1)return {minX=x0,maxX=x1,minZ=z0,maxZ=z1} end
local function copy(value)
    if type(value)~='table' then return value end
    local out={};for key,item in pairs(value) do out[key]=copy(item) end;return out
end
Sites.designs={
    warehouse={style='warehouse',width=12,depth=5.2,height=4.5,floors=1,
        threshold={x=3.6,z=2.6},door={x=3.6,z=3.6},parking={x=3.6,z=6.6}},
    ['brick-walkup']={style='brick-walkup',width=14,depth=9,height=9.3,floors=3,
        threshold={x=-6,z=4.5},door={x=-6,z=5.5},parking={x=-6,z=8.5}},
    garden={style='garden',width=18,depth=10,height=6,floors=2,
        threshold={x=0,z=5},door={x=0,z=6},parking={x=0,z=9}},
    courtyard={style='courtyard',width=24,depth=14,height=6.2,floors=2,
        threshold={x=0,z=7},door={x=0,z=8},parking={x=0,z=11},
        footprints={rect(-12,-7,-7,7),rect(7,12,-7,7),rect(-7,7,-7,-1)},
        obstacles={rect(-1.78,-1.52,6.7,6.95),rect(1.52,1.78,6.7,6.95)}},
    corner={style='corner',width=16,depth=10,height=9.45,floors=3,
        threshold={x=0,z=5},door={x=0,z=6},parking={x=0,z=9},
        obstacles={rect(5.65,8.40,1.4,5.40)}},
}
local function service(id,label,width,depth,height,floors,entryX)
    entryX=entryX or 0
    Sites.designs[id]={style=id,label=label,width=width,depth=depth,height=height,floors=floors or 1,
        threshold={x=entryX,z=depth*.5},door={x=entryX,z=depth*.5+1},parking={x=entryX,z=depth*.5+4}}
end
service('mechanic','Mechanic',16,9,4.7,1,-6.1)
service('grocery','Town grocery',18,11,5,1)
service('post-office','Post office',13,9,5.5,1)
service('police','Police station',16,12,7.2,2)
service('fire-station','Fire station',20,12,6.3,1,-8)
service('diner','Diner',15,8,4,1)
service('coffee-shop','Coffee shop',10,8,3.7,1)
service('general-store','General store',14,9,6.2,2)
service('residential','Apartments',14,10,9.3,3)
Sites.placements={
    {id='warehouse',design='warehouse',origin={x=96.4,z=373.4,h=4.5}},
    {id='brick-walkup',design='brick-walkup',origin={x=231,z=321.5,h=4.5}},
    {id='garden',design='garden',origin={x=425,z=199,h=6}},
    {id='courtyard',design='courtyard',origin={x=187,z=215,h=9}},
    {id='corner',design='corner',origin={x=110,z=121,h=12}},
}
Sites.defaultPlacements=Sites.placements
function Site:toWorld(x,z,h)
    local dx,dz=x*self.scale.x,z*self.scale.z
    return self.origin.x+dx*self.cos-dz*self.sin,self.origin.z+dx*self.sin+dz*self.cos,
        self.origin.h+(h or 0)*self.scale.h
end
function Site:toLocal(x,z)
    local dx,dz=x-self.origin.x,z-self.origin.z
    return (dx*self.cos+dz*self.sin)/self.scale.x,(-dx*self.sin+dz*self.cos)/self.scale.z
end
function Site:normalToWorld(nx,ny,nz)
    nx,ny,nz=nx/self.scale.x,ny/self.scale.h,nz/self.scale.z
    local x,z=nx*self.cos-nz*self.sin,nx*self.sin+nz*self.cos
    local length=math.sqrt(x*x+ny*ny+z*z)
    return x/length,ny/length,z/length
end
local function contains(r,x,z)return x>=r.minX-1e-8 and x<=r.maxX+1e-8 and z>=r.minZ-1e-8 and z<=r.maxZ+1e-8 end
local supportedStyles={}
for id in pairs(Sites.designs) do supportedStyles[id]=true end
local function plain(value,depth,seen,budget)
    local kind=type(value)
    if kind=='number' then return M.finite(value) end
    if kind=='string' then return #value<=256 end
    if kind=='boolean' or kind=='nil' then return true end
    if kind~='table' or depth>8 or seen[value] then return false end
    -- Reliable decoding marks dense arrays with its private, data-only tag.
    -- Accept that official marker while rejecting arbitrary metatables.
    if getmetatable(value)~=nil and not Codec.isArray(value) then return false end
    seen[value]=true
    for key,item in pairs(value) do
        budget.count=budget.count+1
        if budget.count>4096 or (type(key)~='string' and type(key)~='number')
            or not plain(key,depth+1,seen,budget) or not plain(item,depth+1,seen,budget) then return false end
    end
    seen[value]=nil;return true
end
local function validRect(r)
    return type(r)=='table' and M.finite(r.minX) and M.finite(r.maxX) and M.finite(r.minZ) and M.finite(r.maxZ)
        and math.abs(r.minX)<=256 and math.abs(r.maxX)<=256 and math.abs(r.minZ)<=256 and math.abs(r.maxZ)<=256
        and r.maxX-r.minX>=.02 and r.maxZ-r.minZ>=.02
end
local function validRects(values,maximum,emptyAllowed)
    if values==nil then return true end
    if type(values)~='table' or #values>maximum or (#values==0 and not emptyAllowed) then return false end
    local count=0
    for key,r in pairs(values) do
        if type(key)~='number' or key%1~=0 or key<1 or key>#values or not validRect(r) then return false end
        count=count+1
    end
    return count==#values
end
function Sites.validDesign(d)
    if type(d)~='table' or not plain(d,0,{},{count=0}) then return false,'Design must contain bounded plain data' end
    if not supportedStyles[d.style] then return false,'Unknown structure style' end
    if not M.finite(d.width) or not M.finite(d.depth) or not M.finite(d.height)
        or d.width<4 or d.width>128 or d.depth<4 or d.depth>128 or d.height<2.8 or d.height>64 then
        return false,'Invalid structure dimensions'
    end
    if not M.finite(d.floors) or d.floors%1~=0 or d.floors<1 or d.floors>8 or d.height/d.floors<2.8 then
        return false,'Invalid structure floor count or storey height'
    end
    if d.foundation~=nil and not validRect(d.foundation) then return false,'Invalid structure foundation' end
    if not validRects(d.footprints,32,false) then return false,'Invalid structure footprints' end
    if not validRects(d.obstacles,64,true) then return false,'Invalid structure obstacles' end
    if d.style=='courtyard' and (not d.footprints or #d.footprints~=3) then return false,'Courtyard requires three wings' end
    for _,name in ipairs({'threshold','door','parking'}) do
        local a=d[name]
        if type(a)~='table' or not M.finite(a.x) or not M.finite(a.z) or (a.h~=nil and not M.finite(a.h))
            or math.abs(a.x)>256 or math.abs(a.z)>256 or math.abs(a.h or 0)>64 then return false,'Invalid '..name..' anchor' end
    end
    local foundation=d.foundation or rect(-d.width*.5,d.width*.5,-d.depth*.5,d.depth*.5)
    if math.abs(d.threshold.z-foundation.maxZ)>1e-6 or d.threshold.x<foundation.minX+.7
        or d.threshold.x>foundation.maxX-.7 or math.abs(d.door.x-d.threshold.x)>1e-6
        or d.door.z<d.threshold.z+.5 or d.parking.z<d.threshold.z+1 then
        return false,'Entrance anchors must approach the local front facade'
    end
    if d.style=='courtyard' then
        local left,right,back=d.footprints[1],d.footprints[2],d.footprints[3]
        if left.maxX>=right.minX-3 or math.abs(left.maxX-back.minX)>1e-6
            or math.abs(right.minX-back.maxX)>1e-6 or left.maxZ-back.maxZ<2
            or right.maxZ-back.maxZ<2 or math.abs(left.maxZ-right.maxZ)>1e-6 then
            return false,'Courtyard wings must enclose an open inward court'
        end
    end
    for _,r in ipairs(d.footprints or {foundation}) do
        if r.minX<foundation.minX or r.maxX>foundation.maxX or r.minZ<foundation.minZ or r.maxZ>foundation.maxZ then
            return false,'Solid footprint exceeds its foundation'
        end
        if contains(r,d.door.x,d.door.z) or contains(r,d.parking.x,d.parking.z) then return false,'Entry or parking is inside a building' end
    end
    for _,r in ipairs(d.obstacles or {}) do
        if contains(r,d.door.x,d.door.z) or contains(r,d.parking.x,d.parking.z) then return false,'Entry or parking intersects an obstacle' end
    end
    return true
end
function Site:blocked(x,z)
    x,z=self:toLocal(x,z)
    for _,r in ipairs(self.localFootprints) do if contains(r,x,z) then return true end end
    for _,r in ipairs(self.localObstacles) do if contains(r,x,z) then return true end end
    return false
end
function Site:distance(x,z,foundation)
    x,z=self:toLocal(x,z)
    if foundation then
        local r=self.localFoundation
        return M.length(math.max(r.minX-x,0,x-r.maxX)*self.scale.x,
            math.max(r.minZ-z,0,z-r.maxZ)*self.scale.z)
    end
    local result=math.huge
    for _,r in ipairs(self.localFootprints) do
        local dx=math.max(r.minX-x,0,x-r.maxX)*self.scale.x
        local dz=math.max(r.minZ-z,0,z-r.maxZ)*self.scale.z
        result=math.min(result,M.length(dx,dz))
    end
    return result
end
local function worldRect(site,r)
    local out={minX=math.huge,maxX=-math.huge,minZ=math.huge,maxZ=-math.huge,corners={}}
    for _,p in ipairs({{r.minX,r.minZ},{r.maxX,r.minZ},{r.maxX,r.maxZ},{r.minX,r.maxZ}}) do
        local x,z=site:toWorld(p[1],p[2],0)
        out.corners[#out.corners+1]={x=x,z=z}
        out.minX,out.maxX=math.min(out.minX,x),math.max(out.maxX,x)
        out.minZ,out.maxZ=math.min(out.minZ,z),math.max(out.maxZ,z)
    end
    return out
end
local function placement(designs,p)
    local source=type(p.design)=='table' and p.design or assert(designs[p.design or p.id],'Unknown structure design')
    local valid,reason=Sites.validDesign(source);assert(valid,reason)
    local design=copy(source)
    local origin=assert(p.origin,'Structure placement needs an origin')
    local size=p.size or {}
    local sx,sz,sh=(size.width or design.width)/design.width,(size.depth or design.depth)/design.depth,
        (size.height or design.height)/design.height
    assert(M.finite(sx) and M.finite(sz) and M.finite(sh) and sx>0 and sz>0 and sh>0,'Invalid structure size')
    assert(M.finite(origin.x) and M.finite(origin.z) and M.finite(origin.h or 0),'Invalid structure origin')
    local yaw=p.yaw or 0;assert(M.finite(yaw),'Invalid structure yaw')
    local self=setmetatable({id=assert(p.id),design=design,style=design.style or p.design,seed=p.seed,
        origin={x=origin.x,z=origin.z,h=origin.h or 0},yaw=yaw,cos=math.cos(yaw),sin=math.sin(yaw),
        scale={x=sx,z=sz,h=sh},height=design.height*sh,floors=design.floors or 1},Site)
    self.x,self.z,self.h=self.origin.x,self.origin.z,self.origin.h
    self.localFoundation=design.foundation or rect(-design.width*.5,design.width*.5,-design.depth*.5,design.depth*.5)
    self.localFootprints=design.footprints or {self.localFoundation}
    self.localObstacles=design.obstacles or {}
    self.foundation=worldRect(self,self.localFoundation)
    self.minX,self.maxX,self.minZ,self.maxZ=self.foundation.minX,self.foundation.maxX,self.foundation.minZ,self.foundation.maxZ
    self.footprints={};for _,r in ipairs(self.localFootprints) do self.footprints[#self.footprints+1]=worldRect(self,r) end
    self.obstacles={};for _,r in ipairs(self.localObstacles) do self.obstacles[#self.obstacles+1]=worldRect(self,r) end
    for _,name in ipairs({'door','threshold','parking'}) do
        local a=assert(design[name],'Structure design needs '..name)
        local x,z,h=self:toWorld(a.x,a.z,a.h or 0);self[name]={x=x,z=z,h=h}
    end
    self.front={x=-self.sin,z=self.cos}
    return self
end
function Registry:door(id)local site=self.byId[id];return site and site.door end
local empty={}
function Registry:nearby(x,z)
    return self.bins[math.floor(x/self.binSize)..':'..math.floor(z/self.binSize)] or empty
end
function Registry:blocked(x,z)
    for _,site in ipairs(self:nearby(x,z)) do if site:blocked(x,z) then return true end end
    return false
end
function Registry:foundationHeight(x,z)
    for _,site in ipairs(self:nearby(x,z)) do
        local lx,lz=site:toLocal(x,z)
        if contains(site.localFoundation,lx,lz) then return site.h end
    end
end
function Registry:grade(height,x,z)
    local total,weighted,influence=0,0,0
    for _,site in ipairs(self:nearby(x,z)) do
        local d=site:distance(x,z,true)
        if d<1e-8 then return site.h end
        if d<Sites.GRADE_APRON then
            local blend=1-M.smooth(d/Sites.GRADE_APRON)
            -- Inverse distance lets adjacent terraces meet smoothly without
            -- depending on placement order, while preserving every flat base.
            local weight=blend/(d*d)
            total,weighted=total+weight,weighted+site.h*weight
            influence=math.max(influence,blend)
        end
    end
    return total>0 and M.lerp(height,weighted/total,influence) or height
end
function Registry:vegetationAllowed(x,z)
    for _,site in ipairs(self:nearby(x,z)) do if site:distance(x,z,true)<3 then return false end end
    return true
end
function Sites.create(options)
    options=options or {}
    local result=setmetatable({all={},byId={},bins={},binSize=32},Registry)
    for _,p in ipairs(options.placements or Sites.placements) do
        local site=placement(options.designs or Sites.designs,p)
        assert(not result.byId[site.id],'Duplicate structure placement')
        result.all[#result.all+1]=site;result.byId[site.id]=site
        local x0,x1,z0,z1=site.minX,site.maxX,site.minZ,site.maxZ
        for _,bound in ipairs(site.obstacles) do
            x0,x1,z0,z1=math.min(x0,bound.minX),math.max(x1,bound.maxX),math.min(z0,bound.minZ),math.max(z1,bound.maxZ)
        end
        site.collisionBounds={minX=x0,maxX=x1,minZ=z0,maxZ=z1}
        for bx=math.floor((x0-Sites.GRADE_APRON)/result.binSize),math.floor((x1+Sites.GRADE_APRON)/result.binSize) do
            for bz=math.floor((z0-Sites.GRADE_APRON)/result.binSize),math.floor((z1+Sites.GRADE_APRON)/result.binSize) do
                local key=bx..':'..bz;result.bins[key]=result.bins[key] or {}
                result.bins[key][#result.bins[key]+1]=site
            end
        end
    end
    return result
end
Sites.default=Sites.create()
Sites.all,Sites.byId=Sites.default.all,Sites.default.byId
Sites.warehouse=Sites.byId.warehouse
function Sites.door(id)return Sites.default:door(id) end
function Sites.distance(site,x,z)return site:distance(x,z) end
function Sites.blocked(x,z)return Sites.default:blocked(x,z) end
function Sites.grade(height,x,z)return Sites.default:grade(height,x,z) end
function Sites.vegetationAllowed(x,z)return Sites.default:vegetationAllowed(x,z) end
return Sites
