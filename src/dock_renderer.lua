local Shutter=require('src.dock_shutter')
local Exterior=require('src.dock_exterior')
local Weather=require('src.outdoor_weather')
local Dock={}
local view,paused
local function onScreen(a)
    local g=love.graphics;local left,right,top,bottom=math.huge,-math.huge,math.huge,-math.huge
    for _,p in ipairs(a)do
        local x,y=g.transformPoint(p.x,p.y)
        left,right,top,bottom=math.min(left,x),math.max(right,x),math.min(top,y),math.max(bottom,y)
    end
    local canvas=g.getCanvas();local w,h
    if canvas then w,h=canvas:getDimensions()else w,h=g.getDimensions()end
    return right>=0 and bottom>=0 and left<=w and top<=h
end
local function fallback(assets,state,a)
    local image=assets.get('loadingBayExterior');if not image then return end
    local day,rain=Weather.sample(state)
    local left,right,top,bottom=math.huge,-math.huge,math.huge,-math.huge
    for _,p in ipairs(a)do left=math.min(left,p.x);right=math.max(right,p.x);top=math.min(top,p.y);bottom=math.max(bottom,p.y)end
    local shade=rain and .78 or 1
    love.graphics.setColor((.2+.8*day)*shade,(.26+.74*day)*shade,(.38+.62*day)*shade,1)
    love.graphics.draw(image,left,top,0,(right-left)/image:getWidth(),(bottom-top)/image:getHeight())
end
function Dock.draw(world,assets,characters,state,players,context,scene,a,drawTruck)
    local door=world.doorForScene and world.doorForScene(scene) or world.bayDoor
    local progress=door and door.progress or 0
    local visible=onScreen(a)
    -- Nothing below this branch allocates a canvas, queries actors, prepares
    -- terrain or submits exterior work while closed or outside the viewport.
    if progress<=0 or not visible then
        if view and not paused then view:pause();paused=true end
        if visible then Shutter.draw(assets,door,a,require('src.config').truck.aperture)end
        return
    end
    local town=state.home and state.home.town
    if town then
        if view and (view.town.id~=town.id or view.town.generatorVersion~=town.generatorVersion)then view:release();view=nil end
        if state.screen=='world' then
            if not view then view=Exterior.new(town,context)end
            paused=false;view:step(context);view:render(state,characters,players,world.truck)
        else Dock.pause()end
    end
    local g=love.graphics;g.push('all');g.setShader()
    local opening=Shutter.opening(a,progress)
    g.stencil(function()g.polygon('fill',unpack(opening))end,'replace',1);g.setStencilTest('greater',0)
    fallback(assets,state,a)
    if view then view:draw(a)end
    g.setStencilTest()
    -- The existing detailed rear/cargo-door sprite represents the same
    -- shipment. collect() removes its terrain duplicate by job/physical dock.
    if drawTruck then drawTruck()end
    Shutter.draw(assets,door,a,require('src.config').truck.aperture)
    g.pop()
end
function Dock.pause()
    if view and not paused then view:pause();paused=true end
end
function Dock.selectScene(scene,state)
    if scene~='warehouse' and not require('src.room_loading_bays').owns(state,scene)then Dock.pause()end
end
function Dock.characters()
    return view and not paused and view.visibleCharacters or {}
end
function Dock.stats()return view and view.stats end
function Dock.clear()
    if view then view:release();view=nil end
    paused=nil;Shutter.clear()
end
return Dock
