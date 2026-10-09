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
    self.followTarget = nil
    self.followOffsetY = options.followOffsetY or 0
    self.followMaxSpeed = options.followMaxSpeed or 420
    self.followAcceleration = options.followAcceleration or 1800
    self.followResponse = options.followResponse or 0.18
    self.followVelocityX, self.followVelocityY = 0, 0
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
    self.followTarget = nil
    self.followVelocityX, self.followVelocityY = 0, 0
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
    -- Following ignores floor bounds so it can keep its target in view even
    -- at the warehouse edge. The center itself moves in update(), not here.
    if self.followTarget then
        return
    end
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

function MobileCamera:setFollowTarget(target, offsetY)
    if self.followTarget ~= target then
        self:endGesture()
        if not target then self.followVelocityX, self.followVelocityY = 0, 0 end
    end
    self.followTarget = target
    self.followTargetOffsetY = offsetY == nil and self.followOffsetY or offsetY
    self:_clampCenter()
end

local function moveToward(x, y, targetX, targetY, maximumDistance)
    local dx, dy = targetX - x, targetY - y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= maximumDistance or distance < 0.000001 then return targetX, targetY end
    local scale = maximumDistance / distance
    return x + dx * scale, y + dy * scale
end

function MobileCamera:update(dt)
    local target = self.followTarget
    if not target or type(target.x) ~= "number" or type(target.y) ~= "number" then return end

    -- Clamp long frames so a pause or network hitch cannot turn one camera
    -- update into a large teleport. A speed limit also bounds catch-up after
    -- a sudden target jump.
    local elapsed = math.min(math.max(0, tonumber(dt) or 0), 0.1)
    if elapsed <= 0 then return end
    local targetX = target.x
    local targetY = target.y + (self.followTargetOffsetY or 0)
    local dx, dy = targetX - self.centerX, targetY - self.centerY
    local distance = math.sqrt(dx * dx + dy * dy)
    local speed = math.sqrt(self.followVelocityX ^ 2 + self.followVelocityY ^ 2)
    if distance < 0.02 and speed < self.followAcceleration * elapsed then
        self.centerX, self.centerY = targetX, targetY
        self.followVelocityX, self.followVelocityY = 0, 0
        return
    end

    local desiredSpeed = math.min(self.followMaxSpeed, distance / math.max(0.01, self.followResponse))
    local desiredX, desiredY = 0, 0
    if distance > 0.000001 then
        desiredX, desiredY = dx / distance * desiredSpeed, dy / distance * desiredSpeed
    end
    self.followVelocityX, self.followVelocityY = moveToward(
        self.followVelocityX, self.followVelocityY, desiredX, desiredY,
        self.followAcceleration * elapsed)
    self.centerX = self.centerX + self.followVelocityX * elapsed
    self.centerY = self.centerY + self.followVelocityY * elapsed

    -- Avoid overshooting a nearby target while retaining the eased motion for
    -- larger corrections and quick direction changes.
    local remainingX, remainingY = targetX - self.centerX, targetY - self.centerY
    if dx * remainingX + dy * remainingY <= 0 then
        self.centerX, self.centerY = targetX, targetY
        self.followVelocityX, self.followVelocityY = 0, 0
    end
end

function MobileCamera:zoomBy(factor)
    if not self.enabled and not self.followTarget then return false end
    self:endGesture()
    self.zoom = clamp(self.zoom * factor, self.minimumZoom, self.maximumZoom)
    self:_clampCenter()
    return true
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
        following = self.followTarget ~= nil,
    }
end

return MobileCamera
