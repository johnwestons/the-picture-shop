local PixelCanvas=require('src.tests.support.pixel_canvas')
local Held = require("src.home_held_art")
local Fixtures = require("src.tests.home_dining_test")
local Residents = require("src.home_residents")
local Consumption = require("src.home_consumption_art")

local Test = {}

local function capture(canvas, name)
    local folder = os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    if not folder then return end
    local data = canvas:newImageData()
    local bytes = data:encode("png")
    local file = assert(io.open(folder .. "/" .. name .. ".png", "wb"))
    file:write(bytes:getString()); file:close()
    bytes:release(); data:release()
end

local function hasCoverage(canvas)
    local data = canvas:newImageData()
    local visible = false
    for x = 0, canvas:getWidth() - 1, 9 do
        for y = 0, canvas:getHeight() - 1, 9 do
            local r, g, b, a = data:getPixel(x, y)
            if a > .25 and (r > .08 or g > .08 or b > .08) then visible = true end
        end
    end
    data:release()
    return visible
end

function Test.run(context, check)
    local families = { "meal", "sandwich", "bottle" }
    local canvas = PixelCanvas(960, 720)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(.035, .045, .06, 1)
    for familyIndex, family in ipairs(families) do
        check("home_held_" .. family .. "_registered", Held.available(family))
        for directionIndex, direction in ipairs(Held.DIRECTIONS) do
            local x = 88 + (directionIndex - 1) * 108
            local y = 126 + (familyIndex - 1) * 190
            check("home_held_" .. family .. "_" .. direction .. "_contact", Held.contact(family, direction, 44) ~= nil)
            check("home_held_" .. family .. "_" .. direction .. "_draws",
                Held.draw(family, direction, x, y, 44, (directionIndex % 2 == 0) and .02 or 0))
        end
    end
    love.graphics.pop()
    capture(canvas, "home-held-directional-grid")
    check("home_held_directional_grid_has_coverage", hasCoverage(canvas))
    canvas:release()

    -- Exercise the same replicated action payload used by the apartment
    -- renderer. Unknown foods still fall back to the catalog atlas, so older
    -- saves remain drawable while this directional set grows.
    for _, example in ipairs({
        { "eat", "basic_meal", "meal" },
        { "sandwich", "sandwich", "sandwich" },
        { "bottle", "bottled_drink", "bottle" },
    }) do
        local state, player = Fixtures.fresh()
        state.home.inventory[example[2]] = 1
        assert(Residents.command(state, player, example[1] .. ":floor"))
        local activity = assert(Residents.get(state, player).activity)
        local pose = { x = player.x, y = player.y, direction = "south", seconds = 0 }
        local result = Consumption.draw(state, activity, player, pose)
        check("home_held_consumption_" .. example[3] .. "_routes", result == true)
        assert(Residents.command(state, player, "cancel"))
    end
    Held.release()
end

return Test
