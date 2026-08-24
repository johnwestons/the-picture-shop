local PalletJack = {}
local Procurement = require("src.procurement")

local directionFrames = { northwest = 1, northeast = 2, southwest = 3, southeast = 4 }
local dropOffsets = {
    northwest = { x = -56, y = -32 },
    northeast = { x = 56, y = -32 },
    southwest = { x = -56, y = 32 },
    southeast = { x = 56, y = 32 },
}

local operatorSigns = {
    -- The operator stands beyond the handle, opposite the fork direction.
    northwest = { x = 1, y = 1 },
    northeast = { x = -1, y = 1 },
    southwest = { x = 1, y = -1 },
    southeast = { x = -1, y = -1 },
}

local function findPallet(state, palletId)
    for _, job in ipairs(state and state.jobs and state.jobs.active or {}) do
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.id == palletId then return job, pallet end
        end
    end
    for _, order in ipairs(Procurement.ensure(state).orders) do
        for _, pallet in ipairs(order.pallets or {}) do
            if pallet.id == palletId then return order, pallet, true end
        end
    end
end

local function nearestPallet(state, x, y, radius)
    local best, bestDistance
    for _, job in ipairs(state and state.jobs and state.jobs.active or {}) do
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.world and (pallet.location == "warehouse" or pallet.location == "cutter_output") then
                local dx, dy = pallet.world.x - x, pallet.world.y - y
                local distance = dx * dx + dy * dy
                if distance <= radius * radius and (not bestDistance or distance < bestDistance) then
                    best, bestDistance = { job = job, pallet = pallet }, distance
                end
            end
        end
    end
    for _, order in ipairs(Procurement.ensure(state).orders) do
        for _, pallet in ipairs(order.pallets or {}) do
            if pallet.world and pallet.location == "warehouse" then
                local dx, dy = pallet.world.x - x, pallet.world.y - y
                local distance = dx * dx + dy * dy
                if distance <= radius * radius and (not bestDistance or distance < bestDistance) then
                    best, bestDistance = { job = order, pallet = pallet, vendor = true }, distance
                end
            end
        end
    end
    return best
end

function PalletJack.defaultState(config)
    return {
        x = config.spawnX,
        y = config.spawnY,
        direction = "northwest",
        operating = false,
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
    jack.moving = false
    jack.animationClock = type(jack.animationClock) == "number" and jack.animationClock or 0
    return jack
end

function PalletJack.frame(state, config)
    local jack = PalletJack.ensure(state, config)
    return directionFrames[jack.direction], jack.carriedPalletId ~= nil
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
    local nearby = nearestPallet(state, jack.x, jack.y, config.pickupRadius)
    local prompt
    if not jack.operating then
        prompt = "E: operate pallet jack"
    elseif jack.carriedPalletId then
        prompt = "E: lower pallet at this position"
    elseif nearby then
        prompt = "E: lift " .. nearby.pallet.id .. "  |  F: park jack"
    else
        prompt = "E or F: park pallet jack"
    end
    return {
        x = jack.operating and player.x or jack.x,
        y = jack.operating and player.y or jack.y,
        radius = config.interactionRadius,
        prompt = prompt,
        jackState = jack,
    }
end

local function directionFor(dx, dy, current)
    if dx == 0 and dy == 0 then return current end
    if math.abs(dy) >= math.abs(dx) then
        return dy < 0 and "northwest" or "southeast"
    end
    return dx > 0 and "northeast" or "southwest"
end

function PalletJack.move(state, dx, dy, dt, config, canMove)
    local jack = PalletJack.ensure(state, config)
    if not jack.operating then return false end
    jack.moving = dx ~= 0 or dy ~= 0
    jack.animationClock = jack.animationClock + math.max(0, dt)
    if not jack.moving then return false end
    local length = math.sqrt(dx * dx + dy * dy)
    local speed = jack.carriedPalletId and config.loadedSpeed or config.speed
    local nextX = jack.x + dx / length * speed * dt
    local nextY = jack.y + dy / length * speed * dt
    jack.direction = directionFor(dx, dy, jack.direction)
    if not canMove(nextX, nextY, jack.carriedPalletId ~= nil) then return false end
    jack.x, jack.y = nextX, nextY
    local _, pallet = findPallet(state, jack.carriedPalletId)
    if pallet then
        pallet.world = pallet.world or {}
        pallet.world.x, pallet.world.y = jack.x, jack.y
        pallet.world.direction = jack.direction
        pallet.world.rotation = directionFrames[jack.direction]
        pallet.world.fromX, pallet.world.fromY = jack.x, jack.y
        pallet.world.spawnProgress = 1
    end
    return true
end

function PalletJack.use(state, config, canPlace)
    local jack = PalletJack.ensure(state, config)
    if not jack.operating then
        jack.operating = true
        return true, "mounted"
    end
    if jack.carriedPalletId then
        local offset = dropOffsets[jack.direction]
        local dropX, dropY = jack.x + offset.x, jack.y + offset.y
        if not canPlace(dropX, dropY) then return false, "blocked" end
        local _, pallet = findPallet(state, jack.carriedPalletId)
        if not pallet then jack.carriedPalletId = nil; return false, "missing" end
        pallet.location = "warehouse"
        pallet.world = pallet.world or {}
        pallet.world.x, pallet.world.y = dropX, dropY
        pallet.world.direction = jack.direction
        pallet.world.rotation = directionFrames[jack.direction]
        pallet.world.fromX, pallet.world.fromY = dropX, dropY
        pallet.world.spawnProgress = 1
        jack.carriedPalletId = nil
        return true, "lowered", pallet
    end
    local nearby = nearestPallet(state, jack.x, jack.y, config.pickupRadius)
    if nearby then
        nearby.pallet.location = "on_pallet_jack"
        jack.carriedPalletId = nearby.pallet.id
        nearby.pallet.world = nearby.pallet.world or {}
        nearby.pallet.world.direction = jack.direction
        nearby.pallet.world.rotation = directionFrames[jack.direction]
        return true, "lifted", nearby.pallet
    end
    jack.operating = false
    return true, "parked"
end

function PalletJack.park(state, config)
    local jack = PalletJack.ensure(state, config)
    if not jack.operating or jack.carriedPalletId then return false end
    jack.operating, jack.moving = false, false
    return true
end

function PalletJack.carriedItem(state, config)
    local jack = PalletJack.ensure(state, config)
    local job, pallet, vendor = findPallet(state, jack.carriedPalletId)
    if not pallet then return nil end
    return { job = job, pallet = pallet, vendor = vendor, x = jack.x, y = jack.y }
end

function PalletJack.snapshot(state, config)
    local jack = PalletJack.ensure(state, config)
    return {
        x = jack.x, y = jack.y, direction = jack.direction,
        frame = directionFrames[jack.direction], operating = jack.operating,
        moving = jack.moving, carriedPalletId = jack.carriedPalletId,
    }
end

return PalletJack
