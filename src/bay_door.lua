local BayDoor = {}
local Instance = {}
Instance.__index = Instance

function BayDoor.new(config)
    assert(type(config) == "table", "loading-bay configuration is required")
    local instance = setmetatable({
        duration = config.duration or 0.9,
        frameCount = config.frameCount or 5,
        interaction = config.interaction,
    }, Instance)
    instance:reset()
    return instance
end

function Instance:reset()
    self.state = "closed"
    self.progress = 0
end

function Instance:open()
    if self.state ~= "closed" then return false end
    self.state = "opening"
    return true
end

function Instance:close()
    if self.state ~= "open" then return false end
    self.state = "closing"
    return true
end

function Instance:toggle()
    if self.state == "closed" then return self:open() end
    if self.state == "open" then return self:close() end
    return false
end

function Instance:update(dt)
    if self.state ~= "opening" and self.state ~= "closing" then return nil end
    local direction = self.state == "opening" and 1 or -1
    self.progress = math.min(1, math.max(0, self.progress + direction * math.max(0, dt) / self.duration))
    if self.progress >= 1 then
        self.state = "open"
        return "opened"
    elseif self.progress <= 0 then
        self.state = "closed"
        return "closed"
    end
    return nil
end

function Instance:frame()
    return math.floor(self.progress * (self.frameCount - 1) + 0.5) + 1
end

function Instance:getInteraction()
    local prompt
    if self.state == "closed" then
        prompt = "E: open loading bay door"
    elseif self.state == "open" then
        prompt = "E: close loading bay door"
    else
        prompt = "Loading bay door is " .. self.state
    end
    return {
        x = self.interaction.x,
        y = self.interaction.y,
        radius = self.interaction.radius,
        prompt = prompt,
        doorState = self.state,
    }
end

function Instance:getObstacle()
    -- The door is a vertical animated overlay. Floor access is governed by
    -- the aligned warehouse walkmask, so the sprite must never add a circular
    -- movement blocker in front of the loading bay.
    return nil
end

function Instance:snapshot()
    return { state = self.state, progress = self.progress, frame = self:frame() }
end

function Instance:applySnapshot(snapshot)
    local states = { closed = true, opening = true, open = true, closing = true }
    if type(snapshot) ~= "table" or not states[snapshot.state]
        or type(snapshot.progress) ~= "number" or snapshot.progress ~= snapshot.progress
        or snapshot.progress < 0 or snapshot.progress > 1
        or (snapshot.state == "closed" and snapshot.progress ~= 0)
        or (snapshot.state == "open" and snapshot.progress ~= 1)
    then
        return false
    end
    self.state, self.progress = snapshot.state, snapshot.progress
    return true
end

BayDoor.Instance = Instance
return BayDoor
