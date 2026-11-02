-- Household resident identity survives player-slot changes and reconnects.
-- Store personal equipment here, never on a replaceable rendering avatar.
local Gear=require('src.commute.gear')
local Outfit={}
function Outfit.get(state,player)
    if type(state)~='table' or type(player)~='table' then return nil end
    local resident=require('src.home_residents').get(state,player)
    return resident and resident.ridingGear
end
function Outfit.allowed(state,player,action)
    local gear=Outfit.get(state,player)
    if not gear then return true end -- Existing saves have ordinary clothing.
    return Gear.allowed(gear,action)
end
function Outfit.store(state,player,gear)
    local resident=require('src.home_residents').get(state,player)
    if not resident then return false,'Your resident has not joined this household.' end
    if not Gear.valid(gear) then return false,'Invalid riding equipment.' end
    resident.ridingGear=Gear.snapshot(gear)
    resident.revision=resident.revision+1;state.home.revision=state.home.revision+1
    return true
end
return Outfit
