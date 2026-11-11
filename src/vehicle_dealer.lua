-- CritterNet commercial vehicle listings and purchase records.
local TruckService=require('src.commute.truck_service')
local Dealer={}

Dealer.LISTINGS={
    box_new={id='box_new',model='box',condition='new',name='New 16 ft Box Truck',price=69900,
        description='2025 medium-duty box truck with a clean service record.'},
    box_used={id='box_used',model='box',condition='used',name='Used 16 ft Box Truck',price=24999,
        description='2020 work truck in poor condition with body damage and overdue service.'},
    kei_new={id='kei_new',model='kei',condition='new',name='New Imported Kei Truck',price=28000,
        description='Newer mini truck import with a clean service record.'},
    kei_used={id='kei_used',model='kei',condition='used',name='Used Kei Truck',price=8800,
        description='Older 4x4 import in poor condition with body damage and overdue service.'},
}
Dealer.ORDER={'box_new','box_used','kei_new','kei_used'}

local function copy(value)
    if type(value)~='table' then return value end
    local result={}
    for key,item in pairs(value) do result[key]=copy(item) end
    return result
end

function Dealer.listing(id)
    local value=Dealer.LISTINGS[id]
    return value and copy(value) or nil
end

function Dealer.ownershipField(model)
    if model=='box' then return 'boxTruckOwned' end
    if model=='kei' then return 'keiTruckOwned' end
end

function Dealer.owns(state,model)
    local warehouse=state and state.warehouse
    local field=Dealer.ownershipField(model)
    return field~=nil and (warehouse==nil or warehouse[field]~=false)
end

local function startingRecord(listing)
    local damage=0
    local service=TruckService.new()
    if listing.condition=='used' and listing.model=='box' then
        damage=42
        service.totalMiles=112000
        service.oilMiles,service.oilFilterMiles,service.airFilterMiles=33,46,55
        service.sparkPlugMiles,service.coolantMiles=73,123
        service.tireMiles,service.brakeMiles=41,37
    elseif listing.condition=='used' then
        damage=34
        service.totalMiles=58000
        service.oilMiles,service.oilFilterMiles,service.airFilterMiles=32,44,52
        service.sparkPlugMiles,service.coolantMiles=69,118
        service.tireMiles,service.brakeMiles=40,35
    end
    return {damage=damage,repairRevision=0,service=service}
end

function Dealer.purchase(state,listingId,requestId,nowHours)
    local listing=Dealer.LISTINGS[listingId]
    if not listing then return false,'That vehicle is no longer listed.','product_changed' end
    if type(requestId)~='string' or #requestId<1 or #requestId>64
        or not requestId:match('^[%w_.%-]+$') then
        return false,'A valid purchase request ID is required.','invalid_purchase'
    end
    local Upgrades=require('src.warehouse_upgrades')
    local warehouse,reason=Upgrades.ensure(state)
    if not warehouse then return false,reason or 'The shop purchase record is unavailable.','invalid_state' end
    for _,receipt in ipairs(warehouse.receipts) do
        if receipt.requestId==requestId then
            if receipt.kind~='vehicle' or receipt.optionId~=listingId then
                return false,'That purchase request ID was already used for another choice.','request_conflict'
            end
            return true,copy(receipt),'replayed'
        end
    end
    if Dealer.owns(state,listing.model) then
        return false,listing.model=='box' and 'The shop already owns a box truck.'
            or 'The shop already owns a kei truck.','vehicle_owned'
    end
    if type(state.money)~='number' or state.money<listing.price then
        return false,'Not enough money for this vehicle.','insufficient_funds'
    end
    nowHours=nowHours or require('src.business_calendar').absoluteHours(state)
    if type(nowHours)~='number' or nowHours<0 then return false,'Invalid purchase time.','invalid_time' end

    state.home=state.home or require('src.home').new()
    state.home.truckFleet=TruckService.normalizeFleet(state.home.truckFleet)
    state.home.truckFleet[listing.model]=startingRecord(listing)
    state.money=state.money-listing.price
    warehouse[Dealer.ownershipField(listing.model)]=true
    local receipt={requestId=requestId,kind='vehicle',bayId=nil,optionId=listing.id,
        targetId=listing.model,pricePaid=listing.price,purchasedAtHours=nowHours}
    warehouse.receipts[#warehouse.receipts+1]=receipt
    require('src.receipt_book').expense(state,'Vehicle purchase',listing.price*100,
        'CritterNet Vehicle Dealer','Shop',listing.name,'vehicle:'..requestId)
    return true,copy(receipt),'purchased'
end

return Dealer
