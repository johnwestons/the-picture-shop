-- Congestion changes only which peers receive a base motion tick. Server ticks
-- keep their original 12 Hz meaning, and local simulation/inputs keep running.
local Cadence={BASE_HZ=12,REDUCED_HZ=8,MAX_PEERS=3,SAMPLE_SECONDS=.25,
    MAX_SAMPLE_GAP=.75,WARMUP_SECONDS=2,DOWN_SECONDS=.5,RECOVER_SECONDS=20}
local function finite(value)
    return type(value)=='number'and value==value and value~=math.huge and value~=-math.huge
end
local function sample(session,peer,entry,now)
    if entry.sampledAt and now-entry.sampledAt<Cadence.SAMPLE_SECONDS then return end
    local previous=entry.sampledAt
    entry.sampledAt=now
    local read=session.transport and session.transport.peerRoundTripTime
    local okay,rtt=false,nil
    if type(read)=='function'then okay,rtt=pcall(read,session.transport,peer)end
    if not okay or not finite(rtt)or rtt<0 or rtt>60000 then
        entry.hz,entry.phase=Cadence.BASE_HZ,0
        entry.roundTripTimeMs,entry.highSince,entry.highSamples,entry.healthySince=nil,nil,nil,nil
        return
    end
    entry.roundTripTimeMs=rtt
    if not entry.minimumMs then
        entry.firstSampleAt=entry.firstSampleAt or now
        -- ENet starts with a synthetic 500 ms estimate. A decreasing estimate
        -- proves a lower measured baseline; an increasing one needs warm-up so
        -- a constant high-latency path is not mistaken for queue growth.
        if rtt<500 then entry.warmMinimum=math.min(entry.warmMinimum or rtt,rtt)end
        if now-entry.firstSampleAt<Cadence.WARMUP_SECONDS then return end
        entry.minimumMs=math.min(entry.warmMinimum or rtt,rtt)
        entry.warmMinimum=nil
    end
    entry.minimumMs=math.min(entry.minimumMs or rtt,rtt)
    if not previous or now-previous>Cadence.MAX_SAMPLE_GAP then
        entry.highSince,entry.highSamples,entry.healthySince=nil,nil,nil
    end
    local inflation=rtt-entry.minimumMs
    local high=inflation>=math.max(60,entry.minimumMs*.4)
    local healthy=inflation<=math.max(25,entry.minimumMs*.2)
    if high then
        entry.healthySince=nil
        entry.highSince=entry.highSince or now
        entry.highSamples=math.min(3,(entry.highSamples or 0)+1)
        if entry.hz==Cadence.BASE_HZ and entry.highSamples>=3
            and now-entry.highSince>=Cadence.DOWN_SECONDS then
            entry.hz,entry.phase=Cadence.REDUCED_HZ,0
            entry.changedAt=now
        end
    else
        entry.highSince,entry.highSamples=nil,nil
        if healthy then
            entry.healthySince=entry.healthySince or now
            if entry.hz<Cadence.BASE_HZ and now-entry.healthySince>=Cadence.RECOVER_SECONDS then
                entry.hz,entry.phase=Cadence.BASE_HZ,0
                entry.changedAt=now
            end
        else entry.healthySince=nil end
    end
end
function Cadence.recipients(session,elapsedTicks,now)
    local joined={}
    for _,peer in pairs(session.idToPeer)do
        local shopPeer=session.shopPeers and session.shopPeers[peer]
        if not shopPeer or not shopPeer.awaitingReady then joined[peer]=true end
    end
    if session.networkKind~='lan'or not finite(now)then session.motionCadence=nil;return joined end
    local state=session.motionCadence
    if not state or state.sessionId~=session.sessionId or now<(state.lastAt or now)then
        state={sessionId=session.sessionId,peers={}};session.motionCadence=state
    end
    state.lastAt=now
    local count=0
    for peer in pairs(state.peers)do
        if not joined[peer]then state.peers[peer]=nil else count=count+1 end
    end
    local due={}
    for peer in pairs(joined)do
        local entry=state.peers[peer]
        if not entry and count<Cadence.MAX_PEERS then
            entry={hz=Cadence.BASE_HZ,phase=0,sent=0,skipped=0}
            state.peers[peer]=entry;count=count+1
        end
        if not entry then due[peer]=true else
            sample(session,peer,entry,now)
            entry.phase=entry.phase+entry.hz*elapsedTicks
            if entry.phase>=Cadence.BASE_HZ then
                entry.phase=entry.phase%Cadence.BASE_HZ
                entry.sent=entry.sent+1;due[peer]=true
            else entry.skipped=entry.skipped+1 end
        end
    end
    return due
end
return Cadence
