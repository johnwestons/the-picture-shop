-- Vehicle simulation is independent of sprite sheets and renderer frame counts.
-- Cargo remains one existing pallet ID; authoritative custody lives in PalletState.
local Forklift = {}

local directions = { "northwest", "north", "northeast", "east",
    "southeast", "south", "southwest", "west" }
local directionFrames = {}
for index, direction in ipairs(directions) do directionFrames[direction] = index end
local vectors = {
    northwest = { -1, -1 }, north = { 0, -1 }, northeast = { 1, -1 }, east = { 1, 0 },
    southeast = { 1, 1 }, south = { 0, 1 }, southwest = { -1, 1 }, west = { -1, 0 },
}
local EPSILON, MAX_COORDINATE, MAX_DISTANCE = 0.000001, 1000000, 1000000000

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function bounded(value, low, high)
    return finite(value) and value >= low and value <= high
end

local function operatorId(value)
    return bounded(value, 1, 4) and value == math.floor(value)
end

local function palletId(value)
    return type(value) == "string" and #value > 0 and #value <= 128
        and not value:find("%c")
end

local function setting(config, key, fallback, low, high)
    local value = type(config) == "table" and config[key] or nil
    return bounded(value, low, high) and value or fallback
end

local function options(config)
    return {
        spawnX = setting(config, "spawnX", 600, -MAX_COORDINATE, MAX_COORDINATE),
        spawnY = setting(config, "spawnY", 480, -MAX_COORDINATE, MAX_COORDINATE),
        speed = setting(config, "speed", 100, 1, 1000),
        loadedSpeed = setting(config, "loadedSpeed", 72, 1, 1000),
        travelHeight = setting(config, "travelHeight", 0.08, 0.001, 0.2),
        liftDuration = setting(config, "liftDuration", 3, 0.1, 60),
        lowerDuration = setting(config, "lowerDuration", 2.5, 0.1, 60),
        maxStepDistance = setting(config, "maxStepDistance", 4, 0.25, 32),
        collisionHalfWidth = setting(config, "collisionHalfWidth", 40, 1, 200),
        collisionHalfHeight = setting(config, "collisionHalfHeight", 18, 1, 200),
        loadedCollisionHalfWidth = setting(config, "loadedCollisionHalfWidth", 48, 1, 200),
        loadedCollisionHalfHeight = setting(config, "loadedCollisionHalfHeight", 24, 1, 200),
        forkOffsetX = setting(config, "forkOffsetX", 56, 0, 200),
        forkOffsetY = setting(config, "forkOffsetY", 32, 0, 200),
    }
end

local function copy(value)
    local result = {}
    for key, item in pairs(value) do result[key] = item end
    return result
end

function Forklift.defaultState(config)
    local configValues = options(config)
    return { owned = false, x = configValues.spawnX, y = configValues.spawnY,
        direction = "northwest", operating = false, operatorPlayerId = nil,
        carriedPalletId = nil, moving = false, animationDistance = 0,
        forkHeight = 0, targetForkHeight = 0, lifting = false }
end

function Forklift.normalize(value, config)
    value = type(value) == "table" and value or {}
    local result, configValues = Forklift.defaultState(config), options(config)
    result.owned = value.owned == true
    if bounded(value.x, -MAX_COORDINATE, MAX_COORDINATE) then result.x = value.x end
    if bounded(value.y, -MAX_COORDINATE, MAX_COORDINATE) then result.y = value.y end
    if directionFrames[value.direction] then result.direction = value.direction end
    if bounded(value.animationDistance, 0, MAX_DISTANCE) then
        result.animationDistance = value.animationDistance
    end
    if not result.owned then return result end
    if palletId(value.carriedPalletId) then result.carriedPalletId = value.carriedPalletId end
    if bounded(value.forkHeight, 0, 1) then result.forkHeight = value.forkHeight end
    result.operating = value.operating == true and operatorId(value.operatorPlayerId)
    if result.operating then result.operatorPlayerId = value.operatorPlayerId end
    result.targetForkHeight = result.operating and bounded(value.targetForkHeight, 0, 1)
        and value.targetForkHeight or result.forkHeight
    result.lifting = math.abs(result.targetForkHeight - result.forkHeight) > EPSILON
    if not result.lifting then result.targetForkHeight = result.forkHeight end
    result.moving = value.moving == true and result.operating and not result.lifting
        and result.forkHeight <= configValues.travelHeight + EPSILON
        and (not result.carriedPalletId or result.forkHeight >= configValues.travelHeight - EPSILON)
    return result
