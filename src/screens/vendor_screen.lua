local Procurement = require("src.procurement")
local MachineFleet = require("src.machine_fleet")
local BackButton = require("src.screens.back_button")
local Ui = require("src.screens.ui")
local Screen = {}
local CLOSE = { x = 742, y = 70, width = 132, height = 42 }
local NO_THANKS = { x = 676, y = 486, width = 180, height = 46 }
local ROW = { x = 104, y = 178, width = 752, height = 52, gap = 6 }
local MACHINE_ROW = { x = 104, y = 190, width = 752, height = 84, gap = 8 }

local inside = Ui.contains
local function box(rect, fill, line) Ui.panel(rect, fill, line, 5, 2) end

local function row(index)
    return { x = ROW.x, y = ROW.y + (index - 1) * (ROW.height + ROW.gap), width = ROW.width, height = ROW.height }
end

local function buyRect(index)
    local r = row(index); return { x = r.x + r.width - 158, y = r.y + 6, width = 132, height = 40 }
end

local function machineRow(index)
    return { x = MACHINE_ROW.x, y = MACHINE_ROW.y + (index - 1) * (MACHINE_ROW.height + MACHINE_ROW.gap),
        width = MACHINE_ROW.width, height = MACHINE_ROW.height }
end

local function machineBuyRect(index)
    local r = machineRow(index)
    return { x = r.x + r.width - 158, y = r.y + 18, width = 132, height = 48 }
end

function Screen.draw(state, assets, pointerX, pointerY)
    local category = Procurement.category(state.vendorCategory)
    box({ x = 64, y = 48, width = 832, height = 570 }, { 0.045, 0.06, 0.075, 0.99 }, { 0.40, 0.66, 0.72, 1 })
    love.graphics.setColor(0.96, 0.82, 0.26); love.graphics.print(category.name .. " SALESMAN", 104, 82)
    love.graphics.setColor(0.84, 0.91, 0.92)
    love.graphics.print(category.kind == "machines"
        and (category.salesman .. " offers used dealer machines. Inspect the condition before buying.")
        or (category.salesman .. " offers discounted bulk pallet deals."), 104, 116)
    love.graphics.print(string.format("AVAILABLE CASH: $%d", state.money or 0), 104, 150)
    BackButton.draw(assets, CLOSE, "BACK", pointerX, pointerY, false)
    if category.kind == "machines" then
        for index, offer in ipairs(MachineFleet.offers("dealer")) do
            local r, buy = machineRow(index), machineBuyRect(index)
            local affordable = (state.money or 0) >= offer.price
            box(r, { 0.075, 0.11, 0.14, 1 }, { 0.26, 0.43, 0.49, 1 })
            love.graphics.setColor(0.94, 0.97, 0.95)
            love.graphics.print(offer.name, r.x + 22, r.y + 18)
            love.graphics.setColor(offer.condition >= 55 and 0.91 or 0.94,
                offer.condition >= 55 and 0.69 or 0.38, 0.24)
            love.graphics.print(string.format("%s • %.0f%% condition • used dealer inventory",
                offer.conditionStatus, offer.condition), r.x + 22, r.y + 47)
            love.graphics.setColor(0.62, 0.70, 0.72)
            love.graphics.print("Lower purchase price; component service may be due.", r.x + 22, r.y + 66)
            box(buy, affordable and { 0.16, 0.45, 0.31, 1 } or { 0.18, 0.19, 0.20, 1 },
                affordable and { 0.48, 0.86, 0.58, 1 } or { 0.36, 0.38, 0.40, 1 })
            love.graphics.setColor(affordable and 0.95 or 0.58, affordable and 0.98 or 0.62,
                affordable and 0.95 or 0.64)
            love.graphics.printf(string.format("BUY  $%d", offer.price),
                buy.x, buy.y + 16, buy.width, "center")
        end
    else
        for index, item in ipairs(category.items) do
            local r, buy = row(index), buyRect(index)
            local available = item.available ~= false
            local affordable = available and (state.money or 0) >= item.price
            box(r, { 0.075, 0.11, 0.14, 1 }, { 0.26, 0.43, 0.49, 1 })
            love.graphics.setColor(0.94, 0.97, 0.95); love.graphics.print(item.name, r.x + 22, r.y + 9)
            love.graphics.setColor(0.68, 0.78, 0.81)
            local bulkLine = string.format("Bulk $%.2f/%s  |  computer $%.2f/%s  |  dock delivery",
                item.price / item.quantity, item.unit, (item.retailPrice or item.price) / (item.retailQuantity or item.quantity), item.unit)
            love.graphics.print(available and bulkLine or item.unavailableReason, r.x + 22, r.y + 30)
            box(buy, affordable and { 0.16, 0.45, 0.31, 1 } or { 0.18, 0.19, 0.20, 1 },
                affordable and { 0.48, 0.86, 0.58, 1 } or { 0.36, 0.38, 0.40, 1 })
            love.graphics.setColor(affordable and 0.95 or 0.58, affordable and 0.98 or 0.62,
                affordable and 0.95 or 0.64)
            love.graphics.printf(available and string.format("BUY  $%d", item.price) or "LOCKED",
                buy.x, buy.y + 12, buy.width, "center")
        end
    end
    love.graphics.setColor(0.72, 0.80, 0.81)
    love.graphics.print("Nothing needed today? Dismiss this visit without placing an order.", 104, 501)
    BackButton.draw(assets, NO_THANKS, "NO THANKS", pointerX, pointerY, false)
    love.graphics.setColor(0.70, 0.78, 0.80)
    love.graphics.print(category.kind == "machines"
        and "Machines are charged now. Extra units are held in shop storage."
        or "Purchases are charged now. The delivery truck will arrive at the loading dock.", 104, 548)
end

function Screen.mousepressed(state, x, y, button)
    if button ~= 1 then return nil end
    if inside(CLOSE, x, y) then return { action = "close" } end
    if inside(NO_THANKS, x, y) then return { action = "no_thanks" } end
    local category = Procurement.category(state.vendorCategory)
    if category.kind == "machines" then
        for index = 1, #MachineFleet.offers("dealer") do
            if inside(machineBuyRect(index), x, y) then
                local ok, result = MachineFleet.buy(state, "dealer", index)
                if ok then
                    state.message = string.format("Purchased used %s at %.0f%% condition. Unit %s is %s.",
                        result.name, result.condition, result.id, result.status)
                    return { action = "machine_purchased", machine = result }
                end
                state.message = result
                return { action = "blocked" }
            end
        end
        return nil
    end
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
    local r = machineBuyRect(index); return r.x + r.width / 2, r.y + r.height / 2
end

function Screen.closeCenter()
    return CLOSE.x + CLOSE.width / 2, CLOSE.y + CLOSE.height / 2
end

function Screen.noThanksCenter()
    return NO_THANKS.x + NO_THANKS.width / 2, NO_THANKS.y + NO_THANKS.height / 2
end

return Screen
