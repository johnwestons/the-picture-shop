local Viewport = {}

function Viewport.transform(baseWidth, baseHeight)
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local scale = math.min(windowWidth / baseWidth, windowHeight / baseHeight)
    local offsetX = math.floor((windowWidth - baseWidth * scale) / 2)
    local offsetY = math.floor((windowHeight - baseHeight * scale) / 2)
    return offsetX, offsetY, scale
end

function Viewport.beginDraw(baseWidth, baseHeight, clip)
    local offsetX, offsetY, scale = Viewport.transform(baseWidth, baseHeight)
    love.graphics.push("all")
    love.graphics.translate(offsetX, offsetY)
    love.graphics.scale(scale, scale)
    if clip ~= false then
        love.graphics.setScissor(offsetX, offsetY, baseWidth * scale, baseHeight * scale)
    else
        love.graphics.setScissor()
    end
end

function Viewport.gameBounds(baseWidth, baseHeight)
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local offsetX, offsetY, scale = Viewport.transform(baseWidth, baseHeight)
    return {
        left = -offsetX / scale,
        top = -offsetY / scale,
        right = (windowWidth - offsetX) / scale,
        bottom = (windowHeight - offsetY) / scale,
        width = windowWidth / scale,
        height = windowHeight / scale,
        scale = scale,
    }
end

function Viewport.endDraw()
    love.graphics.setScissor()
    love.graphics.pop()
end

function Viewport.toGame(x, y, baseWidth, baseHeight)
    local offsetX, offsetY, scale = Viewport.transform(baseWidth, baseHeight)
    return (x - offsetX) / scale, (y - offsetY) / scale
end

return Viewport
