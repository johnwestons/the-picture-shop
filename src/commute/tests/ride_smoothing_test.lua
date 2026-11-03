local Bike=require('src.commute.motorcycle')
local Camera=require('src.commute.camera')
local FP=require('src.commute.first_person_camera')
local Bindings=require('src.commute.bindings')
local Touch=require('src.commute.touch_controls')
local Test={}
local world={height=function()return 0 end,supportHeight=function()return 0 end,
    roads={nearest=function()return 0,{width=8} end,blocked=function()return false end}}
local function bike() local b=Bike.new(100,100,0);b.speed=10;b.gear=3;return b end
function Test.run(check)
    local p=bike()
    Bike.update(p,{steer=1},1/60,world)
    check('ride_keyboard_press_eases_steering_and_weight_shift',p.steering>0 and p.steering<.03
        and math.abs(p.lean)<.002 and p.heading<.002)
    for _=1,60 do Bike.update(p,{steer=1},1/60,world) end
    local lean=p.lean
    Bike.update(p,{steer=-1},1/60,world)
    check('ride_reversal_does_not_snap_to_opposite_lean',lean<-.15 and p.lean<0 and math.abs(p.lean-lean)<.01)
    for _=1,120 do Bike.update(p,{},1/60,world) end
    check('ride_release_settles_upright_without_lingering_turn',math.abs(p.steering)<.001 and math.abs(p.lean)<.001)
    local samples={}
    for _,hz in ipairs({30,60,120}) do
        local b=bike()
        for _,steer in ipairs({1,-1,0,.4,0}) do
            for _=1,hz/2 do Bike.update(b,{steer=steer,throttle=.3},1/hz,world) end
        end
        samples[#samples+1]=b
    end
    local same=true
    for i=2,3 do
        same=same and math.abs(samples[i].x-samples[1].x)<.001 and math.abs(samples[i].z-samples[1].z)<.001
            and math.abs(samples[i].lean-samples[1].lean)<.0001
    end
    check('ride_smooth_keyboard_reversals_match_30_60_120_fps',same)
    p=bike();local c=Camera.new(p,world);c:setFirstPerson(true,p)
    p.heading=.5;p.lean=-.3;c:update(p,1/60)
    check('ride_camera_softens_heading_and_roll_changes',c.rideHeading>0 and c.rideHeading<.02 and c.roll>0 and c.roll<.003)
    for _=1,90 do c:update(p,1/60) end
    check('ride_camera_converges_without_permanent_heading_error',math.abs(c.rideHeading-.5)<.001 and math.abs(c.roll-.105)<.002)
    p.heading=math.pi*2-.01;c:setFirstPerson(true,p);p.heading=.01;c:update(p,1/60)
    check('ride_camera_wraps_heading_by_shortest_direction',c.rideHeading>math.pi*2-.01 and c.rideHeading<math.pi*2+.01)
    c:recenter();c:orbit(30,10)
    for _=1,60 do c:update(p,1/60) end
    local x,y,squeeze=FP.cockpitPose(c)
    check('ride_cockpit_stays_with_bike_when_looking_right_up',x< -350 and y>100 and squeeze<.9)
    c:orbit(-60,-20)
    for _=1,60 do c:update(p,1/60) end
    x,y=FP.cockpitPose(c)
    check('ride_cockpit_stays_with_bike_when_looking_left_down',x>350 and y< -100)
    c:zoomBy(3);local fov=c.fov;c:recenter();x,y=FP.cockpitPose(c)
    check('ride_center_snaps_to_true_forward_and_keeps_fov',math.abs(x)<.001 and math.abs(y)<.001
        and c.headYawVelocity==0 and c.fov==fov and math.abs(c.viewHeading-p.heading)<.001)
    for _,size in ipairs({{1280,880},{960,678},{640,480}}) do
        local center
        for _,button in ipairs(Touch.actionButtons(size[1],size[2],Bindings.defaults(),{mounted=true},{mobile=true})) do
            if button.action=='recenter' then center=button end
        end
        local hit=center and Touch.actionAt(center.x,center.y,size[1],size[2],Bindings.defaults(),
            {mounted=true},{mobile=true})
        check('ride_shared_center_button_while_moving_'..size[1],hit and hit.action=='recenter')
    end
end
return Test
