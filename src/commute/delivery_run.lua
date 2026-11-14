-- Manifest planning and completion for player-driven shop deliveries.
local Traffic=require('src.commute.delivery_traffic')
local Run={CAPACITY=10,VERSION=1,CITY_HIGHWAY_MILES=50,CITY_LOCAL_MILES_MIN=5,CITY_LOCAL_MILES_MAX=20}

local function copy(value)
    if type(value)~='table' then return value end
    local result={}
    for key,item in pairs(value) do result[key]=copy(item) end
    return result
end

local localClients={
    {'wrenchworks','mechanic'},{'majic blue','mechanic'},{'mechanic','mechanic'},
    {'town grocery','grocery'},{'grocery','grocery'},{'town diner','diner'},
    {'diner','diner'},{'coffee shop','coffee-shop'},{'general store','general-store'},
    {'post office','post-office'},
}

local function findJob(state,id)
    for _,job in ipairs(state.jobs and state.jobs.active or {}) do
        if job.id==id then return job end
    end
end

function Run.destination(job,world)
    if type(job.customerDestination)=='string' and world.roads.destinations[job.customerDestination]
        and job.customerDestination~='warehouse' and job.customerDestination~='mainland_exit' then
        local id=job.customerDestination
        return {kind='town',id=id,label=world.roads.destinations[id].label or id}
    end
    local company=tostring(job.company or ''):lower()
    for _,entry in ipairs(localClients) do
        if company:find(entry[1],1,true) then
            local point=world.roads.destinations[entry[2]]
            if point then return {kind='town',id=entry[2],label=point.label or entry[2]} end
        end
    end
    return {kind='city',id=tostring(job.id),
        label=Traffic.cityLocationFor(job.id),city=Traffic.CITY}
end

local function eligible(job)
    if not job or job.status~='ready_for_pickup'
        or job.pickup and job.pickup.status~='awaiting_schedule'
        and job.pickup.status~='player_delivery' then return false end
    if job.outboundDelivery and job.outboundDelivery.transport == 'customer' then return false end
    if not job.inspection or job.inspection.status~='passed' then return false end
    for _,pallet in ipairs(job.pallets or {}) do
        if pallet.status~='spoiled_discarded'
            and (pallet.status~='wrapped' or not pallet.wrapped
                or pallet.location~='warehouse' and pallet.location~='cutter_output'
                and pallet.location~='press_output') then return false end
    end
    return true
end

function Run.availableJobs(state,world,driverMode,now)
    local result={}
    for _,job in ipairs(state.jobs and state.jobs.active or {}) do
        local mode=job.pickup and job.pickup.driverMode
        local dispatchAt=tonumber(job.pickup and job.pickup.dispatchAtHours) or 0
        if eligible(job) and (not driverMode or mode==driverMode)
            and (mode~='employee' or not now or now>=dispatchAt) then
            local count=0
            for _,pallet in ipairs(job.pallets or {}) do
                if pallet.status~='spoiled_discarded' then count=count+1 end
            end
            if count>0 then
                local destination=Run.destination(job,world)
                result[#result+1]={id=job.id,company=job.company or job.id,
                    palletCount=count,destination=destination}
            end
        end
    end
    return result
end

