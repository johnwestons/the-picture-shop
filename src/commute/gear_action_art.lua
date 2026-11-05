-- Loads reviewed southeast motorcycle dressing strips for the runtime or lab.
-- Runtime defaults only reference shipped assets. The lab passes its staged
-- registration explicitly when reviewing new artwork.
local Registration = require('assets.generated.commute-gear-actions-v1.registration')
local Colorways = require('src.rabbit_colorways')

local Art = {registration = Registration, REFERENCE_HEIGHT = Registration.referenceHeight or 256}
Art.__index = Art
local reverseActionForPose={helmet_off='helmet_on',unzip='zip_up',suit_off='suit_on'}

local SHADER = [[
#ifdef PIXEL
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
    if(pixel.a<0.02) discard;
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
#endif
]]
local DEPTH_VERTEX=[[
#ifdef VERTEX
extern float spriteDepth;
vec4 position(mat4 transform_projection,vec4 vertex_position) {
    vec4 clip=transform_projection*vertex_position;
    clip.z=spriteDepth*clip.w;
    return clip;
}
#endif
]]

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

function Art.supportsAppearance(appearance, registration)
    registration = registration or Registration
    return type(appearance) == 'table' and appearance.character == registration.character
end

function Art.frameForProgress(action, progress, registration)
    registration = registration or Registration
    local entry = registration.actions[action]
    if not entry or not finite(progress) then return nil end
    local p = math.max(0, math.min(.999999, progress))
    return math.floor(p * entry.frameCount) + 1
end

function Art.actionFrameForPose(pose, progress, registration)
    registration=registration or Registration
    local action=reverseActionForPose[pose] or pose
    local entry=registration.actions[action]
    if not entry then return nil,nil end
    local frame=Art.frameForProgress(action,progress,registration)
    if reverseActionForPose[pose] then frame=entry.frameCount+1-frame end
    return action,frame
end

function Art.normalization(action, registration)
    registration = registration or Registration
    local entry = registration.actions[action]
    if not entry or not finite(entry.normalizationHeight) or entry.normalizationHeight <= 0 then return nil end
    return (registration.referenceHeight or Art.REFERENCE_HEIGHT) / entry.normalizationHeight
end

function Art.new(options)
    assert(type(options) == 'table', 'gear action art requires an explicit runtime or review mode')
    local registration = options.registration or Registration
    if options.review == true then
        assert(registration.status == 'staged_unapproved', 'review loader requires staged gear action art')
    elseif options.runtime == true then
        assert(registration.status == 'runtime_approved', 'runtime loader requires approved gear action art')
    else
        error('gear action art requires an explicit runtime or review mode')
    end
    local rideRegistration=require('assets.generated.commute-ride-actions-v1.registration')
    assert(rideRegistration.status=='runtime_approved','ride-action loader requires approved art')
    local actions={}
    for name,entry in pairs(registration.actions) do actions[name]=entry end
    for name,entry in pairs(rideRegistration.actions) do actions[name]=entry end
    local combinedRegistration={}
    for key,value in pairs(registration) do combinedRegistration[key]=value end
    combinedRegistration.actions=actions
    local self = setmetatable({images = {}, masks = {}, quads = {}, actions = actions,
        registration = combinedRegistration}, Art)
    for name, entry in pairs(actions) do
        local image = love.graphics.newImage(entry.path)
        local mask = love.graphics.newImage(entry.maskPath)
        local frameSize=entry.frameSize or registration.frameSize
        assert(image:getWidth() == frameSize * entry.frameCount
            and image:getHeight() == frameSize, 'invalid gear action strip: ' .. name)
        assert(mask:getWidth() == image:getWidth() and mask:getHeight() == image:getHeight(),
            'gear color mask dimensions differ: ' .. name)
        image:setFilter('linear', 'linear')
        mask:setFilter('linear', 'linear')
        self.images[name], self.masks[name], self.quads[name] = image, mask, {}
        for frame = 1, entry.frameCount do
            self.quads[name][frame] = love.graphics.newQuad((frame - 1) * frameSize, 0,
                frameSize, frameSize, image:getWidth(), image:getHeight())
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

function Art:draw(action, frame, x, baseline, scale, appearance, depthShader, spriteDepth)
    if not Art.supportsAppearance(appearance, self.registration) then return false, 'unsupported_character' end
    local entry = self.actions[action]
    if not entry then return false, 'missing_staged_action' end
    if not finite(x) or not finite(baseline) or not finite(scale) or scale <= 0 then
        return false, 'invalid_draw_metrics'
    end
    frame = math.floor(tonumber(frame) or 1)
    frame = (frame - 1) % entry.frameCount + 1
    local fur, overalls = Colorways.normalize(appearance.furColorway, appearance.overallsColorway)
    local anchor=entry.anchor or self.registration.anchor
    local colored=fur~=1 or overalls~=1
    local target
    if colored and self.shader then
        target=self.shader
        if spriteDepth~=nil then
            if not self.depthShader then self.depthShader=love.graphics.newShader(DEPTH_VERTEX..SHADER) end
            target=self.depthShader
        end
    else target=depthShader end
    love.graphics.push('all')
    love.graphics.setColor(1, 1, 1, 1)
    if colored and self.shader then
        local furColor = Colorways.fur[fur].color
        local overallsColor = Colorways.overalls[overalls].color
        for _,shader in ipairs({self.shader,self.depthShader}) do
            if shader then
                shader:send('furTint',furColor);shader:send('overallsTint',overallsColor)
                shader:send('furEnabled',fur==1 and 0 or 1);shader:send('overallsEnabled',overalls==1 and 0 or 1)
                shader:send('actionMask',self.masks[action])
            end
        end
    end
    if spriteDepth~=nil and target==self.depthShader then target:send('spriteDepth',spriteDepth) end
    love.graphics.setShader(target)
    love.graphics.draw(self.images[action], self.quads[action][frame], x, baseline, 0,
        scale, scale, anchor[1], anchor[2])
    love.graphics.pop()
    return true
end

function Art:release()
    for _, image in pairs(self.images) do image:release() end
    for _, image in pairs(self.masks) do image:release() end
    for _, quads in pairs(self.quads) do for _, quad in ipairs(quads) do quad:release() end end
    if self.shader then self.shader:release() end
    if self.depthShader then self.depthShader:release() end
    self.images, self.masks, self.quads = {}, {}, {}
end

return Art
