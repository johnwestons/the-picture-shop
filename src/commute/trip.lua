-- Durable household travel between the existing weekly departure/arrival gates.
-- The scene adapter owns sprites, input/network transport and player spawning.
local Roads=require('src.commute.roads')
local Rider=require('src.commute.rider')
local Gear=require('src.commute.gear')
local Bike=require('src.commute.motorcycle')
local Truck=require('src.commute.delivery_truck')
local Paint=require('src.commute.bike_paint')
local RidingAnimation=require('src.commute.riding_animation')
local NormalArt=require('src.commute.normal_art')
local Residents=require('src.home_residents')
local Flow=require('src.weekend_flow')
local M=require('src.commute.vendor.mathx')
local Bays=require('src.commute.parking_bays')
local Service=require('src.commute.bike_service')
local Trip={VERSION=1}
local function destinations(world) return world and world.roads and world.roads.destinations or Roads.destinations end
local function door(world,id)
    local sites=world and world.sites or require('src.commute.sites')
    return sites.byId[id].door
end
local function parkedInBay(world,id,bike)
    local site=world and world.sites and world.sites.byId[id]
    if site then return Bays.slotAt(site,bike.x,bike.z)~=nil end
    local pad=destinations(world)[id]
    return M.length(bike.x-pad.x,bike.z-pad.z)<=5
end
local function participantId(id) return id=='owner' or Residents.validId(id) end
local function truckParkedInBay(world,id,truck)
    local site=world and world.sites and world.sites.byId[id]
    if site then
        local x,z=site:toLocal(truck.x,truck.z)
        local safeHalfWidth=4-Truck.RADIUS/site.scale.x
        local safeHalfDepth=3.75-Truck.RADIUS/site.scale.z
        return math.abs(x-site.design.parking.x)<=safeHalfWidth
            and math.abs(z-site.design.parking.z)<=safeHalfDepth
    end
    local pad=destinations(world)[id]
    return M.length(truck.x-pad.x,truck.z-pad.z)<=3
end
function Trip.truckParking(world)
    local site=world and world.sites and world.sites.byId.warehouse
    if not site then return nil end
    local heading=math.atan2(site.front.z,site.front.x)
    for _,localPoint in ipairs({{-3.5,7.8},{-4.4,10.1},{-4.0,5.6}}) do
        local x,z=site:toWorld(localPoint[1],localPoint[2],0)
        local h=world:supportHeight(x,z)
        local clear=true
        for i=0,7 do
            local a=i*math.pi/4
            if world.roads:blocked(world,x+math.cos(a)*Truck.RADIUS,z+math.sin(a)*Truck.RADIUS) then clear=false;break end
        end
        if clear then
            local truck=Truck.new(x,z,heading);truck.h=h;truck.homeX=x;truck.homeZ=z
            return truck
        end
    end
end
function Trip.parking(world,id,slot)
    local pad=destinations(world)[id]
    local site=world and world.sites and world.sites.byId[id]
    if not site then return pad end
    slot=slot or 1
    if slot<1 or slot>Bays.COUNT then return nil end
    local front=site.front
    for _,forward in ipairs({Bays.BIKE_FORWARD,.25,-.65}) do
        local x,z=Bays.center(site,slot,forward)
        -- Leave the pedestrian on the building-side walkway, clear of the
        -- parked motorcycle and the drive aisle.
        local px,pz=x-front.x*1.45,z-front.z*1.45
        if Rider.clear(world,x,z,Bike.RADIUS) and Rider.clear(world,px,pz,Rider.RADIUS)
            and math.abs(world:supportHeight(x,z)-world:supportHeight(px,pz))<.45 then
            return {x=x,z=z,h=pad.h,heading=math.atan2(front.z,front.x),pedX=px,pedZ=pz}
        end
    end
    return nil
end
local function parkedRider(anchor,gear)
    local r=Rider.new(anchor.x,anchor.z,anchor.heading or 0,gear)
    if anchor.pedX then r.ped.x,r.ped.z=anchor.pedX,anchor.pedZ end
    return r
end
local function integer(n,min,max) return M.finite(n) and n%1==0 and n>=min and n<=max end
local function position(p)
    return type(p)=='table' and M.finite(p.x) and M.finite(p.z) and M.finite(p.heading)
        and p.x>=56 and p.x<=458 and p.z>=56 and p.z<=458
