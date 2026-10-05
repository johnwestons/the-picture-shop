local Config = require("src.config")
local IpScope = require("src.net.ip_scope")
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
    manualWanInput = "",
    manualDetails = nil,
    manualActive = false,
    focused = nil,
    message = "",
    pressed = nil,
    inviteOnly = false,
    allowIpv4Host = false,
}

local BUTTONS = {
    host = { x = 90, y = 260, width = 230, height = 78, label = "HOST IPv6 GAME" },
    hostIpv4 = { x = 365, y = 260, width = 230, height = 78, label = "HOST IPv4 GAME" },
    manualIpv4 = { x = 350, y = 362, width = 260, height = 54, label = "MANUAL IPv4 ROUTER SETUP" },
    join = { x = 640, y = 260, width = 230, height = 78, label = "JOIN DIRECT GAME" },
    back = { x = 390, y = 500, width = 180, height = 58, label = "BACK" },
    create = { x = 285, y = 390, width = 190, height = 58, label = "CREATE HOST CODE" },
    createIpv4 = { x = 495, y = 390, width = 210, height = 58, label = "HOST IPv4" },
    manualHost = { x = 285, y = 458, width = 210, height = 58, label = "MANUAL IPv4" },
    manualContinue = { x = 285, y = 390, width = 220, height = 58, label = "CONTINUE" },
    manualAdded = { x = 210, y = 458, width = 260, height = 58, label = "I ADDED THIS UDP RULE" },
    manualCancel = { x = 500, y = 458, width = 220, height = 58, label = "CANCEL SETUP" },
    manualDiscard = { x = 210, y = 458, width = 260, height = 58, label = "NO RULE ADDED" },
    manualRuleCleanup = { x = 500, y = 458, width = 220, height = 58, label = "I ADDED A RULE" },
    manualCleanupAck = { x = 330, y = 458, width = 300, height = 58, label = "I REMOVED THE UDP RULE" },
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
    manualWan = { x = 225, y = 270, width = 510, height = 62 },
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
    DirectScreen.manualWanInput = ""
    DirectScreen.manualDetails = nil
    DirectScreen.manualActive = false
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
        "Paste the host code. IPv4 codes do not need this device's IPv6 address.",
        "hostCode")
    return true
end

local function isIpv4Invite(code)
    return type(code) == "string" and code:sub(1, 5) == "TPS1|"
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

local function requestIpv4Host()
    if not DirectScreen.allowIpv4Host
        or not DirectScreen.callbacks
        or type(DirectScreen.callbacks.hostIpv4) ~= "function" then
        DirectScreen.message = "IPv4 Direct hosting is unavailable in this build."
        return false
    end
    local ok, codeOrError = DirectScreen.callbacks.hostIpv4(
        DirectScreen.selectedSlot, playerLabel())
    if ok ~= true then
        DirectScreen.message = tostring(codeOrError or "The IPv4 host could not start.")
        return false
    end
    if type(codeOrError) == "string" then
        DirectScreen.showIpv4HostInvitation(codeOrError)
    else
        DirectScreen.displayCode = nil
        setMode("ipv4_mapping",
            "Finding a safe route and requesting a temporary router mapping.")
    end
    return true
end

local cancel

local function copyManualDetails(value)
    if type(value) ~= "table"
        or not IpScope.parse(value.internalAddress)
        or not IpScope.isGlobal(value.externalAddress) then
        return nil
    end
    local internalPort = tonumber(value.internalPort)
    local externalPort = tonumber(value.externalPort)
    if not internalPort or internalPort ~= math.floor(internalPort)
        or internalPort < 1 or internalPort > 65535
        or not externalPort or externalPort ~= math.floor(externalPort)
        or externalPort < 1 or externalPort > 65535 then
        return nil
    end
    return {
        internalAddress = value.internalAddress,
        internalPort = internalPort,
        externalAddress = value.externalAddress,
        externalPort = externalPort,
        lifetimeSeconds = tonumber(value.lifetimeSeconds),
    }
end

local function chooseManualIpv4()
    if not DirectScreen.allowIpv4Host then
        DirectScreen.message = "Manual IPv4 Direct hosting is unavailable in this build."
        return false
    end
    clearSensitive()
    setMode("ipv4_manual_input",
        "Enter the public WAN IPv4 address shown in your router's status page. The game will not look it up online.",
        "manualWan")
    return true
end

