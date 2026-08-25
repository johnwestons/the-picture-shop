local Config = require("src.config")
local BusinessCalendar = require("src.business_calendar")
local BackButton = require("src.screens.back_button")

local Hud = {}
local EXIT = { x = 816, y = 14, width = 126, height = 40 }

local function shadowedPrint(text, x, y, color)
    love.graphics.setColor(0.04, 0.05, 0.06, 0.9)
    love.graphics.print(text, x + 2, y + 2)
    love.graphics.setColor(color)
    love.graphics.print(text, x, y)
end

local function shadowedPrintf(text, x, y, width, color)
    love.graphics.setColor(0.04, 0.05, 0.06, 0.9)
    love.graphics.printf(text, x + 2, y + 2, width, "left")
    love.graphics.setColor(color)
    love.graphics.printf(text, x, y, width, "left")
end

function Hud.draw(state, prompt, assets, pointerX, pointerY, mobile, controller)
    shadowedPrint("$" .. state.money, 24, 20, { 0.95, 0.84, 0.30 })
    shadowedPrint("Paper: " .. state.inventory.paper, 92, 20, { 0.88, 0.92, 0.94 })
    shadowedPrint("Finished: " .. state.inventory.prints, 190, 20, { 0.88, 0.92, 0.94 })
    shadowedPrint(BusinessCalendar.shortDate(state), 312, 20, { 0.74, 0.88, 0.89 })
    if state.bills and state.bills.balance > 0 then
        shadowedPrint("Bills due: $" .. state.bills.balance, 442, 20, { 0.96, 0.48, 0.30 })
    end
    BackButton.draw(assets, EXIT, "EXIT TO MENU", pointerX, pointerY, false)
    if state.message then
        shadowedPrintf(state.message, 24, 48, Config.baseWidth - 48, { 0.88, 0.92, 0.94 })
    end
    if prompt then
        local shownPrompt = mobile and prompt:gsub("^E:%s*", "TAP USE: ") or prompt
        shadowedPrint(shownPrompt, mobile and 250 or 360, Config.baseHeight - 52, { 0.95, 0.85, 0.35 })
    end
    shadowedPrint(
        controller and "LEFT STICK / D-PAD: MOVE    A: USE    X: PARK    Y: MOVE    START: MENU"
            or mobile and "DRAG LEFT CONTROL TO MOVE    TAP BUTTONS TO WORK"
            or "WASD / arrows: move    E: interact",
        22,
        Config.baseHeight - 28,
        { 0.82, 0.86, 0.88 }
    )
end

function Hud.hitTest(x, y)
    return BackButton.contains(EXIT, x, y) and "exit" or nil
end

return Hud
