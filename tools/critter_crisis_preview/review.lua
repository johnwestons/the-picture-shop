-- Engine-driven regression checks and screenshots, using disposable sessions only.
local Review={}
function Review.run(runtime,Screen,Crisis,Frontier,destination)
    local report=assert(io.open(destination..'/review.txt','w'))
    local checks=0
    local function check(name,condition,detail)
        assert(condition,name..': '..tostring(detail or 'failed'))
        checks=checks+1;report:write('PASS '..name..'\n');report:flush()
    end
    local function capture(name,width,height)
        width,height=width or 960,height or 678
        local canvas=love.graphics.newCanvas(width,height)
        love.graphics.push('all');love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(0,0,0,1)
        local scale=math.min(width/960,height/678)
        love.graphics.translate((width-960*scale)/2,(height-678*scale)/2);love.graphics.scale(scale)
        Screen.draw(runtime);love.graphics.pop()
        local pixels=canvas:newImageData();local encoded=pixels:encode('png')
        local file=assert(io.open(destination..'/'..name..'.png','wb'));file:write(encoded:getString());file:close()
        pixels:release();canvas:release();encoded:release()
    end
    local function step(seconds)
        for _=1,math.ceil(seconds*60) do Frontier.update(1/60) end
    end
    local function pointer(x,y) return (960-960*640/720)/2+x*640/720,38+y*640/720 end
    local Enemy=require('src.critter_crisis_enemy')
    local Protocol=require('src.net.protocol')
    local function session()
        Crisis.clear();Screen.enter();assert(Screen.command(runtime,'start_solo'))
        return Crisis.sessions.front_left
    end
    capture('01-menu')
    local s=session()
    check('enemies start concealed',s.enemies[1].mode=='duck' and s.enemies[1].posture==0)
    local startY=s.enemies[1].y
    capture('02-behind-cover')
    local modes={};local positions={};local lastTravel=0;local monotonic=true
    for frame=1,840 do
        Crisis.update(1/60,function()return {buttons=Crisis.COVER} end)
        local e=s.enemies[1];modes[e.mode]=true
        monotonic=monotonic and e.travel>=lastTravel;lastTravel=e.travel
        if not positions[e.mode] then positions[e.mode]={x=e.x,y=e.y} end
        if frame==105 then capture('03-peeking') end
        if e.mode=='moving' and e.travel>55 and not positions.capturedMovement then
            positions.capturedMovement=true;s.players[1].covered=false;capture('04-advancing');s.players[1].covered=true
        end
        if frame%12==0 and frame<=384 then
            s.players[1].covered=false;capture(string.format('motion-%03d',frame/12));s.players[1].covered=true
        end
    end
    check('gait distance is monotonic',monotonic)
    for mode in pairs(Enemy.MODES) do check('enemy enters '..mode,modes[mode]) end
    check('enemy advances toward player',s.enemies[1].y>startY+100)
    check('cover protects player through attacks',s.players[1].hp==5)
    local e=s.enemies[1];e.posture=1;e.mode='peek'
    local c=Enemy.cover(e)
    check('crate blocks torso shot',not Enemy.hittable(s,e,e.x,c.top+20))
    check('exposed head can be hit',Enemy.hittable(s,e,e.x,Enemy.body(e).top+22))
    e.posture=0
    check('ducked enemy cannot be hit',not Enemy.hittable(s,e,e.x,Enemy.body(e).top+10))
    e.posture=1
    s.partnerId=2;s.mode='coop';s.players[2]={id=2,hp=5,ammo=8,covered=false,reload=0,aimX=480,aimY=310,shot=0}
    s.level=3;s.stop=4;s.enemies={Enemy.new(1,3,4),Enemy.new(2,3,4),Enemy.new(3,3,4)}
    for _,enemy in ipairs(s.enemies) do enemy.mode='peek';enemy.posture=1;enemy.travel=90 end
    local payload={sessionId='CRISIS_TEST',serverTick=42,bayId='front_left',session=Crisis.snapshot()[1]}
    local packet,err=Protocol.encode('crisis_snapshot',payload)
    check('coop motion snapshot encodes',packet,err)
    check('snapshot fits realtime packet',#packet<=Protocol.MAX_PACKET_BYTES,#packet)
    local decoded=assert(Protocol.decode(packet))
    check('snapshot preserves motion',decoded.payload.session.enemies[1].travel==90)
    local multiplayer=runtime.multiplayer
    runtime.multiplayer={isClient=function()return true end,crisisSnapshot=function()return {decoded.payload.session} end}
    capture('05-guest-boat-encounter')
    check('guest uses replicated cover and posture',Screen.sessionFor(runtime).enemies[1].posture==1)
    runtime.multiplayer=multiplayer
    payload.sessionId=string.rep('C',64);payload.serverTick=4294967295;payload.session.score=1000000
    for _,member in ipairs(payload.session.enemies) do member.travel=9999.9;member.x=920.9;member.y=560.9 end
    local worst,worstError=Protocol.encode('crisis_snapshot',payload)
    check('maximum coop animation packet fits MTU',worst and #worst<=1200,worstError or worst and #worst)
    payload.session.enemies[1].posture=2
    check('snapshot rejects invalid posture',not Protocol.encode('crisis_snapshot',payload))
    capture('05-boat-encounter')
    s=session();s.enemies[1].posture=1;s.enemies[1].mode='peek'
    local enemy=s.enemies[1];local targetY=Enemy.body(enemy).top+20
    Crisis.update(0,function()return {x=(enemy.x-480)/480,y=(targetY-339)/339,buttons=Crisis.FIRE} end)
    check('shot kills exposed critter',enemy.hp==0 and s.score==100)
    check('shot consumes round',s.players[1].ammo==7)
    Crisis.update(0,function()return {buttons=Crisis.FIRE} end)
    check('held trigger cannot repeat semiautomatic shot',s.players[1].ammo==7)
    Crisis.update(0,function()return {buttons=Crisis.RELOAD} end)
    for _=1,75 do Crisis.update(1/60,function()return {buttons=Crisis.COVER} end) end
    check('reload completes',s.players[1].ammo==8)
    s=session()
    local barrel=s.barrels[1]
    Crisis.update(0,function()return {x=(barrel.x-480)/480,y=(barrel.y-339)/339,buttons=Crisis.FIRE} end)
    check('supplied barrel is shootable and explodes',not barrel.alive and s.flash>0 and s.score>=130)
    -- Every route and enemy kind uses the same physical cover.
    for level=1,3 do
        s.level=level;s.stop=level==3 and 5 or 2
        s.enemies={}
        local _,count=Enemy.layout(s.level,s.stop)
        for index=1,count do s.enemies[index]=Enemy.new(index,s.level,s.stop);s.enemies[index].posture=1;s.enemies[index].mode='peek' end
        capture('route-'..level)
    end
    Crisis.clear();Screen.enter()
    for _,entry in ipairs({{'4','range'},{'5','stand'},{'6','train'}}) do
        Screen.keypressed(runtime,entry[1]);Screen.keypressed(runtime,'1');check(entry[2]..' launches through cabinet',Frontier.kind==entry[2])
        capture(entry[2]..'-start')
        if entry[2]=='range' then
            Screen.keypressed(runtime,'return');step(1.4)
            check('range round starts and spawns targets',Frontier.state.phase=='play' and #Frontier.state.targets>0)
            local before=Frontier.state.shots
            Screen.mousemoved(runtime,pointer(320,310))
            Screen.keypressed(runtime,'space');Screen.keyreleased('space')
            check('range fires a round',Frontier.state.shots>before)
            Screen.mousepressed(runtime,500,280,2);Screen.mousereleased(2)
            check('range releases aimed view',Frontier.state.aimMode=='hip')
            capture('range-play')
            Frontier.state.time=.01;step(.1)
            check('range reaches results',Frontier.state.phase=='results')
            capture('range-results')
            Screen.keypressed(runtime,'return');Screen.keypressed(runtime,'return')
            check('range replays',Frontier.state.phase=='play')
        elseif entry[2]=='stand' then
            step(2)
            check('last stand spawns opponents',Frontier.state.targets[1].status~='hidden')
            Screen.keypressed(runtime,'space');Screen.keyreleased('space')
            Screen.keypressed(runtime,'r');step(.2);capture('stand-reload')
            Screen.keypressed(runtime,'c');step(.4)
            check('last stand crouches',Frontier.state.coverProgress==1)
            capture('stand-cover')
            Screen.keypressed(runtime,'c');step(.4)
            Screen.mousepressed(runtime,500,280,2);Screen.mousereleased(2)
            check('last stand releases sights',not Frontier.state.gun.ads)
            for _=1,3 do Screen.keypressed(runtime,'tab');step(.1);capture('stand-weapon-'.._) end
            local x,y=pointer(310,650);Frontier.touchpressed('aim',x,y);Frontier.touchreleased('aim')
            check('last stand touch aim toggles sights',Frontier.state.gun.ads)
            local fx,fy=pointer(880,640);Frontier.touchpressed('fire',fx,fy)
            local ax,ay=pointer(400,300);Frontier.touchpressed('drag',ax,ay);Frontier.touchreleased('drag')
            check('aim finger release preserves held fire',Frontier.state.gun.fireHeld)
            Frontier.touchreleased('fire');check('fire finger release clears held fire',not Frontier.state.gun.fireHeld)
            Frontier.state.elapsed=44.99;step(.1)
            check('last stand pauses at intermission',Frontier.state.result=='intermission')
            capture('stand-intermission');Screen.keypressed(runtime,'return')
            check('last stand resumes next wave',Frontier.state.result==nil)
            Frontier.state.quest.positionIntegrity=0;step(.1)
            check('last stand reaches retreat',Frontier.state.result=='retreat')
            capture('stand-retreat');Screen.keypressed(runtime,'return')
            check('last stand retries',Frontier.state.result==nil and Frontier.state.quest.positionIntegrity>0)
            Frontier.state.elapsed=180;Frontier.state.stage=4;Frontier.state.quest.kills=15;Frontier.state.quest.enemyMorale=0
            step(5.2);check('last stand completes victory',Frontier.state.result=='victory');capture('stand-victory')
        else
            step(5)
            check('train reaches combat',Frontier.data.trainAmbush.phase=='combat')
            capture('train-combat')
            Screen.keypressed(runtime,'c');step(.4)
            check('train cover blocks exposure',Frontier.data.trainAmbush.coverProgress==1)
            capture('train-cover');Screen.keypressed(runtime,'c');step(.4)
            for _=1,3 do Screen.keypressed(runtime,'tab');step(.1);capture('train-weapon-'.._) end
            Screen.keypressed(runtime,'x');step(2.2)
            check('train withdraw reaches result',Frontier.data.trainAmbush.phase=='result')
            capture('train-result');Screen.keypressed(runtime,'return');step(.1)
            check('train result returns to cabinet',not Frontier.active())
            Screen.keypressed(runtime,'6')
        end
        if Frontier.active() then
            Screen.focus(false);Screen.keypressed(runtime,'p');step(.1)
            capture(entry[2]..'-mobile',1280,720)
            Screen.keypressed(runtime,'escape')
        end
        check(entry[2]..' exits to menu',not Frontier.active())
    end
    Screen.enter();capture('menu-mobile',720,509)
    local Cabinet=require('src.screens.critter_kombat_screen')
    local pad={axes={},isConnected=function()return true end,getGamepadAxis=function(self,name)return self.axes[name] or 0 end}
    Cabinet.enter(runtime,'front_left');Cabinet.keypressed(runtime,'2')
    for _=1,4 do Cabinet.gamepadpressed(runtime,pad,'dpdown') end
    Cabinet.gamepadpressed(runtime,pad,'a')
    Cabinet.gamepadpressed(runtime,pad,'dpup');Cabinet.gamepadpressed(runtime,pad,'a')
    check('controller launches Last Stand from actual cabinet',Frontier.kind=='stand')
    Cabinet.gamepadpressed(runtime,pad,'a');Cabinet.gamepadreleased(runtime,pad,'a')
    check('cabinet forwards controller release',not Frontier.state.gun.fireHeld)
    Cabinet.mousepressed(runtime,500,280,2);Cabinet.mousereleased(500,280,2)
    check('cabinet forwards right mouse release',not Frontier.state.gun.ads)
    Frontier.update(1/60);pad.axes.triggerright=1;Frontier.update(1/60)
    check('controller trigger holds fire',Frontier.state.gun.fireHeld)
    Cabinet.cancelInputs(true)
    check('cabinet focus loss pauses and clears fire',Frontier.paused and not Frontier.state.gun.fireHeld)
    Cabinet.cancelInputs(false);pad.axes.triggerright=0;Frontier.keypressed('p');Frontier.update(1/60)
    pad.axes.triggerleft=1;Frontier.update(1/60)
    check('controller trigger raises sights',Frontier.state.gun.ads)
    Cabinet.touchpressed(runtime,'aim',450,310)
    local tx,ty=pointer(880,645);Cabinet.touchpressed(runtime,'fire',tx,ty)
    capture('stand-touch-controls')
    check('touch controls are visible',Frontier.state.touchControls)
    Cabinet.touchreleased('aim');Cabinet.touchreleased('fire')
    Cabinet.leave(runtime)
    check('leaving actual cabinet releases imported session',not Frontier.active() and runtime.state.screen=='world')
    report:write('COMPLETE '..checks..' checks\n');report:close()
end
return Review
