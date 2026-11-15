-- Saved, authoritative yard maneuvers. Rendering only reads these poses.
local Truck=require('src.commute.delivery_truck')
local Path=require('src.commute.driving_path')
local Rail=require('src.commute.yard_rail')
local Watchdog=require('src.ai_watchdog')
local Motion={}
local phases={reverse_out=true,departing=true,away=true,waiting_return=true,returning=true,return_walk=true}
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<1e12 end
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
local function wrap(n)return math.atan2(math.sin(n),math.cos(n))end
function Motion.valid(m)
    if type(m)~='table' or not phases[m.phase] or not Truck.valid(m.vehicle)
        or type(m.points)~='table' or #m.points<2 or #m.points>128
        or not finite(m.index) or m.index%1~=0 or m.index<2 or m.index>#m.points
        or not Rail.valid(m.rail) or not finite(m.wait or 0) or (m.wait or 0)<0
        or m.dockDeparture~=nil and type(m.dockDeparture)~='boolean'
        or m.vehicle.pathIndex~=nil and (not finite(m.vehicle.pathIndex)
            or m.vehicle.pathIndex%1~=0 or m.vehicle.pathIndex<2 or m.vehicle.pathIndex>#m.points)
        or m.vehicle.pathTarget~=nil and m.vehicle.pathTarget~='company-departing'
            and m.vehicle.pathTarget~='company-returning'
        or not finite(m.walkSeconds or 0) or (m.walkSeconds or 0)<0 then return false end
    for _,p in ipairs(m.points)do
        if type(p)~='table' or not finite(p.x) or not finite(p.z) or not finite(p.h or 0)
            or p.x<0 or p.x>512 or p.z<0 or p.z>512 then return false end
    end
    return true
end
local function point(site,x,z)
    local wx,wz,h=site:toWorld(x,z,0);return {x=wx,z=wz,h=h}
end
local function stallPath(site,model)
    local anchor=require('src.commute.sites').warehouseTruckLayout.truckHomeParking[model or 'box']
    local x,z=anchor.x,anchor.z
    local radius=5.5
    local points={point(site,x,z),point(site,x,z+2)}
    for i=1,16 do
        local angle=i*math.pi/32
        points[#points+1]=point(site,x-radius+radius*math.cos(angle),z+2+radius*math.sin(angle))
    end
    return points
end
local function setRoute(m,phase,points)
    local route={}
    for _,p in ipairs(points) do route[#route+1]={x=p.x,z=p.z,h=p.h or 0,speedLimit=2.2} end
    m.phase,m.points,m.index=phase,#route<=8 and Rail.round(route) or route,2
    m.rail=nil;m.wait=0
    m.vehicle.speed=0;m.vehicle.steering=0;m.vehicle.slipAngle=0
    m.vehicle.pathIndex=2;m.vehicle.pathTarget=nil
end
function Motion.start(vehicle,world)
    local v=Truck.snapshot(vehicle)
    local site=world.sites.byId.warehouse
    local _,z=site:toLocal(v.x,v.z)
    local home=site.truckHomeParking[v.model or 'box']
    local points=stallPath(site,v.model)
    -- A player may have left the truck at the loading dock instead of its stall.
    local inStall=(v.x-home.x)^2+(v.z-home.z)^2<4
        and math.abs(wrap(v.heading-home.heading))<.35
    if not inStall then
        points={{x=v.x,z=v.z,h=v.h},point(site,20,z),point(site,20,20)}
    end
    local m={phase=inStall and 'reverse_out' or 'departing',vehicle=v,points=points,index=2}
    m.dockDeparture=(v.x-site.truckParking.x)^2+(v.z-site.truckParking.z)^2<4
    if not inStall then
        for i=4,#(world.truckAccess and world.truckAccess.exitPath or {}) do
            points[#points+1]=world.truckAccess.exitPath[i]
        end
    end
    setRoute(m,m.phase,points)
    v.engine=(v.fuel or 0)>0 and not (v.service and v.service.mechanicalFailure)
    return m
end
function Motion.visible(m)return m and m.phase~='away' and m.phase~='waiting_return' end
function Motion.recover(m,world,state)
    if not m or (m.phase~='reverse_out' and m.phase~='departing' and m.phase~='returning') then
        return false,'Company truck is holding its assigned protocol stop.'
    end
    local v=m.vehicle
    local endpoint=Rail.endpoint(m.points,m.phase=='reverse_out')
    local recovered=Rail.place(v,endpoint,world)
    if recovered then m.rail={station=Path.length(m.points)} end
    m.wait=0
    local message=recovered and 'Teleported truck to its clear reserved protocol checkpoint'
        or 'Reserved checkpoint is occupied; holding and checking again'
    Watchdog.note(state,'company-yard:'..(v.model or 'box'),{status=recovered and 'RECOVERED' or 'STALLED',
        system='Shop yard protocol',subject='Company '..(v.model or 'box')..' truck',stage=m.phase,
        reason='Company truck stalled on its yard line',action=message,
        x=v.x,z=v.z,visible=true,scope='world-simulation'})
    return recovered,message
end
local function follow(m,world,dt,state)
    local v=m.vehicle
    if not m.rail then m.rail={station=Rail.project(m.points,v.x,v.z)} end
    local reverse=m.phase=='reverse_out'
    local arrived,moved,reason=Rail.step(v,m.rail,m.points,dt,world,{reverse=reverse,speed=reverse and 1.2 or 2.2})
    m.index=v.pathIndex or 2;m.blocked=reason~=nil or nil
    local issue='company-yard:'..(v.model or 'box')
    if arrived or moved>.001 then
        m.wait=0
        Watchdog.resolve(state,issue,{reason='Company truck resumed its prescribed yard line'})
    else
        m.wait=(m.wait or 0)+dt
        if m.wait>=8 then
            Motion.recover(m,world,state)
        end
    end
    return arrived
end
function Motion.update(m,world,dt,state)
    dt=clamp(tonumber(dt) or 0,0,.1)
    if dt<=0 or m.phase=='away' then return false end
    local site=world.sites.byId.warehouse
    local v=m.vehicle
    if m.phase=='waiting_return' then
        local points=stallPath(site,v.model)
        local gate=world.truckAccess and world.truckAccess.entryGate
        if not gate then return false end
        local entry=world.truckAccess.entryPath
        local approach=entry[2]
        local heading=math.atan2(approach.z-gate.z,approach.x-gate.x)
        if Truck.blocked(world,gate.x,gate.z,heading,v) then return false end
        v.x,v.z,v.h,v.heading=gate.x,gate.z,world:supportHeight(gate.x,gate.z),heading
        v.reverse=false;v.engine=(v.fuel or 0)>0 and not (v.service and v.service.mechanicalFailure)
        -- Follow the freight entrance around the building, then turn into
        -- the home row from the east. A direct gate-to-stall turn is too tight
        -- for a box truck and crosses the adjacent parked vehicle.
        local route={}
        for i=1,#entry-1 do
            local x,z=site:toLocal(entry[i].x,entry[i].z)
            -- Freight turns toward its reversing setup here. A returning
            -- company truck stays on the outer apron, clear of an occupied dock.
            if z<0 and x>2.1 then break end
            route[#route+1]=entry[i]
        end
        route[#route+1]=point(site,12,-8.4)
        for i=1,16 do
            local angle=-math.pi/2+i*math.pi/32
            route[#route+1]=point(site,12+8*math.cos(angle),-.4+8*math.sin(angle))
        end
        route[#route+1]=point(site,20,14)
        for i=1,16 do
            local angle=i*math.pi/32
            route[#route+1]=point(site,14+6*math.cos(angle),14+6*math.sin(angle))
        end
        local anchor=require('src.commute.sites').warehouseTruckLayout.truckHomeParking[v.model or 'box']
        for i=#points,1,-1 do
            local x,z=site:toLocal(points[i].x,points[i].z)
            route[#route+1]=point(site,2*anchor.x-x,z)
        end
        setRoute(m,'returning',route)
        return true
    elseif m.phase=='return_walk' then
        m.walkSeconds=(m.walkSeconds or 0)+dt
        return m.walkSeconds>=3.35 and 'parked' or false
    end
    if not follow(m,world,dt,state) then return true end
    if m.phase=='reverse_out' then
        local _,z=site:toLocal(v.x,v.z)
        local points={{x=v.x,z=v.z,h=v.h},point(site,12,z),point(site,20,z)}
        for i=4,#(world.truckAccess and world.truckAccess.exitPath or {}) do
            points[#points+1]=world.truckAccess.exitPath[i]
        end
        setRoute(m,'departing',points);v.reverse=false
    elseif m.phase=='departing' then
        m.phase='away';v.speed=0;return 'departed'
    else
        local home=site.truckHomeParking[v.model or 'box']
        -- Only settle the final centimetres after checking the entire footprint.
        if Truck.blocked(world,home.x,home.z,home.heading,v) then return true end
        v.x,v.z,v.h,v.heading=home.x,home.z,home.h,home.heading
        v.speed=0;v.reverse=false;v.engine=false
        m.phase='return_walk';m.walkSeconds=0
    end
    return true
end
return Motion