local function requestManualIpv4Host()
    local address = DirectScreen.manualWanInput
    if not IpScope.isGlobal(address) then
        DirectScreen.message = "Enter a canonical public IPv4 address. Private, shared/CGNAT, and reserved addresses cannot be hosted directly."
        DirectScreen.focused = "manualWan"
        return false
    end
    local callback = DirectScreen.callbacks
        and DirectScreen.callbacks.hostIpv4Manual
    if not DirectScreen.allowIpv4Host or type(callback) ~= "function" then
        DirectScreen.message = "Manual IPv4 Direct hosting is unavailable in this build."
        return false
    end
    local called, started, detailsOrError = pcall(callback,
        DirectScreen.selectedSlot, playerLabel(), address)
    if not called or started ~= true then
        DirectScreen.message = tostring(detailsOrError
            or "The secure manual IPv4 listener could not start.")
        return false
    end
    local details = copyManualDetails(detailsOrError)
    if not details then
        DirectScreen.message = "The secure listener did not return safe port-forward details."
        return false
    end
    DirectScreen.manualWanInput = ""
    DirectScreen.manualDetails = details
    setMode("ipv4_manual_rule",
        "Create one temporary UDP port-forward rule exactly as shown. Do not use DMZ, a port range, or an all-protocol rule.")
    return true
end

local function getManualCleanupInfo()
    local callback = DirectScreen.callbacks
        and DirectScreen.callbacks.manualCleanupInfo
    if type(callback) ~= "function" then return nil end
    local called, details = pcall(callback)
    return called and copyManualDetails(details) or nil
end

local function showCleanupFailure(message)
    local details = getManualCleanupInfo()
    if details then
        DirectScreen.showManualCleanup(details, message)
    else
        DirectScreen.showCleanupError(message)
    end
end

local function confirmManualIpv4Rule()
    local callback = DirectScreen.callbacks
        and DirectScreen.callbacks.confirmIpv4Manual
    if type(callback) ~= "function" then
        DirectScreen.message = "The manual IPv4 setup could not be confirmed."
        return false
    end
    local called, confirmed, errorMessage = pcall(callback)
    if not called or confirmed ~= true then
        local details = getManualCleanupInfo()
        if details then
            DirectScreen.showManualCleanup(details,
                "Remove the exact UDP router rule shown before retrying or leaving Direct Play.")
        else
            DirectScreen.message = tostring(errorMessage
                or "The route changed; no invitation was published.")
        end
        return false
    end
    DirectScreen.manualActive = true
    setMode("ipv4_mapping",
        "The rule was confirmed. Finalizing the secure invitation; keep this screen open.")
    return true
end

local function cancelManualWithRule()
    local callback = DirectScreen.callbacks
        and DirectScreen.callbacks.cancelManualWithRule
    if type(callback) ~= "function" then
        DirectScreen.message = "The game could not begin safe router-rule cleanup."
        return false
    end
    local called, cleaned, errorMessage = pcall(callback)
    if not called or cleaned ~= true then
        showCleanupFailure(errorMessage
            or "Remove the router rule before leaving this screen.")
        return false
    end
    return cancel()
end

local function acknowledgeManualCleanup()
    local callback = DirectScreen.callbacks
        and DirectScreen.callbacks.acknowledgeManualCleanup
    if type(callback) ~= "function" then
        DirectScreen.message = "Manual router-rule cleanup is unavailable."
        return false
    end
    local called, acknowledged, errorMessage = pcall(callback)
    if not called or acknowledged ~= true then
        showCleanupFailure(errorMessage
            or "The router-rule removal could not be acknowledged safely.")
        return false
    end
    DirectScreen.manualDetails = nil
    return cancel()
end

local function enterIpv4HostShop()
    if not DirectScreen.callbacks
        or type(DirectScreen.callbacks.enterShop) ~= "function" then
        DirectScreen.message = "The Direct shop session could not be opened."
        return false
    end
    local called, entered, errorMessage = pcall(DirectScreen.callbacks.enterShop)
    if not called or entered ~= true then
        DirectScreen.message = tostring(errorMessage or
            "The Direct shop session could not be opened.")
        return false
    end
    clearSensitive()
    setMode("menu", "")
    return true
end

