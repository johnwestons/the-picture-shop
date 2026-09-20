local Forklift = require("src.forklift")
local Presentation = require("src.forklift_presentation")
local Lab = {}
local Model = {}
Model.__index = Model
local directions = { "northwest", "north", "northeast", "east",
    "southeast", "south", "southwest", "west" }
local labels = { "NW", "N", "NE", "E", "SE", "S", "SW", "W" }
local captureSuffix = "/output/warehouse-expansion-v1/forklift-lab-captures"

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function copy(value)
    local result = {}
    for key, item in pairs(value) do result[key] = item end
    return result
end

function Lab.newModel(config)
    config = config or { spawnX = 0, spawnY = 0, speed = 80, loadedSpeed = 60,
        liftDuration = 3, lowerDuration = 2.5, travelHeight = 0.08, maxStepDistance = 4 }
    local model = setmetatable({ config = config, selectedDirection = 1, paused = false,
        message = "Isolated fixture. No shop, inventory or saves are loaded." }, Model)
    model:reset()
    return model
end

function Model:reset()
    self.state = { forklift = Forklift.defaultState(self.config) }
    self.state.forklift.owned = true
    assert(Forklift.acquire(self.state, self.config, 1))
    self.state.forklift.direction = directions[self.selectedDirection]
    self.paused = false
end

