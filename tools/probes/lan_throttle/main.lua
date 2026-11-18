local root=assert(os.getenv('ENET_PROBE_ROOT'),'Set ENET_PROBE_ROOT')..'/'
package.path=root..'?.lua;'..root..'?/init.lua;'..package.path
function love.load()
 local report=assert(io.open(assert(os.getenv('ENET_PROBE_REPORT'),'Set ENET_PROBE_REPORT'),'w'))
 local cases={}
 local okay,reason=xpcall(function()
  local enet=require('enet');local socket=require('socket')
  local definitions={{name='default'},{name='interval500',config={500,2,2}},
   {name='recover8',config={500,8,2}},{name='noDecel',config={5000,2,0}}}
  for index,def in ipairs(definitions)do
   local port=(tonumber(os.getenv('ENET_PROBE_PORT'))or 23950)+(index-1)*2
   local c={name=def.name,config=def.config,port=port,up={},down={},random=712345,
    sentState=0,gotState=0,sentInput=0,gotInput=0,maxInputGap=0,sentControl=0,gotControl=0,gotAck=0,sentDurable=0,gotDurable=0,
    seenControl={},seenAck={},seenDurable={},controlSentAt={},maxControlDelay=0,maxQueue=0,udpUp=0,udpDown=0,maxGap=0,lastState=nil,lastWindow=0}
   cases[#cases+1]=c
   c.host=assert(enet.host_create('127.0.0.1:'..port,1,3))
   c.front=assert(socket.udp());assert(c.front:setsockname('127.0.0.1',port+1));c.front:settimeout(0)
   c.back=assert(socket.udp());assert(c.back:setsockname('127.0.0.1',0));c.back:settimeout(0)
   c.client=assert(enet.host_create(nil,1,3));c.outbound=assert(c.client:connect('127.0.0.1:'..(port+1),3))
  end
  local started=love.timer.getTime();local lastState,lastInput,lastReliable,lastReport=0,0,0,0
  local function enqueue(c,q,data,delay,jitter,now)
   c.random=c.random*48271%2147483647
   q[#q+1]={data=data,at=now+math.max(0,delay+(c.random/2147483647*2-1)*jitter)}
   c.maxQueue=math.max(c.maxQueue,#q);assert(#q<512,'loopback queue exceeded512')
  end
  local function pump(q,send,now,c,rate)
   table.sort(q,function(a,b)return a.at<b.at end)
   for _=1,128 do local p=q[1];if not p or p.at>now or rate and(c.nextDown or 0)>now then break end;table.remove(q,1);send(p.data);if rate then c.nextDown=math.max(c.nextDown or now,now)+#p.data/rate end end
  end
  while love.timer.getTime()-started<46 do
   local now=love.timer.getTime();local elapsed=now-started
   local delay,jitter=0,0
   if elapsed>=17 then delay,jitter=.1,.035 end
   -- First isolate the latency transition with no loss or cap. Then impose an
   -- 8KB/s cap for10 seconds and remove it to verify backoff and recovery.
   for _,c in ipairs(cases)do
    for _=1,128 do local data,address,port=c.front:receivefrom();if not data then break end;c.address,c.clientPort=address,port;c.udpUp=c.udpUp+#data;enqueue(c,c.up,data,delay,jitter,now)end
    for _=1,128 do local data=c.back:receive();if not data then break end;c.udpDown=c.udpDown+#data;enqueue(c,c.down,data,delay,jitter,now)end
    pump(c.up,function(data)assert(c.back:sendto(data,'127.0.0.1',c.port))end,now)
    pump(c.down,function(data)assert(c.front:sendto(data,c.address,c.clientPort))end,now,c,elapsed>=24 and elapsed<34 and 8000 or nil)
    for _=1,128 do local e=c.host:service(0);if not e then break end
     if e.type=='connect'then c.peer=e.peer;if c.config then c.peer:throttle_configure(unpack(c.config))end end
     if e.type=='receive'and e.data:sub(1,1)=='I'then c.gotInput=c.gotInput+1;if c.lastInput then c.maxInputGap=math.max(c.maxInputGap,now-c.lastInput)end;c.lastInput=now end
     if e.type=='receive'and e.data:sub(1,1)=='A'then local id=tonumber(e.data:sub(2));assert(c.controlSentAt[id]and not c.seenAck[id],'unknown/duplicate reliable reply');c.seenAck[id]=true;c.gotAck=c.gotAck+1 end
     assert(e.type~='disconnect','unexpected host disconnect '..c.name)
    end
    for _=1,128 do local e=c.client:service(0);if not e then break end
     if e.type=='receive'then
      local kind=e.data:sub(1,1)
      if kind=='S'then
       c.gotState=c.gotState+1
       if c.lastState then c.maxGap=math.max(c.maxGap,now-c.lastState)end;c.lastState=now
      elseif kind=='C'then local id=tonumber(e.data:sub(2));assert(c.controlSentAt[id]and not c.seenControl[id],'unknown/duplicate reliable control');c.seenControl[id]=true;c.maxControlDelay=math.max(c.maxControlDelay,now-c.controlSentAt[id]);c.gotControl=c.gotControl+1;c.outbound:send('A'..id,0,'reliable')
      elseif kind=='D'then local id=tonumber(e.data:match('^D(%d+):'));assert(id and id<=c.sentDurable and not c.seenDurable[id],'unknown/duplicate durable record');c.seenDurable[id]=true;c.gotDurable=c.gotDurable+1 end
     end
     assert(e.type~='disconnect','unexpected client disconnect '..c.name)
    end
    if c.peer and elapsed-lastState>=1/8 and elapsed<44 then
     for family=1,3 do c.sentState=c.sentState+1;c.peer:send('S'..c.sentState..':'..string.rep('s',390),1,'unsequenced');c.host:flush()end
    end
    if c.peer and elapsed-lastInput>=.05 and elapsed<44 then c.sentInput=c.sentInput+1;c.outbound:send('I'..c.sentInput..':'..string.rep('i',110),0,'unreliable')end
    if c.peer and elapsed-lastReliable>=.25 and elapsed<44 then
     c.sentControl=c.sentControl+1;c.controlSentAt[c.sentControl]=now;c.peer:send('C'..c.sentControl,0,'reliable')
     c.sentDurable=c.sentDurable+1;c.peer:send('D'..c.sentDurable..':'..string.rep('d',1790),2,'reliable')
    end
    c.host:flush();c.client:flush()
   end
   if elapsed-lastState>=1/8 then lastState=elapsed end
   if elapsed-lastInput>=.05 then lastInput=elapsed end
   if elapsed-lastReliable>=.25 then lastReliable=elapsed end
   if elapsed-lastReport>=1 then
    for _,c in ipairs(cases)do
     report:write(('t=%.2f case=%s sent=%d got=%d newly=%d rtt=%d lastRtt=%d gap=%.3f upQ=%d downQ=%d udpDown=%d\n'):format(elapsed,c.name,c.sentState,c.gotState,c.gotState-c.lastWindow,c.peer and c.peer:round_trip_time()or-1,c.peer and c.peer:last_round_trip_time()or-1,c.lastState and now-c.lastState or 0,#c.up,#c.down,c.udpDown))
     c.lastWindow=c.gotState
    end
    report:flush();lastReport=elapsed
   end
   love.timer.sleep(.001)
  end
  for _,c in ipairs(cases)do
   assert(c.peer and c.sentState>600,'native loopback socket never connected or fixture did not send enough state')
   report:write(('RESULT case=%s state=%d/%d controls=%d/%d acks=%d durable=%d/%d inputs=%d/%d maxInputGapMs=%.1f maxStateGapMs=%.1f maxControlDelayMs=%.1f maxQueue=%d udpDown=%d\n'):format(c.name,c.gotState,c.sentState,c.gotControl,c.sentControl,c.gotAck,c.gotDurable,c.sentDurable,c.gotInput,c.sentInput,c.maxInputGap*1000,c.maxGap*1000,c.maxControlDelay*1000,c.maxQueue,c.udpDown))
   assert(c.gotControl==c.sentControl and c.gotAck==c.sentControl and c.gotDurable==c.sentDurable,'reliable integrity '..c.name)
   assert(#c.up<=4 and #c.down<=4,'backlog did not recover '..c.name)
  end
 end,debug.traceback)
 for _,c in ipairs(cases)do for _,k in ipairs({'host','client'})do if c[k]then pcall(c[k].destroy,c[k])end end;for _,k in ipairs({'front','back'})do if c[k]then c[k]:close()end end end
 report:write(okay and'COMPLETE\n'or'FAIL '..tostring(reason)..'\n');report:close();love.event.quit(okay and 0 or 1)
end
