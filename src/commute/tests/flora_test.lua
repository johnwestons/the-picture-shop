local Flora=require('src.commute.flora')
local Catalog=Flora.catalog
local Sprites=require('src.commute.vendor.plant_sprites')
local Layout=require('src.commute.vendor.plant_atlas_layout')
local Vegetation=require('src.commute.vegetation')
local Test={}
function Test.run(check)
    local complete=#Catalog.order==22 and #Catalog.states==12
    for _,item in ipairs(Sprites.buildItems(function(path)return love.filesystem.getInfo(path)~=nil end)) do
        complete=complete and love.filesystem.getInfo(item.path)~=nil and Layout.entries[item.key]~=nil
    end
    for _,path in ipairs(Layout.pages) do complete=complete and love.filesystem.getInfo(path)~=nil end
    check('commute_flora_full_published_catalog_and_atlas_available',complete and #Layout.pages==226)
    local world=require('src.commute.roads').new():attach(require('src.commute.terrain').new())
    local vegetation=Vegetation.new(world)
    local all=vegetation:visible(256,256,290,{month=5,totalDays=0})
    local kinds,ids,unique={},{},true
    for _,p in ipairs(all) do kinds[p.kind]=true;if ids[p.id] then unique=false end;ids[p.id]=true end
    -- Import the whole library, but don't force species into unsuitable habitat.
    check('commute_flora_town_has_woodland_riverbank_and_meadow_variety',kinds.bloodroot and kinds['virginia-bluebells']
        and kinds['cardinal-flower'] and kinds['purple-coneflower'] and kinds['little-bluestem'] and kinds.persimmon)
    check('commute_flora_expansion_candidate_ids_are_unique',unique)
    local samples={}
    for index,kind in ipairs(Catalog.order) do
        local d=Catalog.types[kind]
        samples[index]={kind=kind,id=index,x=index,z=1,h=2,plantAge=d.mature+1,
            lifePhase='live',phaseAge=0,biteAge=1000,amount=1}
    end
    local oak=samples[5];local calendar={month=4,totalDays=0}
    check('commute_flora_uses_authored_spring_autumn_and_winter_states',Catalog.appearance(oak,calendar)=='flower'
        and Catalog.appearance(oak,{month=11})=='autumn' and Catalog.appearance(oak,{month=1})=='dormant')
    local sprites=Sprites.new();local ready=false
    for _=1,300 do
        sprites:prepare(samples,calendar,0)
        assert(sprites.lastPrepareBytes<=Layout.pageBytes,'Unbounded flora upload')
        if sprites:readyFor(samples,calendar,0) then ready=true;break end
    end
    check('commute_flora_streams_visible_atlas_pages_with_bounded_uploads',ready and sprites.bytes>0
        and sprites.bytes<=sprites.effectiveBudget and sprites.maxUploadBytes<=Layout.pageBytes)
    local seasonal=true
    for month=1,12 do
        for _,p in ipairs(samples) do
            local key=sprites:plantKey(p,{month=month},0)
            seasonal=seasonal and key~=nil and sprites:hasKey(key)
        end
    end
    check('commute_flora_every_species_has_valid_appearance_in_every_month',seasonal)
    local original={kind='grass',id=725,x=10,z=10,h=1}
    Flora.present(original,4261,{month=5,totalDays=0})
    local initialAge=original.plantAge;local d=Catalog.types.grass
    Flora.present(original,4261,{month=5,totalDays=d.longevity-initialAge+1})
    check('commute_flora_simplified_lifecycle_enters_authored_dead_pose',original.lifePhase=='dead'
        and Catalog.appearance(original,{month=5})=='dead')
    Flora.present(original,4261,{month=5,totalDays=d.longevity-initialAge+d.deadDays+1})
    check('commute_flora_simplified_lifecycle_enters_authored_decay_pose',original.lifePhase=='decay')
    Flora.present(original,4261,{month=5,totalDays=d.longevity-initialAge+d.deadDays+d.decayDays+d.vacantDays})
    check('commute_flora_simplified_lifecycle_reseeds_at_same_position',original.lifePhase=='live' and original.plantAge==0
        and original.x==10 and original.z==10 and Catalog.appearance(original,{month=5})=='seed')
    local spring,_,springLitter=Flora.season({month=4})
    local autumn,_,autumnLitter=Flora.season({month=10})
    check('commute_flora_ground_seasons_follow_business_calendar',spring=='spring' and autumn=='autumn' and autumnLitter>springLitter)
    sprites:release()
end
return Test