function Run.build(state,jobIds,world,driverMode)
    if type(jobIds)~='table' or #jobIds<1 or #jobIds>Run.CAPACITY then
        return nil,'Choose at least one job for the delivery run.'
    end
    local seen,total,jobs={},0,{}
    for _,id in ipairs(jobIds) do
        if type(id)~='string' or seen[id] then return nil,'The delivery list contains an invalid job.' end
        seen[id]=true
        local job=findJob(state,id)
        if not eligible(job) then return nil,(id..' is not ready to load onto the shop truck.') end
        if driverMode and (not job.pickup or job.pickup.driverMode~=driverMode) then
            return nil,id..' is assigned to another delivery method.'
        end
        local count=0
        for _,pallet in ipairs(job.pallets or {}) do if pallet.status~='spoiled_discarded' then count=count+1 end end
        total=total+count
        if total>Run.CAPACITY then
            return nil,('The shop truck holds %d pallets per run.'):format(Run.CAPACITY)
        end
        jobs[#jobs+1]={job=job,destination=Run.destination(job,world),palletCount=count}
    end
    local stops,byKey={},{}
    local function add(item,kind)
        local destination=item.destination
        local key=kind..':'..destination.id
        local stop=byKey[key]
        if not stop then
            stop={kind=kind,id=destination.id,label=destination.label,city=destination.city,
                jobIds={},palletCount=0}
            if kind=='city' then
                stop.cityMiles=math.random(Run.CITY_LOCAL_MILES_MIN,Run.CITY_LOCAL_MILES_MAX)
            end
            byKey[key]=stop;stops[#stops+1]=stop
        end
        stop.jobIds[#stop.jobIds+1]=item.job.id
        stop.palletCount=stop.palletCount+item.palletCount
    end
    -- Town deliveries come first; the Millhaven leg is batched at the gate.
    for _,item in ipairs(jobs) do if item.destination.kind=='town' then add(item,'town') end end
    for _,item in ipairs(jobs) do if item.destination.kind=='city' then add(item,'city') end end
    local run={version=Run.VERSION,capacity=Run.CAPACITY,palletCount=total,status='loading',
        stopIndex=1,stops=stops,jobIds={}}
    for _,item in ipairs(jobs) do run.jobIds[#run.jobIds+1]=item.job.id end
    return run
end

function Run.cityStopMiles(stop)
    local miles=type(stop)=='table' and tonumber(stop.cityMiles)
    if miles and miles>=Run.CITY_LOCAL_MILES_MIN and miles<=Run.CITY_LOCAL_MILES_MAX then return miles end
    -- Old saved delivery runs predate per-destination city mileage.
    return 12.5
end

function Run.cityRouteMiles(run,firstStopIndex,lastStopIndex)
    local miles=Run.CITY_HIGHWAY_MILES*2
    for index,stop in ipairs(run and run.stops or {}) do
        if index>=(firstStopIndex or 1) and (not lastStopIndex or index<=lastStopIndex)
            and stop.kind=='city' then
            miles=miles+Run.cityStopMiles(stop)
        end
    end
    return miles
end

function Run.reserve(state,run)
    if not Run.valid(run,state.home) then return false,'The delivery manifest is invalid.' end
    for _,id in ipairs(run.jobIds) do
        local job=findJob(state,id)
        local reserved=job and job.status=='pickup_in_progress' and job.pickup and job.pickup.driverMode=='player'
        if not reserved and not eligible(job) then return false,'A selected job is no longer ready to load.' end
    end
    for _,id in ipairs(run.jobIds) do
        local job=findJob(state,id)
        if job.status=='ready_for_pickup' then
            require('src.job_service').schedulePickup(job,os.time())
            job.pickup.status='player_loading';job.pickup.driverMode='player'
        end
    end
    return true
end

function Run.loadingProgress(state,run)
    local loaded,total=0,0
    for _,id in ipairs(run.jobIds or {}) do
        local job=findJob(state,id)
        if not job then return nil,nil,'A delivery job is missing from the manifest.' end
        for _,pallet in ipairs(job.pallets or {}) do
            if pallet.status~='spoiled_discarded' then
                total=total+1
                if pallet.location=='outbound_truck' then loaded=loaded+1 end
            end
        end
    end
    return loaded,total
end

function Run.nextMessage(run)
    if run.status=='loading' then return 'Back the truck to the shop dock and load every pallet inside.' end
    local stop=run.stops[run.stopIndex]
    if not stop then return 'All deliveries complete. You are free to continue your day.' end
    return stop.kind=='city' and ('GPS: Millhaven bridge exit for '..stop.label..'.')
        or ('GPS: '..stop.label..'. Park nearby and hand off the pallets at the door.')
end

function Run.releaseTrip(state,trip)
    local driver=trip.deliveryDriver
    trip.deliveryRun=nil;trip.deliveryDriver=nil;trip.deliveryVehicleModel=nil
    if not trip.independent then
        trip.independent=true;trip.purpose='outing';trip.origin='warehouse'
        trip.destination=state.home.apartmentId
        for _,part in pairs(trip.participants) do
            part.origin=part.origin or 'warehouse'
            part.destination=part.origin=='warehouse' and state.home.apartmentId or 'warehouse'
        end
    elseif driver and trip.participants[driver] then
        local part=trip.participants[driver]
        part.destination=part.origin=='warehouse' and state.home.apartmentId or 'warehouse'
    end
    state.home.revision=state.home.revision+1
end

function Run.load(state,run)
    local service=require('src.job_service')
    if not Run.valid(run,state.home) then return false,'The delivery manifest is invalid.' end
    -- Validate the complete manifest before changing a job or pallet so that
    -- a stale planner cannot leave a partly loaded truck behind.
    for _,jobId in ipairs(run.jobIds or {}) do
        local job=findJob(state,jobId)
        if not eligible(job) then return false,'A selected job changed before the truck could be loaded.' end
        for _,pallet in ipairs(job.pallets or {}) do
            if pallet.status~='spoiled_discarded' and (pallet.status~='wrapped' or not pallet.wrapped
                or pallet.location~='warehouse' and pallet.location~='cutter_output'
                and pallet.location~='press_output') then
                return false,'Every pallet must be wrapped and staged in the warehouse before loading.'
            end
        end
    end
    for _,jobId in ipairs(run.jobIds or {}) do
        local job=findJob(state,jobId)
        local okay,reason=service.schedulePickup(job,os.time())
        if not okay then return false,reason end
        for _,pallet in ipairs(job.pallets or {}) do
            if pallet.status~='spoiled_discarded' then
                local loaded,message=service.loadForPickup(state,job.id,pallet.id,os.time())
                if not loaded then return false,message end
            end
        end
        job.pickup.status='player_delivery'
    end
    return true
end

function Run.nextStopOpen(state,stop,now)
    now=now or require('src.business_calendar').absoluteHours(state)
    local schedule=stop and stop.kind=='town'
        and require('src.commute.town_characters').businessSchedule(stop.id)
    local retail={diner=true,['coffee-shop']=true,['general-store']=true}
    if not schedule and stop and stop.kind=='town' and retail[stop.id] then
        schedule={openHour=7,closeHour=21}
    end
    if not schedule then return require('src.business_hours').nextService(now),'industrial' end
    local day=math.floor(now/24);local hour=now%24
    if hour<schedule.openHour then return day*24+schedule.openHour,'retail' end
    if hour>=schedule.closeHour then return (day+1)*24+schedule.openHour,'retail' end
    return now,'retail'
end

function Run.completeStop(state,stop,driverDelivery)
    if type(stop)~='table' or type(stop.jobIds)~='table' then return false,'Invalid delivery stop.' end
    local now=require('src.business_calendar').absoluteHours(state)
    local opens,kind=Run.nextStopOpen(state,stop,now)
    if opens>now+1e-7 then
        return false,('Receiving is closed. Return %s.%s'):format(
            require('src.business_calendar').dateTimeTextAtHours(opens),kind=='industrial'
                and ' Industrial deliveries run Monday-Friday, 09:00-20:00.' or '')
    end
    local service=require('src.job_service')
    -- Validate the entire stop before archiving or paying any of its jobs.
    -- Completed jobs are accepted on retry, without paying them a second time.
    for _,jobId in ipairs(stop.jobIds) do
        local job=findJob(state,jobId)
        if job then
            if job.status~='pickup_in_progress' then return false,'The delivery is not loaded.' end
            for _,pallet in ipairs(job.pallets or {}) do
                if pallet.status~='spoiled_discarded' and pallet.location~='outbound_truck' then
                    return false,'The delivery manifest is incomplete. Load every pallet first.'
                end
            end
        else
            local completed=false
            for _,prior in ipairs(state.jobs.completed or {}) do
                if prior.id==jobId then completed=true;break end
            end
            if not completed then return false,'A delivery job is missing.' end
        end
    end
    for _,jobId in ipairs(stop.jobIds) do
        local job=findJob(state,jobId)
        if job then
            local previousPerformance=job.driverDelivery
            if type(driverDelivery)=='table' then job.driverDelivery=copy(driverDelivery) end
            local okay,reason=service.completePickup(state,jobId,os.time())
            if not okay then
                job.driverDelivery=previousPerformance
                return false,reason
            end
        end
    end
    return true
end

function Run.valid(value,home)
    if type(value)~='table' or value.version~=Run.VERSION or value.capacity~=Run.CAPACITY
        or type(value.palletCount)~='number' or value.palletCount<1 or value.palletCount>Run.CAPACITY
        or value.palletCount%1~=0 or type(value.jobIds)~='table' or #value.jobIds<1
        or #value.jobIds>Run.CAPACITY or type(value.stops)~='table' or #value.stops<1
        or #value.stops>Run.CAPACITY or type(value.stopIndex)~='number'
        or value.stopIndex%1~=0 or value.stopIndex<1 or value.stopIndex>#value.stops+1
        or (value.status~='loading' and value.status~='driving' and value.status~='offmap' and value.status~='returning')
        or value.cutsceneStartedAtEpoch~=nil and (type(value.cutsceneStartedAtEpoch)~='number'
            or value.cutsceneStartedAtEpoch<0)
        or value.cutsceneEndsAtEpoch~=nil and (type(value.cutsceneEndsAtEpoch)~='number'
            or value.cutsceneEndsAtEpoch<0) then return false end
    if (value.driverSkill~=nil and (type(value.driverSkill)~='number'
            or value.driverSkill%1~=0 or value.driverSkill<0 or value.driverSkill>100))
        or (value.driverEmployeeId~=nil and (type(value.driverEmployeeId)~='string'
            or #value.driverEmployeeId>64 or not value.driverEmployeeId:match('^[%w_.%-]+$')))
        or value.vehicleModel~=nil and value.vehicleModel~='box' and value.vehicleModel~='kei' then return false end
    local town=home and home.town
    local known={}
    for _,jobId in ipairs(value.jobIds) do
        if type(jobId)~='string' or #jobId>80 or known[jobId] then return false end
        known[jobId]=true
    end
    local counted,assigned=0,{}
    for _,stop in ipairs(value.stops) do
        if type(stop)~='table' or (stop.kind~='town' and stop.kind~='city')
            or type(stop.id)~='string' or #stop.id>80 or type(stop.label)~='string' or #stop.label>120
            or type(stop.jobIds)~='table' or #stop.jobIds<1 or #stop.jobIds>Run.CAPACITY
            or type(stop.palletCount)~='number' or stop.palletCount<1 or stop.palletCount>Run.CAPACITY
            or stop.palletCount%1~=0
            or stop.kind=='city' and stop.cityMiles~=nil and (type(stop.cityMiles)~='number'
                or stop.cityMiles%1~=0 or stop.cityMiles<Run.CITY_LOCAL_MILES_MIN
                or stop.cityMiles>Run.CITY_LOCAL_MILES_MAX)
            or stop.kind=='town' and stop.cityMiles~=nil
            or (stop.standardArrivalAtHours~=nil and (type(stop.standardArrivalAtHours)~='number'
                or stop.standardArrivalAtHours~=stop.standardArrivalAtHours
                or stop.standardArrivalAtHours<0 or stop.standardArrivalAtHours>=1e12)) then return false end
        if stop.kind=='town' and town and not town.destinations[stop.id] then return false end
        for _,jobId in ipairs(stop.jobIds) do
            if not known[jobId] or assigned[jobId] then return false end
            assigned[jobId]=true
        end
        counted=counted+stop.palletCount
    end
    for jobId in pairs(known) do if not assigned[jobId] then return false end end
    return counted==value.palletCount
end

return Run
