-- Frozen, town-specific GPS routes compiled from the generated road graph.
-- Geometry is shared between routes; each route stores only point references
-- plus turn instructions so the town snapshot stays within the shop codec cap.
local DrivingPath=require('src.commute.driving_path')
local Map={VERSION=2}

local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge
end

local function distance(a,b)
    return math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)
end

local function wrap(angle)
    return math.atan2(math.sin(angle),math.cos(angle))
end

local function pointKey(point)
    return ('%.3f:%.3f:%.3f'):format(point.x,point.z,point.h or 0)
end

local function pointLineDistance(point,a,b)
    local dx,dz=b.x-a.x,b.z-a.z
    local length2=dx*dx+dz*dz
    local t=length2>1e-10 and math.max(0,math.min(1,
        ((point.x-a.x)*dx+(point.z-a.z)*dz)/length2)) or 0
    local x,z=a.x+dx*t,a.z+dz*t
    return math.sqrt((point.x-x)^2+(point.z-z)^2)
end

local function simplify(points)
    if type(points)~='table' or #points<2 then return nil,'route has fewer than two road points' end
    local result={points[1]}
    local anchor=1
    while anchor<#points do
        local best=anchor+1
        local walked=0
        for candidate=anchor+1,#points do
            if candidate>anchor+1 then walked=walked+distance(points[candidate-1],points[candidate]) end
            if walked>5.0 then break end
            local safe=true
            for between=anchor+1,candidate-1 do
                if pointLineDistance(points[between],points[anchor],points[candidate])>.38 then
                    safe=false;break
                end
            end
            if not safe then break end
            best=candidate
        end
        result[#result+1]=points[best]
        anchor=best
    end
    return result
end

local function trimRoute(points,trimStart,trimEnd)
    trimStart,trimEnd=math.max(0,trimStart or 0),math.max(0,trimEnd or 0)
    if trimStart<=0 and trimEnd<=0 then return points end
    local segments,total={},0
    for i=2,#points do
        local a,b=points[i-1],points[i]
        local length=distance(a,b)
        segments[i-1]={a=a,b=b,start=total,finish=total+length}
        total=total+length
    end
    local first,last=math.min(total,trimStart),math.max(0,total-trimEnd)
    if last<=first then return points end
    local function at(station)
        for _,segment in ipairs(segments) do
            if station<=segment.finish or segment==segments[#segments] then
                local length=segment.finish-segment.start
                local t=length>1e-8 and math.max(0,math.min(1,(station-segment.start)/length)) or 1
                local a,b=segment.a,segment.b
                return {x=a.x+(b.x-a.x)*t,z=a.z+(b.z-a.z)*t,
                    h=(a.h or b.h or 0)+((b.h or a.h or 0)-(a.h or 0))*t}
            end
        end
        return points[#points]
    end
    local result={at(first)}
    for _,segment in ipairs(segments) do
        if segment.finish>first+1e-7 and segment.finish<last-1e-7 then
            result[#result+1]=segment.b
        end
    end
    result[#result+1]=at(last)
    return result
end

local function routeTurns(points)
    local result={}
    for i=2,#points-1 do
        local before,at,after=points[i-1],points[i],points[i+1]
        local incoming=math.atan2(at.z-before.z,at.x-before.x)
        local outgoing=math.atan2(after.z-at.z,after.x-at.x)
        local angle=wrap(outgoing-incoming)
        if math.abs(angle)>=.22 then
            result[#result+1]={at=i,angle=angle,speed=DrivingPath.turnSpeed(angle)}
        end
    end
    return result
end

local function sortedDestinationIds(town)
    local result={}
    for id in pairs(town.destinations or {}) do
        if id~='mainland_exit' then result[#result+1]=id end
    end
    table.sort(result)
    return result
end

function Map.resolve(drivingMap,route)
    if type(drivingMap)~='table' or type(route)~='table' then return nil end
    local points={}
    for index,nodeId in ipairs(route.points or {}) do
        local source=(nodeId-1)*3+1
        local x,z,h=drivingMap.points[source],drivingMap.points[source+1],drivingMap.points[source+2]
        if not h then return nil end
        points[index]={x=x,z=z,h=h}
    end
    for index=1,#(route.turns or {}),2 do
        local point=points[route.turns[index]]
        if not point then return nil end
        point.speedLimit=route.turns[index+1]
    end
    return points
end

local function routeClear(world,points,Truck,Footprint,checked)
    checked=checked or {}
    for i=2,#points do
        local a,b=points[i-1],points[i]
        local length=distance(a,b)
        local steps=math.max(1,math.ceil(length/1.5))
        local heading=math.atan2(b.z-a.z,b.x-a.x)
        for step=0,steps do
            local t=step/steps
            local x,z=a.x+(b.x-a.x)*t,a.z+(b.z-a.z)*t
            local key=('%0.1f:%0.1f:%0.1f'):format(x,z,heading)
            if not checked[key] then
                checked[key]=true
                if Truck.blocked(world,x,z,heading) then
                    return false,('truck footprint blocked at (%.1f,%.1f), heading %.2f'):format(x,z,heading)
                end
            end
            -- A truck must fit both sides of a turn. Probe the incoming and
            -- outgoing headings at each saved turn, not only its centerline.
            if step==steps and points[i].turnAngle then
                local turn=points[i].turnAngle
                local outHeading=heading+turn
                local outKey=('%0.1f:%0.1f:%0.1f'):format(x,z,outHeading)
                if not checked[outKey] then
                    checked[outKey]=true
                    if Truck.blocked(world,x,z,outHeading) then
                        return false,('truck footprint blocked at turn (%.1f,%.1f), heading %.2f')
                            :format(x,z,outHeading)
                    end
                end
            end
        end
    end
    return true
end

function Map.compile(town,world,options)
    options=options or {}
    local Routes=require('src.commute.routes')
    local planner=Routes.new(world.roads,{pavedOnly=true})
    local ids=sortedDestinationIds(town)
    if #ids<2 then return nil,'town has fewer than two driving destinations' end
    local result={version=Map.VERSION,destinations=ids,points={},routes={}}
    local pointIds={}
    local function intern(point)
        local key=pointKey(point)
        local id=pointIds[key]
        if id then return id end
        id=#result.points/3+1
        pointIds[key]=id
        result.points[#result.points+1]=point.x
        result.points[#result.points+1]=point.z
        result.points[#result.points+1]=point.h or 0
        return id
    end
    local allRoutes={}
    local function addRoute(fromIndex,toIndex,full,points)
        local turns=routeTurns(points)
        local route={from=fromIndex,to=toIndex,length=full.length,bridge=full.crossesBridge==true,
            bidirectional=false,points={},turns={}}
        for _,point in ipairs(points) do route.points[#route.points+1]=intern(point) end
        for _,turn in ipairs(turns) do
            points[turn.at].turnAngle=turn.angle
            points[turn.at].speedLimit=turn.speed
            route.turns[#route.turns+1]=turn.at
            route.turns[#route.turns+1]=turn.speed
        end
        result.routes[#result.routes+1]=route
        allRoutes[#allRoutes+1]={from=ids[fromIndex],to=ids[toIndex],length=full.length,
            points=points,turns=turns}
        return route
    end
    local function compileDirection(fromIndex,toIndex)
        local full,reason=planner:find(ids[fromIndex],ids[toIndex])
        if not full then
            return nil,('%s -> %s is unreachable: %s'):format(ids[fromIndex],ids[toIndex],tostring(reason))
        end
        local points,why=simplify(full.points)
        if not points then return nil,('%s -> %s: %s'):format(ids[fromIndex],ids[toIndex],tostring(why)) end
        return {full=full,points=points}
    end
    for fromIndex=1,#ids do
        for toIndex=fromIndex+1,#ids do
            local forward,forwardError=compileDirection(fromIndex,toIndex)
            if not forward then return nil,forwardError end
            local reverse,reverseError=compileDirection(toIndex,fromIndex)
            if not reverse then return nil,reverseError end
            local samePath=#forward.points==#reverse.points
                and forward.full.crossesBridge==reverse.full.crossesBridge
            if samePath then
                for index,point in ipairs(forward.points) do
                    if pointKey(point)~=pointKey(reverse.points[#reverse.points-index+1]) then
                        samePath=false;break
                    end
                end
            end
            if samePath then
                addRoute(fromIndex,toIndex,forward.full,forward.points).bidirectional=true
            else
                addRoute(fromIndex,toIndex,forward.full,forward.points)
                addRoute(toIndex,fromIndex,reverse.full,reverse.points)
            end
        end
    end
    if options.validateClearance~=false then
        local Truck=require('src.commute.delivery_truck')
        local Footprint=require('src.commute.truck_footprint')
        -- Route pairs share long stretches of the same road graph. Clearance
        -- depends only on this fixed candidate world and the rounded sample
        -- key, so reuse completed checks across routes during this compile.
        local clearanceChecks={}
        for _,route in ipairs(allRoutes) do
            local okay,reason=routeClear(world,route.points,Truck,Footprint,clearanceChecks)
            if not okay then
                return nil,('%s -> %s is not truck-clear: %s'):format(route.from,route.to,tostring(reason))
            end
        end
        if world.truckDestinations and world.mainlandExit then
            local deliveryPlanner=Routes.new(world.roads,{includeTruckOnly=true,pavedOnly=true,
                destinations=world.truckDestinations})
            local gate=world.mainlandExit
            local checks={}
            for id in pairs(world.truckDestinations) do
                if id=='warehouse_truck_dock' or id:match('^warehouse_truck_queue_') then
                    checks[#checks+1]={from=gate,to=id}
                end
            end
            table.sort(checks,function(a,b)return a.to<b.to end)
            for _,check in ipairs(checks) do
                local route,reason=deliveryPlanner:findFromPoint(check.from.x,check.from.z,check.to)
                if not route then
                    return nil,('%s -> %s is unreachable: %s'):format('mainland_exit',check.to,tostring(reason))
                end
                local okay,why=routeClear(world,trimRoute(route.points,Footprint.halfLength+.65,0),
                    Truck,Footprint,clearanceChecks)
                if not okay then
                    return nil,('%s -> %s is not truck-clear: %s')
                        :format('mainland_exit',check.to,tostring(why))
                end
            end
            local dock=world.truckDestinations.warehouse_truck_dock
            local route,reason=deliveryPlanner:findFromPoint(dock.x,dock.z,'mainland_exit')
            if not route then
                return nil,'warehouse_truck_dock -> mainland_exit is unreachable: '..tostring(reason)
            end
            local okay,why=routeClear(world,trimRoute(route.points,0,Footprint.halfLength+.65),
                Truck,Footprint,clearanceChecks)
            if not okay then
                return nil,'warehouse_truck_dock -> mainland_exit is not truck-clear: '..tostring(why)
            end
        end
    end
    return result
end

function Map.valid(town,drivingMap)
    if type(drivingMap)~='table' or drivingMap.version~=Map.VERSION
        or type(drivingMap.destinations)~='table' or type(drivingMap.points)~='table'
        or type(drivingMap.routes)~='table' then return false end
    local expected=sortedDestinationIds(town)
    if #expected<2 or #drivingMap.destinations~=#expected then return false end
    local ids={}
    for index,id in ipairs(drivingMap.destinations) do
        if id~=expected[index] then return false end
        ids[id]=index
    end
    if #drivingMap.points<6 or #drivingMap.points%3~=0 or #drivingMap.points>36000
        or #drivingMap.routes<#expected*(#expected-1)/2
        or #drivingMap.routes>#expected*(#expected-1) then return false end
    for index=1,#drivingMap.points,3 do
        local x,z,h=drivingMap.points[index],drivingMap.points[index+1],drivingMap.points[index+2]
        if not finite(x) or not finite(z) or not finite(h)
            or x<town.bounds.x0 or x>town.bounds.x1
            or z<town.bounds.z0 or z>town.bounds.z1
            or h< -2 or h>84 then return false end
    end
    local pointCount=#drivingMap.points/3
    local seen,routeCount={},0
    for _,route in ipairs(drivingMap.routes) do
        if type(route)~='table'
            or type(route.from)~='number' or route.from%1~=0 or route.from<1 or route.from>#expected
            or type(route.to)~='number' or route.to%1~=0 or route.to<1 or route.to>#expected
            or not ids[expected[route.from]] or not ids[expected[route.to]] or route.from==route.to
            or not finite(route.length) or route.length<=0 or type(route.bridge)~='boolean'
            or type(route.bidirectional)~='boolean'
            or type(route.points)~='table' or #route.points<2 or #route.points>512
            or type(route.turns)~='table' or #route.turns%2~=0 or #route.turns>128 then return false end
        local key=route.from..':'..route.to
        if seen[key] then return false end
        seen[key]=true
        routeCount=routeCount+1
        if route.bidirectional then
            local reverseKey=route.to..':'..route.from
            if seen[reverseKey] then return false end
            seen[reverseKey]=true;routeCount=routeCount+1
        end
        for _,pointId in ipairs(route.points) do
            if type(pointId)~='number' or pointId%1~=0 or pointId<1 or pointId>pointCount then return false end
        end
        local firstId,lastId=route.points[1],route.points[#route.points]
        local firstIndex,lastIndex=(firstId-1)*3+1,(lastId-1)*3+1
        local first={x=drivingMap.points[firstIndex],z=drivingMap.points[firstIndex+1]}
        local last={x=drivingMap.points[lastIndex],z=drivingMap.points[lastIndex+1]}
        local from,to=town.destinations[expected[route.from]],town.destinations[expected[route.to]]
        if not first or not last or not from or not to
            or (first.x-from.x)^2+(first.z-from.z)^2>.03^2
            or (last.x-to.x)^2+(last.z-to.z)^2>.03^2 then return false end
        local turnSeen={}
        for index=1,#route.turns,2 do
            local at,speed=route.turns[index],route.turns[index+1]
            if not finite(at) or at%1~=0 or at<2 or at>#route.points-1 or turnSeen[at]
                or not finite(speed) or speed<1 or speed>8.6 then return false end
            turnSeen[at]=true
        end
    end
    return routeCount==#expected*(#expected-1)
end

return Map
