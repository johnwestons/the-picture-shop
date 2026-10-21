local Frontier=require('src.critter_crisis_frontier')
local Inputs=require('src.critter_crisis_inputs')
local Range=require('src.arcade_frontier.shooting_range')
local Stand=require('src.arcade_frontier.last_stand_shootout')
local Shooting=require('src.arcade_frontier.first_person_shooting')
local Scene=require('src.arcade_frontier.train_ambush_scene')
local Catalog=require('src.arcade_frontier.catalog')
local Mobile=require('src.screens.critter_crisis_mobile')
local Coop={colors={{.2,.95,1,1},{1,.55,.17,1}}}
local titles={range='GUN RANGE',stand='LAST STAND',train='TRAIN ATTACK'}
local assets,fonts
local heardRound,heardShots,heardEnemies
local function text(value,x,y,w,size,color)
    fonts=fonts or {};if not fonts[size] then fonts[size]=love.graphics.newFont('assets/fonts/VT323-Regular.ttf',size) end
    love.graphics.setFont(fonts[size]);love.graphics.setColor(unpack(color or {1,.89,.67,1}))
    love.graphics.printf(value,x,y,w,'center')
end
local function box(x,y,w,h,color)
    love.graphics.setColor(.018,.035,.05,1);love.graphics.rectangle('fill',x,y,w,h,5)
    love.graphics.setColor(unpack(color or {1,.72,.35,1}));love.graphics.rectangle('line',x,y,w,h,5)
end
function Coop.frame(runtime,s)
    return s.frontier or runtime.multiplayer.crisisFrontier and runtime.multiplayer:crisisFrontier(s)
end
local function player(s,id) for _,p in pairs(s.players) do if p.id==id then return p end end end
local function rectFor(session,slot)
    if session.mode=='local' then return slot==1 and 12 or 486,120,462,346.5 end
    return 80,76,800,600
