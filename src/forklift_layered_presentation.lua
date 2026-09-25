-- Candidate continuous side-view lift art. Other headings keep their reviewed
-- four-pose strips until equivalent layers are authored and checked in game.
local Layered = {}
local root = "assets/source/warehouse-expansion-v1/forklift-layer-study/"
local bodyManned = root .. "east-fixed-manned-v1.png"
local bodyEmpty = root .. "east-fixed-empty-v1.png"
local carriage = root .. "east-carriage-v2.png"
local textureWidth, textureHeight = 1536, 1024
local scaleRatio = 0.145 / (0.22 * 1.4)

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

function Layered.plan(vehicle, options)
    options = options or {}
    if type(vehicle) ~= "table" or not vehicle.owned then return nil, "not_owned" end
    if vehicle.direction ~= "east" and vehicle.direction ~= "west" then
        return nil, "unsupported_heading"
    end
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
    local carriageScale = oldScale * scaleRatio
    local bodyScale = carriageScale * (vehicle.operating and 1 or 0.97)
    local mirror = vehicle.direction == "west" and -1 or 1
    local shift = 150 - 560 * height
    local bodyOriginX = vehicle.operating and 720 or 730
    local bodyOriginY = vehicle.operating and 955 or 966
    return {
        bodyPath = vehicle.operating and bodyManned or bodyEmpty,
        carriagePath = carriage,
        textureWidth = textureWidth, textureHeight = textureHeight,
        x = vehicle.x, y = vehicle.y, direction = vehicle.direction,
        forkHeight = height, mirror = mirror, bodyScale = bodyScale,
        carriageScale = carriageScale, bodyOriginX = bodyOriginX,
        bodyOriginY = bodyOriginY, carriageOriginX = 720,
        carriageOriginY = 955, carriageShift = shift,
        loadX = vehicle.x + mirror * (1170 - 720) * carriageScale,
        loadY = vehicle.y + (750 + shift - 955) * carriageScale,
        carriedPalletId = vehicle.carriedPalletId,
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
        graphics.draw(forks, plan.x,
            plan.y + plan.carriageShift * plan.carriageScale, 0,
            plan.mirror * plan.carriageScale, plan.carriageScale,
            plan.carriageOriginX, plan.carriageOriginY)
    end)
    graphics.pop()
    if not okay then return false, drawError end
    return true, plan
end

return Layered
