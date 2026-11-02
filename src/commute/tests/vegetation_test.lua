local Terrain=require('src.commute.terrain')
local Roads=require('src.commute.roads')
local Vegetation=require('src.commute.vegetation')
local Test={}

local function attachedWorld()
    local world=Terrain.new()
    Roads.new():attach(world)
    return world
end

local function sameProps(a,b)
    if #a~=#b then return false end
    for i=1,#a do
        local x,y=a[i],b[i]
        if x.id~=y.id or x.kind~=y.kind or x.x~=y.x or x.z~=y.z
            or x.h~=y.h or x.scale~=y.scale then return false end
    end
    return true
end

function Test.run(check)
    local world=attachedWorld()
    local vegetation=Vegetation.new(world)
    local aroundRiver=vegetation:visible(330,270,82)
    local valid=true
    for _,p in ipairs(aroundRiver) do
        local raw=world:rawHeight(p.x,p.z)
        valid=valid and p.h>.4 and raw>.4 and world.roads:vegetationAllowed(p.x,p.z)
            and require('src.commute.flora').scales[p.kind]~=nil
    end
    check('commute_vegetation_skips_roads_water_and_unsupported_kinds',valid and #aroundRiver>0)

    local firstStats=vegetation:stats()
    local repeated=vegetation:visible(330,270,82)
    local secondStats=vegetation:stats()
    check('commute_vegetation_patch_hits_reuse_candidates',sameProps(aroundRiver,repeated)
        and firstStats.generated==secondStats.generated and firstStats.patches==secondStats.patches)

    local otherWorld=attachedWorld()
    local reordered=Vegetation.new(otherWorld)
    reordered:visible(420,210,36)
    local afterOtherView=reordered:visible(142,154,42)
    check('commute_vegetation_ids_positions_ignore_view_order',sameProps(
        vegetation:visible(142,154,42),afterOtherView))

    local traversed=Vegetation.new(attachedWorld())
    local beforeReload=traversed:visible(72,72,8)
    for pz=4,20 do
        for px=4,20 do
            traversed:visible(72+(px-4)*16,72+(pz-4)*16,0)
        end
    end
    local bounded=traversed:stats()
    local afterReload=traversed:visible(72,72,8)
    local reloaded=traversed:stats()
    check('commute_vegetation_lru_cache_is_bounded_and_reload_is_stable',
        bounded.patches<=256 and bounded.patches==256 and bounded.generated>=289
        and reloaded.patches<=256 and reloaded.generated>bounded.generated
        and sameProps(beforeReload,afterReload))
end

return Test