local function requestGuest()
    if DirectScreen.hostCodeInput == "" then
        DirectScreen.message = "Paste the host code first."
        DirectScreen.focused = "hostCode"
        return false
    end
    if isIpv4Invite(DirectScreen.hostCodeInput) then
        if not DirectScreen.callbacks
            or type(DirectScreen.callbacks.joinIpv4) ~= "function" then
            DirectScreen.message = "IPv4 Direct joining is unavailable in this build."
            return false
        end
        local ok, errorMessage = DirectScreen.callbacks.joinIpv4(
            DirectScreen.hostCodeInput, playerLabel())
        if ok ~= true then
            DirectScreen.message = tostring(errorMessage or "The Direct connection could not start.")
            return false
        end
        DirectScreen.hostCodeInput = ""
        DirectScreen.localAddress = ""
        DirectScreen.displayCode = nil
        setMode("connecting",
            "Connecting securely. Keep this screen open while the host approves you.")
        return true
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
    if value == "" or #value > 160 or value:find("[^A-Za-z0-9_.|:%-]") then return nil end
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
        if isIpv4Invite(value) then
            DirectScreen.focused = "hostCode"
            DirectScreen.message = "IPv4 host code pasted. No global IPv6 address is needed."
        else
            DirectScreen.focused = "address"
            DirectScreen.message = "IPv6 host code pasted. Now enter this device's global IPv6 address."
        end
    else
        return false
    end
    return true
end

cancel = function()
    if DirectScreen.callbacks and type(DirectScreen.callbacks.cancel) == "function" then
        local called, cleaned, cleanupError = pcall(DirectScreen.callbacks.cancel)
        if not called or cleaned ~= true then
            clearSensitive()
            showCleanupFailure(tostring(cleanupError or
                "Direct cleanup could not be verified. Retry before leaving this screen."))
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
            showCleanupFailure(tostring(cleanupError or
                "Direct cleanup could not be verified. Retry before leaving this screen."))
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
    if DirectScreen.focused == "manualWan" then
        local filtered = text:gsub("[^0-9.]", "")
        if filtered == "" then return false end
        DirectScreen.manualWanInput = (DirectScreen.manualWanInput .. filtered):sub(1, 15)
        return true
    end
    local filtered = text:gsub("[^A-Za-z0-9_.|:%-]", "")
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
        if DirectScreen.allowIpv4Host and contains(BUTTONS.hostIpv4, x, y) then
            return "hostIpv4"
        end
        if DirectScreen.allowIpv4Host and contains(BUTTONS.manualIpv4, x, y) then
            return "manualIpv4"
        end
        if contains(BUTTONS.join, x, y) then return "join" end
        if contains(BUTTONS.back, x, y) then return "back" end
    elseif mode == "host_setup" then
        if contains(BUTTONS.create, x, y) then return "create" end
        if DirectScreen.allowIpv4Host and contains(BUTTONS.createIpv4, x, y) then
            return "createIpv4"
        end
        if DirectScreen.allowIpv4Host and contains(BUTTONS.manualHost, x, y) then
            return "manualIpv4"
        end
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
    elseif mode == "opening_host" or mode == "connecting" or mode == "cleanup_failed" then
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    elseif mode == "ipv4_mapping" then
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    elseif mode == "ipv4_manual_input" then
        if contains(BUTTONS.manualContinue, x, y) then return "manualContinue" end
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    elseif mode == "ipv4_manual_rule" then
        if contains(BUTTONS.manualAdded, x, y) then return "manualAdded" end
        if contains(BUTTONS.manualCancel, x, y) then return "manualCancel" end
    elseif mode == "ipv4_manual_cancel" then
        if contains(BUTTONS.manualDiscard, x, y) then return "manualDiscard" end
        if contains(BUTTONS.manualRuleCleanup, x, y) then return "manualRuleCleanup" end
    elseif mode == "ipv4_manual_cleanup" then
        if contains(BUTTONS.manualCleanupAck, x, y) then return "manualCleanupAck" end
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    elseif mode == "ipv4_host_ready" then
        if contains(BUTTONS.copy, x, y) then return "copy" end
        if contains(BUTTONS.start, x, y) then return "enterShop" end
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    end
end

