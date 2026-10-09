local Employees=require("src.employees")
local Animation=require("src.character_animation")
local Catalog=require("src.worker_catalog")
local Speech=require("src.employee_speech")
local Config=require("src.config")
local Jack=require("src.pallet_jack")
local MotionArt=require("src.employee_motion_art")
local Renderer={}
local bubbleFont
function Renderer.pose(entry,characterAssets)
    local a=entry.actor
    local action,frame
    local character=Catalog.character(entry)
    local mirror=1
    local direction=Animation.authoredDirection(a.intentX,a.intentY)
    if entry.worker and a.phase=="pushing" then
        action,mirror=Catalog.pushAction(character,a.intentX,a.intentY)
        frame=Animation.frameForPalletJackPush(8,a.moving,a.jackDistance or a.distance,
            Config.palletJack.gaitPixelsPerFrame or 20)
    elseif a.moving then
        action,mirror=Catalog.action(character,"walk",a.intentX,a.intentY)
        frame=Animation.frameForDistance(8,a.distance,13)
    elseif entry.worker and a.phase=="break" and a.seatBay then
        local worker=entry.worker
        local employeeNumber=tonumber((worker.id or ""):match("EMP%-(%d+)")) or 0
        local activeAction
        if worker.breakKind=="meal" then
            activeAction="break_eat"
        else
            local breakMask=worker.breaksTaken or 0
            local restBreakCount=breakMask%2+math.floor(breakMask/4)%2+math.floor(breakMask/8)%2
            activeAction=(employeeNumber+restBreakCount)%2==0 and "break_water" or "break_coffee"
        end
        local phase=(a.idleClock or 0)%6
        if phase<4 then
            action=activeAction
            frame=Animation.frameForClock(4,phase,1.5)
        else
            action="break_idle"
            frame=Animation.frameForClock(4,phase-4,.65)
        end
        mirror=a.seatBay=="front_left" and -1 or 1
    elseif (entry.worker and a.phase=="working") or (entry.application and a.phase=="waiting") then
        if entry.worker then
            local workAction=Catalog.workAction(entry)
            if workAction then
                action,frame=workAction,Animation.frameForClock(4,a.idleClock,4)
                mirror=(character=="ferret-engineer-worker" and -1 or 1)*(a.intentX<0 and -1 or 1)
            elseif character=="cat-worker" then action="operate_"..direction;frame=a.workFrame or 1
            else action,frame="operate",1 end
        else action,mirror=Catalog.action(character,"idle",a.intentX,a.intentY);frame=Animation.frameForIdle(2,a.idleClock,.65) end
    else
        action,mirror=Catalog.action(character,"idle",a.intentX,a.intentY)
        frame=Animation.frameForIdle(2,a.idleClock,.65)
    end
    return action,frame,mirror
end
local function drawPose(entry,characterAssets,state)
    local a=entry.actor
    local character=Catalog.character(entry)
    local action,frame,mirror=Renderer.pose(entry,characterAssets)
    local ax,ay=characterAssets.getAnchor(character,action,frame)
    local scale=.30*characterAssets.getNormalization(character,action)
    if action:match("^chair_") then scale=.30*Config.characterRendering.referenceHeight/192 end
    local x,y=a.x,a.y
    if state and state.palletJack and state.palletJack.operatorEmployeeId==(entry.worker and entry.worker.id)
        and a.phase=="pushing" then
        local pose=Jack.visualPose(state,Config.palletJack)
        local hand=MotionArt.hands[character][action][frame]
        x=pose.x+pose.handleX-(hand.x-ax)*scale*mirror
        y=pose.y+pose.handleY-(hand.y-ay)*scale
    end
    return character,action,frame,mirror,ax,ay,scale,x,y
end
function Renderer.draw(entry,characterAssets,state)
    local a=entry.actor
    local character,action,frame,mirror,ax,ay,scale,x,y=drawPose(entry,characterAssets,state)
    local image,quad=characterAssets.get(character,action,frame)
    if not image then return end
    love.graphics.setColor(.02,.02,.02,.20)
    love.graphics.ellipse("fill",x,y+1,13,4)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,quad,x,y,0,scale*mirror,scale,ax,ay)
    if entry.application and a.phase=="waiting" then
        love.graphics.setColor(.96,.85,.42,1)
        love.graphics.printf("APPLICANT",a.x-44,a.y-94,88,"center")
    end
end
function Renderer.drawBubble(entry,characterAssets,state)
    local message=Speech.message(Speech.code(entry))
    if not message then return end
    local a=entry.actor
    local character,action,frame,_,_,anchorY,scale,originX,originY=drawPose(entry,characterAssets,state)
    local top
    if characterAssets.getVisibleBounds then
        local _,y=characterAssets.getVisibleBounds(character,action,frame)
        top=y
    end
    local headY=top and originY-(anchorY-top)*scale
        or originY-Config.characterRendering.referenceHeight*.30
    bubbleFont=bubbleFont or love.graphics.newFont(11)
    local width=math.min(124,math.max(52,bubbleFont:getWidth(message)+16))
    local height=22
    local x=math.max(4,math.min(Config.baseWidth-width-4,originX-width/2))
    local y=math.max(4,headY-height-9)
    local tailX=math.max(x+8,math.min(x+width-8,originX))
    love.graphics.push("all")
    love.graphics.setFont(bubbleFont)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(.035,.06,.075,.94)
    love.graphics.polygon("fill",tailX-4,y+height-1,tailX+4,y+height-1,tailX,y+height+6)
    love.graphics.rectangle("fill",x,y,width,height,5,5)
    love.graphics.setColor(.55,.82,.79,.9)
    love.graphics.rectangle("line",x,y,width,height,5,5)
    love.graphics.setColor(.96,.97,.91,1)
    love.graphics.printf(message,x+6,y+5,width-12,"center")
    love.graphics.pop()
end
function Renderer.entries(state) return Employees.actors(state) end
return Renderer
