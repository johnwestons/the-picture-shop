local Placement = {}
local frames = { northwest = 1, northeast = 2, southwest = 3, southeast = 4 }
local clockwise = { northwest = "northeast", northeast = "southeast", southeast = "southwest", southwest = "northwest" }
local operatorSigns = { northwest = {1, 1}, northeast = {-1, 1}, southwest = {1, -1}, southeast = {-1, -1} }

function Placement.defaultState(config)
    return { x = config.spawnX, y = config.spawnY, direction = config.defaultDirection or "northwest",
        moving = false, inMotion = false }
end

function Placement.ensure(state, config)
    if type(state.windmill) ~= "table" then state.windmill = Placement.defaultState(config) end
    local item = state.windmill
    item.x = type(item.x) == "number" and item.x or config.spawnX
    item.y = type(item.y) == "number" and item.y or config.spawnY
    item.direction = frames[item.direction] and item.direction or config.defaultDirection or "northwest"
    item.moving, item.inMotion = item.moving == true, item.inMotion == true
    return item
end

function Placement.frame(state, config) return frames[Placement.ensure(state, config).direction] end
function Placement.operatorPosition(state, config)
    local item, sign = Placement.ensure(state, config)
    sign = operatorSigns[item.direction]
    return item.x + sign[1] * config.operatorDistanceX, item.y + sign[2] * config.operatorDistanceY
end
function Placement.obstacle(state, config)
    local item = Placement.ensure(state, config)
    if item.moving then return nil end
    return { x = item.x, y = item.y - 8, halfWidth = config.collisionHalfWidth,
        halfHeight = config.collisionHalfHeight }
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
    item._relocationOrigin = { x = item.x, y = item.y, direction = item.direction }
    item.moving = true
    return true
end
function Placement.move(state, dx, dy, dt, config, canMove)
    local item = Placement.ensure(state, config)
    if not item.moving then return false end
    item.inMotion = false
    if dx == 0 and dy == 0 then return false end
    local length = math.sqrt(dx * dx + dy * dy)
    local x = item.x + dx / length * config.speed * dt
    local y = item.y + dy / length * config.speed * dt
    if x == item.x and y == item.y then return false end
    if not canMove(x, y) then return false end
    item.x, item.y = x, y
    item.inMotion = true
    return true
end
function Placement.rotate(state, config)
    local item = Placement.ensure(state, config)
    item.direction = clockwise[item.direction]
    return true, item.direction
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
        moving = item.moving, inMotion = item.inMotion }
end

return Placement
