-- One manifest shared by the exterior shop truck and the warehouse loading bay.
-- Warehouse players and employees keep using the existing pallet/jack authority.
local Run=require('src.commute.delivery_run')
local Service=require('src.job_service')
local Sites=require('src.commute.sites')
local Loading={}
local siteCache=setmetatable({}, {__mode='k'})
local legacySites

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

function Loading.canLoad(state,truck)
    if not truck.playerDelivery then return true end
    local run,vehicle,world=Loading.context(state)
    if not run or run.status~='loading' or not vehicle
        or not require('src.commute.trip').truckAtLoadingBay(world,vehicle) then
        return false,'Back the assigned delivery truck squarely against the dock before loading.'
    end
    for _,id in ipairs(run.jobIds) do if id==truck.jobId then return true end end
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
