local Test={}
function Test.run(check)
    local Session=require('src.net.session')
    local Protocol=require('src.net.protocol')
    local Codec=require('src.net.codec')
    local Copy=require('src.net.shop_replication').copy
    local Batches=require('src.net.motion_batches')
    local function record(id,precise)
        return {id=id,name=precise and string.rep(string.char(64+id),Protocol.MAX_NAME_BYTES)or'Worker '..id,
            sceneId='warehouse',resting=false,x=precise and 102.23456543212345 or 100,
            y=precise and 23.45678912345678 or 100,velocityX=precise and 4.234567891234567 or 0,
            velocityY=precise and 2.234567891234567 or 0,intentX=precise and .4123456789123456 or 0,
            intentY=precise and .8234567891234567 or 1,moving=precise==true,facing=1,
            animationDistance=precise and 18734.456789123456 or 0,
            character=precise and string.rep('r',48)or'rabbit-worker',
            furColorway=1,overallsColorway=1,inputSequence=precise and 4294967295 or 1}
    end
    local host=Session.new();host.mode='host';host.ready=true;host.sessionId=string.rep('s',64);host.serverTick=27
    host.idToPeer[2]='guest';host.peerToId.guest=2
    local client=Session.new();client.mode='client';client.ready=true;client.localId=2;client.sessionId=host.sessionId
    local wire,maxBytes,totalBytes={},0,0
    host.transport={send=function(_,peer,bytes,channel,reliable)
        assert(channel==Protocol.CHANNEL_STATE and not reliable and peer=='guest')
        local packet=assert(Protocol.decode(bytes));wire[#wire+1]=packet
        maxBytes=math.max(maxBytes,#bytes);totalBytes=totalBytes+#bytes
        client:_handleClientEnvelope(packet);return true
    end}
    local records={record(1),record(2),record(3),record(4)}
    Batches.send(host,records)
    check('lan_four_ordinary_players_share_one_motion_packet',#wire==1 and #wire[1].payload.players==4)
    local separate=0
    for _,p in ipairs(records)do separate=separate+#assert(Protocol.encode('snapshot',
        {sessionId=host.sessionId,serverTick=27,players=Codec.array({p})}))end
    check('lan_motion_batch_removes_repeated_envelope_bandwidth',totalBytes<separate*.75,
        'batch='..totalBytes..' singles='..separate)
    wire={};host.serverTick=28
    for id=1,4 do records[id]=record(id,true)end
    Batches.send(host,records)
    local seen,exact={},true
    for _,packet in ipairs(wire)do for _,p in ipairs(packet.payload.players)do
        exact=exact and not seen[p.id]and require('src.net.shop_replication').equal(p,records[p.id]);seen[p.id]=true
    end end
    check('lan_worst_case_names_and_precision_fit_bounded_motion_batches',#wire>=1 and #wire<4 and maxBytes<=1200)
    check('lan_split_motion_batches_preserve_exact_roster_and_precision',exact and seen[1]and seen[2]and seen[3]and seen[4]
        and client.lastPlayerTicks[1]==28 and client.lastPlayerTicks[4]==28)
    local truck={token=23,model='box',heading=1.234567891234,speed=12.3412345678,
        steer=.3123456789,brake=0,throttle=1,reverse=false,h=2.34567891234,pitch=.123456789}
    local bike={token=23,heading=1.234567891234,speed=8.23456789,steer=.123456789,brake=0}
    records={record(1),record(2),record(3),record(4)}
    records[1].sceneId='commute';records[2].sceneId='commute';records[3].sceneId='commute'
    wire={};host.serverTick=29
    Batches.send(host,records,{getTruckMotion=function(id)return id==1 and truck or nil end,
        getBikeMotion=function(id)return id==2 and bike or nil end})
    check('lan_vehicle_metadata_stays_in_single_player_shards',#wire==3
        and #wire[1].payload.players==1 and wire[1].payload.players[1].id==1 and wire[1].payload.truck
        and #wire[2].payload.players==1 and wire[2].payload.players[1].id==2 and wire[2].payload.bike
        and #wire[3].payload.players==2 and not wire[3].payload.truck and not wire[3].payload.bike)
    local malformed=Copy(records);malformed[2].x=100001
    wire={};host.serverTick=30;Batches.send(host,malformed)
    seen={};for _,packet in ipairs(wire)do for _,p in ipairs(packet.payload.players)do seen[p.id]=true end end
    check('lan_unencodable_motion_record_does_not_starve_valid_players',seen[1]and not seen[2]and seen[3]and seen[4]
        and client.lastPlayerTicks[1]==30 and client.lastPlayerTicks[3]==30 and client.lastPlayerTicks[4]==30)
    check('lan_batched_vehicle_metadata_is_rejected',not Protocol.encode('snapshot',
        {sessionId=host.sessionId,serverTick=31,players=Codec.array({records[1],records[2]}),truck=truck}))
    local duplicates={record(1),record(1)}
    check('lan_motion_batches_reject_duplicate_player_ids',not Protocol.encode('snapshot',
        {sessionId=host.sessionId,serverTick=31,players=Codec.array(duplicates)}))
    local tooMany={record(1),record(2),record(3),record(4),record(4)}
    check('lan_motion_batches_reject_unbounded_rosters',not Protocol.encode('snapshot',
        {sessionId=host.sessionId,serverTick=31,players=Codec.array(tooMany)}))
    host:drainEvents()
    host.transport=nil
    local okay=pcall(Batches.send,host,records)
    local errors=host:drainEvents()
    check('lan_motion_batch_missing_transport_reports_error_without_throwing',okay and #errors==1
        and errors[1].type=='error'and errors[1].message=='Transport is unavailable.')
    host.idToPeer[3]='other';host.peerToId.other=3;host.pendingPeers.private={}
    local attempts,received={},0
    host.transport={send=function(_,peer,bytes)
        attempts[peer]=(attempts[peer]or 0)+1
        if peer=='guest'then return false,'injected peer failure'end
        assert(peer=='other'and Protocol.decode(bytes));received=received+1;return true
    end}
    Batches.send(host,records)
    check('lan_motion_batch_one_failed_peer_does_not_starve_other_joined_peer',received==1 and attempts.guest==1)
    check('lan_motion_batch_does_not_expose_players_to_pending_peer',attempts.private==nil)
    host.idToPeer[2]=nil;host.idToPeer[3]=nil
    attempts={};Batches.send(host,records)
    check('lan_motion_batch_without_joined_peers_sends_nothing',next(attempts)==nil)
end
return Test
