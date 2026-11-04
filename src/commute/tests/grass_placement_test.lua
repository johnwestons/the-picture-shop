local Placement=require('src.commute.grass_placement')
local Surface=require('src.commute.vendor.terrain')
local Test={}
function Test.fixture()
    local world={size=128,seed=4261,streamed=true,terrain={routes={}},spawn={x=8,z=8},
        height=function()return 3 end,rawHeight=function()return 3 end,supportHeight=function()return 3 end}
    world.plan={height=world.height,habitat=function()return .15,0,.02 end,
        plantCommunity=function()return 'sunny-opening' end,shoreDistance=function()return math.huge end,
        riverDistance=function()return math.huge end,lakes={}}
    return world
end
function Test.run(check)
    local world=Test.fixture();local original=Surface.surface
    local okay,reason=xpcall(function()
        Surface.surface=function()return .3,.4,.2,'meadow',.85 end
        check('grass_placement_accepts_grassy_open_inland_terrain',Placement.sample(world,48,48)==3)
        local sites=require('src.commute.sites').create({placements={}})
        local roads=require('src.commute.roads').new({sites=sites,destinations={},bounds={x0=0,z0=0,x1=128,z1=128},
            definitions={{id='test-road',width=6,interpolation='linear',surface='paved',points={{12,48,3},{116,48,3}}}}})
        world.roads=roads;world.sites=sites
        check('grass_placement_excludes_pavement_and_full_wind_footprint',not Placement.sample(world,48,48)
            and not Placement.sample(world,48,53.5) and Placement.sample(world,48,55))
        for _,s in ipairs(roads.segments) do s.surface='dirt';s.width=3 end
        check('grass_placement_excludes_dirt_trail_and_edge',not Placement.sample(world,48,48)
            and not Placement.sample(world,48,52) and Placement.sample(world,48,54))
        world.roads=nil;world.sites=nil
        local Infrastructure=require('src.commute.infrastructure')
        local walk={corners={{40,45,3},{60,45,3},{60,47,3},{40,47,3}}}
        world.infrastructure=setmetatable({walkBins={['3:3']={walk},['4:3']={walk},['5:3']={walk}}},Infrastructure)
        check('grass_placement_excludes_sidewalks_and_neighbouring_bin_edges',not Placement.sample(world,48,46)
            and not Placement.sample(world,48,49) and Placement.sample(world,48,51))
        world.infrastructure=nil
        local site={distance=function(_,x)return math.max(0,math.abs(x-48)-3) end,
            hardscapeDistance=function(_,_,z)return math.max(0,math.abs(z-48)-2) end}
        world.sites={nearby=function()return {site} end}
        check('grass_placement_excludes_buildings_parking_and_entrance_paths',not Placement.sample(world,48,60)
            and not Placement.sample(world,60,48) and Placement.sample(world,60,60))
        world.sites=nil
        world.roads={recreation={{x=48,z=48,radius=4}}}
        check('grass_placement_preserves_recreation_clearings',not Placement.sample(world,48,53)
            and Placement.sample(world,48,56))
        world.roads=nil
        world.plan.shoreDistance=function()return 8 end
        check('grass_placement_keeps_coastal_beach_buffer',not Placement.sample(world,48,48))
        world.plan.shoreDistance=function()return 20 end
        world.plan.riverDistance=function()return 9,nil,nil,{waterWidth=3} end
        check('grass_placement_keeps_river_bank_buffer',not Placement.sample(world,48,48))
        world.plan.riverDistance=function()return math.huge end
        world.plan.lakes={{x=48,z=48,rx=5,rz=8,angle=.5}}
        check('grass_placement_keeps_lake_and_beach_buffer',not Placement.sample(world,48,48)
            and not Placement.sample(world,55,48) and Placement.sample(world,75,75))
        world.plan.lakes={};world.plan.marshAt=function()return .5 end
        check('grass_placement_excludes_wetlands',not Placement.sample(world,48,48))
        world.plan.marshAt=nil
        world.rawHeight=function(_,x,z)return (x-54)^2+(z-48)^2<1 and -.3 or 3 end
        check('grass_placement_detects_small_legacy_water_without_water_metadata',not Placement.sample(world,48,48))
        world.rawHeight=function()return 3 end
        world.height=function(_,x)return 3+x end
        check('grass_placement_excludes_steep_rock_faces',not Placement.sample(world,48,48))
        world.height=function()return 3 end
        for _,kind in ipairs({'stone','dirt','water','shore'}) do
            Surface.surface=function()return .3,.4,.2,kind,.8 end
            check('grass_placement_rejects_'..kind..'_even_with_tree_anchor',not Placement.sample(world,48,48))
        end
        Surface.surface=function()return .3,.4,.2,'litter',.1 end
        check('grass_placement_requires_grass_material_weight',not Placement.sample(world,48,48))
        check('grass_placement_rejects_world_edge_footprints',not Placement.sample(world,1,48))
    end,debug.traceback)
    Surface.surface=original;assert(okay,reason)
end
return Test
