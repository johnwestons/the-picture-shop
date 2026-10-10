-- Cabinet title, fighter selection and host-authoritative fighting presentation.
local Kombat=require("src.critter_kombat")
local Art=require("src.critter_kombat_art")
local Bindings=require("src.critter_kombat_controls")
local Options=require("src.screens.critter_kombat_options")
local Screen={held={},touches={},view="title",selected="mouse"}
local stage,stageQuad
local fonts={}
local buttons={
    solo={210,525,260,56},versus={490,525,260,56},join={350,598,260,44},
    leave={836,28,96,40},back={28,28,96,40},
    options={28,28,188,40},
    mouse={150,194,300,310},fox={510,194,300,310},confirm={340,549,280,54},
    rematch={350,555,260,48},
    left={90,614,70,48},right={166,614,70,48},jump={490,614,76,48},
    punch={572,614,86,48},kick={664,614,78,48},block={748,614,81,48},
}
local labels={solo="1   SOLO VS AI",versus="2   VERSUS PLAYER",join="3   JOIN PLAYER",
    leave="EXIT",back="BACK",options="O   OPTIONS",confirm="ENTER   READY TO FIGHT",rematch="CHOOSE FIGHTERS",
    left="LEFT",right="RIGHT",jump="JUMP",punch="PUNCH",kick="KICK",block="BLOCK"}
local function inside(x,y,r) return x>=r[1] and x<=r[1]+r[3] and y>=r[2] and y<=r[2]+r[4] end
local function font(size)
    if not fonts[size] then fonts[size]=love.graphics.newFont("assets/fonts/VT323-Regular.ttf",size) end
    love.graphics.setFont(fonts[size])
end
local function text(value,x,y,width,size,color)
    font(size);love.graphics.setColor(unpack(color or {1,.86,.55,1}))
    love.graphics.printf(value,x,y,width,"center")
end
local function matchFor(runtime)
    local bay=runtime.state.roomGameBay
    if runtime.multiplayer:isClient() then
        for _,match in ipairs(runtime.multiplayer:fightSnapshot()) do if match.bayId==bay then return match end end
        return nil
    end
    return Kombat.matches[bay]
end
local function localSide(runtime,match)
    local id=tonumber(runtime.World.player.id) or 1
    if match then
        if match.leftId==id then return "left" end
        if match.rightId==id then return "right" end
    end
end
function Screen.page(runtime)
    local match=matchFor(runtime)
    if Screen.view=="title" or Screen.view=="options" then return Screen.view end
    if match then return match.phase=="selecting" and "select" or "fight" end
    return Screen.view
end
local function clearControls() Screen.held={};Screen.touches={};Screen.mouse={};Screen.mouseButton=nil end
function Screen.cancelInputs(suspended)
    clearControls();Screen.suspended=suspended==true;Screen.awaitNeutral=not suspended
    if Screen.view=="options" then Options.cancelPending() end
end
function Screen.openControls()
    clearControls();Screen.view="options"
    Options.enter(Screen.bindings,function(config)
        if not Bindings.save(config) then return false end
        Screen.bindings=config;Screen.view="title";clearControls();return true
    end,function()Screen.view="title";clearControls()end)
end
local function rect(name)
    if Screen.bindings and Screen.bindings.touch[name] then return Bindings.rect(Screen.bindings,name) end
    return buttons[name]
end
function Screen.enter(runtime,bayId)
    runtime.state.roomGameBay=bayId;runtime.state.screen="critter_kombat"
    runtime.state.message="Choose solo play or challenge another player."
    local match=matchFor(runtime)
    Screen.view=localSide(runtime,match) and (match.phase=="selecting" and "select" or "fight") or "title"
    Screen.selected="mouse";Screen.exitRequested=false;Screen.backRequested=false
    Screen.bindings=Bindings.load();Screen.menuIndex=1;Screen.pad=nil;Screen.suspended=false;Screen.awaitNeutral=false
    Screen.hadMatch=localSide(runtime,match)~=nil
    clearControls()
