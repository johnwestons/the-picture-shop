local MobileControls = {}
MobileControls.__index = MobileControls

local function defaultEnabled()
    if os.getenv("PICTURE_SHOP_MOBILE") == "1" then return true end
    return love and love.system and love.system.getOS and love.system.getOS() == "Android"
end

local function distance(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

function MobileControls.new(options)
    options = options or {}
    local self = setmetatable({}, MobileControls)
    self.enabled = options.enabled
    if self.enabled == nil then self.enabled = defaultEnabled() end
    self.toGame = assert(options.toGame, "mobile controls require toGame")
    self.pressKey = assert(options.pressKey, "mobile controls require pressKey")
    self.releaseKey = assert(options.releaseKey, "mobile controls require releaseKey")
    self.pressPointer = assert(options.pressPointer, "mobile controls require pressPointer")
    self.movePointer = assert(options.movePointer, "mobile controls require movePointer")
    self.releasePointer = assert(options.releasePointer, "mobile controls require releasePointer")
    self.gameplayActive = assert(options.gameplayActive, "mobile controls require gameplayActive")
    self.primaryAction = options.primaryAction or function() return "e", "USE" end
    self.extraActions = options.extraActions or function() return {} end
    self.afterInput = options.afterInput or function() end
    self.beginGesture = options.beginGesture or function() end
    self.updateGesture = options.updateGesture or function() end
    self.endGesture = options.endGesture or function() end
    self.touches = {}
    self.touchOrder = 0
    self.axisX, self.axisY = 0, 0
    self.pointerX, self.pointerY = nil, nil
    self.joystick = { x = 98, y = 574, radius = 72, knob = 29 }
    self.primary = { x = 870, y = 574, radius = 55 }
    self.extra = {
        { x = 767, y = 604, radius = 36 },
        { x = 767, y = 518, radius = 36 },
    }
    return self
end

function MobileControls:isEnabled() return self.enabled end
function MobileControls:ignoreSyntheticMouse(isTouch) return self.enabled and isTouch == true end
function MobileControls:movement() return self.axisX, self.axisY end
function MobileControls:pointer() return self.pointerX, self.pointerY end

function MobileControls:setBounds(bounds)
    if not bounds then return end
    self.joystick.x = bounds.left + 100
    self.joystick.y = bounds.bottom - 104
    self.primary.x = bounds.right - 90
    self.primary.y = bounds.bottom - 104
    self.extra[1].x = bounds.right - 193
    self.extra[1].y = bounds.bottom - 74
    self.extra[2].x = bounds.right - 193
    self.extra[2].y = bounds.bottom - 160
end

function MobileControls:_updatePointer(screenX, screenY)
    self.pointerX, self.pointerY = self.toGame(screenX, screenY)
    return self.pointerX, self.pointerY
end

function MobileControls:_updateJoystick(x, y)
    local stick = self.joystick
    local dx, dy = x - stick.x, y - stick.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < stick.radius * 0.15 then
        self.axisX, self.axisY = 0, 0
    elseif length > 0 then
        local magnitude = math.min(1, length / stick.radius)
        self.axisX, self.axisY = dx / length * magnitude, dy / length * magnitude
    end
end

function MobileControls:_buttonAt(x, y)
    if distance(x, y, self.primary.x, self.primary.y) <= self.primary.radius * 1.2 then
        local key, label = self.primaryAction()
        if key then return key, label end
    end
    local actions = self.extraActions() or {}
    for index, action in ipairs(actions) do
        local button = self.extra[index]
        if button and distance(x, y, button.x, button.y) <= button.radius * 1.25 then
            return action.key, action.label
        end
    end
end

function MobileControls:_startGestureIfReady()
    local candidates = {}
    for id, touch in pairs(self.touches) do
        if touch.kind == "pending" then
            candidates[#candidates + 1] = { id = id, touch = touch }
        end
    end
    if #candidates < 2 then return false end
    table.sort(candidates, function(a, b) return a.touch.order < b.touch.order end)
    local first, second = candidates[1], candidates[2]
    first.touch.kind, second.touch.kind = "gesture", "gesture"
    self.gestureTouches = { first.id, second.id }
    local midX = (first.touch.x + second.touch.x) / 2
    local midY = (first.touch.y + second.touch.y) / 2
    local separation = distance(first.touch.screenX, first.touch.screenY,
        second.touch.screenX, second.touch.screenY)
    self.beginGesture(midX, midY, separation)
    return true
end

function MobileControls:_updateGesture()
    if not self.gestureTouches then return false end
    local first = self.touches[self.gestureTouches[1]]
    local second = self.touches[self.gestureTouches[2]]
    if not first or not second then return false end
    local midX = (first.x + second.x) / 2
    local midY = (first.y + second.y) / 2
    local separation = distance(first.screenX, first.screenY, second.screenX, second.screenY)
    self.updateGesture(midX, midY, separation)
    self.pointerX, self.pointerY = midX, midY
    return true
end

function MobileControls:touchpressed(id, screenX, screenY)
    if not self.enabled then return false end
    local x, y = self:_updatePointer(screenX, screenY)
    if self.gameplayActive() then
        local stick = self.joystick
        if not self.joystickTouch and x <= stick.x + stick.radius * 1.65
            and y >= stick.y - stick.radius * 1.65
        then
            self.joystickTouch = id
            self.touches[id] = { kind = "joystick" }
            self:_updateJoystick(x, y)
            return true
        end
        local key = self:_buttonAt(x, y)
        if key then
            self.touches[id] = { kind = "key", key = key }
            self.pressKey(key)
            self.afterInput(x, y)
            return true
        end
    end
    if self.gameplayActive() then
        if self.gestureTouches then
            self.touches[id] = { kind = "ignored", screenX = screenX, screenY = screenY, x = x, y = y }
            return true
        end
        self.touchOrder = self.touchOrder + 1
        self.touches[id] = {
            kind = "pending", order = self.touchOrder,
            screenX = screenX, screenY = screenY, x = x, y = y,
        }
        self:_startGestureIfReady()
    else
        self.touches[id] = { kind = "pointer" }
        self.pressPointer(screenX, screenY, 1)
        self.afterInput(x, y)
    end
    return true
end

function MobileControls:touchmoved(id, screenX, screenY, dx, dy)
    if not self.enabled then return false end
    local x, y = self:_updatePointer(screenX, screenY)
    local touch = self.touches[id]
    if not touch then return false end
    touch.screenX, touch.screenY, touch.x, touch.y = screenX, screenY, x, y
    if touch.kind == "joystick" then
        self:_updateJoystick(x, y)
    elseif touch.kind == "pointer" then
        self.movePointer(screenX, screenY, dx or 0, dy or 0)
    elseif touch.kind == "gesture" then
        self:_updateGesture()
    end
    return true
end

function MobileControls:touchreleased(id, screenX, screenY)
    if not self.enabled then return false end
    local x, y = self:_updatePointer(screenX, screenY)
    local touch = self.touches[id]
    if not touch then return false end
    if touch.kind == "joystick" then
        if self.joystickTouch == id then
            self.joystickTouch = nil
            self.axisX, self.axisY = 0, 0
        end
    elseif touch.kind == "key" then
        self.releaseKey(touch.key)
    elseif touch.kind == "pointer" then
        self.releasePointer(screenX, screenY, 1)
        self.afterInput(x, y)
    elseif touch.kind == "pending" then
        self.pressPointer(screenX, screenY, 1)
        self.releasePointer(screenX, screenY, 1)
        self.afterInput(x, y)
    elseif touch.kind == "gesture" then
        local partnerId = self.gestureTouches and (self.gestureTouches[1] == id
            and self.gestureTouches[2] or self.gestureTouches[1])
        local partner = partnerId and self.touches[partnerId]
        if partner then partner.kind = "ignored" end
        self.gestureTouches = nil
        self.endGesture()
    end
    self.touches[id] = nil
    return true
end

function MobileControls:cancelAll()
    for _, touch in pairs(self.touches) do
        if touch.kind == "key" then self.releaseKey(touch.key) end
    end
    self.touches = {}
    self.joystickTouch = nil
    self.gestureTouches = nil
    self.endGesture()
    self.axisX, self.axisY = 0, 0
end

local function drawRoundButton(button, label, active, small)
    love.graphics.setColor(0.025, 0.055, 0.07, 0.72)
    love.graphics.circle("fill", button.x, button.y, button.radius)
    love.graphics.setColor(active and 0.98 or 0.42, active and 0.82 or 0.73, active and 0.25 or 0.78, 0.95)
    love.graphics.setLineWidth(small and 3 or 4)
    love.graphics.circle("line", button.x, button.y, button.radius)
    love.graphics.setColor(0.96, 0.98, 0.92, 0.98)
    love.graphics.printf(label or "USE", button.x - button.radius, button.y - (small and 6 or 8),
        button.radius * 2, "center", 0, small and 0.72 or 0.88, small and 0.72 or 0.88)
end

function MobileControls:draw()
    if not self.enabled or not self.gameplayActive() then return end
    local stick = self.joystick
    love.graphics.setColor(0.025, 0.055, 0.07, 0.58)
    love.graphics.circle("fill", stick.x, stick.y, stick.radius)
    love.graphics.setColor(0.42, 0.73, 0.78, 0.88)
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", stick.x, stick.y, stick.radius)
    love.graphics.line(stick.x - 42, stick.y, stick.x + 42, stick.y)
    love.graphics.line(stick.x, stick.y - 42, stick.x, stick.y + 42)
    love.graphics.setColor(0.98, 0.82, 0.25, 0.94)
    love.graphics.circle("fill", stick.x + self.axisX * stick.radius * 0.70,
        stick.y + self.axisY * stick.radius * 0.70, stick.knob)

    local _, primaryLabel = self.primaryAction()
    drawRoundButton(self.primary, primaryLabel or "USE", false, false)
    for index, action in ipairs(self.extraActions() or {}) do
        if self.extra[index] then drawRoundButton(self.extra[index], action.label, false, true) end
    end
    love.graphics.setLineWidth(1)
end

return MobileControls
