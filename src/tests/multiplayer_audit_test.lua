local Test={}
local Protocol=require('src.net.protocol')
local Session=require('src.net.session')
local Schema=require('src.save_schema')
local State=require('src.state')

local function player(id)
    return {id=id,name='Worker '..id,sceneId=id==1 and 'commute' or 'front_left',
        character='rabbit-worker',x=102.234565432,y=23.456789123,velocityX=4.23456789,
        velocityY=2.23456789,intentX=.4123456789,intentY=.823456789,moving=true,facing=1,
        animationDistance=18734.456789,inputSequence=0,furColorway=1,overallsColorway=1,
        resting=false,taskAction='none'}
end

local function packetChecks(check)
    local games={}
    for i,bay in ipairs({'front_left','front_right'}) do
        games[i]={bayId=bay,mode='solo',phase='playing',leftId=i+1,
            leftX=221.34167893456,leftY=213.23456781234,rightX=674.657834567,
            rightY=255.45667890234,puckX=431.2345467789,puckY=318.237767431,
            leftScore=2,rightScore=3,faceoff=0}
    end
    local truck={token=23,model='box',heading=1.234567891234,speed=12.3412345678,
        steer=.3123456789,brake=0,throttle=1,reverse=false,h=2.34567891234,pitch=.123456789}
    local host=Session.new()
    host.mode='host';host.ready=true;host.sessionId='audit-truck-hockey';host.localId=1
    host:_installRoster({player(1),player(2),player(3),player(4)},0)
    local clients,wire={},{}
    for id=2,4 do
        host.idToPeer[id]=id
        local client=Session.new();clients[id]=client
        client.mode='client';client.ready=true;client.sessionId=host.sessionId;client.localId=id
        client:_installRoster({player(1),player(2),player(3),player(4)},0)
    end
    host.transport={send=function(_,peer,bytes,channel,reliable)
        local packet=assert(Protocol.decode(bytes))
        assert(#bytes<=Protocol.MAX_PACKET_BYTES and channel==Protocol.CHANNEL_STATE and not reliable)
        wire[#wire+1]=packet
        clients[peer]:_handleClientEnvelope(packet)
        return true
    end}
    local context={localPlayer=player(1),getGameSnapshot=function()return games end,
        getTruckMotion=function(id)return id==1 and truck or nil end}
    host:_updateHost(.1,context)
    local movement,hockey=0,0
    for _,packet in ipairs(wire) do
        if packet.type=='snapshot' then movement=movement+1 end
        if packet.type=='hockey_snapshot' then hockey=hockey+1 end
    end
    check('audit_two_hockey_tables_and_truck_fit_bounded_motion_batches',movement==6 and hockey==6)
    for id,client in pairs(clients) do
        check('audit_hockey_and_motion_received_by_guest_'..id,#client:gameSnapshot()==2
            and client.lastPlayerTicks[1]==host.serverTick and client.lastPlayerTicks[4]==host.serverTick)
    end
    check('audit_hockey_host_does_not_report_packet_overflow',#host:drainEvents()==0)

    local priorTick=host.serverTick
    games={};host:_updateHost(.1,context)
    local client=clients[2]
    check('audit_hockey_empty_bays_clear_prior_matches',#client:gameSnapshot()==0)
    for _,packet in ipairs(wire) do
        if packet.type=='hockey_snapshot' and packet.payload.serverTick==priorTick then
            client:_handleClientEnvelope(packet)
        end
    end
    check('audit_hockey_reordered_packets_cannot_resurrect_closed_matches',#client:gameSnapshot()==0)
    local legacyClient=Session.new();legacyClient.mode='client';legacyClient.ready=true;legacyClient.sessionId=host.sessionId
    -- Select one match per bay, independent of the three recipient copies.
    local oldGames={}
    for _,bayId in ipairs({'front_left','front_right'})do
        for _,packet in ipairs(wire)do
            if packet.type=='hockey_snapshot'and packet.payload.bayId==bayId and packet.payload.game~=false then
                oldGames[#oldGames+1]=packet.payload.game;break
            end
        end
    end
    legacyClient:_applySnapshot({sessionId=host.sessionId,serverTick=10,players={},games=oldGames})
    legacyClient:_handleClientEnvelope({type='hockey_snapshot',payload={sessionId=host.sessionId,
        serverTick=11,bayId='front_left',game=false}})
    legacyClient:_applySnapshot({sessionId=host.sessionId,serverTick=10,players={},games=oldGames})
    check('audit_legacy_combined_hockey_cannot_resurrect_newer_closed_bay',#legacyClient:gameSnapshot()==1
        and legacyClient:gameSnapshot()[1].bayId=='front_right')
    legacyClient:_applySnapshot({sessionId=host.sessionId,serverTick=12,players={},games={}})
    legacyClient:_applySnapshot({sessionId=host.sessionId,serverTick=10,players={},games=oldGames})
    check('audit_legacy_combined_hockey_tombstones_keep_per_bay_tick_order',#legacyClient:gameSnapshot()==0)
    local valid={sessionId=host.sessionId,serverTick=100,bayId='front_left',game=false}
    check('audit_hockey_tombstone_codec_round_trip',Protocol.decode(assert(Protocol.encode('hockey_snapshot',valid))).payload.game==false)
    valid.game={};check('audit_hockey_rejects_malformed_game',not Protocol.encode('hockey_snapshot',valid))

    local encode=host._encode
    host._encode=function(self,kind,payload)
        if kind=='snapshot'then
            for _,record in ipairs(payload.players)do
                if record.id==2 then return nil,'injected player packet failure'end
            end
        end
        return encode(self,kind,payload)
    end
    host:_updateHost(.1,context)
    check('audit_failed_player_packet_does_not_starve_other_players',client.lastPlayerTicks[1]==host.serverTick
        and client.lastPlayerTicks[3]==host.serverTick and client.lastPlayerTicks[4]==host.serverTick
        and client.lastPlayerTicks[2]<host.serverTick)
    host._encode=encode
    require('src.tests.multiplayer_motion_batches_test').run(check)
    require('src.tests.multiplayer_snapshot_compression_test').run(check)
    require('src.tests.multiplayer_motion_wire_test').run(check)
    require('src.tests.multiplayer_motion_cadence_test').run(check)
    require('src.tests.multiplayer_join_readiness_test').run(check)
end

local function deliveryChecks(check)
    local Town=require('src.commute.town')
    local Residents=require('src.home_residents')
    local Apartments=require('src.client_apartments')
    local Jobs=require('src.jobs')
    local Service=require('src.job_service')
    local Run=require('src.commute.delivery_run')
    local Trip=require('src.commute.trip')
    local Free=require('src.commute.free_travel')
    local town=assert(Town.generate(712345));local world=Town.world(town)
    for _,stage in ipairs({'loading','driving','offmap'}) do
        local s=State.new();s.home.town=town
        s.home.townCharacters=require('src.commute.town_characters').defaultState(town)
        s.calendar.elapsed=require('src.business_calendar').secondsPerDay(s)*10/24
        local hp={id=1,homeResidentId='owner',sceneId='warehouse',character='rabbit-worker'}
        local gp={id=2,sceneId='warehouse',character='rabbit-worker',name='Guest'}
        local rid=assert(Residents.bind(s,gp,string.rep('2',64),{hp}))
        local job=assert(Jobs.createOffer({id='RESET-'..stage,
            company=stage=='offmap' and 'Blue Ridge Packaging' or 'Town Grocery',
            customerDestination=stage~='offmap' and 'grocery' or nil,
            sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
        Jobs.accept(job);job.status='in_production';job.delivery={status='received'};s.jobs.active[1]=job
        for _,p in ipairs(job.pallets) do
            p.location,p.status,p.wrapped,p.remainingSheets='warehouse','wrapped',true,0
            p.finishedSheets=p.initialSheets;p.completedLifts=p.requiredLifts
            p.world={x=400,y=500,sceneId='warehouse',direction='northwest',spawnProgress=1}
            s.inventory.finishedPallets=(s.inventory.finishedPallets or 0)+1
        end
        assert(Service.requestPickup(s,job,100,'player'))
        local run=assert(Run.build(s,{job.id},world,'player'))
        local okay,trip=Free.enter(s,gp,world,run,{hp,gp});assert(okay,trip)
        if stage~='loading' then
            assert(Service.loadForPickup(s,job.id,job.pallets[1].id,100))
            run.status=stage;job.pickup.status='player_delivery'
            if stage=='offmap' then run.cutsceneStartedAtEpoch=os.time();run.cutsceneEndsAtEpoch=os.time()+60 end
        end
        local beforeMoney=s.money;local cargoLocation=job.pallets[1].location
        assert(Apartments.resetSlot(s,s.home.residents[rid].clientSlot))
        check('audit_profile_reset_transfers_manifest_'..stage,trip.deliveryDriver=='owner'
            and trip.deliveryRun==run and trip.truck.owner=='owner' and not trip.truck.driver
            and not trip.participants[rid] and not s.home.residents[rid]
            and job.pallets[1].location==cargoLocation and s.money==beforeMoney)
        local loaded=State.new()
        local saved=assert(Schema.snapshot(s));assert(Schema.validState(saved))
        assert(State.applyLocalSave(loaded,{slot=1,state=saved}))
        trip=loaded.home.commute;run=trip.deliveryRun
        local entered,reason=Free.enter(loaded,hp,world,nil,{hp});assert(entered,reason)
        hp.sceneId='commute'
        local rider=trip.participants.owner.rider
        rider.ped.x,rider.ped.z=trip.truck.x,trip.truck.z
        local mounted,message=Trip.command(loaded,hp,trip.token,'truck',world)
        check('audit_reset_delivery_owner_can_resume_after_reload_'..stage,mounted==true,message)
        if stage=='loading' then
            assert(Service.loadForPickup(loaded,job.id,loaded.jobs.active[1].pallets[1].id,100))
            run.status='driving';loaded.jobs.active[1].pickup.status='player_delivery'
        end
        local stop=run.stops[run.stopIndex]
        local completed,why
        if stop.kind=='city' then
            run.status='offmap';run.cutsceneStartedAtEpoch=os.time()-61;run.cutsceneEndsAtEpoch=os.time()-1
            completed=Trip.update(loaded,hp,{},0,world)
        else
            local door=world.sites.byId[stop.id].door
            trip.truck.x,trip.truck.z,trip.truck.speed=door.x,door.z,0
            rider.vehicle,rider.truck=nil,nil;trip.truck.driver=nil
            rider.ped.x,rider.ped.z,rider.ped.speed=door.x,door.z,0
            completed,why=Trip.command(loaded,hp,trip.token,'deliver_stop',world)
        end
        check('audit_reset_delivery_completes_and_pays_'..stage,completed==true
            and #loaded.jobs.completed==1 and loaded.money>beforeMoney and not trip.deliveryRun,why)
        local paid=loaded.money
        check('audit_reset_delivery_cannot_pay_twice_'..stage,Run.completeStop(loaded,stop)==true and loaded.money==paid)
    end
end

function Test.run(context,check)
    packetChecks(check)
    deliveryChecks(check)
    require('src.tests.multiplayer_replication_test').run(check)
    require('src.tests.multiplayer_runtime_cost_test').run(check)
    require('src.tests.shared_validation_test').run(check)
    require('src.tests.host_snapshot_validation_test').run(check)
    require('src.tests.lan_host_creation_test').run(check)
    require('src.tests.history_retention_test').run(check)
    require('src.tests.movement_prediction_test').run(check)
    -- Normal smoke supplies the live runtime, so exercise GPU drawing as well
    -- as simulation: joining must own a fresh renderer, and drawing must not
    -- alter the client's predicted physics. Keep headless audit helpers usable.
    if context and context.appRuntime then
        require('src.commute.tests.view_lifecycle_test').run(context,check)
    end
end
return Test
