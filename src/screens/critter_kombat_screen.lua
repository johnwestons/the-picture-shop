-- Full-screen local controls and presentation; match outcomes come from the host.
local Kombat=require("src.critter_kombat")
local Screen={held={},touches={}}
local DIR="assets/generated/breakroom-games-v1/"
local images,quads={},{}
local stageQuad
local CELL=362
local buttons={
    solo={91,568,154,43},versus={251,568,154,43},join={411,568,104,43},
    leave={811,35,94,39},left={90,614,70,48},right={166,614,70,48},
    jump={490,614,76,48},punch={572,614,86,48},kick={664,614,78,48},block={748,614,81,48},
}
local labels={solo="1  SOLO",versus="2  VERSUS",join="3  JOIN",leave="EXIT",
    left="LEFT",right="RIGHT",jump="JUMP",punch="PUNCH",kick="KICK",block="BLOCK"}
local function inside(x,y,rect)
    return x>=rect[1] and x<=rect[1]+rect[3] and y>=rect[2] and y<=rect[2]+rect[4]
end
local function image(name)
    if images[name] then return images[name] end
    local path=DIR..name..".png"
    if not love.filesystem.getInfo(path) then return nil end
    local result=love.graphics.newImage(path)
    result:setFilter("nearest","nearest")
    images[name]=result
    return result
end
local function matchFor(runtime)
    local bay=runtime.state.roomGameBay
    if runtime.multiplayer:isClient() then
        for _,match in ipairs(runtime.multiplayer:fightSnapshot()) do
            if match.bayId==bay then return match end
        end
        return nil
    end
    return Kombat.matches[bay]
end
function Screen.enter(runtime,bayId)
    runtime.state.roomGameBay=bayId
    runtime.state.screen="critter_kombat"
    runtime.state.message="Choose a match, then move and fight."
    Screen.held={};Screen.touches={}
end
function Screen.command(runtime,action)
    local okay,code,message
    if runtime.multiplayer:isClient() then
        okay,message=runtime.multiplayer:requestInteraction("roomGame","critter_kombat:"..action)
    else
        okay,code,message=Kombat.command(runtime.state,runtime.World.player,action)
    end
    runtime.state.message=message or (okay and "Waiting for the host..." or "Arcade unavailable.")
    return okay
end
function Screen.leave(runtime)
    local match=matchFor(runtime)
    local id=tonumber(runtime.World.player.id) or 1
    if match and (match.leftId==id or match.rightId==id) then Screen.command(runtime,"leave") end
    runtime.state.screen="world"
    runtime.state.roomGameBay=nil
    Screen.held={};Screen.touches={}
end
function Screen.keypressed(runtime,key)
    if key=="escape" then Screen.leave(runtime);return true end
    if key=="1" then Screen.command(runtime,"start_solo");return true end
    if key=="2" then Screen.command(runtime,"start_versus");return true end
    if key=="3" then Screen.command(runtime,"join");return true end
    return false
end
function Screen.mousepressed(runtime,x,y,button)
    if button~=1 then return false end
    for name,rect in pairs(buttons) do
        if inside(x,y,rect) then
            if name=="leave" then Screen.leave(runtime)
            elseif name=="solo" then Screen.command(runtime,"start_solo")
            elseif name=="versus" then Screen.command(runtime,"start_versus")
            elseif name=="join" then Screen.command(runtime,"join")
            else Screen.held[name]=true;Screen.mouseButton=name end
            return true
        end
    end
    return false
end
function Screen.mousereleased()
    if Screen.mouseButton then Screen.held[Screen.mouseButton]=nil end
    Screen.mouseButton=nil
end
function Screen.touchpressed(runtime,id,sx,sy)
    local x,y=runtime.Viewport.toGame(sx,sy,runtime.Config.baseWidth,
        runtime.Config.baseHeight,runtime.App.officeFitsScreen())
    for name,rect in pairs(buttons) do
        if inside(x,y,rect) then
            if name=="leave" then Screen.leave(runtime)
            elseif name=="solo" then Screen.command(runtime,"start_solo")
            elseif name=="versus" then Screen.command(runtime,"start_versus")
            elseif name=="join" then Screen.command(runtime,"join")
            else Screen.touches[id]=name end
            return true
        end
    end
    return true
end
function Screen.touchmoved(runtime,id,sx,sy)
    local name=Screen.touches[id]
    if not name then return false end
    local x,y=runtime.Viewport.toGame(sx,sy,runtime.Config.baseWidth,
        runtime.Config.baseHeight,runtime.App.officeFitsScreen())
    if not inside(x,y,buttons[name]) then Screen.touches[id]=nil end
    return true
end
function Screen.touchreleased(id)
    Screen.touches[id]=nil
    return true
end
function Screen.controls(runtime)
    local match=matchFor(runtime)
    local id=tonumber(runtime.World.player.id) or 1
    if not match or match.phase~="playing" or id~=match.leftId and id~=match.rightId then
        return 0,0
    end
    local active={}
    for name,value in pairs(Screen.held) do if value then active[name]=true end end
    for _,name in pairs(Screen.touches) do active[name]=true end
    local keyboard=love.keyboard
    local function down(name,...)
        return active[name] or keyboard.isDown(...)
    end
    local x=(down("right","d","right") and 1 or 0)-(down("left","a","left") and 1 or 0)
    local bits=(down("jump","space","w","up") and 1 or 0)
        +(down("punch","j") and 2 or 0)
        +(down("kick","k") and 4 or 0)
        +(down("block","l","s","down") and 8 or 0)
    return x,bits
