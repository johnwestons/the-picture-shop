-- Host-owned road traffic uses the player truck controller and stores only the
-- current pose and route cursor for each active shipment.
local Calendar=require('src.business_calendar')
local Truck=require('src.commute.delivery_truck')
local Footprint=require('src.commute.truck_footprint')
local Network={CITY='Millhaven',AVERAGE_SPEED=8,MAX_INBOUND_TRUCKS=3,TRUCK_CAPACITY=10}
local stuckWatch=setmetatable({}, {__mode='k'})

local citySites={
    'Millhaven Paper Depot','Millhaven Freight Yard','Millhaven Press Row',
    'Millhaven Commercial Wharf',
}
local routeCache={}

local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge
end
local function hash(text)
    local result=17
    for i=1,#tostring(text or '') do result=(result*131+tostring(text):byte(i))%2147483647 end
    return result
end
local function townWorld(town)
    if type(town)~='table' or type(town.id)~='string' then return nil end
    local cached=routeCache[town.id]
    if cached then return cached end
    local ok,world=pcall(require('src.commute.town').world,town)
    if not ok or not world or not world.mainlandExit then return nil end
    local Routes=require('src.commute.routes')
    local planner=Routes.new(world.roads)
    local gate=world.mainlandExit
    local inward=planner:findFromPoint(gate.x,gate.z,'warehouse')
    if not inward or type(inward.points)~='table' or #inward.points<2 then return nil end
    local length=0
    for i=2,#inward.points do
        local a,b=inward.points[i-1],inward.points[i]
        length=length+math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)
    end
    if length<1 then return nil end
    local outward={}
    for i=#inward.points,1,-1 do
        local p=inward.points[i]
        outward[#outward+1]={x=p.x,z=p.z,h=p.h}
    end
    -- Outbound trucks disappear with their nose at the virtual gate. Keeping
    -- the center one truck-length inside lets the full footprint stay on-map
    -- while preserving the visible impression of leaving through the edge.
    local keepDistance=math.max(0,length-Footprint.halfLength-.65)
    local visibleOutward={};local walked=0
    if outward[1] then visibleOutward[1]=outward[1] end
    for i=2,#outward do
        local a,b=outward[i-1],outward[i]
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
    if #visibleOutward>=2 then outward=visibleOutward end
    cached={world=world,gate=gate,inward=inward.points,outward=outward,length=length}
    routeCache[town.id]=cached
    return cached
end

local function routeSample(points,length,progress)
    if type(points)~='table' or #points<2 then return nil end
    local wanted=math.max(0,math.min(1,progress))*length
    local walked=0
    for i=2,#points do
        local a,b=points[i-1],points[i]
        local dx,dz=b.x-a.x,b.z-a.z
        local segment=math.sqrt(dx*dx+dz*dz)
        if wanted<=walked+segment or i==#points then
            local t=segment>1e-6 and math.max(0,math.min(1,(wanted-walked)/segment)) or 1
            return {x=a.x+dx*t,z=a.z+dz*t,h=(a.h or b.h or 0)+((b.h or a.h or 0)-(a.h or b.h or 0))*t,
                heading=math.atan2(dz,dx)}
        end
        walked=walked+segment
    end
end

local shipmentCompany

local function appendPoint(points,x,z,h)
    local prior=points[#points]
    if not prior or (prior.x-x)^2+(prior.z-z)^2>.25 then
        points[#points+1]={x=x,z=z,h=h}
    end
end

local function yardPath(route,base,anchor)
    local points={}
    for _,p in ipairs(base) do appendPoint(points,p.x,p.z,p.h) end
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

local function pathLengthFrom(points,startIndex)
    local length=0
    for i=startIndex or 2,#points do
        local a,b=points[i-1],points[i]
        if a and b then length=length+math.sqrt((b.x-a.x)^2+(b.z-a.z)^2) end
    end
    return length
end

local function lookAheadPoint(points,x,z,startIndex,distance)
    local ax,az=x,z
    for i=startIndex,#points do
        local b=points[i]
        local dx,dz=b.x-ax,b.z-az
        local segment=math.sqrt(dx*dx+dz*dz)
        if segment>1e-7 and distance<=segment then
            local t=distance/segment
            return {x=ax+dx*t,z=az+dz*t}
        end
        distance=distance-segment
        ax,az=b.x,b.z
    end
    return points[#points]
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
        if inbound and inbound~=subject and inbound.phase=='at_bay' and truckAtDock(world,inbound) then
            occupied=true;return
        end
        if outbound and outbound~=subject and outbound.phase=='at_bay' and truckAtDock(world,outbound) then
            occupied=true;return
        end
    end)
    return occupied
end

local function gatherDynamicActors(state)
    local vehicles,pedestrians={},{}
    local commute=state and state.home and state.home.commute
    if commute and type(commute.truck)=='table' and Truck.valid(commute.truck) then
        vehicles[#vehicles+1]=commute.truck
    end
    if commute then
        for _,part in pairs(commute.participants or {}) do
            if not part.interior and part.rider then
                local rider=part.rider
                if rider.vehicle~='truck' then
                    if rider.gear and rider.gear.mounted and rider.bike then
                        pedestrians[#pedestrians+1]={x=rider.bike.x,z=rider.bike.z,radius=.62}
                    elseif rider.ped then pedestrians[#pedestrians+1]={x=rider.ped.x,z=rider.ped.z,radius=.55} end
                end
            end
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
        if inbound and inbound.phase~='offmap' then vehicles[#vehicles+1]=inbound end
        if outbound and outbound.phase~='offmap' then vehicles[#vehicles+1]=outbound end
    end
    return vehicles,pedestrians
end

local function installVehicleCollision(world,vehicles,pedestrians)
    world.vehicleObstacles=function(x,z,heading,subject)
        for _,other in ipairs(vehicles) do
            if other~=subject and finite(other.x) and finite(other.z) and finite(other.heading)
                and Footprint.overlapsTruck(x,z,heading,other.x,other.z,other.heading) then return true end
        end
        local c,s=math.cos(heading),math.sin(heading)
        for _,other in ipairs(pedestrians) do
            if Footprint.overlaps(x,z,c,s,other.x,other.z,other.x,other.z,other.radius) then return true end
        end
        return false
    end
    world.sweepTrafficObstacles=function(x,z,nx,nz,radius,bottom,top)
        local best,nxHit,nzHit,id
        for _,other in ipairs(vehicles) do
            local height=other.h or world:supportHeight(other.x,other.z)
            if finite(other.x) and finite(other.z) and finite(other.heading)
                and bottom<=height+Footprint.height and top>=height then
                local hit,hx,hz=Footprint.sweepCircle(x,z,nx,nz,radius,
                    other.x,other.z,other.heading)
                if hit and (not best or hit<best) then
                    best,nxHit,nzHit,id=hit,hx,hz,other.id or other.pathTarget or 'delivery-truck'
                end
            end
        end
        if best then return best,nxHit,nzHit,'deliveryTruck',id end
    end
end

local function routeWaypointAfter(points,distance)
    local walked=0
    for i=2,#points do
        local a,b=points[i-1],points[i]
        walked=walked+math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)
        if walked>=distance then return i end
    end
    return #points
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
    vehicle.pathIndex=routeWaypointAfter(route.inward,spawnDistance+1.5)
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
        record.vehicle.pathIndex=routeWaypointAfter(route.inward,spawnDistance+1.5)
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
        local points={}
        local approachX=anchor.x+2.8
        for _,p in ipairs({{approachX,anchor.z},{approachX,anchor.z+5.2},{anchor.x,anchor.z+7.5}}) do
            local wx,wz=site:toWorld(p[1],p[2],0);appendPoint(points,wx,wz,route.world:supportHeight(wx,wz))
        end
        for _,p in ipairs(route.outward) do appendPoint(points,p.x,p.z,p.h) end
        record.vehicle=Truck.new(x,z,heading,'plain')
        record.vehicle.phase='departing'
    end
    if not record.vehicle then return nil end
    local vehicle=record.vehicle
    vehicle.h=route.world:supportHeight(vehicle.x,vehicle.z)
    vehicle.pathIndex=vehicle.pathIndex or 2
    vehicle.pathKind=kind;vehicle.pathTarget=nil;vehicle.simRemainder=0
    vehicle.engine=true
    return vehicle
end

local function driveVehicle(vehicle,points,dt,world,targetName)
    if not points or #points<2 then return false end
    if vehicle.pathTarget~=targetName then
        local startIndex=vehicle.pathTarget==nil and vehicle.pathIndex or nil
        vehicle.pathTarget=targetName;vehicle.pathIndex=startIndex or 2
    end
    local index=math.max(2,math.min(#points,vehicle.pathIndex or 2))
    while index<#points do
        local p=points[index]
        if (vehicle.x-p.x)^2+(vehicle.z-p.z)^2>1.35^2 then break end
        index=index+1
    end
    vehicle.pathIndex=index
    local waypoint=points[index]
    local wx,wz=waypoint.x-vehicle.x,waypoint.z-vehicle.z
    local waypointDistance=math.sqrt(wx*wx+wz*wz)
    local remaining=waypointDistance+pathLengthFrom(points,index+1)
    -- Follow a point several metres ahead instead of steering node-by-node.
    -- The road planner emits closely spaced points, and targeting each one
    -- directly makes long trucks cut or oscillate at junction turns.
    local lookAhead=math.max(3.8,math.min(5.8,3.8+(vehicle.speed or 0)*.23))
    local target=lookAheadPoint(points,vehicle.x,vehicle.z,index,lookAhead)
    local dx,dz=target.x-vehicle.x,target.z-vehicle.z
    local error=math.atan2(math.sin(math.atan2(dz,dx)-vehicle.heading),math.cos(math.atan2(dz,dx)-vehicle.heading))
    local steer=math.max(-1,math.min(1,error/math.rad(30)))
    local desired=8.6
    if math.abs(error)>.45 then desired=5.4 end
    if math.abs(error)>.95 then desired=2.8 end
    desired=math.min(desired,math.sqrt(math.max(0,2*2.2*remaining)))
    local final=index==#points and waypointDistance<.72
    local drive=vehicle.speed<desired-.35 and -1 or 0
    local brake=vehicle.speed>desired+.35 and math.min(1,(vehicle.speed-desired)*.7) or 0
    if final then drive,brake=0,1 end
    local watch=stuckWatch[vehicle]
    local routeKey=targetName..':'..index
    if not watch or watch.routeKey~=routeKey then
        watch={routeKey=routeKey,windowTime=0,windowMoved=0,stalled=0,cooldown=0,reverseTime=0}
        stuckWatch[vehicle]=watch
    end
    if watch.reverseTime>0 then
        watch.reverseTime=math.max(0,watch.reverseTime-dt)
        world.activeTruck=vehicle
        Truck.update(vehicle,{drive=1,steer=math.max(-.35,math.min(.35,-steer*.35))},dt,world)
        world.activeTruck=nil
        if watch.reverseTime==0 then
            watch.cooldown=2
            watch.windowTime,watch.windowMoved,watch.stalled=0,0,0
            vehicle.pathTarget=nil
        end
        return false
    end
    world.activeTruck=vehicle
    local moved=Truck.update(vehicle,{drive=drive,steer=steer,brake=brake},dt,world)
    world.activeTruck=nil
    watch.cooldown=math.max(0,watch.cooldown-dt)
    if final or desired<1.2 then
        watch.windowTime,watch.windowMoved,watch.stalled=0,0,0
    else
        if watch.windowTime==0 then watch.windowStartDistance=remaining end
        watch.windowTime=watch.windowTime+dt
        watch.windowMoved=watch.windowMoved+moved
        if watch.windowTime>=1 then
            local madeProgress=watch.windowStartDistance-remaining>=.25
            if watch.windowMoved<.75 or not madeProgress then watch.stalled=watch.stalled+watch.windowTime
            else watch.stalled=0 end
            watch.windowTime,watch.windowMoved=0,0
        end
        if watch.stalled>=4.5 and watch.cooldown<=0 then
            -- Back away from the obstruction with a small counter-steer, then
            -- rejoin the same route cursor. The truck controller still owns
            -- acceleration, steering and every collision check.
            watch.reverseTime=1.6;watch.stalled=0
        end
    end
    if final and vehicle.speed<.3 then return true end
    return false
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

local function updateTrackedDelivery(delivery,company,location,id,now,durationHours,route,epoch)
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
        outbound.roadTownId=id;outbound.arrivalAtHours=start+durationHours
        outbound.departedAtEpoch=outbound.departedAtEpoch or epoch
        outbound.arrivedAtEpoch=outbound.departedAtEpoch+route.length/Network.AVERAGE_SPEED
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

function Network.update(state,town,now,epoch)
    if type(state)~='table' then return false end
    local shipments=state.procurement and state.procurement.shipments or {}
    local jobs=state.jobs
    local activeJobs=jobs and jobs.active or {}
    local completedJobs=jobs and jobs.completed or {}
    if #shipments==0 and #activeJobs==0 and #completedJobs==0 then return false end
    local route=townWorld(town)
    if not route then return false end
    now=finite(now) and now or Calendar.absoluteHours(state)
    epoch=finite(epoch) and epoch or os.time()
    local durationHours=route.length/Network.AVERAGE_SPEED*24/math.max(1,Calendar.secondsPerDay(state))
    local changed=false
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
            delivery.returnRoute.arrivalAtHours=start+durationHours
            delivery.returnRoute.departedAtEpoch=delivery.returnRoute.departedAtEpoch or epoch
            delivery.returnRoute.arrivedAtEpoch=delivery.returnRoute.arrivedAtEpoch
                or delivery.returnRoute.departedAtEpoch+route.length/Network.AVERAGE_SPEED
            delivery.returnRoute.vehicle=nil
            changed=true
        end
    end
    for _,collection in ipairs({activeJobs,completedJobs}) do
        for _,job in ipairs(collection) do
            local delivery=job.delivery
            local company=job.company or 'Millhaven Freight'
            changed=updateTrackedDelivery(delivery,company,Network.cityLocationFor(job.id),town.id,
                now,durationHours,route,epoch) or changed
        end
    end
    local entries=deliveryEntries(state)
    local linksChanged,_,groups=syncTransportLinks(entries)
    changed=linksChanged or changed
    changed=dispatchInbound(state,entries,groups,route,now,epoch) or changed
    local linkedAgain,_,updatedGroups=syncTransportLinks(entries)
    changed=linkedAgain or changed
    changed=createReturnRoutes(state,entries,updatedGroups,now,epoch,durationHours,town.id) or changed
    return changed
end

local function simulateDelivery(delivery,route,dt,state,epoch,world)
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
    local boundaryRepaired=repairBoundaryVehicle(vehicle,record,route,kind,epoch)
    if kind=='outbound' and inbound and inbound.vehicle and inbound.vehicle~=vehicle then
        inbound.vehicle.phase='offmap'
    end
    local changed=created or boundaryRepaired
    local step=math.min(.1,dt)
    if kind=='outbound' then
        if vehicle.phase=='offmap' then return changed end
        local site=route.world.sites.byId.warehouse
        local anchor=site and (site.design.truckParking or site.design.truckWaiting)
        local approachX=anchor and anchor.x+2.8
        local points={}
        if site and anchor then
            for _,p in ipairs({{approachX,anchor.z},{approachX,anchor.z+5.2},{anchor.x,anchor.z+7.5}}) do
                local x,z=site:toWorld(p[1],p[2],0);appendPoint(points,x,z,route.world:supportHeight(x,z))
            end
        end
        for _,p in ipairs(route.outward) do appendPoint(points,p.x,p.z,p.h) end
        if driveVehicle(vehicle,points,step,world,'outbound') then
            vehicle.phase='offmap';vehicle.speed=0;outbound.arrivedAtEpoch=epoch;changed=true
        elseif vehicle.speed>.02 then vehicle.phase='departing' end
    else
        local site=route.world.sites.byId.warehouse
        if not site or not site.design.truckParking then return false end
        local blocked=dockBlocked(state,world,vehicle)
        local anchor=blocked and (site.design.truckWaiting or site.design.truckParking) or site.design.truckParking
        local target=blocked and 'waiting' or 'dock'
        if created and finite(inbound.departedAtEpoch) and finite(inbound.arrivedAtEpoch)
            and epoch>inbound.departedAtEpoch+1 then
            if epoch>=inbound.arrivedAtEpoch then
                vehicle.x,vehicle.z=site:toWorld(anchor.x,anchor.z,0)
                vehicle.heading=site.yaw;vehicle.h=world:supportHeight(vehicle.x,vehicle.z)
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
        points=yardPath(route,base,anchor)
        if vehicle.phase~='at_bay' and vehicle.phase~='waiting_bay' then
            local parked=driveVehicle(vehicle,points,step,world,target)
            if parked then
                vehicle.speed=0;vehicle.phase=blocked and 'waiting_bay' or 'at_bay'
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
    local active=false
    eachDelivery(state,function(_,delivery)
        local inbound=delivery and delivery.route
        local outbound=delivery and delivery.returnRoute
        if delivery and ((delivery.status~='received' and inbound and finite(inbound.departedAtEpoch))
            or (delivery.status=='received' and outbound and finite(outbound.departedAtEpoch)
                and (outbound.vehicle and outbound.vehicle.phase~='offmap'
                    or not outbound.vehicle and (not finite(outbound.arrivedAtEpoch) or os.time()<outbound.arrivedAtEpoch)))) then
            active=true
        end
    end)
    if not active then return false,false end
    local route=townWorld(town)
    if not route then return false,false end
    dt=finite(dt) and math.max(0,dt) or 0
    epoch=finite(epoch) and epoch or os.time()
    local vehicles,pedestrians=gatherDynamicActors(state)
    local world=activeWorld
    if type(world)~='table' or world.townId~=route.world.townId then world=route.world end
    installVehicleCollision(world,vehicles,pedestrians)
    local changed,moving=false,false
    eachDelivery(state,function(_,delivery)
        local localChanged
        if delivery and delivery.route and delivery.route.transportId then
            localChanged=false
        else
            localChanged=simulateDelivery(delivery,route,dt,state,epoch,world)
        end
        changed=localChanged or changed
        local active=delivery and (delivery.status=='received'
            and delivery.returnRoute and delivery.returnRoute.vehicle
            or delivery.route and delivery.route.vehicle)
        moving=moving or active~=nil and active.phase~='at_bay' and active.phase~='waiting_bay' and active.phase~='offmap'
    end)
    world.vehicleObstacles=nil;world.sweepTrafficObstacles=nil;world.activeTruck=nil
    return changed,moving
end

function Network.installVehicleObstacles(state,world)
    if not world then return end
    local vehicles,pedestrians=gatherDynamicActors(state)
    installVehicleCollision(world,vehicles,pedestrians)
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

function Network.actors(state,town,now,epoch)
    local route=townWorld(town)
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
            sample=routeSample(route.outward,route.length,progress);phase='departing';speed=Network.AVERAGE_SPEED
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
    return result
end

function Network.cityLocationFor(id)
    return citySites[(hash(id)+1)%#citySites+1]
end

return Network
