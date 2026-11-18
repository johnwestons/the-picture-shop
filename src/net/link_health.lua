-- A cached ping measures an earlier round trip, not whether gameplay is still
-- reaching authority. Observe both incoming poses and advancing input ACKs.
local Health={}
function Health.info(session)
    local now=session.clock()
    local grace=math.max(1,(tonumber(session.rtt) or 0)/1000+.5)
    local started=session.linkReadyAt or session.connectedAt or now
    local snapshotAge=math.max(0,now-(session.lastAuthoritativeSnapshotAt or started))
    local pending=(session.inputSequence or 0)>(session.lastAcknowledgedInputSequence or 0)
    if pending then session.linkInputPendingSince=session.linkInputPendingSince or now
    else session.linkInputPendingSince=nil end
    local ackAge=math.max(0,now-math.max(session.lastAdvancingInputAckAt or started,
        session.linkInputPendingSince or started))
    local stale=session:isClient() and session.ready==true
        and (snapshotAge>grace or pending and ackAge>grace) or false
    return {stale=stale,snapshotAgeSeconds=snapshotAge,inputAckAgeSeconds=ackAge,
        inputPending=pending,graceSeconds=grace}
end
return Health
