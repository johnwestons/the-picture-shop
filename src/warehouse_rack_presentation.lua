-- World-facing rack sprites are separate from the first-person shelf screen.
-- Ten registered slot anchors share the same transform as each authored rack.
local Presentation = {}
local ROOT = "assets/source/warehouse-expansion-v1/modules/"
local catalog = {
    front_left = { path = ROOT .. "rack-world-left-v2.png", bayId = "front_left", approved = true,
        registration = { textureWidth = 1536, textureHeight = 1024,
            x = 30, y = 447, originX = 140, originY = 480,
            scaleX = 0.30, scaleY = 0.16, rotation = math.rad(18.5), depthY = 447,
            baseline = { x = 140, y = 480, dx = 1070, dy = 500 },
            lowerSlotOffset = -47, upperSourceOffset = { x = -63, y = -350 } } },
    front_right = { path = ROOT .. "rack-world-right-v1.png", bayId = "front_right", approved = true,
        registration = { textureWidth = 1536, textureHeight = 1024,
            x = 930, y = 447, originX = 1465, originY = 615,
            scaleX = 0.255, scaleY = 0.186, rotation = math.rad(-21.6), depthY = 447,
            baseline = { x = 1465, y = 615, dx = -1275, dy = 330 },
            lowerSlotOffset = -47, upperSourceOffset = { x = 85, y = -290 } } },
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function projectFor(warehouse, bay)
    for _, project in ipairs(warehouse.projects or {}) do
        if project.id == bay.projectId and project.bayId == bay.id then return project end
    end
end

function Presentation.reviewCatalog() return copy(catalog) end
function Presentation.validateEntry(entry)
    if type(entry) ~= "table" or type(entry.path) ~= "string" or entry.path == ""
        or (entry.bayId ~= "front_left" and entry.bayId ~= "front_right")
        or type(entry.approved) ~= "boolean" or type(entry.registration) ~= "table" then
        return false, "invalid_world_rack_sprite"
    end
    local r = entry.registration
    if r.textureWidth ~= 1536 or r.textureHeight ~= 1024
        or not finite(r.x) or not finite(r.y) or not finite(r.originX) or not finite(r.originY)
        or not finite(r.scaleX) or r.scaleX <= 0 or r.scaleX > 1
        or not finite(r.scaleY) or r.scaleY <= 0 or r.scaleY > 1
        or not finite(r.rotation) or not finite(r.depthY)
        or not finite(r.lowerSlotOffset)
        or r.originX < 0 or r.originX > r.textureWidth or r.originY < 0 or r.originY > r.textureHeight
        or type(r.baseline) ~= "table" or not finite(r.baseline.x) or not finite(r.baseline.y)
        or not finite(r.baseline.dx) or not finite(r.baseline.dy)
        or type(r.upperSourceOffset) ~= "table" or not finite(r.upperSourceOffset.x)
        or not finite(r.upperSourceOffset.y) then return false, "invalid_world_rack_registration" end
    return true
end

function Presentation.plan(state, bayId, options)
    options = type(options) == "table" and options or {}
    local warehouse = type(state) == "table" and state.warehouse
    local bay = warehouse and warehouse.bays and warehouse.bays[bayId]
    if type(bay) ~= "table" or bay.optionId ~= "storage"
        or (bay.status ~= "complete" and not (bay.status == "building" and options.includeBuilding == true)) then
        return nil, "rack_not_complete"
    end
    local entry = (options.catalog or catalog)[bayId]
    local valid, reason = Presentation.validateEntry(entry)
    if not valid then return nil, reason end
    if not entry.approved and options.review ~= true then return nil, "art_not_approved" end
    local plan = copy(entry.registration)
    plan.path, plan.bayId, plan.approved = entry.path, bayId, entry.approved
    plan.review, plan.alpha = options.review == true, 1
    if bay.status == "building" then
        local project = projectFor(warehouse, { id = bayId, projectId = bay.projectId })
        if not project or project.id ~= warehouse.activeProjectId or project.phase ~= "building"
            or not finite(project.stage) or project.stage ~= math.floor(project.stage)
            or project.stage < 1 or project.stage > 4 then
            return nil, "invalid_building_project"
        end
        plan.alpha = math.min(0.72, 0.14 + project.stage * 0.14)
    end
    return plan
end

local function sourceToWorld(plan, x, y)
    local cosine, sine = math.cos(plan.rotation), math.sin(plan.rotation)
    local dx, dy = (x - plan.originX) * plan.scaleX, (y - plan.originY) * plan.scaleY
    return plan.x + dx * cosine - dy * sine, plan.y + dx * sine + dy * cosine
end

function Presentation.slotPoint(plan, row, column)
    if not plan or (row ~= 1 and row ~= 2) or not finite(column)
        or column ~= math.floor(column) or column < 1 or column > 5 then return nil end
    local fraction = (column - 0.5) / 5
    local baseline = plan.baseline
    local sourceX = baseline.x + baseline.dx * fraction
    local groundSourceY = baseline.y + baseline.dy * fraction
    local slotX, slotY = sourceX, groundSourceY + plan.lowerSlotOffset
    if row == 2 then
        slotX = slotX + plan.upperSourceOffset.x
        slotY = slotY + plan.upperSourceOffset.y
    end
    local x, y = sourceToWorld(plan, slotX, slotY)
    local _, groundY = sourceToWorld(plan, sourceX, groundSourceY)
    return { x = x, y = y, groundY = groundY, row = row, column = column }
end

function Presentation.draw(state, bayId, getImage, options, graphics)
    local plan, reason = Presentation.plan(state, bayId, options)
    if not plan then return false, reason end
    if type(getImage) ~= "function" then return false, "image_provider_required" end
    local okay, image = pcall(getImage, plan.path)
    if not okay or not image or type(image.getDimensions) ~= "function" then return false, "image_unavailable" end
    local width, height = image:getDimensions()
    if width ~= plan.textureWidth or height ~= plan.textureHeight then return false, "image_dimensions" end
    graphics = graphics or (love and love.graphics)
    if not graphics then return false, "graphics_unavailable" end
    graphics.setColor(1, 1, 1, plan.alpha)
    graphics.draw(image, plan.x, plan.y, plan.rotation, plan.scaleX, plan.scaleY, plan.originX, plan.originY)
    graphics.setColor(1, 1, 1, 1)
    return true, plan
end

return Presentation
