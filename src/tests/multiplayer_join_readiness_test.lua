local Test={}
function Test.run(check)
    local Session=require('src.net.session')
    local Protocol=require('src.net.protocol')
    local Refresh=require('src.net.snapshot_refresh')
    local Cadence=require('src.net.motion_cadence')
    local now=0
    local host=Session.new({clock=function()return now end})
    host.mode='host';host.ready=true;host.localId=1;host.sessionId='join-ready'
    host:_installRoster({{id=1,x=100,y=100},{id=2,x=120,y=100},{id=3,x=140,y=100}},0)
    host.idToPeer={[2]='ready',[3]='loading'};host.peerToId={ready=2,loading=3}
    host.pendingPeers.private={connectedAt=now}
    host:_rememberShopPeer('ready',{money=10},{},false)
    host:_rememberShopPeer('loading',{money=10},{},true)
    local deliveries,reads={},{}
    local failLoading=false
    host.transport={peerRoundTripTime=function(_,peer)reads[peer]=(reads[peer]or 0)+1;return 100 end,
        send=function(_,peer,bytes,channel,reliable)
            if failLoading and peer=='loading'then failLoading=false;return false,'injected send failure'end
            deliveries[#deliveries+1]={peer=peer,envelope=assert(Protocol.decode(bytes)),channel=channel,reliable=reliable}
            return true
        end}
    local function count(peer,kind)
        local found=0
        for _,item in ipairs(deliveries)do if item.peer==peer and (not kind or item.envelope.type==kind)then found=found+1 end end
        return found
    end
    local context={localPlayer=host.players[1]}
    for frame=1,60 do now=frame/60;host:_updateHost(1/60,context)end
    check('lan_join_loading_peer_does_not_receive_unusable_realtime_state',count('loading')==0
        and count('ready','snapshot')==12 and count('ready','hockey_snapshot')>=2)
    check('lan_join_deferral_does_not_mark_refresh_or_cadence_baselines',host.snapshotRefresh.loading==nil
        and host.motionCadence.peers.loading==nil and reads.loading==nil)
    check('lan_join_pending_peer_stays_outside_all_realtime_recipient_sets',count('private')==0)
    for _,kind in ipairs({'lan','direct','server'})do
        host.networkKind=kind
        local due=Cadence.recipients(host,1,now)
        check('lan_join_'..kind..'_only_ready_peers_receive_motion',due.ready and not due.loading and not due.private)
    end
    host.networkKind='lan'
    assert(host:_broadcastJoined('radio_state',{sessionId=host.sessionId,revision=1,trackIndex=1,
        active=false,paused=false,muted=false,positionMs=0}))
    assert(host:_broadcastJoined('leave',{sessionId=host.sessionId,playerId=4,reason='disconnected',serverTick=host.serverTick}))
    check('lan_join_reliable_control_broadcasts_continue_while_initial_state_loads',count('loading','radio_state')==1
        and count('loading','leave')==1 and deliveries[#deliveries].reliable)
    local hockey={sessionId=host.sessionId,serverTick=host.serverTick,bayId='front_left',game=false}
    local key=Refresh.key('hockey_snapshot',hockey)
    host.players[3].lastInputSequence=4
    host:_handleHostEnvelope('loading',{type='input',payload={sessionId='another-session',sequence=5,moveX=0,moveY=0}},context)
    host:_handleHostEnvelope('loading',{type='input',payload={sessionId=host.sessionId,sequence=4,moveX=0,moveY=0}},context)
    check('lan_join_wrong_session_and_stale_input_cannot_release_ready_gate',host.shopPeers.loading.awaitingReady)
    host:_handleHostEnvelope('loading',assert(Protocol.make('input',{
        sessionId=host.sessionId,sequence=5,moveX=0,moveY=0})),context)
    check('lan_join_first_valid_neutral_input_releases_ready_gate',not host.shopPeers.loading.awaitingReady and host.shopDirty)
    failLoading=true
    local okay=host:_broadcastJoined('hockey_snapshot',hockey)
    check('lan_join_failed_first_auxiliary_send_keeps_fresh_baseline_due',not okay
        and Refresh.due(host,'loading',key,'hockey_snapshot',hockey,now))
    assert(host:_broadcastJoined('hockey_snapshot',hockey))
    check('lan_join_first_ready_auxiliary_state_arrives_without_waiting_for_refresh',count('loading','hockey_snapshot')==1
        and not Refresh.due(host,'loading',key,'hockey_snapshot',hockey,now))
    local before=count('loading','snapshot')
    now=now+1/12;host:_updateHost(1/12,context)
    check('lan_join_first_ready_motion_arrives_on_next_base_tick',count('loading','snapshot')==before+1)

    -- Rejoining the same peer clears old refresh entries, then waits again.
    host:_rememberShopPeer('loading',{money=10},{},true)
    host:_rememberShopPeer('ready',{money=10},{},true)
    local encode=host._encode;local encodes=0
    host._encode=function(...)encodes=encodes+1;return encode(...)end
    okay=host:_broadcastJoined('hockey_snapshot',hockey)
    local due=Cadence.recipients(host,1,now)
    check('lan_join_all_loading_peers_skip_realtime_encoding_without_error',okay and encodes==0 and next(due)==nil
        and host.snapshotRefresh.loading==nil and host.snapshotRefresh.ready==nil)
    host._encode=encode
end
return Test
