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

-- Collision planes depend on dimensions, never position or ownership. Every
-- worker can share this immutable geometry while keeping fresh world contacts.
-- Bound the cache so unusual imported dimensions cannot grow it indefinitely.
local planeCache, planeCount = {}, 0
local function planeBucket(width, height, mx, my)
    local heights = planeCache[width]
    if not heights then heights={};planeCache[width]=heights end
    local moverWidths = heights[height]
    if not moverWidths then moverWidths={};heights[height]=moverWidths end
    local moverHeights = moverWidths[mx]
    if not moverHeights then moverHeights={};moverWidths[mx]=moverHeights end
    local bucket = moverHeights[my]
    if not bucket then bucket={};moverHeights[my]=bucket end
    return bucket
end
local function planesFor(width, height, shape, mx, my, moverShape)
    local key = (shape == "diamond" and 1 or 0) + (moverShape == "diamond" and 2 or 0)
    local bucket = planeBucket(width,height,mx,my)
    local planes = bucket[key]
    if planes then return planes end
    planes = { {nx=1,ny=0,limit=width+mx}, {nx=0,ny=1,limit=height+my} }
    local function diamondAxes(w, h)
        if w <= 0 or h <= 0 then return end
        local length = math.sqrt(w*w+h*h)
        local nx, ny = h/length, w/length
        local limit = support(shape,nx,ny,width,height) + support(moverShape,nx,ny,mx,my)
        planes[#planes+1] = {nx=nx,ny=ny,limit=limit}
        planes[#planes+1] = {nx=nx,ny=-ny,limit=limit}
    end
    if shape == "diamond" then diamondAxes(width,height) end
    if moverShape == "diamond" then diamondAxes(mx,my) end
    if planeCount >= 128 then
        planeCache, planeCount = {}, 0
        bucket = planeBucket(width,height,mx,my)
    end
    bucket[key], planeCount = planes, planeCount + 1
    return planes
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
    result.planes = planesFor(width,height,obstacle.shape,mx,my,mover.shape)
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

-- Continuous collision for a point swept through a convex ground footprint.
-- Sampling alone can miss a thin obstacle between two valid endpoints.
function Footprint.segmentPenetrates(obstacle, x, y, nextX, nextY)
    local dx,dy=x-obstacle.x,y-obstacle.y
    local vx,vy=nextX-x,nextY-y
    if not obstacle.halfWidth or not obstacle.halfHeight then
        local squared=vx*vx+vy*vy
        local t=squared>0 and math.max(0,math.min(1,-(dx*vx+dy*vy)/squared)) or 0
        return (dx+t*vx)^2+(dy+t*vy)^2 < math.max(0,obstacle.radius-.001)^2
    end
    local planes=obstacle.planes or planesFor(obstacle.halfWidth,obstacle.halfHeight,obstacle.shape,0,0)
    local enter,leave=0,1
    for _,plane in ipairs(planes) do
        local p=dx*plane.nx+dy*plane.ny
        local v=vx*plane.nx+vy*plane.ny
        local limit=plane.limit-.001
        if math.abs(v)<.0000001 then
            if math.abs(p)>=limit then return false end
        else
            local a,b=(-limit-p)/v,(limit-p)/v
            if a>b then a,b=b,a end
            enter,leave=math.max(enter,a),math.min(leave,b)
            if enter>=leave then return false end
        end
    end
    return enter<leave
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
    if not footprint.halfWidth or not footprint.halfHeight then
        local distance = math.sqrt((x - footprint.x)^2 + (y - footprint.y)^2)
        return math.max(0, distance - (tonumber(footprint.radius) or 0))^2
    end
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
