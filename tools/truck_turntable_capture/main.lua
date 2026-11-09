local Elevated = require('src.commute.truck_elevated_art')
local graphics = love.graphics
local frameWidth, frameHeight = 640, 448
local anchorX, anchorY = 320, 320

local views = {
    {name='chase', pitch=8, vertical=48, pageCellWidth=640, pageScale=1, pageAnchorY=352},
    {name='isometric', pitch=32, vertical=38.4, pageCellWidth=384, pageScale=.5, pageAnchorY=316},
}

local function writePng(pixels, path)
    local data = pixels:encode('png')
    local file = assert(io.open(path, 'wb'))
    assert(file:write(data:getString()))
    assert(file:close())
    data:release()
end

function love.load()
    local output = assert(os.getenv('PICTURE_SHOP_TRUCK_CAPTURE_OUTPUT'))
    local masterPath = assert(os.getenv('PICTURE_SHOP_TRUCK_MASTER'))
    local art = Elevated.new()
    local sprite = graphics.newCanvas(frameWidth, frameHeight, {msaa=4})
    -- Assemble on the CPU so the combined sheet can exceed GPU texture limits.
    local sheet = love.image.newImageData(frameWidth * 8, frameHeight * 16)

    for viewIndex, view in ipairs(views) do
        local width = view.pageCellWidth
        local page = graphics.newCanvas(width * 4, 384 * 4)
        for index = 0, 63 do
            graphics.setCanvas(sprite)
            graphics.clear(0, 0, 0, 0)
            graphics.setBlendMode('alpha', 'alphamultiply')
            art:draw(anchorX, anchorY, 2, index * math.pi / 32, nil, view.pitch, view.vertical)
            graphics.setCanvas()

            local pixels = sprite:newImageData()
            local row = (viewIndex - 1) * 8 + math.floor(index / 8)
            sheet:paste(pixels, (index % 8) * frameWidth, row * frameHeight, 0, 0, frameWidth, frameHeight)
            pixels:release()

            -- Extract the game pages from the same render with their existing pivots.
            local slot = index % 16
            graphics.setCanvas(page)
            if slot == 0 then graphics.clear(0, 0, 0, 0) end
            local left, top = slot % 4 * width, math.floor(slot / 4) * 384
            graphics.setScissor(left, top, width, 384)
            graphics.setBlendMode('replace', 'premultiplied')
            graphics.draw(sprite, left + width / 2, top + view.pageAnchorY,
                0, view.pageScale, view.pageScale, anchorX, anchorY)
            graphics.setScissor()
            graphics.setCanvas()
            if slot == 15 then
                local pagePixels = page:newImageData()
                writePng(pagePixels, ('%s/%s-64-%d.png'):format(output, view.name, math.floor(index / 16) + 1))
                pagePixels:release()
            end
        end
        page:release()
    end
    writePng(sheet, masterPath)
    sheet:release()
    sprite:release()
    art:release()
    print('TRUCK_COMPLETE_SHEET_OK')
    love.event.quit()
end

function love.errorhandler(message)
    print(debug.traceback(tostring(message), 2))
    return function() return 1 end
end
