local Config = require("src.config")

local MultiplayerHud = {}

local MARGIN = 18
local BAR_Y = 84
local BAR_HEIGHT = 25
local TOGGLE_WIDTH = 140
local TOGGLE_HEIGHT = 42
local TOGGLE_Y = 116
local PANEL_WIDTH = 450
local PANEL_Y = 166
local PANEL_HEIGHT = 424
local ROW_HEIGHT = 46
local ACTION_HEIGHT = 40
local MAX_VISIBLE_ROWS = 3
local PLAYER_NOTE = "Player names are self-entered. Verify who you invited."

local opened = false
local pressed = nil
local confirmPlayerId = nil

local function contains(rect, x, y)
    return type(rect) == "table"
        and type(x) == "number" and type(y) == "number"
        and x >= rect.x and x <= rect.x + rect.width
        and y >= rect.y and y <= rect.y + rect.height
end

local function center(rect)
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

local function manageable(info)
    return type(info) == "table"
        and info.mode == "host"
        and info.networkKind == "direct"
        and info.canManage == true
end

local function positiveInteger(value)
    value = tonumber(value)
    if not value or value ~= math.floor(value) or value < 1 then return nil end
    return value
end

local function displayName(value)
    value = tostring(value or "Worker")
    value = value:gsub("[%z\1-\31\127]", "?")
    if #value > 24 then value = value:sub(1, 24) end
    return value
end

local function pendingRows(info, panel)
    local rows = {}
    for _, join in ipairs(type(info.pendingJoins) == "table" and info.pendingJoins or {}) do
        local requestId = positiveInteger(join and join.requestId)
        if requestId and #rows < MAX_VISIBLE_ROWS then
            local y = 226 + #rows * ROW_HEIGHT
            rows[#rows + 1] = {
                requestId = requestId,
                name = displayName(join.name),
                bounds = { x = panel.x + 8, y = y, width = panel.width - 16, height = ROW_HEIGHT },
                approve = { x = panel.x + 270, y = y + 3, width = 96, height = ACTION_HEIGHT },
                deny = { x = panel.x + 374, y = y + 3, width = 68, height = ACTION_HEIGHT },
            }
        end
    end
    return rows
end

local function guestRows(info, panel)
    local rows = {}
    for _, guest in ipairs(type(info.connectedGuests) == "table" and info.connectedGuests or {}) do
        local playerId = positiveInteger(guest and (guest.playerId or guest.id))
        if playerId and playerId ~= 1 and #rows < MAX_VISIBLE_ROWS then
            local y = 398 + #rows * ROW_HEIGHT
            rows[#rows + 1] = {
                playerId = playerId,
                name = displayName(guest.name),
                bounds = { x = panel.x + 8, y = y, width = panel.width - 16, height = ROW_HEIGHT },
                remove = { x = panel.x + 322, y = y + 3, width = 120, height = ACTION_HEIGHT },
            }
        end
    end
    return rows
end

function MultiplayerHud.canManage(info)
    return manageable(info)
end

function MultiplayerHud.reset()
    opened = false
    pressed = nil
    confirmPlayerId = nil
end

function MultiplayerHud.open(info)
    if not manageable(info) then
        MultiplayerHud.reset()
        return false
    end
    opened = true
    pressed = nil
    confirmPlayerId = nil
    return true
end

function MultiplayerHud.close()
    local wasOpen = opened
    MultiplayerHud.reset()
    return wasOpen
end

function MultiplayerHud.isOpen()
    return opened
end

-- Pure layout data keeps hit-testing and its tests independent of love.graphics.
function MultiplayerHud.layout(info)
    local allowed = manageable(info)
    local toggle = allowed and {
        x = Config.baseWidth - MARGIN - TOGGLE_WIDTH,
        y = TOGGLE_Y,
        width = TOGGLE_WIDTH,
        height = TOGGLE_HEIGHT,
    } or nil
    local result = {
        manageable = allowed,
        open = allowed and opened,
        toggle = toggle,
        invite = nil,
        note = PLAYER_NOTE,
        pending = {},
        guests = {},
    }
    if not result.open then return result end
    result.panel = {
        x = Config.baseWidth - MARGIN - PANEL_WIDTH,
        y = PANEL_Y,
        width = PANEL_WIDTH,
        height = PANEL_HEIGHT,
    }
    result.pending = pendingRows(info, result.panel)
    result.guests = guestRows(info, result.panel)
    if info.canInvite == true then
        result.invite = {
            x = result.panel.x + 12,
            y = 504,
            width = 180,
            height = 38,
        }
    end
    return result
