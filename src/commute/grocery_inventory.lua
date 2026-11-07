-- Persistent town-grocery stock and weekday deliveries from the outside
-- connection. Store stock is separate from food carried by household members.
local Inventory={VERSION=1,MAX_STOCK=24,DELIVERY_INTERVAL_DAYS=3}
Inventory.PRODUCTS={'vegetables','bread','cereal','sandwich','drink','meal','cup','meal_pack'}
local initial={vegetables=8,bread=10,cereal=6,sandwich=4,drink=12,meal=5,cup=4,meal_pack=2}

function Inventory.defaultState()
    local stock={};for _,id in ipairs(Inventory.PRODUCTS) do stock[id]=initial[id] end
    return {version=Inventory.VERSION,revision=1,stock=stock,nextDeliveryDay=1,
        deliveryCount=0,lastDeliveryDay=nil,lastDeliveryNote='Outside connection delivery scheduled.'}
end

function Inventory.valid(value)
    if type(value)~='table' or value.version~=Inventory.VERSION
        or type(value.revision)~='number' or value.revision%1~=0 or value.revision<1 or value.revision>1e9
        or type(value.nextDeliveryDay)~='number' or value.nextDeliveryDay%1~=0 or value.nextDeliveryDay<0
        or type(value.deliveryCount)~='number' or value.deliveryCount%1~=0 or value.deliveryCount<0
        or value.lastDeliveryDay~=nil and (type(value.lastDeliveryDay)~='number'
            or value.lastDeliveryDay%1~=0 or value.lastDeliveryDay<0)
        or type(value.lastDeliveryNote)~='string' or #value.lastDeliveryNote>160
        or type(value.stock)~='table' then return false end
    local allowed={};for _,id in ipairs(Inventory.PRODUCTS) do allowed[id]=true end
    for id,count in pairs(value.stock) do
        if not allowed[id] or type(count)~='number' or count%1~=0 or count<0 or count>Inventory.MAX_STOCK then
            return false
        end
    end
    for _,id in ipairs(Inventory.PRODUCTS) do
        if type(value.stock[id])~='number' then return false end
    end
    return true
end

function Inventory.normalize(value)
    if Inventory.valid(value) then
        local result={version=value.version,revision=value.revision,stock={},nextDeliveryDay=value.nextDeliveryDay,
            deliveryCount=value.deliveryCount,lastDeliveryDay=value.lastDeliveryDay,lastDeliveryNote=value.lastDeliveryNote}
        for _,id in ipairs(Inventory.PRODUCTS) do result.stock[id]=value.stock[id] end
        return result
    end
    return Inventory.defaultState()
end

function Inventory.ensure(state)
    if not Inventory.valid(state.groceryStore) then
        state.groceryStore=Inventory.normalize(state.groceryStore)
    end
    return state.groceryStore
end

function Inventory.count(stockState,id)
    local store=type(stockState)=='table' and stockState.stock or nil
    return store and store[id] or 0
end

function Inventory.canSupply(stockState,cart)
    for id,quantity in pairs(cart or {}) do
        if Inventory.count(stockState,id)<quantity then return false,id,Inventory.count(stockState,id) end
    end
    return true
end

function Inventory.consume(stockState,cart)
    local available,id,count=Inventory.canSupply(stockState,cart)
    if not available then return false,id,count end
    for productId,quantity in pairs(cart or {}) do stockState.stock[productId]=stockState.stock[productId]-quantity end
    stockState.revision=stockState.revision+1
    return true
end

function Inventory.arriveFromOutsideConnection(state)
    local stock=Inventory.ensure(state)
    local calendar=state.calendar or {}
    if calendar.weekday==6 or calendar.weekday==7 or (calendar.totalDays or 0)<stock.nextDeliveryDay then return false end
    local day=calendar.totalDays or 0
    local delivery=stock.deliveryCount+1
    for index,id in ipairs(Inventory.PRODUCTS) do
        local roll=(day*31+delivery*17+index*13)%11
        if roll>=4 then
            local quantity=2+roll%7
            stock.stock[id]=math.min(Inventory.MAX_STOCK,stock.stock[id]+quantity)
        end
    end
    stock.deliveryCount=delivery
    stock.lastDeliveryDay=day
    stock.nextDeliveryDay=day+Inventory.DELIVERY_INTERVAL_DAYS
    stock.lastDeliveryNote='Outside connection delivery arrived; the next truck is due in about three days.'
    stock.revision=stock.revision+1
    return true
end

return Inventory
