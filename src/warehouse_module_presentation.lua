-- Registered, bay-oriented finished module art. Construction can show the
-- selected room as a translucent site preview until its durable project lands.
local Presentation = {}
local ROOT = "assets/source/warehouse-expansion-v1/modules/"

local catalog = {
    front_left = {
        path = ROOT .. "breakroom-world-left-v1.png", bayId = "front_left", approved = false,
        registration = { textureWidth = 1536, textureHeight = 1024,
            source = { x = 0, y = 0, width = 1536, height = 1024 },
            originX = 1000, originY = 920, x = 145, y = 617, scale = 0.15, depthY = 617,
            obstacles = {
                { x = 92, y = 532, halfWidth = 64, halfHeight = 27 },
                { x = 143, y = 582, halfWidth = 52, halfHeight = 38 },
            } },
    },
    front_right = {
        path = ROOT .. "breakroom-world-right-v1.png", bayId = "front_right", approved = false,
        registration = { textureWidth = 1536, textureHeight = 1024,
            source = { x = 0, y = 0, width = 1536, height = 1024 },
            originX = 800, originY = 950, x = 880, y = 620, scale = 0.13, depthY = 620,
            obstacles = {
                { x = 856, y = 545, halfWidth = 39, halfHeight = 29 },
                { x = 886, y = 587, halfWidth = 43, halfHeight = 32 },
            } },
    },
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

function Presentation.reviewCatalog() return copy(catalog) end

function Presentation.validateEntry(entry)
    if type(entry) ~= "table" or type(entry.path) ~= "string" or entry.path == ""
        or (entry.bayId ~= "front_left" and entry.bayId ~= "front_right")
        or type(entry.approved) ~= "boolean" or type(entry.registration) ~= "table" then
        return false, "invalid_warehouse_module"
    end
    local r = entry.registration
    local source = r.source
    if r.textureWidth ~= 1536 or r.textureHeight ~= 1024
        or type(source) ~= "table" or source.x ~= 0 or source.y ~= 0
        or source.width ~= r.textureWidth or source.height ~= r.textureHeight
        or not finite(r.originX) or not finite(r.originY) or not finite(r.x) or not finite(r.y)
        or not finite(r.scale) or r.scale <= 0 or r.scale > 1
        or not finite(r.depthY) or r.originX < 0 or r.originX > r.textureWidth
        or r.originY < 0 or r.originY > r.textureHeight then
        return false, "invalid_warehouse_module_registration"
    end
    return true
end

local function activeProject(warehouse, bay)
    for _, project in ipairs(warehouse.projects or {}) do
        if project.id == bay.projectId and project.bayId == bay.id then return project end
    end
end

function Presentation.plan(state, bayId, options)
    options = type(options) == "table" and options or {}
    local warehouse = type(state) == "table" and state.warehouse
    local bay = warehouse and warehouse.bays and warehouse.bays[bayId]
    if type(bay) ~= "table" or bay.optionId ~= "breakroom" then return nil, "module_not_installed" end
    local alpha = 1
    if bay.status == "building" and options.includeBuilding == true then
        local project = activeProject(warehouse, { id = bayId, projectId = bay.projectId })
        if not project or project.id ~= warehouse.activeProjectId or project.phase ~= "building"
            or not finite(project.stage) or project.stage ~= math.floor(project.stage)
            or project.stage < 1 or project.stage > 4 then return nil, "module_project_unavailable" end
        alpha = math.min(0.9, 0.18 + project.stage * 0.17)
    elseif bay.status ~= "complete" then
        return nil, "module_not_complete"
    end
    local entry = (options.catalog or catalog)[bayId]
    local valid, reason = Presentation.validateEntry(entry)
    if not valid then return nil, reason end
    if not entry.approved and options.review ~= true then return nil, "art_not_approved" end
    local plan = copy(entry.registration)
    plan.path, plan.bayId, plan.alpha = entry.path, bayId, alpha
    plan.approved, plan.review = entry.approved, options.review == true
    return plan
end

function Presentation.obstacles(bayId, options)
    options = type(options) == "table" and options or {}
    local entry = (options.catalog or catalog)[bayId]
    if not entry then return {} end
    return copy(entry.registration.obstacles or {})
end

function Presentation.draw(state, bayId, getImage, options, graphics)
    local plan, reason = Presentation.plan(state, bayId, options)
    if not plan then return false, reason end
    if type(getImage) ~= "function" then return false, "image_provider_required" end
    local okay, image = pcall(getImage, plan.path)
    if not okay or not image or type(image.getDimensions) ~= "function" then
        return false, "image_unavailable"
    end
    local width, height = image:getDimensions()
    if width ~= plan.textureWidth or height ~= plan.textureHeight then return false, "image_dimensions" end
    graphics = graphics or (love and love.graphics)
    if not graphics then return false, "graphics_unavailable" end
    graphics.setColor(1, 1, 1, plan.alpha)
    graphics.draw(image, plan.x, plan.y, 0, plan.scale, plan.scale, plan.originX, plan.originY)
    graphics.setColor(1, 1, 1, 1)
    return true, plan
end

return Presentation
