-- Compact player tuples can share an existing snapshot envelope. Vehicle view
-- metadata still belongs to exactly one player, so those records stay separate.
local Codec=require('src.net.codec')
local Protocol=require('src.net.protocol')
local Batches={}
function Batches.send(session,records,context,recipients)
    if #records==0 or not next(session.idToPeer)or recipients and not next(recipients)then return end
    if not session.transport or type(session.transport.send)~='function'then
        session:_queue('error',{message='Transport is unavailable.'})
        return
    end
    local pending,pendingWire
    local function payload(players,bike,truck)
        return {sessionId=session.sessionId,serverTick=session.serverTick,
            players=Codec.array(players),bike=bike,truck=truck}
    end
    local function encode(value)
        local wire,reason=session:_encode('snapshot',value)
        if wire and #wire>Protocol.MAX_PACKET_BYTES then return nil,'Motion snapshot exceeds packet limit.'end
        return wire,reason
    end
    local function send(wire)
        local channel,reliable=session:_route('snapshot')
        for _,peer in pairs(session.idToPeer)do
            if not recipients or recipients[peer]then
                local okay,reason=session.transport:send(peer,wire,channel,reliable)
                if not okay then session:_queue('error',{message=reason})end
            end
        end
    end
    local function flush()
        if pendingWire then send(pendingWire)end
        pending,pendingWire=nil,nil
    end
    for _,record in ipairs(records)do
        local bike=record.sceneId=='commute'and context and context.getBikeMotion and context.getBikeMotion(record.id)or nil
        local truck=record.sceneId=='commute'and context and context.getTruckMotion and context.getTruckMotion(record.id)or nil
        if bike or truck then
            flush()
            local wire,reason=encode(payload({record},bike,truck))
            if wire then send(wire)else session:_queue('error',{message=reason})end
        else
            local trial={}
            for index,previous in ipairs(pending or {})do trial[index]=previous end
            trial[#trial+1]=record
            local wire,reason=encode(payload(trial))
            if not wire and pending then
                -- A full batch or one malformed record must not discard the
                -- valid records already collected, nor starve later players.
                flush();trial={record};wire,reason=encode(payload(trial))
            end
            if wire then pending,pendingWire=trial,wire
            else session:_queue('error',{message=reason})end
        end
    end
    flush()
end
return Batches
