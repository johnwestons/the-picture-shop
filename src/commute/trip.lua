-- Durable household travel between the existing weekly departure/arrival gates.
-- The scene adapter owns sprites, input/network transport and player spawning.
local Roads=require('src.commute.roads')
local Rider=require('src.commute.rider')
local Gear=require('src.commute.gear')
local Bike=require('src.commute.motorcycle')
local AIMotorcycleTraffic=require('src.commute.ai_motorcycle_traffic')
local Truck=require('src.commute.delivery_truck')
local Paint=require('src.commute.bike_paint')
local RidingAnimation=require('src.commute.riding_animation')
local NormalArt=require('src.commute.normal_art')
local Residents=require('src.home_residents')
local Flow=require('src.weekend_flow')
local M=require('src.commute.vendor.mathx')
local Bays=require('src.commute.parking_bays')
local Service=require('src.commute.bike_service')
local TruckService=require('src.commute.truck_service')
local Trip={VERSION=1}
local function destinations(world) return world and world.roads and world.roads.destinations or Roads.destinations end
local function door(world,id)
    local sites=world and world.sites or require('src.commute.sites')
    return sites.byId[id].door
end
local function participantId(id) return id=='owner' or Residents.validId(id) end
local function vehicleForModel(t,model)
    return model=='kei' and t.keiTruck or t.truck
end
function Trip.truckFor(rider,t)
    if rider and rider.vehicle=='truck' and Truck.valid(rider.truck) then return rider.truck end
    return t and vehicleForModel(t,t.deliveryVehicleModel)
