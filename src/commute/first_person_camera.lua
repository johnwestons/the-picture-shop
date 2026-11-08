-- Rider-eye projection shared by the perspective renderer and screen markers.
local M=require('src.commute.vendor.mathx')
local Damping=require('src.commute.damping')
local Landing=require('src.commute.landing_camera')
local FP={EYE_HEIGHT=1.65,TRUCK_SEAT_SIDE=-.34,TRUCK_SEAT_UP=.26,
    NEUTRAL_PITCH=-.035,NEAR=.15,FAR=110,FOV=82,LOOK_YAW=180,LOOK_DOWN=90,LOOK_UP=60,
    HEADING_SMOOTH_TIME=.22,ROLL_SMOOTH_TIME=.42,PITCH_SMOOTH_TIME=.30,LOOK_SMOOTH_TIME=.12}
-- Rotate a view's forward and right vectors about the motorcycle's lateral
-- axis. This lets the head look sideways or behind on the pitched chassis.
function FP.tiltView(yaw,pitch,roll,tilt)
    if math.abs(tilt)<1e-9 then return yaw,pitch,roll end
    local cy,sy,cp,sp=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch)
    local cr,sr,ct,st=math.cos(roll),math.sin(roll),math.cos(tilt),math.sin(tilt)
    local fx,fy,fz=cy*cp,sp,sy*cp
    local rx,ry,rz=-sy*cr-cy*sp*sr,cp*sr,cy*cr-sy*sp*sr
    fx,fy=ct*fx-st*fy,st*fx+ct*fy
    rx,ry=ct*rx-st*ry,st*rx+ct*ry
    yaw,pitch=math.atan2(fz,fx),math.atan2(fy,M.length(fx,fz))
    cy,sy,cp,sp=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch)
    return yaw,pitch,math.atan2(-cy*sp*rx+cp*ry-sy*sp*rz,-sy*rx+cy*rz)
end
function FP.update(camera,actor,dt,visual)
    visual=visual or actor
    dt=M.clamp(dt,0,.1)
    local initialize=not camera.eyeHeight
    local function smooth(key,target,time,angle)
        local velocityKey=key..'Velocity'
        if initialize then camera[key],camera[velocityKey]=target,0
        else camera[key],camera[velocityKey]=(angle and Damping.angle or Damping.spring)(
            camera[key] or target,target,camera[velocityKey],time,dt) end
    end
    camera.focusHeight=M.finite(visual.h) and visual.h or M.finite(actor.h) and actor.h
        or (camera.world.supportHeight or camera.world.height)(camera.world,actor.x,actor.z)
    camera.bikeHeading=camera.walkViewHeading or actor.heading or 0
    smooth('rideHeading',camera.bikeHeading,FP.HEADING_SMOOTH_TIME,true)
    smooth('headYaw',camera.lookYaw or 0,FP.LOOK_SMOOTH_TIME)
    smooth('headPitch',camera.lookPitch or 0,FP.LOOK_SMOOTH_TIME)
    local pitch=visual.pitch
    if not M.finite(pitch) and visual~=actor and M.finite(visual.grade) then pitch=math.atan(visual.grade) end
    if not M.finite(pitch) then pitch=actor.pitch or math.atan(actor.grade or 0) end
    camera.bikePitch=pitch
    camera.eyeForward=-FP.EYE_HEIGHT*math.sin(pitch)
    local truck=camera.localVehicle=='truck'
    local seatSide=truck and (camera.truckCabSide or FP.TRUCK_SEAT_SIDE) or 0
    local seatUp=truck and (camera.truckCabUp or FP.TRUCK_SEAT_UP) or 0
    local seatForward=truck and (camera.truckCabForward or 0) or 0
    local rightX,rightZ=-math.sin(camera.bikeHeading),math.cos(camera.bikeHeading)
    camera.centerX=actor.x+(camera.eyeForward+seatForward)*math.cos(camera.bikeHeading)+rightX*seatSide
    camera.centerZ=actor.z+(camera.eyeForward+seatForward)*math.sin(camera.bikeHeading)+rightZ*seatSide
    smooth('eyeHeight',camera.focusHeight+FP.EYE_HEIGHT*math.cos(pitch)+seatUp,.18)
    smooth('ridePitch',pitch,FP.PITCH_SMOOTH_TIME)
    local landing=Landing.target(camera.world,actor,visual)
    camera.landingTarget=landing
    local lookCorrection=0
    if landing then
        local distance=M.length(landing.x-camera.centerX,landing.z-camera.centerZ)
        local aim=M.clamp(math.atan2(landing.h+.25-camera.eyeHeight,math.max(6,distance)),
            -math.rad(32),-math.rad(8))
        -- A gentle head movement keeps the bars in view on steep takeoffs;
        -- automatic aiming must not turn into a look beneath the motorcycle.
        lookCorrection=M.clamp(aim-(FP.NEUTRAL_PITCH+camera.ridePitch),-math.rad(45),math.rad(45))
    end
    smooth('landingLookPitch',lookCorrection,.22)
    local lean=visual.lean or actor.lean or 0
    smooth('rideRoll',M.clamp(-lean*.35,-.13,.13),FP.ROLL_SMOOTH_TIME)
    local heading,headPitch,roll=FP.tiltView(camera.rideHeading-camera.bikeHeading+camera.headYaw,
        FP.NEUTRAL_PITCH+camera.headPitch,camera.rideRoll,camera.ridePitch)
    -- Manual head look retains control; the landing hint fades when looking
    -- sideways/behind or deliberately up/down, then eases out after touchdown.
    local assist=math.max(0,math.cos(camera.headYaw))*(1-M.smooth(math.abs(camera.headPitch)/math.rad(30)))
    camera.viewHeading,camera.viewPitch,camera.roll=camera.bikeHeading+heading,
        M.clamp(headPitch+camera.landingLookPitch*assist,-math.pi*.5+.001,math.pi*.5-.001),roll
    smooth('barSteer',visual.steer or visual.steering or actor.steering or 0,.16)
    camera.fov=camera.fov or FP.FOV
    camera.focal=640/math.tan(math.rad(camera.fov)*.5)
    camera.viewCos,camera.viewSin=math.cos(camera.viewHeading),math.sin(camera.viewHeading)
    camera.viewSlope=math.tan(math.rad(camera.fov)*.5)/math.max(.6,math.cos(camera.viewPitch))
