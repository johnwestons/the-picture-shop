-- The inbound driver walks through the personnel door, waits for a signature,
-- then returns to the cab. The saved visit is durable; the live actor is transient.
local Driver={WAIT_SECONDS=120,SIGNATURE_RADIUS=80,RETRY_DELAY_HOURS=.5}
local Registration=require("src.warehouse_registration")
local Animation=require("src.character_animation")
local Pose=require("src.delivery_driver_pose")
local AIWatchdog=require("src.ai_watchdog")
local actors=setmetatable({},{__mode="k"})
local sideDoor=Registration.exit
-- Use the same clear apron point as the truck interaction. The old point at
-- (64, 242) sat inside the parked truck's collision radius, so the driver
-- could never finish the return-to-cab leg after a signature.
local truckSide=Registration.truck.interaction
local signaturePoint={x=151,y=236}
local deliveryRecord

local function newActor(x,y,phase,deliveryId)
    return {visible=true,x=x,y=y,sceneId="warehouse",intentX=1,intentY=0,
        watchdogLabel=deliveryId and ('Delivery driver '..tostring(deliveryId)) or nil,
        moving=false,distance=0,animationDistance=0,idleClock=0,interactionClock=0,phase=phase}
end

local function visit(state)
    local value=state and state.deliveryDriver
    return type(value)=="table" and value.status~="idle" and value or nil
end
Driver.visit=visit

local function matching(state,deliveryId)
    local value=visit(state)
    return value and tostring(value.deliveryId)==tostring(deliveryId) and value or nil
end
Driver.matching=matching

local function actorFor(state)
    return state and (actors[state] or Pose.actor(state._deliveryDriverPose)) or nil
end
Driver.actor=actorFor

local function ensureActor(state,value)
    local actor=actors[state]
    if actor then return actor end
    if value.status=="approaching" then
        actor=newActor(truckSide.x,truckSide.y,"approach_door",value.deliveryId)
    elseif value.status=="waiting" then
        actor=newActor(signaturePoint.x,signaturePoint.y,"waiting",value.deliveryId)
    elseif value.status=="signed" or value.status=="missed" then
        if value.driverReturned then return nil end
        actor=newActor(signaturePoint.x,signaturePoint.y,"exit_door",value.deliveryId)
    else return nil end
    actors[state]=actor
    return actor
end

local function direction(actor,x,y)
    local dx,dy=x-actor.x,y-actor.y
    local length=math.sqrt(dx*dx+dy*dy)
    if length>.001 then actor.intentX,actor.intentY=dx/length,dy/length end
end

function Driver.start(state,deliveryId,mode)
    if type(state)~="table" or type(deliveryId)~="string" or mode=="pickup" then return false end
    local prior=state.deliveryDriver
    if prior and tostring(prior.deliveryId)==deliveryId and prior.status~="done" then
        ensureActor(state,prior)
        return false
    end
    state.deliveryDriver={version=1,deliveryId=deliveryId,mode=mode,status="approaching",
        waitSeconds=0,driverReturned=false,penaltyApplied=false}
    actors[state]=newActor(truckSide.x,truckSide.y,"approach_door",deliveryId)
    state._deliveryDriverPose=nil
    return true
end

function Driver.reset(state)
    if type(state)~="table" then return false end
    actors[state]=nil
    state._deliveryDriverPose=nil
    return true
end

local function playerAtShop(context)
    for _,player in ipairs(context and context.players and context.players() or {}) do
        if (player.sceneId or "warehouse")=="warehouse" then return true end
    end
    return false
end

local function employeeAtShop(state)
    for _,worker in ipairs(state.employment and state.employment.staff or {}) do
        if worker.status=="employed" and worker.visible and worker.clockedIn
            and (worker.sceneId or "warehouse")=="warehouse" then return worker end
    end
end

local function reputationPenalty(state)
    local reputation=require("src.reputation").ensure(state)
    reputation.score=math.max(-100,reputation.score-2)
end

local function beginExit(actor)
    actor.phase="exit_door"
    actor.idleClock=0
    actor.returnSeconds=0
end

local function acceptSignature(state,value,signer,ink)
    if value.status~="waiting" then return false end
    local receipt=Driver.receipt(state,value.deliveryId)
    if receipt then require('src.receipt_book').delivery(state,receipt,signer or 'Employee',ink) end
    value.status="signed"
    value.signedBy=signer or "Employee"
    value.signedAtHours=require("src.business_calendar").absoluteHours(state)
    value.driverReturned=false
    local actor=actors[state]
    if actor then beginExit(actor) end
    state.message=signer=="You"
        and ("You signed for delivery "..value.deliveryId..". The driver is heading back to the truck.")
        or ((signer or "An employee").." signed for delivery "..value.deliveryId..". The driver is heading back to the truck.")
    return true
