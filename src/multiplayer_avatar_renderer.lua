local CharacterAnimation = require("src.character_animation")
local Config = require("src.config")
local RabbitColorways = require("src.rabbit_colorways")
local JackPresentation = require("src.pallet_jack_presentation")

local Renderer = {}

local pushFacing = {
    northwest = {-1,-1}, north = {0,-1}, northeast = {1,-1}, east = {1,0},
    southeast = {1,1}, south = {0,1}, southwest = {-1,1}, west = {-1,0},
}

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

local function drawPlayer(characterAssets,player,state)
    local character = Config.characters[player.character] and player.character or Config.player.character
    local highFive = player.highFiveAnimation
    local highFiveActive = highFive and characterAssets.hasAction(character, "high_five")
    local resting=player.resting and characterAssets.hasAction(character,"sit")
    local jack=state and state.palletJack
    local pushingJack=jack and jack.operating
        and jack.operatorPlayerId==tonumber(player.id)
        and not highFiveActive
    if pushingJack and JackPresentation.drawWorker(characterAssets, player, state) then
        drawLabel(player)
        return
    end
    local action = resting and "sit" or player.moving and "walk" or "idle"
    local directionScale = player.facing or 1
    local pushArtwork=false
    if player.moving and not resting then
        local directionalAction,mirror=CharacterAnimation.directionalWalkAction(
            player.velocityX or player.intentX,player.velocityY or player.intentY)
        if characterAssets.hasAction(character, directionalAction) then action = directionalAction end
        directionScale = mirror
    end
    if pushingJack then
        local facing=pushFacing[jack.direction] or pushFacing.northwest
        local directionalAction, mirror = CharacterAnimation.directionalPalletJackPushAction(
            facing[1],facing[2])
        if characterAssets.hasAction(character,directionalAction) then
            action=directionalAction
            directionScale=mirror
            pushArtwork=true
        elseif jack.moving then
            action,directionScale=CharacterAnimation.directionalWalkAction(facing[1],facing[2])
        else
            action,directionScale=CharacterAnimation.directionalIdleAction(facing[1],facing[2])
        end
    elseif resting then
        directionScale=player.facing or 1
    elseif not player.moving then
        local directionalAction, mirror = CharacterAnimation.directionalIdleAction(
            player.intentX, player.intentY)
        if characterAssets.hasAction(character, directionalAction) then action = directionalAction end
        directionScale = mirror
    end

    if highFiveActive then
        action = "high_five"
        pushArtwork = false
        local partnerX = tonumber(highFive.partnerX)
        directionScale = partnerX and math.abs(partnerX - player.x) > 0.01
            and (partnerX < player.x and -1 or 1)
            or (tonumber(highFive.partnerId) or 0) < (tonumber(player.id) or 0) and -1 or 1
    end

    local image, _, frameCount = characterAssets.get(character, action, 1)
    frameCount = frameCount or 1
    local frame
    if highFiveActive then
        frame = CharacterAnimation.frameForHighFive(frameCount,
            highFive.elapsed, highFive.duration)
    elseif pushingJack and pushArtwork then
        frame=CharacterAnimation.frameForPalletJackPush(frameCount,jack.moving,
            player.animationDistance or 0,Config.player.walkPixelsPerFrame)
    else
        frame = CharacterAnimation.frameForPlayerAction(action, frameCount,
            player.animationDistance or 0, player.idleClock or 0, Config.player.walkPixelsPerFrame,
            Config.player.idleAnimationRate)
    end
    local quad
    image, quad = characterAssets.get(character, action, frame)
    if image and quad then
        local anchorX, anchorY = characterAssets.getAnchor(character, action, frame)
        local scale = Config.player.drawScale * characterAssets.getNormalization(character, action)
        love.graphics.setColor(1, 1, 1)
        if character == "rabbit-worker" then
            RabbitColorways.draw(image, quad, player.x, player.y, 0,
                scale * directionScale, scale, anchorX, anchorY, 0, 0,
                player.furColorway, player.overallsColorway)
        else
            love.graphics.draw(image, quad, player.x, player.y, 0,
                scale * directionScale, scale, anchorX, anchorY)
        end
    else
        love.graphics.setColor(0.25, 0.62, 0.72, 1)
        love.graphics.rectangle("fill", player.x - 10, player.y - 42, 20, 38)
    end
    drawLabel(player)
end

function Renderer.draw(characterAssets,players,state)
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
    for _, player in ipairs(ordered) do drawPlayer(characterAssets,player,state) end
end

return Renderer
