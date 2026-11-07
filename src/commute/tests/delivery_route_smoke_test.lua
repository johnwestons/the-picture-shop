local Network=require('src.commute.delivery_traffic')
local Town=require('src.commute.town')
local Routes=require('src.commute.routes')
local Truck=require('src.commute.delivery_truck')
local Footprint=require('src.commute.truck_footprint')
local DrivingPath=require('src.commute.driving_path')
local Test={}

local seeds={712345,712346,43127}
local function routeName(seed,from,to)
    return ('delivery_route_seed_%d_%s_to_%s'):format(seed,from,to)
end

local function blockingReasonAt(world,truck,x,z,heading)
    local c,s=math.cos(heading),math.sin(heading)
    local Footprint=require('src.commute.truck_footprint')
    if world.infrastructure then
        local infra=world.infrastructure
        for ix=math.floor((x-Footprint.radius)/12),math.floor((x+Footprint.radius)/12) do
            for iz=math.floor((z-Footprint.radius)/12),math.floor((z+Footprint.radius)/12) do
                local bin=infra.bins[ix..':'..iz]
                for _,shape in ipairs(bin or {}) do
                    if Footprint.overlaps(x,z,c,s,shape.ax,shape.az,shape.bx,shape.bz,shape.radius) then
                        return ('infrastructure:%s:%s:%s@(%.1f,%.1f)'):format(
                            shape.kind,tostring(shape.roadId),tostring(shape.id),shape.ax,shape.az)
                    end
                end
            end
        end
    end
    for _,site in ipairs(world.sites:nearby(x,z)) do
        if Footprint.hitsEdges(site.footprints,x,z,c,s)
            or Footprint.hitsEdges(site.obstacles,x,z,c,s) then return 'site:'..site.id end
    end
    for row=-2,2 do for col=-1,1 do
        local along=row*Footprint.halfLength*.5
        local side=col*Footprint.halfWidth
        local blocked,kind=world.roads:blocked(world,x+c*along-s*side,z+s*along+c*side,true)
        if blocked then
            local reason='road:'..tostring(kind)
            if kind=='bridgeRail' then
                local roadDistance,segment=world.roads:sample(x+c*along-s*side,z+s*along+c*side)
                reason=reason..(':nearest=%s,width=%.1f,lanes=%s,bridge=%s,oneWay=%s,role=%s,distance=%.1f'):
                    format(tostring(segment and segment.id),segment and segment.width or 0,
                        tostring(segment and segment.lanes),tostring(segment and segment.bridge),
                        tostring(segment and segment.oneWay),tostring(segment and segment.role),
                        roadDistance or math.huge)
            end
            return reason
        end
    end end
    if world.vehicleObstacles and world.vehicleObstacles(x,z,heading,truck) then return 'vehicle' end
    local h=world:supportHeight(x,z)
    local hit,_,_,kind,id=world:sweepObstacles(x,z,x,z,Footprint.radius,
        h,h+Footprint.height,c,s)
    if hit~=nil then
        local numericId=tonumber(id)
        for _,patch in pairs(world.vegetation and world.vegetation._patches or {}) do
            for _,prop in ipairs(patch.props or {}) do
                if prop.id==numericId then
                    local distance,segment=world.roads:nearest(prop.x,prop.z)
                    return ('object:%s:%s@(%.1f,%.1f),roadDistance=%.1f,road=%s'):
                        format(tostring(kind),tostring(id),prop.x,prop.z,distance,tostring(segment and segment.id))
                end
            end
        end
        return ('object:%s:%s'):format(tostring(kind),tostring(id))
    end
    return 'clear'
end

local function blockingReason(world,truck)
    local heading=truck.heading or 0
    local here=blockingReasonAt(world,truck,truck.x,truck.z,heading)
    if here~='clear' then return here end
    local direction=truck.reverse and -1 or 1
    local travelHeading=heading+(truck.slipAngle or 0)
    local nx=truck.x+math.cos(travelHeading)*direction*.2
    local nz=truck.z+math.sin(travelHeading)*direction*.2
    return blockingReasonAt(world,truck,nx,nz,heading)
end

