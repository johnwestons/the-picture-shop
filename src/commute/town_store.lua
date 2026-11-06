-- Walk-up town stores. Purchases are carried on the buyer's motorcycle until
-- that resident unloads them into shared household storage at the apartment.
local Catalog=require('src.home_shop_catalog')
local Residents=require('src.home_residents')
local BikeCargo=require('src.home_bike_cargo')
local Store={}
local stores={
    grocery={name='TOWN GROCERY',subtitle='Fresh staples and pantry food',group='groceries',items={
        {id='meal_pack',priceCents=1400},{id='sandwich',priceCents=250},{id='cereal',priceCents=150},
        {id='drink',priceCents=150},{id='bread',priceCents=300},{id='vegetables',priceCents=400},
    }},
    ['general-store']={name='GENERAL STORE',subtitle='Everyday supplies and shelf food',group='groceries',items={
        {id='meal',priceCents=450},{id='meal_pack',priceCents=1850},{id='drink',priceCents=250},
        {id='bread',priceCents=450},{id='vegetables',priceCents=650},{id='cup',priceCents=300},
    }},
    diner={name='TOWN DINER',subtitle='Takeout pickup counter',group='takeout',items={
        {id='pizza',priceCents=1600},{id='chinese',priceCents=1200},
    }},
}
local storeOrder={'grocery','general-store','diner'}
local function integer(n,low,high)
    return type(n)=='number' and n==n and n%1==0 and n>=low and n<=high
end
local function near(a,b,radius)
    return a and b and (a.x-b.x)^2+(a.z-b.z)^2<=radius^2
end
function Store.products(storeId) return stores[storeId] and stores[storeId].items or {} end
function Store.title(storeId) return stores[storeId] and stores[storeId].name or 'TOWN STORE' end
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
    if not Store.counter(rider,world,storeId) then return false,'Walk up to the store counter on foot first.' end
    local quote=Store.quote(storeId,intent.productId,intent.quantity)
    if not quote then return false,'Choose a product sold at this store and a quantity from 1 to 10.' end
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
    state.home.balanceCents=state.home.balanceCents-quote.totalCents
    bikeInventory.items[intent.productId]=(bikeInventory.items[intent.productId] or 0)+intent.quantity
    bikeInventory.revision=bikeInventory.revision+1;resident.revision=resident.revision+1
    state.home.revision=state.home.revision+1
    return true,('%s bought for $%.2f and loaded onto your bike (%d/%d bags).')
        :format(quote.product.name,quote.totalCents/100,BikeCargo.used(bikeInventory),BikeCargo.CAPACITY)
end
function Store.open(storeId,token)
    return {page='store',storeId=storeId,token=token,selected=1,quantity=1,review=nil,notice=nil}
end
local function productAt(v,index) return Store.products(v.storeId)[index] end
function Store.key(v,key,revision,buy,close)
    if key=='escape' or key=='back' then close();return true end
    if v.pending then return true end
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
local layout={close={x=65,y=566,w=180,h=58},buy={x=682,y=566,w=212,h=58},minus={x=700,y=122,w=42,h=38},plus={x=846,y=122,w=42,h=38}}
local function contains(b,x,y) return x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
function Store.pointer(v,x,y,revision,buy,close)
    if y>=566 and y<=634 and x>=65 and x<=245 then close();return true end
    if v.pending then return true end
    if y>=566 and y<=634 and x>=682 and x<=894 then return Store.key(v,'return',revision,buy,close) end
    if contains(layout.minus,x,y) then return Store.key(v,'left',revision,buy,close) end
    if contains(layout.plus,x,y) then return Store.key(v,'right',revision,buy,close) end
    local products=Store.products(v.storeId)
    if x>=65 and x<=575 and y>=174 and y<174+#products*48 then
        v.selected=math.floor((y-174)/48)+1;v.review=nil;v.notice=nil
    end
    return true
end
function Store.update(v,state,dt)
    if v.review and v.review.expectedRevision~=state.home.revision then
        v.review=nil;v.notice='Household details changed. Review the current price again.'
    end
    if v.pending then
        v.pending.elapsed=v.pending.elapsed+math.max(0,dt or 0)
        if state.home.revision>v.pending.revision then
            v.pending=nil;v.notice=state.message or 'Household updated. Check your storage and balance.'
        elseif v.pending.elapsed>=6 then
            v.pending=nil;v.notice='No household update received. Review the price and retry.'
        end
    end
end
function Store.draw(v,balanceCents,bikeInventory,revision,width,height,closeLabel)
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
