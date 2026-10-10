local Anchors = require("src.character_anchors")
local Config = require("src.config")
local ImageContract = require("src.image_contract")
local Metrics = require("src.character_metrics")
local imageCache = require("src.texture_cache").new(16 * 1024 * 1024, 20)
local useSequence = 0
local frameSequence, frameDepth = 0, 0

-- Merge the separately built visitor pack without changing established seat,
-- use, player, or pallet-jack anchor contracts.
for character, actions in pairs(require("src.visitor_character_anchors")) do
    Anchors[character] = Anchors[character] or {}
    for action, frames in pairs(actions) do Anchors[character][action] = frames end
end
for character, actions in pairs(require("src.visitor_character_metrics")) do
    Metrics[character] = Metrics[character] or {}
    for action, frames in pairs(actions) do Metrics[character][action] = frames end
end
for character,actions in pairs(require("src.cat_worker_anchors")) do Anchors[character]=actions end
for character,actions in pairs(require("src.cat_worker_metrics")) do Metrics[character]=actions end
for character,actions in pairs(require("src.mouse_worker_anchors")) do Anchors[character]=actions end
for character,actions in pairs(require("src.mouse_worker_metrics")) do Metrics[character]=actions end
for character,actions in pairs(require("src.worker_action_anchors")) do
    Anchors[character]=Anchors[character] or {}
    for action,frames in pairs(actions) do Anchors[character][action]=frames end
end
for character,actions in pairs(require("src.worker_action_metrics")) do
    Metrics[character]=Metrics[character] or {}
    for action,frames in pairs(actions) do Metrics[character][action]=frames end
end
for character, actions in pairs(require("src.player_action_anchors")) do
    Anchors[character] = Anchors[character] or {}
    for action, frames in pairs(actions) do Anchors[character][action] = frames end
end
for character, actions in pairs(require("src.player_action_metrics")) do
    Metrics[character] = Metrics[character] or {}
    for action, frames in pairs(actions) do Metrics[character][action] = frames end
end
local jackArt = require("src.pallet_jack_art")
for action, frames in pairs(jackArt.anchors) do Anchors["rabbit-worker"][action] = frames end
for action, frames in pairs(jackArt.metrics) do Metrics["rabbit-worker"][action] = frames end
local employeeArt = require("src.employee_motion_art")
for character,actions in pairs(employeeArt.anchors) do
    for action,frames in pairs(actions) do Anchors[character][action]=frames end
end
for character,actions in pairs(employeeArt.metrics) do
    for action,frames in pairs(actions) do Metrics[character][action]=frames end
end
local seatingArt = require("src.client_seating_art")
for character, actions in pairs(seatingArt.anchors) do
    for action, frames in pairs(actions) do Anchors[character][action] = frames end
end
for character, actions in pairs(seatingArt.metrics) do
    for action, frames in pairs(actions) do Metrics[character][action] = frames end
end
local breakArt = require("src.employee_break_art")
for character, actions in pairs(breakArt.anchors) do
    Anchors[character] = Anchors[character] or {}
    for action, frames in pairs(actions) do Anchors[character][action] = frames end
end
for character, actions in pairs(breakArt.metrics) do
    Metrics[character] = Metrics[character] or {}
    for action, frames in pairs(actions) do Metrics[character][action] = frames end
end

