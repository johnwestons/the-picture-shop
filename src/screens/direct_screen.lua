local Config = require("src.config")
local Ui = require("src.screens.ui")

local DirectScreen = {
    mode = "menu",
    callbacks = nil,
    selectedSlot = 1,
    localAddress = "",
    hostCodeInput = "",
    responseInput = "",
    displayCode = nil,
    clipboardCode = nil,
    focused = nil,
    message = "",
    pressed = nil,
    inviteOnly = false,
}

local BUTTONS = {
    host = { x = 190, y = 260, width = 250, height = 78, label = "HOST DIRECT GAME" },
    join = { x = 520, y = 260, width = 250, height = 78, label = "JOIN DIRECT GAME" },
    back = { x = 390, y = 500, width = 180, height = 58, label = "BACK" },
    create = { x = 285, y = 390, width = 190, height = 58, label = "CREATE HOST CODE" },
    start = { x = 285, y = 458, width = 190, height = 58, label = "START CONNECTION" },
    connect = { x = 285, y = 458, width = 190, height = 58, label = "CONNECT" },
    copy = { x = 220, y = 372, width = 170, height = 52, label = "COPY CODE" },
    paste = { x = 570, y = 372, width = 170, height = 52, label = "PASTE CODE" },
    cancel = { x = 500, y = 458, width = 170, height = 58, label = "CANCEL" },
}

local FIELDS = {
    address = { x = 225, y = 270, width = 510, height = 62 },
    guestCode = { x = 175, y = 168, width = 610, height = 94 },
    guestAddress = { x = 225, y = 300, width = 510, height = 56 },
    response = { x = 175, y = 296, width = 610, height = 62 },
}

local function contains(rect, x, y)
    return Ui.contains(rect, x, y)
end

local function playerLabel()
    if love.system and love.system.getOS and love.system.getOS() == "Android" then
        return "Android Worker"
    end
    return "PC Worker"
end

local function clipboardRead()
    if DirectScreen.callbacks and type(DirectScreen.callbacks.readClipboard) == "function" then
        local ok, value = pcall(DirectScreen.callbacks.readClipboard)
        return ok and type(value) == "string" and value or nil
    end
    if love.system and type(love.system.getClipboardText) == "function" then
        local ok, value = pcall(love.system.getClipboardText)
        return ok and type(value) == "string" and value or nil
    end
end

local function clipboardWrite(value)
    if type(value) ~= "string" then return false end
    if DirectScreen.callbacks and type(DirectScreen.callbacks.writeClipboard) == "function" then
        local ok, result = pcall(DirectScreen.callbacks.writeClipboard, value)
        return ok and result ~= false
    end
    if love.system and type(love.system.setClipboardText) == "function" then
        local ok, result = pcall(love.system.setClipboardText, value)
        return ok and result ~= false
    end
    return false
end

local function clearOwnedClipboard()
    local code = DirectScreen.clipboardCode
    DirectScreen.clipboardCode = nil
    if not code then return true end
    local current = clipboardRead()
    if current ~= code then return true end
    return clipboardWrite("")
end

local function clearSensitive()
    clearOwnedClipboard()
    DirectScreen.hostCodeInput = ""
    DirectScreen.responseInput = ""
    DirectScreen.displayCode = nil
    DirectScreen.localAddress = ""
    DirectScreen.focused = nil
end

local function setMode(mode, message, focused)
    DirectScreen.mode = mode
    DirectScreen.message = tostring(message or "")
    DirectScreen.focused = focused
    DirectScreen.pressed = nil
end

local function chooseHost()
    clearSensitive()
    setMode("host_setup",
        "Enter the global IPv6 address shown by this device, then create an expiring host code.",
        "address")
    return true
end

local function chooseGuest()
    clearSensitive()
    setMode("guest_setup",
        "Paste the host code and enter this device's global IPv6 address.",
        "hostCode")
    return true
end

