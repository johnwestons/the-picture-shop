local Ui = require("src.screens.ui")

local BackButton = {}

function BackButton.contains(rect, x, y)
    return Ui.contains(rect, x, y)
end

function BackButton.draw(assets, rect, label, pointerX, pointerY, pressed)
    local hovered = pointerX and pointerY and BackButton.contains(rect, pointerX, pointerY)
    pressed = pressed or (hovered and love.mouse and love.mouse.isDown and love.mouse.isDown(1))
    local frame = pressed and 3 or (hovered and 2 or 1)
    local image = assets and assets.get("polarBackButton")
    local sprite = assets and assets.getQuad("polarBackButton" .. frame)
    if image and sprite then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, sprite.quad, rect.x, rect.y, 0,
            rect.width / sprite.width, rect.height / sprite.height)
    else
        love.graphics.setColor(0.18, 0.19, 0.19, 1)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
    end
    require('src.screens.typography').label(label or 'BACK',rect)
end

return BackButton
