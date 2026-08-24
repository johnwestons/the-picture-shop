local Config = require("src.config")

local Navigation = {}

local function whiteAt(mask, x, y)
    local width, height = mask:getDimensions()
    local pixelX = math.floor(x / Config.baseWidth * width)
    local pixelY = math.floor(y / Config.baseHeight * height)
    if pixelX < 0 or pixelY < 0 or pixelX >= width or pixelY >= height then
        return false
    end
    local red, green, blue = mask:getPixel(pixelX, pixelY)
    return red > 0.9 and green > 0.9 and blue > 0.9
end

local function outsideFixedObstacle(x, y, obstacles)
    for _, obstacle in ipairs(obstacles or {}) do
        local dx = x - obstacle.x
        local dy = y - obstacle.y
        local blocked
        if obstacle.halfWidth and obstacle.halfHeight then
            blocked = math.abs(dx) < obstacle.halfWidth and math.abs(dy) < obstacle.halfHeight
        else
            blocked = dx * dx + dy * dy < obstacle.radius * obstacle.radius
        end
        if blocked then
            return false
        end
    end
    return true
end

local function feetAreOnMask(mask, x, y)
    if not mask then
        return x > 55 and x < Config.baseWidth - 55 and y > 90 and y < Config.baseHeight - 45
    end
    return whiteAt(mask, x - 6, y)
        and whiteAt(mask, x, y + 2)
        and whiteAt(mask, x + 6, y)
end

function Navigation.isWalkable(assets, x, y, obstacles)
    local mask = assets.getData("walkmask")
    return feetAreOnMask(mask, x, y) and outsideFixedObstacle(x, y, obstacles)
end

function Navigation.isAreaWalkable(assets, x, y, halfWidth, halfHeight)
    local mask = assets.getData("walkmask")
    halfWidth, halfHeight = math.max(0, halfWidth or 0), math.max(0, halfHeight or 0)
    local samples = {
        { 0, 0 },
        { -halfWidth, -halfHeight }, { halfWidth, -halfHeight },
        { -halfWidth, halfHeight }, { halfWidth, halfHeight },
        { -halfWidth, 0 }, { halfWidth, 0 },
        { 0, -halfHeight }, { 0, halfHeight },
    }
    for _, offset in ipairs(samples) do
        if not feetAreOnMask(mask, x + offset[1], y + offset[2]) then return false end
    end
    return true
end

-- A saved game or a newly parked object can occasionally leave an actor just
-- inside a collision circle. Allow movement that strictly increases distance
-- from every overlapping obstacle so the player can always walk free.
function Navigation.canMoveFrom(assets, currentX, currentY, nextX, nextY, obstacles)
    local mask = assets.getData("walkmask")
    if not feetAreOnMask(mask, nextX, nextY) then return false end
    for _, obstacle in ipairs(obstacles or {}) do
        local currentDx, currentDy = currentX - obstacle.x, currentY - obstacle.y
        local nextDx, nextDy = nextX - obstacle.x, nextY - obstacle.y
        if obstacle.halfWidth and obstacle.halfHeight then
            local currentInside = math.abs(currentDx) < obstacle.halfWidth and math.abs(currentDy) < obstacle.halfHeight
            local nextInside = math.abs(nextDx) < obstacle.halfWidth and math.abs(nextDy) < obstacle.halfHeight
            local currentDepth = math.min(obstacle.halfWidth - math.abs(currentDx), obstacle.halfHeight - math.abs(currentDy))
            local nextDepth = math.min(obstacle.halfWidth - math.abs(nextDx), obstacle.halfHeight - math.abs(nextDy))
            if nextInside and not (currentInside and nextDepth < currentDepth) then return false end
        else
            local radiusSquared = obstacle.radius * obstacle.radius
            local currentDistance = currentDx * currentDx + currentDy * currentDy
            local nextDistance = nextDx * nextDx + nextDy * nextDy
            if nextDistance < radiusSquared
                and not (currentDistance < radiusSquared and nextDistance > currentDistance + 0.01)
            then
                return false
            end
        end
    end
    return true
end

function Navigation.canMoveAreaFrom(assets, currentX, currentY, nextX, nextY,
    halfWidth, halfHeight, obstacles)
    if not Navigation.canMoveFrom(assets, currentX, currentY, nextX, nextY, obstacles) then
        return false
    end
    return Navigation.isAreaWalkable(assets, nextX, nextY, halfWidth, halfHeight)
end

return Navigation
