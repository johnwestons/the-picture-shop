-- Explicit watchdog service: repair/refuel where the truck stopped. Never move
-- its pose, route, manifest, or delivery clock as a side effect of service.
local Service=require('src.commute.truck_service')
local Power=require('src.commute.truck_power')
local Roadside={}
local engineFields={oil='oilMiles',oil_filter='oilFilterMiles',air_filter='airFilterMiles',
    spark_plugs='sparkPlugMiles',coolant='coolantMiles'}
function Roadside.quote(vehicle,company)
    local reason=Power.reason(vehicle)
    if not reason then return nil end
    local result={reason=reason,priceCents=0,maintenance={}}
    if vehicle.service and vehicle.service.mechanicalFailure then
        result.repair=true
        result.priceCents=Service.repairQuote(vehicle,math.huge).priceCents
        local ratios=Service.ratios(vehicle.service)
        for _,item in ipairs(Service.MAINTENANCE) do
            if engineFields[item.id] and ratios[item.id]>=1 then
                result.maintenance[#result.maintenance+1]=engineFields[item.id]
                result.priceCents=result.priceCents+item.price
            end
        end
    end
    if (vehicle.fuel or 1)<=0 then
        result.fuel=require('src.commute.delivery_truck').TANK_LITERS
        result.priceCents=result.priceCents+math.ceil(result.fuel
            *require('src.company_delivery_driver').FUEL_PRICE_CENTS_PER_LITER)
    end
    -- Outside carriers pay their own operating costs.
    if not company then result.priceCents=0 end
    return result
end
function Roadside.service(state,vehicle,company)
    local quote=Roadside.quote(vehicle,company)
    if not quote then return false,'Truck does not need roadside service.' end
    if quote.repair and ((vehicle.repairRevision or 0)>=Service.MAX_REVISION
        or vehicle.service.revision>=Service.MAX_REVISION) then return false,'Truck service record is full.' end
    if quote.priceCents>0 and not require('src.business_calendar').recordPaidExpenseCents(state,
        'Delivery truck roadside service',quote.priceCents,'truck-roadside') then
        return false,('Roadside service needs $%.2f in company funds.'):format(quote.priceCents/100)
    end
    if quote.repair then
        vehicle.damage=0;vehicle.repairRevision=(vehicle.repairRevision or 0)+1
        local service=vehicle.service
        service.mechanicalFailure=false;service.failureType=nil;service.failureClock=0
        for _,field in ipairs(quote.maintenance) do service[field]=0 end
        service.revision=service.revision+1
    end
    if quote.fuel then vehicle.fuel=quote.fuel end
    vehicle.engine=true
    if company then
        company.fuelLiters=vehicle.fuel;company.revision=company.revision+1
        Service.syncFleet(state.home,{vehicle})
        require('src.company_delivery_driver').syncTripVehicle(state)
        state.home.revision=(state.home.revision or 0)+1
    end
    return true,quote.priceCents>0 and ('Truck serviced in place for $%.2f; its delivery will resume.'):format(quote.priceCents/100)
        or 'Truck restarted in place; its route will resume.'
end
return Roadside
