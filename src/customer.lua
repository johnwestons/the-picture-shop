-- Transient customer movement and reception behavior. The paperwork screen
-- drives these review/resolve transitions while the visitor remains in-world.
local CharacterAnimation = require("src.character_animation")
local GaitMotion = require("src.gait_motion")

local Customer = {}
local Instance = {}
Instance.__index = Instance

local NETWORK_STATES = {
    scheduled = true,
    entering = true,
    waiting = true,
    reviewing = true,
    exiting = true,
    finished = true,
}

local NETWORK_DECISIONS = { accepted = true, declined = true, timed_out = true }

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function copyRoute(route)
    local result = {}
    for index, point in ipairs(route or {}) do
        result[index] = { x = point.x, y = point.y }
    end
    return result
end

local function routeForSeat(instance, seatIndex)
    local route = copyRoute(instance.baseRoute)
    local seat = type(instance.seatSpots) == "table" and instance.seatSpots[seatIndex] or nil
    if not seat then return route, nil end
    for _, point in ipairs(seat.approach or {}) do
        route[#route + 1] = { x = point.x, y = point.y }
    end
    route[#route + 1] = { x = seat.x, y = seat.y }
    return route, seat
end

local function distanceSquared(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
end

local function randomDelay(minimum, maximum, fallback)
    minimum = tonumber(minimum)
    maximum = tonumber(maximum)
    if not minimum and not maximum then return math.max(0, tonumber(fallback) or 1) end
    minimum = math.max(0, minimum or maximum or 0)
    maximum = math.max(minimum, maximum or minimum)
    return minimum + (maximum - minimum) * math.random()
end

local function approach(value, target, amount)
    if value < target then return math.min(target, value + amount) end
    if value > target then return math.max(target, value - amount) end
    return target
end

local function moveToward(instance, target, distance)
    local dx, dy = target.x - instance.x, target.y - instance.y
    local length = math.sqrt(dx * dx + dy * dy)
    if dx ~= 0 then instance.facing = dx < 0 and -1 or 1 end
    if length <= distance or length == 0 then
        instance.x, instance.y = target.x, target.y
        return true, math.max(0, distance - length)
    end
    instance.x = instance.x + dx / length * distance
    instance.y = instance.y + dy / length * distance
    return false, 0
end

function Customer.new(definition)
    assert(type(definition) == "table", "customer definition is required")
    assert(type(definition.route) == "table" and #definition.route >= 2,
        "customer route requires at least two points")
    local instance = setmetatable({
        character = definition.character or "green-blazer-cat",
        characterPool = definition.characterPool,
        characterIndex = 0,
        seatSpots = definition.seatSpots,
        seatIndex = 0,
        maxWaitSeconds = definition.maxWaitSeconds or 300,
        drawScale = definition.drawScale or 0.30,
        speed = definition.speed or 72,
        walkAnimationRate = definition.walkAnimationRate or 4,
        idleAnimationRate = definition.idleAnimationRate or 0.65,
        useAnimationRate = definition.useAnimationRate or 2.5,
        seatingPauseDuration = definition.seatingPauseDuration or 0.28,
        motionProfiles = definition.motionProfiles or {},
        arrivalDelay = definition.arrivalDelay or 1,
        initialArrivalDelay = definition.initialArrivalDelay,
        initialArrivalDelayMin = definition.initialArrivalDelayMin,
        initialArrivalDelayMax = definition.initialArrivalDelayMax,
        arrivalDelayMin = definition.arrivalDelayMin,
        arrivalDelayMax = definition.arrivalDelayMax,
        interactionRadius = definition.interactionRadius or 58,
        baseRoute = copyRoute(definition.route),
        route = {},
    }, Instance)
    instance:reset(true)
    return instance
end

function Instance:reset(initialVisit)
    if type(self.characterPool) == "table" and #self.characterPool > 0 then
        self.characterIndex = self.characterIndex % #self.characterPool + 1
        self.character = self.characterPool[self.characterIndex]
    end
    if type(self.seatSpots) == "table" and #self.seatSpots > 0 then
        self.seatIndex = self.seatIndex % #self.seatSpots + 1
        self.route, self.seat = routeForSeat(self, self.seatIndex)
        self.seatFacing = self.seat.facing or 1
    else
        self.route, self.seat = routeForSeat(self, 0)
        self.seatFacing = nil
    end
    local spawn = self.route[1]
    self.x, self.y = spawn.x, spawn.y
    self.state = "scheduled"
    self.visible = false
    self.timer = initialVisit
        and randomDelay(self.initialArrivalDelayMin, self.initialArrivalDelayMax,
            self.initialArrivalDelay ~= nil and self.initialArrivalDelay or self.arrivalDelay)
        or randomDelay(self.arrivalDelayMin, self.arrivalDelayMax, self.arrivalDelay)
    self.waypoint = 2
    self.facing = 1
    self.intentX, self.intentY = 1, 0
    self.motionX, self.motionY = 0, 0
    self.currentSpeed = 0
    self.animationDistance = 0
    self.gaitSpeedMultiplier, self.gaitAccelerationMultiplier = 1, 1
    self.animationClock = 0
    self.idleClock = 0
    self.inMotion = false
    self.decision = nil
    self.waitTimer = 0
    self.seatingPause = 0
end

local function settleIntoSeat(instance)
    instance.x, instance.y = instance.seat.x, instance.seat.y
    instance.state = "waiting"
    instance.waypoint = #instance.route
    instance.waitTimer = 0
    instance.seatingPause = 0
    instance.currentSpeed = 0
    instance.facing = instance.seatFacing or instance.facing
    instance.intentX, instance.intentY = instance.facing, 0
    return "arrived"
end

local function leaveSeat(instance)
    if instance.seat and #instance.route >= 2 then
        local standingPoint = instance.route[#instance.route - 1]
        instance.x, instance.y = standingPoint.x, standingPoint.y
        instance.waypoint = math.max(1, #instance.route - 2)
    else
        instance.waypoint = #instance.route - 1
    end
    instance.seatingPause = 0
    instance.currentSpeed = 0
    instance.inMotion = false
end

function Instance:update(dt, player, pauseSchedule)
    dt = math.max(0, dt or 0)
    self.inMotion = false
    self.motionX, self.motionY = 0, 0
    if self.state == "scheduled" then
        if pauseSchedule then return nil end
        self.timer = self.timer - dt
        if self.timer > 0 then return nil end
        self.state = "entering"
        self.visible = true
    end

    -- Stop in front of the furniture before changing pose. The seat itself is
    -- a render anchor, not a walking waypoint; walking into that anchor made
    -- the visitor appear to melt through the chair before sitting.
    if self.state == "entering" and self.seatingPause > 0 then
        self.seatingPause = math.max(0, self.seatingPause - dt)
        self.currentSpeed = 0
        self.facing = self.seatFacing or self.facing
        self.intentX, self.intentY = self.facing, 0
        self.idleClock = self.idleClock + dt
        if self.seatingPause > 0 then return nil end
        return settleIntoSeat(self)
    end

    if self.state ~= "entering" and self.state ~= "exiting" then
        self.currentSpeed = 0
        self.gaitSpeedMultiplier, self.gaitAccelerationMultiplier = 1, 1
        self.idleClock = self.idleClock + dt
        if self.state == "waiting" then
            self.waitTimer = self.waitTimer + dt
            self.facing = self.seatFacing or (player and (player.x < self.x and -1 or 1)) or 1
            if self.waitTimer >= self.maxWaitSeconds then
                self.decision = "timed_out"
                self.state = "exiting"
                leaveSeat(self)
                return "timed_out"
            end
        elseif self.state == "reviewing" then
            self.animationClock = self.animationClock + dt
            self.facing = self.seatFacing or (player and (player.x < self.x and -1 or 1)) or 1
        end
        return nil
    end

    -- A customer politely pauses instead of walking through the player.
    if player and distanceSquared(self, player) < 28 * 28 then
        self.currentSpeed = 0
        self.gaitSpeedMultiplier, self.gaitAccelerationMultiplier = 1, 1
        self.idleClock = self.idleClock + dt
        return nil
    end

    local startX, startY = self.x, self.y
    local motionProfile = self.motionProfiles[self.character]
    local travel
    if motionProfile then
        local gaitSpeed, gaitAcceleration = GaitMotion.sample(
            self.animationDistance, motionProfile)
        self.gaitSpeedMultiplier = gaitSpeed
        self.gaitAccelerationMultiplier = gaitAcceleration
        local targetSpeed = self.speed * gaitSpeed
        self.currentSpeed = approach(self.currentSpeed, targetSpeed,
            (motionProfile.acceleration or 420) * gaitAcceleration * dt)
        travel = self.currentSpeed * dt
    else
        self.currentSpeed = self.speed
        self.gaitSpeedMultiplier, self.gaitAccelerationMultiplier = 1, 1
        travel = self.speed * dt
    end
    local event
    while travel > 0 do
        local target = self.route[self.waypoint]
        if not target then
            if self.state == "entering" then
                self.state = "waiting"
                self.waypoint = #self.route
                self.waitTimer = 0
                self.currentSpeed = 0
                event = "arrived"
                break
            end
            self.state = "finished"
            self.visible = false
            self.waypoint = 1
            self.currentSpeed = 0
            event = "exited"
            break
        end
        local reached, remaining = moveToward(self, target, travel)
        if not reached then break end
        travel = remaining
        self.waypoint = self.state == "entering" and self.waypoint + 1 or self.waypoint - 1
        if self.state == "entering" and self.seat and self.waypoint == #self.route then
            local secondsRemaining = travel / math.max(1, self.currentSpeed)
            if secondsRemaining >= self.seatingPauseDuration then
                event = settleIntoSeat(self)
            else
                self.seatingPause = self.seatingPauseDuration - secondsRemaining
                self.currentSpeed = 0
                self.facing = self.seatFacing or self.facing
                self.intentX, self.intentY = self.facing, 0
            end
            break
        end
    end
    local movedX, movedY = self.x - startX, self.y - startY
    local distance = math.sqrt(movedX * movedX + movedY * movedY)
    self.inMotion = distance > 0.0001
    if self.inMotion then
        self.animationClock = self.animationClock + dt
        self.idleClock = 0
        self.motionX, self.motionY = movedX / distance, movedY / distance
        self.intentX, self.intentY = self.motionX, self.motionY
        self.animationDistance = self.animationDistance + distance
        if math.abs(self.motionX) > 0.08 then self.facing = self.motionX < 0 and -1 or 1 end
    else
        self.idleClock = self.idleClock + dt
    end
    if event == "arrived" then
        self.inMotion = false
        self.motionX, self.motionY = 0, 0
        self.facing = self.seatFacing or self.facing
        self.intentX, self.intentY = self.facing, 0
    end
    return event
end

function Instance:isPresent()
    return self.state ~= "scheduled" and self.state ~= "finished"
end

function Instance:beginReview()
    if self.state ~= "waiting" then return false end
    self.state = "reviewing"
    return true
end

function Instance:cancelReview()
    if self.state ~= "reviewing" then return false end
    self.state = "waiting"
    return true
end

function Instance:resolve(decision)
    if self.state ~= "reviewing" then return false end
    if decision ~= "accepted" and decision ~= "declined" then return false end
    self.decision = decision
    self.state = "exiting"
    leaveSeat(self)
    return true
end

function Instance:getInteraction()
    if self.state ~= "waiting" and self.state ~= "reviewing" then return nil end
    return {
        x = self.x,
        y = self.y,
        radius = self.interactionRadius,
        customerState = self.state,
        prompt = self.state == "waiting"
            and "E: look at customer job"
            or "Review job; request written details by email",
    }
end

function Instance:getObstacle()
    if not self.visible then return nil end
    return { x = self.x, y = self.y, radius = 16 }
end

function Instance:isMoving()
    return (self.state == "entering" or self.state == "exiting") and self.inMotion == true
end

function Instance:frameForAction(action, frameCount)
    local motionProfile = self.motionProfiles[self.character]
    if motionProfile and CharacterAnimation.isWalkAction(action) then
        return CharacterAnimation.frameForDistance(frameCount, self.animationDistance,
            motionProfile.walkPixelsPerFrame)
    end
    if type(action) == "string" and (action == "idle" or action:match("^idle_")) then
        return CharacterAnimation.frameForClock(frameCount, self.idleClock,
            self.idleAnimationRate)
    end
    return CharacterAnimation.frameForAction(action, frameCount, self.animationClock,
        self.walkAnimationRate, self.useAnimationRate)
end

function Instance:snapshot()
    return {
        state = self.state,
        visible = self.visible,
        x = self.x,
        y = self.y,
        waypoint = self.waypoint,
        seatIndex = self.seatIndex,
        character = self.character,
        facing = self.facing,
        intentX = self.intentX,
        intentY = self.intentY,
        motionX = self.motionX,
        motionY = self.motionY,
        currentSpeed = self.currentSpeed,
        animationDistance = self.animationDistance,
        animationClock = self.animationClock,
        idleClock = self.idleClock,
        inMotion = self.inMotion,
        decision = self.decision,
        waitTimer = self.waitTimer,
        arrivalTimer = self.timer,
    }
end

-- LAN guests do not simulate reception schedules. They install the host's
-- validated visitor pose instead, keeping both devices on the same customer
-- and vendor without granting the guest authority over either state machine.
function Instance:applySnapshot(snapshot)
    local snapshotRoute, snapshotSeat = routeForSeat(self, snapshot and snapshot.seatIndex or 0)
    if type(snapshot) ~= "table" or not NETWORK_STATES[snapshot.state]
        or type(snapshot.visible) ~= "boolean"
        or not finite(snapshot.x) or not finite(snapshot.y)
        or type(snapshot.waypoint) ~= "number" or snapshot.waypoint % 1 ~= 0
        or snapshot.waypoint < 1 or snapshot.waypoint > #snapshotRoute
        or type(snapshot.seatIndex) ~= "number" or snapshot.seatIndex % 1 ~= 0
        or snapshot.seatIndex < 0
        or (type(self.seatSpots) == "table" and snapshot.seatIndex > #self.seatSpots)
        or type(snapshot.character) ~= "string" or snapshot.character == ""
        or (snapshot.facing ~= -1 and snapshot.facing ~= 1)
        or type(snapshot.inMotion) ~= "boolean"
        or (snapshot.decision ~= nil and not NETWORK_DECISIONS[snapshot.decision])
    then
        return false
    end
    for _, field in ipairs({
        "intentX", "intentY", "motionX", "motionY", "currentSpeed",
        "animationDistance", "animationClock", "idleClock", "waitTimer", "arrivalTimer",
    }) do
        if not finite(snapshot[field]) then return false end
    end
    if snapshot.currentSpeed < 0 or snapshot.animationDistance < 0
        or snapshot.animationClock < 0 or snapshot.idleClock < 0 or snapshot.waitTimer < 0
    then
        return false
    end

    self.state = snapshot.state
    self.visible = snapshot.visible
    self.x, self.y = snapshot.x, snapshot.y
    self.waypoint = snapshot.waypoint
    self.seatIndex = snapshot.seatIndex
    self.character = snapshot.character
    self.facing = snapshot.facing
    self.intentX, self.intentY = snapshot.intentX, snapshot.intentY
    self.motionX, self.motionY = snapshot.motionX, snapshot.motionY
    self.currentSpeed = snapshot.currentSpeed
    self.animationDistance = snapshot.animationDistance
    self.animationClock = snapshot.animationClock
    self.idleClock = snapshot.idleClock
    self.inMotion = snapshot.inMotion
    self.decision = snapshot.decision
    self.waitTimer = snapshot.waitTimer
    self.timer = snapshot.arrivalTimer
    self.seatingPause = 0
    self.route, self.seat = snapshotRoute, snapshotSeat
    if self.seat then
        self.seatFacing = self.seat.facing or 1
    else
        self.seatFacing = nil
    end
    return true
end

function Instance:draw(characterAssets)
    if not self.visible then return end
    local action = self.state == "reviewing" and characterAssets.hasAction(self.character, "use")
        and "use" or ((self.state == "waiting" or self.state == "reviewing")
            and "sit" or (self:isMoving() and "walk" or "idle"))
    local directionScale = self.facing
    if CharacterAnimation.isWalkAction(action) then
        local directionalAction, mirror = CharacterAnimation.directionalWalkAction(
            self.motionX ~= 0 and self.motionX or self.intentX,
            self.motionY ~= 0 and self.motionY or self.intentY)
        if characterAssets.hasAction(self.character, directionalAction) then action = directionalAction end
        directionScale = mirror
    elseif action == "idle" then
        local directionalAction, mirror = CharacterAnimation.directionalIdleAction(
            self.intentX, self.intentY)
        if characterAssets.hasAction(self.character, directionalAction) then action = directionalAction end
        directionScale = mirror
    end
    local image, quad, frameCount = characterAssets.get(self.character, action, 1)
    frameCount = frameCount or 1
    -- Seated/idle clients use one clean atlas cell. Walking and explicit use
    -- actions advance without making a blocked visitor slide in place.
    local frame = self:frameForAction(action, frameCount)
    image, quad, frameCount = characterAssets.get(self.character, action, frame)
    local anchorX, anchorY = characterAssets.getAnchor(self.character, action, frame)
    local normalization = characterAssets.getNormalization(self.character, action)

    if image and quad then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(
            image,
            quad,
            self.x,
            self.y,
            0,
            self.drawScale * normalization * directionScale,
            self.drawScale * normalization,
            anchorX,
            anchorY
        )
        return
    end

    love.graphics.setColor(0.18, 0.30, 0.20)
    love.graphics.rectangle("fill", self.x - 10, self.y - 38, 20, 38)
end

Customer.Instance = Instance
return Customer
