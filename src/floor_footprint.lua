-- Ground footprints, independent of the height/transparent canvas of the art.
local Footprint = {}

function Footprint.at(x, y, config)
    return { x = x, y = y + (config.collisionOffsetY or -8),
        halfWidth = config.collisionHalfWidth, halfHeight = config.collisionHalfHeight,
        shape = "diamond" }
end

local function support(shape, x, y, width, height)
    local horizontal, vertical = math.abs(x) * width, math.abs(y) * height
    return shape == "diamond" and math.max(horizontal, vertical) or horizontal + vertical
end

-- Minkowski expansion: a diamond moving beside a rectangle (or another
-- diamond) retains its sloped edges instead of acquiring empty blocked corners.
function Footprint.expand(obstacle, mover)
    local result = {}
    for key, value in pairs(obstacle) do result[key] = value end
    local width, height = obstacle.halfWidth, obstacle.halfHeight
    local mx, my = mover.x or 0, mover.y or 0
    if not width or not height then
        result.radius = obstacle.radius + math.max(mx, my)
        return result
    end
    local axes = { {1, 0}, {0, 1} }
    local function diamondAxes(w, h)
        if w > 0 and h > 0 then
            axes[#axes + 1] = {h, w}
            axes[#axes + 1] = {h, -w}
        end
    end
    if obstacle.shape == "diamond" then diamondAxes(width, height) end
    if mover.shape == "diamond" then diamondAxes(mx, my) end
    result.planes = {}
    for _, axis in ipairs(axes) do
        local length = math.sqrt(axis[1]^2 + axis[2]^2)
        local nx, ny = axis[1] / length, axis[2] / length
        result.planes[#result.planes + 1] = { nx = nx, ny = ny,
            limit = support(obstacle.shape, nx, ny, width, height)
                + support(mover.shape, nx, ny, mx, my) }
    end
    result.halfWidth, result.halfHeight = width + mx, height + my
    return result
end

function Footprint.penetration(obstacle, x, y)
    local dx, dy = x - obstacle.x, y - obstacle.y
    if obstacle.planes then
        local depth = math.huge
        for _, plane in ipairs(obstacle.planes) do
            depth = math.min(depth, plane.limit - math.abs(dx * plane.nx + dy * plane.ny))
        end
        return depth
    end
    if obstacle.halfWidth and obstacle.halfHeight then
        local depth = math.min(obstacle.halfWidth - math.abs(dx), obstacle.halfHeight - math.abs(dy))
        if obstacle.shape == "diamond" then
            local w, h = obstacle.halfWidth, obstacle.halfHeight
            depth = math.min(depth, (w*h - math.abs(dx)*h - math.abs(dy)*w)
                / math.sqrt(w*w + h*h))
        end
        return depth
    end
    return obstacle.radius - math.sqrt(dx*dx + dy*dy)
end

function Footprint.vertices(footprint)
    local x, y, w, h = footprint.x, footprint.y, footprint.halfWidth, footprint.halfHeight
    if footprint.shape == "diamond" then return {x,y-h, x+w,y, x,y+h, x-w,y} end
    return {x-w,y-h, x+w,y-h, x+w,y+h, x-w,y+h}
end

local function segmentDistanceSquared(x, y, ax, ay, bx, by)
    local dx, dy = bx-ax, by-ay
    local t = math.max(0, math.min(1, ((x-ax)*dx + (y-ay)*dy) / (dx*dx + dy*dy)))
    return (x-ax-t*dx)^2 + (y-ay-t*dy)^2
end

function Footprint.pointDistanceSquared(x, y, footprint)
    if Footprint.penetration(footprint, x, y) >= 0 then return 0 end
    local vertices, distance = Footprint.vertices(footprint), math.huge
    for i = 1, #vertices, 2 do
        local j = i + 2 > #vertices and 1 or i + 2
        distance = math.min(distance, segmentDistanceSquared(x, y,
            vertices[i], vertices[i+1], vertices[j], vertices[j+1]))
    end
    return distance
end

function Footprint.distanceSquared(left, right)
    local expanded = Footprint.expand(left, {x=right.halfWidth,y=right.halfHeight,shape=right.shape})
    if Footprint.penetration(expanded, right.x, right.y) >= 0 then return 0 end
    local distance = math.huge
    for _, pair in ipairs({{left,right},{right,left}}) do
        local vertices = Footprint.vertices(pair[1])
        for i=1,#vertices,2 do
            distance = math.min(distance, Footprint.pointDistanceSquared(vertices[i],vertices[i+1],pair[2]))
        end
    end
    return distance
end

return Footprint
