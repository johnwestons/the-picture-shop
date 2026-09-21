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
    discoveryMessage = "Searching for shops on this network...",
    reconnect = nil,
    internet = false,
}

local BUTTONS = {
    host = { x = 190, y = 260, width = 250, height = 78, label = "HOST THIS SHOP" },
    join = { x = 520, y = 260, width = 250, height = 78, label = "JOIN A SHOP" },
    connect = { x = 300, y = 374, width = 170, height = 58, label = "CONNECT" },
    cancel = { x = 490, y = 374, width = 170, height = 58, label = "CANCEL" },
    back = { x = 390, y = 500, width = 180, height = 58, label = "BACK" },
}

local DISCOVERY_ROWS = {
    { x = 190, y = 374, width = 580, height = 42 },
    { x = 190, y = 422, width = 580, height = 42 },
}

local function contains(rect, x, y)
    return Ui.contains(rect, x, y)
end

local function buttonAt(x, y)
    if LanScreen.mode == "menu" then
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
        LanScreen.message = LanScreen.internet
            and "Enter the host's public IPv4 address and port first."
            or "Enter the LAN host's local IPv4 address first."
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

function LanScreen.enter(options)
    LanScreen.callbacks = options or {}
    LanScreen.internet = LanScreen.callbacks.internet == true
    LanScreen.selectedSlot = tonumber(LanScreen.callbacks.slot) or 1
    LanScreen.mode = "menu"
    LanScreen.address = ""
    LanScreen.message = LanScreen.internet
        and "The host owns the save. Guests connect using the host's public IPv4:port."
        or "The host owns the save. Guests need only the host device's local IPv4 address."
    LanScreen.pressed = nil
    LanScreen.discoveredHosts = {}
    LanScreen.discoveryMessage = LanScreen.internet
        and "Internet search is unavailable without a matchmaking service. Use JOIN A SHOP."
        or "Searching for shops on this network..."
    LanScreen.reconnect = nil
end


function LanScreen.setDiscovery(results, message)
    local hosts = {}
    for _, result in ipairs(type(results) == "table" and results or {}) do
        local address, port = result and result.address, result and tonumber(result.port)
        if type(address) == "string" and #address >= 1 and #address <= 64
            and port and port == math.floor(port) and port >= 1 and port <= 65535
            and #hosts < #DISCOVERY_ROWS
        then
            hosts[#hosts + 1] = {
                address = address,
                port = port,
                name = tostring(result.name or "Local shop"):gsub("[%z\1-\31\127]", "?"):sub(1, 32),
            }
        end
    end
    LanScreen.discoveredHosts = hosts
    LanScreen.discoveryMessage = tostring(message or "Searching for shops on this network...")
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

function LanScreen.update(_) end

function LanScreen.keypressed(key)
    if LanScreen.mode == "menu" then
        if key == "h" or key == "return" or key == "kpenter" then return requestHost() end
        if key == "j" then LanScreen.mode = "join"; LanScreen.message = "Enter the host address, then connect."; return true end
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
        if key == "escape" then LanScreen.mode = "menu"; LanScreen.message = "Choose a LAN role."; return true end
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
    if action == "join" then LanScreen.mode = "join"; LanScreen.message = "Enter the host address, then connect."; return true end
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
    local label = rect.label
    if LanScreen.internet and name == "host" then label = "HOST ONLINE GAME" end
    if LanScreen.internet and name == "join" then label = "JOIN ONLINE GAME" end
    love.graphics.printf(label, rect.x, rect.y + rect.height / 2 - 7, rect.width, "center")
    love.graphics.setLineWidth(1)
end

function LanScreen.draw()
    love.graphics.clear(0.05, 0.06, 0.07)
    love.graphics.setColor(0.95, 0.82, 0.26)
    love.graphics.printf(LanScreen.internet and "ONLINE MULTIPLAYER" or "LOCAL SHOP NETWORK",
        0, 44, Config.baseWidth, "center")
    love.graphics.setColor(0.76, 0.82, 0.82)
    love.graphics.printf("WINDOWS / ANDROID  •  SAME WI-FI OR PHONE HOTSPOT  •  UP TO 4 WORKERS", 0, 76, Config.baseWidth, "center")

    love.graphics.setColor(0.08, 0.10, 0.11, 0.98)
    love.graphics.rectangle("fill", 120, 118, 720, 452, 7, 7)
    love.graphics.setColor(0.34, 0.58, 0.62)
    love.graphics.rectangle("line", 120, 118, 720, 452, 7, 7)

    if LanScreen.mode == "menu" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf("Selected save slot: " .. tostring(LanScreen.selectedSlot), 0, 164, Config.baseWidth, "center")
        love.graphics.setColor(0.68, 0.74, 0.73)
        love.graphics.printf(LanScreen.internet
            and "Host forwards UDP 22122; guests enter the host's public IPv4:port."
            or "The host runs the shop and keeps the save. Guests join as additional workers.",
            170, 198, 620, "center")
        drawButton("host")
        drawButton("join")
        love.graphics.setColor(0.67, 0.75, 0.74)
        love.graphics.printf(LanScreen.internet and "ONLINE SEARCH / MANUAL CONNECT" or "FOUND SHOPS",
            190, 348, 580, "left")
        if #LanScreen.discoveredHosts == 0 then
            love.graphics.printf(LanScreen.discoveryMessage, 190, 390, 580, "center")
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
        love.graphics.printf(LanScreen.internet
            and "Search needs a matchmaking service; use JOIN ONLINE GAME."
            or "Tap a found shop, or use JOIN A SHOP for manual entry.",
            0, 474, Config.baseWidth, "center")
    elseif LanScreen.mode == "join" then
        love.graphics.setColor(0.91, 0.92, 0.86)
        love.graphics.printf(LanScreen.internet
            and "ONLINE HOST PUBLIC IPv4 ADDRESS AND PORT"
            or "LAN HOST LOCAL IPv4 ADDRESS", 0, 184, Config.baseWidth, "center")
        love.graphics.setColor(0.035, 0.045, 0.05, 1)
        love.graphics.rectangle("fill", 225, 270, 510, 62, 4, 4)
        love.graphics.setColor(0.86, 0.70, 0.30, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", 225, 270, 510, 62, 4, 4)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(LanScreen.address == "" and { 0.48, 0.54, 0.54 } or { 0.94, 0.96, 0.93 })
        love.graphics.print(LanScreen.address == "" and
            (LanScreen.internet and "Example: 203.0.113.10:22122" or "Example: 192.168.1.246")
            or LanScreen.address, 246, 292)
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
