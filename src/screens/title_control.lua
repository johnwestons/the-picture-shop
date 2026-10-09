-- The title is printed in the paper sprite. Only the cutter LCD receives
-- live text; preserve the machine's proportions when sizing the whole control.
local Control = {}
local Fonts = require("src.screens.title_fonts")
local SOURCE = { x = 28, y = 54, width = 1838, height = 738 }
local DISPLAY = { x = 414, y = 185, width = 766, height = 153 }
local quads = setmetatable({}, { __mode = "k" })

local function fitText(text, width, height)
    local font, lines, capacity
    for size = 24, 10, -1 do
        font = Fonts.get("lcd", size)
        local _
        _, lines = font:getWrap(text, width)
        capacity = math.max(1, math.floor(height / font:getHeight()))
        if #lines <= capacity then break end
    end
    if #lines > capacity then
        local last = lines[capacity]
        while #last > 0 and font:getWidth(last .. "...") > width do
            -- UTF-8 messages must be shortened at a complete codepoint.
            local shortened = last:gsub("[\194-\244][\128-\191]*$", "")
            last = shortened == last and last:sub(1, -2) or shortened
        end
        lines[capacity] = last .. "..."
        for index = #lines, capacity + 1, -1 do lines[index] = nil end
    end
    return font, lines
end

function Control.draw(assets, x, y, width, text)
    local image = assets and assets.get("titleMenuControl")
    if not image then return false end
    local quad = quads[image]
    if not quad then
        quad = love.graphics.newQuad(SOURCE.x, SOURCE.y, SOURCE.width, SOURCE.height, image:getDimensions())
        quads[image] = quad
    end
    local scale = width / SOURCE.width
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, quad, x, y, 0, scale, scale)
    local displayX = x + (DISPLAY.x - SOURCE.x) * scale
    local displayY = y + (DISPLAY.y - SOURCE.y) * scale
    local displayWidth, displayHeight = DISPLAY.width * scale, DISPLAY.height * scale
    local font, lines = fitText(tostring(text or ""), displayWidth, displayHeight)
    love.graphics.setFont(font)
    love.graphics.setColor(.98, .79, .47, 1)
    local firstY = displayY + (displayHeight - #lines * font:getHeight()) / 2
    for index, line in ipairs(lines) do
        love.graphics.printf(line, displayX, firstY + (index - 1) * font:getHeight(), displayWidth, "center")
    end
    return true
end

return Control
