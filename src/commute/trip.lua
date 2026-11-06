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
local function participantId(id) return id=='owner' or Residents.validId(id) end
local function truckParkedInBay(world,id,truck)
    local site=world and world.sites and world.sites.byId[id]
    if site then
        local x,z=site:toLocal(truck.x,truck.z)
        if id=='warehouse' and site.localTruckParkingArea and site.design.truckParking then
            -- The enlarged hardscape includes a staging slot. Only the marked
            -- primary anchor counts as the loading bay for pallet interactions.
            return math.abs(x-site.design.truckParking.x)<=1.1/site.scale.x
                and math.abs(z-site.design.truckParking.z)<=.9/site.scale.z
        end
        local safeHalfWidth=4-Truck.RADIUS/site.scale.x
        local safeHalfDepth=3.75-Truck.RADIUS/site.scale.z
        return math.abs(x-site.design.parking.x)<=safeHalfWidth
            and math.abs(z-site.design.parking.z)<=safeHalfDepth
    end
    local pad=destinations(world)[id]
    return M.length(truck.x-pad.x,truck.z-pad.z)<=3
end
function Trip.truckAtLoadingBay(world,truck)
    return truck~=nil and truckParkedInBay(world,'warehouse',truck)
end
function Trip.truckParking(world,companyTruck)
    local site=world and world.sites and world.sites.byId.warehouse
    if not site then return nil end
    local heading=site.design.truckParking and site.yaw or math.atan2(site.front.z,site.front.x)
    local candidates=site.design.truckParking and {{site.design.truckParking.x,site.design.truckParking.z}}
        or {{-3.5,7.8},{-4.4,10.1},{-4.0,5.6}}
    for _,localPoint in ipairs(candidates) do
        local x,z=site:toWorld(localPoint[1],localPoint[2],0)
        local h=world:supportHeight(x,z)
        if not Truck.blocked(world,x,z,heading) then
            local truck=Truck.new(x,z,heading,'picture_shop');truck.h=h;truck.homeX=x;truck.homeZ=z
            require('src.company_delivery_driver').apply(companyTruck,truck)
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
    local delivery=type(t)=='table' and t.purpose=='delivery'
    local independent=type(t)=='table' and t.independent==true
    if type(t)~='table' or t.version~=Trip.VERSION or not integer(t.mapVersion,1,1000000)
        or not integer(t.token,1,1e12) or not Roads.destinations[t.origin] or not Roads.destinations[t.destination]
        or t.origin==t.destination and not delivery or (t.origin~='warehouse' and t.destination~='warehouse')
        or t.purpose~=nil and t.purpose~='outing' and t.purpose~='weekend' and not delivery
        or delivery and (t.origin~='warehouse' or t.destination~='warehouse'
            or not require('src.commute.delivery_run').valid(t.deliveryRun,home))
        or not delivery and t.deliveryRun~=nil and not independent
        or t.independent~=nil and t.independent~=true
        or independent and (t.purpose~='outing' or t.origin~='warehouse')
        or independent and t.deliveryRun~=nil and (not require('src.commute.delivery_run').valid(t.deliveryRun,home)
            or not participantId(t.deliveryDriver))
        or independent and t.deliveryRun==nil and t.deliveryDriver~=nil
        or type(t.participants)~='table' or not independent and not t.participants.owner
        or t.mapId~=nil and (type(t.mapId)~='string' or #t.mapId>80
            or home and home.town and t.mapId~=home.town.id) then return false end
    if t.truck~=nil and (not Truck.valid(t.truck)
        or t.truck.driver~=nil and not participantId(t.truck.driver)
        or t.truck.owner~=nil and not participantId(t.truck.owner)) then return false end
    local count,slots,truckDrivers=0,{},0
    for id,p in pairs(t.participants) do
        count=count+1
        if count>(independent and 65 or 4) or id~='owner' and not Residents.validId(id) or type(p)~='table'
            or not integer(p.slot,1,4) or not independent and slots[p.slot] or type(p.arrived)~='boolean'
            or independent and ((p.slot==1)~=(id=='owner') or not Roads.destinations[p.origin]
                or not Roads.destinations[p.destination]
                or p.interior~=nil and p.interior~='grocery')
            or p.interior~=nil and (not independent or type(p.interiorPose)~='table'
                or not M.finite(p.interiorPose.x) or not M.finite(p.interiorPose.y)
                or not M.finite(p.interiorPose.intentX) or math.abs(p.interiorPose.intentX)>1
                or not M.finite(p.interiorPose.intentY) or math.abs(p.interiorPose.intentY)>1
                or not M.finite(p.interiorPose.animationDistance) or p.interiorPose.animationDistance<0
                or p.interiorPose.animationDistance>1e12 or type(p.interiorPose.moving)~='boolean'
                or not require('src.commute.grocery_interior').walkable(p.interiorPose.x,p.interiorPose.y))
            or p.interior==nil and p.interiorPose~=nil
            or type(p.rider)~='table' or not Gear.valid(p.rider.gear)
            or p.interior~=nil and (p.rider.gear.mounted or p.rider.vehicle~=nil)
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
            if independent and (p.origin~='warehouse' and p.origin~=home.apartmentId
                or p.destination~='warehouse' and p.destination~=home.apartmentId) then return false end
            local resident=home.residents and home.residents[id]
            if not resident or (p.rider.bike.paintId or Paint.DEFAULT)~=(resident.ridingPaintId or Paint.DEFAULT)
                or (p.rider.bike.damage or 0)~=(resident.ridingDamage or 0) then return false end
        end
    end
    if truckDrivers>1 or t.truck and t.truck.driver~=nil
        and (not t.participants[t.truck.driver] or t.participants[t.truck.driver].rider.vehicle~='truck')
        or t.truck and t.truck.owner~=nil and not t.participants[t.truck.owner] then return false end
    if independent and t.deliveryDriver and (not t.participants[t.deliveryDriver]
        or not t.truck or t.truck.owner~=t.deliveryDriver) then return false end
    if home then
        if delivery then
            if not home.town then return false end
        elseif not home.weekend
            or t.origin=='warehouse' and t.destination~=home.apartmentId
            or t.destination=='warehouse' and t.origin~=home.apartmentId
            or t.purpose~='outing' and (t.origin=='warehouse' and home.weekend.phase~='ready'
                or t.destination=='warehouse' and home.weekend.phase~='home') then return false end
    end
    return independent or t.participants.owner.slot==1
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
    t.truck=Trip.truckParking(world,require('src.company_delivery_driver').ensure(state))
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
        rider.bike.upgradeParts=require('src.commute.bike_upgrades').copyParts(resident.ridingUpgradeParts)
        rider.bike.paintId=resident.ridingPaintId or Paint.DEFAULT
        rider.bike.service=Service.copy(resident.ridingService)
        rider.bike.damage=resident.ridingDamage or 0
        Rider.update(rider,{},0,world)
        t.participants[id]={slot=slot,arrived=false,rider=rider,appearance=NormalArt.appearance(player)}
    end
    if not Trip.valid(t) then return false,'Invalid travel party.' end
    for id in pairs(t.participants) do state.home.residents[id].bikeParkedAtHome=false end
    state.home.commute=t;state.home.revision=state.home.revision+1
    return true,t
