local BackButton = require("src.screens.back_button")
local Ui = require("src.screens.ui")
local Procurement = require("src.procurement")
local WorkPhone = require("src.work_phone")
local BusinessCalendar = require("src.business_calendar")
local DisplayFonts = require("src.screens.reference_display_fonts")

local Screen = {}

local CLOSE = { x = 742, y = 54, width = 132, height = 42 }
local ACTION = { x = 508, y = 484, width = 330, height = 54 }
local HANG_UP = { x = 508, y = 552, width = 330, height = 44 }
local DIRECTORY = { x = 458, y = 205, width = 372, height = 40, gap = 2 }
local SUPPLIES = { x = 458, y = 292, width = 372, height = 27, gap = 3 }
local PHONE_FOOTER = { x = 62, y = 600, width = 796, height = 38 }

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
    if call.kind == "customer_status" or call.kind == "customer_complaint" then return COLORS.urgent end
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

local function lastJobResponse(phone)
    local last = phone and phone.history and phone.history[#phone.history]
    if last and last.kind == "customer_status" and last.outcome == "completed" and last.response then
        return last
    end
end

local function directoryRow(index)
    return { x = DIRECTORY.x, y = DIRECTORY.y + (index - 1) * (DIRECTORY.height + DIRECTORY.gap),
        width = DIRECTORY.width, height = DIRECTORY.height }
end

local function setPhoneNotice(message, call)
    Screen.directoryNotice = tostring(message or "")
    Screen.directoryNoticeCallId = call and call.id or false
end

local function clearPhoneNotice()
    Screen.directoryNotice = nil
    Screen.directoryNoticeCallId = nil
end

local function removeLastCharacter(text)
    local index = #text
    while index > 1 do
        local byte = text:byte(index)
        if byte < 128 or byte >= 192 then break end
        index = index - 1
    end
    return text:sub(1, index - 1)
end

local function drawPhoneFooter(state, call)
    local currentCallId = call and call.id or false
    if Screen.directoryNotice and Screen.directoryNoticeCallId ~= currentCallId then
        Screen.directoryNotice = nil
        Screen.directoryNoticeCallId = nil
    end
    local message = Screen.directoryNotice
    local label
    if message then
        label = "PHONE NOTICE"
    elseif not call then
        local lastUpdate = lastJobResponse(state.workPhone)
        if lastUpdate then
            label = "OUR RESPONSE TO " .. tostring(lastUpdate.caller)
            message = tostring(lastUpdate.response or "")
        end
    end
    if not message then return end

    panel(PHONE_FOOTER, { 0.055, 0.12, 0.14, 1 }, { 0.20, 0.46, 0.52, 1 })
    love.graphics.setColor(label == "PHONE NOTICE" and { 1.00, 0.72, 0.28, 1 }
        or { 0.96, 0.83, 0.30, 1 })
    local footerText = label .. " • " .. message
    local availableWidth = PHONE_FOOTER.width - 20
    local font = love.graphics.getFont()
    if font:getWidth(footerText) > availableWidth then
        while #footerText > 3 and font:getWidth(footerText .. "…") > availableWidth do
            footerText = removeLastCharacter(footerText)
        end
        footerText = footerText .. "…"
    end
    love.graphics.setColor(0.90, 0.94, 0.92, 1)
    love.graphics.print(footerText, PHONE_FOOTER.x + 10, PHONE_FOOTER.y + 11)
end

local function supplyRow(index)
    return { x = SUPPLIES.x, y = SUPPLIES.y + (index - 1) * (SUPPLIES.height + SUPPLIES.gap),
        width = SUPPLIES.width, height = SUPPLIES.height }
end

local function shortProductName(name)
    name = tostring(name or "Supply")
    if #name > 34 then return name:sub(1, 31) .. "..." end
    return name
end

local function canAct(call)
    if not call then return false end
    if call.connecting then return false end
    if call.direction ~= "outgoing" then return true end
    if call.kind == "outgoing_power" or call.kind == "outgoing_water" then return not call.response end
    return call.kind == "outgoing_supplier" and call.pendingItemIndex ~= nil and not call.orderId
end

local function canOrderSupply(state, call, itemIndex, waiting)
    if waiting or not call or call.orderId or call.direction ~= "outgoing"
        or call.kind ~= "outgoing_supplier" or call.connecting or call.checkoutReady then return false end
    local item = Procurement.category(call.categoryIndex).items[itemIndex]
    return item ~= nil and item.available ~= false and (state.money or 0) >= (item.price or 0)
end

local function supplyBlockReason(state, call, itemIndex)
    local category = call and Procurement.category(call.categoryIndex)
    local item = category and category.items[itemIndex]
    if not item then return "Choose a supply from this supplier's catalog." end
    if item.available == false then
        return item.unavailableReason or "That product is not available yet."
    end
    if item.price and (state.money or 0) < item.price then
        return "There is not enough money for " .. shortProductName(item.name) .. "."
    end
    return "That supply cannot be ordered from this call."
end

function Screen.enter(state)
    WorkPhone.ensure(state)
    clearPhoneNotice()
end

function Screen.draw(state, pointerX, pointerY, assets, waiting)
    local phone = WorkPhone.ensure(state)
    local call = phone.incoming
    panel({ x = 42, y = 34, width = 876, height = 608 },
        { 0.025, 0.055, 0.085, 0.985 }, { 0.10, 0.67, 0.65, 1 })
    panel({ x = 54, y = 46, width = 852, height = 60 },
        { 0.72, 0.72, 0.68, 1 }, { 0.92, 0.93, 0.88, 1 })
    love.graphics.setColor(0.04, 0.16, 0.19, 1)
    DisplayFonts.draw("groovySlab", "PICTURE SHOP WORK PHONE", 78, 67, 28, "left", 810)
    BackButton.draw(assets, CLOSE, "BACK", pointerX, pointerY, waiting == true)

    panel({ x = 62, y = 120, width = 352, height = 476 },
        { 0.035, 0.09, 0.13, 1 }, { 0.12, 0.42, 0.47, 1 })
    drawPhone(assets, state)
    local lamp = lightColor(call)
    love.graphics.setColor(lamp)
    love.graphics.circle("fill", 98, 478, 8)
    love.graphics.setColor(0.82, 0.90, 0.90, 1)
    love.graphics.printf(call and (call.direction == "outgoing" and (call.connecting and "DIALING..." or "LINE CONNECTED")
        or call.answered and "LINE CONNECTED" or "INCOMING CALL")
        or "DIAL TONE • LINE CLEAR", 116, 472, 262, "left")
    drawLegend(88, 516, COLORS.customer, "CUSTOMER / NEW ORDER")
    drawLegend(88, 540, COLORS.service, "UTILITY / SUPPLIER")
    drawLegend(88, 564, COLORS.urgent, "URGENT JOB QUESTION")

    panel({ x = 432, y = 120, width = 426, height = 342 },
        { 0.045, 0.075, 0.105, 1 }, { 0.20, 0.46, 0.52, 1 })
    local answered = call and call.answered == true
    local outgoing = call and call.direction == "outgoing"
    if call then
        love.graphics.setColor(lamp)
        local reviewingOrder = call.pendingItemIndex ~= nil and not call.orderId
        local heading = call.connecting and (call.kind == "outgoing_power" and "CALLING POWER COMPANY"
            or call.kind == "outgoing_water" and "CALLING WATER COMPANY" or "CALLING SUPPLIER")
            or call.checkoutReady and "CHECKOUT REVIEW"
            or reviewingOrder and "SUPPLY SELECTED"
            or (outgoing and "OUTGOING CALL" or (answered and call.role or "INCOMING CALL"))
        love.graphics.print(heading, 458, 145)
        love.graphics.setColor(0.96, 0.83, 0.30, 1)
        love.graphics.printf(call.caller, 458, 178, 372, "left")
        love.graphics.setColor(0.72, 0.84, 0.86, 1)
        love.graphics.printf(call.subject, 458, 211, 372, "left")
        love.graphics.setColor(0.90, 0.94, 0.92, 1)
        local callMessage = call.response or (answered and call.message
            or "Answer the call to hear what they have to say.")
        if call.connecting then
            callMessage = "Calling " .. tostring(call.caller) .. "...\nPlease wait for them to pick up."
        end
        if reviewingOrder and outgoing and call.kind == "outgoing_supplier" then
            local item = Procurement.category(call.categoryIndex).items[call.pendingItemIndex]
            if item then
                callMessage = call.checkoutReady and WorkPhone.checkoutMessage(state, call)
                    or string.format("Selected: %s — $%d\nNo charge yet. Review checkout before placing the order.",
                        shortProductName(item.name), item.price)
            end
        end
        love.graphics.printf(callMessage, 458, 246, 372, "left")
        if outgoing and call.kind == "outgoing_supplier" and not call.connecting and not call.checkoutReady then
            local category = Procurement.category(call.categoryIndex)
            for index, item in ipairs(category.items) do
                local row = supplyRow(index)
                local canOrder = canOrderSupply(state, call, index, waiting)
                local selected = call.pendingItemIndex == index and not call.orderId
                local hovered = canOrder and pointerX and pointerY and Ui.contains(row, pointerX, pointerY)
                panel(row, selected and { 0.30, 0.27, 0.12, 1 }
                    or canOrder and (hovered and { 0.13, 0.34, 0.32, 1 } or { 0.08, 0.20, 0.22, 1 })
                    or { 0.12, 0.14, 0.16, 1 }, canOrder and { 0.25, 0.61, 0.59, 1 }
                    or { 0.27, 0.30, 0.31, 1 })
                love.graphics.setColor(canOrder and { 0.89, 0.94, 0.91, 1 }
                    or { 0.52, 0.57, 0.58, 1 })
                love.graphics.printf(shortProductName(item.name), row.x + 9, row.y + 6, 268, "left")
                love.graphics.setColor(0.96, 0.83, 0.30, 1)
                love.graphics.printf("$" .. tostring(item.price or 0), row.x + 286, row.y + 6, 75, "right")
            end
        elseif outgoing and (call.kind == "outgoing_power" or call.kind == "outgoing_water")
            and not call.response then
            love.graphics.setColor(0.60, 0.70, 0.72, 1)
            love.graphics.printf("Choose the service restoration action to pay the reconnection fee.",
                458, 396, 372, "left")
        elseif call.direction ~= "outgoing" and not answered then
            love.graphics.setColor(0.60, 0.70, 0.72, 1)
            love.graphics.printf("Answer to hear the caller's message.", 458, 405, 372, "left")
        end
    else
        love.graphics.setColor(0.72, 0.84, 0.86, 1)
        DisplayFonts.draw("groovySlab", "CONTACT DIRECTORY", 458, 145, 20, "left", 372)
        love.graphics.setColor(0.90, 0.94, 0.92, 1)
        love.graphics.printf("Select a directory contact to place a call.", 458, 170, 372, "left")
        love.graphics.setColor(0.64, 0.75, 0.77, 1)
        love.graphics.printf("Supplier hours: Mon–Fri, 09:00–20:00.", 458, 184, 372, "left")
        local supplierLinesOpen = BusinessCalendar.isBusinessOpen(state)
        for index, contact in ipairs(WorkPhone.contacts()) do
            local row = directoryRow(index)
            local hovered = pointerX and pointerY and Ui.contains(row, pointerX, pointerY)
            panel(row, hovered and { 0.13, 0.34, 0.32, 1 } or { 0.07, 0.15, 0.18, 1 },
                hovered and { 0.25, 0.78, 0.70, 1 } or { 0.20, 0.46, 0.52, 1 })
            love.graphics.setColor(0.96, 0.83, 0.30, 1)
            love.graphics.print(contact.name, row.x + 10, row.y + 3)
            love.graphics.setColor(0.69, 0.79, 0.81, 1)
            local isSupplier = contact.kind == "outgoing_supplier"
            love.graphics.printf(contact.description, row.x + 10, row.y + 22,
                row.width - (isSupplier and 94 or 20), "left")
            if isSupplier then
                local badge = { x = row.x + row.width - 76, y = row.y + 9, width = 66, height = 22 }
                panel(badge, supplierLinesOpen and { 0.08, 0.28, 0.22, 1 }
                    or { 0.24, 0.18, 0.11, 1 }, supplierLinesOpen and { 0.24, 0.65, 0.48, 1 }
                    or { 0.72, 0.48, 0.24, 1 })
                love.graphics.setColor(supplierLinesOpen and { 0.62, 0.96, 0.78, 1 }
                    or { 1.00, 0.78, 0.45, 1 })
                love.graphics.printf(supplierLinesOpen and "OPEN" or "CLOSED", badge.x, badge.y + 3,
                    badge.width, "center")
            end
        end
    end

    local actionEnabled = canAct(call) and not waiting
    local actionLabel = call and (answered and WorkPhone.actionLabel(state) or "ANSWER") or "NO ACTIVE CALL"
    button(ACTION, actionLabel, actionEnabled, pointerX, pointerY)
    local hangUpLabel = call and (call.kind == "outgoing_supplier" and call.checkoutReady
        and "BACK TO ITEMS" or call.pendingItemIndex and "CANCEL ORDER"
        or (answered and "HANG UP" or "DECLINE CALL")) or "NO ACTIVE CALL"
    button(HANG_UP, hangUpLabel,
        call ~= nil and not waiting, pointerX, pointerY,
        { 0.38, 0.13, 0.19, 1 }, { 0.88, 0.30, 0.42, 1 })
    drawPhoneFooter(state, call)
end

function Screen.remoteIntent(state, x, y)
    if Ui.contains(CLOSE, x, y) then return "close" end
    local call = state.workPhone and state.workPhone.incoming
    if not call then
        for index, contact in ipairs(WorkPhone.contacts()) do
            if Ui.contains(directoryRow(index), x, y) then
                return "phone_call", { contactId = contact.id }
            end
        end
        return nil
    end
    if call.direction == "outgoing" and call.kind == "outgoing_supplier"
        and not call.orderId and not call.connecting and not call.checkoutReady then
        local category = Procurement.category(call.categoryIndex)
        for index, _ in ipairs(category.items) do
            if Ui.contains(supplyRow(index), x, y) then
                return "phone_order", { itemIndex = index }
            end
        end
    end
    if Ui.contains(ACTION, x, y) and canAct(call) then
        return call.answered and "phone_respond" or "phone_answer", { callId = call.id }
    elseif Ui.contains(HANG_UP, x, y) then return "phone_dismiss", { callId = call.id } end
end

function Screen.mousepressed(state, x, y, button)
    if button ~= 1 then return nil end
    if Ui.contains(CLOSE, x, y) then return { action = "close" } end
    local call = WorkPhone.ensure(state).incoming
    if not call then
        for index, contact in ipairs(WorkPhone.contacts()) do
            if Ui.contains(directoryRow(index), x, y) then
                local connected, result = WorkPhone.placeCall(state, contact.id)
                if connected then
                    clearPhoneNotice()
                    return { action = "call_started", call = result }
                end
                setPhoneNotice(result)
                state.message = tostring(result)
                return { action = "blocked" }
            end
        end
        return nil
    end
    if call.direction == "outgoing" and call.kind == "outgoing_supplier"
        and not call.orderId and not call.connecting and not call.checkoutReady then
        local category = Procurement.category(call.categoryIndex)
        for index, _ in ipairs(category.items) do
            if Ui.contains(supplyRow(index), x, y) then
                if not canOrderSupply(state, call, index) then
                    local reason = supplyBlockReason(state, call, index)
                    setPhoneNotice(reason, call)
                    state.message = tostring(reason)
                    return { action = "blocked" }
                end
                local ordered, response = WorkPhone.orderSupply(state, index)
                if ordered then
                    clearPhoneNotice()
                    return { action = "supply_selected", response = response }
                end
                setPhoneNotice(response, call)
                state.message = tostring(response)
                return { action = "blocked" }
            end
        end
    end
    if Ui.contains(ACTION, x, y) then
        if not canAct(call) then return nil end
        if not call.answered then
            local answered, result = WorkPhone.answer(state)
            if answered then
                clearPhoneNotice()
                return { action = "answered", call = result }
            end
            setPhoneNotice(result, call)
            state.message = tostring(result)
            return { action = "blocked" }
        end
        local completed, response = WorkPhone.respond(state)
        if completed then
            clearPhoneNotice()
            return { action = "call_completed", response = response }
        end
        setPhoneNotice(response, call)
        state.message = tostring(response)
        return { action = "blocked" }
    end
    if Ui.contains(HANG_UP, x, y) then
        local returningToItems = call.kind == "outgoing_supplier" and call.checkoutReady
        local ended, response = WorkPhone.dismiss(state)
        if ended then
            clearPhoneNotice()
            return { action = returningToItems and "checkout_closed" or "call_ended", response = response }
        end
        setPhoneNotice(response, call)
        return { action = "blocked" }
    end
    return nil
end

function Screen.buttonCenter(action)
    local rect = action == "close" and CLOSE or action == "hang_up" and HANG_UP or ACTION
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

return Screen
