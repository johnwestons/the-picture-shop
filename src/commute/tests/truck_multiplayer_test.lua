local C=require('src.commute.runtime')
local Motion=require('src.commute.truck_motion')
local Truck=require('src.commute.delivery_truck')
local Rider=require('src.commute.rider')
local Session=require('src.net.session')
local Protocol=require('src.net.protocol')
local Codec=require('src.net.codec')
local Harness=require('src.tests.support.network_impairment_harness')
local Test={}
local function part(model)
    local rider=Rider.new(100,100,0,{version=1,outfit='geared',mounted=false,engine=false,revision=0})
    rider.vehicle='truck';rider.truck=Truck.new(100,100,0,'picture_shop',model)
    return {rider=rider,arrived=false}
end
local function player(id)
    return {id=id,name='Truck Worker '..id,character='rabbit-worker',sceneId='commute',
        x=100,y=100,velocityX=0,velocityY=0,intentX=1,intentY=0,moving=false,facing=1,
        animationDistance=0,inputSequence=0}
end
local function angle(a,b)return math.abs(math.atan2(math.sin(a-b),math.cos(a-b)))end

local function protocolChecks(check)
    local p=player(4)
    p.name=string.rep('W',24);p.character=string.rep('c',48)
    for _,key in ipairs({'x','y','velocityX','velocityY','animationDistance'}) do p[key]=123.12345678901234 end
    p.intentX,p.intentY=.70710678118654757,-.70710678118654757
    p.inputSequence=4294967295
    local source=part('kei');local t=source.rider.truck
    t.heading,t.speed,t.steering,t.brake,t.throttle,t.h,t.pitch=6.123456789012345,14.12345678901234,
        -.7123456789012345,.8123456789012345,.9123456789012345,92.12345678901234,-1.123456789012345
    t.reverse=true
    local motion=Motion.snapshot(source,999999999999)
    local payload={sessionId=string.rep('s',64),serverTick=4294967295,players=Codec.array({p}),truck=motion}
    local bytes,err=Protocol.encode('snapshot',payload)
    local decoded=bytes and Protocol.decode(bytes)
    check('truck_motion_full_precision_packet_fits_mtu',decoded and #bytes<=1200,err or bytes and #bytes)
    check('truck_motion_roundtrip_retains_model_reverse_and_road_pose',decoded and decoded.payload.truck.model=='kei'
        and decoded.payload.truck.reverse and decoded.payload.truck.h==t.h and decoded.payload.truck.pitch==t.pitch)
    for _,bad in ipairs({{'model','bike'},{'reverse',1},{'heading',7},{'speed',-1},{'steer',2},
        {'brake',2},{'throttle',-1},{'h',101},{'pitch',2},{'token',0}}) do
        local old=motion[bad[1]];motion[bad[1]]=bad[2]
        check('truck_motion_rejects_invalid_'..bad[1],not Protocol.encode('snapshot',payload))
        motion[bad[1]]=old
    end
    payload.bike={token=1,heading=0,speed=0,steer=0,brake=0}
    check('truck_motion_rejects_two_vehicles_for_one_driver',not Protocol.encode('snapshot',payload))
    payload.bike=nil;p.sceneId='warehouse'
    check('truck_motion_rejects_indoor_vehicle',not Protocol.encode('snapshot',payload))
    source.interior='grocery'
    check('truck_motion_omits_indoor_driver',Motion.snapshot(source,1)==nil)
    source.interior=nil;source.arrived=true
    check('truck_motion_omits_arrived_driver',Motion.snapshot(source,1)==nil)
end

local function sessionChecks(context,check,hz)
    local now=0;local token=73
    local network=Harness.new({maxClients=3,classify=function(bytes)
        local value=Protocol.decode(bytes);return value and value.type or 'invalid'
    end})
    local parts={part('box'),part('kei'),part('box'),part('kei')}
    parts[4].rider.vehicle=nil;parts[4].rider.gear.mounted=true
    local hp=player(1)
    local host=Session.new({transportFactory=network.factory,clock=function()return now end})
    local state=context.State.new()
    local hc={localPlayer=hp,moveRemote=function()end,
        getShopSnapshot=function()return {state=assert(require('src.save_schema').snapshot(state)),player=hp}end,
        getTruckMotion=function(id)return Motion.snapshot(parts[id],token)end,
        getBikeMotion=function(id)
            if id==4 then local b=parts[4].rider.bike
                return {token=token,heading=b.heading,speed=b.speed,steer=0,brake=0} end
        end}
    assert(host:startHost({name='Truck Host',character='rabbit-worker',addressOptions={socket={dns={
        gethostname=function()return 'truck-host'end,getaddrinfo=function()return {{addr='192.168.1.93'}}end}}}}))
    host.sessionId='truck-motion-test'
    local clients,locals,contexts={},{},{}
    local function pump(dt)
        now=now+dt;network:advanceSteps(1)
        for id,p in pairs(host.players) do C.syncPlayer(id==1 and hp or p,parts[id]) end
        host:update(dt,hc)
        for i,g in ipairs(clients) do
            g:update(dt,contexts[i])
            for _,event in ipairs(g:drainEvents()) do
                assert(event.type~='error',event.message)
                if event.type=='ready' then for key,value in pairs(event.spawn) do locals[i][key]=value end end
            end
        end
        for _,event in ipairs(host:drainEvents()) do assert(event.type~='error',event.message) end
    end
    for i=1,3 do
        local g=Session.new({transportFactory=network.factory,clock=function()return now end})
        clients[i]=g;locals[i]=player(i+1);contexts[i]={localPlayer=locals[i],inputX=0,inputY=0}
        assert(g:startClient('192.168.1.93:22122',{name='Truck Guest '..i,character='rabbit-worker',
            residentToken=string.rep(tostring(i),64)}))
        for _=1,30 do pump(1/hz) end
        assert(g.ready,'Truck guest failed to join')
    end
    -- Retain an old durable snapshot throughout the drive. Realtime motion
    -- must update both the local cab and other players' visible truck bodies.
    local stale={part('box'),part('kei'),part('box'),part('kei')}
    local transmit=network._transmit
    local count=0
    function network:_transmit(direction,link,bytes,channel,reliable)
        if direction=='host_to_client' and not reliable then
            local packet=Protocol.decode(bytes)
            if packet and packet.type=='snapshot' then
                count=count+1
                if count%17==0 then self:dropNext(direction,link.index)
                elseif count%13==0 then self:delayNext(direction,link.index,math.ceil(hz*.1)) end
            end
        end
        return transmit(self,direction,link,bytes,channel,reliable)
    end
    local last,changed,maxStep={},0,0
    local aligned,positions,backward=true,true,true
    for frame=1,hz*4 do
        local time=frame/hz
        for id,p in ipairs(parts) do
            local actor=id==4 and p.rider.bike or p.rider.truck
            actor.x,actor.z=100+time*8,100+id*2
            actor.heading=(6.1+time*.4)%(math.pi*2)
            actor.h,actor.pitch=2+time*.5,time*.03
            actor.speed,actor.steering,actor.throttle=8,.4,.7
        end
        pump(1/hz)
        if frame>hz then
            for _,sample in ipairs({{clients[1],locals[1],2},{clients[1],clients[1].players[1],1},
                {clients[2],clients[2].players[2],2}}) do
                local g,p,id=unpack(sample)
                local visual=C.visualRider(stale[id],p,token).truck
                aligned=aligned and angle(visual.heading,parts[id].rider.truck.heading)<.22
                    and math.abs(visual.h-parts[id].rider.truck.h)<.3
                positions=positions and visual.x==p.x and visual.z==p.y
                local key=tostring(g)..':'..id
                if last[key] then
                    local delta=visual.h-last[key]
                    if delta>1e-7 then changed=changed+1 end
                    backward=backward and delta>=-1e-7
                    maxStep=math.max(maxStep,math.abs(delta))
                end
                last[key]=visual.h
            end
        end
    end
    local suffix='_'..hz..'fps'
    check('truck_motion_live_local_and_remote_views_track_host'..suffix,aligned)
    check('truck_motion_preserves_shared_position_smoothing'..suffix,positions)
    check('truck_motion_height_advances_between_packets_without_rewind'..suffix,
        backward and changed>(hz*3-1)*3*.95 and maxStep<.12,
        ('movingFrames=%d maxHeightStep=%.5f'):format(changed,maxStep))
    check('truck_motion_does_not_mutate_durable_actors'..suffix,stale[1].rider.truck.x==100
        and stale[1].rider.truck.heading==0 and stale[2].rider.truck.h==0)
    local truckPackets,dropped,delayed,bounded=0,0,0,true
    for _,entry in ipairs(network.log) do
        if entry.kind=='snapshot' then
            truckPackets=truckPackets+1;bounded=bounded and entry.bytes<=1200 and not entry.reliable
            if entry.outcome=='dropped' then dropped=dropped+1 end
            if (entry.delay or 0)>0 then delayed=delayed+1 end
        end
    end
    check('truck_motion_uses_bounded_unreliable_updates_with_loss_and_reordering'..suffix,
        bounded and truckPackets>300 and dropped>0 and delayed>0)
    check('truck_motion_keeps_motorcycle_fast_path'..suffix,clients[1].players[4]._rideMotion~=nil
        and clients[1].players[4]._truckMotion==nil)
    -- Stop/reverse and lifecycle changes must not retain an old vehicle pose.
    network._transmit=transmit
    for id=1,3 do local t=parts[id].rider.truck;t.speed=0;t.reverse=true;t.brake=1 end
    for _=1,hz do pump(1/hz) end
    local own=clients[1].players[2]
    local stopped=C.visualRider(stale[2],locals[1],token).truck
    check('truck_motion_stopped_reverse_is_authoritative'..suffix,stopped.reverse and stopped.speed<.001 and stopped.brake>.99)
    local reverseStart=locals[1].x
    for _=1,hz do
        local t=parts[2].rider.truck
        t.x=t.x-3/hz;t.heading=0;t.speed=3;t.brake=0
        pump(1/hz)
    end
    local reversing=C.visualRider(stale[2],locals[1],token).truck
    check('truck_motion_reverse_travel_keeps_physical_facing'..suffix,reversing.reverse
        and reversing.x<reverseStart-2 and angle(reversing.heading,0)<.001 and math.abs(reversing.speed-3)<.001)
    local unchanged=C.visualRider(stale[2],locals[1],token+1).truck
    check('truck_motion_ignores_other_trip'..suffix,unchanged.h==0)
    parts[2].rider.truck.model='box'
    for _=1,math.ceil(hz*.2) do pump(1/hz) end
    check('truck_motion_switches_model_without_blending'..suffix,own._visualTruckMotion.model=='box'
        and C.visualRider(stale[2],locals[1],token).truck.h==0)
    parts[2].rider.vehicle=nil
    for _=1,math.ceil(hz*.2) do pump(1/hz) end
    check('truck_motion_exit_clears_transient_pose'..suffix,own._truckMotion==nil and own._visualTruckMotion==nil
        and locals[1]._visualTruckMotion==nil)
    -- No incoming packets: hold bounded position lead and discard stale motion.
    for _=1,math.ceil(hz*.4) do clients[1]:_updateClientVisuals(1/hz,contexts[1]) end
    check('truck_motion_timeout_clears_remote_pose'..suffix,clients[1].players[1]._visualTruckMotion==nil)
    for _,g in ipairs(clients) do g:stop('test complete') end
    host:stop('test complete');network:dispose()
end

function Test.run(context,check)
    protocolChecks(check)
    local p={_targetRecord={sceneId='commute'},_truckMotion=Motion.snapshot(part('box'),1)}
    p._truckMotion.heading=math.pi*2-.01;Motion.update(p,0)
    p._truckMotion.heading=.01;Motion.update(p,1/60)
    check('truck_motion_turns_across_heading_wrap_by_shortest_arc',
        p._visualTruckMotion.heading>math.pi*2-.01 and p._visualTruckMotion.heading<math.pi*2+.01)
    p._truckMotion.token=2;p._truckMotion.h=10;Motion.update(p,0)
    check('truck_motion_new_trip_resets_smoothing',p._visualTruckMotion.h==10 and p._visualTruckMotion.token==2)
    p._targetRecord.sceneId='warehouse';Motion.update(p,1/60)
    check('truck_motion_scene_change_clears_smoothing',p._visualTruckMotion==nil)
    for _,hz in ipairs({30,60}) do sessionChecks(context,check,hz) end
end
return Test
