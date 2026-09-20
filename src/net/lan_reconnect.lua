-- Bounded client reconnect scheduling. Each attempt is a fresh Session join;
-- this object retains only the public address and display name needed to retry.
local Reconnect = {}
Reconnect.__index = Reconnect

Reconnect.DEFAULT_DELAYS = { 0, 1, 2, 4, 8, 8 }

local function targetCopy(target)
    if type(target) ~= "table" then return nil end
    return {
        address = target.address,
        playerName = target.playerName,
    }
end

local function validTarget(address, playerName)
    return type(address) == "string" and #address >= 1 and #address <= 96
        and type(playerName) == "string" and #playerName >= 1 and #playerName <= 32
end

function Reconnect.new(options)
    options = options or {}
    local delays = {}
    for _, delay in ipairs(options.delays or Reconnect.DEFAULT_DELAYS) do
        delay = tonumber(delay)
        if delay and delay >= 0 and delay <= 60 then delays[#delays + 1] = delay end
    end
    if #delays == 0 then delays = { 0 } end
    return setmetatable({
        delays = delays,
        target = nil,
        active = false,
        state = "idle",
        attempt = 0,
        remaining = 0,
        reason = nil,
        lastError = nil,
    }, Reconnect)
end

function Reconnect:remember(address, playerName)
    address = tostring(address or "")
    playerName = tostring(playerName or "LAN Worker")
    if not validTarget(address, playerName) then return false end
    self.target = { address = address, playerName = playerName }
    return true
end

function Reconnect:begin(reason)
    if not self.target then return false, "No previous LAN host is available to reconnect."
    end
    self.active = true
    self.state = "waiting"
    self.attempt = 0
    self.remaining = self.delays[1]
    self.reason = tostring(reason or "The host connection ended."):sub(1, 160)
    self.lastError = nil
    return true
end

function Reconnect:update(dt)
    if not self.active or self.state ~= "waiting" then return nil end
    dt = tonumber(dt) or 0
    if dt > 0 then self.remaining = math.max(0, self.remaining - math.min(dt, 60)) end
    if self.remaining > 0 then return nil end
    self.attempt = self.attempt + 1
    self.state = "connecting"
    return {
        address = self.target.address,
        playerName = self.target.playerName,
        attempt = self.attempt,
        maxAttempts = #self.delays,
    }
end

function Reconnect:failed(message)
    if not self.active or self.state ~= "connecting" then return false end
    self.lastError = tostring(message or "The host did not answer."):sub(1, 160)
    if self.attempt >= #self.delays then
        self.active = false
        self.state = "exhausted"
        self.remaining = 0
        return false, "Automatic reconnect ended. Enter an address or choose a discovered shop."
    end
    self.state = "waiting"
    self.remaining = self.delays[self.attempt + 1]
    return true
end

function Reconnect:succeeded()
    if not self.target then return false end
    self.active = false
    self.state = "idle"
    self.attempt = 0
    self.remaining = 0
    self.reason = nil
    self.lastError = nil
    return true
end

function Reconnect:cancel(forget)
    self.active = false
    self.state = "idle"
    self.attempt = 0
    self.remaining = 0
    self.reason = nil
    self.lastError = nil
    if forget == true then self.target = nil end
    return true
end

function Reconnect:isActive()
    return self.active
end

function Reconnect:snapshot()
    return {
        active = self.active,
        state = self.state,
        attempt = self.attempt,
        maxAttempts = #self.delays,
        nextIn = math.max(0, math.ceil(self.remaining)),
        reason = self.reason,
        lastError = self.lastError,
        target = targetCopy(self.target),
    }
end

return Reconnect