end
function Trip.valid(t,home)
    if t==nil then return true end
    if type(t)~='table' or t.version~=Trip.VERSION or not integer(t.mapVersion,1,1000000)
        or not integer(t.token,1,1e12) or not Roads.destinations[t.origin] or not Roads.destinations[t.destination]
        or t.origin==t.destination or (t.origin~='warehouse' and t.destination~='warehouse')
        or t.purpose~=nil and t.purpose~='outing' and t.purpose~='weekend'
        or type(t.participants)~='table' or not t.participants.owner
        or t.mapId~=nil and (type(t.mapId)~='string' or #t.mapId>80
            or home and home.town and t.mapId~=home.town.id) then return false end
    if t.truck~=nil and (not Truck.valid(t.truck)
        or t.truck.driver~=nil and not participantId(t.truck.driver)
        or t.truck.owner~=nil and not participantId(t.truck.owner)) then return false end
    local count,slots,truckDrivers=0,{},0
    for id,p in pairs(t.participants) do
        count=count+1
        if count>4 or id~='owner' and not Residents.validId(id) or type(p)~='table'
            or not integer(p.slot,1,4) or slots[p.slot] or type(p.arrived)~='boolean'
            or type(p.rider)~='table' or not Gear.valid(p.rider.gear)
            or not position(p.rider.ped) or not position(p.rider.bike) or not Bike.valid(p.rider.bike)
            or p.rider.vehicle~=nil and (p.rider.vehicle~='truck' or not t.truck or not Truck.valid(p.rider.truck)
                or p.rider.gear.mounted)
            or p.rider.transport~=nil and (p.rider.transport~='truck' or not t.truck or t.truck.owner~=id)
            or not NormalArt.valid(p.appearance) then return false end
        if p.rider.vehicle=='truck' then
            truckDrivers=truckDrivers+1
            if t.truck.driver~=id or t.truck.owner~=id then return false end
        end
        slots[p.slot]=true
        local v=p.presentation
        if v~=nil and (type(v)~='table' or not Gear.poseNames[v.pose] or not M.finite(v.progress)
            or v.progress<0 or v.progress>1 or not M.finite(v.speed) or v.speed<0 or v.speed>(Bike.MAX_PRESENTATION_SPEED or 32)
            or not M.finite(v.distance) or v.distance<0 or v.distance>1e12) then return false end
        if v then
            if v.pose=='crash' and (p.rider.gear.mounted or p.rider.gear.engine or p.rider.gear.outfit~='geared') then return false end
            if not RidingAnimation.valid(v.ridingAction,v.ridingActionTime) then return false end
            for key,range in pairs({throttle={0,1},brake={0,1},slip={0,1},tireSlip={0,1},accelerationPose={0,1},brakingPose={0,1},
                lateralSpeed={-40,40},grade={-10,10},shiftTime={0,Bike.SHIFT_TIME}}) do
                if v[key]~=nil and (not M.finite(v[key]) or v[key]<range[1] or v[key]>range[2]) then return false end
            end
            for key,range in pairs({steer={-1,1},lean={-1,1},boostPulse={0,Bike.BOOST_PULSE},
                impactPulse={0,Bike.IMPACT_DURATION},impactStrength={0,1},h={-2,100},vy={-50,50},suspension={-1,1},landingPulse={0,2},pitch={-1.6,1.6}}) do
                if v[key]~=nil and (not M.finite(v[key]) or v[key]<range[1] or v[key]>range[2]) then return false end
            end
            if v.boost~=nil and type(v.boost)~='boolean' or v.grounded~=nil and type(v.grounded)~='boolean' then return false end
        end
        if home then
            local resident=home.residents and home.residents[id]
            if not resident or (p.rider.bike.paintId or Paint.DEFAULT)~=(resident.ridingPaintId or Paint.DEFAULT)
                or (p.rider.bike.damage or 0)~=(resident.ridingDamage or 0) then return false end
        end
    end
    if truckDrivers>1 or t.truck and t.truck.driver~=nil
        and (not t.participants[t.truck.driver] or t.participants[t.truck.driver].rider.vehicle~='truck')
        or t.truck and t.truck.owner~=nil and not t.participants[t.truck.owner] then return false end
    if home and (not home.weekend
        or t.origin=='warehouse' and t.destination~=home.apartmentId
        or t.destination=='warehouse' and t.origin~=home.apartmentId
        or t.purpose~='outing' and (t.origin=='warehouse' and home.weekend.phase~='ready'
            or t.destination=='warehouse' and home.weekend.phase~='home')) then return false end
    return t.participants.owner.slot==1
