-- Company-owned delivery truck fuel and scheduled-driver dispatch.
-- Route travel is time-compressed to the game's calendar; job loading and
-- delivery completion still use the same authoritative service as player runs.
local Run=require('src.commute.delivery_run')
local Roads=require('src.commute.roads')
local DeliveryTruck=require('src.commute.delivery_truck')
local TruckService=require('src.commute.truck_service')
local Contracts=require('src.employment_contracts')
local Calendar=require('src.business_calendar')
local Payroll=require('src.payroll')
local ScheduledDriving=require('src.commute.scheduled_driving')
local CompanyTruck={TANK_LITERS=DeliveryTruck.TANK_LITERS,FUEL_PRICE_CENTS_PER_LITER=160,
    FUEL_PER_METER=DeliveryTruck.FUEL_PER_METER,LOW_FUEL_LITERS=12,VERSION=1}
local BASELINE_DRIVER_SKILL=55
local routeLookupCache=setmetatable({},{__mode='k'})
local exteriorRoutes=setmetatable({},{__mode='k'})
local leg

local function finite(n) return type(n)=='number' and n==n and math.abs(n)<1e12 end
local function integer(n,lo,hi) return finite(n) and n%1==0 and n>=lo and n<=hi end
local function ownsModel(state,model) return require('src.vehicle_dealer').owns(state,model) end
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end

function CompanyTruck.defaultState()
    return {version=CompanyTruck.VERSION,fuelLiters=CompanyTruck.TANK_LITERS,
        odometerMeters=0,lastPlayerDistance=0,revision=1,status='parked',vehicleModel='box'}
end

