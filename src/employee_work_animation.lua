-- Presentation-only timing for employee work-action clips.
-- Call update from the simulation/update path; sample is safe for drawing.
local WorkAnimation = {}
local EPSILON = 1e-9

local function positiveInteger(value, fallback)
    if type(value) ~= "number" or value ~= math.floor(value) or value < 1 then
        return fallback
    end
    return value
end

local function boundedFrame(value, count, fallback)
    value = positiveInteger(value, fallback)
    return math.max(1, math.min(count, value))
end

local function frameList(values, fallback, count)
    local source = type(values) == "table" and #values > 0 and values or fallback
    local result, previous = {}, nil
    for _, value in ipairs(source) do
        local frame = boundedFrame(value, count, 1)
        if frame ~= previous then
            result[#result + 1] = frame
            previous = frame
        end
    end
    if #result == 0 then result[1] = 1 end
    return result
end

local function clipFor(clip)
    clip = type(clip) == "table" and clip or {}
    local count = positiveInteger(clip.frameCount, 8)
    local legacy = count < 8
    local fallbackApproach = legacy and { 2, 3 } or { 2, 3, 4 }
    local fallbackRecovery = legacy and { 3, 2 } or { 7, 8 }
    return {
        action = clip.action,
        frameCount = count,
        readyFrame = boundedFrame(clip.readyFrame, count, 1),
        approachFrames = frameList(clip.approachFrames, fallbackApproach, count),
        contactFrame = boundedFrame(clip.contactFrame, count, legacy and 3 or 5),
        operationFrame = boundedFrame(clip.operationFrame, count, legacy and count or 6),
        operationEntryFrame = clip.operationEntryFrame ~= nil
            and math.min(count, positiveInteger(clip.operationEntryFrame, 1)) or nil,
        operationEntryDuration = type(clip.operationEntryDuration) == "number"
            and clip.operationEntryDuration >= 0 and clip.operationEntryDuration or 0.10,
        recoveryFrames = frameList(clip.recoveryFrames, fallbackRecovery, count),
        secondsPerFrame = type(clip.secondsPerFrame) == "number"
            and clip.secondsPerFrame > 0 and clip.secondsPerFrame or 0.16,
    }
end

function WorkAnimation.newRecord()
    return {
        action = nil,
        taskKey = nil,
        phase = "ready",
        frame = 1,
        sequenceIndex = 0,
        elapsed = 0,
        recoveryTarget = nil,
        pending = nil,
        clip = nil,
        operationEntryPending = false,
        operationEntryElapsed = 0,
    }
end

function WorkAnimation.reset(record, readyFrame)
    record = type(record) == "table" and record or WorkAnimation.newRecord()
    record.action = nil
    record.taskKey = nil
    record.phase = "ready"
    record.frame = positiveInteger(readyFrame, 1)
    record.sequenceIndex = 0
    record.elapsed = 0
    record.recoveryTarget = nil
    record.pending = nil
    record.clip = nil
    record.operationEntryPending = false
    record.operationEntryElapsed = 0
    return record
end

WorkAnimation.cancel = WorkAnimation.reset

local function enterHeld(record, phase, frame)
    record.phase = phase
    record.frame = frame
    record.sequenceIndex = 0
    record.elapsed = 0
    record.recoveryTarget = nil
    record.operationEntryPending = false
    record.operationEntryElapsed = 0
end

local function enterSequence(record, phase, frames, target)
    record.phase = phase
    record.sequenceIndex = 1
    record.elapsed = 0
    record.frame = frames[1]
    record.recoveryTarget = target
    record.operationEntryPending = false
    record.operationEntryElapsed = 0
end

local function enterOperation(record, clip, showEntry)
    record.phase = "operate"
    record.sequenceIndex = 0
    record.elapsed = 0
    record.recoveryTarget = nil
    record.pending = nil
    record.operationEntryElapsed = 0
    record.operationEntryPending = showEntry and clip.operationEntryFrame ~= nil
        and clip.operationEntryDuration > EPSILON
    record.frame = record.operationEntryPending and clip.operationEntryFrame or clip.operationFrame
end

local function advanceOperationEntry(record, clip, dt)
    if not record.operationEntryPending or clip.operationEntryFrame == nil
        or clip.operationEntryDuration <= EPSILON then
        record.operationEntryPending = false
        record.operationEntryElapsed = 0
        record.frame = clip.operationFrame
        return
    end
    record.frame = clip.operationEntryFrame
    record.operationEntryElapsed = record.operationEntryElapsed + dt
    if record.operationEntryElapsed + EPSILON >= clip.operationEntryDuration then
        record.operationEntryPending = false
        record.operationEntryElapsed = 0
        record.frame = clip.operationFrame
    end
end

local function startApproach(record, key, action, clip)
    record.taskKey = key
    record.action = action
    record.clip = clip
    record.pending = nil
    enterSequence(record, "approach", clip.approachFrames)
end

local function startRecovery(record, target, clip)
    if record.phase == "recovery" then
        record.recoveryTarget = target
        return
    end
    enterSequence(record, "recovery", clip.recoveryFrames, target)
end

local function clearTask(record, clip)
    record.action = nil
    record.taskKey = nil
    record.pending = nil
    record.phase = "ready"
    record.frame = clip.readyFrame
    record.sequenceIndex = 0
    record.elapsed = 0
    record.recoveryTarget = nil
    record.clip = nil
    record.operationEntryPending = false
    record.operationEntryElapsed = 0
end

local function completeSequence(record, mode, key, action)
    local clip = record.clip or clipFor(nil)
    local completed = record.phase
    local target = record.recoveryTarget
    record.sequenceIndex = 0
    record.elapsed = 0
    record.recoveryTarget = nil

    if completed == "approach" then
        if mode == "operate" then
            enterHeld(record, "operate", clip.operationFrame)
        else
            enterHeld(record, "contact", clip.contactFrame)
        end
        return
    end

    if completed == "recovery" then
        if target == "contact" and key == record.taskKey then
            -- A completed operation must return through approach before contact.
            enterSequence(record, "approach", clip.approachFrames)
            return
        end
        local pending = record.pending
        clearTask(record, clip)
        if pending and (mode == "start" or mode == "contact") then
            startApproach(record, key or pending.taskKey, action or pending.action, pending.clip or clip)
        end
    end
end

local function advanceSequence(record, mode, key, action, dt)
    local remaining = dt
    local transitions = 0
    while (record.phase == "approach" or record.phase == "recovery") and transitions < 64 do
        local clip = record.clip or clipFor(nil)
        local frames = record.phase == "approach" and clip.approachFrames or clip.recoveryFrames
        local timeLeft = math.max(0, clip.secondsPerFrame - record.elapsed)
        if remaining + EPSILON < timeLeft then
            record.elapsed = record.elapsed + remaining
            return
        end

        remaining = math.max(0, remaining - timeLeft)
        if record.sequenceIndex < #frames then
            record.sequenceIndex = record.sequenceIndex + 1
            record.frame = frames[record.sequenceIndex]
            record.elapsed = 0
        else
            completeSequence(record, mode, key, action)
            if remaining <= EPSILON then return end
        end
        transitions = transitions + 1
    end
end

local function validMode(mode)
    return mode == "start" or mode == "contact" or mode == "operate"
        or mode == "release" or mode == "ready"
end

-- input.mode is resolved from authoritative work/machine state by the caller:
-- start = a new task/approach, contact = at the controls but not operating,
-- operate = the machine is actively running, release = task ended/interrupted.
-- safeToRecover gates release until the real machine permits the worker to leave.
-- Clips may give operationEntryFrame for a one-shot pose before operationFrame;
-- its duration defaults to .10 seconds, and input.operationStarted can force it.
-- Set reset=true (or call reset/cancel) to discard presentation state immediately.
function WorkAnimation.update(record, input, dt, clip)
    record = type(record) == "table" and record or WorkAnimation.newRecord()
    input = type(input) == "table" and input or {}
    if input.reset == true then return WorkAnimation.reset(record) end
    local requestedClip = type(clip) == "table" and clipFor(clip) or nil
    dt = type(dt) == "number" and math.max(0, dt) or 0

    local mode = validMode(input.mode) and input.mode or "ready"
    local key = input.taskKey
    local action = input.action or (requestedClip and requestedClip.action) or record.action
    if mode == "operate" and key == nil then key = record.taskKey end
    if key == nil and action ~= nil then key = action end
    local sameTask = record.taskKey ~= nil and record.taskKey == key and record.action == action
    local safe = input.safeToRecover ~= false
    local currentClip = record.clip or clipFor(nil)
    local newTaskClip = requestedClip or clipFor(nil)

    -- Active machine state is authoritative. It immediately replaces a stale
    -- task/action and never lets an in-flight approach delay the operation pose.
    if mode == "operate" then
        if action == nil then action = record.action end
        if key ~= nil and action ~= nil then
            local activeClip = sameTask and (requestedClip or currentClip) or newTaskClip
            if sameTask and record.phase == "operate" then
                record.clip = activeClip
                advanceOperationEntry(record, activeClip, dt)
            else
                local operationStarted = input.operationStarted == true
                local showEntry = operationStarted or sameTask
                    and (record.phase == "approach" or record.phase == "contact")
                record.taskKey = key
                record.action = action
                record.clip = activeClip
                enterOperation(record, activeClip, showEntry)
                -- The update that observes the transition exposes the entry
                -- pose for a full sample; later active updates consume time.
            end
        elseif record.taskKey ~= nil then
            enterOperation(record, currentClip, input.operationStarted == true and record.phase ~= "operate")
        end
        return record
    end

    if mode == "release" or mode == "ready" then
        if requestedClip and requestedClip.action == record.action then
            record.clip = requestedClip
            currentClip = requestedClip
        end
        if not safe then
            if record.taskKey ~= nil then
                if record.phase == "operate" then
                    enterHeld(record, "operate", currentClip.operationFrame)
                else
                    enterHeld(record, "contact", currentClip.contactFrame)
                end
            end
            return record
        end
        record.pending = nil
        if record.taskKey ~= nil and record.phase ~= "ready" then
            startRecovery(record, "ready", currentClip)
        elseif record.phase == "ready" then
            record.frame = currentClip.readyFrame
        end
        advanceSequence(record, mode, key, action, dt)
        return record
    end

    if record.taskKey ~= nil and not sameTask then
        record.pending = key ~= nil and action ~= nil and {
            taskKey = key, action = action, clip = newTaskClip,
        } or nil
        if not safe then
            if record.phase ~= "operate" then
                enterHeld(record, "contact", currentClip.contactFrame)
            else
                record.frame = currentClip.operationFrame
            end
            return record
        end
        startRecovery(record, "ready", currentClip)
    elseif record.taskKey == nil then
        if key ~= nil and action ~= nil then
            startApproach(record, key, action, newTaskClip)
        else
            record.phase = "ready"
            record.frame = newTaskClip.readyFrame
            return record
        end
    else
        record.pending = nil
        if requestedClip then
            record.clip = requestedClip
            currentClip = requestedClip
        end
        if record.phase == "operate" then
            startRecovery(record, "contact", currentClip)
        elseif record.phase == "recovery" then
            record.recoveryTarget = "contact"
        elseif record.phase == "ready" then
            startApproach(record, key, action, currentClip)
        elseif record.phase == "contact" then
            -- Contact pose is clip-specific and may change with machine substate.
            record.frame = currentClip.contactFrame
        end
    end

    advanceSequence(record, mode, key, action, dt)
    return record
end

-- Pure read for Renderer.pose/draw paths. `frameCount` is the actual loaded
-- atlas count, so legacy or partially available clips can never index past it.
function WorkAnimation.sample(record, frameCount)
    if type(record) ~= "table" then return nil, 1 end
    local count = positiveInteger(frameCount, 1)
    local frame = boundedFrame(record.frame, count, 1)
    return record.action, frame
end

return WorkAnimation
