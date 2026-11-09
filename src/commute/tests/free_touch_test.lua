local PixelCanvas=require('src.tests.support.pixel_canvas')
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
    check('free_touch_partial_stick_never_adds_gas',drive==0)
    point(0,-1);steer,drive=input()
    check('free_touch_full_up_steers_without_applying_gas',steer<-.9 and drive==0)

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
                math.abs(steer)<1e-6 and drive==0 and x1>x0 and math.abs((y1-y0)/(x1-x0)+4/3)<1e-6)
        end
    end
    camera.yaw,camera.tilt=0,55
    touch.held.accelerate=true
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
    touch.held.accelerate=nil;rider=ride()
    point(-1,.01);local left=input()
    point(-1,-.01);local right=input()
    check('free_touch_nearly_opposite_inputs_choose_consistent_turn',left==right and left==1)
    rider.bike.speed=12
    steer,drive=input()
    check('free_touch_hard_turn_at_speed_coasts_and_steers',drive==0 and steer==1)
    local gx,gy,scale=require('src.commute.cockpit').throttleGrip(960,678)
    local options={mobile=true,camera=camera}
    assert(touch:press('gas',gx,gy,960,678,profile,function()end,{mounted=true},options))
    steer,drive=input()
    check('free_touch_grip_press_without_drag_coasts',drive==0 and touch.gripId=='gas')
    touch:move('gas',gx,gy+27*scale,960,678,profile);steer,drive=input()
    check('free_touch_grip_drag_sets_half_throttle_while_steering',math.abs(drive+.5)<1e-6 and steer==1)
    touch:move('gas',gx,gy+65*scale,960,678,profile);steer,drive=input()
    check('free_touch_grip_full_travel_caps_at_full_gas',drive==-1)
    touch.held.brake=true;steer,drive=input()
    check('free_touch_brake_button_has_priority',drive==1)
    touch.held.brake=nil;touch:release('gas');rider.bike.reverse=true
    point(-1,0);steer,drive=input()
    check('free_touch_in_reverse_steers_without_backing_power',math.abs(steer)<1e-6 and drive==0)
    point(0,0)
    assert(touch:press('gas',gx,gy,960,678,profile,function()end,{mounted=true},options))
    touch:move('gas',gx,gy+51*scale,960,678,profile);steer,drive=input()
    check('free_touch_grip_accelerates_with_centered_stick',steer==0 and drive<-.999)
    touch:move('gas',gx,gy,960,678,profile);steer,drive=input()
    check('free_touch_unwinding_grip_closes_throttle',drive==0)
    touch:move('gas',gx,gy+51*scale,960,678,profile);touch:cancel();steer,drive=input()
    check('free_touch_cancel_clears_grip_and_steering',drive==0 and steer==0 and not touch.gripId)
    assert(touch:press('stick',cx,cy,960,678,profile,function()end));point(-1,0)

    camera:setOutsideMode('follow',rider.bike)
    local oldSteer,oldDrive=Bindings.drive(profile,touch,camera,rider.bike)
    steer,drive=input()
    check('free_touch_follow_keeps_steering_and_separates_pedals',steer==oldSteer and drive==0)
    camera:setFirstPerson(true,rider.bike)
    oldSteer,oldDrive=Bindings.drive(profile,touch,camera,rider.bike)
    steer,drive=input()
    check('free_touch_first_person_keeps_steering_and_separates_pedals',steer==oldSteer and drive==0)
    touch:release('stick')
    check('free_touch_release_clears_direction_marker',touch.aimX==0 and touch.aimY==0)
    local old=Bindings.defaults()
    old.layoutVersion=2
    for i=1,6 do old.layout['touch'..i]={x=i%2==1 and .84 or .94,y=.62+math.floor((i-1)/2)*.14} end
    old.layout.touch4={x=.72,y=.55}
    local migrated=Bindings.normalize(old)
    check('mobile_buttons_upgrade_stock_go_boost_preserving_custom_positions',migrated.layoutVersion==4
        and migrated.layout.touch3.y<migrated.layout.touch1.y and migrated.layout.touch1.x>.84
        and migrated.layout.touch4.x==.72 and migrated.layout.touch4.y==.55)
    local mixed=Bindings.defaults()
    mixed.layoutVersion=3
    mixed.layout.touch3={x=.84,y=.72};mixed.layout.touch4={x=.94,y=.72}
    mixed.layout.touch5={x=.84,y=.88};mixed.layout.touch6={x=.70,y=.87}
    local upgraded=Bindings.normalize(mixed)
    check('desktop_mixed_legacy_layout_moves_stock_buttons_and_keeps_personal_edits',
        upgraded.layout.touch3.x==profile.layout.touch3.x and upgraded.layout.touch3.y==profile.layout.touch3.y
        and upgraded.layout.touch4.x==profile.layout.touch4.x and upgraded.layout.touch5.y==profile.layout.touch5.y
        and upgraded.layout.touch6.x==.70 and upgraded.layout.touch6.y==.87)
    for _,size in ipairs({{640,480},{960,678},{1280,880}}) do
        local w,h=unpack(size)
        for _,transmission in ipairs({'automatic','manual'}) do
            local ctx={mounted=true,transmission=transmission,cameraMenu=true}
            local buttons=Touch.actionButtons(w,h,profile,ctx,{mobile=true})
            local byAction={};for _,button in ipairs(buttons) do byAction[button.action]=button end
            local parity=true
            for _,button in ipairs(Touch.actionButtons(w,h,upgraded,ctx,{mobile=false})) do
                if not button.physical and button.action~='rescue' then
                    local mobile=byAction[button.action]
                    local hit=Touch.actionAt(button.x,button.y,w,h,upgraded,ctx,{mobile=false})
                    parity=parity and mobile and hit and hit.action==button.action
                        and button.x==mobile.x and button.y==mobile.y and button.radius==mobile.radius
                        and button.hitRadius==mobile.hitRadius
                end
            end
            check(('desktop_ride_buttons_match_mobile_and_receive_clicks_%s_%d'):format(transmission,w),parity)
            local gas,boost,brake,off=byAction.accelerate,byAction.boost,byAction.brake,byAction.interact
            check(('mobile_buttons_larger_go_below_boost_at_%d_%s'):format(w,transmission),
                gas.y==off.y and gas.x==boost.x and boost.y==brake.y and gas.y>boost.y
                and gas.radius>brake.radius*1.20 and gas.hitRadius>brake.hitRadius
                and gas.x>.84*w and brake.x>.94*w and brake.x+brake.hitRadius<=w
                and off.x-gas.x>gas.hitRadius+off.hitRadius and gas.y-boost.y>gas.hitRadius+boost.hitRadius)
            local clear=true
            for _,button in ipairs(buttons) do
                if button.action=='transmission' or button.action=='reverse' or button.icon=='shift' then
                    clear=clear and button.x>=w*.80 and button.y>h*.82 and button.y+button.hitRadius<h
                    for _,other in ipairs(buttons) do
                        if button~=other then
                            clear=clear and (button.x-other.x)^2+(button.y-other.y)^2>=(button.hitRadius+other.hitRadius)^2
                        end
                    end
                    local gx,gy,scale=require('src.commute.cockpit').throttleGrip(w,h)
                    clear=clear and button.x-button.hitRadius>gx+48*scale
                    local hit=Touch.actionAt(button.x,button.y,w,h,profile,ctx,{mobile=true})
                    clear=clear and hit and hit.action==button.action
                end
            end
            check(('free_touch_%s_gears_clear_grip_and_ride_buttons_at_%d'):format(transmission,w),clear)
        end
    end

    -- Read the real marker pixels on a clear target. Project the wheel anchor
    -- off-canvas at high zoom so the same compact target can cover every case.
    local g=love.graphics
    local canvas=PixelCanvas(32,32)
    for _,zoom in ipairs({.55,1.35,6.5}) do
        local clear=true
        for _,direction in ipairs({{1,0},{0,-1},{-1,0},{0,1}}) do
            local dx,dy=unpack(direction)
            touch.aimX,touch.aimY=dx,dy
            local anchorX,anchorY=16-dx*(96*zoom+26),16-dy*(96*zoom+26)
            local view={zoom=zoom,screen=function()return anchorX,anchorY end}
            g.push('all');g.setCanvas(canvas);g.clear(0,0,0,0);touch:drawAim(view,rider.bike);g.pop()
            local data=canvas:newImageData()
            local nose,tail,count=0,0,0
            for y=0,31 do for x=0,31 do
                local _,_,_,alpha=data:getPixel(x,y)
                if alpha>.03 then
                    local forward=(x+.5-16)*dx+(y+.5-16)*dy
                    count=count+1;nose=math.max(nose,forward);tail=math.max(tail,-forward)
                    clear=clear and alpha<.78 and (x+.5-anchorX)^2+(y+.5-anchorY)^2>(94*zoom+10)^2
                end
            end end
            data:release()
            clear=clear and count>30 and count<110 and nose>tail+1
        end
        check('free_touch_directional_gem_clears_rider_at_zoom_'..zoom,clear)
    end
    canvas:release()
end
return Test