end

function Driver.sign(state,player,signature)
    local value=visit(state)
    local actor=actorFor(state)
    if not value or value.status~="waiting" or not actor then
        return false,"The driver is not waiting for a signature."
    end
    if signature and (signature.deliveryId~=value.deliveryId
        or signature.ink~=nil and not require('src.receipt_signature').valid(signature.ink)) then
        return false,'This receipt no longer matches the waiting delivery.'
    end
    if type(player)~="table" or (player.sceneId or "warehouse")~="warehouse" then
        return false,"Come into the warehouse to sign for the delivery."
    end
    local dx,dy=(tonumber(player.x) or 0)-actor.x,(tonumber(player.y) or 0)-actor.y
    if dx*dx+dy*dy>(Driver.SIGNATURE_RADIUS+10)^2 then
        return false,"Move closer to the driver to sign for the delivery."
    end
    direction(actor,-dx,-dy)
    return acceptSignature(state,value,player.name or player.displayName or 'You',signature and signature.ink)
end

function Driver.interaction(state)
    local value=visit(state)
    local actor=actorFor(state)
    local pose=state and state._deliveryDriverPose
    local waiting,deliveryId
    if pose and pose.status~=nil then
        waiting=pose.status=="waiting"
        deliveryId=pose.deliveryId
    else
        waiting=value and value.status=="waiting"
        deliveryId=value and value.deliveryId
    end
    if not waiting or not deliveryId or not actor then return nil end
    return {x=actor.x,y=actor.y,radius=Driver.SIGNATURE_RADIUS,
        prompt="E: review and sign delivery "..tostring(deliveryId),deliveryId=deliveryId}
end