function Model:selectDirection(index)
    if not finite(index) or index ~= math.floor(index) then return false end
    self.selectedDirection = ((index - 1) % #directions) + 1
    -- This is a source-view selector, not a live-game turn/drive command.
    self.state.forklift.direction = directions[self.selectedDirection]
    return true
end

function Model:setHeight(height)
    Forklift.move(self.state, 0, 0, 0, self.config, function() return true end, 1)
    local ok, reason = Forklift.setForkHeight(self.state, self.config, 1, height)
    self.message = ok and string.format("Target fork height %.0f%%", height * 100) or tostring(reason)
    return ok, reason
end

function Model:toggleLift()
    return self:setHeight(self.state.forklift.targetForkHeight >= 0.5 and 0 or 1)
end

function Model:togglePause()
    self.paused = not self.paused
    Forklift.move(self.state, 0, 0, 0, self.config, function() return true end, 1)
    return self.paused
end

function Model:update(dt, dx, dy)
    if not finite(dt) or dt < 0 then return false, "invalid_dt" end
    if self.paused then return false, "paused" end
    dx, dy = dx or 0, dy or 0
    local moved, reason = Forklift.move(self.state, dx, dy, math.min(dt, 0.1), self.config,
        function(x, y) return x >= -120 and x <= 120 and y >= -80 and y <= 80 end, 1)
    if (dx ~= 0 or dy ~= 0) and not moved then self.message = tostring(reason) end
    local changed = Forklift.update(self.state, dt, self.config)
    return moved or changed
end

function Model:advanceToHeight(height)
    local ok = self:setHeight(height)
    if not ok then return false end
    local steps = 0
    while self.state.forklift.lifting and steps < 7200 do
        Forklift.update(self.state, 1 / 60, self.config)
        steps = steps + 1
    end
    return not self.state.forklift.lifting and math.abs(self.state.forklift.forkHeight - height) < 0.000001,
        steps
end

function Model:keypressed(key)
    if key == "left" or key == "up" then return self:selectDirection(self.selectedDirection - 1) end
    if key == "right" or key == "down" then return self:selectDirection(self.selectedDirection + 1) end
    if key == "space" then return self:toggleLift() end
    if key == "t" then return self:setHeight(self.config.travelHeight or 0.08) end
    if key == "g" then return self:setHeight(0) end
    if key == "p" then self:togglePause(); return true end
    if key == "r" then self:reset(); return true end
    local digit = tonumber(key)
    if digit and digit >= 1 and digit <= 8 then return self:selectDirection(digit) end
    return false
end

function Lab.layout(width, height)
    width, height = math.max(320, width), math.max(420, height)
    local margin, gap, buttonHeight = 12, 6, 44
    local columns = width >= 760 and 8 or 4
    local directionRows = 8 / columns
    local buttonWidth = (width - margin * 2 - gap * (columns - 1)) / columns
    local buttons = {}
    for index = 1, 8 do
        buttons[#buttons + 1] = { id = "direction", index = index, label = labels[index],
            x = margin + ((index - 1) % columns) * (buttonWidth + gap),
            y = 70 + math.floor((index - 1) / columns) * (buttonHeight + gap),
            width = buttonWidth, height = buttonHeight }
    end
    local actionY = height - 112
    local actionLabels = { "RAISE / LOWER", "TRAVEL", "PAUSE", "GROUND" }
    local actionIds = { "toggle", "travel", "pause", "ground" }
    local actionWidth = (width - margin * 2 - gap * 3) / 4
    for index, label in ipairs(actionLabels) do
        buttons[#buttons + 1] = { id = actionIds[index], label = label,
            x = margin + (index - 1) * (actionWidth + gap), y = actionY,
            width = actionWidth, height = buttonHeight }
    end
    local top = 70 + directionRows * (buttonHeight + gap) + 10
    return { width = width, height = height, buttons = buttons,
        preview = { x = margin, y = top, width = width - margin * 2,
            height = math.max(100, actionY - top - 38) }, actionY = actionY }
end

-- Fit the union of every anchored source cell, including pixels below the
-- wheels. One shared scale and baseline prevents zooming/panning between views.
-- This transform is only for the isolated review lab, never the game renderer.
function Lab.previewTransform(preview, catalog)
    if type(preview) ~= "table" or not finite(preview.x) or not finite(preview.y)
        or not finite(preview.width) or preview.width <= 0
        or not finite(preview.height) or preview.height <= 0
    then return nil, "invalid_preview" end
    catalog = catalog or Presentation.reviewCatalog()
    if type(catalog) ~= "table" then return nil, "invalid_catalog" end
    local left, right, above, below = 0, 0, 0, 0
    for _, direction in ipairs(directions) do
        local sheet = catalog[direction]
        local valid, reason = Presentation.validateSheet(sheet)
        if not valid then return nil, reason end
        for _, frame in ipairs(sheet.frames) do
            local source, anchor = frame.source, frame.wheelAnchor
            left = math.max(left, anchor.x)
            right = math.max(right, source.width - anchor.x)
            above = math.max(above, anchor.y)
            below = math.max(below, source.height - anchor.y)
        end
    end
    local padding = math.min(12, preview.width / 4, preview.height / 4)
    local availableWidth, availableHeight = preview.width - padding * 2, preview.height - padding * 2
    local scale = math.min(0.65, availableWidth / (left + right), availableHeight / (above + below))
    return {
        x = preview.x + padding + (availableWidth - (left + right) * scale) / 2 + left * scale,
        y = preview.y + padding + (availableHeight - (above + below) * scale) / 2 + above * scale,
        scale = scale, padding = padding,
        extents = { left = left, right = right, above = above, below = below },
    }
end

function Model:activateAt(x, y, width, height)
    for _, button in ipairs(Lab.layout(width, height).buttons) do
        if x >= button.x and y >= button.y and x < button.x + button.width and y < button.y + button.height then
            if button.id == "direction" then return self:selectDirection(button.index) end
            if button.id == "toggle" then return self:toggleLift() end
            if button.id == "travel" then return self:setHeight(self.config.travelHeight or 0.08) end
            if button.id == "pause" then self:togglePause(); return true end
            if button.id == "ground" then return self:setHeight(0) end
        end
    end
    return false
end

local function cleanPath(path)
    if type(path) ~= "string" or path == "" or path:find("[%z\r\n]") then return nil end
    path = path:gsub("\\", "/"):gsub("/+$", "")
    for part in path:gmatch("[^/]+") do if part == ".." or part == "." then return nil end end
    return path
end

function Lab.captureDirectoryAllowed(requested, projectSource)
    local path, root = cleanPath(requested), cleanPath(projectSource)
    if not path or not root then return false end
    local expected = root .. captureSuffix
    if root:match("^%a:/") then return path:lower() == expected:lower(), expected end
    return path == expected and root:sub(1, 1) == "/", expected
end

function Lab.captureShot(index)
    if not finite(index) or index ~= math.floor(index) or index < 1 or index > 24 then return nil end
    local direction = math.floor((index - 1) / 3) + 1
    local phase = (index - 1) % 3 + 1
    local heights, names = { 0, 0.5, 1 }, { "lower", "mid", "high" }
    return { directionIndex = direction, direction = directions[direction], height = heights[phase],
        name = string.format("%02d-%s-%s.png", index, directions[direction], names[phase]) }
end

local instance
local function finishCapture(ok, message)
    print((ok and "[FORKLIFT LAB] PASS: " or "[FORKLIFT LAB] FAIL: ") .. tostring(message))
    io.flush()
    love.event.quit(ok and 0 or 1)
end

function Lab.load()
    love.filesystem.setIdentity("the-picture-shop-forklift-lab")
    assert(love.filesystem.getIdentity() == "the-picture-shop-forklift-lab")
    love.window.setTitle("The Picture Shop - Forklift Lift Lab (DRAFT ART)")
    instance = { model = Lab.newModel(), images = {}, captureIndex = 1,
        capturePending = false, capturePrepared = false, failedImages = {} }
    local requested = os.getenv("PICTURE_SHOP_FORKLIFT_LAB_CAPTURE_DIR")
    if requested and requested ~= "" then
        local allowed, directory = Lab.captureDirectoryAllowed(requested, love.filesystem.getSource())
        if not allowed then finishCapture(false, "Capture path must be this project's isolated forklift-lab-captures directory."); return end
        instance.captureDirectory = directory
        instance.captureStarted = love.timer.getTime()
    end
end

local function imageFor(path)
    if instance.failedImages[path] then return nil end
    if not instance.images[path] then
        local ok, image = pcall(love.graphics.newImage, path)
        if not ok then instance.failedImages[path] = tostring(image); return nil end
        image:setFilter("nearest", "nearest")
        instance.images[path] = image
    end
    return instance.images[path]
end

function Lab.update(dt)
    if not instance then return end
    if instance.captureDirectory then
        if love.timer.getTime() - instance.captureStarted > 60 then
            finishCapture(false, "Capture cycle exceeded its 60-second bound."); return
        end
        if not instance.capturePending and not instance.capturePrepared then
            local shot = Lab.captureShot(instance.captureIndex)
            if not shot then finishCapture(true, "Captured all 24 lower/mid/high direction views."); return end
            instance.model:reset()
            instance.model:selectDirection(shot.directionIndex)
            assert(instance.model:advanceToHeight(shot.height), "deterministic lift failed")
            instance.capturePrepared = true
        end
        return
    end
    local dx = (love.keyboard.isDown("d") and 1 or 0) - (love.keyboard.isDown("a") and 1 or 0)
    local dy = (love.keyboard.isDown("s") and 1 or 0) - (love.keyboard.isDown("w") and 1 or 0)
    instance.model:update(dt, dx, dy)
end

local function captureCurrent()
    if not instance.captureDirectory or instance.capturePending or not instance.capturePrepared then return end
    local shot = Lab.captureShot(instance.captureIndex)
    if not shot then return end
    instance.capturePending = true
    love.graphics.captureScreenshot(function(imageData)
        local success, message = pcall(function()
            local path = instance.captureDirectory .. "/" .. shot.name
            local existing = io.open(path, "rb")
            if existing then existing:close(); error("Refusing to overwrite existing capture: " .. path) end
            local encoded = imageData:encode("png")
            local file, openError = io.open(path, "wb")
            if not file then encoded:release(); error(openError) end
            local written, writeError = file:write(encoded:getString())
            local closed, closeError = file:close()
            encoded:release()
            if not written or not closed then error(writeError or closeError or "PNG write failed") end
        end)
        imageData:release()
        if not success then finishCapture(false, message); return end
        instance.captureIndex = instance.captureIndex + 1
        instance.capturePending, instance.capturePrepared = false, false
        if instance.captureIndex > 24 then finishCapture(true, "Captured all 24 lower/mid/high direction views.") end
    end)
end

function Lab.draw()
    if not instance then return end
    local graphics, model = love.graphics, instance.model
    local width, height = graphics.getDimensions()
    local layout = Lab.layout(width, height)
    local preview = layout.preview
    graphics.clear(0.07, 0.08, 0.09, 1)
    graphics.setColor(1, 0.82, 0.25, 1)
    graphics.printf("FORKLIFT LIFT LAB - DRAFT SOURCE ART", 12, 14, width - 24, "center")
    graphics.setColor(0.85, 0.88, 0.9, 1)
    graphics.printf("Isolated test fixture: no live shop, saves, customers or inventory.", 12, 38, width - 24, "center")
    graphics.setScissor(preview.x, preview.y, preview.width, preview.height)
    for row = 0, math.ceil(preview.height / 24) do
        for column = 0, math.ceil(preview.width / 24) do
            local shade = (row + column) % 2 == 0 and 0.19 or 0.24
            graphics.setColor(shade, shade, shade, 1)
            graphics.rectangle("fill", preview.x + column * 24, preview.y + row * 24, 24, 24)
        end
    end
    local display = copy(model.state.forklift)
    local catalog = Presentation.reviewCatalog()
    local transform = assert(Lab.previewTransform(preview, catalog))
    display.x = transform.x + display.x
    display.y = transform.y + display.y
    local options = { review = true, scale = transform.scale, catalog = catalog }
    local plan = Presentation.plan(display, options)
    graphics.setColor(0.1, 0.9, 0.9, 0.7)
    graphics.line(preview.x, display.y, preview.x + preview.width, display.y)
    graphics.line(display.x, preview.y, display.x, preview.y + preview.height)
    local drawn, reason = Presentation.draw(display, imageFor, options)
    if plan then
        graphics.setColor(1, 0.4, 0.2, 1)
        graphics.circle("line", plan.loadX, plan.loadY, 6)
        graphics.line(plan.loadX - 10, plan.loadY, plan.loadX + 10, plan.loadY)
        graphics.line(plan.loadX, plan.loadY - 10, plan.loadX, plan.loadY + 10)
    end
    graphics.setScissor()
    if not drawn then
        graphics.setColor(1, 0.4, 0.3, 1)
        graphics.printf("Source unavailable: " .. tostring(reason), preview.x, preview.y + 20, preview.width, "center")
        if instance.captureDirectory then finishCapture(false, reason); return end
    end
    graphics.setColor(1, 1, 1, 1)
    local lift = model.state.forklift
    graphics.printf(string.format("%s | forks %.1f%% -> %.1f%% | frame %d / 4 | %s",
        lift.direction:upper(), lift.forkHeight * 100, lift.targetForkHeight * 100,
        plan and plan.frameIndex or 0, model.paused and "PAUSED" or (lift.lifting and "LIFTING" or "STOPPED")),
        12, layout.actionY - 28, width - 24, "center")
    for _, button in ipairs(layout.buttons) do
        local active = button.id == "direction" and button.index == model.selectedDirection
            or button.id == "pause" and model.paused
        graphics.setColor(active and 0.55 or 0.2, active and 0.4 or 0.23, active and 0.08 or 0.27, 1)
        graphics.rectangle("fill", button.x, button.y, button.width, button.height, 5, 5)
        graphics.setColor(0.8, 0.83, 0.88, 1)
        graphics.rectangle("line", button.x, button.y, button.width, button.height, 5, 5)
        graphics.setColor(1, 1, 1, 1)
        graphics.printf(button.id == "pause" and model.paused and "RESUME" or button.label,
            button.x + 3, button.y + 14, button.width - 6, "center")
    end
    graphics.setColor(0.85, 0.88, 0.9, 1)
    graphics.printf("Arrows / 1-8: view | Space: raise/lower | T: travel | P: pause | WASD: drive | Esc: exit",
        12, height - 55, width - 24, "center")
    graphics.setColor(1, 0.72, 0.25, 1)
    graphics.printf("Art not integrated: halos, heading and anchor corrections still under review.",
        12, height - 30, width - 24, "center")
    captureCurrent()
end

function Lab.keypressed(key)
    if key == "escape" then love.event.quit(); return end
    if instance and not instance.captureDirectory then instance.model:keypressed(key) end
end

function Lab.mousepressed(x, y, button, istouch)
    if button ~= 1 or istouch or not instance or instance.captureDirectory then return end
    instance.model:activateAt(x, y, love.graphics.getDimensions())
end

function Lab.touchpressed(_, x, y)
    if instance and not instance.captureDirectory then
        instance.model:activateAt(x, y, love.graphics.getDimensions())
    end
end

function Lab.quit()
    if instance then for _, image in pairs(instance.images) do image:release() end end
    instance = nil
end

return Lab
