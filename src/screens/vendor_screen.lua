local Procurement = require("src.procurement")
local BackButton = require("src.screens.back_button")
local Screen = {}
local CLOSE = { x = 742, y = 70, width = 132, height = 42 }
local ROW = { x = 104, y = 220, width = 752, height = 94, gap = 22 }

local function inside(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height
end

local function box(rect, fill, line)
    love.graphics.setColor(fill); love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setColor(line); love.graphics.setLineWidth(2); love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 5, 5)
end

local function row(index)
    return { x = ROW.x, y = ROW.y + (index - 1) * (ROW.height + ROW.gap), width = ROW.width, height = ROW.height }
end

local function buyRect(index)
    local r = row(index); return { x = r.x + r.width - 158, y = r.y + 24, width = 132, height = 48 }
end

function Screen.draw(state, assets, pointerX, pointerY)
    local category = Procurement.category(state.vendorCategory)
    box({ x = 64, y = 48, width = 832, height = 570 }, { 0.045, 0.06, 0.075, 0.99 }, { 0.40, 0.66, 0.72, 1 })
    love.graphics.setColor(0.96, 0.82, 0.26); love.graphics.print(category.name .. " SALESMAN", 104, 82)
    love.graphics.setColor(0.84, 0.91, 0.92); love.graphics.print(category.salesman .. " is showing products available by pallet delivery.", 104, 116)
    love.graphics.print(string.format("AVAILABLE CASH: $%d", state.money or 0), 104, 150)
    BackButton.draw(assets, CLOSE, "BACK", pointerX, pointerY, false)
    for index, item in ipairs(category.items) do
        local r, buy = row(index), buyRect(index)
        local affordable = (state.money or 0) >= item.price
        box(r, { 0.075, 0.11, 0.14, 1 }, { 0.26, 0.43, 0.49, 1 })
        love.graphics.setColor(0.94, 0.97, 0.95); love.graphics.print(item.name, r.x + 22, r.y + 20)
        love.graphics.setColor(0.68, 0.78, 0.81); love.graphics.print("Delivered on its own labeled warehouse pallet", r.x + 22, r.y + 52)
        box(buy, affordable and { 0.16, 0.45, 0.31, 1 } or { 0.18, 0.19, 0.20, 1 },
            affordable and { 0.48, 0.86, 0.58, 1 } or { 0.36, 0.38, 0.40, 1 })
        love.graphics.setColor(affordable and 0.95 or 0.58, affordable and 0.98 or 0.62, affordable and 0.95 or 0.64)
        love.graphics.printf(string.format("BUY  $%d", item.price), buy.x, buy.y + 16, buy.width, "center")
    end
    love.graphics.setColor(0.70, 0.78, 0.80)
    love.graphics.print("Purchases are charged now. The delivery truck will arrive at the loading dock.", 104, 548)
end

function Screen.mousepressed(state, x, y, button)
    if button ~= 1 then return nil end
    if inside(CLOSE, x, y) then return { action = "close" } end
    local category = Procurement.category(state.vendorCategory)
    for index = 1, #category.items do
        if inside(buyRect(index), x, y) then
            local ok, result = Procurement.buy(state, state.vendorCategory, index)
            if ok then
                state.message = string.format("Purchased %s. %s is awaiting truck delivery.", result.productName, result.id)
                return { action = "purchased", order = result }
            end
            state.message = result
            return { action = "blocked" }
        end
    end
end

function Screen.buyButtonCenter(index)
    local r = buyRect(index); return r.x + r.width / 2, r.y + r.height / 2
end

function Screen.closeCenter()
    return CLOSE.x + CLOSE.width / 2, CLOSE.y + CLOSE.height / 2
end

return Screen
