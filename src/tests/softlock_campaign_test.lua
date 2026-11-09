-- Deterministic interruption campaigns. Every rejected/interrupted action must
-- be followed by a successful, bounded recovery through the real game API.
local State=require('src.state')
local Calendar=require('src.business_calendar')
local Residents=require('src.home_residents')
local Schema=require('src.save_schema')
local Layout=require('src.home_layouts')
local Grocery=require('src.commute.grocery_interior')
local Test={}

local function clock(state,hours)
    local seconds=Calendar.secondsPerDay(state)
    state.calendar=Calendar.dateFromHours(hours)
    state.calendar.secondsPerDay=seconds;state.calendar.elapsed=hours%24/24*seconds
end
local function random(seed)
    return function(n) seed=seed*48271%2147483647;return seed%n+1 end
end
local function shuffle(items,rng)
    local result={};for i,v in ipairs(items) do result[i]=v end
    for i=#result,2,-1 do local j=rng(i);result[i],result[j]=result[j],result[i] end
    return result
end
local actions={'drink:sink','wash:basin','bathe:bath','toilet:toilet',
    'rest:floor','eat:floor','sandwich:floor','bottle:floor','sleepfloor:floor','prepare:sink'}
local interruptions={'cancel','walk_away','leave_scene','disconnect','reload'}

