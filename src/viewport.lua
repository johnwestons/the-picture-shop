local Viewport = {}

local function usableArea(safeArea)
    local windowWidth, windowHeight = love.graphics.getDimensions()
    if safeArea and love.window and love.window.getSafeArea then
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
    local scale = math.min(width / baseWidth, height / baseHeight)
    local offsetX = math.floor(x + (width - baseWidth * scale) / 2)
    local offsetY = math.floor(y + (height - baseHeight * scale) / 2)
    return offsetX, offsetY, scale
end

function Viewport.beginDraw(baseWidth, baseHeight, clip, safeArea)
    local offsetX, offsetY, scale = Viewport.transform(baseWidth, baseHeight, safeArea)
    love.graphics.push("all")
    love.graphics.translate(offsetX, offsetY)
    love.graphics.scale(scale, scale)
    if clip ~= false then
        love.graphics.setScissor(offsetX, offsetY, baseWidth * scale, baseHeight * scale)
    else
        love.graphics.setScissor()
    end
end

function Viewport.gameBounds(baseWidth, baseHeight, safeArea)
    local x, y, width, height = usableArea(safeArea)
    local offsetX, offsetY, scale = Viewport.transform(baseWidth, baseHeight, safeArea)
    return {
        left = (x - offsetX) / scale,
        top = (y - offsetY) / scale,
        right = (x + width - offsetX) / scale,
        bottom = (y + height - offsetY) / scale,
        width = width / scale,
        height = height / scale,
        scale = scale,
    }
end

function Viewport.endDraw()
    love.graphics.setScissor()
    love.graphics.pop()
end

function Viewport.toGame(x, y, baseWidth, baseHeight, safeArea)
    local offsetX, offsetY, scale = Viewport.transform(baseWidth, baseHeight, safeArea)
    return (x - offsetX) / scale, (y - offsetY) / scale
end

return Viewport
