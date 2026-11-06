-- Household-owned component progression; commands run through the authoritative host.
local M=require('src.commute.vendor.mathx')
local Upgrades={MAX_LEVEL=3,DOOR_RADIUS=2.2,BIKE_RADIUS=7}
local mph=1/2.236936

-- Legacy packages remain readable so existing household saves keep their
-- original road speed and acceleration. New work is stored per component.
Upgrades.CATALOG={
    {level=1,name='Trail tune',costCents=35000,maxSpeed=55*mph,boostMaxSpeed=60*mph,acceleration=1.38,
        description='Carburetor tuning, fresh filter and trail gearing.',parts='Intake service / gearing / tune'},
    {level=2,name='Performance kit',costCents=85000,maxSpeed=65*mph,boostMaxSpeed=70*mph,acceleration=1.73,
        description='A freer exhaust and revised fueling for stronger acceleration.',parts='Exhaust / fuel kit / final drive'},
    {level=3,name='High-output kit',costCents=180000,maxSpeed=70*mph,boostMaxSpeed=75*mph,acceleration=2.13,
        description='Engine and transmission work for the full 75 mph boost range.',parts='Engine kit / clutch / road gearing'},
}

Upgrades.CATEGORIES={
    {id='engine',name='Engine',part='Cylinder, piston and fueling',offers={
        {name='Fresh top end',costCents=42000,description='Tuned fueling adds power and torque for steep climbs.',effects={powerHp=1.5,torqueNm=1.4,acceleration=.10,hillPull=1.04,maxSpeedMph=.5}},
        {name='Big bore kit',costCents=78000,description='More displacement boosts power, torque and acceleration.',effects={powerHp=2.1,torqueNm=1.8,acceleration=.13,hillPull=1.06,maxSpeedMph=1.2}},
        {name='Competition build',costCents=128000,description='A high-output engine raises power and road speed.',effects={powerHp=2.6,torqueNm=2.2,acceleration=.16,hillPull=1.08,maxSpeedMph=1.6}},
    }},
    {id='clutch',name='Clutch',part='Clutch plates and springs',offers={
        {name='Heavy-duty plates',costCents=26000,description='Stronger clutch plates transfer power with less slip.',effects={clutchEfficiency=1.05,acceleration=.04,hillPull=1.03,shiftTimeMultiplier=.96}},
        {name='Performance springs',costCents=42000,description='Firmer clutch bite improves starts and steep climbs.',effects={clutchEfficiency=1.06,acceleration=.05,hillPull=1.05,shiftTimeMultiplier=.93}},
        {name='Race clutch',costCents=65000,description='Fast, consistent engagement keeps power on the rear wheel.',effects={clutchEfficiency=1.07,acceleration=.06,hillPull=1.06,shiftTimeMultiplier=.90}},
    }},
    {id='exhaust',name='Exhaust',part='Header, muffler and jetting',offers={
        {name='Free-flow muffler',costCents=32000,description='A tuned muffler adds power and road speed.',effects={powerHp=1.0,acceleration=.035,maxSpeedMph=1.2,boostMph=1.4}},
        {name='Expansion chamber',costCents=56000,description='A tuned chamber adds pull through the mid and top range.',effects={powerHp=1.4,acceleration=.05,maxSpeedMph=1.7,boostMph=1.8}},
        {name='Race exhaust',costCents=84000,description='Matched exhaust and fueling raise sustained output.',effects={powerHp=1.8,acceleration=.06,maxSpeedMph=2.2,boostMph=2.3}},
    }},
    {id='gearing',name='Chain & sprockets',part='Chain, countershaft and rear sprocket',offers={
        {name='Trail sprocket set',costCents=18000,description='Shorter gearing improves low-speed pull for hills and loose ground.',effects={hillPull=1.10,gearForceMultiplier=1.07,gearSpeedMultiplier=.97,maxSpeedMph=-.5}},
        {name='Balanced final drive',costCents=28000,description='A balanced ratio adds hill torque while keeping useful road speed.',effects={hillPull=1.08,gearForceMultiplier=1.06,gearSpeedMultiplier=1.01,maxSpeedMph=.8}},
        {name='Road sprocket set',costCents=36000,description='Taller gearing stretches the top end while preserving clean shifts.',effects={hillPull=1.03,gearForceMultiplier=1.02,gearSpeedMultiplier=1.04,maxSpeedMph=1.8,boostMph=2}},
    }},
    {id='brakes',name='Brakes',part='Pads, rotor and cable',offers={
        {name='Fresh brake pads',costCents=16000,description='New compound pads shorten stops and improve brake feel.',effects={brakeMultiplier=1.14}},
        {name='Oversize rotor',costCents=34000,description='A larger rotor adds stronger, more consistent stopping force.',effects={brakeMultiplier=1.16}},
        {name='Performance brake set',costCents=52000,description='A matched rotor and pad set delivers the strongest braking.',effects={brakeMultiplier=1.18}},
    }},
    {id='handling',name='Handling',part='Fork, shocks, bars and tires',offers={
        {name='Fork and shock service',costCents=24000,description='Fresh suspension response improves grip and control through turns.',effects={gripMultiplier=1.06,responseMultiplier=1.06,turnMultiplier=1.04}},
        {name='Steering damper',costCents=39000,description='A steadier front end tracks cleanly over ruts and at speed.',effects={gripMultiplier=1.07,responseMultiplier=1.07,turnMultiplier=1.05}},
        {name='Trail handling set',costCents=58000,description='Reworked suspension and controls give the most composed handling.',effects={gripMultiplier=1.08,responseMultiplier=1.08,turnMultiplier=1.06}},
    }},
    {id='durability',name='Durability',part='Hidden guards and frame reinforcement',offers={
        {name='Engine guard',costCents=22000,description='A hidden engine guard absorbs part of the force from a collision.',effects={damageMultiplier=.88}},
        {name='Frame protection',costCents=36000,description='Reinforced mounts and internal protection reduce crash damage.',effects={damageMultiplier=.87}},
        {name='Rally protection',costCents=54000,description='A reinforced frame and concealed guards provide maximum protection.',effects={damageMultiplier=.86}},
    }},
}
Upgrades.CATEGORY_BY_ID={}
for _,category in ipairs(Upgrades.CATEGORIES) do
    Upgrades.CATEGORY_BY_ID[category.id]=category
    for level,offer in ipairs(category.offers) do offer.level=level;offer.category=category.id end
