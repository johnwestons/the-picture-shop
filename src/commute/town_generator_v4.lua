-- Version 4 keeps the connected town plan and frames it with a seeded island shore.
local Base=require('src.commute.town_generator_v3')
local Terrain=require('src.commute.town_terrain_v3')
local Planner={VERSION=4}

function Planner.generate(seed,options)
    local prepared={}
    for key,value in pairs(options or {}) do prepared[key]=value end
    prepared.generatorVersion=prepared.generatorVersion or 4
    prepared.bounds=prepared.bounds or Terrain.BOUNDS
    if not prepared.shoreline then
        if prepared.isCancelled and prepared.isCancelled() then error('Town generation cancelled.',0) end
        if prepared.progress then prepared.progress(.02,'Shaping island shoreline') end
        prepared.shoreline=Terrain.shoreline(seed,function(value,label)
            if prepared.progress then prepared.progress(.02+.055*(value or 0),label) end
        end,prepared.isCancelled)
        if prepared.isCancelled and prepared.isCancelled() then error('Town generation cancelled.',0) end
        if prepared.progress then prepared.progress(.08,'Shoreline ready') end
    end
    return Base.generate(seed,prepared)
end

return Planner
