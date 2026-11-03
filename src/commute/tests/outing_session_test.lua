-- Real host/client packets exercise the outing command and snapshot boundaries.
local Session=require('src.net.session')
local Protocol=require('src.net.protocol')
local Harness=require('src.tests.support.network_impairment_harness')
local State=require('src.state')
local Schema=require('src.save_schema')
local Travel=require('src.home_travel')
local Trip=require('src.commute.trip')
local Residents=require('src.home_residents')
local Town=require('src.commute.town')
local Commute=require('src.commute.runtime')
local Test={}
function Test.run(check)
    local state=State.new();local world=Town.world(state.home.town);local now=0
    local network=Harness.new({maxClients=1,classify=function(bytes)local p=Protocol.decode(bytes);return p and p.type or 'invalid' end})
    local host=Session.new({transportFactory=network.factory,clock=function()return now end})
    local client=Session.new({transportFactory=network.factory,clock=function()return now end})
    local hp={id=1,homeResidentId='owner',sceneId='warehouse',x=720,y=202,character='rabbit-worker'}
    local gp={id=2,sceneId='warehouse',x=740,y=202,character='rabbit-worker'}
    local events={};local saves=0
    local R={state=state,World={player=hp},_commute={world=world},multiplayer=host,saveCurrent=function()saves=saves+1 end}
    local function players() local result={hp};for id,p in pairs(host.players)do if id~=1 then result[#result+1]=p end end;return result end
    local function travel(p,command)
        local okay,code,message=Travel.command(state,p,command,{world={truck={state='absent'}},commuteWorld=world,players=players})
        if okay then host:markShopDirty() end
        return okay,code,message,'homeTravel'
    end
    local hc={localPlayer=hp,moveRemote=function()end,
        bindResident=function(p,token,connected)return Residents.bind(state,p,token,connected)end,
        resolveGuestSpawn=function(x,y,id)Travel.guestJoined(state,id);return x+id*20,y end,
        getShopSnapshot=function()return {state=assert(Schema.snapshot(state)),player={x=hp.x,y=hp.y,sceneId=hp.sceneId,character=hp.character}}end,
        performInteraction=function(p,kind,command)
            if kind=='homeTravel' then return travel(p,command) end
            if kind=='commute' then return Commute.command(R,p,command) end
        end}
    local gc={localPlayer=gp,inputX=0,inputY=0}
    local function pump(count)
        for _=1,count or 10 do
            now=now+.1;network:advanceSteps(1);client:update(.1,gc);host:update(.1,hc);client:update(0,gc)
            for _,event in ipairs(client:drainEvents())do
                events[event.type]=event
                if event.type=='ready' then for key,value in pairs(event.spawn)do gp[key]=value end end
            end
            host:drainEvents()
        end
    end
    assert(host:startHost({name='Outing Host',character='rabbit-worker',addressOptions={socket={dns={
        gethostname=function()return 'outing-host'end,getaddrinfo=function()return {{addr='192.168.1.93'}}end}}}}))
    host.sessionId='outing-session-test'
    assert(client:startClient('192.168.1.93:22122',{name='Outing Guest',character='rabbit-worker',residentToken=string.rep('b',64)}))
    client.clientNonce='outing-guest';pump()
    check('outing_network_guest_joins_working_household',client.ready and state.home.weekend.phase=='working')
    assert(travel(hp,'outing'));local token=state.home.weekend.travelToken;pump()
    check('outing_network_request_replicates_purpose',events.shop_state.state.home.weekend.travelPurpose=='outing')
    assert(client:requestInteraction('homeTravel','force:'..token));pump()
    check('outing_network_guest_cannot_force_household',not events.interaction_result.accepted and not state.home.commute)
    network:duplicateNext('client_to_host',1,1,true)
    assert(client:requestInteraction('homeTravel','ready:'..token));pump()
    check('outing_network_duplicate_ready_is_one_vote',state.home.weekend.readyMask==3)
    assert(travel(hp,'depart:'..token));pump(15)
    local guest=host.players[2];local id=Residents.key(guest)
    local public=events.shop_state.state
    check('outing_network_authoritative_trip_replicates_without_weekend_phase',public.home.commute.purpose=='outing'
        and public.home.weekend.phase=='working' and public.home.commute.participants[id]~=nil and Schema.validState(public))
    local observer=State.new();assert(State.applySharedSnapshot(observer,public))
    check('outing_network_client_snapshot_retains_town_and_trip',observer.home.commute.token==token
        and observer.home.town.id==state.home.town.id and observer.home.commute.purpose=='outing')
    network:duplicateNext('client_to_host',1,1,true)
    assert(client:requestInteraction('commute','equip:'..token));pump()
    local part=state.home.commute.participants[id];local revision=part.rider.gear.revision
    check('outing_network_guest_equips_only_own_rider_once',part.rider.gear.transition~=nil
        and not state.home.commute.participants.owner.rider.gear.transition and saves==1)
    assert(client:requestInteraction('commute','equip:'..(token+1)));pump()
    check('outing_network_stale_rider_command_rejected',not events.interaction_result.accepted
        and part.rider.gear.revision==revision and saves==1)
    assert(client:requestInteraction('commute','cancel:'..token));pump()
    check('outing_network_guest_cannot_return_household_inside',not events.interaction_result.accepted and state.home.commute~=nil)
    local trip=state.home.commute;local destination=world.sites.byId[trip.destination]
    for _,p in pairs(trip.participants)do
        require('src.commute.gear').update(p.rider.gear,10)
        local anchor=assert(Trip.parking(world,trip.destination,p.slot))
        p.rider.bike.x,p.rider.bike.z=anchor.x,anchor.z
        p.rider.ped.x,p.rider.ped.z=destination.door.x,destination.door.z
        require('src.commute.rider').update(p.rider,{},0,world)
    end
    assert(Trip.command(state,guest,token,'arrive',world))
    assert(Commute.command(R,hp,'arrive:'..token));pump(15)
    public=events.shop_state.state
    check('outing_network_weekday_home_visit_replicates_after_real_door_commit',state.home.commute==nil
        and hp.sceneId=='home' and guest.sceneId=='home' and gp.sceneId=='home' and public.home.visit.scene=='home'
        and public.home.weekend.phase=='working' and Schema.validState(public))
    assert(State.applySharedSnapshot(observer,public))
    check('outing_network_observer_recognizes_weekday_home_visit',require('src.weekend_flow').atHome(observer)
        and not require('src.weekend_flow').shopClosed(observer))
    client:stop('outing complete');host:stop('outing complete');network:dispose()
end
return Test
