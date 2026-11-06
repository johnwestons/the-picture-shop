local M = require("src.commute.vendor.mathx")
local FirstPerson = require('src.commute.first_person_camera')
local Damping = require('src.commute.damping')
local Landing = require('src.commute.landing_camera')

local Camera = {}
Camera.__index = Camera

Camera.SCREEN_WIDTH = 1280
Camera.SCREEN_HEIGHT = 880
Camera.CENTER_X = 640
Camera.CENTER_Y = 440
Camera.TILT_DEFAULT = 55
Camera.TILT_MIN = 6
-- Third-person orbit can get close to a straight-down view without reaching
-- the singular 90-degree projection limit.
Camera.TILT_MAX = 89
Camera.ZOOM_DEFAULT = 1.35
Camera.ZOOM_MIN = 0.55
Camera.ZOOM_MAX = 6.5
Camera.FOLLOW_SMOOTH_TIME = 0.18
Camera.FOLLOW_LOOKAHEAD_DISTANCE = 2.4
Camera.FOLLOW_LOOKAHEAD_FULL_SPEED = 8
Camera.FOLLOW_YAW_SMOOTH_TIME = 0.18
Camera.SHOULDER_FOLLOW_SMOOTH_TIME = 0.30
Camera.SHOULDER_LATERAL_SMOOTH_TIME = 0.52
Camera.SHOULDER_YAW_SMOOTH_TIME = 0.36
Camera.FOLLOW_ORBIT_HOLD = 0.8
Camera.FOLLOW_TILT_DEFAULT = 62
Camera.SHOULDER_TILT = 14
Camera.SHOULDER_ZOOM = 1.45

local rad = math.pi / 180
local defaultGroundSin = math.sin(Camera.TILT_DEFAULT * rad)
local defaultHeightCos = math.cos(Camera.TILT_DEFAULT * rad)

local directions = {
    "east", "southeast", "south", "southwest",
    "west", "northwest", "north", "northeast",
}

local bikeDirections = {
    "east", "east-southeast", "southeast", "south-southeast",
    "south", "south-southwest", "southwest", "west-southwest",
    "west", "west-northwest", "northwest", "north-northwest",
    "north", "north-northeast", "northeast", "east-northeast",
}

local directionVectors = {
    north = { 0, -1 }, northeast = { 0.70710678118655, -0.70710678118655 },
    east = { 1, 0 }, southeast = { 0.70710678118655, 0.70710678118655 },
    south = { 0, 1 }, southwest = { -0.70710678118655, 0.70710678118655 },
    west = { -1, 0 }, northwest = { -0.70710678118655, -0.70710678118655 },
}

