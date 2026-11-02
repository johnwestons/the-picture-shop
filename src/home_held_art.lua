-- Directional handheld props for home actions.
--
-- The source sheets are deliberately kept as simple 4x2 atlases so the
-- action renderer can use the same direction name that the avatar uses.  The
-- prop is centred in each cell; character hands are intentionally omitted so
-- the art follows the game's no-human-hands rule for host and guest views.
local Art = {
    DIRECTIONS = { "southeast", "south", "southwest", "west",
        "northwest", "north", "northeast", "east" },
    PATHS = {
        meal = "assets/generated/home-held-v1/held-meal-eight-directions.png",
        sandwich = "assets/generated/home-held-v1/held-sandwich-eight-directions.png",
        bottle = "assets/generated/home-held-v1/held-bottle-eight-directions.png",
    },
}

local assets, shader

local function directionIndex(direction)
    for i, name in ipairs(Art.DIRECTIONS) do
        if name == direction then return i end
    end
    return #Art.DIRECTIONS
end

local function load(kind)
    assets = assets or {}
    if assets[kind] then return assets[kind] end
    local path = Art.PATHS[kind]
    if not path then return nil end
    local image = love.graphics.newImage(path)
    image:setFilter("linear", "linear")
    local width, height = image:getDimensions()
    local cellWidth, cellHeight = width / 4, height / 2
    local entry = { image = image, quads = {}, width = cellWidth, height = cellHeight }
    for i = 1, 8 do
        local x = ((i - 1) % 4) * cellWidth
        local y = math.floor((i - 1) / 4) * cellHeight
        entry.quads[i] = love.graphics.newQuad(x, y, cellWidth, cellHeight, width, height)
    end
    assets[kind] = entry
    return entry
end

local function ensureShader()
    shader = shader or love.graphics.newShader([[vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 p = Texel(tex, uv);
        if (p.a < 0.18) discard;
        return p * color;
    }]])
    return shader
end

function Art.available(kind)
    return Art.PATHS[kind] ~= nil
end

function Art.index(direction)
    return directionIndex(direction)
end

function Art.contact(kind, direction, size)
    local entry = load(kind)
    if not entry then return nil end
    local scale = (size or 32) / math.max(entry.width, entry.height)
    return {
        direction = direction or Art.DIRECTIONS[directionIndex(direction)],
        frame = directionIndex(direction),
        width = entry.width * scale,
        height = entry.height * scale,
        scale = scale,
        -- The generated cell is centred, so this is also the draw origin.
        x = 0,
        y = 0,
    }
end

function Art.draw(kind, direction, x, y, size, rotation)
    local entry = load(kind)
    if not entry then return false end
    local frame = directionIndex(direction)
    local scale = (size or 32) / math.max(entry.width, entry.height)
    love.graphics.push("all")
    love.graphics.setShader(ensureShader())
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(entry.image, entry.quads[frame], x, y, rotation or 0,
        scale, scale, entry.width / 2, entry.height / 2)
    love.graphics.pop()
    return true
end

function Art.release()
    if assets then
        for _, entry in pairs(assets) do
            entry.image:release()
            for _, quad in ipairs(entry.quads) do quad:release() end
        end
    end
    if shader then shader:release() end
    assets, shader = nil, nil
end

return Art
