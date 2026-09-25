-- Source-review presentation only. Never approves generated art implicitly.
-- Physics owns continuous height; this module only selects/anchors its artwork.
local Presentation = {}
local directionOrder = { "northwest", "north", "northeast", "east",
    "southeast", "south", "southwest", "west" }
local directionIndex = {}
for index, direction in ipairs(directionOrder) do directionIndex[direction] = index end
local sourceRoot = "assets/source/warehouse-expansion-v1/forklift-lift/"
local edgeShader
local edgeShaderSource = [[
    extern vec2 sourceSize;
    extern vec4 sourceRect;

    vec4 premultipliedSample(Image texture, vec2 pixel) {
        vec4 sample = Texel(texture, (pixel + vec2(0.5)) / sourceSize);
        return vec4(sample.rgb * sample.a, sample.a);
    }

    vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screenCoords) {
        vec2 position = uv * sourceSize - vec2(0.5);
        vec2 first = clamp(floor(position), sourceRect.xy,
            sourceRect.xy + sourceRect.zw - vec2(1.0));
        vec2 second = clamp(floor(position) + vec2(1.0), sourceRect.xy,
            sourceRect.xy + sourceRect.zw - vec2(1.0));
        vec2 fraction = fract(position);
        vec4 top = mix(premultipliedSample(texture, first),
            premultipliedSample(texture, vec2(second.x, first.y)), fraction.x);
        vec4 bottom = mix(premultipliedSample(texture, vec2(first.x, second.y)),
            premultipliedSample(texture, second), fraction.x);
        vec4 result = mix(top, bottom, fraction.y);
        if (result.a <= 0.00001) return vec4(0.0);
        return vec4(result.rgb / result.a, result.a) * color;
    }
]]

-- Provisional manual calibration from the 2048x768 source sheets: each pair
-- is the wheel-ground center followed by the carried pallet center on the
-- visible tines. These centers were checked against loaded engine captures
-- at low, middle and high fork heights, not just the bare source sheet.
-- These are review annotations, not approved collision or runtime sprite data.
local calibration = {
    northwest = {
        { 286, 642, 155, 532 }, { 268, 642, 146, 431 },
        { 275, 642, 161, 308 }, { 267, 642, 150, 202 },
    },
    north = {
        -- v2: true straight rear view; ground carriage is occluded by the body.
        { 256, 738, 256, 600 }, { 256, 738, 256, 315 },
        { 256, 738, 256, 215 }, { 256, 738, 256, 125 },
    },
    northeast = {
        { 198, 650, 420, 536 }, { 190, 650, 418, 420 },
        { 182, 650, 416, 278 }, { 182, 650, 415, 165 },
    },
    east = {
        { 205, 638, 443, 644 }, { 197, 638, 423, 579 },
        { 177, 638, 399, 460 }, { 178, 638, 393, 291 },
    },
    southeast = {
        { 174, 647, 407, 693 }, { 176, 647, 392, 631 },
        { 169, 647, 383, 510 }, { 178, 647, 375, 326 },
    },
    south = {
        -- v3: extended mast in high poses, fixed cab and wheel baseline.
        { 271, 675, 271, 587 }, { 266, 675, 266, 545 },
        { 256, 675, 256, 177 }, { 251, 675, 251, 65 },
    },
    southwest = {
        { 399, 650, 163, 695 }, { 375, 650, 143, 581 },
        { 389, 650, 149, 465 }, { 362, 650, 141, 303 },
    },
    west = {
        { 350, 692, 156, 670 }, { 352, 692, 159, 506 },
        { 355, 692, 148, 365 }, { 350, 692, 142, 257 },
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

function Presentation.reviewCatalog(manned)
    if manned == nil then manned = true end
    local catalog = {}
    for _, direction in ipairs(directionOrder) do
        local entry = {
            path = manned and (sourceRoot .. direction .. "-raise-v"
                .. (direction == "north" and "2" or direction == "south" and "3" or "1") .. ".png")
                or (sourceRoot .. direction .. "-raise-empty-v"
                    .. (direction == "southeast" and "2" or "1") .. ".png"),
            width = 2048, height = 768, direction = direction,
            approved = false, manned = manned, anchorStatus = "provisional_manual_review",
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
    local catalog = options.catalog or Presentation.reviewCatalog(vehicle.operating)
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
        if options and options.edgeCleanup and graphics.newShader and graphics.setShader then
            if edgeShader == nil then
                local created, shader = pcall(graphics.newShader, edgeShaderSource)
                edgeShader = created and shader or false
            end
            if edgeShader then
                edgeShader:send("sourceSize", { width, height })
                edgeShader:send("sourceRect", { source.x, source.y, source.width, source.height })
                graphics.setShader(edgeShader)
            end
        end
        graphics.setColor(1, 1, 1, 1)
        graphics.draw(image, quad, plan.x, plan.y, 0, plan.scale, plan.scale, plan.originX, plan.originY)
    end)
    graphics.pop()
    if quad.release then quad:release() end
    if not success then return false, drawError end
    return true, plan
end

return Presentation
