local Camera=require('src.commute.camera')
local FP=require('src.commute.first_person_camera')
local Body=require('src.commute.first_person_bike')
local Landing=require('src.commute.landing_camera')
local Test={}
local function near(a,b,tolerance)return math.abs(a-b)<(tolerance or 1e-6)end
local function advance(camera,actor,seconds,hz)
    hz=hz or 60
    for _=1,math.floor(seconds*hz+.5) do camera:update(actor,1/hz) end
end
local function jumper()
    return {x=100,z=100,h=4,vy=3,vx=12,vz=5,speed=13,heading=0,pitch=.6,lean=0,grounded=false}
end
function Test.run(check)
    local world={size=512,height=function()return -3 end,supportHeight=function()return 0 end}
    local actor=jumper();local target=assert(Landing.target(world,actor))
    local height=actor.h+actor.vy*target.time-.5*Landing.GRAVITY*target.time^2
    check('landing_camera_predicts_ballistic_contact_along_actual_velocity',near(target.x,100+12*target.time)
        and near(target.z,100+5*target.time) and math.abs(height-target.h)<.03 and target.h==0)
    local bridge={height=world.height,supportHeight=function()return 2 end}
    local bridgeTarget=assert(Landing.target(bridge,actor))
    check('landing_camera_uses_bridge_support_instead_of_ground_below',bridgeTarget.h==2 and bridgeTarget.time<target.time)
    local slope={height=world.height,supportHeight=function(_,x,z)return (x-100)*.04+(z-100)*.1 end}
    local slopeTarget=assert(Landing.target(slope,actor))
    check('landing_camera_samples_the_terrain_at_predicted_landing',slopeTarget.h>.5
        and near(slopeTarget.h,slope:supportHeight(slopeTarget.x,slopeTarget.z)))
    local bounded={size=110,height=function(_,x,z)assert(x>=0 and z>=0 and x<=110 and z<=110);return 0 end}
    local boundary=Landing.target(bounded,actor)
    check('landing_camera_keeps_terrain_queries_inside_world_bounds',boundary.x<=110 and boundary.z<=110)
    local camera=Camera.new(actor,world);camera:setFirstPerson(true,actor)
    advance(camera,actor,.8)
    check('landing_camera_looks_down_toward_touchdown_despite_nose_up_bike',camera.viewPitch<-.13
        and camera.viewPitch>=-math.rad(32)-.001 and camera.ridePitch==actor.pitch and camera.landingTarget~=nil)
    local forward,up,right=Body.point(760,300)
    local wx,wy=FP.screen(camera,actor.x+forward*math.cos(actor.pitch)-up*math.sin(actor.pitch),
        actor.z+right,actor.h+forward*math.sin(actor.pitch)+up*math.cos(actor.pitch))
    local bx,by=FP.screen(Body.camera(camera),forward,right,up)
    check('landing_camera_keeps_handlebars_attached_to_pitched_motorcycle',near(wx,bx) and near(wy,by))
    camera.lookPitch=math.rad(40);advance(camera,actor,.8)
    local _,manualPitch=FP.tiltView(camera.rideHeading-camera.bikeHeading+camera.headYaw,
        FP.NEUTRAL_PITCH+camera.headPitch,camera.rideRoll,camera.ridePitch)
    check('landing_camera_respects_deliberate_manual_pitch',near(camera.viewPitch,manualPitch,.001))
    camera.lookPitch=0;camera.lookYaw=math.pi;advance(camera,actor,1.2)
    local _,behindPitch=FP.tiltView(camera.rideHeading-camera.bikeHeading+camera.headYaw,
        FP.NEUTRAL_PITCH+camera.headPitch,camera.rideRoll,camera.ridePitch)
    check('landing_camera_does_not_pull_behind_head_look_toward_forward_landing',near(camera.viewPitch,behindPitch,.001))
    camera.lookYaw=0;advance(camera,actor,1)
    actor.h,actor.pitch,actor.vy,actor.grounded=0,0,0,true
    local previous=camera.viewPitch;local smooth=true
    for _=1,120 do
        camera:update(actor,1/60)
        smooth=smooth and math.abs(camera.viewPitch-previous)<.12;previous=camera.viewPitch
    end
    check('landing_camera_recovers_smoothly_after_touchdown',smooth and math.abs(camera.landingLookPitch)<.001
        and near(camera.viewPitch,FP.NEUTRAL_PITCH,.001) and not camera.landingTarget)
    actor=jumper();actor.grounded=true
    camera=Camera.new(actor,world);camera:setFirstPerson(true,actor)
    check('landing_camera_preserves_normal_grounded_hill_pitch',not camera.landingTarget and camera.landingLookPitch==0
        and near(camera.viewPitch,actor.pitch+FP.NEUTRAL_PITCH))
    actor.grounded=false
    check('landing_camera_authoritative_grounded_visual_overrides_stale_actor',not Landing.target(world,actor,{grounded=true,h=0}))
    local remote=jumper();remote.vx,remote.vz,remote.speed=0,0,0
    local remoteTarget=Landing.target(world,remote,{grounded=false,h=4,vy=3,speed=12})
    check('landing_camera_uses_authoritative_speed_when_snapshot_has_no_velocity',remoteTarget.x>110 and remoteTarget.z==100)
    local samples={}
    for _,hz in ipairs({30,60,120}) do
        actor=jumper();actor.grounded=true
        camera=Camera.new(actor,world);camera:setFirstPerson(true,actor)
        actor.grounded=false;advance(camera,actor,.5,hz);samples[#samples+1]=camera.viewPitch
    end
    check('landing_camera_response_matches_at_30_60_120hz',near(samples[1],samples[2],.002) and near(samples[1],samples[3],.002))
    actor=jumper();camera=Camera.new(actor,world);advance(camera,actor,1)
    check('landing_camera_outside_view_includes_lower_ground_without_losing_rider',camera.focusHeight>actor.h-2.5
        and camera.focusHeight<actor.h-2.3 and actor.x==100 and actor.z==100 and actor.pitch==.6 and actor.vy==3)
    local Bike=require('src.commute.motorcycle')
    local road={height=function()return 0 end,supportHeight=function()return 0 end,
        roads={nearest=function()return 0,{width=8} end,blocked=function()return false end}}
    actor=Bike.new(100,100,0)
    actor.h,actor.vy,actor.pitch,actor.grounded,actor.speed=2,5,.4,false,12
    Bike.resetHorizontal(actor)
    camera=Camera.new(actor,road);camera:setFirstPerson(true,actor)
    local sawApex,sawLanding,visible=false,false,true
    local previousVy=actor.vy
    for frame=1,180 do
        Bike.update(actor,{},1/120,road);camera:update(actor,1/120)
        if previousVy>0 and actor.vy<0 then sawApex=camera.viewPitch<0 end
        if not actor.grounded and frame<=90 then
            local landing=camera.landingTarget
            local _,y,depth=camera:screen(landing.x,landing.z,landing.h)
            visible=visible and depth>0 and y>0 and y<880
        end
        sawLanding=sawLanding or actor.grounded
        previousVy=actor.vy
    end
    check('landing_camera_actual_gravity_jump_keeps_touchdown_visible_through_ascent_and_apex',visible and sawApex and sawLanding)
end
return Test
