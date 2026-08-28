local GaitMotion = {}

local function smoothstep(value)
    return value * value * (3 - 2 * value)
end

local function sampleCurve(values, animationDistance, pixelsPerFrame)
    if type(values) ~= "table" or #values == 0 then return 1 end

    local phase = math.max(0, tonumber(animationDistance) or 0)
        / math.max(1, tonumber(pixelsPerFrame) or 20)
    local pose = math.floor(phase)
    local blend = smoothstep(phase - pose)
    local current = tonumber(values[pose % #values + 1]) or 1
    local following = tonumber(values[(pose + 1) % #values + 1]) or current
    return current + (following - current) * blend
end

function GaitMotion.sample(animationDistance, definition)
    definition = definition or {}
    local pixelsPerFrame = definition.walkPixelsPerFrame or 20
    return sampleCurve(definition.gaitSpeedMultipliers, animationDistance, pixelsPerFrame),
        sampleCurve(definition.gaitAccelerationMultipliers, animationDistance, pixelsPerFrame)
end

return GaitMotion