end
function Trip.start(state,players,token,world)
    if state.home.commute then return false,'A commute is already in progress.' end
    if not integer(token,1,1e12) then return false,'Invalid travel request.' end
    local week=Flow.ensure(state);local outing=week.travelPurpose=='outing'
    local homeward=outing and week.travelOrigin=='warehouse' or not outing and week.phase=='ready'
    if week.travelToken~=token then return false,'That travel request has ended.' end
    if outing and week.travelOrigin~='warehouse' and week.travelOrigin~='home' then return false,'Invalid outing origin.' end
    if not outing and not homeward then
        -- Check Monday/weekdays now without advancing the existing weekly phase.
        local copy=require('src.save_schema').copy(state)
        local okay,message=Flow.returnToWork(copy,copy.home.revision)
        if not okay then return false,message end
    end
    local origin=homeward and 'warehouse' or state.home.apartmentId
    local destination=homeward and state.home.apartmentId or 'warehouse'
    local t={version=Trip.VERSION,mapVersion=Roads.VERSION,mapId=world and world.townId,token=token,purpose=outing and 'outing' or 'weekend',origin=origin,destination=destination,participants={}}
    t.truck=Trip.truckParking(world)
    if not t.truck then return false,'No safe loading area is available for the delivery truck.' end
    for _,player in ipairs(players) do
        local id=Residents.key(player);local resident=Residents.get(state,player)
        if not resident or t.participants[id] then return false,'Each traveler needs a distinct household resident.' end
        local gear=Gear.restore(resident.ridingGear)
        if not gear then return false,'Invalid saved riding equipment.' end
        gear.mounted=false;gear.engine=false
        local slot=tonumber(player.id) or 1
        local anchor=Trip.parking(world,origin,slot)
        if not anchor then return false,'There is no safe parking space for this rider.' end
        local rider=parkedRider(anchor,gear)
        rider.bike.transmission=resident.ridingTransmission or 'automatic'
        rider.bike.upgradeLevel=resident.ridingUpgradeLevel or 0
        rider.bike.paintId=resident.ridingPaintId or Paint.DEFAULT
        rider.bike.service=Service.copy(resident.ridingService)
        rider.bike.damage=resident.ridingDamage or 0
        Rider.update(rider,{},0,world)
        t.participants[id]={slot=slot,arrived=false,rider=rider,appearance=NormalArt.appearance(player)}
    end
    if not Trip.valid(t) then return false,'Invalid travel party.' end
    state.home.commute=t;state.home.revision=state.home.revision+1
    return true,t
end
function Trip.snapshot(t)
    if t==nil then return nil end
    assert(Trip.valid(t),'Invalid commute')
    local result={version=t.version,mapVersion=t.mapVersion,mapId=t.mapId,token=t.token,purpose=t.purpose,origin=t.origin,destination=t.destination,participants={},
        truck=t.truck and Truck.snapshot(t.truck) or nil}
    if result.truck then result.truck.owner=t.truck.owner;result.truck.driver=t.truck.driver end
    for id,p in pairs(t.participants) do
        local pose,progress=Rider.pose(p.rider);local actor=Rider.actor(p.rider)
        local bike=p.rider.bike
        local feedback=bike.ridingAnimation or {}
        local ridingAction,ridingActionTime=RidingAnimation.sample(bike)
        local visual=p.presentation or {pose=pose,progress=progress,speed=actor.speed or 0,distance=actor.distance or 0,
            throttle=bike.throttle,brake=bike.brake,slip=bike.slip,tireSlip=bike.tireSlip,lateralSpeed=bike.lateralSpeed,
            grade=bike.grade,shiftTime=bike.shiftTime,lean=bike.lean,
            boost=bike.boosting==true,boostPulse=bike.boostPulse,steer=bike.steering,
            impactPulse=bike.impactPulse,impactStrength=bike.impactStrength,
            h=bike.h,vy=bike.vy,pitch=bike.pitch,grounded=bike.grounded,suspension=bike.suspension,landingPulse=bike.landingPulse,
            ridingAction=ridingAction,ridingActionTime=ridingActionTime,
            accelerationPose=feedback.accelerationWeight,brakingPose=feedback.brakingWeight}
        result.participants[id]={slot=p.slot,arrived=p.arrived,rider=Rider.snapshot(p.rider),
            appearance=NormalArt.appearance(p.appearance),
            presentation={pose=visual.pose,progress=visual.progress,speed=visual.speed,distance=visual.distance,
                throttle=visual.throttle,brake=visual.brake,slip=visual.slip,tireSlip=visual.tireSlip,lateralSpeed=visual.lateralSpeed,
                grade=visual.grade,shiftTime=visual.shiftTime,
                lean=visual.lean,boost=visual.boost,boostPulse=visual.boostPulse,steer=visual.steer,
                impactPulse=visual.impactPulse,impactStrength=visual.impactStrength,
                h=visual.h,vy=visual.vy,pitch=visual.pitch,grounded=visual.grounded,suspension=visual.suspension,landingPulse=visual.landingPulse,
                ridingAction=visual.ridingAction,ridingActionTime=visual.ridingActionTime,
                accelerationPose=visual.accelerationPose,brakingPose=visual.brakingPose}}
    end
    return result