function CompanyTruck.valid(value)
    if type(value)~='table' or value.version~=CompanyTruck.VERSION
        or not finite(value.fuelLiters) or value.fuelLiters<0 or value.fuelLiters>CompanyTruck.TANK_LITERS
        or not finite(value.odometerMeters) or value.odometerMeters<0
        or (value.lastPlayerDistance~=nil and (not finite(value.lastPlayerDistance) or value.lastPlayerDistance<0))
        or not integer(value.revision,1,1000000000)
        or value.vehicleModel~=nil and value.vehicleModel~='box' and value.vehicleModel~='kei'
        or (value.status~='parked' and value.status~='refueling'
            and value.status~='delivering' and value.status~='returning')
        or (value.deliveryRun~=nil and not Run.valid(value.deliveryRun))
        or (value.nextActionAtHours~=nil and (not finite(value.nextActionAtHours) or value.nextActionAtHours<0))
        or (value.driverEmployeeId~=nil and (type(value.driverEmployeeId)~='string'
            or #value.driverEmployeeId>64 or not value.driverEmployeeId:match('^[%w_.%-]+$')))
        or (value.preferredDriverEmployeeId~=nil and (type(value.preferredDriverEmployeeId)~='string'
            or #value.preferredDriverEmployeeId>64 or not value.preferredDriverEmployeeId:match('^[%w_.%-]+$')))
        or (value.pendingDriverEmployeeId~=nil and (type(value.pendingDriverEmployeeId)~='string'
            or #value.pendingDriverEmployeeId>64 or not value.pendingDriverEmployeeId:match('^[%w_.%-]+$')))
        or (value.departureStage~=nil and value.departureStage~='warehouse_exit'
            and value.departureStage~='outside_walk' and value.departureStage~='boarding'
            and value.departureStage~='truck_departure')
        or (value.departureStartedAtEpoch~=nil and (not finite(value.departureStartedAtEpoch)
            or value.departureStartedAtEpoch<0))
        or (value.departureHomeX~=nil and (not finite(value.departureHomeX) or value.departureHomeX<0 or value.departureHomeX>512))
        or (value.departureHomeZ~=nil and (not finite(value.departureHomeZ) or value.departureHomeZ<0 or value.departureHomeZ>512))
        or (value.departureHomeHeading~=nil and not finite(value.departureHomeHeading))
        or (value.currentLegFuelLiters~=nil and (not finite(value.currentLegFuelLiters)
            or value.currentLegFuelLiters<0 or value.currentLegFuelLiters>CompanyTruck.TANK_LITERS)) then return false end
    if (value.status=='delivering' or value.status=='returning')~=(value.deliveryRun~=nil) then return false end
    if value.departureStage~=nil and (value.status~='delivering' or not value.deliveryRun) then return false end
    if (value.departureHomeX==nil)~=(value.departureHomeZ==nil)
        or value.departureHomeX==nil and value.departureHomeHeading~=nil then return false end
    if (value.status=='refueling')~=(value.nextActionAtHours~=nil and value.deliveryRun==nil
        and value.driverEmployeeId~=nil) then return false end
    return true
end

function CompanyTruck.normalize(value)
    if value==nil then return CompanyTruck.defaultState() end
    if type(value)~='table' then return nil end
    local result=copy(value)
    if result.version~=CompanyTruck.VERSION or not CompanyTruck.valid(result) then return nil end
    return result
end

function CompanyTruck.ensure(state)
    if not state.employment then state.employment=require('src.employees').defaultState(Calendar.absoluteHours(state)) end
    local employment=state.employment
    if not employment.companyTruck then employment.companyTruck=CompanyTruck.defaultState() end
    return employment.companyTruck
end

function CompanyTruck.busy(state)
    local truck=state and state.employment and state.employment.companyTruck
    return truck and (truck.status=='refueling' or truck.deliveryRun~=nil) or false
end

function CompanyTruck.apply(truck,vehicle)
    if vehicle then
        vehicle.fuel=truck and truck.fuelLiters or CompanyTruck.TANK_LITERS
        if vehicle.fuel<=0 then vehicle.engine=false end
        if truck then truck.lastPlayerDistance=0 end
    end
    return vehicle
end

function CompanyTruck.syncFromVehicle(truck,vehicle)
    if not truck or not vehicle or not finite(vehicle.fuel) then return false end
    local fuel=math.max(0,math.min(CompanyTruck.TANK_LITERS,vehicle.fuel))
    local distance=math.max(0,tonumber(vehicle.distance) or 0)
    local previous=truck.lastPlayerDistance or 0
    local distanceChanged=distance>=previous and distance-previous>.00001
    local fuelChanged=math.abs(fuel-truck.fuelLiters)>.00001
    if distanceChanged then truck.odometerMeters=truck.odometerMeters+distance-previous end
    truck.lastPlayerDistance=distance
    if fuelChanged or distanceChanged then
        truck.fuelLiters=fuel
        truck.revision=truck.revision+1
        return true
    end
    return false
end

function CompanyTruck.syncTripVehicle(state)
    local trip=state and state.home and state.home.commute
    local truck=state and state.employment and state.employment.companyTruck
    local busy=false
    for _,vehicle in ipairs(require('src.commute.trip').trucks(trip)) do
        if vehicle.owner or vehicle.driver then busy=true end
    end
    if trip and truck and not busy then
        for _,vehicle in ipairs(require('src.commute.trip').trucks(trip)) do
            vehicle.fuel=truck.fuelLiters
        end
    end
end

local function exteriorVehicle(state)
    local trip=state and state.home and state.home.commute
    local truck=state and state.employment and state.employment.companyTruck
    if not trip or not truck then return nil end
    local key=truck.vehicleModel=='kei' and 'keiTruck' or 'truck'
    return trip[key],trip
end

local function privateExitPath(world,vehicle)
    local site=world and world.sites and world.sites.byId and world.sites.byId.warehouse
    if not site or not vehicle then return nil end
    local cached=exteriorRoutes[vehicle]
    if cached and cached.world==world and cached.x==vehicle.x and cached.z==vehicle.z then
        return cached.route.points,site,cached.route
    end
    local layout=require('src.commute.sites').warehouseTruckLayout
    local x,z=site:toLocal(vehicle.x,vehicle.z)
    local laneZ=z
    local points={{x=x,z=z},{x=12.1,z=laneZ},{x=18.3,z=14.5}}
    local exit=layout.truckExitWaypoints or {}
    for index=5,#exit do points[#points+1]={x=exit[index].x,z=exit[index].z} end
    local result={}
    for _,point in ipairs(points) do
        local wx,wz,h=site:toWorld(point.x,point.z,0)
        result[#result+1]={x=wx,z=wz,h=h}
    end
    local route={points=result}
    exteriorRoutes[vehicle]={world=world,x=vehicle.x,z=vehicle.z,route=route}
    return result,site,route
end

function CompanyTruck.updateExterior(state,world,epoch,now)
    local truck=state and state.employment and state.employment.companyTruck
    if not truck or not truck.departureStage then return false end
    epoch=finite(epoch) and epoch or os.time()
    now=finite(now) and now or Calendar.absoluteHours(state)
    local vehicle,trip=exteriorVehicle(state)
    local stage=truck.departureStage
    local started=truck.departureStartedAtEpoch
    if stage=='outside_walk' then
        if not trip or not vehicle or started and epoch-started>=2.2 then
            truck.departureStage='boarding';truck.departureStartedAtEpoch=epoch
            if vehicle then vehicle.speed=0 end
            truck.revision=truck.revision+1
            return true
        end
        return false
    elseif stage=='boarding' then
        if started and epoch-started>=1.15 then
            truck.departureStage='truck_departure';truck.departureStartedAtEpoch=epoch
            if vehicle and truck.departureHomeX==nil then
                truck.departureHomeX,truck.departureHomeZ,truck.departureHomeHeading=
                    vehicle.x,vehicle.z,vehicle.heading
            end
            if vehicle then vehicle.speed=0;vehicle.engine=true end
            truck.revision=truck.revision+1
            return true
        end
        return false
    elseif stage~='truck_departure' then
        return false
    end
    if not started then truck.departureStartedAtEpoch=epoch;started=epoch end
    if vehicle and truck.departureHomeX==nil then
        truck.departureHomeX,truck.departureHomeZ,truck.departureHomeHeading=
            vehicle.x,vehicle.z,vehicle.heading
    end
    local points,site,route=privateExitPath(world,vehicle)
    local plan=route and ScheduledDriving.sample(route,0,world,vehicle)
    if epoch-started<(plan and plan.duration or 8) then return false end
    if vehicle and points then
        local last=points[#points]
        vehicle.x,vehicle.z,vehicle.heading=last.x,last.z,last.heading or vehicle.heading
        vehicle.h=world:supportHeight(vehicle.x,vehicle.z);vehicle.speed=0
    end
    truck.departureStage=nil;truck.departureStartedAtEpoch=nil
    local run=truck.deliveryRun
    if run then
        run.status='driving'
        local stop=run.stops[run.stopIndex]
        local firstDistance,firstHours=leg({kind='town',id='warehouse'},stop,
            state.home and state.home.town,run.driverSkill,run.vehicleModel)
        truck.currentLegFuelLiters=firstDistance*CompanyTruck.FUEL_PER_METER
        truck.nextActionAtHours=now+firstHours+.08
    end
    truck.revision=truck.revision+1
    return true
end

function CompanyTruck.actors(state,world,epoch)
    local truck=state and state.employment and state.employment.companyTruck
    local stage=truck and truck.departureStage
    local vehicle,trip=exteriorVehicle(state)
    if not stage or not world or not world.sites or not vehicle or not trip then return {} end
    local site=world.sites.byId.warehouse
    if not site then return {} end
    local epochNow=finite(epoch) and epoch or os.time()
    local started=truck.departureStartedAtEpoch or epochNow
    if stage=='truck_departure' then
        local actor=copy(vehicle)
        local _,_,route=privateExitPath(world,vehicle)
        local plan=route and ScheduledDriving.sample(route,0,world,vehicle)
        local pose=plan and ScheduledDriving.sample(route,(epochNow-started)/math.max(.01,plan.duration),world,vehicle)
        if pose then
            actor.x,actor.z,actor.heading=pose.x,pose.z,pose.heading
            actor.h=world:supportHeight(actor.x,actor.z);actor.speed=pose.speed
            actor.distance=(actor.distance or 0)+pose.distance
        end
        return {{id='company-delivery-truck',actor=actor,truck=true,
            deliveryTruck=true,phase='departing',label='Company delivery truck · leaving the warehouse'}}
    end
    local door=site.door
    local startX,startZ=door.x,door.z
    local endX,endZ=vehicle.x,vehicle.z
    local moving=stage=='outside_walk'
    if moving then
        local progress=math.max(0,math.min(1,(epochNow-started)/2.2))
        local fromX,fromZ=door.x,door.z
        local toX,toZ=vehicle.x,vehicle.z
        startX=fromX+(toX-fromX)*progress;startZ=fromZ+(toZ-fromZ)*progress
    elseif stage=='boarding' then
        startX,startZ=endX,endZ
    end
    local person=require('src.employees').worker(state,truck.driverEmployeeId)
    local actor={x=startX,z=startZ,h=world:supportHeight(startX,startZ),
        heading=math.atan2(endZ-startZ,endX-startX),speed=moving and 1.35 or 0,
        distance=moving and math.min(3.2,(epochNow-started)*1.35) or 0,
        moving=moving,speechCode=require('src.employee_speech').EMPLOYEE_GOING_ON_DELIVERY,
        visible=true}
    local result={{id='company-delivery-driver-'..tostring(truck.driverEmployeeId),actor=actor,
        npcCharacter=true,deliveryEmployee=true,characterId='mechanic-raccoon',
        rosterId=truck.driverEmployeeId,label=(person and person.name or 'Delivery driver')}}
    return result
end

local function point(id,town)
    local p=town and town.destinations and town.destinations[id] or Roads.destinations[id]
    if not p then return nil end
    return p.x or p[1],p.z or p[2]
end

local function clamp(value,minimum,maximum)
    return math.max(minimum,math.min(maximum,value))
end

function CompanyTruck.speedMultiplier(skill)
    skill=clamp(tonumber(skill) or BASELINE_DRIVER_SKILL,0,100)
    return .70+skill*.006
end

function CompanyTruck.vehicleSpeedMultiplier(model)
    return model=='kei' and 1.088 or 1
end

local function savedRoutes(town)
    local map=town and town.drivingMap
    if type(map)~='table' then return nil end
    local cached=routeLookupCache[map]
    if cached then return cached end
    cached={}
    for index,id in ipairs(map.destinations or {}) do cached[id]=index end
    local routes={}
    for _,route in ipairs(map.routes or {}) do
        local from,to=map.destinations[route.from],map.destinations[route.to]
        if from and to then
            local turns=type(route.turns)=='table' and #route.turns/2 or 0
            routes[from..'\0'..to]={length=route.length,turns=turns}
            if route.bidirectional then routes[to..'\0'..from]={length=route.length,turns=turns} end
        end
    end
    cached.routes=routes
    routeLookupCache[map]=cached
    return cached
end

leg=function(previous,stop,town,skill,model)
    local speed=CompanyTruck.speedMultiplier(skill)*CompanyTruck.vehicleSpeedMultiplier(model)
    local previousKind=previous and previous.kind
    if previousKind=='city' or stop.kind=='city' then
        local miles
        if stop.kind=='city' then
            miles=Run.cityStopMiles(stop)
            if previousKind~='city' then miles=miles+Run.CITY_HIGHWAY_MILES end
        else
            miles=Run.CITY_HIGHWAY_MILES
        end
        local meters=miles*1609.344
        -- City mileage tracks real fuel/maintenance distance, while calendar
        -- travel stays compressed so a 100+ mile route fits a normal shift.
        return meters,(.10+meters/10000*.18)/speed,0
    end
    local from,to=previous and previous.id or 'warehouse',stop.id
    local lookup=savedRoutes(town)
    local route=lookup and lookup.routes[from..'\0'..to]
    local meters,turns
    if route then
        meters,turns=route.length,route.turns
    elseif lookup and lookup[from] and lookup[to] then
        return nil,nil,'No precomputed GPS route from '..from..' to '..to
    else
        local ax,az=point(from,town)
        local bx,bz=point(to,town)
        meters=ax and bx and math.sqrt((ax-bx)^2+(az-bz)^2)*1.4+350 or 2200
        meters=math.max(1200,meters)
        turns=0
    end
    return meters,(.10+meters/10000+turns*.004)/speed,turns
end

local function routeMetrics(run,town,skill,dispatchAt)
    local meters,hours,standardHours,previous=0,0,0,{kind='town',id='warehouse'}
    for _,stop in ipairs(run.stops) do
        local distance,duration=leg(previous,stop,town,skill,run.vehicleModel)
        local _,standardDuration,reason=leg(previous,stop,town,BASELINE_DRIVER_SKILL,run.vehicleModel)
        if not distance or not standardDuration then return nil,nil,nil,nil,reason end
        meters=meters+distance;hours=hours+duration+.08
        standardHours=standardHours+standardDuration+.08
        if dispatchAt then stop.standardArrivalAtHours=dispatchAt+standardHours end
        previous=stop
    end
    local backDistance,backHours=leg(previous,{kind='town',id='warehouse'},town,skill,run.vehicleModel)
    if not backDistance or not backHours then return nil,nil,nil,nil,'No precomputed return route to warehouse' end
    meters=meters+backDistance;hours=hours+backHours
    return meters*CompanyTruck.FUEL_PER_METER,hours,backDistance*CompanyTruck.FUEL_PER_METER,backHours
end

local function workerById(state,id)
    if not id then return nil end
    for _,worker in ipairs(state.employment and state.employment.staff or {}) do
        if worker.id==id then return worker end
    end
end

local function driverEligible(worker,now)
    if not worker or worker.status~='employed' or worker.terminationRequested
        or not worker.visible or not worker.clockedIn then return false end
    local day=Contracts.shiftDay(worker.contract,now)
    return worker.sentHomeShiftDay~=day and Contracts.onShift(worker.contract,now)
        and worker.phase~='break' and worker.phase~='break_walk'
        and Payroll.balance(worker,now,false)<=0
end

local function availableDriver(state,now,truck)
    -- A queued driver keeps their reservation through the end of a shift or a
    -- refuel stop, so another employee cannot take the delivery out of order.
    local pending=workerById(state,truck and truck.pendingDriverEmployeeId)
    if pending and pending.status=='employed' and not pending.terminationRequested then
        return driverEligible(pending,now) and pending or nil
    end
    if truck and truck.pendingDriverEmployeeId then
        truck.pendingDriverEmployeeId=nil;truck.revision=truck.revision+1
    end

    local preferred=truck and truck.preferredDriverEmployeeId
    if preferred then
        local worker=workerById(state,preferred)
        return driverEligible(worker,now) and worker or nil
    end

    local best,bestSkill
    for _,worker in ipairs(state.employment and state.employment.staff or {}) do
        if driverEligible(worker,now) then
            local skill=tonumber(worker.drivingSkill) or BASELINE_DRIVER_SKILL
            if not best or skill>bestSkill then best,bestSkill=worker,skill end
        end
    end
    return best
end

local function playerHasTruck(state)
    local trip=state.home and state.home.commute
    if not trip then return false end
    return trip.deliveryRun~=nil or trip.truck and (trip.truck.owner~=nil or trip.truck.driver~=nil)
        or trip.keiTruck and (trip.keiTruck.owner~=nil or trip.keiTruck.driver~=nil) or false
end

local function makeRun(state,worker,now)
    local town=state.home and state.home.town
    local world={roads={destinations=town and town.destinations or Roads.destinations}}
    local available=Run.availableJobs(state,world,'employee',now)
    if #available==0 then return nil end
    local ids,chosen,total={},{},0
    local routeError
    local _,shiftEnd=Contracts.shiftBounds(worker.contract,Contracts.shiftDay(worker.contract,now))
    for _,item in ipairs(available) do
        if total+item.palletCount<=Run.CAPACITY then
            local candidate={}
            for _,id in ipairs(ids) do candidate[#candidate+1]=id end
            candidate[#candidate+1]=item.id
            local run=Run.build(state,candidate,world)
            if run then
                run.driverSkill=worker.drivingSkill or BASELINE_DRIVER_SKILL
                run.driverEmployeeId=worker.id
                run.vehicleModel=run.palletCount<=4 and ownsModel(state,'kei') and 'kei' or 'box'
                if ownsModel(state,run.vehicleModel) then
                    local fuel,hours,_,_,reason=routeMetrics(run,town,run.driverSkill,now)
                    if not fuel then routeError=reason end
                    local departureHours=30*24/Calendar.secondsPerDay(state)
                    local finishes=hours and now+hours+departureHours
                    local receivingOpen=finishes and require('src.business_hours').nextService(now,hours+departureHours)==now
                    for _,stop in ipairs(run.stops) do
                        if finishes and Run.nextStopOpen(state,stop,finishes)>finishes then receivingOpen=false end
                    end
                    if fuel and hours and receivingOpen and fuel+1<=CompanyTruck.TANK_LITERS and finishes<=shiftEnd then
                        ids=candidate;chosen=run;total=total+item.palletCount
                    end
                end
            end
        end
    end
    if #ids==0 then return nil,nil,nil,nil,nil,routeError end
    local fuel,hours,returnFuel,returnHours,reason=routeMetrics(chosen,town,chosen.driverSkill,now)
    if not fuel then return nil,nil,nil,nil,nil,reason end
    return chosen,fuel,hours,returnFuel,returnHours
end

local function hasReadyJobs(state,now)
    local town=state.home and state.home.town
    local world={roads={destinations=town and town.destinations or Roads.destinations}}
    return #Run.availableJobs(state,world,'employee',now)>0
end

local function setActivity(state,employeeId,activity,away)
    for _,worker in ipairs(state.employment and state.employment.staff or {}) do
        if worker.id==employeeId then
            worker.activity=activity
            if away then
                worker.awayForDelivery=true;worker.visible=false;worker.phase='hidden'
                worker.sceneId=nil;worker.moving=false;worker.clockedIn=true
            else
                worker.awayForDelivery=nil
                worker.visible=true;worker.phase='idle';worker.sceneId='warehouse';worker.clockedIn=true
                worker.moving=false
            end
            return worker
        end
    end
end

local function returnDriver(state,truck,message)
    local id=truck.driverEmployeeId
    truck.deliveryRun=nil;truck.nextActionAtHours=nil;truck.driverEmployeeId=nil
    truck.currentLegFuelLiters=nil;truck.status='parked'
    truck.revision=truck.revision+1
    if id then setActivity(state,id,message or 'Delivery route complete',false) end
end

local function deliveryPerformance(run,stop,now,driverEmployeeId)
    local skill=clamp(tonumber(run.driverSkill) or BASELINE_DRIVER_SKILL,0,100)
    local standard=tonumber(stop.standardArrivalAtHours) or now
    local lateHours=math.max(0,now-standard)
    local rating=clamp(math.floor(skill/25)+1,1,5)
    if lateHours>=.10 then rating=rating-1 end
    if lateHours>=.50 then rating=rating-1 end
    if standard-now>=.15 and skill>=75 then rating=rating+1 end
    return {version=1,driverEmployeeId=run.driverEmployeeId or driverEmployeeId or 'unknown-driver',driverSkill=skill,
        standardArrivalAtHours=standard,arrivedAtHours=now,lateHours=lateHours,
        serviceRating=clamp(rating,1,5)}
end

local function refuel(state,truck,worker,required,now)
    local low=truck.fuelLiters<=CompanyTruck.LOW_FUEL_LITERS
    local target=low and CompanyTruck.TANK_LITERS or math.min(CompanyTruck.TANK_LITERS,required+1)
    local fullCost=math.ceil(math.max(0,target-truck.fuelLiters)*CompanyTruck.FUEL_PRICE_CENTS_PER_LITER)
    local availableCents=math.max(0,math.floor((state.money or 0)*100+.000001))
    if fullCost>availableCents and low then
        target=math.min(target,required+1)
        fullCost=math.ceil(math.max(0,target-truck.fuelLiters)*CompanyTruck.FUEL_PRICE_CENTS_PER_LITER)
    end
    if fullCost<=0 then return true,false end
    if fullCost>availableCents then
        worker.activity='Delivery truck needs fuel; company funds are short'
        state.message='The scheduled driver cannot refuel the delivery truck: company funds are insufficient.'
        return false,false
    end
    local CalendarModule=require('src.business_calendar')
    local paid=CalendarModule.recordPaidExpenseCents(state,'Delivery truck fuel',fullCost,'truck-fuel')
    if not paid then return false,false end
    truck.fuelLiters=target;truck.revision=truck.revision+1
    truck.status='refueling';truck.driverEmployeeId=worker.id
    truck.nextActionAtHours=now+.12
    setActivity(state,worker.id,'Refueling the delivery truck',true)
    state.message=worker.name..' is refueling the delivery truck. Company expense: $'..string.format('%.2f',fullCost/100)..'.'
    return true,true
end

function CompanyTruck.reserveNextDriver(state,now)
    if not state or not state.employment then return false end
    if not ownsModel(state,'box') and not ownsModel(state,'kei') then return false end
    if not require('src.business_hours').isOpen(now) then return false end
    local truck=CompanyTruck.ensure(state)
    local revision=truck.revision
    if truck.status=='refueling' or truck.deliveryRun or playerHasTruck(state) then return false end
    if not hasReadyJobs(state,now) then
        if truck.pendingDriverEmployeeId then
            truck.pendingDriverEmployeeId=nil;truck.revision=truck.revision+1
        end
        return truck.revision~=revision
    end
    if truck.pendingDriverEmployeeId then
        local pending=workerById(state,truck.pendingDriverEmployeeId)
        if pending and pending.status=='employed' and not pending.terminationRequested then
            return truck.revision~=revision
        end
        truck.pendingDriverEmployeeId=nil;truck.revision=truck.revision+1
    end
    local worker=availableDriver(state,now,truck)
    if not worker then return truck.revision~=revision end
    local run=makeRun(state,worker,now)
    if not run then return truck.revision~=revision end
    if truck.pendingDriverEmployeeId~=worker.id then
        truck.pendingDriverEmployeeId=worker.id;truck.revision=truck.revision+1
    end
    return truck.revision~=revision
end

function CompanyTruck.update(state,now,activeRunOnly)
    if not state or not state.employment then return false end
    local truck=CompanyTruck.ensure(state)
    if not ownsModel(state,'box') and not ownsModel(state,'kei')
        and not truck.deliveryRun and not truck.departureStage then return false end
    local changed=false
    if truck.status=='refueling' then
        if now<(truck.nextActionAtHours or math.huge) then return false end
        local id=truck.driverEmployeeId
        truck.status='parked';truck.nextActionAtHours=nil;truck.driverEmployeeId=nil
        truck.revision=truck.revision+1
        if id then setActivity(state,id,'Delivery truck ready',false) end
        return true
    end
    if truck.departureStage then return false end
    if truck.deliveryRun then
        if now<(truck.nextActionAtHours or math.huge) then return false end
        if truck.status=='returning' then
            local fuel=truck.currentLegFuelLiters or 0
            local meters=fuel/CompanyTruck.FUEL_PER_METER
            truck.fuelLiters=math.max(0,truck.fuelLiters-fuel)
            truck.odometerMeters=truck.odometerMeters+meters
            TruckService.runFleet(state.home,truck.vehicleModel or 'box',meters,0)
            local vehicle=exteriorVehicle(state)
            if vehicle then
                local town=state.home and state.home.town
                local sites=require('src.commute.sites').create({
                    placements=town and town.placements,designs=town and town.designs})
                local site=sites.byId.warehouse
                local home=site and site.truckHomeParking[vehicle.model or 'box']
                if home then
                    vehicle.x,vehicle.z,vehicle.h=home.x,home.z,home.h
                    vehicle.homeX,vehicle.homeZ=home.x,home.z
                    vehicle.heading=home.heading
                end
                vehicle.speed=0;vehicle.reverse=false;vehicle.engine=true
            end
            returnDriver(state,truck,'Returned to the warehouse after deliveries')
            truck.departureHomeX,truck.departureHomeZ,truck.departureHomeHeading=nil,nil,nil
            state.message='The scheduled driver returned with the empty delivery truck.'
            return true
        end
        local run=truck.deliveryRun
        local stop=run.stops[run.stopIndex]
        if not stop then
            local returnDistance,returnHours=leg(run.stops[#run.stops],{kind='town',id='warehouse'},
                state.home and state.home.town,run.driverSkill,run.vehicleModel)
            truck.currentLegFuelLiters=returnDistance*CompanyTruck.FUEL_PER_METER
            truck.status='returning';run.status='returning'
            truck.nextActionAtHours=now+returnHours
            truck.revision=truck.revision+1
            return true
        end
        local performance=deliveryPerformance(run,stop,now,truck.driverEmployeeId)
        local nextOpening=Run.nextStopOpen(state,stop,now)
        if nextOpening>now+1e-7 then
            truck.nextActionAtHours=nextOpening;truck.revision=truck.revision+1
            setActivity(state,truck.driverEmployeeId,'Waiting for receiving to open',true)
            state.message='The delivery is waiting until the customer opens for receiving.'
            return true
        end
        local completed,reason=Run.completeStop(state,stop,performance)
        if not completed then
            state.message='The scheduled driver could not complete a delivery: '..tostring(reason)
            return false
        end
        local fuel=truck.currentLegFuelLiters or 0
        local meters=fuel/CompanyTruck.FUEL_PER_METER
        truck.fuelLiters=math.max(0,truck.fuelLiters-fuel)
        truck.odometerMeters=truck.odometerMeters+meters
        TruckService.runFleet(state.home,run.vehicleModel or truck.vehicleModel or 'box',meters,0)
        run.stopIndex=run.stopIndex+1
        if run.stopIndex>#run.stops then
            local distance,duration=leg(stop,{kind='town',id='warehouse'},
                state.home and state.home.town,run.driverSkill,run.vehicleModel)
            truck.currentLegFuelLiters=distance*CompanyTruck.FUEL_PER_METER
            truck.status='returning';run.status='returning'
            truck.nextActionAtHours=now+duration
        else
            local nextStop=run.stops[run.stopIndex]
            local distance,duration=leg(stop,nextStop,state.home and state.home.town,run.driverSkill,run.vehicleModel)
            truck.currentLegFuelLiters=distance*CompanyTruck.FUEL_PER_METER
            truck.nextActionAtHours=now+duration+.08
        end
        truck.revision=truck.revision+1
        return true
    end
    if activeRunOnly then return false end
    if not require('src.business_hours').isOpen(now) then return false end
    if not hasReadyJobs(state,now) then
        if truck.pendingDriverEmployeeId then
            truck.pendingDriverEmployeeId=nil;truck.revision=truck.revision+1
            return true
        end
        if playerHasTruck(state) then return false end
        local worker=availableDriver(state,now,truck)
        if worker and not worker.assignment and not worker.training
            and truck.fuelLiters<=CompanyTruck.LOW_FUEL_LITERS then
            local okay,didRefuel=refuel(state,truck,worker,0,now)
            if didRefuel then return true end
            if not okay then return false end
        end
        return false
    end
    if playerHasTruck(state) then return false end
    local worker=availableDriver(state,now,truck)
    if not worker then return false end
    if truck.pendingDriverEmployeeId==worker.id and (worker.assignment or worker.training) then return false end
    local run,fuel,hours,returnFuel,returnHours,routeError=makeRun(state,worker,now)
    if not run then
        if routeError then
            if not worker.assignment and not worker.training then worker.activity='Waiting for a usable GPS route' end
            state.message='The scheduled driver could not plan a delivery: '..tostring(routeError)..'.'
            if truck.pendingDriverEmployeeId==worker.id then
                truck.pendingDriverEmployeeId=nil;truck.revision=truck.revision+1
            end
            return true
        end
        return false
    end
    if worker.assignment or worker.training then
        if truck.pendingDriverEmployeeId~=worker.id then
            truck.pendingDriverEmployeeId=worker.id;truck.revision=truck.revision+1
            return true
        end
        return false
    end
    if truck.fuelLiters<=CompanyTruck.LOW_FUEL_LITERS or truck.fuelLiters+1e-7<fuel+1 then
        if truck.pendingDriverEmployeeId~=worker.id then
            truck.pendingDriverEmployeeId=worker.id;truck.revision=truck.revision+1
        end
        local okay,didRefuel=refuel(state,truck,worker,fuel,now)
        if didRefuel then return true end
        if not okay then
            if truck.pendingDriverEmployeeId==worker.id then
                truck.pendingDriverEmployeeId=nil;truck.revision=truck.revision+1
            end
            return true
        end
    end
    local loaded,message=Run.load(state,run)
    if not loaded then
        state.message=message
        if truck.pendingDriverEmployeeId==worker.id then
            truck.pendingDriverEmployeeId=nil;truck.revision=truck.revision+1
        end
        return true
    end
    run.status='loading';run.stopIndex=1
    local firstStop=run.stops[1]
    local firstDistance,firstHours=leg({kind='town',id='warehouse'},firstStop,
        state.home and state.home.town,run.driverSkill,run.vehicleModel)
    truck.vehicleModel=run.vehicleModel or 'box'
    truck.deliveryRun=run;truck.status='delivering';truck.driverEmployeeId=worker.id
    truck.pendingDriverEmployeeId=nil
    truck.currentLegFuelLiters=firstDistance*CompanyTruck.FUEL_PER_METER
    truck.nextActionAtHours=nil;truck.departureStage='warehouse_exit';truck.departureStartedAtEpoch=nil
    local vehicle=exteriorVehicle(state)
    if vehicle then
        truck.departureHomeX,truck.departureHomeZ,truck.departureHomeHeading=
            vehicle.x,vehicle.z,vehicle.heading
    else truck.departureHomeX,truck.departureHomeZ,truck.departureHomeHeading=nil,nil,nil end
    truck.revision=truck.revision+1
    worker.visible=true;worker.clockedIn=true;worker.awayForDelivery=nil
    worker.phase='walking';worker.sceneId='warehouse';worker.moving=false
    worker.activity='Going on a delivery'
    worker.greetingKind=require('src.employee_speech').EMPLOYEE_GOING_ON_DELIVERY
    worker.greetingUntilHours=now+require('src.employee_speech').GREETING_SECONDS*24
        /Calendar.secondsPerDay(state)
    state.message=worker.name..' is heading out to deliver '..run.palletCount..' pallet'..(run.palletCount==1 and '' or 's')..'.'
    return true
end

return CompanyTruck