end

function Forklift.ensure(state, config)
    assert(type(state) == "table", "forklift requires a state table")
    local normalized = Forklift.normalize(state.forklift, config)
    if type(state.forklift) ~= "table" then state.forklift = {} end
    local lift = state.forklift
    for key, value in pairs(normalized) do lift[key] = value end
    lift.operatorPlayerId = normalized.operatorPlayerId
    lift.carriedPalletId = normalized.carriedPalletId
    return lift
end

function Forklift.validState(value, config)
    if type(value) ~= "table" or type(value.owned) ~= "boolean"
        or not bounded(value.x, -MAX_COORDINATE, MAX_COORDINATE)
        or not bounded(value.y, -MAX_COORDINATE, MAX_COORDINATE)
        or not directionFrames[value.direction]
        or type(value.operating) ~= "boolean" or type(value.moving) ~= "boolean"
        or type(value.lifting) ~= "boolean"
        or not bounded(value.forkHeight, 0, 1) or not bounded(value.targetForkHeight, 0, 1)
        or not bounded(value.animationDistance, 0, MAX_DISTANCE)
        or (value.carriedPalletId ~= nil and not palletId(value.carriedPalletId))
        or (value.operating and not operatorId(value.operatorPlayerId))
        or (not value.operating and value.operatorPlayerId ~= nil)
    then return false, "invalid" end
    local expected = Forklift.normalize(value, config)
    for key, item in pairs(expected) do
        if value[key] ~= item then return false, "inconsistent" end
    end
    if value.carriedPalletId ~= expected.carriedPalletId
        or value.operatorPlayerId ~= expected.operatorPlayerId
    then return false, "inconsistent" end
    return true
end

function Forklift.snapshot(state, config)
    return Forklift.normalize(Forklift.ensure(state, config), config)
end

function Forklift.applySnapshot(state, snapshot, config)
    if type(state) ~= "table" or not Forklift.validState(snapshot, config) then
        return false, "invalid"
    end
    if type(state.forklift) ~= "table" or type(state.forklift.owned) ~= "boolean" then
        return false, "invalid_state"
    end
    -- Realtime poses cannot purchase, spawn, or revoke the durable vehicle.
    -- Paid-but-not-yet-materialized vehicles legitimately remain unowned here.
    if snapshot.owned ~= state.forklift.owned
        or (snapshot.owned and type(state.warehouse) == "table"
            and state.warehouse.forkliftOwned ~= true)
    then return false, "awaiting_durable" end
    if snapshot.operating and type(state.palletJack) == "table"
        and state.palletJack.operating
        and state.palletJack.operatorPlayerId == snapshot.operatorPlayerId
    then return false, "operator_conflict" end
    if snapshot.carriedPalletId and type(state.palletJack) == "table"
        and state.palletJack.carriedPalletId == snapshot.carriedPalletId
    then return false, "cargo_conflict" end
    local durableId, durableCount = nil, 0
    local function inspect(groups)
        for _, group in ipairs(groups or {}) do
            for _, pallet in ipairs(group.pallets or {}) do
                if pallet.location == "on_forklift" then
                    durableId, durableCount = pallet.id, durableCount + 1
                end
            end
        end
    end
    inspect(state.jobs and state.jobs.active)
    inspect(state.procurement and state.procurement.orders)
    -- Reliable custody and realtime motion can arrive in either order. Do not
    -- let an old vehicle packet invent, drop, or replace reliable pallet ownership.
    if durableCount > 1 or snapshot.carriedPalletId ~= durableId then
        return false, "awaiting_durable"
    end
    state.forklift = Forklift.normalize(snapshot, config)
    return true, "applied"
end

function Forklift.isOperator(state, config, playerId)
    local lift = Forklift.ensure(state, config)
    return lift.owned and lift.operating and operatorId(playerId)
        and lift.operatorPlayerId == playerId
end

