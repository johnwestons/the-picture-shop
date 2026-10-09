-- Generated Polar 115 casing, display and pushbutton sprites. Nine-slicing
-- preserves the steel posts, clamp rails and screws at every menu size.
local Skin = {}
Skin.dimensions = {
    titleMenuShell = { 1629, 965 },
    titleMenuFields = { 1536, 1024 },
    titleMenuButtons = { 1254, 1254 },
    titleMenuControl = { 1882, 836 },
    titleMenuPallets = { 1536, 1024 },
    titleMenuShelf = { 2152, 731 },
    titleMenuInk = { 1536, 1024 },
    titleMenuToolboxes = { 1536, 1024 },
    titleMenuPalletAnimation = { 1536, 1024 },
    titleMenuInkAnimation = { 1536, 1024 },
    titleMenuToolboxAnimation = { 1536, 1024 },
    titleMenuPalletFocus = { 1536, 1024 },
    titleMenuInkFocus = { 1536, 1024 },
    titleMenuToolboxFocus = { 1536, 1024 },
}
local cached = setmetatable({}, { __mode = "k" })
local sources = {
    shell = { image = "titleMenuShell", x = 64, y = 64, width = 1504, height = 832,
        edges = { 96, 120, 96, 96 } },
}
for index, state in ipairs({ "normal", "hover", "selected", "pressed" }) do
    sources["field-" .. state] = { image = "titleMenuFields", x = 62,
        y = ({ 70, 299, 528, 760 })[index], width = 1414, height = 188,
        edges = { 70, 62, 70, 44 } }
end
for index, state in ipairs({ "normal", "hover", "pressed", "disabled" }) do
    for column, kind in ipairs({ "button", "danger" }) do
        sources[kind .. "-" .. state] = { image = "titleMenuButtons",
            x = column == 1 and 46 or 660, y = ({ 97, 368, 640, 914 })[index],
            width = 550, height = 242, edges = { 62, 68, 62, 57 } }
    end
end

local function slices(image, name)
    local entries = cached[image]
    if not entries then entries = {}; cached[image] = entries end
    if entries[name] then return entries[name] end
    local source = assert(sources[name], "Unknown title sprite: " .. tostring(name))
    local left, top, right, bottom = unpack(source.edges)
    local widths = { left, source.width - left - right, right }
    local heights = { top, source.height - top - bottom, bottom }
    local result, y = {}, source.y
    for row = 1, 3 do
        local x = source.x
        for column = 1, 3 do
            result[#result + 1] = { row = row, column = column,
                width = widths[column], height = heights[row],
                quad = love.graphics.newQuad(x, y, widths[column], heights[row], image:getDimensions()) }
            x = x + widths[column]
        end
        y = y + heights[row]
    end
    entries[name] = result
    return result
end

local function draw(assets, name, rect, left, top, right, bottom)
    local source = assert(sources[name], "Unknown title sprite: " .. tostring(name))
    local image = assets and assets.get(source.image)
    if not image then return false end
    -- Scale corner blocks together for tiny +/- buttons and the slider handle.
    local scale = math.min(1, rect.width / (left + right), rect.height / (top + bottom))
    left, top, right, bottom = left * scale, top * scale, right * scale, bottom * scale
    local widths, heights = { left, rect.width - left - right, right },
        { top, rect.height - top - bottom, bottom }
    local xs, ys = { rect.x, rect.x + left, rect.x + rect.width - right },
        { rect.y, rect.y + top, rect.y + rect.height - bottom }
    love.graphics.setColor(1, 1, 1, 1)
    for _, slice in ipairs(slices(image, name)) do
        if widths[slice.column] > 0 and heights[slice.row] > 0 then
            love.graphics.draw(image, slice.quad, xs[slice.column], ys[slice.row], 0,
                widths[slice.column] / slice.width, heights[slice.row] / slice.height)
        end
    end
    return true
end

function Skin.panel(assets, rect)
    return draw(assets, "shell", rect, 12, 16, 12, 12)
end

function Skin.field(assets, rect, state)
    return draw(assets, "field-" .. (state or "normal"), rect, 11, 9, 11, 8)
end

function Skin.button(assets, rect, state, danger)
    return draw(assets, (danger and "danger-" or "button-") .. (state or "normal"),
        rect, 11, 10, 11, 9)
end

function Skin.slider(assets, rect, amount)
    Skin.field(assets, { x = rect.x, y = rect.y + 9, width = rect.width, height = 14 }, "normal")
    local x = rect.x + math.max(0, math.min(1, amount)) * rect.width
    Skin.field(assets, { x = x - 10, y = rect.y + 3, width = 20, height = 26 }, "selected")
end

return Skin
