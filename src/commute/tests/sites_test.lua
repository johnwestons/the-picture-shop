local Roads=require('src.commute.roads')
local Sites=require('src.commute.sites')
local Rider=require('src.commute.rider')
local Bike=require('src.commute.motorcycle')
local Art=require('src.commute.warehouse_art')
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
    local camera=Camera.new(pad,world);camera.yaw=0
    check('commute_warehouse_front_view_uses_registered_door',Art.view(camera).index==5 and Art.view(camera).door)
    local views={};for yaw=0,315,45 do camera.yaw=yaw;views[Art.view(camera).index]=true end
    local count=0;for _ in pairs(views) do count=count+1 end
    check('commute_warehouse_orbit_resolves_all_eight_views',count==8)
    camera.yaw=0;local visible=Art.alpha(camera,{x=100,z=380,h=4.5},world)
    camera.yaw=180
    check('commute_warehouse_fades_only_when_covering_local_rider',visible==1 and Art.alpha(camera,{x=100,z=380,h=4.5},world)<.5)
    local art=Art.new()
    check('commute_warehouse_atlas_fits_mobile_texture_limit',art.image:getWidth()==2048 and art.image:getHeight()==1024)
    art:release()
end
return Test
