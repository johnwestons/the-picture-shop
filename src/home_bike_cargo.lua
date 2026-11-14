-- Persistent virtual pannier inventory for each resident's motorcycle.
local Catalog=require('src.home_shop_catalog')
local Cargo={CAPACITY=12,VERSION=1}
local function integer(n,low,high)
    return type(n)=='number' and n==n and n%1==0 and n>=low and n<=high
end
local function bikeProduct(id)
    local product=Catalog.PRODUCTS[id]
    return product and (product.group=='groceries' or product.group=='takeout') and product or nil
end
function Cargo.new()
    return {version=Cargo.VERSION,revision=0,items={}}
end
function Cargo.valid(inventory)
    if inventory==nil then return true end
    if type(inventory)~='table' or inventory.version~=Cargo.VERSION
        or not integer(inventory.revision,0,1e12) or type(inventory.items)~='table' then return false end
    local used,count=0,0
    for id,quantity in pairs(inventory.items) do
        if type(id)~='string' or not bikeProduct(id) or not integer(quantity,1,Cargo.CAPACITY) then return false end
        used,count=used+quantity,count+1
        if used>Cargo.CAPACITY or count>32 then return false end
    end
    return true
end
function Cargo.ensure(resident)
    resident.bikeInventory=resident.bikeInventory or Cargo.new()
    return resident.bikeInventory
end
function Cargo.used(inventory)
    local used=0
    for _,quantity in pairs(inventory and inventory.items or {}) do used=used+quantity end
    return used
end
function Cargo.decode(command)
    if type(command)~='string' or #command>32 then return nil end
    local productId,revision=command:match('^bike:([a-z_]+):(%d+)$')
    revision=tonumber(revision)
    if not productId or not revision or revision>1e12
        or productId~='all' and not bikeProduct(productId) then return nil end
    return {productId=productId,expectedRevision=revision}
end
local function residentFor(state,player)
    return require('src.home_residents').get(state,player)
end
function Cargo.target(player,state)
    if not state or not state.home or state.home.commute and not state.home.commute.independent or player.sceneId~='home'
        or not require('src.weekend_flow').atHome(state) then return nil end
    local resident=residentFor(state,player)
    if not resident or resident.bikeParkedAtHome~=true then return nil end
    local Layout=require('src.home_layouts')
    local x,y=Layout.spawn(state,player.id or 1)
    local candidates={{58,-35},{-58,-35},{52,34},{-52,34},{0,-68}}
    for _,offset in ipairs(candidates) do
        local px,py=x+offset[1],y+offset[2]
        if Layout.walkable(state.home.apartmentId,px,py) then x,y=px,py;break end
    end
    local inventory=Cargo.ensure(resident)
    local used=Cargo.used(inventory)
    return {kind='homeActivity',fixtureId='bikeCargo',x=x,y=y,radius=46,
        hoverX=x,hoverY=y-12,hoverRadius=24,
        prompt=('E: bike cargo / %d of %d bags'):format(used,Cargo.CAPACITY),actionLabel='BIKE'}
end
function Cargo.rows(state,player)
    local resident=residentFor(state,player)
    if not resident then return {} end
    local canUnload=player.sceneId=='home' and resident.bikeParkedAtHome==true
        and not (state.home.commute and not state.home.commute.independent)
        and require('src.weekend_flow').atHome(state)
    local inventory=Cargo.ensure(resident);local result={}
    for _,id in ipairs(Catalog.ORDER) do
        local quantity=inventory.items[id] or 0
        if quantity>0 then
            local product=Catalog.PRODUCTS[id]
            result[#result+1]={productId=id,quantity=quantity,name=product.name,
                label=('%d × %s'):format(quantity,product.name),
                command=canUnload and ('bike:%s:%d'):format(id,inventory.revision) or nil}
        end
    end
    if canUnload and #result>1 then
        result[#result+1]={productId='all',label='UNLOAD ALL BIKE CARGO TO HOME STORAGE',
            command=('bike:all:%d'):format(inventory.revision)}
    end
    return result
end
local function unloadItems(inventory,productId)
    local result={}
    if productId=='all' then
        for id,quantity in pairs(inventory.items) do result[id]=quantity end
    elseif inventory.items[productId] then result[productId]=inventory.items[productId] end
    return result
end
function Cargo.command(state,player,command)
    local intent=Cargo.decode(command)
    local resident=residentFor(state,player)
    if not intent or not resident then return false,'Your bike cargo is unavailable.' end
    if player.sceneId~='home' or state.home.commute and not state.home.commute.independent or not require('src.weekend_flow').atHome(state) then
        return false,'Bike cargo can only be unloaded inside your apartment.'
    end
    if resident.bikeParkedAtHome~=true then return false,'Park your bike in an apartment parking space before opening its cargo.' end
    local target=Cargo.target(player,state)
    if not target or (player.x-target.x)^2+(player.y-target.y)^2>target.radius^2 then
        return false,'Walk to the bike cargo access point first.'
    end
    local inventory=Cargo.ensure(resident)
    if inventory.revision~=intent.expectedRevision then return false,'Bike cargo changed. Review its current contents.' end
    local selected=unloadItems(inventory,intent.productId)
    if next(selected)==nil then return false,'There is no matching grocery cargo to unload.' end
    local additions={};local furnitureCatalog=require('src.home_furniture_catalog')
    local furniture=require('src.home_furniture');local furnitureData=furniture.ensure(state)
    local furnitureCount=#furnitureData.items
    for id,amount in pairs(state.home.inventory) do
        if furnitureCatalog.ITEMS[id] then furnitureCount=furnitureCount+amount end
    end
    for id,quantity in pairs(selected) do
        local product=bikeProduct(id);local amount=quantity*product.servings
        additions[product.item]=(additions[product.item] or 0)+amount
    end
    for id,amount in pairs(additions) do
        if not require('src.home_cooking').hasRoom(state,id,amount) then
            return false,'Home food storage is full; make room before unloading this cargo.'
        end
    end
    for id,amount in pairs(additions) do
        if furnitureCatalog.ITEMS[id] then furnitureCount=furnitureCount+amount end
    end
    if furnitureCount>128 then return false,'Home furniture storage is full; make room before unloading this cargo.' end
    local beforeFurniture=#furnitureData.items
    for id,amount in pairs(additions) do state.home.inventory[id]=(state.home.inventory[id] or 0)+amount end
    furniture.materialize(state,false)
    if #state.home.furniture.items>beforeFurniture then state.home.furniture.revision=state.home.furniture.revision+1 end
    for id in pairs(selected) do inventory.items[id]=nil end
    inventory.revision=inventory.revision+1;resident.revision=resident.revision+1
    state.home.revision=state.home.revision+1
    local packages=0;for _,quantity in pairs(selected) do packages=packages+quantity end
    return true,('%d bike cargo bag(s) unloaded to household storage.'):format(packages)
end
return Cargo
