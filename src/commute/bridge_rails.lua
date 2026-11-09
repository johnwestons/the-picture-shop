-- Painted timber bridge rails projected as camera-relative 2D sprite meshes.
-- Road support and rail collision remain owned by roads.lua.
local M = require('src.commute.vendor.mathx')

local Rails = {
    SPAN_METERS = 2.8,
    HEIGHT_METERS = 0.9,
}
Rails.__index = Rails

local SIDES = {-1, 1}

local function pointOnSide(group, distance, side)
    local traversed = 0
    for index, segment in ipairs(group.segments) do
        local endDistance = traversed + segment.len
        if distance < endDistance - 1e-8 or index == #group.segments then
            local t = M.clamp((distance - traversed) / segment.len, 0, 1)
            local x = M.lerp(segment.a.x, segment.b.x, t)
            local z = M.lerp(segment.a.z, segment.b.z, t)
            local h = M.lerp(segment.a.h, segment.b.h, t)
            local offset = side * segment.width * 0.5
            return {
                x = x + segment.nx * offset,
                z = z + segment.nz * offset,
                h = h,
            }
        end
        traversed = endDistance
    end
    error('Cannot place a bridge rail on an empty span')
end

function Rails.layout(roads, spanMeters)
    spanMeters = spanMeters or Rails.SPAN_METERS
    local groups, current = {}, nil
    for _, segment in ipairs(roads.segments) do
        if segment.bridge then
            if not current or current.id ~= segment.id then
                current = {id = segment.id, segments = {}, length = 0}
                groups[#groups + 1] = current
            end
            current.segments[#current.segments + 1] = segment
            current.length = current.length + segment.len
        else
            current = nil
        end
    end

    local pieces = {}
    for _, group in ipairs(groups) do
        local count = math.max(1, math.ceil(group.length / spanMeters))
        local spacing = group.length / count
        for bay = 1, count do
            local fromDistance = (bay - 1) * spacing
            local toDistance = bay * spacing
            for _, side in ipairs(SIDES) do
                local a = pointOnSide(group, fromDistance, side)
                local b = pointOnSide(group, toDistance, side)
                local center = pointOnSide(group, (fromDistance + toDistance) * 0.5, side)
                pieces[#pieces + 1] = {
                    rail = true,
                    bridgeId = group.id,
                    bay = bay,
                    side = side,
                    a = a,
                    b = b,
                    center = center,
                    spacing = spacing,
                    spanLength = group.length,
                }
            end
        end
    end
    return pieces
end

function Rails.project(piece, camera)
    local a, b = piece.a, piece.b
    local ax, ay = camera:screen(a.x, a.z, a.h)
    local bx, by = camera:screen(b.x, b.z, b.h)
    local atx, aty = camera:screen(a.x, a.z, a.h + Rails.HEIGHT_METERS)
    local btx, bty = camera:screen(b.x, b.z, b.h + Rails.HEIGHT_METERS)
    return {
        {atx, aty, 0, 0},
        {ax, ay, 0, 1},
        {bx, by, 1, 1},
        {atx, aty, 0, 0},
        {bx, by, 1, 1},
        {btx, bty, 1, 0},
    }
end

function Rails.new(world)
    local image = love.graphics.newImage('assets/commute/bridge/rail-bay.png')
    assert(image:getWidth() == 2048 and image:getHeight() == 496, 'Invalid bridge rail sprite')
    image:setFilter('linear', 'linear')
    local vertices = Rails.project({
        a = {x = 0, z = 0, h = 0},
        b = {x = 1, z = 0, h = 0},
    }, {screen = function(_, x, z, h) return x, z - h end})
    local mesh = love.graphics.newMesh({
        {'VertexPosition', 'float', 2},
        {'VertexTexCoord', 'float', 2},
    }, vertices, 'triangles', 'stream')
    mesh:setTexture(image)
    return setmetatable({image = image, mesh = mesh, pieces = Rails.layout(world.roads)}, Rails)
end

function Rails:visible(camera, radius)
    local visible = {}
    for _, piece in ipairs(self.pieces) do
        local center = piece.center
        if M.length(center.x - camera.centerX, center.z - camera.centerZ) <= radius + 2 then
            piece.depth = camera:depth(center.x, center.z, center.h)
            visible[#visible + 1] = piece
        end
    end
    return visible
end

function Rails:draw(piece, camera, alpha)
    self.mesh:setVertices(Rails.project(piece, camera))
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(self.mesh)
    love.graphics.setColor(1, 1, 1, 1)
end

function Rails:release()
    self.mesh:release()
    self.image:release()
end

return Rails
