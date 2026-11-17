-- Exchanges for items carried in bike cargo or in a resident's pockets.
-- Home-delivery inventory remains separate and is deliberately ineligible.
local Catalog=require('src.home_shop_catalog')
local BikeCargo=require('src.home_bike_cargo')
local Pockets=require('src.player_pockets')
local Food=require('src.home_food_catalog')
local Residents=require('src.home_residents')
local Trade={VERSION=1,MAX_OFFERS=32,MAX_EMPLOYEE_STOCK=12}

local function integer(value,low,high)
    return type(value)=='number' and value==value and value%1==0 and value>=low and value<=high
end
local function cargoTradeable(id) return BikeCargo.isTradeableProduct(id) end
local function pocketTradeable(id)
    local item=Food.ITEMS[id]
    return item~=nil and item.action~=nil
end
local function sourceValid(source,id)
    source=source or 'cargo'
    return source=='cargo' and cargoTradeable(id) or source=='pocket' and pocketTradeable(id)
end
local function inventoryCount(items)
    local total=0
    for _,amount in pairs(items or {}) do total=total+amount end
    return total
end
local function mapValid(items,source,capacity)
    if type(items)~='table' then return false end
    local count,total=0,0
    for id,amount in pairs(items) do
        if not sourceValid(source,id) or not integer(amount,1,capacity) then return false end
        count,total=count+1,total+amount
        if count>32 or total>capacity then return false end
    end
    return true
end
local function residentIdValid(id) return id=='owner' or Residents.validId(id) end
local function offerSource(offer,field) return offer[field] or 'cargo' end

function Trade.new()
    return {version=Trade.VERSION,nextOfferId=1,offers={},employeeStock={},employeePockets={}}
end
function Trade.valid(data)
    if data==nil then return true end
    if type(data)~='table' or data.version~=Trade.VERSION
        or not integer(data.nextOfferId,1,1e12) or type(data.offers)~='table'
        or type(data.employeeStock)~='table'
        or data.employeePockets~=nil and type(data.employeePockets)~='table' then return false end
    local count,ids=0,{}
    for index,offer in ipairs(data.offers) do
        local giveSource=type(offer)=='table' and offerSource(offer,'giveSource') or nil
        local wantSource=type(offer)=='table' and offerSource(offer,'wantSource') or nil
        if not integer(index,1,Trade.MAX_OFFERS) or type(offer)~='table'
            or not integer(offer.id,1,1e12) or ids[offer.id]
            or not residentIdValid(offer.from) or not residentIdValid(offer.to)
            or offer.from==offer.to or not sourceValid(giveSource,offer.giveId)
            or offer.giveSource~=nil and offer.giveSource~='cargo' and offer.giveSource~='pocket'
            or offer.wantId~=nil and not sourceValid(wantSource,offer.wantId)
            or offer.wantSource~=nil and offer.wantSource~='cargo' and offer.wantSource~='pocket'
            or offer.wantId==nil and offer.wantSource~=nil
            or offer.wantId==offer.giveId and wantSource==giveSource
            or type(offer.createdAtHours)~='number' or offer.createdAtHours~=offer.createdAtHours
            or offer.createdAtHours<0 or offer.createdAtHours>1e12
            or type(offer.expiresAtHours)~='number' or offer.expiresAtHours~=offer.expiresAtHours
            or offer.expiresAtHours<offer.createdAtHours or offer.expiresAtHours>1e12 then return false end
        ids[offer.id]=true;count=count+1
    end
    if count>#data.offers or count>Trade.MAX_OFFERS then return false end
    for employeeId,stock in pairs(data.employeeStock) do
        if type(employeeId)~='string' or #employeeId>40 or not employeeId:match('^[%w%-]+$')
            or type(stock)~='table' or not mapValid(stock.items,'cargo',BikeCargo.CAPACITY) then return false end
    end
    for employeeId,stock in pairs(data.employeePockets or {}) do
        if type(employeeId)~='string' or #employeeId>40 or not employeeId:match('^[%w%-]+$')
            or type(stock)~='table' or not mapValid(stock.items,'pocket',Pockets.CAPACITY) then return false end
    end
    return data.nextOfferId>0
end

