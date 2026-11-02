local Camera=require('src.commute.camera')
local FP=require('src.commute.first_person_camera')
local Rider=require('src.commute.rider')
local Bike=require('src.commute.motorcycle')
local HUD=require('src.commute.cockpit')
local Test={}
local function near(a,b)return math.abs(a-b)<.001 end
function Test.run(check)
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
    camera:toggleView(r);r.gear.transition={action='dismount'};camera:updateRide(r,.016)
    check('first_person_dismount_returns_outside',not camera.firstPerson and not camera:toggleView(r))
    r.gear.transition=nil;r.gear.mounted=false
    check('first_person_on_foot_toggle_rejected',not camera:toggleView(r))
    local roads=require('src.commute.roads').new()
    local terrain=roads:attach(require('src.commute.terrain').new())
    local builder={world=terrain,chunks={},serial=0}
    local mesh=require('src.commute.renderer').build(builder,59,45).mesh
    local inspected,clear=0,true
    for i=1,mesh:getVertexCount() do
        local x,z,h=mesh:getVertex(i)
        local support,kind=terrain:supportHeight(x,z)
        if kind=='bridge' then inspected=inspected+1;clear=clear and h<support end
    end
    mesh:release()
    check('first_person_bridge_mesh_keeps_riverbank_below_deck',inspected>0 and clear)
    for _,size in ipairs({{1280,880},{960,678},{640,480}}) do
        local ox,oy,s=HUD.layout(size[1],size[2])
        check('first_person_touch_toggle_while_moving_'..size[1],HUD.keyAt(ox+625*s,oy+278*s,size[1],size[2],r.bike,{speed=12})=='p')
    end
end
return Test
