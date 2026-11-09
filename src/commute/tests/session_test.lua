-- Real Session/Protocol traffic through the deterministic transport harness.
-- Route driving itself is covered by runtime_test; this exercises authority,
-- animation snapshots, reconnects, late joins and the household boundary.
local Session=require('src.net.session')
local Protocol=require('src.net.protocol')
local Harness=require('src.tests.support.network_impairment_harness')
local Schema=require('src.save_schema')
local Residents=require('src.home_residents')
local Travel=require('src.home_travel')
local Trip=require('src.commute.trip')
local Rider=require('src.commute.rider')
local Gear=require('src.commute.gear')
local C=require('src.commute.runtime')
local Test={}
local function player(id)
    return {id=id,x=720,y=202,sceneId='warehouse',velocityX=0,velocityY=0,intentX=1,intentY=0,
        moving=false,facing=1,animationDistance=0,character='rabbit-worker'}
end
function Test.run(context,check)
    local state=context.State.new()
    state.home=assert(require('src.home').new({town=assert(require('src.commute.town').generate(712345))},state.calendar.totalDays))
    state.home.weekend.phase='ready';state.home.weekend.closedAtHours=44
    -- The mechanic's service/paint transactions occur during opening hours.
    local Calendar=require('src.business_calendar')
    state.calendar=Calendar.dateFromHours(57)
    state.calendar.elapsed=9/24*Calendar.secondsPerDay(state)
    local now=0
    local network=Harness.new({maxClients=3,classify=function(bytes)local v=Protocol.decode(bytes);return v and v.type or 'invalid' end})
    local host=Session.new({transportFactory=network.factory,clock=function()return now end})
    local hp=player(1);local guests,locals,contexts,received={},{},{},{}
    local R={state=state,multiplayer=host,World={player=hp},saveCurrent=function()end}
    R.World.resolveNetworkSpawn=function(x,y,id)return x+(id-1)*20,y end
    local world=C.world(R)
    local function players()
        local result={hp};for id,p in pairs(host.players) do if id~=1 then result[#result+1]=p end end;return result
    end
    local function departure(p,cmd)
        local okay,code,message=Travel.command(state,p,cmd,{world={truck={state='absent'}},players=players,commuteWorld=world})
        if okay then host:markShopDirty() end
        return okay,code,message,'homeTravel'
    end
    local hc={localPlayer=hp,moveRemote=function()end,
        bindResident=function(p,token,connected)
            local id,reason=Residents.bind(state,p,token,connected)
            if id then local okay,message=C.bind(R,p,connected);if not okay then return nil,message end;host:markShopDirty() end
            return id,reason
        end,
        resolveGuestSpawn=function(x,y,id)return x+id*20,y end,
        getShopSnapshot=function()return {state=assert(Schema.snapshot(state)),player={x=hp.x,y=hp.y,sceneId=hp.sceneId,character=hp.character}} end,
        performInteraction=function(p,kind,cmd)
            if kind=='commute' then return C.command(R,p,cmd) end
            if kind=='homeTravel' then return departure(p,cmd) end
        end}
    assert(host:startHost({name='Commute Host',character='rabbit-worker',addressOptions={socket={dns={
        gethostname=function()return 'commute-host'end,getaddrinfo=function()return {{addr='192.168.1.93'}}end}}}}))
    host.sessionId='commute-session-test'
    local function pump(count)
        for _=1,count or 8 do
            now=now+.1;network:advanceSteps(1)
            for i,g in pairs(guests) do g:update(.1,contexts[i]) end
            host:update(.1,hc)
            if state.home.commute then
                for _,p in ipairs(players()) do
                    local part=state.home.commute.participants[Residents.key(p)]
                    if part then
                        local x,y=0,0
                        if now-(p.lastInputAt or 0)<=.35 then x,y=p.inputX or 0,p.inputY or 0 end
                        local input=part.rider.gear.mounted and {steer=x,throttle=math.max(0,-y),brake=math.max(0,y)} or {walkX=x,walkZ=y}
                        Trip.update(state,p,input,.1,world);C.syncPlayer(p,part)
                    end
                end
                host:markShopDirty()
            end
            for i,g in pairs(guests) do
                g:update(0,contexts[i])
                for _,event in ipairs(g:drainEvents()) do
                    received[i]=received[i] or {};received[i][event.type]=event
                    if event.type=='ready' then for k,v in pairs(event.spawn) do locals[i][k]=v end end
                end
            end
            host:drainEvents()
        end
    end
    local function join(i)
        local g=Session.new({transportFactory=network.factory,clock=function()return now end})
        guests[i]=g;locals[i]=player(i+1);contexts[i]={localPlayer=locals[i],inputX=0,inputY=0}
        assert(g:startClient('192.168.1.93:22122',{name='Commute Guest '..i,character='rabbit-worker',residentToken=string.rep(tostring(i),64)}))
        g.clientNonce='commute-guest-'..i..'-'..math.floor(now*10);pump(10)
        assert(g.ready,'Commute guest failed to join');return g
    end
    local g=join(1);join(2);local residentId=g.residentId
    assert(departure(hp,'request'));local token=state.home.weekend.travelToken
    assert(departure(hp,'force:'..token));pump()
    check('commute_session_departure_scene_and_trip_replicate',locals[1].sceneId=='commute'
        and received[1].shop_state.state.home.commute.participants[residentId].slot==2)
    check('commute_session_host_saved_town_reaches_all_guests',require('src.commute.town').fingerprint(received[1].shop_state.state.home.town)
        ==require('src.commute.town').fingerprint(state.home.town) and received[2].shop_state.state.home.town.id==state.home.town.id)
    network:duplicateNext('client_to_host',1,1,true)
    assert(g:requestInteraction('commute','equip:'..token));pump(3)
    local part=state.home.commute.participants[residentId]
    local visual=received[1].shop_state.state.home.commute.participants[residentId]
    check('commute_session_transitional_pose_survives_safe_snapshot',visual.presentation.pose=='suit_on'
        and visual.rider.gear.transition==nil and visual.presentation.progress>0 and part.rider.gear.revision==1)
    pump(40)
    assert(g:requestInteraction('commute','mount:'..token));pump(22)
    check('commute_session_guest_gear_and_ignition_authoritative',part.rider.gear.engine and received[1].interaction_result.accepted)
    local snapshotX,snapshotZ=part.rider.bike.x,part.rider.bike.z
    local renderRider=C.visualRider(part,{sceneId='commute',x=snapshotX+.75,y=snapshotZ+.4})
    check('commute_session_render_uses_smoothed_player_position',renderRider.bike.x==snapshotX+.75
        and renderRider.bike.z==snapshotZ+.4 and part.rider.bike.x==snapshotX and part.rider.bike.z==snapshotZ)
    assert(g:requestInteraction('commute','manual:'..token));pump()
    assert(g:requestInteraction('commute','shiftup:'..token));pump(4)
    visual=received[1].shop_state.state.home.commute.participants[residentId]
    check('commute_session_manual_gear_replicates_to_client',part.rider.bike.transmission=='manual'
        and part.rider.bike.gear==2 and visual.rider.bike.gear==2 and visual.rider.bike.transmission=='manual')
    network:duplicateNext('client_to_host',1,1,true)
    assert(g:requestInteraction('commute','automatic:'..token));pump(12)
    check('commute_session_automatic_selection_survives_duplicate',received[1].interaction_result.accepted
        and part.rider.bike.transmission=='automatic' and part.rider.bike.gear==1)
    local beforeX,beforeZ=part.rider.bike.x,part.rider.bike.z
    contexts[1].inputY=-1;pump(8);contexts[1].inputY=1;pump(12);contexts[1].inputY=0;pump()
    check('commute_session_guest_input_drives_host_bike',math.abs(part.rider.bike.x-beforeX)+math.abs(part.rider.bike.z-beforeZ)>.3
        and math.abs(locals[1].x-part.rider.bike.x)<.5 and part.rider.bike.speed<.05,
        ('travel=%.3f clientDelta=%.3f speed=%.3f gear=%d mode=%s'):format(math.abs(part.rider.bike.x-beforeX)+math.abs(part.rider.bike.z-beforeZ),
            math.abs(locals[1].x-part.rider.bike.x),part.rider.bike.speed,part.rider.bike.gear,part.rider.bike.transmission))
    local oldRider=Rider.snapshot(part.rider);local mechanic=world.sites.byId.mechanic
    part.rider=Rider.new(mechanic.parking.x,mechanic.parking.z,0,{version=1,outfit='geared',mounted=false,engine=false,revision=1})
    part.rider.ped.x,part.rider.ped.z=mechanic.door.x,mechanic.door.z
    require('src.commute.motorcycle').resetContact(part.rider.bike,world);C.syncPlayer(host.players[part.slot],part)
    state.home.balanceCents=100000
    local upgrade=('upgrade:%d:%d:1'):format(token,state.home.revision)
    network:duplicateNext('client_to_host',1,1,true)
    assert(g:requestInteraction('commute',upgrade));pump()
    local price=require('src.commute.bike_upgrades').CATALOG[1].costCents
    check('commute_session_garage_purchase_is_host_authoritative_and_debits_once',received[1].interaction_result.accepted
        and state.home.balanceCents==100000-price and state.home.residents[residentId].ridingUpgradeLevel==1
        and received[2].shop_state.state.home.commute.participants[residentId].rider.bike.upgradeLevel==1,
        received[1].interaction_result.message)
    assert(g:requestInteraction('commute',upgrade));pump()
    check('commute_session_stale_garage_purchase_rejected',not received[1].interaction_result.accepted
        and state.home.balanceCents==100000-price)
    local paintMoney=state.home.balanceCents
    local paintCommand=('bikepaint:%d:0:red'):format(token)
    network:duplicateNext('client_to_host',1,1,true)
    assert(C.request({state={},multiplayer=g},paintCommand))
    check('commute_session_paint_request_waits_for_authoritative_host',state.home.balanceCents==paintMoney
        and state.home.residents[residentId].ridingPaintId=='bronze')
    pump()
    local paintSnapshot=received[2].shop_state.state.home
    check('commute_session_guest_paint_debits_once_and_replicates',received[1].interaction_result.accepted
        and state.home.balanceCents==paintMoney-12500 and state.home.residents[residentId].ridingPaintRevision==1
        and part.rider.bike.paintId=='red' and paintSnapshot.residents[residentId].ridingPaintId=='red'
        and paintSnapshot.commute.participants[residentId].rider.bike.paintId=='red'
        and paintSnapshot.residents.owner.ridingPaintId=='bronze')
    assert(g:requestInteraction('commute',paintCommand));pump()
    check('commute_session_replayed_paint_order_is_rejected_without_charge',not received[1].interaction_result.accepted
        and state.home.balanceCents==paintMoney-12500 and part.rider.bike.paintId=='red')
    oldRider.bike.upgradeLevel=1;oldRider.bike.paintId='red'
    part.rider=assert(Rider.restore(oldRider,world,world.roads.destinations.warehouse))
    C.syncPlayer(host.players[part.slot],part)
    assert(g:requestInteraction('commute','force:'..token));pump()
    check('commute_session_guest_cannot_finish_household',not received[1].interaction_result.accepted and state.home.commute~=nil)
    local parkedX=part.rider.bike.x
    for i=1,2 do guests[i]:stop('test reconnect');guests[i]=nil end;pump()
    join(3)
    check('commute_session_late_join_preserves_offline_rider',state.home.commute.participants[residentId].rider.bike.x==parkedX
        and state.home.commute.participants[residentId].slot~=2 and locals[3].sceneId=='commute')
    g=join(1);part=state.home.commute.participants[residentId]
    check('commute_session_reconnect_rebinds_resident_and_vehicle',g.residentId==residentId and part.slot==3
        and part.rider.gear.engine and part.rider.bike.x==parkedX and Trip.valid(state.home.commute,state.home))
    check('commute_session_paid_finish_survives_live_reconnect',part.rider.bike.paintId=='red'
        and received[1].shop_state.state.home.residents[residentId].ridingPaintRevision==1
        and received[1].shop_state.state.home.commute.participants[residentId].rider.bike.paintId=='red')
    -- Arrivals use the same host-side position checks as the real route test.
    local anchor=world.roads.destinations[state.home.commute.destination]
    local owner=state.home.commute.participants.owner
    owner.rider=Rider.new(anchor.x,anchor.z,0,{version=1,outfit='geared',mounted=false,engine=false,revision=1})
    local entrance=world.sites.byId[state.home.commute.destination].door
    owner.rider.ped.x,owner.rider.ped.z=entrance.x,entrance.z;Rider.update(owner.rider,{},0,world)
    local okay=C.command(R,hp,'arrive:'..token)
    check('commute_session_host_arrival_acknowledged_while_waiting',okay and state.home.commute~=nil and owner.arrived)
    assert(C.command(R,hp,'force:'..token));pump(12)
    check('commute_session_host_brings_connected_and_offline_riders_home',state.home.commute==nil and state.home.weekend.phase=='home'
        and locals[1].sceneId=='home' and locals[3].sceneId=='home' and state.home.residents[residentId].ridingGear.outfit=='geared')
    assert(g:requestInteraction('commute','force:'..token));pump()
    check('commute_session_stale_completion_rejected',not received[1].interaction_result.accepted and state.home.weekend.transition==1)
    assert(g:requestInteraction('commute','remove'));pump()
    check('commute_session_suited_guest_can_remove_gear_indoors',received[1].interaction_result.accepted
        and state.home.residents[residentId].ridingGear.transition.kind=='remove')
    for _,guest in pairs(guests) do guest:stop('test complete') end
    host:stop('test complete');network:dispose();C.release(R)
end
return Test
