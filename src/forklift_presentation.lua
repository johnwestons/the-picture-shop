-- Source-review presentation only. Never approves generated art implicitly.
-- Physics owns continuous height; this module only selects/anchors its artwork.
local Presentation = {}
local directionOrder = { "northwest", "north", "northeast", "east",
    "southeast", "south", "southwest", "west" }
local directionIndex = {}
for index, direction in ipairs(directionOrder) do directionIndex[direction] = index end
local sourceRoot = "assets/source/warehouse-expansion-v1/forklift-lift/"

-- Provisional manual calibration from the 2048x768 source sheets: each pair
-- is the wheel-ground center followed by the fork-carriage contact center.
-- These are review annotations, not approved collision or runtime sprite data.
local calibration = {
    northwest = {
        { 286, 642, 185, 517 }, { 268, 642, 176, 421 },
        { 275, 642, 191, 303 }, { 267, 642, 180, 202 },
    },
    north = {
        -- v2: true straight rear view; ground carriage is occluded by the body.
        { 256, 738, 256, 600 }, { 256, 738, 256, 305 },
        { 256, 738, 256, 205 }, { 256, 738, 256, 110 },
    },
    northeast = {
        { 198, 650, 365, 526 }, { 190, 650, 363, 410 },
        { 182, 650, 361, 268 }, { 182, 650, 360, 155 },
    },
    east = {
        { 205, 638, 363, 602 }, { 197, 638, 343, 537 },
        { 177, 638, 319, 417 }, { 178, 638, 313, 266 },
    },
    southeast = {
        { 174, 647, 337, 649 }, { 176, 647, 327, 581 },
        { 169, 647, 323, 425 }, { 178, 647, 340, 276 },
    },
    south = {
        -- v3: extended mast in high poses, fixed cab and wheel baseline.
        { 271, 675, 271, 572 }, { 266, 675, 266, 530 },
        { 256, 675, 256, 162 }, { 251, 675, 251, 50 },
    },
    southwest = {
        { 399, 650, 193, 605 }, { 375, 650, 173, 496 },
        { 389, 650, 179, 370 }, { 362, 650, 171, 233 },
    },
    west = {
        { 350, 692, 201, 650 }, { 352, 692, 204, 486 },
        { 355, 692, 193, 344 }, { 350, 692, 187, 227 },
    },
}

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

