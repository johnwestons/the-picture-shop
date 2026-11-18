local Test={}
local Session=require('src.net.session')
local Protocol=require('src.net.protocol')
local Controller=require('src.player_controller')
local Config=require('src.config')
local function player(id)
    return {id=id,name='Worker '..id,character='rabbit-worker',sceneId='warehouse',x=100,y=100,
        velocityX=0,velocityY=0,intentX=1,intentY=0,facing=1,moving=false,resting=false,
        animationDistance=0,inputSequence=0,taskAction='none',furColorway=1,overallsColorway=1}
end
local function move(p,dt,x,y)
    Controller.update(p,x,y,dt,function(_,_,nx,ny)return nx>=80 and nx<=380 and ny>=80 and ny<=350 end,Config.player)
end
local function outdoor(check,mode,weak)
    local outage=weak=='outage2' and 2 or weak=='outage5' and 5
    local P=require('src.commute.prediction')
    local Rider=require('src.commute.rider')
    local Truck=require('src.commute.delivery_truck')
    local C=require('src.commute.runtime')
    local Trip=require('src.commute.trip')
    local Copy=require('src.net.shop_replication').copy
    local state=require('src.state').new()
    state.home.residents['guest-1']=Copy(state.home.residents.owner)
    local gear={version=1,outfit=mode=='bike' and 'geared' or 'normal',mounted=mode=='bike',engine=mode=='bike',revision=0}
    local part={slot=2,arrived=false,rider=Rider.new(100,100,0,gear)}
    local trip={version=1,token=71,origin='warehouse',destination='garden',independent=true,participants={['guest-1']=part}}
    if mode=='box' or mode=='kei' then
        part.rider.vehicle='truck';part.rider.truck=Truck.new(100,100,0,nil,mode)
        part.rider.truck.driver='guest-1';trip[mode=='kei' and 'keiTruck' or 'truck']=part.rider.truck
    end
    state.home.commute=trip
    local world={height=function()return 0 end,supportHeight=function()return 0 end,
        roads={nearest=function()return 0,{width=8}end,sample=function()return 0,{width=8}end,blocked=function()return false end}}
    local now=0
    local host=Session.new({clock=function()return now end})
    local client=Session.new({clock=function()return now end})
    host.mode='host';host.ready=true;host.localId=1;host.sessionId='outdoor-test'
    client.mode='client';client.ready=true;client.localId=2;client.sessionId=host.sessionId
    host:_installRoster({player(1),player(2)},0);client:_installRoster({player(1),player(2)},0)
    host.idToPeer[2]='peer';host.peerToId.peer=2
    local hp=host.players[2];hp.homeResidentId='guest-1';C.syncPlayer(hp,part)
    local lp=player(2);lp.homeResidentId='guest-1';C.syncPlayer(lp,part)
    local durable=Copy(part);local cs=Copy(state);local expected=Copy(part)
    local upstream,downstream={},{}
    local count,packets,maxBytes,checkpoints=0,0,0,0
    local function deliver(queue)
        local events={};local i=1
        while i<=#queue do
            if queue[i].at<=now then events[#events+1]=table.remove(queue,i).event else i=i+1 end
        end
        return events
    end
    host.transport={service=function()return deliver(upstream)end,send=function(_,peer,data,channel)
        local envelope=assert(Protocol.decode(data));packets=packets+1;maxBytes=math.max(maxBytes,#data)
        if envelope.type=='prediction_snapshot' then checkpoints=checkpoints+1 end
        if packets%11~=0 and not (weak and now>5 and now<5.45) then downstream[#downstream+1]={at=now+(weak=='slow' and .4 or .15)+(packets%5)*(weak and .027 or .011),
            event={type='receive',data=data,channel=channel,peer=peer}} end
        return true
    end}
    client.transport={service=function()return deliver(downstream)end,sendToServer=function(_,data,channel)
        local envelope=assert(Protocol.decode(data));if envelope.type~='input' then return true end
        count=count+1;maxBytes=math.max(maxBytes,#data)
        if count%9~=0 and not (weak and now>1.8 and now<1.8+(outage or .65)) then upstream[#upstream+1]={at=now+(weak=='slow' and .4 or .15)+(count%7==0 and .09 or 0),
            event={type='receive',data=data,channel=channel,peer='peer'}} end
        return true
    end}
    local frameSteps,maxSteps=0,0
    local hc={localPlayer=host.players[1],predictionKey=function()return P.key(part,71)end,
        requiresPhysicsPrediction=function()return true end,
        getPredictionSnapshot=function()return P.capture(part,71)end,
        moveRemote=function(p,dt,x,y,boost)
            frameSteps=frameSteps+1
            Trip.update(state,p,P.controls(part.rider,x,y,boost),dt,world);C.syncPlayer(p,part)
        end}
    local cc={localPlayer=lp,predictionKey=function()return P.key(durable,71)end,
        requiresPhysicsPrediction=function()return true end,
        predictLocal=function(dt,x,y,boost)P.step(lp,durable,71,dt,x,y,boost,world,cs);C.syncPlayer(lp,lp._predictedCommute.part)end,
        restorePhysicsPrediction=function(snapshot)
            local okay=P.restore(lp,durable,71,snapshot)
            if okay then C.syncPlayer(lp,lp._predictedCommute.part)end
            return okay
        end}
    local reference=player(2);reference.homeResidentId='guest-1'
    local maxError,maxCorrection,maxHistory,maxQueue,firstMove=0,0,0,0,nil
    for frame=1,900 do
        now=frame/60
        cc.inputX=mode=='ped' and (frame<=140 and 1 or frame<=210 and -1 or 0)
            or (frame>90 and frame<=140 and .3 or 0)
        if weak and mode~='ped' and frame>90 and frame<=140 then cc.inputX=math.sin(frame*.09)*.3 end
        cc.inputY=mode=='ped' and (frame>210 and frame<=260 and 1 or 0)
            or (frame<=180 and -1 or frame<=300 and 1 or 0)
        if outage and now>1.8+outage-.5 then cc.inputX,cc.inputY=0,0 end
        P.step(reference,expected,71,1/60,cc.inputX,cc.inputY,false,world,cs)
        local referenceBody=Rider.actor(reference._predictedCommute.rider)
        frameSteps=0;client:update(1/60,cc)
        if weak~='stalled' then host:update(1/60,hc)
        elseif frame%12==0 then host:update(.2,hc)end
        if not firstMove and math.abs(lp.x-100)>.00001 then firstMove=frame end
        maxError=math.max(maxError,math.sqrt((lp.x-referenceBody.x)^2+(lp.y-referenceBody.z)^2))
        maxCorrection=math.max(maxCorrection,client.lastPredictionCorrection or 0)
        maxHistory=math.max(maxHistory,#client.commandPrediction.history)
        maxQueue=math.max(maxQueue,#(hp._commandQueue or {}))
        maxSteps=math.max(maxSteps,frameSteps)
        for _,session in ipairs({host,client}) do
            for _,event in ipairs(session:drainEvents())do assert(event.type~='error',event.message)end
        end
    end
    local label='prediction_'..mode..(outage and ('_outage_'..outage..'s') or weak=='slow' and '_slow_burst_loss'
        or weak=='stalled' and '_slow_host_burst_loss' or weak and '_burst_loss' or '')
    check(label..'_responds_before_network_reply',firstMove and firstMove<9)
    if not outage then
    check(label..'_reconciles_physics_through_latency_loss_reordering',maxError<.05
        and checkpoints>(weak=='stalled' and 50 or 100) and client.lastPhysicsPredictionTick~=nil,'max error='..maxError..' packets='..checkpoints)
    check(label..'_has_no_burst_recovery_correction_spike',maxCorrection<.01,'max correction='..maxCorrection)
    else
        check(label..'_prediction_and_host_queues_remain_bounded',maxHistory<=240 and maxQueue<=120,
            'history='..maxHistory..' queue='..maxQueue..' max correction='..maxCorrection)
    end
    check(label..'_converges_after_braking_and_reverse',math.abs(lp.x-hp.x)<.05
        and math.abs(lp.y-hp.y)<.05,'guest='..lp.x..','..lp.y..' host='..hp.x..','..hp.y)
    check(label..'_host_work_and_history_stay_bounded',maxSteps<=(weak=='stalled' and 15 or 4)
        and maxQueue<=240 and maxHistory<=240,'steps='..maxSteps..' queue='..maxQueue..' history='..maxHistory)
    check(label..'_physics_packets_fit_motion_budget',maxBytes<=Protocol.MAX_PACKET_BYTES,'max bytes='..maxBytes)
    check(label..'_replay_keeps_durable_rider_unchanged',Rider.actor(durable.rider).x==100
        and cs.money==state.money and cs.home.revision==0)
    if mode=='bike' and not outage then
        check(label..'_replay_does_not_multiply_fuel_or_tire_wear',
            math.abs(lp._predictedCommute.rider.bike.service.fuel-reference._predictedCommute.rider.bike.service.fuel)<.0001
            and math.abs(lp._predictedCommute.rider.bike.service.tread-reference._predictedCommute.rider.bike.service.tread)<.0001)
    end
    local body=Rider.actor(part.rider)
    body.speed=3;body.vx=3;body.vz=0
    if mode=='bike' then body._velocitySpeed=3 end
    local previousX=body.x;local ack=hp.inputSequence
    hp._commandQueue={};hp._commandBudget=0;hp.lastInputAt=now-1
    host:_stepRemoteCommands(hp,1/60,hc)
    check(label..'_outage_keeps_physics_running_without_forged_ack',body.x~=previousX and hp.inputSequence==ack)
    local history={}
    for i=1,120 do history[i]={x=1,y=-1,boost=false} end
    host:_queueMovementCommands(hp,{sequence=ack+120,commandKey=P.key(part,71),
        commands=require('src.net.movement_commands').pack(history)},hc)
    check(label..'_long_outage_discards_stale_controls_before_resuming',#hp._commandQueue==3
        and hp.inputSequence==ack+117 and hp._commandBudget<=3/60)
    client:sendNeutralInput()
    check(label..'_neutral_input_clears_private_physics',not lp._movementPredicted and lp._predictedCommute==nil)
end
local function indoor(check,weak)
    local now=0
    local host=Session.new({clock=function()return now end})
    local client=Session.new({clock=function()return now end})
    host.mode='host';host.ready=true;host.localId=1;host.sessionId='prediction-test'
    client.mode='client';client.ready=true;client.localId=2;client.sessionId=host.sessionId
    host:_installRoster({player(1),player(2)},0);client:_installRoster({player(1),player(2)},0)
    host.idToPeer[2]='peer';host.peerToId.peer=2
    local localPlayer=player(2);local expected=player(2)
    local outbound,inbound={},{}
    local count,snapshotCount,maxInput,steadyInput=0,0,0,0
    local dropped,reordered=0,0
    local function deliver(queue)
        local events={};local i=1
        while i<=#queue and #events<64 do
            local item=queue[i]
            if item.at<=now then table.remove(queue,i);events[#events+1]=item.event else i=i+1 end
        end
        return events
    end
    host.transport={
        service=function()return deliver(outbound) end,
        send=function(_,peer,data,channel)
            local envelope=assert(Protocol.decode(data))
            snapshotCount=snapshotCount+1
            local delay=(weak and .4 or .15)+(snapshotCount%3)*(weak and .04 or .013)
            if envelope.type=='snapshot' and snapshotCount%13==0 then dropped=dropped+1;return true end
            inbound[#inbound+1]={at=now+delay,event={type='receive',data=data,channel=channel,peer=peer}}
            return true
        end,
    }
    client.transport={
        service=function()return deliver(inbound) end,
        sendToServer=function(_,data,channel)
            local envelope=assert(Protocol.decode(data))
            if envelope.type~='input' then return true end
            count=count+1;maxInput=math.max(maxInput,#data)
            if now>6.5 then steadyInput=math.max(steadyInput,#data)end
            if weak and now>1.8 and now<2.45 then dropped=dropped+1;return true end
            if count%9==0 then dropped=dropped+1;return true end
            local delay=(weak and .4 or .15)+(count%4)*.009
            if count%7==0 then delay=delay+.09;reordered=reordered+1 end
            outbound[#outbound+1]={at=now+delay,event={type='receive',data=data,channel=channel,peer='peer'}}
            if count%11==0 then outbound[#outbound+1]={at=now+delay+.01,event={type='receive',data=data,channel=channel,peer='peer'}} end
            return true
        end,
    }
    local function key(p)return (p.sceneId or 'warehouse')..'_walk' end
    local frameSteps,maxSteps,maxQueue=0,0,0
    local hc={localPlayer=host.players[1],predictionKey=key,moveRemote=function(...)
        frameSteps=frameSteps+1;move(...)
    end}
    local cc={localPlayer=localPlayer,predictionKey=key,predictLocal=function(dt,x,y)move(localPlayer,dt,x,y)end,inputX=1,inputY=0}
    local maxError,maxCorrection=0,0;local firstMove
    for frame=1,480 do
        now=frame/60
        cc.inputX=frame<=100 and 1 or frame<=170 and -1 or 0
        cc.inputY=frame>170 and frame<=250 and 1 or 0
        move(expected,1/60,cc.inputX,cc.inputY)
        frameSteps=0
        client:update(1/60,cc);host:update(1/60,hc)
        maxSteps=math.max(maxSteps,frameSteps)
        maxQueue=math.max(maxQueue,#(host.players[2]._commandQueue or {}))
        if not firstMove and localPlayer.x>100 then firstMove=frame end
        maxError=math.max(maxError,math.sqrt((localPlayer.x-expected.x)^2+(localPlayer.y-expected.y)^2))
        maxCorrection=math.max(maxCorrection,client.lastPredictionCorrection or 0)
        for _,session in ipairs({host,client}) do
            for _,event in ipairs(session:drainEvents()) do assert(event.type~='error',event.message) end
        end
    end
    local label=weak and 'prediction_slow_burst_walk' or 'prediction_walk'
    check(label..'_starts_before_any_network_reply',firstMove==1)
    check(label..'_replays_exactly_through_latency_loss_and_reordering',maxError<.01
        and dropped>0 and reordered>0,'max positional error='..maxError)
    check(label..'_host_guest_converge_after_turns_stops_and_walls',math.abs(localPlayer.x-host.players[2].x)<.01
        and math.abs(localPlayer.y-host.players[2].y)<.01 and host.players[2].inputSequence>400,
        'guest='..localPlayer.x..','..localPlayer.y..' host='..host.players[2].x..','..host.players[2].y..' ack='..host.players[2].inputSequence)
    check(label..'_redundant_commands_fit_realtime_packet_budget',maxInput<=Protocol.MAX_PACKET_BYTES
        and count>100,'max input bytes='..maxInput)
    check(label..'_recovery_has_bounded_catchup_without_correction_spikes',maxSteps<=4 and maxQueue<=120
        and maxCorrection<.01,'steps='..maxSteps..' queue='..maxQueue..' correction='..maxCorrection)
    check(label..'_steady_packets_shrink_after_recovery',steadyInput<500,
        'largest steady input bytes='..steadyInput)
    local x=host.players[2].x
    local oldAck=host.players[2].inputSequence
    host:_queueMovementCommands(host.players[2],{sequence=oldAck+1000,commandKey='warehouse_walk',
        commands={{1000,0,0},{1000,0,0}}},hc)
    host.players[2]._commandBudget=0
    host:_stepRemoteCommands(host.players[2],0,hc)
    check(label..'_host_does_not_accept_client_time_acceleration',host.players[2].x==x
        and host.players[2].inputSequence==oldAck)
    host.players[2].sceneId='home'
    host:_stepRemoteCommands(host.players[2],.1,hc)
    check(label..'_old_room_commands_are_discarded_after_transition',#host.players[2]._commandQueue==0
        and host.players[2].x==x)
end
function Test.run(check)
    require('src.tests.host_command_clock_test').run(check)
    indoor(check)
    indoor(check,true)
    for _,mode in ipairs({'ped','bike','box','kei'})do outdoor(check,mode)end
    for _,mode in ipairs({'ped','bike','box','kei'})do outdoor(check,mode,true)end
    for _,mode in ipairs({'ped','bike','box','kei'})do outdoor(check,mode,'slow')end
    for _,mode in ipairs({'ped','bike','box','kei'})do outdoor(check,mode,'stalled')end
    for _,mode in ipairs({'ped','bike','box','kei'})do
        outdoor(check,mode,'outage2');outdoor(check,mode,'outage5')
    end
    local Commands=require('src.net.movement_commands')
    local history={}
    for i=1,Commands.MAX_FRAMES do history[i]={x=(i%2001-1000)/1000,y=(1000-i%2001)/1000,boost=i%2==0}end
    local packed=Commands.pack(history)
    local decoded=assert(Commands.unpack(packed))
    check('prediction_packed_input_preserves_continuous_analog_history',#packed==360 and #decoded==120
        and decoded[120][1]==-880 and decoded[120][2]==880 and decoded[120][3]==1)
    check('prediction_packed_input_rejects_bad_axis_reserved_bits_and_unbounded_history',
        not Commands.count(packed..'x') and not Commands.count(packed..packed)
        and not Commands.count(string.char(255,255,255)) and not Commands.count(string.char(255,7,0)))
    local payload={sessionId='version-check',sequence=120,moveX=0,moveY=0,
        commandKey='warehouse_walk',commands=packed}
    local envelope=assert(Protocol.make('input',payload))
    envelope.version=80
    check('prediction_protocol_80_clients_are_rejected_before_packed_input',
        Protocol.VERSION==82 and Protocol.decode(assert(require('src.net.codec').encode(envelope)))==nil)
    payload.sequence=119
    check('prediction_packed_input_cannot_claim_negative_history_sequences',Protocol.encode('input',payload)==nil)
    require('src.tests.remote_motion_test').run(check)
    require('src.tests.prediction_checkpoint_test').run(check)
    require('src.tests.prediction_wire_test').run(check)
end
return Test
