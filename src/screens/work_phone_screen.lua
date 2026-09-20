local BackButton = require("src.screens.back_button")
local Ui = require("src.screens.ui")
local WorkPhone = require("src.work_phone")

local Screen = { lastResponse = nil }

local CLOSE = { x = 742, y = 54, width = 132, height = 42 }
local ACTION = { x = 508, y = 484, width = 330, height = 54 }
local HANG_UP = { x = 508, y = 552, width = 330, height = 44 }

local COLORS = {
    idle = { 0.35, 0.40, 0.42, 1 },
    customer = { 0.10, 0.88, 0.82, 1 },
    service = { 1.00, 0.70, 0.12, 1 },
    urgent = { 1.00, 0.20, 0.42, 1 },
}

local function panel(rect, fill, border)
    Ui.panel(rect, fill, border, 4, 2)
end

local function button(rect, label, enabled, pointerX, pointerY, fill, border)
    local hovered = enabled and pointerX and pointerY and Ui.contains(rect, pointerX, pointerY)
    local color = enabled and (hovered and { 0.19, 0.52, 0.48, 1 }
        or fill or { 0.10, 0.37, 0.35, 1 }) or { 0.16, 0.18, 0.20, 1 }
    panel(rect, color, enabled and (border or { 0.30, 0.88, 0.78, 1 })
        or { 0.30, 0.33, 0.35, 1 })
    love.graphics.setColor(enabled and { 0.96, 1.00, 0.96, 1 }
        or { 0.48, 0.52, 0.54, 1 })
    love.graphics.printf(label, rect.x, rect.y + rect.height / 2 - 6,
        rect.width, "center")
end

local function lightColor(call)
    if not call then return COLORS.idle end
    if call.kind == "customer_order" then return COLORS.customer end
    if call.kind == "customer_status" then return COLORS.urgent end
    return COLORS.service
end

local function drawPhone(assets, state)
    local image = assets and assets.get("workPhone")
    local sprite = assets and assets.getQuad(
        "workPhone" .. WorkPhone.spriteFrame(state, love.timer.getTime()))
    if not image or not sprite then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, sprite.quad, 72, 118, 0, 0.76, 0.76)
end

local function drawLegend(x, y, color, label)
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y + 2, 11, 11, 2, 2)
    love.graphics.setColor(0.72, 0.80, 0.82, 1)
    love.graphics.print(label, x + 18, y)
end

function Screen.enter(state)
    WorkPhone.ensure(state)
    Screen.lastResponse = nil
end

function Screen.draw(state, pointerX, pointerY, assets, waiting)
    local phone = WorkPhone.ensure(state)
    local call = phone.incoming
    panel({ x = 42, y = 34, width = 876, height = 608 },
        { 0.025, 0.055, 0.085, 0.985 }, { 0.10, 0.67, 0.65, 1 })
    panel({ x = 54, y = 46, width = 852, height = 60 },
        { 0.72, 0.72, 0.68, 1 }, { 0.92, 0.93, 0.88, 1 })
    love.graphics.setColor(0.04, 0.16, 0.19, 1)
    love.graphics.print("PICTURE SHOP WORK PHONE", 78, 67)
    BackButton.draw(assets, CLOSE, "BACK", pointerX, pointerY, waiting == true)

    panel({ x = 62, y = 120, width = 352, height = 476 },
        { 0.035, 0.09, 0.13, 1 }, { 0.12, 0.42, 0.47, 1 })
    drawPhone(assets, state)
    local lamp = lightColor(call)
    love.graphics.setColor(lamp)
    love.graphics.circle("fill", 98, 478, 8)
    love.graphics.setColor(0.82, 0.90, 0.90, 1)
    love.graphics.printf(call and (call.answered and "LINE CONNECTED" or "INCOMING CALL")
        or "PHONE LINE READY", 116, 472, 262, "left")
    drawLegend(88, 516, COLORS.customer, "CUSTOMER / NEW ORDER")
    drawLegend(88, 540, COLORS.service, "SUPPLIER OR SERVICE")
    drawLegend(88, 564, COLORS.urgent, "URGENT JOB QUESTION")

    panel({ x = 432, y = 120, width = 426, height = 342 },
        { 0.045, 0.075, 0.105, 1 }, { 0.20, 0.46, 0.52, 1 })
    love.graphics.setColor(lamp)
    love.graphics.print(call and call.role or "NO ACTIVE CALL", 458, 145)
    love.graphics.setColor(0.96, 0.83, 0.30, 1)
    love.graphics.printf(call and call.caller or "The wall phone is quiet.",
        458, 178, 372, "left")
    love.graphics.setColor(0.72, 0.84, 0.86, 1)
    love.graphics.printf(call and call.subject or "CALL HISTORY", 458, 211, 372, "left")
    love.graphics.setColor(0.90, 0.94, 0.92, 1)
    local body = call and call.message or Screen.lastResponse
    if not body then
        local latest = phone.history[#phone.history]
        body = latest and (latest.caller .. ": " .. tostring(latest.response or latest.outcome))
            or "Customers can place orders or ask where a job is and when it will be done. Supplier and service calls use the amber light."
    end
    love.graphics.printf(body, 458, 246, 372, "left")
    if call and not call.answered then
        love.graphics.setColor(0.60, 0.70, 0.72, 1)
        love.graphics.printf(call.kind == "construction_notice"
            and "Answer to acknowledge. A missed notice does not cancel the visit."
            or "Answer before discussing the job or placing an order.",
            458, 405, 372, "left")
    end

    local actionLabel = call and (call.answered and WorkPhone.actionLabel(state) or "ANSWER")
        or "NO CALL"
    button(ACTION, actionLabel, call ~= nil and not waiting, pointerX, pointerY)
    button(HANG_UP, call and (call.answered and "HANG UP"
        or call.kind == "construction_notice" and "SAVE NOTICE" or "DECLINE CALL") or "HANG UP",
        call ~= nil and not waiting, pointerX, pointerY, { 0.38, 0.13, 0.19, 1 }, { 0.88, 0.30, 0.42, 1 })
end

function Screen.remoteIntent(state, x, y)
    if Ui.contains(CLOSE, x, y) then return "close" end
    local call = state.workPhone and state.workPhone.incoming
    if not call then return nil end
    if Ui.contains(ACTION, x, y) then
        return call.answered and "phone_respond" or "phone_answer", { callId = call.id }
    elseif Ui.contains(HANG_UP, x, y) then return "phone_dismiss", { callId = call.id } end
end

function Screen.mousepressed(state, x, y, button)
    if button ~= 1 then return nil end
    if Ui.contains(CLOSE, x, y) then return { action = "close" } end
    local call = WorkPhone.ensure(state).incoming
    if not call then return nil end
    if Ui.contains(ACTION, x, y) then
        if not call.answered then
            local answered, result = WorkPhone.answer(state)
            if answered then return { action = "answered", call = result } end
            state.message = tostring(result)
            return { action = "blocked" }
        end
        local completed, response = WorkPhone.respond(state)
        if completed then
            Screen.lastResponse = response
            return { action = "call_completed", response = response }
        end
        state.message = tostring(response)
        return { action = "blocked" }
    end
    if Ui.contains(HANG_UP, x, y) then
        local ended, response = WorkPhone.dismiss(state)
        if ended then
            Screen.lastResponse = response
            return { action = "call_ended", response = response }
        end
        return { action = "blocked" }
    end
    return nil
end

function Screen.buttonCenter(action)
    local rect = action == "close" and CLOSE or action == "hang_up" and HANG_UP or ACTION
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

return Screen
