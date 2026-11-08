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
local DrivingPath=require('src.commute.driving_path')
local TrafficActorIndex=require('src.commute.traffic_actor_index')
local AIWatchdog=require('src.ai_watchdog')
local Network={CITY='Millhaven',AVERAGE_SPEED=8,MAX_INBOUND_TRUCKS=3,TRUCK_CAPACITY=10}
local stuckWatch=setmetatable({}, {__mode='k'})
local ruleWatch=setmetatable({}, {__mode='k'})
local maneuverPaths=setmetatable({}, {__mode='k'})
local yardPaths=setmetatable({}, {__mode='k'})
local stopRoutes=setmetatable({}, {__mode='k'})
local leftTurnLaneRoutes=setmetatable({}, {__mode='k'})
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
    if route.accessIntegrated then
        yardPaths[vehicle]=nil
        local destination=targetDestination(route,target)
        if not destination then return nil end
        local cached=maneuverPaths[vehicle]
        if not cached or cached.target~=target then
            local planned=route.planner:findFromPoint(vehicle.x,vehicle.z,destination)
            if not planned or type(planned.points)~='table' or #planned.points<2 then
                maneuverPaths[vehicle]=nil
                return nil
            end
            cached={target=target,points=planned.points}
            maneuverPaths[vehicle]=cached
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

local function leftTurnLaneBlend(points,index,vehicle,world)
    local roads=world.roads
    if not roads or not roads.nearest then return 1 end
    local cached=leftTurnLaneRoutes[points]
    if not cached or cached.roads~=roads then
        local candidates={}
        for i=2,#points-1 do
            if turnAngle(points,i)<-.32 then
                local before,at=points[i-1],points[i]
                local dx,dz=at.x-before.x,at.z-before.z
                local length=math.sqrt(dx*dx+dz*dz)
                if length>1e-8 then
                    local setback=math.max(5,math.min(9,length*.7))
                    local mx,mz=at.x-dx/length*setback,at.z-dz/length*setback
                    local _,incoming=roads:nearest(mx,mz,true)
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
    return clamp((walked-2)/10,0,1)
end

local function junctionLaneBlend(world,x,z)
    local roads=world.roads
    local binSize=roads and roads.binSize or 16
    local key=math.floor(x/binSize)..':'..math.floor(z/binSize)
    local blend=1
    for _,junction in ipairs(roads and roads.junctionBins and roads.junctionBins[key] or {}) do
        local radius=junction.outerRadius or junction.radius or 0
        local distance=math.sqrt((x-junction.x)^2+(z-junction.z)^2)-radius
        if distance<7 then blend=math.min(blend,clamp(distance/7,0,1)) end
    end
    return blend
end

local function laneTarget(points,index,vehicle,target,targetHeading,world,ruleState,dt)
    local roads=world.roads
    if not roads or not roads.nearest then return target end
    local _,segment=roads:nearest(target.x,target.z,true)
    local side=TrafficRules.drivingSide(world.town)
    local leftBlend=leftTurnLaneBlend(points,index,vehicle,world)
    local offset=TrafficRules.laneOffset(segment,side,false,vehicle)
    if segment and segment.turnLane then offset=offset*leftBlend end
    local blend=junctionLaneBlend(world,target.x,target.z)
    ruleState.laneOffset=ruleState.laneOffset or 0
    local wanted=offset*blend
    local blendRate=segment and (segment.bridge or (segment.lanes or 0)<2 or segment.role=='drive')
        and 12 or 4
    ruleState.laneOffset=ruleState.laneOffset+(wanted-ruleState.laneOffset)*clamp(dt*blendRate,0,1)
    local x,z=TrafficRules.lanePoint(target,targetHeading,ruleState.laneOffset,1)
    return {x=x,z=z},segment
end

