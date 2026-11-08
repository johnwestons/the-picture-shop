-- Extend the world behind the cab to the physical display. The dashboard and
-- touch controls keep their authored 1280x880 coordinates and optical center.
local Viewport={}

function Viewport.layout(width,height,bounds)
    local scaleX,scaleY
    if require('src.viewport').fullScreenDevice() then
        scaleX,scaleY=width/1280,height/880
    else
        local scale=math.min(width/1280,height/880)
        scaleX,scaleY=scale,scale
    end
    local x,y=(width-1280*scaleX)*.5,(height-880*scaleY)*.5
    local left=math.floor((bounds.left-x)/scaleX)
    local top=math.floor((bounds.top-y)/scaleY)
    local right=math.ceil((bounds.right-x)/scaleX)
    local bottom=math.ceil((bounds.bottom-y)/scaleY)
    return {x=left,y=top,width=right-left,height=bottom-top}
end

function Viewport.camera(camera,layout)
    return setmetatable({viewportWidth=layout.width,viewportHeight=layout.height,
        viewCenterX=(camera.viewCenterX or 640)-layout.x,
        viewCenterY=(camera.viewCenterY or 440)-layout.y},{__index=camera})
end

function Viewport.forRuntime(R,camera)
    if not camera.firstPerson or camera.localVehicle~='truck' then return camera end
    local x,y,_,scaleX,scaleY=require('src.viewport').transform(R.Config.baseWidth,R.Config.baseHeight,
        R.App.officeUsesSafeArea and R.App.officeUsesSafeArea())
    local width,height=love.graphics.getDimensions()
    -- Derive the cab camera bounds from the physical display transform so its
    -- scenery reaches the display edges along with the rest of the commute view.
    local bounds={left=-x/scaleX,top=-y/scaleY,right=(width-x)/scaleX,bottom=(height-y)/scaleY}
    local layout=Viewport.layout(R.Config.baseWidth,R.Config.baseHeight,bounds)
    return Viewport.camera(camera,layout),layout
end

return Viewport
