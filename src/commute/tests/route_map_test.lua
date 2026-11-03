local Map=require('src.commute.route_map')
local Test={}
local function near(a,b)return math.abs(a-b)<.000001 end
local function fixture(count)
    local world={bounds={x0=-100,z0=40,x1=700,z1=440},waterLevel=0,sites={all={}},roads={paths={},destinations={}}}
    world.height=function(_,x,z)return (x<80 and z>200) and -1 or 3+x*.03 end
    for i=1,count do
        local x,z=-65+((i-1)%8)*95,80+math.floor((i-1)/8)*95
        local site={id=('building-%02d'):format(i),x=x,z=z,
            origin={x=x,z=z},foundation={minX=x-8,maxX=x+8,minZ=z-8,maxZ=z+8},
            footprints={{corners={{x=x-8,z=z-8},{x=x+8,z=z-8},{x=x+8,z=z+8},{x=x-8,z=z+8}}}}}
        world.sites.all[#world.sites.all+1]=site
        world.roads.destinations[site.id]={label='Building '..i,x=x,z=z}
    end
    return world
end
function Test.run(check)
    local world=fixture(16);local map=Map.new(world);local rect={x=24,y=132,width=912,height=522}
    check('travel_map_construction_is_lazy',map.background==nil and map.terrainSamples==0 and map.backgroundBuilds==0)
    local s=map:snapshot(rect,{x=300,z=240,heading=0},{destination='building-03',home='building-08'})
    check('travel_map_all_buildings_have_stable_numbered_names',#s.buildings==16
        and s.buildings[3].id=='building-03' and s.buildings[3].label=='Building 3'
        and s.buildings[3].destination and s.buildings[8].home)
    local bounds=Map.bounds(world);local l=s.layout.map
    local x0,y0=Map.project(world,l,bounds.x0,bounds.z0)
    local x1,y1=Map.project(world,l,bounds.x1,bounds.z1)
    check('travel_map_projection_preserves_rectangular_world_and_translated_bounds',
        near((x1-x0)/(y1-y0),2) and near(s.marker.x,(x0+x1)/2) and near(s.marker.y,(y0+y1)/2)
        and x0>=l.x and y0>=l.y and x1<=l.x+l.width and y1<=l.y+l.height)
    local good=true
    for _,case in ipairs({{0,1,0,'E'},{math.pi/2,0,1,'S'},{math.pi,-1,0,'W'},{-math.pi/2,0,-1,'N'}})do
        local marker=map:snapshot(rect,{x=300,z=240,heading=case[1]}).marker
        good=good and near(marker.dx,case[2]) and near(marker.dz,case[3]) and marker.label==case[4]
            and near(marker.tipX-marker.x,case[2]*13) and near(marker.tipY-marker.y,case[3]*13)
    end
    check('travel_map_heading_arrow_matches_world_cardinal_directions',good)
    local moved=map:snapshot(rect,{x=400,z=190,heading=-math.pi/4})
    check('travel_map_actor_position_and_heading_are_live',moved.marker.x>s.marker.x and moved.marker.y<s.marker.y
        and moved.marker.label=='NE' and map.backgroundBuilds==0)
    local allFit=true
    for _,size in ipairs({rect,{x=24,y=132,width=1232,height=722}})do
        for _,count in ipairs({5,16,24,32})do
            local model=Map.new(fixture(count));local snap=model:snapshot(size,{x=0,z=100,heading=1})
            for _,entry in ipairs(snap.buildings)do
                local r=entry.keyRect
                allFit=allFit and entry.label~='' and r.width>90 and r.height>=20
                    and r.x>=size.x and r.y>=size.y and r.x+r.width<=size.x+size.width
                    and r.y+r.height<=size.y+size.height-35
            end
            model:release()
        end
    end
    check('travel_map_building_key_fits_both_game_and_preview_panels',allFit)
    local oldCalls=0;local oldHeight=world.height
    world.height=function(...)oldCalls=oldCalls+1;return oldHeight(...)end
    map:prepare();local background=map.background;local samples=map.terrainSamples
    map:prepare();map:snapshot(rect,{x=301,z=241,heading=2});map:prepare()
    check('travel_map_terrain_and_static_geometry_are_cached_once',map.background==background
        and samples==Map.RESOLUTION^2 and oldCalls==samples and map.terrainSamples==samples and map.backgroundBuilds==1)
    map:release();map:release();map:prepare()
    check('travel_map_release_is_idempotent_and_cannot_recreate_resources',map.released and map.background==nil
        and map.backgroundBuilds==1 and map.terrainSamples==samples)
end
return Test
