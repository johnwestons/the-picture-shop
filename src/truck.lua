local Truck = {}
local Instance = {}
Instance.__index = Instance

local function lerp(a, b, amount)
    return a + (b - a) * amount
end

local function smoothstep(amount)
    amount = math.max(0, math.min(1, amount or 0))
    return amount * amount * (3 - 2 * amount)
end

function Truck.new(config)
    assert(type(config) == "table", "truck configuration is required")
    local instance = setmetatable({
        scheduleDelay = config.scheduleDelay or 1.5,
        backingDuration = config.backingDuration or 2.2,
        cargoDuration = config.cargoDuration or 0.75,
        cargoFrameCount = config.cargoFrameCount or 5,
        start = config.start,
        parked = config.parked,
        interaction = config.interaction,
        obstacle = config.obstacle,
    }, Instance)
    instance:reset()
    return instance
end

function Instance:reset()
    self.state = "absent"
    self.jobId = nil
    self.mode = nil
    self.timer = 0
    self.backingProgress = 0
    self.cargoProgress = 0
end

function Instance:schedule(jobId, mode)
    if self.state ~= "absent" or type(jobId) ~= "string" then return false end
    self.jobId = jobId
    self.mode = mode or "delivery"
    self.timer = self.scheduleDelay
    self.state = "scheduled"
    return true
end

function Instance:update(dt, bayDoorState)
    dt = math.max(0, dt or 0)
    if self.state == "scheduled" then
        self.timer = self.timer - dt
        if self.timer <= 0 then
            self.timer = 0
            self.state = "waiting_for_bay"
            return "request_bay_open"
        end
    elseif self.state == "waiting_for_bay" then
        if bayDoorState == "open" then
            self.state = "backing"
            self.backingProgress = 0
            return "backing_started"
        end
    elseif self.state == "backing" then
        self.backingProgress = math.min(1, self.backingProgress + dt / self.backingDuration)
        if self.backingProgress >= 1 then
            self.state = "parked_closed"
            return "parked"
        end
    elseif self.state == "cargo_opening" then
        self.cargoProgress = math.min(1, self.cargoProgress + dt / self.cargoDuration)
        if self.cargoProgress >= 1 then
            self.state = "cargo_open"
            return "cargo_opened"
        end
    elseif self.state == "cargo_closing" then
        self.cargoProgress = math.max(0, self.cargoProgress - dt / self.cargoDuration)
        if self.cargoProgress <= 0 then
            self.state = "parked_closed"
            return "cargo_closed"
        end
    elseif self.state == "departing" then
        self.backingProgress = math.max(0, self.backingProgress - dt / self.backingDuration)
        if self.backingProgress <= 0 then
            self.state = "absent"
            self.jobId = nil
            self.mode = nil
            return "departed"
        end
    end
    return nil
end

function Instance:toggleCargoDoor()
    if self.state == "parked_closed" then
        self.state = "cargo_opening"
        return true
    elseif self.state == "cargo_open" then
        self.state = "cargo_closing"
        return true
    end
    return false
end

function Instance:depart()
    if self.state ~= "parked_closed" then return false end
    self.state = "departing"
    self.backingProgress = 1
    return true
end

function Instance:cargoFrame()
    return math.floor(self.cargoProgress * (self.cargoFrameCount - 1) + 0.5) + 1
end

function Instance:isVisible()
    return self.state == "backing"
        or self.state == "parked_closed"
        or self.state == "cargo_opening"
        or self.state == "cargo_open"
        or self.state == "cargo_closing"
        or self.state == "departing"
end

function Instance:isParked()
    return self.state == "parked_closed"
        or self.state == "cargo_opening"
        or self.state == "cargo_open"
        or self.state == "cargo_closing"
end

function Instance:blocksBayClosure()
    return self.state == "waiting_for_bay" or self:isVisible()
end

function Instance:transform()
    local amount = (self.state == "backing" or self.state == "departing")
        and self.backingProgress
        or (self:isParked() and 1 or 0)
    -- Ease both ends of the maneuver so the truck pulls away from rest and
    -- settles against the dock without the visible start/stop snap produced
    -- by a constant-speed interpolation.
    amount = smoothstep(amount)
    return {
        x = lerp(self.start.x, self.parked.x, amount),
        y = lerp(self.start.y, self.parked.y, amount),
        scale = lerp(self.start.scale, self.parked.scale, amount),
    }
end

function Instance:getInteraction()
    if not self:isParked() then return nil end
    local prompt
    if self.mode == "machine_delivery" and self.state == "parked_closed" then
        prompt = "E: open flatbed delivery manifest"
    elseif self.state == "parked_closed" then
        prompt = "E: open truck cargo door"
    elseif self.state == "cargo_open" then
        prompt = "E: open truck cargo inventory"
    else
        prompt = "Truck cargo door is " .. self.state:gsub("cargo_", "")
    end
    return {
        x = self.interaction.x,
        y = self.interaction.y,
        radius = self.interaction.radius,
        prompt = prompt,
        truckState = self.state,
    }
end

function Instance:getObstacle()
    if not self:isVisible() then return nil end
    local transform = self:transform()
    return {
        x = transform.x + self.obstacle.offsetX,
        y = transform.y + self.obstacle.offsetY,
        radius = self.obstacle.radius,
    }
end

function Instance:snapshot()
    local transform = self:transform()
    return {
        state = self.state,
        jobId = self.jobId,
        mode = self.mode,
        backingProgress = self.backingProgress,
        cargoProgress = self.cargoProgress,
        cargoFrame = self:cargoFrame(),
        x = transform.x,
        y = transform.y,
        scale = transform.scale,
    }
end

function Instance:applySnapshot(snapshot)
    local states = {
        absent = true, scheduled = true, waiting_for_bay = true, backing = true,
        parked_closed = true, cargo_opening = true, cargo_open = true,
        cargo_closing = true, departing = true,
    }
    local modes = {
        delivery = true, vendor_delivery = true, machine_delivery = true, pickup = true,
    }
    if type(snapshot) ~= "table" or not states[snapshot.state]
        or type(snapshot.backingProgress) ~= "number"
        or snapshot.backingProgress ~= snapshot.backingProgress
        or snapshot.backingProgress < 0 or snapshot.backingProgress > 1
        or type(snapshot.cargoProgress) ~= "number"
        or snapshot.cargoProgress ~= snapshot.cargoProgress
        or snapshot.cargoProgress < 0 or snapshot.cargoProgress > 1
    then
        return false
    end
    if snapshot.state == "absent" then
        if snapshot.jobId ~= nil or snapshot.mode ~= nil
            or snapshot.backingProgress ~= 0 or snapshot.cargoProgress ~= 0
        then
            return false
        end
    elseif type(snapshot.jobId) ~= "string" or snapshot.jobId == ""
        or not modes[snapshot.mode]
    then
        return false
    end
    self.state = snapshot.state
    self.jobId = snapshot.jobId
    self.mode = snapshot.mode
    self.backingProgress = snapshot.backingProgress
    self.cargoProgress = snapshot.cargoProgress
    self.timer = 0
    return true
end

Truck.Instance = Instance
return Truck
