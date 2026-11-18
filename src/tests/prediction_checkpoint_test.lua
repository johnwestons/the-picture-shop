local Test={}
function Test.run(check)
    require('src.tests.prediction_obstacles_test').run(check)
    require('src.tests.prediction_truck_fuel_test').run(check)
    require('src.tests.prediction_precision_test').run(check)
    local P=require('src.commute.prediction')
    local Session=require('src.net.session')
    local Rider=require('src.commute.rider')
    local C=require('src.commute.runtime')
    local Copy=require('src.net.shop_replication').copy
    local part={slot=2,arrived=false,rider=Rider.new(100,100,0,
        {version=1,outfit='normal',mounted=false,engine=false,revision=0})}
    local state=require('src.state').new()
    local world={height=function()return 0 end,supportHeight=function()return 0 end,
        roads={nearest=function()return 0,{width=8}end,sample=function()return 0,{width=8}end,blocked=function()return false end}}
    local now,token=0,31
    local client=Session.new({clock=function()return now end})
    client.mode='client';client.ready=true;client.localId=2
    local player={id=2,homeResidentId='owner',x=100,y=100}
    local reference={id=2,homeResidentId='owner',x=100,y=100}
    local replays,restores,steps=0,0,0
    local context={localPlayer=player,predictionKey=function()return P.key(part,token)end,
        requiresPhysicsPrediction=function()return true end,
        predictLocal=function(dt,x,y,boost,replay)
            steps=steps+1;if replay then replays=replays+1 end
            P.step(player,part,token,dt,x,y,boost,world,state)
            C.syncPlayer(player,player._predictedCommute.part)
        end,
        restorePhysicsPrediction=function(snapshot)
            restores=restores+1
            local result=P.restore(player,part,token,snapshot)
            if result then C.syncPlayer(player,player._predictedCommute.part)end
            return result
        end}
    local snapshots={}
    for frame=1,240 do
        now=frame/60
        context.inputX=frame<=70 and 1 or frame<=130 and 0 or frame<=190 and -1 or 0
        context.inputY=frame>70 and frame<=130 and 1 or frame>190 and -1 or 0
        P.step(reference,part,token,1/60,context.inputX,context.inputY,false,world,state)
        snapshots[frame]=P.captureLocal(reference)
        if frame>=15 and frame%5==0 then
            local snapshot=Copy(snapshots[frame-10]);snapshot.sequence=frame-10;snapshot.serverTick=frame/5
            client.physicsPredictionSnapshot=snapshot
        end
        client:_updateClientPrediction(1/60,context)
    end
    check('prediction_matching_full_checkpoints_skip_all_replay_through_walk_turns',
        replays==0 and restores==0 and steps==240,'steps='..steps..' replay='..replays..' restores='..restores)
    check('prediction_matching_checkpoint_keeps_full_precision_private_physics',
        player.x==reference._predictedCommute.rider.ped.x and player.y==reference._predictedCommute.rider.ped.z
        and part.rider.ped.x==100 and #client.commandPrediction.history==10)

    local sequence=client.inputSequence-5
    local collision=Copy(snapshots[sequence]);collision.sequence=sequence;collision.serverTick=1000
    collision.values[1]=collision.values[1]+1
    client.physicsPredictionSnapshot=collision
    local beforeX=player.x
    client:_updateClientPrediction(0,context)
    check('prediction_authoritative_collision_forces_restore_and_pending_replay',
        restores==1 and replays==5 and math.abs(player.x-beforeX-1)<.00001)
    local neutral=Copy(collision);neutral.values[1]=neutral.values[1]+.5;neutral.serverTick=1001
    client.physicsPredictionSnapshot=neutral;beforeX=player.x
    client:_updateClientPrediction(0,context)
    check('prediction_repeated_ack_neutral_outage_physics_is_not_skipped',
        restores==2 and replays==10 and math.abs(player.x-beforeX-.5)<.00001)
    local same=Copy(neutral);same.serverTick=1002
    client.physicsPredictionSnapshot=same
    client:_updateClientPrediction(0,context)
    check('prediction_repeated_unchanged_ack_does_not_repeat_replay',restores==2 and replays==10)
    local velocity=Copy(neutral);velocity.serverTick=1003;velocity.values[8]=velocity.values[8]+.01
    client.physicsPredictionSnapshot=velocity
    client:_updateClientPrediction(0,context)
    check('prediction_velocity_mismatch_requires_reconciliation_even_at_same_position',restores==3 and replays==15)

    local old=client.commandPrediction
    token=32
    client:_updateClientPrediction(1/60,context)
    check('prediction_changed_trip_key_discards_all_checkpoint_cache',client.commandPrediction~=old
        and #client.commandPrediction.history==1 and client.commandPrediction.ackCheckpoint==nil
        and client.commandPrediction.history[1].checkpoint.key==P.key(part,token))
    client.physicsPredictionSnapshot=nil
    for _=1,300 do now=now+1/60;client:_updateClientPrediction(1/60,context)end
    local history=client.commandPrediction.history
    local bounded=#history==240
    for _,command in ipairs(history)do bounded=bounded and #command.checkpoint.values==#P.fields.ped end
    check('prediction_checkpoint_cache_is_capped_with_command_history',bounded)
    local lost=Copy(history[1].checkpoint);lost.sequence=history[1].sequence-1;lost.serverTick=2000
    client.physicsPredictionSnapshot=lost
    local previousRestores=restores
    client:_updateClientPrediction(0,context)
    check('prediction_ack_outside_retained_cache_uses_authoritative_fallback',restores==previousRestores+1)

    local complete=true
    for mode,names in pairs(P.fields)do
        local base={key='checkpoint-'..mode,mode=mode,values={}}
        for i=1,#names do base.values[i]=0 end
        for i=1,#names do
            local other=Copy(base);other.values[i]=.00001
            complete=complete and not P.matches(base,other)
        end
    end
    check('prediction_checkpoint_match_compares_every_physics_field_in_every_mode',complete)
    local base=Copy(history[#history].checkpoint)
    local rounded=Copy(base);rounded.values[1]=rounded.values[1]+.000001
    local changed=Copy(base);changed.values[1]=changed.values[1]+.000002
    check('prediction_checkpoint_tolerance_is_limited_to_one_quantization_unit',P.matches(base,rounded)and not P.matches(base,changed))
    changed=Copy(base);changed.values[11]=changed.values[11]+.0000001
    check('prediction_checkpoint_boolean_states_require_exact_agreement',not P.matches(base,changed))
    changed=Copy(base);changed.mode='bike'
    local wrongKey=Copy(base);wrongKey.key=wrongKey.key..'-other'
    local missing=Copy(base);missing.values[#missing.values]=nil
    local nan=Copy(base);nan.values[1]=0/0
    local infinite=Copy(base);infinite.values[1]=math.huge
    check('prediction_checkpoint_rejects_wrong_mode_key_shape_and_nonfinite_values',
        not P.matches(base,changed)and not P.matches(base,wrongKey)and not P.matches(base,missing)
        and not P.matches(base,nan)and not P.matches(base,infinite))
end
return Test
