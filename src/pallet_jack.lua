local PalletJack = {}
local PalletState = require("src.pallet_state")

-- Driving inertia is presentation-only state. Keeping it outside the durable
-- jack record means old saves and multiplayer snapshots stay byte-compatible.
local runtimeMotion = setmetatable({}, { __mode = "k" })

local directionFrames = {
    northwest = 1, north = 2, northeast = 3, east = 4,
    southeast = 5, south = 6, southwest = 7, west = 8,
}
local palletFrames = {
    northwest = 1, north = 1,
    northeast = 2, east = 2,
    southeast = 4, south = 4,
    southwest = 3, west = 3,
}
local dropOffsets = {
    northwest = { x = -56, y = -32 },
    north = { x = 0, y = -48 },
    northeast = { x = 56, y = -32 },
    east = { x = 56, y = 0 },
    southeast = { x = 56, y = 32 },
    south = { x = 0, y = 48 },
    southwest = { x = -56, y = 32 },
    west = { x = -56, y = 0 },
}

local directionVectors = {
    northwest = { x = -1, y = -1 }, north = { x = 0, y = -1 },
    northeast = { x = 1, y = -1 }, east = { x = 1, y = 0 },
    southeast = { x = 1, y = 1 }, south = { x = 0, y = 1 },
    southwest = { x = -1, y = 1 }, west = { x = -1, y = 0 },
}

local directionAngles = {
    east = 0, southeast = math.pi / 4, south = math.pi / 2,
    southwest = math.pi * 3 / 4, west = math.pi,
    northwest = math.pi * 5 / 4, north = math.pi * 3 / 2,
    northeast = math.pi * 7 / 4,
}
local art = require("src.pallet_jack_art")
local function angleDelta(from, to)
    return (to - from + math.pi) % (math.pi * 2) - math.pi
end

local directionFor

local function operatorOffset(directionName, config)
    local authored = config.operatorOffsets and config.operatorOffsets[directionName]
    if authored then return authored.x or 0, authored.y or 0 end
    local direction = directionVectors[directionName] or directionVectors.northwest
    return -direction.x * (config.operatorDistanceX or 42),
        -direction.y * (config.operatorDistanceY or 24)
end

local function motionFor(jack, config)
    local motion = runtimeMotion[jack]
    if not motion then
        local offsetX, offsetY = operatorOffset(jack.direction, config or {})
        motion = { velocityX = 0, velocityY = 0, distance = 0,
            operatorDirection = jack.direction,
            operatorOffsetX = offsetX, operatorOffsetY = offsetY,
            heading = directionAngles[jack.direction],
            targetHeading = directionAngles[jack.direction] }
        runtimeMotion[jack] = motion
    end
    return motion
end

local function validOperatorId(value)
    return type(value) == "number" and value == math.floor(value)
        and value >= 1 and value <= 4
end

function PalletJack.dropPosition(state, config)
    local jack = PalletJack.ensure(state, config)
    local offset = dropOffsets[jack.direction]
    return jack.x + offset.x, jack.y + offset.y
end

local function findPallet(state, palletId)
    local item = PalletState.find(state, palletId)
    if item then return item.job, item.pallet, item.vendor end
end

local function eligibleForJack(item)
    local pallet = item and item.pallet
    if not pallet or type(pallet.world) ~= "table" then return false end
    if item.vendor then return pallet.location == "warehouse" end
    return pallet.location == "warehouse" or pallet.location == "cutter_output"
        or pallet.location == "press_output"
end

local function pickupBlocker(state, item)
    if not eligibleForJack(item) then return "unavailable" end
    if require("src.pallet_storage").isSupporting(state, item.pallet.id) then
        return "supporting_pallet"
    end
    if state.employment and require("src.employees").reservation(state, nil, item.pallet.id) then
        return "employee_reserved"
    end
end

