local Ui = {}
local pressFeedback = nil

function Ui.contains(rect, x, y)
    return x >= rect.x and y >= rect.y
        and x <= rect.x + rect.width and y <= rect.y + rect.height
end

function Ui.commaNumber(value)
    local text = tostring(math.floor(value or 0))
    local changed
    repeat text, changed = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until changed == 0
    return text
end

function Ui.money(value) return "$" .. Ui.commaNumber(value) end

function Ui.box(x, y, width, height, fill, border, radius, lineWidth)
    radius = radius or 0
    love.graphics.setColor(fill)
    love.graphics.rectangle("fill", x, y, width, height, radius, radius)
    if border then
        love.graphics.setColor(border)
        love.graphics.setLineWidth(lineWidth or 2)
        love.graphics.rectangle("line", x, y, width, height, radius, radius)
    end
end

function Ui.panel(rect, fill, border, radius, lineWidth)
    Ui.box(rect.x, rect.y, rect.width, rect.height, fill, border, radius or 4, lineWidth)
end

function Ui.notePress(x, y)
    if not x or not y then return end
    pressFeedback = { x = x, y = y, at = love.timer.getTime() }
end

function Ui.drawPressFeedback()
    if not pressFeedback then return end
    local age = love.timer.getTime() - pressFeedback.at
    if age > 0.24 then pressFeedback = nil; return end
    local progress = age / 0.24
    love.graphics.setColor(0.98, 0.82, 0.25, 0.9 * (1 - progress))
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", pressFeedback.x, pressFeedback.y, 5 + progress * 18)
    love.graphics.setColor(1, 1, 1, 1)
end

return Ui
