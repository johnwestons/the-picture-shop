-- Rider-eye projection shared by the perspective renderer and screen markers.
local M=require('src.commute.vendor.mathx')
local Damping=require('src.commute.damping')
local FP={EYE_HEIGHT=1.65,NEAR=.15,FAR=110,FOV=82,LOOK_YAW=180,LOOK_DOWN=90,LOOK_UP=60,
    HEADING_SMOOTH_TIME=.22,ROLL_SMOOTH_TIME=.42,PITCH_SMOOTH_TIME=.30,LOOK_SMOOTH_TIME=.12}
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
    camera.centerX,camera.centerZ=actor.x,actor.z
    camera.focusHeight=(camera.world.supportHeight or camera.world.height)(camera.world,actor.x,actor.z)
    smooth('eyeHeight',camera.focusHeight+FP.EYE_HEIGHT,.18)
    camera.bikeHeading=actor.heading or 0
    smooth('rideHeading',camera.bikeHeading,FP.HEADING_SMOOTH_TIME,true)
    smooth('headYaw',camera.lookYaw or 0,FP.LOOK_SMOOTH_TIME)
    smooth('headPitch',camera.lookPitch or 0,FP.LOOK_SMOOTH_TIME)
    camera.viewHeading=camera.rideHeading+camera.headYaw
    local pitch=math.atan(visual.grade or actor.grade or 0)-.035
    smooth('ridePitch',M.clamp(pitch,-.6,.6),FP.PITCH_SMOOTH_TIME)
    camera.viewPitch=camera.ridePitch+camera.headPitch
    local lean=visual.lean or actor.lean or 0
    smooth('roll',M.clamp(-lean*.35,-.13,.13),FP.ROLL_SMOOTH_TIME)
    smooth('cockpitLean',lean,.18)
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
    return forward>=-padding and math.abs(right)<=math.max(0,forward)*camera.viewSlope+padding
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
    return 640+right*camera.focal/depth,440-up*camera.focal/depth,depth
end
function FP.depthValue(depth)
    return (FP.FAR+FP.NEAR)/(FP.FAR-FP.NEAR)-2*FP.FAR*FP.NEAR/((FP.FAR-FP.NEAR)*depth)
end
function FP.send(camera,shader)
    shader:send('eyePosition',{camera.centerX,camera.eyeHeight,camera.centerZ})
    shader:send('eyeAngles',{camera.viewHeading,camera.viewPitch,camera.roll})
    shader:send('eyeLens',{camera.focal,FP.NEAR,FP.FAR})
end
return FP
