-- Company-owned delivery truck fuel and scheduled-driver dispatch.
-- Route travel is time-compressed to the game's calendar; job loading and
-- delivery completion still use the same authoritative service as player runs.
local Run=require('src.commute.delivery_run')
local Roads=require('src.commute.roads')
local Contracts=require('src.employment_contracts')
local Calendar=require('src.business_calendar')
local Payroll=require('src.payroll')
local CompanyTruck={TANK_LITERS=60,FUEL_PRICE_CENTS_PER_LITER=160,
    FUEL_PER_METER=.0003,LOW_FUEL_LITERS=12,VERSION=1}

local function finite(n) return type(n)=='number' and n==n and math.abs(n)<1e12 end
local function integer(n,lo,hi) return finite(n) and n%1==0 and n>=lo and n<=hi end
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end

function CompanyTruck.defaultState()
    return {version=CompanyTruck.VERSION,fuelLiters=CompanyTruck.TANK_LITERS,
        odometerMeters=0,lastPlayerDistance=0,revision=1,status='parked'}
end

function CompanyTruck.valid(value)
    if type(value)~='table' or value.version~=CompanyTruck.VERSION
        or not finite(value.fuelLiters) or value.fuelLiters<0 or value.fuelLiters>CompanyTruck.TANK_LITERS
        or not finite(value.odometerMeters) or value.odometerMeters<0
        or (value.lastPlayerDistance~=nil and (not finite(value.lastPlayerDistance) or value.lastPlayerDistance<0))
        or not integer(value.revision,1,1000000000)
        or (value.status~='parked' and value.status~='refueling'
            and value.status~='delivering' and value.status~='returning')
        or (value.deliveryRun~=nil and not Run.valid(value.deliveryRun))
        or (value.nextActionAtHours~=nil and (not finite(value.nextActionAtHours) or value.nextActionAtHours<0))
        or (value.driverEmployeeId~=nil and (type(value.driverEmployeeId)~='string'
            or #value.driverEmployeeId>64 or not value.driverEmployeeId:match('^[%w_.%-]+$')))
        or (value.currentLegFuelLiters~=nil and (not finite(value.currentLegFuelLiters)
            or value.currentLegFuelLiters<0 or value.currentLegFuelLiters>CompanyTruck.TANK_LITERS)) then return false end
    if (value.status=='delivering' or value.status=='returning')~=(value.deliveryRun~=nil) then return false end
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
    if math.abs(fuel-truck.fuelLiters)>.00001 then
        local distance=math.max(0,tonumber(vehicle.distance) or 0)
        local previous=truck.lastPlayerDistance or 0
        if distance>=previous then truck.odometerMeters=truck.odometerMeters+distance-previous end
        truck.lastPlayerDistance=distance
        truck.fuelLiters=fuel
        truck.revision=truck.revision+1
        return true
    end
    return false
end

function CompanyTruck.syncTripVehicle(state)
    local trip=state and state.home and state.home.commute
    local truck=state and state.employment and state.employment.companyTruck
    if trip and trip.truck and truck and not trip.truck.owner and not trip.truck.driver then
        trip.truck.fuel=truck.fuelLiters
    end
end

local function point(id)
    local p=Roads.destinations[id]
    if not p then return nil end
    return p.x or p[1],p.z or p[2]
end

local function leg(previous,stop)
    local previousKind=previous and previous.kind
    if previousKind=='city' or stop.kind=='city' then
        local meters=previousKind=='city' and stop.kind=='city' and 4000 or 10000
        return meters,.42
    end
    local ax,az=point(previous and previous.id or 'warehouse')
    local bx,bz=point(stop.id)
    local meters=ax and bx and math.sqrt((ax-bx)^2+(az-bz)^2)*1.4+350 or 2200
    return math.max(1200,meters),.10+meters/10000
end

local function routeMetrics(run)
    local meters,hours,previous=0,0,{kind='town',id='warehouse'}
    for _,stop in ipairs(run.stops) do
        local distance,duration=leg(previous,stop)
        meters=meters+distance;hours=hours+duration+.08
        previous=stop
    end
    local backDistance,backHours=leg(previous,{kind='town',id='warehouse'})
    meters=meters+backDistance;hours=hours+backHours
    return meters*CompanyTruck.FUEL_PER_METER,hours,backDistance*CompanyTruck.FUEL_PER_METER,backHours
end

local function availableDriver(state,now)
    for _,worker in ipairs(state.employment and state.employment.staff or {}) do
        local day=Contracts.shiftDay(worker.contract,now)
        if worker.status=='employed' and worker.contract.role=='driver' and not worker.terminationRequested
            and not worker.stopRequested and worker.visible and worker.clockedIn
            and worker.sentHomeShiftDay~=day and Contracts.onShift(worker.contract,now)
            and worker.phase~='break' and worker.phase~='break_walk'
            and Payroll.balance(worker,now,false)<=0 then return worker end
    end
end

local function playerHasTruck(state)
    local trip=state.home and state.home.commute
    if not trip then return false end
    return trip.deliveryRun~=nil or trip.truck and (trip.truck.owner~=nil or trip.truck.driver~=nil) or false
end

local function makeRun(state,worker,now)
    local available=Run.availableJobs(state,{roads={destinations=Roads.destinations}})
    if #available==0 then return nil end
    local ids,chosen,total={},{},0
    local _,shiftEnd=Contracts.shiftBounds(worker.contract,Contracts.shiftDay(worker.contract,now))
    for _,item in ipairs(available) do
        if total+item.palletCount<=Run.CAPACITY then
            local candidate={}
            for _,id in ipairs(ids) do candidate[#candidate+1]=id end
            candidate[#candidate+1]=item.id
            local run=Run.build(state,candidate,{roads={destinations=Roads.destinations}})
            if run then
                local fuel,hours=routeMetrics(run)
                if fuel+1<=CompanyTruck.TANK_LITERS and now+hours<=shiftEnd then
                    ids=candidate;chosen=run;total=total+item.palletCount
                end
            end
        end
    end
    if #ids==0 then return nil end
    return chosen,routeMetrics(chosen)
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

function CompanyTruck.update(state,now)
    if not state or not state.employment then return false end
    local truck=CompanyTruck.ensure(state)
    local changed=false
    if truck.status=='refueling' then
        if now<(truck.nextActionAtHours or math.huge) then return false end
        local id=truck.driverEmployeeId
        truck.status='parked';truck.nextActionAtHours=nil;truck.driverEmployeeId=nil
        truck.revision=truck.revision+1
        if id then setActivity(state,id,'Delivery truck ready',false) end
        return true
    end
    if truck.deliveryRun then
        if now<(truck.nextActionAtHours or math.huge) then return false end
        if truck.status=='returning' then
            local fuel=truck.currentLegFuelLiters or 0
            truck.fuelLiters=math.max(0,truck.fuelLiters-fuel)
            truck.odometerMeters=truck.odometerMeters+fuel/CompanyTruck.FUEL_PER_METER
            returnDriver(state,truck,'Returned to the warehouse after deliveries')
            state.message='The scheduled driver returned with the empty delivery truck.'
            return true
        end
        local run=truck.deliveryRun
        local stop=run.stops[run.stopIndex]
        if not stop then
            local returnDistance,returnHours=leg(run.stops[#run.stops],{kind='town',id='warehouse'})
            truck.currentLegFuelLiters=returnDistance*CompanyTruck.FUEL_PER_METER
            truck.status='returning';run.status='returning'
            truck.nextActionAtHours=now+returnHours
            truck.revision=truck.revision+1
            return true
        end
        local completed,reason=Run.completeStop(state,stop)
        if not completed then
            state.message='The scheduled driver could not complete a delivery: '..tostring(reason)
            return false
        end
        local fuel=truck.currentLegFuelLiters or 0
        truck.fuelLiters=math.max(0,truck.fuelLiters-fuel)
        truck.odometerMeters=truck.odometerMeters+fuel/CompanyTruck.FUEL_PER_METER
        run.stopIndex=run.stopIndex+1
        if run.stopIndex>#run.stops then
            local distance,duration=leg(stop,{kind='town',id='warehouse'})
            truck.currentLegFuelLiters=distance*CompanyTruck.FUEL_PER_METER
            truck.status='returning';run.status='returning'
            truck.nextActionAtHours=now+duration
        else
            local nextStop=run.stops[run.stopIndex]
            local distance,duration=leg(stop,nextStop)
            truck.currentLegFuelLiters=distance*CompanyTruck.FUEL_PER_METER
            truck.nextActionAtHours=now+duration+.08
        end
        truck.revision=truck.revision+1
        return true
    end
    if playerHasTruck(state) then return false end
    local worker=availableDriver(state,now)
    if not worker then return false end
    if truck.fuelLiters<=CompanyTruck.LOW_FUEL_LITERS then
        local okay,didRefuel=refuel(state,truck,worker,0,now)
        if didRefuel then return true end
        if not okay then return false end
    end
    local run,fuel,hours,returnFuel,returnHours=makeRun(state,worker,now)
    if not run then
        if worker.activity~='Awaiting delivery orders' then worker.activity='Awaiting delivery orders';return true end
        return false
    end
    if truck.fuelLiters<=CompanyTruck.LOW_FUEL_LITERS or truck.fuelLiters+1e-7<fuel+1 then
        local okay,didRefuel=refuel(state,truck,worker,fuel,now)
        if didRefuel then return true end
        if not okay then return false end
    end
    local loaded,message=Run.load(state,run)
    if not loaded then state.message=message;return false end
    run.status='driving';run.stopIndex=1
    local firstStop=run.stops[1]
    local firstDistance,firstHours=leg({kind='town',id='warehouse'},firstStop)
    truck.deliveryRun=run;truck.status='delivering';truck.driverEmployeeId=worker.id
    truck.currentLegFuelLiters=firstDistance*CompanyTruck.FUEL_PER_METER
    truck.nextActionAtHours=now+firstHours+.08
    truck.revision=truck.revision+1
    setActivity(state,worker.id,'Driving the delivery route',true)
    state.message=worker.name..' left to deliver '..run.palletCount..' pallet'..(run.palletCount==1 and '' or 's')..'.'
    return true
end

return CompanyTruck
