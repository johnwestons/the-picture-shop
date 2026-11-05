local CutterPlacement = {}
local MachineRotation = require("src.machine_rotation")

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
function CutterPlacement.defaultState(config)
    local direction = config.defaultDirection or "northwest"
    return {
        x = config.spawnX,
        y = config.spawnY,
        direction = direction,
        rotationIndex = MachineRotation.frameForDirection("cutter", direction) or 1,
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
    cutter.rotationIndex = MachineRotation.normalizedFrame("cutter", cutter, config.defaultDirection or "northwest")
    cutter.direction = MachineRotation.directionForFrame("cutter", cutter.rotationIndex)
    cutter.moving = cutter.moving == true
    cutter.inMotion = cutter.inMotion == true
    return cutter
end

function CutterPlacement.frame(state, config)
    return directionFrames[CutterPlacement.ensure(state, config).direction]
end

function CutterPlacement.rotationFrameFor(placement)
    return MachineRotation.frameFor("cutter", placement)
end

function CutterPlacement.operatorPosition(state, config)
    local cutter = CutterPlacement.ensure(state, config)
    local signX, signY = MachineRotation.operatorVector("cutter", cutter.rotationIndex)
    return cutter.x + signX * config.operatorDistanceX,
        cutter.y + signY * config.operatorDistanceY
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
        rotationIndex = cutter.rotationIndex,
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
    cutter.rotationIndex = cutter.rotationIndex % 64 + 1
    cutter.direction = MachineRotation.directionForFrame("cutter", cutter.rotationIndex)
    return true, cutter.direction, cutter.rotationIndex
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
        rotationIndex = cutter.rotationIndex,
        moving = cutter.moving,
        inMotion = cutter.inMotion,
    }
end

return CutterPlacement