function Driver.receipt(state,deliveryId)
    local value=matching(state,deliveryId)
    if not value or value.status~="waiting" then return nil end
    local record=deliveryRecord(state,value)
    if not record then return nil end

    local manifest,items
    if value.mode=="machine_delivery" then
        manifest,items=require("src.machine_fleet").truckInventory(state,value.deliveryId)
    else
        manifest,items=require("src.pallet_logistics").truckInventory(state,value.deliveryId)
    end
    manifest=manifest or record
    items=items or {}
    local first=items[1] or {}
    local pallet=first.pallet or first
    local count=#items
    local product=first.productName or manifest.machineName or manifest.productName
    if not product and value.mode=="machine_delivery" then product="Used shop machinery" end
    if not product and value.mode=="vendor_delivery" then product="Shop supplies" end
    if not product then product="Client job materials" end
    if count>1 then product=product.." + "..tostring(count-1).." more pallet(s)" end

    local quantity
    if value.mode=="machine_delivery" then
        quantity="1 machine"
    elseif first.quantity~=nil then
        quantity=tostring(first.quantity).." "..tostring(first.unit or "units")
    elseif first.sheets~=nil then
        quantity=tostring(first.sheets).." sheets"
    else
        quantity=tostring(count)..(count==1 and " pallet" or " pallets")
    end

    local StatusLabels=require("src.status_labels")
    local status=manifest.status or record.status
    local delivery=manifest.delivery or record.delivery or {}
    local supplier=manifest.company or record.company
    if not supplier and manifest.orderIds then
        local only,mixed
        for _,id in ipairs(manifest.orderIds) do
            local purchase=require('src.procurement').orderById(state,id)
            local company=purchase and (purchase.company or purchase.vendor)
            if company then
                if only and only~=company then mixed=true end
                only=only or company
            end
        end
        supplier=mixed and 'Millhaven Freight' or only
    end
    supplier=supplier or (delivery.route and delivery.route.originCompany) or 'Picture Shop delivery'
    local previews={}
    if value.mode=='machine_delivery' then
        previews[1]={image='machineFlatbedLoaded'}
    else
        for i=1,math.min(3,#items) do
            local item=items[i];local cargo=item.pallet or item
            local image,quad=require('src.world_renderer').palletVisual({pallet=cargo,vendor=item.vendorProduct==true})
            previews[#previews+1]={image=image,quad=quad}
        end
    end
    local artwork=manifest.artwork or record.artwork or {}
    return {
        deliveryId=tostring(value.deliveryId),
        document=value.mode=="machine_delivery" and "MACHINERY RECEIPT"
            or value.mode=="vendor_delivery" and "PURCHASE RECEIPT" or "CLIENT DELIVERY RECEIPT",
        supplier=supplier,
        orderState=status and StatusLabels.get(status) or "In transit",
        deliveryState="Driver waiting for signature",
        shipment=product,
        quantity=quantity,
        category=first.categoryName or pallet.categoryName
            or (value.mode=="machine_delivery" and "Shop machinery"
                or value.mode=="vendor_delivery" and "Shop supplies" or "Client materials"),
        amountLabel=(value.mode=="vendor_delivery" or value.mode=="machine_delivery")
            and "Purchase price" or "Job value",
        declaredValue=manifest.price or record.price
            or (manifest.quote and manifest.quote.totalPrice)
            or (record.quote and record.quote.totalPrice),
        palletCount=count,
        location="Warehouse loading bay",
        deliveryStatus=delivery.status,
        previews=previews,
        artworkKey=artwork.key or manifest.artworkKey or record.artworkKey,
        artworkName=artwork.displayName or artwork.fileName,
    }
end

local function missed(state,value,actor)
    value.status="missed"
    value.driverReturned=false
    value.penaltyApplied=true
    reputationPenalty(state)
    if actor then beginExit(actor) end
    state.message="The driver left without a signature for "..tostring(value.deliveryId)..". Shop reputation decreased by 2."
    return true
end

function Driver.update(state,dt,context)
    local value=visit(state)
    if not value then return false end
    local actor=ensureActor(state,value)
    if not actor then return false end
    dt=math.max(0,tonumber(dt) or 0)
    local changed=false
    local AI=require("src.employee_ai")
    if actor.phase=="exit_door" or actor.phase=="exit_cab" then
        actor.returnSeconds=(actor.returnSeconds or 0)+dt
    end
    if actor.phase=="approach_door" then
        direction(actor,sideDoor.x,sideDoor.y)
        local reached=AI.move(actor,sideDoor,dt,context)
        if reached then actor.phase="approach_sign";changed=true end
    elseif actor.phase=="approach_sign" then
        direction(actor,signaturePoint.x,signaturePoint.y)
        local reached=AI.move(actor,signaturePoint,dt,context)
        if reached then
            value.status="waiting";value.waitSeconds=0
            actor.phase="waiting";changed=true
        end
    elseif actor.phase=="waiting" then
        actor.moving=false;actor.idleClock=(actor.idleClock or 0)+dt
    elseif actor.phase=="exit_door" then
        direction(actor,sideDoor.x,sideDoor.y)
        local reached=AI.move(actor,sideDoor,dt,context)
        if reached then
            actor.phase="exit_cab"
            local contact=Registration.truck.interaction
            local goals={
                {x=contact.x,y=contact.y},
                {x=contact.x+24,y=contact.y},
                {x=contact.x,y=contact.y+22},
                {x=contact.x+24,y=contact.y+22},
                {x=contact.x-18,y=contact.y+20},
                {x=contact.x+42,y=contact.y+8},
            }
            local routeContext=context.forActor and context.forActor(actor) or context
            actor.returnPoint=AI.findReachablePoint(actor,goals,routeContext)
                or {x=contact.x,y=contact.y}
            changed=true
        end
    elseif actor.phase=="exit_cab" then
        local returnPoint=actor.returnPoint or truckSide
        local nearCab=(actor.x-truckSide.x)^2+(actor.y-truckSide.y)^2<=22^2
        local reached=false
        if not nearCab then
            direction(actor,returnPoint.x,returnPoint.y)
            reached=AI.move(actor,returnPoint,dt,context)
        end
        -- If furniture or another actor blocks every nearby apron point, do
        -- not hold the truck and shipment indefinitely. The driver exits the
        -- scene after a bounded retry window so the completed delivery can
        -- continue through its normal departure flow.
        if nearCab or reached or actor.returnSeconds>=18 then
            if not nearCab and not reached then
                AIWatchdog.clear(state,actor,'Delivery driver exit timeout accepted')
                AIWatchdog.note(state,'delivery-driver:'..tostring(value.deliveryId),{
                    status='RECOVERED',system='Warehouse delivery',subject=actor.watchdogLabel,
                    stage='return_to_truck',reason='Driver could not reach the truck before the exit timeout',
                    action='Removed the blocked driver actor and released the truck departure',
                    x=actor.x,y=actor.y,visible=actor.visible})
            end
            actor.visible=false;actor.moving=false;actor.phase="gone"
            value.driverReturned=true;changed=true
        end
    end
    if actor.phase=="exit_door" and actor.returnSeconds>=18 then
        AIWatchdog.clear(state,actor,'Delivery driver exit timeout accepted')
        AIWatchdog.note(state,'delivery-driver:'..tostring(value.deliveryId),{
            status='RECOVERED',system='Warehouse delivery',subject=actor.watchdogLabel,
            stage='return_to_door',reason='Driver could not reach the side door before the exit timeout',
            action='Removed the blocked driver actor and released the truck departure',
            x=actor.x,y=actor.y,visible=actor.visible})
        actor.visible=false;actor.moving=false;actor.phase="gone"
        value.driverReturned=true;changed=true
    end
    if value.status=="waiting" and not playerAtShop(context) then
        local worker=employeeAtShop(state)
        if worker then changed=acceptSignature(state,value,worker.name or "Employee") or changed end
    end
    if value.status=="approaching" or value.status=="waiting" then
        local previous=math.floor(value.waitSeconds or 0)
        value.waitSeconds=math.min(Driver.WAIT_SECONDS,(value.waitSeconds or 0)+dt)
        if math.floor(value.waitSeconds)~=previous then changed=true end
        if value.waitSeconds>=Driver.WAIT_SECONDS then changed=missed(state,value,actor) or changed end
    end
    return changed
end

deliveryRecord=function(state,value)
    if not state or not value then return nil end
    if value.mode=="machine_delivery" then
        return require("src.machine_fleet").orderById(state,value.deliveryId)
    end
    local purchase=require("src.procurement").orderById(state,value.deliveryId)
    if purchase then return purchase end
    for _,job in ipairs(state.jobs and state.jobs.active or {}) do
        if tostring(job.id)==tostring(value.deliveryId) then return job end
    end
end

local function received(state,value)
    local record=deliveryRecord(state,value)
    if not record then return false end
    if value.mode=="machine_delivery" then
        return require("src.machine_fleet").remainingOnTruck(state,value.deliveryId)==0
    end
    return require("src.pallet_logistics").remainingOnTruck(state,value.deliveryId)==0
end

function Driver.departIfReady(state,truck)
    local value=matching(state,truck and truck.jobId)
    if not value or (value.status~="signed" and value.status~="missed") or not value.driverReturned then return false end
    local canDepart=value.status=="missed" or received(state,value)
    if not canDepart then return false end
    if truck.state=="cargo_open" then return truck:toggleCargoDoor() end
    if truck.state=="parked_closed" then return truck:depart() end
    return false
end

local function retryDelivery(state,value)
    local record=deliveryRecord(state,value)
    local delivery=record and record.delivery
    if not delivery then return false end
    local retryAt=require('src.business_hours').nextService(
        require("src.business_calendar").absoluteHours(state)+Driver.RETRY_DELAY_HOURS)
    delivery.status=value.mode=="machine_delivery" and "awaiting_delivery"
        or value.mode=="vendor_delivery" and "awaiting_schedule" or "pending_arrival"
    delivery.expectedAtHours=retryAt
    delivery.readyAtHours=retryAt
    delivery.route=nil
    delivery.returnRoute=nil
    return true
end

function Driver.departed(state,deliveryId)
    local value=matching(state,deliveryId)
    if not value then return false end
    if value.status=="missed" and not received(state,value) then retryDelivery(state,value) end
    value.status="done"
    value.driverReturned=true
    actors[state]=nil
    state._deliveryDriverPose=nil
    return true
end

function Driver.pose(state)
    local actor=actors[state]
    local value=visit(state)
    return Pose.capture(actor,value and value.status,value and value.deliveryId)
end

function Driver.applyPose(state,value)
    if type(state)~="table" then return false end
    local pose=Pose.normalize(value)
    state._deliveryDriverPose=pose
    actors[state]=nil
    return true
end

function Driver.presentation(state)
    return actorFor(state)
end

function Driver.draw(actor,sourceImage,sourceQuad,scaleMultiplier)
    if not actor or actor.visible==false then return false end
    local direction=Animation.authoredDirection(actor.intentX,actor.intentY)
    local action=actor.moving and "walk" or "idle"
    local name=action..(direction=="east" and "" or "_"..direction)
    local path="assets/source/warehouse-expansion-v1/mechanic-raccoon/"..name..".png"
    local image=sourceImage(path)
    if not image then return false end
    local width,height=image:getDimensions()
    local frames=action=="walk" and 8 or 2
    local frame=action=="walk"
        and Animation.frameForGait(frames,actor.animationDistance or actor.distance or 0,12)
        or Animation.frameForIdle(frames,actor.idleClock or 0,.65)
    local quad=sourceQuad(path,frame,512,512)
    if not quad then return false end
    love.graphics.setColor(1,1,1,1)
    local scale=76.8/385*(tonumber(scaleMultiplier) or 1)
    love.graphics.draw(image,quad,actor.x,actor.y,0,scale,scale,256,458)
    return true
end

return Driver