function Forklift.acquire(state, config, playerId)
    local lift = Forklift.ensure(state, config)
    if not operatorId(playerId) then return false, "invalid_operator" end
    if not lift.owned then return false, "not_owned" end
    if type(state.palletJack) == "table" and state.palletJack.operating
        and state.palletJack.operatorPlayerId == playerId
    then return false, "already_operating_vehicle" end
    if lift.operating then
        return lift.operatorPlayerId == playerId,
            lift.operatorPlayerId == playerId and "already_mounted" or "busy"
    end
    lift.operating, lift.operatorPlayerId, lift.moving = true, playerId, false
    return true, "mounted"
end

function Forklift.release(state, config, playerId)
    local lift = Forklift.ensure(state, config)
    if not Forklift.isOperator(state, config, playerId) then return false, "not_owner" end
    if lift.moving then return false, "moving" end
    if lift.lifting or lift.forkHeight > EPSILON then return false, "lower_forks_first" end
    lift.operating, lift.operatorPlayerId = false, nil
    return true, lift.carriedPalletId and "parked_loaded" or "parked"
end

function Forklift.forceRelease(state, config, playerId)
    local lift = Forklift.ensure(state, config)
    if playerId ~= nil and not operatorId(playerId) then return false, "invalid_operator" end
    if lift.operating and playerId ~= nil and lift.operatorPlayerId ~= playerId then
        return false, "not_owner"
    end
    lift.operating, lift.operatorPlayerId, lift.moving = false, nil, false
    -- A disconnect parks the machine in place, never drops cargo or finishes a lift unattended.
    lift.targetForkHeight, lift.lifting = lift.forkHeight, false
    return true, lift.carriedPalletId and "parked_loaded" or "parked"
end

function Forklift.setForkHeight(state, config, playerId, target)
    local lift = Forklift.ensure(state, config)
    if not Forklift.isOperator(state, config, playerId) then return false, "not_owner" end
    if not bounded(target, 0, 1) then return false, "invalid_height" end
    if lift.moving then return false, "moving" end
    if math.abs(target - lift.targetForkHeight) <= EPSILON then return true, "already_targeted" end
    lift.targetForkHeight = target
    lift.lifting = math.abs(target - lift.forkHeight) > EPSILON
    if not lift.lifting then lift.targetForkHeight = lift.forkHeight end
    return true, lift.lifting and "lifting" or "positioned"
end

function Forklift.update(state, dt, config)
    local lift = Forklift.ensure(state, config)
    if not finite(dt) or dt < 0 then return false, "invalid_dt" end
    if not lift.operating or not lift.lifting or dt == 0 then return false, "idle" end
    local configValues = options(config)
    local delta = lift.targetForkHeight - lift.forkHeight
    local duration = delta > 0 and configValues.liftDuration or configValues.lowerDuration
    local step = math.min(math.abs(delta), dt / duration)
    lift.forkHeight = lift.forkHeight + (delta > 0 and step or -step)
    if math.abs(lift.targetForkHeight - lift.forkHeight) <= EPSILON then
        lift.forkHeight, lift.lifting = lift.targetForkHeight, false
    end
    lift.moving = false
    return true, lift.lifting and "lifting" or "positioned"
end

function Forklift.directionFor(dx, dy, current)
    if not finite(dx) or not finite(dy) or (dx == 0 and dy == 0) then
        return directionFrames[current] and current or "northwest"
    end
    local ax, ay, threshold = math.abs(dx), math.abs(dy), 0.4142135623730951
    if ax <= ay * threshold then return dy < 0 and "north" or "south" end
    if ay <= ax * threshold then return dx < 0 and "west" or "east" end
    if dy < 0 then return dx < 0 and "northwest" or "northeast" end
    return dx < 0 and "southwest" or "southeast"
end

