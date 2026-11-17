local Config = require("src.config")
local OverlayLayout = require("src.screens.world_overlay_layout")

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
local profileRequestId = nil

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
        and info.canManage == true
end

local function viewable(info)
    return type(info) == "table"
        and (info.mode == "host" or info.mode == "client")
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

local RESOURCE_LABELS = {
    reception_customer = "RECEPTION",
    vendor = "SUPPLIER CATALOG",
    truck = "DELIVERY TRUCK",
    office_computer = "OFFICE COMPUTER",
    cutter = "POLAR CUTTER",
    windmill = "WINDMILL",
    skid_wrapper = "SKID WRAPPER",
    pallet_jack = "PALLET JACK",
}

local function resourceLabel(resourceId)
    return RESOURCE_LABELS[resourceId] or tostring(resourceId or "SHARED CONTROL")
        :gsub("_", " "):upper()
end

local function playerName(info, playerId)
    for _, player in ipairs(type(info.players) == "table" and info.players or {}) do
        if positiveInteger(player and (player.playerId or player.id)) == playerId then
            return displayName(player.name)
        end
    end
    return playerId == 1 and "Host" or ("Worker " .. tostring(playerId or "?"))
end

local function pendingLabel(pending)
    if type(pending) ~= "table" then return nil end
    local target = pending.resourceId and resourceLabel(pending.resourceId)
        or tostring(pending.targetKind or "SHOP ACTION"):gsub("_", " "):upper()
    if pending.kind == "urgent_safety" then
        return "URGENT SAFETY SENT • WAITING FOR HOST • " .. target
    elseif pending.kind == "workshop_acquire" then
        return "REQUESTING " .. target .. " • WAITING FOR HOST"
    end
    return target .. " • WAITING FOR HOST"
end

