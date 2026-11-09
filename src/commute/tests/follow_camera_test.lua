local Camera=require('src.commute.camera')
local Test={}
local world={size=512,height=function()return 2 end,supportHeight=function()return 2 end}
local tau=math.pi*2
local function difference(a,b)return (a-b+180)%360-180 end
local function rider()
    return {bike={x=240,z=240,h=2,heading=0,speed=8,vx=8,vz=0},
        ped={x=240,z=241,h=2,heading=0,speed=0},gear={mounted=true}}
end
local function advance(camera,r,seconds,hz)
    hz=hz or 60
    for _=1,math.floor(seconds*hz+.5) do camera:updateRide(r,1/hz) end
end
function Test.run(check)
    local defaultFollow=Camera.new({x=240,z=240,heading=0},world)
    defaultFollow:setOutsideMode('follow',defaultFollow.lastActor)
    local followTilt=defaultFollow.tilt
    defaultFollow:orbit(0,3)
    check('camera_follow_starts_at_a_steeper_over_the_shoulder_angle_and_remains_adjustable',
        followTilt==Camera.FOLLOW_TILT_DEFAULT and defaultFollow.tilt==followTilt+3)
    local r=rider();local camera=Camera.new(r.bike,world)
    camera:orbit(37,7);camera:zoomBy(-2);camera:pan(20,10)
    local zoom,targetZoom,tilt,panX,panY=camera.zoom,camera.targetZoom,camera.tilt,camera.offsetX,camera.offsetY
    r.bike.heading=math.pi/2;advance(camera,r,.5)
    check('camera_fixed_angle_remains_fixed_as_bike_turns',camera.outsideMode=='fixed' and camera.yaw==37)
    check('camera_unknown_outside_mode_is_rejected',not camera:setOutsideMode('invalid') and camera.outsideMode=='fixed')
    assert(camera:setOutsideMode('follow',r.bike))
    check('camera_follow_selection_starts_directly_behind_rider',camera:headingDirection16(r.bike.heading)=='north')
    check('camera_follow_selection_preserves_other_camera_adjustments',camera.targetZoom==targetZoom
        and camera.tilt==tilt and camera.offsetX==panX and camera.offsetY==panY)
    local allBehind=true
    for i=0,15 do
        r.bike.heading=i*tau/16;advance(camera,r,1.5)
        local x0,y0=camera:screen(r.bike.x,r.bike.z,r.bike.h)
        local x1,y1=camera:screen(r.bike.x+math.cos(r.bike.heading)*3,
            r.bike.z+math.sin(r.bike.heading)*3,r.bike.h)
        allBehind=allBehind and math.abs(x1-x0)<.001 and y1<y0
            and camera:headingDirection16(r.bike.heading)=='north'
    end
    check('camera_follow_places_forward_above_rider_for_all_sixteen_headings',allBehind)
    -- Crossing the zero-degree world heading must not spin the long way round.
    r.bike.heading=tau-.02;advance(camera,r,1.5)
    local yaw=camera.yaw;r.bike.heading=.02;camera:updateRide(r,1/60)
    check('camera_follow_wraps_shortest_way_without_yaw_snap',difference(camera.yaw,yaw)<0
        and math.abs(difference(camera.yaw,yaw))<.2)
    advance(camera,r,1.5)
    r.bike.reverse=true;r.bike.vx,r.bike.vz=-8,6
    advance(camera,r,.5)
    check('camera_follow_tracks_body_heading_during_reverse_or_slide',camera:headingDirection16(r.bike.heading)=='north')
    local beforeX,beforeZ=r.bike.x,r.bike.z
    camera:orbit(60,3);advance(camera,r,.4)
    check('camera_follow_allows_temporary_manual_orbit',math.abs(difference(camera.yaw,-r.bike.heading*180/math.pi-90))>55)
    advance(camera,r,2.5)
    check('camera_follow_returns_behind_after_orbit_release',math.abs(difference(camera.yaw,-r.bike.heading*180/math.pi-90))<.01)
    camera:orbit(-70,0);camera:recenter()
    check('camera_follow_center_immediately_clears_temporary_orbit',camera.followYawOffset==0
        and camera.followOrbitHold==0 and camera.followYawVelocity==0
        and camera:headingDirection16(r.bike.heading)=='north')
    camera:zoomBy(-2);camera:orbit(0,10);advance(camera,r,.5)
    zoom,targetZoom,tilt=camera.zoom,camera.targetZoom,camera.tilt
    assert(camera:toggleView(r));r.bike.heading=math.pi
    advance(camera,r,.7);assert(camera:toggleView(r))
    check('camera_follow_returns_from_first_person_behind_current_heading',not camera.firstPerson
        and camera.outsideMode=='follow' and camera:headingDirection16(r.bike.heading)=='north'
        and camera.zoom==zoom and camera.targetZoom==targetZoom and camera.tilt==tilt)
    assert(camera:setOutsideMode('fixed',r.bike))
    check('camera_fixed_mode_restores_previous_manual_yaw',camera.yaw==37 and camera.targetZoom==targetZoom and camera.tilt==tilt)
    assert(camera:setOutsideMode('follow',r.bike));camera:updateRide(r,0)
    local oldYaw=camera.yaw;r.gear.mounted=false;r.ped.heading=math.pi/2
    advance(camera,r,1)
    check('camera_follow_preference_does_not_rotate_on_foot',camera.outsideMode=='follow' and camera.yaw==oldYaw)
    r.gear.mounted=true;r.bike.heading=0;advance(camera,r,1.5)
    check('camera_follow_resumes_when_rider_remounts',camera:headingDirection16(r.bike.heading)=='north')
    camera:orbit(75,0);r.gear.transition={kind='dismount'};camera:updateRide(r,1/60)
    check('camera_follow_dismount_clears_stale_temporary_orbit',camera.followYawOffset==0
        and camera.followOrbitHold==0 and camera.followYawVelocity==0)
    r.gear.mounted=false;r.gear.transition=nil;advance(camera,r,.2)
    r.gear.mounted=true;advance(camera,r,.8)
    check('camera_follow_remount_recenters_without_old_orbit_hold',
        math.abs(difference(camera.yaw,-r.bike.heading*180/math.pi-90))<.11)
    assert(camera:toggleView(r));r.gear.transition={kind='dismount'};camera:updateRide(r,1/60)
    check('camera_follow_dismount_exits_first_person_and_keeps_preference',not camera.firstPerson
        and camera.outsideMode=='follow' and camera.followMounted==false)
    check('camera_follow_never_changes_bike_position_or_velocity',r.bike.x==beforeX and r.bike.z==beforeZ
        and r.bike.vx==-8 and r.bike.vz==6 and r.bike.speed==8)
    local samples={}
    for _,hz in ipairs({30,60,120}) do
        local actor=rider();local c=Camera.new(actor.bike,world);c:setOutsideMode('follow',actor.bike)
        actor.bike.heading=math.pi/2;advance(c,actor,.5,hz)
        c:orbit(50,0);advance(c,actor,1.2,hz)
        samples[#samples+1]=c.yaw
    end
    check('camera_follow_angular_response_matches_30_60_120hz',math.abs(difference(samples[1],samples[2]))<.5
        and math.abs(difference(samples[1],samples[3]))<.5)
    local turner=rider();local turningCamera=Camera.new(turner.bike,world)
    turningCamera:setOutsideMode('follow',turner.bike);local stable=true;local previous=turningCamera.yaw
    for frame=1,720 do
        turner.bike.heading=(frame/120)%tau;turningCamera:updateRide(turner,1/120)
        stable=stable and math.abs(difference(turningCamera.yaw,previous))<1
            and math.abs(difference(turningCamera.yaw,-turner.bike.heading*180/math.pi-90))<11
        previous=turningCamera.yaw
    end
    check('camera_follow_continuous_turn_stays_behind_without_wrap_jump',stable)
    local walker=rider();walker.gear.mounted=false
    local walkingCamera=Camera.new(walker.ped,world);walkingCamera:orbit(43,0)
    walkingCamera:setOutsideMode('follow',walker.ped,false);advance(walkingCamera,walker,.5)
    check('camera_follow_preference_selected_on_foot_keeps_existing_angle',walkingCamera.yaw==43
        and walkingCamera.outsideMode=='follow')
    local remote=rider();remote.bike.speed=0
    local remoteCamera=Camera.new(remote.bike,world);remoteCamera:setOutsideMode('follow',remote.bike)
    for _=1,90 do remoteCamera:updateRide(remote,1/60,{speed=8}) end
    check('camera_follow_lookahead_uses_authoritative_remote_speed',remoteCamera.centerX>remote.bike.x+2)
end
return Test
