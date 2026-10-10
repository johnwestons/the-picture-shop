-- Shared pose timing keeps animation impact aligned with the host hit window.
local Art={CELL=256,ANCHOR_X=128,ANCHOR_Y=240,HEIGHT=180}
Art.ROSTER={mouse={name="MOUSE",subtitle="Frontier mechanic"},fox={name="FOX",subtitle="Rail-yard tinkerer"}}
local images,quads={},{}
local DIR="assets/generated/critter-kombat-v2/"
local function frameAt(time,count,duration,loop)
    local progress=math.max(0,time or 0)/duration
    return (loop and math.floor(progress*count)%count or math.min(count-1,math.floor(progress*count)))+1
end
function Art.pose(f)
    local action,time=f.action,f.actionTime or 0
    if action=="punch" or action=="kick" then
        local startup,activeEnd,duration=.11,.22,.33
        if action=="kick" then startup,activeEnd,duration=.20,.34,.52 end
        local frame
        if time<startup then frame=frameAt(time,3,startup)
        elseif time<=activeEnd then frame=4
        else frame=4+frameAt(time-activeEnd,2,duration-activeEnd) end
        local row=(action=="punch" and 0 or 2)+((f.variant or 1)-1)
        return "attacks",row*6+frame,6,4
    end
    local row,count,duration,loop=0,4,.8,true
    if action=="walk" then row,duration=1,.48
    elseif action=="jump" then row,duration,loop=2,1.14,false
    elseif action=="block" then row,duration,loop=3,.20,false
    elseif action=="hit" then row,duration,loop=4,.23,false
    elseif action=="knockout" then return "support",21+math.min(1,math.floor(time/.25)),4,6
    elseif action=="victory" then return "support",23+math.floor(time*3)%2,4,6 end
    return "support",row*4+frameAt(time,count,duration,loop),4,6
end
function Art.draw(f,x,y,scale)
    local sheet,frame,cols,rows=Art.pose(f)
    local character=Art.ROSTER[f.character] and f.character or "mouse"
    local key=character.."-"..sheet
    if not images[key] then
        images[key]=love.graphics.newImage(DIR..key..".png")
        images[key]:setFilter("nearest","nearest")
    end
    local qkey=sheet..":"..frame
    if not quads[qkey] then
        quads[qkey]=love.graphics.newQuad((frame-1)%cols*Art.CELL,math.floor((frame-1)/cols)*Art.CELL,
            Art.CELL,Art.CELL,cols*Art.CELL,rows*Art.CELL)
    end
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(images[key],quads[qkey],x,y,0,(f.face or 1)*scale,scale,Art.ANCHOR_X,Art.ANCHOR_Y)
end
function Art.clear()
    for _,sprite in pairs(images) do sprite:release() end
    images,quads={},{}
end
return Art
