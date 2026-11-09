-- Small shared sprite atlas for the quiet motorcycle controls.
local Icons={}
local image,quads,cellWidth,cellHeight

local GRID={
    throttle={1,1}, brake={2,1}, steer={3,1}, map={4,1},
    camera={1,2}, follow={2,2}, center={3,2}, boost={4,2},
    headlight={1,3}, transmission={2,3}, reverse={3,3}, more={4,3},
    ignition={1,4}, shift={2,4}, dismount={3,4}, helmet={4,4},
}

local ACTIONS={
    accelerate='throttle', brake='brake', interact='dismount',
    boost='boost', view='camera', followCamera='follow', recenter='center',
    headlight='headlight', transmission='transmission', reverse='reverse',
    more='more', back='reverse', ignition='ignition',
    rescue='center',
    shiftDown='shift', shiftUp='shift', gear='helmet',
}

local function load()
    if image then return end
    image=love.graphics.newImage('assets/generated/commute-ui-icons-v1/action-icons-atlas.png')
    image:setFilter('linear','linear')
    local width,height=image:getDimensions()
    cellWidth,cellHeight=width/4,height/4
    quads={}
    for name,cell in pairs(GRID) do
        quads[name]=love.graphics.newQuad((cell[1]-1)*cellWidth,(cell[2]-1)*cellHeight,
            cellWidth,cellHeight,width,height)
    end
end

function Icons.action(action) return ACTIONS[action] end
function Icons.prewarm() load();return image end

function Icons.draw(name,cx,cy,size,tint)
    local quad
    if GRID[name] then load();quad=quads[name] end
    if not quad then return false end
    local g=love.graphics
    if tint then g.setColor(tint[1],tint[2],tint[3],tint[4] or 1)
    else g.setColor(1,1,1,1) end
    g.draw(image,quad,cx-size*.5,cy-size*.5,0,size/cellWidth,size/cellHeight)
    return true
end

function Icons.release()
    if image then image:release() end
    image,quads,cellWidth,cellHeight=nil,nil,nil,nil
end

return Icons
