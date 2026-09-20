local Watchdog = {}
Watchdog.__index = Watchdog

local EXCHANGE_SECONDS = 30

local function finiteNumber(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function policies(leaseSeconds)
    return {
        host_initial_exchange = {
            seconds = EXCHANGE_SECONDS,
            reason = "challenge_failed",
        },
        host_waiting_renewal = {
            seconds = leaseSeconds + 30,
            reason = "renewal_failed",
        },
        host_renewed_exchange = {
            seconds = EXCHANGE_SECONDS,
            reason = "challenge_failed",
        },
        guest_connected = {
            seconds = EXCHANGE_SECONDS,
            reason = "challenge_failed",
        },
        guest_waiting_renewal = {
            seconds = leaseSeconds + 60,
            reason = "challenge_failed",
        },
        guest_renewed_exchange = {
            seconds = EXCHANGE_SECONDS,
            reason = "challenge_failed",
        },
    }
end

function Watchdog.new(leaseSeconds)
    if not finiteNumber(leaseSeconds) or leaseSeconds <= 0
        or leaseSeconds > 3600 then
        return nil
    end
    return setmetatable({
        policies = policies(leaseSeconds),
        state = nil,
        deadline = nil,
        reason = nil,
        lastNow = nil,
        failed = false,
    }, Watchdog)
end

function Watchdog:clear()
    self.state = nil
    self.deadline = nil
    self.reason = nil
    self.lastNow = nil
    self.failed = false
end

function Watchdog:transition(state, now)
    local policy = self.policies[state]
    if not policy then
        self:clear()
        return true
    end
    if self.failed then return false end
    if not finiteNumber(now) then
        if not self.state then
            self.state = state
            self.reason = policy.reason
        end
        self.failed = true
        return false
    end
    if self.lastNow and now < self.lastNow then
        self.failed = true
        return false
    end
    if self.deadline and now >= self.deadline then
        self.failed = true
        return false
    end
    if self.state == state and self.deadline then
        self.lastNow = now
        return true
    end
    self.state = state
    self.deadline = now + policy.seconds
    self.reason = policy.reason
    self.lastNow = now
    self.failed = false
    return true
end

function Watchdog:timeout(now)
    if not self.state then return nil end
    if self.failed or not finiteNumber(now)
        or (self.lastNow and now < self.lastNow) then
        self.failed = true
        return self.reason
    end
    self.lastNow = now
    if now >= self.deadline then return self.reason end
    return nil
end

return Watchdog
