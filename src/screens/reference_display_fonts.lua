-- Display-only bitmap faces derived from the approved font sheets.
local Atlas = require("assets.fonts.reference-inspired.font-atlases")
local DisplayFonts = {}

local fonts
local EM_HEIGHT = 132
local TOP_BEARING = 30

local function face(kind)
    fonts = fonts or Atlas.load()
    return fonts[kind]
end

local function wordsAndWidth(font, text, spaceWidth)
    local words, width = {}, 0
    for word in tostring(text):gmatch("%S+") do
        if #words > 0 then width = width + spaceWidth end
        words[#words + 1] = word
        width = width + font:getWidth(word)
    end
    return words, width
end

function DisplayFonts.draw(kind, text, x, y, visibleHeight, alignment, maxWidth)
    local g = love.graphics
    local original = g.getFont()
    local font = face(kind)
    local scale = visibleHeight / EM_HEIGHT
    local spaceWidth = EM_HEIGHT * 0.34
    local words, textWidth = wordsAndWidth(font, text, spaceWidth)

    if maxWidth and textWidth * scale > maxWidth then
        scale = scale * maxWidth / (textWidth * scale)
    end
    local drawnWidth = textWidth * scale
    if alignment == "center" then x = x + (maxWidth - drawnWidth) * 0.5
    elseif alignment == "right" then x = x + maxWidth - drawnWidth end

    g.setFont(font)
    for _, word in ipairs(words) do
        g.print(word, x, y - TOP_BEARING * scale, 0, scale, scale)
        x = x + (font:getWidth(word) + spaceWidth) * scale
    end
    g.setFont(original)
end

return DisplayFonts
