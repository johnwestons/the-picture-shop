-- Version 4 keeps the connected town plan and frames it with a seeded island shore.
local Base=require('src.commute.town_generator_v3')
local Terrain=require('src.commute.town_terrain_v3')
local Planner={VERSION=4}

function Planner.generate(seed,options)
    local prepared={}
    for key,value in pairs(options or {}) do prepared[key]=value end
    prepared.generatorVersion=prepared.generatorVersion or 4
    prepared.bounds=prepared.bounds or Terrain.BOUNDS
    prepared.shoreline=prepared.shoreline or Terrain.shoreline(seed)
    return Base.generate(seed,prepared)
end

return Planner
