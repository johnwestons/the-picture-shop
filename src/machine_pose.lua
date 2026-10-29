local MachinePose = {}
local Transport = require("src.machine_transport")

local ORDER = { "cutter", "wrapper", "windmill" }
local DIRECTIONS = {
    cutter = {
        northwest = true, north = true, northeast = true, east = true,
        southeast = true, south = true, southwest = true, west = true,
    },
    wrapper = {
        northwest = true, northeast = true, southeast = true, southwest = true,
    },
    windmill = {
        northwest = true, northeast = true, southeast = true, southwest = true,
    },
}

local function finite(value, limit)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
        and math.abs(value) <= limit
end

local function exactShape(value, required, optional)
    if type(value) ~= "table" then return false end
    local allowed = {}
    for _, key in ipairs(required) do allowed[key] = true end
    for _, key in ipairs(optional or {}) do allowed[key] = true end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    for _, key in ipairs(required) do
        if value[key] == nil then return false end
    end
    return true
end

local function sameCoordinate(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= 0.000001
end

function MachinePose.normalize(value, jack, maxCoordinate, label)
    label = tostring(label or "machine poses")
    maxCoordinate = tonumber(maxCoordinate) or 100000
    if not exactShape(value, ORDER) then
        return nil, label .. " must contain exactly cutter, wrapper, and windmill"
    end

    local normalized = {}
    local activeKind, activePose
    for _, kind in ipairs(ORDER) do
        local pose = value[kind]
        local poseLabel = label .. "." .. kind
        if not exactShape(pose, { "x", "y", "direction", "moving", "inMotion" }, { "machineId", "sceneId" }) then
            return nil, poseLabel .. " has an invalid shape"
        end
        if not finite(pose.x, maxCoordinate) or not finite(pose.y, maxCoordinate) then
            return nil, poseLabel .. " coordinates are out of range"
        end
        if pose.machineId ~= nil and (type(pose.machineId) ~= "string" or #pose.machineId > 64
            or not pose.machineId:match("^MCH%-%d+$")) then
            return nil, poseLabel .. ".machineId is invalid"
        end
        if pose.sceneId~=nil and pose.sceneId~="warehouse" and pose.sceneId~="front_left"
            and pose.sceneId~="front_right" then return nil,poseLabel..".sceneId is invalid" end
        if type(pose.direction) ~= "string" or not DIRECTIONS[kind][pose.direction] then
            return nil, poseLabel .. ".direction is invalid"
        end
        if type(pose.moving) ~= "boolean" or type(pose.inMotion) ~= "boolean" then
            return nil, poseLabel .. " motion flags must be boolean"
        end
        if pose.inMotion and not pose.moving then
            return nil, poseLabel .. ".inMotion requires an active relocation"
        end
        if pose.moving then
            if activeKind then return nil, label .. " has more than one active relocation" end
            activeKind, activePose = kind, pose
        end
        normalized[kind] = {
            machineId = pose.machineId,
            x = pose.x,
            y = pose.y,
            direction = pose.direction,
            moving = pose.moving,
            inMotion = pose.inMotion,
            sceneId=pose.sceneId or "warehouse",
        }
    end

    if activeKind and jack ~= nil then
        if type(jack) ~= "table" or jack.operating ~= true
            or type(jack.operatorPlayerId) ~= "number"
            or jack.operatorPlayerId % 1 ~= 0
            or jack.operatorPlayerId < 1 or jack.operatorPlayerId > 4
            or jack.carriedPalletId ~= nil
            or jack.candidatePalletId ~= nil
        then
            return nil, label .. " active relocation requires a worker-owned empty pallet jack"
        end
        if jack.direction ~= activePose.direction or jack.moving ~= activePose.inMotion
            or not sameCoordinate(jack.x, activePose.x)
            or not sameCoordinate(jack.y, activePose.y + 8)
        then
            return nil, label .. " active relocation must remain attached to the pallet jack"
        end
    end

    return normalized
end

function MachinePose.snapshot(state)
    if type(state) ~= "table" then return nil end
    local poses = {}
    for _, kind in ipairs(ORDER) do
        local item = state[kind]
        local machineId = state._machinePoseUnits and state._machinePoseUnits[kind]
        if machineId then
            local unit, pose = Transport.resolve(state, kind, machineId)
            if unit and unit.world then item = pose else machineId = nil end
        end
        if not machineId then
            local unit=Transport.resolve(state,kind)
            if unit and unit.world then item,machineId=unit.world,unit.id end
        end
        local activeKind, activePose, activeUnit = Transport.active(state)
        if activeKind == kind then item, machineId = activePose, activeUnit and activeUnit.id or nil end
        if type(item) ~= "table" then return nil end
        poses[kind] = {
            machineId = machineId,
            x = item.x,
            y = item.y,
            direction = item.direction,
            moving = item.moving == true,
            inMotion = item.inMotion == true,
            sceneId=item.sceneId or "warehouse",
        }
    end
    return MachinePose.normalize(poses)
end

function MachinePose.copy(value)
    return MachinePose.normalize(value)
end

function MachinePose.activeKind(value)
    if type(value) ~= "table" then return nil end
    for _, kind in ipairs(ORDER) do
        if type(value[kind]) == "table" and value[kind].moving == true then return kind end
    end
    return nil
end

local function targetsFor(state, normalized)
    local targets = {}
    for _, kind in ipairs(ORDER) do
        local source = normalized[kind]
        if source.machineId then
            local unit, pose = Transport.resolve(state, kind, source.machineId)
            if not unit or (not unit.world and type(state[kind])~="table") then
                return nil, "machine pose references an unavailable unit"
            end
            targets[kind] = { unit=unit, pose=pose }
        end
    end
    return targets
end

function MachinePose.canApply(state, value)
    if type(state) ~= "table" then return false, "machine pose state is invalid" end
    local normalized, reason = MachinePose.normalize(value)
    if not normalized then return false, reason end
    local targets, targetError = targetsFor(state, normalized)
    return targets ~= nil, targetError
end

function MachinePose.apply(state, value)
    if type(state) ~= "table" then return false, "machine pose state is invalid" end
    local normalized, normalizeError = MachinePose.normalize(value)
    if not normalized then return false, normalizeError end
    local targets, targetError = targetsFor(state, normalized)
    if not targets then return false, targetError end
    for _, kind in ipairs(ORDER) do
        if type(state[kind]) ~= "table" then state[kind] = {} end
        state[kind].moving, state[kind].inMotion = false, false
    end
    for _, unit in ipairs(state.machines and state.machines.items or {}) do
        if unit.world then unit.world.moving, unit.world.inMotion = false, false end
    end
    state._machinePoseUnits = {}
    for _, kind in ipairs(ORDER) do
        local target, source = state[kind], normalized[kind]
        local resolved=targets[kind]
        if resolved then
            if not resolved.unit.world then
                resolved.unit.world={}
                for key,value in pairs(resolved.pose or state[kind]) do
                    resolved.unit.world[key]=value
                end
            end
            target=resolved.unit.world
        end
        target.x, target.y = source.x, source.y
        target.direction = source.direction
        target.sceneId=source.sceneId or "warehouse"
        target.moving, target.inMotion = source.moving, source.inMotion
        state._machinePoseUnits[kind] = source.machineId
    end
    return true
end

return MachinePose
