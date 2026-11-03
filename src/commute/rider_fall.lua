local M = require('src.commute.vendor.mathx')
local Fall = {DURATION=1.35, FLIGHT=.55}

-- Follow the best open line along or away from the impact surface. Checking
-- the full path keeps a throw from crossing a trunk, guardrail or bridge edge.
local function landingAlong(world, bike, directionX, directionZ, radius, distance, clear)
    local x, z = bike.x, bike.z
    local height = world:supportHeight(x,z)
    local count = math.ceil(distance / .24)
    for i = 1, count do
        local nextX = bike.x + directionX * distance * i / count
        local nextZ = bike.z + directionZ * distance * i / count
        local nextHeight = world:supportHeight(nextX,nextZ)
        if math.abs(nextHeight-height) > .32 or world.roads:blocked(world,nextX,nextZ)
            or not clear(world,nextX,nextZ,radius) then break end
        local bottom, top = math.min(height,nextHeight), math.max(height,nextHeight)+1.5
        if world.sweepObstacles and world:sweepObstacles(x,z,nextX,nextZ,radius,bottom,top) then break end
        if world.infrastructure and world.infrastructure:sweep(x,z,nextX,nextZ,radius,bottom,top) then break end
        x, z, height = nextX, nextZ, nextHeight
    end
    return x, z, M.length(x-bike.x,z-bike.z)
end

function Fall.begin(rider, hit, world, radius, clear)
    local bike, ped, gear = rider.bike, rider.ped, rider.gear
    local nx, nz = hit.nx, hit.nz
    local tangentX, tangentZ = -nz, nx
    if tangentX*hit.dx + tangentZ*hit.dz < 0 then tangentX,tangentZ = -tangentX,-tangentZ end
    local distance = 1.8 + 1.4 * hit.severity
    local bestX, bestZ, bestDistance = bike.x, bike.z, 0
    -- First try the side carrying the rider's momentum. The last choice backs
    -- away from a narrow dead end along the incoming rideable surface.
    for _, direction in ipairs({
        {tangentX + nx*.25, tangentZ + nz*.25},
        {-tangentX + nx*.25, -tangentZ + nz*.25},
        {nx,nz}, {-hit.dx,-hit.dz},
    }) do
        local length = M.length(direction[1],direction[2])
        if length > 0 then
            local x,z,traveled = landingAlong(world,bike,direction[1]/length,direction[2]/length,radius,distance,clear)
            if traveled > bestDistance then bestX,bestZ,bestDistance = x,z,traveled end
            if traveled >= distance-.001 then break end
        end
    end
    gear.mounted, gear.engine, gear.transition = false, false, nil
    gear.revision = gear.revision + 1
    bike.throttle, bike.brake, bike.boosting = 0, 0, false
    ped.x,ped.z,ped.speed,ped.vx,ped.vz = bike.x,bike.z,0,0,0
    ped.heading = bestDistance > .01 and math.atan2(bestZ-bike.z,bestX-bike.x) or bike.heading
    ped.crash = {fromX=bike.x,fromZ=bike.z,toX=bestX,toZ=bestZ,elapsed=0}
end

function Fall.update(ped, dt)
    local fall = ped.crash
    fall.elapsed = math.min(Fall.DURATION, fall.elapsed+dt)
    local flight = math.min(1, fall.elapsed / Fall.FLIGHT)
    local travel = 1-(1-flight)^2
    ped.x = M.lerp(fall.fromX,fall.toX,travel)
    ped.z = M.lerp(fall.fromZ,fall.toZ,travel)
    if fall.elapsed >= Fall.DURATION then ped.crash = nil; return true end
    return false
end

return Fall
