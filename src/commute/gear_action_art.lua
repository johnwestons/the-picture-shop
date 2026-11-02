-- Review-only loader for the southeast motorcycle dressing strips.
-- These drawings are rabbit-specific and remain staged until removal and
-- directional coverage exist. No commute renderer calls this module yet.
local Registration = require('assets.staging.commute-gear-actions-v1.registration')
local Colorways = require('src.rabbit_colorways')

local Art = {
    registration = Registration,
    REFERENCE_HEIGHT = Registration.referenceHeight or 256,
}
Art.__index = Art

local SHADER = [[
extern vec3 furTint;
extern vec3 overallsTint;
extern float furEnabled;
extern float overallsEnabled;
extern Image actionMask;

vec3 rgbToHsv(vec3 c) {
    vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsvToRgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec4 pixel = Texel(texture, texture_coords) * color;
    vec2 masks = Texel(actionMask, texture_coords).rg;
    vec3 hsv = rgbToHsv(pixel.rgb);
    if (furEnabled > 0.5 && masks.r > 0.0) {
        vec3 tint = rgbToHsv(furTint);
        vec3 recolored = vec3(tint.x, hsv.y * tint.y / 0.82, hsv.z * tint.z / 0.88);
        pixel.rgb = mix(pixel.rgb, hsvToRgb(recolored), masks.r);
        hsv = rgbToHsv(pixel.rgb);
    }
    if (overallsEnabled > 0.5 && masks.g > 0.0) {
        vec3 tint = rgbToHsv(overallsTint);
        vec3 recolored = vec3(tint.x, hsv.y * tint.y / 0.88, hsv.z * tint.z / 0.88);
        pixel.rgb = mix(pixel.rgb, hsvToRgb(recolored), masks.g);
    }
    return pixel;
}
]]

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

function Art.supportsAppearance(appearance)
    return type(appearance) == 'table' and appearance.character == Registration.character
end

function Art.frameForProgress(action, progress)
    local entry = Registration.actions[action]
    if not entry or not finite(progress) then return nil end
    local p = math.max(0, math.min(.999999, progress))
    return math.floor(p * entry.frameCount) + 1
end

function Art.normalization(action)
    local entry = Registration.actions[action]
    if not entry or not finite(entry.normalizationHeight) or entry.normalizationHeight <= 0 then return nil end
    return Art.REFERENCE_HEIGHT / entry.normalizationHeight
end

function Art.new(options)
    assert(type(options) == 'table' and options.review == true,
        'staged motorcycle action art can only be loaded by an explicit review')
    assert(Registration.status == 'staged_unapproved', 'motorcycle action art is not approved for runtime use')
    local self = setmetatable({images = {}, masks = {}, quads = {}, actions = Registration.actions}, Art)
    for name, entry in pairs(Registration.actions) do
        local image = love.graphics.newImage(entry.path)
        local mask = love.graphics.newImage(entry.maskPath)
        assert(image:getWidth() == Registration.frameSize * entry.frameCount
            and image:getHeight() == Registration.frameSize, 'invalid staged gear action strip: ' .. name)
        assert(mask:getWidth() == image:getWidth() and mask:getHeight() == image:getHeight(),
            'gear color mask dimensions differ: ' .. name)
        image:setFilter('linear', 'linear')
        mask:setFilter('linear', 'linear')
        self.images[name], self.masks[name], self.quads[name] = image, mask, {}
        for frame = 1, entry.frameCount do
            self.quads[name][frame] = love.graphics.newQuad((frame - 1) * Registration.frameSize, 0,
                Registration.frameSize, Registration.frameSize, image:getWidth(), image:getHeight())
        end
    end
    local ok, shader = pcall(love.graphics.newShader, SHADER)
    assert(ok and shader, 'scoped gear-action colorway shader failed: ' .. tostring(shader))
    self.shader = shader
    return self
end

function Art:has(action)
    return self.actions[action] ~= nil
end

function Art:draw(action, frame, x, baseline, scale, appearance)
    if not Art.supportsAppearance(appearance) then return false, 'unsupported_character' end
    local entry = self.actions[action]
    if not entry then return false, 'missing_staged_action' end
    if not finite(x) or not finite(baseline) or not finite(scale) or scale <= 0 then
        return false, 'invalid_draw_metrics'
    end
    frame = math.floor(tonumber(frame) or 1)
    frame = (frame - 1) % entry.frameCount + 1
    local fur, overalls = Colorways.normalize(appearance.furColorway, appearance.overallsColorway)
    love.graphics.push('all')
    love.graphics.setColor(1, 1, 1, 1)
    if self.shader and (fur ~= 1 or overalls ~= 1) then
        local furColor = Colorways.fur[fur].color
        local overallsColor = Colorways.overalls[overalls].color
        self.shader:send('furTint', furColor)
        self.shader:send('overallsTint', overallsColor)
        self.shader:send('furEnabled', fur == 1 and 0 or 1)
        self.shader:send('overallsEnabled', overalls == 1 and 0 or 1)
        self.shader:send('actionMask', self.masks[action])
        love.graphics.setShader(self.shader)
    else
        love.graphics.setShader()
    end
    love.graphics.draw(self.images[action], self.quads[action][frame], x, baseline, 0,
        scale, scale, Registration.anchor[1], Registration.anchor[2])
    love.graphics.pop()
    return true
end

function Art:release()
    for _, image in pairs(self.images) do image:release() end
    for _, image in pairs(self.masks) do image:release() end
    for _, quads in pairs(self.quads) do for _, quad in ipairs(quads) do quad:release() end end
    if self.shader then self.shader:release() end
    self.images, self.masks, self.quads = {}, {}, {}
end

return Art
