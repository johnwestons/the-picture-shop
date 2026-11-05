-- Manifest planning and completion for player-driven shop deliveries.
local Traffic=require('src.commute.delivery_traffic')
local Run={CAPACITY=10,VERSION=1}

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
    if not job.inspection or job.inspection.status~='passed' then return false end
    for _,pallet in ipairs(job.pallets or {}) do
        if pallet.status~='spoiled_discarded'
            and (pallet.status~='wrapped' or not pallet.wrapped
                or pallet.location~='warehouse' and pallet.location~='cutter_output'
                and pallet.location~='press_output') then return false end
    end
    return true
end

function Run.availableJobs(state,world)
    local result={}
    for _,job in ipairs(state.jobs and state.jobs.active or {}) do
        if eligible(job) then
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

function Run.build(state,jobIds,world)
    if type(jobIds)~='table' or #jobIds<1 or #jobIds>Run.CAPACITY then
        return nil,'Choose at least one job for the delivery run.'
    end
    local seen,total,jobs={},0,{}
    for _,id in ipairs(jobIds) do
        if type(id)~='string' or seen[id] then return nil,'The delivery list contains an invalid job.' end
        seen[id]=true
        local job=findJob(state,id)
        if not eligible(job) then return nil,(id..' is not ready to load onto the shop truck.') end
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

function Run.load(state,run)
    local service=require('src.job_service')
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

function Run.completeStop(state,stop)
    if type(stop)~='table' or type(stop.jobIds)~='table' then return false,'Invalid delivery stop.' end
    local service=require('src.job_service')
    for _,jobId in ipairs(stop.jobIds) do
        local okay,reason=service.completePickup(state,jobId,os.time())
        if not okay then return false,reason end
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
    local town=home and home.town
    local known={}
    for _,jobId in ipairs(value.jobIds) do
        if type(jobId)~='string' or #jobId>80 or known[jobId] then return false end
        known[jobId]=true
    end
    local counted=0
    for _,stop in ipairs(value.stops) do
        if type(stop)~='table' or (stop.kind~='town' and stop.kind~='city')
            or type(stop.id)~='string' or #stop.id>80 or type(stop.label)~='string' or #stop.label>120
            or type(stop.jobIds)~='table' or #stop.jobIds<1 or #stop.jobIds>Run.CAPACITY
            or type(stop.palletCount)~='number' or stop.palletCount<1 or stop.palletCount>Run.CAPACITY
            or stop.palletCount%1~=0 then return false end
        if stop.kind=='town' and town and not town.destinations[stop.id] then return false end
        for _,jobId in ipairs(stop.jobIds) do if not known[jobId] then return false end end
        counted=counted+stop.palletCount
    end
    return counted==value.palletCount
end

return Run
