local Preload=require("src.home_art_preload")
-- Tools are contextual presentation, never owned inventory or extra portions.
local Residents=require("src.home_residents")
local Layout=require("src.home_layouts")
local Calendar=require("src.business_calendar")
local Animation=require("src.character_animation")
local Colorways=require("src.rabbit_colorways")
local Props=require("src.home_routine_props")
local Routine={}
local actions={cook=true,prepare=true,wash=true,dishes=true,wipe=true,scrub=true,sweep=true,
    loadwash=true,unload=true,change=true,trash=true,cupwash=true,cupfill=true,
    bathe=true,toilet=true}
local hands={
    work_task={{180,134},{172,143}},work_task_north={{166,121},{163,125}},
    work_task_northeast={{170,140},{165,146}},work_task_southeast={{165,129},{163,134}},
    work_task_south={{129,134},{131,137}},
}
function Routine.get(state,player)
    if not state.home or not require("src.weekend_flow").atHome(state) or player.sceneId~="home" then return nil end
    local r=Residents.display(state,player);local a=r and r.activity
    if not a or not actions[a.kind] or (player.x-a.x)^2+(player.y-a.y)^2>4 then return nil end
    local privacyActivity=a.kind=="bathe" or a.kind=="toilet"
    if (player.character or require("src.config").player.character)~="rabbit-worker" and not privacyActivity then return nil end
    local item=a.furnitureId and require("src.home_surfaces").find(state,a.furnitureId)
    if item and (item.editor or require("src.home_surfaces").editConflict(state,item)) then return nil end
    local targetX,targetY,x,y
    local fixture=Layout.get(state).fixtures[a.fixtureId or a.target]
    if fixture then
        x,y=Layout.toWorld(unpack(fixture.approach));targetX,targetY=Layout.toWorld(fixture.x,fixture.y)
    elseif item and item.location=="floor" then
        local approach=require("src.home_furniture").targets(state,player)["furniture"..item.id]
        if not approach then return nil end
        x,y=approach.x,approach.y;targetX,targetY=item.x,item.y
    elseif a.target=="floor" then
        x,y=player.x,player.y;targetX,targetY=x+(player.facing or 1)*30,y+10
        if a.kind=="sweep" or a.kind=="trash" then
            local ix,iy=player.intentX or 0,player.intentY or 0
            if ix*ix+iy*iy<.0001 then ix,iy=player.facing or 1,0 end
            targetX,targetY=x+ix*30,y+iy*15
        end
    else return nil end
    local dx,dy=targetX-x,(targetY-y)*2
    local direction=Animation.authoredDirection(dx,dy)
    local action,mirror=Animation.directionalTaskAction("work_task",dx,dy)
    -- These two existing strips are named opposite their visible front/back
    -- three-quarter views. Register the actual drawings for household work.
    if action=="work_task_northeast" then action="work_task_southeast"
    elseif action=="work_task_southeast" then action="work_task_northeast" end
    local privacy=a.kind=="bathe" or a.kind=="toilet"
    if privacy then action,mirror=Animation.directionalIdleAction(dx,dy) end
    local seconds=math.max(0,Calendar.absoluteHours(state)-a.startedAt)*Calendar.secondsPerDay(state)/24
    local duration=math.max(.001,(a.endsAt-a.startedAt)*Calendar.secondsPerDay(state)/24)
    local routineProgress=math.max(0,math.min(1,seconds/duration))
    local frame=2+math.floor(seconds*3)%2
    local bowlX,bowlY,laundryProgress,sinkAction
    if a.kind=="cook" and item and item.kind=="stove" then
        local Art=require("src.home_cooking_art")
        local px,py,bx,by=Art.standingPose(state,direction,item)
        if px and (px-player.x)^2+(py-player.y)^2<=60^2 then
            x,y,bowlX,bowlY=px,py,bx,by
            frame=Art.frame(seconds);action="home_cook_"..direction;mirror=1
        end
    elseif a.kind=="sweep" then
        frame=require("src.home_sweep_art").frame(seconds);action="home_sweep_"..direction;mirror=1
    elseif a.kind=="trash" then
        local duration=(a.endsAt-a.startedAt)*Calendar.secondsPerDay(state)/24
        frame=require("src.home_trash_art").frame(seconds,duration);action="home_trash_"..direction;mirror=1
    elseif a.kind=="loadwash" or a.kind=="unload" then
        local Art=require("src.home_laundry_art")
        local px,py,facing=Art.standingPose(state)
        if not px then return nil end
        local duration=(a.endsAt-a.startedAt)*Calendar.secondsPerDay(state)/24
        x,y,direction=px,py,facing
        frame=Art.frame(seconds,duration,a.kind);action="home_laundry_"..direction;mirror=1
        laundryProgress=duration>0 and math.max(0,math.min(1,seconds/duration)) or 1
    elseif a.kind=="wash" or a.kind=="dishes" or a.kind=="cupwash" or a.kind=="cupfill" then
        local Art=require("src.home_washing_art")
        local fixtureName=a.fixtureId or a.target
        local px,py,facing=Art.standingPose(state,fixtureName,a.kind)
        if px then
            x,y,direction=px,py,facing
            frame=Art.frame(a.kind,seconds);action="home_sink_"..direction;mirror=1;sinkAction=a.kind
        end
    elseif a.kind=="wipe" or a.kind=="scrub" then
        local Art=require("src.home_wipe_art")
        local px,py,facing=Art.standingPose(state,a.target)
        if not px then return nil end
        x,y,direction=px,py,facing
        frame=Art.frame(seconds,a.kind);action="home_wipe_"..direction;mirror=1
    end
    return {routine=a.kind,action=action,frame=frame,mirror=mirror,direction=direction,seconds=seconds,
        duration=duration,progress=laundryProgress or routineProgress,
        x=x,y=y,groundX=x,groundY=y,depth=y,item=item,bowlX=bowlX,bowlY=bowlY,sinkAction=sinkAction,
        privacy=privacy,privacyKind=privacy and a.kind or nil,
        bounds=privacy and {x-62,y-112,x+62,y+14}
            or (a.kind=="sweep" or a.kind=="trash" or bowlX) and {x-105,y-130,x+105,y+18}
            or (a.kind=="loadwash" or a.kind=="unload" or sinkAction) and {x-90,y-115,x+90,y+18}
            or {x-58,y-90,x+58,y+10}}
