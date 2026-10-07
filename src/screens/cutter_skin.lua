-- Cosmetic nine-slice skins sampled from the approved steel GUI concept.
-- Text, machine artwork, control rectangles and input remain in MachineScreen.
local Skin = {}
local cached = setmetatable({}, { __mode = "k" })
local sources = {
    shell = { 59, 47, 1422, 775, 22 },
    normal = { 46, 848, 254, 98, 18 },
    hover = { 347, 851, 254, 94, 18 },
    pressed = { 646, 854, 244, 90, 18 },
    selected = { 1240, 851, 249, 96, 18 },
}

local function slices(image, name)
    local entries = cached[image]
    if not entries then entries = {}; cached[image] = entries end
    if entries[name] then return entries[name] end
    local source = sources[name]
    local x, y, w, h, edge = unpack(source)
    local widths, heights = { edge, w - edge * 2, edge }, { edge, h - edge * 2, edge }
    local result, sy = {}, y
    for row = 1, 3 do
        local sx = x
        for column = 1, 3 do
            result[#result + 1] = { row = row, column = column,
                width = widths[column], height = heights[row],
                quad = love.graphics.newQuad(sx, sy, widths[column], heights[row], image:getDimensions()) }
            sx = sx + widths[column]
        end
        sy = sy + heights[row]
    end
    entries[name] = result
    return result
end

local function nineSlice(assets, name, x, y, width, height, edge, borderOnly)
    local image = assets and assets.get("cutterGuiSteel")
    if not image then return false end
    edge = math.min(edge, width / 2, height / 2)
    local widths, heights = { edge, width - edge * 2, edge }, { edge, height - edge * 2, edge }
    local xs, ys = { x, x + edge, x + width - edge }, { y, y + edge, y + height - edge }
    love.graphics.setColor(1, 1, 1, 1)
    for _, slice in ipairs(slices(image, name)) do
        if not borderOnly or slice.row ~= 2 or slice.column ~= 2 then
            love.graphics.draw(image, slice.quad, xs[slice.column], ys[slice.row], 0,
                widths[slice.column] / slice.width, heights[slice.row] / slice.height)
        end
    end
    return true
end

function Skin.panel(x, y, width, height, focused, display)
    love.graphics.setColor(display and { .025, .065, .105, 1 } or { .035, .075, .115, 1 })
    love.graphics.rectangle("fill", x, y, width, height, 4, 4)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(.015, .025, .04, 1)
    love.graphics.rectangle("line", x, y, width, height, 4, 4)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(focused and { .45, .83, 1, 1 } or { .30, .55, .72, 1 })
    love.graphics.rectangle("line", x + 1.5, y + 1.5, width - 3, height - 3, 3, 3)
    love.graphics.setColor(.11, .23, .34, 1)
    love.graphics.line(x + 4, y + height - 3, x + width - 4, y + height - 3)
end

function Skin.button(assets, x, y, width, height, state)
    if not nineSlice(assets, state or "normal", x, y, width, height, height <= 30 and 4 or 5) then
        Skin.panel(x, y, width, height, state == "hover" or state == "selected")
    end
    if state == "selected" then
        love.graphics.setColor(.67, .89, 1, 1)
        love.graphics.rectangle("fill", x + 6, y + height - 4, width - 12, 2)
    end
end

function Skin.shell(assets)
    love.graphics.setColor(.035, .045, .06, 1)
    love.graphics.rectangle("fill", 18, 18, 924, 642, 5, 5)
    nineSlice(assets, "shell", 18, 18, 924, 642, 9, true)
    -- Small corner fasteners occupy only the existing outer margin.
    for _, p in ipairs({ {28, 28}, {932, 28}, {28, 650}, {932, 650} }) do
        love.graphics.setColor(.04, .05, .06, 1)
        love.graphics.circle("fill", p[1], p[2], 4.5)
        love.graphics.setColor(.66, .70, .73, 1)
        love.graphics.circle("fill", p[1], p[2] - .5, 3.3)
        love.graphics.setColor(.09, .12, .14, 1)
        love.graphics.setLineWidth(1)
        love.graphics.line(p[1] - 2, p[2], p[1] + 2, p[2])
        love.graphics.line(p[1], p[2] - 2, p[1], p[2] + 2)
    end
    love.graphics.setColor(.025, .065, .105, 1)
    love.graphics.rectangle("fill", 34, 27, 742, 27, 3, 3)
    love.graphics.setColor(.92, .65, .22, 1)
    love.graphics.rectangle("fill", 38, 48, 292, 1)
end

return Skin