end

function MultiplayerHud.hitTest(x, y, info)
    local layout = MultiplayerHud.layout(info)
    if not layout.manageable then return nil end
    if contains(layout.toggle, x, y) then return { kind = "toggle" } end
    if not layout.open then return nil end
    for _, row in ipairs(layout.pending) do
        if contains(row.approve, x, y) then
            return { kind = "approve", requestId = row.requestId }
        end
        if contains(row.deny, x, y) then
            return { kind = "deny", requestId = row.requestId }
        end
    end
    for _, row in ipairs(layout.guests) do
        if contains(row.remove, x, y) then
            return { kind = "remove", playerId = row.playerId }
        end
    end
    if contains(layout.invite, x, y) then return { kind = "invite" } end
    if contains(layout.panel, x, y) then return { kind = "panel" } end
    return nil
end

function MultiplayerHud.buttonCenter(kind, identifier, info)
    local layout = MultiplayerHud.layout(info)
    if kind == "toggle" then return center(layout.toggle) end
    if kind == "invite" then return center(layout.invite) end
    if kind == "approve" or kind == "deny" then
        for _, row in ipairs(layout.pending) do
            if row.requestId == positiveInteger(identifier) then return center(row[kind]) end
        end
    elseif kind == "remove" then
        for _, row in ipairs(layout.guests) do
            if row.playerId == positiveInteger(identifier) then return center(row.remove) end
        end
    end
    return nil
end

function MultiplayerHud.keypressed(key, info)
    if not manageable(info) then
        MultiplayerHud.reset()
        return false
    end
    if key == "p" then
        if opened then MultiplayerHud.close() else MultiplayerHud.open(info) end
        return true
    end
    if key == "escape" and opened then
        MultiplayerHud.close()
        return true
    end
    return false
end

function MultiplayerHud.mousepressed(x, y, button, info)
    if button ~= 1 then return false end
    if not manageable(info) then
        MultiplayerHud.reset()
        return false
    end
    local target = MultiplayerHud.hitTest(x, y, info)
    if not target then
        -- Closing is harmless UI state; returning false lets the world receive
        -- the same outside click.
        if opened then MultiplayerHud.close() end
        return false
    end
    if target.kind == "toggle" then
        if opened then MultiplayerHud.close() else MultiplayerHud.open(info) end
        return true
    end
    if target.kind == "panel" then
        pressed = nil
        confirmPlayerId = nil
        return true
    end
    pressed = target
    if target.kind == "remove" then
        if confirmPlayerId ~= target.playerId then
            confirmPlayerId = target.playerId
            return true
        end
        confirmPlayerId = nil
        return { kind = "remove", playerId = target.playerId }
    end
    confirmPlayerId = nil
    if target.kind == "approve" then
        return { kind = "approve", requestId = target.requestId }
    end
    if target.kind == "invite" then return { kind = "invite" } end
    return { kind = "deny", requestId = target.requestId }
end

function MultiplayerHud.mousereleased(x, y, button, info)
    if button ~= 1 then return false end
    local wasPressed = pressed ~= nil
    pressed = nil
    return wasPressed or MultiplayerHud.hitTest(x, y, info) ~= nil
end

local function isPressed(kind, identifier)
    if type(pressed) ~= "table" or pressed.kind ~= kind then return false end
    if kind == "invite" then return true end
    if kind == "approve" or kind == "deny" then return pressed.requestId == identifier end
    return pressed.playerId == identifier
end

local function drawButton(rect, label, active, danger)
    love.graphics.setColor(active and { 0.35, 0.45, 0.39, 1 }
        or danger and { 0.33, 0.12, 0.12, 1 }
        or { 0.12, 0.24, 0.27, 1 })
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(danger and { 0.95, 0.42, 0.36, 1 }
        or { 0.86, 0.70, 0.30, 1 })
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(0.94, 0.96, 0.93, 1)
    love.graphics.printf(label, rect.x + 4, rect.y + 13, rect.width - 8, "center")