end
function Trip.restore(t,world)
    if not t then return nil end
    if not Trip.valid(t) then return nil,'Invalid saved commute.' end
    if t.mapId and world.townId and t.mapId~=world.townId then return nil,'The saved trip belongs to another town.' end
    local result=Trip.snapshot(t)
    if not result.truck or t.mapVersion~=Roads.VERSION then result.truck=Trip.truckParking(world) end
    if not result.truck then return nil,'No safe loading area exists for the delivery truck.' end
    if t.mapVersion~=Roads.VERSION then result.truck.owner=nil;result.truck.driver=nil end
    for _,p in pairs(result.participants) do
        local anchor=Trip.parking(world,p.arrived and t.destination or t.origin,p.slot)
        if not anchor then return nil,'No safe parking space exists for the saved rider.' end
        if t.mapVersion~=Roads.VERSION then
            p.rider.bike.x=-1 -- Rider recovery relocates to a valid parking pad.
            p.rider.vehicle=nil;p.rider.transport=nil
        end
        local rider,reason=Rider.restore(p.rider,world,anchor)
        if not rider then return nil,reason end
        p.rider=rider
        if rider.vehicle=='truck' then rider.truck=result.truck end
        p.presentation=nil
        if t.mapVersion~=Roads.VERSION then p.arrived=false end
    end
    result.mapVersion=Roads.VERSION;result.mapId=world.townId;return result
end
function Trip.participant(state,player,token)
    local t=state.home.commute
    if not t or t.token~=token then return nil,'That commute has ended.' end
    local part=t.participants[Residents.key(player)]
    if not part or part.slot~=(tonumber(player.id) or 1) then return nil,'You are not assigned to this commute.' end
    return part,t
