local Camera=require('src.commute.camera')
local FP=require('src.commute.first_person_camera')
local Rider=require('src.commute.rider')
local Bike=require('src.commute.motorcycle')
local Runtime=require('src.commute.runtime')
local Bindings=require('src.commute.bindings')
local Test={}
local function near(a,b)return math.abs(a-b)<.001 end
function Test.run(check)
    require('src.commute.tests.landing_camera_test').run(check)
    local View=require('src.commute.first_person_renderer')
    local localEntry={actor={x=1},localPlayer=true}
    local remoteEntry={actor={x=2}}
    check('first_person_renderer_excludes_local_rider_even_when_interpolated_copy_is_used',
        not View.shouldDrawActor(localEntry,{x=1}) and View.shouldDrawActor(remoteEntry,{x=1}))
    require('src.commute.tests.ride_smoothing_test').run(check)
    require('src.commute.tests.first_person_bike_test').run(check)
    local world={height=function()return 0 end,supportHeight=function()return 4 end,
        roads={nearest=function()return 0,{width=8} end,blocked=function()return false end}}
    local r=Rider.new(100,100,0,{version=1,outfit='geared',mounted=true,engine=true,revision=0})
    local camera=Camera.new(r.bike,world)
    camera.yaw,camera.tilt,camera.zoom,camera.targetZoom=35,65,.8,.8
    check('first_person_toggle_when_mounted',camera:toggleView(r) and camera.firstPerson)
    camera:updateRide(r,0)
    check('first_person_eye_above_bridge_support',near(camera.eyeHeight,4+FP.EYE_HEIGHT))
    camera.viewPitch=0
    local x,y,d=camera:screen(110,100,camera.eyeHeight)
    check('first_person_forward_is_center',near(x,640) and near(y,440) and near(d,10))
    local right=camera:screen(110,101,camera.eyeHeight)
    local far=camera:screen(120,101,camera.eyeHeight)
    check('first_person_perspective_shrinks_with_distance',right>640 and near(right-640,2*(far-640)))
    check('first_person_behind_eye_is_hidden',camera:screen(99,100,4)==-10000)
    check('first_person_clip_depth_near_and_far',near(FP.depthValue(FP.NEAR),-1) and near(FP.depthValue(FP.FAR),1))
    check('first_person_culling_keeps_front_and_near_sides',FP.inView(camera,120,100,12)
        and FP.inView(camera,100,108,12) and not FP.inView(camera,70,100,12))
    local distance=r.bike.distance
    for _=1,80 do Bike.update(r.bike,{throttle=1,steer=.7},1/60,world);camera:updateRide(r,1/60) end
    check('first_person_follows_real_steering_and_lean',r.bike.distance>distance and camera.barSteer>.6
        and camera.roll>0 and near(camera.centerX,r.bike.x) and math.abs(camera.viewHeading-r.bike.heading)<.35)
    for _=1,30 do camera:updateRide(r,.05,{steer=-.8,lean=.25,grade=.1}) end
    check('first_person_uses_network_steering_telemetry',camera.barSteer<-.7 and camera.roll<0 and camera.ridePitch>0)
    camera:orbit(200,200);camera:zoomBy(200)
    check('first_person_look_and_fov_clamped',near(camera.lookYaw,math.rad(FP.LOOK_YAW)) and near(camera.lookPitch,math.rad(FP.LOOK_UP)) and camera.fov==60)
    camera:orbit(-400,-400)
    check('first_person_can_look_behind_and_straight_down',near(camera.lookYaw,-math.pi) and near(camera.lookPitch,-math.pi/2))
    camera:recenter()
    check('first_person_recenter_stays_on_bike',camera.firstPerson and camera.lookYaw==0 and camera.lookPitch==0 and camera.fov==60)
    local bx,bz,heading,speed=r.bike.x,r.bike.z,r.bike.heading,r.bike.speed
    camera:toggleView(r)
    check('first_person_restores_outside_settings',not camera.firstPerson and camera.yaw==35 and camera.tilt==65 and camera.zoom==.8)
    check('first_person_toggle_never_changes_physics',r.bike.x==bx and r.bike.z==bz and r.bike.heading==heading and r.bike.speed==speed)
    local truck={x=140,z=110,heading=.2,speed=0,h=4,pitch=.08,engine=true}
    local truckRider={truck=truck,vehicle='truck',gear={mounted=false,transition=nil}}
    local truckCamera=Camera.new(truck,world)
    truckCamera:setOutsideMode('follow',truck,true)
    local CameraMenu=require('src.commute.camera_menu')
    check('truck_camera_menu_enables_first_person_and_shoulder',
        CameraMenu.enabled('first',truckRider) and CameraMenu.enabled('shoulder',truckRider))
    check('truck_camera_toggle_enters_and_stays_in_first_person',truckCamera:toggleView(truckRider)
        and truckCamera.firstPerson)
    truckCamera:updateRide(truckRider,1/60)
    check('truck_first_person_camera_tracks_truck_heading_and_eye',truckCamera.firstPerson
        and truckCamera.lastActor==truck and near(truckCamera.eyeHeight,4+FP.EYE_HEIGHT*math.cos(truck.pitch)))
    truckCamera:orbit(24,-8);truckCamera:zoomBy(2)
    check('truck_first_person_keeps_free_look_and_fov_controls',truckCamera.lookYaw>0 and truckCamera.fov<FP.FOV)
    truckCamera:recenter()
    check('truck_first_person_recenter_resets_free_look',truckCamera.firstPerson and truckCamera.lookYaw==0
        and truckCamera.lookPitch==0)
    truckCamera:setFirstPerson(false,truck);truckCamera:setOutsideMode('shoulder',truck,true)
    truckCamera:updateRide(truckRider,1/60)
    local localView=View.actorCamera(truckCamera.shoulderView,truck,1,true)
    local offsetView=View.actorCamera(truckCamera.shoulderView,truck,1)
    check('shoulder_local_rider_heading_stays_rear_facing_when_eye_is_offset',
        truckCamera.shoulderView and localView.viewHeading==truck.heading
        and math.abs(localView.viewHeading-offsetView.viewHeading)>.01)
    check('truck_shoulder_view_includes_only_the_driven_truck_from_local_vehicles',
        View.shouldDrawLocalActor(truckCamera.shoulderView,{localPlayer=true,truck=true})
        and not View.shouldDrawLocalActor(truckCamera.shoulderView,{localPlayer=true,bikeOnly=true}))
    local touchButtons=require('src.commute.touch_controls').actionButtons(1280,880,Bindings.defaults(),
        {mounted=true,vehicle='truck',engine=true,headlight=false,headlightHighBeam=false,
            gearTransition=false,cameraMenu=false},
        {mobile=true,camera={firstPerson=true}})
    local truckControls={}
    for _,button in ipairs(touchButtons) do truckControls[button.action]=button end
    check('truck_mobile_controls_include_ignition_lights_and_both_turn_signals',
        truckControls.ignition and truckControls.headlight and truckControls.beam
        and truckControls.signalLeft and truckControls.signalRight)
    local controlContext={mounted=true,vehicle='truck',engine=true,headlight=false,
        headlightHighBeam=false,gearTransition=false,cameraMenu=false}
    local ignitionTouch=require('src.commute.touch_controls').actionAt(
        truckControls.ignition.x,truckControls.ignition.y,1280,880,Bindings.defaults(),controlContext,
        {mobile=true,camera={firstPerson=true},hiddenHud=true})
    check('truck_cockpit_ignition_switch_is_a_mobile_hit_target_even_with_hud_hidden',
        ignitionTouch and ignitionTouch.action=='ignition')
    check('truck_cockpit_switches_have_clear_visual_hit_sizes',
        truckControls.ignition.radius>=15 and truckControls.ignition.hitRadius>=26)
    local player={id=1}
    local part={slot=1,rider=r}
    local inputRuntime={state={screen='world',home={commute={participants={owner=part}}}},
        World={player=player},Config={},App={settings={motorcycleControls=Bindings.defaults()}},
        _commute={renderer={},camera=camera}}
    for _,size in ipairs({{1280,880},{960,678},{640,480}}) do
        inputRuntime.Config.baseWidth,inputRuntime.Config.baseHeight=size[1],size[2]
        local button=Runtime.cameraButton(inputRuntime)
        local okay=button and Runtime.cameraPointer(inputRuntime,button.x+button.width*.5,button.y+button.height*.5)
        local row=require('src.commute.camera_menu').row(button,4)
        okay=okay and inputRuntime._commute.cameraMenu and Runtime.cameraPointer(inputRuntime,row.x+30,row.y+15)
        check('first_person_camera_toggle_button_while_moving_'..size[1],okay and camera.firstPerson)
        camera:toggleView(r)
    end
    camera:toggleView(r);r.gear.transition={action='dismount'};camera:updateRide(r,.016)
    check('first_person_dismount_returns_outside',not camera.firstPerson and not camera:toggleView(r))
    r.gear.transition=nil;r.gear.mounted=false
    check('first_person_on_foot_toggle_rejected',not camera:toggleView(r))
    require('src.commute.tests.terrain_renderer_test').run(check)
    require('src.commute.tests.bike_multiplayer_view_test').run(check)
end
return Test
