local Bindings=require('src.commute.bindings')
local Camera=require('src.commute.camera')
local Rider=require('src.commute.rider')
local Touch=require('src.commute.touch_controls')
local Test={}
local world={height=function()return 0 end,supportHeight=function()return 0 end,
    roads={nearest=function()return 0,{width=8}end,blocked=function()return false end}}

function Test.run(check)
    local profile=Bindings.defaults()
    local touch=Touch.new()
    local cx,cy=profile.layout.stick.x*960,profile.layout.stick.y*678
    local radius=678*.09
    local function point(x,y)
        assert(touch:move('stick',cx+radius*x,cy+radius*y,960,678,profile))
    end
    assert(touch:press('stick',cx,cy,960,678,profile,function()end))
    local function ride()
        return Rider.new(100,100,0,{version=1,outfit='geared',mounted=true,engine=true,revision=0})
    end
    local rider=ride()
    local camera=Camera.new(rider.bike,world)
    local function input()
        return Bindings.drive(profile,touch,camera,rider.bike,true)
    end
    point(.08,0)
    local steer,drive=input()
    check('free_touch_center_jitter_is_neutral',steer==0 and drive==0)
    point(.32,0)
    steer,drive=input()
    check('free_touch_small_push_gives_proportional_drive',drive<-.20 and drive>-.30)

    point(.6,-.8)
    for _,tilt in ipairs({20,55,89}) do
        for _,yaw in ipairs({0,82,181,273}) do
            camera.yaw,camera.tilt=yaw,tilt
            local dx,dz=camera:screenGroundDirection(touch.aimX,touch.aimY)
            rider.bike.heading=math.atan2(dz,dx)
            steer,drive=input()
            -- Compare against the camera's real forward projection.
            local x0,y0=camera:screen(100,100,0)
            local x1,y1=camera:screen(100+math.cos(rider.bike.heading),100+math.sin(rider.bike.heading),0)
            check(('free_touch_held_diagonal_matches_screen_at_%d_%d'):format(yaw,tilt),
                math.abs(steer)<1e-6 and drive<-.99 and x1>x0 and math.abs((y1-y0)/(x1-x0)+4/3)<1e-6)
        end
    end
    camera.yaw,camera.tilt=0,55
    for _,hz in ipairs({30,60,120}) do
        for _,target in ipairs({math.pi/2,math.pi}) do
            rider=ride()
            point(math.cos(target),math.sin(target))
            local stayedForward=true
            for _=1,5*hz do
                steer,drive=input()
                Rider.update(rider,{steer=steer,drive=drive},1/hz,world)
                stayedForward=stayedForward and not rider.bike.reverse
            end
            local bike=rider.bike
            check(('free_touch_starts_and_completes_%d_turn_at_%dhz'):format(math.floor(target*180/math.pi+.5),hz),
                stayedForward and math.cos(bike.heading-target)>.98 and bike.distance>3)
        end
    end
    rider=ride()
    point(-1,.01);local left=input()
    point(-1,-.01);local right=input()
    check('free_touch_nearly_opposite_inputs_choose_consistent_turn',left==right and left==1)
    rider.bike.speed=12
    steer,drive=input()
    check('free_touch_hard_turn_at_speed_coasts_and_steers',drive==0 and steer==1)
    touch.held.brake=true;steer,drive=input()
    check('free_touch_brake_button_has_priority',drive==1)
    touch.held.brake=nil;rider.bike.reverse=true
    point(-1,0);steer,drive=input()
    check('free_touch_in_reverse_points_along_backward_travel',math.abs(steer)<1e-6 and drive>.99)

    camera:setOutsideMode('follow',rider.bike)
    local oldSteer,oldDrive=Bindings.drive(profile,touch,camera,rider.bike)
    steer,drive=input()
    check('free_touch_follow_keeps_previous_inputs',steer==oldSteer and drive==oldDrive)
    camera:setFirstPerson(true,rider.bike)
    oldSteer,oldDrive=Bindings.drive(profile,touch,camera,rider.bike)
    steer,drive=input()
    check('free_touch_first_person_keeps_previous_inputs',steer==oldSteer and drive==oldDrive)
    touch:release('stick')
    check('free_touch_release_clears_direction_and_arrow',touch.aimX==0 and touch.aimY==0)
end
return Test
