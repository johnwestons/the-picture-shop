local Config = require("src.config")
local Ui = require("src.screens.ui")

local LanScreen = {
    mode = "menu",
    address = "",
    message = "",
    callbacks = nil,
    selectedSlot = 1,
    pressed = nil,
    discoveredHosts = {},
    rawDiscoveredResults = {},
    discoveryStatus = "Searching local adapters, including USB Ethernet...",
    discoveryMessage = "Searching local adapters, including USB Ethernet...",
    localInterfaces = {},
    matchingHostCount = 0,
    connectionMode = "auto",
    autoJoin = false,
    autoJoinCandidate = nil,
    autoJoinElapsed = 0,
    autoJoinFired = nil,
    reconnect = nil,
}

local BUTTONS = {
    host = { x = 190, y = 294, width = 250, height = 54, label = "HOST THIS SHOP" },
    join = { x = 520, y = 294, width = 250, height = 54, label = "JOIN A SHOP" },
    connect = { x = 300, y = 374, width = 170, height = 58, label = "CONNECT" },
    cancel = { x = 490, y = 374, width = 170, height = 58, label = "CANCEL" },
    back = { x = 390, y = 510, width = 180, height = 50, label = "BACK" },
    refresh = { x = 704, y = 214, width = 106, height = 40, label = "REFRESH" },
    autoJoin = { x = 190, y = 354, width = 580, height = 34, label = "AUTO-JOIN" },
}

local DISCOVERY_ROWS = {
    { x = 190, y = 412, width = 580, height = 42 },
    { x = 190, y = 460, width = 580, height = 42 },
}

local CONNECTION_MODES = {
    { id = "auto", label = "AUTO", x = 150, y = 214, width = 132, height = 40 },
    { id = "wifi", label = "WI-FI", x = 287, y = 214, width = 132, height = 40 },
    { id = "usb", label = "USB TETHER", x = 424, y = 214, width = 132, height = 40 },
    { id = "manual", label = "MANUAL IP", x = 561, y = 214, width = 135, height = 40 },
}

local CONNECTION_MODE_SET = { auto = true, wifi = true, usb = true }

local function contains(rect, x, y)
    return Ui.contains(rect, x, y)
end

local function buttonAt(x, y)
    if LanScreen.mode == "menu" then
        for _, mode in ipairs(CONNECTION_MODES) do
            if contains(mode, x, y) then return "connection:" .. mode.id end
        end
        if contains(BUTTONS.refresh, x, y) then return "refresh" end
        if contains(BUTTONS.autoJoin, x, y) then return "autoJoin" end
        if contains(BUTTONS.host, x, y) then return "host" end
        if contains(BUTTONS.join, x, y) then return "join" end
        for index, rect in ipairs(DISCOVERY_ROWS) do
            if LanScreen.discoveredHosts[index] and contains(rect, x, y) then
                return "discovered:" .. tostring(index)
            end
        end
        if contains(BUTTONS.back, x, y) then return "back" end
    elseif LanScreen.mode == "join" then
        if contains(BUTTONS.connect, x, y) then return "connect" end
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    elseif LanScreen.mode == "connecting" or LanScreen.mode == "reconnecting" then
        if contains(BUTTONS.cancel, x, y) then return "cancel" end
    end
end

local function playerLabel()
    if love.system and love.system.getOS and love.system.getOS() == "Android" then
        return "Android Worker"
    end
    return "PC Worker"
end

local function requestHost()
    if not LanScreen.callbacks or not LanScreen.callbacks.host then return false end
    local ok, message = LanScreen.callbacks.host(LanScreen.selectedSlot, playerLabel())
    if ok == false then LanScreen.message = tostring(message or "Could not start the LAN host.") end
    return ok ~= false
end

local function requestJoin()
    if LanScreen.address == "" then
        LanScreen.message = "Enter the LAN host's local IPv4 address first."
        return false
    end
    if not LanScreen.callbacks or not LanScreen.callbacks.join then return false end
    local ok, message = LanScreen.callbacks.join(LanScreen.address, playerLabel())
    if ok == false then
        LanScreen.message = tostring(message or "Could not start the connection.")
        return false
    end
    LanScreen.mode = "connecting"
    LanScreen.message = "Connecting to " .. LanScreen.address .. "..."
    return true
end

local function requestDiscovered(index)
    local host = LanScreen.discoveredHosts[index]
    if not host then return false end
    LanScreen.address = tostring(host.address) .. ":" .. tostring(host.port)
    return requestJoin()
