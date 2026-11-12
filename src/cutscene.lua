-- Portable authored cutscenes. The editor and runtime share this data contract.
local Cutscene = { VERSION = 1, MAX_DURATION = 300 }
local allowedActions = {
    boost = true, shift = true, brake = true, jump = true,
    tuck = true, turn = true,
}
local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end
local function identifier(value)
    return type(value) == "string" and #value >= 1 and #value <= 56
        and value:match("^[%w_%-]+$") ~= nil
end
local function list(value, maximum)
    if type(value) ~= "table" or #value > maximum then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #value then return false end
        count = count + 1
    end
    return count == #value
end
local function cueList(project, key, maximum, validate)
    local cues = project[key]
    if not list(cues, maximum) then return false, "Invalid " .. key .. " track." end
    local previous = -math.huge
    for _, cue in ipairs(cues) do
        if type(cue) ~= "table" or not finite(cue.time)
            or cue.time < 0 or cue.time > project.duration or cue.time < previous then
            return false, "Invalid timing in " .. key .. " track."
        end
        local okay, reason = validate(cue)
        if not okay then return false, reason end
        previous = cue.time
    end
    return true
end

function Cutscene.validate(project)
    if type(project) ~= "table" or project.version ~= Cutscene.VERSION
        or not identifier(project.id) or type(project.title) ~= "string"
        or #project.title < 1 or #project.title > 96
        or not finite(project.duration) or project.duration < 2
        or project.duration > Cutscene.MAX_DURATION
        or not finite(project.trimIn) or not finite(project.trimOut)
        or project.trimIn < 0 or project.trimOut > project.duration
        or project.trimOut - project.trimIn < .25 then
        return false, "Cutscene header or trim range is invalid."
    end
    if type(project.world) ~= "table" or not finite(project.world.seed)
        or project.world.seed % 1 ~= 0 or project.world.seed < 1
        or project.world.seed > 2147483646 then
        return false, "Choose a whole-number town seed."
    end
    if type(project.route) ~= "table" or not identifier(project.route.from)
        or not identifier(project.route.to) then return false, "Cutscene route is invalid." end
    if type(project.actor) ~= "table"
        or project.actor.kind ~= "motorcycle-rider" and project.actor.kind ~= "player-character"
        or project.actor.kind == "motorcycle-rider" and (project.actor.outfit ~= "geared" or project.actor.mounted ~= true)
        or project.actor.kind == "player-character" and ((project.actor.outfit ~= "normal" and project.actor.outfit ~= "geared") or project.actor.mounted ~= false) then
        return false, "Choose a geared motorcycle rider or an on-foot player character."
    end
    local okay, reason = cueList(project, "camera", 96, function(cue)
        if type(cue.label) ~= "string" or #cue.label > 48
            or not finite(cue.yaw) or math.abs(cue.yaw) > 720
            or not finite(cue.tilt) or cue.tilt < 6 or cue.tilt > 89
            or not finite(cue.zoom) or cue.zoom < .45 or cue.zoom > 4 then
            return false, "Camera cues need a label, yaw, tilt, and zoom in range."
        end
        return true
    end)
    if not okay then return false, reason end
    okay, reason = cueList(project, "actions", 192, function(cue)
        if not allowedActions[cue.action] or not finite(cue.duration)
            or cue.duration < .1 or cue.duration > 12 then
            return false, "Unknown or invalid rider action cue."
        end
        if cue.action == "jump" and (not finite(cue.height) or cue.height < .2 or cue.height > 8) then
            return false, "Jump height must be between 0.2 and 8 metres."
        end
        return true
    end)
    if not okay then return false, reason end
    okay, reason = cueList(project, "dialogue", 192, function(cue)
        if type(cue.speaker) ~= "string" or #cue.speaker > 32
            or type(cue.text) ~= "string" or #cue.text < 1 or #cue.text > 240
            or not finite(cue.duration) or cue.duration < .5 or cue.duration > 20 then
            return false, "Dialogue cues need a speaker, line, and visible duration."
        end
        return true
    end)
    if not okay then return false, reason end
    okay, reason = cueList(project, "speed", 96, function(cue)
        if not finite(cue.mph) or cue.mph < 0 or cue.mph > 120 then
            return false, "Speed cues must be between 0 and 120 mph."
        end
        return true
    end)
    if not okay then return false, reason end
    if #project.camera == 0 or #project.speed < 2 then
        return false, "Add at least one camera cue and two speed cues."
    end
    if project.take ~= nil then
        local take = project.take
        if type(take) ~= "table" or take.fps ~= 30
            or take.actorKind ~= "motorcycle-rider" and take.actorKind ~= "player-character"
            or not finite(take.duration)
            or take.duration < .05 or take.duration > project.duration
            or not list(take.frames, 12000) or #take.frames < 2 then
            return false, "The recorded actor take is invalid or too long."
        end
        if take.route ~= nil then
            local route = take.route
            if type(route) ~= "table" or not finite(route.seed) or route.seed % 1 ~= 0
                or route.seed < 1 or route.seed > 2147483646
                or not identifier(route.from) or not identifier(route.to) or route.from == route.to then
                return false, "The recorded actor take has an invalid route reference."
            end
        end
        local previous = -math.huge
        for _, frame in ipairs(take.frames) do
            local numeric = { "time", "x", "z", "h", "heading", "speed", "lean", "steering",
                "throttle", "brake", "boostPulse", "shiftTime", "pitch", "vy", "distance", "gear", "rpm", "vx", "vz" }
            if type(frame) ~= "table" or type(frame.boosting) ~= "boolean"
                or type(frame.grounded) ~= "boolean" or type(frame.reverse) ~= "boolean" then return false, "Recorded actor frame is malformed." end
            for _, key in ipairs(numeric) do if not finite(frame[key]) then return false, "Recorded actor frame has an invalid value." end end
            if frame.time <= previous or frame.time < 0 or frame.time > take.duration + .05
                or frame.x < -1000 or frame.x > 1000 or frame.z < -1000 or frame.z > 1000
                or frame.h < -10 or frame.h > 100 or frame.speed < 0 or frame.speed > 50
                or math.abs(frame.lean) > 1 or math.abs(frame.steering) > 1
                or frame.throttle < 0 or frame.throttle > 1 or frame.brake < 0 or frame.brake > 1
                or frame.boostPulse < 0 or frame.boostPulse > 2 or frame.shiftTime < 0 or frame.shiftTime > 2
                or frame.pitch < -2 or frame.pitch > 2 or math.abs(frame.vy) > 60
                or frame.distance < 0 or frame.gear < 1 or frame.gear > 8
                or frame.gear % 1 ~= 0 or frame.rpm < 0 or frame.rpm > 10000
                or math.abs(frame.vx) > 60 or math.abs(frame.vz) > 60 then
                return false, "Recorded actor frame is outside its safe range."
            end
            previous = frame.time
        end
        if take.frames[1].time > .05 or take.frames[#take.frames].time > take.duration + .05 then
            return false, "Recorded actor take does not cover its duration."
        end
    end
    return true
end

function Cutscene.cameraAt(project, time)
    local cues = project.camera
    if time <= cues[1].time then return cues[1] end
    for index = 2, #cues do
        local left, right = cues[index - 1], cues[index]
        if time <= right.time then
            local span = right.time - left.time
            local t = span <= .000001 and 1
                or math.max(0, math.min(1, (time - left.time) / span))
            t = t * t * (3 - 2 * t)
            local delta = (right.yaw - left.yaw + 180) % 360 - 180
            return { label = t < .5 and left.label or right.label,
                time = time, yaw = left.yaw + delta * t,
                tilt = left.tilt + (right.tilt - left.tilt) * t,
                zoom = left.zoom + (right.zoom - left.zoom) * t }
        end
    end
    return cues[#cues]
end

function Cutscene.speedAt(project, time)
    local cues = project.speed
    if time <= cues[1].time then return cues[1].mph end
    for index = 2, #cues do
        local right, left = cues[index], cues[index - 1]
        if time <= right.time then
            local span = math.max(.001, right.time - left.time)
            local t = math.max(0, math.min(1, (time - left.time) / span))
            return left.mph + (right.mph - left.mph) * t
        end
    end
    return cues[#cues].mph
end

function Cutscene.dialogueAt(project, time)
    for index = #project.dialogue, 1, -1 do
        local cue = project.dialogue[index]
        if time >= cue.time and time <= cue.time + cue.duration then return cue end
    end
end

function Cutscene.actionsAt(project, time)
    local active = {}
    for _, cue in ipairs(project.actions) do
        if time >= cue.time and time <= cue.time + cue.duration then active[#active + 1] = cue end
    end
    return active
end

function Cutscene.samplePath(plan, distance)
    distance = math.max(0, math.min(plan.length, distance))
    for index = 2, #plan.points do
        if distance <= plan.cumulative[index] or index == #plan.points then
            local a, b = plan.points[index - 1], plan.points[index]
            local span = plan.cumulative[index] - plan.cumulative[index - 1]
            local t = span > 0 and (distance - plan.cumulative[index - 1]) / span or 0
            return { x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t,
                h = (a.h or 0) + ((b.h or a.h or 0) - (a.h or 0)) * t }
        end
    end
    local point = plan.points[#plan.points]
    return { x = point.x, z = point.z, h = point.h or 0 }
end

function Cutscene.sampleTake(project, time)
    local take = project.take
    if not take then return nil end
    local frames = take.frames
    if time <= frames[1].time then return frames[1] end
    if time >= frames[#frames].time then return frames[#frames] end
    local low, high = 1, #frames
    while low < high do
        local middle = math.floor((low + high) * .5)
        if frames[middle].time < time then low = middle + 1 else high = middle end
    end
    local right, left = frames[low], frames[low - 1]
    local span = math.max(.000001, right.time - left.time)
    local amount = math.max(0, math.min(1, (time - left.time) / span))
    local result = { time = time }
    for _, key in ipairs({ "x", "z", "h", "speed", "lean", "steering", "throttle", "brake",
        "boostPulse", "shiftTime", "pitch", "vy", "distance", "rpm", "vx", "vz" }) do
        result[key] = left[key] + (right[key] - left[key]) * amount
    end
    local turn = math.atan2(math.sin(right.heading - left.heading), math.cos(right.heading - left.heading))
    result.heading = left.heading + turn * amount
    if amount < .5 then
        result.gear, result.boosting, result.grounded, result.reverse =
            left.gear, left.boosting, left.grounded, left.reverse
    else
        result.gear, result.boosting, result.grounded, result.reverse =
            right.gear, right.boosting, right.grounded, right.reverse
    end
    return result
end

function Cutscene.load(id)
    if not identifier(id) then return nil, "Invalid cutscene id." end
    local path = "assets/generated/cutscenes/" .. id .. ".lua"
    local chunk, reason = love.filesystem.load(path)
    if not chunk then return nil, "Cutscene is not imported: " .. tostring(reason) end
    local okay, project = pcall(chunk)
    if not okay then return nil, "Cutscene file could not be loaded: " .. tostring(project) end
    local valid, issue = Cutscene.validate(project)
    if not valid then return nil, issue end
    return project
end

return Cutscene
