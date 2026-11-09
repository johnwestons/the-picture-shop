local Terrain=require('src.commute.terrain')
local Roads=require('src.commute.roads')
local Bike=require('src.commute.motorcycle')
local Test={}
function Test.run(check)
    local roads=Roads.new();local w=roads:attach(Terrain.new())
    local connected,dry,grade=true,true,true;local maxGrade=0;local mismatch=''
    for _,s in ipairs(roads.segments) do
        maxGrade=math.max(maxGrade,math.abs(s.b.h-s.a.h)/s.len)
        local x,z=(s.a.x+s.b.x)*.5,(s.a.z+s.b.z)*.5
        if roads:blocked(w,x,z) then dry=false end
        local h=w:supportHeight(x,z)
        if math.abs(h-(s.a.h+s.b.h)*.5)>.3 then grade=false;mismatch=s.id..' '..x..','..z..' actual='..h..' road='..(s.a.h+s.b.h)*.5 end
    end
    check('commute_roads_all_centerlines_traversable',dry)
    check('commute_road_support_matches_authored_profile',grade,mismatch)
    check('commute_road_grades_are_gentle',maxGrade<.2,tostring(maxGrade))
    for id,p in pairs(roads.destinations) do
        local d=roads:nearest(p.x,p.z);connected=connected and d<.01
        check('commute_destination_dry_'..id,not roads:blocked(w,p.x,p.z) and math.abs(w:supportHeight(p.x,p.z)-p.h)<.001)
    end
    check('commute_destinations_connect_to_streets',connected)
    check('commute_bridge_spans_real_water',w:height(330,270)<0 and w:supportHeight(330,270)>3)
    check('commute_bridge_rails_block_side_exit',roads:blocked(w,330,273.2) and not roads:blocked(w,330,270))
    check('commute_water_blocks_riding',roads:blocked(w,w:riverCenterX(340),340))
    check('commute_vegetation_excludes_roads_and_lots',not roads:vegetationAllowed(330,270) and not roads:vegetationAllowed(100,380))
    local p=Bike.new(310,270,0)
    for _=1,180 do Bike.update(p,{throttle=1},1/60,w) end
    check('commute_bike_accelerates_across_bridge',p.x>320 and p.z==270 and p.speed>0 and p.h>3)
    local before=p.distance
    for _=1,120 do Bike.update(p,{brake=1},1/60,w) end
    check('commute_bike_brakes_to_stop',p.speed==0 and p.distance>=before)
    local stopped=p.distance;Bike.update(p,{steer=1},.1,w)
    check('commute_stopped_wheels_do_not_animate',p.distance==stopped)
    p=Bike.new(330,270,math.pi/2);p.speed=12
    for _=1,20 do Bike.update(p,{throttle=1},.1,w) end
    check('commute_fast_bike_cannot_tunnel_through_bridge_rail',p.z<272.5)
    local a,b=Bike.new(310,270,0),Bike.new(310,270,0)
    for _=1,60 do Bike.update(a,{throttle=1},1/60,w) end
    for _=1,30 do Bike.update(b,{throttle=1},1/30,w) end
    check('commute_acceleration_stable_across_frame_rates',math.abs(a.x-b.x)<.05)
end
return Test
