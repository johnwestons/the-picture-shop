local Hockey=require("src.air_hockey")
local Screen={}
local images={}
local DIR="assets/generated/breakroom-games-v1/"
local function image(name)
    if images[name] then return images[name] end
    local file=DIR..name..".png"
    if not love.filesystem.getInfo(file) then return nil end
    images[name]=love.graphics.newImage(file)
    images[name]:setFilter("linear","linear")
    return images[name]
end
local function inside(x,y,rect)
    return x>=rect[1] and x<=rect[1]+rect[3] and y>=rect[2] and y<=rect[2]+rect[4]
end
local BUTTONS={solo={95,550,225,52},versus={367,550,225,52},join={640,550,225,52},
    leave={792,42,100,43}}
local function drawButton(rect,label,enabled)
    love.graphics.setColor(enabled and .10 or .08,enabled and .32 or .12,.32,1)
    love.graphics.rectangle("fill",rect[1],rect[2],rect[3],rect[4],6)
    love.graphics.setColor(enabled and .86 or .45,enabled and .92 or .52,enabled and .84 or .51,1)
    love.graphics.rectangle("line",rect[1],rect[2],rect[3],rect[4],6)
    love.graphics.printf(label,rect[1],rect[2]+14,rect[3],"center")
end
local function matchFor(runtime)
    local bay=runtime.state.roomGameBay
    if runtime.multiplayer:isClient() then
        local games=runtime.multiplayer:gameSnapshot() or {}
        for _,entry in ipairs(games) do if entry.bayId==bay then return entry end end
        return nil
    end
    return Hockey.matches[bay]
end
function Screen.enter(runtime,bayId)
    runtime.state.roomGameBay=bayId
    runtime.state.screen="air_hockey"
    runtime.state.message="Choose solo play or invite another player."
    Screen.dragging=false
end
function Screen.command(runtime,action)
    local okay,code,message
    if runtime.multiplayer:isClient() then
        okay,message=runtime.multiplayer:requestInteraction("roomGame","air_hockey:"..action)
    else
        okay,code,message=Hockey.command(runtime.state,runtime.World.player,action)
    end
    runtime.state.message=message or (okay and "Waiting for the host..." or "Game action unavailable.")
    return okay
end
function Screen.leave(runtime)
    local match=matchFor(runtime)
    local id=tonumber(runtime.World.player.id) or 1
    if match and (match.leftId==id or match.rightId==id) then Screen.command(runtime,"leave") end
    runtime.state.screen="world"
    runtime.state.roomGameBay=nil
    Screen.dragging=false
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
    if inside(x,y,BUTTONS.leave) then Screen.leave(runtime);return true end
    for action,rect in pairs(BUTTONS) do
        if action~="leave" and inside(x,y,rect) then
            Screen.command(runtime,action=="solo" and "start_solo"
                or action=="versus" and "start_versus" or "join")
            return true
        end
    end
    Screen.dragging=inside(x,y,{80,120,800,400})
    return Screen.dragging
end
function Screen.mousereleased() Screen.dragging=false end
function Screen.touchpressed(runtime,id,screenX,screenY)
    local x,y=runtime.Viewport.toGame(screenX,screenY,runtime.Config.baseWidth,
        runtime.Config.baseHeight,runtime.App.officeFitsScreen())
    Screen.touchX,Screen.touchY=x,y
    Screen.touchId=id
    return Screen.mousepressed(runtime,x,y,1)
end
function Screen.touchmoved(runtime,id,screenX,screenY)
    if id~=Screen.touchId then return false end
    Screen.touchX,Screen.touchY=runtime.Viewport.toGame(screenX,screenY,
        runtime.Config.baseWidth,runtime.Config.baseHeight,runtime.App.officeFitsScreen())
    return true
end
function Screen.touchreleased(id)
    if id~=Screen.touchId then return false end
    Screen.touchId,Screen.touchX,Screen.touchY=nil,nil,nil
    Screen.dragging=false
    return true
end
function Screen.controls(runtime,keyboardX,keyboardY)
    local match=matchFor(runtime)
    local id=tonumber(runtime.World.player.id) or 1
    if not match or match.phase~="playing" then return 0,0 end
    local side=id==match.leftId and "left" or id==match.rightId and "right" or nil
    if not side then return 0,0 end
    if Screen.dragging then
        local mx,my=Screen.touchX,Screen.touchY
        if not mx then mx,my=runtime.pointerPosition() end
        local px,py=side=="left" and match.leftX or match.rightX,
            side=="left" and match.leftY or match.rightY
        return math.max(-1,math.min(1,(mx-80-px)/70)),
            math.max(-1,math.min(1,(my-120-py)/70))
    end
    return keyboardX,keyboardY
end
function Screen.draw(runtime)
    local match=matchFor(runtime)
    love.graphics.push("all")
    love.graphics.setColor(.025,.042,.05,.95)
    love.graphics.rectangle("fill",43,25,872,626,12)
    love.graphics.setColor(.95,.76,.29,1)
    love.graphics.print("AIR HOCKEY",82,45)
    love.graphics.setColor(.83,.89,.88,1)
    love.graphics.printf(match and string.format("ORANGE %d     :     %d TEAL",match.leftScore,match.rightScore)
        or "FIRST TO SEVEN",300,46,360,"center")
    local rink=image("air-hockey-rink")
    if rink then love.graphics.setColor(1,1,1,1);love.graphics.draw(rink,80,120) end
    if match then
        for _,piece in ipairs({
            {"orange-striker",match.leftX,match.leftY},
            {"teal-striker",match.rightX,match.rightY},
            {"puck",match.puckX,match.puckY},
        }) do
            local sprite=image(piece[1])
            if sprite then love.graphics.setColor(1,1,1,1)
                love.graphics.draw(sprite,80+piece[2]-sprite:getWidth()/2,
                    120+piece[3]-sprite:getHeight()/2) end
        end
        if match.phase=="waiting" or match.phase=="finished" then
            love.graphics.setColor(.02,.04,.05,.77)
            love.graphics.rectangle("fill",275,263,410,80,8)
            love.graphics.setColor(.98,.9,.68,1)
            love.graphics.printf(match.phase=="waiting" and "WAITING FOR SECOND PLAYER"
                or (match.leftScore>match.rightScore and "ORANGE WINS!" or "TEAL WINS!"),275,291,410,"center")
        end
    end
    local id=tonumber(runtime.World.player.id) or 1
    drawButton(BUTTONS.solo,"1  SOLO VS AI",not match or match.phase=="finished")
    drawButton(BUTTONS.versus,"2  INVITE PLAYER",not match or match.phase=="finished")
    drawButton(BUTTONS.join,"3  JOIN",match and match.phase=="waiting" and match.leftId~=id)
    drawButton(BUTTONS.leave,"EXIT",true)
    love.graphics.setColor(.72,.81,.81,1)
    love.graphics.printf("Move with WASD / arrows, drag with mouse or touch. Each paddle stays on its half.",80,617,800,"center")
    love.graphics.pop()
end
return Screen
