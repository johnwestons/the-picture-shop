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
        -- Keep scene art square on wide phones. The camera can use the extra
        -- horizontal space; touch controls use gameBounds to reach its edges.
        local scale=math.min(width/baseWidth,height/baseHeight)
        local offsetX=x+(width-baseWidth*scale)*.5
        local offsetY=y+(height-baseHeight*scale)*.5
        return offsetX,offsetY,scale,scale,scale
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

function Viewport.drawGutters(baseWidth, baseHeight)
    if not Viewport.fullScreenDevice() then return end
    local bounds=Viewport.gameBounds(baseWidth,baseHeight)
    if bounds.left>=0 and bounds.right<=baseWidth then return end
    local g=love.graphics
    g.push('all');g.setShader();g.setScissor()
    for _,band in ipairs({{bounds.left,0},{baseWidth,bounds.right}}) do
        local left,right=band[1],band[2]
        if right>left then
            g.setColor(.045,.073,.077,1)
            g.rectangle('fill',left,bounds.top,right-left,bounds.height)
            g.setColor(.11,.17,.16,.42)
            for y=0,baseHeight,46 do g.rectangle('fill',left,y,right-left,1) end
            g.setColor(.37,.32,.21,.64)
            g.rectangle('fill',right==0 and right-2 or left,bounds.top,2,bounds.height)
        end
    end
    g.pop()
end

function Viewport.drawWorldBackdrop(bounds,camera)
    if not Viewport.fullScreenDevice() then return end
    local left,top=camera:screenToWorld(bounds.left,bounds.top)
    local right,bottom=camera:screenToWorld(bounds.right,bounds.bottom)
    local g=love.graphics
    g.push('all');g.setShader()
    g.setColor(.045,.073,.077,1)
    g.rectangle('fill',left,top,right-left,bottom-top)
    g.setColor(.11,.17,.16,.35)
    for x=math.floor(left/48)*48,right,48 do g.rectangle('fill',x,top,1,bottom-top) end
    for y=math.floor(top/48)*48,bottom,48 do g.rectangle('fill',left,y,right-left,1) end
    g.pop()
end

return Viewport
