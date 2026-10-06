local CutterPlacement = {}

local directionFrames = {
    northwest = 1,
    north = 2,
    northeast = 3,
    east = 4,
    southeast = 5,
    south = 6,
    southwest = 7,
    west = 8,
}
local clockwise = {
    northwest = "north",
    north = "northeast",
    northeast = "east",
    east = "southeast",
    southeast = "south",
    south = "southwest",
    southwest = "west",
    west = "northwest",
}
local operatorSigns = {
    northwest = { x = 1, y = 1 },
    north = { x = 0, y = 1 },
    northeast = { x = -1, y = 1 },
    east = { x = -1, y = 0 },
    southeast = { x = -1, y = -1 },
    south = { x = 0, y = -1 },
    southwest = { x = 1, y = -1 },
    west = { x = 1, y = 0 },
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
    return require("src.floor_footprint").at(cutter.x, cutter.y, config)
end

function CutterPlacement.interaction(player, state, config, palletJackOperating)
    local cutter = CutterPlacement.ensure(state, config)
    return {
        x = cutter.moving and player.x or cutter.x,
        y = cutter.moving and player.y or cutter.y,
        radius = config.interactionRadius,
        prompt = cutter.moving
            and "WASD: move cutter with pallet jack  |  Q: rotate  |  E: lock in place"
            or (palletJackOperating and "E: use cutter  |  M: relocate with pallet jack"
                or "E: use cutter  |  Operate pallet jack to relocate"),
        cutterState = cutter,
    }
end

function CutterPlacement.beginMove(state, config)
    local cutter = CutterPlacement.ensure(state, config)
    if cutter.moving then return false end
    cutter._relocationOrigin = {
        x = cutter.x,
        y = cutter.y,
        direction = cutter.direction,
    }
    cutter.moving = true
    return true
end

function CutterPlacement.move(state, dx, dy, dt, config, canMove)
    local cutter = CutterPlacement.ensure(state, config)
    if not cutter.moving then return false end
    cutter.inMotion = false
    if dx == 0 and dy == 0 then return false end
    if not require("src.placement_motion").move(cutter,dx,dy,dt,config.speed,canMove) then return false end
    cutter.inMotion = true
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
    cutter._relocationOrigin = nil
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