function Trade.ensure(state)
    local home=state and state.home
    if not home then return nil end
    home.trading=home.trading or Trade.new()
    home.trading.employeePockets=home.trading.employeePockets or {}
    local now=require('src.business_calendar').absoluteHours(state)
    local expired=false
    for index=#home.trading.offers,1,-1 do
        local offer=home.trading.offers[index]
        if type(offer.expiresAtHours)=='number' and offer.expiresAtHours<=now then
            table.remove(home.trading.offers,index);expired=true
        end
    end
    if expired then home.revision=home.revision+1 end
    return home.trading
end

function Trade.decode(command)
    if type(command)~='string' or #command>100 then return nil end
    local target,give,want,giveSource,wantSource
    target,give,want=command:match('^offer:(%d+):([a-z_]+):([a-z_]+)$')
    if target then
        target=tonumber(target)
        if not integer(target,1,4) or not cargoTradeable(give)
            or want~='gift' and (not cargoTradeable(want) or want==give) then return nil end
        return {action='offer',targetPlayerId=target,giveId=give,giveSource='cargo',
            wantId=want~='gift' and want or nil,wantSource=want~='gift' and 'cargo' or nil}
    end
    target,giveSource,give=command:match('^offer:(%d+):([a-z]+):([a-z_]+):gift$')
    if target then
        target=tonumber(target)
        if integer(target,1,4) and sourceValid(giveSource,give) then
            return {action='offer',targetPlayerId=target,giveId=give,giveSource=giveSource,
                wantId=nil,wantSource=nil}
        end
        return nil
    end
    target,giveSource,give,wantSource,want=command:match('^offer:(%d+):([a-z]+):([a-z_]+):([a-z]+):([a-z_]+)$')
    if target then
        target=tonumber(target)
        if not integer(target,1,4) or not sourceValid(giveSource,give)
            or not sourceValid(wantSource,want)
            or give==want and giveSource==wantSource then return nil end
        return {action='offer',targetPlayerId=target,giveId=give,giveSource=giveSource,
            wantId=want,wantSource=wantSource}
    end
    local offerId=command:match('^accept:(%d+)$')
    if offerId then offerId=tonumber(offerId);if integer(offerId,1,1e12) then return {action='accept',offerId=offerId} end end
    offerId=command:match('^decline:(%d+)$')
    if offerId then offerId=tonumber(offerId);if integer(offerId,1,1e12) then return {action='decline',offerId=offerId} end end
    local employeeId=command:match('^employee:([%w%-]+):accept$')
    if employeeId and #employeeId<=40 then return {action='employeeAccept',employeeId=employeeId} end
    local productId
    employeeId,productId=command:match('^employee:([%w%-]+):gift:([a-z_]+)$')
    if employeeId and #employeeId<=40 and cargoTradeable(productId) then
        return {action='employeeGift',employeeId=employeeId,giveId=productId,giveSource='cargo'}
    end
    employeeId,giveSource,productId=command:match('^employee:([%w%-]+):gift:([a-z]+):([a-z_]+)$')
    if employeeId and #employeeId<=40 and sourceValid(giveSource,productId) then
        return {action='employeeGift',employeeId=employeeId,giveId=productId,giveSource=giveSource}
    end
end
function Trade.validCommand(command) return Trade.decode(command)~=nil end

local function playerById(playerId,players)
    for _,candidate in ipairs(players or {}) do if tonumber(candidate.id)==playerId then return candidate end end
end
local function playerByResident(state,residentId,players)
    for _,candidate in ipairs(players or {}) do
        if Residents.key(candidate)==residentId and Residents.get(state,candidate) then return candidate end
    end
end
local function samePlaceAndNear(state,a,b,radius)
    if not a or not b or a.sceneId~=b.sceneId then return false end
    if a.sceneId=='home' then
        local Apartments=require('src.client_apartments')
        if Apartments.forPlayer(state,a)~=Apartments.forPlayer(state,b) then return false end
    end
    local dx,dy=(tonumber(a.x) or 0)-(tonumber(b.x) or 0),(tonumber(a.y) or 0)-(tonumber(b.y) or 0)
    return dx*dx+dy*dy<=radius*radius
end
local function residentInventory(state,player)
    local resident=player and Residents.get(state,player)
    if not resident then return nil end
    return resident,BikeCargo.ensure(resident)
end
local function inventoryFor(state,player,source)
    local resident=player and Residents.get(state,player)
    if not resident then return nil end
    source=source or 'cargo'
    return resident,source=='pocket' and Pockets.ensure(resident) or BikeCargo.ensure(resident)
