local Config = require("src.config")
local BackButton = require("src.screens.back_button")

local JobOfferScreen = {}

local PANEL = { x = 100, y = 32, width = 760, height = 610 }
local BUTTONS = {
    back = { x = 714, y = 44, width = 126, height = 40 },
    decline = { x = 258, y = 574, width = 160, height = 46 },
    accept = { x = 542, y = 574, width = 160, height = 46 },
}

local function contains(rect, x, y)
    return x >= rect.x and y >= rect.y
        and x <= rect.x + rect.width
        and y <= rect.y + rect.height
end

local function commaNumber(value)
    local text = tostring(math.floor(value or 0))
    local changed
    repeat
        text, changed = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until changed == 0
    return text
end

local function money(value)
    return "$" .. commaNumber(value)
end

local function sizeText(size)
    return string.format("%g × %g inches", size.width, size.height)
end

local function line(label, value, x, y)
    love.graphics.setColor(0.28, 0.30, 0.31)
    love.graphics.print(label, x, y)
    love.graphics.setColor(0.08, 0.09, 0.10)
    love.graphics.print(value, x + 122, y)
end

local function button(action, label, pointerX, pointerY)
    local rect = BUTTONS[action]
    local hovered = pointerX and pointerY and contains(rect, pointerX, pointerY)
    if action == "accept" then
        love.graphics.setColor(hovered and 0.18 or 0.12, hovered and 0.55 or 0.43, 0.28)
    else
        love.graphics.setColor(hovered and 0.70 or 0.57, 0.18, 0.17)
    end
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(0.98, 0.98, 0.96)
    love.graphics.printf(label, rect.x, rect.y + 15, rect.width, "center")
end

function JobOfferScreen.hitTest(x, y)
    if contains(BUTTONS.back, x, y) then return "back" end
    if contains(BUTTONS.accept, x, y) then return "accept" end
    if contains(BUTTONS.decline, x, y) then return "decline" end
    return nil
end

function JobOfferScreen.buttonCenter(action)
    local rect = BUTTONS[action]
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function JobOfferScreen.draw(state, pointerX, pointerY, assets)
    local job = state.currentOffer
    love.graphics.setColor(0.01, 0.02, 0.03, 0.72)
    love.graphics.rectangle("fill", 0, 0, Config.baseWidth, Config.baseHeight)

    love.graphics.setColor(0.94, 0.92, 0.84)
    love.graphics.rectangle("fill", PANEL.x, PANEL.y, PANEL.width, PANEL.height, 5, 5)
    love.graphics.setColor(0.17, 0.22, 0.25)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", PANEL.x, PANEL.y, PANEL.width, PANEL.height, 5, 5)
    love.graphics.rectangle("fill", PANEL.x, PANEL.y, PANEL.width, 66, 5, 5)
    love.graphics.setColor(0.97, 0.84, 0.30)
    love.graphics.printf("CUSTOMER CUTTING JOB TICKET", PANEL.x, PANEL.y + 14, PANEL.width, "center")
    love.graphics.setColor(0.84, 0.88, 0.88)
    love.graphics.printf("Quote based on $150 per 500-sheet lift", PANEL.x, PANEL.y + 38, PANEL.width, "center")
    BackButton.draw(assets, BUTTONS.back, "BACK", pointerX, pointerY, false)

    if not job then
        love.graphics.setColor(0.58, 0.12, 0.12)
        love.graphics.printf("No valid job paperwork is available.", PANEL.x, 310, PANEL.width, "center")
        return
    end

    local details = job.details or {}
    line("Company", job.company, 136, 116)
    line("Job number", job.id, 136, 140)
    line("Parent sheet", sizeText(job.sourceSize), 136, 174)
    line("Finished size", sizeText(job.finishedSize), 136, 198)
    line("Stock", details.stockDescription or "Customer-supplied paper", 136, 222)
    line("Packaging", job.packaging == "boxed" and "Boxes on pallet, stretch-wrapped" or "Flat on pallet, stretch-wrapped", 520, 222)

    local tableX, tableY = 136, 260
    love.graphics.setColor(0.78, 0.76, 0.68)
    love.graphics.rectangle("fill", tableX, tableY, 688, 28)
    love.graphics.setColor(0.11, 0.12, 0.13)
    love.graphics.print("PALLET", tableX + 16, tableY + 7)
    love.graphics.print("SHEETS", tableX + 178, tableY + 7)
    love.graphics.print("500-SHEET LIFTS", tableX + 342, tableY + 7)
    love.graphics.print("PRICE", tableX + 574, tableY + 7)

    for index, pallet in ipairs(job.quote.pallets) do
        local rowY = tableY + 28 + (index - 1) * 28
        love.graphics.setColor(index % 2 == 0 and 0.88 or 0.91, 0.89, 0.82)
        love.graphics.rectangle("fill", tableX, rowY, 688, 28)
        love.graphics.setColor(0.10, 0.11, 0.12)
        love.graphics.print(tostring(pallet.number), tableX + 35, rowY + 7)
        love.graphics.print(commaNumber(pallet.sheetCount), tableX + 188, rowY + 7)
        love.graphics.print(tostring(pallet.requiredLifts), tableX + 390, rowY + 7)
        love.graphics.print(money(pallet.price), tableX + 584, rowY + 7)
    end

    love.graphics.setColor(0.12, 0.14, 0.15)
    love.graphics.print(
        string.format("TOTAL: %d pallets  •  %s sheets  •  %d lifts", job.quote.palletCount,
            commaNumber(job.quote.totalSheets), job.quote.totalLifts),
        136,
        442
    )
    love.graphics.setColor(0.10, 0.39, 0.24)
    love.graphics.printf("JOB VALUE  " .. money(job.quote.totalPrice), 580, 442, 244, "right")

    line("Grain/handling", details.grainDirection or "Follow customer labels", 136, 472)
    line("Due", details.dueDate or "Standard turnaround", 136, 496)
    love.graphics.setColor(0.28, 0.30, 0.31)
    love.graphics.print("Notes", 136, 520)
    love.graphics.setColor(0.08, 0.09, 0.10)
    love.graphics.printf(details.notes or "", 258, 520, 566, "left")

    button("decline", "DECLINE", pointerX, pointerY)
    button("accept", "ACCEPT JOB", pointerX, pointerY)
    love.graphics.setColor(0.32, 0.34, 0.34)
    love.graphics.printf("Accept, decline, or return to the conversation", PANEL.x, 628, PANEL.width, "center")
end

return JobOfferScreen
