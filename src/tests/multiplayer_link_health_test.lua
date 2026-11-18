local Test={}
function Test.run(check)
    local Session=require('src.net.session')
    local Hud=require('src.screens.multiplayer_hud')
    local now=0
    local client=Session.new({clock=function() return now end})
    client.mode='client';client.ready=true;client.localId=2;client.sessionId='health'
    client.linkReadyAt=0;client.rtt=20;client.lastPongAt=0;client.inputSequence=100
    local tick=0
    local function snapshot(ack)
        tick=tick+1
        client:_applySnapshot({sessionId=client.sessionId,serverTick=tick,players={
            {id=2,name='Guest',sceneId='warehouse',x=100,y=100,inputSequence=ack}}})
    end
    snapshot(1);client:hudInfo()
    now=1.01
    check('link_health_cached_good_ping_cannot_hide_missing_snapshots',
        client:hudInfo().connectionStale and Hud.statusSummary(client:hudInfo()).connection=='WAITING FOR HOST')
    snapshot(1)
    check('link_health_repeated_snapshot_ack_does_not_hide_upstream_failure',client:hudInfo().connectionStale)
    check('link_health_diagnostics_expose_authority_and_ack_freshness',
        client:debugInfo().connectionStale and client:debugInfo().snapshotAgeSeconds==0
        and client:debugInfo().inputAckAgeSeconds>1)
    snapshot(2)
    check('link_health_advancing_ack_restores_connection_status',not client:hudInfo().connectionStale
        and Hud.statusSummary(client:hudInfo()).connection=='CONNECTED • 20 MS • GOOD')
    client.rtt=800
    now=2.21
    check('link_health_benign_800ms_rtt_has_sufficient_grace',not client:hudInfo().connectionStale
        and math.abs(client:hudInfo().connectionGraceSeconds-1.3)<1e-9)
    for i=1,20 do now=now+.1;snapshot(i+2);assert(not client:hudInfo().connectionStale) end
    check('link_health_slow_but_advancing_connection_stays_live',not client:hudInfo().connectionStale)
    snapshot(100);client:hudInfo()
    now=now+10;snapshot(100);client:hudInfo()
    client.inputSequence=101
    check('link_health_resuming_after_idle_gets_ack_grace',not client:hudInfo().connectionStale)
    client.mode='host';now=now+20
    check('link_health_host_status_is_unaffected',not client:hudInfo().connectionStale
        and Hud.statusSummary(client:hudInfo()).connection=='HOST ONLINE')
    client:stop()
    check('link_health_disconnect_clears_previous_session_timestamps',client.linkReadyAt==nil
        and client.lastAuthoritativeSnapshotAt==nil and client.lastAdvancingInputAckAt==nil
        and client.lastAcknowledgedInputSequence==nil and client.linkInputPendingSince==nil)
end
return Test
