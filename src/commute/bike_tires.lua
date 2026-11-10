-- Tire compounds are mechanic upgrades. The host validates each order against
-- the parked motorcycle's live service record before charging shared funds.
local M=require('src.commute.vendor.mathx')
local Upgrades=require('src.commute.bike_upgrades')
local Service=require('src.commute.bike_service')
local Tires={MAX_REVISION=1000000000000}

function Tires.valid(id)
    return type(id)=='string' and Service.tires[id]~=nil
end
function Tires.validRevision(value)
    return type(value)=='number' and value>=0 and value<=Tires.MAX_REVISION and value%1==0
end
function Tires.quote(state,service,id)
    if not (state and state.home and M.finite(state.home.balanceCents)
        and Tires.valid(id) and Service.valid(service)) then return nil end
    local offer=Service.tires[id]
    local label,price,available=Service.offer(service,id)
    if not label or not Tires.validRevision(service.revision) then return nil end
    local balance=state.home.balanceCents
    return {offer=offer,current=Service.tires[service.tire],tireId=service.tire,tread=service.tread,
        revision=service.revision,priceCents=price,balanceCents=balance,
        shortfallCents=math.max(0,price-balance),status=not available and 'current'
            or balance<price and 'unaffordable' or 'available'}
end
function Tires.purchase(state,player,trip,world,intent)
    if type(intent)~='table' or not trip or intent.token~=trip.token then
        return false,'That ride has ended.'
    end
    if not Tires.valid(intent.tireId) or not Tires.validRevision(intent.expectedServiceRevision) then
        return false,'Choose a valid tire set and review its current quote.'
    end
    local okay,message,resident,bike=Upgrades.canVisit(state,player,trip,world)
    if not okay then return false,message end
    local service=bike.service
    if not Service.valid(service) or resident.ridingService and (not Service.valid(resident.ridingService)
            or resident.ridingService.tire~=service.tire
            or resident.ridingService.revision~=service.revision) then
        return false,'The motorcycle tire record is out of sync.'
    end
    if service.revision~=intent.expectedServiceRevision then
        return false,'Your tire record changed. Review the updated quote.'
    end
    if service.revision>=Tires.MAX_REVISION then return false,'The tire service record cannot accept another order.' end
    local label,price,available=Service.offer(service,intent.tireId)
    if not available then return false,'These tires are already installed and in good condition.' end
    if not M.finite(state.home.balanceCents) or state.home.balanceCents<price then
        return false,'Not enough household money for these tires.'
    end
    state.home.balanceCents=state.home.balanceCents-price
    require('src.receipt_book').expense(state,'Motorcycle tires',price,'Majic Blue','Household',label)
    service.tire=intent.tireId;service.tread=0;service.revision=service.revision+1
    resident.ridingService=Service.copy(service)
    resident.revision=resident.revision+1;state.home.revision=state.home.revision+1
    return true,label..' installed.'
end
return Tires
