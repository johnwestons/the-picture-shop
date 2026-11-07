-- The established 960x678 warehouse floor is the source of truth for this
-- experimental 3D registration. The default orthographic projection maps
-- every floor and wall vertex back to the same pixel in the authored sprite.
local Registration = require("src.warehouse_registration")
local Geometry = {}

Geometry.WIDTH, Geometry.HEIGHT = 960, 678
Geometry.CENTER_Y = 210
Geometry.SCALE = 48 * math.sqrt(2)
Geometry.ELEVATION = math.rad(30)
Geometry.YAW = -math.pi * 0.75

local floorEdge = Registration.floorEdges.warehouse

function Geometry.edge(x)
    if x <= floorEdge[1][1] then return floorEdge[1][2] end
    for i = 2, #floorEdge do
        local a, b = floorEdge[i - 1], floorEdge[i]
        if x <= b[1] then
            return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
        end
    end
    return floorEdge[#floorEdge][2]
end

function Geometry.floorPoint(sx, sy)
    local difference = (sx - Geometry.WIDTH * 0.5) / 48
    local sum = (sy - Geometry.CENTER_Y) / 24
    return (sum + difference) * 0.5, (sum - difference) * 0.5
end

function Geometry.sourcePoint(x, z, height)
    return Geometry.WIDTH * 0.5 + 48 * (x - z),
        Geometry.CENTER_Y + 24 * (x + z)
            - height * Geometry.SCALE * math.cos(Geometry.ELEVATION)
end

function Geometry.floorContains(x, z)
    local sx, sy = Geometry.sourcePoint(x, z, 0)
    return sx >= 8 and sx <= 952 and sy >= Geometry.edge(sx) + 4
        and sy <= Geometry.HEIGHT - 8
end

local function vertex(sx, sy, height)
    local x, z = Geometry.floorPoint(sx, sy + height * Geometry.SCALE * math.cos(Geometry.ELEVATION))
    return {x, z, height, sx / Geometry.WIDTH, sy / Geometry.HEIGHT}
end

local function emitQuad(vertices, a, b, c, d)
    for _, p in ipairs({a, b, c, a, c, d}) do vertices[#vertices + 1] = p end
end

function Geometry.meshes()
    local floor, rear = {}, {}
    -- Subdivide at every registered change in the wall/floor contact line.
    -- Extra segments improve perspective interpolation when the camera moves.
    for i = 2, #floorEdge do
        local a, b = floorEdge[i - 1], floorEdge[i]
        local count = math.max(1, math.ceil((b[1] - a[1]) / 24))
        for step = 0, count - 1 do
            local x0 = a[1] + (b[1] - a[1]) * step / count
            local x1 = a[1] + (b[1] - a[1]) * (step + 1) / count
            local y0, y1 = Geometry.edge(x0), Geometry.edge(x1)
            local fx0, fz0 = Geometry.floorPoint(x0, y0)
            local fx1, fz1 = Geometry.floorPoint(x1, y1)
            local h0 = y0 / (Geometry.SCALE * math.cos(Geometry.ELEVATION))
            local h1 = y1 / (Geometry.SCALE * math.cos(Geometry.ELEVATION))
            emitQuad(floor, vertex(x0, y0, 0), vertex(x1, y1, 0),
                vertex(x1, Geometry.HEIGHT, 0), vertex(x0, Geometry.HEIGHT, 0))
            -- The wall curtain follows the source art's actual floor contact.
            -- Its UVs preserve the painted racks, dock, beams, and office.
            emitQuad(rear,
                {fx0, fz0, h0, x0 / Geometry.WIDTH, 0},
                {fx1, fz1, h1, x1 / Geometry.WIDTH, 0},
                {fx1, fz1, 0, x1 / Geometry.WIDTH, y1 / Geometry.HEIGHT},
                {fx0, fz0, 0, x0 / Geometry.WIDTH, y0 / Geometry.HEIGHT})
        end
    end
    return floor, rear
end

function Geometry.enclosure()
    local height = 4.7
    local left, right, front, ceiling, upper = {}, {}, {}, {}, {}
    local function wall(vertices, a, b, u0, u1)
        emitQuad(vertices,
            {a[1],a[2],height,u0,0.01}, {b[1],b[2],height,u1,0.01},
            {b[1],b[2],0,u1,0.25}, {a[1],a[2],0,u0,0.25})
    end
    local lx0,lz0=Geometry.floorPoint(0,Geometry.edge(0))
    local lx1,lz1=Geometry.floorPoint(0,Geometry.HEIGHT)
    local rx0,rz0=Geometry.floorPoint(Geometry.WIDTH,Geometry.edge(Geometry.WIDTH))
    local rx1,rz1=Geometry.floorPoint(Geometry.WIDTH,Geometry.HEIGHT)
    wall(left,{lx0,lz0},{lx1,lz1},0.01,0.17)
    wall(right,{rx1,rz1},{rx0,rz0},0.81,0.99)
    wall(front,{lx1,lz1},{rx1,rz1},0.15,0.75)
    for i=2,#floorEdge do
        local a,b=floorEdge[i-1],floorEdge[i]
        local count=math.max(1,math.ceil((b[1]-a[1])/24))
        for step=0,count-1 do
            local x0=a[1]+(b[1]-a[1])*step/count
            local x1=a[1]+(b[1]-a[1])*(step+1)/count
            local y0,y1=Geometry.edge(x0),Geometry.edge(x1)
            local fx0,fz0=Geometry.floorPoint(x0,y0)
            local fx1,fz1=Geometry.floorPoint(x1,y1)
            local h0=y0/(Geometry.SCALE*math.cos(Geometry.ELEVATION))
            local h1=y1/(Geometry.SCALE*math.cos(Geometry.ELEVATION))
            emitQuad(upper,
                {fx0,fz0,height,x0/Geometry.WIDTH,0.055},
                {fx1,fz1,height,x1/Geometry.WIDTH,0.055},
                {fx1,fz1,h1,x1/Geometry.WIDTH,0},
                {fx0,fz0,h0,x0/Geometry.WIDTH,0})
        end
    end
    local floor = Geometry.meshes()
    for _,v in ipairs(floor) do
        ceiling[#ceiling+1]={v[1],v[2],height,0,0}
    end
    return left,right,front,ceiling,upper
end

function Geometry.projectOrbit(x, z, height, camera, width, canvasHeight)
    local dx, dz = x - camera.x, z - camera.z
    local c, s = math.cos(camera.yaw), math.sin(camera.yaw)
    local right, forward = -dx * s + dz * c, dx * c + dz * s
    local scale = Geometry.SCALE * camera.zoom * width / Geometry.WIDTH
    return width * 0.5 + right * scale,
        canvasHeight * 0.5 + (Geometry.CENTER_Y - Geometry.HEIGHT * 0.5)
            * canvasHeight / Geometry.HEIGHT * camera.zoom
            + (-forward * math.sin(camera.elevation) - height * math.cos(camera.elevation)) * scale
end

return Geometry
