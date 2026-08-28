local PalletJack = {}
local PalletState = require("src.pallet_state")

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

local operatorSigns = {
    -- The operator stands beyond the handle, opposite the fork direction.
    northwest = { x = 1, y = 1 },
    north = { x = 0, y = 1 },
    northeast = { x = -1, y = 1 },
    east = { x = -1, y = 0 },
    southeast = { x = -1, y = -1 },
    south = { x = 0, y = -1 },
    southwest = { x = 1, y = -1 },
    west = { x = 1, y = 0 },
}

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

function PalletJack.pickupCandidate(state, config, palletId)
    local jack = PalletJack.ensure(state, config)
    local radius = math.max(0, tonumber(config and config.pickupRadius) or 0)
    local best, bestDistance
    for _, item in ipairs(PalletState.items(state)) do
        if (palletId == nil or item.pallet.id == palletId) and eligibleForJack(item) then
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
    if not eligibleForJack(requested) then return nil, "unavailable" end
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
    if jack.operating then
        if jack.operatorPlayerId == operatorPlayerId then return true, "already_mounted" end
        return false, "busy"
    end
    jack.operating = true
    jack.operatorPlayerId = operatorPlayerId
    jack.moving = false
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
    return true, jack.carriedPalletId and "parked_loaded" or "parked"
end

function PalletJack.frame(state, config)
    local jack = PalletJack.ensure(state, config)
    return directionFrames[jack.direction], jack.carriedPalletId ~= nil,
        palletFrames[jack.direction]
end

function PalletJack.operatorPosition(state, config)
    local jack = PalletJack.ensure(state, config)
    local sign = operatorSigns[jack.direction]
    return jack.x + sign.x * (config.operatorDistanceX or 42),
        jack.y + sign.y * (config.operatorDistanceY or 24)
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
        prompt = "E: lower pallet at this position"
    elseif nearby then
        prompt = "E: lift " .. nearby.pallet.id .. "  |  F: park jack"
    else
        prompt = "E or F: park pallet jack"
    end
    return {
        x = ownsJack and player.x or jack.x,
        y = ownsJack and player.y or jack.y,
        radius = config.interactionRadius,
        prompt = prompt,
        jackState = jack,
        candidatePalletId = nearby and nearby.pallet.id or nil,
        ownsJack = ownsJack,
    }
end

local function directionFor(dx, dy, current)
    if dx == 0 and dy == 0 then return current end
    if dx < 0 then
        if dy < 0 then return "northwest" end
        if dy > 0 then return "southwest" end
        return "west"
    end
    if dx > 0 then
        if dy < 0 then return "northeast" end
        if dy > 0 then return "southeast" end
        return "east"
    end
    return dy < 0 and "north" or "south"
end

function PalletJack.move(state, dx, dy, dt, config, canMove)
    local jack = PalletJack.ensure(state, config)
    if not jack.operating then return false end
    jack.moving = false
    jack.animationClock = jack.animationClock + math.max(0, dt)
    if dx == 0 and dy == 0 then return false end
    local length = math.sqrt(dx * dx + dy * dy)
    local speed = jack.carriedPalletId and config.loadedSpeed or config.speed
    local nextX = jack.x + dx / length * speed * dt
    local nextY = jack.y + dy / length * speed * dt
    jack.direction = directionFor(dx, dy, jack.direction)
    if nextX == jack.x and nextY == jack.y then return false end
    if not canMove(nextX, nextY, jack.carriedPalletId ~= nil) then return false end
    jack.x, jack.y = nextX, nextY
    jack.moving = true
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
    if not jack.operating then
        return PalletJack.mount(state, config, operatorPlayerId or 1)
    end
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
        or type(snapshot.x) ~= "number" or snapshot.x ~= snapshot.x
        or type(snapshot.y) ~= "number" or snapshot.y ~= snapshot.y
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
    jack.x, jack.y = snapshot.x, snapshot.y
    jack.direction = snapshot.direction
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