local function finiteNumber(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return fallback
end

local function surfaceHeight(world, x, z)
    if world.supportHeight then
        local support = world:supportHeight(x, z)
        if type(support) == "number" and support == support
            and support ~= math.huge and support ~= -math.huge then
            return support
        end
    end
    local height = world:height(x, z)
    return finiteNumber(height, 0)
end

local function actorHeight(world,actor,x,z)
    local height=finiteNumber(actor and actor.h,nil)
    if height~=nil then return height end
    return surfaceHeight(world,x,z)
end

local function smoothDamp(current, target, velocity, smoothTime, dt)
    smoothTime = math.max(0.0001, smoothTime)
    local omega = 2 / smoothTime
    local x = omega * dt
    local decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
    local change = current - target
    local temp = (velocity + omega * change) * dt
    velocity = (velocity - omega * temp) * decay
    local value = target + (change + temp) * decay
    if (target - current > 0) == (value > target) then
        value = target
        velocity = 0
    end
    return value, velocity
end

local function headingSector(x, z)
    if math.abs(x) + math.abs(z) < 1e-12 then return "south" end
    local angle
    if math.atan2 then
        angle = math.atan2(z, x)
    elseif x > 0 then
        angle = math.atan(z / x)
    elseif x < 0 and z >= 0 then
        angle = math.atan(z / x) + math.pi
    elseif x < 0 then
        angle = math.atan(z / x) - math.pi
    elseif z > 0 then
        angle = math.pi / 2
    else
        angle = -math.pi / 2
    end
    local sector = math.floor((angle + math.pi / 8) / (math.pi / 4)) % 8 + 1
    return directions[sector]
end

local function headingSector16(x, z)
    if math.abs(x) + math.abs(z) < 1e-12 then return "south" end
    local angle
    if math.atan2 then
        angle = math.atan2(z, x)
    elseif x > 0 then
        angle = math.atan(z / x)
    elseif x < 0 and z >= 0 then
        angle = math.atan(z / x) + math.pi
    elseif x < 0 then
        angle = math.atan(z / x) - math.pi
    elseif z > 0 then
        angle = math.pi / 2
    else
        angle = -math.pi / 2
    end
    local sector = math.floor((angle + math.pi / 16) / (math.pi / 8)) % 16 + 1
    return bikeDirections[sector]
end

local function worldBounds(world)
    local bounds = world.bounds
    if bounds then
        local minX = finiteNumber(bounds.minX or bounds.x0 or bounds.left, nil)
        local maxX = finiteNumber(bounds.maxX or bounds.x1 or bounds.right, nil)
        local minZ = finiteNumber(bounds.minZ or bounds.z0 or bounds.top, nil)
        local maxZ = finiteNumber(bounds.maxZ or bounds.z1 or bounds.bottom, nil)
        if minX and maxX and minZ and maxZ then return minX, minZ, maxX, maxZ end
    end

    local size = finiteNumber(world.size, nil)
    if size then return 0, 0, size, size end
    local width, depth = finiteNumber(world.width, nil), finiteNumber(world.depth, nil)
    if width and depth then return 0, 0, width, depth end

    local minX, maxX = finiteNumber(world.minX, nil), finiteNumber(world.maxX, nil)
    local minZ, maxZ = finiteNumber(world.minZ, nil), finiteNumber(world.maxZ, nil)
    if minX and maxX and minZ and maxZ then return minX, minZ, maxX, maxZ end
    return nil
end

local function clampToWorld(world, x, z)
    local minX, minZ, maxX, maxZ = worldBounds(world)
    if not minX then return x, z end
    return M.clamp(x, minX, maxX), M.clamp(z, minZ, maxZ)
end

local function screenCenter(self)
    return (self.viewportWidth or Camera.SCREEN_WIDTH) * .5,
        (self.viewportHeight or Camera.SCREEN_HEIGHT) * .5
end

function Camera:setViewport(width,height)
    width=math.max(1,math.floor(finiteNumber(width,Camera.SCREEN_WIDTH)+.5))
    height=math.max(1,math.floor(finiteNumber(height,Camera.SCREEN_HEIGHT)+.5))
    self.viewportWidth,self.viewportHeight=width,height
    return width,height
end

function Camera.project(x, z, height)
    return x * 48, z * 29 - height * 22
end

function Camera.new(actor, world)
    assert(type(world) == "table" and type(world.height) == "function", "camera world needs height(x,z)")
    actor = actor or { x = 0, z = 0 }
    local centerX = finiteNumber(actor.x, 0)
    local centerZ = finiteNumber(actor.z, 0)
    local focusHeight = actorHeight(world,actor,centerX,centerZ)
    local x, y = Camera.project(centerX, centerZ, focusHeight)
    return setmetatable({
        world = world,
        lastActor = actor,
        centerX = centerX,
        centerZ = centerZ,
        focusHeight = focusHeight,
        x = x,
        y = y,
        zoom = Camera.ZOOM_DEFAULT,
        targetZoom = Camera.ZOOM_DEFAULT,
        offsetX = 0,
        offsetY = 0,
        centerVelocityX = 0,
        centerVelocityZ = 0,
        yaw = 0,
        tilt = Camera.TILT_DEFAULT,
        outsideMode = 'fixed',
        fixedYaw = 0,
        followYawOffset = 0,
        followOrbitHold = 0,
        followYawVelocity = 0,
    }, Camera)
end

function Camera:_orientationBasis()
    local yaw, tilt = self.yaw, self.tilt
    if self._basisYaw ~= yaw then
        local yawRadians = yaw * rad
        self._yawCos, self._yawSin = math.cos(yawRadians), math.sin(yawRadians)
        self._basisYaw = yaw
    end
    if self._basisTilt ~= tilt then
        local tiltRadians = tilt * rad
        self._groundScale = math.sin(tiltRadians) / defaultGroundSin
        self._heightScale = math.cos(tiltRadians) / defaultHeightCos
        self._basisTilt = tilt
    end
    return self._yawCos, self._yawSin, self._groundScale, self._heightScale
end

function Camera:groundScale()
    local _, _, scale = self:_orientationBasis()
    return scale
end

function Camera:heightScale()
    local _, _, _, scale = self:_orientationBasis()
    return scale
end

local function behindYaw(actor)
    return (-finiteNumber(actor and actor.heading,0)/rad-90)%360
end

function Camera:setOutsideMode(mode,actor,mounted)
    if mode~='fixed' and mode~='follow' and mode~='shoulder' then return false end
    self.lastActor=actor or self.lastActor
    if type(mounted)=='boolean' then self.followMounted=mounted end
    if self.outsideMode==mode then return true end
    if self.outsideMode=='shoulder' then
        self.tilt,self.targetZoom=self.previousTilt,self.previousZoom
        self.shoulderView=nil
        self.shoulderHeadingOffset=nil
    end
    if self.outsideMode=='fixed' then self.fixedYaw=self.yaw end
    if mode~='fixed' then
        if not self.firstPerson and self.followMounted~=false then self.yaw=behindYaw(self.lastActor) end
        -- A slightly steeper default gives the rider a closer over-the-shoulder
        -- view while leaving an existing manual tilt untouched.
        if mode=='shoulder' then
            self.previousTilt,self.previousZoom=self.tilt,self.targetZoom
            self.tilt,self.targetZoom=Camera.SHOULDER_TILT,Camera.SHOULDER_ZOOM
            self.shoulderHeadingOffset=nil
        elseif self.tilt==Camera.TILT_DEFAULT then self.tilt=Camera.FOLLOW_TILT_DEFAULT end
    else self.yaw=self.fixedYaw or self.yaw end
    self.outsideMode=mode
    self.followYawOffset,self.followOrbitHold,self.followYawVelocity=0,0,0
    return true
end

function Camera:setFirstPerson(enabled, actor, onFoot)
    self.firstPerson = enabled == true
    self.shoulderView=nil
    self.shoulderHeadingOffset=nil
    self.lastActor = actor or self.lastActor
    self.walkViewHeading = self.firstPerson and onFoot and (self.lastActor.heading or 0) or nil
    self.centerVelocityX, self.centerVelocityZ = 0, 0
    if self.firstPerson then
        self.eyeHeight = nil
        self.lookYaw, self.lookPitch = 0, 0
        FirstPerson.update(self, self.lastActor, 0)
    else
        self.centerX, self.centerZ = self.lastActor.x, self.lastActor.z
        self.focusHeight = actorHeight(self.world,self.lastActor,self.centerX,self.centerZ)
        self.heightVelocity=0
        if self.outsideMode~='fixed' and self.followMounted~=false then
            self.yaw=behindYaw(self.lastActor)
            self.followYawOffset,self.followOrbitHold,self.followYawVelocity=0,0,0
        end
    end
end

function Camera:toggleView(rider)
    local truck=rider.vehicle=='truck' and rider.truck or nil
    if rider.gear.transition then return false end
    local onFoot=not truck and not rider.gear.mounted
    self.localVehicle=truck and 'truck' or rider.gear.mounted and 'bike' or 'ped'
    self:setFirstPerson(not self.firstPerson, truck or (onFoot and rider.ped or rider.bike),onFoot)
    return true
end

function Camera:updateRide(rider, dt, visual)
    local truck=rider.vehicle=='truck' and rider.truck or nil
    local actor = truck or rider.gear.mounted and rider.bike or rider.ped
    local mounted=(rider.gear.mounted or truck~=nil) and not rider.gear.transition
    self.localVehicle=truck and 'truck' or rider.gear.mounted and 'bike' or 'ped'
    if not mounted and self.followMounted then
        -- Leaving the bike keeps the current outside angle, but a later mount
        -- should not resume an old head-look offset or angular momentum.
        self.followYawOffset,self.followOrbitHold,self.followYawVelocity=0,0,0
    end
    if not mounted then self.shoulderHeadingOffset=nil end
    self.followMounted=mounted
    if self.firstPerson and (rider.gear.transition or (self.walkViewHeading~=nil)==mounted) then
        self:setFirstPerson(false, actor)
    end
    self:update(actor, dt, self.walkViewHeading and actor or truck or visual)
end

function Camera:update(actor, dt, visual)
    if actor then self.lastActor = actor end
    actor = actor or self.lastActor
    if not actor then return end
    dt = math.max(0, finiteNumber(dt, 0))
    if self.firstPerson then FirstPerson.update(self, actor, dt, visual);return end
    local followDt = math.min(dt, 0.1)
    if self.outsideMode~='fixed' and self.followMounted~=false then
        -- Orbit is a temporary look around in follow mode. Once released, the
        -- camera eases back behind the bike, including when the bike is sliding.
        local count=math.max(1,math.ceil(followDt*120-1e-9))
        local yawDt=followDt/count
        local yawSmoothTime=self.outsideMode=='shoulder'
            and Camera.SHOULDER_YAW_SMOOTH_TIME or Camera.FOLLOW_YAW_SMOOTH_TIME
        for _=1,count do
            local returnDt=math.max(0,yawDt-(self.followOrbitHold or 0))
            self.followOrbitHold=math.max(0,(self.followOrbitHold or 0)-yawDt)
            self.followYawOffset=(self.followYawOffset or 0)*math.exp(-returnDt*7)
            local angle,velocity=Damping.angle(self.yaw*rad,
                (behindYaw(actor)+self.followYawOffset)*rad,self.followYawVelocity,
                yawSmoothTime,yawDt)
            self.yaw=(angle/rad)%360;self.followYawVelocity=velocity
        end
    end
    local c, s, groundScale = self:_orientationBasis()
    local localX = self.offsetX / 48
    local localZ = self.offsetY / (29 * groundScale)
    local panX = localX * c + localZ * s
    local panZ = -localX * s + localZ * c
    local targetX = finiteNumber(actor.x, self.centerX) + panX
    local targetZ = finiteNumber(actor.z, self.centerZ) + panZ

    local speed = math.max(0, finiteNumber(visual and visual.speed or actor.speed, 0))
    local heading = finiteNumber(actor.heading, 0)
    if speed > 0 then
        local lead = Camera.FOLLOW_LOOKAHEAD_DISTANCE * M.clamp(
            speed / Camera.FOLLOW_LOOKAHEAD_FULL_SPEED, 0, 1)
        targetX = targetX + math.cos(heading) * lead
        targetZ = targetZ + math.sin(heading) * lead
    end
    targetX, targetZ = clampToWorld(self.world, targetX, targetZ)

    if self.outsideMode=='shoulder' then
        -- Let the bike move across the shoulder frame more freely side to
        -- side than it moves toward or away from the camera. Work in the
        -- camera's local axes so the extra lag follows its current orbit.
        local currentRight=self.centerX*c-self.centerZ*s
        local currentForward=self.centerX*s+self.centerZ*c
        local targetRight=targetX*c-targetZ*s
        local targetForward=targetX*s+targetZ*c
        local velocityRight=(self.centerVelocityX or 0)*c-(self.centerVelocityZ or 0)*s
        local velocityForward=(self.centerVelocityX or 0)*s+(self.centerVelocityZ or 0)*c
        currentRight,velocityRight=smoothDamp(currentRight,targetRight,velocityRight,
            Camera.SHOULDER_LATERAL_SMOOTH_TIME,followDt)
        currentForward,velocityForward=smoothDamp(currentForward,targetForward,velocityForward,
            Camera.SHOULDER_FOLLOW_SMOOTH_TIME,followDt)
        self.centerX=currentRight*c+currentForward*s
        self.centerZ=-currentRight*s+currentForward*c
        self.centerVelocityX=velocityRight*c+velocityForward*s
        self.centerVelocityZ=-velocityRight*s+velocityForward*c
        self.centerX,self.centerZ=clampToWorld(self.world,self.centerX,self.centerZ)
    else
        self.centerX, self.centerVelocityX = smoothDamp(self.centerX, targetX,
            self.centerVelocityX or 0, Camera.FOLLOW_SMOOTH_TIME, followDt)
        self.centerZ, self.centerVelocityZ = smoothDamp(self.centerZ, targetZ,
            self.centerVelocityZ or 0, Camera.FOLLOW_SMOOTH_TIME, followDt)
    end
    local height=actorHeight(self.world,actor,self.centerX,self.centerZ)
    self.landingTarget=Landing.target(self.world,actor,visual)
    if self.landingTarget then
        -- Keep both the jumping rider and the lower landing surface in view.
        height=height-M.clamp(height-self.landingTarget.h,0,4)*.6
    end
    if finiteNumber(actor.h,nil)~=nil then
        self.focusHeight,self.heightVelocity=smoothDamp(self.focusHeight,height,self.heightVelocity or 0,.18,followDt)
    else self.focusHeight=height;self.heightVelocity=0 end
    self.x, self.y = Camera.project(self.centerX, self.centerZ, self.focusHeight)
    self.zoom = M.lerp(self.zoom, self.targetZoom, 1 - math.exp(-dt * 12))
    if self.outsideMode=='shoulder' and self.followMounted~=false then
        self._shoulderCamera=self._shoulderCamera or Camera.new(actor,self.world)
        self.shoulderView=self._shoulderCamera
        require('src.commute.shoulder_camera').update(self.shoulderView,self,actor)
    else self.shoulderView=nil end
end

function Camera:screen(x, z, height)
    if self.shoulderView then return self.shoulderView:screen(x,z,height) end
    -- Lua evaluates function arguments eagerly. Do not sample the terrain as
    -- a fallback argument when scenery already supplies its cached elevation.
    height = finiteNumber(height, nil)
    if height == nil then height = surfaceHeight(self.world, x, z) end
    if self.firstPerson then return FirstPerson.screen(self,x,z,height) end
    local centerX,centerY=screenCenter(self)
    local c, s, groundScale, heightScale = self:_orientationBasis()
    local dx, dz = x - self.centerX, z - self.centerZ
    local right = dx * c - dz * s
    local depth = dx * s + dz * c
    return centerX + right * 48 * self.zoom,
        centerY + (depth * 29 * groundScale
            - (height - self.focusHeight) * 22 * heightScale) * self.zoom
end

function Camera:screenToWorld(sx, sy)
    local centerX,centerY=screenCenter(self)
    local c, s, groundScale, heightScale = self:_orientationBasis()
    local right = (sx - centerX) / (48 * self.zoom)
    local originX = self.centerX + right * c
    local originZ = self.centerZ - right * s
    local dirX, dirZ = s, c

    local minX, minZ, maxX, maxZ = worldBounds(self.world)
    local safeMinX, safeMinZ, safeMaxX, safeMaxZ
    if minX then
        safeMinX, safeMinZ = minX, minZ
        safeMaxX, safeMaxZ = math.max(minX, maxX - 1e-7), math.max(minZ, maxZ - 1e-7)
    else
        safeMinX, safeMinZ, safeMaxX, safeMaxZ = -8192, -8192, 8192, 8192
    end

    local function clipAxis(origin, delta, lower, upper, lo, hi)
        if math.abs(delta) < 1e-12 then
            if origin < lower or origin > upper then return nil end
            return lo, hi
        end
        local a, b = (lower - origin) / delta, (upper - origin) / delta
        if a > b then a, b = b, a end
        return math.max(lo, a), math.min(hi, b)
    end

    local boundLo, boundHi = -math.huge, math.huge
    boundLo, boundHi = clipAxis(originX, dirX, safeMinX, safeMaxX, boundLo, boundHi)
    if not boundLo then
        local flatDepth = (sy - centerY) / (self.zoom * 29 * groundScale)
        return clampToWorld(self.world, originX + flatDepth * dirX, originZ + flatDepth * dirZ)
    end
    boundLo, boundHi = clipAxis(originZ, dirZ, safeMinZ, safeMaxZ, boundLo, boundHi)
    if not boundLo or boundLo > boundHi then
        local flatDepth = (sy - centerY) / (self.zoom * 29 * groundScale)
        return clampToWorld(self.world, originX + flatDepth * dirX, originZ + flatDepth * dirZ)
    end

    local maxHeight = finiteNumber(self.world.maxSupportHeight,
        finiteNumber(self.world.maxHeight, 84))
    local screenOffset = (sy - centerY) / self.zoom
    local heightDepth0 = (screenOffset - self.focusHeight * 22 * heightScale) / (29 * groundScale)
    local heightDepthMax = (screenOffset + (maxHeight - self.focusHeight) * 22 * heightScale)
        / (29 * groundScale)
    local lo = math.max(boundLo, math.min(heightDepth0, heightDepthMax))
    local hi = math.min(boundHi, math.max(heightDepth0, heightDepthMax))
    if lo > hi then
        local depth = M.clamp(heightDepth0, boundLo, boundHi)
        return clampToWorld(self.world, originX + depth * dirX, originZ + depth * dirZ)
    end

    local function residual(depth)
        local x, z = originX + depth * dirX, originZ + depth * dirZ
        local rawHeight = surfaceHeight(self.world, x, z)
        local height = math.max(0, rawHeight)
        return centerY + (depth * 29 * groundScale
            - (height - self.focusHeight) * 22 * heightScale) * self.zoom - sy,
            rawHeight
    end

    local function nextGridBoundary(depth, base, slope, lower)
        if math.abs(slope) < 1e-12 then return nil end
        local coordinate = base + slope * depth
        local edge
        if slope > 0 then edge = math.ceil(coordinate - 1e-9) - 1
        else edge = math.floor(coordinate + 1e-9) + 1 end
        local crossing = (edge - base) / slope
        if crossing >= depth - 1e-9 then
            edge = edge + (slope > 0 and -1 or 1)
            crossing = (edge - base) / slope
        end
        if crossing <= lower + 1e-9 then return lower end
        return crossing
    end

    local gridX, gridZ = 2 * originX, 2 * originZ
    local stepX, stepZ = 2 * dirX, 2 * dirZ
    local gridSum, stepSum = gridX + gridZ, stepX + stepZ
    local depth = hi
    local value, rawHeight = residual(depth)
    local bestDepth, bestAbs = depth, math.abs(value)
    if bestAbs < 1e-7 then return clampToWorld(self.world,
        originX + depth * dirX, originZ + depth * dirZ) end

    local maxSegments = math.min(10000, math.ceil((hi - lo)
        * (math.abs(stepX) + math.abs(stepZ) + math.abs(stepSum) + 8)))
    local function chooseBoundary(current, candidate)
        if candidate and candidate < depth - 1e-9 and candidate > current then return candidate end
        return current
    end
    local function crossing(d0, f0, d1, f1)
        if math.abs(f0) < 1e-7 then return d0 end
        if math.abs(f1) < 1e-7 then return d1 end
        if f0 * f1 < 0 then return d0 + (d1 - d0) * (f0 / (f0 - f1)) end
    end

    -- Terrain triangles use half-unit cells. Walking their grid and diagonal
    -- edges keeps the screen ray exact for planar slopes and finds the nearest
    -- support surface when a bridge deck sits above the ground.
    for _ = 1, maxSegments do
        local nextDepth = lo
        nextDepth = chooseBoundary(nextDepth, nextGridBoundary(depth, gridX, stepX, lo))
        nextDepth = chooseBoundary(nextDepth, nextGridBoundary(depth, gridZ, stepZ, lo))
        nextDepth = chooseBoundary(nextDepth, nextGridBoundary(depth, gridSum, stepSum, lo))
        local nextValue, nextRawHeight = residual(nextDepth)
        local nextAbs = math.abs(nextValue)
        if nextAbs < bestAbs then bestDepth, bestAbs = nextDepth, nextAbs end
        if rawHeight * nextRawHeight < 0 then
            local waterDepth = depth + (nextDepth - depth) * (rawHeight / (rawHeight - nextRawHeight))
            local waterValue = residual(waterDepth)
            local waterAbs = math.abs(waterValue)
            if waterAbs < bestAbs then bestDepth, bestAbs = waterDepth, waterAbs end
            local waterHit = crossing(depth, value, waterDepth, waterValue)
                or crossing(waterDepth, waterValue, nextDepth, nextValue)
            if waterHit then
                return clampToWorld(self.world, originX + waterHit * dirX, originZ + waterHit * dirZ)
            end
        end
        local hitDepth = crossing(depth, value, nextDepth, nextValue)
        if hitDepth then return clampToWorld(self.world,
            originX + hitDepth * dirX, originZ + hitDepth * dirZ) end
        if nextAbs < 1e-7 then
            return clampToWorld(self.world, originX + nextDepth * dirX, originZ + nextDepth * dirZ)
        end
        if nextDepth <= lo + 1e-9 then break end
        depth, value, rawHeight = nextDepth, nextValue, nextRawHeight
    end
    return clampToWorld(self.world, originX + bestDepth * dirX, originZ + bestDepth * dirZ)
end

function Camera:depth(x, z, height)
    height = finiteNumber(height, nil)
    if height == nil then height = surfaceHeight(self.world, x, z) end
    if self.firstPerson then
        local _,_,depth=FirstPerson.coordinates(self,x,z,height)
        return -depth
    end
    local _, _, groundScale, heightScale = self:_orientationBasis()
    local groundDepth = (x - self.centerX) * self._yawSin + (z - self.centerZ) * self._yawCos
    return groundDepth * 22 * heightScale + (height - self.focusHeight) * 29 * groundScale
end

function Camera:relativeDirection(heading)
    local vector = directionVectors[type(heading) == "string" and heading:lower() or ""]
        or directionVectors.south
    local c, s = self:_orientationBasis()
    return headingSector(vector[1] * c - vector[2] * s, vector[1] * s + vector[2] * c)
end

function Camera:headingDirection(radians)
    radians = finiteNumber(radians, 0)
    if self.firstPerson then
        local angle=radians-self.viewHeading
        return headingSector(math.sin(angle),-math.cos(angle))
    end
    local worldX, worldZ = math.cos(radians), math.sin(radians)
    local c, s = self:_orientationBasis()
    return headingSector(worldX * c - worldZ * s, worldX * s + worldZ * c)
end

function Camera:headingDirection16(radians)
    radians = finiteNumber(radians, 0)
    if self.firstPerson then
        local angle=radians-self.viewHeading
        return headingSector16(math.sin(angle),-math.cos(angle))
    end
    local worldX, worldZ = math.cos(radians), math.sin(radians)
    local c, s = self:_orientationBasis()
    return headingSector16(worldX * c - worldZ * s, worldX * s + worldZ * c)
end

function Camera:screenVectorToWorld(right, depth)
    if self.walkViewHeading then
        return -right*self.viewSin-depth*self.viewCos,right*self.viewCos-depth*self.viewSin
    end
    local c, s = self:_orientationBasis()
    return right * c + depth * s, -right * s + depth * c
end

-- Invert the ground-plane scale used by screen(), including the orbit tilt.
function Camera:screenGroundDirection(dx,dy,actor)
    if self.shoulderView and actor then
        -- Invert the perspective ground-plane projection at the rider.
        local eye=self.shoulderView
        local h=actor.h or eye.focusHeight
        local sx,_,depth=eye:screen(actor.x,actor.z,h)
        local forward=dy*depth/math.min(-.01,h-eye.eyeHeight)
        local right=dx+(sx-(eye.viewportWidth or 1280)*.5)/eye.focal*math.cos(eye.viewPitch)*forward
        return eye.viewCos*forward-eye.viewSin*right,eye.viewSin*forward+eye.viewCos*right
    end
    return self:screenVectorToWorld(dx/48,dy/(29*self:groundScale()))
end

function Camera:orbit(yawDeltaDegrees, tiltDeltaDegrees)
    if self.firstPerson then
        if self.walkViewHeading then
            self.walkViewHeading=(self.walkViewHeading+finiteNumber(yawDeltaDegrees,0)*rad)%(2*math.pi)
        else
            self.lookYaw=M.clamp((self.lookYaw or 0)+finiteNumber(yawDeltaDegrees,0)*rad,-FirstPerson.LOOK_YAW*rad,FirstPerson.LOOK_YAW*rad)
        end
        self.lookPitch=M.clamp((self.lookPitch or 0)+finiteNumber(tiltDeltaDegrees,0)*rad,-FirstPerson.LOOK_DOWN*rad,FirstPerson.LOOK_UP*rad)
        FirstPerson.update(self,self.lastActor,0)
        return
    end
    self.yaw = (self.yaw + finiteNumber(yawDeltaDegrees, 0)) % 360
    if self.outsideMode~='fixed' and self.followMounted~=false and finiteNumber(yawDeltaDegrees,0)~=0 then
        self.followYawOffset=M.clamp((self.followYawOffset or 0)+yawDeltaDegrees,-180,180)
        self.followOrbitHold=Camera.FOLLOW_ORBIT_HOLD
        self.followYawVelocity=0
    elseif self.outsideMode=='fixed' then self.fixedYaw=self.yaw end
    self.tilt = M.clamp(self.tilt + finiteNumber(tiltDeltaDegrees, 0), Camera.TILT_MIN, Camera.TILT_MAX)
end

function Camera:zoomBy(amount)
    if self.firstPerson then
        self.fov=M.clamp(self.fov-finiteNumber(amount,0)*3,60,100)
        FirstPerson.update(self,self.lastActor,0)
        return
    end
    self.targetZoom = M.clamp(self.targetZoom * math.exp(finiteNumber(amount, 0) * 0.12),
        Camera.ZOOM_MIN, Camera.ZOOM_MAX)
end

function Camera:pan(dx, dy)
    if self.firstPerson then return end
    self.offsetX = self.offsetX - finiteNumber(dx, 0) / self.zoom
    self.offsetY = self.offsetY - finiteNumber(dy, 0) / self.zoom
end

function Camera:recenter()
    if self.firstPerson then
        FirstPerson.recenter(self)
        return
    end
    self.offsetX, self.offsetY = 0, 0
    if self.outsideMode=='shoulder' then self.shoulderHeadingOffset=nil end
    self.targetZoom = self.outsideMode=='shoulder' and Camera.SHOULDER_ZOOM or Camera.ZOOM_DEFAULT
    self.zoom = self.targetZoom
    self.yaw = self.outsideMode~='fixed' and self.followMounted~=false and behindYaw(self.lastActor) or 0
    self.tilt = self.outsideMode=='shoulder' and Camera.SHOULDER_TILT or Camera.TILT_DEFAULT
    self.followYawOffset,self.followOrbitHold,self.followYawVelocity=0,0,0
    if self.outsideMode=='fixed' then self.fixedYaw=self.yaw end
    self.centerVelocityX, self.centerVelocityZ = 0, 0
    if self.lastActor then
        self.centerX, self.centerZ = clampToWorld(self.world,
            finiteNumber(self.lastActor.x, self.centerX), finiteNumber(self.lastActor.z, self.centerZ))
        self.focusHeight = actorHeight(self.world,self.lastActor,self.centerX,self.centerZ)
        self.heightVelocity=0
        self.x, self.y = Camera.project(self.centerX, self.centerZ, self.focusHeight)
    end
end

function Camera:send(shader)
    if shader:hasUniform('cameraScreenCenter') then
        local centerX,centerY=screenCenter(self)
        shader:send('cameraScreenCenter',{centerX,centerY})
    end
    if shader:hasUniform('firstPerson') then
        shader:send('firstPerson',self.firstPerson==true)
        if self.firstPerson then FirstPerson.send(self,shader) end
    end
    local _, _, groundScale, heightScale = self:_orientationBasis()
    if shader:hasUniform("cameraWorldX") then
        shader:send("cameraWorldX", self.centerX)
        shader:send("cameraWorldZ", self.centerZ)
        shader:send("focusHeight", self.focusHeight)
        shader:send("cameraZoom", self.zoom)
        shader:send("cameraYaw", self.yaw * rad)
        shader:send("groundScale", groundScale)
        shader:send("heightScale", heightScale)
    else
        -- The source Critter Party shader uses a packed center and longer
        -- scale names; retain that contract for shader copies that keep it.
        shader:send("cameraCenter", { self.centerX, self.centerZ })
        shader:send("cameraFocusHeight", self.focusHeight)
        shader:send("cameraZoom", self.zoom)
        shader:send("cameraYaw", self.yaw * rad)
        shader:send("cameraGroundScale", groundScale)
        shader:send("cameraHeightScale", heightScale)
    end
end

return Camera
