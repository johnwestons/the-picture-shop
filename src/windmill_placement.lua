local Placement = {}
local MachineRotation = require("src.machine_rotation")
local frames = { northwest = 1, northeast = 2, southwest = 3, southeast = 4 }

function Placement.defaultState(config)
    local direction = config.defaultDirection or "northwest"
    return { x = config.spawnX, y = config.spawnY, direction = direction,
        rotationIndex = MachineRotation.frameForDirection("windmill", direction) or 1,
        moving = false, inMotion = false }
end

function Placement.ensure(state, config)
    if type(state.windmill) ~= "table" then state.windmill = Placement.defaultState(config) end
    local item = state.windmill
    item.x = type(item.x) == "number" and item.x or config.spawnX
    item.y = type(item.y) == "number" and item.y or config.spawnY
    item.direction = frames[item.direction] and item.direction or config.defaultDirection or "northwest"
    item.rotationIndex = MachineRotation.normalizedFrame("windmill", item, config.defaultDirection or "northwest")
    item.direction = MachineRotation.directionForFrame("windmill", item.rotationIndex)
    item.moving, item.inMotion = item.moving == true, item.inMotion == true
    return item
end

function Placement.frame(state, config) return frames[Placement.ensure(state, config).direction] end
function Placement.rotationFrameFor(placement) return MachineRotation.frameFor("windmill", placement) end
function Placement.operatorPosition(state, config)
    local item = Placement.ensure(state, config)
    local signX, signY = MachineRotation.operatorVector("windmill", item.rotationIndex)
    return item.x + signX * config.operatorDistanceX, item.y + signY * config.operatorDistanceY
end
function Placement.obstacle(state, config)
    local item = Placement.ensure(state, config)
    if item.moving then return nil end
    return require("src.floor_footprint").at(item.x, item.y, config)
end
function Placement.interaction(player, state, config, palletJackOperating)
    local item = Placement.ensure(state, config)
    return { x = item.moving and player.x or item.x,
        y = item.moving and player.y or item.y,
        radius = config.interactionRadius,
        prompt = item.moving
            and "WASD: move Windmill with pallet jack  |  Q: rotate  |  E: lock in place"
            or (palletJackOperating and "E: operate Windmill  |  M: relocate with pallet jack"
                or "E: operate Windmill  |  Operate pallet jack to relocate") }
end
function Placement.beginMove(state, config)
    local item = Placement.ensure(state, config)
    if item.moving then return false end
    item._relocationOrigin = { x = item.x, y = item.y, direction = item.direction,
        rotationIndex = item.rotationIndex }
    item.moving = true
    return true
end
function Placement.move(state, dx, dy, dt, config, canMove)
    local item = Placement.ensure(state, config)
    if not item.moving then return false end
    item.inMotion = false
    if dx == 0 and dy == 0 then return false end
    if not require("src.placement_motion").move(item,dx,dy,dt,config.speed,canMove) then return false end
    item.inMotion = true
    return true
end
function Placement.rotate(state, config)
    local item = Placement.ensure(state, config)
    item.rotationIndex = item.rotationIndex % 64 + 1
    item.direction = MachineRotation.directionForFrame("windmill", item.rotationIndex)
    return true, item.direction, item.rotationIndex
end
function Placement.place(state, config)
    local item = Placement.ensure(state, config)
    if not item.moving then return false end
    item.moving, item.inMotion = false, false
    item._relocationOrigin = nil
    return true
end
function Placement.snapshot(state, config)
    local item = Placement.ensure(state, config)
    return { x = item.x, y = item.y, direction = item.direction, frame = frames[item.direction],
        rotationIndex = item.rotationIndex, moving = item.moving, inMotion = item.inMotion }
end

return Placement
