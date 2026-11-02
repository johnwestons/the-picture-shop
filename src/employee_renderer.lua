local Employees=require("src.employees")
local Animation=require("src.character_animation")
local Catalog=require("src.worker_catalog")
local Speech=require("src.employee_speech")
local Config=require("src.config")
local Jack=require("src.pallet_jack")
local MotionArt=require("src.employee_motion_art")
local WorkPresentation=require("src.employee_work_presentation")
local EmployeeHighFive=require("src.employee_high_five")
local Renderer={}
local bubbleFont
local function gaitFrameCount(assets,character,action)
    local count=assets and assets.getFrameCount and assets.getFrameCount(character,action)
    return count and count>0 and count or 8
end
function Renderer.pose(entry,characterAssets)
    local a=entry.actor
    local action,frame
    local character=Catalog.character(entry)
    local mirror=1
    local direction=Animation.authoredDirection(a.intentX,a.intentY)
    local workAction,workFrame=WorkPresentation.pose(a)
    local highFive=entry.worker and EmployeeHighFive.get(entry.worker.id)
    if highFive then
        action="idle"
        frame=1
        mirror=highFive.partnerX<a.x and -1 or 1
    elseif entry.worker and a.phase=="pushing" then
        action,mirror=Catalog.pushAction(character,a.intentX,a.intentY)
        frame=Animation.frameForPalletJackPush(gaitFrameCount(characterAssets,character,action),a.moving,a.jackDistance or a.distance,
            Config.palletJack.gaitPixelsPerFrame or 20)
    elseif a.moving then
        action,mirror=Catalog.action(character,"walk",a.intentX,a.intentY)
        frame=Animation.frameForGait(gaitFrameCount(characterAssets,character,action),a.distance,Catalog.motion.walkPixelsPerFrame)
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
    elseif entry.worker and workAction then
        action,frame=workAction,workFrame
        mirror=(character=="ferret-engineer-worker" and -1 or 1)*(a.intentX<0 and -1 or 1)
    elseif (entry.worker and a.phase=="working") or (entry.application and a.phase=="waiting") then
        if entry.worker then
            local workAction=Catalog.workAction(entry)
            if workAction then
                local expanded=require("src.worker_work_art").paths[character]
                local frames=expanded and expanded[workAction] and {1,2,workAction=="work_wrapping" and 3 or 4,workAction=="work_wrapping" and 5 or 6} or {1,2,3,4}
                action,frame=workAction,frames[math.max(1,math.min(4,a.workFrame or 1))]
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
    if characterAssets.resolveAction then
        local resolved=characterAssets.resolveAction(character,action)
        if resolved~=action then action,frame=resolved,1 end
    end
    local ax,ay=characterAssets.getAnchor(character,action,frame)
    local scale=.30*characterAssets.getNormalization(character,action)
    if action:match("^chair_") then scale=.30*Config.characterRendering.referenceHeight/192 end
    local x,y=a.x,a.y
    local fleet=require("src.pallet_jack_fleet")
    local jack=state and entry.worker and fleet.owned(state,entry.worker.id)
    if jack and a.phase=="pushing" and MotionArt.hands[character]
        and MotionArt.hands[character][action] then
        local pose=Jack.visualPose(fleet.view(state,jack),Config.palletJack)
        local hand=MotionArt.hands[character][action][frame]
        x=pose.x+pose.handleX-(hand.x-ax)*scale*mirror
        y=pose.y+pose.handleY-(hand.y-ay)*scale
    end
    return character,action,frame,mirror,ax,ay,scale,x,y
end

local function highFiveFur(character)
    if character=="cat-worker" then return .24,.23,.22 end
    if character=="tinker-fox-worker" then return .78,.39,.17 end
    return .57,.50,.40
end

local function drawHighFiveArm(character,animation,actor,mirror,ax,ay,scale,x,y)
    local frame=Animation.frameForHighFive(8,animation.elapsed,animation.duration)
    local poses={
        [1]={ lift=0, reach=0 },
        [2]={ lift=.20, reach=.08 },
        [3]={ lift=.55, reach=.32 },
        [4]={ lift=.88, reach=.78 },
        [5]={ lift=1, reach=1 },
        [6]={ lift=1, reach=1 },
        [7]={ lift=.68, reach=.48 },
        [8]={ lift=.24, reach=.15 },
    }
    local pose=poses[frame]
    if not pose or pose.lift<=0 then return end

    -- Draw in the character sprite's local 256px frame so the hand follows
    -- the employee's facing and world scale without changing their species.
    local sx,sy=137,145
    local ex=142+pose.reach*12
    local ey=137-pose.lift*40
    local hx=145+pose.reach*49
    local hy=137-pose.lift*70
    local red,green,blue=highFiveFur(character)
    love.graphics.push("all")
    love.graphics.translate(x,y)
    love.graphics.scale(scale*mirror,scale)
    love.graphics.translate(-ax,-ay)
    love.graphics.setLineWidth(18)
    love.graphics.setColor(.12,.09,.08,1)
    love.graphics.line(sx,sy,ex,ey,hx,hy)
    love.graphics.circle("fill",ex,ey,9)
    love.graphics.ellipse("fill",hx,hy,13,10)
    love.graphics.setLineWidth(11)
    love.graphics.setColor(red,green,blue,1)
    love.graphics.line(sx,sy,ex,ey,hx,hy)
    love.graphics.circle("fill",ex,ey,5.5)
    love.graphics.ellipse("fill",hx,hy,9,7)
    if frame==5 or frame==6 then
        love.graphics.setColor(1,.84,.34,.95)
        love.graphics.setLineWidth(3)
        for _,ray in ipairs({
            {hx,hy-19,hx,hy-12},{hx+17,hy-8,hx+11,hy-5},
            {hx+14,hy+10,hx+9,hy+6},{hx-12,hy-12,hx-8,hy-7},
        }) do love.graphics.line(ray[1],ray[2],ray[3],ray[4]) end
    end
    love.graphics.pop()
end

function Renderer.draw(entry,characterAssets,state)
    local a=entry.actor
    local character,action,frame,mirror,ax,ay,scale,x,y=drawPose(entry,characterAssets,state)
    local image,quad=characterAssets.get(character,action,frame)
    if not image then return end
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,quad,x,y,0,scale*mirror,scale,ax,ay)
    local highFive=entry.worker and EmployeeHighFive.get(entry.worker.id)
    if highFive then drawHighFiveArm(character,highFive,a,mirror,ax,ay,scale,x,y) end
    if entry.application and a.phase=="waiting" then
        love.graphics.setColor(.96,.85,.42,1)
        love.graphics.printf("APPLICANT",a.x-44,a.y-94,88,"center")
    end
end
function Renderer.bubbleLayout(message,font)
    local width=math.min(176,math.max(52,font:getWidth(message)+16))
    local _,lines=font:getWrap(message,width-12)
    local height=math.max(22,math.ceil(#lines*font:getHeight()*font:getLineHeight())+10)
    return width,height
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
    local width,height=Renderer.bubbleLayout(message,bubbleFont)
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
