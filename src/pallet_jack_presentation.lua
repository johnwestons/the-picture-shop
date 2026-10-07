local Config = require("src.config")
local PalletJack = require("src.pallet_jack")
local Animation = require("src.character_animation")
local Blend = require("src.sprite_blend")
local Art = require("src.pallet_jack_art")
local Presentation = {}

local views = {
    {"push", 1}, {"push_southeast", 1}, {"push_south", 1}, {"push_southeast", -1},
    {"push", -1}, {"push_northeast", -1}, {"push_north", 1}, {"push_northeast", 1},
}

function Presentation.workerPoses(characters, player, state)
    local pose = PalletJack.visualPose(state, Config.palletJack)
    local phase = (pose.heading % (2 * math.pi)) / (2 * math.pi) * 8 + .5
    local view = math.floor(phase) % 8 + 1
    local character = player.character or Config.player.character
    local poses = {}
    for index, amount in ipairs({1}) do
        local direction = views[(view + index - 2) % 8 + 1]
        local action, mirror = direction[1], direction[2]
        if not state.palletJack.moving then action = action .. "_idle" end
        if not characters.hasAction(character, action) then return nil end
        local _, _, count = characters.get(character, action, 1)
        local gait = pose.distance / Config.palletJack.gaitPixelsPerFrame * (count / 8)
        local frame = state.palletJack.moving and math.floor(gait) % count + 1
            or Animation.frameForIdle(count, state.palletJack.animationClock, .65)
        local nextFrame = state.palletJack.moving and frame % count + 1 or frame
        local gaitBlend = state.palletJack.moving and gait - math.floor(gait) or 0
        for part, weight in ipairs({1 - gaitBlend, gaitBlend}) do
            local f = part == 1 and frame or nextFrame
            local image, quad = characters.get(character, action, f)
            local hands = Art.hands[action][f]
            local scale = Config.player.drawScale * characters.getNormalization(character, action)
            poses[#poses + 1] = {image = image, quad = quad,
                anchorX = hands.x, anchorY = hands.y,
                scaleX = scale * mirror, scaleY = scale, weight = amount * weight}
        end
    end
    poses[1].furColorway = player.furColorway
    poses[1].overallsColorway = player.overallsColorway
    return poses, pose
end

function Presentation.drawWorker(characters, player, state)
    local poses, pose = Presentation.workerPoses(characters, player, state)
    if not poses then return false end
    love.graphics.setColor(.03, .04, .05, .24)
    love.graphics.ellipse("fill", pose.x + pose.operatorX, pose.y + pose.operatorY + 1, 13, 5)
    love.graphics.setColor(1, 1, 1)
    return Blend.draw(poses, pose.x + pose.handleX, pose.y + pose.handleY)
end

function Presentation.drawJack(assets, state)
    local pose = PalletJack.visualPose(state, Config.palletJack)
    local image = assets.get("palletJack")
    local frame = pose.blend < .5 and pose.frame or pose.nextFrame
    local a = assets.getQuad("palletJack" .. frame)
    if not image or not a then return false end
    local scale = Config.palletJack.drawScale * (Config.palletJack.resolutionScale or 1)
    love.graphics.setColor(1, 1, 1)
    -- Thirty-two real turn drawings avoid transparent double-fork silhouettes.
    -- Render each grip at the continuous attachment point, so selecting the
    -- nearest authored view cannot make the worker's hands jump off the bar.
    local authored = Art.frames[frame]
    love.graphics.draw(image, a.quad, pose.x + pose.handleX, pose.y + pose.handleY, 0,
        scale, scale, Art.originX + authored.handleX, Art.originY + authored.handleY)
    return true
end

return Presentation
