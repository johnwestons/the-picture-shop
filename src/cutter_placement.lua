local CutterPlacement = {}

local directionFrames = { northwest = 1, northeast = 2, southwest = 3, southeast = 4 }
local clockwise = {
    northwest = "northeast",
    northeast = "southeast",
    southeast = "southwest",
    southwest = "northwest",
}
local operatorSigns = {
    northwest = { x = 1, y = 1 },
    northeast = { x = -1, y = 1 },
    southwest = { x = 1, y = -1 },
    southeast = { x = -1, y = -1 },
}

function CutterPlacement.defaultState(config)
    return {
        x = config.spawnX,
        y = config.spawnY,
        direction = config.defaultDirection or "northwest",
        moving = false,
        inMotion = false,
    }
end

function CutterPlacement.ensure(state, config)
    if type(state.cutter) ~= "table" then state.cutter = CutterPlacement.defaultState(config) end
    local cutter = state.cutter
    cutter.x = type(cutter.x) == "number" and cutter.x or config.spawnX
    cutter.y = type(cutter.y) == "number" and cutter.y or config.spawnY
    cutter.direction = directionFrames[cutter.direction] and cutter.direction
        or config.defaultDirection or "northwest"
    cutter.moving = cutter.moving == true
    cutter.inMotion = cutter.inMotion == true
    return cutter
end

function CutterPlacement.frame(state, config)
    return directionFrames[CutterPlacement.ensure(state, config).direction]
end

function CutterPlacement.operatorPosition(state, config)
    local cutter = CutterPlacement.ensure(state, config)
    local sign = operatorSigns[cutter.direction]
    return cutter.x + sign.x * config.operatorDistanceX,
        cutter.y + sign.y * config.operatorDistanceY
end

function CutterPlacement.obstacle(state, config)
    local cutter = CutterPlacement.ensure(state, config)
    if cutter.moving then return nil end
    return { x = cutter.x, y = cutter.y - 8,
        halfWidth = config.collisionHalfWidth, halfHeight = config.collisionHalfHeight }
end

function CutterPlacement.interaction(player, state, config)
    local cutter = CutterPlacement.ensure(state, config)
    return {
        x = cutter.moving and player.x or cutter.x,
        y = cutter.moving and player.y or cutter.y,
        radius = config.interactionRadius,
        prompt = cutter.moving
            and "WASD: move cutter  |  Q: rotate  |  E: lock in place"
            or "E: use cutter  |  M: relocate  |  Q: rotate 90 degrees",
        cutterState = cutter,
    }
end

function CutterPlacement.beginMove(state, config)
    local cutter = CutterPlacement.ensure(state, config)
    if cutter.moving then return false end
    cutter.moving = true
    return true
end

function CutterPlacement.move(state, dx, dy, dt, config, canMove)
    local cutter = CutterPlacement.ensure(state, config)
    if not cutter.moving then return false end
    cutter.inMotion = dx ~= 0 or dy ~= 0
    if not cutter.inMotion then return false end
    local length = math.sqrt(dx * dx + dy * dy)
    local nextX = cutter.x + dx / length * config.speed * dt
    local nextY = cutter.y + dy / length * config.speed * dt
    if not canMove(nextX, nextY) then return false end
    cutter.x, cutter.y = nextX, nextY
    return true
end

function CutterPlacement.rotate(state, config)
    local cutter = CutterPlacement.ensure(state, config)
    cutter.direction = clockwise[cutter.direction]
    return true, cutter.direction
end

function CutterPlacement.place(state, config)
    local cutter = CutterPlacement.ensure(state, config)
    if not cutter.moving then return false end
    cutter.moving, cutter.inMotion = false, false
    return true
end

function CutterPlacement.snapshot(state, config)
    local cutter = CutterPlacement.ensure(state, config)
    return {
        x = cutter.x,
        y = cutter.y,
        direction = cutter.direction,
        frame = directionFrames[cutter.direction],
        moving = cutter.moving,
        inMotion = cutter.inMotion,
    }
end

return CutterPlacement
