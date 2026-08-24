local Ui = require("src.screens.ui")

local BackButton = {}

function BackButton.contains(rect, x, y)
    return Ui.contains(rect, x, y)
end

function BackButton.draw(assets, rect, label, pointerX, pointerY, pressed)
    local hovered = pointerX and pointerY and BackButton.contains(rect, pointerX, pointerY)
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
    love.graphics.setColor(0.94, 0.94, 0.90)
    love.graphics.printf(label or "BACK", rect.x, rect.y + rect.height / 2 - 6, rect.width, "center")
end

return BackButton
