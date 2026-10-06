local Employees=require("src.employees")
local Animation=require("src.character_animation")
local Renderer={}
function Renderer.pose(entry,characterAssets)
    local a=entry.actor
    local action,frame
    local direction=Animation.authoredDirection(a.intentX,a.intentY)
    if a.moving then
        action=Animation.authoredAction("walk",a.intentX,a.intentY)
        frame=Animation.frameForDistance(8,a.distance,13)
    elseif entry.worker and a.phase=="break" and a.seatBay then
        action=a.seatBay=="front_left" and "rest_west" or "rest_east"
        frame=a.breakRemaining<.03 and 4 or a.idleClock<.2 and 1
            or Animation.frameForIdle(2,a.idleClock,.65)==2 and 3 or 2
    elseif (entry.worker and a.phase=="working") or (entry.application and a.phase=="waiting") then
        action="operate_"..direction;frame=a.workFrame or 1
    else
        action=Animation.authoredAction("idle",a.intentX,a.intentY)
        frame=Animation.frameForIdle(2,a.idleClock,.65)
    end
    return action,frame
end
function Renderer.draw(entry,characterAssets)
    local a=entry.actor
    local action,frame=Renderer.pose(entry,characterAssets)
    local image,quad=characterAssets.get("cat-worker",action,frame)
    if not image then return end
    local ax,ay=characterAssets.getAnchor("cat-worker",action,frame)
    local scale=.30*characterAssets.getNormalization("cat-worker","idle")
    love.graphics.setColor(.02,.02,.02,.20)
    love.graphics.ellipse("fill",a.x,a.y+1,13,4)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,quad,a.x,a.y,0,scale,scale,ax,ay)
    if entry.application and a.phase=="waiting" then
        love.graphics.setColor(.96,.85,.42,1)
        love.graphics.printf("APPLICANT",a.x-44,a.y-94,88,"center")
    end
end
function Renderer.entries(state) return Employees.actors(state) end
return Renderer
