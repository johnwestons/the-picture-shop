-- Blend authored poses with premultiplied color, so transparent edges do not
-- darken and extra frames never appear as two translucent outlines.
local Blend = {}
local Colorways = require("src.rabbit_colorways")
local shader
local paddedQuads = setmetatable({}, {__mode = "k"})
local source = [[
extern Image imageB;
extern Image imageC;
extern Image imageD;
extern vec4 rectA;
extern vec4 rectB;
extern vec4 rectC;
extern vec4 rectD;
extern vec2 anchorA;
extern vec2 anchorB;
extern vec2 anchorC;
extern vec2 anchorD;
extern vec2 ratioB;
extern vec2 ratioC;
extern vec2 ratioD;
extern vec4 weights;
vec4 samplePose(Image img, vec2 p, vec4 rect) {
    if (p.x < 0.0 || p.y < 0.0 || p.x >= 1.0 || p.y >= 1.0) return vec4(0.0);
    vec4 value = Texel(img, rect.xy + p * rect.zw);
    return vec4(value.rgb * value.a, value.a);
}
vec4 effect(vec4 color, Image imageA, vec2 tc, vec2 screen) {
    vec2 p = (tc - rectA.xy) / rectA.zw;
    vec2 localPoint = p - anchorA;
    vec4 a = samplePose(imageA, p, rectA);
    vec4 b = samplePose(imageB, localPoint * ratioB + anchorB, rectB);
    vec4 c = samplePose(imageC, localPoint * ratioC + anchorC, rectC);
    vec4 d = samplePose(imageD, localPoint * ratioD + anchorD, rectD);
    vec4 result = a * weights.x + b * weights.y + c * weights.z + d * weights.w;
    return applyRabbitColorways(vec4(result.a > 0.00001 ? result.rgb / result.a : vec3(0.0), result.a) * color);
}
]]

function Blend.draw(poses, x, y)
    local a = poses[1]
    if not a or not a.image or not a.quad then return false end
    shader = shader or love.graphics.newShader(Colorways.blendShaderSource() .. source)
    local previous = love.graphics.getShader()
    local function rect(p)
        local qx, qy, qw, qh = p.quad:getViewport()
        local iw, ih = p.image:getDimensions()
        return {qx / iw, qy / ih, qw / iw, qh / ih}, qw, qh
    end
    local r, width, height = rect(a)
    shader:send("rectA", r)
    shader:send("anchorA", {a.anchorX / width, a.anchorY / height})
    local weights = {a.weight or 1, 0, 0, 0}
    for i, letter in ipairs({"B", "C", "D"}) do
        local p = poses[i + 1] or a
        local target, tw, th = rect(p)
        shader:send("image" .. letter, p.image)
        shader:send("rect" .. letter, target)
        shader:send("anchor" .. letter, {p.anchorX / tw, p.anchorY / th})
        shader:send("ratio" .. letter,
            {width * a.scaleX / (tw * p.scaleX), height * a.scaleY / (th * p.scaleY)})
        weights[i + 1] = poses[i + 1] and (p.weight or 0) or 0
    end
    shader:send("weights", weights)
    Colorways.configureShader(shader, a.furColorway, a.overallsColorway)
    love.graphics.setShader(shader)
    -- Neighboring camera views can extend beyond the first view's bounds.
    -- A larger drawing quad prevents clipping; samplePose still masks every
    -- texture lookup to its own actual cell, including mirrored poses.
    local padded = paddedQuads[a.quad]
    if not padded then
        local qx, qy = a.quad:getViewport()
        local iw, ih = a.image:getDimensions()
        padded = love.graphics.newQuad(qx - width / 2, qy - height / 2,
            width * 2, height * 2, iw, ih)
        paddedQuads[a.quad] = padded
    end
    love.graphics.draw(a.image, padded, x, y, 0,
        a.scaleX, a.scaleY, a.anchorX + width / 2, a.anchorY + height / 2)
    love.graphics.setShader(previous)
    return true
end

return Blend
