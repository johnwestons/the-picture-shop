-- Real-engine measurements using fresh, private test saves only.
local output = assert(os.getenv("PICTURE_SHOP_PERFORMANCE_OUTPUT"))
local rows, counters = {}, {}
local profiler = os.getenv("PICTURE_SHOP_PERFORMANCE_PROFILE") == "1" and require("jit.profile")
local profileFilter = os.getenv("PICTURE_SHOP_PERFORMANCE_PROFILE_FILTER")
local function profileMeasure(name)
    if not profiler then return false end
    if not profileFilter or profileFilter=="" then return true end
    for selected in profileFilter:gmatch("[^,]+") do
        if selected==name then return true end
    end
    return false
end
local function count(target, key, name)
    local original = target[key]
    target[key] = function(...)
        counters[name] = (counters[name] or 0) + 1
        return original(...)
    end
end
local function measure(name, repetitions, run, afterSample)
    collectgarbage("collect")
    local samples, before = {}, {}
    for key, value in pairs(counters) do before[key] = value end
    local stacks = {}
    local collectProfile=profileMeasure(name)
    if collectProfile then profiler.start("i1", function(thread, count)
        local stack = profiler.dumpstack(thread, "pl\n", 10)
        stacks[stack] = (stacks[stack] or 0) + count
    end) end
    for index = 1, repetitions do
        local started = love.timer.getTime()
        run(index)
        samples[index] = (love.timer.getTime() - started) * 1000
        if afterSample then afterSample(index) end
    end
    if collectProfile then profiler.stop() end
    local first=samples[1]
    table.sort(samples)
    local total = 0
    for _, sample in ipairs(samples) do total = total + sample end
    local row = {name=name, mean_ms=total/repetitions, p95_ms=samples[math.ceil(repetitions*.95)],
        max_ms=samples[#samples], repetitions=repetitions,first_ms=first,
        warm_mean_ms=repetitions>1 and (total-first)/(repetitions-1) or total}
    for key, value in pairs(counters) do row[key] = value - (before[key] or 0) end
    if collectProfile then
        row.profile = {}
        for stack, count in pairs(stacks) do row.profile[#row.profile+1] = {stack=stack,samples=count} end
        table.sort(row.profile,function(a,b) return a.samples>b.samples end)
    end
    rows[#rows+1] = row
    print(string.format("%s mean=%.3fms p95=%.3fms max=%.3fms decodes=%d reads=%d saves=%d",
        name,row.mean_ms,row.p95_ms,row.max_ms,row.image_decodes or 0,row.file_reads or 0,row.saves or 0))
    io.flush()
end
local function runtimeOf(callback)
    for index=1,60 do
        local name,value=debug.getupvalue(callback,index)
        if not name then break end
        if type(value)=="table" and value.App and value.state then return value end
    end
    error("App context unavailable to performance probe")
end
local function populate(runtime)
    local state=runtime.state
    for index=1,80 do
        local job=assert(runtime.Jobs.createOffer({id="PERF-"..index,company="Performance fixture",
            sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
        runtime.Jobs.accept(job)
        state.jobs.completed[#state.jobs.completed+1]=job
    end
    for index=1,200 do
        require("src.inbox").addNotice(state,{id="perf-email-"..index,kind="client_notice",
            sender="Performance fixture",subject="Shop update "..index,
            body="An archived message for the loading benchmark.",receivedAtHours=index,read=true})
    end
end
local function finish(runtime,app)
    local assets,characters=runtime.Assets,runtime.CharacterAssets
    local result=require("tools.performance_probe.json")({rows=rows,
        active_texture_bytes=assets.textureBytes()+characters.textureBytes(),
        cached_texture_bytes=assets.cachedTextureBytes()+characters.cachedTextureBytes(),
        warehouse_source_texture_bytes=require("src.warehouse_renderer").sourceTextureBytes(),
        warehouse_cached_texture_bytes=require("src.warehouse_renderer").cachedTextureBytes(),
        gpu_texture_bytes=love.graphics.getStats().texturememory})
    local file=assert(io.open(output.."/measurements.json","wb"));file:write(result);file:close()
    if app.sound then app.sound:shutdown() end
    runtime.Save.shutdown()
    love.event.quit(0)
end
function love.load()
    local identity=assert(os.getenv("PICTURE_SHOP_TEST_IDENTITY"))
    assert(identity:match("^the%-picture%-shop%-test%-[%w%-]+$"))
    love.filesystem.setIdentity(identity)
    count(love.image,"newImageData","image_decodes")
    count(love.graphics,"newImage","texture_uploads")
    count(love.filesystem,"read","file_reads")
    count(love.filesystem,"write","file_writes")
    count(require("src.save"),"save","saves")
    require("src.smoke").requested=function() return false end
    local app
    measure("module_startup",1,function() app=require("src.app") end)
    local runtime=runtimeOf(app.load)
    measure("asset_and_app_startup",1,function() app.load() end)
    -- Keep the older synchronous comparison rows reproducible. The stall
    -- scenarios below explicitly exercise the real asynchronous pipeline.
    require("src.image_loader").setEnabled(os.getenv("PICTURE_SHOP_PERFORMANCE_HOME_PREWARM")=="1")
    assert(#runtime.state.assetErrors==0,table.concat(runtime.state.assetErrors,"\n"))
    local mobile=os.getenv("PICTURE_SHOP_MOBILE")=="1"
    local width,height=mobile and 1600 or 960,mobile and 720 or 678
    love.window.setMode(width,height,{vsync=0,resizable=false})
    if os.getenv("PICTURE_SHOP_PERFORMANCE_BACKGROUND_WAREHOUSE")=="1" then
        require("tools.performance_probe.background_warehouse")(runtime,app,rows,output)
        finish(runtime,app);return
    end
    if os.getenv("PICTURE_SHOP_PERFORMANCE_HOME_ACTIONS")=="1" then
        require("tools.performance_probe.home_actions")(runtime,app,rows,output)
        finish(runtime,app);return
    end
    local assets,characters=runtime.Assets,runtime.CharacterAssets
    measure("cutter_menu_pack_roundtrip",10,function()
        assert(assets.activatePack("cutter"));assert(assets.activatePack("menu"))
    end)
    measure("press_world_roundtrip",10,function()
        assert(assets.activatePack("press"));assert(assets.activatePack(nil))
    end)
    measure("character_options_roundtrip",10,function()
        characters.retainCharacters({"rabbit-worker"}, true)
        assert(characters.get("rabbit-worker","idle_south",1))
        characters.retainCharacters({}, true)
    end)
    assert(runtime.startGame(runtime.Save.newGame(1),"probe"))
    runtime.state.activeSlot=nil
    runtime.state.employment.recruiting=false
    measure("world_update",600,function() app.update(1/60) end)
    local canvas=love.graphics.newCanvas(width,height)
    local function draw()
        love.graphics.setCanvas({canvas,stencil=true});app.draw();love.graphics.setCanvas()
        love.graphics.flushBatch()
    end
    local function capture(name)
        local data=canvas:newImageData()
        local encoded=data:encode("png")
        local file=assert(io.open(output.."/"..name..".png","wb"))
        file:write(encoded:getString());file:close();data:release();encoded:release()
    end
    measure("world_draw",180,draw)
    runtime.state.screen="machine"
    runtime.state.machineType="polar_115"
    draw()
    local originalClamp=assert(assets.get("cutterClamp"))
    measure("cutter_options_ui_roundtrip",10,function()
        assert(runtime.openOptions());draw()
        assert(assets.activePackName()=="cutter" and assets.get("cutterClamp")==originalClamp)
        assert(runtime.closeOptions());draw()
    end)
    runtime.state.screen="world"
    runtime.state.optionsReturnScreen=nil
    populate(runtime)
    runtime.state.screen="computer";runtime.ComputerScreen.enter(runtime.state)
    measure("office_draw_populated",180,draw)
    measure("save_populated",12,function() assert(runtime.Save.save(1,runtime.state,runtime.World.snapshot())) end)
    runtime.state.screen="title"
    measure("title_draw_populated",180,draw)
    runtime.state.screen="world"
    runtime.state.activeSlot=1
    measure("gameplay_with_saves",600,function() app.update(1/60) end)
    local AI=require("src.employee_ai")
    local navigationAssets={getData=function() return nil end}
    local obstacles={{x=450,y=330,halfWidth=24,halfHeight=240}}
    local pathContext={assets=navigationAssets,obstacles=function() return obstacles end}
    measure("employee_route_detour",20,function()
        assert(AI.findReachablePoint({x=100,y=300},{{x=800,y=300}},pathContext))
    end)
    measure("employee_route_blocked_goal",5,function()
        assert(not AI.findReachablePoint({x=100,y=300},{{x=450,y=300}},pathContext))
    end)
    local network=require("src.tests.support.network_impairment_harness").new({maxClients=1})
    local host=require("src.net.session").new({transportFactory=network.factory})
    assert(host:startHost({networkKind="direct"}))
    host:markShopDirty(true)
    local snapshots=0
    local hostContext={localPlayer=runtime.World.player,getShopSnapshot=function()
        snapshots=snapshots+1
        return {state=runtime.SaveSchema.snapshot(runtime.state)}
    end}
    measure("host_without_guests",1800,function() host:update(1/60,hostContext) end)
    rows[#rows].shop_snapshots=snapshots
    assert(host:stop("Performance probe complete"))
    local multiplayerNetwork=require("src.tests.support.network_impairment_harness").new({maxClients=3})
    local Session=require("src.net.session")
    local multiplayerHost=Session.new({transportFactory=multiplayerNetwork.factory,clock=function() return 100 end})
    assert(multiplayerHost:startHost({networkKind="server",name="Performance Host"}))
    local multiplayerShop={state=runtime.SaveSchema.snapshot(runtime.state),player=runtime.World.snapshot()}
    local multiplayerContext={localPlayer=runtime.World.player,
        resolveGuestSpawn=function(hostX,hostY,index) return hostX+index*24,hostY,"warehouse" end,
        getShopSnapshot=function() return multiplayerShop end,
        moveRemote=function(player,dt,inputX,inputY)
            runtime.World.updateRemotePlayer(player,dt,inputX,inputY,runtime.Assets,runtime.state)
        end,
        getVisitorSnapshot=function() return {customer=runtime.World.customerSnapshot(),vendor=runtime.World.vendorSnapshot()} end,
        getGameSnapshot=function() return require("src.air_hockey").snapshot() end,
        getBasketballSnapshot=function() return require("src.basketball").snapshot(runtime.state) end,
        getFightSnapshot=function() return require("src.critter_kombat").snapshot() end,
        getCrisisSnapshot=function() return require("src.critter_crisis").snapshot() end,
        getCrisisEncounters=function() return require("src.critter_crisis").sessions end,
        getEnvironmentSnapshot=function() return runtime.World.environmentSnapshot() end,
        getPalletJackSnapshot=function() return runtime.World.networkPalletJackSnapshot(runtime.state) end,
        getPalletJackId=function() return runtime.state.palletJack and runtime.state.palletJack.id end,
        getExtraPalletJackSnapshots=function() return require("src.pallet_jack_fleet").snapshots(runtime.state) end,
        getForkliftSnapshot=function() return runtime.Forklift.snapshot(runtime.state,runtime.Config.forklift) end,
        getMachinePoseSnapshot=function() return runtime.World.networkMachinePoseSnapshot(runtime.state) end,
        getWorkshopSnapshot=function() return {resources=runtime.workshopAuthority and runtime.workshopAuthority:snapshot() or {},
            wrapper=runtime.wrapperSnapshotView()} end,
        }
    local guests,guestContexts={},{}
    for index=1,3 do
        guests[index]=Session.new({transportFactory=multiplayerNetwork.factory,clock=function() return 100 end})
        guestContexts[index]={localPlayer={x=420+index*24,y=500,sceneId="warehouse",
            character="rabbit-worker",furColorway=1,overallsColorway=1,taskAction="none"},
            inputX=index*.15,inputY=(index-2)*.1}
        assert(guests[index]:startClient("127.0.0.1:22122",{networkKind="server",
            name="Performance Guest "..index,character="rabbit-worker",residentToken=string.rep(tostring(index),64)}))
    end
    for index,guest in ipairs(guests) do guest:update(0,guestContexts[index]) end
    multiplayerHost:update(0,multiplayerContext)
    for index,guest in ipairs(guests) do guest:update(0,guestContexts[index]) end
    for _,guest in ipairs(guests) do assert(guest.ready,"performance guest failed to join") end
    local sentPackets=0
    local send=multiplayerNetwork.host.send
    multiplayerNetwork.host.send=function(transport,...)
        sentPackets=sentPackets+1
        return send(transport,...)
    end
    measure("host_three_guests",600,function()
        multiplayerHost:update(1/60,multiplayerContext)
        for index,guest in ipairs(guests) do guest:update(1/60,guestContexts[index]) end
    end)
    rows[#rows].sent_packets=sentPackets
    assert(multiplayerHost:stop("Performance probe complete"))
    local gpuBefore=love.graphics.getStats().texturememory
    local headings={"northwest","north","northeast","east","southeast","south","southwest","west"}
    runtime.state.forklift.owned=true
    runtime.state.warehouse.forkliftOwned=true
    measure("forklift_all_views_sync_loader_disabled",16,function(index)
        local vehicle=runtime.state.forklift
        vehicle.direction=headings[(index-1)%8+1]
        vehicle.operating=index>8
        vehicle.operatorPlayerId=vehicle.operating and 1 or nil
        draw()
    end)
    rows[#rows].additional_gpu_texture_bytes=love.graphics.getStats().texturememory-gpuBefore
    require("tools.performance_probe.crowded_shop")(runtime,app,measure,draw,rows)
    require("tools.performance_probe.stalls")(runtime,app,measure,draw,rows,capture)
    require("tools.performance_probe.scenes")(runtime,app,rows,output)
    finish(runtime,app)
end
