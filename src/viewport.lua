local Viewport = {}

function Viewport.fullScreenDevice()
    local osName=love.system and love.system.getOS and love.system.getOS()
    return osName=='Android'
end

local function usableArea(safeArea)
    local windowWidth, windowHeight = love.graphics.getDimensions()
    if safeArea and not Viewport.fullScreenDevice() and love.window and love.window.getSafeArea then
        local x, y, width, height = love.window.getSafeArea()
        if x and y and width and height and width > 0 and height > 0 then
            x, y = math.max(0, x), math.max(0, y)
            width, height = math.min(width, windowWidth - x), math.min(height, windowHeight - y)
            if width > 0 and height > 0 then return x, y, width, height end
        end
    end
    return 0, 0, windowWidth, windowHeight
end

function Viewport.transform(baseWidth, baseHeight, safeArea)
    local x, y, width, height = usableArea(safeArea)
    if Viewport.fullScreenDevice() then
        -- Mobile layouts are authored for landscape. Fill the complete drawable
        -- surface so the UI, world, and touch targets do not sit in side bars.
        local scaleX,scaleY=width/baseWidth,height/baseHeight
        return x,y,math.min(scaleX,scaleY),scaleX,scaleY
    end
    local scale = math.min(width / baseWidth, height / baseHeight)
    local offsetX = math.floor(x + (width - baseWidth * scale) / 2)
    local offsetY = math.floor(y + (height - baseHeight * scale) / 2)
    return offsetX, offsetY, scale, scale, scale
end

function Viewport.beginDraw(baseWidth, baseHeight, clip, safeArea)
    local offsetX, offsetY, _, scaleX, scaleY = Viewport.transform(baseWidth, baseHeight, safeArea)
    love.graphics.push("all")
    love.graphics.translate(offsetX, offsetY)
    love.graphics.scale(scaleX, scaleY)
    if clip ~= false then
        love.graphics.setScissor(offsetX, offsetY, baseWidth * scaleX, baseHeight * scaleY)
    else
        love.graphics.setScissor()
    end
end

function Viewport.gameBounds(baseWidth, baseHeight, safeArea)
    local x, y, width, height = usableArea(safeArea)
    local offsetX, offsetY, _, scaleX, scaleY = Viewport.transform(baseWidth, baseHeight, safeArea)
    return {
        left = (x - offsetX) / scaleX,
        top = (y - offsetY) / scaleY,
        right = (x + width - offsetX) / scaleX,
        bottom = (y + height - offsetY) / scaleY,
        width = width / scaleX,
        height = height / scaleY,
        scale = math.min(scaleX,scaleY),
        scaleX = scaleX,
        scaleY = scaleY,
    }
end

function Viewport.endDraw()
    love.graphics.setScissor()
    love.graphics.pop()
end

function Viewport.toGame(x, y, baseWidth, baseHeight, safeArea)
    local offsetX, offsetY, _, scaleX, scaleY = Viewport.transform(baseWidth, baseHeight, safeArea)
    return (x - offsetX) / scaleX, (y - offsetY) / scaleY
end

return Viewport
