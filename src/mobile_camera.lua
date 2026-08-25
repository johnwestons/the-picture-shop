local MobileCamera = {}
MobileCamera.__index = MobileCamera

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function MobileCamera.new(options)
    options = options or {}
    local self = setmetatable({}, MobileCamera)
    self.enabled = options.enabled == true
    self.baseWidth = options.baseWidth or 960
    self.baseHeight = options.baseHeight or 678
    self.centerX = self.baseWidth / 2
    self.centerY = self.baseHeight / 2
    self.zoom = 1
    self.minimumZoom = 1
    self.maximumZoom = options.maximumZoom or 2.75
    self.viewWidth = self.baseWidth
    self.viewHeight = self.baseHeight
    self.initialized = false
    self.viewKey = nil
    self.savedViews = {}
    return self
end

function MobileCamera:selectView(key, fillScreen)
    key = key or "default"
    if self.viewKey == key then return end
    if self.viewKey then
        self.savedViews[self.viewKey] = {
            centerX = self.centerX,
            centerY = self.centerY,
            zoom = self.zoom,
        }
    end
    self:endGesture()
    self.viewKey = key
    local saved = self.savedViews[key]
    if saved then
        self.centerX, self.centerY, self.zoom = saved.centerX, saved.centerY, saved.zoom
    else
        self.centerX, self.centerY = self.baseWidth / 2, self.baseHeight / 2
        local fillZoom = math.max(
            self.viewWidth / self.baseWidth,
            self.viewHeight / self.baseHeight
        )
        self.zoom = fillScreen and fillZoom or 1
    end
    self.zoom = clamp(self.zoom, self.minimumZoom, self.maximumZoom)
    self:_clampCenter()
end

function MobileCamera:isEnabled()
    return self.enabled
end

function MobileCamera:_clampCenter()
    local visibleWidth = self.viewWidth / self.zoom
    local visibleHeight = self.viewHeight / self.zoom
    if visibleWidth >= self.baseWidth then
        self.centerX = self.baseWidth / 2
    else
        self.centerX = clamp(self.centerX, visibleWidth / 2, self.baseWidth - visibleWidth / 2)
    end
    if visibleHeight >= self.baseHeight then
        self.centerY = self.baseHeight / 2
    else
        self.centerY = clamp(self.centerY, visibleHeight / 2, self.baseHeight - visibleHeight / 2)
    end
end

function MobileCamera:setViewport(viewWidth, viewHeight)
    self.viewWidth = math.max(1, viewWidth or self.baseWidth)
    self.viewHeight = math.max(1, viewHeight or self.baseHeight)
    self.minimumZoom = math.min(1, math.max(
        self.viewWidth / self.baseWidth,
        self.viewHeight / self.baseHeight
    ))
    local fillZoom = math.max(
        self.viewWidth / self.baseWidth,
        self.viewHeight / self.baseHeight
    )
    if not self.initialized then
        self.zoom = clamp(fillZoom, self.minimumZoom, self.maximumZoom)
        self.initialized = true
    else
        self.zoom = clamp(self.zoom, self.minimumZoom, self.maximumZoom)
    end
    self:_clampCenter()
end

function MobileCamera:screenToWorld(gameX, gameY)
    return self.centerX + (gameX - self.baseWidth / 2) / self.zoom,
        self.centerY + (gameY - self.baseHeight / 2) / self.zoom
end

function MobileCamera:worldToScreen(worldX, worldY)
    return self.baseWidth / 2 + (worldX - self.centerX) * self.zoom,
        self.baseHeight / 2 + (worldY - self.centerY) * self.zoom
end

function MobileCamera:beginGesture(gameX, gameY, distance)
    if not self.enabled then return false end
    local anchorX, anchorY = self:screenToWorld(gameX, gameY)
    self.gesture = {
        anchorX = anchorX,
        anchorY = anchorY,
        startDistance = math.max(1, distance or 1),
        startZoom = self.zoom,
    }
    return true
end

function MobileCamera:updateGesture(gameX, gameY, distance)
    if not self.gesture then return false end
    local gesture = self.gesture
    self.zoom = clamp(
        gesture.startZoom * math.max(1, distance or 1) / gesture.startDistance,
        self.minimumZoom,
        self.maximumZoom
    )
    self.centerX = gesture.anchorX - (gameX - self.baseWidth / 2) / self.zoom
    self.centerY = gesture.anchorY - (gameY - self.baseHeight / 2) / self.zoom
    self:_clampCenter()
    return true
end

function MobileCamera:endGesture()
    self.gesture = nil
end

function MobileCamera:beginDraw()
    love.graphics.push("all")
    love.graphics.translate(self.baseWidth / 2, self.baseHeight / 2)
    love.graphics.scale(self.zoom, self.zoom)
    love.graphics.translate(-self.centerX, -self.centerY)
end

function MobileCamera:endDraw()
    love.graphics.pop()
end

function MobileCamera:snapshot()
    return {
        centerX = self.centerX,
        centerY = self.centerY,
        zoom = self.zoom,
        minimumZoom = self.minimumZoom,
        maximumZoom = self.maximumZoom,
    }
end

return MobileCamera
