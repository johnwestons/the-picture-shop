local Placement = {}
local MachineRotation = require("src.machine_rotation")
local directions = {
    northwest = true, north = true, northeast = true, east = true,
    southeast = true, south = true, southwest = true, west = true,
}

function Placement.defaultState(config)
    local direction = config.defaultDirection or "northwest"
    return {
        x = config.spawnX,
        y = config.spawnY,
        direction = direction,
        rotationIndex = MachineRotation.frameForDirection("wrapper", direction) or 1,
        moving = false,
        inMotion = false,
    }
end

function Placement.ensure(state, config)
    if type(state.wrapper) ~= "table" then state.wrapper = Placement.defaultState(config) end
    local wrapper = state.wrapper
    wrapper.x = type(wrapper.x) == "number" and wrapper.x or config.spawnX
    wrapper.y = type(wrapper.y) == "number" and wrapper.y or config.spawnY
    wrapper.direction = directions[wrapper.direction] and wrapper.direction
        or config.defaultDirection or "northwest"
    wrapper.rotationIndex = MachineRotation.normalizedFrame("wrapper", wrapper,
        config.defaultDirection or "northwest")
    wrapper.direction = MachineRotation.directionForFrame("wrapper", wrapper.rotationIndex)
    wrapper.moving = wrapper.moving == true
    wrapper.inMotion = wrapper.inMotion == true
    return wrapper
end

function Placement.rotationFrameFor(placement)
    return MachineRotation.frameFor("wrapper", placement)
end

function Placement.frame(state, config)
    return Placement.rotationFrameFor(Placement.ensure(state, config))
end

function Placement.operatorPosition(state, config)
    local item = Placement.ensure(state, config)
    local signX, signY = MachineRotation.operatorVector("wrapper", item.rotationIndex)
    return item.x + signX * config.operatorDistanceX,
        item.y + signY * config.operatorDistanceY
end

function Placement.obstacle(state, config)
    local item = Placement.ensure(state, config)
    if item.moving then return nil end
    return require("src.floor_footprint").at(item.x, item.y, config)
end

function Placement.interaction(player, state, config, palletJackOperating)
    local item = Placement.ensure(state, config)
    return {
        x = item.moving and player.x or item.x,
        y = item.moving and player.y or item.y,
        radius = config.interactionRadius,
        prompt = item.moving and "WASD: move wrapper with pallet jack  |  Q: rotate  |  E: lock in place"
            or (palletJackOperating and "E: use skid wrapper  |  M: relocate with pallet jack"
                or "E: use skid wrapper  |  Operate pallet jack to relocate"),
    }
end

function Placement.beginMove(state, config)
    local item = Placement.ensure(state, config)
    if item.moving then return false end
    item._relocationOrigin = {
        x = item.x,
        y = item.y,
        direction = item.direction,
        rotationIndex = item.rotationIndex,
    }
    item.moving = true
    return true
end

function Placement.move(state, dx, dy, dt, config, canMove)
    local item = Placement.ensure(state, config)
    if not item.moving then return false end
    item.inMotion = require("src.placement_motion").move(item, dx, dy, dt, config.speed, canMove)
    return item.inMotion
end

function Placement.rotate(state, config)
    local item = Placement.ensure(state, config)
    item.rotationIndex = item.rotationIndex % 64 + 1
    item.direction = MachineRotation.directionForFrame("wrapper", item.rotationIndex)
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
    return {
        x = item.x,
        y = item.y,
        direction = item.direction,
        frame = item.rotationIndex,
        rotationIndex = item.rotationIndex,
        moving = item.moving,
        inMotion = item.inMotion,
    }
end

return Placement
