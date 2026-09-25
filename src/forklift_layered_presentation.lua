-- Candidate continuous lift art for all eight headings. The reviewed four-pose
-- strips remain as a fallback when a layer cannot load.
local Layered = {}
local root = "assets/source/warehouse-expansion-v1/forklift-layer-study/"
local textureWidth, textureHeight = 1536, 1024
local scaleRatio = 0.145 / (0.22 * 1.4)
local studies = {
    side = {
        manned = root .. "east-fixed-manned-v1.png",
        empty = root .. "east-fixed-empty-v1.png",
        carriage = root .. "east-carriage-v2.png",
        bodyOriginX = 720, bodyOriginY = 955,
        emptyOriginX = 730, emptyOriginY = 966, emptyScale = 0.97,
        carriageOriginX = 720, carriageOriginY = 955,
        carriageX = 0, carriageLow = 150, carriageTravel = 560,
        loadX = 1170, loadY = 750,
    },
    frontDiagonal = {
        manned = root .. "southeast-fixed-manned-v1.png",
        empty = root .. "southeast-fixed-empty-v1.png",
        carriage = root .. "southeast-carriage-v1.png",
        bodyOriginX = 630, bodyOriginY = 850,
        emptyOriginX = 630, emptyOriginY = 864, emptyScale = 0.955,
        carriageOriginX = 630, carriageOriginY = 850,
        carriageX = 150, carriageLow = 80, carriageTravel = 480,
        loadX = 970, loadY = 820,
    },
    rearDiagonal = {
        manned = root .. "northeast-fixed-manned-v1.png",
        empty = root .. "northeast-fixed-empty-v1.png",
        carriage = root .. "northeast-carriage-v2.png",
        bodyOriginX = 680, bodyOriginY = 890,
        emptyOriginX = 680, emptyOriginY = 890, emptyScale = 1,
        carriageOriginX = 680, carriageOriginY = 890,
        carriageScale = 0.8, carriageX = 265,
        carriageLow = 150, carriageTravel = 563,
        loadX = 1000, loadY = 440,
    },
    front = {
        manned = root .. "south-fixed-manned-v1.png",
        empty = root .. "south-fixed-empty-v1.png",
        carriage = root .. "south-carriage-v1.png",
        bodyOriginX = 768, bodyOriginY = 965,
        emptyOriginX = 768, emptyOriginY = 965, emptyScale = 1,
        carriageOriginX = 782, carriageOriginY = 792,
        carriageScale = 0.65, carriageX = 0,
        carriageLow = 0, carriageTravel = 846,
        loadX = 768, loadY = 720,
    },
    rear = {
        manned = root .. "north-fixed-manned-v1.png",
        empty = root .. "north-fixed-empty-v1.png",
        carriage = root .. "north-carriage-v1.png",
        bodyOriginX = 768, bodyOriginY = 990,
        emptyOriginX = 768, emptyOriginY = 990, emptyScale = 1,
        carriageOriginX = 768, carriageOriginY = 990,
        carriageX = 0, carriageLow = 300, carriageTravel = 510,
        loadX = 768, loadY = 600,
        frontClipY = 480,
    },
}
local directions = {
    east = { study = studies.side, mirror = 1 },
    west = { study = studies.side, mirror = -1 },
    southeast = { study = studies.frontDiagonal, mirror = 1 },
    southwest = { study = studies.frontDiagonal, mirror = -1 },
    northeast = { study = studies.rearDiagonal, mirror = 1 },
    northwest = { study = studies.rearDiagonal, mirror = -1 },
    south = { study = studies.front, mirror = 1 },
    north = { study = studies.rear, mirror = 1 },
}

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