function PalletJack.pickupCandidate(state, config, palletId)
    local jack = PalletJack.ensure(state, config)
    local radius = math.max(0, tonumber(config and config.pickupRadius) or 0)
    local best, bestDistance
    for _, item in ipairs(PalletState.items(state)) do
        if (palletId == nil or item.pallet.id == palletId) and not pickupBlocker(state, item) then
            local dx, dy = item.pallet.world.x - jack.x, item.pallet.world.y - jack.y
            local distance = dx * dx + dy * dy
            if distance <= radius * radius and (not bestDistance or distance < bestDistance
                or (distance == bestDistance and item.pallet.id < best.pallet.id))
            then
                best, bestDistance = item, distance
            end
        end
    end
    if best then return best, nil, bestDistance end
    if palletId == nil then return nil, "no_pallet" end
    local requested = PalletState.find(state, palletId)
    if not requested then return nil, "missing" end
    local blocker = pickupBlocker(state, requested)
    if blocker then return nil, blocker end
    return nil, "out_of_range"
end

function PalletJack.defaultState(config)
    return {
        x = config.spawnX,
        y = config.spawnY,
        direction = "northwest",
        operating = false,
        operatorPlayerId = nil,
        carriedPalletId = nil,
        moving = false,
        animationClock = 0,
    }
end

function PalletJack.ensure(state, config)
    if type(state.palletJack) ~= "table" then state.palletJack = PalletJack.defaultState(config) end
    local jack = state.palletJack
    jack.x = type(jack.x) == "number" and jack.x or config.spawnX
    jack.y = type(jack.y) == "number" and jack.y or config.spawnY
    jack.direction = directionFrames[jack.direction] and jack.direction or "northwest"
    jack.operating = jack.operating == true
    if jack.operating then
        -- Older single-player runtime state had no explicit owner. Treat it as
        -- the local host without ever persisting this transient network field.
        jack.operatorPlayerId = validOperatorId(jack.operatorPlayerId)
            and jack.operatorPlayerId or 1
    else
        jack.operatorPlayerId = nil
    end
    if type(jack.candidatePalletId) ~= "string" or jack.candidatePalletId == "" then
        jack.candidatePalletId = nil
    end
    if not jack.operating or jack.carriedPalletId then jack.candidatePalletId = nil end
    jack.moving = jack.moving == true
    if not jack.operating then jack.moving = false end
    jack.animationClock = type(jack.animationClock) == "number" and jack.animationClock or 0
    return jack
end

function PalletJack.mount(state, config, operatorPlayerId)
    local jack = PalletJack.ensure(state, config)
    if not validOperatorId(operatorPlayerId) then return false, "invalid_operator" end
    local forklift = state.forklift
    if type(forklift) == "table" and forklift.operating
        and forklift.operatorPlayerId == operatorPlayerId then
        return false, "operating_forklift"
    end
    if jack.operating then
        if jack.operatorPlayerId == operatorPlayerId then return true, "already_mounted" end
        return false, "busy"
    end
    jack.operating = true
    jack.operatorPlayerId = operatorPlayerId
    jack.moving = false
    runtimeMotion[jack] = nil
    motionFor(jack, config)
    return true, "mounted"
end

function PalletJack.isOperator(state, config, playerId)
    local jack = PalletJack.ensure(state, config)
    return jack.operating and validOperatorId(playerId)
        and jack.operatorPlayerId == playerId
end

function PalletJack.forceRelease(state, config, operatorPlayerId)
    local jack = PalletJack.ensure(state, config)
    if not jack.operating then return true, "already_released" end
    if operatorPlayerId ~= nil and jack.operatorPlayerId ~= operatorPlayerId then
        return false, "not_owner"
    end
    jack.operating = false
    jack.operatorPlayerId = nil
    jack.moving = false
    runtimeMotion[jack] = nil
    return true, jack.carriedPalletId and "parked_loaded" or "parked"
end