end

local function cancelConnection()
    if LanScreen.callbacks and LanScreen.callbacks.cancel then LanScreen.callbacks.cancel() end
    LanScreen.mode = "menu"
    LanScreen.message = "Connection cancelled."
    return true
end

local function goBack()
    if LanScreen.callbacks and LanScreen.callbacks.back then LanScreen.callbacks.back() end
    return true
end

local function saveConnectionSettings()
    if LanScreen.callbacks and type(LanScreen.callbacks.saveSettings) == "function" then
        local ok = LanScreen.callbacks.saveSettings()
        return ok ~= false
    end
    return true
end

local function openManualEntry()
    LanScreen.mode = "join"
    LanScreen.message = "Enter the host's local IPv4 address, then connect."
end

function LanScreen.setConnectionMode(mode)
    if mode == "manual" then openManualEntry(); return true end
    if not CONNECTION_MODE_SET[mode] then return false end
    LanScreen.connectionMode = mode
    LanScreen.autoJoinCandidate = nil
    LanScreen.autoJoinElapsed = 0
    LanScreen.autoJoinFired = nil
    local saved = true
    if LanScreen.callbacks and type(LanScreen.callbacks.settings) == "table" then
        LanScreen.callbacks.settings.lanConnectionMode = mode
        saved = saveConnectionSettings()
    end
    LanScreen.setDiscovery(LanScreen.rawDiscoveredResults, LanScreen.discoveryStatus)
    LanScreen.mode = "menu"
    LanScreen.message = mode == "usb"
        and "Choose a found shop, or enter the host's USB Ethernet IPv4 address."
        or "Choose a found shop, or enter the host device's local IPv4 address."
    if not saved then LanScreen.message = LanScreen.message .. " Preference could not be saved." end
    return true
end

function LanScreen.setAutoJoin(enabled)
    LanScreen.autoJoin = enabled == true
    LanScreen.autoJoinCandidate = nil
    LanScreen.autoJoinElapsed = 0
    LanScreen.autoJoinFired = nil
    local saved = true
    if LanScreen.callbacks and type(LanScreen.callbacks.settings) == "table" then
        LanScreen.callbacks.settings.lanAutoJoin = LanScreen.autoJoin
        saved = saveConnectionSettings()
    end
    LanScreen.message = LanScreen.autoJoin
        and "Auto-join is on. The game joins only when exactly one matching shop is found."
        or "Auto-join is off. Select a found shop to connect."
    if not saved then LanScreen.message = LanScreen.message .. " Preference could not be saved." end
    return true
end

function LanScreen.setLocalInterfaces(interfaces)
    local safe = {}
    for _, interface in ipairs(type(interfaces) == "table" and interfaces or {}) do
        local address = type(interface) == "table" and interface.address or nil
        if type(address) == "string" and #address <= 32 then
            safe[#safe + 1] = {
                address = address,
                prefixLength = type(interface) == "table" and tonumber(interface.prefixLength) or nil,
                interfaceName = tostring(type(interface) == "table" and interface.interfaceName or "")
                    :gsub("[%z\1-\31\127]", "?"):sub(1, 48),
                isUsb = type(interface) == "table" and interface.isUsb == true or false,
            }
        end
    end
    LanScreen.localInterfaces = safe
    LanScreen.setDiscovery(LanScreen.rawDiscoveredResults, LanScreen.discoveryStatus)
end

