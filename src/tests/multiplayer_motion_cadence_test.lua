local Test={}
function Test.run(check)
    local Cadence=require('src.net.motion_cadence')
    local Session=require('src.net.session')
    local Protocol=require('src.net.protocol')
    local now=0
    local rtts={fast=15,slow=150}
    local session=Session.new({clock=function()return now end})
    session.sessionId='cadence-test';session.idToPeer={[2]='fast',[3]='slow'}
    session.pendingPeers.private={}
    session.transport={peerRoundTripTime=function(_,peer)return rtts[peer]end}
    local function steps(seconds)
        local counts={fast=0,slow=0}
        for _=1,math.floor(seconds*12+.5)do
            now=now+1/12
            local due=Cadence.recipients(session,1,now)
            for peer in pairs(due)do counts[peer]=(counts[peer]or 0)+1 end
        end
        return counts
    end
    steps(3)
    check('lan_cadence_clean_and_constant_delayed_peers_stay_at_twelve',session.motionCadence.peers.fast.hz==12
        and session.motionCadence.peers.slow.hz==12)
    rtts.slow=250;steps(1.25)
    check('lan_cadence_sustained_rtt_inflation_reduces_only_congested_peer',session.motionCadence.peers.slow.hz==8
        and session.motionCadence.peers.fast.hz==12)
    local counts=steps(3)
    check('lan_cadence_reduced_peer_receives_two_of_three_original_ticks',counts.slow==24 and counts.fast==36)
    check('lan_cadence_unjoined_peers_never_receive_samples_or_cache_entries',not session.motionCadence.peers.private
        and counts.private==nil)
    rtts.slow=150;steps(10)
    check('lan_cadence_recovery_holds_reduced_rate_to_avoid_oscillation',session.motionCadence.peers.slow.hz==8)
    steps(11)
    check('lan_cadence_twenty_healthy_seconds_restore_full_rate',session.motionCadence.peers.slow.hz==12)
    rtts.slow=250;steps(.25);rtts.slow=150;steps(1)
    check('lan_cadence_one_short_latency_spike_does_not_reduce_rate',session.motionCadence.peers.slow.hz==12)
    rtts.slow=250;steps(.25);now=now+5;Cadence.recipients(session,60,now)
    check('lan_cadence_one_stalled_sample_cannot_manufacture_sustained_congestion',session.motionCadence.peers.slow.hz==12)
    steps(1.25)
    check('lan_cadence_real_samples_after_stall_can_still_detect_congestion',session.motionCadence.peers.slow.hz==8)
    for index,value in ipairs({false,0/0,math.huge,-1,60001})do
        rtts.slow=value;steps(.5)
        check('lan_cadence_invalid_telemetry_falls_back_to_twelve_'..index,session.motionCadence.peers.slow.hz==12)
    end
    session.transport.peerRoundTripTime=function()error('read failed')end;steps(.5)
    check('lan_cadence_telemetry_exception_does_not_interrupt_host',session.motionCadence.peers.slow.hz==12)
    session.transport.peerRoundTripTime=nil;steps(.5)
    check('lan_cadence_absent_telemetry_keeps_compatibility_rate',session.motionCadence.peers.slow.hz==12)
    session.idToPeer[3]=nil;steps(.25)
    check('lan_cadence_disconnected_peer_state_is_pruned',session.motionCadence.peers.slow==nil)
    local previous=session.motionCadence
    session.sessionId='new-session';steps(.25)
    check('lan_cadence_session_identity_change_drops_old_measurements',session.motionCadence~=previous)
    previous=session.motionCadence;now=now-10;Cadence.recipients(session,1,now)
    check('lan_cadence_backward_clock_resets_measurement_window',session.motionCadence~=previous)
    Cadence.recipients(session,1,0/0)
    check('lan_cadence_nonfinite_clock_returns_joined_set_without_caching',session.motionCadence==nil)
    for _,kind in ipairs({'direct','server'})do
        session.networkKind=kind
        local due=Cadence.recipients(session,1,now)
        check('lan_cadence_'..kind..'_retains_original_transport_behavior',due.fast and session.motionCadence==nil)
    end
    session.networkKind='lan';session.idToPeer={}
    for index=1,12 do session.idToPeer[index]='peer'..index end
    Cadence.recipients(session,1,now)
    local size=0;for _ in pairs(session.motionCadence.peers)do size=size+1 end
    check('lan_cadence_cache_is_bounded_even_with_unexpected_peer_count',size==3)
    session:_resetRuntime();check('lan_cadence_session_reset_releases_measurements',session.motionCadence==nil)

    -- Start on the impaired connection: warm-up must not turn ENet's synthetic
    -- 500 ms estimate into a permanent baseline or misclassify a slow fixed RTT.
    for _,constant in ipairs({150,800})do
        local cold=Session.new();cold.sessionId='cold-'..constant;cold.idToPeer[2]='peer'
        local sample=500
        cold.transport={peerRoundTripTime=function()return sample end}
        for index=0,48 do
            sample=index<8 and 500+(constant-500)*index/8 or constant
            Cadence.recipients(cold,1,index/12)
        end
        check('lan_cadence_cold_constant_link_warms_without_false_congestion_'..constant,cold.motionCadence.peers.peer.hz==12)
        sample=constant+math.max(100,constant*.5)
        for index=49,65 do Cadence.recipients(cold,1,index/12)end
        check('lan_cadence_cold_impaired_link_detects_subsequent_queue_growth_'..constant,cold.motionCadence.peers.peer.hz==8)
    end

    now=0
    local host=Session.new({clock=function()return now end})
    host.mode='host';host.ready=true;host.localId=1;host.sessionId='cadence-integration'
    host:_installRoster({{id=1,x=100,y=100},{id=2,x=120,y=100},{id=3,x=140,y=100}},0)
    host.idToPeer={[2]='fast',[3]='slow'};host.peerToId={fast=2,slow=3};host.pendingPeers.private={connectedAt=now}
    host.players[2]._commandStream={};host.players[3]._commandStream={}
    host._stepRemoteCommands=function()end
    rtts={fast=15,slow=150}
    local sent={}
    host.transport={peerRoundTripTime=function(_,peer)return rtts[peer]end,
        send=function(_,peer,bytes,channel,reliable)
            local packet=assert(Protocol.decode(bytes));local byPeer=sent[peer]or{};sent[peer]=byPeer
            local list=byPeer[packet.type]or{};byPeer[packet.type]=list
            list[#list+1]={tick=packet.payload.serverTick,reliable=reliable,channel=channel}
            return true
        end}
    local P=require('src.commute.prediction');local values={}
    for index,field in ipairs(P.fields.bike)do values[index]=field=='gear'and 1 or 0 end
    local context={localPlayer=host.players[1],getPredictionSnapshot=function()
        return {key='cadence-bike',mode='bike',values=values}
    end}
    local function frames(seconds)
        for _=1,math.floor(seconds*60+.5)do now=now+1/60;host:_updateHost(1/60,context)end
    end
    frames(3);rtts.slow=250;frames(1.5);sent={};local firstTick=host.serverTick;frames(3)
    local fast,slow=sent.fast,sent.slow
    local paired=true
    for _,peer in ipairs({'fast','slow'})do
        local packets=sent[peer]
        paired=paired and #packets.snapshot==#packets.prediction_snapshot
        for index,snapshot in ipairs(packets.snapshot)do
            paired=paired and snapshot.tick==packets.prediction_snapshot[index].tick
        end
    end
    check('lan_cadence_service_pairs_physics_and_player_updates_per_peer',paired)
    check('lan_cadence_service_preserves_base_tick_time_and_fast_peer_rate',host.serverTick-firstTick==36
        and #fast.snapshot==36 and #slow.snapshot==24)
    check('lan_cadence_other_state_families_keep_their_existing_schedule',#fast.hockey_snapshot==#slow.hockey_snapshot
        and #slow.hockey_snapshot>=4)
    check('lan_cadence_service_does_not_expose_packets_to_pending_peers',sent.private==nil)
    assert(host:_send('slow','radio_state',{sessionId=host.sessionId,revision=1,trackIndex=1,
        active=false,paused=false,muted=false,positionMs=0}))
    assert(host:_sendShopChanges({money=20},{}))
    check('lan_cadence_reliable_control_and_durable_changes_are_not_throttled',#sent.slow.radio_state==1
        and sent.slow.radio_state[1].reliable and sent.slow.shop_state[1].reliable
        and sent.slow.shop_state[1].channel==Protocol.CHANNEL_DURABLE)
end
return Test