local function statusPlayers(info)
    local rows = {}
    for _, player in ipairs(type(info.players) == "table" and info.players or {}) do
        local playerId = positiveInteger(player and (player.playerId or player.id))
        if playerId and #rows < 4 then
            local badges = {}
            if playerId == 1 or player.isHost == true then badges[#badges + 1] = "HOST" end
            if playerId == positiveInteger(info.localPlayerId) or player.isLocal == true then
                badges[#badges + 1] = "YOU"
            end
            rows[#rows + 1] = {
                playerId = playerId,
                name = displayName(player.name),
                badge = table.concat(badges, " • "),
            }
        end
    end
    table.sort(rows, function(left, right) return left.playerId < right.playerId end)
    return rows
end

function MultiplayerHud.statusSummary(info)
    info = type(info) == "table" and info or {}
    local isHost = info.mode == "host"
    local rtt = tonumber(info.rtt)
    local connection
    if isHost then
        connection = "HOST ONLINE"
    elseif rtt then
        local quality = rtt <= 80 and "GOOD" or rtt <= 180 and "FAIR" or "SLOW"
        connection = string.format("CONNECTED • %d MS • %s", math.floor(rtt + 0.5), quality)
    else
        connection = "CONNECTED • MEASURING LINK"
    end

    local control = pendingLabel(info.pendingActivity)
    if not control and info.activeResourceId then
        control = "YOU CONTROL • " .. resourceLabel(info.activeResourceId)
    end
    if not control then
        local occupied = {}
        for _, resource in ipairs(type(info.workshopResources) == "table"
            and info.workshopResources or {}) do
            local ownerPlayerId = positiveInteger(resource and resource.ownerPlayerId)
            if resource and resource.occupied == true and ownerPlayerId then
                occupied[#occupied + 1] = playerName(info, ownerPlayerId)
                    .. " USING • " .. resourceLabel(resource.resourceId)
            end
        end
        if #occupied > 0 then
            control = occupied[1] .. (#occupied > 1
                and ("  + " .. tostring(#occupied - 1) .. " MORE") or "")
        else
            control = "ALL SHARED CONTROLS AVAILABLE"
        end
    end
    return {
        authority = isHost and "THIS DEVICE OWNS AND SAVES THE SHOP"
            or "THE HOST DEVICE OWNS AND SAVES THE SHOP",
        connection = connection,
        control = control,
        status = tostring(info.status or "Session active"):gsub("[%z\1-\31\127]", "?"):sub(1, 72),
    }
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
                unmatched = join.unmatched == true,
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
    profileRequestId = nil
end

function MultiplayerHud.open(info)
    if not viewable(info) then
        MultiplayerHud.reset()
        return false
    end
    opened = true
    pressed = nil
    confirmPlayerId = nil
    profileRequestId = nil
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
    local visible = viewable(info)
    local allowed = manageable(info)
    local toggle = visible and OverlayLayout.rect(info.overlayLayout, 'session',
        TOGGLE_WIDTH, TOGGLE_HEIGHT,
        Config.baseWidth - MARGIN - TOGGLE_WIDTH, TOGGLE_Y) or nil
    local result = {
        viewable = visible,
        manageable = allowed,
        open = visible and opened,
        toggle = toggle,
        invite = nil,
        note = PLAYER_NOTE,
        pending = {},
        guests = {},
        statusPlayers = {},
        summary = nil,
    }
    if not result.open then return result end
    result.panel = {
        x = Config.baseWidth - MARGIN - PANEL_WIDTH,
        y = PANEL_Y,
        width = PANEL_WIDTH,
        height = PANEL_HEIGHT,
    }
    if not allowed then
        result.statusPlayers = statusPlayers(info)
        result.summary = MultiplayerHud.statusSummary(info)
        return result
    end
    result.pending = pendingRows(info, result.panel)
    result.guests = guestRows(info, result.panel)
    if profileRequestId then
        for _,join in ipairs(info.pendingJoins or {}) do
            if join.requestId==profileRequestId and join.unmatched then
                local choices={}
                if join.canCreate then
                    choices[#choices+1]={choice='new',label='CREATE NEW CLIENT SAVE'}
                end
                for _,saved in ipairs(join.profileChoices or {}) do
                    choices[#choices+1]={choice=saved.slot,
                        label='CLAIM SLOT '..saved.slot..'  '..displayName(saved.name)}
                end
                for index,row in ipairs(choices) do
                    row.bounds={x=result.panel.x+12,y=266+(index-1)*56,width=result.panel.width-24,height=46}
                end
                result.profile={requestId=profileRequestId,name=displayName(join.name),choices=choices,
                    back={x=result.panel.x+12,y=514,width=120,height=40},
                    deny={x=result.panel.x+result.panel.width-132,y=514,width=120,height=40}}
                break
            end
        end
        if not result.profile then profileRequestId=nil end
    end
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
    if not layout.viewable then return nil end
    if contains(layout.toggle, x, y) then return { kind = "toggle" } end
    if not layout.open then return nil end
    if layout.profile then
        for _,row in ipairs(layout.profile.choices) do
            if contains(row.bounds,x,y) then
                return {kind='approve',requestId=layout.profile.requestId,profileChoice=row.choice}
            end
        end
        if contains(layout.profile.back,x,y) then return {kind='profile_back'} end
        if contains(layout.profile.deny,x,y) then
            return {kind='deny',requestId=layout.profile.requestId}
        end
        if contains(layout.panel,x,y) then return {kind='panel'} end
        return nil
    end
    for _, row in ipairs(layout.manageable and layout.pending or {}) do
        if contains(row.approve, x, y) then
            return { kind = row.unmatched and 'choose_profile' or 'approve', requestId = row.requestId }
        end
        if contains(row.deny, x, y) then
            return { kind = "deny", requestId = row.requestId }
        end
    end
    for _, row in ipairs(layout.manageable and info.networkKind=='direct' and layout.guests or {}) do
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
    if not viewable(info) then
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
    if not viewable(info) then
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
    if target.kind=='choose_profile' then
        profileRequestId=target.requestId
        return true
    end
    if target.kind=='profile_back' then profileRequestId=nil;return true end
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
        profileRequestId=nil
        return { kind = "approve", requestId = target.requestId,profileChoice=target.profileChoice }
    end
    if target.kind == "invite" then return { kind = "invite" } end
    profileRequestId=nil
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

local function drawStatusPanel(info, layout)
    local panel, summary = layout.panel, layout.summary
    love.graphics.setColor(0.025, 0.04, 0.05, 0.97)
    love.graphics.rectangle("fill", panel.x, panel.y, panel.width, panel.height, 6, 6)
    love.graphics.setColor(0.38, 0.80, 0.76, 1)
    love.graphics.rectangle("line", panel.x, panel.y, panel.width, panel.height, 6, 6)
    love.graphics.printf("LOCAL PLAY STATUS", panel.x + 12, panel.y + 14,
        panel.width - 24, "left")

    love.graphics.setColor(0.91, 0.93, 0.90, 1)
    love.graphics.printf(summary.authority, panel.x + 12, 208, panel.width - 24, "left")
    love.graphics.setColor(0.55, 0.82, 0.77, 1)
    love.graphics.printf(summary.connection, panel.x + 12, 232, panel.width - 24, "left")

    love.graphics.setColor(0.67, 0.75, 0.74, 1)
    love.graphics.printf("CONNECTED WORKERS", panel.x + 12, 270, panel.width - 24, "left")
    if #layout.statusPlayers == 0 then
        love.graphics.printf("Waiting for the roster...", panel.x + 12, 302,
            panel.width - 24, "left")
    end
    for index, row in ipairs(layout.statusPlayers) do
        local y = 300 + (index - 1) * 34
        love.graphics.setColor(0.91, 0.93, 0.90, 1)
        local star=row.playerId==1 and 16 or 0
        if star>0 then
            love.graphics.setColor(.95,.78,.23,1);require('src.player_profile').drawStar(panel.x+18,y+7,6)
            love.graphics.setColor(.91,.93,.90,1)
        end
        love.graphics.printf(row.name, panel.x + 12+star, y, panel.width - 128-star, "left")
        love.graphics.setColor(0.95, 0.78, 0.23, 1)
        love.graphics.printf(row.badge, panel.x + panel.width - 120, y, 108, "right")
    end

    love.graphics.setColor(0.67, 0.75, 0.74, 1)
    love.graphics.printf("SHARED CONTROL", panel.x + 12, 452, panel.width - 24, "left")
    love.graphics.setColor(0.91, 0.93, 0.90, 1)
    love.graphics.printf(summary.control, panel.x + 12, 480, panel.width - 24, "left")
    love.graphics.setColor(0.55, 0.64, 0.63, 1)
    love.graphics.printf(summary.status, panel.x + 12, 522, panel.width - 24, "center")
    love.graphics.printf(PLAYER_NOTE, panel.x + 12, 554, panel.width - 24, "center")
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
    local bar = OverlayLayout.rect(info.overlayLayout, 'netStatus', width, BAR_HEIGHT,
        Config.baseWidth - width - MARGIN, BAR_Y)
    love.graphics.setColor(0.025, 0.04, 0.05, 0.91)
    love.graphics.rectangle("fill", bar.x, bar.y, width, BAR_HEIGHT, 4, 4)
    love.graphics.setColor(info.mode == "host" and { 0.95, 0.78, 0.23, 1 }
        or { 0.38, 0.80, 0.76, 1 })
    love.graphics.rectangle("line", bar.x, bar.y, width, BAR_HEIGHT, 4, 4)
    love.graphics.printf(line, bar.x + 8, bar.y + 6, width - 16, "center")

    local layout = MultiplayerHud.layout(info)
    drawButton(layout.toggle, opened and "CLOSE STATUS" or "SESSION (P)", false, false)
    if not layout.open then return end
    if not layout.manageable then
        drawStatusPanel(info, layout)
        return
    end

    local panel = layout.panel
    love.graphics.setColor(0.025, 0.04, 0.05, 0.97)
    love.graphics.rectangle("fill", panel.x, panel.y, panel.width, panel.height, 6, 6)
    love.graphics.setColor(0.95, 0.78, 0.23, 1)
    love.graphics.rectangle("line", panel.x, panel.y, panel.width, panel.height, 6, 6)
    love.graphics.printf(direct and "DIRECT PLAYERS" or "LAN CLIENT ACCESS",
        panel.x + 12, panel.y + 14, panel.width - 24, "left")

    if layout.profile then
        love.graphics.setColor(.91,.93,.90,1)
        love.graphics.printf('Choose a profile for '..layout.profile.name,
            panel.x+12,214,panel.width-24,'left')
        love.graphics.setColor(.67,.75,.74,1)
        love.graphics.printf('Claiming transfers this saved profile to the joining device.',
            panel.x+12,240,panel.width-24,'left')
        for _,row in ipairs(layout.profile.choices) do
            drawButton(row.bounds,row.label,false,false)
        end
        if #layout.profile.choices==0 then
            love.graphics.printf('All client slots are connected. No profile is available.',
                panel.x+12,290,panel.width-24,'left')
        end
        drawButton(layout.profile.back,'BACK',false,false)
        drawButton(layout.profile.deny,'DENY',false,true)
        return
    end

    love.graphics.setColor(0.67, 0.75, 0.74, 1)
    love.graphics.printf("WAITING FOR APPROVAL", panel.x + 12, 204, 245, "left")
    if #layout.pending == 0 then
        love.graphics.printf("No one is waiting.", panel.x + 12, 244, panel.width - 24, "left")
    end
    for _, row in ipairs(layout.pending) do
        love.graphics.setColor(0.91, 0.93, 0.90, 1)
        love.graphics.printf(row.name, panel.x + 12, row.bounds.y + 16, 248, "left")
        drawButton(row.approve, row.unmatched and 'CHOOSE' or 'APPROVE',
            isPressed('approve', row.requestId), false)
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
        if direct then
            drawButton(row.remove, confirming and "CONFIRM" or "REMOVE",
                isPressed("remove", row.playerId), true)
        end
    end

    if layout.invite then
        drawButton(layout.invite, "INVITE WORKER", isPressed("invite"), false)
    end

    love.graphics.setColor(0.61, 0.68, 0.67, 1)
    love.graphics.printf(layout.note, panel.x + 12, 550, panel.width - 24, "center")
end

return MultiplayerHud
