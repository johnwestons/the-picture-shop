local Placement = {}
local frames = { northwest = 1, northeast = 2, southwest = 3, southeast = 4 }
local clockwise = { northwest = "northeast", northeast = "southeast", southeast = "southwest", southwest = "northwest" }
local operatorSigns = { northwest = {1, 1}, northeast = {-1, 1}, southwest = {1, -1}, southeast = {-1, -1} }

function Placement.defaultState(config)
    return { x = config.spawnX, y = config.spawnY, direction = config.defaultDirection or "northwest", moving = false, inMotion = false }
end

function Placement.ensure(state, config)
    if type(state.wrapper) ~= "table" then state.wrapper = Placement.defaultState(config) end
    local wrapper = state.wrapper
    wrapper.x = type(wrapper.x) == "number" and wrapper.x or config.spawnX
    wrapper.y = type(wrapper.y) == "number" and wrapper.y or config.spawnY
    wrapper.direction = frames[wrapper.direction] and wrapper.direction or config.defaultDirection or "northwest"
    wrapper.moving = wrapper.moving == true
    wrapper.inMotion = wrapper.inMotion == true
    return wrapper
end

function Placement.frame(state, config) return frames[Placement.ensure(state, config).direction] end
function Placement.operatorPosition(state, config) local item = Placement.ensure(state, config); local sign = operatorSigns[item.direction]; return item.x + sign[1] * config.operatorDistanceX, item.y + sign[2] * config.operatorDistanceY end
function Placement.obstacle(state, config) local item = Placement.ensure(state, config); if item.moving then return nil end; return { x = item.x, y = item.y - 6, halfWidth = config.collisionHalfWidth, halfHeight = config.collisionHalfHeight } end
function Placement.interaction(player, state, config)
    local item = Placement.ensure(state, config)
    return { x = item.moving and player.x or item.x, y = item.moving and player.y or item.y, radius = config.interactionRadius,
        prompt = item.moving and "WASD: move wrapper  |  Q: rotate  |  E: lock in place" or "E: use skid wrapper  |  M: relocate  |  Q: rotate 90 degrees" }
end
function Placement.beginMove(state, config) local item = Placement.ensure(state, config); if item.moving then return false end; item.moving = true; return true end
function Placement.move(state, dx, dy, dt, config, canMove) local item = Placement.ensure(state, config); if not item.moving then return false end; item.inMotion = dx ~= 0 or dy ~= 0; if not item.inMotion then return false end; local length = math.sqrt(dx * dx + dy * dy); local x, y = item.x + dx / length * config.speed * dt, item.y + dy / length * config.speed * dt; if not canMove(x, y) then return false end; item.x, item.y = x, y; return true end
function Placement.rotate(state, config) local item = Placement.ensure(state, config); item.direction = clockwise[item.direction]; return true, item.direction end
function Placement.place(state, config) local item = Placement.ensure(state, config); if not item.moving then return false end; item.moving, item.inMotion = false, false; return true end
function Placement.snapshot(state, config) local item = Placement.ensure(state, config); return { x=item.x, y=item.y, direction=item.direction, frame=frames[item.direction], moving=item.moving, inMotion=item.inMotion } end
return Placement
