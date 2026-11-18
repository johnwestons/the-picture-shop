local root=assert(os.getenv('ENET_PROBE_ROOT'),'Set ENET_PROBE_ROOT')..'/'
package.path=root..'?.lua;'..root..'?/init.lua;'..package.path
local flag=os.getenv('ENET_PROBE_FLAG')or'unreliable'
local port=tonumber(os.getenv('ENET_PROBE_PORT'))or 24940
local ticks=tonumber(os.getenv('ENET_PROBE_TICKS'))or 180
function love.load()
 local report=assert(io.open(assert(os.getenv('ENET_PROBE_REPORT')),'w'))
 local host,client
 local okay,err=xpcall(function()
  local enet=require('enet')
  local Protocol=require('src.net.protocol')
  local Codec=require('src.net.codec')
  local Session=require('src.net.session')
  local P=require('src.commute.prediction')
  host=assert(enet.host_create('127.0.0.1:'..port,1,3))
  client=assert(enet.host_create(nil,1,3))
  local outbound=assert(client:connect('127.0.0.1:'..(port+1),3))
  local peer
  local receiver=Session.new();receiver.mode='client';receiver.ready=true;receiver.localId=2;receiver.sessionId='jitter-probe'
  local received,completed,motion,lastPhysics,lastMotion={},0,0,0,0
  local completedGaps,maxGap,lastComplete={},0,nil
  local function pump()
   while true do local event=host:service(0);if not event then break end
    if event.type=='connect'then peer=event.peer end
   end
   while true do local event=client:service(0);if not event then break end
    if event.type=='receive'then
     local envelope=assert(Protocol.decode(event.data))
     received[envelope.type]=(received[envelope.type]or 0)+1
     receiver:_handleClientEnvelope(envelope)
     local snapshot=receiver.physicsPredictionSnapshot
     if snapshot and snapshot.serverTick>lastPhysics then
      lastPhysics=snapshot.serverTick;completed=completed+1
      local at=love.timer.getTime()
      if lastComplete then local gap=at-lastComplete;completedGaps[#completedGaps+1]=gap;maxGap=math.max(maxGap,gap)end
      lastComplete=at
     end
     if receiver.lastPlayerTicks[2]and receiver.lastPlayerTicks[2]>lastMotion then
      lastMotion=receiver.lastPlayerTicks[2];motion=motion+1
     end
     receiver:drainEvents()
    end
   end
  end
  local deadline=love.timer.getTime()+5
  while not peer and love.timer.getTime()<deadline do pump();love.timer.sleep(.001)end
  assert(peer,'ENet loopback connection did not complete')
  local sentBytes,sentCount=0,0
  local function send(kind,payload,channel,reliable)
   local bytes=assert(Protocol.encode(kind,payload))
   peer:send(bytes,channel or 1,reliable and'reliable'or flag)
   -- Keep independent families in distinct datagrams even as wire compression
   -- improves. Otherwise ENet can coalesce this small fixture into one packet
   -- and accidentally stop exercising reordering at the transport boundary.
   host:flush()
   sentBytes=sentBytes+#bytes;sentCount=sentCount+1
  end
  local started=love.timer.getTime()
  for tick=1,ticks do
   local due=started+(tick-1)/12
   while love.timer.getTime()<due do pump();love.timer.sleep(.001)end
   local player={id=2,name='Loopback Player',sceneId='commute',resting=false,
    x=123.456789,y=234.567891,velocityX=4.23456789,velocityY=2.34567891,
    intentX=.4123456789,intentY=.823456789,moving=true,facing=1,
    animationDistance=18734.456789,character='rabbit-worker',furColorway=1,overallsColorway=1,inputSequence=tick*5}
   send('snapshot',{sessionId=receiver.sessionId,serverTick=tick,players=Codec.array({player})})
   for part=1,math.ceil(#P.fields.bike/P.PART_VALUES)do
    local values={}
    for index=(part-1)*P.PART_VALUES+1,math.min(#P.fields.bike,part*P.PART_VALUES)do
     local field=P.fields.bike[index]
     values[#values+1]=P.booleans[field]and index%2 or field=='gear'and 1 or index*.1234567
    end
    send('prediction_snapshot',{sessionId=receiver.sessionId,serverTick=tick,playerId=2,
     sequence=tick*5,key='ride_1_bike_1',mode='bike',part=part,values=Codec.array(values)})
   end
   send('hockey_snapshot',{sessionId=receiver.sessionId,serverTick=tick,bayId='front_left',game=false})
   if tick%12==0 then
    send('radio_state',{sessionId=receiver.sessionId,revision=tick,trackIndex=1,active=false,paused=false,muted=false,positionMs=0},0,true)
    send('shop_state',{sessionId=receiver.sessionId,revision=tick,state={money=tick}},2,true)
   end
   host:flush();pump()
  end
  deadline=love.timer.getTime()+2
  while love.timer.getTime()<deadline do pump();love.timer.sleep(.001)end
  if flag=='unsequenced' then
   assert(motion==ticks and completed==ticks,'Jitter lost independent movement/physics updates')
   assert(received.radio_state==math.floor(ticks/12) and received.shop_state==math.floor(ticks/12),'Reliable messages were lost')
  end
  table.sort(completedGaps)
  report:write(('flag=%s ticks=%d sentPackets=%d sentBytes=%d motion=%d physicsComplete=%d physicsShards=%d maxPhysicsGapMs=%.1f p95PhysicsGapMs=%.1f reliableControl=%d reliableDurable=%d\n')
   :format(flag,ticks,sentCount,sentBytes,motion,completed,received.prediction_snapshot or 0,maxGap*1000,
    (completedGaps[math.ceil(#completedGaps*.95)]or 0)*1000,received.radio_state or 0,received.shop_state or 0))
 end,debug.traceback)
 if not okay then report:write('FAIL '..tostring(err)..'\n')end
 report:close()
 if client then client:destroy()end;if host then host:destroy()end
 love.event.quit(okay and 0 or 1)
end