end
local function tools(p,hx,hy)
    local kind=p.routine;local wave=math.sin(p.seconds*5)
    if kind=="cook" then Props.draw(2,hx,hy,.065,p.mirror,wave*.13,270,190)
    elseif kind=="prepare" then
        local t=p.progress or 0;local reach=math.sin(p.seconds*3)*.8
        if t<.76 then
            require("src.home_held_art").draw("ingredients",p.direction,hx,hy+3+reach,28)
        else
            local settle=math.min(1,(t-.76)/.14)
            require("src.home_held_art").draw("sandwich",p.direction,hx+reach,hy+2+settle*2,18)
        end
    elseif kind=="dishes" then Props.draw(4,hx,hy+4,.065,p.mirror)
    elseif kind=="wipe" or kind=="scrub" then Props.draw(3,hx+wave*2,hy+4,.055,p.mirror)
    elseif kind=="sweep" then Props.draw(5,hx,hy,.16,p.mirror,wave*.05,210,240)
    elseif kind=="change" then
        if p.progress<.24 or p.progress>.78 then
            local lift=math.sin(p.seconds*4)*1.8
            require("src.home_held_art").draw("towel",p.direction,hx,hy+3-lift,26)
        end
    elseif kind=="trash" then Props.draw(7,hx,hy,.09,p.mirror,0,190,110)
    elseif kind=="cupwash" or kind=="cupfill" then
        require("src.home_furniture_art").draw({kind="cup",direction=p.direction,x=hx,y=hy+6})
    end
    if kind=="wash" or kind=="dishes" or kind=="cupwash" or kind=="cupfill" then
        love.graphics.push("all");love.graphics.setShader()
        for i=1,3 do
            local drop=(p.seconds*9+i*4)%12
            love.graphics.setColor(.52,.82,.94,.7*(1-drop/16))
            love.graphics.line(hx+(i-2)*3,hy+drop,hx+(i-2)*3,hy+drop+2)
        end
        love.graphics.pop()
    end