local function household(context,check,rng)
    local recovered=0
    for _,apartment in ipairs(require('src.home_catalog').ORDER) do
        for _,command in ipairs(shuffle(actions,rng)) do
            for _,interruption in ipairs(shuffle(interruptions,rng)) do
                local state=State.new();state.home.apartmentId=apartment
                state.home.weekend.phase='home';state.home.weekend.closedAtHours=44
                state.home.furniture.items={}
                clock(state,44)
                for _,need in ipairs(Residents.NEEDS) do state.home.residents.owner[need]=10 end
                local kind,target=command:match('^(%w+):(%w+)$')
                local definition=Residents.ACTIONS[kind]
                if definition.item then state.home.inventory[definition.item]=2 end
                state.home.inventory.bread=2;state.home.inventory.vegetables=2
                local x,y=Layout.spawn(state,1)
                if target~='floor' then x,y=Layout.toWorld(unpack(Layout.get(state).fixtures[target].approach)) end
                local player={id=1,x=x,y=y,sceneId='home',resting=false}
                local prefix='softlock_home_'..apartment..'_'..kind..'_'..interruption
                local function advance(hours,present)
                    local first=Calendar.absoluteHours(state)
                    clock(state,first+hours)
                    Residents.advance(state,present or {player},first,first+hours)
                end
                local okay,code,message=Residents.command(state,player,command)
                check(prefix..'_starts',okay,tostring(code)..': '..tostring(message))
                local stock=definition.item and state.home.inventory[definition.item]
                check(prefix..'_duplicate_rejected',not Residents.command(state,player,command)
                    and (not stock or state.home.inventory[definition.item]==stock))
                advance(definition.minutes/60*(rng(20)+5)/100)
                if interruption=='cancel' then assert(Residents.command(state,player,'cancel'))
                elseif interruption=='walk_away' then player.x=x+60;advance(.001);player.x=x
                elseif interruption=='leave_scene' then player.sceneId='warehouse';advance(.001);player.sceneId='home'
                elseif interruption=='disconnect' then advance(.001,{})
                else
                    assert(context.save.save(3,state,{x=x,y=y,sceneId='home'}))
                    local saved=assert(context.save.load(3))
                    state=State.new();assert(State.applyLocalSave(state,saved))
                    Residents.recover(state)
                    player={id=1,x=x,y=y,sceneId='home',resting=false}
                end
                -- Disconnected actors are recreated on reconnect, as in runtime.
                if interruption=='disconnect' then player={id=1,x=x,y=y,sceneId='home',resting=false} end
                check(prefix..'_released',not Residents.get(state,player).activity and not player.resting)
                local restarted,restartCode,restartMessage=Residents.command(state,player,command)
                check(prefix..'_restarts',restarted,tostring(restartCode)..': '..tostring(restartMessage))
                local before=Residents.get(state,player)
                local endAt=Residents.activityEndAt(state,before,before.activity)
                for _=1,180 do
                    if not Residents.get(state,player).activity then break end
                    advance(definition.minutes/60/(45+rng(30)))
                end
                local person=Residents.get(state,player)
                check(prefix..'_completes',not person.activity and not player.resting
                    and Calendar.absoluteHours(state)>=endAt-1e-7)
                if definition.item then
                    check(prefix..'_consumes_once_per_attempt',state.home.inventory[definition.item]==0)
                elseif kind=='prepare' then
                    check(prefix..'_cooking_recovers_without_duplicate_food',state.home.inventory.bread==0
                        and state.home.inventory.vegetables==0 and state.home.inventory.rough_sandwich==2)
                end
                local snapshot,reason=Schema.snapshot(state)
                check(prefix..'_durable',snapshot and Schema.validState(snapshot),reason)
                recovered=recovered+1
            end
        end
    end
    check('softlock_household_all_interruptions_recover',recovered==#require('src.home_catalog').ORDER*#actions*#interruptions)
end

local function grocery(check,rng)
    for _,shared in ipairs({false,true}) do
        local state=State.new();state.screen='world'
        if shared then state.home.commute={independent=true,participants={}} end
        local player={id=1,x=480,y=548,intentX=0,intentY=-1,sceneId='grocery',
            velocityX=0,velocityY=0,animationDistance=0,idleClock=0}
        local inputX,inputY=0,0
        local R={state=state,World={player=player},Config={baseWidth=960,baseHeight=678},
            Input={movement=function()return inputX,inputY end}}
        local view=Grocery.new(R)
        local function tick()
            local action=Grocery.update(view,R,1/60)
            if shared then
                player.cartPushing=view.pose.cartPushing
                Grocery.movePose(player,view.netInputX or 0,view.netInputY or 0,1/60,state)
            end
            return action
        end
        assert(Grocery.keypressed(view,'e')=='cartpush_on')
        for step=1,36 do
            local prefix='softlock_grocery_'..tostring(shared)..'_'..step
            local destination=Grocery.hotspots[rng(#Grocery.hotspots)]
            Grocery.pointer(view,R,destination.x,destination.y)
            for _=1,rng(12) do tick() end
            state.screen='options';tick();state.screen='world'
            -- Manual movement interrupts click-to-walk, then a new destination
            -- must still be reachable from the resulting position.
            inputX,inputY=(rng(3)-2),(rng(3)-2)
            for _=1,6 do tick() end
            inputX,inputY=0,0
            local action=Grocery.pointer(view,R,destination.x,destination.y)
            for _=1,1800 do if action then break end;action=tick() end
            check(prefix..'_reaches_destination',action==destination.id,
                ('target=%s pose=%.2f,%.2f waypoints=%s'):format(destination.id,view.pose.x,view.pose.y,
                    require('src.net.codec').encode(view.path or {})))
            if step%6==0 then
                assert(Grocery.keypressed(view,'f')=='cartpush_off')
                Grocery.pointer(view,R,520,548)
                for _=1,1800 do
                    if (view.pose.x-520)^2+(view.pose.y-548)^2<=50^2 then break end
                    tick()
                end
                check(prefix..'_can_retrieve_returned_cart',Grocery.keypressed(view,'e')=='cartpush_on')
            end
        end
        -- Selecting a shelf already in reach supersedes a pending walk to a
        -- different shelf, so closing its menu cannot resume that old intent.
        local produce=Grocery.hotspots[1]
        local action=Grocery.pointer(view,R,produce.x,produce.y)
        for _=1,1800 do if action then break end;action=tick() end
        assert(action==produce.id)
        Grocery.pointer(view,R,726,276)
        check('softlock_grocery_nearby_shelf_cancels_old_route_'..tostring(shared),
            Grocery.pointer(view,R,produce.x,produce.y)==produce.id and view.path==nil
            and view.pathAction==nil and view.netInputX==0 and view.netInputY==0)
        check('softlock_grocery_interruptions_recover_'..tostring(shared),view.pose.cartPushing)
    end
end

local function highFives(check)
    local Session=require('src.net.session')
    local Protocol=require('src.net.protocol')
    for _,mode in ipairs({'decline','walk_away','leave_scene','disconnect','expire'}) do
        local now=10
        local session=Session.new({clock=function()return now end})
        session.ready=true;session.localId=1;session.sessionId='softlock-social'
        session.players={[1]={id=1,name='Host',x=100,y=100,sceneId='warehouse'},
            [2]={id=2,name='Guest',x=110,y=100,sceneId='warehouse'}}
        session.idToPeer[2]='guest'
        session._send=function(_,_,kind,payload)return Protocol.encode(kind,payload)~=nil end
        session._broadcastJoined=function(_,kind,payload)return Protocol.encode(kind,payload)~=nil end
        local accepted,id=session:_createHighFive(1,2);assert(accepted)
        check('softlock_highfive_'..mode..'_duplicate_rejected',not session:_createHighFive(1,2))
        if mode=='disconnect' then session:_clearHighFivesForPlayer(2)
        elseif mode=='expire' then now=110;session:_processHostHighFives()
        else
            if mode=='walk_away' then session.players[2].x=900 end
            if mode=='leave_scene' then session.players[2].sceneId='home' end
            assert(session:_resolveHighFive(id,2,mode~='decline'))
        end
        check('softlock_highfive_'..mode..'_released',next(session.pendingHighFives)==nil
            and next(session.activeHighFives)==nil and not session:_resolveHighFive(id,2,true))
        now=now+100;session.players[2].x=110;session.players[2].sceneId='warehouse'
        local restarted,newId=session:_createHighFive(1,2);assert(restarted)
        local resolved,status=session:_resolveHighFive(newId,2,true)
        check('softlock_highfive_'..mode..'_restarts',resolved and status=='accepted'
            and session.activeHighFives[newId]~=nil and not session:_resolveHighFive(newId,2,true))
        now=now+10;session:_processHostHighFives()
        check('softlock_highfive_'..mode..'_completes',next(session.activeHighFives)==nil
            and not session:_highFivePlayerBusy(1,now) and not session:_highFivePlayerBusy(2,now))
    end
end

function Test.run(context,check)
    local seed=tonumber(os.getenv('PICTURE_SHOP_GAMEPLAY_SEED')) or 104729
    assert(seed>=1 and seed<2147483647 and seed%1==0,'Invalid gameplay campaign seed')
    print('GAMEPLAY_CAMPAIGN_SEED '..seed)
    local rng=random(seed)
    household(context,check,rng)
    grocery(check,rng)
    highFives(check)
    check('softlock_campaign_completed',true,'seed='..seed)
end
return Test
