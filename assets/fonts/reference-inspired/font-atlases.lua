local glyphs = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
local base = "assets/fonts/reference-inspired/"

local function make(image, spacing)
    local font = love.graphics.newImageFont(base .. image, glyphs, spacing)
    font:setFilter("linear", "linear")
    return font
end

return {
    glyphs = glyphs,
    load = function()
        return {
            groovySlab = make("groove_slab.png", 2),
            arcadeFlash = make("arcade_flash.png", 3),
        }
    end,
}