function PalletJack.frame(state, config)
    local jack = PalletJack.ensure(state, config)
    return directionFrames[jack.direction], jack.carriedPalletId ~= nil,
        palletFrames[jack.direction]
end

function PalletJack.operatorPosition(state, config)
    local jack = PalletJack.ensure(state, config)
    local motion = motionFor(jack, config)
    -- Snap only after an external placement/rotation changes the jack's view.
    -- Normal steering eases the operator's offset every movement substep.
    if motion.operatorDirection ~= jack.direction then
        motion.operatorDirection = jack.direction
        motion.heading = directionAngles[jack.direction]
        motion.targetHeading = motion.heading
    end
    local pose = PalletJack.visualPose(state, config)
    -- Both the rendered grip and the operator's ground point use the same
    -- continuous heading. Independent offset easing made the hands detach.
    return pose.x + pose.operatorX, pose.y + pose.operatorY
end

function PalletJack.visualPose(state, config)
    local jack = PalletJack.ensure(state, config)
    local motion = motionFor(jack, config)
    if motion.operatorDirection ~= jack.direction then
        motion.operatorDirection = jack.direction
        motion.heading = directionAngles[jack.direction]
        motion.targetHeading = motion.heading
    end
    local phase = (motion.heading % (math.pi * 2)) / (math.pi * 2) * #art.frames
    local first = math.floor(phase) % #art.frames + 1
    local second = first % #art.frames + 1
    local blend = phase - math.floor(phase)
    local a, b = art.frames[first], art.frames[second]
    local function sample(key)
        return (a[key] + (b[key] - a[key]) * blend)
            * config.drawScale * (config.resolutionScale or 1)
    end
    return { x = jack.x, y = jack.y, heading = motion.heading,
        frame = first, nextFrame = second, blend = blend, distance = motion.distance,
        handleX = sample("handleX"), handleY = sample("handleY"),
        loadX = sample("loadX"), loadY = sample("loadY"),
        operatorX = sample("operatorX"), operatorY = sample("operatorY") }
end

function PalletJack.animationDistance(state, config)
    return motionFor(PalletJack.ensure(state, config), config).distance
end

function PalletJack.stop(state, config)
    local jack = PalletJack.ensure(state, config)
    local motion = motionFor(jack, config)
    motion.velocityX, motion.velocityY = 0, 0
    jack.moving = false
end

-- A reliable shop refresh replaces the durable jack table while retaining its
-- live snapshot. Carry its private motion forward only for that identical pose.
function PalletJack.continueMotion(state, previousJack, config)
    local jack = PalletJack.ensure(state, config)
    local previousMotion = previousJack and runtimeMotion[previousJack]
    if not previousMotion or not jack.operating or not previousJack.operating
        or jack.operatorPlayerId ~= previousJack.operatorPlayerId
        or jack.x ~= previousJack.x or jack.y ~= previousJack.y
        or jack.direction ~= previousJack.direction then return false end
    local motion = {}
    for key, value in pairs(previousMotion) do motion[key] = value end
    runtimeMotion[jack] = motion
    return true
end

-- Machine placement resolves its own collisions and speed. Record only the
-- resulting travel so pushing feet stay in step, without retaining drive inertia.
function PalletJack.followPlacement(state, item, dt, config)
    local jack = PalletJack.ensure(state, config)
    local motion = motionFor(jack, config)
    local dx, dy = item.x - jack.x, item.y + 8 - jack.y
    PalletJack.stop(state, config)
    jack.x, jack.y = item.x, item.y + 8
    jack.direction, jack.moving = item.direction, item.inMotion == true
    jack.animationClock = jack.animationClock + math.max(0, tonumber(dt) or 0)
    if jack.moving then motion.distance = motion.distance + math.sqrt(dx * dx + dy * dy) end
    motion.operatorDirection = jack.direction
    motion.heading = directionAngles[jack.direction]
    motion.targetHeading = motion.heading
end

