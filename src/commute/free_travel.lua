-- One shared outdoor world, with independent resident journeys. Interior
-- locations live on residents; only outdoor travelers need physics records.
local Residents=require('src.home_residents')
local Gear=require('src.commute.gear')
local Rider=require('src.commute.rider')
local Free={}

function Free.enter(state,player,world,run,players)
    local Trip=require('src.commute.trip')
    local id=Residents.key(player);local resident=Residents.get(state,player)
    if not resident then return false,'Join the household before leaving.' end
    local scene=player.sceneId or 'warehouse'
    if scene~='home' and scene~='warehouse' then return false,'Use the apartment or warehouse exit.' end
    local t=state.home.commute
    if t and not t.independent then return false,'Finish the existing household trip first.' end
    if t and t.participants[id] then return false,'You are already outside.' end
    if run and t and (t.deliveryRun or t.truck.owner) then return false,'The truck is already in use.' end
    local slot=tonumber(player.id) or 1
    local origin=scene=='home' and state.home.apartmentId or 'warehouse'
    local anchor=Trip.parking(world,origin,slot)
    if not anchor then return false,'There is no safe parking space at this exit.' end
    local gear=Gear.restore(resident.ridingGear)
    if not gear then return false,'Invalid riding equipment.' end
    gear.mounted=false;gear.engine=false
    local rider=Rider.new(anchor.x,anchor.z,anchor.heading or 0,gear)
    rider.ped.x,rider.ped.z=anchor.pedX or anchor.x,anchor.pedZ or anchor.z
    local bike=rider.bike
    bike.transmission=resident.ridingTransmission or 'automatic'
    bike.upgradeLevel=resident.ridingUpgradeLevel or 0
    bike.upgradeParts=require('src.commute.bike_upgrades').copyParts(resident.ridingUpgradeParts)
    bike.paintId=resident.ridingPaintId or require('src.commute.bike_paint').DEFAULT
    bike.service=require('src.commute.bike_service').copy(resident.ridingService)
    bike.damage=resident.ridingDamage or 0
    Rider.update(rider,{},0,world)
    if not t then
        local truck=Trip.truckParking(world,require('src.company_delivery_driver').ensure(state))
        if not truck then return false,'No safe loading area is available.' end
        t={version=Trip.VERSION,mapVersion=require('src.commute.roads').VERSION,mapId=world.townId,
            token=state.home.revision+1,independent=true,purpose='outing',origin='warehouse',
            destination=state.home.apartmentId,participants={},truck=truck}
        for _,other in ipairs(players or {player}) do
            local person=Residents.get(state,other)
            if person then person.sceneId=other.sceneId=='home' and 'home' or 'warehouse' end
        end
    end
    if run then
        t.deliveryRun=run;t.deliveryDriver=id
        t.truck.owner=id
    end
    t.participants[id]={slot=slot,arrived=false,rider=rider,origin=origin,
        destination=run and 'warehouse' or scene=='home' and 'warehouse' or state.home.apartmentId,
        appearance=require('src.commute.normal_art').appearance(player)}
    resident.bikeParkedAtHome=false;resident.sceneId='commute';resident.activity=nil
    state.home.commute=t;state.home.revision=state.home.revision+1
    return true,t
end

function Free.leave(state,player,token,destination,world)
    local Trip=require('src.commute.trip')
    local part,t=Trip.participant(state,player,token)
    if not part then return false,t end
    local id=Residents.key(player)
    if destination~='warehouse' and destination~=state.home.apartmentId then return false,'Unknown entrance.' end
    if t.deliveryDriver==id and destination~='warehouse' then return false,'Finish the delivery route at the warehouse.' end
    local previous=part.destination;part.destination=destination
    local okay,message=Trip.command(state,player,token,'arrive',world)
    if not okay then part.destination=previous;return false,message end
    local resident=Residents.get(state,player);local r=part.rider
    resident.ridingGear=Gear.snapshot(r.gear)
    resident.ridingUpgradeLevel=r.bike.upgradeLevel or 0
    resident.ridingUpgradeParts=require('src.commute.bike_upgrades').copyParts(r.bike.upgradeParts)
    resident.ridingPaintId=r.bike.paintId
    resident.ridingService=require('src.commute.bike_service').copy(r.bike.service)
    resident.ridingDamage=r.bike.damage or 0
    resident.bikeParkedAtHome=destination==state.home.apartmentId and r.transport~='truck'
    resident.sceneId=destination=='warehouse' and 'warehouse' or 'home'
    resident.revision=resident.revision+1
    if t.truck.owner==id then t.truck.owner=nil;t.truck.driver=nil end
    if t.deliveryDriver==id then t.deliveryDriver=nil;t.deliveryRun=nil end
    t.participants[id]=nil
    state.home.revision=state.home.revision+1
    -- Retain the shared truck position and town token while interiors are occupied.
    return true,{destination=destination,participants={[id]=part},message=destination=='warehouse'
        and 'Back at the warehouse. Other players can continue their trips.' or 'Welcome to your apartment.'}
end

return Free