end
local function changeGlow(p)
    if p.routine~="change" or p.progress<.24 or p.progress>.78 then return end
    -- Draw over the character to mark the short change beat.
    local pulse=.45+.35*math.sin(p.seconds*9)
    love.graphics.setColor(.82,.94,1,pulse)
    for i=1,3 do
        local x=p.x+(i-2)*7+math.sin(p.seconds*3+i)*2
        local y=p.y-30+math.cos(p.seconds*4+i)*3
        love.graphics.line(x-2,y,x+2,y);love.graphics.line(x,y-2,x,y+2)
    end
    love.graphics.setColor(1,1,1,1)
end
function Routine.draw(p,player,characters)
    if p.routine=="prepare" or p.routine=="change" then
        if not Preload.want("held",function()
            local Held=require("src.home_held_art")
            if p.routine=="change" then return Held.prewarm("towel") end
            local a,b=Held.prewarm("ingredients"),Held.prewarm("sandwich")
            return a and b
        end) then return false end
    end
    if p.privacy then return require("src.home_privacy_art").draw(p,player,characters) end
    if p.routine=="cook" and p.bowlX then
        return require("src.home_cooking_art").draw(p.direction,p.frame,p.x,p.y,player,true,p.bowlX,p.bowlY)~=false
    end
    if p.routine=="sweep" then return require("src.home_sweep_art").draw(p.direction,p.frame,p.x,p.y,player)~=false end
    if p.routine=="trash" then return require("src.home_trash_art").draw(p.direction,p.frame,p.x,p.y,player)~=false end
    if p.routine=="loadwash" or p.routine=="unload" then
        return require("src.home_laundry_art").draw(p.direction,p.frame,p.x,p.y,player,p.routine,p.progress)~=false
    end
    if p.sinkAction then
        return require("src.home_washing_art").draw(p.sinkAction,p.direction,p.frame,p.x,p.y,player,p.seconds)~=false
    end
    if p.routine=="wipe" or p.routine=="scrub" then return require("src.home_wipe_art").draw(p.direction,p.frame,p.x,p.y,player)~=false end
    local action=characters.resolveAction("rabbit-worker",p.action)
    if action~=p.action then Preload.wait();return false end
    local image,quad=characters.get("rabbit-worker",action,p.frame);if not image then Preload.wait();return false end
    local ax,ay=characters.getAnchor("rabbit-worker",action,p.frame)
    local scale=require("src.config").player.drawScale*characters.getNormalization("rabbit-worker",action)
    local hand=(hands[p.action] or hands.work_task)[p.frame-1]
    local hx,hy=p.x+(hand[1]-ax)*scale*p.mirror,p.y+(hand[2]-ay)*scale
    local behind=p.direction=="north" or p.direction=="northeast" or p.direction=="northwest"
    love.graphics.push("all");love.graphics.setColor(1,1,1,1);love.graphics.setShader()
    if behind then tools(p,hx,hy) end
    Colorways.draw(image,quad,p.x,p.y,0,scale*p.mirror,scale,ax,ay,0,0,player.furColorway,player.overallsColorway)
    if not behind then tools(p,hx,hy) end
    changeGlow(p)
    love.graphics.pop();return true
end
function Routine.furniture(state,item)
    if item.kind~="stove" then return end
    for _,r in pairs(state.home.residents or {}) do
        if r.activity and r.activity.kind=="cook" and r.activity.furnitureId==item.id then
            local Art=require("src.home_cooking_art");local x,y=Art.stoveTop(item)
            Art.drawPan(item.direction,x,y)
            local clock=math.max(0,Calendar.absoluteHours(state)-r.activity.startedAt)*Calendar.secondsPerDay(state)/24
            love.graphics.push("all");love.graphics.setShader()
            for i=1,3 do
                local rise=(clock*5+i*5)%18;love.graphics.setColor(.85,.89,.86,.3*(1-rise/18))
                love.graphics.ellipse("line",x+(i-2)*4+math.sin(clock+i),y-7-rise,2,3)
            end
            love.graphics.pop();return
        end
    end
end
function Routine.release() Props.release();require("src.home_sweep_art").release();require("src.home_cooking_art").release();require("src.home_trash_art").release();require("src.home_wipe_art").release();require("src.home_laundry_art").release();require("src.home_washing_art").release();require("src.home_privacy_art").release() end
return Routine
