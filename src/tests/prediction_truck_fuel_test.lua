local Test={}
function Test.run(check)
    local P=require('src.commute.prediction')
    local Session=require('src.net.session')
    local Rider=require('src.commute.rider')
    local Truck=require('src.commute.delivery_truck')
    local Service=require('src.commute.truck_service')
    local Trip=require('src.commute.trip')
    local C=require('src.commute.runtime')
    local Copy=require('src.net.shop_replication').copy
    local state=require('src.state').new()
    state.home.residents['guest-1']=Copy(state.home.residents.owner)
    local function part(model,slot,id,z)
        local p={slot=slot,arrived=false,rider=Rider.new(100,z,0,
            {version=1,outfit='normal',mounted=false,engine=false,revision=0})}
        p.rider.vehicle='truck';p.rider.truck=Truck.new(100,z,0,nil,model)
        Service.apply(p.rider.truck);p.rider.truck.driver=id
        return p
    end
    local kei,box=part('kei',2,'guest-1',100),part('box',1,'owner',120)
    local token=57
    state.home.commute={version=1,token=token,origin='warehouse',destination='garden',independent=true,
        participants={['guest-1']=kei,owner=box},keiTruck=kei.rider.truck,truck=box.rider.truck}
    local world={height=function()return 0 end,supportHeight=function()return 0 end,
        roads={nearest=function()return 0,{width=8}end,sample=function()return 0,{width=8}end,
            blocked=function()return false end}}
    local guest={id=2,homeResidentId='guest-1',x=100,y=100}
    local owner={id=1,homeResidentId='owner',x=100,y=120}
    local player=Copy(guest);local durable=Copy(kei);local clientState=Copy(state)
    local now,restores,replays=0,0,0
    local client=Session.new({clock=function()return now end})
    client.mode='client';client.ready=true;client.localId=2
    local context={localPlayer=player,predictionKey=function()return P.key(durable,token)end,
        requiresPhysicsPrediction=function()return true end,
        predictLocal=function(dt,x,y,boost,replay)
            if replay then replays=replays+1 end
            P.step(player,durable,token,dt,x,y,boost,world,clientState)
            C.syncPlayer(player,player._predictedCommute.part)
        end,
        restorePhysicsPrediction=function(snapshot)
            restores=restores+1
            local okay=P.restore(player,durable,token,snapshot)
            if okay then C.syncPlayer(player,player._predictedCommute.part)end
            return okay
        end}
    local snapshots={};local sharedBurns=0
    for frame=1,420 do
        now=frame/60
        context.inputX=frame>150 and frame<250 and .15 or 0
        context.inputY=frame<320 and -.55 or 0
        Trip.update(state,guest,P.controls(kei.rider,context.inputX,context.inputY,false),1/60,world)
        local ownFuel=kei.rider.truck.fuel
        Trip.update(state,owner,P.controls(box.rider,0,-1,false),1/60,world)
        if kei.rider.truck.fuel<ownFuel then sharedBurns=sharedBurns+1 end
        snapshots[frame]=P.capture(kei,token)
        if frame>=20 and frame%5==0 then
            local snapshot=Copy(snapshots[frame-15]);snapshot.sequence=frame-15;snapshot.serverTick=frame/5
            client.physicsPredictionSnapshot=snapshot
        end
        client:_updateClientPrediction(1/60,context)
    end
    local final=Copy(snapshots[420]);final.sequence=420;final.serverTick=1000
    client.physicsPredictionSnapshot=final;client:_updateClientPrediction(0,context)
    check('prediction_shared_box_kei_fuel_avoids_unnecessary_restore_and_replay',
        sharedBurns>150 and restores==0 and replays==0,'shared burns='..sharedBurns..' restores='..restores..' replays='..replays
            ..' kei='..kei.rider.truck.distance..' box='..box.rider.truck.distance..' fuel='..box.rider.truck.fuel)
    local current=player._predictedCommute.rider.truck
    check('prediction_shared_truck_fuel_matches_authority_without_changing_durable_state',
        math.abs(current.fuel-kei.rider.truck.fuel)<=1.0001e-6
        and P.matches(P.captureLocal(player),final) and durable.rider.truck.fuel==60
        and clientState.employment.companyTruck.fuelLiters==60
        and #client.commandPrediction.history==0)

    local fuelIndex,engineIndex,serviceIndex,collisionIndex
    for i,key in ipairs(P.fields.kei)do
        if key=='fuel'then fuelIndex=i elseif key=='engine'then engineIndex=i
        elseif key=='service.oilMiles'then serviceIndex=i elseif key=='collisionContact'then collisionIndex=i end
    end
    local function fixture()
        local expected=Copy(final);expected.sequence=10;expected.values[fuelIndex]=20
        local authoritative=Copy(expected);authoritative.values[fuelIndex]=19.9
        local pending=Copy(expected);pending.values[fuelIndex]=19.99
        local live={_predictedCommute={key=expected.key,mode='kei',rider={truck={model='kei',engine=true,fuel=19.99}}}}
        return live,{{sequence=11,checkpoint=pending}},expected,authoritative
    end
    local live,history,expected,authoritative=fixture()
    check('prediction_shared_fuel_rebase_updates_current_pending_and_ack_atomically',
        P.reconcileSharedTruckFuel(live,history,expected,authoritative)
        and math.abs(live._predictedCommute.rider.truck.fuel-19.89)<1e-10
        and math.abs(history[1].checkpoint.values[fuelIndex]-19.89)<1e-10 and expected.values[fuelIndex]==19.9)
    local cases={
        empty=function(_,_,_,host)host.values[fuelIndex]=0 end,
        pending_empty_crossing=function(_,commands)commands[1].checkpoint.values[fuelIndex]=.05 end,
        live_empty_crossing=function(p)p._predictedCommute.rider.truck.fuel=.05 end,
        near_empty=function(_,_,base,host)base.values[fuelIndex]=.000003;host.values[fuelIndex]=.000001 end,
        refill=function(_,_,_,host)host.values[fuelIndex]=20.1 end,
        overflow=function(p)p._predictedCommute.rider.truck.fuel=61 end,
        engine_change=function(_,_,_,host)host.values[engineIndex]=0 end,
        pending_engine_change=function(_,commands)commands[1].checkpoint.values[engineIndex]=0 end,
        service_change=function(_,_,_,host)host.values[serviceIndex]=host.values[serviceIndex]+.01 end,
        collision_change=function(_,_,_,host)host.values[collisionIndex]=1-host.values[collisionIndex] end,
        position_change=function(_,_,_,host)host.values[1]=host.values[1]+.1 end,
        missing_checkpoint=function(_,commands)commands[1].checkpoint=nil end,
        incompatible_checkpoint=function(_,commands)commands[1].checkpoint.key='other' end,
        nonfinite=function(_,_,_,host)host.values[fuelIndex]=0/0 end,
    }
    for name,change in pairs(cases)do
        live,history,expected,authoritative=fixture();change(live,history,expected,authoritative)
        local before=live._predictedCommute.rider.truck.fuel
        local oldAck=expected.values[fuelIndex]
        local oldPending=history[1].checkpoint and history[1].checkpoint.values[fuelIndex]
        check('prediction_shared_fuel_'..name..'_requires_full_replay_without_partial_mutation',
            not P.reconcileSharedTruckFuel(live,history,expected,authoritative)
            and live._predictedCommute.rider.truck.fuel==before and expected.values[fuelIndex]==oldAck
            and (not history[1].checkpoint or history[1].checkpoint.values[fuelIndex]==oldPending))
    end
end
return Test
