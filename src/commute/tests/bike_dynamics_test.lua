local Bike=require('src.commute.motorcycle')
local Rider=require('src.commute.rider')
local Test={}
local function world(height,offroad,blocked)
    local w={supportHeight=function(_,x,z)return height and height(x,z) or 0 end,
        roads={nearest=function()return offroad and 20 or 0,{width=6} end,
            blocked=function(_,_,x,z)return blocked and blocked(x,z) or false end}}
    w.height=w.supportHeight;return w
end
local function run(bike,w,seconds,hz,input,observe)
    for _=1,math.floor(seconds*hz+.5) do
        Bike.update(bike,input or {throttle=1},1/hz,w)
        if observe then observe(bike) end
    end
    return bike
end
local function crest(x)
    if x<20 then return x*.25 end
    if x<26 then return 5-(x-20)*.25 end
    return 3.5
end
function Test.run(check)
    local waterEdge={supportHeight=function()return 0 end,
        roads={nearest=function()return 20,{width=8,surface='dirt'}end,
            blocked=function(_,_,x)return x>=12 end}}
    local recoverable=Bike.new(0,0,0)
    run(recoverable,waterEdge,5,60,{throttle=1})
    local stuckX,stuckZ=recoverable.x,recoverable.z
    local rescued=Bike.rescue(recoverable,waterEdge)
    check('motorcycle_rescue_moves_away_from_water_and_clears_stuck_momentum',rescued
        and recoverable.x<10 and (recoverable.x-stuckX)^2+(recoverable.z-stuckZ)^2>=25 and recoverable.speed==0 and recoverable.vx==0 and recoverable.vz==0
        and not recoverable.reverse)
    local road=run(Bike.new(0,0,0),world(),25,60)
    local trail=run(Bike.new(0,0,0),world(nil,true),25,60)
    check('commute_trail_bike_retains_82_percent_offroad_speed',trail.speed/road.speed>.80
        and trail.speed/road.speed<.84 and road.speed>Bike.MAX_SPEED-.01 and road.speed<=Bike.MAX_SPEED)
    check('commute_flat_suspension_remains_in_contact_without_bobbing',road.grounded
        and math.abs(road.h)<1e-10 and math.abs(road.vy)<1e-10)
    local fall=Bike.new(0,0,0);fall.h=5;fall.vy=0;fall.grounded=false
    run(fall,world(),.5,120,{})
    check('commute_airborne_follows_gravity_instead_of_terrain_height',not fall.grounded
        and math.abs(fall.h-(5-.5*Bike.GRAVITY*.5^2))<.025 and math.abs(fall.vy+Bike.GRAVITY*.5)<1e-8)
    local landedAt,landingPulse
    run(fall,world(),3,120,{},function(p)
        if p.grounded and not landedAt then landedAt=p.h;landingPulse=p.landingPulse end
    end)
    check('commute_landings_damp_through_suspension_without_ground_snap',landedAt
        and math.abs(landedAt)>.001 and landingPulse>0 and fall.grounded and math.abs(fall.h)<.002 and math.abs(fall.vy)<.002)
    local results={}
    for _,hz in ipairs({30,60,120}) do
        local w=world(crest);local p=Bike.new(0,0,0);p.speed=12;p.gear=4
        local launchVy,maxGap,airTime=0,0,0
        run(p,w,8,hz,{throttle=1},function(b)
            if not b.grounded then launchVy=math.max(launchVy,b.vy);airTime=airTime+1/hz end
            maxGap=math.max(maxGap,b.h-crest(b.x))
        end)
        check('commute_hill_launch_preserves_upward_momentum_'..hz,launchVy>1 and maxGap>.3 and airTime>.2
            and p.grounded and math.abs(p.h-crest(p.x))<.01)
        results[#results+1]=p
    end
    check('commute_vertical_contact_and_jumps_match_30_60_120hz',
        math.abs(results[1].x-results[2].x)<1e-8 and math.abs(results[1].h-results[3].h)<1e-8
        and math.abs(results[1].vy-results[3].vy)<1e-8)
    local wall=world(nil,false,function(x)return x>=5 and x<=5.2 end)
    local airborne=Bike.new(0,0,0);airborne.upgradeLevel=3;airborne.speed=26.8;airborne.gear=4
    airborne.h=3;airborne.vy=3;airborne.grounded=false
    run(airborne,wall,.5,30,{throttle=1})
    check('commute_swept_walls_stop_fast_airborne_bikes',airborne.x<5-Bike.RADIUS+.01 and airborne.speed==0)
    local r=Rider.new(100,100,0);r.gear.outfit='geared';r.gear.mounted=true;r.gear.engine=true
    r.bike.h=4;r.bike.vy=0;r.bike.grounded=false
    local dismount,reason=Rider.command(r,'dismount',world())
    check('commute_cannot_dismount_at_airborne_apex',not dismount and reason:find('landed',1,true)~=nil)
    r.bike.upgradeLevel=3
    local restored=assert(Rider.restore(Rider.snapshot(r),world(),{x=100,z=100}))
    check('commute_save_restores_upgrades_parked_on_safe_ground',restored.bike.upgradeLevel==3
        and restored.bike.speed==0 and restored.bike.vy==0 and restored.bike.h==0 and restored.bike.grounded)
    local snapshot=Rider.snapshot(r);snapshot.bike.upgradeLevel=4
    check('commute_rejects_invalid_saved_upgrade',not Rider.restore(snapshot,world(),{x=100,z=100}))
    local upgraded=Bike.new(0,0,0);upgraded.upgradeLevel=3
    run(upgraded,world(),45,60,{throttle=1,boost=true})
    check('commute_top_upgrade_boost_reaches_about_75mph',upgraded.speed>=Bike.BOOST_MAX_SPEED-.4
        and upgraded.speed<=Bike.BOOST_MAX_SPEED)
    local Camera=require('src.commute.camera')
    local actor={x=100,z=100,h=5,heading=0,speed=6,pitch=.2,grade=0}
    local camera=Camera.new(actor,world());camera:setFirstPerson(true,actor)
    check('commute_first_person_eye_follows_airborne_body_and_pitch',math.abs(camera.eyeHeight-(5+1.65*math.cos(.2)))<1e-8
        and math.abs(camera.ridePitch-.2)<1e-8 and math.abs(camera.viewPitch-.165)<1e-8)
    camera:setFirstPerson(false,actor);actor.h=7
    for _=1,120 do camera:update(actor,1/120) end
    check('commute_outside_camera_follows_airborne_height',math.abs(camera.focusHeight-7)<.002)
end
return Test