local function requestHost()
    if DirectScreen.localAddress == "" then
        DirectScreen.message = "Enter this device's global IPv6 address first."
        return false
    end
    if not DirectScreen.callbacks or type(DirectScreen.callbacks.host) ~= "function" then
        DirectScreen.message = "Direct hosting is unavailable in this build."
        return false
    end
    local ok, codeOrError = DirectScreen.callbacks.host(
        DirectScreen.selectedSlot, playerLabel(), DirectScreen.localAddress)
    if ok ~= true or type(codeOrError) ~= "string" then
        DirectScreen.message = tostring(codeOrError or "The host code could not be created.")
        return false
    end
    DirectScreen.displayCode = codeOrError
    DirectScreen.hostCodeInput = ""
    DirectScreen.responseInput = ""
    setMode("host_reply",
        "Copy the host code to the other player. Paste their reply code below when it arrives.",
        "response")
    return true
end

local function requestGuest()
    if DirectScreen.hostCodeInput == "" then
        DirectScreen.message = "Paste the host code first."
        DirectScreen.focused = "hostCode"
        return false
    end
    if DirectScreen.localAddress == "" then
        DirectScreen.message = "Enter this device's global IPv6 address first."
        DirectScreen.focused = "address"
        return false
    end
    if not DirectScreen.callbacks or type(DirectScreen.callbacks.join) ~= "function" then
        DirectScreen.message = "Direct joining is unavailable in this build."
        return false
    end
    local ok, codeOrError = DirectScreen.callbacks.join(
        DirectScreen.hostCodeInput, DirectScreen.localAddress, playerLabel())
    if ok ~= true or type(codeOrError) ~= "string" then
        DirectScreen.message = tostring(codeOrError or "The Direct connection could not start.")
        return false
    end
    DirectScreen.hostCodeInput = ""
    DirectScreen.localAddress = ""
    DirectScreen.displayCode = codeOrError
    setMode("opening_guest",
        "Copy this reply code to the host. Keep this screen open while authentication completes.")
    return true
end

local function submitResponse()
    if DirectScreen.responseInput == "" then
        DirectScreen.message = "Paste the other player's reply code first."
        return false
    end
    if not DirectScreen.callbacks or type(DirectScreen.callbacks.response) ~= "function" then
        DirectScreen.message = "Direct response authentication is unavailable."
        return false
    end
    local ok, errorMessage = DirectScreen.callbacks.response(DirectScreen.responseInput)
    if ok ~= true then
        DirectScreen.message = tostring(errorMessage or "The reply code was rejected.")
        return false
    end
    DirectScreen.responseInput = ""
    clearOwnedClipboard()
    DirectScreen.displayCode = nil
    setMode("opening_host", "Authenticating the direct connection. Keep this screen open.")
    return true
end

local function copyCode()
    if type(DirectScreen.displayCode) ~= "string" then return false end
    if not clipboardWrite(DirectScreen.displayCode) then
        DirectScreen.message = "The code could not be copied on this device."
        return false
    end
    DirectScreen.clipboardCode = DirectScreen.displayCode
    DirectScreen.message = "Code copied. It will be cleared from this clipboard after use or cancellation."
    return true
end

