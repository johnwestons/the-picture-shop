local Test={}
function Test.run(check)
    local Session=require('src.net.session')
    local Protocol=require('src.net.protocol')
    local Commands=require('src.net.movement_commands')
    local function fixture()
        local now,sequence=0,0
        local host=Session.new({clock=function()return now end})
        host.mode='host';host.ready=true;host.localId=1;host.sessionId='host-clock'
        local function player(id)
            return {id=id,name='Worker '..id,character='rabbit-worker',sceneId='warehouse',x=100,y=100,
                velocityX=0,velocityY=0,intentX=0,intentY=0,facing=1,moving=false,resting=false,
                animationDistance=0,inputSequence=0,furColorway=1,overallsColorway=1,lastInputAt=0}
        end
        host:_installRoster({player(1),player(2),player(3)},0)
        local events,history={},{}
        local acknowledged={[2]=0,[3]=0}
        local steps,neutral,maxSteps=0,0,0
        local context={localPlayer=host.players[1],predictionKey=function()return 'warehouse'end,
            requiresPhysicsPrediction=function()return true end,
            moveRemote=function(p,dt,x)
                steps=steps+1;if x==0 then neutral=neutral+1 end
                p.x=p.x+(x or 0)*dt;p.y=p.y+dt
            end}
        host.transport={service=function(_,maximum)
            local batch={};for _=1,math.min(maximum,#events)do batch[#batch+1]=table.remove(events,1)end
            return batch
        end,send=function(_,_,packet)
            local envelope=assert(Protocol.decode(packet))
            if envelope.type=='snapshot' then
                for _,record in ipairs(envelope.payload.players)do
                    if acknowledged[record.id] then acknowledged[record.id]=math.max(acknowledged[record.id],record.inputSequence or 0)end
                end
            end
            return true
        end}
        for id=2,3 do host.idToPeer[id]='peer'..id;host.peerToId['peer'..id]=id end
        local function produce()
            local ack=math.min(acknowledged[2],acknowledged[3])
            while history[1] and history[1].sequence<=ack do table.remove(history,1)end
            sequence=sequence+1;history[#history+1]={sequence=sequence,x=1,y=0,boost=false}
            if #history>120 then table.remove(history,1)end
            if sequence%3~=0 then return end
            local packet=assert(Protocol.encode('input',{sessionId=host.sessionId,sequence=sequence,
                moveX=1,moveY=0,commandKey='warehouse',commands=Commands.pack(history)}))
            for id=2,3 do events[#events+1]={type='receive',peer='peer'..id,channel=Protocol.CHANNEL_STATE,data=packet}end
        end
        local function update(dt,clockDt)
            if clockDt~=nil then now=now+clockDt end
            steps=0;host:update(dt,context);maxSteps=math.max(maxSteps,steps)
            return steps
        end
        local function advance(frames,runHost)
            for _=1,frames do now=now+1/60;produce();if runHost then update(1/60)end end
        end
        return {host=host,advance=advance,update=update,produce=produce,
            sequence=function()return sequence end,events=events,
            stats=function()return maxSteps,neutral end,
            clock=function(value)if value~=nil then now=value end;return now end}
    end
    for _,pause in ipairs({.8,2,5})do
        local f=fixture();f.advance(60,true)
        for repetition=1,3 do
            f.advance(math.floor(pause*60),false)
            local before=f.host.players[2].inputSequence
            f.update(pause)
            check('host_clock_'..pause..'s_stall_first_frame_has_bounded_work_'..repetition,
                select(1,f.stats())<=30 and f.host.players[2].inputSequence>=before)
            f.advance(180,true)
            local queue=#f.host.players[2]._commandQueue
            check('host_clock_'..pause..'s_stall_does_not_leave_permanent_input_backlog_'..repetition,
                queue<=3 and f.sequence()-f.host.players[2].inputSequence<=3,
                'queue='..queue..' pending='..(f.sequence()-f.host.players[2].inputSequence))
        end
        check('host_clock_'..pause..'s_stall_preserves_queue_and_credit_bounds',
            #f.host.players[3]._commandQueue<=3 and f.host.players[2]._commandBudget<=1
                and f.host.players[3]._commandBudget<=1)
    end
    local f=fixture();f.advance(60,true)
    f.advance(48,false);f.update(.25) -- Upstream caller already clamped dt.
    f.advance(90,true)
    check('host_clock_uses_trusted_wall_time_when_upstream_dt_was_clamped',
        f.sequence()-f.host.players[2].inputSequence<=3)
    f=fixture();f.advance(60,true);f.advance(300,false)
    local acknowledged=f.host.players[2].inputSequence
    f.update(5)
    local frames=1;local monotonic=true
    while #f.events>0 do
        local previous=f.host.players[2].inputSequence
        -- The native service queue spans several64-event batches. No new
        -- client time is produced while those stale datagrams are consumed.
        local worked=f.update(0)
        monotonic=monotonic and f.host.players[2].inputSequence>=previous and worked==0
        frames=frames+1
    end
    check('host_clock_long_stall_rebases_every_saturated_service_batch_without_free_movement',
        frames>=3 and monotonic and f.host.players[2].inputSequence>=acknowledged
        and #f.host.players[2]._commandQueue<=3 and f.host.hostCommandRebase==nil)
    f.advance(60,true)
    check('host_clock_saturated_recovery_converges_after_fresh_input',
        f.sequence()-f.host.players[2].inputSequence<=3 and #f.host.players[3]._commandQueue<=3)

    for _,waveSize in ipairs({10,64})do
        local delayed=fixture();delayed.advance(60,true);delayed.update(1/30,1/30);delayed.advance(300,false)
        local waiting={};for i,event in ipairs(delayed.events)do waiting[i]=event end
        for i=#delayed.events,1,-1 do delayed.events[i]=nil end
        delayed.update(5) -- Nothing arrived in the first post-stall poll.
        local nextEvent=1
        while nextEvent<=#waiting do
            for _=1,waveSize do
                if waiting[nextEvent]then delayed.events[#delayed.events+1]=waiting[nextEvent];nextEvent=nextEvent+1 end
            end
            delayed.update(1/60,1/60)
        end
        delayed.advance(120,true)
        check('host_clock_delayed_'..waveSize..'_event_waves_do_not_rebuild_permanent_backlog',
            delayed.sequence()-delayed.host.players[2].inputSequence<=3 and #delayed.host.players[3]._commandQueue<=3
            and not delayed.host.players[2]._commandHostStall and not delayed.host.players[3]._commandHostStall)
    end
    for _,waveSize in ipairs({10,64})do
        local network=fixture();network.advance(60,true);network.update(1/30,1/30)
        local waiting={}
        for _=1,300 do
            network.advance(1,false)
            for _,event in ipairs(network.events)do waiting[#waiting+1]=event end
            for i=#network.events,1,-1 do network.events[i]=nil end
            network.update(1/60) -- Host keeps running while the link is stalled.
        end
        check('host_clock_network_outage_enters_shared_recovery_without_host_stall_'..waveSize,
            network.host.players[2]._commandOutage==true and network.host.players[2]._commandHostStall==true)
        local nextEvent=1
        while nextEvent<=#waiting do
            for _=1,waveSize do
                if waiting[nextEvent]then network.events[#network.events+1]=waiting[nextEvent];nextEvent=nextEvent+1 end
            end
            network.update(1/60,1/60)
        end
        network.advance(120,true)
        check('host_clock_network_outage_delayed_'..waveSize..'_event_waves_do_not_rebuild_backlog',
            network.sequence()-network.host.players[2].inputSequence<=3 and #network.host.players[3]._commandQueue<=3
            and not network.host.players[2]._commandHostStall and not network.host.players[3]._commandHostStall)
    end

    -- A full redundant batch can move its first sequence without an ACK;
    -- only a shortened, same-generation history beyond the fixed barrier
    -- proves that the client observed the authoritative recovery checkpoint.
    local recovery=fixture();recovery.advance(60,true)
    local p=recovery.host.players[2]
    p._commandHostStall=true;p._commandRecoverySequence=100
    local context={predictionKey=function()return 'warehouse'end}
    local function batch(last,count,legacy)
        local history={};for sequence=last-count+1,last do history[#history+1]={sequence=sequence,x=1,y=0}end
        local commands=Commands.pack(history)
        return {sequence=last,commandKey='warehouse',commands=legacy and Commands.unpack(commands)or commands}
    end
    recovery.host:_queueMovementCommands(p,batch(300,120),context)
    check('host_clock_full_120_frame_truncation_is_not_acknowledgement_proof',p._commandHostStall==true)
    recovery.host:_queueMovementCommands(p,batch(312,12,true),context)
    check('host_clock_legacy_12_frame_truncation_is_not_acknowledgement_proof',p._commandHostStall==true)
    recovery.host:_queueMovementCommands(p,batch(313,1),context)
    check('host_clock_shortened_history_beyond_fixed_barrier_finishes_recovery',
        not p._commandHostStall and p._commandRecoverySequence==nil)
    p._commandHostStall=true;p._commandRecoverySequence=100
    recovery.host:_beginHostCommandFrame(2)
    recovery.host:_queueMovementCommands(p,batch(314,1),context)
    check('host_clock_second_stall_resets_old_barrier_before_accepting_input',
        p._commandHostStall==true and p._commandRecoverySequence==nil)
    recovery.host:_stepRemoteCommands(p,.25,context)
    check('host_clock_second_stall_sets_new_barrier_to_latest_received_sequence',p._commandRecoverySequence==314)

    f=fixture();f.advance(60,true);f.update(1/30,1/30)
    local x,y=f.host.players[2].x,f.host.players[2].y
    f.clock(f.clock()+2);f.update(2)
    local _,neutral=f.stats()
    check('host_clock_stall_with_no_inputs_preserves_bounded_neutral_physics',
        f.host.players[2].x==x and f.host.players[2].y>y and neutral>0 and select(1,f.stats())<=30,
        'x='..f.host.players[2].x..' before='..x..' y='..f.host.players[2].y..' before='..y..' neutral='..neutral)
    local previousY=f.host.players[2].y
    for _=1,120 do f.update(1/120,1/120)end
    check('host_clock_pending_recovery_keeps_neutral_physics_at_120_fps',
        math.abs(f.host.players[2].y-previousY-1)<1e-8 and f.host.players[2]._commandHostStall==true)
    for _,fps in ipairs({120,240})do
        local pending=fixture();pending.advance(60,true);pending.advance(300,false);pending.update(5)
        local actor=pending.host.players[2];local old=actor.inputSequence
        -- Retained latest commands still consume fractional clock credit while
        -- waiting for a client to acknowledge this recovery barrier.
        for _=1,fps/10 do pending.update(1/fps,1/fps)end
        check('host_clock_pending_nonempty_recovery_executes_at_'..fps..'_fps',
            actor.inputSequence>old and #actor._commandQueue==0)
    end
    -- Backward/nonfinite clocks cannot mint elapsed movement credit.
    f=fixture();f.advance(60,true)
    f.clock(f.clock()-10);f.update(0)
    f.clock(0/0);f.update(0)
    check('host_clock_invalid_samples_do_not_create_nonfinite_credit',
        f.host.players[2]._commandBudget==f.host.players[2]._commandBudget and f.host.players[2]._commandBudget<=1)
end
return Test
