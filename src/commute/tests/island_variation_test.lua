local Town=require('src.commute.town')
local Options=require('src.commute.island_options')
local Routes=require('src.commute.routes')
local Generation=require('src.commute.tests.town_generation_test')
local Test={}

local function footprint(town)
    local cells={}
    local minX,maxX,minZ,maxZ=512,0,512,0
    for _,road in ipairs(town.roads) do
        if road.role=='main' or road.role=='local' then
            for _,point in ipairs(road.points) do
                local x,z=point[1],point[2]
                minX,maxX=math.min(minX,x),math.max(maxX,x)
                minZ,maxZ=math.min(minZ,z),math.max(maxZ,z)
                cells[math.floor(x/32)..':'..math.floor(z/32)]=true
            end
        end
    end
    return cells,maxX-minX,maxZ-minZ
end

local function distance(a,b)
    local changed=0
    for cell in pairs(a) do if not b[cell] then changed=changed+1 end end
    for cell in pairs(b) do if not a[cell] then changed=changed+1 end end
    return changed
end

function Test.run(check)
    local ruralFootprints={}
    local branchCounts={}
    local bypass,perimeter=false,false
    for _,seed in ipairs({1,2,3,4,5,42}) do
        local town=assert(Town.generate(seed,{island=Options.copy({roads=1})}))
        local cells,width,depth=footprint(town)
        ruralFootprints[#ruralFootprints+1]=cells
        branchCounts[#town.topology.mainStreet.roadIds]=true
        local throughCenter=false
        for _,road in ipairs(town.roads) do
            if road.role=='main' then
                local a,b=road.points[1],road.points[#road.points]
                local da=(a[1]-256)^2+(a[2]-256)^2
                local db=(b[1]-256)^2+(b[2]-256)^2
                if da<130^2 and db<130^2 then throughCenter=true end
            end
        end
        if throughCenter then bypass=true else perimeter=true end
        check('island_country_roads_fill_land_and_keep_every_address_'..seed,
            town.generatorVersion==Town.GENERATOR_VERSION and width>300 and depth>300
            and #town.placements==18 and Town.valid(town))
        if seed==3 then
            local repeated=assert(Town.generate(seed,{island=Options.copy({roads=1})}))
            check('island_country_seed_repeats_exact_saved_layout',Town.fingerprint(town)==Town.fingerprint(repeated))
        end
    end
    local varied=bypass and perimeter and branchCounts[11] and branchCounts[12]
    for i=2,#ruralFootprints do
        varied=varied and distance(ruralFootprints[1],ruralFootprints[i])>=10
    end
    check('island_country_rerolls_change_road_footprint_and_branch_count',varied)
    for _,roads in ipairs({2,3}) do
        for _,seed in ipairs({2,3,42}) do
            local town=assert(Town.generate(seed,{island=Options.copy({roads=roads})}))
            local _,width,depth=footprint(town)
            check(('island_density_%d_spreads_streets_%d'):format(roads,seed),
                width>300 and depth>300 and Town.valid(town))
        end
    end
    for _,case in ipairs({{roads=1,seed=1},{roads=1,seed=42},{roads=3,seed=3}}) do
        local town=assert(Town.generate(case.seed,{island=Options.copy({roads=case.roads})}))
        local world=Town.world(town)
        local routes=Routes.new(world.roads)
        local okay,reason=Generation.physical(world,routes)
        check(('island_density_%d_safe_routes_%d'):format(case.roads,case.seed),okay,reason)
    end
    local old=assert(Town.generate(712345,{generatorVersion=7,island=Options.copy({roads=1})}))
    check('island_older_generator_remains_available_for_saved_versions',old.generatorVersion==7 and Town.valid(old))
end

return Test