end
local base={level=0,name='Standard trail bike',costCents=0,maxSpeed=45*mph,boostMaxSpeed=50*mph,acceleration=1.15,
    powerHp=11,torqueNm=14,hillPull=1,clutchEfficiency=1,gearForceMultiplier=1,gearSpeedMultiplier=1,
    brakeMultiplier=1,gripMultiplier=1,responseMultiplier=1,turnMultiplier=1,damageMultiplier=1,shiftTimeMultiplier=1}

function Upgrades.validLevel(level)
    return level==nil or M.finite(level) and level%1==0 and level>=0 and level<=Upgrades.MAX_LEVEL
end
function Upgrades.validCategory(id) return type(id)=='string' and Upgrades.CATEGORY_BY_ID[id]~=nil end
function Upgrades.emptyParts()
    local parts={};for _,category in ipairs(Upgrades.CATEGORIES) do parts[category.id]=0 end;return parts
end
function Upgrades.copyParts(parts)
    local copy=Upgrades.emptyParts()
    if type(parts)=='table' then for _,category in ipairs(Upgrades.CATEGORIES) do copy[category.id]=parts[category.id] or 0 end end
    return copy
end
function Upgrades.validParts(parts)
    if parts==nil then return true end
    if type(parts)~='table' then return false end
    for key,level in pairs(parts) do
        if not Upgrades.validCategory(key) or not M.finite(level) or level%1~=0 or level<0 or level>Upgrades.MAX_LEVEL then return false end
    end
    for _,category in ipairs(Upgrades.CATEGORIES) do
        local level=parts[category.id];if level~=nil and (not M.finite(level) or level%1~=0 or level<0 or level>Upgrades.MAX_LEVEL) then return false end
    end
    return true
end
local function freshProfile()
    local profile={};for k,v in pairs(base) do profile[k]=v end;return profile
end
local function applyEffects(profile,effects)
    for key,value in pairs(effects or {}) do
        if key=='powerHp' or key=='torqueNm' or key=='acceleration' or key=='maxSpeedMph' or key=='boostMph' then
            if key=='maxSpeedMph' then profile.maxSpeed=profile.maxSpeed+value*mph
            elseif key=='boostMph' then profile.boostMaxSpeed=profile.boostMaxSpeed+value*mph
            else profile[key]=profile[key]+value end
        elseif key=='hillPull' or key=='clutchEfficiency' or key=='gearForceMultiplier' or key=='gearSpeedMultiplier'
            or key=='brakeMultiplier' or key=='gripMultiplier' or key=='responseMultiplier' or key=='turnMultiplier'
            or key=='damageMultiplier' or key=='shiftTimeMultiplier' then
            profile[key]=profile[key]*value
        end
    end
