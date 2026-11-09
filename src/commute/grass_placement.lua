-- Town-specific exclusions for the Critter Party grass-field geometry.
-- Clearance encloses a whole comb, including its lean and maximum wind bend.
local M=require('src.commute.vendor.mathx')
local Surface=require('src.commute.vendor.terrain')
local Placement={CLEARANCE=2,WATER_GAP=4,COAST_GAP=7}
local function distance(x,z,ax,az,bx,bz)
    local dx,dz=bx-ax,bz-az
    local u=M.clamp(((x-ax)*dx+(z-az)*dz)/math.max(1e-12,dx*dx+dz*dz),0,1)
    return M.length(x-ax-u*dx,z-az-u*dz)
end
function Placement.hardscape(world,x,z,clearance)
    local r=clearance or Placement.CLEARANCE
    local roads=world.roads
    if roads then
        -- Inspect every overlapping segment: nearest-road priority can conceal
        -- the shoulder of another road or trail at an intersection.
        local list=roads.bins and roads.bins[math.floor(x/16)..':'..math.floor(z/16)] or {}
        for _,s in ipairs(list) do
            if distance(x,z,s.a.x,s.a.z,s.b.x,s.b.z)<=s.width*.5+r+.65 then return true end
        end
        for _,j in ipairs(roads.junctionBins and roads.junctionBins[math.floor(x/16)..':'..math.floor(z/16)] or {}) do
            if M.length(x-j.x,z-j.z)<=j.outerRadius+r+.65 then return true end
        end
        for _,area in ipairs(roads.recreation or {}) do
            if M.length(x-area.x,z-area.z)<=area.radius+r+.5 then return true end
        end
    end
    local sites=world.sites or roads and roads.sites
    if sites and sites.nearby then
        for _,site in ipairs(sites:nearby(x,z)) do
            if site:distance(x,z,true)<r+1 or site:hardscapeDistance(x,z)<r+.6 then return true end
        end
    end
    local infrastructure=world.infrastructure
    if infrastructure and infrastructure.sidewalkDistance
        and infrastructure:sidewalkDistance(x,z,r+.4)<=r+.35 then return true end
    return false
end
function Placement.sample(world,x,z,clearance)
    local r=clearance or Placement.CLEARANCE
    local b=world.playableBounds or {x0=0,z0=0,x1=world.size,z1=world.size}
    if x-r<b.x0 or z-r<b.z0 or x+r>b.x1 or z+r>b.z1 then return nil,'bounds' end
    if Placement.hardscape(world,x,z,r) then return nil,'hardscape' end
    local plan=world.plan
    if plan then
        if plan.shoreDistance and plan:shoreDistance(x,z)<=Placement.COAST_GAP+r then return nil,'coast' end
        if plan.riverDistance then
            local d,_,_,river=plan:riverDistance(x,z)
            if river and d<=(river.waterWidth or 2)*1.55+Placement.WATER_GAP+r then return nil,'river' end
        end
        for _,lake in ipairs(plan.lakes or {}) do
            local dx,dz=x-lake.x,z-lake.z;local c,s=math.cos(lake.angle or 0),math.sin(lake.angle or 0)
            local d=M.length((dx*c+dz*s)/lake.rx,(-dx*s+dz*c)/lake.rz)
            if d<=1.45+(Placement.WATER_GAP+r)/math.min(lake.rx,lake.rz) then return nil,'lake' end
        end
        if plan.marshAt and plan:marshAt(x,z)>.12 then return nil,'marsh' end
    end
    local h=world:height(x,z)
    if h<=.8 then return nil,'shore' end
    -- Catch small/legacy pools as well as the current analytic waterways.
    for i=0,8 do
        local a=i*math.pi/4;local reach=i==8 and 0 or Placement.WATER_GAP+r
        local sx,sz=x+math.cos(a)*reach,z+math.sin(a)*reach
        if world:rawHeight(sx,sz)<=.4 then return nil,'water' end
    end
    local hx=world:height(x+.4,z)-world:height(x-.4,z)
    local hz=world:height(x,z+.4)-world:height(x,z-.4)
    local slope=M.length(hx,hz)/.8
    if slope>.58 then return nil,'slope' end
    local _,_,_,kind,grass=Surface.surface(world,x,z,{height=h,slope=slope})
    if kind=='stone' or kind=='dirt' or kind=='water' or kind=='shore' or grass<.16 then return nil,'material' end
    return h,grass
end
return Placement
