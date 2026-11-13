local Config = require("src.config")
local BusinessCalendar = require("src.business_calendar")
local BackButton = require("src.screens.back_button")
local Ui = require("src.screens.ui")
local Typography = require("src.screens.typography")
local WarehouseHud = require('src.screens.warehouse_hud')

local Hud = {}
local EXIT = { x = 816, y = 14, width = 126, height = 40 }

function Hud.exitRect(bounds)
    return {x=(bounds and bounds.right or Config.baseWidth)-EXIT.width-18,y=14,
        width=EXIT.width,height=EXIT.height}
end
function Hud.exitHit(x,y,bounds)
    return BackButton.contains(Hud.exitRect(bounds),x,y)
end
function Hud.drawExit(assets,pointerX,pointerY,bounds)
    local rect=Hud.exitRect(bounds)
    local hovered=pointerX and pointerY and BackButton.contains(rect,pointerX,pointerY)
    Ui.panel(rect,hovered and {.20,.27,.27,1} or {.12,.17,.18,1},{.43,.53,.51,1},4,1)
    love.graphics.setColor(.94,.95,.89)
    love.graphics.printf('EXIT TO MENU',rect.x,rect.y+(rect.height-love.graphics.getFont():getHeight())/2,
        rect.width,'center')
end

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
        followPlayerCamera,twelveHourTime,feedback,sceneId,player)
    bounds = bounds or { left = 0, right = Config.baseWidth, bottom = Config.baseHeight }
    local left, right, bottom = mobile and bounds.left or 0,
        mobile and bounds.right or Config.baseWidth,
        mobile and bounds.bottom or Config.baseHeight
    EXIT.x, EXIT.y = right - EXIT.width - 18, 14
    local atHome=sceneId=="home" and state.home
    if sceneId=='warehouse' then
        WarehouseHud.drawStatus(state,feedback,{left=left,right=right},twelveHourTime)
    elseif atHome then
        WarehouseHud.drawTerrainStatus(state,feedback,{left=left,right=right},twelveHourTime)
    else
    local originalFont=love.graphics.getFont()
    local cashFont=Typography.get(mobile and 21 or 18)
    love.graphics.setFont(cashFont)
    local cashText = atHome and ("Home "..Ui.money(state.home.balanceCents/100)) or Ui.money(state.money)
    local cashWidth = math.max(112, math.min(180, love.graphics.getFont():getWidth(cashText) + 22))
    local cashX, cashY, cashHeight = left + 18, 13, mobile and 36 or 33
    local cashDelta, cashTimer, cashDuration = 0, 0, 1
    if feedback and not atHome then cashDelta, cashTimer, cashDuration = feedback:cashEffect() end
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
    love.graphics.print(cashText, cashX + 11, cashY + (cashHeight-cashFont:getHeight())/2)
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
    local infoX = left + math.max(160, cashWidth + 34)
    local dateX = infoX
    if atHome then
        local apartmentName = require("src.home_catalog").APARTMENTS[state.home.apartmentId].name
        shadowedPrint(apartmentName, infoX, 20, { .88, .92, .94 })
        dateX = infoX + math.max(150, love.graphics.getFont():getWidth(apartmentName) + 18)
    end
    love.graphics.setFont(originalFont)
    local date = BusinessCalendar.ensure(state)
    local dateText = BusinessCalendar.weekdayName(date.weekday) .. " • "
        .. BusinessCalendar.shortDate(state)
    shadowedPrint(dateText, dateX, 20, { 0.74, 0.88, 0.89 })
    shadowedPrint("TIME "..BusinessCalendar.timeText(state,twelveHourTime),dateX,38,{.96,.85,.40})
    if not atHome and state.bills and state.bills.balance > 0 then
        local billsX = dateX + math.max(190, love.graphics.getFont():getWidth(dateText) + 18)
        shadowedPrint("Bills due: $" .. state.bills.balance, billsX, 20, { 0.96, 0.48, 0.30 })
    end
    end
    if sceneId~='warehouse' then Hud.drawExit(assets,pointerX,pointerY,{right=right}) end
    if state.message and sceneId~='warehouse' then
        local reserved=sceneId=="warehouse" and 442 or 320
        love.graphics.push('all')
        love.graphics.setFont(Typography.get(mobile and 18 or 16))
        shadowedPrintf(state.message, left + 24, 62, right - left - reserved, { 0.88, 0.92, 0.94 })
        love.graphics.pop()
    end
    local week=state.home and state.home.weekend
    if week and week.phase~="working" and sceneId~='warehouse' then
        local status=require("src.weekend_flow").isOuting(state) and "TOWN OUTING: use either entrance to return. The shop keeps its normal schedule."
            or week.phase=="closing" and "FRIDAY CLOSING: finish work and pickups, then go home from the front entrance."
            or week.phase=="ready" and "SHOP CLOSED: use the exterior front entrance to go home. Time is held."
            or ("AT HOME: return becomes available Monday at "..BusinessCalendar.formatTime(7,30,twelveHourTime)
                ..", before the "..BusinessCalendar.formatTime(8,0,twelveHourTime)
                .." employee shift. Shop opens at "..BusinessCalendar.formatTime(9,0,twelveHourTime)..".")
        shadowedPrintf(status,left+24,92,right-left-48,{.96,.85,.40})
    end
    if prompt then
        local shownPrompt = prompt
        if mobile then
            shownPrompt = shownPrompt:gsub("^E%s+or%s+F:%s*", "TAP USE / PARK: ")
                :gsub("^E:%s*EMAIL RESUME%s*|%s*X:%s*NOT HIRING", "TAP EMAIL RESUME / NOT HIRING button")
                :gsub("^E:%s*", "TAP USE: ")
                :gsub("%s+X:%s*dismiss applicant", " / use DISMISS button")
        elseif controller then
            shownPrompt = shownPrompt:gsub("^E%s+or%s+F:%s*", "A or X: ")
                :gsub("^E:%s*EMAIL RESUME%s*|%s*X:%s*NOT HIRING", "A: EMAIL RESUME  /  B: NOT HIRING")
                :gsub("^E:%s*", "A: ")
                :gsub("X:%s*dismiss applicant", "B: dismiss applicant")
        end
        shadowedPrint(shownPrompt, mobile and (left + right) / 2 - 230 or 360,
            bottom - 52, { 0.95, 0.85, 0.35 })
    end
    if atHome and player then require("src.home_activity_controls").drawHud(state,player,left,right) end
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
