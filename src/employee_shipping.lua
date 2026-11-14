local Fleet=require("src.pallet_jack_fleet")
local Jack=require("src.pallet_jack")
local Config=require("src.config")
local Transport=require("src.employee_pallet_jack")
local Shipping={}
local function reserved(state,worker,palletId)
    for _,w in ipairs(state.employment.staff) do
        if w~=worker and w.visible and w.clockedIn
            and (w._shippingPalletId==palletId or w._inboundDeliveryPalletId==palletId) then return true end
    end
    for _,jack in ipairs(Fleet.all(state)) do
        if jack.carriedPalletId==palletId and jack.operating and jack.operatorEmployeeId~=worker.id then return true end
    end
    return false
end

local function unloadInbound(state,worker,dt,context,truck)
    local visit=state.deliveryDriver
    if truck.mode=="machine_delivery" or truck.mode=="pickup"
        or not visit or visit.status=="idle" or visit.status=="done" or visit.status=="missed"
        or tostring(visit.deliveryId)~=tostring(truck.jobId) then return false,false end
    if context.canLoadTruck and not context.canLoadTruck() then
        worker.activity="Waiting for the delivery manifest"
        return true,false
    end
    if truck.state=="parked_closed" then
        worker.activity="Opening the delivery truck"
        return true,context.openInboundDelivery()==true
    end
    if truck.state~="cargo_open" then
        worker.activity="Waiting for the delivery truck"
        return true,false
    end
    local selected
    for _,item in ipairs(context.inboundDeliveryItems and context.inboundDeliveryItems() or {}) do
        if item.location=="awaiting_delivery" and not reserved(state,worker,item.id) then
            if not selected or item.id==worker._inboundDeliveryPalletId then selected=item end
            if item.id==worker._inboundDeliveryPalletId then break end
        end
    end
    if not selected then
        worker._inboundDeliveryPalletId=nil
        if context.inboundDeliveryRemaining and context.inboundDeliveryRemaining()==0 then
            worker.activity="Delivery unloaded; close the cargo door from the manifest"
            return false,false
        end
        worker.activity="Waiting for an available delivery pallet"
        return true,false
    end
    worker._inboundDeliveryPalletId=selected.id
    local goal=context.inboundApproachPoint and context.inboundApproachPoint(worker)
    if not goal then worker.activity="Delivery truck access is blocked";return true,false end
    local reached,blocked=context.move(worker,goal,dt)
    worker.phase="walking"
    worker.activity=blocked and "Delivery truck access is blocked" or "Unloading inbound delivery"
    if not reached then return true,false end
    local okay=context.unloadInboundDelivery(worker,selected.id)
    if okay then worker._inboundDeliveryPalletId=nil end
    return true,okay==true
end

function Shipping.update(state,worker,dt,context)
    if not context.pickupTruck then return false,false end
    local truck=context.pickupTruck()
    if truck.mode~="pickup" then return unloadInbound(state,worker,dt,context,truck) end
    local job,inventory=require('src.player_delivery_loading').manifest(state,truck)
    local own=Fleet.owned(state,worker.id)
    local pallet,jobId
    if job and job.status=="pickup_in_progress" then
        for _,item in ipairs(inventory) do
            local p=item.pallet
            if p.status=="wrapped" and p.wrapped and not reserved(state,worker,p.id)
                and (p.location=="warehouse" or p.location=="cutter_output" or p.location=="press_output"
                    or p.location=="on_pallet_jack") then
                if not pallet or p.id==worker._shippingPalletId or own and own.carriedPalletId==p.id then
                    pallet=p;jobId=item.jobId or job.id
                end
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
    worker.activity=loaded and "Loading "..jobId.." onto its assigned truck" or "Collecting finished skid for "..jobId
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
