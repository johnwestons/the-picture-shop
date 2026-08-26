local Animation = {}

function Animation.frameForAction(action, frameCount, clock, walkRate, useRate)
    frameCount = math.max(1, tonumber(frameCount) or 1)
    local rate = action == "walk" and (tonumber(walkRate) or 4)
        or (action == "use" and (tonumber(useRate) or 2.5) or nil)
    if not rate or frameCount <= 1 then return 1 end

    local cycleLength = math.max(1, frameCount * 2 - 2)
    local frame = math.floor(math.max(0, tonumber(clock) or 0) * rate) % cycleLength + 1
    if frameCount > 1 and frame > frameCount then frame = frameCount * 2 - frame end
    return frame
end

return Animation
