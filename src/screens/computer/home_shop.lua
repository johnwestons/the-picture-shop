local Catalog=require("src.home_shop_catalog")
local Shopping=require("src.home_shopping")
local Art=require("src.home_food_art")
local Calendar=require("src.business_calendar")
local Component={}
local function productArt(productId,product,x,y,size)
    if product.furnitureId then require("src.home_furniture_art").icon(product.furnitureId,x,y,size)
    elseif product.group=="groceries" then require("src.commute.grocery_ui_art").drawProduct(productId,x,y,size)
    else Art.draw(product.sprite,x,y,size) end
end
local buttons={previous={x=104,y=554,width=125,height=44},next={x=244,y=554,width=125,height=44},
    orders={x=390,y=554,width=190,height=44},groceries={x=104,y=554,width=180,height=44},
    minus={x=544,y=554,width=48,height=44},plus={x=790,y=554,width=48,height=44},
    cancel={x=104,y=540,width=220,height=44},confirm={x=608,y=540,width=230,height=44},
    quantityMinus={x=548,y=396,width=48,height=44},quantityPlus={x=790,y=396,width=48,height=44}}
function Component.install(Runtime)
    local page,confirmation,sequence,lastTab=1,nil,0,nil
    local function syncTab()
        if lastTab~=Runtime.ComputerScreen.tab then page=1;confirmation=nil;lastTab=Runtime.ComputerScreen.tab end
    end
    local function recorded(state)
        if not confirmation then return false end
        for _,row in ipairs(state.home.shopping and state.home.shopping.orders or {}) do
            if row.requestId==confirmation.requestId then return row end
        end
        return false
    end
    function Runtime.ComputerScreen.homeShopControlCenter(name,index)
        local r=name=="buy" and {x=706,y=298+((index or 1)-1)*58,width=132,height=44} or buttons[name]
        return r.x+r.width/2,r.y+r.height/2
    end
    local function products(group)
        local result={};for _,id in ipairs(Catalog.ORDER) do if Catalog.PRODUCTS[id].group==group then result[#result+1]=id end end;return result
    end
    local function usesTwelveHourTime()
        return Runtime.twelveHourTime()
    end
    local function send(state,intent)
        if Runtime.dependencies.remoteCommand then return Runtime.remoteAction(intent.kind,intent) end
        local ok,message,code
        if Runtime.dependencies.warehouseCommand then ok,code,message=Runtime.dependencies.warehouseCommand(intent)
        else ok,message=require("src.home").command(state,intent,nil,usesTwelveHourTime()) end
        state.message=message or "Household action unavailable."
        return {action=ok and "home_changed" or "blocked"}
    end
    function Runtime.homeShopMousepressed(state,x,y)
        syncTab()
        if confirmation then
            if Runtime.contains(buttons.cancel,x,y) then confirmation=nil;return {action="home_view"} end
            if recorded(state) then return {action="home_view"} end
            if Runtime.contains(buttons.quantityMinus,x,y) and not confirmation.requestId then confirmation.quantity=math.max(1,confirmation.quantity-1)
            elseif Runtime.contains(buttons.quantityPlus,x,y) and not confirmation.requestId then confirmation.quantity=math.min(10,confirmation.quantity+1)
            elseif Runtime.contains(buttons.confirm,x,y) then
                if not confirmation.requestId then sequence=sequence+1;confirmation.requestId=Runtime.nextFinanceRequestId(sequence) end
                return send(state,{kind=Catalog.PRODUCTS[confirmation.productId].furnitureId and "home_order_furniture" or "home_order_food",productId=confirmation.productId,quantity=confirmation.quantity,
                    requestId=confirmation.requestId,expectedRevision=state.home.revision})
            end
            return {action="home_view"}
        end
        if Runtime.ComputerScreen.tab=="home_orders" then
            if Runtime.contains(buttons.groceries,x,y) then Runtime.ComputerScreen.tab="groceries";page=1;return {action="home_view"} end
            local limit=Shopping.budget(state)
            local intent
            if Runtime.contains(buttons.minus,x,y) then intent=math.max(0,limit-500)
            elseif Runtime.contains(buttons.plus,x,y) then intent=math.min(1000000,limit+500) end
            if intent then
                if Runtime.ComputerScreen.radioReadOnly() then state.message="Only the host changes the shared guest budget.";return {action="blocked"} end
                return send(state,{kind="home_set_food_limit",limitCents=intent,expectedRevision=state.home.revision})
            end
            if x>=750 and x<=838 and y>=250 and y<=294 then page=page+1;return {action="home_view"} end
            return nil
        end
        local list=products(Runtime.ComputerScreen.tab)
        if Runtime.contains(buttons.previous,x,y) then page=math.max(1,page-1);return {action="home_view"} end
        if Runtime.contains(buttons.next,x,y) then page=math.min(math.ceil(#list/4),page+1);return {action="home_view"} end
        if Runtime.contains(buttons.orders,x,y) then Runtime.ComputerScreen.tab="home_orders";page=1;return {action="home_view"} end
        for i=1,4 do
            if x>=706 and x<=838 and y>=298+(i-1)*58 and y<=342+(i-1)*58 then
                local id=list[(page-1)*4+i]
                if id then confirmation={productId=id,quantity=1};return {action="home_view"} end
            end
        end
        return nil
    end
    function Runtime.drawHomeShop(state,px,py)
        syncTab()
        local home=state.home;local shop=home.shopping or Shopping.new()
        local twelveHourTime=usesTwelveHourTime()
        Runtime.panel({x=82,y=190,width=792,height=424},{.045,.08,.10,1},{.28,.50,.49,1})
        local function text(value,x,y,width,color)
            love.graphics.setColor(unpack(color or {.86,.93,.89,1}));love.graphics.printf(value,x,y,width,"left")
        end
        local function button(rect,label,enabled)
            Runtime.drawComputerButton(rect,label,enabled==false and "disabled" or (px and Runtime.contains(rect,px,py) and "primaryHover" or "primary"))
        end
        local address=require("src.home_catalog").APARTMENTS[home.apartmentId].name
        if confirmation then
            local q=Shopping.quote(confirmation.productId,confirmation.quantity)
            local ordered=recorded(state)
            if ordered then
                q.subtotalCents=ordered.unitPriceCents*ordered.quantity
                q.shippingCents,q.totalCents=ordered.shippingCents,ordered.totalCents
            end
            text("HOUSEHOLD CHECKOUT",104,208,700,{1,.86,.41,1})
            productArt(confirmation.productId,q.product,248,352,190)
            text(q.product.name,414,252,424)
            text(string.format("%d serving(s)/item(s)\nItems: $%.2f   Delivery: $%.2f\nTOTAL FROM HOUSEHOLD: $%.2f",
                q.servings,q.subtotalCents/100,q.shippingCents/100,q.totalCents/100),414,282,424)
            if q.product.furnitureId then
                local small=require("src.home_furniture_catalog").ITEMS[q.product.furnitureId].small
                text(q.product.dimensions.." · 8 directions"..(small and "" or " · clear floor required"),414,331,424)
            end
            text("Deliver to: "..address.."\nArrival: "..Calendar.dateTimeTextAtHours(ordered and ordered.dueAt or Calendar.absoluteHours(state)+q.minutes/60,twelveHourTime),414,350,424)
            text("Quantity: "..confirmation.quantity,614,410,160)
            button(buttons.quantityMinus,"-",not confirmation.requestId and confirmation.quantity>1);button(buttons.quantityPlus,"+",not confirmation.requestId and confirmation.quantity<10)
            local _,_,remaining=Shopping.budget(state)
            text(q.product.furnitureId and string.format("Household funds $%.2f  |  Guest furniture buying: %s",home.balanceCents/100,
                home.furniture.permissions.purchase and "enabled by host" or "disabled")
                or string.format("Household funds $%.2f  |  Shared guest budget remaining $%.2f",home.balanceCents/100,remaining/100),104,465,730)
            text(ordered and "Order recorded. See Home deliveries for its saved arrival time."
                or ("Delivery: %d%% of items, $%.2f minimum. Parcels wait at your apartment entrance."):format(
                    Shopping.DELIVERY_PERCENT,Shopping.MINIMUM_DELIVERY_CENTS/100),104,494,730)
            button(buttons.cancel,ordered and "DONE" or "BACK",true)
            button(buttons.confirm,ordered and "ORDER RECORDED" or "CONFIRM ORDER",not ordered and home.balanceCents>=q.totalCents)
            return
        end
        if Runtime.ComputerScreen.tab=="home_orders" then
            local count=#shop.orders;local pages=math.max(1,math.ceil(count/6));page=(page-1)%pages+1
            text("HOME DELIVERIES / "..address,104,208,730,{1,.86,.41,1})
            text("Collect ready parcels at your apartment entrance.",104,240,620)
            button({x=750,y=250,width=88,height=44},page.."/"..pages.." >",pages>1)
            for i=1,6 do
                local row=shop.orders[count-(page-1)*6-i+1]
                if row then
                    local y=298+(i-1)*33;local product=Catalog.PRODUCTS[row.productId]
                    text("#"..row.id.."  "..product.name.." x"..row.quantity,104,y,340)
                    text(row.status=="transit" and Calendar.dateTimeTextAtHours(row.dueAt,twelveHourTime)
                        or row.status=="waiting" and "AT APARTMENT DOOR" or "RECEIVED",458,y,380)
                end
            end
            if count==0 then text("No orders yet. Affordable ready meals need no stove or fridge.",104,322,700) end
            local limit,spent,remaining=Shopping.budget(state)
            text(string.format("Guests combined: $%.2f spent / $%.2f this shop week. $%.2f remains.",spent/100,limit/100,remaining/100),104,511,730)
            button(buttons.groceries,"GROCERIES",true)
            button(buttons.minus,"-",not Runtime.ComputerScreen.radioReadOnly() and limit>0)
            text("Guest limit $"..string.format("%.2f",limit/100),606,567,180)
            button(buttons.plus,"+",not Runtime.ComputerScreen.radioReadOnly() and limit<1000000)
            return
        end
        local group=Runtime.ComputerScreen.tab;local list=products(group);page=math.max(1,math.min(page,math.ceil(#list/4)))
        text(group=="furniture" and "CRITTERNET HOME & LIVING" or group=="takeout" and "CRITTERNET TAKEOUT" or "CRITTERNET GROCERIES",104,208,500,{1,.86,.41,1})
        text(string.format("Household funds: $%.2f  |  Deliver to: %s",home.balanceCents/100,address),104,239,730)
        text(("Delivery: %d%% of items, $%.2f minimum. Review before paying."):format(
            Shopping.DELIVERY_PERCENT,Shopping.MINIMUM_DELIVERY_CENTS/100),104,267,730)
        for i=1,4 do
            local id=list[(page-1)*4+i];local p=id and Catalog.PRODUCTS[id]
            if p then
                local y=298+(i-1)*58
                productArt(id,p,128,y+22,52)
                text(p.name,166,y+2,365)
                text(p.furnitureId and p.dimensions.." · 8 directions · "..p.minutes.." game min" or p.servings.." serving(s)/item(s) · "..p.minutes.." game min delivery",166,y+24,440,{.62,.78,.76,1})
                text(string.format("$%.2f",p.priceCents/100),602,y+13,90)
                button({x=706,y=y,width=132,height=44},"REVIEW",true)
            end
        end
        button(buttons.previous,"PREVIOUS",page>1);button(buttons.next,"NEXT",page*4<#list)
        button(buttons.orders,"HOME DELIVERIES",true)
    end
end
return Component