local CharacterAssets = {
    metadata = {},
    images = {},
    frames = {},
    failures = {},
    loadFailures = {},
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
    local actionSizes = Config.characterActionFrameSizes and Config.characterActionFrameSizes[character]
    local additionalActionSizes = Config.workerActionFrameSizes
        and Config.workerActionFrameSizes[character]
    local frameSize = actionSizes and actionSizes[action]
        or additionalActionSizes and additionalActionSizes[action]
        or Config.workerFrameSizes[character] or 512
    if height ~= frameSize or width % frameSize ~= 0 then
        CharacterAssets.failures[#CharacterAssets.failures + 1] = path .. ": invalid character frame strip size"
        return
    end
    local frameCount = width / frameSize
    local actionAnchors = Anchors[character] and Anchors[character][action]
    if not actionAnchors or #actionAnchors ~= frameCount then
        CharacterAssets.failures[#CharacterAssets.failures + 1] = string.format(
            "%s: expected %d precomputed character anchors", path, frameCount)
        return
    end
    local actionMetrics = Metrics[character] and Metrics[character][action]
    if not actionMetrics or #actionMetrics ~= frameCount then
        CharacterAssets.failures[#CharacterAssets.failures + 1] = string.format(
            "%s: expected %d precomputed visible-frame bounds", path, frameCount)
        return
    end
    CharacterAssets.metadata[character][action] = {
        path = path,
        width = width,
        height = height,
        frameCount = frameCount,
        frameSize = frameSize,
        visibleHeight = 0,
    }
    for _, bounds in ipairs(actionMetrics) do
        local metadata = CharacterAssets.metadata[character][action]
        metadata.visibleHeight = math.max(metadata.visibleHeight, bounds[4] - bounds[2])
    end
end

local function actionHeight(character, action)
    local frames = Metrics[character] and Metrics[character][action]
    local height = 0
    for _, bounds in ipairs(frames or {}) do height = math.max(height, bounds[4] - bounds[2]) end
    return height
end

function CharacterAssets.getNormalization(character, action)
    -- Normalize every character action to one shared world-space body height.
    -- This lets playable and visiting characters use the same rendering path.
    local reference = Config.characterRendering.referenceHeight
    local metadata = CharacterAssets.metadata[character] and CharacterAssets.metadata[character][action]
    local height = metadata and metadata.visibleHeight or actionHeight(character, action)
    if reference <= 0 or height <= 0 then return 1 end
    return reference / height
end

function CharacterAssets.getVisibleBounds(character, action, frame)
    local frames = Metrics[character] and Metrics[character][action]
    if not frames or #frames == 0 then return nil end
    local bounds = frames[((frame or 1) - 1) % #frames + 1]
    return bounds[1], bounds[2], bounds[3], bounds[4]
end

function CharacterAssets.normalizedFrameMetrics(character, action, frame)
    local left, top, right, bottom = CharacterAssets.getVisibleBounds(character, action, frame)
    if not left then return nil end
    local scale = CharacterAssets.getNormalization(character, action)
    return {
        width = (right - left) * scale,
        height = (bottom - top) * scale,
        scale = scale,
    }
end

function CharacterAssets.characterNames()
    local result = {}
    for character in pairs(Config.characters) do result[#result + 1] = character end
    table.sort(result)
    return result
end

function CharacterAssets.actions(character)
    local result = {}
    for action in pairs(Config.characters[character] or {}) do result[#result + 1] = action end
    table.sort(result)
    return result
end

function CharacterAssets.hasAction(character, action)
    return CharacterAssets.metadata[character]
        and CharacterAssets.metadata[character][action] ~= nil
end

function CharacterAssets.load()
    CharacterAssets.releaseAll()
    useSequence = 0
    frameSequence, frameDepth = 0, 0
    CharacterAssets.metadata, CharacterAssets.images = {}, {}
    CharacterAssets.frames, CharacterAssets.failures, CharacterAssets.loadFailures = {}, {}, {}
    for character, actions in pairs(Config.characters) do
        CharacterAssets.metadata[character] = {}
        CharacterAssets.images[character] = {}
        CharacterAssets.frames[character] = {}
        CharacterAssets.loadFailures[character] = {}
        for action, path in pairs(actions) do validateAction(character, action, path) end
    end
end

local function loadAction(character, action)
    local metadata = CharacterAssets.metadata[character] and CharacterAssets.metadata[character][action]
    if not metadata then return nil end
    if CharacterAssets.loadFailures[character]
        and CharacterAssets.loadFailures[character][action]
    then return nil end
    local existing = CharacterAssets.images[character][action]
    if existing then return existing, CharacterAssets.frames[character][action], metadata.frameCount end

    local image
    local ok, frames = pcall(function()
        image = imageCache:take(metadata.path) or love.graphics.newImage(metadata.path)
        if not image then error("image loader returned no texture") end
        image:setFilter("nearest", "nearest")
        local result = {}
        for frame = 1, metadata.frameCount do
            result[frame] = love.graphics.newQuad(
                (frame - 1) * metadata.frameSize, 0, metadata.frameSize, metadata.frameSize, metadata.width, metadata.height)
        end
        return result
    end)
    if not ok then
        release(image)
        local message = string.format("%s: GPU texture load failed: %s", metadata.path, tostring(frames))
        CharacterAssets.failures[#CharacterAssets.failures + 1] = message
        CharacterAssets.loadFailures[character][action] = message
        return nil
    end
    CharacterAssets.images[character][action] = image
    CharacterAssets.frames[character][action] = frames
    return image, frames, metadata.frameCount
end

function CharacterAssets.get(character, action, frame)
    local metadata = CharacterAssets.metadata[character] and CharacterAssets.metadata[character][action]
    if metadata then
        useSequence = useSequence + 1
        metadata.lastUse = useSequence
        metadata.lastFrame = frameSequence
    end
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

-- Pin every pose drawn by every actor this frame (including remote players
-- using a GUI). Old directions/actions share the bounded inactive LRU instead
-- of remaining resident for the lifetime of a visible character species.
function CharacterAssets.beginFrame()
    if frameDepth == 0 then frameSequence = frameSequence + 1 end
    frameDepth = frameDepth + 1
end

function CharacterAssets.endFrame()
    if frameDepth == 0 then return end
    frameDepth = frameDepth - 1
    if frameDepth > 0 then return end
    local retired = {}
    for character, actions in pairs(CharacterAssets.images) do
        for action, image in pairs(actions) do
            local metadata = CharacterAssets.metadata[character][action]
            if metadata.lastFrame ~= frameSequence then
                retired[#retired+1] = {metadata=metadata,image=image}
                actions[action] = nil
                CharacterAssets.frames[character][action] = nil
            end
        end
    end
    table.sort(retired,function(a,b) return (a.metadata.lastUse or 0)<(b.metadata.lastUse or 0) end)
    for _,entry in ipairs(retired) do imageCache:put(entry.metadata.path,entry.image) end
end

function CharacterAssets.retainCharacters(activeCharacters, cacheInactive)
    -- Explicit release requests (asset checks/reloads) remain immediate. During
    -- screen changes, a small idle cache avoids decoding the same actor again.
    if not cacheInactive then imageCache:clear() end
    local active = {}
    for key, value in pairs(activeCharacters or {}) do
        if type(key) == "number" then active[value] = true elseif value then active[key] = true end
    end
    local retired = {}
    for character, actions in pairs(CharacterAssets.images) do
        if not active[character] then
            for action, image in pairs(actions) do
                local metadata = CharacterAssets.metadata[character][action]
                if cacheInactive then
                    retired[#retired+1] = {metadata=metadata,image=image}
                else release(image) end
                actions[action] = nil
                CharacterAssets.frames[character][action] = nil
            end
        end
    end
    -- Keep the poses actually drawn most recently when a whole character has
    -- more actions than the idle budget can hold.
    table.sort(retired,function(a,b)
        return (a.metadata.lastUse or 0) < (b.metadata.lastUse or 0)
    end)
    for _,entry in ipairs(retired) do imageCache:put(entry.metadata.path,entry.image) end
end

function CharacterAssets.releaseAll()
    imageCache:clear()
    for _, actions in pairs(CharacterAssets.images or {}) do
        for _, image in pairs(actions) do release(image) end
    end
end
function CharacterAssets.pruneCache() imageCache:prune() end
function CharacterAssets.clearCache() imageCache:clear() end
function CharacterAssets.cachedTextureBytes() return imageCache.bytes end

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
