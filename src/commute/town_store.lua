-- Walk-up town stores. Purchases are carried on the buyer's motorcycle until
-- that resident unloads them into shared household storage at the apartment.
local Catalog=require('src.home_shop_catalog')
local Residents=require('src.home_residents')
local BikeCargo=require('src.home_bike_cargo')
local GroceryInventory=require('src.commute.grocery_inventory')
local TownCharacters=require('src.commute.town_characters')
local Calendar=require('src.business_calendar')
local GroceryUiArt=require('src.commute.grocery_ui_art')
local Store={}
local stores={
    grocery={name='TOWN GROCERY',subtitle='Fresh staples and pantry food',group='groceries',items={
        {id='vegetables',priceCents=400},{id='bread',priceCents=300},{id='cereal',priceCents=150},
        {id='sandwich',priceCents=250},{id='drink',priceCents=150},{id='meal',priceCents=500},
        {id='cup',priceCents=250},{id='meal_pack',priceCents=1400},
    }},
    ['general-store']={name='GENERAL STORE',subtitle='Everyday supplies and shelf food',group='groceries',items={
        {id='meal',priceCents=450},{id='meal_pack',priceCents=1850},{id='drink',priceCents=250},
        {id='bread',priceCents=450},{id='vegetables',priceCents=650},{id='cup',priceCents=300},
    }},
    diner={name='TOWN DINER',subtitle='Takeout pickup counter',group='takeout',items={
        {id='pizza',priceCents=1600},{id='chinese',priceCents=1200},
    }},
    ['gas-station']={name='GAS STATION',subtitle='Quick snacks and drinks',group='groceries',items={
        {id='drink',priceCents=250},{id='sandwich',priceCents=450},{id='meal',priceCents=650},
    }},
}
local storeOrder={'grocery','general-store','diner','gas-station'}
local groceryCategories={
    produce={label='PRODUCE',items={'vegetables'}},
    pantry={label='PANTRY',items={'bread','cereal'}},
    chilled={label='CHILLED GOODS',items={'sandwich','drink','meal'}},
    household={label='HOUSEHOLD',items={'cup'}},
    specials={label='DAILY SPECIALS',items={'meal_pack'}},
}
local cartDigits='123456789abcdefghijklmnopqrstuvwxyz0'
local GROCERY_ROW_HEIGHT=40
local function integer(n,low,high)
    return type(n)=='number' and n==n and n%1==0 and n>=low and n<=high
end
local function near(a,b,radius)
    return a and b and (a.x-b.x)^2+(a.z-b.z)^2<=radius^2
end
function Store.products(storeId) return stores[storeId] and stores[storeId].items or {} end
function Store.title(storeId) return stores[storeId] and stores[storeId].name or 'TOWN STORE' end
local function productOffer(storeId,productId)
    for _,offer in ipairs(Store.products(storeId)) do if offer.id==productId then return offer end end
