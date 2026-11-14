-- Host-owned road traffic uses the player truck controller and stores only the
-- current pose and route cursor for each active shipment.
local Calendar=require('src.business_calendar')
local Truck=require('src.commute.delivery_truck')
local Bike=require('src.commute.motorcycle')
local Footprint=require('src.commute.truck_footprint')
local TrafficRules=require('src.commute.traffic_rules')
local AIMotorcycleTraffic=require('src.commute.ai_motorcycle_traffic')
local TownCharacters=require('src.commute.town_characters')
local EmployeeCommuters=require('src.commute.employee_commute')
local VisitorCommuters=require('src.commute.visitor_commute')
local DrivingPath=require('src.commute.driving_path')
local TrafficActorIndex=require('src.commute.traffic_actor_index')
local AIWatchdog=require('src.ai_watchdog')
local DockManeuver=require('src.commute.dock_maneuver')
local TrafficRecovery=require('src.commute.truck_traffic_recovery')
local WarehouseQueue=require('src.commute.warehouse_queue')
local TrafficBudget=require('src.commute.traffic_budget')
-- Admission limits delay departures; they never hide or delete active traffic.
local Network={CITY='Millhaven',AVERAGE_SPEED=8,MAX_ACTIVE_TRUCKS=16,
    DISPATCH_HEADWAY_SECONDS=8,TRUCK_CAPACITY=10}
local stuckWatch=setmetatable({}, {__mode='k'})
local ruleWatch=setmetatable({}, {__mode='k'})
local maneuverPaths=setmetatable({}, {__mode='k'})
local yardPaths=setmetatable({}, {__mode='k'})
local stopRoutes=setmetatable({}, {__mode='k'})
local leftTurnLaneRoutes=setmetatable({}, {__mode='k'})
local parkedPositionReports=setmetatable({}, {__mode='k'})
local queueCapacityMonitors=setmetatable({}, {__mode='k'})
local lastWorldByState=setmetatable({}, {__mode='k'})
-- Junction reservations belong to the active town world. Weak world keys let
-- abandoned commute worlds release their vehicle claims with the rest of the
-- simulation instead of leaving stale town/coordinate entries behind.
local junctionClaims=setmetatable({}, {__mode='k'})
local trafficClock=0
local TRAFFIC_MAX_STEP=.1
local TRAFFIC_MAX_CATCHUP=.5

local citySites={
    'Millhaven Paper Depot','Millhaven Freight Yard','Millhaven Press Row',
    'Millhaven Commercial Wharf',
}
-- Route records own their derived world, but should only live as long as the
-- immutable town definition that requested them. Town IDs are strings and do
-- not make safe weak keys, so key by the caller's collectible town table.
local routeCache=setmetatable({}, {__mode='k'})

local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge
end
local function hash(text)
    local result=17
    for i=1,#tostring(text or '') do result=(result*131+tostring(text):byte(i))%2147483647 end
    return result
