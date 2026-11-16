local Town=require('src.commute.town')
local Test={}
function Test.run(_,check)
    for _,case in ipairs({{seed=712345},{seed=42},{seed=1,roads=1},{seed=77,version=1}}) do
        local town=assert(Town.generate(case.seed,{generatorVersion=case.version,
            island=case.roads and require('src.commute.island_options').copy({roads=case.roads})}))
        local before=Town.fingerprint(town)
        local world=Town.world(town);local site=world.sites.byId.clinic
        local prefix='medical_town_'..case.seed
        check(prefix..'_clinic_exists',site~=nil)
        check(prefix..'_rescue_farm_exists',world.sites.byId.farm~=nil)
        check(prefix..'_saved_town_not_mutated',Town.valid(town) and before==Town.fingerprint(town))
        check(prefix..'_clinic_route_connected',require('src.commute.routes').new(world.roads):find('warehouse','clinic')~=nil)
        check(prefix..'_clinic_door_walkable',require('src.commute.rider').clear(world,site.door.x,site.door.z,.3))
        local mesh=require('src.commute.structure_geometry').build(site)
        check(prefix..'_clinic_has_medical_sign',mesh.features.clinicCrosses and #mesh.features.clinicCrosses==1)
    end
end
return Test
