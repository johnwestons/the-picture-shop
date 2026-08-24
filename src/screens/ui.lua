local Ui = {}

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

return Ui