function Layered.plan(vehicle, options)
    options = options or {}
    if type(vehicle) ~= "table" or not vehicle.owned then return nil, "not_owned" end
    local direction = directions[vehicle.direction]
    if not direction then return nil, "unsupported_heading" end
    if options.review ~= true then return nil, "art_not_approved" end
    if not finite(vehicle.x) or not finite(vehicle.y) or not finite(vehicle.forkHeight)
        or type(vehicle.operating) ~= "boolean" then
        return nil, "invalid_vehicle"
    end
    local oldScale = options.scale or 0.22 * 1.4
    if not finite(oldScale) or oldScale <= 0 or oldScale > 4 then
        return nil, "invalid_scale"
    end
    local height = math.max(0, math.min(1, vehicle.forkHeight))
    local study = direction.study
    local baseScale = oldScale * scaleRatio
    local carriageScale = baseScale * (study.carriageScale or 1)
    local bodyScale = baseScale * (vehicle.operating and 1 or study.emptyScale)
    local mirror = direction.mirror
    local shift = study.carriageLow - study.carriageTravel * height
    local bodyOriginX = vehicle.operating and study.bodyOriginX or study.emptyOriginX
    local bodyOriginY = vehicle.operating and study.bodyOriginY or study.emptyOriginY
    return {
        bodyPath = vehicle.operating and study.manned or study.empty,
        carriagePath = study.carriage,
        textureWidth = textureWidth, textureHeight = textureHeight,
        x = vehicle.x, y = vehicle.y, direction = vehicle.direction,
        forkHeight = height, mirror = mirror, bodyScale = bodyScale,
        carriageScale = carriageScale, bodyOriginX = bodyOriginX,
        bodyOriginY = bodyOriginY, carriageOriginX = study.carriageOriginX,
        carriageOriginY = study.carriageOriginY, carriageShift = shift,
        carriageX = study.carriageX,
        loadX = vehicle.x + mirror * (study.loadX + study.carriageX
            - study.carriageOriginX) * carriageScale,
        loadY = vehicle.y + (study.loadY + shift
            - study.carriageOriginY) * carriageScale,
        carriedPalletId = vehicle.carriedPalletId,
        frontClipY = study.frontClipY,
        approved = false, review = true,
    }
end

function Layered.draw(vehicle, getImage, options, graphics)
    local plan, code = Layered.plan(vehicle, options)
    if not plan then return false, code end
    if type(getImage) ~= "function" then return false, "image_provider_required" end
    local body, forks = getImage(plan.bodyPath), getImage(plan.carriagePath)
    if not body or not forks or type(body.getDimensions) ~= "function"
        or type(forks.getDimensions) ~= "function" then
        return false, "image_unavailable"
    end
    local bw, bh = body:getDimensions()
    local fw, fh = forks:getDimensions()
    if bw ~= textureWidth or bh ~= textureHeight
        or fw ~= textureWidth or fh ~= textureHeight then
        return false, "image_dimensions"
    end
    graphics = graphics or (love and love.graphics)
    if not graphics then return false, "graphics_unavailable" end
    graphics.push("all")
    local okay, drawError = pcall(function()
        graphics.setColor(1, 1, 1, 1)
        graphics.draw(body, plan.x, plan.y, 0,
            plan.mirror * plan.bodyScale, plan.bodyScale,
            plan.bodyOriginX, plan.bodyOriginY)
        if plan.frontClipY then
            local clipBottom = plan.y + (plan.frontClipY - plan.bodyOriginY) * plan.bodyScale
            graphics.stencil(function()
                graphics.rectangle("fill", plan.x - 1000, plan.y - 1000,
                    2000, clipBottom - (plan.y - 1000))
            end, "replace", 1)
            graphics.setStencilTest("equal", 1)
        end
        graphics.draw(forks, plan.x + plan.mirror * plan.carriageX * plan.carriageScale,
            plan.y + plan.carriageShift * plan.carriageScale, 0,
            plan.mirror * plan.carriageScale, plan.carriageScale,
            plan.carriageOriginX, plan.carriageOriginY)
        if plan.frontClipY then graphics.setStencilTest() end
    end)
    graphics.pop()
    if not okay then return false, drawError end
    return true, plan
end

return Layered
