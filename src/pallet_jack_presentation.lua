local Config = require("src.config")
local PalletJack = require("src.pallet_jack")
local Animation = require("src.character_animation")
local Blend = require("src.sprite_blend")
local Art = require("src.pallet_jack_art")
local MotionPose = require("src.pallet_jack_pose")
local Presentation = {}

local views = {
    {"push", 1}, {"push_southeast", 1}, {"push_south", 1}, {"push_southeast", -1},
    {"push", -1}, {"push_northeast", -1}, {"push_north", 1}, {"push_northeast", 1},
}

function Presentation.workerPoses(characters, player, state)
    local pose = PalletJack.visualPose(state, Config.palletJack)
    -- Select the same camera on either side of the wire's angle quantization,
    -- including exact sector boundaries during turns.
    local phase = MotionPose.headingForRender(pose.heading) / (2 * math.pi) * 8 + .5
    local view = math.floor(phase) % 8 + 1
    local character = player.character or Config.player.character
    local direction = views[view]
    local action, mirror = direction[1], direction[2]
    if not state.palletJack.moving then action = action .. "_idle" end
    if not characters.hasAction(character, action) then return nil end
    local _, _, count = characters.get(character, action, 1)
    local frame = state.palletJack.moving and Animation.frameForGait(count,pose.distance,Config.palletJack.gaitPixelsPerFrame)
        or Animation.frameForIdle(count, state.palletJack.animationClock, .65)
    -- Sixteen authored drawings already supply the intermediate poses.
    -- Cross-fading different boot silhouettes makes translucent feet.
    local image, quad = characters.get(character, action, frame)
    local hands = Art.hands[action][frame]
    local scale = Config.player.drawScale * characters.getNormalization(character, action)
    local poses={{image=image,quad=quad,anchorX=hands.x,anchorY=hands.y,
        scaleX=scale*mirror,scaleY=scale,weight=1,
        furColorway=player.furColorway,overallsColorway=player.overallsColorway}}
    return poses, pose
end

function Presentation.drawWorker(characters, player, state)
    local poses, pose = Presentation.workerPoses(characters, player, state)
    if not poses then return false end
    love.graphics.setColor(1, 1, 1)
    return Blend.draw(poses, pose.x + pose.handleX, pose.y + pose.handleY)
end

function Presentation.drawJack(assets, state)
    local pose = PalletJack.visualPose(state, Config.palletJack)
    local image = assets.get("palletJack")
    local frame=math.floor(MotionPose.headingForRender(pose.heading)/(2*math.pi)*#Art.frames+.5)%#Art.frames+1
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
