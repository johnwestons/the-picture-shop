local Animation = {}

function Animation.isWalkAction(action)
    return type(action) == "string" and (action == "walk" or action:match("^walk_") ~= nil
        or action == "push" or action:match("^push_") ~= nil)
end

function Animation.frameForClock(frameCount, clock, rate)
    frameCount = math.max(1, tonumber(frameCount) or 1)
    if frameCount <= 1 then return 1 end
    rate = math.max(0, tonumber(rate) or 0)
    return math.floor(math.max(0, tonumber(clock) or 0) * rate) % frameCount + 1
end

function Animation.frameForDistance(frameCount, distance, pixelsPerFrame)
    frameCount = math.max(1, tonumber(frameCount) or 1)
    if frameCount <= 1 then return 1 end
    pixelsPerFrame = math.max(1, tonumber(pixelsPerFrame) or 12)
    return math.floor(math.max(0, tonumber(distance) or 0) / pixelsPerFrame) % frameCount + 1
end

function Animation.frameForIdle(frameCount, clock, rate)
    frameCount = math.max(1, tonumber(frameCount) or 1)
    rate = math.max(0, tonumber(rate) or 0)
    if frameCount == 2 and rate > 0 then
        -- A two-cell neutral/blink pair should blink briefly, not hold closed
        -- eyes for half of the idle cycle. Rear-view settle frames use the same
        -- gentle cadence and stay on the same planted anchor.
        local period = frameCount / rate
        local phase = math.max(0, tonumber(clock) or 0) % period
        return phase >= period - math.min(.14, period * .1) and 2 or 1
    end
    return Animation.frameForClock(frameCount, clock, rate)
end

local function directionalAction(prefix, x, y)
    x, y = tonumber(x) or 0, tonumber(y) or 0
    local absX, absY = math.abs(x), math.abs(y)
    local diagonalThreshold = 0.41421356237 -- tan(22.5 degrees)
    if absX < 0.0001 and absY < 0.0001 then return prefix, 1 end
    if absX <= absY * diagonalThreshold then
        return y < 0 and prefix .. "_north" or prefix .. "_south", 1
    end
    if absY <= absX * diagonalThreshold then
        return prefix, x < 0 and -1 or 1
    end
    return y < 0 and prefix .. "_northeast" or prefix .. "_southeast",
        x < 0 and -1 or 1
end

function Animation.directionalWalkAction(x, y)
    return directionalAction("walk", x, y)
end

function Animation.directionalPalletJackPushAction(x, y)
    return directionalAction("push", x, y)
end

function Animation.directionalIdleAction(x, y)
    return directionalAction("idle", x, y)
end

function Animation.authoredDirection(x,y)
    local index=math.floor((math.atan2(y or 0,x or 1)+math.pi/8)/(math.pi/4))%8+1
    return ({"east","southeast","south","southwest","west","northwest","north","northeast"})[index]
end

function Animation.authoredAction(prefix,x,y)
    local direction=Animation.authoredDirection(x,y)
    return direction=="east" and prefix or prefix.."_"..direction
end

function Animation.frameForPlayerAction(action, frameCount, distance, idleClock,
    pixelsPerFrame, idleRate)
    if Animation.isWalkAction(action) then
        return Animation.frameForDistance(frameCount, distance, pixelsPerFrame)
    end
    return Animation.frameForClock(frameCount, idleClock, idleRate)
end

function Animation.frameForAction(action, frameCount, clock, walkRate, useRate)
    frameCount = math.max(1, tonumber(frameCount) or 1)
    local rate = Animation.isWalkAction(action) and (tonumber(walkRate) or 4)
        or (action == "use" and (tonumber(useRate) or 2.5) or nil)
    if not rate or frameCount <= 1 then return 1 end

    local cycleLength = math.max(1, frameCount * 2 - 2)
    local frame = math.floor(math.max(0, tonumber(clock) or 0) * rate) % cycleLength + 1
    if frameCount > 1 and frame > frameCount then frame = frameCount * 2 - frame end
    return frame
end

return Animation
