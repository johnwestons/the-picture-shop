-- Host-authoritative truck service at the town mechanic.
local M=require('src.commute.vendor.mathx')
local Residents=require('src.home_residents')
local Trip=require('src.commute.trip')
local Truck=require('src.commute.delivery_truck')
local Service=require('src.commute.truck_service')
local Mechanic={DOOR_RADIUS=2.2,PARK_RADIUS=14,MAX_REVISION=Service.MAX_REVISION}
local function integer(n,lo,hi)return M.finite(n) and n%1==0 and n>=lo and n<=hi end
function Mechanic.canVisit(state,player,trip,world,model)
    if not (state and state.home and trip and trip==state.home.commute) then return false,'That ride has ended.' end
    if not require('src.commute.town_characters').isOpen(state.home,'mechanic',
        require('src.business_calendar').absoluteHours(state)) then
        return false,'Majic Blue is closed for the night. The mechanic is open 08:00–18:00.'
    end
    if type(player)~='table' then return false,'Visit the mechanic during your ride.' end
    local id=Residents.key(player);local resident=Residents.get(state,player)
    local part=trip.participants and trip.participants[id]
    if not resident or not part or part.slot~=(tonumber(player.id) or 1) or part.arrived
        or player.sceneId~='commute' then return false,'Visit the mechanic during your ride.' end
    local rider=part.rider;local ped=rider and rider.ped
    if not ped or rider.vehicle=='truck' or rider.gear.mounted or rider.gear.engine
        or rider.gear.transition or ped.crash or (ped.speed or 0)>.05 then
        return false,'Park the truck, get out and walk to the mechanic door.'
    end
    local sites=world and (world.sites or world.roads and world.roads.sites)
    local site=sites and sites.byId.mechanic
    if not site or M.length(ped.x-site.door.x,ped.z-site.door.z)>Mechanic.DOOR_RADIUS then
        return false,'Walk to the mechanic door first.'
    end
    local selected,distance
    for _,truck in ipairs(Trip.trucks(trip)) do
        local nearPed=M.length(ped.x-truck.x,ped.z-truck.z)
        local nearBay=M.length(site.parking.x-truck.x,site.parking.z-truck.z)
        if (not model or truck.model==model) and truck.owner==id and truck.driver==nil
            and (truck.speed or 0)<=.05 and truck.service and Truck.valid(truck)
            and nearPed<=Mechanic.PARK_RADIUS and nearBay<=Mechanic.PARK_RADIUS
            and (not distance or nearPed<distance) then selected,distance=truck,nearPed end
    end
    if not selected then return false,'Bring your owned truck to the mechanic parking area and leave it parked.' end
    return true,nil,resident,selected,part
end
function Mechanic.quote(state,truck,kind,id)
    if not truck or not truck.service then return nil end
    if kind=='repair' then return Service.repairQuote(truck,state.home.balanceCents) end
    if kind=='maintenance' then return Service.maintenanceQuote(truck,id,state.home.balanceCents) end
    if kind=='upgrade' then return Service.upgradeQuote(truck,id,state.home.balanceCents) end
end
local function serviceField(id)
    return ({oil='oilMiles',oil_filter='oilFilterMiles',air_filter='airFilterMiles',
        spark_plugs='sparkPlugMiles',coolant='coolantMiles',tires='tireMiles',brakes='brakeMiles'})[id]
end
function Mechanic.purchase(state,player,trip,world,intent,kind)
    if type(intent)~='table' or not trip or intent.token~=trip.token
        or (intent.model~='box' and intent.model~='kei') then return false,'That mechanic order has expired.' end
    local okay,message,resident,truck=Mechanic.canVisit(state,player,trip,world,intent.model)
    if not okay then return false,message end
    if kind=='repair' then
        if not integer(intent.expectedRevision,0,Mechanic.MAX_REVISION)
            or not integer(intent.expectedDamage,0,100) or type(intent.expectedFailure)~='boolean' then
            return false,'Review the current truck repair estimate.'
        end
        local quote=Mechanic.quote(state,truck,'repair')
        if quote.revision~=intent.expectedRevision or quote.damage~=intent.expectedDamage
            or quote.failed~=intent.expectedFailure then return false,'The truck condition changed. Review the updated estimate.' end
        if quote.status~='available' then return false,quote.status=='healthy' and 'This truck is in full working order.'
            or 'Not enough household money for this repair.' end
        if quote.revision>=Mechanic.MAX_REVISION then return false,'The truck repair record cannot accept another order.' end
        state.home.balanceCents=state.home.balanceCents-quote.priceCents
        truck.damage=0;truck.repairRevision=quote.revision+1
        truck.service.mechanicalFailure=false;truck.service.failureType=nil;truck.service.failureClock=0
        truck.service.revision=truck.service.revision+1
        if intent.expectedFailure and (truck.fuel or 0)>0 then truck.engine=true end
        message='Truck collision and engine repairs are complete.'
    elseif kind=='maintenance' then
        local field=serviceField(intent.item)
        if not field or not integer(intent.expectedRevision,0,Mechanic.MAX_REVISION) then
            return false,'Choose an available truck maintenance service.'
        end
        local quote=Mechanic.quote(state,truck,'maintenance',intent.item)
        if not quote or quote.revision~=intent.expectedRevision then return false,'Truck service changed. Review the updated estimate.' end
        if quote.status~='available' then return false,quote.status=='healthy'
            and 'This maintenance item is in good condition.' or 'Not enough household money for this service.' end
        if quote.revision>=Mechanic.MAX_REVISION then return false,'The truck service record cannot accept another order.' end
        state.home.balanceCents=state.home.balanceCents-quote.priceCents
        truck.service[field]=0;truck.service.revision=truck.service.revision+1
        if intent.item=='oil' or intent.item=='oil_filter' or intent.item=='air_filter'
            or intent.item=='spark_plugs' or intent.item=='coolant' then
            truck.service.failureClock=math.max(0,truck.service.failureClock-18)
        end
        message=quote.item.name..' service is complete.'
    elseif kind=='upgrade' then
        local category=intent.category;local entry=Service.UPGRADES[category]
        if not entry or not integer(intent.expectedRevision,0,Mechanic.MAX_REVISION)
            or not integer(intent.expectedLevel,0,Service.UPGRADE_MAX-1) then
            return false,'Choose an available truck component upgrade.'
        end
        local current=truck.service.upgrades[category]
        local quote=Mechanic.quote(state,truck,'upgrade',category)
        if quote.revision~=intent.expectedRevision or current~=intent.expectedLevel
            or intent.level~=current+1 then return false,'Truck components changed. Review the updated estimate.' end
        if quote.status~='available' then return false,quote.status=='maxed'
            and 'This truck component is fully upgraded.' or 'Not enough household money for this upgrade.' end
        if quote.revision>=Mechanic.MAX_REVISION then return false,'The truck upgrade record cannot accept another order.' end
        state.home.balanceCents=state.home.balanceCents-quote.priceCents
        truck.service.upgrades[category]=intent.level;truck.service.upgradeRevision=quote.revision+1
        message=quote.offer.name..' installed.'
    else return false,'That truck service is unavailable.' end
    TruckService.syncFleet(state.home,Trip.trucks(trip))
    resident.revision=resident.revision+1;state.home.revision=state.home.revision+1
    return true,message
end
return Mechanic
