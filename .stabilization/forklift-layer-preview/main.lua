local root = assert(os.getenv("PICTURE_SHOP_ROOT"), "PICTURE_SHOP_ROOT required")
local output = assert(os.getenv("PICTURE_SHOP_PREVIEW"), "PICTURE_SHOP_PREVIEW required")
local imageRoot = root .. "/assets/source/warehouse-expansion-v1/forklift-layer-study/"
local body, carriage
local captured = false

local function loadImage(path)
    local file = assert(io.open(imageRoot .. path, "rb"))
    local bytes = assert(file:read("*a"))
    file:close()
    local data = love.filesystem.newFileData(bytes, path)
    local image = love.graphics.newImage(data)
    image:setFilter("linear", "linear")
    return image
end

function love.load()
    love.window.setMode(1280, 680)
    love.window.setTitle("Forklift layered lift study")
    body = loadImage(os.getenv("PICTURE_SHOP_PREVIEW_EMPTY") == "1"
        and "east-fixed-empty-v1.png" or "east-fixed-manned-v1.png")
    carriage = loadImage("east-carriage-v2.png")
end

function love.draw()
    local g = love.graphics
    g.clear(0.075, 0.08, 0.09)
    g.setColor(1, 0.82, 0.25)
    g.printf("EAST-FACING FORKLIFT: LAYERED LIFT STUDY", 0, 22, 1280, "center")
    g.setColor(0.82, 0.86, 0.9)
    g.printf("One fixed body and one smoothly moving fork carriage; unapproved source candidate", 0, 45, 1280, "center")
    local scale = 0.44
    for index, height in ipairs({ 0, 0.5, 1 }) do
        local left = 20 + (index - 1) * 420
        local center = left + 200
        for row = 0, 20 do
            for column = 0, 17 do
                local shade = (row + column) % 2 == 0 and 0.18 or 0.23
                g.setColor(shade, shade, shade)
                g.rectangle("fill", left + column * 23, 110 + row * 23, 23, 23)
            end
        end
        local x = center - 850 * scale
        local y = 590 - 930 * scale
        g.setColor(0.15, 0.85, 0.9, 0.7)
        g.line(left, 590, left + 400, 590)
        g.setColor(1, 1, 1)
        g.draw(body, x, y, 0, scale, scale)
        g.draw(carriage, x, y + (150 - 560 * height) * scale, 0, scale, scale)
        g.printf(string.format("FORK HEIGHT %.0f%%", height * 100), left, 615, 400, "center")
    end
    if not captured then
        captured = true
        g.captureScreenshot(function(imageData)
            local encoded = imageData:encode("png")
            local file = assert(io.open(output, "wb"))
            assert(file:write(encoded:getString()))
            assert(file:close())
            encoded:release()
            imageData:release()
            love.event.quit()
        end)
    end
end