end
function FP.recenter(camera)
    camera.lookYaw,camera.lookPitch,camera.headYaw,camera.headPitch=0,0,0,0
    camera.headYawVelocity,camera.headPitchVelocity=0,0
    camera.rideHeading=camera.lastActor.heading or 0
    if camera.walkViewHeading then camera.walkViewHeading=camera.rideHeading end
    camera.rideHeadingVelocity=0
    -- Center the head without changing the chosen field of view or bank.
    FP.update(camera,camera.lastActor,0)
end
function FP.cockpitPose(camera)
    local yaw=(camera.bikeHeading-camera.viewHeading+math.pi)%(2*math.pi)-math.pi
    yaw=M.clamp(yaw,-math.rad(80),math.rad(80))
    return camera.focal*math.tan(yaw),camera.focal*math.tan(camera.headPitch),math.cos(yaw)
end
function FP.inView(camera,x,z,padding)
    local dx,dz=x-camera.centerX,z-camera.centerZ
    local forward=dx*camera.viewCos+dz*camera.viewSin
    local right=-dx*camera.viewSin+dz*camera.viewCos
    local width=camera.viewportWidth or 1280
    local slope=(width*.5)/camera.focal/math.max(.6,math.cos(camera.viewPitch))
    return forward>=-padding and math.abs(right)<=math.max(0,forward)*math.max(camera.viewSlope,slope)+padding
end
function FP.coordinates(camera,x,z,h)
    local dx,dz=x-camera.centerX,z-camera.centerZ
    local c,s=math.cos(camera.viewHeading),math.sin(camera.viewHeading)
    local right,forward=-dx*s+dz*c,dx*c+dz*s
    local up=h-camera.eyeHeight
    local cp,sp=math.cos(camera.viewPitch),math.sin(camera.viewPitch)
    local depth=forward*cp+up*sp
    up=up*cp-forward*sp
    local cr,sr=math.cos(camera.roll),math.sin(camera.roll)
    return right*cr+up*sr,up*cr-right*sr,depth
end
function FP.screen(camera,x,z,h)
    local right,up,depth=FP.coordinates(camera,x,z,h)
    -- Markers behind the eye must never flip across the viewport.
    if depth<FP.NEAR then return -10000,-10000,depth end
    local centerX=camera.viewCenterX or (camera.viewportWidth or 1280)*.5
    local centerY=camera.viewCenterY or (camera.viewportHeight or 880)*.5
    return centerX+right*camera.focal/depth,centerY-up*camera.focal/depth,depth
end
function FP.depthValue(depth)
    return (FP.FAR+FP.NEAR)/(FP.FAR-FP.NEAR)-2*FP.FAR*FP.NEAR/((FP.FAR-FP.NEAR)*depth)
end
function FP.send(camera,shader)
    if shader:hasUniform('viewCenter') then
        shader:send('viewCenter',{camera.viewCenterX or (camera.viewportWidth or 1280)*.5,
            camera.viewCenterY or (camera.viewportHeight or 880)*.5})
    end
    shader:send('eyePosition',{camera.centerX,camera.eyeHeight,camera.centerZ})
    shader:send('eyeAngles',{camera.viewHeading,camera.viewPitch,camera.roll})
    shader:send('eyeLens',{camera.focal,FP.NEAR,FP.FAR})
end
return FP