-- Remote snapshots also use the same turn arc. Advancing presentation never
-- changes authoritative position, ownership, collision or durable save data.
function PalletJack.updatePresentation(state, dt, config)
    local jack = PalletJack.ensure(state, config)
    local motion = motionFor(jack, config)
    local amount = (config.turnRadiansPerSecond or math.pi * 2.5)
        * math.max(0, math.min(tonumber(dt) or 0, .1))
    local delta = angleDelta(motion.heading, motion.targetHeading)
    motion.heading = motion.heading + math.max(-amount, math.min(amount, delta))
end

function PalletJack.obstacle(state, config)
    local jack = PalletJack.ensure(state, config)
    if jack.operating then return nil end
    local loaded = jack.carriedPalletId ~= nil
    return {
        x = jack.x,
        y = jack.y - 5,
        halfWidth = loaded and config.loadedCollisionHalfWidth or config.collisionHalfWidth,
        halfHeight = loaded and config.loadedCollisionHalfHeight or config.collisionHalfHeight,
    }
end

function PalletJack.interaction(player, state, config)
    local jack = PalletJack.ensure(state, config)
    local nearby = PalletJack.pickupCandidate(state, config)
    local playerId = validOperatorId(player and player.id) and player.id or 1
    local ownsJack = jack.operating and jack.operatorPlayerId == playerId
    local prompt
    if not jack.operating then
        prompt = "E: operate pallet jack"
    elseif not ownsJack then
        prompt = "Pallet jack in use by another worker"
    elseif jack.carriedPalletId then
        prompt = "L: lower pallet at the selected position"
    elseif nearby then
        prompt = "Tap skid or L: lift " .. nearby.pallet.id .. "  |  F: park jack"
    else
        prompt = "F: park pallet jack"
    end
    return {
        -- Keep the jack anchored to its own hit target while it is moving.
        -- Centering this interaction on the operator made it hide nearby
        -- computers, doors, machines, and customers from the normal USE key.
        x = jack.x,
        y = jack.y,
        radius = config.interactionRadius,
        prompt = prompt,
        jackState = jack,
        candidatePalletId = nearby and nearby.pallet.id or nil,
        ownsJack = ownsJack,
    }
end

directionFor = function(dx, dy, current)
    if math.abs(dx) < 0.0001 and math.abs(dy) < 0.0001 then return current end
    local absX, absY = math.abs(dx), math.abs(dy)
    local diagonalThreshold = 0.41421356237
    if absX <= absY * diagonalThreshold then return dy < 0 and "north" or "south" end
    if absY <= absX * diagonalThreshold then return dx < 0 and "west" or "east" end
    if dx < 0 then return dy < 0 and "northwest" or "southwest" end
    return dy < 0 and "northeast" or "southeast"
end

local function moveToward(x, y, targetX, targetY, maximumDelta)
    local dx, dy = targetX - x, targetY - y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= maximumDelta or distance < 0.000001 then return targetX, targetY end
    local scale = maximumDelta / distance
    return x + dx * scale, y + dy * scale
end

local gaitSpeed = { 0.96, 0.94, 1.04, 1.06, 0.96, 0.94, 1.04, 1.06 }
local gaitAcceleration = { 0.92, 0.90, 1.08, 1.10, 0.92, 0.90, 1.08, 1.10 }

local function smoothstep(value)
    return value * value * (3 - 2 * value)
end