local function pointSummary(points,truck)
    local result={}
    local first=math.max(1,(truck.pathIndex or 2)-2)
    local last=math.min(#points,first+5)
    for i=first,last do
        local p=points[i]
        result[#result+1]=('%d:(%.1f,%.1f,a%s,v%s)'):format(i,p.x,p.z,
            p.turnAngle and ('%.2f'):format(p.turnAngle) or '-',
            p.speedLimit and ('%.1f'):format(p.speedLimit) or '-')
    end
    return table.concat(result,',')
end

local function remainingAlong(points,truck)
    local cursor=math.max(2,math.min(#points,truck.pathIndex or 2))
    local walked=0
    for i=cursor+1,#points do
        local a,b=points[i-1],points[i]
        walked=walked+math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)
    end
    local waypoint=points[cursor]
    return walked+math.sqrt((truck.x-waypoint.x)^2+(truck.z-waypoint.z)^2),
        math.sqrt((truck.x-waypoint.x)^2+(truck.z-waypoint.z)^2)
end

local function drive(world,route,from,to,startDistance)
    local first,second=route.points[1],route.points[2]
    local startSample
    if startDistance and startDistance>0 then
        startDistance=math.min(startDistance,math.max(0,route.length-.01))
        startSample=DrivingPath.sample(route.points,route.length,startDistance/route.length)
    end
    local startX,startZ,startHeading=startSample and startSample.x or first.x,
        startSample and startSample.z or first.z,
        startSample and startSample.heading or math.atan2(second.z-first.z,second.x-first.x)
    local truck=Truck.new(startX,startZ,startHeading,'plain')
    truck.h=startSample and startSample.h or 0
    truck.pathIndex=startDistance and DrivingPath.indexAtDistance(route.points,startDistance+1.5) or 2
    local target=from..'->'..to
    local limit=math.max(35,route.length/4+25)
    local elapsed,stallElapsed=0,0
    local bestRemaining=route.length
    local detail,trace=nil,{}
    local originalBlocked=Truck.blocked
    Truck.blocked=function(blockWorld,x,z,heading,subject)
        local blocked=originalBlocked(blockWorld,x,z,heading,subject)
        if blocked and subject==truck then
            truck.lastBlocked=('%s at (%.2f,%.2f) heading %.2f'):format(
                blockingReasonAt(world,truck,x,z,heading),x,z,heading)
        end
        return blocked
    end
    while elapsed<limit do
        elapsed=elapsed+.1
        if Network.driveRoute(truck,route.points,.1,world,target) then
            Truck.blocked=originalBlocked
            local dx,dz=truck.x-route.points[#route.points].x,truck.z-route.points[#route.points].z
            return dx*dx+dz*dz<=1.1^2,elapsed,truck
        end
        local remaining,crossTrack=remainingAlong(route.points,truck)
        if remaining<bestRemaining-.35 then bestRemaining,stallElapsed=remaining,0
        else stallElapsed=stallElapsed+.1 end
        if os.getenv('PICTURE_SHOP_DELIVERY_ROUTE_TRACE')=='1'
            and math.abs(elapsed-math.floor(elapsed/2+.5)*2)<.051 then
            trace[#trace+1]=('t%.0f=(%.1f,%.1f,h%.2f,s%.2f,i%d,v%.2f,r%s)'):format(
                elapsed,truck.x,truck.z,truck.heading or 0,truck.slipAngle or 0,
                truck.pathIndex or 0,truck.speed or 0,
                tostring(truck.reverse))
        end
        if stallElapsed>=14 then
            detail=('stalled at (%.1f,%.1f) heading=%.2f slip=%.2f reverse=%s index=%d waypointDistance=%.1fm remaining=%.1fm speed=%.2f block=%s lastBlocked=%s route=%s trace=%s')
                :format(truck.x,truck.z,truck.heading or 0,truck.slipAngle or 0,
                    tostring(truck.reverse),truck.pathIndex or 0,
                    crossTrack,remaining,truck.speed or 0,blockingReason(world,truck),
                    tostring(truck.lastBlocked),pointSummary(route.points,truck),
                    table.concat(trace,','))
            break
        end
    end
    local final=route.points[#route.points]
    local dx,dz=truck.x-final.x,truck.z-final.z
    Truck.blocked=originalBlocked
    return false,elapsed,truck,('remaining=%.1fm speed=%.2f distance=%.1fm'):format(
        math.sqrt(dx*dx+dz*dz),truck.speed or 0,truck.distance or 0)..'; '..(detail or 'time limit')
end

function Test.run(check)
    local totalRoutes,successfulRoutes=0,0
    local slowest={seconds=0}
    local failures={}
    local sampleTown
    local fromFilter=os.getenv('PICTURE_SHOP_DELIVERY_ROUTE_FROM')
    local toFilter=os.getenv('PICTURE_SHOP_DELIVERY_ROUTE_TO')
    local seedFilter=tonumber(os.getenv('PICTURE_SHOP_DELIVERY_ROUTE_SEED'))
    for _,seed in ipairs(seeds) do
        if not seedFilter or seed==seedFilter then
        local town=assert(Town.generate(seed))
        sampleTown=sampleTown or town
        local world=Town.world(town)
        local planner=Routes.new(world.roads,{pavedOnly=true})
        local ids={}
        for id in pairs(world.roads.destinations) do
            if id~='mainland_exit' then ids[#ids+1]=id end
        end
        table.sort(ids)
        for _,from in ipairs(ids) do
            for _,to in ipairs(ids) do
                if from~=to and (not fromFilter or from==fromFilter) and (not toFilter or to==toFilter) then
                    totalRoutes=totalRoutes+1
                    local route,reason=planner:find(from,to)
                    if not route then
                        failures[#failures+1]=routeName(seed,from,to)..' unreachable: '..tostring(reason)
                    else
                        local arrived,seconds,truck,detail=drive(world,route,from,to)
                        if arrived then
                            successfulRoutes=successfulRoutes+1
                            if seconds>slowest.seconds then
                                slowest={seconds=seconds,seed=seed,from=from,to=to}
                            end
                        end
                        if not arrived then
                            failures[#failures+1]=('%s %.1fm after %.1fs; %s'):format(
                                routeName(seed,from,to),route.length,seconds,detail or 'no arrival')
                        end
                    end
                end
            end
        end
        local deliveryPlanner=Routes.new(world.roads,{includeTruckOnly=world.truckDestinations~=nil,
            pavedOnly=true,destinations=world.truckDestinations})
        local deliveryTarget=world.truckDestinations and 'warehouse_truck_dock' or 'warehouse'
        local deliveryRoute,deliveryRouteError=deliveryPlanner:findFromPoint(
            world.mainlandExit.x,world.mainlandExit.z,deliveryTarget)
        local deliveryRouteArrived,deliveryRouteSeconds,_,deliveryRouteDetail
        if deliveryRoute then
            deliveryRouteArrived,deliveryRouteSeconds,_,deliveryRouteDetail=drive(world,deliveryRoute,
                'mainland_exit',deliveryTarget,Footprint.halfLength+.65)
        end
        check(('delivery_truck_follows_live_gate_to_warehouse_route_%d'):format(seed),
            deliveryRouteArrived==true,
            deliveryRoute and ('%.1fm in %.1fs: %s'):format(deliveryRoute.length,
                deliveryRouteSeconds or 0,deliveryRouteDetail or 'arrived')
                or ('route unavailable: '..tostring(deliveryRouteError)))
        end
    end
    local mapSnapshotOkay=false
    local mapSnapshotDetail='no generated town was available'
    if sampleTown then
        local Codec=require('src.net.codec')
        local Schema=require('src.save_schema')
        local limits={maxBytes=512*1024,maxDepth=32,maxEntries=32768,
            maxStringBytes=128*1024,maxNumberBytes=32}
        local state=Schema.defaultState()
        state.home=assert(require('src.home').new({town=sampleTown},state.calendar.totalDays))
        local snapshot=assert(Schema.snapshot(state))
        local packet,encodeError=Codec.encode(snapshot,limits)
        local decoded=packet and Codec.decode(packet,limits)
        local routeCount=#sampleTown.drivingMap.routes
        local expectedRouteCount=#sampleTown.drivingMap.destinations*(#sampleTown.drivingMap.destinations-1)
        local expandedRouteCount=0
        for _,route in ipairs(sampleTown.drivingMap.routes) do
            expandedRouteCount=expandedRouteCount+(route.bidirectional and 2 or 1)
        end
        mapSnapshotOkay=packet~=nil and #packet<limits.maxBytes and decoded~=nil
            and Schema.validState(decoded) and Town.valid(decoded.home.town)
            and expandedRouteCount==expectedRouteCount
            and Town.world(decoded.home.town).roads.drivingMap~=nil
        mapSnapshotDetail=encodeError or ('%d route entries, %d/%d bytes'):format(
            routeCount,#(packet or ''),limits.maxBytes)
        if packet then
            print(('DELIVERY_ROUTE_MAP_SNAPSHOT routes=%d points=%d bytes=%d limit=%d'):
                format(routeCount,#sampleTown.drivingMap.points/3,#packet,limits.maxBytes))
        end
    end
    check('delivery_gps_map_roundtrips_in_reliable_town_snapshot',mapSnapshotOkay,mapSnapshotDetail)
    local failureSummary={}
    for i=1,math.min(12,#failures) do failureSummary[#failureSummary+1]=failures[i] end
    print(('DELIVERY_ROUTE_SMOKE_RESULT %d/%d routes; slowest %.1fs (%s -> %s, seed %s); failures=%d'):
        format(successfulRoutes,totalRoutes,slowest.seconds,tostring(slowest.from),tostring(slowest.to),
            tostring(slowest.seed),#failures))
    check('delivery_route_smoke_covers_every_ordered_town_destination_pair',
        totalRoutes>0 and successfulRoutes==totalRoutes,
        ('%d/%d routes; slowest %.1fs (%s -> %s, seed %s); failures=%d: %s'):format(
            successfulRoutes,totalRoutes,slowest.seconds,tostring(slowest.from),tostring(slowest.to),
            tostring(slowest.seed),#failures,table.concat(failureSummary,' | ')))
end

return Test
