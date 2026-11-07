-- Cached, town-local road paths shared by scheduled residents and employees.
local Town=require('src.commute.town')
local Routes=require('src.commute.routes')
local DrivingPath=require('src.commute.driving_path')
local CommuterRoutes={}
local townCache=setmetatable({}, {__mode='k'})

local function roadWorld(town,activeWorld)
    if type(town)~='table' then return nil end
    if type(activeWorld)=='table' and activeWorld.townId==town.id and activeWorld.roads then
        return activeWorld
    end
    local ok,world=pcall(Town.world,town)
    return ok and world or nil
end

local function cacheFor(town,activeWorld)
    if type(town)~='table' then return nil end
    local cache=townCache[town]
    if not cache then
        local world=roadWorld(town,activeWorld)
        if not world then return nil end
        cache={world=world,planner=Routes.new(world.roads,{pavedOnly=true}),paths={}}
        townCache[town]=cache
    end
    return cache
end

function CommuterRoutes.world(town,activeWorld)
    local cache=cacheFor(town,activeWorld)
    return cache and cache.world or nil
end

function CommuterRoutes.route(town,fromId,toId,activeWorld)
    local cache=cacheFor(town,activeWorld)
    if not cache then return nil end
    local key=tostring(fromId)..'\0'..tostring(toId)
    if cache.paths[key]==false then return nil end
    if not cache.paths[key] then
        local route=cache.planner:find(fromId,toId)
        cache.paths[key]=route or false
    end
    return cache.paths[key]
end

function CommuterRoutes.sample(route,progress)
    if not route or type(route.points)~='table' or #route.points<2 then return nil end
    return DrivingPath.sample(route.points,route.length,progress)
end

return CommuterRoutes
