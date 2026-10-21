-- First-person arcade light-gun presentation and local controls.
local Crisis=require("src.critter_crisis")
local Enemy=require("src.critter_crisis_enemy")
local Art=require("src.critter_crisis_art")
local Inputs=require('src.critter_crisis_inputs')
local Coop=require('src.screens.critter_crisis_coop')
local Mobile=require('src.screens.critter_crisis_mobile')
local Screen={view="menu",aimX=480,aimY=330,mouseFire=false,touches={},cover=false,reload=false}
local images,fonts={},{}
local base="assets/generated/critter-crisis-v1/"
local function font(n)
    if not fonts[n] then fonts[n]=love.graphics.newFont("assets/fonts/VT323-Regular.ttf",n) end
    love.graphics.setFont(fonts[n])
    return fonts[n]
end
local function label(s,x,y,w,n,color)
    -- Keep status values on one line, even for long scores or route names.
    local face=font(n)
    while n>14 and face:getWidth(s)>w-12 do n=n-1;face=font(n) end
    love.graphics.setColor(unpack(color or {1,.89,.67,1}));love.graphics.printf(s,x,y,w,"center")
end
local function rect(x,y,w,h,fill,line)
    love.graphics.setColor(unpack(fill));love.graphics.rectangle("fill",x,y,w,h,6)
    love.graphics.setColor(unpack(line));love.graphics.rectangle("line",x,y,w,h,6)
end
local function inside(x,y,r) return x>=r[1] and x<=r[1]+r[3] and y>=r[2] and y<=r[2]+r[4] end
local buttons={solo={50,376,270,70},coop={345,376,270,70},join={640,376,270,70},
    back={28,25,112,44},leave={820,25,112,44},restart={335,518,290,55},
    cover={762,603,174,57},reload={570,603,174,57}}
local menuButtons={'solo','coop','join'}
local phoneMenu={
    {'1','SOLO',{50,354,415,78}},{'2','HOST CO-OP',{495,354,415,78}},
    {'3','JOIN CO-OP',{50,451,415,78}},{'h','CONNECT PHONES',{495,451,415,78}},
}
local function image(name)
    if not images[name] then
        images[name]=love.graphics.newImage(base..name..".png")
        images[name]:setFilter("nearest","nearest")
    end
    return images[name]
end
local function frame(name,cell,x,y,sx,sy,clip)
    local atlas=image(name)
    local height=math.min(cell.h,clip or cell.h)
    if height<=0 then return end
    if not cell.quad then cell.quad=love.graphics.newQuad(cell.x,cell.y,cell.w,cell.h,atlas:getDimensions()) end
    cell.quad:setViewport(cell.x,cell.y,cell.w,height,atlas:getDimensions())
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(atlas,cell.quad,x,y,0,sx,sy or sx,cell.ax,cell.ay)
end
local function sprite(col,row,x,y,scale)
    frame("enemies-and-props",Art.original[row].frames[col],x,y,scale,scale)
end
local function drawEnemy(enemy,session)
    if enemy.posture==0 then return end
    local body=Enemy.body(enemy)
    local running=enemy.mode=="moving"
    local row=running and Art.run[enemy.kind] or Art.original[enemy.kind]
    local index=running and math.floor(enemy.travel/60*8)%8+1 or 1
    local cell=row.frames[index]
    local scale=160*body.scale/(running and row.height or cell.h)
    -- Crop the sinking body at its foot plane, then draw the physical cover over it.
    local bottom=Enemy.isBoat(session) and Enemy.cover(enemy,true).top or enemy.y
    local clip=cell.ay-(body.y-bottom)/scale
    local facing=enemy.x>480 and -1 or 1
    if running and not Enemy.isBoat(session) then
        local covers,count=Enemy.layout(session.level,session.stop)
        local target=covers[enemy.coverId+count]
        if target then facing=target.x<enemy.x and -1 or 1 end
    end
    frame(running and "enemy-run-v2" or "enemies-and-props",cell,enemy.x,body.y,scale*facing,scale,clip)
    if enemy.mode=="attack" then
        love.graphics.setColor(1,.39,.16,.9);love.graphics.setLineWidth(2)
        love.graphics.circle("line",enemy.x,body.top+31*body.scale,29*body.scale)
    end
    if enemy.shot>0 then
        love.graphics.setColor(1,.83,.35,enemy.shot/.22)
        love.graphics.circle("fill",enemy.x+65*body.scale*facing,body.top+67*body.scale,7*body.scale)
        love.graphics.setColor(1,1,1,1)
    end
