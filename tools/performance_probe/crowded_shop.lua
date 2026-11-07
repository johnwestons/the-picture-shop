-- Synthetic capacity fixture: deliberately dense, repeatable, private state.
return function(runtime, app, measure, draw, rows)
    local Fleet = require("src.machine_fleet")
    local Schema = require("src.save_schema")
    local Employees = require("src.employees")
    local Calendar = require("src.business_calendar")
    local state = runtime.state
    state.activeSlot = nil
    state.screen = "world"
    state.forklift.operating = false
    state.forklift.operatorPlayerId = nil
    state.forklift.owned = false
    state.warehouse.forkliftOwned = false
    state.money = 1000000
    local starter = Schema.copy(Fleet.ensure(state).items[1])
    for index = 3, 14 do
        local item = Schema.copy(starter)
        item.id = string.format("MCH-%04d", index)
        item.serial = "PS-" .. item.id
        item.world = {x=350+((index-3)%6)*75, y=320+math.floor((index-3)/6)*210, direction="northwest"}
        state.machines.items[#state.machines.items+1] = item
    end
    Fleet.ensure(state)
    for index = 1, 80 do
        local job = assert(runtime.Jobs.createOffer({id="CROWD-"..index,company="Capacity fixture",
            sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
        runtime.Jobs.accept(job)
        state.jobs.active[#state.jobs.active+1] = job
        for _, pallet in ipairs(job.pallets) do
            pallet.location = "warehouse"
            pallet.world = {x=310+((index-1)%10)*50,y=380+math.floor((index-1)/10)*14,direction="northwest"}
        end
    end
    local function hours(h)
        state.calendar=Calendar.dateFromTotalDay(math.floor(h/24))
        state.calendar.elapsed=(h%24)/24*Calendar.secondsPerDay(state)
    end
    local applicant = assert(Employees.createApplicant(state,0))
    assert(Employees.requestResume(state,applicant.id,0))
    hours(.5);Employees.advance(state,.5)
    assert(Employees.command(state,{kind="offer_employee",applicationId=applicant.id,
        expectedRevision=applicant.revision,wageCents=10000,days=31,startHour=9,endHour=17},.5))
    hours(1.25);Employees.advance(state,1.25)
    assert(Employees.command(state,{kind="hire_employee",applicationId=applicant.id,
        expectedRevision=applicant.revision},1.25))
    local worker=state.employment.staff[1]
    for index=2,10 do
        local copy=Schema.copy(worker)
        copy.id=string.format("EMP-%04d",index)
        state.employment.staff[index]=copy
    end
    state.employment.nextEmployeeId=11
    hours(9.25)
    state.employment.lastAtHours=9.25
    for index,w in ipairs(state.employment.staff) do
        w.visible=true;w.phase="idle";w.x=330+index*40;w.y=580
    end
    assert(Employees.valid(state.employment),"Invalid crowd workforce")
    local Storage=require("src.pallet_storage")
    local function previousRackLookup()
        local slots=Storage.slots(state,"warehouse-rack")
        for column=1,Storage.COLUMNS do
            if not slots[1][column] then return column end
        end
    end
    local function directRackLookup()
        return Storage.firstOpenBottomSlot(state,"warehouse-rack")
    end
    local legacyTimes,directTimes={},{}
    local function timed(run)
        local started=love.timer.getTime();run()
        return (love.timer.getTime()-started)*1000
    end
    measure("rack_slot_lookup_compare",600,function(index)
        if index%2==1 then
            legacyTimes[index]=timed(previousRackLookup)
            directTimes[index]=timed(directRackLookup)
        else
            directTimes[index]=timed(directRackLookup)
            legacyTimes[index]=timed(previousRackLookup)
        end
    end)
    local function addLookupStats(name,samples)
        local ordered,total={},0
        for index,value in ipairs(samples) do ordered[index]=value;total=total+value end
        table.sort(ordered)
        rows[#rows][name.."_mean_ms"]=total/#ordered
        rows[#rows][name.."_p95_ms"]=ordered[math.ceil(#ordered*.95)]
    end
    addLookupStats("previous_lookup",legacyTimes)
    addLookupStats("direct_lookup",directTimes)
    measure("crowded_world_update_14_machines_80_pallets_10_staff",180,function() app.update(1/60) end)
    local previousClockSpeed=runtime.App.gameClockSpeed
    runtime.App.gameClockSpeed=10
    measure("crowded_world_update_at_10x_clock",180,function() app.update(1/60) end)
    runtime.App.gameClockSpeed=previousClockSpeed
    measure("crowded_world_draw",90,draw)
    local snapshot=assert(Schema.snapshot(state))
    assert(Schema.validState(snapshot),"Crowded fixture must be a valid save")
    local Protocol=require("src.net.protocol")
    local protocolPayload={sessionId="PERFORMANCE-SESSION",revision=1,state=snapshot}
    local protocolValue=assert(Protocol.make("shop_state",protocolPayload))
    local protocolRawPacket=assert(require("src.net.codec").encode(protocolValue,{
        maxBytes=Protocol.MAX_SHOP_SNAPSHOT_BYTES,maxDepth=32,maxEntries=65536,
        maxStringBytes=128*1024,maxNumberBytes=32,
    }))
    local protocolPacket=assert(Protocol.encode("shop_state",protocolPayload))
    measure("crowded_protocol_shop_state_encode",30,function()
        assert(Protocol.encode("shop_state",protocolPayload))
    end)
    rows[#rows].packet_bytes=#protocolPacket
    rows[#rows].raw_packet_bytes=#protocolRawPacket
    measure("crowded_protocol_shop_state_decode",30,function()
        local envelope=assert(Protocol.decode(protocolPacket))
        assert(envelope.type=="shop_state")
    end)
    rows[#rows].packet_bytes=#protocolPacket
    for _,trial in ipairs({{format="lz4",repetitions=30},{format="zlib",repetitions=10}}) do
        local compressed
        measure("crowded_protocol_"..trial.format.."_compress_shop_state",trial.repetitions,function()
            compressed=love.data.compress("string",trial.format,protocolRawPacket)
        end)
        rows[#rows].raw_bytes=#protocolRawPacket
        rows[#rows].compressed_bytes=#compressed
        local prefix={}
        for index=1,math.min(16,#compressed) do
            prefix[#prefix+1]=string.format("%02x",compressed:byte(index))
        end
        rows[#rows].compressed_prefix_hex=table.concat(prefix)
        assert(love.data.decompress("string",trial.format,compressed)==protocolRawPacket)
        measure("crowded_protocol_"..trial.format.."_decompress_shop_state",trial.repetitions,function()
            assert(love.data.decompress("string",trial.format,compressed)==protocolRawPacket)
        end)
        rows[#rows].raw_bytes=#protocolRawPacket
        rows[#rows].compressed_bytes=#compressed
    end
    runtime._performanceSaveState=snapshot
    measure("crowded_save",3,function() assert(runtime.Save.save(1,state,runtime.World.snapshot())) end)
    state.activeSlot=1
    measure("crowded_gameplay_with_saves",600,function() app.update(1/60) end)
    state.activeSlot=nil
    -- Measure session encoding and delivery with the same dense world used by
    -- the single-player capacity rows. Nonurgent dirties exercise the normal
    -- four-per-second durable snapshot limit.
    local network=require("src.tests.support.network_impairment_harness").new({maxClients=3})
    local Session=require("src.net.session")
    local sessionClock=100
    local function now() return sessionClock end
    local host=Session.new({transportFactory=network.factory,clock=now})
    assert(host:startHost({networkKind="server",name="Crowded Performance Host"}))
    local hostContext={localPlayer=runtime.World.player,
        resolveGuestSpawn=function(hostX,hostY,index) return hostX+index*24,hostY,"warehouse" end,
        getShopSnapshot=function()
            return {state=assert(Schema.snapshot(state)),player=runtime.World.snapshot()}
        end,
        moveRemote=function(player,dt,inputX,inputY)
            runtime.World.updateRemotePlayer(player,dt,inputX,inputY,runtime.Assets,state)
        end,
        getVisitorSnapshot=function() return {customer=runtime.World.customerSnapshot(),vendor=runtime.World.vendorSnapshot()} end,
        getGameSnapshot=function() return require("src.air_hockey").snapshot() end,
        getBasketballSnapshot=function() return require("src.basketball").snapshot(state) end,
        getFightSnapshot=function() return require("src.critter_kombat").snapshot() end,
        getCrisisSnapshot=function() return require("src.critter_crisis").snapshot() end,
        getCrisisEncounters=function() return require("src.critter_crisis").sessions end,
        getEnvironmentSnapshot=function() return runtime.World.environmentSnapshot() end,
        getPalletJackSnapshot=function() return runtime.World.networkPalletJackSnapshot(state) end,
        getPalletJackId=function() return state.palletJack and state.palletJack.id end,
        getExtraPalletJackSnapshots=function() return require("src.pallet_jack_fleet").snapshots(state) end,
        getForkliftSnapshot=function() return runtime.Forklift.snapshot(state,runtime.Config.forklift) end,
        getMachinePoseSnapshot=function() return runtime.World.networkMachinePoseSnapshot(state) end,
        getWorkshopSnapshot=function() return {resources=runtime.workshopAuthority and runtime.workshopAuthority:snapshot() or {},
            wrapper=runtime.wrapperSnapshotView()} end}
    local guests,guestContexts={},{}
    for index=1,3 do
        guests[index]=Session.new({transportFactory=network.factory,clock=now})
        guestContexts[index]={localPlayer={x=420+index*24,y=500,sceneId="warehouse",
            character="rabbit-worker",furColorway=1,overallsColorway=1,taskAction="none"},
            inputX=index*.15,inputY=(index-2)*.1}
        assert(guests[index]:startClient("127.0.0.1:22122",{networkKind="server",
            name="Dense Guest "..index,character="rabbit-worker",
            residentToken=string.rep(tostring(index),64)}))
    end
    for index,guest in ipairs(guests) do guest:update(0,guestContexts[index]) end
    host:update(0,hostContext)
    for index,guest in ipairs(guests) do guest:update(0,guestContexts[index]) end
    for index,guest in ipairs(guests) do
        if not guest.ready then
            local details={}
            for _,event in ipairs(guest:drainEvents()) do
                details[#details+1]=table.concat({tostring(event.type),tostring(event.code),tostring(event.message)},":")
            end
            for _,event in ipairs(host:drainEvents()) do
                details[#details+1]="host/"..table.concat({tostring(event.type),tostring(event.code),tostring(event.message)},":")
            end
            error("crowded performance guest "..index.." failed to join: status="..tostring(guest.status)
                .." disconnected="..tostring(guest.disconnectReason).." events="..table.concat(details," | "))
        end
    end
    local sentPackets,sentBytes,sentBytesByChannel,maxDurablePacket=0,0,{},0
    local send=network.host.send
    network.host.send=function(transport,peer,payload,channel,...)
        sentPackets=sentPackets+1
        if type(payload)=="string" then
            sentBytes=sentBytes+#payload
            sentBytesByChannel[channel]=(sentBytesByChannel[channel] or 0)+#payload
            if channel==2 then maxDurablePacket=math.max(maxDurablePacket,#payload) end
        end
        return send(transport,peer,payload,channel,...)
    end
    local hostTimes,guestTimes={},{{},{},{},total={}}
    local networkProfiler=os.getenv("PICTURE_SHOP_PERFORMANCE_NETWORK_PROFILE")=="1"
        and require("jit.profile") or nil
    local networkStacks={}
    if networkProfiler then
        networkProfiler.start("i1",function(thread,count)
            local stack=networkProfiler.dumpstack(thread,"pl\n",12)
            networkStacks[stack]=(networkStacks[stack] or 0)+count
        end)
    end
    measure("crowded_host_three_guests",600,function(index)
        sessionClock=sessionClock+1/60
        if index%6==0 then host:markShopDirty() end
        local started=love.timer.getTime()
        host:update(1/60,hostContext)
        hostTimes[index]=(love.timer.getTime()-started)*1000
        local guestTotal=0
        for guestIndex,guest in ipairs(guests) do
            started=love.timer.getTime()
            guest:update(1/60,guestContexts[guestIndex])
            guestTimes[guestIndex][index]=(love.timer.getTime()-started)*1000
            guestTotal=guestTotal+guestTimes[guestIndex][index]
        end
        guestTimes.total[index]=guestTotal
    end)
    if networkProfiler then
        networkProfiler.stop()
        rows[#rows].profile={}
        for stack,count in pairs(networkStacks) do
            rows[#rows].profile[#rows[#rows].profile+1]={stack=stack,samples=count}
        end
        table.sort(rows[#rows].profile,function(left,right) return left.samples>right.samples end)
    end
    rows[#rows].sent_packets=sentPackets
    rows[#rows].sent_payload_bytes=sentBytes
    rows[#rows].sent_payload_kib_per_second=sentBytes/1024/10
    rows[#rows].sent_control_payload_bytes=sentBytesByChannel[0] or 0
    rows[#rows].sent_state_payload_bytes=sentBytesByChannel[1] or 0
    rows[#rows].sent_durable_payload_bytes=sentBytesByChannel[2] or 0
    rows[#rows].max_durable_packet_bytes=maxDurablePacket
    local function addTiming(prefix,samples)
        local ordered,total={},0
        for index,value in ipairs(samples) do ordered[index]=value;total=total+value end
        table.sort(ordered)
        rows[#rows][prefix.."_mean_ms"]=total/#ordered
        rows[#rows][prefix.."_p95_ms"]=ordered[math.ceil(#ordered*.95)]
        rows[#rows][prefix.."_max_ms"]=ordered[#ordered]
    end
    addTiming("host_update",hostTimes)
    addTiming("three_guest_updates",guestTimes.total)
    for index=1,3 do addTiming("guest_"..index.."_update",guestTimes[index]) end
    assert(host:stop("Crowded performance probe complete"))
    -- Ten workers trying to reach machinery exercises the congested route and
    -- workstation selection paths that an idle workforce does not cover.
    for _,w in ipairs(state.employment.staff) do
        w.cutterSkill=50
        w.training={skill="cutter",target=75,remainingHours=20}
    end
    measure("crowded_workers_seeking_machine_access",120,function() app.update(1/60) end)
    for _,w in ipairs(state.employment.staff) do w.training=nil;w._trainingMachineId=nil end
    measure("crowded_machine_lookup",1000,function()
        for _,item in ipairs(state.machines.items) do assert(Fleet.byId(state,item.id)==item) end
    end)
    local Navigation=require("src.navigation")
    local obstacles={}
    for i=1,100 do obstacles[i]={x=80+(i%20)*40,y=250+math.floor(i/20)*30,halfWidth=12,halfHeight=8} end
    local assets={getData=function() return nil end}
    measure("crowded_clear_traversal",300,function()
        assert(Navigation.canTraverse(assets,100,600,850,600,obstacles))
    end)
    local Navigator=require("src.npc_navigation")
    local pathContext={assets=assets,obstacles=function() return obstacles end}
    measure("crowded_route_detour",20,function()
        assert(Navigator.findPath({x=100,y=200},{{x=850,y=500}},pathContext))
    end)
    -- Pallet unloading tests many wheel contacts around each machine. Keep
    -- the ordinary one-goal searches above before this case: mixed candidate
    -- counts exercise the same LuaJIT traces as a live warehouse session.
    local contacts={}
    for index=1,640 do
        contacts[index]={x=720+(index%16)*6,y=200+math.floor((index-1)/16)*6}
    end
    local contactContext={assets=assets,obstacles=function()
        return {{x=450,y=330,halfWidth=24,halfHeight=240}}
    end}
    measure("machine_contact_route_640_candidates",20,function()
        assert(Navigator.findPath({x=100,y=300},contacts,contactContext))
    end)
    local maskCalls={getData=0,dimensions=0,pixels=0}
    local walkmask={getDimensions=function()
        maskCalls.dimensions=maskCalls.dimensions+1
        return 960,678
    end,getPixel=function()
        maskCalls.pixels=maskCalls.pixels+1
        return 1,1,1,1
    end}
    local maskAssets={getData=function(name)
        if name=="walkmask" then maskCalls.getData=maskCalls.getData+1;return walkmask end
    end}
    local maskContext={assets=maskAssets,obstacles=contactContext.obstacles}
    measure("machine_contact_route_640_candidates_walkmask",20,function()
        assert(Navigator.findPath({x=100,y=300},contacts,maskContext))
    end)
    rows[#rows].walkmask_get_data_calls=maskCalls.getData
    rows[#rows].walkmask_dimensions_calls=maskCalls.dimensions
    rows[#rows].walkmask_pixel_calls=maskCalls.pixels
    local characters=runtime.CharacterAssets
    measure("character_action_working_set",1,function()
        characters.retainCharacters({"rabbit-worker"},true)
        for _,action in ipairs(characters.actions("rabbit-worker")) do
            if characters.beginFrame then characters.beginFrame() end
            assert(characters.get("rabbit-worker",action,1))
            if characters.endFrame then characters.endFrame() end
        end
    end)
    rows[#rows].active_texture_bytes=characters.textureBytes()
    rows[#rows].cached_texture_bytes=characters.cachedTextureBytes()
    rows[#rows].resident_actions=characters.residentActionCount()
    print(string.format("character working set active=%.1fMiB cached=%.1fMiB actions=%d",
        characters.textureBytes()/1048576,characters.cachedTextureBytes()/1048576,characters.residentActionCount()))
end