end
local function inventoryCapacity(source) return source=='pocket' and Pockets.CAPACITY or BikeCargo.CAPACITY end
local function inventoryUsed(inventory) return inventoryCount(inventory and inventory.items) end
local function reservedCount(trading,residentId,productId,source)
    local count=0;source=source or 'cargo'
    for _,offer in ipairs(trading and trading.offers or {}) do
        if offer.from==residentId and offer.giveId==productId
            and offerSource(offer,'giveSource')==source then count=count+1 end
    end
    return count
end
function Trade.availableCount(state,player,productId,source)
    source=source or 'cargo'
    local resident,inventory=inventoryFor(state,player,source)
    if not resident or not sourceValid(source,productId) then return 0 end
    local trading=Trade.ensure(state)
    return math.max(0,(inventory.items[productId] or 0)-reservedCount(
        trading,Residents.key(player),productId,source))
end
function Trade.inventoryRows(state,player)
    local _,inventory=residentInventory(state,player);local rows={}
    if not inventory then return rows end
    for _,id in ipairs(Catalog.ORDER) do
        local amount=Trade.availableCount(state,player,id,'cargo')
        if amount>0 then rows[#rows+1]={id=id,name=Catalog.PRODUCTS[id].name,quantity=amount,source='cargo'} end
    end
    return rows
end
function Trade.pocketRows(state,player)
    local _,inventory=inventoryFor(state,player,'pocket');local rows={}
    if not inventory then return rows end
    local ids={};for id,item in pairs(Food.ITEMS) do if item.action then ids[#ids+1]=id end end
    table.sort(ids)
    for _,id in ipairs(ids) do
        local amount=Trade.availableCount(state,player,id,'pocket')
        if amount>0 then rows[#rows+1]={id=id,name=Food.ITEMS[id].name,quantity=amount,source='pocket'} end
    end
    return rows
end
function Trade.pendingFor(state,player,fromResidentId)
    local trading=Trade.ensure(state);local key=player and Residents.key(player);local rows={}
    if not trading or not key then return rows end
    for _,offer in ipairs(trading.offers) do
        if offer.to==key and (not fromResidentId or offer.from==fromResidentId) then rows[#rows+1]=offer end
    end
    return rows
end
function Trade.sentFor(state,player,toResidentId)
    local trading=Trade.ensure(state);local key=player and Residents.key(player);local rows={}
    if not trading or not key then return rows end
    for _,offer in ipairs(trading.offers) do
        if offer.from==key and (not toResidentId or offer.to==toResidentId) then rows[#rows+1]=offer end
    end
    return rows
end
local function findOffer(trading,offerId)
    for index,offer in ipairs(trading.offers) do if offer.id==offerId then return offer,index end end
end
local function employeeSerial(employeeId) return tonumber(tostring(employeeId or ''):match('(%d+)$')) or 1 end
local function cargoIds()
    local ids={};for _,id in ipairs(Catalog.ORDER) do if cargoTradeable(id) then ids[#ids+1]=id end end
    return ids
end
local function pocketIds()
    local ids={};for id,item in pairs(Food.ITEMS) do if item.action then ids[#ids+1]=id end end
    table.sort(ids);return ids
end
local function initialEmployeeStock(worker)
    local ids=cargoIds();local id=ids[(employeeSerial(worker.id)-1)%#ids+1]
    return {[id]=1}
end
local function initialEmployeePockets(worker)
    local ids=pocketIds();local id=ids[(employeeSerial(worker.id)-1)%#ids+1]
    return {[id]=1}
end
local function employeeStock(state,worker)
    local trading=Trade.ensure(state);local row=trading and trading.employeeStock[worker.id]
    return row and row.items or initialEmployeeStock(worker)
end
local function employeePockets(state,worker)
    local trading=Trade.ensure(state);local row=trading and trading.employeePockets[worker.id]
    return row and row.items or initialEmployeePockets(worker)
end
local function employeeInventory(state,worker,source)
    return source=='pocket' and employeePockets(state,worker) or employeeStock(state,worker)
end
local function employeeItemName(id,source)
    return source=='pocket' and Food.ITEMS[id].name or Catalog.PRODUCTS[id].name
end
function Trade.employeeOffer(state,worker,player)
    if not state or not worker or worker.status~='employed' or not worker.visible then return nil end
    local source,stock='pocket',employeePockets(state,worker)
    local ids=pocketIds();local giveId
    for _,id in ipairs(ids) do if (stock[id] or 0)>0 then giveId=id;break end end
    if not giveId then
        source,stock='cargo',employeeStock(state,worker);ids=cargoIds()
        for _,id in ipairs(ids) do if (stock[id] or 0)>0 then giveId=id;break end end
    end
    if not giveId then return nil end
    local wantId,wantSource
    if employeeSerial(worker.id)%4~=0 then
        if player then
            local sources={source,source=='pocket' and 'cargo' or 'pocket'}
            for _,candidateSource in ipairs(sources) do
                local candidates=candidateSource=='pocket' and pocketIds() or cargoIds()
                for _,id in ipairs(candidates) do
                    if (id~=giveId or candidateSource~=source)
                        and Trade.availableCount(state,player,id,candidateSource)>0 then
                        wantId,wantSource=id,candidateSource;break
                    end
                end
                if wantId then break end
            end
        else
            local offset=(employeeSerial(worker.id)+2)%#ids
            for step=0,#ids-1 do
                local id=ids[(offset+step)%#ids+1]
                if id~=giveId then wantId=id;wantSource=source;break end
            end
        end
    end
    return {employeeId=worker.id,giveId=giveId,giveName=employeeItemName(giveId,source),
        giveSource=source,wantId=wantId,wantSource=wantSource,
        wantName=wantId and employeeItemName(wantId,wantSource) or nil,gift=wantId==nil}
end
function Trade.employeeStockRows(state,worker)
    local rows={}
    for _,source in ipairs({'pocket','cargo'}) do
        local stock=worker and employeeInventory(state,worker,source) or {}
        local ids=source=='pocket' and pocketIds() or cargoIds()
        for _,id in ipairs(ids) do
            if (stock[id] or 0)>0 then rows[#rows+1]={id=id,name=employeeItemName(id,source),
                quantity=stock[id],source=source} end
        end
    end
    return rows
end

local function addDelta(deltas,id,amount) deltas[id]=(deltas[id] or 0)+amount end
local function projectedUsed(inventory,deltas)
    local used=inventoryUsed(inventory)
    for _,amount in pairs(deltas or {}) do used=used+amount end
    return used
end
local function adjust(items,id,amount)
    local nextAmount=(items[id] or 0)+amount
    if nextAmount<=0 then items[id]=nil else items[id]=nextAmount end
end
local function touchPlayer(state,resident,...)
    local seen={}
    for index=1,select('#',...) do
        local inventory=select(index,...)
        if inventory and not seen[inventory] then
            inventory.revision=(inventory.revision or 0)+1;seen[inventory]=true
        end
    end
    resident.revision=(resident.revision or 0)+1
    state.home.revision=state.home.revision+1
end
local function nearbyPlayer(state,player,target)
    return target and player~=target and samePlaceAndNear(state,player,target,112)
end
local function offerItem(state,player,intent,players)
    local target=playerById(intent.targetPlayerId,players)
    if not nearbyPlayer(state,player,target) then return false,'out_of_range','Move closer to the other player before proposing a trade.' end
    local from,to=Residents.key(player),Residents.key(target)
    if not residentIdValid(from) or not residentIdValid(to) or from==to then return false,'profile_missing','Both players need an assigned resident profile.' end
    local giveSource=intent.giveSource or 'cargo';local wantSource=intent.wantSource or 'cargo'
    if Trade.availableCount(state,player,intent.giveId,giveSource)<1 then
        return false,'item_missing','That item is not available in your selected inventory.'
    end
    if intent.wantId and Trade.availableCount(state,target,intent.wantId,wantSource)<1 then
        return false,'item_missing','The requested item is not currently available in the other player’s selected inventory.'
    end
    local trading=Trade.ensure(state)
    if #trading.offers>=Trade.MAX_OFFERS then return false,'offers_full','There are too many open trades. Resolve an existing offer first.' end
    local id=trading.nextOfferId;trading.nextOfferId=id+1
    local now=require('src.business_calendar').absoluteHours(state)
    trading.offers[#trading.offers+1]={id=id,from=from,to=to,giveId=intent.giveId,
        giveSource=giveSource,wantId=intent.wantId,wantSource=intent.wantId and wantSource or nil,
        createdAtHours=now,expiresAtHours=now+24*7}
    state.home.revision=state.home.revision+1
    local offered=employeeItemName(intent.giveId,giveSource)
    return true,'offer_sent',intent.wantId and ('Trade offer sent: %s for %s.'):format(
        offered,employeeItemName(intent.wantId,wantSource)) or ('Gift offer sent: %s.'):format(offered)
end

local function resolveOffer(state,player,intent,players)
    local trading=Trade.ensure(state);local offer,index=findOffer(trading,intent.offerId)
    if not offer then return false,'offer_gone','That trade offer is no longer available.' end
    local ownKey=Residents.key(player)
    if intent.action=='decline' then
        if ownKey~=offer.from and ownKey~=offer.to then return false,'not_yours','That trade offer belongs to another player.' end
        table.remove(trading.offers,index);state.home.revision=state.home.revision+1
        return true,'declined','Trade offer closed.'
    end
    if ownKey~=offer.to then return false,'not_yours','Only the receiving player can accept this trade.' end
    local sender=playerByResident(state,offer.from,players)
    if not sender or not samePlaceAndNear(state,player,sender,112) then return false,'sender_unavailable','The other player must be nearby to complete this trade.' end
    local giveSource,wantSource=offerSource(offer,'giveSource'),offerSource(offer,'wantSource')
    local senderResident,senderGive=inventoryFor(state,sender,giveSource)
    local receiverResident,receiverGive=inventoryFor(state,player,giveSource)
    if not receiverResident or not senderResident then return false,'profile_missing','A player inventory is unavailable.' end
    if (senderGive.items[offer.giveId] or 0)
        <reservedCount(trading,offer.from,offer.giveId,giveSource) then
        return false,'item_missing','The offered item is no longer available.'
    end
    local senderWant,receiverWant
    if offer.wantId then
        local _,senderWantInventory=inventoryFor(state,sender,wantSource)
        local _,receiverWantInventory=inventoryFor(state,player,wantSource)
        senderWant,receiverWant=senderWantInventory,receiverWantInventory
        if Trade.availableCount(state,player,offer.wantId,wantSource)<1 then
            return false,'item_missing','You no longer have the item requested in this trade.'
        end
    end
    local senderDelta,receiverDelta={},{}
    addDelta(senderDelta,offer.giveId,-1);addDelta(receiverDelta,offer.giveId,1)
    if offer.wantId and wantSource==giveSource then
        addDelta(senderDelta,offer.wantId,1);addDelta(receiverDelta,offer.wantId,-1)
    end
    if projectedUsed(senderGive,senderDelta)>inventoryCapacity(giveSource)
        or projectedUsed(receiverGive,receiverDelta)>inventoryCapacity(giveSource) then
        return false,'inventory_full','There is not enough room in one player’s selected inventory.'
    end
    if offer.wantId and wantSource~=giveSource then
        local _,senderWantInventory=inventoryFor(state,sender,wantSource)
        local _,receiverWantInventory=inventoryFor(state,player,wantSource)
        if projectedUsed(senderWantInventory,{[offer.wantId]=1})>inventoryCapacity(wantSource)
            or projectedUsed(receiverWantInventory,{[offer.wantId]=-1})>inventoryCapacity(wantSource) then
            return false,'inventory_full','There is not enough room in one player’s selected inventory.'
        end
    end
    adjust(senderGive.items,offer.giveId,-1);adjust(receiverGive.items,offer.giveId,1)
    if offer.wantId then
        adjust(receiverWant.items,offer.wantId,-1);adjust(senderWant.items,offer.wantId,1)
    end
    touchPlayer(state,senderResident,senderGive,senderWant)
    touchPlayer(state,receiverResident,receiverGive,receiverWant)
    table.remove(trading.offers,index)
    return true,'accepted',offer.wantId and 'Trade completed.' or 'Gift received.'
end

local function employeeCommand(state,player,intent)
    local worker=require('src.employees').worker(state,intent.employeeId)
    local scene=require('src.shop_rooms').scene(player)
    local dx,dy=(tonumber(player.x) or 0)-(worker and tonumber(worker.x) or 0),
        (tonumber(player.y) or 0)-(worker and tonumber(worker.y) or 0)
    if not worker or worker.status~='employed' or not worker.visible
        or (worker.sceneId or 'warehouse')~=scene or dx*dx+dy*dy>112^2 then
        return false,'out_of_range','Move closer to the employee before trading.'
    end
    local trading=Trade.ensure(state)
    if intent.action=='employeeGift' then
        local source=intent.giveSource or 'cargo'
        if Trade.availableCount(state,player,intent.giveId,source)<1 then
            return false,'item_missing','That item is not available in your selected inventory.'
        end
        local stock=employeeInventory(state,worker,source)
        if inventoryCount(stock)>=inventoryCapacity(source) then
            return false,'employee_full',worker.name..' cannot carry any more items in that inventory.'
        end
        local resident,inventory=inventoryFor(state,player,source)
        adjust(inventory.items,intent.giveId,-1)
        adjust(stock,intent.giveId,1)
        trading[source=='pocket' and 'employeePockets' or 'employeeStock'][worker.id]={items=stock}
        touchPlayer(state,resident,inventory)
        return true,'gifted','You gave '..worker.name..' '..employeeItemName(intent.giveId,source)..'.'
    end
    local offer=Trade.employeeOffer(state,worker,player)
    if not offer then return false,'unavailable',worker.name..' has nothing to trade right now.' end
    local giveSource,wantSource=offer.giveSource,offer.wantSource or 'cargo'
    local resident=Residents.get(state,player)
    if not resident then return false,'profile_missing','Your carried inventory is unavailable.' end
    local playerWant
    if offer.wantId then local _,inventory=inventoryFor(state,player,wantSource);playerWant=inventory end
    if offer.wantId and Trade.availableCount(state,player,offer.wantId,wantSource)<1 then
        return false,'item_missing','You do not have the item '..offer.wantName..' that '..worker.name..' wants.'
    end
    local employeeGive=employeeInventory(state,worker,giveSource)
    if (employeeGive[offer.giveId] or 0)<1 then return false,'item_missing','The employee’s offered item is no longer available.' end
    local _,playerReceive=inventoryFor(state,player,giveSource)
    local playerDeltas,employeeDeltas={},{}
    addDelta(playerDeltas,offer.giveId,1);addDelta(employeeDeltas,offer.giveId,-1)
    if offer.wantId and wantSource==giveSource then
        addDelta(playerDeltas,offer.wantId,-1);addDelta(employeeDeltas,offer.wantId,1)
    end
    if projectedUsed(playerReceive,playerDeltas)>inventoryCapacity(giveSource)
        or projectedUsed(employeeGive,employeeDeltas)>inventoryCapacity(giveSource) then
        return false,'inventory_full','Make room in the employee or your selected inventory before trading.'
    end
    if offer.wantId and wantSource~=giveSource then
        local employeeWant=employeeInventory(state,worker,wantSource)
        if projectedUsed(playerWant,{[offer.wantId]=-1})>inventoryCapacity(wantSource)
            or projectedUsed(employeeWant,{[offer.wantId]=1})>inventoryCapacity(wantSource) then
            return false,'inventory_full','Make room in the employee or your selected inventory before trading.'
        end
    end
    adjust(employeeGive,offer.giveId,-1);adjust(playerReceive.items,offer.giveId,1)
    local employeeWant
    if offer.wantId then
        adjust(playerWant.items,offer.wantId,-1)
        employeeWant=employeeInventory(state,worker,wantSource)
        adjust(employeeWant,offer.wantId,1)
    end
    trading[giveSource=='pocket' and 'employeePockets' or 'employeeStock'][worker.id]={items=employeeGive}
    if offer.wantId then trading[wantSource=='pocket' and 'employeePockets' or 'employeeStock'][worker.id]={items=employeeWant} end
    touchPlayer(state,resident,playerReceive,playerWant)
    return true,'accepted',offer.gift and (worker.name..' gave you '..offer.giveName..'.')
        or ('Trade complete: you gave '..offer.wantName..' for '..offer.giveName..'.')
end

function Trade.command(state,player,command,players)
    local intent=Trade.decode(command)
    if not intent or not state or not state.home or type(player)~='table' then
        return false,'invalid_action','Choose a valid player or employee trade.'
    end
    if intent.action=='offer' then return offerItem(state,player,intent,players) end
    if intent.action=='accept' or intent.action=='decline' then return resolveOffer(state,player,intent,players) end
    return employeeCommand(state,player,intent)
end
return Trade
