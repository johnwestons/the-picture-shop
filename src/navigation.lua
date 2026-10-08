local Config = require("src.config")
local Footprint = require("src.floor_footprint")

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
        if Footprint.penetration(obstacle, x, y) > 0.001 then
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
local function clearsObstaclesFrom(currentX, currentY, nextX, nextY, obstacles)
    for _, obstacle in ipairs(obstacles or {}) do
        local currentDx, currentDy = currentX - obstacle.x, currentY - obstacle.y
        local nextDx, nextDy = nextX - obstacle.x, nextY - obstacle.y
        if obstacle.halfWidth and obstacle.halfHeight then
            local currentDepth = Footprint.penetration(obstacle, currentX, currentY)
            local nextDepth = Footprint.penetration(obstacle, nextX, nextY)
            local currentInside, nextInside = currentDepth > 0.001, nextDepth > 0.001
            local movingAway = nextDx * nextDx + nextDy * nextDy
                > currentDx * currentDx + currentDy * currentDy + 0.01
            -- A wide rectangle can have the same minimum penetration while
            -- the actor slides toward its nearest escape edge. Treat that as
            -- valid escape movement so machines, jacks and players cannot be
            -- permanently trapped by overlapping saved placements.
            if nextInside and not (currentInside
                and (nextDepth < currentDepth or (nextDepth <= currentDepth + 0.001 and movingAway)))
            then return false end
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

function Navigation.canMoveFrom(assets, currentX, currentY, nextX, nextY, obstacles)
    return feetAreOnMask(assets.getData("walkmask"), nextX, nextY)
        and clearsObstaclesFrom(currentX, currentY, nextX, nextY, obstacles)
end

-- Validate the whole segment, including thin furniture and mask edges between
-- grid nodes. Recovery permits a short escape from an invalid starting pixel;
-- once on the floor the actor cannot cross a blocked mask pixel again.
function Navigation.canTraverse(assets, x, y, nextX, nextY, obstacles, recover)
    local mask = assets.getData("walkmask")
    local dx, dy = nextX - x, nextY - y
    local length = math.sqrt(dx * dx + dy * dy)
    local onFloor = feetAreOnMask(mask, x, y)
    if not onFloor and (not recover or length > 32) then return false end
    for _,obstacle in ipairs(obstacles or {}) do
        if Footprint.penetration(obstacle,x,y)<=.001
            and Footprint.segmentPenetrates(obstacle,x,y,nextX,nextY) then return false end
    end
    local stride=1
    if mask then
        local width,height=mask:getDimensions()
        stride=math.min(stride,Config.baseWidth/width,Config.baseHeight/height)*.5
    end
    local steps = math.max(1, math.ceil(length / stride))
    local previousX, previousY = x, y
    for index = 1, steps do
        local px, py = x + dx * index / steps, y + dy * index / steps
        local floor = feetAreOnMask(mask, px, py)
        if (onFloor and not floor)
            or not clearsObstaclesFrom(previousX, previousY, px, py, obstacles) then return false end
        onFloor = onFloor or floor
        previousX, previousY = px, py
    end
    return onFloor
end

function Navigation.canMoveAreaFrom(assets, currentX, currentY, nextX, nextY,
    halfWidth, halfHeight, obstacles)
    if not Navigation.canMoveFrom(assets, currentX, currentY, nextX, nextY, obstacles) then
        return false
    end
    return Navigation.isAreaWalkable(assets, nextX, nextY, halfWidth, halfHeight)
end

return Navigation
