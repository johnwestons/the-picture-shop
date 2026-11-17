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
local function outdoor(check,mode)
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
        if packets%11~=0 then downstream[#downstream+1]={at=now+.15+(packets%5)*.011,
            event={type='receive',data=data,channel=channel,peer=peer}} end
        return true
    end}
    client.transport={service=function()return deliver(downstream)end,sendToServer=function(_,data,channel)
        local envelope=assert(Protocol.decode(data));if envelope.type~='input' then return true end
        count=count+1;maxBytes=math.max(maxBytes,#data)
        if count%9~=0 then upstream[#upstream+1]={at=now+.15+(count%7==0 and .09 or 0),
            event={type='receive',data=data,channel=channel,peer='peer'}} end
        return true
    end}
    local hc={localPlayer=host.players[1],predictionKey=function()return P.key(part,71)end,
        requiresPhysicsPrediction=function()return true end,
        getPredictionSnapshot=function()return P.capture(part,71)end,
        moveRemote=function(p,dt,x,y,boost)Trip.update(state,p,P.controls(part.rider,x,y,boost),dt,world);C.syncPlayer(p,part)end}
    local cc={localPlayer=lp,predictionKey=function()return P.key(durable,71)end,
        requiresPhysicsPrediction=function()return true end,
        predictLocal=function(dt,x,y,boost)P.step(lp,durable,71,dt,x,y,boost,world,cs);C.syncPlayer(lp,lp._predictedCommute.part)end,
        restorePhysicsPrediction=function(snapshot)
            local okay=P.restore(lp,durable,71,snapshot)
            if okay then C.syncPlayer(lp,lp._predictedCommute.part)end
            return okay
        end}
    local reference=player(2);reference.homeResidentId='guest-1'
    local maxError,firstMove=0,nil
    for frame=1,900 do
        now=frame/60
        cc.inputX=mode=='ped' and (frame<=140 and 1 or frame<=210 and -1 or 0)
            or (frame>90 and frame<=140 and .3 or 0)
        cc.inputY=mode=='ped' and (frame>210 and frame<=260 and 1 or 0)
            or (frame<=180 and -1 or frame<=300 and 1 or 0)
        P.step(reference,expected,71,1/60,cc.inputX,cc.inputY,false,world,cs)
        local referenceBody=Rider.actor(reference._predictedCommute.rider)
        client:update(1/60,cc);host:update(1/60,hc)
        if not firstMove and math.abs(lp.x-100)>.00001 then firstMove=frame end
        maxError=math.max(maxError,math.sqrt((lp.x-referenceBody.x)^2+(lp.y-referenceBody.z)^2))
        for _,session in ipairs({host,client}) do
            for _,event in ipairs(session:drainEvents())do assert(event.type~='error',event.message)end
        end
    end
    check('prediction_'..mode..'_responds_before_network_reply',firstMove and firstMove<9)
    check('prediction_'..mode..'_reconciles_physics_through_latency_loss_reordering',maxError<.05
        and checkpoints>100 and client.lastPhysicsPredictionTick~=nil,'max error='..maxError..' packets='..checkpoints)
    check('prediction_'..mode..'_converges_after_braking_and_reverse',math.abs(lp.x-hp.x)<.05
        and math.abs(lp.y-hp.y)<.05,'guest='..lp.x..','..lp.y..' host='..hp.x..','..hp.y)
    check('prediction_'..mode..'_physics_packets_fit_motion_budget',maxBytes<=Protocol.MAX_PACKET_BYTES,'max bytes='..maxBytes)
    check('prediction_'..mode..'_replay_keeps_durable_rider_unchanged',Rider.actor(durable.rider).x==100
        and cs.money==state.money and cs.home.revision==0)
    if mode=='bike' then
        check('prediction_bike_replay_does_not_multiply_fuel_or_tire_wear',
            math.abs(lp._predictedCommute.rider.bike.service.fuel-reference._predictedCommute.rider.bike.service.fuel)<.0001
            and math.abs(lp._predictedCommute.rider.bike.service.tread-reference._predictedCommute.rider.bike.service.tread)<.0001)
    end
    local body=Rider.actor(part.rider)
    body.speed=3;body.vx=3;body.vz=0
    if mode=='bike' then body._velocitySpeed=3 end
    local previousX=body.x;local ack=hp.inputSequence
    hp._commandQueue={};hp._commandBudget=0;hp.lastInputAt=now-1
    host:_stepRemoteCommands(hp,1/60,hc)
    check('prediction_'..mode..'_outage_keeps_physics_running_without_forged_ack',body.x~=previousX and hp.inputSequence==ack)
    client:sendNeutralInput()
    check('prediction_'..mode..'_neutral_input_clears_private_physics',not lp._movementPredicted and lp._predictedCommute==nil)
end
function Test.run(check)
    local now=0
    local host=Session.new({clock=function()return now end})
    local client=Session.new({clock=function()return now end})
    host.mode='host';host.ready=true;host.localId=1;host.sessionId='prediction-test'
    client.mode='client';client.ready=true;client.localId=2;client.sessionId=host.sessionId
    host:_installRoster({player(1),player(2)},0);client:_installRoster({player(1),player(2)},0)
    host.idToPeer[2]='peer';host.peerToId.peer=2
    local localPlayer=player(2);local expected=player(2)
    local outbound,inbound={},{}
    local count,snapshotCount,maxInput=0,0,0
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
            local delay=.15+(snapshotCount%3)*.013
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
            if count%9==0 then dropped=dropped+1;return true end
            local delay=.15+(count%4)*.009
            if count%7==0 then delay=delay+.09;reordered=reordered+1 end
            outbound[#outbound+1]={at=now+delay,event={type='receive',data=data,channel=channel,peer='peer'}}
            if count%11==0 then outbound[#outbound+1]={at=now+delay+.01,event={type='receive',data=data,channel=channel,peer='peer'}} end
            return true
        end,
    }
    local function key(p)return (p.sceneId or 'warehouse')..'_walk' end
    local hc={localPlayer=host.players[1],predictionKey=key,moveRemote=move}
    local cc={localPlayer=localPlayer,predictionKey=key,predictLocal=function(dt,x,y)move(localPlayer,dt,x,y)end,inputX=1,inputY=0}
    local maxError=0;local firstMove
    for frame=1,480 do
        now=frame/60
        cc.inputX=frame<=100 and 1 or frame<=170 and -1 or 0
        cc.inputY=frame>170 and frame<=250 and 1 or 0
        move(expected,1/60,cc.inputX,cc.inputY)
        client:update(1/60,cc);host:update(1/60,hc)
        if not firstMove and localPlayer.x>100 then firstMove=frame end
        maxError=math.max(maxError,math.sqrt((localPlayer.x-expected.x)^2+(localPlayer.y-expected.y)^2))
        for _,session in ipairs({host,client}) do
            for _,event in ipairs(session:drainEvents()) do assert(event.type~='error',event.message) end
        end
    end
    check('prediction_walk_starts_before_any_network_reply',firstMove==1)
    check('prediction_walk_replays_exactly_through_latency_loss_and_reordering',maxError<.01
        and dropped>0 and reordered>0,'max positional error='..maxError)
    check('prediction_host_guest_converge_after_turns_stops_and_walls',math.abs(localPlayer.x-host.players[2].x)<.01
        and math.abs(localPlayer.y-host.players[2].y)<.01 and host.players[2].inputSequence>400,
        'guest='..localPlayer.x..','..localPlayer.y..' host='..host.players[2].x..','..host.players[2].y..' ack='..host.players[2].inputSequence)
    check('prediction_redundant_commands_fit_realtime_packet_budget',maxInput<=Protocol.MAX_PACKET_BYTES
        and count>100,'max input bytes='..maxInput)
    local x=host.players[2].x
    local oldAck=host.players[2].inputSequence
    host:_queueMovementCommands(host.players[2],{sequence=oldAck+1000,commandKey='warehouse_walk',
        commands={{1000,0,0},{1000,0,0}}},hc)
    host.players[2]._commandBudget=0
    host:_stepRemoteCommands(host.players[2],0,hc)
    check('prediction_host_does_not_accept_client_time_acceleration',host.players[2].x==x
        and host.players[2].inputSequence==oldAck)
    host.players[2].sceneId='home'
    host:_stepRemoteCommands(host.players[2],.1,hc)
    check('prediction_old_room_commands_are_discarded_after_transition',#host.players[2]._commandQueue==0
        and host.players[2].x==x)
    for _,mode in ipairs({'ped','bike','box','kei'})do outdoor(check,mode)end
end
return Test
