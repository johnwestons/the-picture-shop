local Roads=require('src.commute.roads')
local Sites=require('src.commute.sites')
local Rider=require('src.commute.rider')
local Bike=require('src.commute.motorcycle')
local Geometry=require('src.commute.structure_geometry')
local Camera=require('src.commute.camera')
local Test={}
function Test.run(check)
    local world=Roads.new():attach(require('src.commute.terrain').new())
    local site=Sites.warehouse;local pad=Roads.destinations.warehouse
    check('commute_warehouse_door_matches_existing_trip_gate',site.door.x==pad.x and site.door.z==pad.z-3)
    local flat,excluded=true,true
    for x=site.minX,site.maxX do for z=site.minZ,site.maxZ do
        flat=flat and math.abs(world:supportHeight(x,z)-site.h)<.001
        excluded=excluded and not world.roads:vegetationAllowed(x,z) and world.roads:blocked(world,x,z)
    end end
    check('commute_warehouse_has_level_foundation',flat)
    check('commute_warehouse_footprint_blocks_actors_and_flora',excluded)
    check('commute_warehouse_front_door_and_parking_remain_clear',Rider.clear(world,site.door.x,site.door.z,Rider.RADIUS)
        and Rider.clear(world,pad.x,pad.z,Bike.RADIUS))
    local bike=Bike.new(site.x,380,-math.pi/2);bike.speed=12
    for _=1,20 do Bike.update(bike,{throttle=1},.1,world) end
    check('commute_warehouse_fast_vehicle_cannot_tunnel_into_wall',bike.z>site.maxZ and bike.speed==0)
    local isolated=Sites.create({placements={{id='terrace',design='warehouse',origin={x=0,z=0,h=6}}}})
    local last=isolated:grade(0,6,0);local maxSlope=0;local monotonic=true
    for step=1,Sites.GRADE_APRON*4 do
        local h=isolated:grade(0,6+step*.25,0)
        monotonic=monotonic and h<=last+1e-9;maxSlope=math.max(maxSlope,math.abs(h-last)/.25);last=h
    end
    check('commute_foundation_apron_smoothly_returns_to_terrain',monotonic and last==0 and maxSlope<1)
    local townWorld=require('src.commute.town').world(assert(require('src.commute.town').generate(712345)))
    local roadHeights=true
    for _,segment in ipairs(townWorld.roads.segments) do
        if not segment.bridge then
            local x,z=(segment.a.x+segment.b.x)*.5,(segment.a.z+segment.b.z)*.5
            local _,_,expected=townWorld.roads:sample(x,z)
            roadHeights=roadHeights and math.abs(townWorld:height(x,z)-expected)<1e-6
        end
    end
    check('commute_broader_aprons_preserve_road_and_parking_elevations',roadHeights)
    local model=Geometry.build(site)
    check('commute_warehouse_mesh_entry_uses_registered_threshold',
        model.features.entrance[1].x==site.threshold.x and model.features.entrance[1].z==site.threshold.z)
    check('commute_warehouse_mesh_contains_all_facades_and_roof',
        model.bounds.minX<=site.minX and model.bounds.maxX>=site.maxX
        and model.bounds.minZ<=site.minZ and model.bounds.maxZ>=site.maxZ
        and model.bounds.maxH>site.h+site.height and model.counts.roofs>0)
    local camera=Camera.new(pad,world);camera.yaw=0
    local firstX,firstY=camera:screen(site.threshold.x,site.threshold.z,site.h+2)
    camera.yaw=1
    local nextX,nextY=camera:screen(site.threshold.x,site.threshold.z,site.h+2)
    check('commute_warehouse_geometry_projects_continuously_during_orbit',
        math.abs(firstX-nextX)+math.abs(firstY-nextY)>0
        and math.abs(firstX-nextX)+math.abs(firstY-nextY)<20)
    check('commute_warehouse_geometry_uses_bounded_static_vertex_data',#model.vertices<65000
        and #model.vertices%3==0 and #model.vertices[1]==12)

end
return Test
