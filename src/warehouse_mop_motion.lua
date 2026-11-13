-- Samples the authored mop head's floor contact as its six-frame sweep plays.
local Condition=require("src.warehouse_condition")
local Mop=require("src.home_mop_art")
local Motion={}

function Motion.contactAt(x,y,direction,seconds)
    local contact=Mop.contact(direction,Mop.frame(seconds))
    if not contact or not contact.valid then return nil end
    local angle=contact.floorAngle
    while angle>math.pi do angle=angle-math.pi*2 end
    while angle< -math.pi do angle=angle+math.pi*2 end
    return x+contact.floorX,y+contact.floorY,angle
end

local function record(state,task,player,x,y,seconds,deferCompletion)
    local cx,cy,angle=Motion.contactAt(x,y,task.direction,seconds)
    if not cx then return false,false end
    local previous=task.lastWipe
    if previous and seconds-(previous.time or -1)<.05
        and (cx-previous.x)^2+(cy-previous.y)^2<4 then return false,false end
    local changed,done=Condition.mopContact(state,task.puddle,cx,cy,angle,deferCompletion)
    if changed then task.lastWipe={x=cx,y=cy,time=seconds} end
    return changed,done
end

function Motion.advance(state,task,player,dt,startX,startY,endX,endY,deferCompletion)
    dt=math.max(0,tonumber(dt) or 0)
    local elapsed=math.max(0,tonumber(task.elapsed) or 0)
    startX,startY=tonumber(startX) or player.x,tonumber(startY) or player.y
    endX,endY=tonumber(endX) or player.x,tonumber(endY) or player.y
    local stamps,done=0,false
    if not task.contactStarted then
        local changed,finished=record(state,task,player,startX,startY,elapsed,deferCompletion)
        if changed then stamps=stamps+1 end
        if finished then return stamps,true end
        task.contactStarted=true
    end
    local finish=elapsed+dt
    local fps=Mop.fps
    local firstTick=math.floor(elapsed*fps+1e-8)+1
    local lastTick=math.floor(finish*fps+1e-8)
    for tick=firstTick,lastTick do
        local moment=tick/fps
        local fraction=dt>0 and math.max(0,math.min(1,(moment-elapsed)/dt)) or 1
        local x=startX+(endX-startX)*fraction
        local y=startY+(endY-startY)*fraction
        local changed,finished=record(state,task,player,x,y,moment+1e-6,deferCompletion)
        if changed then stamps=stamps+1 end
        if finished then done=true;break end
    end
    local moveX,moveY=task.moveX or startX,task.moveY or startY
    local dx,dy=endX-moveX,endY-moveY
    local distance=math.sqrt(dx*dx+dy*dy)
    if not done and distance>=8 then
        local steps=math.floor(distance/8)
        for index=1,steps do
            local fraction=math.min(1,index*8/distance)
            local x,y=moveX+dx*fraction,moveY+dy*fraction
            local seconds=elapsed+dt*fraction
            local changed,finished=record(state,task,player,x,y,seconds,deferCompletion)
            if changed then stamps=stamps+1 end
            if finished then done=true;break end
        end
        local consumed=math.min(1,steps*8/distance)
        task.moveX=moveX+dx*consumed
        task.moveY=moveY+dy*consumed
    end
    if done then task.moveX,task.moveY=endX,endY
    elseif not task.moveX then task.moveX,task.moveY=moveX,moveY end
    task.elapsed=finish
    return stamps,done
end

return Motion
