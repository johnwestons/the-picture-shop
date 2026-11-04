-- Continuous, visual-only motion for the cutter's separate moving components.
local Motion = {}

local TURN_TIME = 0.46
-- Cutting stick in the operator artwork, mapped from the 768 x 512 sprite.
Motion.cutLineY = 78 + 217 * 347 / 512

local function fraction(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function smooth(value)
    value = fraction(value)
    return value * value * (3 - 2 * value)
end

function Motion.frame(progress)
    return math.floor(fraction(progress) * 4 + 0.5) + 1
end

-- Retained for callers that inspect the original atlas registrations.
function Motion.sample(name, progress)
    local phase = fraction(progress)
    if name == "cutterBlade" then
        return 1, 88 * 2 * math.min(phase, 1 - phase)
    elseif name == "cutterClamp" then
        return 1, 58 * phase
    end
    return Motion.frame(phase), 0
end

function Motion.bladeDepthPose(depth)
    local amount = smooth(depth)
    return {
        x = 4 * amount,
        y = 30 * amount,
        angle = 0,
        depth = amount,
    }
end

function Motion.clampPose(progress)
    local amount = smooth(progress)
    return {
        x = 0,
        y = 19 * amount,
        angle = 0,
        depth = amount,
    }
end

local function normalizedAngle(value)
    return (tonumber(value) or 0) % 360
end

local function turnDelta(from, to)
    return (to - from + 180) % 360 - 180
end

function Motion.newPaperTurn()
    return {
        paperKey = nil,
        target = 0,
        from = 0,
        delta = 0,
        orientation = 0,
        elapsed = TURN_TIME,
        duration = TURN_TIME,
        progress = 1,
    }
end

function Motion.observePaperTurn(turn, paper)
    if not turn then return end
    if type(paper) ~= "table" then
        if turn.paperKey ~= nil then
            turn.paperKey, turn.from, turn.target = nil, turn.orientation, 0
            turn.delta, turn.elapsed = turnDelta(turn.orientation, 0), 0
        end
        return
    end

    local key = paper.palletId or paper.id or paper.artworkId or "loaded-paper"
    local target = normalizedAngle(paper.orientation)
    if turn.paperKey ~= key or turn.activeLift ~= paper.activeLift then
        turn.activeLift = paper.activeLift
        turn.paperKey, turn.target = key, target
        turn.from, turn.orientation, turn.delta = target, target, 0
        turn.elapsed, turn.progress = turn.duration or TURN_TIME, 1
    elseif math.abs(turnDelta(turn.target, target)) > 0.01 then
        turn.from = turn.orientation
        turn.target = target
        turn.delta = turnDelta(turn.from, target)
        turn.elapsed, turn.progress = 0, 0
    end
end

function Motion.updatePaperTurn(turn, dt)
    if not turn then return 0, 1 end
    turn.duration = turn.duration or TURN_TIME
    turn.elapsed = math.min(turn.duration, (turn.elapsed or turn.duration)
        + math.max(0, tonumber(dt) or 0))
    local t = turn.duration > 0 and turn.elapsed / turn.duration or 1
    turn.progress = smooth(t)
    turn.orientation = normalizedAngle(turn.from + turn.delta * turn.progress)
    return turn.orientation, turn.progress
end

return Motion
