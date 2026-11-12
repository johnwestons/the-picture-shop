-- Deterministic speed envelopes for clock-sampled NPC journeys. A profile is
-- built once per road route; rendering never advances simulation or saves.
local Path=require('src.commute.driving_path')
local Rules=require('src.commute.traffic_rules')
local Scheduled={}
local worlds=setmetatable({}, {__mode='k'})
local function clamp(v,a,b)return math.max(a,math.min(b,v))end

local function joinInsideCorners(nodes)
    local result={}
    for _,node in ipairs(nodes) do
        local a=result[#result]
        if a and not a.stop then
            local dx,dz=node.x-a.x,node.z-a.z
            for i=#result-2,math.max(1,#result-24),-1 do
                local b,c=result[i],result[i+1]
                if c.stop then break end
                local ex,ez=c.x-b.x,c.z-b.z
                local determinant=dx*ez-dz*ex
                if math.abs(determinant)>1e-8 and math.abs(node.h-b.h)<.35 then
                    local bx,bz=b.x-a.x,b.z-a.z
                    local t=(bx*ez-bz*ex)/determinant
                    local u=(bx*dz-bz*dx)/determinant
                    if t>=0 and t<=1 and u>=0 and u<=1 then
                        -- Offset lines overlap at an inside corner. Join at
                        -- their intersection instead of riding around a loop
                        -- toward the original centerline vertex and back.
                        for j=#result,i+1,-1 do result[j]=nil end
                        result[#result+1]={x=a.x+dx*t,z=a.z+dz*t,h=node.h,
                            station=(b.station+node.station)*.5,speed=math.min(b.speed,node.speed)}
                        break
                    end
                end
            end
        end
        result[#result+1]=node
    end
    return result
end

local function profile(route,world,vehicle)
    if not route or not route.points or #route.points<2 or not world then return nil end
    local routes=worlds[world]
    if not routes then routes=setmetatable({}, {__mode='k'});worlds[world]=routes end
    local variants=routes[route]
    if not variants then variants={};routes[route]=variants end
    local kind=vehicle.trafficKind=='motorcycle' and 'motorcycle' or vehicle.model or 'box'
    local variant=kind..':'..tostring(vehicle.driverSkill or '')
    if variants[variant] then return variants[variant] end
    local Network=require('src.commute.delivery_traffic')
    local points=route.points
    local length=Path.length(points)
    if length<.01 then return nil end
    local stations={0,length}
    for station=1,length-1,1 do stations[#stations+1]=station end
    local stops={}
    for _,stop in ipairs(Network.routeStops(points,world)) do
        local station=clamp(stop.station-Rules.dimensions(vehicle).halfLength-.35,0,length)
        stations[#stations+1]=station;stops[station]=true
    end
    table.sort(stations)
    -- Two adjacent stationary anchors still need room to accelerate between
    -- them, including very short driveway routes and closely spaced stops.
    local expanded={}
    for i,station in ipairs(stations) do
        local previous=stations[i-1]
        if previous and station-previous>.001
            and (previous==0 or stops[previous]) and (station==length or stops[station]) then
            expanded[#expanded+1]=(previous+station)*.5
        end
        expanded[#expanded+1]=station
    end
    stations=expanded
    local nodes={}
    local markers=Path.speedLimits(points)
    for _,station in ipairs(stations) do
        if #nodes==0 or station-nodes[#nodes].station>.001 then
            local center=Path.sample(points,length,station/length)
            local subject={x=center.x,z=center.z,trafficKind=vehicle.trafficKind,model=vehicle.model}
            local lane,road=Network.lanePosition(subject,points,center,world)
            -- Ease out of the departure anchor as well as into the arrival.
            local startBlend=clamp(station/8,0,1)
            local node={x=center.x+(lane.x-center.x)*startBlend,
                z=center.z+(lane.z-center.z)*startBlend,h=center.h,
                station=station,stop=stops[station],speed=math.min(Rules.driverTownSpeed(vehicle),Rules.roadSpeed(road))}
            for _,marker in ipairs(markers) do
                local ahead=marker.distance-station
                if ahead>=-6-Rules.dimensions(vehicle).halfLength then
                    node.speed=math.min(node.speed,math.sqrt(marker.speed^2
                        +2*Rules.brakeDeceleration(vehicle)*math.max(0,ahead-8-Rules.dimensions(vehicle).halfLength)))
                end
            end
            if node.stop or station==0 or station==length then node.speed=0 end
            nodes[#nodes+1]=node
        elseif stops[station] then nodes[#nodes].stop=true;nodes[#nodes].speed=0 end
    end
    nodes=joinInsideCorners(nodes)
    local acceleration=kind=='motorcycle' and 1.5 or 1
    for i=2,#nodes do
        local a,b=nodes[i-1],nodes[i]
        b.distance=math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)
        b.speed=math.min(b.speed,math.sqrt(a.speed^2+2*acceleration*b.distance))
    end
    for i=#nodes-1,1,-1 do
        local a,b=nodes[i],nodes[i+1]
        a.speed=math.min(a.speed,math.sqrt(b.speed^2+2*Rules.brakeDeceleration(vehicle)*b.distance))
    end
    local seconds=0
    for i,node in ipairs(nodes) do
        if i>1 then seconds=seconds+2*node.distance/math.max(.01,node.speed+nodes[i-1].speed) end
        node.arrival=seconds
        seconds=seconds+(node.stop and Rules.STOP_DWELL_SECONDS or 0)
        node.departure=seconds
    end
    local result={nodes=nodes,duration=seconds,length=length}
    variants[variant]=result
    return result
end

function Scheduled.sample(route,progress,world,vehicle)
    local plan=profile(route,world,vehicle or {trafficKind='motorcycle'})
    if not plan then return nil end
    local time=clamp(progress or 0,0,1)*plan.duration
    local nodes=plan.nodes
    local lo,hi=1,#nodes
    while lo<hi do
        local mid=math.floor((lo+hi)*.5)
        if nodes[mid].departure<time then lo=mid+1 else hi=mid end
    end
    local b=nodes[lo]
    local a=nodes[math.max(1,lo-1)]
    local nextNode=nodes[math.min(#nodes,lo+1)]
    if time>=b.arrival then
        local heading=lo<#nodes and math.atan2(nextNode.z-b.z,nextNode.x-b.x)
            or math.atan2(b.z-a.z,b.x-a.x)
        return {x=b.x,z=b.z,h=b.h,heading=heading,speed=b.stop and 0 or b.speed,progress=b.station/plan.length,
            distance=b.station,duration=plan.duration}
    end
    local elapsed=time-a.departure
    local duration=b.arrival-a.departure
    local acceleration=duration>0 and (b.speed-a.speed)/duration or 0
    local traveled=a.speed*elapsed+.5*acceleration*elapsed*elapsed
    local fraction=b.distance>0 and clamp(traveled/b.distance,0,1) or 1
    return {x=a.x+(b.x-a.x)*fraction,z=a.z+(b.z-a.z)*fraction,h=a.h+(b.h-a.h)*fraction,
        heading=math.atan2(b.z-a.z,b.x-a.x),speed=math.max(0,a.speed+acceleration*elapsed),
        progress=(a.station+(b.station-a.station)*fraction)/plan.length,
        distance=a.station+(b.station-a.station)*fraction,duration=plan.duration}
end

function Scheduled.profile(route,world,vehicle)
    return profile(route,world,vehicle or {trafficKind='motorcycle'})
end

return Scheduled
