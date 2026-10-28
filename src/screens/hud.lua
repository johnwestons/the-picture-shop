local Config = require("src.config")
local BusinessCalendar = require("src.business_calendar")
local BackButton = require("src.screens.back_button")
local Ui = require("src.screens.ui")

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

function Hud.draw(state, prompt, assets, pointerX, pointerY, mobile, controller, bounds,
        followPlayerCamera,twelveHourTime,feedback)
    bounds = bounds or { left = 0, right = Config.baseWidth, bottom = Config.baseHeight }
    local left, right, bottom = mobile and bounds.left or 0,
        mobile and bounds.right or Config.baseWidth,
        mobile and bounds.bottom or Config.baseHeight
    EXIT.x, EXIT.y = right - EXIT.width - 18, 14
    local cashText = Ui.money(state.money)
    local cashWidth = math.max(112, math.min(180, love.graphics.getFont():getWidth(cashText) + 22))
    local cashX, cashY, cashHeight = left + 18, 13, 32
    local cashDelta, cashTimer, cashDuration = 0, 0, 1
    if feedback then cashDelta, cashTimer, cashDuration = feedback:cashEffect() end
    local cashAge = cashDuration - cashTimer
    local pulse = cashTimer > 0 and math.max(0, 1 - cashAge / 0.34) or 0
    local scale = 1 + pulse * 0.075
    local cashColor = { 0.71, 0.63, 0.35 }
    if cashTimer > 0 then
        cashColor = cashDelta >= 0 and { 0.36, 0.88, 0.60 } or { 1.0, 0.61, 0.36 }
    end
    love.graphics.push("all")
    love.graphics.translate(cashX + cashWidth / 2, cashY + cashHeight / 2)
    love.graphics.scale(scale, scale)
    love.graphics.translate(-cashX - cashWidth / 2, -cashY - cashHeight / 2)
    love.graphics.setColor(0.055, 0.075, 0.085, 0.94)
    love.graphics.rectangle("fill", cashX, cashY, cashWidth, cashHeight, 6, 6)
    love.graphics.setColor(cashColor[1], cashColor[2], cashColor[3], 0.28 + pulse * 0.68)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", cashX, cashY, cashWidth, cashHeight, 6, 6)
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.print(cashText, cashX + 11, cashY + 8)
    love.graphics.pop()
    if cashTimer > 0 then
        local fade = math.min(1, cashTimer / 0.25)
        local direction = cashDelta >= 0 and "+" or "−"
        local changeText = direction .. Ui.money(math.abs(cashDelta))
        love.graphics.push("all")
        love.graphics.setColor(cashColor[1], cashColor[2], cashColor[3], fade)
        love.graphics.print(changeText, cashX + 9, cashY + 33 - math.min(cashAge, 0.42) * 14)
        love.graphics.pop()
    end
    local paperX = left + math.max(160, cashWidth + 34)
    local samplesX, dateX = paperX + 98, paperX + 198
    shadowedPrint("Paper: " .. state.inventory.paper, paperX, 20, { 0.88, 0.92, 0.94 })
    shadowedPrint("Samples: " .. state.inventory.prints, samplesX, 20, { 0.88, 0.92, 0.94 })
    shadowedPrint(BusinessCalendar.shortDate(state), dateX, 20, { 0.74, 0.88, 0.89 })
    shadowedPrint("TIME "..BusinessCalendar.timeText(state,twelveHourTime),dateX,38,{.96,.85,.40})
    if state.bills and state.bills.balance > 0 then
        shadowedPrint("Bills due: $" .. state.bills.balance, dateX + 190, 20, { 0.96, 0.48, 0.30 })
    end
    BackButton.draw(assets, EXIT, "EXIT TO MENU", pointerX, pointerY, false)
    if state.message then
        shadowedPrintf(state.message, left + 24, 62, right - left - 48, { 0.88, 0.92, 0.94 })
    end
    if prompt then
        local shownPrompt = prompt
        if mobile then
            shownPrompt = shownPrompt:gsub("^E%s+or%s+F:%s*", "TAP USE / PARK: ")
                :gsub("^E:%s*", "TAP USE: ")
                :gsub("%s+X:%s*dismiss applicant", " / use DISMISS button")
        elseif controller then
            shownPrompt = shownPrompt:gsub("^E%s+or%s+F:%s*", "A or X: ")
                :gsub("^E:%s*", "A: ")
                :gsub("X:%s*dismiss applicant", "B: dismiss applicant")
        end
        shadowedPrint(shownPrompt, mobile and (left + right) / 2 - 230 or 360,
            bottom - 52, { 0.95, 0.85, 0.35 })
    end
    shadowedPrint(
        controller and "LEFT STICK / D-PAD: MOVE    A: USE    X: PARK    Y: MOVE    START: MENU"
            or mobile and (followPlayerCamera
                and "ONE FINGER: CONTROLS    TWO FINGERS: PINCH ZOOM    CAMERA: FOLLOW"
                or "ONE FINGER: CONTROLS    TWO FINGERS: PINCH + PAN")
            or "WASD / arrows: move    E: interact",
        left + 22,
        bottom - 28,
        { 0.82, 0.86, 0.88 }
    )
end

function Hud.hitTest(x, y)
    return BackButton.contains(EXIT, x, y) and "exit" or nil
end

return Hud