local function parseIPv4(value)
    if type(value) ~= "string" then return nil end
    local octets = {}
    for part in value:gmatch("[^%.]+") do
        local number = tonumber(part)
        if not number or number ~= math.floor(number) or number < 0 or number > 255 then return nil end
        octets[#octets + 1] = number
    end
    return #octets == 4 and octets or nil
end

local function sameSubnet(interface, hostAddress)
    local localOctets, hostOctets = parseIPv4(interface.address), parseIPv4(hostAddress)
    if not localOctets or not hostOctets then return false end
    local prefix = tonumber(interface.prefixLength)
    if not prefix or prefix ~= math.floor(prefix) or prefix < 1 or prefix > 32 then
        prefix = 24
    end
    local remaining = prefix
    for index = 1, 4 do
        local bits = math.min(8, remaining)
        local block = 2 ^ (8 - bits)
        if math.floor(localOctets[index] / block) ~= math.floor(hostOctets[index] / block) then
            return false
        end
        remaining = remaining - bits
    end
    return true
end

local function hostMatchesMode(address)
    if LanScreen.connectionMode == "auto" then return true end
    for _, interface in ipairs(LanScreen.localInterfaces) do
        local pathMatches = LanScreen.connectionMode == "usb"
            and interface.isUsb or LanScreen.connectionMode == "wifi" and not interface.isUsb
        if pathMatches and sameSubnet(interface, address) then return true end
    end
    return false
end

local function adapterSummary()
    local usb, other
    for _, interface in ipairs(LanScreen.localInterfaces) do
        if interface.isUsb and not usb then usb = interface.address end
        if not interface.isUsb and not other then other = interface.address end
    end
    local usbText = usb or "not detected"
    local otherText = other or "not detected"
    return "USB ETHERNET: " .. usbText .. "     WI-FI / ETHERNET: " .. otherText
end

function LanScreen.enter(options)
    LanScreen.callbacks = options or {}
    LanScreen.selectedSlot = tonumber(LanScreen.callbacks.slot) or 1
    local settings = LanScreen.callbacks.settings
    LanScreen.connectionMode = type(settings) == "table"
        and CONNECTION_MODE_SET[settings.lanConnectionMode] and settings.lanConnectionMode or "auto"
    LanScreen.autoJoin = type(settings) == "table" and settings.lanAutoJoin == true or false
    LanScreen.mode = "menu"
    LanScreen.address = ""
    LanScreen.message = "The host owns the save. Guests need the host device's local IPv4 address to join."
    LanScreen.pressed = nil
    LanScreen.discoveredHosts = {}
    LanScreen.rawDiscoveredResults = {}
    LanScreen.matchingHostCount = 0
    LanScreen.discoveryMessage = "Searching local adapters, including USB Ethernet..."
    LanScreen.discoveryStatus = LanScreen.discoveryMessage
    LanScreen.localInterfaces = {}
    LanScreen.autoJoinCandidate = nil
    LanScreen.autoJoinElapsed = 0
    LanScreen.autoJoinFired = nil
    LanScreen.reconnect = nil
end


function LanScreen.setDiscovery(results, message)
    local safeResults = {}
    for _, result in ipairs(type(results) == "table" and results or {}) do
        local address, port = result and result.address, result and tonumber(result.port)
        if type(address) == "string" and #address >= 1 and #address <= 64
            and port and port == math.floor(port) and port >= 1 and port <= 65535
        then
            safeResults[#safeResults + 1] = {
                address = address,
                port = port,
                name = tostring(result.name or "Local shop"):gsub("[%z\1-\31\127]", "?"):sub(1, 32),
            }
        end
    end
    LanScreen.rawDiscoveredResults = safeResults
    LanScreen.discoveryStatus = tostring(message or "Searching local adapters, including USB Ethernet...")
    local hosts = {}
    local matchCount = 0
    for _, result in ipairs(safeResults) do
        if hostMatchesMode(result.address) then
            matchCount = matchCount + 1
            if #hosts < #DISCOVERY_ROWS then hosts[#hosts + 1] = result end
        end
    end
    LanScreen.discoveredHosts = hosts
    LanScreen.matchingHostCount = matchCount
    if matchCount ~= 1 then
        LanScreen.autoJoinCandidate = nil
        LanScreen.autoJoinElapsed = 0
        LanScreen.autoJoinFired = nil
    end
    local fallback = LanScreen.discoveryStatus
    if matchCount == 0 then
        if LanScreen.connectionMode == "usb" then
            local foundUsb = false
            for _, interface in ipairs(LanScreen.localInterfaces) do
                if interface.isUsb then foundUsb = true; break end
            end
            fallback = foundUsb and "Searching the USB tether link..."
                or "No USB Ethernet address found. Enable USB tethering or choose WI-FI."
        elseif LanScreen.connectionMode == "wifi" then
            local foundWifi = false
            for _, interface in ipairs(LanScreen.localInterfaces) do
                if not interface.isUsb then foundWifi = true; break end
            end
            fallback = foundWifi and "Searching Wi-Fi / hotspot..."
                or "No Wi-Fi address found. Join a Wi-Fi network or choose AUTO."
        end
    elseif matchCount > #DISCOVERY_ROWS then
        fallback = tostring(matchCount) .. " shops found; showing the first two."
    end
    LanScreen.discoveryMessage = tostring(fallback)
        :gsub("[%z\1-\31\127]", "?"):sub(1, 96)
end

function LanScreen.discoveredCenter(index)
    local rect = DISCOVERY_ROWS[tonumber(index)]
    if not rect or not LanScreen.discoveredHosts[tonumber(index)] then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function LanScreen.showReconnect(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    LanScreen.mode = "reconnecting"
    LanScreen.reconnect = {
        attempt = tonumber(snapshot.attempt) or 0,
        maxAttempts = tonumber(snapshot.maxAttempts) or 0,
        nextIn = tonumber(snapshot.nextIn) or 0,
        state = tostring(snapshot.state or "waiting"),
        address = snapshot.target and tostring(snapshot.target.address or "") or LanScreen.address,
        lastError = snapshot.lastError and tostring(snapshot.lastError) or nil,
    }
    if LanScreen.reconnect.address ~= "" then LanScreen.address = LanScreen.reconnect.address end
    if LanScreen.reconnect.state == "connecting" then
        LanScreen.message = string.format("Reconnect attempt %d of %d is contacting %s...",
            LanScreen.reconnect.attempt, LanScreen.reconnect.maxAttempts, LanScreen.address)
    else
        LanScreen.message = string.format("Host link lost. Retrying in %d second%s...",
            math.max(0, math.ceil(LanScreen.reconnect.nextIn)),
            math.ceil(LanScreen.reconnect.nextIn) == 1 and "" or "s")
    end
end

function LanScreen.setMessage(message, mode)
    if mode then LanScreen.mode = mode end
    LanScreen.message = tostring(message or "")
end

function LanScreen.showError(message)
    LanScreen.mode = "join"
    LanScreen.message = tostring(message or "The LAN connection ended.")
    LanScreen.reconnect = nil
end

function LanScreen.wantsTextInput()
    return LanScreen.mode == "join"
end

function LanScreen.update(dt)
    if LanScreen.mode ~= "menu" or not LanScreen.autoJoin
        or LanScreen.matchingHostCount ~= 1
        or not LanScreen.discoveredHosts[1]
    then
        LanScreen.autoJoinCandidate = nil
        LanScreen.autoJoinElapsed = 0
        return
    end
    local host = LanScreen.discoveredHosts[1]
    local signature = host.address .. ":" .. tostring(host.port)
    if LanScreen.autoJoinCandidate ~= signature then
        LanScreen.autoJoinCandidate = signature
        LanScreen.autoJoinElapsed = 0
        LanScreen.autoJoinFired = nil
        return
    end
    if LanScreen.autoJoinFired == signature then return end
    LanScreen.autoJoinElapsed = LanScreen.autoJoinElapsed + math.max(0, tonumber(dt) or 0)
    if LanScreen.autoJoinElapsed >= 1.5 then
        LanScreen.autoJoinFired = signature
        requestDiscovered(1)
    end
end

function LanScreen.keypressed(key)
    if LanScreen.mode == "menu" then
        if key == "h" or key == "return" or key == "kpenter" then return requestHost() end
        if key == "j" then openManualEntry(); return true end
        if key == "escape" or key == "backspace" then return goBack() end
        return false
    end
    if LanScreen.mode == "join" then
        if key == "backspace" then
            local byteOffset = utf8 and utf8.offset and utf8.offset(LanScreen.address, -1)
            LanScreen.address = byteOffset and LanScreen.address:sub(1, byteOffset - 1) or LanScreen.address:sub(1, -2)
            return true
        end
        if key == "return" or key == "kpenter" then return requestJoin() end
        if key == "escape" then LanScreen.mode = "menu"; LanScreen.message = "Choose a connection method or select a found shop."; return true end
        return false
    end
    if (LanScreen.mode == "connecting" or LanScreen.mode == "reconnecting")
        and (key == "escape" or key == "backspace")
    then
        return cancelConnection()
    end
    return false
end

function LanScreen.textinput(text)
    if LanScreen.mode ~= "join" or type(text) ~= "string" then return false end
    local filtered = text:gsub("[^%w%.%-:]", "")
    if filtered == "" then return false end
    LanScreen.address = (LanScreen.address .. filtered):sub(1, 96)
    return true
end

function LanScreen.mousepressed(x, y, button)
    if button ~= 1 then return false end
    if LanScreen.mode == "join" and contains({ x = 225, y = 270, width = 510, height = 62 }, x, y) then
        return true
    end
    local action = buttonAt(x, y)
    LanScreen.pressed = action
    if action == "host" then return requestHost() end
    if action == "join" then openManualEntry(); return true end
    if action == "refresh" then
        if LanScreen.callbacks and type(LanScreen.callbacks.refresh) == "function" then
            LanScreen.callbacks.refresh()
        end
        LanScreen.message = "Network adapters refreshed. Searching for shops..."
        return true
    end
    if action == "autoJoin" then return LanScreen.setAutoJoin(not LanScreen.autoJoin) end
    local connectionMode = type(action) == "string" and action:match("^connection:(%w+)$")
    if connectionMode then return LanScreen.setConnectionMode(connectionMode) end
    local discoveredIndex = type(action) == "string" and action:match("^discovered:(%d+)$")
    if discoveredIndex then return requestDiscovered(tonumber(discoveredIndex)) end
    if action == "connect" then return requestJoin() end
    if action == "cancel" then return cancelConnection() end
    if action == "back" then return goBack() end
    return false
end

function LanScreen.mousereleased(_, _, button)
    if button == 1 then LanScreen.pressed = nil end
end

local function drawButton(name)
    local rect = BUTTONS[name]
    local active = LanScreen.pressed == name
    love.graphics.setColor(active and { 0.33, 0.47, 0.43, 1 } or { 0.12, 0.24, 0.27, 1 })
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.86, 0.70, 0.30, 1)
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setColor(0.94, 0.96, 0.93)
    love.graphics.printf(rect.label, rect.x, rect.y + rect.height / 2 - 7, rect.width, "center")
    love.graphics.setLineWidth(1)
end

local function drawModeButton(mode)
    local selected = LanScreen.connectionMode == mode.id
    local rect = mode
    love.graphics.setColor(selected and { 0.04, 0.35, 0.37, 1 } or { 0.11, 0.16, 0.17, 1 })
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(selected and { 0.28, 0.90, 0.84, 1 } or { 0.42, 0.53, 0.52, 1 })
    love.graphics.setLineWidth(selected and 2 or 1)
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(selected and { 0.92, 1, 0.97, 1 } or { 0.76, 0.82, 0.80, 1 })
    love.graphics.printf(rect.label, rect.x, rect.y + 15, rect.width, "center")
    love.graphics.setLineWidth(1)
end

local function drawAutoJoinToggle()
    local rect = BUTTONS.autoJoin
    love.graphics.setColor(LanScreen.autoJoin and { 0.04, 0.27, 0.21, 1 } or { 0.09, 0.13, 0.14, 1 })
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(LanScreen.autoJoin and { 0.26, 0.76, 0.45, 1 } or { 0.38, 0.48, 0.47, 1 })
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 4, 4)
    local status = LanScreen.autoJoin and "ON" or "OFF"
    love.graphics.setColor(0.89, 0.93, 0.90, 1)
    love.graphics.printf("AUTO-JOIN ONE FOUND SHOP: " .. status
        .. "     (only connects when exactly one matching shop is found)",
        rect.x + 10, rect.y + 11, rect.width - 20, "center")
