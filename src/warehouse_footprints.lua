-- Short, local visual trails. Positions come from the same player poses used
-- for world rendering; no save or network state is needed.
local Condition=require("src.warehouse_condition")
local Prints={MAX_PER_PLAYER=5,LIFETIME=3.5,STEP_DISTANCE=17}
local tracks={}
local function inside(x,y,cx,cy,rx,ry)
    local dx,dy=(x-cx)/rx,(y-cy)/ry
    return dx*dx+dy*dy<=1
end
function Prints.surface(state,x,y)
    local c=Condition.of(state)
    if not c or c.mode~="story" then return nil end
    if not c.cleaned.east and (inside(x,y,758,493,100,32) or inside(x,y,813,505,52,23)) then
        return "water"
    end
    if not c.cleaned.west and (inside(x,y,150,383,100,35) or inside(x,y,217,497,73,28))
        or not c.cleaned.center and (inside(x,y,433,426,90,35) or inside(x,y,605,260,62,25))
        or not c.cleaned.east and inside(x,y,846,363,64,25) then
        return "dirt"
    end
end
local function add(track,x,y,angle,material,now)
    local entries=track.entries
    entries[#entries+1]={x=x,y=y,angle=angle,material=material,at=now,side=track.side}
    track.side=-track.side
    while #entries>Prints.MAX_PER_PLAYER do table.remove(entries,1) end
end
local function updateOne(state,id,player,now)
    local track=tracks[id]
    if not track then
        tracks[id]={x=player.x,y=player.y,scene=player.sceneId,side=1,entries={},carry=0}
        return
    end
    if player.sceneId~="warehouse" or track.scene~="warehouse" then
        tracks[id]={x=player.x,y=player.y,scene=player.sceneId,side=1,entries={},carry=0}
        return
    end
    local dx,dy=player.x-track.x,player.y-track.y
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance>110 then
        track.x,track.y=player.x,player.y
        track.carry=0
        return
    end
    if distance>=Prints.STEP_DISTANCE then
        local steps=math.min(5,math.floor(distance/Prints.STEP_DISTANCE))
        local angle=math.atan2(dy,dx)+math.pi/2
        for i=1,steps do
            local fraction=(i*Prints.STEP_DISTANCE)/distance
            local x,y=track.x+dx*fraction,track.y+dy*fraction
            local material=Prints.surface(state,x,y)
            if material then track.carry=4;track.material=material
            elseif track.carry>0 then material=track.material;track.carry=track.carry-1 end
            if material then add(track,x,y,angle,material,now) end
        end
        local fraction=(steps*Prints.STEP_DISTANCE)/distance
        track.x,track.y=track.x+dx*fraction,track.y+dy*fraction
    end
    for index=#track.entries,1,-1 do
        if now-track.entries[index].at>=Prints.LIFETIME then table.remove(track.entries,index) end
    end
end
function Prints.update(state,localPlayer,remotePlayers,now)
    now=now or love.timer.getTime()
    local c=Condition.of(state)
    if not c or c.mode~="story" then tracks={};return end
    if type(localPlayer)=="table" and type(localPlayer.x)=="number" and type(localPlayer.y)=="number" then
        updateOne(state,"local",localPlayer,now)
    end
    local seen={["local"]=true}
    for index,player in ipairs(remotePlayers or {}) do
        if type(player)=="table" and type(player.x)=="number" and type(player.y)=="number" then
            local id="remote:"..tostring(player.id or index)
            seen[id]=true
            updateOne(state,id,player,now)
        end
    end
    for id in pairs(tracks) do if not seen[id] then tracks[id]=nil end end
end
function Prints.draw(now)
    now=now or love.timer.getTime()
    love.graphics.push("all")
    for _,track in pairs(tracks) do
        for _,mark in ipairs(track.entries) do
            local fade=math.max(0,1-(now-mark.at)/Prints.LIFETIME)
            if fade>0 then
                local water=mark.material=="water"
                love.graphics.setColor(water and .08 or .19,water and .25 or .16,water and .29 or .10,
                    fade*(water and .32 or .27))
                love.graphics.push()
                love.graphics.translate(mark.x,mark.y)
                love.graphics.rotate(mark.angle)
                love.graphics.translate(mark.side*3,0)
                love.graphics.ellipse("fill",0,-3,2.9,4.2)
                love.graphics.ellipse("fill",0,3,2.4,2.4)
                love.graphics.pop()
            end
        end
    end
    love.graphics.pop()
end
function Prints.count(id)
    local track=tracks[id or "local"]
    return track and #track.entries or 0
end
function Prints.reset() tracks={} end
return Prints
