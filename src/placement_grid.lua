local Grid = {}

local function round(value)
    return math.floor(value + 0.5)
end

function Grid.snap(x, y, config)
    config = config or {}
    local width = config.cellWidth or 32
    local height = config.cellHeight or 24
    local originX = config.originX or 0
    local originY = config.originY or 0
    return originX + round((x - originX) / width) * width,
        originY + round((y - originY) / height) * height
end

function Grid.cells(centerX, centerY, config, canPlace)
    config = config or {}
    local width = config.cellWidth or 32
    local height = config.cellHeight or 24
    local radius = config.previewRadius or 3
    local maxDistance = config.selectionRadius or 104
    local snappedX, snappedY = Grid.snap(centerX, centerY, config)
    local cells = {}
    for row = -radius, radius do
        for column = -radius, radius do
            local x = snappedX + column * width
            local y = snappedY + row * height
            local dx, dy = x - centerX, y - centerY
            if dx * dx + dy * dy <= maxDistance * maxDistance then
                cells[#cells + 1] = {
                    x = x,
                    y = y,
                    valid = canPlace(x, y) == true,
                }
            end
        end
    end
    return cells, snappedX, snappedY
end

function Grid.hit(cells, x, y, config)
    config = config or {}
    local halfWidth = (config.cellWidth or 32) * 0.48
    local halfHeight = (config.cellHeight or 24) * 0.48
    local best, bestDistance
    for _, cell in ipairs(cells or {}) do
        local normalized = math.abs(x - cell.x) / halfWidth + math.abs(y - cell.y) / halfHeight
        if normalized <= 1 then
            local distance = (x - cell.x) ^ 2 + (y - cell.y) ^ 2
            if not bestDistance or distance < bestDistance then
                best, bestDistance = cell, distance
            end
        end
    end
    return best
end

function Grid.draw(snapshot)
    if not snapshot then return end
    local config = snapshot.config or {}
    local halfWidth = (config.cellWidth or 32) * 0.48
    local halfHeight = (config.cellHeight or 24) * 0.48
    love.graphics.setLineWidth(1)
    for _, cell in ipairs(snapshot.cells or {}) do
        local selected = snapshot.selected
            and snapshot.selected.x == cell.x and snapshot.selected.y == cell.y
        if cell.valid then
            love.graphics.setColor(selected and 0.35 or 0.12,
                selected and 1.00 or 0.82, selected and 0.38 or 0.25,
                selected and 0.62 or 0.28)
        else
            love.graphics.setColor(0.85, 0.16, 0.12, 0.12)
        end
        love.graphics.polygon("fill",
            cell.x, cell.y - halfHeight,
            cell.x + halfWidth, cell.y,
            cell.x, cell.y + halfHeight,
            cell.x - halfWidth, cell.y)
        love.graphics.setColor(cell.valid and 0.35 or 0.72,
            cell.valid and 1.00 or 0.20, cell.valid and 0.42 or 0.16,
            selected and 0.95 or 0.48)
        love.graphics.polygon("line",
            cell.x, cell.y - halfHeight,
            cell.x + halfWidth, cell.y,
            cell.x, cell.y + halfHeight,
            cell.x - halfWidth, cell.y)
    end
    love.graphics.setColor(1, 1, 1)
end

return Grid
