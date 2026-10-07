local Config = require("src.config")

local HighFiveUi = { hoveredTargetId = nil }

local CARD = {
    x = Config.baseWidth / 2 - 184,
    y = 22,
    width = 368,
    height = 110,
}

local ACCEPT = { x = CARD.x + 16, y = CARD.y + 70, width = 160, height = 28 }
local DECLINE = { x = CARD.x + 192, y = CARD.y + 70, width = 160, height = 28 }
local HIGH_FIVE_RANGE = 108

local function inside(rect, x, y)
    return x >= rect.x and y >= rect.y
        and x <= rect.x + rect.width and y <= rect.y + rect.height
end

local function distanceSquared(left, right)
    if not left or not right then return math.huge end
    local dx, dy = (tonumber(left.x) or 0) - (tonumber(right.x) or 0),
        (tonumber(left.y) or 0) - (tonumber(right.y) or 0)
    return dx * dx + dy * dy
end

local function targetAt(x, y, players)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local selected, selectedDistance
    for _, player in ipairs(players or {}) do
        if type(player) == "table" and type(player.x) == "number"
            and type(player.y) == "number"
        then
            local dx, dy = x - player.x, y - (player.y - 42)
            local metric = dx * dx / (34 * 34) + dy * dy / (49 * 49)
            if math.abs(dx) <= 34 and math.abs(dy) <= 49
                and (not selectedDistance or metric < selectedDistance)
            then
                selected, selectedDistance = player, metric
            end
        end
    end
    return selected
end

local function drawPanel(rect, fill, outline)
    love.graphics.setColor(fill[1], fill[2], fill[3], fill[4] or 1)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setColor(outline[1], outline[2], outline[3], outline[4] or 1)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setLineWidth(1)
end

local function drawButton(rect, label, primary)
    drawPanel(rect,
        primary and { 0.22, 0.43, 0.29, 1 } or { 0.17, 0.20, 0.21, 1 },
        primary and { 0.68, 0.81, 0.47, 1 } or { 0.44, 0.50, 0.48, 1 })
    love.graphics.setColor(0.96, 0.95, 0.85, 1)
    love.graphics.printf(label, rect.x, rect.y + 6, rect.width, "center")
end

function HighFiveUi.drawWorld(mouseX, mouseY, players, localPlayer, info)
    HighFiveUi.hoveredTargetId = nil
    if not info or not info.active then return end
    local target = targetAt(mouseX, mouseY, players)
    if not target then return end
    HighFiveUi.hoveredTargetId = tonumber(target.id)
    local nearby = distanceSquared(localPlayer, target)
        <= HIGH_FIVE_RANGE * HIGH_FIVE_RANGE
    local label = nearby and "G  HIGH FIVE" or "MOVE CLOSER"
    local width, height = 116, 25
    local x, y = target.x - width / 2, target.y - 105
    drawPanel({ x = x, y = y, width = width, height = height },
        nearby and { 0.08, 0.12, 0.12, 0.92 } or { 0.13, 0.13, 0.12, 0.9 },
        nearby and { 0.93, 0.76, 0.28, 1 } or { 0.54, 0.50, 0.38, 1 })
    love.graphics.setColor(nearby and { 0.99, 0.88, 0.48, 1 } or { 0.79, 0.76, 0.66, 1 })
    love.graphics.printf(label, x, y + 5, width, "center")
end

function HighFiveUi.draw(info)
    if not info or not info.active then return end
    local offer = info.offers and info.offers[1]
    if offer then
        drawPanel(CARD, { 0.055, 0.075, 0.074, 0.96 }, { 0.82, 0.69, 0.29, 1 })
        love.graphics.setColor(0.99, 0.84, 0.36, 1)
        love.graphics.printf("HIGH FIVE?", CARD.x + 12, CARD.y + 9, CARD.width - 24, "center")
        love.graphics.setColor(0.88, 0.91, 0.86, 1)
        love.graphics.printf(tostring(offer.initiatorName or "A player") .. " wants to high-five.",
            CARD.x + 12, CARD.y + 32, CARD.width - 24, "center")
        drawButton(ACCEPT, "ACCEPT", true)
        drawButton(DECLINE, "DECLINE", false)
        return
    end
    if info.notice then
        local width, height = 390, 34
        local rect = { x = Config.baseWidth / 2 - width / 2, y = 20,
            width = width, height = height }
        drawPanel(rect, { 0.055, 0.075, 0.074, 0.93 }, { 0.62, 0.58, 0.34, 1 })
        love.graphics.setColor(0.92, 0.91, 0.80, 1)
        love.graphics.printf(tostring(info.notice), rect.x + 8, rect.y + 9,
            rect.width - 16, "center")
    end
end

function HighFiveUi.mousepressed(screenX, screenY, worldX, worldY, button,
        info, players, localPlayer, multiplayer)
    if button ~= 1 or not info or not info.active then return false end
    local offer = info.offers and info.offers[1]
    if offer then
        if inside(CARD, screenX, screenY) then
            local accepted = inside(ACCEPT, screenX, screenY)
            local declined = inside(DECLINE, screenX, screenY)
            if accepted or declined then
                local ok, message = multiplayer:respondHighFive(offer.requestId, accepted)
                if ok then return true end
                return true, message
            end
            return true
        end
    end
    local target = targetAt(worldX, worldY, players)
    if not target then return false end
    local ok, message = multiplayer:requestHighFive(target.id)
    if ok then return true end
    return true, message
end

function HighFiveUi.keypressed(key, info, multiplayer)
    if (key ~= "g" and key ~= "G") or not info or not info.active
        or #((info.offers) or {}) > 0
    then
        return false
    end
    local targetId = HighFiveUi.hoveredTargetId
    if not targetId then return false end
    local ok, message = multiplayer:requestHighFive(targetId)
    if ok then return true end
    return true, message
end

return HighFiveUi