end
local function buttons(session,slot)
    if session.game=='mission' and session.mode=='coop' then
        return {{x=570,y=603,w=174,h=57,name='RELOAD',action=Frontier.RELOAD},
            {x=762,y=603,w=174,h=57,name='COVER',action=Frontier.COVER}}
    end
    local pair=session.mode=='local'
    local x=pair and (slot==1 and 12 or 486) or 110
    local y=session.game=='mission' and 629 or pair and 568 or 619
    local width=pair and 462 or 740
    local names=session.game=='mission' and {'FIRE','COVER','RELOAD'}
        or session.game=='stand' and {'FIRE','COVER','RELOAD','AIM','WEAPON','MODE','SUPPLY','NEXT'}
        or {'FIRE','COVER','RELOAD','AIM','WEAPON','MODE'}
    local actions={FIRE=Frontier.FIRE,COVER=Frontier.COVER,RELOAD=Frontier.RELOAD,AIM=Frontier.ADS,
        WEAPON=Frontier.WEAPON,MODE=Frontier.MODE,SUPPLY=Frontier.SUPPLY,NEXT=Frontier.CONTINUE}
    local columns=pair and math.min(4,#names) or #names
    local out={}
    for i,name in ipairs(names) do out[i]={x=x+(i-1)%columns*width/columns,y=y+math.floor((i-1)/columns)*51,w=width/columns-6,h=session.game=='mission' and 36 or 44,name=name,action=actions[name]} end
    return out
end
function Coop.drawHud(runtime,s)
    love.graphics.setColor(.01,.02,.03,1);love.graphics.rectangle('fill',0,s.game=='mission' and 574 or 478,960,204)
    local f=s.game~='mission' and Coop.frame(runtime,s)
    for slot=1,2 do
        local id=slot==1 and s.ownerId or s.partnerId;local p=id~=nil and player(s,id)
        local x=slot==1 and 12 or 486;local y=s.game=='mission' and 580 or 484
        box(x,y,462,s.game=='mission' and 89 or 184,Coop.colors[slot])
        local hp=p and p.hp or 0;local ammo=p and p.ammo or 0
        if f then hp=f.pilots[slot].data.health;ammo=f.kind=='range' and f.pilots[slot].range.loaded or f.pilots[slot].gun.magazine end
        text('P'..slot..'  LIFE '..hp..'   AMMO '..ammo..(hp<=0 and '   DOWN' or p and p.covered and '   COVER' or ''),x+4,y+(s.game=='mission' and 4 or 9),454,24,Coop.colors[slot])
        if s.game=='mission' then
            text(slot==1 and 'MOUSE / WASD  CTRL FIRE  C COVER  R RELOAD' or 'ARROWS  ENTER FIRE  R-SHIFT COVER  BACKSPACE RELOAD',x+8,y+29,446,15)
        else
            text(slot==1 and 'MOUSE / WASD   SPACE FIRE   C COVER   R RELOAD' or 'ARROWS AIM   ENTER FIRE   R-SHIFT COVER   BACKSPACE RELOAD',x+8,y+46,446,18)
        end
        for _,b in ipairs(buttons(s,slot)) do box(b.x,b.y,b.w,b.h,Coop.colors[slot]);text(b.name,b.x,b.y+7,b.w,22) end
    end
end
local function drawView(f,slot,seat)
    love.graphics.setFont(require('src.arcade_frontier.typography').font(love.graphics,'regular',20))
    local view,data,gun=Frontier.view(f,slot)
    local aim=Inputs.actors[seat]
    if f.kind=='range' then
        local copy={};for k,v in pairs(view) do copy[k]=v end;view=copy
        view.aimX,view.aimY=aim.x,aim.y
    else
        local copy={};for k,v in pairs(gun) do copy[k]=v end;gun=copy;view.gun=copy
        gun.aimX,gun.aimY=aim.x,aim.y
    end
    if f.kind=='range' then
        if not assets then assets=require('src.screens.frontier_arcade').rangeAssets() end
        Range.draw(view,data,assets,{},Catalog,false)
        love.graphics.setColor(.02,.025,.03,1);love.graphics.rectangle('fill',0,640,960,80)
        text('SHOTS '..view.shots..'   |   '..view.weapon:upper():gsub('-',' '),15,660,930,26,Coop.colors[slot])
        if f.pilots[slot].covered then text('IN COVER',280,570,400,36,Coop.colors[slot]) end
    elseif f.kind=='stand' then
        Stand.draw(view,data,960,720)
        if view.ducking then
            box(240,304,480,112)
            text(data.health<=0 and 'DOWN - PARTNER CAN CONTINUE' or 'IN COVER\nRelease COVER to return',252,326,456,30,Coop.colors[slot])
        end
        love.graphics.setColor(.02,.025,.03,1);love.graphics.rectangle('fill',0,680,960,40)
        text('PLAYER '..slot..'   |   '..gun.weapon:upper():gsub('-',' '),15,685,930,24,Coop.colors[slot])
    else
        Scene.draw(view,960,720,data.accessibility or {})
        if not view.cover and view.coverProgress==0 then Shooting.draw(gun,960,720) end
        love.graphics.setColor(unpack(Coop.colors[slot]));love.graphics.circle('line',gun.aimX,gun.aimY,12)
        text('TRAIN '..math.ceil(100*f.world.protection/math.max(1,f.world.maxProtection))..'%   |   AMMO '..gun.magazine,150,10,660,29,Coop.colors[slot])
    end
end
function Coop.draw(runtime,s)
    Inputs.configure(s)
    love.graphics.push('all');love.graphics.setColor(.01,.02,.03,1);love.graphics.rectangle('fill',0,0,960,678)
    local f=Coop.frame(runtime,s);local pair=s.mode=='local'
    local ownSlot=tonumber(runtime.World.player.id)==s.ownerId and 1 or 2
    text(titles[s.game]..' / '..(pair and 'TWO PLAYERS HERE' or 'LAN CO-OP'),122,8,700,28)
    if Mobile.active(runtime,s) then box(12,8,114,60);text('BACK',16,22,106,32)
    else box(12,4,96,34);text('BACK',12,8,96,24) end
    if s.phase=='waiting' then
        text('WAITING FOR PLAYER 2',160,265,640,42)
        text('Other phone or computer: open this cabinet and choose JOIN CO-OP.',60,330,840,26)
    elseif not f then text('SYNCING THE SHARED ENCOUNTER...',100,310,760,30)
    else
        if pair then text('TEAM SCORE '..s.score,270,57,420,28) end
        for slot=1,2 do if pair or slot==ownSlot then
            local x,y,w,h=rectFor(s,slot)
            love.graphics.push('all')
            local sx,sy=love.graphics.transformPoint(x,y);local ex,ey=love.graphics.transformPoint(x+w,y+h)
            love.graphics.intersectScissor(sx,sy,ex-sx,ey-sy)
            love.graphics.translate(x,y);love.graphics.scale(w/960)
            drawView(f,slot,pair and slot or 1)
            love.graphics.pop()
            if pair then text('PLAYER '..slot,x,91,w,26,Coop.colors[slot]) end
        end end
        if pair then Coop.drawHud(runtime,s)
        elseif not Mobile.active(runtime,s) then
            box(4,586,952,92)
            local p=f.pilots[ownSlot];local other=f.pilots[ownSlot==1 and 2 or 1]
            local ammo=f.kind=='range' and p.range.loaded or p.gun.magazine
            text('LIFE '..p.data.health..'  AMMO '..ammo..' | PARTNER '..other.data.health..' LIFE | TEAM '..s.score,110,590,740,23,Coop.colors[ownSlot])
            for _,b in ipairs(buttons(s,1)) do box(b.x,b.y,b.w,b.h);text(b.name,b.x,b.y+8,b.w,22) end
        end
        if f.kind=='stand' and f.world.result=='intermission' then
            box(170,240,620,130);text('WAVE COMPLETE',190,262,580,36)
            text(Mobile.active(runtime,s) and 'TAP NEXT WAVE' or 'ENTER / START TO CONTINUE',190,310,580,28)
        end
        if s.phase=='finished' or s.phase=='failed' then
            box(190,220,580,178);text(s.phase=='finished' and 'TEAM COMPLETE!' or 'TEAM DEFEATED',210,247,540,39)
            text('TEAM SCORE '..s.score,210,299,540,28)
            text(ownSlot==1 and (Mobile.active(runtime,s) and 'TAP PLAY AGAIN' or 'ENTER / START TO RESTART') or 'WAITING FOR PLAYER 1 TO RESTART',200,345,560,25)
        end
    end
    if not Mobile.active(runtime,s) and s.phase~='playing' and s.phase~='waiting' and ownSlot==1 then box(810,4,138,34);text('RESTART',810,8,138,24) end
    if Mobile.active(runtime,s) and s.phase~='waiting' then Mobile.draw(runtime,s) end
    love.graphics.pop()
end
function Coop.update(runtime,s)
    local f=Coop.frame(runtime,s)
    if not f then return end
    if heardRound~=s.roundId then heardRound=s.roundId;heardShots={0,0};heardEnemies=0 end
    for slot,p in ipairs(f.pilots) do
        if p.shots>(heardShots[slot] or 0) and (f.kind~='stand' or runtime.multiplayer:isClient()) then
            Shooting.playReport(f.kind=='range' and p.range.weapon or p.gun.weapon,Catalog,p.data,false)
        end
        heardShots[slot]=p.shots
    end
    if runtime.multiplayer:isClient() and (f.world.enemyShots or 0)>heardEnemies then
        Shooting.playReport('frontier-22-lever-rifle',Catalog,f.worldData,true)
    end
    heardEnemies=f.world.enemyShots or 0
end
function Coop.point(session,x,y)
    if session.game=='mission' then return 1,x,y end
    local slot=session.mode=='local' and (x<480 and 1 or 2) or 1
    local rx,ry,w,h=rectFor(session,slot)
    if x<rx or x>rx+w or y<ry or y>ry+h then return nil end
    return slot,(x-rx)*960/w,(y-ry)*960/w
end
function Coop.action(session,x,y)
    local count=session.mode=='local' and 2 or 1
    for slot=1,count do for _,b in ipairs(buttons(session,slot)) do
        if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then return slot,b.action end
    end end
end
function Coop.release()
    heardRound=nil;heardShots=nil
    if assets then
        assets.weaponViews:release();for name,image in pairs(assets) do if name~='weaponViews' then image:release() end end
        assets=nil
    end
end
return Coop
