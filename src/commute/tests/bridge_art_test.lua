local Roads = require('src.commute.roads')
local Camera = require('src.commute.camera')
local BridgeArt = require('src.commute.bridge_art')

local Test = {}
local function near(a, b, epsilon)
    return math.abs(a - b) <= (epsilon or 1e-5)
end
local function finite(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

function Test.run(check)
    local roads = Roads.new()
    local length, bridgeSegments, bridgeWidth, widthOkay = 0, {}, nil, true
    for _, segment in ipairs(roads.segments) do
        if segment.bridge then
            length = length + segment.len
            bridgeSegments[#bridgeSegments + 1] = segment
            bridgeWidth = bridgeWidth or segment.width
            widthOkay = widthOkay and near(segment.width, 5)
        end
    end
    check('bridge asphalt keeps the existing five-meter driveable width', widthOkay,
        ('width=%.2f'):format(bridgeWidth or -1))
    local art = BridgeArt.new({
        roads = roads,
        height = function() return 1.2 end,
        ungradedHeight = function() return 1.2 end,
    })
    local expectedBays = math.ceil(length / BridgeArt.BAY_METERS)
    local spacingOkay = #art.sides == expectedBays * 2
    for index = 1, #art.sides, 2 do
        local left, right = art.sides[index], art.sides[index + 1]
        spacingOkay = spacingOkay and left and right and left.bay == right.bay
            and left.bridgeId == right.bridgeId and left.side == -1 and right.side == 1
            and near(left.spacing, length / expectedBays)
            and left.spacing <= BridgeArt.BAY_METERS
    end
    check('concrete side-bay sprites cover both parapets at even registered spans',
        spacingOkay, ('pieces=%d length=%.2f roadWidth=%.2f'):format(#art.sides, length, bridgeWidth or -1))

    local detailsOkay = #art.caps == #bridgeSegments * 2 and #art.endPosts == 4
    for _, cap in ipairs(art.caps) do
        detailsOkay = detailsOkay and cap.bridgeCap and cap.bridgeId == 'east-bank'
            and cap.side ~= 0 and cap.len > 0
    end
    for _, post in ipairs(art.endPosts) do
        detailsOkay = detailsOkay and post.bridgeEndPost and post.bridgeId == 'east-bank'
            and (post.side == -1 or post.side == 1)
            and near(post.height, BridgeArt.PROFILE_METERS * BridgeArt.DECK_LINE_FROM_TOP)
    end
    check('painted cap strips and separate terminal blocks follow both bridge edges', detailsOkay,
        ('caps=%d terminals=%d'):format(#art.caps, #art.endPosts))

    local camera = Camera.new({x = 331, z = 270}, {
        height = function() return 1.2 end,
        supportHeight = function() return 1.2 end,
    })
    local projectionOkay = true
    for tilt = 20, 80, 15 do
        camera.tilt = tilt
        for yaw = 0, 315, 45 do
            camera.yaw = yaw
            local vertices = BridgeArt.sideVertices(art.sides[1], camera)
            local top, bottom, farBottom = vertices[1], vertices[2], vertices[3]
            local dx, dy = farBottom[1] - bottom[1], farBottom[2] - bottom[2]
            projectionOkay = projectionOkay and finite(top[1]) and finite(top[2])
                and top[2] < bottom[2]
                and math.sqrt(dx * dx + dy * dy) > 1
        end
    end
    check('concrete parapets stay upright and follow the road through camera yaw and tilt', projectionOkay)

    local capProjectionOkay = true
    for yaw = 0, 315, 45 do
        camera.yaw = yaw
        local vertices = BridgeArt.capVertices(art.caps[1], camera)
        capProjectionOkay = capProjectionOkay and #vertices == 6
        for _, vertex in ipairs(vertices) do
            capProjectionOkay = capProjectionOkay and finite(vertex[1]) and finite(vertex[2])
                and finite(vertex[3]) and finite(vertex[4])
        end
    end
    check('textured parapet cap strips remain projected across yawed bridge edges', capProjectionOkay)

    camera.yaw, camera.tilt = 335, 55
    local deck = BridgeArt.projectDeck(bridgeSegments, camera)
    local deckOkay = #deck == #bridgeSegments * 6
    for _, vertex in ipairs(deck) do
        deckOkay = deckOkay and finite(vertex[1]) and finite(vertex[2])
            and finite(vertex[3]) and finite(vertex[4])
    end
    check('textured asphalt deck projects every existing bridge segment', deckOkay,
        ('vertices=%d segments=%d'):format(#deck, #bridgeSegments))

    local pierOkay = #art.piers == #BridgeArt.PIER_FRACTIONS
    for _, pier in ipairs(art.piers) do
        local vertices = BridgeArt.pierVertices(pier, camera)
        pierOkay = pierOkay and near(pier.baseHeight, 1.2) and near(pier.deckHeight, 3.6)
            and near(pier.topHeight, pier.deckHeight - BridgeArt.GIRDER_DEPTH_METERS)
            and pier.width > bridgeWidth and #vertices == 6
        for _, vertex in ipairs(vertices) do
            pierOkay = pierOkay and finite(vertex[1]) and finite(vertex[2])
        end
    end
    check('two painted pier sprites anchor to terrain and meet the existing deck elevation', pierOkay,
        ('piers=%d'):format(#art.piers))

    local assetsOkay = art.sideImage:getWidth() == 2030 and art.sideImage:getHeight() == 589
        and art.pierImage:getWidth() == 1024 and art.pierImage:getHeight() == 985
        and art.capImage:getWidth() == 512 and art.capImage:getHeight() == 128
        and art.endBlockImage:getWidth() == 426 and art.endBlockImage:getHeight() == 1024
        and art.asphaltImage:getWidth() == 256 and art.asphaltImage:getHeight() == 256
        and near(BridgeArt.GIRDER_DEPTH_METERS, 1.41)
    check('generated concrete, cap, end-block, and asphalt textures load at registered runtime sizes', assetsOkay)
    art:release()
end

return Test
