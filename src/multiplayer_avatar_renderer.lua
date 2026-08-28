local CharacterAnimation = require("src.character_animation")
local Config = require("src.config")

local Renderer = {}

local function drawLabel(player)
    local label = tostring(player.name or player.id or "Worker")
    if #label > 22 then label = label:sub(1, 22) end
    local font = love.graphics.getFont()
    local width = math.max(54, font:getWidth(label) + 12)
    local x, y = player.x - width / 2, player.y - 79
    love.graphics.setColor(0.025, 0.035, 0.04, 0.86)
    love.graphics.rectangle("fill", x, y, width, 17, 3, 3)
    love.graphics.setColor(0.95, 0.82, 0.26, 1)
    love.graphics.printf(label, x, y + 2, width, "center")
end

local function drawPlayer(characterAssets, player)
    local character = Config.characters[player.character] and player.character or Config.player.character
    local action = player.moving and "walk" or "idle"
    local directionScale = player.facing or 1
    if player.moving then
        local directionalAction, mirror = CharacterAnimation.directionalWalkAction(
            player.velocityX or player.intentX, player.velocityY or player.intentY)
        if characterAssets.hasAction(character, directionalAction) then action = directionalAction end
        directionScale = mirror
    else
        local directionalAction, mirror = CharacterAnimation.directionalIdleAction(
            player.intentX, player.intentY)
        if characterAssets.hasAction(character, directionalAction) then action = directionalAction end
        directionScale = mirror
    end

    local image, _, frameCount = characterAssets.get(character, action, 1)
    frameCount = frameCount or 1
    local frame = CharacterAnimation.frameForPlayerAction(action, frameCount,
        player.animationDistance or 0, player.idleClock or 0, Config.player.walkPixelsPerFrame,
        Config.player.idleAnimationRate)
    local quad
    image, quad = characterAssets.get(character, action, frame)
    if image and quad then
        local anchorX, anchorY = characterAssets.getAnchor(character, action, frame)
        local scale = Config.player.drawScale * characterAssets.getNormalization(character, action)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, quad, player.x, player.y, 0,
            scale * directionScale, scale, anchorX, anchorY)
    else
        love.graphics.setColor(0.25, 0.62, 0.72, 1)
        love.graphics.rectangle("fill", player.x - 10, player.y - 42, 20, 38)
    end
    drawLabel(player)
end

function Renderer.draw(characterAssets, players)
    if type(players) ~= "table" then return end
    local ordered = {}
    for _, player in pairs(players) do
        if type(player) == "table" and type(player.x) == "number" and type(player.y) == "number" then
            ordered[#ordered + 1] = player
        end
    end
    table.sort(ordered, function(a, b)
        if a.y == b.y then return tostring(a.id) < tostring(b.id) end
        return a.y < b.y
    end)
    for _, player in ipairs(ordered) do drawPlayer(characterAssets, player) end
end

return Renderer
