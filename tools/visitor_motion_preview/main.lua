-- Visual check through the actual runtime loader and animation lab.
-- Run with PICTURE_SHOP_PREVIEW_ROOT and PICTURE_SHOP_PREVIEW_OUTPUT set to
-- absolute project / output directories. Captures never write game saves.
local root = assert(os.getenv("PICTURE_SHOP_PREVIEW_ROOT"), "Set PICTURE_SHOP_PREVIEW_ROOT")
local output = assert(os.getenv("PICTURE_SHOP_PREVIEW_OUTPUT"), "Set PICTURE_SHOP_PREVIEW_OUTPUT")
io.stdout:setvbuf("no")
function love.errorhandler(message)
    local detail = tostring(message) .. "\n" .. debug.traceback()
    local file = io.open(output .. "/error.txt", "wb")
    if file then file:write(detail); file:close() end
    print(detail)
    return function() return 1 end
end
assert(love.filesystem.getSource():gsub("\\", "/") == root:gsub("\\", "/"),
    "Run the visitor preview from the game project root")
assert(love.filesystem.getIdentity():match("^the%-picture%-shop%-test%-[%w%-]+$"),
    "Visitor preview requires a fresh isolated test identity")
local Assets = require("src.character_assets")
local Lab = require("src.screens.sprite_motion_lab")
local Config = require("src.config")
local roster = { "business-dragon", "business-fox", "business-cat", "tan-cat", "blue-coaler-cat", "green-blazer-cat" }
local shot, pending, peak = 1, false, 0
local queue = {}
for _, viewport in ipairs({ { "desktop", 960, 678 }, { "mobile-landscape", 1600, 720 } }) do
    for _, character in ipairs(roster) do
        for phase = 1, 8 do
            queue[#queue + 1] = { character = character, phase = phase,
                viewport = viewport[1], width = viewport[2], height = viewport[3] }
        end
    end
end

local function prepare()
    local scene = queue[shot]
    if not scene then
        assert(#Assets.failures == 0, table.concat(Assets.failures, "\n"))
        local report = assert(io.open(output .. "/engine-review.txt", "wb"))
        report:write(string.format("PASS: %d runtime captures, six visitors, eight directions, eight gait phases, desktop and landscape phone viewport.\nPeak character textures: %.2f MiB; no pixel scans or missing textures.\n", #queue, peak / 1048576))
        report:close()
        love.event.quit(0)
        return
    end
    love.window.setMode(scene.width, scene.height, { vsync = 0, resizable = false })
    for index, character in ipairs(Assets.characterNames()) do
        if character == scene.character then Lab.selected = index end
    end
    Assets.retainCharacters({ [scene.character] = true })
    Lab.distance = (scene.phase - 1) * 13 + .01
    Lab.clock = scene.phase == 8 and 2 / Config.customer.idleAnimationRate - .07 or .5
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    Assets.load()
    local healthy, errors = Assets.assertHealthy()
    assert(healthy, type(errors) == "table" and table.concat(errors, "\n") or tostring(errors))
    Lab.enter(Assets)
    prepare()
end

function love.draw()
    local scene = queue[shot]
    if not scene then return end
    local factor = math.min(scene.width / Config.baseWidth, scene.height / Config.baseHeight)
    love.graphics.clear(.025, .035, .05)
    love.graphics.push()
    love.graphics.translate((scene.width - Config.baseWidth * factor) / 2,
        (scene.height - Config.baseHeight * factor) / 2)
    love.graphics.scale(factor)
    Lab.draw(Assets)
    love.graphics.pop()
    peak = math.max(peak, Assets.textureBytes())
    if pending then return end
    pending = true
    local filename = string.format("%s/%s-%s-phase-%d.png", output, scene.viewport, scene.character, scene.phase)
    love.graphics.captureScreenshot(function(data)
        local encoded = data:encode("png")
        local file = assert(io.open(filename, "wb"))
        file:write(encoded:getString())
        file:close()
        encoded:release()
        data:release()
        shot, pending = shot + 1, false
        prepare()
    end)
end

function love.keypressed(key)
    if key == "escape" then love.event.quit(1) end
end