local function sampleGait(values, distance, pixelsPerFrame)
    local phase = math.max(0, distance) / math.max(1, pixelsPerFrame)
    local pose = math.floor(phase)
    local blend = smoothstep(phase - pose)
    local current = values[pose % #values + 1]
    local following = values[(pose + 1) % #values + 1]
    return current + (following - current) * blend
end

local function driveStep(jack, motion, dx, dy, dt, speed, config, canMove)
    local inputLength = math.sqrt(dx * dx + dy * dy)
    local strength = math.min(1, inputLength)
    local desiredX, desiredY = 0, 0
    local pixelsPerFrame = config.gaitPixelsPerFrame or 20
    local phaseSpeed = sampleGait(gaitSpeed, motion.distance, pixelsPerFrame)
    if inputLength > 0.0001 then
        desiredX = dx / inputLength * speed * strength * phaseSpeed
        desiredY = dy / inputLength * speed * strength * phaseSpeed
    end

    local dot = motion.velocityX * desiredX + motion.velocityY * desiredY
    local reversing = inputLength > 0.0001 and dot < -0.0001
    local acceleration
    if inputLength <= 0.0001 or reversing then
        acceleration = jack.carriedPalletId
            and (config.loadedDeceleration or config.deceleration or 620)
            or (config.deceleration or 620)
    else
        acceleration = jack.carriedPalletId
            and (config.loadedAcceleration or config.acceleration or 420)
            or (config.acceleration or 420)
        acceleration = acceleration * sampleGait(gaitAcceleration,
            motion.distance, pixelsPerFrame)
    end
    motion.velocityX, motion.velocityY = moveToward(
        motion.velocityX, motion.velocityY, desiredX, desiredY, acceleration * dt)

    local stepX, stepY = motion.velocityX * dt, motion.velocityY * dt
    if math.abs(stepX) < 0.000001 and math.abs(stepY) < 0.000001 then return 0, 0 end
    if canMove(jack.x + stepX, jack.y + stepY) then
        jack.x, jack.y = jack.x + stepX, jack.y + stepY
        return stepX, stepY
    end

    -- Resolve the axes separately when the full step is blocked, preserving
    -- the unblocked component so the jack can slide smoothly along walls.
    local movedX, movedY = 0, 0
    local function tryX()
        if math.abs(stepX) < 0.000001 then return end
        if canMove(jack.x + stepX, jack.y) then
            jack.x, movedX = jack.x + stepX, stepX
        else
            motion.velocityX = 0
        end
    end
    local function tryY()
        if math.abs(stepY) < 0.000001 then return end
        if canMove(jack.x, jack.y + stepY) then
            jack.y, movedY = jack.y + stepY, stepY
        else
            motion.velocityY = 0
        end
    end
    if math.abs(stepX) >= math.abs(stepY) then tryX(); tryY() else tryY(); tryX() end
    return movedX, movedY
end

function PalletJack.move(state, dx, dy, dt, config, canMove)
    local jack = PalletJack.ensure(state, config)
    if not jack.operating then return false end
    jack.moving = false
    jack.animationClock = jack.animationClock + math.max(0, dt)
    local speed = jack.carriedPalletId and config.loadedSpeed or config.speed
    local motion = motionFor(jack, config)
    local elapsed = math.min(math.max(0, tonumber(dt) or 0), 0.1)
    if elapsed <= 0 then return false end
    local slices = math.max(1, math.ceil(elapsed / (1 / 60)))
    local sliceDt = elapsed / slices
    local movedDistance = 0
    for _ = 1, slices do
        local x, y = driveStep(jack, motion, tonumber(dx) or 0, tonumber(dy) or 0,
            sliceDt, speed, config, function(nextX, nextY)
                return canMove(nextX, nextY, jack.carriedPalletId ~= nil)
            end)
        local distance = math.sqrt(x * x + y * y)
        movedDistance = movedDistance + distance
        if distance > 0.0001 then
            jack.direction = directionFor(x, y, jack.direction)
            motion.operatorDirection = jack.direction
            motion.targetHeading = math.atan2(y, x)
            motion.distance = motion.distance + distance
        end
        PalletJack.updatePresentation(state, sliceDt, config)
    end
    if movedDistance > 0.0001 then
        jack.moving = true
    end
    if not jack.moving and math.abs(motion.velocityX) + math.abs(motion.velocityY) < 0.001 then
        motion.velocityX, motion.velocityY = 0, 0
    end
    if not jack.moving then return false end
    local _, pallet = findPallet(state, jack.carriedPalletId)
    if pallet then
        pallet.world = pallet.world or {}
        pallet.world.x, pallet.world.y = jack.x, jack.y
        pallet.world.direction = jack.direction
        pallet.world.rotation = palletFrames[jack.direction]
        pallet.world.fromX, pallet.world.fromY = jack.x, jack.y
        pallet.world.spawnProgress = 1
    end
    return true
end

function PalletJack.lift(state, config, palletId)
    local jack = PalletJack.ensure(state, config)
    if not jack.operating then return false, "not_operating" end
    if jack.carriedPalletId then return false, "already_loaded" end
    if type(palletId) ~= "string" or palletId == "" then return false, "invalid_pallet" end
    local nearby, candidateError = PalletJack.pickupCandidate(state, config, palletId)
    if not nearby then return false, candidateError end
    local transitioned, transitionError = PalletState.transition(
        state, nearby.pallet, "on_pallet_jack")
    if not transitioned then return false, transitionError end
    nearby.pallet.world = nearby.pallet.world or {}
    nearby.pallet.world.x, nearby.pallet.world.y = jack.x, jack.y
    nearby.pallet.world.direction = jack.direction
    nearby.pallet.world.rotation = palletFrames[jack.direction]
    nearby.pallet.world.fromX, nearby.pallet.world.fromY = jack.x, jack.y
    nearby.pallet.world.spawnProgress = 1
    return true, "lifted", nearby.pallet
end

function PalletJack.lower(state, config, canPlace, placementX, placementY, palletId)
    local jack = PalletJack.ensure(state, config)
    if not jack.operating then return false, "not_operating" end
    if not jack.carriedPalletId then return false, "not_loaded" end
    if palletId ~= nil and palletId ~= jack.carriedPalletId then return false, "wrong_pallet" end
    local dropX, dropY = placementX, placementY
    if type(dropX) ~= "number" or type(dropY) ~= "number" then
        dropX, dropY = PalletJack.dropPosition(state, config)
    end
    if type(canPlace) ~= "function" or not canPlace(dropX, dropY) then
        return false, "blocked"
    end
    local _, pallet = findPallet(state, jack.carriedPalletId)
    if not pallet then return false, "missing" end
    local world = {}
    for key, value in pairs(pallet.world or {}) do world[key] = value end
    world.x, world.y = dropX, dropY
    world.direction = jack.direction
    world.rotation = palletFrames[jack.direction]
    world.fromX, world.fromY = dropX, dropY
    world.spawnProgress = 1
    local transitioned, transitionError = PalletState.transition(
        state, pallet, "warehouse", { world = world })
    if not transitioned then return false, transitionError end
    return true, "lowered", pallet
end

function PalletJack.use(state, config, canPlace, placementX, placementY, operatorPlayerId)
    local jack = PalletJack.ensure(state, config)
    operatorPlayerId = operatorPlayerId or 1
    if not jack.operating then
        return PalletJack.mount(state, config, operatorPlayerId)
    end
    if jack.operatorPlayerId ~= operatorPlayerId then return false, "not_owner" end
    if jack.carriedPalletId then
        return PalletJack.lower(state, config, canPlace,
            placementX, placementY, jack.carriedPalletId)
    end
    local nearby = PalletJack.pickupCandidate(state, config)
    if nearby then
        return PalletJack.lift(state, config, nearby.pallet.id)
    end
    PalletJack.forceRelease(state, config, jack.operatorPlayerId)
    return true, "parked"
end

function PalletJack.park(state, config)
    local jack = PalletJack.ensure(state, config)
    if not jack.operating or jack.carriedPalletId then return false end
    return PalletJack.forceRelease(state, config, jack.operatorPlayerId)
end

function PalletJack.carriedItem(state, config)
    local jack = PalletJack.ensure(state, config)
    local job, pallet, vendor = findPallet(state, jack.carriedPalletId)
    if not pallet then return nil end
    return { job = job, pallet = pallet, vendor = vendor, x = jack.x, y = jack.y }
end

function PalletJack.snapshot(state, config)
    local jack = PalletJack.ensure(state, config)
    local candidate = jack.operating and not jack.carriedPalletId
        and PalletJack.pickupCandidate(state, config) or nil
    return {
        x = jack.x, y = jack.y, direction = jack.direction,
        frame = directionFrames[jack.direction], palletFrame = palletFrames[jack.direction],
        operating = jack.operating,
        moving = jack.moving, operatorPlayerId = jack.operatorPlayerId,
        carriedPalletId = jack.carriedPalletId,
        candidatePalletId = candidate and candidate.pallet.id or nil,
    }
end

function PalletJack.applySnapshot(state, snapshot, config)
    if type(state) ~= "table" or type(snapshot) ~= "table"
        or type(snapshot.x) ~= "number" or snapshot.x ~= snapshot.x or math.abs(snapshot.x) == math.huge
        or type(snapshot.y) ~= "number" or snapshot.y ~= snapshot.y or math.abs(snapshot.y) == math.huge
        or not directionFrames[snapshot.direction]
        or type(snapshot.operating) ~= "boolean" or type(snapshot.moving) ~= "boolean"
        or (snapshot.moving and not snapshot.operating)
        or (snapshot.operating ~= validOperatorId(snapshot.operatorPlayerId))
        or (snapshot.carriedPalletId ~= nil and type(snapshot.carriedPalletId) ~= "string")
        or (snapshot.candidatePalletId ~= nil and type(snapshot.candidatePalletId) ~= "string")
        or (snapshot.candidatePalletId ~= nil
            and (not snapshot.operating or snapshot.carriedPalletId ~= nil))
    then
        return false, "invalid"
    end
    local durableCarriedPalletId
    for _, item in ipairs(PalletState.items(state)) do
        if item.pallet.location == "on_pallet_jack" then
            durableCarriedPalletId = item.pallet.id
            break
        end
    end
    -- Realtime and durable packets use different ENet channels. Never let an
    -- older realtime ownership bit undo a newer reliable pallet transition,
    -- and do not disconnect when the realtime transition arrives first.
    if snapshot.carriedPalletId ~= durableCarriedPalletId then
        return false, "awaiting_durable"
    end
    local jack = PalletJack.ensure(state, config)
    local motion = motionFor(jack, config)
    local dx, dy = snapshot.x - jack.x, snapshot.y - jack.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local continuous = snapshot.operating and jack.operating
        and snapshot.operatorPlayerId == jack.operatorPlayerId and distance < 80
    if continuous then
        motion.distance = motion.distance + distance
    else
        -- Ownership changes, parking and teleports start a new motion history.
        motion.velocityX, motion.velocityY, motion.distance = 0, 0, 0
        motion.heading = directionAngles[snapshot.direction]
    end
    jack.x, jack.y = snapshot.x, snapshot.y
    jack.direction = snapshot.direction
    motion.operatorDirection = jack.direction
    motion.targetHeading = directionAngles[jack.direction]
    jack.operating, jack.moving = snapshot.operating, snapshot.moving
    jack.operatorPlayerId = snapshot.operatorPlayerId
    jack.carriedPalletId = snapshot.carriedPalletId
    jack.candidatePalletId = snapshot.candidatePalletId
    if snapshot.carriedPalletId then
        local item = PalletState.find(state, snapshot.carriedPalletId)
        item.pallet.world = item.pallet.world or {}
        item.pallet.world.x, item.pallet.world.y = jack.x, jack.y
        item.pallet.world.direction = jack.direction
        item.pallet.world.rotation = palletFrames[jack.direction]
        item.pallet.world.fromX, item.pallet.world.fromY = jack.x, jack.y
        item.pallet.world.spawnProgress = 1
    end
    return true
end

return PalletJack