end
function Store.productsFor(view)
    if view.storeId~='grocery' or not view.categoryId or view.categoryId=='checkout' then
        return Store.products(view.storeId)
    end
    local category=groceryCategories[view.categoryId];local result={}
    for _,id in ipairs(category and category.items or {}) do
        local offer=productOffer('grocery',id);if offer then result[#result+1]=offer end
    end
    return result
end
function Store.category(view,categoryId)
    if view.storeId~='grocery' or categoryId~='checkout' and not groceryCategories[categoryId] then return false end
    if categoryId=='checkout' and view.interiorKind=='grocery' then
        if not view.cartPushed then
            view.notice='Take the shopping cart with you before checking out.'
            return false
        end
        if not view.atGroceryRegister then
            view.notice='Bring your shopping cart to the staffed register to check out.'
            return false
        end
    end
    if categoryId~='checkout' then view.lastCategory=categoryId end
    view.page='store';view.categoryId=categoryId;view.selected=1;view.quantity=1
    view.review=nil;view.notice=nil
    return true
end
function Store.cartCount(cart)
    local count=0;for _,quantity in pairs(cart or {}) do count=count+quantity end;return count
end
function Store.cartRoom(bikeInventory)
    return math.max(0,BikeCargo.CAPACITY-BikeCargo.used(bikeInventory))
end
function Store.cartTotal(cart)
    local total=0
    for id,quantity in pairs(cart or {}) do
        local quote=Store.quote('grocery',id,quantity)
        if not quote then return nil end
        total=total+quote.totalCents
    end
    return total
end
function Store.stockCount(view,productId)
    return GroceryInventory.count(view and view.storeStock,productId)
end
function Store.cartAvailability(view,cart)
    for id,quantity in pairs(cart or {}) do
        local available=Store.stockCount(view,id)
        if available<quantity then return false,id,available,quantity end
    end
    return true
end
function Store.encodeCart(cart)
    if type(cart)~='table' or Store.cartCount(cart)>12 then return nil end
    local parts={}
    for index,offer in ipairs(Store.products('grocery')) do
        local quantity=cart and cart[offer.id]
        if quantity and quantity>0 then
            if not integer(quantity,1,10) then return nil end
            parts[#parts+1]=cartDigits:sub(index,index)..cartDigits:sub(quantity,quantity)
        end
    end
    for id,quantity in pairs(cart) do
        if not productOffer('grocery',id) or not integer(quantity,1,10) then return nil end
    end
    if #parts==0 then return nil end
    return table.concat(parts)
end
function Store.decodeCart(payload)
    if type(payload)~='string' or #payload<2 or #payload%2~=0 or #payload>32 then return nil end
    local cart={}
    for offset=1,#payload,2 do
        local index=cartDigits:find(payload:sub(offset,offset),1,true)
        local quantity=cartDigits:find(payload:sub(offset+1,offset+1),1,true)
        local offer=index and Store.products('grocery')[index]
        if not offer or not integer(quantity,1,10) or cart[offer.id] then return nil end
        cart[offer.id]=quantity
    end
    if Store.cartCount(cart)>12 then return nil end
    return cart
end
function Store.counter(rider,world,storeId)
    local store=stores[storeId]
    local site=world and world.sites and world.sites.byId[storeId]
    return store and site and not rider.gear.mounted and not rider.gear.transition
        and rider.vehicle~='truck' and rider.transport~='truck'
        and not rider.ped.crash and near(rider.ped,site.door,2)
end
function Store.nearCounter(rider,world)
    for _,id in ipairs(storeOrder) do
        local site=world and world.sites and world.sites.byId[id]
        if site and near(rider.ped,site.door,3.5) then return id end
    end
end
function Store.bikeNearby(rider,world,storeId)
    local site=world and world.sites and world.sites.byId[storeId]
    return site and near(rider.bike,site.parking,8) or false
end
function Store.quote(storeId,productId,quantity)
    if not integer(quantity,1,10) then return nil end
    local product=Catalog.PRODUCTS[productId]
    local store=stores[storeId]
    if not product or not store or product.group~=store.group then return nil end
    for _,offer in ipairs(Store.products(storeId)) do
        if offer.id==productId then
            return {product=product,unitPriceCents=offer.priceCents,totalCents=offer.priceCents*quantity,
                servings=product.servings*quantity}
        end
    end
end
function Store.purchase(state,player,rider,world,storeId,intent)
    if (storeId=='grocery' or storeId=='gas-station')
        and not TownCharacters.isOpen(state.home,storeId,Calendar.absoluteHours(state)) then
        return false,Store.title(storeId)..' is closed for the night.'
    end
    if not Store.counter(rider,world,storeId) then return false,'Walk up to the store counter on foot first.' end
    local quote=Store.quote(storeId,intent.productId,intent.quantity)
    if not quote then return false,'Choose a product sold at this store and a quantity from 1 to 10.' end
    if storeId=='grocery' then
        local available=GroceryInventory.count(GroceryInventory.ensure(state),intent.productId)
        if available<intent.quantity then
            return false,available>0 and ('Only %d %s in stock right now.'):format(available,quote.product.name)
                or (quote.product.name..' is out of stock right now.')
        end
    end
    if intent.expectedRevision~=state.home.revision then return false,'Household details changed. Review the current price and try again.' end
    local residentId=Residents.key(player)
    local resident=Residents.get(state,player)
    if not resident then return false,'Join this household before shopping.' end
    local bikeInventory=BikeCargo.ensure(resident)
    if BikeCargo.used(bikeInventory)+intent.quantity>BikeCargo.CAPACITY then
        return false,'Bike cargo is full. Unload groceries at your apartment before buying more.'
    end
    local shop=require('src.home_shopping').ensure(state)
    local _,spent,remaining=require('src.home_shopping').budget(state)
    if residentId~='owner' and quote.totalCents>remaining then
        return false,'This purchase exceeds the household\'s remaining shared guest food budget.'
    end
    if state.home.balanceCents<quote.totalCents then return false,'Not enough household funds.' end
    if residentId~='owner' then
        local period=state.home.weekend.closesAtHours
        if period>shop.budgetCloseHours then shop.budgetCloseHours=period;shop.guestSpentCents=0;spent=0 end
        shop.guestSpentCents=spent+quote.totalCents
    end
    if storeId=='grocery' then
        local consumed=GroceryInventory.consume(GroceryInventory.ensure(state),{[intent.productId]=intent.quantity})
        if not consumed then return false,'That item just sold out. Review the grocery shelf again.' end
    end
    state.home.balanceCents=state.home.balanceCents-quote.totalCents
    bikeInventory.items[intent.productId]=(bikeInventory.items[intent.productId] or 0)+intent.quantity
    bikeInventory.revision=bikeInventory.revision+1;resident.revision=resident.revision+1
    state.home.revision=state.home.revision+1
    return true,('%s bought for $%.2f and loaded onto your bike (%d/%d bags).')
        :format(quote.product.name,quote.totalCents/100,BikeCargo.used(bikeInventory),BikeCargo.CAPACITY)
end
function Store.purchaseCart(state,player,rider,world,intent)
    if not TownCharacters.isOpen(state.home,'grocery',Calendar.absoluteHours(state)) then
        return false,'Town Grocery is closed for the night.'
    end
    if not Store.counter(rider,world,'grocery') then return false,'Walk up to the grocery checkout counter first.' end
    if intent.expectedRevision~=state.home.revision then
        return false,'Household details changed. Review the cart total and check out again.'
    end
    if type(intent.cart)~='table' then return false,'Your grocery cart is empty.' end
    local storeStock=GroceryInventory.ensure(state)
    local totalCents,bagCount=0,0
    for id,quantity in pairs(intent.cart) do
        local quote=Store.quote('grocery',id,quantity)
        if not quote or not integer(quantity,1,10) then return false,'The cart contains an item or quantity this store cannot sell.' end
        totalCents=totalCents+quote.totalCents;bagCount=bagCount+quantity
    end
    local supplied,shortId,available=GroceryInventory.canSupply(storeStock,intent.cart)
    if not supplied then
        local product=Catalog.PRODUCTS[shortId]
        return false,available>0 and ('Only %d %s in stock right now. Update your cart before checkout.'):format(available,product.name)
            or (product.name..' is out of stock right now. Remove it from your cart or wait for a delivery.')
    end
    if bagCount<1 or bagCount>12 then return false,'Add between 1 and 12 bags before checking out.' end
    local residentId=Residents.key(player)
    local resident=Residents.get(state,player)
    if not resident then return false,'Join this household before shopping.' end
    local bikeInventory=BikeCargo.ensure(resident)
    if BikeCargo.used(bikeInventory)+bagCount>BikeCargo.CAPACITY then
        return false,'Bike cargo is full. Unload groceries at your apartment before checking out.'
    end
    if state.home.balanceCents<totalCents then return false,'Not enough household funds for this cart.' end
    local shop=require('src.home_shopping').ensure(state)
    local _,spent,remaining=require('src.home_shopping').budget(state)
    if residentId~='owner' and totalCents>remaining then
        return false,'This cart exceeds the household\'s remaining shared guest food budget.'
    end
    if residentId~='owner' then
        local period=state.home.weekend.closesAtHours
        if period>shop.budgetCloseHours then shop.budgetCloseHours=period;shop.guestSpentCents=0;spent=0 end
        shop.guestSpentCents=spent+totalCents
    end
    local consumed=GroceryInventory.consume(GroceryInventory.ensure(state),intent.cart)
    if not consumed then return false,'Some groceries just sold out. Review the cart before paying.' end
    for id,quantity in pairs(intent.cart) do
        bikeInventory.items[id]=(bikeInventory.items[id] or 0)+quantity
    end
    state.home.balanceCents=state.home.balanceCents-totalCents
    bikeInventory.revision=bikeInventory.revision+1;resident.revision=resident.revision+1
    state.home.revision=state.home.revision+1
    return true,('Checkout complete: %d grocery bag(s) for $%.2f, loaded onto your bike (%d/%d bags).')
        :format(bagCount,totalCents/100,BikeCargo.used(bikeInventory),BikeCargo.CAPACITY)
end
function Store.open(storeId,token)
    return {page='store',storeId=storeId,token=token,selected=1,quantity=1,review=nil,notice=nil,
        categoryId=storeId=='grocery' and 'pantry' or nil,cart={}}
end
local function productAt(v,index) return Store.productsFor(v)[index] end
local function cartRows(v)
    local rows={}
    for _,offer in ipairs(Store.products('grocery')) do
        local quantity=v.cart and v.cart[offer.id]
        if quantity and quantity>0 then rows[#rows+1]={offer=offer,quantity=quantity} end
    end
    return rows
end
local function cartAdjust(v,delta)
    local rows=cartRows(v);local selected=math.max(1,math.min(#rows,v.selected or 1));local row=rows[selected]
    if not row then v.notice='Your cart is empty.';return end
    local nextQuantity=row.quantity+delta
    if nextQuantity<=0 then
        v.cart[row.offer.id]=nil;v.selected=math.max(1,math.min(selected,#cartRows(v)))
    elseif nextQuantity<=10 and nextQuantity<=Store.stockCount(v,row.offer.id)
        and Store.cartCount(v.cart)-row.quantity+nextQuantity<=(v.cartCapacity or 12) then
        v.cart[row.offer.id]=nextQuantity
    elseif nextQuantity>Store.stockCount(v,row.offer.id) then
        v.notice=('Only %d %s in stock right now.'):format(Store.stockCount(v,row.offer.id),Catalog.PRODUCTS[row.offer.id].name)
    else v.notice='There is no room for more bags on the bike.' end
end
function Store.key(v,key,revision,buy,close,buyCart)
    if key=='escape' or key=='back' then close();return true end
    if v.pending then return true end
    if v.storeId=='grocery' then
        if v.categoryId=='checkout' then
            local rows=cartRows(v)
            if key=='up' or key=='down' then
                v.selected=math.max(1,math.min(#rows,(v.selected or 1)+(key=='up' and -1 or 1)))
            elseif key=='left' then cartAdjust(v,-1)
            elseif key=='right' then cartAdjust(v,1)
            elseif key=='tab' or key=='c' then Store.category(v,v.lastCategory or 'pantry')
            elseif key=='return' or key=='kpenter' or key=='e' then
                local payload=Store.encodeCart(v.cart)
                if not payload then v.notice='Your cart is empty. Browse a shelf and add something first.'
                elseif not Store.cartAvailability(v,v.cart) then
                    local _,id,available,requested=Store.cartAvailability(v,v.cart)
                    local name=Catalog.PRODUCTS[id].name
                    v.notice=available>0 and ('Only %d %s remain in store; the cart needs %d.'):format(available,name,requested)
                        or (name..' is out of stock. Remove it or wait for delivery.')
                elseif not buyCart then v.notice='Checkout is unavailable right now.'
                else
                    local notice,accepted=buyCart('grocery',v.cart,revision,payload)
                    v.notice=notice
                    if accepted then v.pending={kind='cart',revision=revision,
                        bikeRevision=v.bikeInventoryRevision or 0,elapsed=0} end
                end
            end
            return true
        end
        local products=Store.productsFor(v)
        if v.interiorKind=='grocery' and not v.cartPushed then
            v.notice='Take the shopping cart before adding groceries.'
            return true
        end
        if key=='up' or key=='down' then
            v.selected=math.max(1,math.min(#products,(v.selected or 1)+(key=='up' and -1 or 1)))
            v.notice=nil
        elseif key=='left' or key=='right' then
            v.quantity=math.max(1,math.min(10,(v.quantity or 1)+(key=='left' and -1 or 1)))
            v.notice=nil
        elseif key=='tab' or key=='c' then Store.category(v,'checkout')
        elseif key=='space' or key=='return' or key=='kpenter' or key=='e' then
            local offer=productAt(v,v.selected)
            local already=offer and (v.cart[offer.id] or 0) or 0
            if not offer then v.notice='This shelf is empty.'
            elseif already+v.quantity>10 then v.notice='The cart limit for this item is 10.'
            elseif already+v.quantity>Store.stockCount(v,offer.id) then
                local stock=Store.stockCount(v,offer.id)
                v.notice=stock>0 and ('Only %d %s in stock right now.'):format(stock,Catalog.PRODUCTS[offer.id].name)
                    or (Catalog.PRODUCTS[offer.id].name..' is out of stock. Wait for the next delivery.')
            elseif Store.cartCount(v.cart)+v.quantity>(v.cartCapacity or 12) then
                v.notice='There is no room for that many bags on the bike.'
            else
                v.cart[offer.id]=(v.cart[offer.id] or 0)+v.quantity
                v.notice=('%d × %s added to your cart.'):format(v.quantity,Catalog.PRODUCTS[offer.id].name)
            end
        end
        return true
    end
    if key=='up' or key=='down' then
        v.selected=math.max(1,math.min(#Store.products(v.storeId),v.selected+(key=='up' and -1 or 1)))
        v.review=nil;v.notice=nil
    elseif key=='left' or key=='right' then
        v.quantity=math.max(1,math.min(10,v.quantity+(key=='left' and -1 or 1)))
        v.review=nil;v.notice=nil
    elseif key=='return' or key=='kpenter' or key=='e' then
        local offer=productAt(v,v.selected)
        if not offer then return true end
        if not v.review then
            local quote=Store.quote(v.storeId,offer.id,v.quantity)
            v.review={productId=offer.id,quantity=v.quantity,expectedRevision=revision,
                totalCents=quote.totalCents}
            v.notice=('Buy %d for $%.2f? Confirm again to pay.'):format(v.quantity,quote.totalCents/100)
        elseif v.review.productId~=offer.id or v.review.quantity~=v.quantity
            or v.review.expectedRevision~=revision then
            v.review=nil;v.notice='Household details changed. Review the purchase again.'
        else
            local notice,accepted=buy(v.storeId,v.review.productId,v.review.quantity,v.review.expectedRevision)
            v.notice=notice
            if accepted then v.pending={revision=v.review.expectedRevision,elapsed=0} end
            v.review=nil
        end
    end
    return true
end
local layout={close={x=65,y=566,w=180,h=58},cart={x=274,y=566,w=218,h=58},buy={x=682,y=566,w=212,h=58},
    minus={x=700,y=122,w=42,h=38},plus={x=846,y=122,w=42,h=38},
    groceryMinus={x=606,y=414,w=40,h=34},groceryPlus={x=854,y=414,w=40,h=34}}
local function contains(b,x,y) return x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
function Store.pointer(v,x,y,revision,buy,close,buyCart)
    if y>=566 and y<=634 and x>=65 and x<=245 then close();return true end
    if v.pending then return true end
    if v.storeId=='grocery' then
        if y>=566 and y<=634 and x>=layout.cart.x and x<=layout.cart.x+layout.cart.w then
            if v.categoryId=='checkout' then Store.category(v,v.lastCategory or 'pantry') else Store.category(v,'checkout') end
            return true
        end
        if y>=566 and y<=634 and x>=682 and x<=894 then
            return Store.key(v,v.categoryId=='checkout' and 'return' or 'space',revision,buy,close,buyCart)
        end
        local minus,plus=layout.groceryMinus,layout.groceryPlus
        if contains(minus,x,y) then return Store.key(v,'left',revision,buy,close,buyCart) end
        if contains(plus,x,y) then return Store.key(v,'right',revision,buy,close,buyCart) end
        local rows=v.categoryId=='checkout' and cartRows(v) or Store.productsFor(v)
        if x>=53 and x<=561 and y>=195 and y<195+#rows*GROCERY_ROW_HEIGHT then
            v.selected=math.floor((y-195)/GROCERY_ROW_HEIGHT)+1;v.notice=nil
        end
        return true
    end
    if y>=566 and y<=634 and x>=682 and x<=894 then return Store.key(v,'return',revision,buy,close) end
    if contains(layout.minus,x,y) then return Store.key(v,'left',revision,buy,close) end
    if contains(layout.plus,x,y) then return Store.key(v,'right',revision,buy,close) end
    local products=Store.productsFor(v)
    if x>=65 and x<=575 and y>=174 and y<174+#products*48 then
        v.selected=math.floor((y-174)/48)+1;v.review=nil;v.notice=nil
    end
    return true
end
function Store.update(v,state,dt,bikeInventory)
    v.storeStock=state.groceryStore or GroceryInventory.defaultState()
    v.calendarDay=state.calendar and state.calendar.totalDays or 0
    v.calendarWeekday=state.calendar and state.calendar.weekday or 1
    if v.review and v.review.expectedRevision~=state.home.revision then
        v.review=nil;v.notice='Household details changed. Review the current price again.'
    end
    if v.pending then
        v.pending.elapsed=v.pending.elapsed+math.max(0,dt or 0)
        if state.home.revision>v.pending.revision then
            local wasCart=v.pending.kind=='cart'
            local completed=not wasCart or bikeInventory
                and (bikeInventory.revision or 0)>=(v.pending.bikeRevision or 0)+1
            v.pending=nil
            if wasCart and completed then v.cart={};v.selected=1 end
            v.notice=wasCart and (completed and (state.message or 'Checkout complete.')
                or 'Household changed. Your cart is still here; review the total before checking out again.')
                or state.message or 'Household updated. Check your storage and balance.'
        elseif v.pending.elapsed>=6 then
            v.pending=nil;v.notice='No household update received. Review the price and retry.'
        end
    end
end
local function drawButton(g,b,text,enabled,primary)
    local fill=primary and {.25,.43,.26} or {.15,.25,.19}
    local edge=primary and {.94,.73,.39} or {.62,.73,.57}
    if not enabled then fill={.10,.15,.12};edge={.32,.39,.33} end
    g.setColor(.025,.055,.035,.58);g.rectangle('fill',b.x,b.y+3,b.w,b.h,8)
    g.setColor(fill[1],fill[2],fill[3],1);g.rectangle('fill',b.x,b.y,b.w,b.h-3,8)
    g.setColor(edge[1],edge[2],edge[3],1);g.rectangle('line',b.x,b.y,b.w,b.h-3,8)
    g.setColor(enabled and 1 or .48,enabled and .94 or .53,enabled and .75 or .48,1)
    g.setFont(Fonts.get('metal',11));g.printf(text,b.x+8,b.y+14,b.w-16,'center')
end
local function drawGrocery(v,balanceCents,bikeInventory,revision,width,height)
    v.bikeInventoryRevision=bikeInventory and bikeInventory.revision or 0
    v.cartCapacity=Store.cartRoom(bikeInventory)
    local g=love.graphics;local rows=v.categoryId=='checkout' and cartRows(v) or Store.productsFor(v)
    local count=Store.cartCount(v.cart);local total=Store.cartTotal(v.cart) or 0
    local selected=rows[v.selected or 1]
    g.push('all');g.scale(width/960,height/678)
    g.setColor(.008,.018,.013,.76);g.rectangle('fill',0,0,960,678)
    g.setColor(.055,.09,.064,1);g.rectangle('fill',26,22,908,634,16)
    g.setColor(.73,.63,.40,1);g.setLineWidth(2);g.rectangle('line',26,22,908,634,16)
    g.setColor(.10,.22,.15,1);g.rectangle('fill',40,34,880,112,10)
    local awning={{.80,.31,.22,1},{.97,.88,.68,1},{.34,.49,.30,1},{.97,.88,.68,1}}
    local stripeWidth=880/16
    for stripe=0,15 do
        g.setColor(unpack(awning[stripe%#awning+1]))
        local x=40+stripe*stripeWidth
        g.rectangle('fill',x,34,stripeWidth+1,12)
        g.circle('fill',x+stripeWidth/2,46,6)
    end
    g.setColor(.89,.75,.45,1);g.rectangle('fill',40,51,880,2)
    GroceryUiArt.drawEmblem(91,98,83)
    local title=v.categoryId=='checkout' and 'REGISTER CHECKOUT'
        or groceryCategories[v.categoryId] and groceryCategories[v.categoryId].label or 'GROCERY AISLE'
    g.setColor(1,.88,.61,1);g.setFont(Fonts.get('metal',21));g.print('TOWN GROCERY',140,61)
    g.setColor(.99,.96,.85,1);g.setFont(Fonts.get('metal',14));g.print(title,140,92)
    g.setColor(.70,.83,.68,1);g.setFont(Fonts.get('metal',10))
    g.print(v.categoryId=='checkout' and 'A friendly checkout, staffed by our store cat'
        or 'Fresh finds for your neighborhood kitchen',140,119)
    local used=BikeCargo.used(bikeInventory)
    local chips={
        {x=492,w=126,caption='HOUSEHOLD',value=('$%.2f'):format(balanceCents/100),color={.99,.86,.57,1}},
        {x=625,w=126,caption='BIKE BAGS',value=('%d / %d'):format(used,BikeCargo.CAPACITY),color={.80,.90,.72,1}},
        {x=758,w=150,caption='SHOPPING CART',value=('%d  ·  $%.2f'):format(count,total/100),color={1,.82,.53,1}},
    }
    for _,chip in ipairs(chips) do
        g.setColor(.045,.12,.078,1);g.rectangle('fill',chip.x,63,chip.w,53,7)
        g.setColor(.27,.40,.28,1);g.rectangle('line',chip.x,63,chip.w,53,7)
        g.setColor(.64,.77,.64,1);g.setFont(Fonts.get('metal',8));g.printf(chip.caption,chip.x+8,71,chip.w-16,'left')
        g.setColor(unpack(chip.color));g.setFont(Fonts.get('metal',13));g.printf(chip.value,chip.x+8,88,chip.w-16,'left')
    end
    local daysToDelivery=math.max(0,(v.storeStock and v.storeStock.nextDeliveryDay or 0)-(v.calendarDay or 0))
    local deliveryText=daysToDelivery==0 and ((v.calendarWeekday or 1)>=6 and 'next weekday' or 'due today')
        or ('in '..daysToDelivery..' day(s)')
    g.setColor(.88,.84,.66,1);g.rectangle('fill',46,153,868,27,6)
    g.setColor(.36,.51,.36,1);g.circle('fill',61,166,5)
    g.setColor(.13,.25,.17,1);g.setFont(Fonts.get('metal',9))
    g.print(v.categoryId=='checkout' and 'REGISTER OPEN  ·  Review your basket before paying'
        or ('FRESH STOCK DELIVERY  ·  '..deliveryText),75,160)
    g.setColor(.085,.14,.096,1);g.rectangle('fill',46,188,522,326,9)
    g.setColor(.25,.36,.25,1);g.rectangle('line',46,188,522,326,9)
    g.setColor(.91,.84,.66,1);g.rectangle('fill',578,188,336,326,9)
    g.setColor(.69,.59,.38,1);g.rectangle('line',578,188,336,326,9)
    for i,row in ipairs(rows) do
        local offer=v.categoryId=='checkout' and row.offer or row
        local quantity=v.categoryId=='checkout' and row.quantity or 1
        local product=Catalog.PRODUCTS[offer.id];local y=195+(i-1)*GROCERY_ROW_HEIGHT
        if i==v.selected then
            g.setColor(.27,.40,.27,1);g.rectangle('fill',53,y,508,GROCERY_ROW_HEIGHT-2,6)
            g.setColor(.96,.75,.40,1);g.rectangle('fill',53,y+5,3,GROCERY_ROW_HEIGHT-12,2)
        else
            g.setColor(.12,.20,.14,1);g.rectangle('fill',53,y,508,GROCERY_ROW_HEIGHT-2,6)
        end
        g.setColor(.87,.82,.66,1);g.rectangle('fill',59,y+3,35,35,7)
        GroceryUiArt.drawProduct(offer.id,76.5,y+20,35)
        g.setColor(.98,.95,.82,1);g.setFont(Fonts.get('metal',11))
        g.print(product.name,103,y+4)
        local stored=bikeInventory and bikeInventory.items[offer.id] or 0
        local inStock=Store.stockCount(v,offer.id)
        local detail=v.categoryId=='checkout' and ('In cart: %d  /  on bike: %d'):format(quantity,stored)
            or ('Stock: %d  /  %d serving(s)/item  /  on bike: %d'):format(inStock,product.servings,stored)
        if v.categoryId=='checkout' then detail=detail..('  /  store: %d'):format(inStock) end
        if inStock==0 then detail='OUT OF STOCK  /  '..detail end
        g.setColor(inStock==0 and 1 or .69,inStock==0 and .52 or .77,inStock==0 and .42 or .69,1)
        g.setFont(Fonts.get('metal',8));g.print(detail,103,y+22)
        g.setColor(.98,.87,.60,1);g.setFont(Fonts.get('metal',10))
        g.printf(('$%.2f'):format(offer.priceCents/100),450,y+13,101,'right')
    end
    g.setColor(.18,.30,.20,1);g.setFont(Fonts.get('metal',9))
    g.print(v.categoryId=='checkout' and 'IN YOUR BASKET' or 'FRESH PICKS',594,199)
    if selected then
        local offer=v.categoryId=='checkout' and selected.offer or selected
        local product=Catalog.PRODUCTS[offer.id]
        g.setColor(.98,.93,.80,1);g.rectangle('fill',681,205,130,112,10)
        g.setColor(.82,.73,.53,1);g.rectangle('line',681,205,130,112,10)
        GroceryUiArt.drawProduct(offer.id,746,261,104)
        g.setColor(.14,.25,.17,1);g.setFont(Fonts.get('metal',15))
        g.printf(product.name,594,326,304,'center')
        g.setColor(.30,.39,.28,1);g.setFont(Fonts.get('metal',9))
        local descriptor=product.description or ('A lovely grocery pick with %d serving(s) per item.'):format(product.servings)
        g.printf(descriptor,602,349,288,'center')
        g.setColor(.20,.33,.22,1);g.setFont(Fonts.get('metal',9))
        local inStock=Store.stockCount(v,offer.id)
        local stored=bikeInventory and bikeInventory.items[offer.id] or 0
        g.printf(('IN STORE  %d   ·   ON BIKE  %d'):format(inStock,stored),594,391,304,'center')
        if v.categoryId=='checkout' then
            g.setColor(.20,.33,.22,1);g.setFont(Fonts.get('metal',10))
            g.printf(('QUANTITY IN CART  %d'):format(selected.quantity),594,414,304,'center')
            g.setColor(.38,.46,.32,1);g.setFont(Fonts.get('metal',8))
            g.printf('Left: remove one  ·  Right: add one',594,433,304,'center')
            local canPay,shortId,available,requested=Store.cartAvailability(v,v.cart)
            if not canPay then
                local shortName=Catalog.PRODUCTS[shortId].name
                g.setColor(.68,.24,.16,1);g.setFont(Fonts.get('metal',8))
                g.printf(available>0 and ('Only %d %s left; cart needs %d.'):format(available,shortName,requested)
                    or (shortName..' is out of stock. Remove it to check out.'),596,449,300,'center')
            elseif v.storeStock and v.storeStock.lastDeliveryNote then
                g.setColor(.30,.43,.29,1);g.setFont(Fonts.get('metal',8))
                g.printf(v.storeStock.lastDeliveryNote,596,449,300,'center')
            end
            g.setColor(.22,.33,.26,1)
            g.rectangle('fill',layout.groceryMinus.x,layout.groceryMinus.y,layout.groceryMinus.w,layout.groceryMinus.h,6)
            g.rectangle('fill',layout.groceryPlus.x,layout.groceryPlus.y,layout.groceryPlus.w,layout.groceryPlus.h,6)
            g.setColor(1,.92,.72,1);g.setFont(Fonts.get('metal',14))
            g.printf('−',layout.groceryMinus.x,layout.groceryMinus.y+7,layout.groceryMinus.w,'center')
            g.printf('+',layout.groceryPlus.x,layout.groceryPlus.y+7,layout.groceryPlus.w,'center')
        else
            local quote=Store.quote('grocery',offer.id,v.quantity or 1)
            g.setColor(.20,.33,.22,1);g.setFont(Fonts.get('metal',10))
            g.printf(('QUANTITY  %d'):format(v.quantity or 1),594,414,304,'center')
            g.setColor(.22,.33,.26,1)
            g.rectangle('fill',layout.groceryMinus.x,layout.groceryMinus.y,layout.groceryMinus.w,layout.groceryMinus.h,6)
            g.rectangle('fill',layout.groceryPlus.x,layout.groceryPlus.y,layout.groceryPlus.w,layout.groceryPlus.h,6)
            g.setColor(1,.92,.72,1);g.setFont(Fonts.get('metal',14))
            g.printf('−',layout.groceryMinus.x,layout.groceryMinus.y+7,layout.groceryMinus.w,'center')
            g.printf('+',layout.groceryPlus.x,layout.groceryPlus.y+7,layout.groceryPlus.w,'center')
            g.setColor(.66,.25,.16,1);g.setFont(Fonts.get('metal',11))
            g.printf(('ITEM TOTAL  $%.2f'):format(quote.totalCents/100),594,448,304,'center')
        end
    elseif v.categoryId=='checkout' then
        GroceryUiArt.drawEmblem(746,302,126)
        g.setColor(.24,.34,.23,1);g.setFont(Fonts.get('metal',10))
        g.printf('Your basket is waiting for its first good find.',602,393,288,'center')
    else
        GroceryUiArt.drawEmblem(746,302,126)
        g.setColor(.24,.34,.23,1);g.setFont(Fonts.get('metal',10))
        g.printf('Choose a fresh find from the shelf.',602,393,288,'center')
    end
    g.setColor(.055,.12,.08,1);g.rectangle('fill',46,520,868,32,6)
    g.setColor(.89,.82,.63,1);g.setFont(Fonts.get('metal',9))
    local hint=v.pending and 'Waiting for the host to confirm checkout…' or v.notice
        or v.categoryId=='checkout' and 'Select a cart line to change its quantity. Press Enter or Pay Now to finish.'
        or 'Choose an item, set quantity, then press Enter or Add to Cart.'
    g.printf(hint,62,529,836)
    drawButton(g,layout.close,'Back to floor',not v.pending,false)
    local canOpenCheckout=v.interiorKind~='grocery' or v.cartPushed and v.atGroceryRegister
    drawButton(g,layout.cart,v.categoryId=='checkout' and 'Continue shopping' or ('View cart ('..count..')'),
        not v.pending and (v.categoryId=='checkout' or canOpenCheckout),false)
    local cartCanPay=Store.cartAvailability(v,v.cart)
    local selectedOffer=v.categoryId=='checkout' and selected and selected.offer or selected
    local selectedInStock=selectedOffer and (v.cart[selectedOffer.id] or 0)+(v.quantity or 1)<=Store.stockCount(v,selectedOffer.id)
    drawButton(g,layout.buy,v.categoryId=='checkout' and (count>0 and 'Pay now' or 'Cart is empty') or 'Add to cart',
        not v.pending and (v.categoryId~='checkout' and selectedInStock or count>0 and cartCanPay),true)
    g.pop();return true
end
function Store.draw(v,balanceCents,bikeInventory,revision,width,height,closeLabel,storeStock,calendarDay,calendarWeekday)
    if storeStock then v.storeStock=storeStock end
    if calendarDay~=nil then v.calendarDay=calendarDay end
    if calendarWeekday~=nil then v.calendarWeekday=calendarWeekday end
    if v.storeId=='grocery' then return drawGrocery(v,balanceCents,bikeInventory,revision,width,height) end
    local g=love.graphics;local products=Store.products(v.storeId)
    g.push('all');g.scale(width/960,height/678)
    g.setColor(0,0,0,.72);g.rectangle('fill',0,0,960,678)
    g.setColor(.035,.065,.06,1);g.rectangle('fill',36,38,888,600,10)
    local subtitle=v.storeId=='grocery' and 'INSIDE CHECKOUT' or 'WALK-UP MARKET'
    g.setColor(.96,.9,.7);g.print(Store.title(v.storeId)..'  /  '..subtitle,70,65,0,1.4)
    g.setColor(.79,.84,.76);g.print(stores[v.storeId].subtitle,70,105)
    g.print(('Household $%.2f'):format(balanceCents/100),620,105)
    local used=BikeCargo.used(bikeInventory)
    g.print(('Bike cargo %d / %d bags'):format(used,BikeCargo.CAPACITY),775,105)
    for i,offer in ipairs(products) do
        local product=Catalog.PRODUCTS[offer.id];local y=174+(i-1)*48
        local stored=bikeInventory and bikeInventory.items[offer.id] or 0
        g.setColor(i==v.selected and .24 or .09,i==v.selected and .31 or .17,.21,1)
        g.rectangle('fill',65,y,510,43,4)
        g.setColor(.98,.95,.82,1)
        g.print(product.name,80,y+8)
        g.setColor(.69,.77,.69,1)
        g.print(('%d serving(s)/item, on bike: %d'):format(product.servings,stored),80,y+25)
        g.setColor(.98,.95,.82,1);g.printf(('$%.2f each'):format(offer.priceCents/100),428,y+14,132,'right')
    end
    local offer=productAt(v,v.selected);local quote=offer and Store.quote(v.storeId,offer.id,v.quantity)
    if quote then
        local product=quote.product
        g.setColor(.94,.9,.77,1)
        g.printf(product.name..'\n'..product.servings..' serving(s)/item\nNo delivery fee at the store.\nHome computer orders include delivery; takeout has its own menu and fee.',610,174,280)
        g.print(('QUANTITY  %d'):format(v.quantity),610,335)
        g.setColor(.22,.33,.26,1);g.rectangle('fill',layout.minus.x,layout.minus.y,layout.minus.w,layout.minus.h,4);g.rectangle('fill',layout.plus.x,layout.plus.y,layout.plus.w,layout.plus.h,4)
        g.setColor(1,.92,.72,1);g.printf('−',layout.minus.x,layout.minus.y+8,layout.minus.w,'center');g.printf('+',layout.plus.x,layout.plus.y+8,layout.plus.w,'center')
        g.print(('TOTAL  $%.2f'):format(quote.totalCents/100),610,384)
    end
    g.setColor(.94,.9,.77,1);g.printf(v.pending and 'Waiting for the host to confirm the purchase…' or v.notice or ('Use ↑/↓ to choose, ←/→ for quantity, Enter to review. Household revision '..revision..'.'),70,510,810)
    g.setColor(.22,.33,.26,1);g.rectangle('fill',layout.close.x,layout.close.y,layout.close.w,layout.close.h,4);g.rectangle('fill',layout.buy.x,layout.buy.y,layout.buy.w,layout.buy.h,4)
    g.setColor(1,.92,.72,1);g.print(closeLabel or 'Leave store',95,586);g.print(v.review and 'Confirm purchase' or 'Review purchase',711,586)
    g.pop();return true
end
return Store
