local Employees=require("src.employees")
local Animation=require("src.character_animation")
local Catalog=require("src.worker_catalog")
local Renderer={}
function Renderer.pose(entry,characterAssets)
    local a=entry.actor
    local action,frame
    local character=Catalog.character(entry)
    local mirror=1
    local direction=Animation.authoredDirection(a.intentX,a.intentY)
    if a.moving then
        action,mirror=Catalog.action(character,"walk",a.intentX,a.intentY)
        frame=Animation.frameForDistance(8,a.distance,13)
    elseif entry.worker and a.phase=="break" and a.seatBay then
        if character=="cat-worker" then
            action=a.seatBay=="front_left" and "rest_west" or "rest_east"
            frame=a.breakRemaining<.03 and 4 or a.idleClock<.2 and 1
                or Animation.frameForIdle(2,a.idleClock,.65)==2 and 3 or 2
        else action,frame="rest",1 end
    elseif (entry.worker and a.phase=="working") or (entry.application and a.phase=="waiting") then
        if character=="cat-worker" then action="operate_"..direction;frame=a.workFrame or 1
        elseif entry.worker then action,frame="operate",1
        else action,mirror=Catalog.action(character,"idle",a.intentX,a.intentY);frame=Animation.frameForIdle(2,a.idleClock,.65) end
    else
        action,mirror=Catalog.action(character,"idle",a.intentX,a.intentY)
        frame=Animation.frameForIdle(2,a.idleClock,.65)
    end
    return action,frame,mirror
end
function Renderer.draw(entry,characterAssets)
    local a=entry.actor
    local character=Catalog.character(entry)
    local action,frame,mirror=Renderer.pose(entry,characterAssets)
    local image,quad=characterAssets.get(character,action,frame)
    if not image then return end
    local ax,ay=characterAssets.getAnchor(character,action,frame)
    local scale=.30*characterAssets.getNormalization(character,"idle")
    love.graphics.setColor(.02,.02,.02,.20)
    love.graphics.ellipse("fill",a.x,a.y+1,13,4)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,quad,a.x,a.y,0,scale*mirror,scale,ax,ay)
    if entry.application and a.phase=="waiting" then
        love.graphics.setColor(.96,.85,.42,1)
        love.graphics.printf("APPLICANT",a.x-44,a.y-94,88,"center")
    end
end
function Renderer.entries(state) return Employees.actors(state) end
return Renderer
