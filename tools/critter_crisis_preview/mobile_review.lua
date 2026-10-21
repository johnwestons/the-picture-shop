local Review={}
function Review.run(runtime,Screen,Crisis,Arcade,destination)
    local report=assert(io.open(destination..'/review.txt','w'));local count=0
    local function check(name,ok,detail)
        assert(ok,name..': '..tostring(detail or 'failed'));count=count+1;report:write('PASS '..name..'\n');report:flush()
    end
    local Devices=require('tools.critter_crisis_preview.phone_devices')
    local Actions=require('src.critter_crisis_actions')
    local Protocol=require('src.net.protocol')
    local serialPlayer={sequences={65535,0,0,0,0,0}}
    check('press counter wraps once',Actions.consume(serialPlayer,{sequences=Actions.blank()})==1)
    check('old counter cannot rewind actions',Actions.consume(serialPlayer,{sequences={65535,0,0,0,0,0}})==0
        and Actions.consume(serialPlayer,{sequences=Actions.blank()})==0)
    check('focus cancellation consumes queued taps',Actions.consume(serialPlayer,{sequences={1,0,0,0,0,0},suspended=true})==0
        and Actions.consume(serialPlayer,{sequences={1,0,0,0,0,0}})==0)
    local original=runtime.multiplayer
    local device=Devices.new(runtime,true);Screen=device.screen
    local function capture(name,width,height)
        width,height=width or 960,height or 678
        local canvas=love.graphics.newCanvas(width,height)
        love.graphics.push('all');love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.008,.012,.02,1)
        local left,right=width>960 and 42 or 0,width>960 and 24 or 0
        local scale=math.min((width-left-right)/960,height/678)
        love.graphics.translate(left+(width-left-right-960*scale)/2,(height-678*scale)/2);love.graphics.scale(scale)
        Screen.draw(runtime);love.graphics.pop()
        local pixels=canvas:newImageData();local encoded=pixels:encode('png')
        local file=assert(io.open(destination..'/'..name..'.png','wb'));file:write(encoded:getString());file:close()
        pixels:release();encoded:release();canvas:release()
    end
    capture('01-phone-menu',1280,720)
    runtime.multiplayer={isClient=function()return false end,isActive=function()return false end}
    Screen.keypressed(runtime,'2');check('offline co-op explains connecting devices',Screen.connectionHelp and not next(Crisis.sessions))
    capture('02-connection-help',1280,720);Screen.keypressed(runtime,'escape');runtime.multiplayer=original
    for _,kind in ipairs({'mission','range','stand','train'}) do
        Crisis.clear();Screen.enter()
        assert(Screen.command(runtime,kind=='mission' and 'start_coop' or 'start_'..kind..'_coop'))
        local session=Crisis.sessions.front_left
        capture(kind..'-waiting',1280,720)
        assert(Crisis.command(runtime.state,{id=2,x=runtime.World.player.x,y=runtime.World.player.y,sceneId='front_left'},'join'))
        for _=1,120 do Crisis.update(1/60,function()return {}end) end
        Screen.arcadeInputs(runtime)
        if kind=='mission' then
            local dimensions,safeArea=love.graphics.getDimensions,love.window.getSafeArea
            local viewport=runtime.Viewport;runtime.Viewport=require('src.viewport')
            love.graphics.getDimensions=function()return 1280,720 end
            love.window.getSafeArea=function()return 42,0,1214,720 end
            local ox,oy,scale=runtime.Viewport.transform(960,678,true)
            local id=newproxy();local aim=device.input.actors[1].x
            Screen.touchpressed(runtime,id,ox+140*scale,oy+610*scale)
            Screen.touchmoved(runtime,id,ox+185*scale,oy+580*scale)
            Screen.touchreleased(id)
            check('notched landscape phone transforms touch aim',math.abs(device.input.actors[1].x-aim-99)<.01 and device.input.packet().buttons==0)
            local fire=newproxy();Screen.touchpressed(runtime,fire,ox+840*scale,oy+610*scale)
            check('notched landscape phone transforms fire button',device.input.packet().buttons==1)
            Screen.touchreleased(fire)
            love.graphics.getDimensions=dimensions;love.window.getSafeArea=safeArea;runtime.Viewport=viewport
            device.input.configure({roundId=-1});device.input.configure(session)
        end
        local aimId,fireId,coverId=newproxy(),newproxy(),newproxy()
        local beforeX,beforeY=device.input.actors[1].x,device.input.actors[1].y
        Screen.touchpressed(runtime,aimId,140,610);Screen.touchmoved(runtime,aimId,185,580)
        local a=Screen.arcadeInputs(runtime)
        check(kind..' drag aims without firing',a.buttons==0 and device.input.actors[1].x>beforeX and device.input.actors[1].y<beforeY)
        Screen.touchpressed(runtime,coverId,410,610);Screen.touchpressed(runtime,fireId,840,610)
        check(kind..' aim cover and fire use separate fingers',device.input.packet().buttons==3)
        Screen.touchreleased(fireId);check(kind..' releasing fire preserves cover',device.input.packet().buttons==2)
        Screen.touchreleased(coverId);Screen.touchreleased(aimId)
        check(kind..' Android touch identifiers release cleanly',device.input.packet().buttons==0)
        local packet=device.input.packet()
        local encoded,err=Protocol.encode('input',{sessionId='PHONE',sequence=1,moveX=0,moveY=0,arcade=packet})
        check(kind..' touch packet fits LAN limit',encoded and #encoded<=1200,err)
        local decoded=assert(Protocol.decode(encoded)).payload.arcade
        local malformed=device.input.packet();malformed.sequences[1]=-1
        check(kind..' LAN rejects invalid press counter',not Protocol.encode('input',{sessionId='PHONE',sequence=1,moveX=0,moveY=0,arcade=malformed}))
        check(kind..' tap survives release before sampling',decoded.buttons==0 and decoded.sequences[1]==1)
        local other=Actions.seat(decoded,false,session.roundId)
        local before=session.players[1].ammo
        Crisis.update(0,function(id)return id==1 and other or {}end)
        check(kind..' tap fires after release',session.players[1].ammo==before-1)
        Crisis.update(.1,function(id)return id==1 and other or {}end)
        check(kind..' duplicate sample does not fire again',session.players[1].ammo==before-1)
        check(kind..' old-round input cannot fire in new round',not Actions.seat(decoded,false,session.roundId+1))
        capture(kind..'-phone',1280,720);capture(kind..'-small-phone',800,450)
        Screen.focus(false);check(kind..' background cancels fingers',device.input.packet().suspended and device.input.packet().buttons==0);Screen.focus(true)
        if kind=='stand' then
            session.frontier.world.result='intermission';capture('stand-next-wave',1280,720)
            device:tap('next');Crisis.update(.01,function(id)return id==1 and Actions.seat(device.input.packet(),false,session.roundId) or {}end)
            check('phone can advance Last Stand wave',not session.frontier.world.result)
        end
        session.phase='finished';capture(kind..'-phone-results',1280,720)
        local round=session.roundId;device:tap('restart')
        check(kind..' phone restarts team round',Crisis.sessions.front_left.roundId>round and Crisis.sessions.front_left.partnerId==2)
    end
    Crisis.clear();Screen.enter();runtime.multiplayer=original
    require('tools.critter_crisis_preview.lan_review').run(check,true)
    report:write('ALL '..count..' CHECKS PASSED\n');report:close()
end
return Review
