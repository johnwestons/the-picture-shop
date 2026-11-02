-- Imagegen-painted asphalt, concrete parapets, and concrete support piers.
-- Bridge surface/support height and collision remain owned by roads.lua.
local M = require('src.commute.vendor.mathx')

local BridgeArt = {
    BAY_METERS = 4.8,
    PROFILE_METERS = 3.0,
    DECK_LINE_FROM_TOP = 0.53,
    GIRDER_DEPTH_METERS = 3.0 * (1 - 0.53),
    CAP_WIDTH_METERS = 0.48,
    CAP_OUTER_FRACTION = 0.28,
    END_BLOCK_WIDTH_METERS = 0.58,
    END_BLOCK_HEIGHT_METERS = 3.0 * 0.53,
    DECK_TEXTURE_TILE_METERS = 3.2,
    PIER_FRACTIONS = {0.33, 0.67},
}
BridgeArt.__index = BridgeArt

local SIDES = {-1, 1}
local MESH_FORMAT = {
    {'VertexPosition', 'float', 2},
    {'VertexTexCoord', 'float', 2},
}

local function finite(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function bridgeGroups(roads)
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
    return groups
end

local function pointAt(group, distance, side, extraOffset)
    local traversed = 0
    for index, segment in ipairs(group.segments) do
        local endDistance = traversed + segment.len
        if distance < endDistance - 1e-8 or index == #group.segments then
            local t = M.clamp((distance - traversed) / segment.len, 0, 1)
            local x = M.lerp(segment.a.x, segment.b.x, t)
            local z = M.lerp(segment.a.z, segment.b.z, t)
            local h = M.lerp(segment.a.h, segment.b.h, t)
            local offset = side * segment.width * 0.5 + (extraOffset or 0)
            return {x = x + segment.nx * offset, z = z + segment.nz * offset, h = h,
                width = segment.width}
        end
        traversed = endDistance
    end
    error('Cannot place bridge art on an empty span')
end

function BridgeArt.layout(roads, spanMeters, offsetMeters)
    spanMeters = spanMeters or BridgeArt.BAY_METERS
    offsetMeters = offsetMeters or 0
    local pieces = {}
    for _, group in ipairs(bridgeGroups(roads)) do
        local count = math.max(1, math.ceil(group.length / spanMeters))
        local spacing = group.length / count
        for bay = 1, count do
            local fromDistance = (bay - 1) * spacing
            local toDistance = bay * spacing
            -- The generated bay ends bevel inward slightly. Overlap neighboring
            -- billboards by 12 cm so those beveled ends never open a seam.
            local overlap = 0.12
            local drawFrom = math.max(0, fromDistance - (bay > 1 and overlap * 0.5 or 0))
            local drawTo = math.min(group.length, toDistance + (bay < count and overlap * 0.5 or 0))
            for _, side in ipairs(SIDES) do
                local a = pointAt(group, drawFrom, side, offsetMeters)
                local b = pointAt(group, drawTo, side, offsetMeters)
                local center = pointAt(group, (fromDistance + toDistance) * 0.5, side, offsetMeters)
                pieces[#pieces + 1] = {
                    bridgeSide = true, bridgeId = group.id, bay = bay, side = side,
                    a = a, b = b, center = center, spacing = spacing,
                    spanLength = group.length,
                }
            end
        end
    end
    return pieces
end

function BridgeArt.capLayout(roads)
    local caps = {}
    for _, segment in ipairs(roads.segments) do
        if segment.bridge then
            for _, side in ipairs(SIDES) do
                local offset = side * segment.width * 0.5
                local a = {x = segment.a.x + segment.nx * offset, z = segment.a.z + segment.nz * offset, h = segment.a.h}
                local b = {x = segment.b.x + segment.nx * offset, z = segment.b.z + segment.nz * offset, h = segment.b.h}
                caps[#caps + 1] = {
                    bridgeCap = true, bridgeId = segment.id, side = side,
                    a = a, b = b, nx = segment.nx, nz = segment.nz,
                    center = {x = (a.x + b.x) * 0.5, z = (a.z + b.z) * 0.5,
                        h = (a.h + b.h) * 0.5},
                    distance = segment.distance or 0, len = segment.len,
                }
            end
        end
    end
    return caps
end

function BridgeArt.endPostLayout(roads)
    local posts = {}
    for _, group in ipairs(bridgeGroups(roads)) do
        local first, last = group.segments[1], group.segments[#group.segments]
        for _, endpoint in ipairs({
            {segment = first, point = first.a, name = 'start', direction = 1},
            {segment = last, point = last.b, name = 'end', direction = -1},
        }) do
            local s, point = endpoint.segment, endpoint.point
            local length = math.max(1e-6, s.len)
            local inset = endpoint.direction * 0.12
            local tangentX, tangentZ = (s.b.x - s.a.x) / length, (s.b.z - s.a.z) / length
            for _, side in ipairs(SIDES) do
                local lateral = side * s.width * 0.5
                posts[#posts + 1] = {
                    bridgeEndPost = true, bridgeId = group.id, endName = endpoint.name,
                    side = side,
                    x = point.x + s.nx * lateral + tangentX * inset,
                    z = point.z + s.nz * lateral + tangentZ * inset,
                    h = point.h, width = BridgeArt.END_BLOCK_WIDTH_METERS,
                    height = BridgeArt.END_BLOCK_HEIGHT_METERS,
                }
            end
        end
    end
    return posts
end

local function sideVertices(piece, camera)
    local above = BridgeArt.PROFILE_METERS * BridgeArt.DECK_LINE_FROM_TOP
    local below = BridgeArt.PROFILE_METERS - above
    local a, b = piece.a, piece.b
    local atx, aty = camera:screen(a.x, a.z, a.h + above)
    local abx, aby = camera:screen(a.x, a.z, a.h - below)
    local btx, bty = camera:screen(b.x, b.z, b.h + above)
    local bbx, bby = camera:screen(b.x, b.z, b.h - below)
    return {
        {atx, aty, 0, 0}, {abx, aby, 0, 1}, {bbx, bby, 1, 1},
        {atx, aty, 0, 0}, {bbx, bby, 1, 1}, {btx, bty, 1, 0},
    }
end

function BridgeArt.projectDeck(segments, camera, tileMeters)
    tileMeters = tileMeters or BridgeArt.DECK_TEXTURE_TILE_METERS
    local vertices = {}
    for _, segment in ipairs(segments) do
        if segment.bridge then
            local width = segment.width * 0.5
            local a, b = segment.a, segment.b
            local distanceA = segment.distance or 0
            local distanceB = distanceA + segment.len
            local ax, ay = camera:screen(a.x + segment.nx * width, a.z + segment.nz * width, a.h + 0.045)
            local bx, by = camera:screen(b.x + segment.nx * width, b.z + segment.nz * width, b.h + 0.045)
            local cx, cy = camera:screen(b.x - segment.nx * width, b.z - segment.nz * width, b.h + 0.045)
            local dx, dy = camera:screen(a.x - segment.nx * width, a.z - segment.nz * width, a.h + 0.045)
            local u0, u1 = distanceA / tileMeters, distanceB / tileMeters
            local v0, v1 = width / tileMeters, -width / tileMeters
            vertices[#vertices + 1] = {ax, ay, u0, v0}
            vertices[#vertices + 1] = {bx, by, u1, v0}
            vertices[#vertices + 1] = {cx, cy, u1, v1}
            vertices[#vertices + 1] = {ax, ay, u0, v0}
            vertices[#vertices + 1] = {cx, cy, u1, v1}
            vertices[#vertices + 1] = {dx, dy, u0, v1}
        end
    end
    return vertices
end

function BridgeArt.pierLayout(world, fractions)
    fractions = fractions or BridgeArt.PIER_FRACTIONS
    local piers = {}
    for _, group in ipairs(bridgeGroups(world.roads)) do
        for index, fraction in ipairs(fractions) do
            local point = pointAt(group, group.length * fraction, 0, 0)
            local base = world.ungradedHeight and world:ungradedHeight(point.x, point.z)
                or world:height(point.x, point.z)
            piers[#piers + 1] = {
                bridgePier = true, bridgeId = group.id, pier = index,
                x = point.x, z = point.z, deckHeight = point.h,
                topHeight = point.h - BridgeArt.GIRDER_DEPTH_METERS,
                baseHeight = base, width = point.width + 0.35,
            }
        end
    end
    return piers
end

local function pierVertices(pier, camera)
    local cx, topY = camera:screen(pier.x, pier.z, pier.topHeight)
    local _, baseY = camera:screen(pier.x, pier.z, pier.baseHeight)
    local halfWidth = pier.width * 48 * camera.zoom * 0.5
    local left, right = cx - halfWidth, cx + halfWidth
    return {
        {left, topY, 0, 0}, {left, baseY, 0, 1}, {right, baseY, 1, 1},
        {left, topY, 0, 0}, {right, baseY, 1, 1}, {right, topY, 1, 0},
    }
end

local function capVertices(cap, camera)
    local width = BridgeArt.CAP_WIDTH_METERS
    local innerOffset = width * (1 - BridgeArt.CAP_OUTER_FRACTION)
    local outerOffset = width * BridgeArt.CAP_OUTER_FRACTION
    local above = BridgeArt.PROFILE_METERS * BridgeArt.DECK_LINE_FROM_TOP
    local side = cap.side
    local aiX = cap.a.x - cap.nx * side * innerOffset
    local aiZ = cap.a.z - cap.nz * side * innerOffset
    local aoX = cap.a.x + cap.nx * side * outerOffset
    local aoZ = cap.a.z + cap.nz * side * outerOffset
    local biX = cap.b.x - cap.nx * side * innerOffset
    local biZ = cap.b.z - cap.nz * side * innerOffset
    local boX = cap.b.x + cap.nx * side * outerOffset
    local boZ = cap.b.z + cap.nz * side * outerOffset
    local heightA, heightB = cap.a.h + above + 0.02, cap.b.h + above + 0.02
    local ax0, ay0 = camera:screen(aiX, aiZ, heightA)
    local ax1, ay1 = camera:screen(aoX, aoZ, heightA)
    local bx0, by0 = camera:screen(biX, biZ, heightB)
    local bx1, by1 = camera:screen(boX, boZ, heightB)
    local u0, u1 = cap.distance / BridgeArt.DECK_TEXTURE_TILE_METERS,
        (cap.distance + cap.len) / BridgeArt.DECK_TEXTURE_TILE_METERS
    return {
        {ax0, ay0, u0, 0}, {bx0, by0, u1, 0}, {bx1, by1, u1, 1},
        {ax0, ay0, u0, 0}, {bx1, by1, u1, 1}, {ax1, ay1, u0, 1},
    }
end

local function endPostVertices(post, camera)
    local cx, topY = camera:screen(post.x, post.z, post.h + post.height)
    local _, baseY = camera:screen(post.x, post.z, post.h)
    local halfWidth = post.width * 48 * camera.zoom * 0.5
    local left, right = cx - halfWidth, cx + halfWidth
    return {
        {left, topY, 0, 0}, {left, baseY, 0, 1}, {right, baseY, 1, 1},
        {left, topY, 0, 0}, {right, baseY, 1, 1}, {right, topY, 1, 0},
    }
end

local function newTexturedMesh(vertices, texture)
    local mesh = love.graphics.newMesh(MESH_FORMAT, vertices, 'triangles', 'stream')
    mesh:setTexture(texture)
    return mesh
end

local function placeholderVertices(count)
    local vertices = {}
    for _ = 1, count do
        for _ = 1, 6 do vertices[#vertices + 1] = {0, 0, 0, 0} end
    end
    return vertices
end

function BridgeArt.new(world)
    local side = love.graphics.newImage('assets/commute/bridge/concrete-side-bay.png')
    local pier = love.graphics.newImage('assets/commute/bridge/concrete-pier.png')
    local cap = love.graphics.newImage('assets/commute/bridge/concrete-parapet-cap.png')
    local endBlock = love.graphics.newImage('assets/commute/bridge/concrete-parapet-end-block.png')
    local asphalt = love.graphics.newImage('assets/commute/bridge/asphalt.png')
    for _, image in ipairs({side, pier, cap, endBlock, asphalt}) do
        image:setFilter('linear', 'linear')
    end
    asphalt:setWrap('mirroredrepeat', 'mirroredrepeat')
    cap:setWrap('mirroredrepeat', 'mirroredrepeat')

    local segments = {}
    for _, segment in ipairs(world.roads.segments) do
        if segment.bridge then segments[#segments + 1] = segment end
    end
    local sides = BridgeArt.layout(world.roads)
    local caps = BridgeArt.capLayout(world.roads)
    local endPosts = BridgeArt.endPostLayout(world.roads)
    local piers = BridgeArt.pierLayout(world)
    local self = setmetatable({world = world, sideImage = side, pierImage = pier,
        capImage = cap, endBlockImage = endBlock, asphaltImage = asphalt, segments = segments,
        sides = sides, caps = caps, endPosts = endPosts, piers = piers,
        sideMesh = newTexturedMesh(placeholderVertices(1), side),
        pierMesh = newTexturedMesh(placeholderVertices(1), pier),
        capMesh = newTexturedMesh(placeholderVertices(1), cap),
        endBlockMesh = newTexturedMesh(placeholderVertices(1), endBlock),
        deckMesh = newTexturedMesh(placeholderVertices(#segments), asphalt)}, BridgeArt)
    return self
end

function BridgeArt:visibleSides(camera, radius)
    local visible = {}
    for _, piece in ipairs(self.sides) do
        local center = piece.center
        if M.length(center.x - camera.centerX, center.z - camera.centerZ) <= radius + 3 then
            piece.depth = camera:depth(center.x, center.z, center.h)
            visible[#visible + 1] = piece
        end
    end
    return visible
end

function BridgeArt:drawDeck(camera, radius)
    if not self.segments[1] then return end
    if M.length(self.segments[1].a.x - camera.centerX, self.segments[1].a.z - camera.centerZ)
        > radius + (self.segments[1].len or 0) + 4 then
        local near = false
        for _, segment in ipairs(self.segments) do
            if M.length(segment.a.x - camera.centerX, segment.a.z - camera.centerZ) <= radius + segment.len then
                near = true; break
            end
        end
        if not near then return end
    end
    self.deckMesh:setVertices(BridgeArt.projectDeck(self.segments, camera))
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.deckMesh)
end

function BridgeArt:drawSide(piece, camera, alpha)
    self.sideMesh:setVertices(sideVertices(piece, camera))
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(self.sideMesh)
end

function BridgeArt:visibleCaps(camera, radius)
    local visible = {}
    for _, cap in ipairs(self.caps) do
        local center = cap.center
        if M.length(center.x - camera.centerX, center.z - camera.centerZ) <= radius + 4 then
            cap.depth = camera:depth(center.x, center.z,
                center.h + BridgeArt.PROFILE_METERS * BridgeArt.DECK_LINE_FROM_TOP)
            visible[#visible + 1] = cap
        end
    end
    return visible
end

function BridgeArt:drawCap(cap, camera, alpha)
    self.capMesh:setVertices(capVertices(cap, camera))
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(self.capMesh)
end

function BridgeArt:visibleEndPosts(camera, radius)
    local visible = {}
    for _, post in ipairs(self.endPosts) do
        if M.length(post.x - camera.centerX, post.z - camera.centerZ) <= radius + 4 then
            post.depth = camera:depth(post.x, post.z, post.h + post.height * 0.5)
            visible[#visible + 1] = post
        end
    end
    return visible
end

function BridgeArt:drawEndPost(post, camera, alpha)
    self.endBlockMesh:setVertices(endPostVertices(post, camera))
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(self.endBlockMesh)
end

function BridgeArt:visiblePiers(camera, radius)
    local visible = {}
    for _, pier in ipairs(self.piers) do
        if M.length(pier.x - camera.centerX, pier.z - camera.centerZ) <= radius + 8 then
            visible[#visible + 1] = pier
        end
    end
    return visible
end

function BridgeArt:drawPiers(camera, radius)
    for _, pier in ipairs(self:visiblePiers(camera, radius)) do
        self:drawPier(pier, camera)
    end
end

function BridgeArt:drawPier(pier, camera)
    self.pierMesh:setVertices(pierVertices(pier, camera))
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.pierMesh)
end

function BridgeArt:release()
    self.sideMesh:release(); self.pierMesh:release(); self.capMesh:release(); self.endBlockMesh:release(); self.deckMesh:release()
    self.sideImage:release(); self.pierImage:release(); self.capImage:release(); self.endBlockImage:release(); self.asphaltImage:release()
end

BridgeArt.sideVertices = sideVertices
BridgeArt.pierVertices = pierVertices
BridgeArt.capVertices = capVertices
BridgeArt.endPostVertices = endPostVertices
BridgeArt.pointAt = pointAt

return BridgeArt
