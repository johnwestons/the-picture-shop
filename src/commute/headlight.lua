-- Shared headlamp geometry for the outside beam and first-person scene light.
local Headlight={FORWARD=.72,HEIGHT=.82}

function Headlight.position(bike)
    local pitch=bike.pitch or 0
    local heading=bike.heading or 0
    local forward=Headlight.FORWARD*math.cos(pitch)
    local x=(bike.x or 0)+math.cos(heading)*forward
    local z=(bike.z or 0)+math.sin(heading)*forward
    local height=(bike.h or 0)+Headlight.HEIGHT+Headlight.FORWARD*math.sin(pitch)
    return x,z,height
end

function Headlight.parameters(bike)
    local high=bike.headlightHighBeam==true
    local angle=(high and .035 or .075)-(bike.pitch or 0)
    return high and 19 or 11,high and .24 or .16,math.max(-.18,math.min(.32,math.tan(angle)))
end

function Headlight.send(shader,camera,bike)
    local x,z,height=Headlight.position(bike)
    local range,spread,drop=Headlight.parameters(bike)
    shader:send('rideHeadlight',bike.headlight==true)
    shader:send('rideForward',{math.cos(bike.heading or 0),math.sin(bike.heading or 0)})
    shader:send('rideLightOffset',{x-camera.centerX,z-camera.centerZ})
    shader:send('rideLightHeight',height)
    shader:send('rideBeamRange',range)
    shader:send('rideBeamSpread',spread)
    shader:send('rideBeamDrop',drop)
end

return Headlight