end
local function frame(f)
    if f.action=="walk" then return math.floor(f.actionTime*8)%2==0 and 2 or 3 end
    if f.action=="jump" then return 4 end
    if f.action=="punch" then return f.actionTime<.11 and 5 or 6 end
    if f.action=="kick" then return f.actionTime<.20 and 7 or 8 end
    return ({idle=1,block=9,hit=10,knockout=11,victory=12})[f.action] or 1
end
local function drawFighter(spriteName,f)
    local sprite=image(spriteName)
    if not sprite then return end
    local number=frame(f)
    local quad=quads[number]
    if not quad then
        quad=love.graphics.newQuad(((number-1)%4)*CELL,math.floor((number-1)/4)*CELL,
            CELL,CELL,sprite:getWidth(),sprite:getHeight())
        quads[number]=quad
    end
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(sprite,quad,80+f.x,510-f.z,0,f.face*.52,.52,CELL/2,CELL)
end
local function drawButton(name,enabled)
    local r=buttons[name]
    love.graphics.setColor(enabled and .14 or .055,enabled and .25 or .10,.25,.96)
    love.graphics.rectangle("fill",r[1],r[2],r[3],r[4],5)
    love.graphics.setColor(enabled and .96 or .46,enabled and .81 or .49,.42,1)
    love.graphics.rectangle("line",r[1],r[2],r[3],r[4],5)
    love.graphics.printf(labels[name],r[1],r[2]+(r[4]-14)/2,r[3],"center")
end
function Screen.draw(runtime)
    local match=matchFor(runtime)
    local id=tonumber(runtime.World.player.id) or 1
    love.graphics.push("all")
    love.graphics.setColor(.025,.035,.055,1)
    love.graphics.rectangle("fill",0,0,960,678)
    local stage=image("critter-kombat-rail-yard")
    if stage then
        -- Crop a slightly enlarged backdrop around the fighters for a small
        -- horizontal camera track while keeping the combat arena fixed.
        local sourceWidth=stage:getWidth()/1.12
        local midpoint=match and (match.left.x+match.right.x)/2 or 400
        local sourceX=math.max(0,math.min(stage:getWidth()-sourceWidth,
            (stage:getWidth()-sourceWidth)/2+(midpoint-400)*.18))
        stageQuad=stageQuad or love.graphics.newQuad(sourceX,0,sourceWidth,stage:getHeight(),
            stage:getWidth(),stage:getHeight())
        stageQuad:setViewport(sourceX,0,sourceWidth,stage:getHeight(),
            stage:getWidth(),stage:getHeight())
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(stage,stageQuad,80,110,0,800/sourceWidth,450/stage:getHeight())
    end
    love.graphics.setColor(.05,.07,.10,.93)
    love.graphics.rectangle("fill",80,110,800,68)
    love.graphics.setColor(1,.83,.44,1)
    love.graphics.print("CRITTER KOMBAT",92,39)
    if match then
        drawFighter("critter-kombat-mouse-actions",match.left)
        drawFighter("critter-kombat-fox-actions",match.right)
        love.graphics.setColor(.43,.11,.11,1)
        love.graphics.rectangle("fill",102,143,280,16)
        love.graphics.rectangle("fill",578,143,280,16)
        love.graphics.setColor(.89,.64,.18,1)
        love.graphics.rectangle("fill",102,143,280*match.left.health/100,16)
        love.graphics.rectangle("fill",858-280*match.right.health/100,143,
            280*match.right.health/100,16)
        love.graphics.setColor(1,.94,.69,1)
        love.graphics.print("MOUSE  "..match.left.wins,102,119)
        love.graphics.printf("FOX  "..match.right.wins,688,119,170,"right")
        love.graphics.printf(string.format("ROUND %d   %02d",match.round,math.ceil(match.seconds)),
            390,122,180,"center")
        if match.phase~="playing" then
            love.graphics.setColor(.02,.025,.04,.77)
            love.graphics.rectangle("fill",246,277,468,88,6)
            love.graphics.setColor(1,.86,.53,1)
            local status=match.phase=="waiting" and "WAITING FOR PLAYER TWO"
                or match.phase=="finished" and (match.left.wins>match.right.wins and "MOUSE WINS!" or "FOX WINS!")
                or "ROUND OVER"
            love.graphics.printf(status,246,311,468,"center")
        end
    else
        love.graphics.setColor(.02,.025,.04,.78)
        love.graphics.rectangle("fill",229,284,502,74,6)
        love.graphics.setColor(1,.86,.53,1)
        love.graphics.printf("CHOOSE SOLO OR VERSUS",229,309,502,"center")
    end
    drawButton("solo",not match or match.phase=="finished")
    drawButton("versus",not match or match.phase=="finished")
    drawButton("join",match and match.phase=="waiting" and match.leftId~=id)
    drawButton("leave",true)
    for _,name in ipairs({"left","right","jump","punch","kick","block"}) do drawButton(name,true) end
    love.graphics.setColor(.78,.83,.83,1)
    love.graphics.printf("Move: A/D or arrows     Jump: Space     Punch: J     Kick: K     Block: L",
        80,539,800,"center")
    love.graphics.pop()
end
return Screen
