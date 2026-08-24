-- Transient customer movement and reception behavior. Job paperwork is
-- intentionally left to the next implementation step; this module exposes
-- review/resolve transitions that the future popup can call.
local Customer = {}
local Instance = {}
Instance.__index = Instance

local function copyRoute(route)
    local result = {}
    for index, point in ipairs(route or {}) do
        result[index] = { x = point.x, y = point.y }
    end
    return result
end

local function distanceSquared(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
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
        drawScale = definition.drawScale or 0.34,
        speed = definition.speed or 72,
        walkAnimationRate = definition.walkAnimationRate or 4,
        arrivalDelay = definition.arrivalDelay or 1,
        interactionRadius = definition.interactionRadius or 58,
        route = copyRoute(definition.route),
    }, Instance)
    instance:reset()
    return instance
end

function Instance:reset()
    if type(self.characterPool) == "table" and #self.characterPool > 0 then
        self.characterIndex = self.characterIndex % #self.characterPool + 1
        self.character = self.characterPool[self.characterIndex]
    end
    if type(self.seatSpots) == "table" and #self.seatSpots > 0 then
        self.seatIndex = self.seatIndex % #self.seatSpots + 1
        self.seat = self.seatSpots[self.seatIndex]
        self.seatFacing = self.seat.facing or 1
        self.route[#self.route] = { x = self.seat.x, y = self.seat.y }
    end
    local spawn = self.route[1]
    self.x, self.y = spawn.x, spawn.y
    self.state = "scheduled"
    self.visible = false
    self.timer = self.arrivalDelay
    self.waypoint = 2
    self.facing = 1
    self.animationClock = 0
    self.decision = nil
    self.waitTimer = 0
end

function Instance:update(dt, player)
    dt = math.max(0, dt or 0)
    self.animationClock = self.animationClock + dt
    if self.state == "scheduled" then
        self.timer = self.timer - dt
        if self.timer > 0 then return nil end
        self.state = "entering"
        self.visible = true
    end

    if self.state ~= "entering" and self.state ~= "exiting" then
        if self.state == "waiting" then
            self.waitTimer = self.waitTimer + dt
            self.facing = self.seatFacing or (player and (player.x < self.x and -1 or 1)) or 1
            if self.waitTimer >= self.maxWaitSeconds then
                self.decision = "timed_out"
                self.state = "exiting"
                self.waypoint = #self.route - 1
                return "timed_out"
            end
        elseif self.state == "reviewing" then
            self.facing = self.seatFacing or (player and (player.x < self.x and -1 or 1)) or 1
        end
        return nil
    end

    -- A customer politely pauses instead of walking through the player.
    if player and distanceSquared(self, player) < 28 * 28 then return nil end

    local travel = self.speed * dt
    while travel > 0 do
        local target = self.route[self.waypoint]
        if not target then
            if self.state == "entering" then
                self.state = "waiting"
                self.waypoint = #self.route
                self.waitTimer = 0
                return "arrived"
            end
            self.state = "finished"
            self.visible = false
            self.waypoint = 1
            return "exited"
        end
        local reached, remaining = moveToward(self, target, travel)
        if not reached then break end
        travel = remaining
        self.waypoint = self.state == "entering" and self.waypoint + 1 or self.waypoint - 1
    end
    return nil
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
    self.waypoint = #self.route - 1
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
            or "A: accept job    D: decline job",
    }
end

function Instance:getObstacle()
    if not self.visible then return nil end
    return { x = self.x, y = self.y, radius = 16 }
end

function Instance:isMoving()
    return self.state == "entering" or self.state == "exiting"
end

function Instance:snapshot()
    return {
        state = self.state,
        visible = self.visible,
        x = self.x,
        y = self.y,
        waypoint = self.waypoint,
        seatIndex = self.seatIndex,
        decision = self.decision,
        waitTimer = self.waitTimer,
    }
end

function Instance:draw(characterAssets)
    if not self.visible then return end
    local action = (self.state == "waiting" or self.state == "reviewing")
        and "sit" or (self:isMoving() and "walk" or "idle")
    local rate = action == "walk" and self.walkAnimationRate or 2
    local image, quad, frameCount = characterAssets.get(self.character, action, 1)
    frameCount = frameCount or 1
    local cycleLength = action == "walk" and math.max(1, frameCount * 2 - 2) or frameCount
    local frame = math.floor(self.animationClock * rate) % cycleLength + 1
    if action == "walk" and frameCount > 1 then
        frame = frame <= frameCount and frame or frameCount * 2 - frame
    end
    image, quad, frameCount = characterAssets.get(self.character, action, frame)
    local anchorX, anchorY = characterAssets.getAnchor(self.character, action, frame)

    if image and quad then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(
            image,
            quad,
            self.x,
            self.y,
            0,
            self.drawScale * self.facing,
            self.drawScale,
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
