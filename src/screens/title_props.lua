-- Source PNGs are kept unchanged. Pallet pockets stretch horizontally while
-- outer perspective and square inner end blocks keep their proportions.
local Props = {}
local cached = setmetatable({}, { __mode = "k" })
local palletRows = {
    normal = { y = 86, height = 214 }, hover = { y = 312, height = 214 },
    selected = { y = 542, height = 216 }, pressed = { y = 776, height = 172 },
    focus1 = { y = 138, height = 228, focused = true, bodyHeight = 214 },
    focus2 = { y = 518, height = 240, focused = true, bodyHeight = 214 },
    click1 = { y = 554, height = 190, animated = true },
    click2 = { y = 766, height = 190, animated = true },
}
local palletColumns = {
    left = { x = 25, edges = { 128, 159 } },
    right = { x = 784, edges = { 159, 128 } },
}
local inkRows = { normal = 34, hover = 289, pressed = 545, disabled = 775 }
local toolboxRows = { normal = 14, hover = 280, pressed = 540, disabled = 754 }
local inkAnimation = {
    focus1 = { y = 40, height = 352, focused = true, bodyHeight = 216 },
    focus2 = { y = 448, height = 472, focused = true, bodyHeight = 216, bottomExtra = 34 },
    click1 = { y = 544, height = 198 }, click2 = { y = 770, height = 214 },
}
local toolboxAnimation = {
    focus1 = { y = 76, height = 386, focused = true, bodyHeight = 258 },
    focus2 = { y = 489, height = 467, focused = true, bodyHeight = 258 },
    click1 = { y = 552, height = 204 }, click2 = { y = 758, height = 242 },
}
local labelCenters = {
    ink = { normal = 0.62, hover = 0.62, pressed = 0.585, disabled = 0.63 },
    toolbox = { normal = 0.755, hover = 0.72, pressed = 0.62, disabled = 0.72 },
}

function Props.labelCenter(kind, state)
    if kind == "ink" and inkAnimation[state] then
        return state == "focus1" and 0.58 or state == "focus2" and 0.63
            or state == "click2" and 0.645 or 0.635
    end
    if kind == "toolbox" and toolboxAnimation[state] then
        return state == "focus1" and 0.737 or state == "focus2" and 0.727
            or state == "click1" and 0.728 or 0.748
    end
    return labelCenters[kind][state or "normal"] or labelCenters[kind].normal
end

function Props.labelHeight(kind, state)
    return kind == "ink" and 0.35 or state == "pressed" and 0.23 or 0.30
end

local function quad(image, x, y, width, height)
    local entries = cached[image]
    if not entries then entries = {}; cached[image] = entries end
    local key = table.concat({ x, y, width, height }, ":")
    if not entries[key] then
        entries[key] = love.graphics.newQuad(x, y, width, height, image:getDimensions())
    end
    return entries[key]
end

local function drawPallet(assets, rect, state, column)
    local frame = palletRows[state or "normal"] or palletRows.normal
    local image = assets and assets.get(frame.focused and "titleMenuPalletFocus"
        or frame.animated and "titleMenuPalletAnimation" or "titleMenuPallets")
    if not image then return false end
    local source = palletColumns[column]
    local scale = rect.height / (frame.bodyHeight or frame.height)
    local leftEdge, rightEdge = source.edges[1], source.edges[2]
    if frame.focused then
        leftEdge, rightEdge = column == "left" and 240 or 159, column == "right" and 240 or 159
    end
    local sourceWidths = { leftEdge, 728 - leftEdge - rightEdge, rightEdge }
    local widths = { sourceWidths[1] * scale, 0, sourceWidths[3] * scale }
    widths[2] = math.max(0, rect.width - widths[1] - widths[3])
    local sourceX, targetX = source.x, rect.x
    love.graphics.setColor(1, 1, 1, 1)
    for index, sourceWidth in ipairs(sourceWidths) do
        love.graphics.draw(image, quad(image, sourceX, frame.y, sourceWidth, frame.height),
            targetX, rect.y + rect.height - frame.height * scale,
            0, widths[index] / sourceWidth, scale)
        sourceX, targetX = sourceX + sourceWidth, targetX + widths[index]
    end
    return true
end

function Props.palletPair(assets, rect, state)
    local gap = 2
    local width = (rect.width - gap) / 2
    local left = { x = rect.x, y = rect.y, width = width, height = rect.height }
    local right = { x = rect.x + width + gap, y = rect.y, width = width, height = rect.height }
    drawPallet(assets, left, state, "left")
    drawPallet(assets, right, state, "right")
    return left, right
end

function Props.shelf(assets, rect)
    local image = assets and assets.get("titleMenuShelf")
    if not image then return false end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, quad(image, 90, 56, 1974, 624), rect.x, rect.y,
        0, rect.width / 1974, rect.height / 624)
    return true
end

function Props.ink(assets, rect, state, danger)
    local frame = inkAnimation[state]
    if frame then
        local image = assets and assets.get(frame.focused and "titleMenuInkFocus" or "titleMenuInkAnimation")
        if not image then return false end
        love.graphics.setColor(1, 1, 1, 1)
        local width = frame.focused and 630 or 646
        local sourceX = frame.focused and (danger and 838 or 69) or (danger and 829 or 62)
        local scale = rect.height / (frame.bodyHeight or frame.height)
        love.graphics.draw(image, quad(image, sourceX, frame.y, width, frame.height), rect.x,
            rect.y + rect.height + (frame.bottomExtra or 0) * scale - frame.height * scale,
            0, rect.width / width, scale)
        return true
    end
    local image = assets and assets.get("titleMenuInk")
    if not image then return false end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, quad(image, danger and 838 or 69,
        inkRows[state or "normal"] or inkRows.normal, 630, 216), rect.x, rect.y,
        0, rect.width / 630, rect.height / 216)
    return true
end

function Props.toolbox(assets, rect, state)
    local frame = toolboxAnimation[state]
    if frame then
        local image = assets and assets.get(frame.focused and "titleMenuToolboxFocus" or "titleMenuToolboxAnimation")
        if not image then return false end
        love.graphics.setColor(1, 1, 1, 1)
        local width, sourceX = frame.focused and 1246 or 1132, frame.focused and 145 or 202
        local scale = rect.height / (frame.bodyHeight or frame.height)
        love.graphics.draw(image, quad(image, sourceX, frame.y, width, frame.height),
            rect.x, rect.y + rect.height - frame.height * scale, 0, rect.width / width, scale)
        return true
    end
    local image = assets and assets.get("titleMenuToolboxes")
    if not image then return false end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, quad(image, 202,
        toolboxRows[state or "normal"] or toolboxRows.normal, 1132, 258), rect.x, rect.y,
        0, rect.width / 1132, rect.height / 258)
    return true
end

return Props