end
function Trip.command(state,player,token,action,world)
    local part,t=Trip.participant(state,player,token)
    if not part then return false,t end
    if part.arrived then return false,'Already waiting at the destination door.' end
    if action~='arrive' then
        if action=='truck' then
            local rider=t.participants[Residents.key(player)].rider
            local truck=t.truck
            if not truck then return false,'The delivery truck is unavailable.' end
            if rider.vehicle=='truck' then
                if truck.driver~=Residents.key(player) then return false,'The truck controls are assigned to another rider.' end
                if truck.speed>.05 then return false,'Stop the delivery truck before getting out.' end
                local sideX,sideZ=-math.sin(truck.heading),math.cos(truck.heading)
                local x,z
                for _,sign in ipairs({1,-1}) do
                    local sx,sz=truck.x+sideX*1.8*sign,truck.z+sideZ*1.8*sign
                    local h=world:supportHeight(sx,sz)
                    local hit=world.sweepObstacles and world:sweepObstacles(sx,sz,sx,sz,Rider.RADIUS,h,h+1.7)
                    if Rider.clear(world,sx,sz,Rider.RADIUS) and not hit then x,z=sx,sz;break end
                end
                if not x then return false,'There is no clear space beside the truck.' end
                rider.vehicle=nil;rider.truck=nil
                rider.ped.x,rider.ped.z,rider.ped.heading=x,z,truck.heading
                rider.ped.speed,rider.ped.vx,rider.ped.vz=0,0,0
                truck.driver=nil
                state.home.revision=state.home.revision+1
                return true,'You are out of the delivery truck.'
            end
            if t.origin~='warehouse' then return false,'The delivery truck is available from the warehouse loading area.' end
            if rider.gear.mounted or rider.gear.transition or rider.ped.crash then return false,'Get off the motorcycle and finish the current action first.' end
            if truck.owner and truck.owner~=Residents.key(player) then return false,'The delivery truck is assigned to another rider.' end
            if truck.driver then return false,'Another rider is driving the delivery truck.' end
            if M.length(rider.ped.x-truck.x,rider.ped.z-truck.z)>5.5 then return false,'Walk over to the delivery truck first.' end
            truck.owner=Residents.key(player);truck.driver=Residents.key(player)
            rider.vehicle='truck';rider.transport='truck';rider.truck=truck
            rider.ped.x,rider.ped.z,rider.ped.heading=truck.x,truck.z,truck.heading
            rider.ped.speed,rider.ped.vx,rider.ped.vz=0,0,0
            state.home.revision=state.home.revision+1
            return true,'Delivery truck ready. Use the riding controls to drive; stop and interact to get out.'
        end
        if part.rider.vehicle=='truck' then return false,'Get out of the delivery truck before using motorcycle controls.' end
        local okay,message=Rider.command(part.rider,action,world)
        if okay and action=='mount' then part.rider.transport=nil end
        if okay and action=='rescue' then state.home.revision=state.home.revision+1 end
        if okay and (action=='automatic' or action=='manual') then
            local resident=Residents.get(state,player)
            resident.ridingTransmission=action;resident.revision=resident.revision+1
            state.home.revision=state.home.revision+1
        end
        return okay,message
    end
    local r=part.rider;local entrance=door(world,t.destination)
    if r.vehicle=='truck' then return false,'Stop and get out of the delivery truck before walking to the door.' end
    if r.ped.crash or not Gear.allowed(r.gear,'door') or r.ped.speed>.05 then return false,'Stop on foot at the destination door.' end
    local isTruck=r.transport=='truck'
    local vehicle=isTruck and t.truck or r.bike
    local inBay=vehicle and (isTruck and truckParkedInBay(world,t.destination,vehicle)
        or not isTruck and parkedInBay(world,t.destination,vehicle))
    if not vehicle or not inBay or (vehicle.speed or 0)>.05 then
        return false,isTruck and 'Park the delivery truck in the loading area first.'
            or 'Park your motorcycle inside a marked space first.'
    end
    if M.length(r.ped.x-entrance.x,r.ped.z-entrance.z)>1.8 then return false,'Walk to the destination door.' end
    part.arrived=true;state.home.revision=state.home.revision+1;return true
end
function Trip.update(state,player,input,dt,world)
    local t=state.home.commute;if not t then return false end
    local part=Trip.participant(state,player,t.token)
    if not part or part.arrived then return false end
    local changed
    if part.rider.vehicle=='truck' then
        local truck=t.truck
        if not truck or truck.driver~=Residents.key(player) then return false end
        changed=Truck.update(truck,input,dt,world)>0
        part.rider.truck=truck
        part.rider.ped.x,part.rider.ped.z,part.rider.ped.heading=truck.x,truck.z,truck.heading
        part.rider.ped.h=truck.h;part.rider.ped.speed=0
    else changed=Rider.update(part.rider,input,dt,world) end
    local resident=state.home.residents[Residents.key(player)]
    resident.ridingService=part.rider.bike.service
    local damage=part.rider.bike.damage or 0
    if damage~=(resident.ridingDamage or 0) then
        resident.ridingDamage=damage
        resident.revision=resident.revision+1
        changed=true
    end
    if changed then state.home.revision=state.home.revision+1 end
    return changed
end
function Trip.finish(state,host,token,bringEveryone)
    if (tonumber(host.id) or 1)~=1 then return false,'The host chooses when the household enters.' end
    local owner,t=Trip.participant(state,host,token)
    if not owner then return false,t end
    if not Trip.valid(t,state.home) then return false,'The commute no longer matches this household.' end
    if not owner.arrived then return false,'Park, dismount and walk to the destination door first.' end
    for _,part in pairs(t.participants) do
        if not part.arrived and not bringEveryone then return false,'Waiting for the other riders. The host can bring everyone.' end
    end
    local okay,message
    if t.purpose=='outing' then okay=Flow.outingArrival(state,t.destination~='warehouse');message=state.message
    elseif t.destination=='warehouse' then okay,message=Flow.returnToWork(state,state.home.revision)
    else okay,message=Flow.depart(state,state.home.revision) end
    if not okay then return false,message end
    for id,part in pairs(t.participants) do
        local resident=state.home.residents[id]
        local gear=Gear.snapshot(part.rider.gear);gear.mounted=false;gear.engine=false
        resident.ridingGear=gear;resident.ridingUpgradeLevel=part.rider.bike.upgradeLevel or 0
        resident.ridingPaintId=part.rider.bike.paintId or Paint.DEFAULT;resident.revision=resident.revision+1
    end
    state.home.commute=nil
    -- The scene adapter uses this result to spawn all travelers through the
    -- existing apartment/warehouse spawn resolution in the same update.
    return true,{destination=t.destination,participants=t.participants,message=message}
