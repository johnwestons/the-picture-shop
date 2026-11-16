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

local function roadLength(road)
    local length=0
    for i=2,#road.points do
        local a,b=road.points[i-1],road.points[i]
        length=length+math.sqrt((b[1]-a[1])^2+(b[2]-a[2])^2)
    end
    return length
end

function Test.run(check)
    local ruralFootprints={}
    local newCountryTopology=true
    for _,seed in ipairs({1,2,3,4,5,42}) do
        local town=assert(Town.generate(seed,{island=Options.copy({roads=1})}))
        local cells,width,depth=footprint(town)
        ruralFootprints[#ruralFootprints+1]=cells
        local core=town.topology.mainStreet
        local throughCenter,perimeterRoad=false,false
        local coreArms,curved=0,0
        for _,road in ipairs(town.roads) do
            if road.role=='main' then
                local a,b=road.points[1],road.points[#road.points]
                local da=(a[1]-256)^2+(a[2]-256)^2
                local db=(b[1]-256)^2+(b[2]-256)^2
                if da<130^2 and db<130^2 then throughCenter=true end
                if road.id~='mainland-connector' and da>130^2 and db>130^2 then perimeterRoad=true end
                if math.abs(a[1]-core.x)<.01 and math.abs(a[2]-core.z)<.01 then coreArms=coreArms+1 end
                if math.abs(b[1]-core.x)<.01 and math.abs(b[2]-core.z)<.01 then coreArms=coreArms+1 end
                local length=roadLength(road)
                local chord=math.sqrt((b[1]-a[1])^2+(b[2]-a[2])^2)
                if chord>0 then
                    local ratio=length/chord
                    if ratio>1.0008 then curved=curved+1 end
                end
            end
        end
        local firstSpine,secondSpine=town.roads[1],town.roads[2]
        local spineStart,spineEnd=firstSpine.points[1],secondSpine.points[#secondSpine.points]
        local spineChord=math.sqrt((spineEnd[1]-spineStart[1])^2+(spineEnd[2]-spineStart[2])^2)
        local spineRatio=(roadLength(firstSpine)+roadLength(secondSpine))/math.max(.001,spineChord)
        check('island_country_roads_fill_land_and_keep_every_address_'..seed,
            town.generatorVersion==Town.GENERATOR_VERSION and width>300 and depth>300
            and #town.placements>=18 and town.destinations.clinic~=nil and Town.valid(town),
            string.format('placements=%d width=%.1f depth=%.1f valid=%s clinic=%s',
                #town.placements,width,depth,tostring(Town.valid(town)),tostring(town.destinations.clinic~=nil)))
        local topology=core.pattern=='country' and #core.roadIds==12
            and throughCenter and not perimeterRoad and coreArms==2 and curved>=2 and spineRatio>1.015
        newCountryTopology=newCountryTopology and topology
        check('island_country_roads_use_curved_inland_spine_without_perimeter_loop_'..seed,
            topology,('pattern=%s roads=%d coreArms=%d inland=%s perimeter=%s curved=%d spineRatio=%.3f')
                :format(tostring(core.pattern),#core.roadIds,coreArms,tostring(throughCenter),
                    tostring(perimeterRoad),curved,spineRatio))
        if seed==3 then
            local repeated=assert(Town.generate(seed,{island=Options.copy({roads=1})}))
            check('island_country_seed_repeats_exact_saved_layout',Town.fingerprint(town)==Town.fingerprint(repeated))
        end
    end
    local varied=newCountryTopology
    for i=2,#ruralFootprints do
        varied=varied and distance(ruralFootprints[1],ruralFootprints[i])>=10
    end
    check('island_country_rerolls_change_road_footprint_without_repeating_a_perimeter',varied)
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
    local previousCountry=assert(Town.generate(712345,{generatorVersion=13,island=Options.copy({roads=1})}))
    check('island_saved_country_generator_13_remains_readable',previousCountry.generatorVersion==13
        and previousCountry.topology.mainStreet.pattern=='crossroads' and Town.valid(previousCountry))
end

return Test
