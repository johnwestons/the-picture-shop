local Test={}
function Test.run(check)
    local Session=require('src.net.session')
    local Refresh=require('src.net.snapshot_refresh')
    local Protocol=require('src.net.protocol')
    local now=0
    local host=Session.new({clock=function()return now end})
    host.sessionId='refresh-audit';host.idToPeer[2]='guest';host.peerToId.guest=2
    local packets,bytes,fail=0,0,false
    local deliveries={}
    host.transport={send=function(_,peer,wire,channel,reliable)
        if fail then fail=false;return false,'injected failure' end
        assert(channel==Protocol.CHANNEL_STATE and not reliable)
        packets=packets+1;bytes=bytes+#wire
        deliveries[#deliveries+1]={peer=peer,envelope=assert(Protocol.decode(wire)),at=now}
        return true
    end}
    local function send(tick,bay)
        return host:_broadcastJoined('hockey_snapshot',{sessionId=host.sessionId,
            serverTick=tick,bayId=bay or 'front_left',game=false})
    end
    for tick=1,120 do now=(tick-1)/12;assert(send(tick)) end
    check('lan_idle_auxiliary_snapshots_reduce_traffic_but_repeat_for_loss_recovery',packets==10,
        'packets='..packets..' insteadOf=120 bytes='..bytes)
    local boundedGaps=true
    for i=2,#deliveries do boundedGaps=boundedGaps and deliveries[i].at-deliveries[i-1].at<=1.000001 end
    check('lan_lost_idle_tombstones_retry_within_one_second',boundedGaps)
    now=9.95;host.idToPeer[3]='late';host.peerToId.late=3
    local before=packets;assert(send(121))
    check('lan_new_peer_gets_own_auxiliary_baseline',packets==before+1 and deliveries[#deliveries].peer=='late')
    local payload={sessionId=host.sessionId,serverTick=121,resourceId='cutter',view={blade=false}}
    local key=Refresh.key('cutter_snapshot',payload)
    Refresh.remember(host,'guest',key,payload,now)
    payload.serverTick=122
    check('lan_auxiliary_tick_alone_does_not_force_a_send',not Refresh.due(host,'guest',key,'cutter_snapshot',payload,now))
    payload.view.blade=true
    check('lan_changed_machine_safety_state_sends_immediately',Refresh.due(host,'guest',key,'cutter_snapshot',payload,now))
    payload={revision=1,resources={{resourceId='cutter',revision=2,occupied=false}}}
    key=Refresh.key('workshop_snapshot',payload);Refresh.remember(host,'guest',key,payload,now)
    payload.revision=2
    check('lan_workshop_tick_does_not_force_a_send',not Refresh.due(host,'guest',key,'workshop_snapshot',payload,now))
    payload.resources[1].revision=3
    check('lan_resource_revision_is_never_suppressed',Refresh.due(host,'guest',key,'workshop_snapshot',payload,now))
    check('lan_player_and_prediction_snapshots_keep_full_cadence',Refresh.key('snapshot',{})==nil
        and Refresh.key('prediction_snapshot',{})==nil and Refresh.key('crisis_frame',{})==nil)
    payload={serverTick=1,customer={x=1,y=2,state='waiting',animationClock=0,idleClock=0,waitTimer=0,arrivalTimer=0},vendor={state='absent'}}
    key=Refresh.key('visitor_snapshot',payload);Refresh.remember(host,'guest',key,payload,now)
    payload.customer.animationClock=10;payload.customer.idleClock=1;payload.customer.waitTimer=2;payload.customer.arrivalTimer=3
    check('lan_stationary_visitor_clock_changes_wait_for_refresh',not Refresh.due(host,'guest',key,'visitor_snapshot',payload,now))
    check('lan_stationary_visitor_countdowns_still_refresh_once_a_second',Refresh.due(host,'guest',key,'visitor_snapshot',payload,now+1))
    payload.customer.state='leaving'
    check('lan_visitor_decisions_send_immediately',Refresh.due(host,'guest',key,'visitor_snapshot',payload,now))
    payload.customer.state='waiting';payload.customer.x=2
    check('lan_moving_visitors_keep_full_snapshot_cadence',Refresh.due(host,'guest',key,'visitor_snapshot',payload,now))
    for i=1,256 do Refresh.remember(host,'guest','machine:'..i,{id=i},now) end
    local count=0;for _ in pairs(host.snapshotRefresh.guest.entries) do count=count+1 end
    check('lan_auxiliary_snapshot_cache_is_bounded',count==Refresh.MAX_ENTRIES
        and #host.snapshotRefresh.guest.order==Refresh.MAX_ENTRIES)
    host.idToPeer[3]=nil;host.peerToId.late=nil
    Refresh.prune(host)
    check('lan_departed_peer_snapshot_cache_is_removed',host.snapshotRefresh.late==nil)
    Refresh.forget(host,'guest');fail=true
    before=packets;local okay=send(123,'front_right');assert(send(123,'front_right'))
    check('lan_failed_auxiliary_send_retries_without_waiting_for_refresh',not okay and packets==before+1)
    host.sessionId='new-refresh-audit';Refresh.prune(host)
    check('lan_new_session_clears_old_auxiliary_baselines',next(host.snapshotRefresh)==nil)
    local wireArray=require('src.net.codec').array
    local machineViews={
        cutter_snapshot={runtimeRevision=1,step='idle',phasePermille=0,loaded=false,clamp=false,
            clampPermille=0,bladePermille=0,barrierClear=true,emergencyStopped=false,
            gaugeCentiInch=0,programIndex=1,memoryCentiInch=wireArray({})},
        windmill_snapshot={runtimeRevision=1,status='idle',speed=3000,motor=false,feeder=false,
            impression=false,emergency=false,counter=0,goodSheets=0,spoilage=0,targetSheets=250,
            feedStart=300,feedRemaining=300,proofApproved=false,artworkVerified=false,
            setupPermille={0,0,0,0,0,0},candidates=wireArray({}),serviceStep='idle',servicePermille=0,plateMarkerPermille=670},
    }
    for kind,view in pairs(machineViews)do
        Refresh.forget(host,'guest')
        local resource=kind=='cutter_snapshot'and'cutter'or'windmill'
        local machine={sessionId=host.sessionId,serverTick=1000,resourceId=resource,resourceRevision=7,view=view}
        local first=#deliveries+1;local before=packets
        for tick=1,120 do
            now=20+(tick-1)/12;machine.serverTick=1000+tick;view.runtimeRevision=9000+tick
            assert(host:_broadcastJoined(kind,machine))
        end
        check('lan_idle_'..resource..'_runtime_revision_does_not_flood_the_link',packets-before==10)
        local key=Refresh.key(kind,machine)
        view.runtimeRevision=10000
        check('lan_'..resource..'_runtime_only_refresh_keeps_one_second_deadline',
            not Refresh.due(host,'guest',key,kind,machine,now)
            and Refresh.due(host,'guest',key,kind,machine,30))
        machine.resourceRevision=8
        check('lan_'..resource..'_resource_revision_sends_immediately',Refresh.due(host,'guest',key,kind,machine,now))
        machine.resourceRevision=7
        if resource=='cutter'then view.phasePermille=1 else view.setupPermille[1]=1 end
        check('lan_active_'..resource..'_phase_sends_immediately',Refresh.due(host,'guest',key,kind,machine,now))
        if resource=='cutter'then view.phasePermille=0;view.emergencyStopped=true
        else view.setupPermille[1]=0;view.emergency=true end
        check('lan_'..resource..'_safety_changes_send_immediately',Refresh.due(host,'guest',key,kind,machine,now))
        local receiver=Session.new();receiver.mode='client';receiver.ready=true;receiver.sessionId=host.sessionId
        receiver:_handleClientEnvelope(deliveries[first].envelope)
        receiver:_handleClientEnvelope(deliveries[#deliveries].envelope)
        receiver:_handleClientEnvelope(deliveries[first].envelope)
        local events=receiver:drainEvents()
        check('lan_'..resource..'_throttled_refresh_preserves_revision_and_tick_ordering',#events==2
            and events[2].view.runtimeRevision==deliveries[#deliveries].envelope.payload.view.runtimeRevision
            and events[2].resourceRevision==7)
    end
    local Codec=require('src.net.codec')
    local Replication=require('src.net.shop_replication')
    local player={id=2,name='Weak WiFi Worker',sceneId='commute',resting=false,taskAction='none',
        x=102.234565432,y=23.456789123,velocityX=4.23456789,velocityY=2.23456789,
        intentX=.4123456789,intentY=.823456789,moving=true,facing=1,
        animationDistance=18734.456789,character='rabbit-worker',furColorway=1,overallsColorway=1,inputSequence=9231}
    local payload={sessionId='compact-audit',serverTick=27,players=Codec.array({player})}
    local compact=assert(Protocol.encode('snapshot',payload))
    local verbose=assert(Codec.encode({version=Protocol.VERSION,type='snapshot',payload=payload},{maxBytes=4096}))
    local decoded=assert(Protocol.decode(compact))
    local expected=Replication.copy(player);expected.taskAction=nil
    check('lan_compact_player_snapshot_preserves_every_field_and_full_precision',
        Replication.equal(decoded.payload.players[1],expected))
    check('lan_compact_player_snapshot_removes_repeated_field_name_bandwidth',#compact<#verbose*.7,
        'compact='..#compact..' verbose='..#verbose)
    local compactRaw=compact:sub(1,4)=='TPSL'and love.data.decompress('string','lz4',compact:sub(5))or compact
    local wire=assert(Codec.decode(compactRaw))
    local tuple=wire.payload.players[1]
    check('lan_player_wire_tuple_has_fixed_bounded_shape',Codec.isArray(tuple)and #tuple==12 and #tuple[6]==56)
    tuple[13]=true
    check('lan_player_wire_rejects_extra_tuple_fields',not Protocol.decode(assert(Codec.encode(wire))))
    tuple[13]=nil;tuple[12]=nil
    check('lan_player_wire_rejects_missing_tuple_fields',not Protocol.decode(assert(Codec.encode(wire))))
    tuple[12]=9231;tuple[4]=1
    check('lan_player_wire_keeps_existing_boolean_validation',not Protocol.decode(assert(Codec.encode(wire))))
    tuple[4]=false;tuple[6]=love.data.pack('string','<d',100001)..tuple[6]:sub(9)
    check('lan_player_wire_keeps_existing_coordinate_bounds',not Protocol.decode(assert(Codec.encode(wire))))
    check('lan_player_wire_rejects_noncanonical_named_snapshot_records',not Protocol.decode(verbose))
end
return Test
