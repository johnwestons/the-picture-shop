-- Short-lived presentation state for employee high-five responses.
local HighFive = {}
local DURATION = 0.95
local active = {}

function HighFive.start(employeeId, partnerX, partnerY)
    if type(employeeId) ~= "string" or employeeId == "" then return false end
    active[employeeId] = {
        elapsed = 0,
        duration = DURATION,
        partnerX = tonumber(partnerX) or 0,
        partnerY = tonumber(partnerY) or 0,
    }
    return true
end

function HighFive.update(dt)
    local step = math.max(0, tonumber(dt) or 0)
    for employeeId, animation in pairs(active) do
        animation.elapsed = animation.elapsed + step
        if animation.elapsed >= animation.duration then active[employeeId] = nil end
    end
end

function HighFive.get(employeeId)
    return active[employeeId]
end

return HighFive
