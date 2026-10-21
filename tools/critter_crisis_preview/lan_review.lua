local Review={}
function Review.run(check,phoneChecks)
    local Crisis=require('src.critter_crisis')
    local Session=require('src.net.session')
    local Games=require('src.breakroom_games')
    local state=require('src.state').new();state.money=50000
    local upgrades=require('src.warehouse_upgrades')
    assert(upgrades.purchase(state,'front_left','breakroom','CRISIS-ROOM',0))
    upgrades.update(state,0);upgrades.update(state,0,{noticeDeliveredProjectId='WUP-0001',noticeCallId='CRISIS-CALL'})
    upgrades.update(state,2,{workerArrivedProjectId='WUP-0001'})
    upgrades.update(state,98);upgrades.update(state,98,{workerReleasedProjectId='WUP-0001'})
    assert(Games.purchase(state,'front_left','critter_kombat','CRISIS-CABINET'))
    local fixture=Games.CATALOG.critter_kombat
    local hp={id=1,x=fixture.interactionX,y=fixture.interactionY,sceneId='front_left',character='rabbit-worker'}
    local gp={id=2,x=hp.x,y=hp.y,sceneId='front_left',character='rabbit-worker'}
    local now=0
    local host=Session.new({clock=function()return now end})
    local guest=Session.new({clock=function()return now end})
    local hc={localPlayer=hp,moveRemote=function()end,resolveGuestSpawn=function()return gp.x,gp.y end,
        getShopSnapshot=function()return {state=assert(require('src.save_schema').snapshot(state)),player={x=hp.x,y=hp.y,character=hp.character}}end,
        getCrisisSnapshot=Crisis.snapshot,getCrisisEncounters=function()return Crisis.sessions end,
        performInteraction=function(p,kind,command)
            local okay,code,message=Crisis.command(state,p,command:match('^critter_crisis:(.+)$'))
            return okay,code,message,kind
        end}
    local gc={localPlayer=gp,inputX=0,inputY=0,gameX=0,gameY=0,combatButtons=0}
    assert(host:startHost({name='Crisis Test Host',character='rabbit-worker',bind='127.0.0.1',port=22967,
        addressOptions={socket={dns={gethostname=function()return 'localhost'end,toip=function()return '192.168.1.2'end}}}}))
    assert(guest:startClient('127.0.0.1:22967',{name='Crisis Test Guest',character='rabbit-worker'}))
    local hostInput={buttons=2}
    local devices
    local function pump(count)
        for _=1,count do
            if devices then
                gc.arcade=devices.guest.screen.arcadeInputs(devices.guest.runtime);gc.combatButtons=0
                local packet=devices.host.screen.arcadeInputs(devices.host.runtime)
                hostInput=packet and require('src.critter_crisis_actions').seat(packet,false,packet.roundId) or {}
            end
            now=now+.01;host:update(.01,hc);guest:update(.01,gc)
            Crisis.update(.01,function(id,session)
                if id==1 then return hostInput end
                local remote=host.players[id==0 and 2 or id]
                if not remote or now-(remote.lastInputAt or 0)>.35 then return nil end
                if remote.arcadeInput then
                    local a=remote.arcadeInput
                    return require('src.critter_crisis_actions').seat(a,id==0,session.roundId)
                end
                return {x=remote.gameInputX,y=remote.gameInputY,buttons=remote.combatButtons}
            end)
            love.timer.sleep(.001)
        end
    end
    pump(100);check('ENet loopback guest joins shop',guest.ready)
    host.players[2].sceneId='front_left'
    for _,kind in ipairs({'mission','range','stand','train'}) do
        Crisis.clear();gc.arcade=nil;gc.combatButtons=2;hostInput={buttons=2}
        local action=kind=='mission' and 'start_coop' or 'start_'..kind..'_coop'
        assert(Crisis.command(state,hp,action));pump(25)
        local s=Crisis.sessions.front_left
        check(kind..' LAN waiting session reaches guest',guest:crisisSnapshot()[1].phase=='waiting')
        assert(guest:requestInteraction('roomGame','critter_crisis:join'));pump(200)
        check(kind..' LAN join starts shared encounter',s.partnerId==2 and s.phase=='playing' and guest:crisisSnapshot()[1].phase=='playing')
        if kind~='mission' then check(kind..' ENet sends complete frontier frame',guest:crisisFrontier(guest:crisisSnapshot()[1])) end
        local ammo1,ammo2=s.players[1].ammo,s.players[2].ammo
        if kind=='mission' then gc.combatButtons=1
        else gc.arcade={x=-.5,y=-.2,buttons=1,x2=0,y2=0,buttons2=0};gc.combatButtons=0 end
        pump(45)
        check(kind..' guest trigger changes only guest weapon',s.players[2].ammo==ammo2-1 and s.players[1].ammo==ammo1)
        gc.combatButtons=0;if gc.arcade then gc.arcade.buttons=0 end;pump(45)
        hostInput={x=.5,y=-.2,buttons=1};pump(45)
        check(kind..' host trigger changes only host weapon',s.players[1].ammo==ammo1-1)
        local replica=guest:crisisSnapshot()[1]
        local mine
        for _,p in ipairs(replica.players)do if p.id==2 then mine=p end end
        check(kind..' guest receives authoritative ammo',mine.ammo==s.players[2].ammo)
        if kind~='mission' then
            local frame=guest:crisisFrontier(replica)
            local parts,wireError=require('src.critter_crisis_wire').parts(s)
            local decoded,decodeError
            if parts then decoded,decodeError=require('src.critter_crisis_wire').decode(table.concat(parts)) end
            check(kind..' guest shares host world clock',frame and math.abs(frame.world.clock-s.frontier.world.clock)<.5,
                tostring(frame and frame.world.clock)..' vs '..s.frontier.world.clock..' / '..tostring(wireError)..' / '..tostring(decodeError)..' decoded '..tostring(decoded))
        end
        hostInput={buttons=2};gc.combatButtons=2;if gc.arcade then gc.arcade.buttons=2 end
        local previous=s.roundId;s.phase='finished';pump(25);assert(Crisis.command(state,hp,'restart'));pump(40)
        check(kind..' LAN rematch retains guest and replaces round',guest:crisisSnapshot()[1].roundId>previous and Crisis.sessions.front_left.partnerId==2)
        assert(guest:requestInteraction('roomGame','critter_crisis:leave'));pump(35)
        check(kind..' guest leave clears both cabinets',not Crisis.sessions.front_left and #guest:crisisSnapshot()==0)
    end
    assert(guest:requestInteraction('roomGame','critter_crisis:start_range_local'));pump(50)
    gc.arcade={x=-.5,y=-.2,buttons=0,x2=.5,y2=-.2,buttons2=1};pump(30)
    local s=Crisis.sessions.front_left
    check('LAN guest can run two seats on their own machine',s.ownerId==2 and s.mode=='local' and s.players[0].ammo==11 and s.players[2].ammo==12)
    if phoneChecks then
        local Devices=require('tools.critter_crisis_preview.phone_devices')
        for _,roles in ipairs({{true,true,'phone-phone'},{false,true,'PC-phone'},{true,false,'phone-PC'}}) do
            for _,kind in ipairs({'mission','range','stand','train'}) do
                Crisis.clear();devices=nil;gc.arcade=nil;hostInput={};pump(30)
                assert(Crisis.command(state,hp,kind=='mission' and 'start_coop' or 'start_'..kind..'_coop'))
                devices={host=Devices.new({state=state,World={player=hp},multiplayer=host},roles[1]),
                    guest=Devices.new({state={roomGameBay='front_left'},World={player=gp},multiplayer=guest},roles[2])}
                pump(30);devices.guest.screen.keypressed(devices.guest.runtime,'3');pump(185)
                local encounter=Crisis.sessions.front_left
                local label=roles[3]..' '..kind
                check(label..' has one player per device',encounter.mode=='coop' and encounter.partnerId==2)
                devices.host.input.aim(1,480,300);devices.guest.input.aim(1,480,300)
                local first,second=encounter.players[1].ammo,encounter.players[2].ammo
                devices.host:tap('fire');devices.guest:tap('fire')
                check(label..' quick taps finish before network sample',devices.host.input.packet().buttons==0 and devices.guest.input.packet().buttons==0)
                pump(40)
                check(label..' both quick taps arrive once',encounter.players[1].ammo==first-1 and encounter.players[2].ammo==second-1)
                pump(50)
                check(label..' repeated packets do not repeat shots',encounter.players[1].ammo==first-1 and encounter.players[2].ammo==second-1)
                devices.guest:tap('reload');pump(15)
                check(label..' quick reload stays personal',encounter.players[2].reload>0 and encounter.players[1].reload==0)
                devices.host.screen.focus(false);devices.guest.screen.focus(false);pump(10)
                check(label..' focus clears held actions',hostInput.buttons==0 and gc.arcade.buttons==0)
                devices.host.screen.focus(true);devices.guest.screen.focus(true)
                encounter.phase='finished';local oldRound=encounter.roundId;pump(30)
                devices.host:tap('restart');pump(35)
                check(label..' restart works without a keyboard',Crisis.sessions.front_left.roundId>oldRound and Crisis.sessions.front_left.partnerId==2)
            end
        end
    end
    local errors={}
    for _,session in ipairs({host,guest})do for _,event in ipairs(session:drainEvents())do if event.type=='error' then errors[#errors+1]=event.message end end end
    check('ENet co-op sessions have no protocol errors',#errors==0,table.concat(errors,' / '))
    host:stop('Review complete');guest:stop('Review complete');Crisis.clear()
    check('disconnect clears replicated encounter frames',not next(guest.crisisFrames) and not next(guest.crisisAssembly))
end
return Review