end
function Upgrades.profile(parts,legacyLevel)
    if type(parts)=='number' then
        local old=Upgrades.CATALOG[parts] or base
        local result=freshProfile();result.level=old.level or 0;result.name=old.name
        result.maxSpeed=old.maxSpeed or result.maxSpeed;result.boostMaxSpeed=old.boostMaxSpeed or result.boostMaxSpeed
        result.acceleration=old.acceleration or result.acceleration;return result
    end
    local result=freshProfile();parts=Upgrades.copyParts(parts)
    local old=Upgrades.CATALOG[legacyLevel or 0]
    if old then
        result.maxSpeed=old.maxSpeed;result.boostMaxSpeed=old.boostMaxSpeed;result.acceleration=old.acceleration
        result.level=old.level;result.name=old.name
    end
    for _,category in ipairs(Upgrades.CATEGORIES) do
        for level=1,parts[category.id] do applyEffects(result,category.offers[level].effects) end
    end
    result.installedParts=parts
    if not old then
        local names={};for _,category in ipairs(Upgrades.CATEGORIES) do if parts[category.id]>0 then names[#names+1]=category.name end end
        result.name=#names==0 and base.name or table.concat(names,' / ')
    end
    return result
end
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
    local residentParts=Upgrades.copyParts(resident.ridingUpgradeParts)
    local rider=part.rider;local bike=rider and rider.bike;local ped=rider and rider.ped
    if not bike or not ped or ped.crash or rider.gear.mounted or rider.gear.engine or rider.gear.transition
        or (bike.speed or 0)>.05 or (ped.speed or 0)>.05 or bike.grounded==false
        or math.abs(bike.vy or 0)>.1 then return false,'Park, dismount and stop at the mechanic door.' end
    local bikeParts=Upgrades.copyParts(bike.upgradeParts)
    if (bike.upgradeLevel or 0)~=level then return false,'The motorcycle upgrade record is out of sync.' end
    for _,category in ipairs(Upgrades.CATEGORIES) do
        if residentParts[category.id]~=bikeParts[category.id] then return false,'The motorcycle upgrade record is out of sync.' end
    end
    local sites=world and (world.sites or world.roads and world.roads.sites)
    local site=sites and sites.byId.mechanic
    if not site or M.length(ped.x-site.door.x,ped.z-site.door.z)>Upgrades.DOOR_RADIUS
        or M.length(bike.x-site.parking.x,bike.z-site.parking.z)>Upgrades.BIKE_RADIUS then
        return false,'Visit the mechanic with your parked motorcycle.'
    end
    return true,nil,resident,bike
end
function Upgrades.quote(state,player,selection)
    local resident=require('src.home_residents').get(state,player)
    if not resident then return nil end
    if type(selection)=='number' then
        local offer=Upgrades.CATALOG[selection];if not offer then return nil end
        local current=resident.ridingUpgradeLevel or 0
        local status=selection<=current and 'installed' or selection>current+1 and 'locked'
            or state.home.balanceCents<offer.costCents and 'unaffordable' or 'available'
        return {offer=offer,current=Upgrades.profile(current),level=current,status=status,
            balanceCents=state.home.balanceCents,shortfallCents=math.max(0,offer.costCents-state.home.balanceCents)}
    end
    if not Upgrades.validCategory(selection) then return nil end
    local category=Upgrades.CATEGORY_BY_ID[selection];local parts=Upgrades.copyParts(resident.ridingUpgradeParts)
    local currentLevel=parts[selection];local offer=category.offers[currentLevel+1]
    local current=Upgrades.profile(parts,resident.ridingUpgradeLevel)
    if not offer then return {category=category,current=current,currentLevel=currentLevel,status='maxed',balanceCents=state.home.balanceCents,shortfallCents=0} end
    local nextParts=Upgrades.copyParts(parts);nextParts[selection]=offer.level
    local after=Upgrades.profile(nextParts,resident.ridingUpgradeLevel)
    local status=state.home.balanceCents<offer.costCents and 'unaffordable' or 'available'
    return {category=category,offer=offer,current=current,after=after,currentLevel=currentLevel,level=currentLevel,
        status=status,balanceCents=state.home.balanceCents,shortfallCents=math.max(0,offer.costCents-state.home.balanceCents)}
end
function Upgrades.purchase(state,player,trip,world,intent)
    if type(intent)~='table' or not trip or intent.token~=trip.token then return false,'That ride has ended.' end
    local okay,message,resident,bike=Upgrades.canVisit(state,player,trip,world)
    if not okay then return false,message end
    if intent.category then
        if not Upgrades.validCategory(intent.category) then return false,'Choose an available motorcycle component.' end
        local current=Upgrades.copyParts(resident.ridingUpgradeParts)[intent.category]
        if intent.expectedCategoryLevel~=current then return false,'Your bike changed. Review the updated quote.' end
        local offer=Upgrades.CATEGORY_BY_ID[intent.category].offers[current+1]
        if not offer then return false,'This component is fully upgraded.' end
        if intent.level~=offer.level then return false,'Choose the next upgrade for this component.' end
        if state.home.balanceCents<offer.costCents then return false,'Not enough household money for this upgrade.' end
        state.home.balanceCents=state.home.balanceCents-offer.costCents
        resident.ridingUpgradeParts=Upgrades.copyParts(resident.ridingUpgradeParts)
        resident.ridingUpgradeParts[intent.category]=offer.level;resident.revision=resident.revision+1
        bike.upgradeParts=Upgrades.copyParts(resident.ridingUpgradeParts);state.home.revision=state.home.revision+1
        return true,offer.name..' installed.'
    end
    local level=resident.ridingUpgradeLevel or 0
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