end

function LanScreen.draw()
    love.graphics.clear(0.05, 0.06, 0.07)
    love.graphics.setColor(0.95, 0.82, 0.26)
    love.graphics.printf("LOCAL SHOP NETWORK", 0, 44, Config.baseWidth, "center")
    love.graphics.setColor(0.76, 0.82, 0.82)
    love.graphics.printf("WINDOWS / ANDROID  •  WI-FI, HOTSPOT OR USB-C  •  UP TO 4 WORKERS", 0, 76, Config.baseWidth, "center")

    love.graphics.setColor(0.08, 0.10, 0.11, 0.98)
    love.graphics.rectangle("fill", 120, 118, 720, 452, 7, 7)
    love.graphics.setColor(0.34, 0.58, 0.62)
    love.graphics.rectangle("line", 120, 118, 720, 452, 7, 7)

    if LanScreen.mode == "menu" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("Selected save slot: " .. tostring(LanScreen.selectedSlot), 0, 144, Config.baseWidth, "center")
        love.graphics.setColor(0.68, 0.74, 0.73)
        love.graphics.printf("The host runs the shop and keeps the save. Guests join as additional workers.", 170, 169, 620, "center")
        love.graphics.setColor(0.60, 0.79, 0.76)
        love.graphics.printf("USB-C needs a data cable and Android USB tethering; the cable alone is not a network.",
            155, 190, 650, "center")
        love.graphics.setColor(0.60, 0.79, 0.76)
        for _, mode in ipairs(CONNECTION_MODES) do drawModeButton(mode) end
        drawButton("refresh")
        love.graphics.setColor(0.67, 0.75, 0.74)
        love.graphics.printf("ADDRESSES ON THIS DEVICE", 190, 258, 580, "left")
        love.graphics.setColor(0.90, 0.92, 0.87)
        love.graphics.printf(adapterSummary(), 190, 274, 580, "center")
        drawButton("host")
        drawButton("join")
        drawAutoJoinToggle()
        love.graphics.setColor(0.67, 0.75, 0.74)
        love.graphics.printf("FOUND SHOPS", 190, 392, 580, "left")
        if #LanScreen.discoveredHosts == 0 then
            love.graphics.printf(LanScreen.discoveryMessage, 190, 426, 580, "center")
        end
        for index, host in ipairs(LanScreen.discoveredHosts) do
            local rect = DISCOVERY_ROWS[index]
            love.graphics.setColor(LanScreen.pressed == "discovered:" .. tostring(index)
                and { 0.25, 0.40, 0.39, 1 } or { 0.07, 0.13, 0.14, 1 })
            love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
            love.graphics.setColor(0.38, 0.80, 0.76, 1)
            love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 4, 4)
            love.graphics.printf(host.name, rect.x + 12, rect.y + 14, 300, "left")
            love.graphics.printf(host.address .. ":" .. tostring(host.port),
                rect.x + 316, rect.y + 14, rect.width - 328, "right")
        end
        drawButton("back")
        love.graphics.setColor(0.62, 0.68, 0.67)
        local hint = LanScreen.connectionMode == "usb"
            and "No USB address? Enable USB tethering in Android Network / Connections settings."
            or "Tap a found shop, or choose MANUAL IP to enter the host address."
        love.graphics.printf(hint, 150, 574, 660, "center")
    elseif LanScreen.mode == "join" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("LAN HOST LOCAL IPv4 ADDRESS", 0, 184, Config.baseWidth, "center")
        love.graphics.setColor(0.60, 0.79, 0.76)
        local transportHint = LanScreen.connectionMode == "usb"
            and "USB-C: enable Android USB tethering in Network / Connections settings."
            or "Join the same Wi-Fi network or phone hotspot as the host. Internet is not required."
        love.graphics.printf(transportHint, 170, 220, 620, "center")
        love.graphics.setColor(0.60, 0.71, 0.69)
        local addressHint = LanScreen.connectionMode == "usb"
            and "Enter the host's USB Ethernet address shown on Local Play; phone-to-phone needs USB Ethernet support."
            or "Enter the host's local address shown on Local Play; use an address on the same network."
        love.graphics.printf(addressHint,
            170, 242, 620, "center")
        love.graphics.setColor(0.035, 0.045, 0.05, 1)
        love.graphics.rectangle("fill", 225, 270, 510, 62, 4, 4)
        love.graphics.setColor(0.86, 0.70, 0.30, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", 225, 270, 510, 62, 4, 4)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(LanScreen.address == "" and { 0.48, 0.54, 0.54 } or { 0.94, 0.96, 0.93 })
        local example = LanScreen.connectionMode == "usb" and "Example USB address: 192.168.42.129"
            or "Example: 192.168.1.246"
        love.graphics.print(LanScreen.address == "" and example or LanScreen.address, 246, 292)
        drawButton("connect")
        drawButton("cancel")
    elseif LanScreen.mode == "connecting" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("CONNECTING TO THE HOST", 0, 220, Config.baseWidth, "center")
        love.graphics.setColor(0.66, 0.76, 0.75)
        love.graphics.printf("The game is exchanging a compatible protocol hello and shop snapshot.", 190, 268, 580, "center")
        drawButton("cancel")
    else
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("RECONNECTING TO THE HOST", 0, 202, Config.baseWidth, "center")
        love.graphics.setColor(0.66, 0.76, 0.75)
        love.graphics.printf("Each attempt creates a fresh worker session and waits for a new host snapshot.",
            190, 250, 580, "center")
        if LanScreen.reconnect and LanScreen.reconnect.lastError then
            love.graphics.printf(LanScreen.reconnect.lastError, 190, 306, 580, "center")
        end
        drawButton("cancel")
    end

    love.graphics.setColor(0.82, 0.88, 0.88)
    love.graphics.printf(LanScreen.message, 150, 598, 660, "center")
end

return LanScreen
