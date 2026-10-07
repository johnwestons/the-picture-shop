local Colorways = {}

Colorways.fur = {
    { name = "Ginger", color = { 0.88, 0.34, 0.08 } },
    { name = "Cream", color = { 0.96, 0.78, 0.52 } },
    { name = "Cocoa", color = { 0.48, 0.25, 0.12 } },
    { name = "Silver", color = { 0.55, 0.58, 0.62 } },
    { name = "Snow", color = { 0.91, 0.89, 0.84 } },
    { name = "Charcoal", color = { 0.25, 0.27, 0.30 } },
}

Colorways.overalls = {
    { name = "Blue", color = { 0.10, 0.43, 0.86 } },
    { name = "Red", color = { 0.79, 0.22, 0.25 } },
    { name = "Green", color = { 0.16, 0.58, 0.31 } },
    { name = "Purple", color = { 0.53, 0.29, 0.75 } },
    { name = "Gold", color = { 0.88, 0.58, 0.12 } },
    { name = "Slate", color = { 0.31, 0.36, 0.43 } },
}

local shader
local shaderFailed = false
local SHADER_SOURCE = [[
extern vec3 furTint;
extern vec3 overallsTint;
extern float furEnabled;
extern float overallsEnabled;

vec3 rgbToHsv(vec3 c) {
    vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)),
        d / (q.x + e), q.x);
}

vec3 hsvToRgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

float hueDistance(float a, float b) {
    float distance = abs(a - b);
    return min(distance, 1.0 - distance);
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec4 pixel = Texel(texture, texture_coords) * color;
    vec3 hsv = rgbToHsv(pixel.rgb);

    float furMask = furEnabled
        * (1.0 - smoothstep(0.035, 0.090, hueDistance(hsv.x, 0.070)))
        * smoothstep(0.34, 0.52, hsv.y)
        * smoothstep(0.38, 0.55, hsv.z);
    if (furMask > 0.0) {
        vec3 tint = rgbToHsv(furTint);
        vec3 recolored = vec3(tint.x, hsv.y * tint.y / 0.82,
            hsv.z * tint.z / 0.88);
        pixel.rgb = mix(pixel.rgb, hsvToRgb(recolored), furMask);
    }

    float overallsMask = overallsEnabled
        * (1.0 - smoothstep(0.045, 0.120, hueDistance(hsv.x, 0.585)))
        * smoothstep(0.22, 0.42, hsv.y)
        * smoothstep(0.10, 0.22, hsv.z);
    if (overallsMask > 0.0) {
        vec3 tint = rgbToHsv(overallsTint);
        vec3 recolored = vec3(tint.x, hsv.y * tint.y / 0.88,
            hsv.z * tint.z / 0.88);
        pixel.rgb = mix(pixel.rgb, hsvToRgb(recolored), overallsMask);
    }
    return pixel;
}
]]

local function index(value, choices)
    value = tonumber(value)
    if not value or value ~= value then return 1 end
    return math.max(1, math.min(#choices, math.floor(value)))
end

function Colorways.normalize(fur, overalls)
    return index(fur, Colorways.fur), index(overalls, Colorways.overalls)
end

function Colorways.count(group)
    return #(Colorways[group] or {})
end

function Colorways.choice(group, choiceIndex)
    local choices = Colorways[group] or {}
    return choices[index(choiceIndex, choices)]
end

local function getShader()
    if shader or shaderFailed or not love or not love.graphics then return shader end
    local ok, result = pcall(love.graphics.newShader, SHADER_SOURCE)
    if ok then shader = result else shaderFailed = true end
    return shader
end

function Colorways.draw(image, quad, x, y, rotation, scaleX, scaleY, originX, originY,
        shearX, shearY, furIndex, overallsIndex)
    local fur, overalls = Colorways.normalize(furIndex, overallsIndex)
    if fur == 1 and overalls == 1 then
        love.graphics.draw(image, quad, x, y, rotation, scaleX, scaleY, originX, originY, shearX, shearY)
        return
    end
    local activeShader = getShader()
    if not activeShader then
        love.graphics.draw(image, quad, x, y, rotation, scaleX, scaleY, originX, originY, shearX, shearY)
        return
    end
    activeShader:send("furTint", Colorways.fur[fur].color)
    activeShader:send("overallsTint", Colorways.overalls[overalls].color)
    activeShader:send("furEnabled", fur == 1 and 0 or 1)
    activeShader:send("overallsEnabled", overalls == 1 and 0 or 1)
    love.graphics.push("all")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(activeShader)
    love.graphics.draw(image, quad, x, y, rotation, scaleX, scaleY, originX, originY, shearX, shearY)
    love.graphics.pop()
end

return Colorways