local function normalizedCode(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" or #value > 160 or value:find("[^A-Za-z0-9_.%-]") then return nil end
    return value
end

local function pasteCode()
    local value = normalizedCode(clipboardRead())
    if not value then
        DirectScreen.message = "The clipboard does not contain a valid Direct code."
        return false
    end
    if DirectScreen.mode == "host_reply" then
        DirectScreen.responseInput = value
        DirectScreen.focused = "response"
        DirectScreen.message = "Reply code pasted. Select CONNECT to authenticate it."
    elseif DirectScreen.mode == "guest_setup" then
        DirectScreen.hostCodeInput = value
        DirectScreen.focused = "address"
        DirectScreen.message = "Host code pasted. Now enter this device's global IPv6 address."
    else
        return false
    end
    return true
end

local function cancel()
    if DirectScreen.callbacks and type(DirectScreen.callbacks.cancel) == "function" then
        local called, cleaned, cleanupError = pcall(DirectScreen.callbacks.cancel)
        if not called or cleaned ~= true then
            clearSensitive()
            setMode("cleanup_failed", tostring(cleanupError or
                "Direct cleanup could not be verified. Select CANCEL to retry, or restart the game before another connection."))
            return false
        end
    end
    clearSensitive()
    setMode("menu", "Direct connection cancelled. No invitation remains active.")
    return true
end

local function goBack()
    if DirectScreen.mode ~= "menu" then return cancel() end
    clearSensitive()
    if DirectScreen.callbacks and type(DirectScreen.callbacks.back) == "function" then
        local called, cleaned, cleanupError = pcall(DirectScreen.callbacks.back)
        if not called or cleaned ~= true then
            setMode("cleanup_failed", tostring(cleanupError or
                "Direct cleanup could not be verified. Select CANCEL to retry, or restart the game before another connection."))
            return false
        end
    end
    return true
end

local function backspace(value)
    local offset = utf8 and utf8.offset and utf8.offset(value, -1)
    return offset and value:sub(1, offset - 1) or value:sub(1, -2)
end

local function appendInput(text)
    if DirectScreen.focused == "address" then
        local filtered = text:gsub("[^0-9A-Fa-f:]", "")
        if filtered == "" then return false end
        DirectScreen.localAddress = (DirectScreen.localAddress .. filtered):sub(1, 39)
        return true
    end
    local filtered = text:gsub("[^A-Za-z0-9_.%-]", "")
    if filtered == "" then return false end
    if DirectScreen.focused == "hostCode" then
        DirectScreen.hostCodeInput = (DirectScreen.hostCodeInput .. filtered):sub(1, 160)
        return true
    elseif DirectScreen.focused == "response" then
        DirectScreen.responseInput = (DirectScreen.responseInput .. filtered):sub(1, 160)
        return true
    end
    return false
end

local function buttonAt(x, y)
    local mode = DirectScreen.mode
    if mode == "menu" then
        if contains(BUTTONS.host, x, y) then return "host" end
        if contains(BUTTONS.join, x, y) then return "join" end
        if contains(BUTTONS.back, x, y) then return "back" end
    elseif mode == "host_setup" then
        if contains(BUTTONS.create, x, y) then return "create" end
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    elseif mode == "guest_setup" then
        if contains(BUTTONS.paste, x, y) then return "paste" end
        if contains(BUTTONS.start, x, y) then return "start" end
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    elseif mode == "host_reply" then
        if contains(BUTTONS.copy, x, y) then return "copy" end
        if contains(BUTTONS.paste, x, y) then return "paste" end
        if contains(BUTTONS.connect, x, y) then return "connect" end
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    elseif mode == "opening_guest" then
        if contains(BUTTONS.copy, x, y) then return "copy" end
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    elseif mode == "opening_host" or mode == "cleanup_failed" then
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    end
end

function DirectScreen.enter(options)
    clearSensitive()
    DirectScreen.callbacks = options or {}
    DirectScreen.selectedSlot = tonumber(DirectScreen.callbacks.slot) or 1
    DirectScreen.inviteOnly = DirectScreen.callbacks.inviteOnly == true
    if DirectScreen.inviteOnly then
        setMode("host_setup",
            "Invite one more worker with a fresh private code. Enter this host's global IPv6 address.",
            "address")
    else
        setMode("menu",
            "No account or relay is used. Each invitation connects one worker with fresh keys.")
    end
end

function DirectScreen.leave()
    clearSensitive()
    DirectScreen.callbacks = nil
    DirectScreen.inviteOnly = false
    setMode("menu", "")
end

function DirectScreen.setMessage(message, mode)
    if mode then DirectScreen.mode = mode end
    DirectScreen.message = tostring(message or "")
end

function DirectScreen.showError(message)
    clearSensitive()
    setMode("menu", tostring(message or "The Direct connection ended."))
end

function DirectScreen.showCleanupError(message)
    clearSensitive()
    setMode("cleanup_failed", tostring(message or
        "Direct cleanup could not be verified. Select CANCEL to retry, or restart the game before another connection."))
end

function DirectScreen.wantsTextInput()
    return DirectScreen.mode == "host_setup"
        or DirectScreen.mode == "guest_setup"
        or DirectScreen.mode == "host_reply"
end

function DirectScreen.update(_) end

function DirectScreen.keypressed(key)
    local ctrl = love.keyboard and love.keyboard.isDown
        and love.keyboard.isDown("lctrl", "rctrl")
    if ctrl and key == "v" then return pasteCode() end
    if ctrl and key == "c" then return copyCode() end

    if DirectScreen.mode == "menu" then
        if key == "h" then return chooseHost() end
        if key == "j" or key == "return" or key == "kpenter" then return chooseGuest() end
        if key == "escape" or key == "backspace" then return goBack() end
        return false
    end
    if key == "escape" then return cancel() end
    if key == "tab" and DirectScreen.mode == "guest_setup" then
        DirectScreen.focused = DirectScreen.focused == "hostCode" and "address" or "hostCode"
        return true
    end
    if key == "backspace" then
        if DirectScreen.focused == "address" then
            DirectScreen.localAddress = backspace(DirectScreen.localAddress)
        elseif DirectScreen.focused == "hostCode" then
            DirectScreen.hostCodeInput = backspace(DirectScreen.hostCodeInput)
        elseif DirectScreen.focused == "response" then
            DirectScreen.responseInput = backspace(DirectScreen.responseInput)
        else
            return false
        end
        return true
    end
    if key == "return" or key == "kpenter" then
        if DirectScreen.mode == "host_setup" then return requestHost() end
        if DirectScreen.mode == "guest_setup" then return requestGuest() end
        if DirectScreen.mode == "host_reply" then return submitResponse() end
    end
    return false
end

function DirectScreen.textinput(text)
    return type(text) == "string" and appendInput(text) or false
end

function DirectScreen.mousepressed(x, y, button)
    if button ~= 1 then return false end
    if DirectScreen.mode == "host_setup" and contains(FIELDS.address, x, y) then
        DirectScreen.focused = "address"; return true
    elseif DirectScreen.mode == "guest_setup" then
        if contains(FIELDS.guestCode, x, y) then DirectScreen.focused = "hostCode"; return true end
        if contains(FIELDS.guestAddress, x, y) then DirectScreen.focused = "address"; return true end
    elseif DirectScreen.mode == "host_reply" and contains(FIELDS.response, x, y) then
        DirectScreen.focused = "response"; return true
    end
    local action = buttonAt(x, y)
    DirectScreen.pressed = action
    if action == "host" then return chooseHost() end
    if action == "join" then return chooseGuest() end
    if action == "back" then return goBack() end
    if action == "create" then return requestHost() end
    if action == "start" then return requestGuest() end
    if action == "connect" then return submitResponse() end
    if action == "copy" then return copyCode() end
    if action == "paste" then return pasteCode() end
    if action == "cancel" then return cancel() end
    return false
end

function DirectScreen.mousereleased(_, _, button)
    if button == 1 then DirectScreen.pressed = nil end
end

function DirectScreen.buttonCenter(name)
    local rect = BUTTONS[name]
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function DirectScreen.fieldCenter(name)
    local rect = FIELDS[name]
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

local function drawButton(name)
    local rect = BUTTONS[name]
    local active = DirectScreen.pressed == name
    love.graphics.setColor(active and { 0.33, 0.47, 0.43, 1 } or { 0.12, 0.24, 0.27, 1 })
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.86, 0.70, 0.30, 1)
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setColor(0.94, 0.96, 0.93)
    love.graphics.printf(rect.label, rect.x, rect.y + rect.height / 2 - 7, rect.width, "center")
    love.graphics.setLineWidth(1)