end
local function townWorld(town,activeWorld)
    if type(town)~='table' or type(town.id)~='string' then return nil end
    local activeWorldMatches=type(activeWorld)=='table' and activeWorld.townId==town.id
        and activeWorld.roads and activeWorld.mainlandExit
    local cached=routeCache[town]
    if cached and (not activeWorldMatches or cached.world==activeWorld) then
        return cached
    end
    local world=activeWorld
    if not activeWorldMatches then
        local ok
        ok,world=pcall(require('src.commute.town').world,town)
        if not ok then return nil end
    end
    if not world or not world.mainlandExit then return nil end
    local gate=world.mainlandExit
    local Routes=require('src.commute.routes')
    local integrated=world.truckDestinations~=nil
    local planner=Routes.new(world.roads,{includeTruckOnly=integrated,pavedOnly=true,
        destinations=integrated and world.truckDestinations or nil})
    local site=world.sites.byId.warehouse
    local inward,outward
    if integrated and site and site.truckParking then
        inward=planner:findFromPoint(gate.x,gate.z,'warehouse_truck_dock')
        outward=planner:findFromPoint(site.truckParking.x,site.truckParking.z,'mainland_exit')
    else
        inward=planner:findFromPoint(gate.x,gate.z,'warehouse')
        if inward then
            outward={points={}}
            for i=#inward.points,1,-1 do
                local p=inward.points[i]
                outward.points[#outward.points+1]={x=p.x,z=p.z,h=p.h,speedLimit=p.speedLimit,
                    turnAngle=finite(p.turnAngle) and -p.turnAngle or nil}
            end
        end
    end
    if not inward or not outward or type(inward.points)~='table' or #inward.points<2
        or type(outward.points)~='table' or #outward.points<2 then return nil end
    local function pathLength(points)
        local length=0
        for i=2,#points do
            local a,b=points[i-1],points[i]
            length=length+math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)
        end
        return length
    end
    local length=pathLength(inward.points)
    local outwardLength=pathLength(outward.points)
    if length<1 or outwardLength<1 then return nil end
    -- Outbound trucks disappear with their nose at the virtual gate. Keeping
    -- the center one truck-length inside lets the full footprint stay on-map
    -- while preserving the visible impression of leaving through the edge.
    local keepDistance=math.max(0,outwardLength-Footprint.halfLength-.65)
    local visibleOutward={};local walked=0
    local outwardPoints=outward.points
    if outwardPoints[1] then visibleOutward[1]=outwardPoints[1] end
    for i=2,#outwardPoints do
        local a,b=outwardPoints[i-1],outwardPoints[i]
        local segment=math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)
        if walked+segment>=keepDistance then
            local t=segment>1e-7 and math.max(0,math.min(1,(keepDistance-walked)/segment)) or 1
            visibleOutward[#visibleOutward+1]={x=a.x+(b.x-a.x)*t,z=a.z+(b.z-a.z)*t,
                h=(a.h or 0)+((b.h or a.h or 0)-(a.h or 0))*t}
            break
        end
        walked=walked+segment
        visibleOutward[#visibleOutward+1]=b
    end
    if #visibleOutward>=2 then outwardPoints=visibleOutward end
    cached={world=world,gate=gate,inward=inward.points,outward=outwardPoints,
        length=length,outboundLength=outwardLength,planner=planner,accessIntegrated=integrated,
        truckDestinations=world.truckDestinations}
    routeCache[town]=cached
    return cached
end

local routeSample=DrivingPath.sample

local shipmentCompany

local function appendPoint(points,x,z,h,source)
    local prior=points[#points]
    if not prior or (prior.x-x)^2+(prior.z-z)^2>.25 then
        local point={x=x,z=z,h=h}
        if source then
            point.speedLimit,point.turnAngle=source.speedLimit,source.turnAngle
        end
        points[#points+1]=point
    end
end

local function yardPath(route,base,anchor)
    local points={}
    for _,p in ipairs(base) do appendPoint(points,p.x,p.z,p.h,p) end
    local site=route.world.sites.byId.warehouse
    local parking=site and site.design.truckParking
    if not site or not parking then return points end
    local approachX=parking.x+2.8
    for _,p in ipairs({
        {parking.x,parking.z+7.5},{approachX,parking.z+5.2},
        {approachX,anchor.z},{anchor.x,anchor.z},
    }) do
        local x,z=site:toWorld(p[1],p[2],0)
        appendPoint(points,x,z,route.world:supportHeight(x,z))
    end
    return points
end

local function targetDestination(route,target)
    if target=='dock' then return 'warehouse_truck_dock' end
    local slot=tostring(target):match('^waiting%-(%d+)$')
    return slot and ('warehouse_truck_queue_'..slot) or nil
end

local function deliveryPath(route,vehicle,target,base,anchor)
    if anchor and anchor.points then
        local cached=maneuverPaths[vehicle]
        if not cached or cached.target~=target then
            local best=math.huge
            for i=2,#anchor.points do
                local at=DrivingPath.progress(anchor.points,i,vehicle.x,vehicle.z)
                local p=DrivingPath.sample(anchor.points,nil,at/DrivingPath.length(anchor.points))
                local distance=(p.x-vehicle.x)^2+(p.z-vehicle.z)^2
                if distance<best then vehicle.pathIndex=i;best=distance end
            end
            maneuverPaths[vehicle]={target=target,points=anchor.points}
        end
        return anchor.points
    end
    if route.accessIntegrated then
        yardPaths[vehicle]=nil
        local destination=targetDestination(route,target)
        if not destination then return nil end
        local cached=maneuverPaths[vehicle]
        if not cached or cached.target~=target or vehicle.replanRoute then
            local planned=route.planner:findFromPoint(vehicle.x,vehicle.z,destination)
            if not planned or type(planned.points)~='table' or #planned.points<2 then
                maneuverPaths[vehicle]=nil
                return nil
            end
            cached={target=target,points=planned.points}
            maneuverPaths[vehicle]=cached
            vehicle.replanRoute=nil
            vehicle.pathIndex=2
        end
        return cached.points
    end
    local localStart=vehicle.localManeuver==true
    local cached=yardPaths[vehicle]
    local anchorX,anchorZ=anchor and anchor.x,anchor and anchor.z
    if cached and cached.route==route and cached.target==target
        and cached.localStart==localStart and cached.anchorX==anchorX and cached.anchorZ==anchorZ then
        return cached.points
    end
    local points=yardPath(route,base,anchor)
    yardPaths[vehicle]={route=route,target=target,localStart=localStart,
        anchorX=anchorX,anchorZ=anchorZ,points=points}
    return points
end

local function clamp(value,lo,hi)return math.max(lo,math.min(hi,value))end

local function turnAngle(points,index)
    local at=points[index]
    if at and finite(at.turnAngle) then return at.turnAngle end
    local before,after=points[index-1],points[index+1]
    if not before or not at or not after then return 0 end
    local incoming=math.atan2(at.z-before.z,at.x-before.x)
    local outgoing=math.atan2(after.z-at.z,after.x-at.x)
    return math.atan2(math.sin(outgoing-incoming),math.cos(outgoing-incoming))
end

-- A junction disk describes pavement, not a lane. Match the route's tangent
-- to a real road segment so crossing streets cannot erase the lane offset.
local function routeRoad(roads,x,z,heading)
    local _,nearest=roads:nearest(x,z,true)
    local fx,fz=math.cos(heading),math.sin(heading)
    local key=math.floor(x/(roads.binSize or 16))..':'..math.floor(z/(roads.binSize or 16))
    local best,score
    for _,segment in ipairs(roads.bins and roads.bins[key] or {}) do
        if segment.surface~='dirt' and segment.len and segment.len>0 then
            local alignment=math.abs((segment.dx*fx+segment.dz*fz)/segment.len)
            if alignment>.7 then
                local t=clamp(((x-segment.a.x)*segment.dx+(z-segment.a.z)*segment.dz)/segment.length2,0,1)
                local distance=math.sqrt((x-segment.a.x-t*segment.dx)^2+(z-segment.a.z-t*segment.dz)^2)
                local rank=distance+(1-alignment)*8
                if distance<=segment.width*.5 and (not score or rank<score) then best,score=segment,rank end
            end
        end
    end
    return best or nearest
end

local function leftTurnLaneBlend(points,index,vehicle,world)
    local roads=world.roads
    if not roads or not roads.nearest then return 1 end
    local cached=leftTurnLaneRoutes[points]
    if not cached or cached.roads~=roads then
        local candidates={}
        for i=2,#points-1 do
            local angle=turnAngle(points,i)
            local acrossTraffic=TrafficRules.drivingSide(world.town)=='left' and angle>.32
                or TrafficRules.drivingSide(world.town)~='left' and angle<-.32
            if acrossTraffic then
                local before,at=points[i-1],points[i]
                local dx,dz=at.x-before.x,at.z-before.z
                local length=math.sqrt(dx*dx+dz*dz)
                if length>1e-8 then
                    local setback=math.max(5,math.min(9,length*.7))
                    local mx,mz=at.x-dx/length*setback,at.z-dz/length*setback
                    local incoming=routeRoad(roads,mx,mz,math.atan2(dz,dx))
                    if incoming and incoming.turnLane then
                        candidates[#candidates+1]={index=i,station=DrivingPath.station(points,i)}
                    end
                end
            end
        end
        cached={roads=roads,candidates=candidates}
        leftTurnLaneRoutes[points]=cached
    end
    local candidates=cached.candidates
    local lo,hi=1,#candidates
    while lo<=hi do
        local middle=math.floor((lo+hi)*.5)
        if candidates[middle].index<index then lo=middle+1 else hi=middle-1 end
    end
    local candidate=candidates[lo]
    if not candidate then return 1 end
    local current=DrivingPath.station(points,index)
    local point=points[index]
    local walked=math.sqrt((point.x-vehicle.x)^2+(point.z-vehicle.z)^2)
        +math.max(0,candidate.station-current)
    return clamp((walked-7)/18,0,1)
end

local function laneTarget(points,index,vehicle,target,targetHeading,targetIndex,world,ruleState,dt)
    local roads=world.roads
    if not roads or not roads.nearest then return target end
    local segment=routeRoad(roads,target.x,target.z,targetHeading)
    local side=TrafficRules.drivingSide(world.town)
    local leftBlend=leftTurnLaneBlend(points,index,vehicle,world)
    local offset=TrafficRules.laneOffset(segment,side,false,vehicle)
    if segment and segment.turnLane then offset=offset*leftBlend end
    -- Return to the destination's anchor only on the final approach, never
    -- simply because the route passes through an intersection.
    local remaining=DrivingPath.length(points)-DrivingPath.progress(points,targetIndex,target.x,target.z)
    local wanted=offset*clamp(remaining/12,0,1)
    ruleState.laneOffset=ruleState.laneOffset or wanted
    local blendRate=segment and (segment.bridge or (segment.lanes or 0)<2 or segment.role=='drive')
        and 12 or 4
    ruleState.laneOffset=ruleState.laneOffset+(wanted-ruleState.laneOffset)*clamp(dt*blendRate,0,1)
    local x,z=TrafficRules.lanePoint(target,targetHeading,ruleState.laneOffset,1)
    return {x=x,z=z},segment
end

local function routePassesStop(points,stop,approachX,approachZ)
    local tolerance=math.max(1.1,(stop.roadWidth or 5.8)*.22)
    local bestStation,bestDistance
    for i=2,#points do
        local a,b=points[i-1],points[i]
        local dx,dz=b.x-a.x,b.z-a.z
        local length2=dx*dx+dz*dz
        if length2>1e-8 then
            local t=clamp(((stop.stopX-a.x)*dx+(stop.stopZ-a.z)*dz)/length2,0,1)
            local x,z=a.x+dx*t,a.z+dz*t
            local vx,vz=dx/math.sqrt(length2),dz/math.sqrt(length2)
            local distance2=(x-stop.stopX)^2+(z-stop.stopZ)^2
            if distance2<=tolerance*tolerance and vx*approachX+vz*approachZ>.72
                and (not bestDistance or distance2<bestDistance) then
                bestStation=DrivingPath.station(points,i-1)+math.sqrt(length2)*t
                bestDistance=distance2
            end
        end
    end
    return bestStation
end

local junctionBins=setmetatable({}, {__mode='k'})
local function junctionRadiusIndex(roads)
    local cached=junctionBins[roads]
    if cached then return cached end
    local bins={}
    for index,junction in ipairs(roads.junctions or {}) do
        local ix,iz=math.floor(junction.x*10),math.floor(junction.z*10)
        local key=ix..':'..iz
        local entries=bins[key]
        if not entries then entries={};bins[key]=entries end
        entries[#entries+1]={junction=junction,index=index}
    end
    junctionBins[roads]=bins
    return bins
end

local function junctionRadius(world,x,z)
    local roads=world and world.roads
    if not roads then return 5 end
    local bins=junctionRadiusIndex(roads)
    local centerX,centerZ=math.floor(x*10),math.floor(z*10)
    local best,bestIndex
    for ix=centerX-1,centerX+1 do
        for iz=centerZ-1,centerZ+1 do
            for _,entry in ipairs(bins[ix..':'..iz] or {}) do
                local junction=entry.junction
                if math.abs(junction.x-x)<.1 and math.abs(junction.z-z)<.1
                    and (not bestIndex or entry.index<bestIndex) then
                    best,bestIndex=junction,entry.index
                end
            end
        end
    end
    return best and (best.outerRadius or best.radius or 5) or 5
end

local function stopCandidates(points,world)
    local cached=stopRoutes[points]
    if cached then return cached end
    local result={}
    local fixtures=world.infrastructure and world.infrastructure.fixtures or {}
    for _,fixture in ipairs(fixtures) do
        if fixture.kind=='stop' and finite(fixture.stopX) and finite(fixture.stopZ)
            and finite(fixture.fx) and finite(fixture.fz) then
            local length=math.sqrt(fixture.fx*fixture.fx+fixture.fz*fixture.fz)
            if length>.5 then
                local ax,az=-fixture.fx/length,-fixture.fz/length
                local station=routePassesStop(points,fixture,ax,az)
                if station then
                    local junctionX=fixture.junctionX or fixture.stopX+ax*12
                    local junctionZ=fixture.junctionZ or fixture.stopZ+az*12
                    result[#result+1]={fixture=fixture,station=station,approachX=ax,approachZ=az,
                        roadWidth=fixture.roadWidth or 5.8,junctionX=junctionX,junctionZ=junctionZ,
                        junctionRadius=junctionRadius(world,junctionX,junctionZ),
                        key=('%s:%.1f:%.1f'):format(world.townId or 'town',junctionX,junctionZ)}
                end
            end
        end
    end
    stopRoutes[points]=result
    return result
end

local function nextStopSign(vehicle,points,index,world)
    local best,bestDistance
    local dimensions=TrafficRules.dimensions(vehicle)
    local progress=DrivingPath.progress(points,index,vehicle.x,vehicle.z)
    for _,candidate in ipairs(stopCandidates(points,world)) do
        local fixture=candidate.fixture
        local dx,dz=fixture.stopX-vehicle.x,fixture.stopZ-vehicle.z
        local ahead=dx*candidate.approachX+dz*candidate.approachZ
        local lateral=math.abs(-dx*candidate.approachZ+dz*candidate.approachX)
        local routeDistance=candidate.station-progress
        if routeDistance>=-dimensions.halfLength and routeDistance<30
            and ahead>0 and ahead<26 and lateral<=candidate.roadWidth*.5+dimensions.halfWidth
            and (not bestDistance or ahead<bestDistance) then
            best={fixture=fixture,approachX=candidate.approachX,approachZ=candidate.approachZ,
                distance=ahead,junctionX=candidate.junctionX,junctionZ=candidate.junctionZ,
                junctionRadius=candidate.junctionRadius,key=candidate.key}
            bestDistance=ahead
        end
    end
    return best
end

local function releaseJunctionClaim(vehicle,state,world)
    if not state.junctionKey then return end
    local claims=junctionClaims[world]
    local claim=claims and claims[state.junctionKey]
    if not claim or claim.vehicle~=vehicle then state.junctionKey=nil;return end
    if claim.expires<=trafficClock then
        claims[state.junctionKey]=nil;state.junctionKey=nil;return
    end
    local dx,dz=vehicle.x-state.junctionX,vehicle.z-state.junctionZ
    if dx*dx+dz*dz>(state.junctionRadius+TrafficRules.dimensions(vehicle).radius+1)^2 then
        claims[state.junctionKey]=nil;state.junctionKey=nil
    end
end

local function canEnterJunction(vehicle,stop,world,state)
    local claims=junctionClaims[world]
    local claim=claims and claims[stop.key]
    if claim and claim.expires>trafficClock and claim.vehicle~=vehicle then return false end
    local radius=stop.junctionRadius or junctionRadius(world,stop.junctionX,stop.junctionZ)
    local actors=world.trafficActorIndex
        and world.trafficActorIndex:queryCircle(stop.junctionX,stop.junctionZ,
            radius+TrafficRules.dimensions(vehicle).radius+6)
        or world.trafficActors or {}
    for _,entry in ipairs(actors) do
        local other=entry.actor or entry
        if TrafficRules.actorBlocksJunction(vehicle,other,entry.kind,
            stop.junctionX,stop.junctionZ,radius) then return false end
    end
    if not claims then claims={};junctionClaims[world]=claims end
    claims[stop.key]=setmetatable({vehicle=vehicle,expires=trafficClock+8},{__mode='v'})
    state.junctionKey,state.junctionX,state.junctionZ,state.junctionRadius=
        stop.key,stop.junctionX,stop.junctionZ,radius
    return true
end

local function stopRule(vehicle,points,index,world,dt,state)
    local stop=nextStopSign(vehicle,points,index,world)
    if not stop then
        if state.stopKey and state.stopPassed then state.stopKey=nil;state.stopDwell=0;state.stopPassed=nil end
        return nil,false
    end
    if state.stopKey~=stop.key then
        state.stopKey,state.stopDwell,state.stopPassed=stop.key,0,false
    end
    local centerGap=stop.distance-TrafficRules.dimensions(vehicle).halfLength-.35
    if state.stopPassed then return stop,false end
    if centerGap<=.18 then
        if (vehicle.speed or 0)<.05 then state.stopDwell=(state.stopDwell or 0)+dt
        else state.stopDwell=0 end
        if state.stopDwell>=TrafficRules.STOP_DWELL_SECONDS then
            if canEnterJunction(vehicle,stop,world,state) then
                state.stopPassed=true
                return stop,false
            end
        end
        return stop,true
    end
    return stop,false
end

local function truckAtDock(world,truck)
    local site=world and world.sites and world.sites.byId.warehouse
    local anchor=site and site.design.truckParking
    if not site or not anchor or type(truck)~='table' then return false end
    local x,z=site:toLocal(truck.x,truck.z)
    return math.abs(x-anchor.x)<=1.1/site.scale.x and math.abs(z-anchor.z)<=.9/site.scale.z
end

local function eachDelivery(state,callback)
    for _,shipment in ipairs(state and state.procurement and state.procurement.shipments or {}) do
        callback(shipment.id,shipment.delivery,shipmentCompany(state,shipment))
    end
    local jobs=state and state.jobs
    for _,collection in ipairs({jobs and jobs.active or {},jobs and jobs.completed or {}}) do
        for _,job in ipairs(collection) do
            if job.delivery and job.delivery.route then
                callback(job.id,job.delivery,job.company or 'Millhaven Freight')
            end
            if job.pickup and job.pickup.roadDelivery then
                callback(job.id..':pickup',job.pickup.roadDelivery,job.company or 'Millhaven Freight')
            end
        end
    end
end

local function deliveryEntries(state)
    local result={}
    eachDelivery(state,function(id,delivery,company)
        if type(delivery)=='table' then
            result[#result+1]={id=tostring(id),delivery=delivery,company=company}
        end
    end)
    return result
end

local function palletCountFor(state,id,delivery)
    for _,shipment in ipairs(state and state.procurement and state.procurement.shipments or {}) do
        if tostring(shipment.id)==tostring(id) then
            return require('src.procurement').remainingOnTruck(state,shipment.id)
        end
    end
    local wanted
    if type(delivery.palletIds)=='table' then
        wanted={}
        for _,palletId in ipairs(delivery.palletIds) do wanted[palletId]=true end
    end
    local jobs=state and state.jobs
    for _,collection in ipairs({jobs and jobs.active or {},jobs and jobs.completed or {}}) do
        for _,job in ipairs(collection) do
            if tostring(job.id)==tostring(id) then
                local count=0
                for _,pallet in ipairs(job.pallets or {}) do
                    if pallet.location=='awaiting_delivery' and (not wanted or wanted[pallet.id]) then
                        count=count+1
                    end
                end
                return count
            end
        end
    end
    return 0
end

local function transportGroups(entries)
    local byId,groups,repaired={},{},false
    for _,entry in ipairs(entries) do byId[entry.id]=entry end
    for _,entry in ipairs(entries) do
        local delivery,route=entry.delivery,entry.delivery.route
        if route then
            local transportId=route.transportId
            local leader=transportId and byId[transportId]
            if transportId and (not leader or not leader.delivery.route
                or leader.delivery.route.transportId~=nil) then
                route.transportId=nil
                transportId=nil
                repaired=true
            end
            local owner=transportId or entry.id
            groups[owner]=groups[owner] or {id=owner,leader=transportId and byId[owner] or entry,members={}}
            groups[owner].members[#groups[owner].members+1]=entry
        end
    end
    return byId,groups,repaired
end

local function syncTransportLinks(entries)
    local byId,groups,repaired=transportGroups(entries)
    local changed=repaired
    for _,entry in ipairs(entries) do
        local route=entry.delivery.route
        if route and route.transportId then
            local leader=byId[route.transportId]
            local leadRoute=leader and leader.delivery.route
            if leadRoute then
                for _,field in ipairs({'startAtHours','arrivalAtHours','departedAtEpoch','arrivedAtEpoch','roadTownId'}) do
                    if route[field]~=leadRoute[field] then route[field]=leadRoute[field];changed=true end
                end
                if route.vehicle~=leadRoute.vehicle then
                    if route.vehicle~=nil and leadRoute.vehicle==nil then changed=true end
                    route.vehicle=leadRoute.vehicle
                end
            end
        end
    end
    return changed,byId,groups
end

local function groupReceived(group)
    if not group then return false end
    for _,entry in ipairs(group.members) do
        if entry.delivery.status~='received' then return false end
    end
    return true
end

local function groupPalletCount(state,group)
    local count=0
    for _,entry in ipairs(group and group.members or {}) do
        count=count+palletCountFor(state,entry.id,entry.delivery)
    end
    return count
end

local function canLoadOnTruck(route,epoch)
    if not route or route.vehicle and (route.vehicle.phase=='at_bay'
        or route.vehicle.phase=='waiting_bay' or route.vehicle.phase=='offmap'
        or route.vehicle.phase=='departing') then return false end
    if not finite(route.departedAtEpoch) then return true end
    if route.vehicle then return route.vehicle.phase=='approaching' or route.vehicle.phase=='approaching_wait' end
    return not finite(route.arrivedAtEpoch) or (epoch or os.time())<route.arrivedAtEpoch
end

function Network.inboundTruckPallets(state,id)
    local entries=deliveryEntries(state)
    local byId,groups=transportGroups(entries)
    local entry=byId[tostring(id)]
    if not entry or entry.delivery.status=='received' or not entry.delivery.route then return 0,false end
    local route=entry.delivery.route
    local owner=route.transportId or entry.id
    local group=groups[owner]
    local leadRoute=group and group.leader.delivery.route or route
    return groupPalletCount(state,group),canLoadOnTruck(leadRoute,os.time())
end

local function dockBlocked(state,world,subject)
    local commute=state and state.home and state.home.commute
    if commute and truckAtDock(world,commute.truck) then return true end
    if commute and truckAtDock(world,commute.keiTruck) then return true end
    local occupied=false
    eachDelivery(state,function(_,delivery)
        if occupied or type(delivery)~='table' then return end
        local outbound=delivery.returnRoute and delivery.returnRoute.vehicle
        if outbound and outbound~=subject and outbound.phase~='offmap' and truckAtDock(world,outbound) then
            occupied=true;return
        end
    end)
    return occupied
end

local function gatherDynamicActors(state,town,activeWorld,visitors)
    local vehicles,pedestrians,motorcycles,trafficActors={},{},{},{}
    local commute=state and state.home and state.home.commute
    if commute then
        for _,truck in ipairs(require('src.commute.trip').trucks(commute)) do
            if type(truck)=='table' and Truck.valid(truck) then
                local dims=Footprint.dimensions(truck)
                vehicles[#vehicles+1]=truck
                trafficActors[#trafficActors+1]={actor=truck,id='player-truck-'..(truck.model or 'box'),
                    isPlayer=true,kind='vehicle',halfLength=dims.halfLength,halfWidth=dims.halfWidth}
            end
        end
    end
    if commute then
        for _,part in pairs(commute.participants or {}) do
            if not part.interior and part.rider then
                local rider=part.rider
                if rider.vehicle~='truck' then
                    if rider.gear and rider.gear.mounted and rider.bike then
                        local bike=rider.bike
                        pedestrians[#pedestrians+1]={actor=bike,radius=.62}
                        motorcycles[#motorcycles+1]=bike
                        trafficActors[#trafficActors+1]={actor=bike,id=tostring(part.slot or 'player-bike'),
                            isPlayer=true,kind='bike',radius=.62,halfLength=.65,halfWidth=.38}
                    elseif rider.ped then
                        local ped=rider.ped
                        pedestrians[#pedestrians+1]={x=ped.x,z=ped.z,radius=.55}
                        trafficActors[#trafficActors+1]={actor=ped,id=tostring(part.slot or 'player'),
                            isPlayer=true,kind='pedestrian',radius=.55,halfLength=.3,halfWidth=.55}
                    end
                end
            end
        end
    end
    for _,entry in ipairs(AIMotorcycleTraffic.actors(commute)) do
        local bike=entry.actor
        bike.aiKind='motorcycle';bike.trafficKind='motorcycle';bike.trafficId=entry.id
        pedestrians[#pedestrians+1]={actor=bike,radius=.50}
        motorcycles[#motorcycles+1]=bike
        trafficActors[#trafficActors+1]={actor=bike,id=entry.id,isPlayer=false,kind='bike',
            radius=.50,halfLength=AIMotorcycleTraffic.HALF_LENGTH,
            halfWidth=AIMotorcycleTraffic.HALF_WIDTH}
    end
    town=town or state and state.home and state.home.town
    local now=state and Calendar.absoluteHours(state) or 0
    local scheduled={}
    for _,entry in ipairs(TownCharacters.actors(state and state.home,town,now,activeWorld)) do
        scheduled[#scheduled+1]=entry
    end
    for _,entry in ipairs(EmployeeCommuters.actors(state,town,now,activeWorld)) do
        scheduled[#scheduled+1]=entry
    end
    for _,entry in ipairs(VisitorCommuters.actors(visitors,state,town,now,activeWorld)) do
        scheduled[#scheduled+1]=entry
    end
    for _,entry in ipairs(scheduled) do
        local actor=entry.actor
        if entry.npcCharacter then
            pedestrians[#pedestrians+1]={x=actor.x,z=actor.z,radius=.34}
            trafficActors[#trafficActors+1]={actor=actor,id=entry.id,isPlayer=false,kind='pedestrian',
                radius=.34,height=1.7}
        else
            actor.aiKind='motorcycle';actor.trafficKind='motorcycle';actor.trafficId=entry.id
            pedestrians[#pedestrians+1]={actor=actor,radius=.50}
            motorcycles[#motorcycles+1]=actor
            trafficActors[#trafficActors+1]={actor=actor,id=entry.id,isPlayer=false,kind='bike',
                radius=.50,halfLength=AIMotorcycleTraffic.HALF_LENGTH,
                halfWidth=AIMotorcycleTraffic.HALF_WIDTH}
        end
    end
    local entries=deliveryEntries(state)
    local _,groups=transportGroups(entries)
    for _,entry in ipairs(entries) do
        local delivery=entry.delivery
        local inboundRoute=delivery.route
        if inboundRoute and inboundRoute.transportId then inboundRoute=nil end
        local inboundNeeded=delivery.status~='received'
            or not groupReceived(groups[entry.id])
        local inbound=inboundRoute and inboundNeeded and inboundRoute.vehicle
        local outbound=delivery.returnRoute and delivery.returnRoute.vehicle
        if inbound and inbound.phase~='offmap' then
            inbound.trafficId=entry.id
            local dimensions=Footprint.dimensions(inbound)
            vehicles[#vehicles+1]=inbound
            trafficActors[#trafficActors+1]={actor=inbound,id=entry.id,isPlayer=false,kind='vehicle',
                halfLength=dimensions.halfLength,halfWidth=dimensions.halfWidth}
        end
        if outbound and outbound.phase~='offmap' then
            outbound.trafficId=entry.id..':return'
            local dimensions=Footprint.dimensions(outbound)
            vehicles[#vehicles+1]=outbound
            trafficActors[#trafficActors+1]={actor=outbound,id=entry.id..':return',isPlayer=false,kind='vehicle',
                halfLength=dimensions.halfLength,halfWidth=dimensions.halfWidth}
        end
    end
    return vehicles,pedestrians,motorcycles,trafficActors
end

local function sweepCircles(x,z,nx,nz,radius,otherX,otherZ,otherRadius)
    local dx,dz=nx-x,nz-z
    local ox,oz=x-otherX,z-otherZ
    local combined=radius+otherRadius
    local c=ox*ox+oz*oz-combined*combined
    local a=dx*dx+dz*dz
    local b=2*(ox*dx+oz*dz)
    if c<=0 then
        if b>=0 then return nil end
        local length=math.sqrt(ox*ox+oz*oz)
        if length<1e-8 then
            length=math.sqrt(dx*dx+dz*dz)
            if length<1e-8 then return 0,1,0 end
            return 0,-dx/length,-dz/length
        end
        return 0,ox/length,oz/length
    end
    if a<1e-10 then return nil end
    local discriminant=b*b-4*a*c
    if discriminant<0 then return nil end
    local t=(-b-math.sqrt(discriminant))/(2*a)
    if t<0 or t>1 then return nil end
    local hx,hz=ox+dx*t,oz+dz*t
    local length=math.sqrt(hx*hx+hz*hz)
    if length<1e-8 then return t,1,0 end
    return t,hx/length,hz/length
end

local function installVehicleCollision(world,trafficActors,actorIndex)
    local function forEachNearby(minX,minZ,maxX,maxZ,callback)
        if actorIndex then return actorIndex:forEachBox(minX,minZ,maxX,maxZ,callback) end
        for order,entry in ipairs(trafficActors) do
            local actor=entry.actor or entry
            if finite(actor.x) and finite(actor.z)
                and actor.x>=minX and actor.x<=maxX and actor.z>=minZ and actor.z<=maxZ
                and callback(entry,order,actor)==false then return false end
        end
        return true
    end
    world.vehicleObstacles=function(x,z,heading,subject)
        local c,s=math.cos(heading),math.sin(heading)
        local blocked=false
        forEachNearby(x-Footprint.radius*2,z-Footprint.radius*2,
            x+Footprint.radius*2,z+Footprint.radius*2,function(entry,_,other)
            if entry.kind=='vehicle' then
                if other~=subject and finite(other.heading)
                    and Footprint.overlapsTruck(x,z,heading,other.x,other.z,other.heading,
                        subject and subject.model,other.model) then
                    blocked=true;return false
                end
            elseif Footprint.overlaps(x,z,c,s,other.x,other.z,other.x,other.z,
                entry.radius or entry.halfWidth or .55) then
                blocked=true;return false
            end
        end)
        return blocked
    end
    world.sweepTrafficObstacles=function(x,z,nx,nz,radius,bottom,top,subjectBike)
        local best,nxHit,nzHit,bestKind,bestId,bestPriority,bestOrder
        local activeBike=subjectBike or world.activeTrafficBike
        forEachNearby(
            math.min(x,nx)-radius-Footprint.radius,math.min(z,nz)-radius-Footprint.radius,
            math.max(x,nx)+radius+Footprint.radius,math.max(z,nz)+radius+Footprint.radius,
            function(entry,order,other)
            if entry.kind=='vehicle' then
                if finite(other.heading) then
                    local height=other.h or world:supportHeight(other.x,other.z)
                    local dims=Footprint.dimensions(other)
                    if bottom<=height+dims.height and top>=height then
                        local hit,hx,hz=Footprint.sweepCircle(x,z,nx,nz,radius,
                            other.x,other.z,other.heading,other.model)
                        local tieWins=hit and best and math.abs(hit-best)<=1e-8
                            and (1<bestPriority or 1==bestPriority and order<bestOrder)
                        if hit and (not best or hit<best-1e-8 or tieWins) then
                            best,nxHit,nzHit,bestKind,bestId,bestPriority,bestOrder=hit,hx,hz,
                                'deliveryTruck',other.id or entry.id or other.pathTarget or 'delivery-truck',1,order
                        end
                    end
                end
            elseif entry.kind=='bike' and other~=activeBike then
                    local height=other.h or world:supportHeight(other.x,other.z)
                    if bottom<=height+Bike.COLLISION_HEIGHT and top>=height then
                        local hit,hx,hz=sweepCircles(x,z,nx,nz,radius,other.x,other.z,Bike.RADIUS)
                        local tieWins=hit and best and math.abs(hit-best)<=1e-8
                            and (2<bestPriority or 2==bestPriority and order<bestOrder)
                        if hit and (not best or hit<best-1e-8 or tieWins) then
                            best,nxHit,nzHit,bestKind,bestId,bestPriority,bestOrder=hit,hx,hz,
                                'motorcycleTraffic',other.trafficId or 'ai-motorcycle',2,order
                        end
                    end
            elseif entry.kind=='pedestrian' then
                local height=finite(other.h) and other.h or world:supportHeight(other.x,other.z)
                local pedestrianHeight=entry.height or 1.7
                if bottom<=height+pedestrianHeight and top>=height then
                    local hit,hx,hz=sweepCircles(x,z,nx,nz,radius,other.x,other.z,entry.radius or .55)
                    local tieWins=hit and best and math.abs(hit-best)<=1e-8
                        and (3<bestPriority or 3==bestPriority and order<bestOrder)
                    if hit and (not best or hit<best-1e-8 or tieWins) then
                        best,nxHit,nzHit,bestKind,bestId,bestPriority,bestOrder=hit,hx,hz,
                            'pedestrian',other.id or entry.id or 'pedestrian',3,order
                    end
                end
                end
            end)
        if best then return best,nxHit,nzHit,bestKind,bestId end
    end
end

local function repairBoundaryVehicle(vehicle,record,route,kind,epoch)
    local gate=route.gate
    if not gate or math.sqrt((vehicle.x-gate.x)^2+(vehicle.z-gate.z)^2)>=Footprint.halfLength+.2 then
        return false
    end
    if kind=='outbound' then
        vehicle.phase='offmap';vehicle.speed=0
        record.arrivedAtEpoch=epoch
        return true
    end
    local spawnDistance=Footprint.halfLength+.65
    local sample=routeSample(route.inward,route.length,spawnDistance/route.length)
    if not sample then return false end
    vehicle.x,vehicle.z,vehicle.h,vehicle.heading=sample.x,sample.z,sample.h,sample.heading
    vehicle.speed,vehicle.reverse,vehicle.steering,vehicle.slipAngle=0,false,0,0
    vehicle.pathIndex=DrivingPath.indexAtDistance(route.inward,spawnDistance+1.5)
    vehicle.pathTarget=nil;vehicle.phase='approaching'
    return true
end

local function beginVehicle(delivery,record,route,kind)
    if type(record.vehicle)=='table' then return record.vehicle end
    local site=route.world.sites.byId.warehouse
    if kind=='inbound' then
        -- Keep the full truck footprint inside the playable boundary. The
        -- gate remains a virtual portal; traffic appears on the road just
        -- inside it and follows the same route into town.
        local spawnDistance=Footprint.halfLength+.65
        local sample=routeSample(route.inward,route.length,spawnDistance/route.length)
        if not sample then return nil end
        record.vehicle=Truck.new(sample.x,sample.z,sample.heading,'plain')
        record.vehicle.pathIndex=DrivingPath.indexAtDistance(route.inward,spawnDistance+1.5)
        record.vehicle.phase='approaching'
    else
        local anchor=site and (site.design.truckParking or site.design.truckWaiting)
        if not anchor then return nil end
        local start=delivery.route and delivery.route.vehicle
        local x,z,heading
        if start and start.phase=='at_bay' then x,z,heading=start.x,start.z,start.heading end
        if not x then
            x,z=site:toWorld(anchor.x,anchor.z,0);heading=site.yaw
        end
        record.vehicle=Truck.new(x,z,heading,'plain')
        record.vehicle.phase='departing'
        record.vehicle.pathIndex=2
    end
    if not record.vehicle then return nil end
    local vehicle=record.vehicle
    vehicle.h=route.world:supportHeight(vehicle.x,vehicle.z)
    if finite(delivery.driverSkill) then vehicle.driverSkill=delivery.driverSkill end
    vehicle.pathIndex=vehicle.pathIndex or 2
    vehicle.pathKind=kind;vehicle.pathTarget=nil;vehicle.simRemainder=0
    vehicle.engine=true
    return vehicle
end

local function updateTrafficActorIndex(world,vehicle,kind)
    local index=world.trafficActorIndex
    if not index then return end
    if index:contains(vehicle) then index:update(vehicle);return end
    local dimensions=TrafficRules.dimensions(vehicle)
    index:update(vehicle,{actor=vehicle,id=vehicle.trafficId,kind=kind,
        radius=kind=='bike' and .50 or nil,
        halfLength=dimensions.halfLength,halfWidth=dimensions.halfWidth})
end

local function updateTrafficVehicle(vehicle,steer,desired,hold,dt,world,state)
    local speed=vehicle.speed or 0
    local motorcycle=vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle'
    local acceleration=motorcycle and 1.5 or 1.0
    -- Ramp the requested speed after a stop. Keep the ramp close to actual
    -- motion so waiting behind traffic cannot store a full-throttle launch.
    state.cruiseSpeed=hold and 0 or math.min(desired,
        math.min(state.cruiseSpeed or speed,speed+.5)+acceleration*dt)
    desired=state.cruiseSpeed
    if vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle' then
        local throttle,brake=0,0
        if hold or desired<.01 then brake=1
        elseif speed>desired+.08 then brake=clamp((speed-desired)*1.4,0,1)
        else throttle=clamp(.10+(desired-speed)*.65,.02,.55) end
        world.activeTrafficBike=vehicle
        local moved=Bike.update(vehicle,{throttle=throttle,brake=brake,steer=steer},dt,world)
        world.activeTrafficBike=nil
        updateTrafficActorIndex(world,vehicle,'bike')
        return moved
    end
    world.activeTruck=vehicle
    local drive=-clamp((desired-speed)*1.4+.015,.002,.75)
    local brake=speed>desired+.03 and clamp((speed-desired)*1.4,0,1) or 0
    if hold then drive,brake=0,1 end
    local moved=Truck.update(vehicle,{drive=drive,steer=steer,brake=brake},dt,world)
    world.activeTruck=nil
    updateTrafficActorIndex(world,vehicle,'vehicle')
    return moved
end

local function recoverMotorcycle(vehicle,watch,steer,dt,world)
    world.activeTrafficBike=vehicle
    if watch.reverseFinishing then
        Bike.update(vehicle,{throttle=0,brake=1,steer=0},dt,world)
        if vehicle.speed<.05 then
            if vehicle.reverse then Bike.command(vehicle,'reverse') end
            watch.reverseFinishing=false;watch.cooldown=2
            watch.windowTime,watch.windowMoved,watch.stalled=0,0,0
            vehicle.pathTarget=nil
        end
    else
        if not vehicle.reverse and vehicle.speed<.05 then Bike.command(vehicle,'reverse') end
        if vehicle.reverse then
            Bike.update(vehicle,{drive=1,steer=math.max(-.35,math.min(.35,-steer*.35))},dt,world)
        else
            Bike.update(vehicle,{throttle=0,brake=1,steer=0},dt,world)
        end
        watch.reverseTime=math.max(0,watch.reverseTime-dt)
        if watch.reverseTime==0 then watch.reverseFinishing=true end
    end
    world.activeTrafficBike=nil
    updateTrafficActorIndex(world,vehicle,'bike')
end

local function advanceRouteIndex(vehicle,points,laneOffset)
    local index=math.max(2,math.min(#points,vehicle.pathIndex or 2))
    local laneAllowance=math.abs(laneOffset or 0)+TrafficRules.dimensions(vehicle).halfWidth+2.0
    local crossTrackLimit=math.max(4.2,laneAllowance)
    while index<#points do
        local previous,p=points[index-1],points[index]
        local dx,dz=p.x-previous.x,p.z-previous.z
        local length=math.sqrt(dx*dx+dz*dz)
        local toX,toZ=vehicle.x-p.x,vehicle.z-p.z
        local distance2=toX*toX+toZ*toZ
        local along=toX*dx+toZ*dz
        local crossTrack=length>1e-6 and math.abs(dx*toZ-dz*toX)/length or math.sqrt(distance2)
        local nextPoint=points[index+1]
        local nx,nz=nextPoint.x-p.x,nextPoint.z-p.z
        local nextLength=math.sqrt(nx*nx+nz*nz)
        local nextCross=nextLength>1e-6 and math.abs(nx*toZ-nz*toX)/nextLength or math.huge
        local nextAlignment=nextLength>1e-6 and
            (nx*math.cos(vehicle.heading)+nz*math.sin(vehicle.heading))/nextLength or 0
        -- The inside lane of a sharp turn can join the exit before crossing
        -- the centerline vertex's incoming plane. Recognize that local exit
        -- instead of circling back toward a point behind the vehicle.
        local joinedExit=distance2<=math.max(8,laneAllowance+4)^2 and toX*nx+toZ*nz>0
            and nextAlignment>.5 and nextCross<=crossTrackLimit and nextCross+.5<crossTrack
        -- Curved roads are sampled more closely than the truck can follow
        -- point-by-point. Advance after crossing a waypoint while nearby, so
        -- missing the radius cannot make a driver loop back to a passed point.
        if distance2<=1.35^2 or along>=0 and crossTrack<=crossTrackLimit or joinedExit then index=index+1
        else break end
    end
    if index<#points then
        local a,b=points[index-1],points[index]
        local dx,dz=b.x-a.x,b.z-a.z
        local length2=dx*dx+dz*dz
        local t=length2>1e-8 and clamp(((vehicle.x-a.x)*dx+(vehicle.z-a.z)*dz)/length2,0,1) or 1
        local bestDistance=(vehicle.x-a.x-t*dx)^2+(vehicle.z-a.z-t*dz)^2
        if bestDistance>.25 then
            -- Closely spaced junctions can put a long vehicle onto the exit
            -- before it crosses every centerline waypoint. Rejoin only a
            -- nearby forward segment that agrees with its travel direction.
            -- Do this while still inside the incoming lane's tolerance too:
            -- an inside turn can otherwise orbit its last pre-junction point.
            local walked=0
            for nextIndex=index+1,#points do
                local from,to=points[nextIndex-1],points[nextIndex]
                local nx,nz=to.x-from.x,to.z-from.z
                local length=math.sqrt(nx*nx+nz*nz)
                walked=walked+length
                if walked>20 then break end
                if length>1e-6 and (nx*math.cos(vehicle.heading)+nz*math.sin(vehicle.heading))/length>.7 then
                    local along=((vehicle.x-from.x)*nx+(vehicle.z-from.z)*nz)/(length*length)
                    if along>=0 and along<=1 then
                        local distance=(vehicle.x-from.x-nx*along)^2+(vehicle.z-from.z-nz*along)^2
                        if distance<=crossTrackLimit^2 and distance<bestDistance-.25 then
                            bestDistance=distance;index=nextIndex
                        end
                    end
                end
            end
        end
    end
    vehicle.pathIndex=index
    return index
end

local function routeSpeedLimit(vehicle,points,index,waypointDistance,remaining,headingError)
    local maxSpeed=Truck.MAX_SPEED
    if vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle' then maxSpeed=Bike.MAX_SPEED end
    local desired=math.min(TrafficRules.driverTownSpeed(vehicle),maxSpeed)
    if math.abs(headingError)>.45 then desired=math.min(desired,4.5) end
    if math.abs(headingError)>.95 then desired=math.min(desired,2.8) end
    local routeStation=DrivingPath.progress(points,index,vehicle.x,vehicle.z)
    for _,marker in ipairs(DrivingPath.speedLimits(points)) do
        local turnDistance=marker.distance-routeStation
        -- Reach corner speed before steering into the bend, then retain it
        -- until the rear of the vehicle has followed the exit lane.
        if turnDistance>=-6-TrafficRules.dimensions(vehicle).halfLength then
            if turnDistance<=70 then
                local available=math.max(0,turnDistance-8-TrafficRules.dimensions(vehicle).halfLength)
                desired=math.min(desired,math.sqrt(marker.speed*marker.speed
                    +2*TrafficRules.brakeDeceleration(vehicle)*available))
            else
                break
            end
        end
    end
    return math.min(desired,math.sqrt(math.max(0,
        2*TrafficRules.brakeDeceleration(vehicle)*remaining)))
end

local function driveForward(vehicle,points,dt,world,targetName,watchdogState)
    if not points or #points<2 then return false end
    if vehicle.pathTarget~=targetName then
        local startIndex=vehicle.pathTarget==nil and vehicle.pathIndex or nil
        vehicle.pathTarget=targetName;vehicle.pathIndex=startIndex or 2
    end
    local ruleState=ruleWatch[vehicle]
    if not ruleState then
        ruleState={routeTarget=targetName,passDelta=0,stopDwell=0}
        ruleWatch[vehicle]=ruleState
    elseif ruleState.routeTarget~=targetName then
        ruleState.routeTarget=targetName
        ruleState.stopKey=nil;ruleState.stopDwell=0;ruleState.stopPassed=false
        ruleState.passTarget=nil;ruleState.passingActor=nil;ruleState.passAborting=nil
        ruleState.passEvading=nil;ruleState.passDelta=0
    end
    releaseJunctionClaim(vehicle,ruleState,world)
    local laneOffset=(ruleState.laneOffset or 0)+(ruleState.passDelta or 0)
    local index=advanceRouteIndex(vehicle,points,laneOffset)
    local remaining,waypointDistance=DrivingPath.remaining(points,index,vehicle.x,vehicle.z)
    local _,currentSegment=world.roads:nearest(vehicle.x,vehicle.z,true)
    -- Follow a point several metres ahead instead of steering node-by-node.
    -- The road planner emits closely spaced points, and targeting each one
    -- directly makes long trucks cut or oscillate at junction turns.
    local motorcycle=vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle'
    local yard=currentSegment and (currentSegment.truckOnly or currentSegment.role=='drive')
    local baseLookAhead=(motorcycle or yard) and 3.8 or Truck.profile(vehicle).wheelbase*1.8
    if not motorcycle and not yard then
        local ahead=0
        for i=index,math.min(#points-1,index+16) do
            if math.abs(turnAngle(points,i))>2.1 then baseLookAhead=3.8;break end
            ahead=ahead+math.sqrt((points[i+1].x-points[i].x)^2+(points[i+1].z-points[i].z)^2)
            if ahead>14 then break end
        end
    end
    local lookAhead=baseLookAhead+math.min(2,(vehicle.speed or 0)*.23)
    local target,targetHeading,targetIndex=DrivingPath.lookAhead(points,vehicle.x,vehicle.z,index,lookAhead,true)
    if not yard then
        local side=TrafficRules.drivingSide(world.town)
        local incoming=routeRoad(world.roads,vehicle.x,vehicle.z,vehicle.heading)
        local offset=math.abs(ruleState.laneOffset or TrafficRules.laneOffset(incoming,side,false,vehicle))
        for i=index,math.min(#points-1,targetIndex-1) do
            local angle=turnAngle(points,i)*(side=='left' and -1 or 1)
            if angle>.32 and angle<2.1 then
                -- The inside lane rounds the corner before the centerline.
                -- Include that shortened distance when looking onto the exit;
                -- otherwise a wide road can put the target on the wrong side
                -- of the nose and make the driver circle away from its turn.
                local shortcut=math.min(12,2*offset*math.tan(angle*.5))
                target,targetHeading,targetIndex=DrivingPath.lookAhead(points,vehicle.x,vehicle.z,index,
                    lookAhead+shortcut,true)
                break
            end
        end
    end
    local laneSegment
    target,laneSegment=laneTarget(points,index,vehicle,target,targetHeading,targetIndex,world,ruleState,dt)
    local stop,stopHold=stopRule(vehicle,points,index,world,dt,ruleState)
    local baseLaneOffset=ruleState.laneOffset or 0
    ruleState.passDelta=ruleState.passDelta or 0
    local passingActor=ruleState.passingActor
    local passAbortHold=false
    if passingActor then
        local blockerAhead=finite(passingActor.x) and finite(passingActor.z)
        local forward=0
        if blockerAhead then
            local fx,fz=math.cos(vehicle.heading or 0),math.sin(vehicle.heading or 0)
            forward=(passingActor.x-vehicle.x)*fx+(passingActor.z-vehicle.z)*fz
        end
        local currentOffset=baseLaneOffset+ruleState.passDelta
        local passed=not blockerAhead or forward<-(TrafficRules.dimensions(vehicle).halfLength
            +TrafficRules.dimensions(passingActor).halfLength+1)
        local passLookahead=blockerAhead
            and TrafficRules.passLookaheadSeconds(vehicle,forward,passingActor) or 0
        local returnClear=TrafficRules.laneClear(vehicle,laneSegment,baseLaneOffset,currentOffset,
            world.trafficActors,world.trafficActorIndex,passingActor)
        local mergeGap=forward-TrafficRules.dimensions(vehicle).halfLength
            -TrafficRules.dimensions(passingActor).halfLength
        local canReturn=returnClear and (passed or mergeGap>=TrafficRules.MIN_FOLLOW_GAP)
        local passClear=TrafficRules.laneClear(vehicle,laneSegment,ruleState.passTarget,currentOffset,
            world.trafficActors,world.trafficActorIndex,passingActor,passLookahead)
        if canReturn and (passed or ruleState.passAborting or not passClear) then
            ruleState.passingActor=nil;ruleState.passTarget=nil;ruleState.passAborting=nil
            ruleState.passEvading=nil;passingActor=nil
        elseif not passClear then
            local escapeOffset=TrafficRules.passEscapeOffset(vehicle,laneSegment,ruleState.passTarget,
                currentOffset,world.trafficActors,world.trafficActorIndex,passingActor,passLookahead)
            if escapeOffset then
                -- Move to the far edge of the passing lane when there is room
                -- to clear an oncoming vehicle without leaving the pavement.
                ruleState.passTarget=escapeOffset;ruleState.passAborting=nil;ruleState.passEvading=true
            else
                -- Narrow roads have no safe evasive strip; wait for a merge gap.
                ruleState.passAborting=true;passAbortHold=true
            end
        elseif ruleState.passAborting then
            ruleState.passAborting=nil
        end
    end
    if not passingActor and not passAbortHold and not (stop and not ruleState.stopPassed)
        and not (targetName:match('^waiting%-') and remaining<45)
        and not (currentSegment and currentSegment.junction) then
        local passTarget,blocker=TrafficRules.passLaneOffset(vehicle,laneSegment,baseLaneOffset,
            world.trafficActors,world.trafficActorIndex)
        if passTarget then
            ruleState.passTarget=passTarget;ruleState.passingActor=blocker
            ruleState.passAborting=nil;ruleState.passEvading=nil;passingActor=blocker
        end
    end
    local wantedPassDelta=passingActor and (ruleState.passTarget-baseLaneOffset) or 0
    local passBlend=ruleState.passEvading and clamp(dt*8,0,1) or clamp(dt*1.8,0,1)
    ruleState.passDelta=ruleState.passDelta+(wantedPassDelta-ruleState.passDelta)*passBlend
    local passX,passZ=TrafficRules.lanePoint(target,targetHeading,ruleState.passDelta,1)
    target={x=passX,z=passZ}
    local dx,dz=target.x-vehicle.x,target.z-vehicle.z
    local headingError=math.atan2(math.sin(math.atan2(dz,dx)-vehicle.heading),
        math.cos(math.atan2(dz,dx)-vehicle.heading))
    local steer=math.max(-1,math.min(1,headingError/math.rad(30)))
    local desired=routeSpeedLimit(vehicle,points,index,waypointDistance,remaining,headingError)
    desired=math.min(desired,TrafficRules.roadSpeed(laneSegment),TrafficRules.roadSpeed(currentSegment))
    local localYield
    desired,localYield=TrafficRules.limitForTraffic(vehicle,desired,world.trafficActors,
        laneSegment or currentSegment,world.trafficActorIndex,passingActor)
    if stop and not ruleState.stopPassed then
        local centerGap=stop.distance-TrafficRules.dimensions(vehicle).halfLength-.35
        local stopSpeed=math.sqrt(2*TrafficRules.brakeDeceleration(vehicle)*math.max(0,centerGap))
        desired=math.min(desired,stopSpeed)
    end
    local final=index==#points and waypointDistance<.72
    if passAbortHold then desired=0 end
    local hold=final or stopHold or localYield or passAbortHold
    local watch=stuckWatch[vehicle]
    local routeKey=targetName..':'..index
    if not watch or watch.targetName~=targetName then
        if watch then AIWatchdog.resolve(watchdogState,watch.issueId,{reason='Route stage advanced'}) end
        watch={routeKey=routeKey,targetName=targetName,windowTime=0,windowMoved=0,stalled=0,cooldown=0,
            reverseTime=0,recoveryAttempts=0,
            issueId='road-driver:'..tostring(vehicle.trafficId or vehicle.pathTarget or targetName)}
        stuckWatch[vehicle]=watch
    end
    watch.routeKey=routeKey
    if watch.reverseTime>0 then
        if vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle' then
            recoverMotorcycle(vehicle,watch,steer,dt,world)
        else
            watch.reverseTime=math.max(0,watch.reverseTime-dt)
            world.activeTruck=vehicle
            Truck.update(vehicle,{drive=1,steer=math.max(-.35,math.min(.35,-steer*.35))},dt,world)
            world.activeTruck=nil
            updateTrafficActorIndex(world,vehicle,'vehicle')
        end
        if watch.reverseTime==0 and not watch.reverseFinishing then
            watch.cooldown=2
            watch.windowTime,watch.windowMoved,watch.stalled=0,0,0
            vehicle.pathTarget=nil
            vehicle.replanRoute=true
            watch.waitTime=0;watch.waitX=nil;watch.waitZ=nil
        end
        return false
    end
    if watch.reverseFinishing then
        recoverMotorcycle(vehicle,watch,steer,dt,world)
        return false
    end
    local operationIssueId=watch.issueId..':controller'
    local operationOkay,moved=AIWatchdog.protect(watchdogState,operationIssueId,{
        system='Road traffic',subject=vehicle.trafficId or 'Delivery vehicle',stage=routeKey,
        scope='world-simulation',x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false},
        function()
            return updateTrafficVehicle(vehicle,steer,desired,hold,dt,world,ruleState)
        end,
        function(operationError)
            world.activeTruck=nil;world.activeTrafficBike=nil
            local kind=(vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle') and 'bike' or 'vehicle'
            local rescueOkay,rescued,rescueReason=pcall(function()
                if kind=='bike' then return Bike.rescue(vehicle,world) end
                return Truck.command(vehicle,'rescue',world)
            end)
            if not rescueOkay then rescueReason=tostring(rescued);rescued=false end
            if rescued then
                vehicle.pathTarget=nil
                vehicle.replanRoute=true
                updateTrafficActorIndex(world,vehicle,kind)
                return {ok=true,action='Moved to a collision-checked clear road position and replanned',
                    detail='Controller error: '..operationError}
            end
            -- Keep the rest of the simulation running while the route-level
            -- watchdog retries. Do not leave a partially updated controller
            -- marked as the active vehicle or holding a junction reservation.
            vehicle.speed=0;vehicle.throttle=0;vehicle.brake=1;vehicle.steering=0
            pcall(releaseJunctionClaim,vehicle,ruleState,world)
            pcall(updateTrafficActorIndex,world,vehicle,kind)
            return {ok=false,action='Stopped the faulty vehicle controller; route recovery will retry',
                detail=tostring(rescueReason or 'Safe road recovery was unavailable')}
        end)
    if not operationOkay then
        pcall(releaseJunctionClaim,vehicle,ruleState,world)
        return false
    end
    releaseJunctionClaim(vehicle,ruleState,world)
    watch.cooldown=math.max(0,watch.cooldown-dt)
    if final or stopHold or localYield or passAbortHold then
        -- A moving queue is making progress. Only a stationary wait may
        -- escalate; reverse movement is handled above and cannot erase attempts.
        if not watch.waitX or (vehicle.x-watch.waitX)^2+(vehicle.z-watch.waitZ)^2>.4^2 then
            watch.waitX,watch.waitZ=vehicle.x,vehicle.z
            watch.waitTime=0
        end
        watch.waitTime=(watch.waitTime or 0)+dt
        local queueHold=targetName:match('^waiting%-') and remaining<35 and localYield
        if queueHold then watch.waitTime=0 end
        if not final and watch.waitTime>=12 and not watch.waitReported then
            watch.waitReported=true
            AIWatchdog.note(watchdogState,watch.issueId,{status='STALLED',system='Road traffic',
                subject=vehicle.trafficId or 'Delivery vehicle',stage=routeKey,
                reason='Traffic wait has prevented route progress for 12 seconds',
                action='Waiting for clearance; prolonged stationary waits trigger reverse and safe road recovery',
                detail=('yield=%s stop=%s passing=%s desired=%.2f waypoint=%d')
                    :format(tostring(localYield),tostring(stopHold),tostring(passAbortHold),desired,index),
                elapsed=watch.waitTime,x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,
                scope='world-simulation'})
        end
        local waitLimit=(stopHold and 30 or 12)+hash(vehicle.trafficId or targetName)%21/10
        if not final and watch.waitTime>=waitLimit and watch.cooldown<=0 then
            -- Driving back to the same blockage after reversing is not a
            -- recovery. Keep these attempts until we pass the original stall.
            watch.recoveryAttempts=watch.recoveryAttempts+1
            watch.recoveryProgressMark=watch.recoveryProgressMark or remaining
            watch.recoveryRoute=watch.recoveryRoute or points
            local rescued,reason=false,nil
            if watch.recoveryAttempts>=3 then
                if vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle' then
                    -- Motorcycle recovery already checks terrain and traffic.
                    rescued,reason=Bike.rescue(vehicle,world)
                else
                    rescued,reason=TrafficRecovery.rescue(vehicle,watch.recoveryRoute,world)
                end
            end
            local action='Backing away under collision control, then retrying the route'
            if rescued then
                local claims=junctionClaims[world]
                local claim=claims and claims[ruleState.junctionKey]
                if claim and claim.vehicle==vehicle then claims[ruleState.junctionKey]=nil end
                ruleWatch[vehicle]=nil;maneuverPaths[vehicle]=nil;yardPaths[vehicle]=nil
                DockManeuver.clear(vehicle,watchdogState,'Traffic deadlock recovery')
                vehicle.pathTarget=nil;vehicle.replanRoute=true
                watch.cooldown=2
                updateTrafficActorIndex(world,vehicle,
                    (vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle') and 'bike' or 'vehicle')
                action='Rescue moved the vehicle to a clear road position behind the obstruction; route retained'
            else
                watch.reverseTime=1.6
                if reason then action='No clear rescue position; backing away and retrying' end
            end
            AIWatchdog.note(watchdogState,watch.issueId,{status='RECOVERING',system='Road traffic',
                subject=vehicle.trafficId or 'Delivery vehicle',stage=routeKey,
                reason='Prolonged stationary traffic wait',action=action,detail=reason,
                elapsed=watch.waitTime,attempt=watch.recoveryAttempts,x=vehicle.x,z=vehicle.z,
                visible=vehicle.visible~=false,scope='world-simulation'})
            watch.waitTime=0;watch.waitX=nil;watch.waitZ=nil
            return false
        end
        watch.windowTime,watch.windowMoved,watch.stalled=0,0,0
        if final then AIWatchdog.resolve(watchdogState,watch.issueId,{reason='Route waypoint reached',
            x=vehicle.x,z=vehicle.z}) end
    else
        if watch.recoveryProgressMark and remaining<watch.recoveryProgressMark-5 then
            watch.recoveryAttempts=0;watch.recoveryProgressMark=nil
            watch.recoveryRoute=nil
        end
        if watch.waitReported then
            AIWatchdog.resolve(watchdogState,watch.issueId,{reason='Traffic obstruction cleared; driving resumed'})
        end
        watch.waitTime=0;watch.waitReported=false
        watch.waitX=nil;watch.waitZ=nil
        if watch.windowTime==0 then watch.windowStartDistance=remaining end
        watch.windowTime=watch.windowTime+dt
        watch.windowMoved=watch.windowMoved+moved
        if watch.windowTime>=1 then
            -- Slow, deliberate crawling is progress too. Judge it against the
            -- requested speed instead of demanding walking speed from a truck.
            local minimumProgress=math.max(.03,math.min(.25,desired*.1))
            local madeProgress=watch.windowStartDistance-remaining>=minimumProgress
            if watch.windowMoved<.03 or not madeProgress then watch.stalled=watch.stalled+watch.windowTime
            else
                watch.stalled=0
                AIWatchdog.resolve(watchdogState,watch.issueId,{reason='Vehicle resumed route progress',
                    x=vehicle.x,z=vehicle.z})
            end
            watch.windowTime,watch.windowMoved=0,0
        end
        if watch.stalled>=4.5 and watch.cooldown<=0 then
            watch.recoveryAttempts=watch.recoveryAttempts+1
            watch.recoveryProgressMark=watch.recoveryProgressMark or remaining
            watch.recoveryRoute=watch.recoveryRoute or points
            local action='Backed away from the obstruction and retried the same route'
            local rescued,rescueReason=false,nil
            if watch.recoveryAttempts>=3 then
                if vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle' then
                    rescued,rescueReason=Bike.rescue(vehicle,world)
                else
                    rescued,rescueReason=Truck.command(vehicle,'rescue',world)
                end
                if rescued then
                    action='Moved to a collision-checked clear road position and replanned'
                    watch.reverseTime=0;watch.reverseFinishing=false;watch.cooldown=2
                    watch.windowTime,watch.windowMoved,watch.stalled=0,0,0
                    vehicle.pathTarget=nil
                    vehicle.replanRoute=true
                    local kind=(vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle') and 'bike' or 'vehicle'
                    updateTrafficActorIndex(world,vehicle,kind)
                else
                    action='Safe road recovery was blocked; backing away and retrying'
                    watch.reverseTime=1.6;watch.stalled=0
                end
            else
                -- The vehicle controller still owns acceleration, steering,
                -- and every collision check during the reverse maneuver.
                watch.reverseTime=1.6;watch.stalled=0
            end
            AIWatchdog.note(watchdogState,watch.issueId,{status=rescued and 'RECOVERING' or 'STALLED',
                system='Road traffic',subject=vehicle.trafficId or 'Delivery vehicle',stage=routeKey,
                reason='No safe route progress for 4.5 seconds',action=action,
                detail=rescueReason,x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,
                scope='world-simulation'})
            if rescued then return false end
        end
    end
    if final and vehicle.speed<.3 then return true end
    return false
end

local function driveVehicle(vehicle,points,dt,world,targetName,watchdogState)
    local plan=DockManeuver.plan(vehicle,points,world,watchdogState)
    if not plan then
        DockManeuver.clear(vehicle,watchdogState,'Truck switched to another route')
        return driveForward(vehicle,points,dt,world,targetName,watchdogState)
    end
    if plan.stage=='approach' then
        if not driveForward(vehicle,plan.forward,dt,world,targetName,watchdogState) then return false end
        plan.stage='reverse'
    end
    local okay,arrived=AIWatchdog.protect(watchdogState,
        'delivery-dock-controller:'..tostring(vehicle.trafficId or 'truck'),{
            system='Delivery docking',subject=vehicle.trafficId or 'Delivery truck',stage='backing_to_dock',
            x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,scope='world-simulation'},
        function()return DockManeuver.reverse(vehicle,plan,dt,world,watchdogState)end,
        function()
            world.activeTruck=nil
            vehicle.speed=0;vehicle.steering=0;vehicle.slipAngle=0;vehicle.throttle=0;vehicle.brake=1
            return {ok=true,action='Stopped the faulty docking controller and will retry next simulation step'}
        end)
    updateTrafficActorIndex(world,vehicle,'vehicle')
    return okay and arrived
end

-- Shared route follower for autonomous delivery traffic. Keeping this entry
-- point public lets terrain smoke tests exercise the exact production driver
-- against every generated town address instead of a test-only steering copy.
Network.driveRoute=function(vehicle,points,dt,world,targetName,watchdogState)
    trafficClock=trafficClock+math.max(0,finite(dt) and dt or 0)
    return driveVehicle(vehicle,points,dt,world,targetName,watchdogState)
end

-- Scheduled commuters use the same lane geometry and stop fixtures when
-- deriving their deterministic, clock-sampled journeys on every peer.
function Network.lanePosition(vehicle,points,sample,world)
    return laneTarget(points,sample.pathIndex,vehicle,sample,sample.heading,sample.pathIndex,world,{},1)
end
Network.routeStops=stopCandidates

local function firstOrder(state,shipment)
    local wanted={}
    for _,id in ipairs(shipment.orderIds or {}) do wanted[id]=true end
    for _,order in ipairs(state.procurement and state.procurement.orders or {}) do
        if wanted[order.id] then return order end
    end
end

local function sourceLocation(state,shipment)
    local order=firstOrder(state,shipment)
    if order and order.category=='paper' then return citySites[1] end
    local index=(hash(shipment.id)+1)%#citySites+1
    return citySites[index]
end

shipmentCompany=function(state,shipment)
    local wanted,companies={},{}
    for _,id in ipairs(shipment.orderIds or {}) do wanted[id]=true end
    for _,order in ipairs(state.procurement and state.procurement.orders or {}) do
        if wanted[order.id] then
            local company=order.company or order.vendor
            if type(company)=='string' and company~='' and not companies[company] then
                companies[company]=true
            end
        end
    end
    local only,count=nil,0
    for company in pairs(companies) do only=company;count=count+1 end
    if count==1 then return only end
    return 'Millhaven Freight'
end

local function updateTrackedDelivery(delivery,company,location,id,now,durationHours,outboundDurationHours,route,epoch)
    if type(delivery)~='table' then return false end
    local expected=tonumber(delivery.readyAtHours)
    local changed=false
    if delivery.status=='pending_arrival' and expected and not delivery.route then
        delivery.route={originCity=Network.CITY,originLocation=location,
            originCompany=company,destination='warehouse',startAtHours=expected-durationHours,
            arrivalAtHours=expected,roadTownId=id}
        changed=true
    end
    local inbound=delivery.route
    if inbound and inbound.roadTownId~=id then
        inbound.roadTownId=id
        if expected then inbound.startAtHours=expected-durationHours end
        inbound.vehicle=nil
        changed=true
    end
    local outbound=delivery.returnRoute
    if outbound and outbound.roadTownId~=id then
        local start=tonumber(outbound.startAtHours) or now
        outbound.roadTownId=id;outbound.arrivalAtHours=start+outboundDurationHours
        outbound.departedAtEpoch=outbound.departedAtEpoch or epoch
        outbound.arrivedAtEpoch=outbound.departedAtEpoch+route.outboundLength/Network.AVERAGE_SPEED
        outbound.vehicle=nil
        changed=true
    end
    return changed
end

local function dispatchInbound(state,entries,groups,route,now,epoch)
    local duration=route.length/Network.AVERAGE_SPEED*24/math.max(1,Calendar.secondsPerDay(state))
    if require('src.business_hours').nextService(now,duration)>now+1e-7 then return false end
    local carriers,activeCount={},0
    local lastDeparture,queued,inboundCount=-math.huge,0,0
    local gateClear=true
    local gate=route.inward[1]
    for _,entry in ipairs(entries) do
        local delivery=entry.delivery
        local inbound,outbound=delivery.route,delivery.returnRoute
        if inbound and not inbound.transportId and finite(inbound.departedAtEpoch) then
            lastDeparture=math.max(lastDeparture,inbound.departedAtEpoch)
            local vehicle=inbound.vehicle
            if delivery.status~='received' and (not vehicle or vehicle.phase~='offmap') then
                inboundCount=inboundCount+1
            end
        end
        if outbound and finite(outbound.departedAtEpoch) and not (inbound and inbound.transportId)
            and (outbound.vehicle and outbound.vehicle.phase~='offmap'
                or not outbound.vehicle and (outbound.arrivedAtEpoch or math.huge)>epoch) then
            activeCount=activeCount+1
        end
        local vehicle=delivery.status=='received' and outbound and outbound.vehicle or inbound and inbound.vehicle
        if vehicle and vehicle.phase~='offmap' and not (inbound and inbound.transportId) then
            if vehicle.phase=='waiting_bay' then queued=queued+1 end
            if finite(vehicle.x) and finite(vehicle.z)
                and (vehicle.x-gate.x)^2+(vehicle.z-gate.z)^2<15^2 then gateClear=false end
        end
    end
    for _,entry in ipairs(entries) do
        local group=groups[entry.id]
        local inbound=entry.delivery.route
        if group and group.leader==entry and inbound and not inbound.transportId
            and finite(inbound.departedAtEpoch) and not groupReceived(group)
            and not (inbound.vehicle and inbound.vehicle.phase=='offmap') then
            local carrier={id=entry.id,group=group,route=inbound,
                pallets=groupPalletCount(state,group),canLoad=not entry.delivery.customerPickup
                    and canLoadOnTruck(inbound,epoch)}
            carriers[#carriers+1]=carrier
            activeCount=activeCount+1
        end
    end
    table.sort(carriers,function(a,b)
        if a.pallets~=b.pallets then return a.pallets>b.pallets end
        return a.id<b.id
    end)

    local due={}
    for _,entry in ipairs(entries) do
        local delivery,inbound=entry.delivery,entry.delivery.route
        if inbound and not inbound.transportId and delivery.status~='received'
            and not finite(inbound.departedAtEpoch) and finite(inbound.startAtHours)
            and now>=inbound.startAtHours then
            local pallets=palletCountFor(state,entry.id,delivery)
            if pallets>0 or delivery.customerPickup then due[#due+1]={entry=entry,pallets=pallets} end
        end
    end
    table.sort(due,function(a,b)
        local aStart=a.entry.delivery.route.startAtHours or 0
        local bStart=b.entry.delivery.route.startAtHours or 0
        if aStart~=bStart then return aStart<bStart end
        return a.entry.id<b.entry.id
    end)

    local changed=false
    local dockOccupied=dockBlocked(state,route.world)
    local queueCapacity=WarehouseQueue.capacity(route)
    local inboundCapacity=math.min(Network.MAX_ACTIVE_TRUCKS,queueCapacity+(dockOccupied and 0 or 1))
    for _,item in ipairs(due) do
        local entry=item.entry
        local inbound=entry.delivery.route
        local best,bestRemainder
        if not entry.delivery.customerPickup and item.pallets<=Network.TRUCK_CAPACITY then
            for _,carrier in ipairs(carriers) do
                if carrier.canLoad and carrier.pallets+item.pallets<=Network.TRUCK_CAPACITY then
                    local remainder=Network.TRUCK_CAPACITY-carrier.pallets-item.pallets
                    if not best or remainder<bestRemainder then best,bestRemainder=carrier,remainder end
                end
            end
        end
        if best then
            inbound.transportId=best.id
            for _,field in ipairs({'startAtHours','arrivalAtHours','departedAtEpoch','arrivedAtEpoch','roadTownId'}) do
                inbound[field]=best.route[field]
            end
            inbound.vehicle=best.route.vehicle
            if entry.company~=best.group.leader.company then
                best.route.originCompany='Millhaven Freight'
            end
            best.group.members[#best.group.members+1]=entry
            best.pallets=best.pallets+item.pallets
            changed=true
        elseif activeCount<Network.MAX_ACTIVE_TRUCKS and inboundCount<inboundCapacity
            and gateClear and TrafficBudget.allows(state,activeCount)
            and epoch-lastDeparture>=Network.DISPATCH_HEADWAY_SECONDS
            and queued<queueCapacity then
            inbound.departedAtEpoch=epoch
            inbound.arrivedAtEpoch=epoch+route.length/Network.AVERAGE_SPEED
            local group=groups[entry.id] or {id=entry.id,leader=entry,members={entry}}
            groups[entry.id]=group
            carriers[#carriers+1]={id=entry.id,group=group,route=inbound,
                pallets=item.pallets,canLoad=not entry.delivery.customerPickup and item.pallets<Network.TRUCK_CAPACITY}
            activeCount=activeCount+1
            inboundCount=inboundCount+1
            lastDeparture=epoch
            changed=true
        end
    end
    return changed
end

local function createReturnRoutes(state,entries,groups,now,epoch,durationHours,townId)
    local changed=false
    for _,entry in ipairs(entries) do
        local delivery,inbound=entry.delivery,entry.delivery.route
        local group=groups[entry.id]
        if inbound and not inbound.transportId and not delivery.returnRoute
            and delivery.status=='received' and groupReceived(group) then
            local start=now
            local destinationLocation=inbound.originLocation or Network.cityLocationFor(entry.id)
            delivery.returnRoute={origin='warehouse',destinationCity=Network.CITY,
                destinationLocation=destinationLocation,originCompany=entry.company or 'Millhaven Freight',
                startAtHours=start,arrivalAtHours=start+durationHours,departedAtEpoch=epoch,
                arrivedAtEpoch=epoch+durationHours*Calendar.secondsPerDay(state)/24,
                roadTownId=townId}
            changed=true
        end
    end
    return changed
end

function Network.update(state,town,now,epoch,activeWorld)
    if type(state)~='table' then return false end
    local companyTruck=require('src.company_delivery_driver')
    local companyState=state.employment and state.employment.companyTruck
    local companyActive=companyState and (companyState.deliveryRun~=nil
        or companyState.status=='refueling' or companyState.departureStage~=nil)
    local shipments=state.procurement and state.procurement.shipments or {}
    local jobs=state.jobs
    local activeJobs=jobs and jobs.active or {}
    local completedJobs=jobs and jobs.completed or {}
    if #shipments==0 and #activeJobs==0 and #completedJobs==0 and not companyActive then return false end
    local route=townWorld(town,activeWorld)
    if not route then return false end
    now=finite(now) and now or Calendar.absoluteHours(state)
    epoch=finite(epoch) and epoch or os.time()
    local durationHours=route.length/Network.AVERAGE_SPEED*24/math.max(1,Calendar.secondsPerDay(state))
    local outboundDurationHours=route.outboundLength/Network.AVERAGE_SPEED*24/math.max(1,Calendar.secondsPerDay(state))
    local changed=companyTruck.updateExterior(state,route.world,epoch,now)
    if companyActive then
        changed=companyTruck.update(state,now,true) or changed
        companyTruck.syncTripVehicle(state)
    end
    for _,shipment in ipairs(shipments) do
        local delivery=shipment.delivery
        local expected=delivery and tonumber(delivery.expectedAtHours)
        if delivery and expected and delivery.status~='received' and not delivery.route then
            delivery.route={originCity=Network.CITY,originLocation=sourceLocation(state,shipment),
                originCompany=shipmentCompany(state,shipment),destination='warehouse',startAtHours=expected-durationHours,
                arrivalAtHours=expected,roadTownId=town.id}
            changed=true
        end
        if delivery and delivery.route and delivery.route.roadTownId~=town.id then
            delivery.route.roadTownId=town.id
            if expected then delivery.route.startAtHours=expected-durationHours end
            delivery.route.vehicle=nil
            changed=true
        end
        if delivery and delivery.returnRoute and delivery.returnRoute.roadTownId~=town.id then
            local start=tonumber(delivery.returnRoute.startAtHours) or now
            delivery.returnRoute.roadTownId=town.id
            delivery.returnRoute.arrivalAtHours=start+outboundDurationHours
            delivery.returnRoute.departedAtEpoch=delivery.returnRoute.departedAtEpoch or epoch
            delivery.returnRoute.arrivedAtEpoch=delivery.returnRoute.arrivedAtEpoch
                or delivery.returnRoute.departedAtEpoch+route.outboundLength/Network.AVERAGE_SPEED
            delivery.returnRoute.vehicle=nil
            changed=true
        end
    end
    for _,collection in ipairs({activeJobs,completedJobs}) do
        for _,job in ipairs(collection) do
            local delivery=job.delivery
            local company=job.company or 'Millhaven Freight'
            changed=updateTrackedDelivery(delivery,company,Network.cityLocationFor(job.id),town.id,
                now,durationHours,outboundDurationHours,route,epoch) or changed
            local pickup=job.pickup
            if pickup and not pickup.driverMode and pickup.status~='player_delivery' then
                if not pickup.roadDelivery and (job.status=='ready_for_pickup' or job.status=='pickup_in_progress') then
                    pickup.dispatchAtHours=pickup.dispatchAtHours or now+.5
                    pickup.roadDelivery={status='pending_arrival',customerPickup=true,
                        readyAtHours=pickup.dispatchAtHours+durationHours}
                    changed=true
                    updateTrackedDelivery(pickup.roadDelivery,company,Network.cityLocationFor(job.id),town.id,
                        now,durationHours,outboundDurationHours,route,epoch)
                    -- Existing saves may already have the warehouse pickup
                    -- loading. Restore its exterior at the dock, not at the gate.
                    if pickup.status~='awaiting_schedule' then
                        local inbound=pickup.roadDelivery.route
                        inbound.departedAtEpoch=epoch-route.length/Network.AVERAGE_SPEED-2
                        inbound.arrivedAtEpoch=epoch-1
                    end
                end
                local road=pickup.roadDelivery
                if road then
                    if pickup.status=='completed' and road.status~='received' then
                        road.status='received';road.receivedAtHours=now;changed=true
                    end
                    changed=updateTrackedDelivery(road,company,Network.cityLocationFor(job.id),town.id,
                        now,durationHours,outboundDurationHours,route,epoch) or changed
                end
            end
        end
    end
    local entries=deliveryEntries(state)
    -- ETAs and actual dispatch use the same receiving window. Also repair
    -- undispatched routes loaded from older saves or held in a full queue.
    local hours=require('src.business_hours')
    for _,entry in ipairs(entries) do
        local delivery=entry.delivery;local inbound=delivery.route
        if inbound and not inbound.transportId and not finite(inbound.departedAtEpoch) then
            local start=hours.nextService(inbound.startAtHours or now,durationHours)
            if hours.nextService(now,durationHours)>now+1e-7 then
                start=math.max(start,hours.nextService(now,durationHours))
            end
            if inbound.startAtHours~=start then
                inbound.startAtHours=start;inbound.arrivalAtHours=start+durationHours
                if delivery.readyAtHours then delivery.readyAtHours=inbound.arrivalAtHours end
                if delivery.expectedAtHours then delivery.expectedAtHours=inbound.arrivalAtHours end
                changed=true
            end
        end
    end
    local linksChanged,_,groups=syncTransportLinks(entries)
    changed=linksChanged or changed
    changed=dispatchInbound(state,entries,groups,route,now,epoch) or changed
    local linkedAgain,_,updatedGroups=syncTransportLinks(entries)
    changed=linkedAgain or changed
    changed=createReturnRoutes(state,entries,updatedGroups,now,epoch,outboundDurationHours,town.id) or changed
    return changed
end

local function simulateDelivery(delivery,route,dt,state,epoch,world,entryId,queue)
    if type(delivery)~='table' then return false end
    local inbound,outbound=delivery.route,delivery.returnRoute
    local record,kind
    if delivery.status=='received' and outbound and finite(outbound.departedAtEpoch)
        and epoch>=outbound.departedAtEpoch
        and (outbound.vehicle and outbound.vehicle.phase~='offmap'
            or not outbound.vehicle and (not finite(outbound.arrivedAtEpoch) or epoch<outbound.arrivedAtEpoch)) then
        record,kind=outbound,'outbound'
    elseif delivery.status~='received' and inbound and finite(inbound.departedAtEpoch)
        and epoch>=inbound.departedAtEpoch then
        record,kind=inbound,'inbound'
    else return false end

    local vehicle=record.vehicle
    local created=vehicle==nil
    if vehicle and (not Truck.valid(vehicle) or type(vehicle.phase)~='string') then
        record.vehicle=nil;vehicle=nil;created=true
    end
    vehicle=vehicle or beginVehicle(delivery,record,route,kind)
    if not vehicle or dt<=0 then return false end
    vehicle.trafficId=tostring(entryId or 'delivery')..(kind=='outbound' and ':return' or '')
    if finite(delivery.driverSkill) then vehicle.driverSkill=delivery.driverSkill end
    local boundaryRepaired=repairBoundaryVehicle(vehicle,record,route,kind,epoch)
    if kind=='outbound' and inbound and inbound.vehicle and inbound.vehicle~=vehicle then
        inbound.vehicle.phase='offmap'
    end
    local changed=created or boundaryRepaired
    local step=math.min(.1,dt)
    if kind=='outbound' then
        if vehicle.phase=='offmap' then return changed end
        local site=route.world.sites.byId.warehouse
        local points={}
        if route.accessIntegrated then
            points=route.outward
        else
            local anchor=site and (site.design.truckParking or site.design.truckWaiting)
            local approachX=anchor and anchor.x+2.8
            if site and anchor then
                for _,p in ipairs({{approachX,anchor.z},{approachX,anchor.z+5.2},{anchor.x,anchor.z+7.5}}) do
                    local x,z=site:toWorld(p[1],p[2],0);appendPoint(points,x,z,route.world:supportHeight(x,z))
                end
            end
            for _,p in ipairs(route.outward) do appendPoint(points,p.x,p.z,p.h,p) end
        end
        if driveVehicle(vehicle,points,step,world,'outbound',state) then
            vehicle.phase='offmap';vehicle.speed=0;outbound.arrivedAtEpoch=epoch;changed=true
        elseif vehicle.speed>.02 then vehicle.phase='departing' end
    else
        local site=route.world.sites.byId.warehouse
        if not site or not site.design.truckParking then return false end
        local assignment=queue[inbound]
        if not assignment then return changed end
        local target,anchor=assignment.target,assignment.anchor
        local blocked=assignment.slot~=nil
        if not anchor then
            local monitor=queueCapacityMonitors[vehicle]
            if not monitor then monitor={};queueCapacityMonitors[vehicle]=monitor end
            local localX,localZ=site:toLocal(vehicle.x,vehicle.z)
            AIWatchdog.observe(state,monitor,{issueId='delivery-queue-capacity:'..tostring(vehicle.trafficId),
                system='Shop driveway',subject=vehicle.trafficId or 'Delivery truck',stage='queue_capacity',
                dt=step,timeout=3,retryDelay=3,
                reason='The generated route has no safe remaining truck queue position',
                detail=('target=%s slot=%s capacity=%s local=%.1f,%.1f'):format(tostring(target),
                    tostring(assignment.slot),tostring(assignment.capacity),localX,localZ),
                x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,scope='world-simulation',
                recover=function()
                    return {ok=false,action='Holding this truck while the warehouse queue advances'}
                end})
            return changed
        end
        local queueMonitor=queueCapacityMonitors[vehicle]
        if queueMonitor then AIWatchdog.clear(state,queueMonitor,'A safe warehouse queue position is available') end
        queueCapacityMonitors[vehicle]=nil
        if created and finite(inbound.departedAtEpoch) and finite(inbound.arrivedAtEpoch)
            and epoch>inbound.departedAtEpoch+1 then
            if epoch>=inbound.arrivedAtEpoch then
                vehicle.x,vehicle.z=site:toWorld(anchor.x,anchor.z,0)
                vehicle.heading=anchor.heading or (blocked and (site.yaw-math.pi*.5) or site.yaw)
                vehicle.h=world:supportHeight(vehicle.x,vehicle.z)
                vehicle.speed=0;vehicle.phase=blocked and 'waiting_bay' or 'at_bay'
                vehicle.pathTarget=target;vehicle.pathIndex=2
                if blocked and not vehicle.noticeSent then
                    vehicle.noticeSent=true
                    state.message='A delivery truck is waiting outside. Move the Picture Shop truck to clear the loading bay.'
                end
                return true
            end
            local elapsed=math.max(0,epoch-inbound.departedAtEpoch)
            local duration=math.max(1,inbound.arrivedAtEpoch-inbound.departedAtEpoch)
            local progress=math.max(0,math.min(1,elapsed/duration))
            local sample=routeSample(route.inward,route.length,progress)
            if sample then
                vehicle.x,vehicle.z,vehicle.h,vehicle.heading=sample.x,sample.z,sample.h,sample.heading
                local travelled=progress*route.length;local walked=0
                for i=2,#route.inward do
                    local a,b=route.inward[i-1],route.inward[i]
                    local segment=math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)
                    if travelled<=walked+segment or i==#route.inward then
                        vehicle.pathIndex=i;break
                    end
                    walked=walked+segment
                end
                vehicle.pathTarget=target
            end
        end
        if blocked and not vehicle.noticeSent then
            local x,z=site:toWorld(site.design.truckParking.x,site.design.truckParking.z,0)
            if (vehicle.x-x)^2+(vehicle.z-z)^2<30^2 then
                vehicle.noticeSent=true
                state.message='A delivery truck is approaching, but the loading bay is occupied. Move the Picture Shop truck to clear it.'
                changed=true
            end
        end
        local anchorX,anchorZ=site:toWorld(anchor.x,anchor.z,0)
        local atAssignedPosition=(vehicle.x-anchorX)^2+(vehicle.z-anchorZ)^2<1.2^2
        if vehicle.pathTarget==target
            and (vehicle.phase=='waiting_bay' and blocked or vehicle.phase=='at_bay' and not blocked)
            and atAssignedPosition then
            vehicle.speed=0
            local reportedTarget=parkedPositionReports[vehicle]
            if reportedTarget then
                AIWatchdog.resolve(state,'delivery-park-position:'..tostring(vehicle.trafficId),
                    {reason='Truck reached its assigned warehouse stop',x=vehicle.x,z=vehicle.z})
                parkedPositionReports[vehicle]=nil
            end
            AIWatchdog.clear(state,vehicle,'Holding assigned receiving position')
            return changed
        end
        if (vehicle.phase=='at_bay' or vehicle.phase=='waiting_bay')
            and (vehicle.pathTarget~=target or not atAssignedPosition) then
            local localX,localZ=site:toLocal(vehicle.x,vehicle.z)
            local anchorLocalX,anchorLocalZ=site:toLocal(anchorX,anchorZ)
            if parkedPositionReports[vehicle]~=target then
                parkedPositionReports[vehicle]=target
                AIWatchdog.note(state,'delivery-park-position:'..tostring(vehicle.trafficId),{
                    status='RECOVERING',system='Shop driveway',subject=vehicle.trafficId or 'Delivery truck',
                    stage='rejoin_'..tostring(target),
                    reason='Truck was marked parked away from its assigned dock or queue position',
                    action='Cleared the parked state and replanned to the assigned warehouse stop',
                    detail=('phase=%s target=%s local=%.1f,%.1f assigned=%.1f,%.1f path=%s')
                        :format(tostring(vehicle.phase),tostring(target),localX,localZ,
                            anchorLocalX,anchorLocalZ,tostring(vehicle.pathIndex)),
                    x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,scope='world-simulation'})
            end
            vehicle.pathTarget=nil;vehicle.phase=blocked and 'approaching_wait' or 'approaching'
            vehicle.pathIndex=2;vehicle.localManeuver=true;vehicle.replanRoute=true;changed=true
        end
        local points
        if vehicle.pathTarget~=target then
            if vehicle.phase=='waiting_bay' then
                vehicle.phase='approaching_wait';changed=true
            end
            if vehicle.pathTarget~=nil then vehicle.localManeuver=true end
            local startIndex=vehicle.pathTarget==nil and vehicle.pathIndex or nil
            vehicle.pathIndex=startIndex or 2;vehicle.pathTarget=target
        end
        local base=vehicle.localManeuver and {{x=vehicle.x,z=vehicle.z,h=vehicle.h}} or route.inward
        points=deliveryPath(route,vehicle,target,base,anchor)
        if not points then
            AIWatchdog.observe(state,vehicle,{issueId='delivery-route-plan:'..tostring(vehicle.trafficId),
                system='Road traffic',subject=vehicle.trafficId or 'Delivery truck',
                stage='route_to_'..tostring(target),dt=step,timeout=3,retryDelay=3,
                reason='The route planner could not connect the vehicle to its next delivery waypoint',
                x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,scope='world-simulation',
                recover=function(attempt)
                    maneuverPaths[vehicle]=nil;yardPaths[vehicle]=nil
                    vehicle.pathTarget=nil;vehicle.pathIndex=2
                    if attempt>=3 then
                        local rescued,rescueReason
                        if vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle' then
                            rescued,rescueReason=Bike.rescue(vehicle,world)
                        else
                            rescued,rescueReason=Truck.command(vehicle,'rescue',world)
                        end
                        if not rescued then
                            return {ok=false,action='Could not find a clear road recovery point',
                                detail=tostring(rescueReason or 'Route will be retried')}
                        end
                        local kind=(vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle') and 'bike' or 'vehicle'
                        updateTrafficActorIndex(world,vehicle,kind)
                        return {ok=true,action='Moved to a collision-checked road point and rebuilt the route'}
                    end
                    return {ok=true,action='Cleared cached route data and retried route planning'}
                end})
        else
            AIWatchdog.clear(state,vehicle,'Next delivery route became available')
        end
        if vehicle.phase~='at_bay' and vehicle.phase~='waiting_bay' then
            local parked=points and driveVehicle(vehicle,points,step,world,target,state) or false
            if parked then
                vehicle.speed=0;vehicle.phase=blocked and 'waiting_bay' or 'at_bay'
                vehicle.heading=anchor.heading or (blocked and (site.yaw-math.pi*.5) or site.yaw)
                vehicle.localManeuver=nil
                if vehicle.phase=='at_bay' then inbound.arrivedAtEpoch=epoch end
                changed=true
            else vehicle.phase=blocked and 'approaching_wait' or 'approaching' end
        elseif vehicle.phase=='waiting_bay' and not vehicle.noticeSent then
            vehicle.noticeSent=true
            state.message='A delivery truck is waiting outside. Move the Picture Shop truck to clear the loading bay.'
            changed=true
        end
    end
    return changed
end

function Network.simulate(state,town,dt,epoch,activeWorld,visitors)
    if type(state)~='table' then return false,false end
    local started=love.timer.getTime()
    epoch=finite(epoch) and epoch or os.time()
    local activeDelivery=false
    eachDelivery(state,function(_,delivery)
        local inbound=delivery and delivery.route
        local outbound=delivery and delivery.returnRoute
        if delivery and ((delivery.status~='received' and inbound and finite(inbound.departedAtEpoch))
            or (delivery.status=='received' and outbound and finite(outbound.departedAtEpoch)
                and (outbound.vehicle and outbound.vehicle.phase~='offmap'
                    or not outbound.vehicle and (not finite(outbound.arrivedAtEpoch) or epoch<outbound.arrivedAtEpoch)))) then
            activeDelivery=true
        end
    end)
    local commute=state.home and state.home.commute
    if not activeDelivery and not commute then return false,false end
    local route=townWorld(town,activeWorld)
    if not route then return false,false end
    dt=finite(dt) and math.max(0,dt) or 0
    local world=activeWorld
    if type(world)~='table' or world.townId~=route.world.townId then world=route.world end
    lastWorldByState[state]=world
    local motorcyclesCreated=AIMotorcycleTraffic.ensure(commute,world)
    local hasMotorcycles=commute and #(commute.aiMotorcycles or {})>0
    if not activeDelivery and not hasMotorcycles then return motorcyclesCreated,false end
    local elapsed=math.min(dt,TRAFFIC_MAX_CATCHUP)
    local stepCount=math.max(1,math.ceil(elapsed/TRAFFIC_MAX_STEP))
    local step=elapsed/stepCount
    trafficClock=trafficClock+elapsed
    local changed,moving=motorcyclesCreated,false
    for _=1,stepCount do
        local queue=WarehouseQueue.plan(deliveryEntries(state),route,dockBlocked(state,world),epoch,Network.lanePosition)
        -- Rebuild the shared actor index for each substep so every driver sees
        -- road users at their latest pose, including vehicles created during
        -- the preceding substep.
        local vehicles,_,_,trafficActors=gatherDynamicActors(state,town,world,visitors)
        world.trafficActors=trafficActors
        world.trafficActorIndex=TrafficActorIndex.shouldUse(#trafficActors)
            and TrafficActorIndex.new(trafficActors) or nil
        installVehicleCollision(world,trafficActors,world.trafficActorIndex)
        local function driveRoute(vehicle,points,driveDt,driveWorld,targetName)
            return driveVehicle(vehicle,points,driveDt,driveWorld,targetName,state)
        end
        local bikeChanged,bikeMoving=AIMotorcycleTraffic.update(commute,world,step,driveRoute,state)
        changed=bikeChanged or changed
        moving=bikeMoving
        eachDelivery(state,function(id,delivery)
            local localChanged
            if delivery and delivery.route and delivery.route.transportId then
                localChanged=false
            else
                localChanged=simulateDelivery(delivery,route,step,state,epoch,world,id,queue)
            end
            changed=localChanged or changed
            local active=delivery and (delivery.status=='received'
                and delivery.returnRoute and delivery.returnRoute.vehicle
                or delivery.route and delivery.route.vehicle)
            if active and active.phase~='offmap' then
                local present=false
                for _,other in ipairs(vehicles) do if other==active then present=true;break end end
                if not present then
                    local actorId=tostring(id or 'delivery')
                        ..(delivery.status=='received' and ':return' or '')
                    active.trafficId=actorId
                    vehicles[#vehicles+1]=active
                    local dimensions=Footprint.dimensions(active)
                    trafficActors[#trafficActors+1]={actor=active,id=actorId,isPlayer=false,kind='vehicle',
                        halfLength=dimensions.halfLength,halfWidth=dimensions.halfWidth}
                end
            end
            moving=moving or active~=nil and active.phase~='at_bay'
                and active.phase~='waiting_bay' and active.phase~='offmap'
        end)
        world.vehicleObstacles=nil;world.sweepTrafficObstacles=nil;world.activeTruck=nil
        world.activeTrafficBike=nil;world.trafficActors=nil;world.trafficActorIndex=nil
    end
    TrafficBudget.record(state,(love.timer.getTime()-started)*1000,stepCount)
    return changed,moving
end

function Network.installVehicleObstacles(state,world,visitors)
    if not world then return end
    local vehicles,pedestrians,motorcycles,trafficActors=gatherDynamicActors(state,
        state and state.home and state.home.town,world,visitors)
    installVehicleCollision(world,trafficActors)
end

function Network.arrived(shipment,epoch)
    local route=shipment and shipment.delivery and shipment.delivery.route
    if not route then return true end
    if route.vehicle then return route.vehicle.phase=='at_bay' end
    if finite(route.departedAtEpoch) then return false end
    epoch=finite(epoch) and epoch or os.time()
    return finite(route.arrivedAtEpoch) and epoch>=route.arrivedAtEpoch
end

function Network.pickupArrived(job)
    local road=job and job.pickup and job.pickup.roadDelivery
    return not road or Network.arrived({delivery=road})
end

function Network.tracking(shipment,now,epoch)
    local delivery=shipment and shipment.delivery or {}
    epoch=finite(epoch) and epoch or os.time()
    local outbound=delivery.returnRoute
    if outbound and outbound.vehicle and outbound.vehicle.phase~='offmap' then
        return 'Leaving town · heading to '..Network.CITY
    end
    if outbound and finite(outbound.departedAtEpoch) and finite(outbound.arrivedAtEpoch)
        and epoch>=outbound.departedAtEpoch and epoch<outbound.arrivedAtEpoch then
        return 'Leaving town · heading to '..Network.CITY
    end
    if outbound and finite(outbound.arrivedAtEpoch) and epoch>=outbound.arrivedAtEpoch
        and delivery.status=='received' then return 'Delivered · truck returned to '..Network.CITY end
    local inbound=delivery.route
    if inbound and inbound.vehicle and delivery.status~='received' then
        local slot=tostring(inbound.vehicle.pathTarget or ''):match('^waiting%-(%d+)$')
        if inbound.vehicle.phase=='waiting_bay' then return 'At The Picture Shop · queue position '..(slot or '?') end
        if inbound.vehicle.phase=='approaching_wait' then return 'In town · joining queue position '..(slot or '?') end
        if inbound.vehicle.phase=='at_bay' then return 'At The Picture Shop · warehouse loading bay' end
        if inbound.vehicle.phase~='offmap' then return 'In town · on the way to The Picture Shop' end
    end
    if inbound and finite(inbound.startAtHours) and finite(inbound.arrivalAtHours) then
        if not inbound.departedAtEpoch then
            return 'At '..Network.CITY..' · '..tostring(inbound.originLocation or 'Freight Yard')
        end
        if epoch<inbound.arrivedAtEpoch then return 'In town · on the way to The Picture Shop' end
        if delivery.status~='received' then return 'At The Picture Shop · warehouse loading bay' end
    end
    if delivery.status=='received' then return 'Delivered · supplier shipment received' end
    if delivery.status=='at_bay' or delivery.status=='backing' or delivery.status=='unloading'
        or delivery.status=='scheduled' then return 'At The Picture Shop · warehouse loading bay' end
    return Network.CITY..' · preparing shipment'
end

function Network.cachedWorld(town)
    local cached=town and routeCache[town]
    return cached and cached.world
end
local function vehicleForWatchdogIssue(state,issueId)
    if type(issueId)~='string' then return nil end
    local trafficId=issueId:match('^road%-driver:(.+)$')
        or issueId:match('^delivery%-dock:(.+)$')
        or issueId:match('^delivery%-dock%-controller:(.+)$')
        or issueId:match('^delivery%-route%-plan:(.+)$')
        or issueId:match('^delivery%-queue%-capacity:(.+)$')
        or issueId:match('^delivery%-park%-position:(.+)$')
    if not trafficId then return nil end
    trafficId=trafficId:gsub(':controller$','')
    local returning=trafficId:sub(-7)==':return'
    local id=returning and trafficId:sub(1,-8) or trafficId
    for _,entry in ipairs(deliveryEntries(state)) do
        if entry.id==id then
            local delivery=entry.delivery
            local record=returning and delivery.returnRoute or delivery.route
            local kind=returning and 'outbound' or 'inbound'
            local vehicle=record and record.vehicle
            if vehicle and vehicle.phase~='offmap' then
                return entry,vehicle,record,kind
            end
        end
    end
end
function Network.debugUnstickAvailable(state,issueId)
    local entry,vehicle=vehicleForWatchdogIssue(state,issueId)
    return entry~=nil and vehicle~=nil
end
function Network.debugUnstick(state,issueId)
    local entry,vehicle,record,kind=vehicleForWatchdogIssue(state,issueId)
    if not entry or not vehicle then return false,'No active delivery truck matches that watchdog report.' end
    vehicle.trafficId=kind=='outbound' and entry.id..':return' or entry.id
    local town=state.home and state.home.town
    local world=lastWorldByState[state] or Network.cachedWorld(town)
    if not world and town then
        local okay,result=pcall(require('src.commute.town').world,town)
        if okay then world=result end
    end
    if not world then return false,'The delivery town is not available for a safe route reset.' end
    local route=townWorld(town,world)
    if not route then return false,'The delivery road graph is not available for a safe route reset.' end
    world=route.world
    lastWorldByState[state]=world
    local site=world.sites and world.sites.byId and world.sites.byId.warehouse
    local beforeX,beforeZ=vehicle.x,vehicle.z
    local localX,localZ=beforeX,beforeZ
    if site then localX,localZ=site:toLocal(beforeX,beforeZ) end
    local recoveryPath=kind=='outbound' and route.outward or route.inward
    local rescued,detail=false,'Kept the truck in place and rebuilt its route from the current pose'
    if recoveryPath and #recoveryPath>=2 then
        local oldActors,oldIndex=world.trafficActors,world.trafficActorIndex
        local oldVehicleObstacles,oldSweepObstacles=world.vehicleObstacles,world.sweepTrafficObstacles
        local _,_,_,actors=gatherDynamicActors(state,town,world)
        world.trafficActors=actors
        world.trafficActorIndex=TrafficActorIndex.shouldUse(#actors) and TrafficActorIndex.new(actors) or nil
        installVehicleCollision(world,actors,world.trafficActorIndex)
        local okay,result,reason=pcall(TrafficRecovery.rescue,vehicle,recoveryPath,world)
        world.trafficActors,world.trafficActorIndex=oldActors,oldIndex
        world.vehicleObstacles,world.sweepTrafficObstacles=oldVehicleObstacles,oldSweepObstacles
        if okay and result then rescued=true;detail='Moved to a collision-checked point behind the obstruction'
        elseif not okay then detail='Route reset requested; safe reverse-point check failed: '..tostring(result)
        elseif reason then detail='Route reset requested; safe reverse-point check found no clear point: '..tostring(reason) end
    end
    local finalLocalX,finalLocalZ=vehicle.x,vehicle.z
    if site then finalLocalX,finalLocalZ=site:toLocal(vehicle.x,vehicle.z) end
    local target=vehicle.pathTarget or (kind=='outbound' and 'outbound' or 'assigned dock/queue')
    DockManeuver.clear(vehicle,state,'Manual watchdog unstick')
    for _,prefix in ipairs({'road-driver:','delivery-dock:','delivery-dock-controller:',
        'delivery-route-plan:','delivery-queue-capacity:','delivery-park-position:'}) do
        AIWatchdog.resolve(state,prefix..vehicle.trafficId,{reason='Manual driveway unstick requested'})
        if prefix=='road-driver:' or prefix=='delivery-dock:' then
            AIWatchdog.resolve(state,prefix..tostring(vehicle.trafficId)..':controller',
                {reason='Manual driveway unstick requested'})
        end
    end
    stuckWatch[vehicle]=nil;ruleWatch[vehicle]=nil;maneuverPaths[vehicle]=nil;yardPaths[vehicle]=nil
    stopRoutes[vehicle]=nil;leftTurnLaneRoutes[vehicle]=nil
    parkedPositionReports[vehicle]=nil;queueCapacityMonitors[vehicle]=nil
    vehicle.pathTarget=nil;vehicle.pathIndex=2;vehicle.localManeuver=true;vehicle.replanRoute=true
    if kind=='outbound' then vehicle.phase='departing'
    else vehicle.phase='approaching';record.vehicle=vehicle end
    AIWatchdog.note(state,'delivery-debug-unstick:'..entry.id..(kind=='outbound' and ':return' or ''),{
        status='RECOVERED',system='Shop driveway',subject=entry.id,stage=tostring(target),
        reason='Manual unstick requested from the game watchdog',
        action=rescued and detail or 'Cleared parked and route state; replanning from the current truck position',
        detail=('before=%.1f,%.1f after=%.1f,%.1f safeMove=%s route=%s')
            :format(localX,localZ,finalLocalX,finalLocalZ,tostring(rescued),tostring(record.roadTownId)),
        x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,scope='world-simulation'})
    return true,rescued and 'Truck moved to a clear point and its delivery route was replanned.'
        or 'Truck route state was reset and it will replan from its current position.'
end
-- Read physical poses without constructing route planners or sampling trips.
-- Small indoor views do not need the full map's render-only fallback routes.
function Network.physicalActors(state)
    local result,seen={},{}
    for _,entry in ipairs(deliveryEntries(state))do
        local delivery=entry.delivery
        local inbound,outbound=delivery.route,delivery.returnRoute
        local vehicle=outbound and outbound.vehicle and outbound.vehicle.phase~='offmap' and outbound.vehicle
            or delivery.status~='received' and inbound and inbound.vehicle
                and inbound.vehicle.phase~='offmap' and inbound.vehicle
        if vehicle and not (inbound and inbound.transportId) then
            local id=vehicle.trafficId or entry.id
            if not seen[id] then
                seen[id]=true
                result[#result+1]={id=id,shipmentId=entry.id,actor=vehicle,truck=true,phase=vehicle.phase}
            end
        end
    end
    return result
end
function Network.actors(state,town,now,epoch,activeWorld,visitors)
    local route=townWorld(town,activeWorld)
    if not route then return {} end
    now=finite(now) and now or Calendar.absoluteHours(state)
    epoch=finite(epoch) and epoch or os.time()
    local result={}
    local entries=deliveryEntries(state)
    local _,groups=transportGroups(entries)
    local function append(id,delivery,company,group)
        delivery=delivery or {}
        local inbound,outbound=delivery.route,delivery.returnRoute
        if inbound and inbound.transportId then return end
        local inboundNeeded=delivery.status~='received' or not groupReceived(group)
        company=outbound and outbound.originCompany or inbound and inbound.originCompany or company
        local sample,phase,speed
        local physical=outbound and outbound.vehicle and outbound.vehicle.phase~='offmap' and outbound.vehicle
            or inboundNeeded and inbound and inbound.vehicle
                and inbound.vehicle.phase~='offmap' and inbound.vehicle
        if physical then
            sample={x=physical.x,z=physical.z,h=physical.h or 0,heading=physical.heading}
            phase=physical.phase
            speed=physical.speed or 0
        elseif outbound and not outbound.vehicle and finite(outbound.departedAtEpoch) and finite(outbound.arrivedAtEpoch)
            and epoch>=outbound.departedAtEpoch and epoch<outbound.arrivedAtEpoch then
            local progress=(epoch-outbound.departedAtEpoch)/math.max(1e-8,outbound.arrivedAtEpoch-outbound.departedAtEpoch)
            sample=routeSample(route.outward,route.outboundLength,progress);phase='departing';speed=Network.AVERAGE_SPEED
        elseif inboundNeeded and inbound and not inbound.vehicle and finite(inbound.departedAtEpoch)
            and finite(inbound.arrivedAtEpoch) and epoch>=inbound.departedAtEpoch and epoch<inbound.arrivedAtEpoch then
            local progress=(epoch-inbound.departedAtEpoch)/math.max(1e-8,inbound.arrivedAtEpoch-inbound.departedAtEpoch)
            sample=routeSample(route.inward,route.length,progress);phase='approaching';speed=Network.AVERAGE_SPEED
        elseif not outbound and inboundNeeded and inbound and not inbound.vehicle
            and finite(inbound.arrivedAtEpoch) and epoch>=inbound.arrivedAtEpoch then
            local site=route.world.sites.byId.warehouse
            local localPoint=site and site.design.truckParking
            if localPoint then
                local x,z=site:toWorld(localPoint.x,localPoint.z,0)
                sample={x=x,z=z,h=route.world:supportHeight(x,z),heading=site.yaw}
                phase='at_bay';speed=0
            end
        end
        if sample then
            local actor={x=sample.x,z=sample.z,h=sample.h,heading=sample.heading,
                speed=speed,engine=speed>0,reverse=physical and physical.reverse or false,
                steering=physical and physical.steering or 0,slipAngle=physical and physical.slipAngle or 0,
                pitch=physical and physical.pitch or 0,livery='plain',company=company,turnSignal=nil}
            local source={delivery=delivery}
            result[#result+1]={id=id,shipmentId=id,actor=actor,
                truck=true,deliveryTruck=true,phase=phase,label=Network.tracking(source,now,epoch)}
        end
    end
    for _,entry in ipairs(entries) do
        append(entry.id,entry.delivery,entry.company,groups[entry.id])
    end
    for _,entry in ipairs(AIMotorcycleTraffic.actors(state.home and state.home.commute)) do
        result[#result+1]=entry
    end
    for _,entry in ipairs(TownCharacters.actors(state.home,town,now,activeWorld)) do
        result[#result+1]=entry
    end
    for _,entry in ipairs(EmployeeCommuters.actors(state,town,now,activeWorld)) do
        result[#result+1]=entry
    end
    for _,entry in ipairs(VisitorCommuters.actors(visitors,state,town,now,activeWorld)) do
        result[#result+1]=entry
    end
    for _,entry in ipairs(require('src.company_delivery_driver').actors(state,route.world,epoch)) do
        result[#result+1]=entry
    end
    return result
end

function Network.cityLocationFor(id)
    return citySites[(hash(id)+1)%#citySites+1]
end

return Network