end
function Screen.command(runtime,action)
    local okay,code,message
    if runtime.multiplayer:isClient() then
        okay,message=runtime.multiplayer:requestInteraction("roomGame","critter_kombat:"..action)
    else okay,code,message=Kombat.command(runtime.state,runtime.World.player,action) end
    runtime.state.message=message or (okay and "Waiting for the host..." or "Arcade unavailable.")
    return okay
end
local function close(runtime,toTitle)
    if runtime.multiplayer:isClient() and runtime.multiplayer.pendingInteraction then
        Screen.exitRequested=not toTitle;Screen.backRequested=toTitle;clearControls();return
    end
    local match=matchFor(runtime)
    if localSide(runtime,match) or Screen.view=="select" then
        if not Screen.command(runtime,"leave") then return end
    end
    clearControls();Screen.exitRequested=false;Screen.backRequested=false;Screen.view="title"
    Screen.hadMatch=false
    if not toTitle then runtime.state.screen="world";runtime.state.roomGameBay=nil;Art.clear() end
end
function Screen.leave(runtime) close(runtime,false) end
local function enabled(runtime,name)
    local match=matchFor(runtime);local side=localSide(runtime,match)
    if name=="leave" or name=="back" or name=="options" then return true end
    if name=="solo" or name=="versus" then return not match or match.phase=="finished" end
    if name=="join" then return match and match.mode=="versus" and match.phase=="selecting" and not match.rightId and not side end
    if name=="confirm" or name=="mouse" or name=="fox" then
        return match and side and match.phase=="selecting" and not match[side.."Ready"]
            and not runtime.multiplayer.pendingInteraction
    end
    if name=="rematch" then return match and side and match.phase=="finished" end
    return match and side and match.phase=="playing"
end
local function activate(runtime,name)
    if not enabled(runtime,name) then return false end
    if name=="leave" then Screen.leave(runtime)
    elseif name=="options" then Screen.openControls()
    elseif name=="back" then close(runtime,true)
    elseif name=="solo" or name=="versus" or name=="join" then
        if Screen.command(runtime,name=="join" and "join" or "start_"..name) then
            Screen.view="select";Screen.selected="mouse";clearControls()
        end
    elseif name=="mouse" or name=="fox" then Screen.selected=name
    elseif name=="confirm" then Screen.command(runtime,"ready_"..Screen.selected);clearControls()
    elseif name=="rematch" then
        local match=matchFor(runtime)
        Screen.selected=match[localSide(runtime,match)].character
        if Screen.command(runtime,"rematch") then Screen.view="select";clearControls() end
    else return false end
    return true
