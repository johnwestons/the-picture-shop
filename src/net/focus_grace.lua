local FocusGrace = {}
FocusGrace.__index = FocusGrace

function FocusGrace.new(options)
    options = options or {}
    local clock = options.clock or os.time
    assert(type(clock) == "function", "Focus grace clock must be a function.")
    local wallClock = options.wallClock
    assert(wallClock == nil or type(wallClock) == "function",
        "Focus grace wall clock must be a function.")
    local timeoutSeconds = tonumber(options.timeoutSeconds) or 120
    assert(timeoutSeconds > 0, "Focus grace timeout must be greater than zero.")
    return setmetatable({
        clock = clock,
        wallClock = wallClock,
        timeoutSeconds = timeoutSeconds,
        lostAt = nil,
        lostAtWall = nil,
    }, FocusGrace)
end

function FocusGrace:start()
    if self.lostAt ~= nil then return false end
    self.lostAt = self.clock()
    self.lostAtWall = self.wallClock and self.wallClock() or nil
    return true
end

function FocusGrace:clear()
    local wasTracking = self.lostAt ~= nil
    self.lostAt = nil
    self.lostAtWall = nil
    return wasTracking
end

function FocusGrace:isTracking()
    return self.lostAt ~= nil
end

function FocusGrace:elapsed()
    if self.lostAt == nil then return nil end
    local elapsed = math.max(0, self.clock() - self.lostAt)
    -- Android's monotonic timer excludes deep sleep. Wall time catches a
    -- suspended phone, while a clock correction backwards cannot extend the
    -- grace already measured by the monotonic timer.
    if self.lostAtWall ~= nil then
        elapsed = math.max(elapsed, self.wallClock() - self.lostAtWall)
    end
    return elapsed
end

function FocusGrace:isExpired()
    local elapsed = self:elapsed()
    return elapsed ~= nil and elapsed > self.timeoutSeconds
end

return FocusGrace
