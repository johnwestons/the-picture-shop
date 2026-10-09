local Config = require("src.config")
local Fonts = {}
local cached = {}
local paths = { lcd = Config.paths.titleLcdFont, paper = Config.paths.workOrderFont,
    ink = Config.paths.titleInkFont, metal = Config.paths.titleMetalFont }

function Fonts.get(kind, size)
    local key = kind .. ":" .. size
    if not cached[key] then
        local font = love.graphics.newFont(assert(paths[kind]), size)
        font:setFilter(kind == "lcd" and "nearest" or "linear",
            kind == "lcd" and "nearest" or "linear")
        cached[key] = font
    end
    return cached[key]
end

function Fonts.fit(kind, text, size, width, height)
    for candidate = size, 9, -1 do
        local font = Fonts.get(kind, candidate)
        if font:getWidth(text) <= width and font:getHeight() <= height then return font end
    end
    return Fonts.get(kind, 9)
end

return Fonts
