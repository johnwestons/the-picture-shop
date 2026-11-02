local Catalog=require("src.home_shop_catalog")
local Calendar=require("src.business_calendar")
local Residents=require("src.home_residents")
local Shopping={}
local function integer(n,a,b) return type(n)=="number" and n==n and n>=a and n<=b and n==math.floor(n) end
local function time(n) return type(n)=="number" and n==n and n>=0 and n<=24000100 end
function Shopping.new()
    return {version=1,nextOrderId=1,guestLimitCents=3000,guestSpentCents=0,budgetCloseHours=-1,orders={}}
end
function Shopping.valid(shop)
    if shop==nil then return true end
    if type(shop)~="table" or shop.version~=1 or not integer(shop.nextOrderId,1,1e9)
        or not integer(shop.guestLimitCents,0,1000000) or not integer(shop.guestSpentCents,0,1e12)
        or not (shop.budgetCloseHours==-1 or time(shop.budgetCloseHours)) or type(shop.orders)~="table" or #shop.orders>128 then return false end
    local ids,requests,count={},{},0
    for index,row in pairs(shop.orders) do
        if not integer(index,1,#shop.orders) or type(row)~="table" then return false end
        local product=Catalog.PRODUCTS[row.productId]
        if not product or not integer(row.id,1,shop.nextOrderId-1) or ids[row.id]
            or type(row.requestId)~="string" or #row.requestId<1 or #row.requestId>64 or not row.requestId:match("^[%w_.%-]+$") or requests[row.requestId]
            or not (row.residentId=="owner" or Residents.validId(row.residentId))
            or not integer(row.quantity,1,10) or not integer(row.servingsPerUnit,1,20)
            or row.itemId~=product.item or not integer(row.unitPriceCents,1,1000000)
            or not integer(row.shippingCents,0,1000000) or row.totalCents~=row.quantity*row.unitPriceCents+row.shippingCents
            or not time(row.orderedAt) or not time(row.dueAt) or row.dueAt<row.orderedAt
            or row.dueAt-row.orderedAt>24 or not time(row.budgetCloseHours)
            or (row.status~="transit" and row.status~="waiting" and row.status~="collected") then return false end
        if row.status=="transit" then
            if row.arrivedAt~=nil or row.collectedAt~=nil then return false end
        elseif row.arrivedAt~=row.dueAt or row.status=="waiting" and row.collectedAt~=nil
            or row.status=="collected" and (not time(row.collectedAt) or row.collectedAt<row.dueAt) then return false end
        ids[row.id]=true;requests[row.requestId]=true;count=count+1
    end
    return count==#shop.orders
end
function Shopping.ensure(state)
    local home=state.home
    home.shopping=home.shopping or Shopping.new()
    return home.shopping
end
function Shopping.budget(state)
    local shop=state.home.shopping or Shopping.new()
    local period=state.home.weekend.closesAtHours
    local spent=period>shop.budgetCloseHours and 0 or shop.guestSpentCents
    return shop.guestLimitCents,spent,math.max(0,shop.guestLimitCents-spent)
end
function Shopping.quote(productId,quantity)
    local product=Catalog.PRODUCTS[productId]
    if not product or not integer(quantity,1,10) then return nil end
    return {product=product,subtotalCents=product.priceCents*quantity,shippingCents=product.shippingCents,
        totalCents=product.priceCents*quantity+product.shippingCents,minutes=product.minutes,servings=product.servings*quantity}
end
function Shopping.setLimit(state,player,intent)
    if (player.id or 1)~=1 then return false,"Only the host can change the shared guest food budget." end
    if intent.expectedRevision~=state.home.revision then return false,"Household details changed. Review the current budget." end
    if not integer(intent.limitCents,0,1000000) then return false,"Choose a valid guest food budget." end
    local shop=Shopping.ensure(state)
    if shop.guestLimitCents==intent.limitCents then return false,"That guest budget is already set." end
    shop.guestLimitCents=intent.limitCents;state.home.revision=state.home.revision+1
    return true,"Shared guest food budget saved."
end
function Shopping.order(state,player,intent)
    local quote=Shopping.quote(intent.productId,intent.quantity)
    if not quote or type(intent.requestId)~="string" or #intent.requestId<1 or #intent.requestId>64
        or not intent.requestId:match("^[%w_.%-]+$") then return false,"Choose a listed household product and quantity." end
    local furniture=quote.product.group=="furniture"
    if intent.kind and intent.kind~=(furniture and "home_order_furniture" or "home_order_food") then return false,"Use the matching household catalog." end
    local residentId=Residents.key(player)
    if not Residents.get(state,player) then return false,"Join this household before ordering." end
    if furniture and not require("src.home_furniture").allowed(state,player,"purchase") then return false,"The host has not enabled guest furniture purchases." end
    local shop=Shopping.ensure(state)
    for _,row in ipairs(shop.orders) do
        if row.requestId==intent.requestId then
            if row.productId~=intent.productId or row.quantity~=intent.quantity or row.residentId~=residentId then return false,"That order reference is already in use." end
            return true,"This order is already recorded; no second payment was taken.","replayed"
        end
    end
    if intent.expectedRevision~=state.home.revision then return false,"Household details changed. Review and confirm the order again." end
    if state.home.balanceCents<quote.totalCents then return false,"Not enough household funds. Business cash cannot pay for this order." end
    local _,_,remaining=Shopping.budget(state)
    if not furniture and residentId~="owner" and quote.totalCents>remaining then return false,"This order exceeds the household's remaining shared guest food budget." end
    local pending=0
    for _,row in ipairs(shop.orders) do if row.status~="collected" then pending=pending+1 end end
    if pending>=16 then return false,"Collect some home deliveries before ordering more." end
    local now=Calendar.absoluteHours(state);local product=quote.product
    local row={id=shop.nextOrderId,requestId=intent.requestId,residentId=residentId,productId=intent.productId,
        itemId=product.item,quantity=intent.quantity,servingsPerUnit=product.servings,unitPriceCents=product.priceCents,
        shippingCents=quote.shippingCents,totalCents=quote.totalCents,orderedAt=now,dueAt=now+product.minutes/60,
        status="transit",budgetCloseHours=state.home.weekend.closesAtHours}
    if row.budgetCloseHours>shop.budgetCloseHours then shop.budgetCloseHours=row.budgetCloseHours;shop.guestSpentCents=0 end
    if not furniture and residentId~="owner" then shop.guestSpentCents=shop.guestSpentCents+row.totalCents end
    shop.nextOrderId=shop.nextOrderId+1;shop.orders[#shop.orders+1]=row
    if #shop.orders>128 then
        for i,old in ipairs(shop.orders) do if old.status=="collected" then table.remove(shop.orders,i);break end end
    end
    state.home.balanceCents=state.home.balanceCents-row.totalCents;state.home.revision=state.home.revision+1
    require("src.inbox").addNotice(state,{id="HOME-ORDER-"..row.id,sender="CritterNet Home Delivery",noticeKind="home_order",
        subject="Home order #"..row.id..": "..product.name,total=row.totalCents/100,
        body=string.format("Paid $%.2f from your household account, including $%.2f delivery. %d serving(s)/item(s) "..
            "will arrive at %s, at your apartment. Collect them at the apartment entrance. Orders wait safely if you are away.",
            row.totalCents/100,row.shippingCents/100,quote.servings,Calendar.dateTimeTextAtHours(row.dueAt))})
    return true,"Home order placed. Delivery in "..product.minutes.." game minutes."
end
function Shopping.advance(state)
    if not state.home or not state.home.shopping then return false end
    local now=Calendar.absoluteHours(state);local changed=false
    for _,row in ipairs(state.home.shopping.orders) do
        if row.status=="transit" and now+1e-7>=row.dueAt then
            row.status="waiting";row.arrivedAt=row.dueAt;changed=true
            require("src.inbox").addNotice(state,{id="HOME-ARRIVAL-"..row.id,sender="CritterNet Home Delivery",noticeKind="home_delivery",
                subject="Home order #"..row.id.." has arrived",body="Your order is waiting at your apartment entrance. It will stay there until a resident collects it."})
        end
    end
    if changed then state.home.revision=state.home.revision+1 end
    return changed
end
function Shopping.waiting(state)
    local count=0
    for _,row in ipairs(state.home.shopping and state.home.shopping.orders or {}) do if row.status=="waiting" then count=count+1 end end
    return count
end
function Shopping.target(player,state)
    if not state or not state.home or state.home.weekend.phase~="home" or player.sceneId~="home" or Shopping.waiting(state)==0 then return nil end
    local x,y=require("src.home_layouts").spawn(state,1);x=x+28;y=y+4
    return {kind="homeDelivery",x=x,y=y,radius=42,hoverX=x,hoverY=y-12,hoverRadius=22,
        prompt="E: receive "..Shopping.waiting(state).." home delivery parcel(s)",actionLabel="RECEIVE"}
end
function Shopping.collect(state,player,players)
    local allowed,reason=require('src.commute.outfit').allowed(state,player,'household')
    if not allowed then return false,reason end
    local target=Shopping.target(player,state)
    if not Residents.get(state,player) then return false,"Your resident has not joined this household." end
    if not target then return false,"No home deliveries are ready here." end
    if (player.x-target.x)^2+(player.y-target.y)^2>target.radius^2 then return false,"Walk to the apartment delivery spot first." end
    local additions={};local now=Calendar.absoluteHours(state)
    for _,row in ipairs(state.home.shopping.orders) do
        if row.status=="waiting" then additions[row.itemId]=(additions[row.itemId] or 0)+row.quantity*row.servingsPerUnit end
    end
    for id,count in pairs(additions) do if not require("src.home_cooking").hasRoom(state,id,count) then return false,"Home storage is full or reserved for cooking; the delivery will keep waiting." end end
    local furniture=require("src.home_furniture");local count=#furniture.ensure(state).items
    for id,amount in pairs(additions) do if require("src.home_furniture_catalog").ITEMS[id] then count=count+amount+(state.home.inventory[id] or 0) end end
    if count>128 then return false,"Furniture storage is full; your parcels will keep waiting." end
    local firstNewId=furniture.ensure(state).nextId
    for id,count in pairs(additions) do state.home.inventory[id]=(state.home.inventory[id] or 0)+count end
    furniture.materialize(state,false)
    local deliveredFurniture=furniture.ensure(state).nextId-firstNewId
    local staged=furniture.stageDeliveries(state,firstNewId,players or {player})
    if deliveredFurniture>0 then state.home.furniture.revision=state.home.furniture.revision+1 end
    for _,row in ipairs(state.home.shopping.orders) do if row.status=="waiting" then row.status="collected";row.collectedAt=now end end
    state.home.revision=state.home.revision+1
    local message
    if deliveredFurniture==0 then message="Home deliveries received. Food and household supplies are ready in Home [H]."
    elseif staged==deliveredFurniture then message="Home deliveries received. Furniture is staged in clear living-room spaces; use Furnish [M] to move items into place and connect kitchen appliances."
    elseif staged>0 then message="Home deliveries received. Some furniture is staged in clear spaces; the rest remains in Furnish [M] storage. Move appliances to their kitchen hookups."
    else message="Home deliveries received. There was no clear staging space, so furniture remains in Furnish [M] storage." end
    return true,message
end
return Shopping
