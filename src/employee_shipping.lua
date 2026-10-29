local Fleet=require("src.pallet_jack_fleet")
local Jack=require("src.pallet_jack")
local Config=require("src.config")
local Transport=require("src.employee_pallet_jack")
local Shipping={}
local function reserved(state,worker,palletId)
    for _,w in ipairs(state.employment.staff) do
        if w~=worker and w.visible and w.clockedIn and w._shippingPalletId==palletId then return true end
    end
    for _,jack in ipairs(Fleet.all(state)) do
        if jack.carriedPalletId==palletId and jack.operating and jack.operatorEmployeeId~=worker.id then return true end
    end
    return false
end
function Shipping.update(state,worker,dt,context)
    if not context.pickupTruck then return false,false end
    local truck=context.pickupTruck()
    local job
    if truck.mode=="pickup" then
        for _,candidate in ipairs(state.jobs.active) do if candidate.id==truck.jobId then job=candidate;break end end
    end
    local own=Fleet.owned(state,worker.id)
    local pallet
    if job and job.status=="pickup_in_progress" then
        for _,p in ipairs(job.pallets) do
            if p.status=="wrapped" and p.wrapped and not reserved(state,worker,p.id)
                and (p.location=="warehouse" or p.location=="cutter_output" or p.location=="press_output"
                    or p.location=="on_pallet_jack") then
                if not pallet or p.id==worker._shippingPalletId or own and own.carriedPalletId==p.id then pallet=p end
                if own and own.carriedPalletId==p.id then break end
            end
        end
    end
    if not pallet then
        worker._shippingPalletId=nil
        if own and not own.carriedPalletId then
            if (worker.sceneId or "warehouse")~="warehouse" then
                local _,changed=context.travelScene(worker,"warehouse",dt);return true,changed
            end
            return true,Transport.park(state,worker,dt,context)==true
        end
        if (worker.sceneId or "warehouse")~="warehouse" then
            local _,changed=context.travelScene(worker,"warehouse",dt);return true,changed
        end
        return false,false
    end
    worker._shippingPalletId=pallet.id
    if context.canLoadTruck and not context.canLoadTruck() then
        worker.activity="Waiting for the truck manifest";return true,false
    end
    if truck.state=="parked_closed" then truck:toggleCargoDoor();return true,true end
    if truck.state~="cargo_open" then worker.activity="Waiting for assigned pickup truck";return true,false end
    local jack=Fleet.employee(state,worker,pallet.id)
    if not jack then worker.activity="Waiting for an available pallet jack";return true,false end
    local view=Fleet.view(state,jack)
    if not own then
        if (worker.sceneId or "warehouse")~=jack.sceneId then
            local _,changed=context.travelScene(worker,jack.sceneId,dt);return true,changed
        end
        local goal=context.jackApproachPoint(worker)
        if not goal then worker.activity="Pallet jack access is blocked";return true,false end
        local reached=context.move(worker,goal,dt)
        worker.phase,worker.activity="walking","Walking to pallet jack for pickup loading"
        if reached then return true,Jack.mountEmployee(view,Config.palletJack,worker.id)==true end
        return true,false
    end
    local loaded=jack.carriedPalletId==pallet.id
    if jack.carriedPalletId and not loaded then
        worker.activity="Assigned truck is waiting for another skid";return true,false
    end
    local destination=loaded and (truck.sceneId or "warehouse") or (pallet.world and pallet.world.sceneId or "warehouse")
    if jack.sceneId~=destination then
        local _,changed=context.travelScene(worker,destination,dt);return true,changed
    end
    local key=pallet.id..":"..jack.sceneId..":"..tostring(loaded)
    local cached=worker._jackTarget
    local goal=cached and cached.key==key and cached.goal
    if not goal then
        goal=loaded and context.truckLoadingPoint(worker,pallet) or context.jackPickupPoint(worker,pallet)
        worker._jackTarget=goal and {key=key,goal=goal} or nil
    end
    if not goal then worker.activity="Clear the skid's route to its assigned truck";return true,false end
    worker.activity=loaded and "Loading "..job.id.." onto its assigned truck" or "Collecting finished skid for "..job.id
    local reached,blocked=Transport.move(state,worker,goal,dt,context)
    if blocked then worker._jackTarget=nil end
    if not reached then return true,false end
    worker._jackTarget=nil
    if loaded then
        local ok=context.loadPickup(worker,pallet.id)
        if ok then worker._shippingPalletId=nil end
        return true,ok==true
    end
    if context.jackLoadClear and not context.jackLoadClear(worker,pallet.id,jack.x,jack.y) then
        worker.activity="Clear the finished skid's loading route";return true,false
    end
    return true,Jack.lift(view,Config.palletJack,pallet.id)==true
end
return Shipping