function Forklift.move(state, dx, dy, dt, config, canMove, playerId)
    local lift = Forklift.ensure(state, config)
    if not Forklift.isOperator(state, config, playerId) then return false, "not_owner" end
    lift.moving = false
    if not finite(dx) or not finite(dy) or not bounded(dt, 0, 60)
        or math.abs(dx) > 1000 or math.abs(dy) > 1000
    then return false, "invalid_input" end
    local configValues = options(config)
    if lift.lifting or lift.forkHeight > configValues.travelHeight + EPSILON then
        return false, "forks_elevated"
    end
    if lift.carriedPalletId and lift.forkHeight < configValues.travelHeight - EPSILON then
        return false, "raise_to_travel_height"
    end
    if dx == 0 and dy == 0 or dt == 0 then return false, "idle" end
    if type(canMove) ~= "function" then return false, "collision_required" end
    local length = math.sqrt(dx * dx + dy * dy)
    local divisor = math.max(1, length)
    dx, dy = dx / divisor, dy / divisor
    local speed = lift.carriedPalletId and configValues.loadedSpeed or configValues.speed
    local distance = math.sqrt(dx * dx + dy * dy) * speed * dt
    local steps = math.max(1, math.ceil(distance / configValues.maxStepDistance))
    local stepX, stepY = dx * speed * dt / steps, dy * speed * dt / steps
    lift.direction = Forklift.directionFor(dx, dy, lift.direction)
    local travelled = 0
    for _ = 1, steps do
        local nextX, nextY = lift.x + stepX, lift.y + stepY
        if not bounded(nextX, -MAX_COORDINATE, MAX_COORDINATE)
            or not bounded(nextY, -MAX_COORDINATE, MAX_COORDINATE)
            or not canMove(nextX, nextY, lift.carriedPalletId ~= nil, lift.direction)
        then break end
        lift.x, lift.y = nextX, nextY
        travelled = travelled + math.sqrt(stepX * stepX + stepY * stepY)
    end
    lift.moving = travelled > 0
    lift.animationDistance = (lift.animationDistance + travelled) % MAX_DISTANCE
    return lift.moving, lift.moving and "moved" or "blocked", travelled
end

local function transferCargo(state, config, playerId, id, transfer, attaching)
    local lift = Forklift.ensure(state, config)
    if not Forklift.isOperator(state, config, playerId) then return false, "not_owner" end
    if not palletId(id) then return false, "invalid_pallet" end
    if lift.moving or lift.lifting then return false, "not_stationary" end
    if attaching and lift.carriedPalletId then
        return false, lift.carriedPalletId == id and "already_loaded" or "cargo_occupied"
    end
    if not attaching and lift.carriedPalletId ~= id then return false, "wrong_pallet" end
    if type(state.palletJack) == "table" and state.palletJack.carriedPalletId == id then
        return false, "cargo_conflict"
    end
    if type(transfer) ~= "function" then return false, "transfer_required" end
    -- The callback must atomically validate height, reach, destination occupancy,
    -- and canonical pallet custody. A refusal must make no domain changes.
    local ok, code = transfer(id, attaching and "attach" or "detach", copy(lift))
    if ok ~= true then return false, code or "transfer_rejected" end
    lift.carriedPalletId = attaching and id or nil
    return true, attaching and "attached" or "detached"
end

function Forklift.attachCargo(state, config, playerId, id, transfer)
    return transferCargo(state, config, playerId, id, transfer, true)
end

function Forklift.detachCargo(state, config, playerId, id, transfer)
    return transferCargo(state, config, playerId, id, transfer, false)
end

function Forklift.frame(state, config)
    local lift = Forklift.ensure(state, config)
    return directionFrames[lift.direction], lift.carriedPalletId ~= nil, lift.forkHeight
end

function Forklift.dropPosition(state, config)
    local lift, configValues = Forklift.ensure(state, config), options(config)
    local vector = vectors[lift.direction]
    return lift.x + vector[1] * configValues.forkOffsetX,
        lift.y + vector[2] * configValues.forkOffsetY
end

function Forklift.operatorPosition(state, config)
    local lift = Forklift.ensure(state, config)
    return lift.x, lift.y
end

function Forklift.obstacle(state, config)
    local lift, configValues = Forklift.ensure(state, config), options(config)
    if not lift.owned then return nil end
    return { x = lift.x, y = lift.y,
        halfWidth = lift.carriedPalletId and configValues.loadedCollisionHalfWidth
            or configValues.collisionHalfWidth,
        halfHeight = lift.carriedPalletId and configValues.loadedCollisionHalfHeight
            or configValues.collisionHalfHeight }
end

return Forklift