end

local function drawField(rect, value, placeholder, focused)
    love.graphics.setColor(0.035, 0.045, 0.05, 1)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(focused and { 0.95, 0.82, 0.26, 1 } or { 0.34, 0.58, 0.62, 1 })
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(value == "" and { 0.48, 0.54, 0.54 } or { 0.94, 0.96, 0.93 })
    love.graphics.printf(value == "" and placeholder or value,
        rect.x + 14, rect.y + 12, rect.width - 28, "left")
end

local function drawCode(rect, code, label)
    love.graphics.setColor(0.91, 0.92, 0.86)
    love.graphics.printf(label, 0, rect.y - 26, Config.baseWidth, "center")
    love.graphics.setColor(0.035, 0.045, 0.05, 1)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(0.86, 0.70, 0.30, 1)
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(0.94, 0.96, 0.93)
    love.graphics.printf(tostring(code or ""), rect.x + 12, rect.y + 10,
        rect.width - 24, "left")
end

function DirectScreen.draw()
    love.graphics.clear(0.05, 0.06, 0.07)
    love.graphics.setColor(0.95, 0.82, 0.26)
    love.graphics.printf("DIRECT INTERNET CO-OP", 0, 34, Config.baseWidth, "center")
    love.graphics.setColor(0.76, 0.82, 0.82)
    love.graphics.printf("NO ACCOUNT  •  NO MATCHMAKING  •  NO RELAY FEE  •  EXPIRING TWO-CODE SETUP",
        0, 66, Config.baseWidth, "center")
    love.graphics.setColor(0.08, 0.10, 0.11, 0.98)
    love.graphics.rectangle("fill", 120, 108, 720, 470, 7, 7)
    love.graphics.setColor(0.34, 0.58, 0.62)
    love.graphics.rectangle("line", 120, 108, 720, 470, 7, 7)

    if DirectScreen.mode == "menu" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("Selected host save slot: " .. tostring(DirectScreen.selectedSlot),
            0, 164, Config.baseWidth, "center")
        love.graphics.setColor(0.68, 0.74, 0.73)
        love.graphics.printf("The host keeps the save. Players exchange the two codes privately.",
            170, 198, 620, "center")
        drawButton("host"); drawButton("join"); drawButton("back")
    elseif DirectScreen.mode == "host_setup" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("THIS DEVICE'S GLOBAL IPv6 ADDRESS", 0, 210, Config.baseWidth, "center")
        drawField(FIELDS.address, DirectScreen.localAddress, "Example: 2600:...",
            DirectScreen.focused == "address")
        drawButton("create"); drawButton("cancel")
    elseif DirectScreen.mode == "guest_setup" then
        drawField(FIELDS.guestCode, DirectScreen.hostCodeInput, "Paste the TPS2H host code",
            DirectScreen.focused == "hostCode")
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("THIS DEVICE'S GLOBAL IPv6 ADDRESS", 0, 274, Config.baseWidth, "center")
        drawField(FIELDS.guestAddress, DirectScreen.localAddress, "Example: 2600:...",
            DirectScreen.focused == "address")
        drawButton("paste"); drawButton("start"); drawButton("cancel")
    elseif DirectScreen.mode == "host_reply" then
        drawCode({ x = 150, y = 134, width = 660, height = 112 },
            DirectScreen.displayCode, "HOST CODE — SHARE PRIVATELY")
        drawField(FIELDS.response, DirectScreen.responseInput, "Paste the TPS2R reply code",
            DirectScreen.focused == "response")
        drawButton("copy"); drawButton("paste"); drawButton("connect"); drawButton("cancel")
    elseif DirectScreen.mode == "opening_guest" then
        drawCode({ x = 150, y = 164, width = 660, height = 128 },
            DirectScreen.displayCode, "REPLY CODE — SEND BACK TO THE HOST")
        drawButton("copy"); drawButton("cancel")
    elseif DirectScreen.mode == "cleanup_failed" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("DIRECT CLEANUP NEEDS ATTENTION", 0, 218,
            Config.baseWidth, "center")
        love.graphics.setColor(0.66, 0.76, 0.75)
        love.graphics.printf("Retry cleanup before creating another invitation. If it still fails, restart the game.",
            180, 264, 600, "center")
        drawButton("cancel")
    else
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("AUTHENTICATING DIRECT CONNECTION", 0, 218, Config.baseWidth, "center")
        love.graphics.setColor(0.66, 0.76, 0.75)
        love.graphics.printf("The exact IPv6 socket will transfer into encrypted game transport after authentication.",
            180, 264, 600, "center")
        drawButton("cancel")
    end

    love.graphics.setColor(0.82, 0.88, 0.88)
    love.graphics.printf(DirectScreen.message, 150, 604, 660, "center")
end

return DirectScreen
