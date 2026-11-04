-- Household-owned progression; commands run through the authoritative host.
local M=require('src.commute.vendor.mathx')
local Upgrades={MAX_LEVEL=3,DOOR_RADIUS=2.2,BIKE_RADIUS=7}
local mph=1/2.236936
Upgrades.CATALOG={
    {level=1,name='Trail tune',costCents=35000,maxSpeed=55*mph,boostMaxSpeed=60*mph,acceleration=1.38,
        description='Carburetor tuning, fresh filter and trail gearing.',parts='Intake service / gearing / tune'},
    {level=2,name='Performance kit',costCents=85000,maxSpeed=65*mph,boostMaxSpeed=70*mph,acceleration=1.73,
        description='A freer exhaust and revised fueling for stronger acceleration.',parts='Exhaust / fuel kit / final drive'},
    {level=3,name='High-output kit',costCents=180000,maxSpeed=70*mph,boostMaxSpeed=75*mph,acceleration=2.13,
        description='Engine and transmission work for the full 75 mph boost range.',parts='Engine kit / clutch / road gearing'},
}
local base={level=0,name='Standard trail bike',costCents=0,maxSpeed=45*mph,boostMaxSpeed=50*mph,acceleration=1.15}
function Upgrades.validLevel(level)
    return level==nil or M.finite(level) and level%1==0 and level>=0 and level<=Upgrades.MAX_LEVEL
end
function Upgrades.profile(level) return Upgrades.CATALOG[level or 0] or base end
function Upgrades.next(value)
    local level=type(value)=='table' and value.ridingUpgradeLevel or value
    return Upgrades.CATALOG[(level or 0)+1]
end
function Upgrades.canVisit(state,player,trip,world)
    if not (state and state.home and trip and trip==state.home.commute) then return false,'That ride has ended.' end
    if type(player)~='table' or player.sceneId~='commute' then return false,'Visit the mechanic during your ride.' end
    local Residents=require('src.home_residents')
    local id=Residents.key(player);local resident=Residents.get(state,player)
    local part=trip.participants and trip.participants[id]
    if not resident or not part or part.slot~=(tonumber(player.id) or 1) or part.arrived then
        return false,'You are not an active rider on this trip.'
    end
    local level=resident.ridingUpgradeLevel or 0
    local rider=part.rider;local bike=rider and rider.bike;local ped=rider and rider.ped
    if not bike or not ped or ped.crash or rider.gear.mounted or rider.gear.engine or rider.gear.transition
        or (bike.speed or 0)>.05 or (ped.speed or 0)>.05 or bike.grounded==false
        or math.abs(bike.vy or 0)>.1 then return false,'Park, dismount and stop at the mechanic door.' end
    if (bike.upgradeLevel or 0)~=level then return false,'The motorcycle upgrade record is out of sync.' end
    local sites=world and (world.sites or world.roads and world.roads.sites)
    local site=sites and sites.byId.mechanic
    if not site or M.length(ped.x-site.door.x,ped.z-site.door.z)>Upgrades.DOOR_RADIUS
        or M.length(bike.x-site.parking.x,bike.z-site.parking.z)>Upgrades.BIKE_RADIUS then
        return false,'Visit the mechanic with your parked motorcycle.'
    end
    return true,nil,resident,bike
end
function Upgrades.quote(state,player,level)
    local resident=require('src.home_residents').get(state,player)
    if not resident or not Upgrades.CATALOG[level] then return nil end
    local current=resident.ridingUpgradeLevel or 0
    local offer=Upgrades.CATALOG[level]
    local status=level<=current and 'installed' or level>current+1 and 'locked'
        or state.home.balanceCents<offer.costCents and 'unaffordable' or 'available'
    return {offer=offer,current=Upgrades.profile(current),level=current,status=status,
        balanceCents=state.home.balanceCents,shortfallCents=math.max(0,offer.costCents-state.home.balanceCents)}
end
function Upgrades.purchase(state,player,trip,world,intent)
    if type(intent)~='table' or not trip or intent.token~=trip.token then return false,'That ride has ended.' end
    local okay,message,resident,bike=Upgrades.canVisit(state,player,trip,world)
    if not okay then return false,message end
    local level=resident.ridingUpgradeLevel or 0
    -- Live household needs and payroll can change while the quote is open.
    -- The bike's installed level is the transaction version; replaying an old
    -- order cannot debit funds twice. Retain the old command's revision check.
    if intent.expectedLevel~=nil then
        if not Upgrades.validLevel(intent.expectedLevel) or intent.expectedLevel~=level then
            return false,'Your bike changed. Review the updated quote.'
        end
    elseif intent.expectedRevision~=state.home.revision then return false,'Household details changed. Please try again.' end
    local offer=Upgrades.next(level)
    if not offer then return false,'Your motorcycle already has every upgrade.' end
    if intent.level~=offer.level then return false,'Buy the next motorcycle upgrade in order.' end
    if state.home.balanceCents<offer.costCents then return false,'Not enough household money for this upgrade.' end
    state.home.balanceCents=state.home.balanceCents-offer.costCents
    resident.ridingUpgradeLevel=offer.level;resident.revision=resident.revision+1
    bike.upgradeLevel=offer.level;state.home.revision=state.home.revision+1
    return true,offer.name..' installed.'
end
return Upgrades
