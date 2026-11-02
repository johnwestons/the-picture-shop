local root = 'C:/Users/johnw/OneDrive/Documents/ChatGPT/The Picture Shop/'
local phase = {'left_contact','left_down','right_passing','right_up','right_contact','right_down','left_passing','left_up'}
local mode = os.getenv('PICTURE_SHOP_EAST_CANDIDATE_VIEW') or 'strips'
local capturePath = os.getenv('PICTURE_SHOP_EAST_CANDIDATE_CAPTURE')
local frameSize, header, checker = 256, 36, 16
local images, captured = {}, false

local function load(path)
    if images[path] then return images[path] end
    local file, err = io.open(root .. path, 'rb')
    assert(file, err)
    local bytes = file:read('*a'); file:close()
    local data = love.filesystem.newFileData(bytes, path:match('[^/\\]+$'))
    local image = love.graphics.newImage(data)
    image:setFilter('nearest', 'nearest')
    images[path] = image
    return image
end

local function checkerboard(x, y)
    local g = love.graphics
    for cy = 0, frameSize - 1, checker do
        for cx = 0, frameSize - 1, checker do
            local even = (math.floor(cx/checker) + math.floor(cy/checker)) % 2 == 0
            if even then g.setColor(.79,.81,.79,1) else g.setColor(.90,.91,.89,1) end
            g.rectangle('fill', x+cx, y+cy, checker, checker)
        end
    end
end

local function drawCell(image, frame, x, y)
    local g = love.graphics
    checkerboard(x,y)
    local quad = g.newQuad((frame-1)*frameSize,0,frameSize,frameSize,image:getDimensions())
    g.setColor(1,1,1,1);g.draw(image,quad,x,y)
    g.setColor(.35,.83,.71,1);g.setLineWidth(1);g.line(x,y+238,x+frameSize,y+238)
end

local function rows()
    if mode == 'contacts' then
        return {
            {label='LEFT CONTACT',path='assets/staging/commute-rider-v2-east-contact-test/east-contact-pair.png',frames=2},
        }
    end
    return {
        {label='FULL STRIP ALT1',path='assets/staging/commute-rider-v2-east-alt1/walk_east_candidate.png',frames=8},
        {label='FULL STRIP ALT2',path='assets/staging/commute-rider-v2-east-alt2/walk_east_candidate.png',frames=8},
    }
end

function love.load()
    local count = mode == 'contacts' and 2 or 8
    local rowList = rows()
    love.window.setMode(frameSize*count,(frameSize+header)*#rowList,{resizable=false,vsync=0,highdpi=false})
    love.window.setTitle('East walk candidate — static native review')
    love.graphics.setDefaultFilter('nearest','nearest')
end

function love.draw()
    local g=love.graphics;g.clear(.12,.16,.17,1)
    for ri,row in ipairs(rows()) do
        local top=(ri-1)*(frameSize+header)
        local image=load(row.path)
        g.setColor(1,1,1,1);g.print(row.label,8,top+5)
        for frame=1,row.frames do
            local x=(frame-1)*frameSize
            local label = mode == 'contacts' and (frame==1 and 'left-contact' or 'right-contact-edit') or (frame..' '..phase[frame])
            g.print(label,x+5,top+20)
            drawCell(image,frame,x,top+header)
        end
    end
    if capturePath and not captured then
        captured=true
        g.captureScreenshot(function(data)
            local f,err=io.open(capturePath,'wb');assert(f,err)
            f:write(data:encode('png'):getString());f:close()
            print('EAST_CANDIDATE_CAPTURE '..capturePath)
            love.event.quit()
        end)
    end
end

function love.keypressed(key)
    if key=='escape' then love.event.quit() end
end