function DirectScreen.enter(options)
    clearSensitive()
    DirectScreen.callbacks = options or {}
    DirectScreen.selectedSlot = tonumber(DirectScreen.callbacks.slot) or 1
    DirectScreen.inviteOnly = DirectScreen.callbacks.inviteOnly == true
    DirectScreen.allowIpv4Host = DirectScreen.callbacks.allowIpv4Host == true
    if DirectScreen.inviteOnly then
        setMode("host_setup",
        "Invite one more worker using IPv6, automatic IPv4 mapping, or manual UDP forwarding if enabled.",
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
    DirectScreen.allowIpv4Host = false
    setMode("menu", "")
end

function DirectScreen.showIpv4HostInvitation(code)
    if type(code) ~= "string" or code == "" then return false end
    clearSensitive()
    DirectScreen.displayCode = code
    setMode("ipv4_host_ready",
        "Share this code, then enter the shop. It expires after 2 minutes if nobody connects; the host approves every worker.")
    return true
end

function DirectScreen.showManualIpv4HostInvitation(code, details)
    local safeDetails = copyManualDetails(details)
    if type(code) ~= "string" or code == "" or not safeDetails then return false end
    clearSensitive()
    DirectScreen.displayCode = code
    DirectScreen.manualDetails = safeDetails
    DirectScreen.manualActive = true
    setMode("ipv4_host_ready",
        "Share this code privately. The invitation expires after 2 minutes. The router rule remains until you remove it; remove it before leaving Direct hosting.")
    return true
end

function DirectScreen.showManualSetupInvalidated(listenerClosed)
    if DirectScreen.mode ~= "ipv4_manual_rule"
        or not copyManualDetails(DirectScreen.manualDetails) then
        return false
    end
    local message = listenerClosed == true
        and "The network changed during setup. The listener is closed and no invitation was published. Did you add the router rule?"
        or "The network changed during setup. No invitation was published, but listener closure is not yet verified; keep the game open while cleanup retries. Did you add the router rule?"
    setMode("ipv4_manual_cancel", message)
    return true
end

function DirectScreen.showIpv4HostPending(message)
    clearSensitive()
    setMode("ipv4_mapping", message or
        "Finding a safe route and requesting a temporary router mapping.")
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

function DirectScreen.showManualCleanup(details, message)
    local safeDetails = copyManualDetails(details)
    clearSensitive()
    if not safeDetails then
        setMode("cleanup_failed", message or
            "The listener could not be confirmed closed. Retry cleanup before leaving the game.")
        return false
    end
    DirectScreen.manualDetails = safeDetails
    setMode("ipv4_manual_cleanup", message or
        "Remove this exact UDP rule in your router, then confirm below before leaving Direct Play.")
    return true
end

function DirectScreen.wantsTextInput()
    return DirectScreen.mode == "host_setup"
        or DirectScreen.mode == "guest_setup"
        or DirectScreen.mode == "host_reply"
        or DirectScreen.mode == "ipv4_manual_input"
end

function DirectScreen.update(_) end

function DirectScreen.keypressed(key)
    local ctrl = love.keyboard and love.keyboard.isDown
        and love.keyboard.isDown("lctrl", "rctrl")
    if ctrl and key == "v" then return pasteCode() end
    if ctrl and key == "c" then return copyCode() end

    if DirectScreen.mode == "menu" then
        if key == "h" then return chooseHost() end
        if key == "4" and DirectScreen.allowIpv4Host then return requestIpv4Host() end
        if key == "m" and DirectScreen.allowIpv4Host then return chooseManualIpv4() end
        if key == "j" or key == "return" or key == "kpenter" then return chooseGuest() end
        if key == "escape" or key == "backspace" then return goBack() end
        return false
    end
    if key == "escape" then
        if DirectScreen.mode == "ipv4_manual_rule" then
            setMode("ipv4_manual_cancel",
                "Did you add the UDP router rule? Choose accurately so cleanup is not lost.")
            return true
        elseif DirectScreen.mode == "ipv4_manual_cancel" then
            setMode("ipv4_manual_rule",
                "Create one temporary UDP port-forward rule exactly as shown. Do not use DMZ, a port range, or an all-protocol rule.")
            return true
        end
        return cancel()
    end
    if key == "tab" and DirectScreen.mode == "guest_setup" then
        DirectScreen.focused = isIpv4Invite(DirectScreen.hostCodeInput)
            and "hostCode"
            or DirectScreen.focused == "hostCode" and "address" or "hostCode"
        return true
    end
    if key == "backspace" then
        if DirectScreen.focused == "address" then
            DirectScreen.localAddress = backspace(DirectScreen.localAddress)
        elseif DirectScreen.focused == "hostCode" then
            DirectScreen.hostCodeInput = backspace(DirectScreen.hostCodeInput)
        elseif DirectScreen.focused == "response" then
            DirectScreen.responseInput = backspace(DirectScreen.responseInput)
        elseif DirectScreen.focused == "manualWan" then
            DirectScreen.manualWanInput = backspace(DirectScreen.manualWanInput)
        else
            return false
        end
        return true
    end
    if key == "return" or key == "kpenter" then
        if DirectScreen.mode == "host_setup" then return requestHost() end
        if DirectScreen.mode == "guest_setup" then return requestGuest() end
        if DirectScreen.mode == "host_reply" then return submitResponse() end
        if DirectScreen.mode == "ipv4_host_ready" then return enterIpv4HostShop() end
        if DirectScreen.mode == "ipv4_manual_input" then return requestManualIpv4Host() end
        if DirectScreen.mode == "ipv4_manual_rule" then return confirmManualIpv4Rule() end
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
    elseif DirectScreen.mode == "ipv4_manual_input" and contains(FIELDS.manualWan, x, y) then
        DirectScreen.focused = "manualWan"; return true
    end
    local action = buttonAt(x, y)
    DirectScreen.pressed = action
    if action == "host" then return chooseHost() end
    if action == "hostIpv4" or action == "createIpv4" then return requestIpv4Host() end
    if action == "manualIpv4" then return chooseManualIpv4() end
    if action == "manualContinue" then return requestManualIpv4Host() end
    if action == "manualAdded" then return confirmManualIpv4Rule() end
    if action == "manualCancel" then
        setMode("ipv4_manual_cancel",
            "Did you add the UDP router rule? Choose accurately so cleanup is not lost.")
        return true
    end
    if action == "manualDiscard" then return cancel() end
    if action == "manualRuleCleanup" then return cancelManualWithRule() end
    if action == "manualCleanupAck" then return acknowledgeManualCleanup() end
    if action == "join" then return chooseGuest() end
    if action == "back" then return goBack() end
    if action == "create" then return requestHost() end
    if action == "start" then return requestGuest() end
    if action == "enterShop" then return enterIpv4HostShop() end
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

local function drawButton(name, label)
    local rect = BUTTONS[name]
    local active = DirectScreen.pressed == name
    love.graphics.setColor(active and { 0.33, 0.47, 0.43, 1 } or { 0.12, 0.24, 0.27, 1 })
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.86, 0.70, 0.30, 1)
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setColor(0.94, 0.96, 0.93)
    love.graphics.printf(label or rect.label,
        rect.x, rect.y + rect.height / 2 - 7, rect.width, "center")
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
    love.graphics.printf("NO ACCOUNT  •  NO MATCHMAKING  •  NO RELAY FEE  •  PRIVATE, EXPIRING INVITATIONS",
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
        drawButton("host")
        if DirectScreen.allowIpv4Host then drawButton("hostIpv4") end
        if DirectScreen.allowIpv4Host then drawButton("manualIpv4") end
        drawButton("join"); drawButton("back")
    elseif DirectScreen.mode == "host_setup" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("THIS DEVICE'S GLOBAL IPv6 ADDRESS", 0, 210, Config.baseWidth, "center")
        drawField(FIELDS.address, DirectScreen.localAddress, "Example: 2600:...",
            DirectScreen.focused == "address")
        drawButton("create")
        if DirectScreen.allowIpv4Host then drawButton("createIpv4") end
        if DirectScreen.allowIpv4Host then drawButton("manualHost") end
        drawButton("cancel")
    elseif DirectScreen.mode == "guest_setup" then
        drawField(FIELDS.guestCode, DirectScreen.hostCodeInput, "Paste a TPS1 or TPS2H host code",
            DirectScreen.focused == "hostCode")
        if isIpv4Invite(DirectScreen.hostCodeInput) then
            love.graphics.setColor(0.91, 0.92, 0.86)
            love.graphics.printf("IPv4 invitation — no public IPv6 address required",
                170, 280, 620, "center")
        else
            love.graphics.setColor(0.91, 0.92, 0.86)
            love.graphics.printf("THIS DEVICE'S GLOBAL IPv6 ADDRESS", 0, 274, Config.baseWidth, "center")
            drawField(FIELDS.guestAddress, DirectScreen.localAddress, "Example: 2600:...",
                DirectScreen.focused == "address")
        end
        drawButton("paste")
        if isIpv4Invite(DirectScreen.hostCodeInput) then
            drawButton("start", "CONNECT")
        else
            drawButton("start")
        end
        drawButton("cancel")
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
    elseif DirectScreen.mode == "connecting" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("CONNECTING TO THE DIRECT HOST", 0, 218, Config.baseWidth, "center")
        love.graphics.setColor(0.66, 0.76, 0.75)
        love.graphics.printf("The host must approve this player before the shop save is shared.",
            180, 264, 600, "center")
        drawButton("cancel")
    elseif DirectScreen.mode == "ipv4_mapping" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("PREPARING A TEMPORARY IPv4 INVITATION", 0, 218,
            Config.baseWidth, "center")
        love.graphics.setColor(0.66, 0.76, 0.75)
        love.graphics.printf("The game will not change router rules. If automatic mapping is unavailable, setup stops safely.",
            180, 264, 600, "center")
        drawButton("cancel")
    elseif DirectScreen.mode == "ipv4_manual_input" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("PUBLIC IPv4 FROM YOUR ROUTER STATUS PAGE", 0, 194,
            Config.baseWidth, "center")
        drawField(FIELDS.manualWan, DirectScreen.manualWanInput,
            "Example: 203.0.113.25", DirectScreen.focused == "manualWan")
        love.graphics.setColor(0.70, 0.77, 0.75)
        love.graphics.printf("Do not use a VPN address. Stop if the router shows private or shared/CGNAT IPv4; this path cannot cross carrier NAT.",
            180, 344, 600, "center")
        drawButton("manualContinue")
        drawButton("cancel")
    elseif DirectScreen.mode == "ipv4_manual_rule" then
        local details = DirectScreen.manualDetails or {}
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("ADD ONE UDP ROUTER RULE", 0, 164,
            Config.baseWidth, "center")
        love.graphics.setColor(0.95, 0.82, 0.26)
        love.graphics.printf("UDP  " .. tostring(details.externalPort or "?")
            .. "  →  " .. tostring(details.internalAddress or "?")
            .. ":" .. tostring(details.internalPort or "?"),
            160, 202, 640, "center")
        love.graphics.setColor(0.72, 0.78, 0.77)
        love.graphics.printf("Router: forward only the external UDP port to this device and internal port shown above. No TCP, port range, or DMZ. Windows Firewall: keep it enabled; if needed, allow this game's inbound UDP on the shown internal port and active Private profile only. Never allow all ports.",
            180, 246, 600, "center")
        love.graphics.printf("The rule does not expire automatically. If you add it, remove it before leaving. If the game closes unexpectedly, remove it directly in your router.",
            180, 332, 600, "center")
        drawButton("manualAdded")
        drawButton("manualCancel")
    elseif DirectScreen.mode == "ipv4_manual_cancel" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("WAS A ROUTER RULE ADDED?", 0, 202,
            Config.baseWidth, "center")
        love.graphics.setColor(0.72, 0.78, 0.77)
        love.graphics.printf("Choose “NO RULE ADDED” only if you did not save a UDP forward. Otherwise choose the cleanup path so removal stays tracked. Keep the game open until cleanup finishes; no invitation was published for this route.",
            180, 252, 600, "center")
        drawButton("manualDiscard")
        drawButton("manualRuleCleanup")
    elseif DirectScreen.mode == "ipv4_manual_cleanup" then
        local details = DirectScreen.manualDetails or {}
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("REMOVE THIS ROUTER RULE", 0, 178,
            Config.baseWidth, "center")
        love.graphics.setColor(0.95, 0.82, 0.26)
        love.graphics.printf("UDP  " .. tostring(details.externalPort or "?")
            .. "  →  " .. tostring(details.internalAddress or "?")
            .. ":" .. tostring(details.internalPort or "?"),
            160, 222, 640, "center")
        love.graphics.setColor(0.72, 0.78, 0.77)
        love.graphics.printf("Delete/save the exact forward in your router. The game confirms cleanup only after its listener is closed.",
            180, 278, 600, "center")
        drawButton("manualCleanupAck")
    elseif DirectScreen.mode == "ipv4_host_ready" then
        drawCode({ x = 150, y = 134, width = 660, height = 128 },
            DirectScreen.displayCode, "IPv4 HOST CODE — SHARE PRIVATELY")
        drawButton("copy")
        drawButton("start", "ENTER SHOP")
        drawButton("cancel")
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
