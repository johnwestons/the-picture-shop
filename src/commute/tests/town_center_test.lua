local Town = require('src.commute.town')
local Routes = require('src.commute.routes')
local Codec = require('src.net.codec')
local Test = {}
local limits = {maxBytes=524288,maxEntries=32768}

local function samePosition(a,b)
    return math.abs(a[1]-b[1])+math.abs(a[2]-b[2])+math.abs(a[3]-b[3])<.00001
end

function Test.run(check)
    local patterns,water,loops={},{},{}
    local sample
    for _,seed in ipairs({1,2,3,42,4261,712345,712346,609997962,Town.MAX_SEED}) do
        local town=assert(Town.generate(seed))
        local main=town.topology.mainStreet
        patterns[main.pattern]=true
        water[town.terrain.family]=true
        loops[town.topology.cycles]=true
        local roads,arms,oneWay,centerCount={},0,0,0
        local proper=true
        for _,road in ipairs(town.roads) do
            roads[road.id]=road
            if road.role=='main' then
                proper=proper and road.sidewalks and not road.oneWay and road.lanes>=2
                for _,i in ipairs({1,#road.points}) do
                    local p=road.points[i]
                    if p[1]==main.x and p[2]==main.z then arms=arms+1 end
                end
            elseif road.oneWay then
                oneWay=oneWay+1
                proper=proper and road.role=='local' and road.lanes==1
            end
        end
        for _,lot in ipairs(town.placements) do
            local frontage=roads[lot.frontageRoadId]
            local driveway=roads[lot.id..'-drive']
            local joins=false
            for _,point in ipairs(frontage.points) do
                if samePosition(point,driveway.points[1]) then joins=true end
            end
            proper=proper and joins and driveway.role=='drive'
            if lot.district=='center' then
                centerCount=centerCount+1
                proper=proper and frontage.role=='main'
            else proper=proper and frontage.role=='local' end
        end
        check('town_center_core_frontages_join_main_and_residences_join_side_streets_'..seed,
            town.generatorVersion==Town.GENERATOR_VERSION and proper and centerCount==9)
        check('town_center_has_promised_junction_and_one_way_alternative_'..seed,
            arms==(main.pattern=='crossroads' and 4 or 2) and oneWay>=1)
        local world=Town.world(town)
        -- A visible lane and both wheel tracks must follow the same profile,
        -- including beside driveways and across junction pavement.
        local peak,errorHeight=0,0
        for _,s in ipairs(world.roads.segments) do
            if s.role=='main' or s.role=='local' then
                peak=math.max(peak,math.abs(s.a.h-s.b.h)/s.len)
                for _,side in ipairs({-.3,0,.3}) do
                    local x=(s.a.x+s.b.x)*.5+s.nx*s.width*side
                    local z=(s.a.z+s.b.z)*.5+s.nz*s.width*side
                    errorHeight=math.max(errorHeight,math.abs(world:supportHeight(x,z)-(s.a.h+s.b.h)*.5))
                end
            end
        end
        check('town_graded_streets_follow_visible_lanes_'..seed,peak<.061 and errorHeight<.03)
        local routes=Routes.new(world.roads)
        local connected=true
        for id in pairs(town.destinations) do
            connected=connected and routes:find('warehouse',id)~=nil and routes:find(id,'warehouse')~=nil
        end
        check('town_center_destinations_remain_routable_both_directions_'..seed,connected)
        sample=town
    end
    check('town_center_seeds_vary_strip_crossroads_neighborhood_loops_and_watersheds',
        patterns.strip and patterns.crossroads and next(loops,next(loops))~=nil and next(water,next(water))~=nil)
    local encoded=assert(Codec.encode(sample,limits))
    local frozen=assert(Codec.decode(encoded,limits))
    local loaded=Town.world(frozen)
    check('town_center_frozen_data_roundtrip_and_generation_determinism',Town.valid(frozen)
        and loaded.townId==sample.id and assert(Codec.encode(frozen,limits))==encoded
        and assert(Codec.encode(assert(Town.generate(sample.seed)),limits))==encoded)
    local function rejected(edit)
        local bad=Town.copy(sample);edit(bad)
        local ok,valid=pcall(Town.valid,bad)
        return ok and not valid
    end
    check('town_center_rejects_invalid_saved_district_lane_and_frontage',
        rejected(function(t)t.topology=5 end)
        and rejected(function(t)t.roads[1].lanes=0 end)
        and rejected(function(t)t.placements[1].frontageRoadId='missing' end)
        and rejected(function(t)t.recreation[1].trailId='warehouse-drive' end))
    local old=assert(Town.generate(712345,{generatorVersion=2}))
    check('town_center_older_seed_and_presets_keep_original_road_plan',
        old.id=='town-v2-712345-1664945830' and Town.valid(old) and old.recreation==nil
        and assert(Town.generate(99,{generatorVersion=0})).id==Town.legacy().id)
    local fingerprint=Town.fingerprint(old)
    check('town_center_current_mechanic_name_keeps_saved_seed_fingerprint',
        Town.world(old).roads.destinations.mechanic.label=='Majic Blue' and Town.fingerprint(old)==fingerprint
        and loaded.roads.destinations.mechanic.label=='Majic Blue')
end
return Test
