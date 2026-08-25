local Controller = {}
Controller.__index = Controller

local dpadKeys = {
    dpleft = "left", dpright = "right", dpup = "up", dpdown = "down",
}

function Controller.new(options)
    local self = setmetatable({}, Controller)
    self.pressKey = assert(options.pressKey)
    self.releaseKey = assert(options.releaseKey)
    self.pressPointer = assert(options.pressPointer)
    self.releasePointer = assert(options.releasePointer)
    self.screenInfo = assert(options.screenInfo)
    self.worldMenuAction = assert(options.worldMenuAction)
    self.pointerX = options.pointerX or 480
    self.pointerY = options.pointerY or 339
    self.active = nil
    self.pointerHeld = false
    self.heldKeys = {}
    return self
end

function Controller:_findGamepad()
    if not love.joystick or not love.joystick.getJoysticks then return nil end
    for _, joystick in ipairs(love.joystick.getJoysticks()) do
        if joystick:isGamepad() then return joystick end
    end
end

function Controller:isActive()
    return self.active ~= nil
end

function Controller:pointer()
    return self.pointerX, self.pointerY
end

function Controller:update(dt)
    local current = self:_findGamepad()
    if current ~= self.active then
        self:cancelAll()
        self.active = current
    end
    if not self.active then return end
    local screen = self.screenInfo()
    if screen == "world" or screen == "asset_error" then return end
    local x = self.active:getGamepadAxis("rightx") or 0
    local y = self.active:getGamepadAxis("righty") or 0
    if math.abs(x) < 0.18 and math.abs(y) < 0.18 then
        x = self.active:getGamepadAxis("leftx") or 0
        y = self.active:getGamepadAxis("lefty") or 0
    end
    if math.abs(x) < 0.18 then x = 0 end
    if math.abs(y) < 0.18 then y = 0 end
    local speed = 520
    self.pointerX = math.max(0, math.min(960, self.pointerX + x * speed * dt))
    self.pointerY = math.max(0, math.min(678, self.pointerY + y * speed * dt))
end

function Controller:_pressMappedKey(button, key)
    self.heldKeys[button] = key
    self.pressKey(key)
    return true
end

function Controller:gamepadpressed(joystick, button)
    if not joystick or not joystick:isGamepad() then return false end
    self.active = joystick
    local screen, machineType = self.screenInfo()
    if dpadKeys[button] then return self:_pressMappedKey(button, dpadKeys[button]) end
    if screen == "world" then
        if button == "a" then return self:_pressMappedKey(button, "e")
        elseif button == "x" then return self:_pressMappedKey(button, "f")
        elseif button == "y" then return self:_pressMappedKey(button, "m")
        elseif button == "rightshoulder" then return self:_pressMappedKey(button, "q")
        elseif button == "start" then self.worldMenuAction(); return true end
        return false
    end
    if button == "b" or button == "back" or button == "start" then
        return self:_pressMappedKey(button, "escape")
    end
    if screen == "machine" and machineType == "cutter" then
        if button == "leftshoulder" then return self:_pressMappedKey(button, "j")
        elseif button == "rightshoulder" then return self:_pressMappedKey(button, "k")
        elseif button == "x" then return self:_pressMappedKey(button, "space")
        elseif button == "y" then return self:_pressMappedKey(button, "q") end
    end
    if button == "a" then
        self.pointerHeld = true
        self.pressPointer(self.pointerX, self.pointerY, 1)
        return true
    end
    return false
end

function Controller:gamepadreleased(joystick, button)
    if joystick ~= self.active then return false end
    local key = self.heldKeys[button]
    if key then
        self.heldKeys[button] = nil
        self.releaseKey(key)
        return true
    end
    if button == "a" and self.pointerHeld then
        self.pointerHeld = false
        self.releasePointer(self.pointerX, self.pointerY, 1)
        return true
    end
    return false
end

function Controller:cancelAll()
    for _, key in pairs(self.heldKeys) do self.releaseKey(key) end
    self.heldKeys = {}
    if self.pointerHeld then
        self.releasePointer(self.pointerX, self.pointerY, 1)
        self.pointerHeld = false
    end
end

function Controller:draw()
    if not self.active then return end
    local screen = self.screenInfo()
    if screen == "world" or screen == "asset_error" then return end
    love.graphics.setColor(0.02, 0.05, 0.07, 0.92)
    love.graphics.circle("fill", self.pointerX, self.pointerY, 13)
    love.graphics.setColor(0.98, 0.82, 0.25, 1)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", self.pointerX, self.pointerY, 13)
    love.graphics.line(self.pointerX - 18, self.pointerY, self.pointerX + 18, self.pointerY)
    love.graphics.line(self.pointerX, self.pointerY - 18, self.pointerX, self.pointerY + 18)
    love.graphics.setLineWidth(1)
end

return Controller
