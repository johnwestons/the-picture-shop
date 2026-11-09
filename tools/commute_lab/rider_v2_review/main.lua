local root = 'C:/Users/johnw/OneDrive/Documents/ChatGPT/The Picture Shop/'
local reviewRoot = root .. 'output/commute-rider-v2-review/'
local directions = {'north', 'northeast', 'east', 'southeast', 'south'}
local phases = {'left_contact','left_down','right_passing','right_up','right_contact','right_down','left_passing','left_up'}
local mode = os.getenv('PICTURE_SHOP_RIDER_V2_VIEW') or 'walk'
local capturePath = os.getenv('PICTURE_SHOP_RIDER_V2_CAPTURE')
local checker = 16
local frameSize = 256
local headerSize = 44
local baseline = 238
local images = {}
local captured = false

local function loadImage(path)
    local f, err = io.open(root .. path, 'rb')
    assert(f, err)
    local bytes = f:read('*a')
    f:close()
    local fileData = love.filesystem.newFileData(bytes, path:match('[^/\\]+$'))
    local image = love.graphics.newImage(fileData)
    image:setFilter('nearest', 'nearest')
    return image
end

local function checkerboard(x, y)
    local g = love.graphics
    for cy = 0, frameSize - 1, checker do
        for cx = 0, frameSize - 1, checker do
            local even = (math.floor(cx / checker) + math.floor(cy / checker)) % 2 == 0
            if even then g.setColor(.79,.81,.79,1) else g.setColor(.90,.91,.89,1) end
            g.rectangle('fill', x + cx, y + cy, checker, checker)
        end
    end
end

local function strip(path)
    local image = images[path]
    if not image then
        image = loadImage(path)
        images[path] = image
    end
    return image
end

function love.load()
    local width = mode == 'idle' and frameSize * 2 or frameSize * 8
    local height = (frameSize + headerSize) * #directions
    love.window.setMode(width, height, {resizable=false, vsync=0, highdpi=false})
    love.window.setTitle('Commute rider v2 — native sprite review / ' .. mode)
    love.graphics.setDefaultFilter('nearest', 'nearest')
end

local function drawCell(image, frame, x, y)
    local g = love.graphics
    g.setColor(.05,.08,.09,1);g.rectangle('fill',x,y,frameSize,frameSize)
    checkerboard(x,y)
    local quad = love.graphics.newQuad((frame-1)*frameSize,0,frameSize,frameSize,image:getDimensions())
    g.setColor(1,1,1,1);g.draw(image,quad,x,y)
    g.setColor(.35,.83,.71,1);g.setLineWidth(1);g.line(x,y+baseline,x+frameSize,y+baseline)
    g.setColor(.91,.97,.85,1);g.rectangle('fill',x+frameSize*.5-2,y+baseline-2,4,4)
end

function love.draw()
    local g = love.graphics
    g.clear(.12,.16,.17,1)
    for row,direction in ipairs(directions) do
        local top=(row-1)*(frameSize+headerSize)
        if mode=='idle' then
            local image=strip('assets/staging/commute-rider-v2/idle_'..direction..'.png')
            g.setColor(1,1,1,1);g.print(direction:upper(),8,top+7)
            g.print('neutral',8,top+25);g.print('settle',frameSize+8,top+25)
            drawCell(image,1,0,top+headerSize)
            drawCell(image,2,frameSize,top+headerSize)
        else
            local image=strip('assets/staging/commute-rider-v2/walk_'..direction..'.png')
            g.setColor(1,1,1,1);g.print(direction:upper(),8,top+7)
            for frame=1,8 do
                local x=(frame-1)*frameSize
                g.print(frame..' '..phases[frame],x+8,top+25)
                drawCell(image,frame,x,top+headerSize)
            end
        end
    end
    if capturePath and not captured then
        captured=true
        love.graphics.captureScreenshot(function(data)
            local f,err=io.open(capturePath,'wb')
            assert(f,err);f:write(data:encode('png'):getString());f:close()
            print('RIDER_V2_CAPTURE '..capturePath)
            love.event.quit()
        end)
    end
end

function love.keypressed(key)
    if key=='escape' then love.event.quit() end
end
