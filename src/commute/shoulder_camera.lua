-- A third-person eye using the same perspective projection and depth buffer
-- as the rider-eye camera. Its boom follows the outside camera's orbit.
local M=require('src.commute.vendor.mathx')
local Shoulder={}

function Shoulder.update(eye,camera,rider)
    local world=camera.world
    local yaw=math.rad(-90-camera.yaw)
    local forwardX,forwardZ=math.cos(yaw),math.sin(yaw)
    local tilt=math.rad(camera.tilt)
    local arm=M.clamp(6.4/camera.zoom,2.5,11)
    local back=math.cos(tilt)*arm
    local dx,dz=-forwardX*back-forwardZ*.78,-forwardZ*back+forwardX*.78
    local fraction=1
    local h=rider.h or (world.supportHeight or world.height)(world,rider.x,rider.z)
    -- Keep the boom on the rider's side of walls when leaving a building.
    if world.sites and world.sites.blocked then
        local steps=math.max(1,math.ceil(M.length(dx,dz)))
        for i=1,steps do
            if world.sites:blocked(rider.x+dx*i/steps,rider.z+dz*i/steps) then
                fraction=math.max(.08,(i-1)/steps);break
            end
        end
    end
    if world.sweepObstacles then
        local hit=world:sweepObstacles(rider.x,rider.z,rider.x+dx*fraction,rider.z+dz*fraction,.18,h+1,h+1.6)
        if hit then fraction=fraction*math.max(.08,hit-.03) end
    end
    eye.centerX,eye.centerZ=rider.x+dx*fraction,rider.z+dz*fraction
    local ground=(world.supportHeight or world.height)(world,eye.centerX,eye.centerZ)
    eye.eyeHeight=math.max(ground+.35,h+1.35+math.sin(tilt)*arm*fraction)
    eye.focusHeight=h
    eye.firstPerson,eye.includeLocalRider=true,true
    eye.viewHeading,eye.viewPitch,eye.roll=yaw,-tilt,0
    eye.viewCos,eye.viewSin=forwardX,forwardZ
    eye.viewportWidth,eye.viewportHeight=camera.viewportWidth,camera.viewportHeight
    eye.fov=74
    local lens=math.tan(math.rad(eye.fov)*.5)
    eye.focal=(eye.viewportWidth or 1280)*.5/lens
    eye.viewSlope=lens/math.max(.6,math.cos(tilt))
end
return Shoulder