local function routePassesStop(points,stop,approachX,approachZ)
    local tolerance=math.max(1.1,(stop.roadWidth or 5.8)*.22)
    for i=2,#points do
        local a,b=points[i-1],points[i]
        local dx,dz=b.x-a.x,b.z-a.z
        local length2=dx*dx+dz*dz
        if length2>1e-8 then
            local t=clamp(((stop.stopX-a.x)*dx+(stop.stopZ-a.z)*dz)/length2,0,1)
            local x,z=a.x+dx*t,a.z+dz*t
            local vx,vz=dx/math.sqrt(length2),dz/math.sqrt(length2)
            local distance2=(x-stop.stopX)^2+(z-stop.stopZ)^2
            if distance2<=tolerance*tolerance and vx*approachX+vz*approachZ>.72 then return true end
        end
    end
    return false
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
                if routePassesStop(points,fixture,ax,az) then
                    local junctionX=fixture.junctionX or fixture.stopX+ax*12
                    local junctionZ=fixture.junctionZ or fixture.stopZ+az*12
                    result[#result+1]={fixture=fixture,approachX=ax,approachZ=az,
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
    for _,candidate in ipairs(stopCandidates(points,world)) do
        local fixture=candidate.fixture
        local dx,dz=fixture.stopX-vehicle.x,fixture.stopZ-vehicle.z
        local ahead=dx*candidate.approachX+dz*candidate.approachZ
        local lateral=math.abs(-dx*candidate.approachZ+dz*candidate.approachX)
        if ahead>0 and ahead<26 and lateral<=candidate.roadWidth*.5+dimensions.halfWidth
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
        if (vehicle.speed or 0)<.22 then state.stopDwell=(state.stopDwell or 0)+dt end
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
    local occupied=false
    eachDelivery(state,function(_,delivery)
        if occupied or type(delivery)~='table' then return end
        local inbound=delivery.route and delivery.route.vehicle
        local outbound=delivery.returnRoute and delivery.returnRoute.vehicle
        if inbound and inbound~=subject then
            if inbound.pathTarget=='dock' and inbound.phase~='offmap'
                or inbound.phase=='at_bay' and truckAtDock(world,inbound) then
                occupied=true;return
            end
        end
        if outbound and outbound~=subject and outbound.phase~='offmap' and truckAtDock(world,outbound) then
            occupied=true;return
        end
    end)
    return occupied
end

local function queueTarget(state,subject,id,delivery,site,integrated)
    local anchors=integrated and site.truckQueueAnchors or {site.localTruckWaiting or site.design.truckWaiting}
    if #anchors==0 then return 'waiting-1',anchors[1] end
    local waiting={{vehicle=subject,id=tostring(id or ''),
        arrived=tonumber(delivery and delivery.route and delivery.route.departedAtEpoch) or math.huge}}
    eachDelivery(state,function(id,other)
        local route=other and other.route
        local vehicle=route and route.vehicle
        if vehicle and vehicle~=subject and vehicle.phase~='offmap'
            and tostring(vehicle.pathTarget or ''):match('^waiting%-%d+$') then
            waiting[#waiting+1]={vehicle=vehicle,id=tostring(id),
                arrived=tonumber(route.departedAtEpoch) or math.huge}
        end
    end)
    table.sort(waiting,function(a,b)
        if a.arrived~=b.arrived then return a.arrived<b.arrived end
        return a.id<b.id
    end)
    local slot=1
    for index,item in ipairs(waiting) do if item.vehicle==subject then slot=index;break end end
    slot=math.min(slot,#anchors)
    return 'waiting-'..slot,anchors[slot]
end

local function gatherDynamicActors(state,town,activeWorld)
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

local function updateTrafficVehicle(vehicle,steer,desired,hold,dt,world)
    if vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle' then
        local throttle,brake=0,0
        local speed=vehicle.speed or 0
        if hold or desired<.12 then brake=1
        elseif speed<desired-.25 then throttle=clamp((desired-speed)*.55,.12,1)
        elseif speed>desired+.25 then brake=clamp((speed-desired)*.70,.08,1)
        else throttle=.10 end
        world.activeTrafficBike=vehicle
        local moved=Bike.update(vehicle,{throttle=throttle,brake=brake,steer=steer},dt,world)
        world.activeTrafficBike=nil
        updateTrafficActorIndex(world,vehicle,'bike')
        return moved
    end
    world.activeTruck=vehicle
    local drive=vehicle.speed<desired-.35 and -1 or 0
    local brake=vehicle.speed>desired+.35 and math.min(1,(vehicle.speed-desired)*.7) or 0
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
        -- Curved roads are sampled more closely than the truck can follow
        -- point-by-point. Advance after crossing a waypoint while nearby, so
        -- missing the radius cannot make a driver loop back to a passed point.
        if distance2<=1.35^2 or along>=0 and crossTrack<=crossTrackLimit then index=index+1
        else break end
    end
    vehicle.pathIndex=index
    return index
end

local function routeSpeedLimit(vehicle,points,index,waypointDistance,remaining,headingError)
    local maxSpeed=Truck.MAX_SPEED
    if vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle' then maxSpeed=Bike.MAX_SPEED end
    local desired=math.min(TrafficRules.driverTownSpeed(vehicle),maxSpeed)
    if math.abs(headingError)>.45 then desired=5.4 end
    if math.abs(headingError)>.95 then desired=2.8 end
    local routeStation=DrivingPath.station(points,index-1)
    for _,marker in ipairs(DrivingPath.speedLimits(points)) do
        if marker.index>=index then
            local turnDistance=waypointDistance+marker.distanceBefore-routeStation
            if marker.index==index or turnDistance<=70 then
                local available=math.max(0,turnDistance-1.5)
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

local function driveVehicle(vehicle,points,dt,world,targetName,watchdogState)
    if not points or #points<2 then return false end
    if vehicle.pathTarget~=targetName then
        local startIndex=vehicle.pathTarget==nil and vehicle.pathIndex or nil
        vehicle.pathTarget=targetName;vehicle.pathIndex=startIndex or 2
    end
    local ruleState=ruleWatch[vehicle]
    if not ruleState then
        ruleState={routeTarget=targetName,laneOffset=0,passDelta=0,stopDwell=0}
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
    -- Follow a point several metres ahead instead of steering node-by-node.
    -- The road planner emits closely spaced points, and targeting each one
    -- directly makes long trucks cut or oscillate at junction turns.
    local lookAhead=math.max(3.8,math.min(5.8,3.8+(vehicle.speed or 0)*.23))
    local target,targetHeading=DrivingPath.lookAhead(points,vehicle.x,vehicle.z,index,lookAhead,
        not DrivingPath.hasTurnGuidance(points)
            and vehicle.trafficKind~='motorcycle' and vehicle.aiKind~='motorcycle')
    local laneSegment
    target,laneSegment=laneTarget(points,index,vehicle,target,targetHeading,world,ruleState,dt)
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
    if not passingActor and not passAbortHold then
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
    local _,currentSegment=world.roads:nearest(vehicle.x,vehicle.z,true)
    local localYield
    desired,localYield=TrafficRules.limitForTraffic(vehicle,desired,world.trafficActors,
        laneSegment or currentSegment,world.trafficActorIndex,passingActor)
    local stop,stopHold=stopRule(vehicle,points,index,world,dt,ruleState)
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
    if not watch or watch.routeKey~=routeKey then
        if watch then AIWatchdog.resolve(watchdogState,watch.issueId,{reason='Route stage advanced'}) end
        watch={routeKey=routeKey,windowTime=0,windowMoved=0,stalled=0,cooldown=0,
            reverseTime=0,recoveryAttempts=0,
            issueId='road-driver:'..tostring(vehicle.trafficId or vehicle.pathTarget or targetName)}
        stuckWatch[vehicle]=watch
    end
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
            return updateTrafficVehicle(vehicle,steer,desired,hold,dt,world)
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
    if final or desired<1.2 or stopHold or localYield then
        watch.windowTime,watch.windowMoved,watch.stalled=0,0,0
        if final then AIWatchdog.resolve(watchdogState,watch.issueId,{reason='Route waypoint reached',
            x=vehicle.x,z=vehicle.z}) end
    else
        if watch.windowTime==0 then watch.windowStartDistance=remaining end
        watch.windowTime=watch.windowTime+dt
        watch.windowMoved=watch.windowMoved+moved
        if watch.windowTime>=1 then
            local madeProgress=watch.windowStartDistance-remaining>=.25
            if watch.windowMoved<.75 or not madeProgress then watch.stalled=watch.stalled+watch.windowTime
            else
                watch.stalled=0;watch.recoveryAttempts=0
                AIWatchdog.resolve(watchdogState,watch.issueId,{reason='Vehicle resumed route progress',
                    x=vehicle.x,z=vehicle.z})
            end
            watch.windowTime,watch.windowMoved=0,0
        end
        if watch.stalled>=4.5 and watch.cooldown<=0 then
            watch.recoveryAttempts=watch.recoveryAttempts+1
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

-- Shared route follower for autonomous delivery traffic. Keeping this entry
-- point public lets terrain smoke tests exercise the exact production driver
-- against every generated town address instead of a test-only steering copy.
Network.driveRoute=function(vehicle,points,dt,world,targetName,watchdogState)
    trafficClock=trafficClock+math.max(0,finite(dt) and dt or 0)
    return driveVehicle(vehicle,points,dt,world,targetName,watchdogState)
end

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
    local carriers,activeCount={},0
    for _,entry in ipairs(entries) do
        local group=groups[entry.id]
        local inbound=entry.delivery.route
        if group and group.leader==entry and inbound and not inbound.transportId
            and finite(inbound.departedAtEpoch) and not groupReceived(group)
            and not (inbound.vehicle and inbound.vehicle.phase=='offmap') then
            local carrier={id=entry.id,group=group,route=inbound,
                pallets=groupPalletCount(state,group),canLoad=canLoadOnTruck(inbound,epoch)}
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
            if pallets>0 then due[#due+1]={entry=entry,pallets=pallets} end
        end
    end
    table.sort(due,function(a,b)
        local aStart=a.entry.delivery.route.startAtHours or 0
        local bStart=b.entry.delivery.route.startAtHours or 0
        if aStart~=bStart then return aStart<bStart end
        return a.entry.id<b.entry.id
    end)

    local changed=false
    for _,item in ipairs(due) do
        local entry=item.entry
        local inbound=entry.delivery.route
        local best,bestRemainder
        if item.pallets<=Network.TRUCK_CAPACITY then
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
        elseif activeCount<Network.MAX_INBOUND_TRUCKS then
            inbound.departedAtEpoch=epoch
            inbound.arrivedAtEpoch=epoch+route.length/Network.AVERAGE_SPEED
            local group=groups[entry.id] or {id=entry.id,leader=entry,members={entry}}
            groups[entry.id]=group
            carriers[#carriers+1]={id=entry.id,group=group,route=inbound,
                pallets=item.pallets,canLoad=item.pallets<Network.TRUCK_CAPACITY}
            activeCount=activeCount+1
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
        end
    end
    local entries=deliveryEntries(state)
    local linksChanged,_,groups=syncTransportLinks(entries)
    changed=linksChanged or changed
    changed=dispatchInbound(state,entries,groups,route,now,epoch) or changed
    local linkedAgain,_,updatedGroups=syncTransportLinks(entries)
    changed=linkedAgain or changed
    changed=createReturnRoutes(state,entries,updatedGroups,now,epoch,outboundDurationHours,town.id) or changed
    return changed
end

local function simulateDelivery(delivery,route,dt,state,epoch,world,entryId)
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
        local blocked=dockBlocked(state,world,vehicle)
        local target,anchor
        if blocked then target,anchor=queueTarget(state,vehicle,entryId,delivery,site,route.accessIntegrated)
        else target,anchor='dock',site.design.truckParking end
        if created and finite(inbound.departedAtEpoch) and finite(inbound.arrivedAtEpoch)
            and epoch>inbound.departedAtEpoch+1 then
            if epoch>=inbound.arrivedAtEpoch then
                vehicle.x,vehicle.z=site:toWorld(anchor.x,anchor.z,0)
                vehicle.heading=blocked and (site.yaw-math.pi*.5) or site.yaw
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
        if vehicle.phase=='at_bay' and blocked then
            vehicle.pathTarget=nil;vehicle.phase='approaching';vehicle.pathIndex=2
            vehicle.localManeuver=true;changed=true
        elseif vehicle.phase=='waiting_bay' and not blocked then
            vehicle.pathTarget=nil;vehicle.phase='approaching';vehicle.pathIndex=2
            vehicle.localManeuver=true;changed=true
        end
        local points
        if vehicle.pathTarget~=target then
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
                vehicle.heading=blocked and (site.yaw-math.pi*.5) or site.yaw
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

function Network.simulate(state,town,dt,epoch,activeWorld)
    if type(state)~='table' then return false,false end
    local activeDelivery=false
    eachDelivery(state,function(_,delivery)
        local inbound=delivery and delivery.route
        local outbound=delivery and delivery.returnRoute
        if delivery and ((delivery.status~='received' and inbound and finite(inbound.departedAtEpoch))
            or (delivery.status=='received' and outbound and finite(outbound.departedAtEpoch)
                and (outbound.vehicle and outbound.vehicle.phase~='offmap'
                    or not outbound.vehicle and (not finite(outbound.arrivedAtEpoch) or os.time()<outbound.arrivedAtEpoch)))) then
            activeDelivery=true
        end
    end)
    local commute=state.home and state.home.commute
    if not activeDelivery and not commute then return false,false end
    local route=townWorld(town,activeWorld)
    if not route then return false,false end
    dt=finite(dt) and math.max(0,dt) or 0
    epoch=finite(epoch) and epoch or os.time()
    local world=activeWorld
    if type(world)~='table' or world.townId~=route.world.townId then world=route.world end
    local motorcyclesCreated=AIMotorcycleTraffic.ensure(commute,world)
    local hasMotorcycles=commute and #(commute.aiMotorcycles or {})>0
    if not activeDelivery and not hasMotorcycles then return motorcyclesCreated,false end
    local elapsed=math.min(dt,TRAFFIC_MAX_CATCHUP)
    local stepCount=math.max(1,math.ceil(elapsed/TRAFFIC_MAX_STEP))
    local step=elapsed/stepCount
    trafficClock=trafficClock+elapsed
    local changed,moving=motorcyclesCreated,false
    for _=1,stepCount do
        -- Rebuild the shared actor index for each substep so every driver sees
        -- road users at their latest pose, including vehicles created during
        -- the preceding substep.
        local vehicles,_,_,trafficActors=gatherDynamicActors(state,town,world)
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
                localChanged=simulateDelivery(delivery,route,step,state,epoch,world,id)
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
    return changed,moving
end

function Network.installVehicleObstacles(state,world)
    if not world then return end
    local vehicles,pedestrians,motorcycles,trafficActors=gatherDynamicActors(state,
        state and state.home and state.home.town,world)
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
        if inbound.vehicle.phase=='waiting_bay' then return 'At The Picture Shop · loading bay occupied' end
        if inbound.vehicle.phase=='approaching_wait' then return 'In town · loading bay occupied' end
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

function Network.actors(state,town,now,epoch,activeWorld)
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
    for _,entry in ipairs(require('src.company_delivery_driver').actors(state,route.world,epoch)) do
        result[#result+1]=entry
    end
    return result
end

function Network.cityLocationFor(id)
    return citySites[(hash(id)+1)%#citySites+1]
end

return Network
