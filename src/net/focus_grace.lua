local FocusGrace = {}
FocusGrace.__index = FocusGrace

function FocusGrace.new(options)
    options = options or {}
    local clock = options.clock or os.time
    assert(type(clock) == "function", "Focus grace clock must be a function.")
    local timeoutSeconds = tonumber(options.timeoutSeconds) or 120
    assert(timeoutSeconds > 0, "Focus grace timeout must be greater than zero.")
    return setmetatable({
        clock = clock,
        timeoutSeconds = timeoutSeconds,
        lostAt = nil,
    }, FocusGrace)
end

function FocusGrace:start()
    if self.lostAt ~= nil then return false end
    self.lostAt = self.clock()
    return true
end

function FocusGrace:clear()
    local wasTracking = self.lostAt ~= nil
    self.lostAt = nil
    return wasTracking
end

function FocusGrace:isTracking()
    return self.lostAt ~= nil
end

function FocusGrace:elapsed()
    if self.lostAt == nil then return nil end
    return math.max(0, self.clock() - self.lostAt)
end

function FocusGrace:isExpired()
    local elapsed = self:elapsed()
    return elapsed ~= nil and elapsed > self.timeoutSeconds
end

return FocusGrace