end
local function visible(runtime)
    local page=Screen.page(runtime)
    if page=="title" then return {"solo","versus","join","options","leave"} end
    if page=="select" then return {"mouse","fox","confirm","back","leave"} end
    local result={"leave"}
    if Screen.bindings.showTouch then for _,name in ipairs(Bindings.ACTIONS) do result[#result+1]=name end end
    local match=matchFor(runtime)
    if match and match.phase=="finished" then result[#result+1]="rematch" end
    return result
end
function Screen.keypressed(runtime,key)
    local page=Screen.page(runtime)
    if page=="options" then return Options.keypressed(key) end
    if key=="escape" then if page=="select" then close(runtime,true) else Screen.leave(runtime) end;return true end
    if page=="title" then
        local name=({["1"]="solo",["2"]="versus",["3"]="join",["return"]="solo",space="solo",o="options"})[key]
        if name then activate(runtime,name);return true end
    elseif page=="select" then
        local name=({["1"]="mouse",["2"]="fox",left="mouse",a="mouse",right="fox",d="fox",["return"]="confirm",space="confirm"})[key]
        if name then activate(runtime,name);return true end
    elseif key=="return" then activate(runtime,"rematch");return true end
    return false
end
local function press(runtime,x,y,pointer)
    for _,name in ipairs(visible(runtime)) do
        if inside(x,y,rect(name)) then
            if not enabled(runtime,name) then return true end
            if not activate(runtime,name) then
                if pointer then Screen.touches[pointer]=name
                else Screen.held[name]=true;Screen.mouseButton=name end
            end
            return true
        end
    end
    return true
end
function Screen.mousepressed(runtime,x,y,button)
    if Screen.page(runtime)=="options" then return Options.mousepressed(x,y,button) end
    if Screen.page(runtime)=="fight" then
        if button==1 and (inside(x,y,buttons.leave) or inside(x,y,buttons.rematch) and enabled(runtime,"rematch")) then
            return press(runtime,x,y)
        end
        for _,action in ipairs(Bindings.ACTIONS) do
            for _,mapped in ipairs(Screen.bindings.mouse[action]) do
                if mapped==button then Screen.mouse[button]=true;return true end
            end
        end
    end
    if button~=1 then return true end;return press(runtime,x,y)
end
function Screen.mousereleased(_,_,button)
    if Screen.view=="options" then return Options.released() end
    if button then Screen.mouse[button]=nil else Screen.mouse={} end
    if button==1 or not button then
        if Screen.mouseButton then Screen.held[Screen.mouseButton]=nil end;Screen.mouseButton=nil
    end
    return true
end
function Screen.mousemoved(runtime,x,y)
    if Screen.page(runtime)=="options" then return Options.mousemoved(x,y) end
    return true
end
function Screen.touchpressed(runtime,id,sx,sy)
    local x,y=runtime.Viewport.toGame(sx,sy,runtime.Config.baseWidth,runtime.Config.baseHeight,runtime.App.officeFitsScreen())
    if Screen.page(runtime)=="options" then return Options.mousepressed(x,y,1,id) end
    return press(runtime,x,y,id)
end
function Screen.touchmoved(runtime,id,sx,sy)
    local x,y=runtime.Viewport.toGame(sx,sy,runtime.Config.baseWidth,runtime.Config.baseHeight,runtime.App.officeFitsScreen())
    if Screen.page(runtime)=="options" then return Options.mousemoved(x,y,id) end
    local name=Screen.touches[id];if not name then return false end
    if not inside(x,y,rect(name)) then Screen.touches[id]=nil end;return true
end
function Screen.touchreleased(id)
    if Screen.view=="options" then return Options.released(id) end
    Screen.touches[id]=nil;return true
end
function Screen.gamepadpressed(runtime,pad,button)
    if Screen.suspended then return true end
    Screen.pad=pad
    local page=Screen.page(runtime)
    if page=="options" then return Options.gamepadpressed(button) end
    if page=="title" then
        local names={"solo","versus","join","options"}
        if button=="dpup" or button=="dpdown" then Screen.menuIndex=(Screen.menuIndex-1+(button=="dpup" and -1 or 1))%4+1
        elseif button=="a" then activate(runtime,names[Screen.menuIndex])
        elseif button=="start" then Screen.openControls()
        elseif button=="b" or button=="back" then Screen.leave(runtime) end
    elseif page=="select" then
        if button=="dpleft" then activate(runtime,"mouse") elseif button=="dpright" then activate(runtime,"fox")
        elseif button=="a" then activate(runtime,"confirm") elseif button=="b" or button=="back" then close(runtime,true) end
    elseif button=="back" then Screen.leave(runtime)
    elseif button=="start" then activate(runtime,"rematch") end
    return true
end
function Screen.gamepadreleased() return true end
function Screen.gamepadaxis(runtime,pad,axis,value)
    if Screen.suspended then return true end
    Screen.pad=pad
    if Screen.page(runtime)=="options" then return Options.gamepadaxis(axis,value) end
    return true
end
function Screen.controls(runtime)
    if Screen.exitRequested or Screen.backRequested then close(runtime,Screen.backRequested);return 0,0 end
    local match=matchFor(runtime)
    if Screen.view~="title" and Screen.view~="options" then
        local side=localSide(runtime,match)
        if side then
            local view=match.phase=="selecting" and "select" or "fight"
            if view=="select" and Screen.view=="fight" then Screen.selected=match[side].character end
            Screen.view=view;Screen.hadMatch=true
        elseif Screen.hadMatch and not runtime.multiplayer.pendingInteraction then
            Screen.view="title";Screen.hadMatch=false;clearControls()
            runtime.state.message="The match ended. Choose a new match."
        end
    end
    if Screen.page(runtime)~="fight" or not match or match.phase~="playing" or not localSide(runtime,match) then return 0,0 end
    local active={}
    for name,value in pairs(Screen.held) do if value then active[name]=true end end
    for _,name in pairs(Screen.touches) do active[name]=true end
    if Screen.suspended then return 0,0 end
    local x,bits=Bindings.input(Screen.bindings,active,Screen.mouse,Bindings.findGamepad(Screen.pad))
    if Screen.awaitNeutral then
        if x==0 and bits==0 then Screen.awaitNeutral=false end
        return 0,0
    end
    return x,bits
end
local function drawButton(runtime,name)
    local r=rect(name);local on=enabled(runtime,name)
    local alpha=Screen.bindings.touch[name] and Screen.bindings.touchOpacity or 1
    local selected=Screen.pad and Screen.page(runtime)=="title" and ({"solo","versus","join","options"})[Screen.menuIndex]==name
    love.graphics.setLineWidth(selected and 3 or 1)
    love.graphics.setColor(on and .12 or .055,on and .24 or .10,.24,.98*alpha)
    love.graphics.rectangle("fill",r[1],r[2],r[3],r[4],5)
    love.graphics.setColor(on and .97 or .40,on and .75 or .44,.34,alpha)
    love.graphics.rectangle("line",r[1],r[2],r[3],r[4],5)
    text(labels[name],r[1],r[2]+(r[4]-26)/2,r[3],26,on and {1,.9,.67,alpha} or {.44,.51,.53,alpha})
end
local function drawStage(match)
    stage=stage or love.graphics.newImage("assets/generated/breakroom-games-v1/critter-kombat-rail-yard.png")
    stage:setFilter("nearest","nearest")
    local sw=stage:getWidth()/1.12
    local mid=match and (match.left.x+match.right.x)/2 or 400
    local sx=math.max(0,math.min(stage:getWidth()-sw,(stage:getWidth()-sw)/2+(mid-400)*.18))
    stageQuad=stageQuad or love.graphics.newQuad(sx,0,sw,stage:getHeight(),stage:getWidth(),stage:getHeight())
    stageQuad:setViewport(sx,0,sw,stage:getHeight(),stage:getWidth(),stage:getHeight())
    love.graphics.setColor(1,1,1,1);love.graphics.draw(stage,stageQuad,0,90,0,960/sw,480/stage:getHeight())
end
local function preview(character,x,y,scale,face)
    Art.draw({character=character,action="idle",actionTime=love.timer.getTime()%100,face=face},x,y,scale)
end
local function drawTitle(runtime)
    drawStage();love.graphics.setColor(.015,.025,.04,.64);love.graphics.rectangle("fill",0,0,960,678)
    text("CRITTER KOMBAT",80,98,800,82)
    text("RAIL YARD RUMBLE",80,183,800,29,{.73,.84,.84,1})
    preview("mouse",305,490,1.29,1);preview("fox",655,490,1.29,-1)
    text("VS",420,327,120,60)
    for _,name in ipairs({"solo","versus","join","options","leave"}) do drawButton(runtime,name) end
end
local function drawSelect(runtime,match)
    drawStage();love.graphics.setColor(.015,.025,.04,.82);love.graphics.rectangle("fill",0,0,960,678)
    text("CHOOSE YOUR FIGHTER",90,83,780,50)
    text("1 / 2 or arrows to choose  -  Enter to confirm",90,139,780,25,{.73,.83,.84,1})
    local side=localSide(runtime,match);local ready=side and match[side.."Ready"]
    local chosen=ready and match[side].character or Screen.selected
    for i,character in ipairs({"mouse","fox"}) do
        local r=buttons[character];local selected=chosen==character
        love.graphics.setColor(selected and .13 or .055,selected and .23 or .10,.18,.98)
        love.graphics.rectangle("fill",r[1],r[2],r[3],r[4],8)
        love.graphics.setLineWidth(selected and 3 or 1);love.graphics.setColor(selected and 1 or .30,selected and .79 or .40,.38,1)
        love.graphics.rectangle("line",r[1],r[2],r[3],r[4],8)
        preview(character,r[1]+150,437,1.15,1)
        text(i.."  "..Art.ROSTER[character].name,r[1],445,300,32)
        text(Art.ROSTER[character].subtitle,r[1],478,300,22,{.70,.79,.79,1})
    end
    local status
    if ready then
        status=match.mode=="versus" and not match.rightId and "READY - WAITING FOR PLAYER TWO TO JOIN"
            or "READY - WAITING FOR THE OTHER FIGHTER"
    elseif not match or not side then status="WAITING FOR THE HOST..."
    else status=match.mode=="solo" and "SOLO VS AI - YOUR OPPONENT USES THE OTHER FIGHTER"
        or "VERSUS - EACH PLAYER CHOOSES ON THEIR OWN SCREEN" end
    text(status,90,515,780,24,{.73,.83,.84,1})
    drawButton(runtime,"confirm");drawButton(runtime,"back");drawButton(runtime,"leave")
    text(runtime.state.message or "",90,627,780,22,{.68,.75,.77,1})
end
local function drawFight(runtime,match)
    drawStage(match)
    text("CRITTER KOMBAT",80,25,720,35);drawButton(runtime,"leave")
    if not match then text("MATCH ENDED",180,290,600,45);return end
    local age=runtime.multiplayer:isClient() and runtime.multiplayer.fightReceivedAt
        and math.max(0,math.min(.10,runtime.multiplayer.clock()-runtime.multiplayer.fightReceivedAt)) or 0
    for _,fighter in ipairs({match.left,match.right}) do
        local pose={character=fighter.character,variant=fighter.variant,face=fighter.face,
            action=fighter.action,actionTime=fighter.actionTime+age}
        Art.draw(pose,80+fighter.x,510-fighter.z,.93)
    end
    love.graphics.setColor(.035,.05,.08,.96);love.graphics.rectangle("fill",80,104,800,76)
    love.graphics.setColor(.43,.11,.11,1)
    love.graphics.rectangle("fill",102,148,280,16);love.graphics.rectangle("fill",578,148,280,16)
    love.graphics.setColor(.90,.65,.20,1)
    love.graphics.rectangle("fill",102,148,280*match.left.health/100,16)
    love.graphics.rectangle("fill",858-280*match.right.health/100,148,280*match.right.health/100,16)
    text(Art.ROSTER[match.left.character].name.."  "..match.left.wins,102,115,280,27)
    text(Art.ROSTER[match.right.character].name.."  "..match.right.wins,578,115,280,27)
    text(string.format("ROUND %d  %02d",match.round,math.ceil(match.seconds)),390,122,180,26)
    if match.phase~="playing" then
        love.graphics.setColor(.015,.025,.04,.84);love.graphics.rectangle("fill",210,263,540,114,6)
        local status=match.phase=="intro" and ((match.countdown or 0)>.45 and "GET READY" or "FIGHT!")
            or match.phase=="finished" and (Art.ROSTER[match.left.wins>match.right.wins and match.left.character or match.right.character].name.." WINS!")
            or "ROUND OVER"
        text(status,210,289,540,58)
        if match.phase=="finished" then drawButton(runtime,"rematch") end
    end
    if match.phase~="finished" then
        text("Jump: "..Bindings.label(Screen.bindings,"keyboard","jump").."   Punch: "..Bindings.label(Screen.bindings,"keyboard","punch")
            .."   Kick: "..Bindings.label(Screen.bindings,"keyboard","kick").."   Block: "..Bindings.label(Screen.bindings,"keyboard","block"),
            80,565,800,25,{.72,.81,.82,1})
    end
    if Screen.bindings.showTouch then for _,name in ipairs(Bindings.ACTIONS) do drawButton(runtime,name) end end
end
function Screen.draw(runtime)
    love.graphics.push("all");love.graphics.setColor(.025,.035,.055,1);love.graphics.rectangle("fill",0,0,960,678)
    local match=matchFor(runtime);local page=Screen.page(runtime)
    if page=="options" then Options.draw()
    elseif page=="title" then drawTitle(runtime)
    elseif page=="select" then drawSelect(runtime,match)
    else drawFight(runtime,match) end
    love.graphics.pop()
end
return Screen
