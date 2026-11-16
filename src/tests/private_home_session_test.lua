local Session=require('src.net.session')
local Protocol=require('src.net.protocol')
local Harness=require('src.tests.support.network_impairment_harness')
local Residents=require('src.home_residents')
local Travel=require('src.home_travel')
local Layout=require('src.home_layouts')
local Schema=require('src.save_schema')
local Households=require('src.client_households')
local Test={}

local function player(id)
    return {id=id,x=720,y=202,sceneId='warehouse',velocityX=0,velocityY=0,intentX=1,intentY=0,
        moving=false,facing=1,animationDistance=0,character='rabbit-worker'}
end

function Test.run(context,check)
    local state=context.State.new()
    state.home.weekend.phase='ready'
    state.home.weekend.closedAtHours=44
    local now=0
    local network=Harness.new({maxClients=3,classify=function(bytes)
        local value=Protocol.decode(bytes)
        return value and value.type or 'invalid'
    end})
    local host=Session.new({transportFactory=network.factory,clock=function()return now end})
    local hp=player(1)
    local guests,avatars,contexts,received={},{},{},{}
    local function players()
        local result={hp}
        for id,p in pairs(host.players) do if id~=1 then result[#result+1]=p end end
        return result
    end
    local function command(p,cmd)
        local ok,code,message=Travel.command(state,p,cmd,{world={truck={state='absent'}},players=players})
        if ok then host:markShopDirty() end
        return ok,code,message,'homeTravel'
    end
    local runtime={state=state,saveCurrent=function()end}
    local hc={localPlayer=hp,moveRemote=function()end,
        bindResident=function(p,credential,connected)
            local id,reason=Residents.bind(state,p,credential,connected)
            if id then host:markShopDirty() end
            return id,reason
        end,
        resolveGuestSpawn=function(x,y,id)
            Travel.guestJoined(state,id)
            if hp.sceneId=='home' then
                local p=host.players[id]
                local home=Households.forPlayer(state,p)
                local a,b=Layout.spawn({home=home},1)
                return a,b,'home'
            end
            return x+id*20,y
        end,
        getShopSnapshot=function()
            return {state=assert(Schema.snapshot(state)),player={x=hp.x,y=hp.y,sceneId=hp.sceneId,character=hp.character}}
        end,
        performInteraction=function(p,kind,cmd)
            if kind=='homeTravel' then return command(p,cmd) end
            if kind=='homeActivity' then
                return Households.withPlayer(runtime,p,function()
                    local ok,code,message=Residents.command(state,p,cmd)
                    if ok then host:markShopDirty() end
                    return ok,code,message,'homeActivity'
                end)
            end
        end}
    assert(host:startHost({name='Private Home Host',character=hp.character,addressOptions={socket={dns={
        gethostname=function()return 'private-home-host'end,getaddrinfo=function()return {{addr='192.168.1.93'}}end}}}}))
    host.sessionId='private-home-session'
    local function pump(count)
        for _=1,count or 8 do
            now=now+.1;network:advanceSteps(1)
            for i,g in pairs(guests) do g:update(.1,contexts[i]) end
            host:update(.1,hc)
            for i,g in pairs(guests) do
                g:update(0,contexts[i])
                for _,event in ipairs(g:drainEvents()) do
                    received[i]=received[i] or {}
                    received[i][event.type]=event
                    if event.type=='ready' then
                        for key,value in pairs(event.spawn) do avatars[i][key]=value end
                    end
                end
            end
            host:drainEvents()
        end
    end
    local function join(i)
        local g=Session.new({transportFactory=network.factory,clock=function()return now end})
        guests[i]=g;avatars[i]=player(i+1);contexts[i]={localPlayer=avatars[i],inputX=0,inputY=0}
        assert(g:startClient('192.168.1.93:22122',{name='Guest '..i,character='rabbit-worker',residentToken=string.rep(tostring(i),64)}))
        g.clientNonce='private-home-'..i..'-'..math.floor(now*10)
        pump(10)
        return g
    end
    for i=1,3 do check('private_home_join_'..i,join(i).ready) end
    local apartmentIds={}
    for i=1,3 do
        local id=guests[i].residentId
        local home=assert(Households.forPlayer(state,host.players[i+1]))
        apartmentIds[home.apartmentId]=true
        check('private_home_assigned_'..i,home.apartmentId~=state.home.apartmentId and home.balanceCents~=nil)
    end
    local count=0;for _ in pairs(apartmentIds) do count=count+1 end
    check('private_home_four_distinct_apartments',count==3)
    assert(command(hp,'request'));pump()
    local token=state.home.weekend.travelToken
    assert(command(hp,'force:'..token));pump(15)
    check('private_home_everyone_arrives',hp.sceneId=='home' and state.home.weekend.phase=='home')
    for i=1,3 do
        local home=Households.forPlayer(state,host.players[i+1])
        local x,y=Layout.spawn({home=home},1)
        check('private_home_spawn_'..i,avatars[i].sceneId=='home' and math.abs(avatars[i].x-x)<1 and math.abs(avatars[i].y-y)<1)
    end
    local first=host.players[2]
    local second=host.players[3]
    local firstHome=Households.forPlayer(state,first)
    local secondHome=Households.forPlayer(state,second)
    local x1,y1=Layout.toWorld(unpack(Layout.get({home=firstHome}).fixtures.bath.approach))
    local x2,y2=Layout.toWorld(unpack(Layout.get({home=secondHome}).fixtures.bath.approach))
    first.x,first.y=x1,y1;second.x,second.y=x2,y2
    assert(guests[1]:requestInteraction('homeActivity','bathe:bath'));pump()
    assert(guests[2]:requestInteraction('homeActivity','bathe:bath'));pump()
    assert(received[1].interaction_result.accepted and received[2].interaction_result.accepted,
        tostring(received[1].interaction_result.message)..' / '..tostring(received[2].interaction_result.message))
    check('private_home_independent_bathrooms',true)
    local durable=assert(Schema.snapshot(state))
    check('private_home_save_includes_three_households',require('src.home').valid(durable.home) and durable.home.clientHomes[guests[1].residentId]~=nil
        and durable.home.clientHomes[guests[2].residentId]~=nil and durable.home.clientHomes[guests[3].residentId]~=nil)
    local id=guests[1].residentId
    guests[1]:stop();pump();join(1)
    check('private_home_reconnect_restores_resident',guests[1].residentId==id and avatars[1].sceneId=='home')
end
return Test
