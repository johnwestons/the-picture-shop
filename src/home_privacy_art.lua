-- Privacy presentation for bathroom activities. Bathing and toilet mechanics
-- remain owned by the resident/chore systems; this module only obscures the
-- active character sprite while the shared activity is running.
local Animation = require("src.character_animation")
local Colorways = require("src.rabbit_colorways")
local Config = require("src.config")

local Privacy = {}
local shader

local SHADER_SOURCE = Colorways.blendShaderSource() .. [[
extern vec2 uvMin;
extern vec2 uvMax;
extern vec2 pixelStep;
extern float privacyAlpha;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec4 source = Texel(texture, texture_coords) * color;
    if (source.a < 0.08) discard;

    vec2 bounded = clamp(texture_coords, uvMin, uvMax);
    vec2 cell = floor((bounded - uvMin) / pixelStep);
    vec2 sampleUv = uvMin + (cell + vec2(0.5, 0.5)) * pixelStep;
    sampleUv = clamp(sampleUv, uvMin, uvMax);
    vec4 block = applyRabbitColorways(Texel(texture, sampleUv) * color);

    // Reduce the sampled color to broad blocks and pull it toward a neutral
    // privacy tone. The original alpha preserves the character silhouette but
    // removes readable facial, clothing, and action detail.
    vec3 mosaic = floor(block.rgb * 5.0 + vec3(0.5, 0.5, 0.5)) / 5.0;
    mosaic = mix(mosaic, vec3(0.18, 0.22, 0.28), 0.55);
    return vec4(mosaic, source.a * privacyAlpha);
}
]]

local function getShader()
    if not shader then shader = love.graphics.newShader(SHADER_SOURCE) end
    return shader
end

local function directionVector(direction)
    local vectors = {
        east={1,0}, southeast={1,1}, south={0,1}, southwest={-1,1},
        west={-1,0}, northwest={-1,-1}, north={0,-1}, northeast={1,-1},
    }
    local v = vectors[direction] or vectors.south
    return v[1], v[2]
end

function Privacy.draw(pose, player, characters)
    local character = Config.characters[player.character] and player.character or Config.player.character
    local dx, dy = directionVector(pose.direction)
    local action, mirror = Animation.directionalIdleAction(dx, dy)
    if characters.resolveAction then action = characters.resolveAction(character, action) end
    local image, quad, frameCount = characters.get(character, action, 1)
    if not image or not quad then
        -- Keep the privacy contract even if an optional character asset is
        -- unavailable. A neutral pixel block is preferable to an uncovered
        -- bathroom action.
        love.graphics.push("all")
        love.graphics.setColor(0.18, 0.22, 0.28, 0.92)
        for row=0,5 do
            for column=0,3 do
                if (row + column) % 2 == 0 then
                    love.graphics.rectangle("fill", pose.x - 18 + column * 10,
                        pose.y - 58 + row * 10, 10, 10)
                end
            end
        end
        love.graphics.pop()
        return true
    end

    local frame = Animation.frameForIdle(frameCount or 1, pose.seconds or 0, 1.2)
    image, quad = characters.get(character, action, frame)
    local anchorX, anchorY = characters.getAnchor(character, action, frame)
    local scale = Config.player.drawScale * characters.getNormalization(character, action)
    local qx, qy, qw, qh = quad:getViewport()
    local imageWidth, imageHeight = image:getDimensions()
    local activeShader = getShader()
    activeShader:send("uvMin", {qx / imageWidth, qy / imageHeight})
    activeShader:send("uvMax", {(qx + qw) / imageWidth, (qy + qh) / imageHeight})
    activeShader:send("pixelStep", {24 / imageWidth, 24 / imageHeight})
    activeShader:send("privacyAlpha", 0.98)
    Colorways.configureShader(activeShader, player.furColorway, player.overallsColorway)

    love.graphics.push("all")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(activeShader)
    love.graphics.draw(image, quad, pose.x, pose.y, 0, scale * mirror, scale,
        anchorX, anchorY)
    love.graphics.pop()
    return true
end

function Privacy.release()
    if shader then shader:release(); shader = nil end
end

return Privacy