end

function MultiplayerHud.draw(info)
    if type(info) ~= "table" or info.mode == "offline" then
        if opened then MultiplayerHud.reset() end
        return
    end
    local direct = info.networkKind == "direct"
    local role = info.mode == "host"
        and (direct and "DIRECT HOST" or "LAN HOST")
        or (direct and "DIRECT GUEST" or "LAN GUEST")
    local players = tonumber(info.playerCount) or 1
    local line = role .. "  •  " .. tostring(players) .. "/4 WORKERS"
    if not direct and info.mode == "host" and info.address then
        line = line .. "  •  " .. tostring(info.address) .. ":" .. tostring(info.port or 22122)
    elseif info.rtt then
        line = line .. "  •  " .. tostring(math.floor(info.rtt + 0.5)) .. " ms"
    end
    local width = math.min(500, math.max(290, love.graphics.getFont():getWidth(line) + 24))
    local x = Config.baseWidth - width - MARGIN
    love.graphics.setColor(0.025, 0.04, 0.05, 0.91)
    love.graphics.rectangle("fill", x, BAR_Y, width, BAR_HEIGHT, 4, 4)
    love.graphics.setColor(info.mode == "host" and { 0.95, 0.78, 0.23, 1 }
        or { 0.38, 0.80, 0.76, 1 })
    love.graphics.rectangle("line", x, BAR_Y, width, BAR_HEIGHT, 4, 4)
    love.graphics.printf(line, x + 8, BAR_Y + 6, width - 16, "center")

    if not manageable(info) then
        if opened then MultiplayerHud.reset() end
        return
    end
    local layout = MultiplayerHud.layout(info)
    drawButton(layout.toggle, opened and "CLOSE PLAYERS" or "PLAYERS (P)", false, false)
    if not layout.open then return end

    local panel = layout.panel
    love.graphics.setColor(0.025, 0.04, 0.05, 0.97)
    love.graphics.rectangle("fill", panel.x, panel.y, panel.width, panel.height, 6, 6)
    love.graphics.setColor(0.95, 0.78, 0.23, 1)
    love.graphics.rectangle("line", panel.x, panel.y, panel.width, panel.height, 6, 6)
    love.graphics.printf("DIRECT PLAYERS", panel.x + 12, panel.y + 14, panel.width - 24, "left")

    love.graphics.setColor(0.67, 0.75, 0.74, 1)
    love.graphics.printf("WAITING FOR APPROVAL", panel.x + 12, 204, 245, "left")
    if #layout.pending == 0 then
        love.graphics.printf("No one is waiting.", panel.x + 12, 244, panel.width - 24, "left")
    end
    for _, row in ipairs(layout.pending) do
        love.graphics.setColor(0.91, 0.93, 0.90, 1)
        love.graphics.printf(row.name, panel.x + 12, row.bounds.y + 16, 248, "left")
        drawButton(row.approve, "APPROVE", isPressed("approve", row.requestId), false)
        drawButton(row.deny, "DENY", isPressed("deny", row.requestId), true)
    end

    love.graphics.setColor(0.67, 0.75, 0.74, 1)
    love.graphics.printf("CONNECTED GUESTS", panel.x + 12, 376, 245, "left")
    if #layout.guests == 0 then
        love.graphics.printf("No guests are connected.", panel.x + 12, 416, panel.width - 24, "left")
    end
    for _, row in ipairs(layout.guests) do
        love.graphics.setColor(0.91, 0.93, 0.90, 1)
        love.graphics.printf(row.name, panel.x + 12, row.bounds.y + 16, 300, "left")
        local confirming = confirmPlayerId == row.playerId
        drawButton(row.remove, confirming and "CONFIRM" or "REMOVE",
            isPressed("remove", row.playerId), true)
    end

    if layout.invite then
        drawButton(layout.invite, "INVITE WORKER", isPressed("invite"), false)
    end

    love.graphics.setColor(0.61, 0.68, 0.67, 1)
    love.graphics.printf(layout.note, panel.x + 12, 550, panel.width - 24, "center")
end

return MultiplayerHud