end
local function drawEncounter(session)
    local boat=Enemy.isBoat(session)
    local entries={}
    for i,enemy in ipairs(session.enemies) do if enemy.hp>0 then
        entries[#entries+1]={kind="enemy",data=enemy,depth=enemy.y,order=i}
        if boat then entries[#entries+1]={kind="boat",data=enemy,depth=enemy.y,order=10+i} end
    end end
    if not boat then
        for i,cover in ipairs(Enemy.layout(session.level,session.stop)) do
            entries[#entries+1]={kind="cover",data=cover,depth=cover.y,order=10+i}
        end
    end
    for i,barrel in ipairs(session.barrels) do if barrel.alive then
        entries[#entries+1]={kind="barrel",data=barrel,depth=barrel.y+70,order=30+i}
    end end
    table.sort(entries,function(a,b) return a.depth<b.depth or a.depth==b.depth and a.order<b.order end)
    for _,entry in ipairs(entries) do
        local item=entry.data
        if entry.kind=="enemy" then drawEnemy(item,session)
        elseif entry.kind=="cover" then
            local c=Enemy.cover(item)
            local cell=Art.original[4].frames[4]
            love.graphics.setColor(0,0,0,.35)
            love.graphics.ellipse('fill',c.x,c.y+1,c.width*.52,8*c.scale)
            frame("enemies-and-props",cell,c.x,c.y,c.width/cell.w,c.height/cell.h)
        elseif entry.kind=="boat" then
            local c=Enemy.cover(item,true);local art=image("pursuit-boat")
            local scale=c.width/art:getWidth()
            love.graphics.setColor(1,1,1,1)
            love.graphics.draw(art,c.x,c.y,0,scale,scale,art:getWidth()/2,art:getHeight())
        else sprite(4,1,item.x,item.y+70,.43) end
    end
end
local function activeId(runtime) return tonumber(runtime.World.player.id) or 1 end
function Screen.sessionFor(runtime)
    local bay=runtime.state.roomGameBay
    if runtime.multiplayer:isClient() then
        for _,session in ipairs(runtime.multiplayer:crisisSnapshot()) do
            if session.bayId==bay then return session end
        end
        return nil
    end
    return Crisis.sessions[bay]
end
local function participant(runtime,s)
    local id=activeId(runtime)
    return s and (s.ownerId==id or s.partnerId==id)
end
function Screen.enter()
    Inputs.reset();Inputs.session=nil;Coop.release();Mobile.reset();Screen.connectionHelp=false
    Screen.view="menu";Screen.aimX=480;Screen.aimY=330;Screen.menuSelection=1
    Screen.mouseFire=false;Screen.touches={};Screen.cover=false;Screen.reload=false
    Screen.pad=nil;Screen.padFire=false;Screen.padCover=false;Screen.padReload=false;Screen.tapFire=false
    Screen.suspended=false;Screen.padReady=false;Screen.triggerFire=false;Screen.triggerCover=false
end
function Screen.command(runtime,action)
    local _,mode=Crisis.startAction(action)
    if (mode=='coop' or action=='join') and runtime.multiplayer.isActive and not runtime.multiplayer:isActive() then
        Screen.connectionHelp=true
        runtime.state.message='Connect both devices through Local Play first.'
        return false
    end
    local okay,code,message
    if runtime.multiplayer:isClient() then
        okay,message=runtime.multiplayer:requestInteraction("roomGame","critter_crisis:"..action)
    else okay,code,message=Crisis.command(runtime.state,runtime.World.player,action) end
    runtime.state.message=message or (okay and "Waiting for host..." or "Arcade unavailable.")
    return okay
end
function Screen.page(runtime)
    local session=Screen.sessionFor(runtime)
    if participant(runtime,session) then return session.phase=="waiting" and "waiting" or "playing" end
    return "menu"
end
function Screen.leave(runtime)
    local session=Screen.sessionFor(runtime)
    if participant(runtime,session) then Screen.command(runtime,"leave") end
    Screen.enter()
end
local function background(session)
    if not session then return "transit-yard" end
    if session.level==1 then return "transit-yard" end
    if session.level==2 then return "reactor-tower" end
    return session.stop>=4 and "boat-chase" or "docks"
end
local function drawBackdrop(session)
    local art=image(background(session));love.graphics.setColor(1,1,1,1)
    local stop=session and session.stop or 1
    local count=session and #Crisis.ROUTES[session.level].stops or 4
    local progress=(stop-1)/(count-1)
    local sx,sy=1032/art:getWidth(),570/art:getHeight()
    love.graphics.draw(art,-72*progress,75-45*(1-progress),0,sx,sy)
    if session and session.level==3 and session.stop>=4 then
        local tick=love.timer.getTime()*85
        love.graphics.setColor(.42,.91,1,.36)
        love.graphics.setLineWidth(3)
        for i=1,5 do
            local y=375+((tick+i*67)%190)
            love.graphics.line(360-(y-375)*1.1,y,480,y+53)
            love.graphics.line(600+(y-375)*1.1,y,480,y+53)
        end
    end
    love.graphics.setColor(.02,.025,.045,.28);love.graphics.rectangle("fill",0,75,960,500)
end
local function drawButton(name,title)
    love.graphics.setLineWidth(Screen.pad and menuButtons[Screen.menuSelection]==name and 3 or 1)
    local r=buttons[name];rect(r[1],r[2],r[3],r[4],{.055,.13,.19,.94},{.93,.69,.30,1})
    label(title,r[1],r[2]+(r[4]-30)/2,r[3],30)
    love.graphics.setLineWidth(1)
end
local function drawWeapon(player,offset)
    love.graphics.push();love.graphics.translate(offset or 0,0)
    local gun=image("player-pistol-v2")
    local shot=math.max(0,player.shot or 0)
    local recoil=math.min(1,shot/.12)
    local reload=player.reload>0 and math.sin(math.min(1,player.reload/1.15)*math.pi)*64 or 0
    local scale=224/gun:getHeight()
    local bottom=579+recoil*13+reload
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(gun,480,bottom,0,scale,scale,gun:getWidth()/2,gun:getHeight())
    if shot>0 then
        local muzzleY=bottom-224+20
        love.graphics.setColor(1,.66,.18,recoil)
        love.graphics.polygon("fill",480,muzzleY-36,474,muzzleY-13,460,muzzleY-24,
            470,muzzleY-3,459,muzzleY+5,480,muzzleY+2,498,muzzleY+8,
            490,muzzleY-6,501,muzzleY-23,486,muzzleY-13)
        love.graphics.setColor(1,.96,.73,recoil)
        love.graphics.circle("fill",480,muzzleY-5,7)
    end
    love.graphics.pop()
end
local function drawRoute(session,route)
    local width=920/#route.stops
    for index,stop in ipairs(route.stops) do
        local current=index==session.stop
        local x=20+(index-1)*width
        rect(x,538,width-4,32,current and {.22,.16,.065,.96} or {.012,.02,.03,.94},
            current and {.93,.69,.30,1} or {.16,.24,.27,1})
        label(stop,x+2,545,width-8,20,current and {1,.85,.49,1} or {.66,.78,.79,1})
    end
end
function Screen.draw(runtime)
    local session=Screen.sessionFor(runtime);local page=Screen.page(runtime)
    if page~='menu' and session.game~='mission' then Coop.draw(runtime,session);return end
    love.graphics.push("all")
    love.graphics.setColor(.02,.035,.05,1);love.graphics.rectangle("fill",0,0,960,678)
    drawBackdrop(session)
    if Screen.connectionHelp then
        love.graphics.setColor(.01,.02,.035,.96);love.graphics.rectangle('fill',30,70,900,570,12)
        label('TWO PHONES / PHONE + COMPUTER',55,104,850,43)
        label('1  Connect both devices to the same Wi-Fi or hotspot.',65,198,830,29)
        label('2  In LOCAL PLAY, one device hosts and the other joins.',65,260,830,29)
        label('3  Visit the SAME arcade cabinet on both devices.',65,322,830,29)
        label('4  Choose HOST CO-OP, then JOIN CO-OP on the other.',65,384,830,29)
        label('Each device gets one player and a full-screen view.',65,455,830,28,{.4,.92,1,1})
        rect(240,552,300,68,{.035,.12,.17,1},{.3,.9,1,1});label('LOCAL PLAY',240,570,300,32)
        rect(570,552,150,68,{.035,.12,.17,1},{.3,.9,1,1});label('BACK',570,570,150,32)
        love.graphics.pop();return
    end
    love.graphics.setColor(.012,.02,.03,.98);love.graphics.rectangle("fill",0,0,960,76)
    if page=="menu" then label("CRITTER CRISIS!",165,14,630,53)
    else label("CRITTER CRISIS!",143,3,652,40) end
    if page=="menu" then
        love.graphics.setColor(.015,.025,.045,.68);love.graphics.rectangle("fill",35,145,890,463,10)
        label("THREE MISSIONS - ONE SHOT AT A TIME",80,172,800,37)
        for level,route in ipairs(Crisis.ROUTES) do
            label(level.."  "..route.name,112,236+(level-1)*41,736,30,{.73,.86,.87,1})
        end
        if Mobile.enabled(runtime) then
            for _,entry in ipairs(phoneMenu) do
                local r=entry[3];rect(r[1],r[2],r[3],r[4],{.025,.06,.09,.97},{.93,.69,.3,1})
                label((Screen.pad and tonumber(entry[1])==Screen.menuSelection and '> ' or '')..entry[2],r[1],r[2]+(r[4]-30)/2,r[3],31)
            end
            drawButton('back','BACK')
            label('ONE PLAYER PER DEVICE - SAME WI-FI OR HOTSPOT',60,650,840,21,{.4,.92,1,1})
        else
        drawButton("solo","1  SOLO MISSION");drawButton("coop","2  HOST CO-OP")
        drawButton("join","3  JOIN PLAYER");drawButton("back","BACK")
        label("CRITTER CRISIS - SOLO AND CO-OP MISSIONS",100,534,760,19,{.73,.86,.87,1})
        label("Aim and fire | Hold cover to duck | Reload between volleys",100,614,760,23)
        label(Screen.pad and "D-PAD: SELECT   A: PLAY   B: BACK" or runtime.state.message or "",95,642,770,22,{.75,.84,.83,1})
        end
    else
        drawButton("leave","EXIT")
        local route=Crisis.ROUTES[session.level]
        label("LEVEL "..session.level.."  "..route.name.."  >  "..route.stops[session.stop],143,48,652,23)
        drawEncounter(session)
        if session.mode=='local' then label('TEAM SCORE '..session.score,310,82,340,25) end
        if session.flash>0 then
            love.graphics.setColor(1,.63,.15,session.flash*.9);love.graphics.circle("fill",480,420,160*session.flash/.42)
        end
        local me
        for _,p in pairs(session.players) do if p.id==activeId(runtime) then me=p end end
        if session.mode=='local' then
            Inputs.configure(session)
            for slot,id in ipairs({session.ownerId,session.partnerId}) do
                local p
                for _,candidate in pairs(session.players) do if candidate.id==id then p=candidate end end
                if p then
                    local a=Inputs.actors[slot]
                    love.graphics.setColor(unpack(Coop.colors[slot]));love.graphics.setLineWidth(2)
                    love.graphics.circle('line',a.x,a.y,15);love.graphics.line(a.x-25,a.y,a.x+25,a.y)
                    love.graphics.line(a.x,a.y-25,a.x,a.y+25);font(21);love.graphics.print('P'..slot,a.x+20,a.y-28)
                    if not p.covered and p.hp>0 then drawWeapon(p,slot==1 and -190 or 190) end
                end
            end
        elseif me then
            local x,y=Screen.aimX,Screen.aimY
            if Inputs.active(session) then Inputs.configure(session);x,y=Inputs.actors[1].x,Inputs.actors[1].y end
            love.graphics.setColor(.18,1,.91,1);love.graphics.setLineWidth(2)
            love.graphics.circle("line",x,y,15);love.graphics.line(x-26,y,x-8,y);love.graphics.line(x+8,y,x+26,y)
            love.graphics.line(x,y-26,x,y-8);love.graphics.line(x,y+8,x,y+26)
            if not me.covered then
                drawWeapon(me)
            end
            if me.covered then
                love.graphics.setColor(.02,.04,.06,.95);love.graphics.rectangle("fill",0,493,960,81)
                label("IN COVER",330,496,300,34)
            end
        end
        -- Navigation is drawn over the weapon so the hands never hide a stop.
        drawRoute(session,route)
        love.graphics.setColor(.012,.02,.03,.96);love.graphics.rectangle("fill",0,574,960,104)
        local muted={.66,.78,.79,1}
        label("SCORE",20,588,150,21,muted)
        label(tostring(session.score),20,616,150,34)
        if me then
            label("LIFE",188,588,146,21,muted)
            label(string.rep("+",me.hp),188,616,146,34)
            label("AMMO",354,588,188,21,muted)
            label(me.ammo.." / 8",354,616,188,34)
            if me.reload>0 then label("RELOADING",354,651,188,18,{.95,.72,.35,1}) end
        end
        label(session.mode=="coop" and "CO-OP MISSION" or "SOLO MISSION",570,578,366,20,muted)
        if session.mode=='coop' then
            for _,p in pairs(session.players) do if p.id~=activeId(runtime) then
                label('PARTNER  LIFE '..p.hp..'  AMMO '..p.ammo,20,84,300,24,Coop.colors[2])
                love.graphics.setColor(unpack(Coop.colors[2]));love.graphics.circle('line',p.aimX,p.aimY,11)
            end end
        end
        if session.phase=="waiting" then
            love.graphics.setColor(.015,.025,.04,.83);love.graphics.rectangle("fill",145,246,670,160,8)
            label("WAITING FOR SECOND PLAYER",165,282,630,48)
            label('Other device: open this cabinet and choose JOIN CO-OP.',155,350,650,25)
        elseif session.phase=="finished" or session.phase=="failed" then
            love.graphics.setColor(.015,.025,.04,.88);love.graphics.rectangle("fill",130,201,700,365,8)
            label(session.phase=="finished" and "CRISIS CLEARED!" or "MISSION FAILED",150,247,660,60)
            label("FINAL SCORE  "..session.score,180,327,600,42)
            if session.ownerId==activeId(runtime) then drawButton("restart","RESTART") end
        elseif session.transition>0 then
            label("AREA CLEAR  -  ADVANCING",170,267,620,50)
        end
        if session.mode=='local' then Coop.drawHud(runtime,session)
        elseif page~="waiting" and session.phase=="playing" then
            drawButton("reload","RELOAD");drawButton("cover","COVER")
        end
        if Mobile.active(runtime,session) and session.phase~='waiting' then Mobile.draw(runtime,session) end
    end
    love.graphics.pop()
end
function Screen.keypressed(runtime,key)
    if Screen.connectionHelp then
        if key=='escape' or key=='b' then Screen.connectionHelp=false
        elseif key=='return' and runtime.openLocalPlay then
            if runtime.saveCurrent and not runtime.saveCurrent() then return true end
            local slot=runtime.state.activeSlot;Screen.enter();runtime.openLocalPlay(slot)
        end
        return true
    end
    local page=Screen.page(runtime)
    if key=="escape" then
        if page=="menu" then return "back" else Screen.leave(runtime);return true end
    end
    if page=="menu" then
        if key=='h' then Screen.connectionHelp=true;return true end
        local action=({["1"]="start_solo",["2"]="start_coop",["3"]="join",["return"]="start_solo"})[key]
        if action then Screen.command(runtime,action);return true end
    else
        local s=Screen.sessionFor(runtime)
        if Inputs.active(s) then
            Inputs.configure(s)
            if key=='return' and (s.phase=='finished' or s.phase=='failed') and s.ownerId==activeId(runtime) then Screen.command(runtime,'restart')
            else Inputs.keypressed(key) end
            return true
        end
        if key=="space" or key=="lshift" or key=="rshift" then Screen.cover=true;return true end
        if key=="r" then Screen.reload=true;return true end
        if key=="return" and Screen.sessionFor(runtime).phase~="playing" then Screen.command(runtime,"restart");return true end
    end
    return true
end
function Screen.keyreleased(key)
    Inputs.keyreleased(key)
    if key=="space" or key=="lshift" or key=="rshift" then Screen.cover=false end
    if key=="r" then Screen.reload=false end
end
local function point(runtime,x,y)
    Screen.aimX=math.max(40,math.min(920,x));Screen.aimY=math.max(105,math.min(560,y))
end
function Screen.mousepressed(runtime,x,y,button)
    if Screen.connectionHelp then
        if inside(x,y,{240,552,300,68}) then return Screen.keypressed(runtime,'return') end
        if inside(x,y,{570,552,150,68}) then return Screen.keypressed(runtime,'escape') end
        return true
    end
    local s=Screen.sessionFor(runtime)
    if participant(runtime,s) and Mobile.active(runtime,s) and button==1 then
        local action=Mobile.press(runtime,s,'mouse',x,y)
        if action=='leave' then Screen.leave(runtime) elseif action=='restart' then Screen.command(runtime,'restart') end
        return true
    end
    if participant(runtime,s) and Inputs.active(s) then
        Inputs.configure(s)
        if (s.game=='mission' and inside(x,y,buttons.leave)) or (s.game~='mission' and x<110 and y<42) then Screen.leave(runtime);return true end
        if (s.phase=='finished' or s.phase=='failed') and s.ownerId==activeId(runtime) then
            if (s.game=='mission' and inside(x,y,buttons.restart)) or (s.game~='mission' and x>=810 and y<42) then Screen.command(runtime,'restart') end
            return true
        end
        local slot,action=Coop.action(s,x,y)
        if slot then Inputs.press('mouse:'..button,slot,action)
        else
            local ax,ay;slot,ax,ay=Coop.point(s,x,y)
            if slot then Inputs.aim(slot,ax,ay);Inputs.press('mouse:'..button,slot,button==1 and 1 or button==2 and 8 or nil) end
        end
        return true
    end
    if button~=1 then return true end
    local page=Screen.page(runtime)
    if page=="menu" then
        if Mobile.enabled(runtime) then
            if inside(x,y,buttons.back) then return 'back' end
            for _,entry in ipairs(phoneMenu) do
                if inside(x,y,entry[3]) then return Screen.keypressed(runtime,entry[1]) end
            end
            return true
        end
        if inside(x,y,buttons.back) then return "back" end
        for name,action in pairs({solo="start_solo",coop="start_coop",join="join"}) do
            if inside(x,y,buttons[name]) then Screen.command(runtime,action);return true end
        end
    else
        if inside(x,y,buttons.leave) then Screen.leave(runtime);return true end
        if inside(x,y,buttons.restart) and Screen.sessionFor(runtime).phase~="playing" then Screen.command(runtime,"restart");return true end
        if inside(x,y,buttons.cover) then Screen.cover=true;return true end
        if inside(x,y,buttons.reload) then Screen.reload=true;return true end
        point(runtime,x,y);Screen.mouseFire=true
    end
    return true
end
function Screen.mousereleased(button)
    if button==1 then Mobile.release('mouse') end
    Inputs.release('mouse:'..tostring(button or 1))
    Screen.mouseFire=false;Screen.cover=false;Screen.reload=false
end
function Screen.mousemoved(runtime,x,y)
    if Mobile.move('mouse',x,y) then return true end
    local s=Screen.sessionFor(runtime)
    if participant(runtime,s) and Inputs.active(s) then
        Inputs.configure(s);local slot,ax,ay=Coop.point(s,x,y)
        if slot then Inputs.aim(slot,ax,ay) end
    elseif Screen.page(runtime)~="menu" then point(runtime,x,y) end;return true
end
function Screen.touchpressed(runtime,id,sx,sy)
    Mobile.usedTouch=true
    local x,y=runtime.Viewport.toGame(sx,sy,runtime.Config.baseWidth,runtime.Config.baseHeight,runtime.App.officeFitsScreen())
    local s=Screen.sessionFor(runtime)
    if participant(runtime,s) and Mobile.active(runtime,s) then
        local action=Mobile.press(runtime,s,id,x,y)
        if action=='leave' then Screen.leave(runtime) elseif action=='restart' then Screen.command(runtime,'restart') end
        return true
    end
    if participant(runtime,s) and Inputs.active(s) then
        Inputs.configure(s)
        local slot,action=Coop.action(s,x,y)
        if slot then Inputs.press('touch:'..tostring(id),slot,action);Inputs.touches[id]={slot=slot}
        else
            local ax,ay;slot,ax,ay=Coop.point(s,x,y)
            if slot and y>75 and y<575 then
                if s.game=='mission' and s.mode=='local' then slot=x<480 and 1 or 2 end
                Inputs.touches[id]={slot=slot,aim=true};Inputs.aim(slot,ax,ay);Inputs.press('touch:'..tostring(id),slot,1)
            else return Screen.mousepressed(runtime,x,y,1) end
        end
        return true
    end
    local wasMenu=Screen.page(runtime)=="menu"
    local action=Screen.mousepressed(runtime,x,y,1)
    if not wasMenu then
        if inside(x,y,buttons.cover) then Screen.touches[id]="cover";Screen.cover=true
        elseif inside(x,y,buttons.reload) then Screen.touches[id]="reload";Screen.reload=true
        elseif y>75 and y<575 then Screen.touches[id]="fire";Screen.tapFire=true end
    end
    Screen.mouseFire=false
    return action
end
function Screen.touchmoved(runtime,id,sx,sy)
    if Mobile.touches[id] then
        local x,y=runtime.Viewport.toGame(sx,sy,runtime.Config.baseWidth,runtime.Config.baseHeight,runtime.App.officeFitsScreen())
        Mobile.move(id,x,y);return true
    end
    if Inputs.touches[id] then
        local t=Inputs.touches[id]
        local x,y=runtime.Viewport.toGame(sx,sy,runtime.Config.baseWidth,runtime.Config.baseHeight,runtime.App.officeFitsScreen())
        local slot,ax,ay=Coop.point(Inputs.session,x,y)
        if t.aim and slot then Inputs.aim(t.slot,ax,ay) end
        return true
    end
    if Screen.touches[id]=="fire" then
        local x,y=runtime.Viewport.toGame(sx,sy,runtime.Config.baseWidth,runtime.Config.baseHeight,runtime.App.officeFitsScreen())
        point(runtime,x,y)
    end
    return true
end
function Screen.touchreleased(id)
    if Mobile.release(id) then return true end
    Inputs.release('touch:'..tostring(id));Inputs.touches[id]=nil
    Screen.touches[id]=nil;Screen.cover=false;Screen.reload=false
    for _,name in pairs(Screen.touches) do if name=="cover" then Screen.cover=true elseif name=="reload" then Screen.reload=true end end
    return true
end
function Screen.gamepadpressed(runtime,pad,button)
    if Screen.suspended then return true end
    if Screen.pad~=pad then Screen.padReady=false end
    Screen.pad=pad
    if Screen.connectionHelp then
        if button=='a' or button=='start' then return Screen.keypressed(runtime,'return') end
        if button=='b' or button=='back' then return Screen.keypressed(runtime,'escape') end
        return true
    end
    local page=Screen.page(runtime)
    local s=Screen.sessionFor(runtime)
    if participant(runtime,s) and Inputs.active(s) then
        Inputs.configure(s)
        if button=='b' or button=='back' then Screen.leave(runtime)
        elseif button=='start' and (s.phase=='finished' or s.phase=='failed') and s.ownerId==activeId(runtime) then Screen.command(runtime,'restart')
        else Inputs.gamepadpressed(pad,button) end
        return true
    end
    if page=="menu" then
        if button=="dpup" or button=="dpdown" or button=="dpleft" or button=="dpright" then
            local direction=(button=="dpup" or button=="dpleft") and -1 or 1
            Screen.menuSelection=((Screen.menuSelection or 1)-1+direction)%3+1
        elseif button=="a" then Screen.keypressed(runtime,tostring(Screen.menuSelection or 1))
        elseif button=="x" then Screen.command(runtime,"start_coop")
        elseif button=="y" then Screen.command(runtime,"join")
        elseif button=="b" or button=="back" then return Screen.keypressed(runtime,'escape') end
    else
        if button=='start' and s and (s.phase=='finished' or s.phase=='failed') then Screen.command(runtime,'restart')
        elseif button=="a" or button=="rightshoulder" then Screen.padFire=true
        elseif button=="leftshoulder" then Screen.padCover=true
        elseif button=="x" then Screen.padReload=true
        elseif button=="b" or button=="back" then Screen.leave(runtime) end
    end
    return true
end
function Screen.gamepadreleased(pad,button)
    Inputs.gamepadreleased(pad,button)
    if button=="a" or button=="rightshoulder" then Screen.padFire=false end
    if button=="leftshoulder" then Screen.padCover=false end
    if button=="x" then Screen.padReload=false end
end
function Screen.gamepadaxis(runtime,pad,axis,value)
    if Screen.suspended then return true end
    if Screen.pad~=pad then Screen.padReady=false;Screen.pad=pad end
    local s=Screen.sessionFor(runtime)
    if participant(runtime,s) and Inputs.active(s) then Inputs.configure(s);Inputs.assignPad(pad) end
    return true
end
function Screen.controls(runtime)
    if Screen.suspended then return 0,0,0 end
    local s=Screen.sessionFor(runtime)
    if Inputs.active(s) then return 0,0,0 end
    if not participant(runtime,s) or s.phase~="playing" then return 0,0,0 end
    local fire=Screen.mouseFire or Screen.padFire or Screen.tapFire or Screen.triggerFire
    local cover=Screen.cover or Screen.padCover or Screen.triggerCover
    local reload=Screen.reload or Screen.padReload
    Screen.tapFire=false
    return (Screen.aimX-480)/480,(Screen.aimY-339)/339,
        (fire and Crisis.FIRE or 0)+(cover and Crisis.COVER or 0)+(reload and Crisis.RELOAD or 0)
end
function Screen.arcadeInputs(runtime)
    local s=Screen.sessionFor(runtime)
    if participant(runtime,s) and Inputs.active(s) then Inputs.configure(s);return Inputs.packet() end
end
function Screen.update(dt,runtime)
    local s=runtime and Screen.sessionFor(runtime)
    if participant(runtime or {World={player={id=-1}}},s) and Inputs.active(s) then
        Inputs.configure(s);Inputs.update(dt)
        if s.game~='mission' then Coop.update(runtime,s) end
    elseif s and s.game=='mission' and not Screen.suspended and Screen.pad then
        if not Screen.pad:isConnected() then
            Screen.pad=nil;Screen.padReady=false;Screen.padFire=false;Screen.padCover=false;Screen.padReload=false
            Screen.triggerFire=false;Screen.triggerCover=false
        else
            local dx,dy=Screen.pad:getGamepadAxis('rightx'),Screen.pad:getGamepadAxis('righty')
            if math.abs(dx)>.15 or math.abs(dy)>.15 then point(runtime,Screen.aimX+dx*460*dt,Screen.aimY+dy*460*dt) end
            local fire=Screen.pad:getGamepadAxis('triggerright')>.4
            local cover=Screen.pad:getGamepadAxis('triggerleft')>.4
            if not fire and not cover then Screen.padReady=true end
            Screen.triggerFire=Screen.padReady and fire;Screen.triggerCover=Screen.padReady and cover
        end
    end
end
function Screen.focus(focused)
    Screen.suspended=not focused;Inputs.focus(focused)
    if not focused then
        Mobile.reset();Screen.padReady=false;Screen.triggerFire=false;Screen.triggerCover=false
        Screen.padFire=false;Screen.padCover=false;Screen.padReload=false;Screen.mouseFire=false;Screen.tapFire=false
    end
end
return Screen
