local Roads = require('src.commute.roads')
local Camera = require('src.commute.camera')
local BridgeRails = require('src.commute.bridge_rails')
local Test = {}

local function near(a, b, epsilon)
    return math.abs(a - b) <= (epsilon or 1e-5)
end

function Test.run(check)
    local roads = Roads.new()
    local pieces = BridgeRails.layout(roads)
    local bridgeLength = 0
    for _, segment in ipairs(roads.segments) do
        if segment.bridge then bridgeLength = bridgeLength + segment.len end
    end
    local bayCount = math.ceil(bridgeLength / BridgeRails.SPAN_METERS)
    check('bridge rail layout covers both bridge sides with sprite bays',
        #pieces == bayCount * 2 and bayCount > 0,
        ('pieces=%d bays=%d length=%.2f'):format(#pieces, bayCount, bridgeLength))

    local spacingOkay = true
    for index = 1, #pieces, 2 do
        local left, right = pieces[index], pieces[index + 1]
        spacingOkay = spacingOkay and left and right
            and left.bay == right.bay and left.bridgeId == right.bridgeId
            and left.side == -1 and right.side == 1
            and near(left.spacing, bridgeLength / bayCount)
            and left.spacing <= BridgeRails.SPAN_METERS
            and left.spacing > BridgeRails.SPAN_METERS - 0.5
            and near(left.center.h, right.center.h)
    end
    check('paired rail bays keep level-matched support points and even post spacing', spacingOkay)

    local world = {
        size = 512,
        height = function() return 4 end,
        supportHeight = function() return 4 end,
    }
    local actor = {x = 330, z = 270}
    local camera = Camera.new(actor, world)
    camera.zoom = 1
    local cameraOkay = true
    for yaw = 0, 315, 45 do
        camera.yaw = yaw
        for index = 1, #pieces, 2 do
            local vertices = BridgeRails.project(pieces[index], camera)
            local topA, baseA, baseB, topB = vertices[1], vertices[2], vertices[3], vertices[6]
            local spanX, spanY = baseB[1] - baseA[1], baseB[2] - baseA[2]
            cameraOkay = cameraOkay
                and near(topA[1], baseA[1]) and near(topB[1], baseB[1])
                and topA[2] < baseA[2] and topB[2] < baseB[2]
                and math.sqrt(spanX * spanX + spanY * spanY) > 1
        end
    end
    check('bridge sprite projection follows all camera yaws and keeps posts upright', cameraOkay)

    local art = BridgeRails.new({roads = roads})
    local visible = art:visible(camera, 64)
    local assetOkay = art.image:getWidth() == 2048 and art.image:getHeight() == 496
        and #visible > 0 and visible[1].depth ~= nil
    check('painted bridge rail asset loads and visible bays receive camera depth', assetOkay)
    art:release()
end

return Test
