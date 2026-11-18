local Test={}
function Test.run(check)
    local P=require('src.commute.prediction')
    local Rider=require('src.commute.rider')
    local Bike=require('src.commute.motorcycle')
    local Session=require('src.net.session')
    local C=require('src.commute.runtime')
    local Copy=require('src.net.shop_replication').copy
    local Protocol=require('src.net.protocol')
    local state=require('src.state').new()
    local world={height=function(_,x,z)return math.sin(x*.025)*.08+z*.001 end,
        roads={nearest=function()return 0,{width=8}end,sample=function()return 0,{width=8}end,
            blocked=function()return false end}}
    world.supportHeight=world.height
    local part={slot=2,arrived=false,rider=Rider.new(100,100,.123456789123,
        {version=1,outfit='geared',mounted=true,engine=true,revision=0})}
    local bike=part.rider.bike
    bike.speed=5.123456789123;Bike.resetHorizontal(bike);Bike.resetContact(bike,world)
    for _=1,120 do Rider.update(part.rider,P.controls(part.rider,.1,-.6,false),1/60,world)end
    local durable=Copy(part);local token=73;local initial=P.capture(part,token)
    local fullPrecision=false
    for _,value in ipairs(initial.values)do
        if value~=math.floor(value*1e6+.5)/1e6 then fullPrecision=true end
    end
    check('prediction_capture_preserves_full_precision_integration_seed',fullPrecision)
    local player={id=2,homeResidentId='owner'}
    assert(P.restore(player,durable,token,initial));C.syncPlayer(player,player._predictedCommute.part)
    local now,restores,replays=0,0,0
    local client=Session.new({clock=function()return now end})
    client.mode='client';client.ready=true;client.localId=2
    local context={localPlayer=player,predictionKey=function()return P.key(durable,token)end,
        requiresPhysicsPrediction=function()return true end,
        predictLocal=function(dt,x,y,boost,replay)
            if replay then replays=replays+1 end
            P.step(player,durable,token,dt,x,y,boost,world,state)
            C.syncPlayer(player,player._predictedCommute.part)
        end,
        restorePhysicsPrediction=function(snapshot)
            restores=restores+1
            local okay=P.restore(player,durable,token,snapshot)
            if okay then C.syncPlayer(player,player._predictedCommute.part)end
            return okay
        end}
    local snapshots={};local fullBytes,roundedBytes,maxBytes,packets=0,0,0,0
    for frame=1,600 do
        now=frame/60
        context.inputX=.18*math.sin(frame*.025);context.inputY=-.6
        -- Match the input command's existing thousandth precision, while the
        -- physics state itself retains every IEEE double bit.
        context.inputX=math.floor(context.inputX*1000+.5)/1000
        Rider.update(part.rider,P.controls(part.rider,context.inputX,context.inputY,false),1/60,world)
        snapshots[frame]=P.capture(part,token)
        if frame%5==0 then
            local payload=Copy(snapshots[frame]);payload.sessionId='full-precision-bike'
            payload.serverTick=frame/5;payload.playerId=2;payload.sequence=frame;payload.part=1
            local wire=assert(Protocol.encode('prediction_snapshot',payload))
            local rounded=Copy(payload)
            for i,value in ipairs(rounded.values)do rounded.values[i]=math.floor(value*1e6+.5)/1e6 end
            fullBytes=fullBytes+#wire;roundedBytes=roundedBytes+#assert(Protocol.encode('prediction_snapshot',rounded))
            maxBytes=math.max(maxBytes,#wire);packets=packets+1
        end
        if frame>=20 and frame%5==0 then
            local snapshot=Copy(snapshots[frame-15]);snapshot.sequence=frame-15;snapshot.serverTick=frame/5
            client.physicsPredictionSnapshot=snapshot
        end
        client:_updateClientPrediction(1/60,context)
    end
    check('prediction_full_precision_bike_seed_avoids_derivative_replay_on_slopes_and_turns',
        restores==0 and replays==0,'restores='..restores..' replays='..replays)
    check('prediction_full_precision_bike_retains_authoritative_physics',P.matches(P.captureLocal(player),P.capture(part,token)))
    check('prediction_full_precision_checkpoint_stays_within_packet_budget',maxBytes<=Protocol.MAX_PACKET_BYTES,
        ('full mean=%.2f rounded mean=%.2f max=%d packets=%d'):format(fullBytes/packets,roundedBytes/packets,maxBytes,packets))

    -- Intentional scalar speed changes must still reset horizontal velocity on
    -- the next update. Restoring the old marker to speed would conceal them.
    bike.speed=3.123456789123;bike._velocitySpeed=4.432109876543
    local reset=P.capture(part,token)
    assert(P.restore(player,durable,token,reset))
    local private=player._predictedCommute.rider.bike
    check('prediction_restore_preserves_authoritative_velocity_reset_marker',
        private.speed==bike.speed and private._velocitySpeed==bike._velocitySpeed
        and private._velocitySpeed~=private.speed)
    Rider.update(part.rider,P.controls(part.rider,0,-.2,false),1/60,world)
    P.step(player,durable,token,1/60,0,-.2,false,world,state)
    check('prediction_velocity_reset_after_restore_matches_host_next_step',P.matches(P.captureLocal(player),P.capture(part,token)))
end
return Test
