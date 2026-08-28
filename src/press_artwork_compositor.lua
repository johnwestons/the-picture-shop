local Compositor = {}

-- Printable sheet/plate corners inside each 627x627 process-atlas cell.
-- Order is top-left, top-right, bottom-right, bottom-left.
local SURFACES = {
    [1] = { { 0.15, 0.24 }, { 0.54, 0.12 }, { 0.93, 0.37 }, { 0.56, 0.85 } },
    [2] = { { 0.19, 0.29 }, { 0.47, 0.14 }, { 0.97, 0.40 }, { 0.53, 0.82 } },
    [3] = { { 0.17, 0.17 }, { 0.57, 0.06 }, { 0.96, 0.49 }, { 0.55, 0.76 } },
    [4] = { { 0.32, 0.09 }, { 0.68, 0.25 }, { 0.95, 0.50 }, { 0.60, 0.72 } },
}

local function clamp(value, low, high)
    return math.max(low, math.min(high, tonumber(value) or low))
end

local function dimensions(value, defaultWidth, defaultHeight)
    value = type(value) == "table" and value or {}
    return math.max(0.01, tonumber(value.width) or defaultWidth),
        math.max(0.01, tonumber(value.height) or defaultHeight)
end

local function interpolate(surface, u, v)
    local topX = surface[1][1] + (surface[2][1] - surface[1][1]) * u
    local topY = surface[1][2] + (surface[2][2] - surface[1][2]) * u
    local bottomX = surface[4][1] + (surface[3][1] - surface[4][1]) * u
    local bottomY = surface[4][2] + (surface[3][2] - surface[4][2]) * u
    return {
        topX + (bottomX - topX) * v,
        topY + (bottomY - topY) * v,
    }
end

function Compositor.layout(job, stage, quality, offsetU, offsetV)
    stage = math.max(1, math.min(4, math.floor(tonumber(stage) or 1)))
    local surface = SURFACES[stage]
    local sheetWidth, sheetHeight = dimensions(job and job.finishedSize, 10, 15)
    local artWidth, artHeight = dimensions(job and job.press and job.press.artworkSize,
        sheetWidth * 0.6, sheetHeight * 0.6)
    local leftMargin, rightMargin = 0.08, 0.08
    local topMargin, bottomMargin = 0.14, 0.08 -- includes the gripper margin
    local availableWidth = 1 - leftMargin - rightMargin
    local availableHeight = 1 - topMargin - bottomMargin
    local width = math.min(availableWidth, artWidth / sheetWidth)
    local height = math.min(availableHeight, artHeight / sheetHeight)
    local u0 = leftMargin + (availableWidth - width) / 2 + (tonumber(offsetU) or 0)
    local v0 = topMargin + (availableHeight - height) / 2 + (tonumber(offsetV) or 0)
    u0 = clamp(u0, leftMargin, 1 - rightMargin - width)
    v0 = clamp(v0, topMargin, 1 - bottomMargin - height)
    local u1, v1 = u0 + width, v0 + height
    return {
        stage = stage,
        quality = clamp(quality == nil and 1 or quality, 0, 1),
        reversed = stage == 2,
        bounds = { u0 = u0, v0 = v0, u1 = u1, v1 = v1 },
        surface = surface,
        corners = {
            interpolate(surface, u0, v0),
            interpolate(surface, u1, v0),
            interpolate(surface, u1, v1),
            interpolate(surface, u0, v1),
        },
    }
end

local function inkTint(job, stage)
    if stage ~= 2 then return 1, 1, 1 end
    local colorIndex = job and job.press and job.press.activeColorIndex or 1
    local name = job and job.press and job.press.colorSequence
        and job.press.colorSequence[colorIndex] or "Black"
    name = tostring(name):lower()
    if name:find("red", 1, true) then return 0.72, 0.25, 0.20 end
    if name:find("blue", 1, true) or name:find("cyan", 1, true) then return 0.20, 0.42, 0.68 end
    if name:find("yellow", 1, true) then return 0.74, 0.62, 0.18 end
    if name:find("green", 1, true) then return 0.22, 0.52, 0.30 end
    return 0.34, 0.36, 0.37
end

local function meshFor(image, layout, x, y, width, height)
    local uvLeft, uvRight = layout.reversed and 1 or 0, layout.reversed and 0 or 1
    local uv = { { uvLeft, 0 }, { uvRight, 0 }, { uvRight, 1 }, { uvLeft, 1 } }
    local vertices = {}
    for index, corner in ipairs(layout.corners) do
        vertices[index] = {
            x + corner[1] * width, y + corner[2] * height,
            uv[index][1], uv[index][2], 1, 1, 1, 1,
        }
    end
    local mesh = love.graphics.newMesh(vertices, "fan", "stream")
    mesh:setTexture(image)
    return mesh
end

function Compositor.draw(image, job, stage, x, y, width, height, quality)
    if not image then return false end
    quality = clamp(quality == nil and 1 or quality, 0, 1)
    local drift = (1 - quality) * 0.035
    if stage ~= 2 and drift > 0.003 then
        local red = meshFor(image, Compositor.layout(job, stage, quality, drift, -drift),
            x, y, width, height)
        love.graphics.setColor(0.84, 0.16, 0.20, 0.28)
        love.graphics.draw(red)
        if red.release then red:release() end
        local cyan = meshFor(image, Compositor.layout(job, stage, quality, -drift, drift),
            x, y, width, height)
        love.graphics.setColor(0.10, 0.42, 0.68, 0.24)
        love.graphics.draw(cyan)
        if cyan.release then cyan:release() end
    end
    local layout = Compositor.layout(job, stage, quality)
    local mesh = meshFor(image, layout, x, y, width, height)
    local red, green, blue = inkTint(job, stage)
    love.graphics.setColor(red, green, blue, 0.52 + quality * 0.48)
    love.graphics.draw(mesh)
    if mesh.release then mesh:release() end
    love.graphics.setColor(1, 1, 1, 1)
    return true
end

return Compositor