end
function Trip.trucks(t)
    local result={}
    if t and t.truck then result[#result+1]=t.truck end
    if t and t.keiTruck then result[#result+1]=t.keiTruck end
    return result
end
function Trip.ownsModel(state,model)
    return require('src.vehicle_dealer').owns(state,model)
end
local function hasTruckOwner(t,id)
    for _,truck in ipairs(Trip.trucks(t)) do if truck.owner==id then return true end end
    return false
end
function Trip.nearestTruck(t,rider,radius)
    if not rider or not rider.ped then return nil end
    local nearest,distance
    for _,truck in ipairs(Trip.trucks(t)) do
        local current=M.length(rider.ped.x-truck.x,rider.ped.z-truck.z)
        if current<=(radius or math.huge) and (not distance or current<distance) then
            nearest,distance=truck,current
        end
    end
    return nearest,distance
end
local function truckParkedInBay(world,id,truck)
    local site=world and world.sites and world.sites.byId[id]
    if site then
        local x,z=site:toLocal(truck.x,truck.z)
        if id=='warehouse' and site.localTruckParkingArea and site.design.truckParking then
            -- The box truck's primary loading position stays aligned to the marked bay.
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
    if not truck or (truck.speed or 0)>.05 then return false end
    local site=world and world.sites and world.sites.byId.warehouse
    local anchor=site and site.design.truckParking
    if not anchor then return false end
    local F=require('src.commute.truck_footprint')
    if math.cos((truck.heading or 0)-site.yaw)<math.cos(math.rad(12)) then return false end
    local length=F.dimensions(truck).halfLength
    local rearX,rearZ=truck.x-math.cos(truck.heading)*length,truck.z-math.sin(truck.heading)*length
    local dockX,dockZ=site:toWorld(anchor.x,anchor.z,0)
    dockX,dockZ=dockX-site.cos*F.halfLength,dockZ-site.sin*F.halfLength
    local dx,dz=rearX-dockX,rearZ-dockZ
    return math.abs(dx*site.cos+dz*site.sin)<=.8 and math.abs(-dx*site.sin+dz*site.cos)<=.65
end
function Trip.truckParking(world,companyTruck,model,boxTruck)
    local site=world and world.sites and world.sites.byId.warehouse
    if not site then return nil end
    local heading=site.design.truckParking and site.yaw or math.atan2(site.front.z,site.front.x)
    model=model or 'box'
    local anchor=site.truckHomeParking and site.truckHomeParking[model]
    if not anchor then return nil end
    heading=anchor.heading or heading
    local candidates={}
    for _,offset in ipairs({{0,0},{-.35,0},{.35,0},{0,-.35},{0,.35}}) do
        candidates[#candidates+1]={anchor.x+offset[1],anchor.z+offset[2]}
    end
    for _,point in ipairs(candidates) do
        local x,z=point[1],point[2]
        local h=world:supportHeight(x,z)
        local subject={model=model}
        local blocked=Truck.blocked(world,x,z,heading,subject)
        if not blocked and model=='kei' and boxTruck then
            blocked=require('src.commute.truck_footprint').overlapsTruck(x,z,heading,
                boxTruck.x,boxTruck.z,boxTruck.heading,model,boxTruck.model)
        end
        if not blocked then
            local truck=Truck.new(x,z,heading,model=='box' and 'picture_shop' or 'plain',model)
            TruckService.apply(truck)
            truck.h=h;truck.homeX=x;truck.homeZ=z
            if model=='box' then require('src.company_delivery_driver').apply(companyTruck,truck) end
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
        local layout=site.employeeParking
        local px,pz
        if layout and layout.walkSide then
            px,pz=x+site.cos*layout.walkSide*1.45,z+site.sin*layout.walkSide*1.45
        else px,pz=x-front.x*1.45,z-front.z*1.45 end
        if Rider.clear(world,x,z,Bike.RADIUS) and Rider.clear(world,px,pz,Rider.RADIUS)
            and math.abs(world:supportHeight(x,z)-world:supportHeight(px,pz))<.45 then
            return {x=x,z=z,h=pad.h,heading=Bays.heading(site),pedX=px,pedZ=pz}
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
        -- Generated towns extend to the mainland bridge at the map edge.
        and p.x>=0 and p.x<=512 and p.z>=0 and p.z<=512
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
        or t.aiMotorcycles~=nil and not AIMotorcycleTraffic.valid(t.aiMotorcycles)
        or t.mapId~=nil and (type(t.mapId)~='string' or #t.mapId>80
            or home and home.town and t.mapId~=home.town.id) then return false end
    for _,truck in ipairs({t.truck or false,t.keiTruck or false}) do
        if truck and (not Truck.valid(truck)
            or truck.driver~=nil and not participantId(truck.driver)
            or truck.owner~=nil and not participantId(truck.owner)) then return false end
    end
    if t.deliveryVehicleModel~=nil and t.deliveryVehicleModel~='box' and t.deliveryVehicleModel~='kei' then return false end
    local count,slots,truckDrivers=0,{},0
    for id,p in pairs(t.participants) do
        count=count+1
        if count>(independent and 65 or 4) or id~='owner' and not Residents.validId(id) or type(p)~='table'
            or not integer(p.slot,1,4) or not independent and slots[p.slot] or type(p.arrived)~='boolean'
            or independent and ((p.slot==1)~=(id=='owner') or not Roads.destinations[p.origin]
                or not Roads.destinations[p.destination]
                or p.interior~=nil and p.interior~='grocery' and p.interior~='barn')
            or p.interior~=nil and (not independent or type(p.interiorPose)~='table'
                or not M.finite(p.interiorPose.x) or not M.finite(p.interiorPose.y)
                or not M.finite(p.interiorPose.intentX) or math.abs(p.interiorPose.intentX)>1
                or not M.finite(p.interiorPose.intentY) or math.abs(p.interiorPose.intentY)>1
                or not M.finite(p.interiorPose.animationDistance) or p.interiorPose.animationDistance<0
                or p.interiorPose.animationDistance>1e12 or type(p.interiorPose.moving)~='boolean'
                or p.interiorPose.cartPushing~=nil and type(p.interiorPose.cartPushing)~='boolean'
                or not (p.interior=='barn' and require('src.commute.barn_interior').walkable(p.interiorPose.x,p.interiorPose.y)
                    or p.interior=='grocery' and require('src.commute.grocery_interior').walkable(p.interiorPose.x,p.interiorPose.y)))
            or p.interior==nil and p.interiorPose~=nil
            or type(p.rider)~='table' or not Gear.valid(p.rider.gear)
            or p.interior~=nil and (p.rider.gear.mounted or p.rider.vehicle~=nil)
            or not position(p.rider.ped) or not position(p.rider.bike) or not Bike.valid(p.rider.bike)
            or p.rider.vehicle~=nil and (p.rider.vehicle~='truck' or not Truck.valid(p.rider.truck)
                or not vehicleForModel(t,p.rider.truck.model or 'box')
                or p.rider.gear.mounted)
            or p.rider.transport~=nil and (p.rider.transport~='truck' or not hasTruckOwner(t,id))
            or not NormalArt.valid(p.appearance) then return false end
        if p.rider.vehicle=='truck' then
            truckDrivers=truckDrivers+1
            local truck=vehicleForModel(t,p.rider.truck.model or 'box')
            if truck.driver~=id or truck.owner~=id then return false end
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
    if truckDrivers>2 then return false end
    for _,truck in ipairs({t.truck or false,t.keiTruck or false}) do
        if truck and (truck.driver~=nil and (not t.participants[truck.driver]
                or t.participants[truck.driver].rider.vehicle~='truck'
                or (t.participants[truck.driver].rider.truck.model or 'box')~=(truck.model or 'box'))
            or truck.owner~=nil and not t.participants[truck.owner]
                and not (independent and t.deliveryRun and truck.owner==t.deliveryDriver
                    and truck==vehicleForModel(t,t.deliveryVehicleModel or 'box'))) then return false end
    end
    if independent and t.deliveryDriver and (home and not home.residents[t.deliveryDriver]
        or not vehicleForModel(t,t.deliveryVehicleModel or 'box')
        or vehicleForModel(t,t.deliveryVehicleModel or 'box').owner~=t.deliveryDriver) then return false end
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
    local t={version=Trip.VERSION,mapVersion=Roads.VERSION,mapId=world and world.townId,
        token=token,purpose=outing and 'outing' or 'weekend',origin=origin,destination=destination,
        participants={},aiMotorcycles={}}
    local companyTruck=require('src.company_delivery_driver').ensure(state)
    if Trip.ownsModel(state,'box') then
        t.truck=Trip.truckParking(world,companyTruck)
        if not t.truck then return false,'No safe loading area is available for the delivery truck.' end
        TruckService.applyFleet(t.truck,state.home.truckFleet)
    end
    if Trip.ownsModel(state,'kei') then
        t.keiTruck=Trip.truckParking(world,companyTruck,'kei',t.truck)
        if not t.keiTruck then return false,'No safe parking space is available for the kei delivery truck.' end
        t.keiTruck.fuel=t.truck and t.truck.fuel or companyTruck.fuelLiters
        TruckService.applyFleet(t.keiTruck,state.home.truckFleet)
    end
    if t.truck and t.keiTruck then t.keiTruck.fuel=t.truck.fuel end
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
        deliveryRun=t.deliveryRun and dataCopy(t.deliveryRun) or nil,
        deliveryVehicleModel=t.deliveryVehicleModel,
        aiMotorcycles=AIMotorcycleTraffic.snapshot(t.aiMotorcycles),
        keiTruck=t.keiTruck and Truck.snapshot(t.keiTruck) or nil}
    if result.truck then
        result.truck.owner=t.truck and t.truck.owner or nil
        result.truck.driver=t.truck and t.truck.driver or nil
    end
    if result.keiTruck then
        result.keiTruck.owner=t.keiTruck and t.keiTruck.owner or nil
        result.keiTruck.driver=t.keiTruck and t.keiTruck.driver or nil
    end
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
function Trip.restore(t,world,companyTruck,truckFleet,ownership)
    if not t then return nil end
    if not Trip.valid(t) then return nil,'Invalid saved commute.' end
    if t.mapId and world.townId and t.mapId~=world.townId then return nil,'The saved trip belongs to another town.' end
    local result=Trip.snapshot(t)
    if t.mapVersion~=Roads.VERSION then result.aiMotorcycles={} end
    ownership=ownership or {}
    local ownsBox=ownership.boxTruckOwned~=false
    local ownsKei=ownership.keiTruckOwned~=false
    if not ownsBox and result.truck then return nil,'The saved commute uses a box truck the shop does not own.' end
    if not ownsKei and result.keiTruck then return nil,'The saved commute uses a kei truck the shop does not own.' end
    local replaceTruck=ownsBox and (not result.truck or t.mapVersion~=Roads.VERSION)
    local replaceKei=ownsKei and (not result.keiTruck or t.mapVersion~=Roads.VERSION)
    if not ownsBox then result.truck=nil
    elseif replaceTruck then result.truck=Trip.truckParking(world,companyTruck) end
    if not ownsKei then result.keiTruck=nil
    elseif replaceKei then
        result.keiTruck=Trip.truckParking(world,companyTruck,'kei',result.truck)
        if result.keiTruck and result.truck then result.keiTruck.fuel=result.truck.fuel end
    end
    if ownsBox and not result.truck then return nil,'No safe loading area exists for the delivery truck.' end
    if ownsKei and not result.keiTruck then return nil,'No safe parking space exists for the kei delivery truck.' end
    local site=world.sites and world.sites.byId.warehouse
    for _,vehicle in ipairs(Trip.trucks(result)) do
        local anchor=site and site.truckHomeParking[vehicle.model or 'box']
        if anchor then
            local x,z=site:toLocal(vehicle.x,vehicle.z)
            local oldZ=vehicle.model=='kei' and 14.9 or 7.1
            if not vehicle.owner and not vehicle.driver and vehicle.speed<.05
                and math.abs(x-8.15)<.6 and math.abs(z-oldZ)<.6
                and not Truck.blocked(world,anchor.x,anchor.z,anchor.heading,vehicle) then
                -- Only relocate an idle truck in a retired home stall. Preserve
                -- player parking elsewhere and all vehicle condition/fuel data.
                vehicle.x,vehicle.z,vehicle.h,vehicle.heading=anchor.x,anchor.z,anchor.h,anchor.heading
                vehicle.reverse=false;vehicle.steering=0;vehicle.slipAngle=0
            end
            vehicle.homeX,vehicle.homeZ=anchor.x,anchor.z
        end
    end
    local function savedRecord(vehicle)
        if vehicle and TruckService.validRecord({damage=vehicle.damage or 0,
            repairRevision=vehicle.repairRevision or 0,service=vehicle.service}) then
            return TruckService.record(vehicle)
        end
    end
    if result.truck then
        TruckService.apply(result.truck,savedRecord(t.truck) or truckFleet and truckFleet.box)
    end
    if result.keiTruck then
        TruckService.apply(result.keiTruck,savedRecord(t.keiTruck) or truckFleet and truckFleet.kei)
    end
    if t.mapVersion~=Roads.VERSION and result.deliveryRun and result.deliveryRun.status=='offmap' then
        -- Re-enter the gate cinematic after a road-map migration instead of
        -- restoring an off-map driver with no usable vehicle controls.
        result.deliveryRun.status='driving'
        result.deliveryRun.cutsceneStartedAtEpoch=nil;result.deliveryRun.cutsceneEndsAtEpoch=nil
    end
    if t.mapVersion~=Roads.VERSION then
        if result.truck then result.truck.owner=nil;result.truck.driver=nil end
        if result.keiTruck then result.keiTruck.owner=nil;result.keiTruck.driver=nil end
        if result.independent and result.deliveryRun and result.deliveryDriver then
            local deliveryVehicle=vehicleForModel(result,result.deliveryVehicleModel or 'box')
            if not deliveryVehicle then return nil,'The saved delivery vehicle is no longer owned.' end
            deliveryVehicle.owner=result.deliveryDriver
        end
    end
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
        if rider.vehicle=='truck' then rider.truck=vehicleForModel(result,rider.truck.model or 'box') end
        p.presentation=nil
        if t.mapVersion~=Roads.VERSION then p.arrived=false end
    end
    if companyTruck and (result.truck or result.keiTruck) then
        local activeTruck=vehicleForModel(result,t.deliveryVehicleModel or 'box')
        if t.mapVersion==Roads.VERSION and activeTruck and activeTruck.fuel~=nil then
            companyTruck.fuelLiters=activeTruck.fuel
        elseif result.truck then
            require('src.company_delivery_driver').apply(companyTruck,result.truck)
        end
        if result.truck then result.truck.fuel=companyTruck.fuelLiters end
        if result.keiTruck then result.keiTruck.fuel=companyTruck.fuelLiters end
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
    local baseTrip=t
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
        local truck=Trip.truckFor(rider,t)
        if not truck or truck.speed>.05 then return false,'Stop the delivery truck before loading pallets.' end
        if not Trip.truckAtLoadingBay(world,truck) then
            return false,'Park the truck inside the marked warehouse loading bay before loading pallets.'
        end
        if M.length(rider.ped.x-truck.x,rider.ped.z-truck.z)>5.5 then
            return false,'Walk over to the truck in the loading bay to load the pallets.'
        end
        local loaded,total,reason=require('src.commute.delivery_run').loadingProgress(state,run)
        return false,reason or ('%d/%d pallets loaded. Use the warehouse loading manifest or let employees load the truck.')
            :format(loaded,total)
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
        local truck=Trip.truckFor(rider,t)
        if not truck or truck.speed>.05
            or M.length(truck.x-doorPoint.x,truck.z-doorPoint.z)>22 then
            return false,'Park the delivery truck near the customer first.'
        end
        local okay,message=require('src.commute.delivery_run').completeStop(state,stop)
        if not okay then return false,message end
        run.stopIndex=run.stopIndex+1
        local notice='Delivered '..stop.palletCount..' pallet'..(stop.palletCount==1 and '' or 's')..' to '..stop.label..'. '
            ..require('src.commute.delivery_run').nextMessage(run)
        if run.stopIndex>#run.stops then require('src.commute.delivery_run').releaseTrip(state,baseTrip) end
        state.home.revision=state.home.revision+1
        return true,notice
    end
    if action~='arrive' then
        if action=='truck' then
            local rider=t.participants[Residents.key(player)].rider
            if require('src.company_delivery_driver').busy(state) then
                return false,'The scheduled driver is using the delivery truck right now.'
            end
            if rider.vehicle=='truck' then
                local truck=rider.truck
                if not Truck.valid(truck) then return false,'The delivery truck is unavailable.' end
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
            local available,nearestDistance
            for _,candidate in ipairs(Trip.trucks(t)) do
                if (not candidate.owner or candidate.owner==Residents.key(player)) and not candidate.driver then
                    local distance=M.length(rider.ped.x-candidate.x,rider.ped.z-candidate.z)
                    if not nearestDistance or distance<nearestDistance then available,nearestDistance=candidate,distance end
                end
            end
            local truck=available
            if not truck then return false,'No delivery truck is available.' end
            if not t.independent and t.origin~='warehouse' then return false,'The delivery truck is available from the warehouse loading area.' end
            if rider.gear.mounted or rider.gear.transition or rider.ped.crash then return false,'Get off the motorcycle and finish the current action first.' end
            if truck.owner and truck.owner~=Residents.key(player) then return false,'The delivery truck is assigned to another rider.' end
            if truck.driver then return false,'Another rider is driving the delivery truck.' end
            if nearestDistance>5.5 then return false,'Walk over to the delivery truck first.' end
            truck.fuel=require('src.company_delivery_driver').ensure(state).fuelLiters
            if run then
                local loaded=require('src.commute.delivery_run').loadingProgress(state,run)
                if (run.status~='loading' or (loaded or 0)>0)
                    and (truck.model or 'box')~=(baseTrip.deliveryVehicleModel or 'box') then
                    return false,'The delivery pallets are loaded on the other truck.'
                end
                for _,other in ipairs(Trip.trucks(baseTrip)) do
                    if other~=truck and other.owner==Residents.key(player) and not other.driver then other.owner=nil end
                end
                baseTrip.deliveryVehicleModel=truck.model or 'box'
                if baseTrip.deliveryRun then baseTrip.deliveryRun.vehicleModel=baseTrip.deliveryVehicleModel end
            end
            truck.owner=Residents.key(player);truck.driver=Residents.key(player)
            rider.vehicle='truck';rider.transport='truck';rider.truck=truck
            rider.ped.x,rider.ped.z,rider.ped.heading=truck.x,truck.z,truck.heading
            rider.ped.speed,rider.ped.vx,rider.ped.vz=0,0,0
            state.home.revision=state.home.revision+1
            return true,'Delivery truck ready. Use the riding controls to drive; stop and interact to get out.'
        end
        if part.rider.vehicle=='truck' then
            local truck=part.rider.truck
            local radioAction=({radioPrevious='previous',radioPlay='play',radioNext='next',radioMute='mute'})[action]
            if radioAction then
                if truck.driver~=Residents.key(player) then return false,'The truck controls are assigned to another rider.' end
                local okay=require('src.jukebox').control(radioAction)
                if okay then state.home.revision=state.home.revision+1 end
                return okay,okay and 'Truck radio updated.' or 'That radio control is unavailable.'
            end
            if action=='ignition' or action=='headlight' or action=='beam'
                or action=='signalLeft' or action=='signalRight' or action=='rescue' then
                if truck.driver~=Residents.key(player) then return false,'The truck controls are assigned to another rider.' end
                local okay,message=Truck.command(truck,action,world)
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
        if part.interior=='barn' then
            require('src.commute.barn_interior').movePose(part.interiorPose,dx,dz,dt,state)
        else
            require('src.commute.grocery_interior').movePose(part.interiorPose,dx,dz,dt,state)
        end
        return false
    end
    local run=(not t.independent or t.deliveryDriver==Residents.key(player)) and t.deliveryRun
    if run and run.status=='returning' and run.stopIndex>#run.stops then
        require('src.commute.delivery_run').releaseTrip(state,t)
        state.message='All deliveries complete. You are free to continue your day.'
        return true
    end
    if run and run.status=='offmap' then
        local key=Residents.key(player)
        local truck=Trip.truckFor(part.rider,t)
        local driver=truck and (key==truck.driver
            or truck.driver==nil and (tonumber(player.id) or 1)==1)
        if driver and os.time()>=(run.cutsceneEndsAtEpoch or math.huge) then
            local gate=world.mainlandExit
            local dx,dz=math.cos(gate.heading),math.sin(gate.heading)
            local heading=gate.heading+math.pi
            local returnX,returnZ
            for _,distance in ipairs({8,16,24,32}) do
                local x,z=gate.x-dx*distance+dz*1.8,gate.z-dz*distance-dx*1.8
                if not Truck.blocked(world,x,z,heading,truck) then returnX,returnZ=x,z;break end
            end
            if not returnX then state.message='Waiting for a clear lane on the return bridge.';return false end
            local firstCityStopIndex=run.stopIndex
            local delivered=0
            local receivingClosed=false
            while run.stops[run.stopIndex] and run.stops[run.stopIndex].kind=='city' do
                local stop=run.stops[run.stopIndex]
                local now=require('src.business_calendar').absoluteHours(state)
                if require('src.commute.delivery_run').nextStopOpen(state,stop,now)>now+1e-7 then
                    receivingClosed=true;break
                end
                local okay,message=require('src.commute.delivery_run').completeStop(state,stop)
                if not okay then state.message=message;return false end
                delivered=delivered+stop.palletCount
                run.stopIndex=run.stopIndex+1
            end
            local lastCityStopIndex=math.max(firstCityStopIndex,run.stopIndex-1)
            local cityRouteMeters=require('src.commute.delivery_run').cityRouteMiles(
                run,firstCityStopIndex,lastCityStopIndex)*1609.344
            Truck.accountRouteDistance(truck,cityRouteMeters)
            TruckService.syncFleet(state.home,Trip.trucks(t))
            local companyTruck=require('src.company_delivery_driver').ensure(state)
            require('src.company_delivery_driver').syncFromVehicle(companyTruck,truck)
            for _,parked in ipairs(Trip.trucks(t)) do parked.fuel=truck.fuel end
            run.status='driving'
            run.cutsceneStartedAtEpoch=nil;run.cutsceneEndsAtEpoch=nil
            if not truck.driver then
                truck.owner,truck.driver=key,key
                part.rider.vehicle='truck';part.rider.transport='truck';part.rider.truck=truck
            end
            truck.x,truck.z=returnX,returnZ
            truck.heading=heading
            truck.speed=0;truck.reverse=false;truck.steering=0;truck.slipAngle=0
            truck.collisionContact=false;truck.collisionStun=0
            truck.h=world:supportHeight(truck.x,truck.z)
            part.rider.ped.x,part.rider.ped.z,part.rider.ped.heading=truck.x,truck.z,truck.heading
            state.message=('Millhaven delivery complete: %d pallets delivered. '):format(delivered)
                ..require('src.commute.delivery_run').nextMessage(run)
            if receivingClosed then
                state.message='Millhaven receiving closed during the trip. Your remaining pallets are still on the truck; return during weekday business hours.'
            end
            if run.stopIndex>#run.stops then require('src.commute.delivery_run').releaseTrip(state,t) end
            state.home.revision=state.home.revision+1
            return true
        end
        return false
    end
    local changed
    if part.rider.vehicle=='truck' then
        local truck=Trip.truckFor(part.rider,t)
        if not truck or truck.driver~=Residents.key(player) then return false end
        if run and run.status=='loading' then
            local loaded=require('src.commute.delivery_run').loadingProgress(state,run)
            if (loaded or 0)>0 and Trip.truckAtLoadingBay(world,truck) then input={drive=0,steer=0,brake=1} end
        end
        local moved,conditionChanged=Truck.update(truck,input,dt,world)
        changed=moved>0 or conditionChanged
        if TruckService.syncFleet(state.home,Trip.trucks(t)) then changed=true end
        if require('src.company_delivery_driver').syncFromVehicle(
            require('src.company_delivery_driver').ensure(state),truck) then
            changed=true
            for _,parked in ipairs(Trip.trucks(t)) do parked.fuel=truck.fuel end
        end
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
                    local now=require('src.business_calendar').absoluteHours(state)
                    local duration=5*24/require('src.business_calendar').secondsPerDay(state)
                    local opens=require('src.business_hours').nextService(now,duration)
                    if opens>now+1e-7 then
                        truck.x,truck.z=gate.x-dx*16,gate.z-dz*16
                        truck.speed=0;truck.h=world:supportHeight(truck.x,truck.z)
                        part.rider.ped.x,part.rider.ped.z=truck.x,truck.z
                        state.message='Millhaven receiving is closed or closing. Return '..require('src.business_calendar').dateTimeTextAtHours(opens)..'.'
                        state.home.revision=state.home.revision+1
                        return true
                    end
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
    TruckService.syncFleet(state.home,Trip.trucks(t))
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
        if part.rider.vehicle=='truck' then part.rider.truck=vehicleForModel(t,part.rider.truck.model or 'box') end
        state.home.revision=state.home.revision+1
        return true,part
    end
    for _,other in pairs(t.participants) do count=count+1;occupied[other.slot]=true end
    local function retain(otherId,other)
        local person=state.home.residents[otherId]
        if person then local gear=Gear.snapshot(other.rider.gear);gear.mounted=false;gear.engine=false;person.ridingGear=gear end
        for _,truck in ipairs(Trip.trucks(t)) do
            if truck.owner==otherId then truck.owner=nil;truck.driver=nil end
        end
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
        if part.rider.vehicle=='truck' then part.rider.truck=vehicleForModel(t,part.rider.truck.model or 'box') end
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
    TruckService.syncFleet(state.home,Trip.trucks(t))
    if t.purpose=='outing' then Flow.outingArrival(state,t.origin~='warehouse') end
    state.home.commute=nil;state.home.revision=state.home.revision+1
    return true,{destination=t.origin,participants=t.participants,message='Back inside. Your riding gear stays with you.'}
end
return Trip
