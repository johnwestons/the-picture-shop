local InteractionBeacon = {}

InteractionBeacon.VERSION = 1

local DEFAULT_PALETTE = {
    deep = { 0.48, 0.24, 0.05 },
    base = { 1.00, 0.88, 0.34 },
    highlight = { 1.00, 0.98, 0.78 },
    outline = { 0.10, 0.07, 0.02 },
}

local activationTarget
local activationTime = -math.huge

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function smoothstep(value)
    value = clamp(value, 0, 1)
    return value * value * (3 - 2 * value)
end

local function targetOf(selected)
    return selected and (selected.target or selected) or nil
end

local function now()
    return love.timer and love.timer.getTime and love.timer.getTime() or 0
end

local function paletteFor(selected, options)
    local target = targetOf(selected)
    return (target and target.beaconPalette)
        or (selected and selected.beaconPalette)
        or (options and options.palette)
        or DEFAULT_PALETTE
end

local function snap(value, options)
    if options and options.pixelSnap == false then
        return value
    end
    return math.floor(value + 0.5)
end

local function distanceFor(selected, target, options)
    if type(selected.playerDistance) == "number" then
        return selected.playerDistance
    end
    local player = options and options.player
    if player and type(player.x) == "number" and type(player.y) == "number" then
        local dx, dy = target.x - player.x, target.y - player.y
        return math.sqrt(dx * dx + dy * dy)
    end
    return 0
end

function InteractionBeacon.isVisible(selected)
    local target = targetOf(selected)
    return target ~= nil
        and type(target.x) == "number"
        and type(target.y) == "number"
        and selected.available ~= false
        and target.available ~= false
        and target.disabled ~= true
        and target.hidden ~= true
        and target.beacon ~= false
end

function InteractionBeacon.closeness(selected, options)
    if not InteractionBeacon.isVisible(selected) then
        return 0
    end
    local target = targetOf(selected)
    local radius = selected.releaseRadius
        or selected.radius
        or target.interactionRadius
        or target.radius
        or (options and options.radius)
        or 64
    return smoothstep(1 - distanceFor(selected, target, options) / math.max(radius, 1))
end

function InteractionBeacon.colorFor(selected, options)
    local palette = paletteFor(selected, options)
    local amount = InteractionBeacon.closeness(selected, options)
    local deep, base = palette.deep, palette.base
    return {
        deep[1] + (base[1] - deep[1]) * amount,
        deep[2] + (base[2] - deep[2]) * amount,
        deep[3] + (base[3] - deep[3]) * amount,
    }, amount, palette
end

function InteractionBeacon.notifyActivated(selected)
    activationTarget = targetOf(selected)
    activationTime = now()
end

local function activationAmount(target, reducedMotion)
    if reducedMotion or target ~= activationTarget then
        return 0
    end
    return clamp(1 - (now() - activationTime) / 0.18, 0, 1)
end

local function drawDiamond(mode, x, y, size)
    love.graphics.polygon(mode, x, y - size, x + size, y, x, y + size, x - size, y)
end

function InteractionBeacon.drawUnderlay(selected, clock, options)
    options = options or {}
    if not InteractionBeacon.isVisible(selected) then
        return
    end

    local target = targetOf(selected)
    local color, close, palette = InteractionBeacon.colorFor(selected, options)
    local reducedMotion = options.reducedMotion == true
    local highContrast = options.highContrast == true
    local hovered = selected.hovered == true
    local pulse = reducedMotion and 0 or math.sin((clock or 0) * 4.2) * 0.8
    local activation = activationAmount(target, reducedMotion)
    local scale = 0.90 + close * 0.10 + (hovered and 0.08 or 0) + activation * 0.10
    local radius = (target.beaconRadius or 15) * scale + pulse
    local x = snap(target.x + (target.beaconOffsetX or 0), options)
    local y = snap(target.y + (target.beaconGroundOffset or 8), options)
    local oldWidth = love.graphics.getLineWidth()

    love.graphics.setColor(palette.outline[1], palette.outline[2], palette.outline[3], highContrast and 0.92 or 0.68)
    love.graphics.setLineWidth(highContrast and 4 or 3)
    love.graphics.ellipse("line", x, y, radius + 2, radius * 0.43 + 1)

    love.graphics.setColor(color[1], color[2], color[3], 0.08 + close * 0.10)
    love.graphics.ellipse("fill", x, y, radius, radius * 0.43)
    love.graphics.setColor(color[1], color[2], color[3], 0.62 + close * 0.28)
    love.graphics.setLineWidth(highContrast and 2.5 or 1.5)
    love.graphics.ellipse("line", x, y, radius, radius * 0.43)
    love.graphics.setLineWidth(oldWidth)
    love.graphics.setColor(1, 1, 1, 1)
end

function InteractionBeacon.drawOverlay(selected, clock, options)
    options = options or {}
    if not InteractionBeacon.isVisible(selected) then
        return
    end

    local target = targetOf(selected)
    local color, close, palette = InteractionBeacon.colorFor(selected, options)
    local reducedMotion = options.reducedMotion == true
    local highContrast = options.highContrast == true
    local hovered = selected.hovered == true
    local bob = reducedMotion and 0 or math.sin((clock or 0) * 3.8) * (1.2 + close * 0.8)
    local activation = activationAmount(target, reducedMotion)
    local size = (target.beaconSize or 5) * (0.92 + close * 0.08 + (hovered and 0.12 or 0) + activation * 0.18)
    local x = snap(target.x + (target.beaconOffsetX or 0), options)
    local y = snap(target.y - (target.beaconHeight or 29) + bob, options)
    local oldWidth = love.graphics.getLineWidth()

    love.graphics.setColor(palette.outline[1], palette.outline[2], palette.outline[3], highContrast and 0.95 or 0.78)
    love.graphics.setLineWidth(highContrast and 3 or 2)
    love.graphics.line(x, y + size + 2, x, target.y - 7)
    drawDiamond("fill", x, y, size + (highContrast and 2.5 or 1.5))

    love.graphics.setColor(color[1], color[2], color[3], 0.82 + close * 0.18)
    drawDiamond("fill", x, y, size)
    love.graphics.setColor(palette.highlight[1], palette.highlight[2], palette.highlight[3], 0.72 + activation * 0.28)
    love.graphics.setLineWidth(1)
    love.graphics.line(x, y - size + 1, x - size + 1, y)
    love.graphics.setLineWidth(oldWidth)
    love.graphics.setColor(1, 1, 1, 1)
end

function InteractionBeacon.formatPrompt(prompt, mode)
    if not prompt or prompt == "" then
        return nil
    end
    local action = tostring(prompt)
        :gsub("^%s*%[[EeQqAa]%]%s*", "")
        :gsub("^%s*[EeQqAa]%s*[:%-]%s*", "")
    if mode == "touch" or mode == "mobile" then
        return "TAP  " .. action
    elseif mode == "controller" then
        return "A  " .. action
    elseif mode == "mouse" then
        return "CLICK / E  " .. action
    end
    return "E  " .. action
end

return InteractionBeacon