end
local function dataCopy(value)
    if type(value)~='table' then return value end
    local result={};for key,item in pairs(value) do result[key]=dataCopy(item) end;return result
end
function Trip.snapshot(t)
    if t==nil then return nil end
    assert(Trip.valid(t),'Invalid commute')
    local result={version=t.version,mapVersion=t.mapVersion,mapId=t.mapId,token=t.token,purpose=t.purpose,origin=t.origin,destination=t.destination,participants={},
        independent=t.independent,deliveryDriver=t.deliveryDriver,
        truck=t.truck and Truck.snapshot(t.truck) or nil,
        deliveryRun=t.deliveryRun and dataCopy(t.deliveryRun) or nil}
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
            origin=p.origin,destination=p.destination,interior=p.interior,interiorPose=dataCopy(p.interiorPose),
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
function Trip.restore(t,world,companyTruck)
    if not t then return nil end
    if not Trip.valid(t) then return nil,'Invalid saved commute.' end
    if t.mapId and world.townId and t.mapId~=world.townId then return nil,'The saved trip belongs to another town.' end
    local result=Trip.snapshot(t)
    if not result.truck or t.mapVersion~=Roads.VERSION then result.truck=Trip.truckParking(world,companyTruck) end
    if t.mapVersion~=Roads.VERSION and result.deliveryRun and result.deliveryRun.status=='offmap' then
        -- Re-enter the gate cinematic after a road-map migration instead of
        -- restoring an off-map driver with no usable vehicle controls.
        result.deliveryRun.status='driving'
        result.deliveryRun.cutsceneStartedAtEpoch=nil;result.deliveryRun.cutsceneEndsAtEpoch=nil
    end
    if not result.truck then return nil,'No safe loading area exists for the delivery truck.' end
    if t.mapVersion~=Roads.VERSION then result.truck.owner=nil;result.truck.driver=nil end
    for _,p in pairs(result.participants) do
        local anchor=Trip.parking(world,p.arrived and (p.destination or t.destination) or (p.origin or t.origin),p.slot)
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
    if companyTruck and result.truck then
        if t.truck and t.truck.fuel~=nil and t.mapVersion==Roads.VERSION then
            companyTruck.fuelLiters=result.truck.fuel
        else
            require('src.company_delivery_driver').apply(companyTruck,result.truck)
        end
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
    if t.independent then
        if part.interior then return false,'Leave the store before using outdoor controls.' end
        t=setmetatable({origin=part.origin,destination=part.destination,
            deliveryRun=t.deliveryDriver==Residents.key(player) and t.deliveryRun or false},{__index=t})
    end
    if part.arrived then return false,'Already waiting at the destination door.' end
    local run=t.deliveryRun
    if run and run.status=='offmap' then return false,'The truck is making its short off-map delivery run.' end
    if run and action=='load_delivery' then
        if run.status~='loading' then return false,'The delivery pallets have already been loaded.' end
        local rider=part.rider
        if rider.vehicle or rider.gear.mounted or rider.gear.transition or rider.ped.crash
            or rider.ped.speed>.05 then return false,'Get out of the truck and stand still to load the pallets.' end
        if not t.truck or t.truck.speed>.05 then return false,'Stop the delivery truck before loading pallets.' end
        if not Trip.truckAtLoadingBay(world,t.truck) then
            return false,'Park the truck inside the marked warehouse loading bay before loading pallets.'
        end
        if M.length(rider.ped.x-t.truck.x,rider.ped.z-t.truck.z)>5.5 then
            return false,'Walk over to the truck in the loading bay to load the pallets.'
        end
        local okay,message=require('src.commute.delivery_run').load(state,run)
        if not okay then return false,message end
        run.status='driving'
        state.home.revision=state.home.revision+1
        return true,'Pallets loaded. Follow the GPS to the first delivery stop.'
    end
    if run and action=='deliver_stop' then
        local stop=run.stops[run.stopIndex]
        if run.status~='driving' or not stop or stop.kind~='town' then
            return false,'There is no local delivery ready at this stop.'
        end
        local rider=part.rider;local site=world.sites.byId[stop.id]
        if not site or rider.vehicle or rider.gear.mounted or rider.gear.transition
            or rider.ped.crash or rider.ped.speed>.05 then
            return false,'Park the truck and walk to the delivery door.'
        end
        local doorPoint=site.door
        if M.length(rider.ped.x-doorPoint.x,rider.ped.z-doorPoint.z)>1.8 then
            return false,'Walk to '..stop.label..' to hand off the pallets.'
        end
        if not t.truck or t.truck.speed>.05
            or M.length(t.truck.x-doorPoint.x,t.truck.z-doorPoint.z)>22 then
            return false,'Park the delivery truck near the customer first.'
        end
        local okay,message=require('src.commute.delivery_run').completeStop(state,stop)
        if not okay then return false,message end
        run.stopIndex=run.stopIndex+1
        if run.stopIndex>#run.stops then run.status='returning' end
        state.home.revision=state.home.revision+1
        return true,'Delivered '..stop.palletCount..' pallet'..(stop.palletCount==1 and '' or 's')..' to '..stop.label..'.'
    end
    if run and action=='arrive' and run.status~='loading'
        and (run.status~='returning' or run.stopIndex<=#run.stops) then
        return false,'Finish every planned delivery and return to the warehouse first.'
    end
    if action~='arrive' then
        if action=='truck' then
            local rider=t.participants[Residents.key(player)].rider
            local truck=t.truck
            if not truck then return false,'The delivery truck is unavailable.' end
            if require('src.company_delivery_driver').busy(state) then
                return false,'The scheduled driver is using the delivery truck right now.'
            end
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
            if not t.independent and t.origin~='warehouse' then return false,'The delivery truck is available from the warehouse loading area.' end
            if rider.gear.mounted or rider.gear.transition or rider.ped.crash then return false,'Get off the motorcycle and finish the current action first.' end
            if truck.owner and truck.owner~=Residents.key(player) then return false,'The delivery truck is assigned to another rider.' end
            if truck.driver then return false,'Another rider is driving the delivery truck.' end
            if M.length(rider.ped.x-truck.x,rider.ped.z-truck.z)>5.5 then return false,'Walk over to the delivery truck first.' end
            truck.fuel=require('src.company_delivery_driver').ensure(state).fuelLiters
            truck.owner=Residents.key(player);truck.driver=Residents.key(player)
            rider.vehicle='truck';rider.transport='truck';rider.truck=truck
            rider.ped.x,rider.ped.z,rider.ped.heading=truck.x,truck.z,truck.heading
            rider.ped.speed,rider.ped.vx,rider.ped.vz=0,0,0
            state.home.revision=state.home.revision+1
            return true,'Delivery truck ready. Use the riding controls to drive; stop and interact to get out.'
        end
        if part.rider.vehicle=='truck' then
            local radioAction=({radioPrevious='previous',radioPlay='play',radioNext='next',radioMute='mute'})[action]
            if radioAction then
                if t.truck.driver~=Residents.key(player) then return false,'The truck controls are assigned to another rider.' end
                local okay=require('src.jukebox').control(radioAction)
                if okay then state.home.revision=state.home.revision+1 end
                return okay,okay and 'Truck radio updated.' or 'That radio control is unavailable.'
            end
            if action=='ignition' or action=='headlight' or action=='beam'
                or action=='signalLeft' or action=='signalRight' or action=='rescue' then
                if t.truck.driver~=Residents.key(player) then return false,'The truck controls are assigned to another rider.' end
                local okay,message=Truck.command(t.truck,action,world)
                if okay then state.home.revision=state.home.revision+1 end
                return okay,message
            end
            return false,'Get out of the delivery truck before using motorcycle controls.'
        end
        if run and action=='mount' then return false,'Use the delivery truck for this route.' end
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
    if M.length(r.ped.x-entrance.x,r.ped.z-entrance.z)>1.8 then return false,'Walk to the destination door.' end
    part.arrived=true;state.home.revision=state.home.revision+1;return true
end
function Trip.update(state,player,input,dt,world)
    local t=state.home.commute;if not t then return false end
    local part=Trip.participant(state,player,t.token)
    if not part or part.arrived then return false end
    if part.interior then
        local dx,dz=input.walkX or 0,input.walkZ or 0
        local length=math.sqrt(dx*dx+dz*dz)
        if length>1 then dx,dz=dx/length,dz/length end
        require('src.commute.grocery_interior').movePose(part.interiorPose,dx*145*math.min(.1,dt),dz*145*math.min(.1,dt))
        return false
    end
    local run=(not t.independent or t.deliveryDriver==Residents.key(player)) and t.deliveryRun
    if run and run.status=='offmap' then
        local key=Residents.key(player)
        local driver=t.truck and (key==t.truck.driver
            or t.truck.driver==nil and (tonumber(player.id) or 1)==1)
        if driver and os.time()>=(run.cutsceneEndsAtEpoch or math.huge) then
            local stop=run.stops[run.stopIndex]
            local okay,message=require('src.commute.delivery_run').completeStop(state,stop)
            if not okay then state.message=message;return false end
            run.stopIndex=run.stopIndex+1
            run.status=run.stopIndex>#run.stops and 'returning' or 'driving'
            run.cutsceneStartedAtEpoch=nil;run.cutsceneEndsAtEpoch=nil
            local gate=world.mainlandExit
            local dx,dz=math.cos(gate.heading),math.sin(gate.heading)
            if not t.truck.driver then
                t.truck.owner,t.truck.driver=key,key
                part.rider.vehicle='truck';part.rider.transport='truck';part.rider.truck=t.truck
            end
            t.truck.x,t.truck.z=gate.x-dx*8,gate.z-dz*8
            local nextStop=run.stops[run.stopIndex]
            t.truck.heading=nextStop and nextStop.kind=='city' and gate.heading or gate.heading+math.pi
            t.truck.speed=0;t.truck.reverse=false
            t.truck.h=world:supportHeight(t.truck.x,t.truck.z)
            part.rider.ped.x,part.rider.ped.z,part.rider.ped.heading=t.truck.x,t.truck.z,t.truck.heading
            state.message='Millhaven delivery complete. Return to The Picture Shop.'
            state.home.revision=state.home.revision+1
            return true
        end
        return false
    end
    local changed
    if part.rider.vehicle=='truck' then
        local truck=t.truck
        if not truck or truck.driver~=Residents.key(player) then return false end
        changed=Truck.update(truck,input,dt,world)>0
        if require('src.company_delivery_driver').syncFromVehicle(
            require('src.company_delivery_driver').ensure(state),truck) then changed=true end
        part.rider.truck=truck
        part.rider.ped.x,part.rider.ped.z,part.rider.ped.heading=truck.x,truck.z,truck.heading
        part.rider.ped.h=truck.h;part.rider.ped.speed=0
        if run and run.status=='driving' then
            local stop=run.stops[run.stopIndex]
            local gate=world.mainlandExit
            if stop and stop.kind=='city' and gate and truck.speed>.4 then
                local dx,dz=math.cos(gate.heading),math.sin(gate.heading)
                local along=(truck.x-gate.x)*dx+(truck.z-gate.z)*dz
                local across=math.abs((truck.x-gate.x)*(-dz)+(truck.z-gate.z)*dx)
                local facing=math.cos(truck.heading)*dx+math.sin(truck.heading)*dz
                if along>=-16 and along<=3 and across<=8 and facing>.45 then
                    run.status='offmap';run.cutsceneStartedAtEpoch=os.time()
                    run.cutsceneEndsAtEpoch=run.cutsceneStartedAtEpoch+5
                    truck.x,truck.z=gate.x-dx*8,gate.z-dz*8
                    truck.speed=0;truck.h=world:supportHeight(truck.x,truck.z)
                    part.rider.ped.x,part.rider.ped.z,part.rider.ped.heading=truck.x,truck.z,truck.heading
                    state.home.revision=state.home.revision+1
                    return true
                end
            end
        end
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
    if not owner.arrived then return false,'Dismount and walk to the destination door first.' end
    if t.deliveryRun and (t.deliveryRun.status~='returning'
        or t.deliveryRun.stopIndex<=#t.deliveryRun.stops) then
        return false,'Complete the delivery route and return the truck to the warehouse first.'
    end
    for _,part in pairs(t.participants) do
        if not part.arrived and not bringEveryone then return false,'Waiting for the other riders. The host can bring everyone.' end
    end
    local okay,message
    if t.purpose=='delivery' then
        okay=true;message='Delivery route complete. The truck and remaining pallets are back at the warehouse.'
        state.home.revision=state.home.revision+1
    elseif t.purpose=='outing' then okay=Flow.outingArrival(state,t.destination~='warehouse');message=state.message
    elseif t.destination=='warehouse' then okay,message=Flow.returnToWork(state,state.home.revision)
    else okay,message=Flow.depart(state,state.home.revision) end
    if not okay then return false,message end
    for id,part in pairs(t.participants) do
        local resident=state.home.residents[id]
        local gear=Gear.snapshot(part.rider.gear);gear.mounted=false;gear.engine=false
        resident.ridingGear=gear;resident.ridingUpgradeLevel=part.rider.bike.upgradeLevel or 0
        resident.ridingUpgradeParts=require('src.commute.bike_upgrades').copyParts(part.rider.bike.upgradeParts)
        resident.ridingPaintId=part.rider.bike.paintId or Paint.DEFAULT;resident.revision=resident.revision+1
        resident.bikeParkedAtHome=t.destination==state.home.apartmentId and part.arrived
            and part.rider.vehicle~='truck' and part.rider.transport~='truck'
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
    -- Joining the host never enrolls an indoor resident in somebody else's trip.
    if t.independent then
        if not part then return true end
        -- Resident identity owns a journey. A disconnected resident's former
        -- network slot may be reused without moving or adopting that traveler.
        part.slot=slot;part.presentation=nil;part.appearance=NormalArt.appearance(player)
        part.rider=assert(Rider.restore(Rider.snapshot(part.rider),world,assert(Trip.parking(world,part.origin,slot))))
        if part.rider.vehicle=='truck' then part.rider.truck=t.truck end
        state.home.revision=state.home.revision+1
        return true,part
    end
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
        part.rider.bike.upgradeParts=require('src.commute.bike_upgrades').copyParts(resident.ridingUpgradeParts)
        part.rider.bike.paintId=resident.ridingPaintId or Paint.DEFAULT
        part.rider.bike.service=Service.copy(resident.ridingService)
        part.rider.bike.damage=resident.ridingDamage or 0
        resident.bikeParkedAtHome=false
        Rider.update(part.rider,{},0,world);t.participants[id]=part
    else
        part.rider=assert(Rider.restore(Rider.snapshot(part.rider),world,assert(Trip.parking(world,part.origin or t.origin,slot))))
        if part.rider.vehicle=='truck' then part.rider.truck=t.truck end
    end
    part.slot=slot;part.presentation=nil;part.appearance=NormalArt.appearance(player)
    state.home.revision=state.home.revision+1;return true,part
end
function Trip.cancel(state,host,token,world)
    if (tonumber(host.id) or 1)~=1 then return false,'The host chooses when to return inside.' end
    local owner,t=Trip.participant(state,host,token);if not owner then return false,t end
    if t.deliveryRun and t.deliveryRun.status~='loading' then
        return false,'Complete the planned stops and return the truck before ending the delivery route.'
    end
    local entrance=door(world,t.origin);local r=owner.rider
    if not Gear.allowed(r.gear,'door') or r.ped.speed>.05
        or M.length(r.ped.x-entrance.x,r.ped.z-entrance.z)>1.8 then return false,'Walk to the origin door first.' end
    for _,part in pairs(t.participants) do
        if part.rider.ped.crash or part.rider.gear.mounted or part.rider.vehicle=='truck' or part.rider.gear.transition then
            return false,'Other riders need to return and dismount before going back inside.'
        end
    end
    for id,part in pairs(t.participants) do
        local resident=state.home.residents[id]
        resident.ridingGear=Gear.snapshot(part.rider.gear)
        resident.bikeParkedAtHome=t.origin==state.home.apartmentId
    end
    if t.purpose=='outing' then Flow.outingArrival(state,t.origin~='warehouse') end
    state.home.commute=nil;state.home.revision=state.home.revision+1
    return true,{destination=t.origin,participants=t.participants,message='Back inside. Your riding gear stays with you.'}
end
return Trip