end
function Trip.rebind(state,player,connected,world)
    local t=state.home.commute;if not t then return true end
    local id=Residents.key(player);local slot=tonumber(player.id) or 1
    local resident=Residents.get(state,player)
    if not resident then return false,'Your resident has not joined this household.' end
    if not integer(slot,1,4) or (slot==1)~=(id=='owner') then return false,'Invalid rider slot.' end
    local live={owner=true}
    for _,p in pairs(connected or {}) do local key=Residents.key(p);if p~=player and key then live[key]=true end end
    local part=t.participants[id];local count,occupied=0,{}
    for _,other in pairs(t.participants) do count=count+1;occupied[other.slot]=true end
    local function retain(otherId,other)
        local person=state.home.residents[otherId]
        if person then local gear=Gear.snapshot(other.rider.gear);gear.mounted=false;gear.engine=false;person.ridingGear=gear end
        if t.truck and t.truck.owner==otherId then t.truck.owner=nil;t.truck.driver=nil end
    end
    for otherId,other in pairs(t.participants) do
        if otherId~=id and other.slot==slot then
            if live[otherId] then return false,'That rider slot is already connected.' end
            if part then other.slot=part.slot
            else
                local spare
                for candidate=2,4 do if not occupied[candidate] then spare=candidate;break end end
                if spare then other.slot=spare
                else retain(otherId,other);t.participants[otherId]=nil;count=count-1 end
            end
        end
    end
    if not part then
        if count>=4 then return false,'This commute already has four riders.' end
        local anchor=Trip.parking(world,t.origin,slot)
        if not anchor then return false,'There is no safe parking space for this rider.' end
        local gear=assert(Gear.restore(resident.ridingGear));gear.mounted=false;gear.engine=false
        part={slot=slot,arrived=false,rider=parkedRider(anchor,gear)}
        part.rider.bike.transmission=resident.ridingTransmission or 'automatic'
        part.rider.bike.upgradeLevel=resident.ridingUpgradeLevel or 0
        part.rider.bike.paintId=resident.ridingPaintId or Paint.DEFAULT
        part.rider.bike.service=Service.copy(resident.ridingService)
        part.rider.bike.damage=resident.ridingDamage or 0
        Rider.update(part.rider,{},0,world);t.participants[id]=part
    else
        part.rider=assert(Rider.restore(Rider.snapshot(part.rider),world,assert(Trip.parking(world,t.origin,slot))))
    end
    part.slot=slot;part.presentation=nil;part.appearance=NormalArt.appearance(player)
    state.home.revision=state.home.revision+1;return true,part
end
function Trip.cancel(state,host,token,world)
    if (tonumber(host.id) or 1)~=1 then return false,'The host chooses when to return inside.' end
    local owner,t=Trip.participant(state,host,token);if not owner then return false,t end
    local entrance=door(world,t.origin);local r=owner.rider
    if not Gear.allowed(r.gear,'door') or r.ped.speed>.05
        or M.length(r.ped.x-entrance.x,r.ped.z-entrance.z)>1.8 then return false,'Walk to the origin door first.' end
    for _,part in pairs(t.participants) do
        if part.rider.ped.crash or part.rider.gear.mounted or part.rider.vehicle=='truck' or part.rider.gear.transition
            or not parkedInBay(world,t.origin,part.rider.bike) then
            return false,'Other riders need to return and dismount before going back inside.'
        end
    end
    if t.truck and t.truck.owner and M.length(t.truck.x-t.truck.homeX,t.truck.z-t.truck.homeZ)>5.5 then
        return false,'Return the delivery truck to the loading area before going back inside.'
    end
    for id,part in pairs(t.participants) do state.home.residents[id].ridingGear=Gear.snapshot(part.rider.gear) end
    if t.purpose=='outing' then Flow.outingArrival(state,t.origin~='warehouse') end
    state.home.commute=nil;state.home.revision=state.home.revision+1
    return true,{destination=t.origin,participants=t.participants,message='Back inside. Your riding gear stays with you.'}
end
return Trip
