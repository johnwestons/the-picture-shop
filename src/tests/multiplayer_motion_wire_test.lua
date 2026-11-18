local Test={}
function Test.run(check)
    local Protocol=require('src.net.protocol')
    local Codec=require('src.net.codec')
    local R=require('src.net.shop_replication')
    local record={id=2,name='Motion precision',sceneId='commute',resting=false,taskAction='mop_puddle1',
        x=1e-200,y=-1e-200,velocityX=10000,velocityY=-10000,intentX=1,intentY=-1,
        moving=true,facing=-1,animationDistance=1e9,character='rabbit-worker',
        furColorway=1,overallsColorway=1,inputSequence=4294967295}
    local truck={token=1e12,model='kei',reverse=true,heading=math.pi*2,speed=100,
        steer=-1,brake=1,throttle=1,h=100,pitch=-1.6}
    local bike={token=1e12,heading=-math.pi*2,speed=1e-200,steer=1,brake=0}
    local payload={sessionId='binary-motion-review',serverTick=4294967295,players=Codec.array({record})}
    local function raw(packet)return packet:sub(1,4)=='TPSL'and love.data.decompress('string','lz4',packet:sub(5))or packet end
    local function wire(value)return assert(Codec.decode(raw(assert(Protocol.encode('snapshot',value)))))end
    local function reject(envelope)return not Protocol.decode(assert(Codec.encode(envelope)))end
    local original=R.copy(payload)
    local decoded=assert(Protocol.decode(assert(Protocol.encode('snapshot',payload))))
    check('motion_wire_player_tiny_and_extreme_values_preserve_full_precision',R.equal(decoded.payload,payload)
        and R.equal(payload,original))
    local baseline=wire(payload)
    local tuple=baseline.payload.players[1]
    check('motion_wire_player_has_exactly_seven_binary_doubles',#tuple==12 and #tuple[6]==56
        and love.data.unpack('<d',tuple[6])==record.x)
    local playerBad={100001,-100001,10001,-10001,1.001,-1.001,-1}
    local playerFields={'x','y','velocityX','velocityY','intentX','intentY','animationDistance'}
    for index,name in ipairs(playerFields)do
        local bad=R.copy(baseline);local bytes=bad.payload.players[1][6]
        bad.payload.players[1][6]=bytes:sub(1,(index-1)*8)..love.data.pack('string','<d',playerBad[index])..bytes:sub(index*8+1)
        check('motion_wire_player_retains_'..name..'_bounds',reject(bad))
    end
    for _,kind in ipairs({'bike','truck'})do
        local value=R.copy(payload);value[kind]=R.copy(kind=='bike'and bike or truck)
        local current=wire(value);local metadata=current.payload[kind]
        local fields=kind=='bike'and {'heading','speed','steer','brake'}or {'heading','speed','steer','brake','throttle','h','pitch'}
        local invalid=kind=='bike'and {7,-1,2,2}or {7,-1,2,2,2,101,2}
        local vectorIndex=kind=='bike'and 2 or 4
        check('motion_wire_'..kind..'_full_precision_and_metadata_round_trip',R.equal(
            assert(Protocol.decode(assert(Protocol.encode('snapshot',value)))).payload,value)
            and #metadata[vectorIndex]==#fields*8)
        for index,name in ipairs(fields)do
            local bad=R.copy(current);local bytes=metadata[vectorIndex]
            bad.payload[kind][vectorIndex]=bytes:sub(1,(index-1)*8)..love.data.pack('string','<d',invalid[index])..bytes:sub(index*8+1)
            check('motion_wire_'..kind..'_retains_'..name..'_bounds',reject(bad))
        end
        local short=R.copy(current);short.payload[kind][vectorIndex]=metadata[vectorIndex]:sub(2)
        local long=R.copy(current);long.payload[kind][vectorIndex]=metadata[vectorIndex]..string.rep('\0',8)
        check('motion_wire_'..kind..'_rejects_inexact_vector_lengths',reject(short)and reject(long))
        local prior=R.copy(current)
        prior.payload[kind]=kind=='bike'and Codec.array({bike.token,bike.heading,bike.speed,bike.steer,bike.brake})
            or Codec.array({truck.token,truck.model,truck.heading,truck.speed,truck.steer,truck.brake,truck.throttle,truck.reverse,truck.h,truck.pitch})
        check('motion_wire_'..kind..'_rejects_prior_decimal_tuple_format',reject(prior))
    end
    local malformed={tuple[6]:sub(2),tuple[6]..'\0',string.rep('\0',64),{},false}
    for index,badValue in ipairs(malformed)do
        local bad=R.copy(baseline);bad.payload.players[1][6]=badValue
        check('motion_wire_player_rejects_malformed_vector_'..index,reject(bad))
    end
    local values={0/0,math.huge,-math.huge,-0.0}
    -- Build negative zero from its IEEE sign bit, independent of Lua literal folding.
    local negativeZero=string.char(0,0,0,0,0,0,0,128)
    for index,value in ipairs(values)do
        local bad=R.copy(baseline)
        bad.payload.players[1][6]=(index==4 and negativeZero or love.data.pack('string','<d',value))..tuple[6]:sub(9)
        check('motion_wire_player_rejects_noncanonical_double_'..index,reject(bad))
    end
    local prior=R.copy(baseline)
    prior.payload.players[1]=Codec.array({record.id,record.name,record.sceneId,record.resting,record.taskAction,
        record.x,record.y,record.velocityX,record.velocityY,record.intentX,record.intentY,record.moving,
        record.facing,record.animationDistance,record.character,record.furColorway,record.overallsColorway,record.inputSequence})
    check('motion_wire_rejects_prior_eighteen_field_player_tuple',reject(prior))
    local oldVersion=R.copy(baseline);oldVersion.version=81
    check('motion_wire_rejects_old_protocol_version',reject(oldVersion))
    local welcome=assert(Protocol.decode(assert(Protocol.encode('welcome',{
        sessionId=payload.sessionId,serverTick=payload.serverTick,playerId=2,players=payload.players}))))
    check('motion_wire_welcome_preserves_named_player_contract',R.equal(welcome.payload.players[1],record))
end
return Test
