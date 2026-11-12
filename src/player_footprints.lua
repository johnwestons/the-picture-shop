-- Short-lived, scene-local shoe prints. Samples use the same player poses as
-- world rendering and stay transient; only the surrounding floor state is saved.
local Condition=require("src.warehouse_condition")
local Prints={MAX_PER_PLAYER=48,LIFETIME=3.5,STEP_DISTANCE=17}
local tracks={}

local materials={
    water={life=3.5,alpha=.34,color={.055,.17,.19},width=2.8,length=4.3,carry=4},
    dirt={life=3.5,alpha=.29,color={.20,.125,.068},width=2.9,length=4.4,carry=4},
    dust={life=11,alpha=.25,color={.29,.235,.16},width=3.0,length=4.5},
    concrete={life=9,alpha=.075,color={.18,.18,.17},width=2.8,length=4.2},
    tile={life=8,alpha=.055,color={.20,.205,.19},width=2.7,length=4.0},
    wood={life=8,alpha=.065,color={.24,.17,.105},width=2.8,length=4.2},
}

local function inside(x,y,cx,cy,rx,ry)
    local dx,dy=(x-cx)/rx,(y-cy)/ry
    return dx*dx+dy*dy<=1
end

local function homeSurface(state,x,y)
    local Layout=require("src.home_layouts")
    local id=state and state.home and state.home.apartmentId
    if not id or not Layout.walkable(id,x,y) then return nil end
    local entry=Layout.DATA[id]
    for _,room in ipairs({"bathroom","kitchen"}) do
        local source=entry.rooms[room]
        local tx,ty=Layout.toWorld(source[1],source[2])
        if (x-tx)^2+(y-ty)^2<82^2 then return "tile" end
    end
    return "wood"
end

function Prints.surface(state,x,y,sceneId)
    sceneId=sceneId or "warehouse"
    if sceneId=="warehouse" then
        local c=Condition.of(state)
        if not c or c.mode~="story" then return "concrete" end
        if not c.cleaned.east and (inside(x,y,758,493,100,32) or inside(x,y,813,505,52,23)) then
            return "water"
        end
        if not c.cleaned.west and (inside(x,y,150,383,100,35) or inside(x,y,217,497,73,28))
            or not c.cleaned.center and (inside(x,y,433,426,90,35) or inside(x,y,605,260,62,25))
            or not c.cleaned.east and inside(x,y,846,363,64,25) then
            return "dirt"
        end
        -- The sealed slab keeps only a faint powder trace; contaminated patches
        -- leave stronger prints that carry a few steps beyond their edges.
        return "concrete"
    end

    if sceneId=="home" then return homeSurface(state,x,y) end
    if sceneId=="barn" then
        local Barn=require("src.commute.barn_interior")
        return Barn.walkable(x,y) and "dust" or nil
    end
    if sceneId=="grocery" then
        local Grocery=require("src.commute.grocery_interior")
        return Grocery.walkable(x,y) and "tile" or nil
    end
    if sceneId=="station" then
        local Station=require("src.commute.gas_station_interior")
        return Station.walkable(x,y) and "tile" or nil
    end

    local Rooms=require("src.shop_rooms")
    if sceneId=="front_left" or sceneId=="front_right" then
        local kind=Rooms.definition(state,sceneId)
        if not kind or not Rooms.walkable(x,y,sceneId,kind) then return nil end
        if Rooms.isBuilding(state,sceneId) then return "dust" end
        if kind=="breakroom" then return "wood" end
        if kind=="storage" then return "concrete" end
        return "tile"
    end
end

local function newTrack(player)
    return {x=player.x,y=player.y,scene=player.sceneId or "warehouse",side=1,entries={},carry=0}
end

local function add(track,x,y,angle,material,now)
    local entries=track.entries
    entries[#entries+1]={x=x,y=y,angle=angle,material=material,at=now,
        scene=track.scene,side=track.side}
    track.side=-track.side
    while #entries>Prints.MAX_PER_PLAYER do table.remove(entries,1) end
end

local function expire(track,now)
    for index=#track.entries,1,-1 do
        local mark=track.entries[index]
        local style=materials[mark.material] or materials.dirt
        if now-mark.at>=style.life then table.remove(track.entries,index) end
    end
end

local function updateOne(state,id,player,now)
    local scene=player.sceneId or "warehouse"
    local track=tracks[id]
    if not track then
        tracks[id]=newTrack(player)
        return
    end
    if track.scene~=scene then
        track.x,track.y=player.x,player.y
        track.scene,track.carry=scene,0
        expire(track,now)
        return
    end

    if player.moving==false then
        track.x,track.y=player.x,player.y
        track.carry=0
        expire(track,now)
        return
    end

    local dx,dy=player.x-track.x,player.y-track.y
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance>110 then
        track.x,track.y=player.x,player.y
        track.carry=0
    elseif distance>=Prints.STEP_DISTANCE then
        local steps=math.min(6,math.floor(distance/Prints.STEP_DISTANCE))
        local angle=math.atan2(dy,dx)+math.pi/2
        for i=1,steps do
            local fraction=(i*Prints.STEP_DISTANCE)/distance
            local x,y=track.x+dx*fraction,track.y+dy*fraction
            local material=Prints.surface(state,x,y,scene)
            if material then
                track.carry=(materials[material] and materials[material].carry) or 0
                track.material=material
            elseif track.carry>0 then
                material=track.material
                track.carry=track.carry-1
            end
            if material then add(track,x,y,angle,material,now) end
        end
        local fraction=(steps*Prints.STEP_DISTANCE)/distance
        track.x,track.y=track.x+dx*fraction,track.y+dy*fraction
    end
    expire(track,now)
end

function Prints.update(state,localPlayer,remotePlayers,now)
    now=now or love.timer.getTime()
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
    for id,track in pairs(tracks) do
        if not seen[id] then
            expire(track,now)
            if #track.entries==0 then tracks[id]=nil end
        end
    end
end

local function drawMark(mark,fade)
    local style=materials[mark.material] or materials.dirt
    local alpha=style.alpha*fade
    love.graphics.push()
    love.graphics.translate(mark.x,mark.y)
    love.graphics.rotate(mark.angle)
    love.graphics.translate(mark.side*3,0)
    love.graphics.setColor(style.color[1],style.color[2],style.color[3],alpha)
    love.graphics.ellipse("fill",0,-3,style.width,style.length)
    love.graphics.ellipse("fill",0,3,style.width*.82,style.length*.62)
    if mark.material=="water" then
        love.graphics.setColor(.46,.66,.65,alpha*.28)
        love.graphics.arc("line","open",0,-3,style.width*.68,math.pi*1.12,math.pi*1.88)
    elseif mark.material=="dust" then
        love.graphics.setColor(.41,.34,.24,alpha*.45)
        love.graphics.line(-1.2,-4,1.2,-4)
    end
    love.graphics.pop()
end

function Prints.draw(sceneId,now)
    if type(sceneId)=="number" then now,sceneId=sceneId,nil end
    now=now or love.timer.getTime()
    love.graphics.push("all")
    for _,track in pairs(tracks) do
        for _,mark in ipairs(track.entries) do
            if not sceneId or mark.scene==sceneId then
                local style=materials[mark.material] or materials.dirt
                local fade=math.max(0,1-(now-mark.at)/style.life)
                if fade>0 then drawMark(mark,fade) end
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
