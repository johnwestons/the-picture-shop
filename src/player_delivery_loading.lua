-- One manifest shared by the exterior shop truck and the warehouse loading bay.
-- Warehouse players and employees keep using the existing pallet/jack authority.
local Run=require('src.commute.delivery_run')
local Service=require('src.job_service')
local Sites=require('src.commute.sites')
local Loading={}
local siteCache=setmetatable({}, {__mode='k'})
local legacySites

local function brief(value,limit)
    local text=tostring(value or '')
    if #text<=limit then return text end
    local last=limit-3
    while text:byte(last+1)>=128 and text:byte(last+1)<192 do last=last-1 end
    return text:sub(1,last)..'...'
end

function Loading.itemDetail(item)
    return string.format('%s · %s · %s',brief(item.company,36),brief(item.destinationLabel,32),
        item.location=='outbound_truck' and 'Loaded' or 'Ready to load')
end

local function manifestRun(state,truck)
    local trip=state.home and state.home.commute
    local run=trip and trip.deliveryRun
    if not run or truck.mode~='pickup' or (truck.sceneId or 'warehouse')~='warehouse' then return nil end
    for _,id in ipairs(run.jobIds) do if id==truck.jobId then return run end end
end

-- Both the local screen and the host's remote manifest use the same stable
-- row order. Keep loaded rows so a later job never slides under a pending tap.
function Loading.manifest(state,truck)
    local run=manifestRun(state,truck)
    if not run then return Service.pickupInventory(state,truck.jobId) end
    local inventory,destinations={},{}
    for _,stop in ipairs(run.stops) do
        for _,id in ipairs(stop.jobIds) do
            destinations[id]=stop.kind=='city' and (stop.city or 'Millhaven') or stop.label
        end
    end
    for _,id in ipairs(run.jobIds) do
        local job,items=Service.pickupInventory(state,id)
        for _,item in ipairs(items) do
            item.jobId=id;item.company=job.company or id;item.destinationLabel=destinations[id]
            inventory[#inventory+1]=item
        end
    end
    return {id=run.jobIds[1],manifestId=run.jobIds[1],company='Delivery run',status='pickup_in_progress'},inventory,run
end

function Loading.remaining(state,truck)
    local run=manifestRun(state,truck)
    if not run then return Service.remainingPickup(state,truck.jobId) end
    local loaded,total=Run.loadingProgress(state,run)
    return loaded and total-loaded or run.palletCount
end

function Loading.context(state)
    local home=state and state.home
    local trip=home and home.commute
    local run=trip and trip.deliveryRun
    if not run then return nil end
    local world
    if home.town then
        world=siteCache[home.town]
        if not world then
            world={sites=Sites.create({placements=home.town.placements,designs=home.town.designs})}
            siteCache[home.town]=world
        end
    else
        legacySites=legacySites or {sites=Sites.create()};world=legacySites
    end
    local vehicle=trip.deliveryVehicleModel=='kei' and trip.keiTruck or trip.truck
    return run,vehicle,world
end

function Loading.canLoad(state,truck,palletId)
    if not truck.playerDelivery then return true,nil,truck.jobId end
    local run,vehicle,world=Loading.context(state)
    if not run or run.status~='loading' or not vehicle or not manifestRun(state,truck)
        or not require('src.commute.trip').truckAtLoadingBay(world,vehicle) then
        return false,'Back the assigned delivery truck squarely against the dock before loading.'
    end
    local loaded,total=Run.loadingProgress(state,run)
    if not loaded or total~=run.palletCount or total>Run.CAPACITY then
        return false,'The delivery manifest changed. Check the selected jobs before loading.'
    end
    if not palletId then return manifestRun(state,truck)~=nil end
    for _,id in ipairs(run.jobIds) do
        local job,items=Service.pickupInventory(state,id)
        if job and not (job.outboundDelivery and job.outboundDelivery.transport=='customer') then
            for _,item in ipairs(items) do if item.id==palletId then return true,nil,id end end
        end
    end
    return false,'This pallet is not on the active delivery manifest.'
end

function Loading.sync(state,truck,door)
    local run,vehicle,world=Loading.context(state)
    local aligned=vehicle and require('src.commute.trip').truckAtLoadingBay(world,vehicle)
    if not run or not aligned or run.status~='loading' and run.status~='driving' then
        if truck.playerDelivery then truck:reset();truck.playerDelivery=nil;return true end
        return false
    end
    if not truck.playerDelivery and (truck.state~='absent' or run.status~='loading') then return false end
    -- Older saved loading runs had not yet reserved their indoor manifests.
    if not truck.playerDelivery then
        local reserved,reason=Run.reserve(state,run)
        if not reserved then state.message=reason;return false end
    end
    local loaded,total,reason=Run.loadingProgress(state,run)
    if not loaded then state.message=reason;return false end
    local nextJob
    for _,id in ipairs(run.jobIds) do
        if Service.remainingPickup(state,id)>0 then nextJob=id;break end
    end
    local changed=false
    if not truck.playerDelivery then
        truck.playerDelivery=true;truck.mode='pickup';truck.sceneId='warehouse'
        truck.state='parked_closed';truck.backingProgress=1;truck.cargoProgress=0;truck.timer=0
        truck.jobId=nextJob or run.jobIds[#run.jobIds]
        state.message=('Truck aligned at the dock. Load %d pallets using the warehouse manifest or pallet jacks.'):format(total)
        changed=true
    elseif nextJob and truck.jobId~=nextJob then
        truck.jobId=nextJob;changed=true
    end
    if door and door.state=='closed' then door:open();changed=true end
    if run.status=='loading' and loaded==total then
        if truck.state=='cargo_open' then truck:toggleCargoDoor();changed=true
        elseif truck.state=='parked_closed' then
            run.status='driving'
            for _,id in ipairs(run.jobIds) do
                local job=select(1,Service.pickupInventory(state,id))
                if job then job.pickup.status='player_delivery' end
            end
            state.message=('Pallets loaded: %d/%d. Cargo secured. '):format(loaded,total)..Run.nextMessage(run)
            state.home.revision=state.home.revision+1;changed=true
        end
    end
    return changed
end

return Loading
