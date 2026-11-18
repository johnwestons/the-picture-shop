local Test={}
function Test.run(check)
    local Protocol=require('src.net.protocol')
    local Codec=require('src.net.codec')
    local Wire=require('src.net.player_wire')
    local R=require('src.net.shop_replication')
    local function player(id)
        return {id=id,name='WiFi Test Guest '..id,sceneId='warehouse',resting=false,
            x=172.88108706268+id,y=404.81948761382+id,velocityX=-4.2223737635027,
            velocityY=2.8819798697842,intentX=-.82594602786754,intentY=.56374919871325,
            moving=true,facing=-1,animationDistance=4387.1833068915,
            character='rabbit-worker',furColorway=1,overallsColorway=1,inputSequence=21461}
    end
    local payload={sessionId='snapshot-compression-test',serverTick=9784,
        players=Codec.array({player(1),player(2),player(3)})}
    local function canonical(value,limit)
        local envelope=assert(Protocol.make('snapshot',value))
        for index,record in ipairs(envelope.payload.players)do envelope.payload.players[index]=Wire.pack(record)end
        return assert(Codec.encode(envelope,{maxBytes=limit or 1200,maxDepth=8,maxEntries=256,
            maxStringBytes=1200,maxNumberBytes=32}))
    end
    local raw=canonical(payload)
    local packet=assert(Protocol.encode('snapshot',payload))
    local compressed=packet:sub(1,4)==Protocol.SHOP_COMPRESSION_MAGIC
    check('lan_snapshot_batch_compression_saves_at_least_sixty_four_bytes',compressed and #packet+64<=#raw)
    check('lan_snapshot_compression_preserves_all_player_fields_and_precision',
        R.equal(assert(Protocol.decode(packet)),assert(Protocol.make('snapshot',payload))))
    local solo=R.copy(payload);solo.players=Codec.array({player(1)})
    local soloRaw=canonical(solo);local soloPacket=assert(Protocol.encode('snapshot',solo))
    local candidate=love.data.compress('string','lz4',soloRaw)
    check('lan_snapshot_unhelpful_compression_keeps_original_packet',#candidate+4+64>#soloRaw and soloPacket==soloRaw)
    local vehicle=R.copy(solo);vehicle.players[1].sceneId='commute'
    vehicle.truck={token=5,model='box',heading=2.542674570292,speed=5.1121666804357,
        steer=-.00069819080280243,brake=.097949919915686,throttle=0,reverse=false,
        h=5.0067244609611,pitch=.0028639739328508}
    check('lan_snapshot_vehicle_metadata_stays_exact_with_optional_compression',R.equal(
        assert(Protocol.decode(assert(Protocol.encode('snapshot',vehicle)))),assert(Protocol.make('snapshot',vehicle))))
    local vehicleWire=require('src.net.vehicle_wire')
    for _,kind in ipairs({'bike','truck'})do
        local value=R.copy(vehicle)
        if kind=='bike'then
            value.bike={token=999999999999,heading=math.pi,speed=17.12345678912345,
                steer=1e-200,brake=.00123456789012345};value.truck=nil
        end
        local original=R.copy(value)
        local encoded=assert(Protocol.encode('snapshot',value))
        local decoded=assert(Protocol.decode(encoded))
        check('lan_'..kind..'_wire_preserves_all_metadata_and_does_not_mutate_source',
            R.equal(decoded.payload[kind],value[kind])and R.equal(original,value))
        local wireRaw=encoded:sub(1,4)=='TPSL'and love.data.decompress('string','lz4',encoded:sub(5))or encoded
        local wireEnvelope=assert(Codec.decode(wireRaw))
        local tuple=wireEnvelope.payload[kind]
        check('lan_'..kind..'_wire_uses_fixed_compact_tuple',Codec.isArray(tuple)
            and #tuple==(kind=='bike'and 2 or 4)and R.equal(vehicleWire.unpack(kind,tuple),value[kind]))
        for index=1,#tuple do
            local malformed=R.copy(wireEnvelope);malformed.payload[kind][index]={}
            check('lan_'..kind..'_tuple_rejects_invalid_field_'..index,not Protocol.decode(assert(Codec.encode(malformed))))
        end
        local extra=R.copy(wireEnvelope);extra.payload[kind][#tuple+1]=0
        local missing=R.copy(wireEnvelope);missing.payload[kind][#tuple]=nil
        check('lan_'..kind..'_tuple_rejects_wrong_length',not Protocol.decode(assert(Codec.encode(extra)))
            and not Protocol.decode(assert(Codec.encode(missing))))
        local namedVehicle=R.copy(wireEnvelope);namedVehicle.payload[kind]=R.copy(value[kind])
        check('lan_'..kind..'_tuple_rejects_noncanonical_named_wire_metadata',not Protocol.decode(assert(Codec.encode(namedVehicle))))
    end
    local named=assert(Codec.encode(assert(Protocol.make('snapshot',solo))))
    check('lan_compressed_snapshot_still_rejects_noncanonical_named_player_records',not Protocol.decode(
        Protocol.SHOP_COMPRESSION_MAGIC..love.data.compress('string','lz4',named)))
    local oversized=R.copy(payload);oversized.players[4]=player(4)
    for _,record in ipairs(oversized.players)do
        record.name=string.rep('n',Protocol.MAX_NAME_BYTES);record.character=string.rep('r',48)
        record.animationDistance=18734.456789123456;record.inputSequence=4294967295
    end
    oversized.games=Codec.array({})
    for index,bay in ipairs({'front_left','front_right'})do
        oversized.games[index]={bayId=bay,mode='solo',phase='playing',leftId=index,
            leftX=221.34167893456,leftY=213.23456781234,rightX=674.657834567,
            rightY=255.45667890234,puckX=431.2345467789,puckY=318.237767431,
            leftScore=2,rightScore=3,faceoff=0}
    end
    local envelope={version=Protocol.VERSION,type='snapshot',payload=R.copy(oversized)}
    for index,record in ipairs(envelope.payload.players)do envelope.payload.players[index]=Wire.pack(record)end
    local largeRaw=assert(Codec.encode(envelope,{maxBytes=4096,maxDepth=8,maxEntries=256,maxStringBytes=1200,maxNumberBytes=32}))
    local largePacket=Protocol.SHOP_COMPRESSION_MAGIC..love.data.compress('string','lz4',largeRaw)
    check('lan_snapshot_compression_does_not_bypass_raw_packet_limit',#largeRaw>1200 and #largePacket<1200
        and not Protocol.encode('snapshot',oversized)and not Protocol.decode(largePacket))
end
return Test
