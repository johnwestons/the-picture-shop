-- Shared screen-space cover, animation and hit geometry for host and guests.
local Enemy={}
-- Share the imported Last Stand's cover cadence with the main cabinet mission.
local coverSeconds=require('src.arcade_frontier.last_stand_tuning').coverSeconds
Enemy.MODES={duck=true,rise=true,peek=true,attack=true,fire=true,lower=true,moving=true}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
function Enemy.isBoat(session) return session.level==3 and session.stop>=4 end
function Enemy.layout(level,stop)
    local count=2+((level+stop)%2)
    local covers={}
    for tier=1,3 do for lane=1,count do
        local x=count==2 and (lane==1 and 240 or 720) or 160+(lane-1)*320
        local sign=lane%2==1 and 1 or -1
        x=x+(tier==2 and (count==2 and 140*sign or 80) or tier==3 and -10 or 0)
        local y=370+(tier-1)*60+(lane%2)*12
        covers[#covers+1]={x=x,y=y,tier=tier,lane=lane}
    end end
    return covers,count
end
function Enemy.scale(y) return .78+clamp((y-346)/140,0,1)*.38 end
function Enemy.posture(enemy)
    local p=clamp(enemy.posture or 0,0,1)
    return p*p*(3-2*p)
end
function Enemy.body(enemy)
    local scale=Enemy.scale(enemy.y)
    local posture=Enemy.posture(enemy)
    local sink=(1-posture)*100*scale
    return {x=enemy.x,y=enemy.y+sink,scale=scale,
        top=enemy.y-160*scale+sink,left=enemy.x-50*scale,
        right=enemy.x+55*scale,bottom=enemy.y-10*scale+sink}
end
function Enemy.cover(cover,boat)
    local scale=Enemy.scale(cover.y)
    local width=(boat and 214 or 154)*scale
    local height=(boat and 92 or 96)*scale
    local bottom=cover.y+(boat and 20*scale or 0)
    return {x=cover.x,y=bottom,scale=scale,left=cover.x-width/2,
        right=cover.x+width/2,top=bottom-height,bottom=bottom,width=width,height=height}
end
function Enemy.barrel(barrel)
    return {left=barrel.x-40,right=barrel.x+40,top=barrel.y-27,bottom=barrel.y+70,depth=barrel.y+70}
end
function Enemy.occluded(session,enemy,x,y)
    if Enemy.isBoat(session) then
        for _,other in ipairs(session.enemies) do if other.hp>0 then
            local c=Enemy.cover(other,true)
            if other.y>=enemy.y-1 and x>=c.left and x<=c.right and y>=c.top and y<=c.bottom then return true end
        end end
    else
        local covers=Enemy.layout(session.level,session.stop)
        for _,cover in ipairs(covers) do
            local c=Enemy.cover(cover)
            if cover.y>=enemy.y-1 and x>=c.left and x<=c.right and y>=c.top and y<=c.bottom then return true end
        end
    end
    return false
end
function Enemy.hittable(session,enemy,x,y)
    if enemy.hp<=0 or (enemy.posture or 0)<.05 then return false end
    local b=Enemy.body(enemy)
    return x>=b.left and x<=b.right and y>=b.top and y<=b.bottom
        and not Enemy.occluded(session,enemy,x,y)
end
function Enemy.new(index,level,stop)
    local covers=Enemy.layout(level,stop)
    local c=covers[index]
    return {x=c.x,y=c.y,hp=level==3 and 2 or 1,kind=((index+stop+level-3)%4)+1,
        mode='duck',timer=.75+index*.45,coverId=index,posture=0,travel=0,speed=0,shot=0}
end
local function enter(enemy,mode,duration)
    enemy.mode=mode;enemy.timer=duration
end
function Enemy.update(enemy,session,dt)
    if enemy.hp<=0 then return end
    enemy.shot=math.max(0,enemy.shot-dt)
    local covers,count=Enemy.layout(session.level,session.stop)
    if enemy.mode=='moving' then
        local target=covers[enemy.moveTarget]
        local dx,dy=target.x-enemy.x,target.y-enemy.y
        local distance=math.sqrt(dx*dx+dy*dy)
        if distance<.01 then
            enemy.x=target.x;enemy.y=target.y;enemy.coverId=enemy.moveTarget
            enemy.moveTarget=nil;enemy.speed=0;enter(enemy,'lower',coverSeconds)
        else
            -- Gait follows actual displacement, including acceleration and braking.
            local gait=1+.06*math.sin(enemy.travel/60*math.pi*4)
            enemy.speed=math.min(94*gait,enemy.speed+240*gait*dt,math.sqrt(2*280*distance))
            local step=math.min(distance,enemy.speed*dt)
            enemy.x=enemy.x+dx/distance*step;enemy.y=enemy.y+dy/distance*step
            enemy.travel=enemy.travel+step/Enemy.scale(enemy.y)
        end
        return
    end
    enemy.timer=enemy.timer-dt
    if enemy.mode=='rise' then enemy.posture=clamp(1-enemy.timer/coverSeconds,0,1)
    elseif enemy.mode=='lower' then enemy.posture=clamp(enemy.timer/coverSeconds,0,1) end
    if enemy.timer>0 then return end
    if enemy.mode=='duck' then
        if enemy.advance and enemy.coverId+count<=#covers then enemy.moveTarget=enemy.coverId+count end
        enemy.advance=false;enter(enemy,'rise',coverSeconds)
    elseif enemy.mode=='rise' then
        enemy.posture=1
        if enemy.moveTarget then enemy.speed=0;enter(enemy,'moving',0)
        else enter(enemy,'peek',.8) end
    elseif enemy.mode=='peek' then enter(enemy,'attack',.6)
    elseif enemy.mode=='attack' then
        for _,player in pairs(session.players) do
            if not player.covered then player.hp=math.max(0,player.hp-1) end
        end
        enemy.shot=.22;enemy.advance=true;enter(enemy,'fire',.22)
    elseif enemy.mode=='fire' then enter(enemy,'lower',coverSeconds)
    elseif enemy.mode=='lower' then
        enemy.posture=0;enter(enemy,'duck',.65+(enemy.kind-1)*.12)
    end
end
return Enemy
