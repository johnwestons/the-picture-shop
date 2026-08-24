local Anchors = require("src.character_anchors")
local Config = require("src.config")
local ImageContract = require("src.image_contract")

local CharacterAssets = {
    metadata = {},
    images = {},
    frames = {},
    failures = {},
}

local function release(image)
    if image and image.release then pcall(image.release, image) end
end

local function validateAction(character, action, path)
    local width, height, errorMessage = ImageContract.dimensions(path)
    if not width then
        CharacterAssets.failures[#CharacterAssets.failures + 1] = path .. ": " .. errorMessage
        return
    end
    if height ~= 512 or width % 512 ~= 0 then
        CharacterAssets.failures[#CharacterAssets.failures + 1] = path .. ": expected 512px-high frame strip"
        return
    end
    local frameCount = width / 512
    local actionAnchors = Anchors[character] and Anchors[character][action]
    if not actionAnchors or #actionAnchors ~= frameCount then
        CharacterAssets.failures[#CharacterAssets.failures + 1] = string.format(
            "%s: expected %d precomputed character anchors", path, frameCount)
        return
    end
    CharacterAssets.metadata[character][action] = {
        path = path,
        width = width,
        height = height,
        frameCount = frameCount,
    }
end

function CharacterAssets.load()
    CharacterAssets.releaseAll()
    CharacterAssets.metadata, CharacterAssets.images = {}, {}
    CharacterAssets.frames, CharacterAssets.failures = {}, {}
    for character, actions in pairs(Config.characters) do
        CharacterAssets.metadata[character] = {}
        CharacterAssets.images[character] = {}
        CharacterAssets.frames[character] = {}
        for action, path in pairs(actions) do validateAction(character, action, path) end
    end
end

local function loadAction(character, action)
    local metadata = CharacterAssets.metadata[character] and CharacterAssets.metadata[character][action]
    if not metadata then return nil end
    local existing = CharacterAssets.images[character][action]
    if existing then return existing, CharacterAssets.frames[character][action], metadata.frameCount end

    local ok, image = pcall(love.graphics.newImage, metadata.path)
    if not ok or not image then return nil end
    image:setFilter("nearest", "nearest")
    local frames = {}
    for frame = 1, metadata.frameCount do
        frames[frame] = love.graphics.newQuad(
            (frame - 1) * 512, 0, 512, 512, metadata.width, metadata.height)
    end
    CharacterAssets.images[character][action] = image
    CharacterAssets.frames[character][action] = frames
    return image, frames, metadata.frameCount
end

function CharacterAssets.get(character, action, frame)
    local image, frames, frameCount = loadAction(character, action)
    if not image or not frames or frameCount == 0 then return nil end
    return image, frames[((frame or 1) - 1) % frameCount + 1], frameCount
end

function CharacterAssets.getAnchor(character, action, frame)
    local actionAnchors = Anchors[character] and Anchors[character][action]
    if not actionAnchors or #actionAnchors == 0 then return 256, 398 end
    local anchor = actionAnchors[((frame or 1) - 1) % #actionAnchors + 1]
    return anchor.x, anchor.y
end

function CharacterAssets.retainCharacters(activeCharacters)
    local active = {}
    for key, value in pairs(activeCharacters or {}) do
        if type(key) == "number" then active[value] = true elseif value then active[key] = true end
    end
    for character, actions in pairs(CharacterAssets.images) do
        if not active[character] then
            for action, image in pairs(actions) do
                release(image)
                actions[action] = nil
                CharacterAssets.frames[character][action] = nil
            end
        end
    end
end

function CharacterAssets.releaseAll()
    for _, actions in pairs(CharacterAssets.images or {}) do
        for _, image in pairs(actions) do release(image) end
    end
end

function CharacterAssets.textureBytes()
    local bytes = 0
    for _, actions in pairs(CharacterAssets.images) do
        for _, image in pairs(actions) do
            local width, height = image:getDimensions()
            bytes = bytes + width * height * 4
        end
    end
    return bytes
end

function CharacterAssets.residentActionCount()
    local count = 0
    for _, actions in pairs(CharacterAssets.images) do
        for _ in pairs(actions) do count = count + 1 end
    end
    return count
end

function CharacterAssets.anchorPixelScans() return 0 end

function CharacterAssets.assertHealthy()
    return #CharacterAssets.failures == 0, table.concat(CharacterAssets.failures, "\n")
end

function CharacterAssets.failureCount() return #CharacterAssets.failures end

return CharacterAssets
