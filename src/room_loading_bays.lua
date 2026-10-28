-- Purchased room docks share the existing, job-addressed truck queue.
local Bays={PRICE=1800,IDS={"front_left","front_right"}}
function Bays.catalog() return {id="garage_door",name="Truck loading garage door",price=Bays.PRICE} end
function Bays.owns(state,id)
    return state and state.warehouse and state.warehouse.garageDoors
        and state.warehouse.garageDoors[id]~=nil or false
end
function Bays.validate(warehouse)
    local doors=warehouse.garageDoors
    if doors==nil then return true end
    if type(doors)~="table" then return false end
    local requests={}
    for _,r in ipairs(warehouse.receipts or {}) do requests[r.requestId]=true end
    for id,r in pairs(doors) do
        local bay=warehouse.bays and warehouse.bays[id]
        if (id~="front_left" and id~="front_right") or not bay or bay.status~="complete"
            or (bay.optionId~="storage" and bay.optionId~="floor") or type(r)~="table"
            or type(r.requestId)~="string" or #r.requestId<1 or #r.requestId>64
            or not r.requestId:match("^[%w_.%-]+$") or requests[r.requestId]
            or r.pricePaid~=Bays.PRICE or type(r.purchasedAtHours)~="number"
            or r.purchasedAtHours~=r.purchasedAtHours or r.purchasedAtHours<0
            or r.purchasedAtHours==math.huge then return false end
        for key in pairs(r) do
            if key~="requestId" and key~="pricePaid" and key~="purchasedAtHours" then return false end
        end
        requests[r.requestId]=true
    end
    return true
end
function Bays.purchase(state,id,requestId)
    local warehouse,reason=require("src.warehouse_upgrades").ensure(state)
    if not warehouse then return false,reason end
    if (id~="front_left" and id~="front_right") or type(requestId)~="string"
        or #requestId<1 or #requestId>64 or not requestId:match("^[%w_.%-]+$") then
        return false,"Choose a room and a valid purchase request."
    end
    for room,receipt in pairs(warehouse.garageDoors or {}) do
        if receipt.requestId==requestId then
            if room==id then return true,receipt,"replayed" end
            return false,"This purchase request was already used for another room."
        end
    end
    for _,receipt in ipairs(warehouse.receipts) do
        if receipt.requestId==requestId then return false,"This purchase request was already used." end
    end
    local bay=warehouse.bays[id]
    if not bay or bay.status~="complete" or (bay.optionId~="storage" and bay.optionId~="floor") then
        return false,"Complete a storage or utility room before adding its truck loading bay."
    end
    if Bays.owns(state,id) then return false,"This room already has a loading garage door." end
    if type(state.money)~="number" or state.money~=state.money or state.money==math.huge or state.money<Bays.PRICE then
        return false,"Not enough money for this garage door."
    end
    local receipt={requestId=requestId,pricePaid=Bays.PRICE,
        purchasedAtHours=require("src.business_calendar").absoluteHours(state)}
    warehouse.garageDoors=warehouse.garageDoors or {}
    warehouse.garageDoors[id]=receipt
    state.money=state.money-Bays.PRICE
    return true,receipt,"purchased"
end
function Bays.pickupScene(state,job)
    local counts={}
    for _,p in ipairs(job.pallets or {}) do
        local scene=p.world and p.world.sceneId or "warehouse"
        counts[scene]=(counts[scene] or 0)+1
    end
    local preferred=job.pickup and job.pickup.sceneId
    if Bays.owns(state,preferred) then return preferred end
    local selected,best
    for _,id in ipairs(Bays.IDS) do
        if Bays.owns(state,id) and (not best or (counts[id] or 0)>best) then
            selected,best=id,counts[id] or 0
        end
    end
    return selected or "warehouse"
end
-- The room bay is on the back wall, clear of the pedestrian exit and racks.
Bays.aperture={{x=780,y=104},{x=924,y=126},{x=924,y=280},{x=780,y=258}}
Bays.interaction={x=758,y=296,radius=44,hoverX=758,hoverY=218,hoverRadius=26}
Bays.truckInteraction={x=851,y=310,radius=54,hoverX=851,hoverY=221,hoverRadius=42}
Bays.loadingPoint={x=850,y=329}
return Bays