function Presentation.reviewCatalog()
    local catalog = {}
    for _, direction in ipairs(directionOrder) do
        local entry = {
            path = sourceRoot .. direction .. "-raise-v"
                .. (direction == "north" and "2" or direction == "south" and "3" or "1") .. ".png",
            width = 2048, height = 768, direction = direction,
            approved = false, manned = true, anchorStatus = "provisional_manual_review",
            issues = { "soft_gold_gray_alpha_fringe", "per_frame_anchor_calibration_requires_review" },
            frames = {},
        }
        if direction == "north" then
            entry.issues[#entry.issues + 1] = "ground_carriage_occluded_anchor_estimate"
        elseif direction == "south" then
            entry.issues[#entry.issues + 1] = "fork_projection_and_nonuniform_source_step_spacing_need_review"
        end
        for index, points in ipairs(calibration[direction]) do
            entry.frames[index] = {
                source = { x = (index - 1) * 512, y = 0, width = 512, height = 768 },
                wheelAnchor = { x = points[1], y = points[2] },
                loadAnchor = { x = points[3], y = points[4] },
                height = (index - 1) / 3,
            }
        end
        catalog[direction] = entry
    end
    return catalog
end

function Presentation.validateSheet(sheet)
    if type(sheet) ~= "table" or not directionIndex[sheet.direction]
        or type(sheet.path) ~= "string" or sheet.path == ""
        or not finite(sheet.width) or sheet.width <= 0
        or not finite(sheet.height) or sheet.height <= 0
        or type(sheet.frames) ~= "table" or #sheet.frames < 2
        or type(sheet.manned) ~= "boolean" or type(sheet.approved) ~= "boolean"
    then return false, "invalid_sheet" end
    local previousHeight, previousLoadY = -1, math.huge
    for _, frame in ipairs(sheet.frames) do
        if type(frame) ~= "table" or type(frame.source) ~= "table"
            or type(frame.wheelAnchor) ~= "table" or type(frame.loadAnchor) ~= "table"
        then return false, "invalid_frame" end
        local source, wheel, load = frame.source, frame.wheelAnchor, frame.loadAnchor
        for _, value in ipairs({ source.x, source.y, source.width, source.height,
            wheel.x, wheel.y, load.x, load.y, frame.height }) do
            if not finite(value) then return false, "invalid_anchor" end
        end
        -- Explicit checks also reject missing members (which ipairs would omit).
        if not finite(source.x) or not finite(source.y) or not finite(source.width)
            or not finite(source.height) or not finite(wheel.x) or not finite(wheel.y)
            or not finite(load.x) or not finite(load.y) or not finite(frame.height)
        then return false, "invalid_anchor" end
        if source.x < 0 or source.y < 0 or source.width <= 0 or source.height <= 0
            or source.x + source.width > sheet.width or source.y + source.height > sheet.height
            or wheel.x < 0 or wheel.x > source.width or wheel.y < 0 or wheel.y > source.height
            or load.x < 0 or load.x > source.width or load.y < 0 or load.y > source.height
        then return false, "out_of_bounds" end
        if frame.height <= previousHeight or frame.height < 0 or frame.height > 1 then
            return false, "invalid_height_order"
        end
        local relativeLoadY = load.y - wheel.y
        if relativeLoadY >= previousLoadY then return false, "non_monotonic_forks" end
        previousHeight, previousLoadY = frame.height, relativeLoadY
    end
    if sheet.frames[1].height ~= 0 or sheet.frames[#sheet.frames].height ~= 1 then
        return false, "incomplete_height_range"
    end
    return true
end

function Presentation.heightSample(sheet, height)
    local valid, code = Presentation.validateSheet(sheet)
    if not valid then return nil, code end
    if not finite(height) then return nil, "invalid_height" end
    height = clamp(height, 0, 1)
    local lower, upper = 1, #sheet.frames
    for index = 1, #sheet.frames - 1 do
        if height <= sheet.frames[index + 1].height then lower, upper = index, index + 1; break end
    end
    local first, second = sheet.frames[lower], sheet.frames[upper]
    local blend = (height - first.height) / (second.height - first.height)
    local frameIndex = blend < 0.5 and lower or upper
    local firstX = first.loadAnchor.x - first.wheelAnchor.x
    local secondX = second.loadAnchor.x - second.wheelAnchor.x
    local firstY = first.loadAnchor.y - first.wheelAnchor.y
    local secondY = second.loadAnchor.y - second.wheelAnchor.y
    return {
        height = height, lowerFrame = lower, upperFrame = upper, blend = blend,
        frameIndex = frameIndex,
        loadOffset = { x = firstX + (secondX - firstX) * blend,
            y = firstY + (secondY - firstY) * blend },
    }
end

function Presentation.plan(vehicle, options)
    options = type(options) == "table" and options or {}
    if type(vehicle) ~= "table" or not vehicle.owned then return nil, "not_owned" end
    if not finite(vehicle.x) or not finite(vehicle.y) or not finite(vehicle.forkHeight)
        or not directionIndex[vehicle.direction] or type(vehicle.operating) ~= "boolean"
    then return nil, "invalid_vehicle" end
    local catalog = options.catalog or Presentation.reviewCatalog()
    local sheet = catalog[vehicle.direction]
    local valid, code = Presentation.validateSheet(sheet)
    if not valid then return nil, code end
    if sheet.direction ~= vehicle.direction then return nil, "heading_mismatch" end
    if not sheet.approved and options.review ~= true then return nil, "art_not_approved" end
    if sheet.manned ~= vehicle.operating and options.review ~= true then return nil, "driver_mismatch" end
    local sample, sampleCode = Presentation.heightSample(sheet, vehicle.forkHeight)
    if not sample then return nil, sampleCode end
    local scale = finite(options.scale) and options.scale > 0 and options.scale <= 4
        and options.scale or 0.22
    local frame = sheet.frames[sample.frameIndex]
    return {
        path = sheet.path, direction = vehicle.direction, directionFrame = directionIndex[vehicle.direction],
        frameIndex = sample.frameIndex, forkHeight = sample.height,
        source = copy(frame.source), textureWidth = sheet.width, textureHeight = sheet.height,
        originX = frame.wheelAnchor.x, originY = frame.wheelAnchor.y,
        x = vehicle.x, y = vehicle.y, scale = scale,
        -- A full-vehicle strip holds one authored pose between thresholds.
        -- Cargo must stay on those visible tines, not float toward the next pose.
        loadX = vehicle.x + (frame.loadAnchor.x - frame.wheelAnchor.x) * scale,
        loadY = vehicle.y + (frame.loadAnchor.y - frame.wheelAnchor.y) * scale,
        carriedPalletId = vehicle.carriedPalletId,
        approved = sheet.approved, review = options.review == true,
        driverMismatch = sheet.manned ~= vehicle.operating, issues = copy(sheet.issues or {}),
        sample = sample,
    }
end

-- getImage(path) must return a LÖVE image already managed by the caller's asset
-- lifecycle. This function never opens source files or falls back to fake art.
function Presentation.draw(vehicle, getImage, options, graphics)
    local plan, code = Presentation.plan(vehicle, options)
    if not plan then return false, code end
    if type(getImage) ~= "function" then return false, "image_provider_required" end
    local image = getImage(plan.path)
    if not image or type(image.getDimensions) ~= "function" then return false, "image_unavailable" end
    local width, height = image:getDimensions()
    if width ~= plan.textureWidth or height ~= plan.textureHeight then return false, "image_dimensions" end
    graphics = graphics or (love and love.graphics)
    if not graphics then return false, "graphics_unavailable" end
    local source = plan.source
    local quad = graphics.newQuad(source.x, source.y, source.width, source.height, width, height)
    graphics.push("all")
    local success, drawError = pcall(function()
        graphics.setColor(1, 1, 1, 1)
        graphics.draw(image, quad, plan.x, plan.y, 0, plan.scale, plan.scale, plan.originX, plan.originY)
    end)
    graphics.pop()
    if quad.release then quad:release() end
    if not success then return false, drawError end
    return true, plan
end

return Presentation
