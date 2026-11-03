-- Real apartment actions, measured through the actual window and renderer.
-- Reset only public action-art caches: disk/driver caches remain uncontrolled.
return function(runtime,app,rows,output)
    local Fixtures=require("src.tests.home_dining_test")
    local Layout=require("src.home_layouts")
    local Furniture=require("src.home_furniture")
    local Residents=require("src.home_residents")
    local Calendar=require("src.business_calendar")
    local Pose=require("src.home_activity_pose")
    local Routine=require("src.home_routine_pose")
    local Held=require("src.home_held_art")
    local frames=math.max(60,math.min(600,tonumber(os.getenv("PICTURE_SHOP_PERFORMANCE_HOME_FRAMES")) or 120))
    local apartment=os.getenv("PICTURE_SHOP_PERFORMANCE_HOME_APARTMENT") or "corner"
    local filter=os.getenv("PICTURE_SHOP_PERFORMANCE_HOME_FILTER")
    local prewarm=os.getenv("PICTURE_SHOP_PERFORMANCE_HOME_PREWARM")=="1"
    local Preload=prewarm and require("src.home_art_preload")
    local cases={{"wash","sink"},{"drink","sink"},{"dishes","sink"},{"wipe","sink"},{"scrub","bath"},
        {"loadwash","laundry"},{"unload","laundry"},{"change","laundry"},{"sweep","floor"},
        {"trash","floor"},{"prepare","sink"},{"bathe","bath"},{"toilet","toilet"},
        {"eat","floor"},{"sandwich","floor"},{"bottle","floor"},{"sleepfloor","floor"},
        {"sit","chair"},{"cook","stove"},{"cupfill","cup"},{"cupwash","cup"},{"cupdrink","cup"}}
    local renderer,version,vendor,device=love.graphics.getRendererInfo()
    local width,height=love.graphics.getDimensions()
    local events,observing,currentSample={},false,nil
    local preloadResourceFailures={}
    local currentBaselineFrames=0
    local originalImage,originalShader=love.graphics.newImage,love.graphics.newShader
    local uploadPathIndex
    for index=1,60 do
        local name=debug.getupvalue(require("src.image_loader").update,index)
        if name=="uploadPath" then uploadPathIndex=index;break end
        if not name then break end
    end
    local function imageSource(value)
        if type(value)=="string" then return value end
        if uploadPathIndex then
            local _,path=debug.getupvalue(require("src.image_loader").update,uploadPathIndex)
            return path
        end
    end
    local function instrument(original,kind)
        return function(...)
            if not observing then return original(...) end
            local first=select(1,...)
            local callsite=debug.getinfo(2,"Sl")
            local started=love.timer.getTime()
            local result=original(...)
            events[#events+1]={kind=kind,sample_index=currentSample,callsite=callsite.short_src..":"..callsite.currentline,source=kind=="image" and imageSource(first) or nil,
                elapsed_ms=(love.timer.getTime()-started)*1000}
            return result
        end
    end
    love.graphics.newImage=instrument(originalImage,"image")
    love.graphics.newShader=instrument(originalShader,"shader")
    local function saveImage(data,name)
        local encoded=data:encode("png")
        local file=assert(io.open(output.."/"..name..".png","wb"))
        file:write(encoded:getString());file:close();encoded:release()
    end
    local function setTime(state,hours)
        state.calendar=Calendar.dateFromHours(hours)
        state.calendar.elapsed=hours%24/24*Calendar.secondsPerDay(state)
    end
    local function fixture(kind,target)
        local state,p=Fixtures.fresh(apartment)
        p.character="rabbit-worker"
        local c=state.home.chores
        c.dishes=4;c.trash=4;c.soil.kitchen=50;c.soil.bathroom=50;c.soil.living=50
        c.laundry.dirty=1;c.laundry.clean=1
        if kind=="unload" then c.laundry.phase="ready";c.laundry.cycle=1;c.laundry.startedAt=43;c.laundry.dueAt=43.75 end
        state.home.inventory.bread=2;state.home.inventory.vegetables=4
        local definition=Residents.ACTIONS[kind]
        if definition.item then state.home.inventory[definition.item]=1 end
        local item
        if target=="chair" or target=="cup" then item=Fixtures.table(state,p,target)
        elseif target=="stove" then
            state.home.inventory.stove=1;Furniture.materialize(state,false)
            item=state.home.furniture.items[#state.home.furniture.items]
            item.location="floor";item.x,item.y=Layout.kitchenPower(state);item.direction="west"
        end
        if item then
            target="furniture"..item.id
            if item.kind=="cup" then item.contents.water=kind=="cupdrink" and 1 or 0;item.contents.dirty=kind=="cupwash" end
            local point=assert(Furniture.targets(state,p)[target],"No approach for "..kind)
            p.x,p.y=point.x,point.y
        elseif target~="floor" then p.x,p.y=Layout.toWorld(unpack(Layout.get(state).fixtures[target].approach)) end
        assert(runtime.startGame({state=assert(runtime.SaveSchema.snapshot(state)),player=p},"probe"))
        state,p=runtime.state,runtime.World.player
        state.activeSlot=nil;state.employment.recruiting=false
        runtime.App.gameClockSpeed=1
        local function start()
            if item and item.kind=="cup" then
                local actual=assert(Furniture.find(state,item.id))
                local okay,code,message=Residents.command(state,p,"object:pickup:"..actual.id..":"..actual.revision)
                assert(okay,tostring(code)..": "..tostring(message))
                p.x,p.y=Layout.toWorld(unpack(Layout.get(state).fixtures.sink.approach))
            end
            local okay,code,message=Residents.command(state,p,kind..":"..target)
            assert(okay,tostring(code)..": "..tostring(message))
            return assert(Residents.get(state,p).activity)
        end
        return state,p,start
    end
    local function present(state,p,a,seconds,readback)
        if a then setTime(state,a.startedAt+seconds*24/Calendar.secondsPerDay(state)) end
        local pixels
        local started=love.timer.getTime()
        love.event.pump();app.update(0)
        local updated=love.timer.getTime()
        if a then assert(Residents.get(state,p).activity==a,"Action ended during phase sweep") end
        love.graphics.setCanvas();app.draw()
        local stats=love.graphics.getStats()
        local drawn=love.timer.getTime()
        if readback then love.graphics.captureScreenshot(function(data) pixels=data end) end
        love.graphics.present()
        local finished=love.timer.getTime()
        if readback then assert(pixels,"Window GPU readback did not complete") end
        assert(state.screen~="asset_error",table.concat(state.assetErrors or {},"\n"))
        return {wall_ms=(finished-started)*1000,update_ms=(updated-started)*1000,
            draw_ms=(drawn-updated)*1000,present_ms=(finished-drawn)*1000,
            draw_calls=stats.drawcalls,texture_bytes=stats.texturememory,activity_seconds=seconds,
            managed_action_bytes=Preload and Preload.bytes() or nil},pixels
    end
    local function rowFor(kind,temperature,samples,resourceEvents,elapsed)
        local sorted,total,over16,over33,peakTextureBytes,peakActionBytes={},0,0,0,0,0
        for i,sample in ipairs(samples) do
            sorted[i]=sample.wall_ms;total=total+sample.wall_ms
            peakTextureBytes=math.max(peakTextureBytes,sample.texture_bytes)
            peakActionBytes=math.max(peakActionBytes,sample.managed_action_bytes or 0)
            if sample.wall_ms>1000/60 then over16=over16+1 end
            if sample.wall_ms>1000/30 then over33=over33+1 end
        end
        table.sort(sorted)
        local row={name="home_action_"..kind.."_"..temperature,action=kind,apartment=apartment,
            measurement=temperature~="warm" and temperature~="baseline" and "update_draw_present_gpu_readback_every_frame" or "update_draw_present_with_final_gpu_readback",
            cache_state=({cold="resource_cache_cold_os_and_driver_caches_uncontrolled",warm="action_resources_warm",preload="bounded_family_streaming",ready="prewarmed_action_resources",baseline="ordinary_room_and_avatar_warmup"})[temperature],
            repetitions=#samples,first_ms=samples[1].wall_ms,mean_ms=total/#samples,baseline_warmup_frames=currentBaselineFrames,
            p95_ms=sorted[math.ceil(#sorted*.95)],max_ms=sorted[#sorted],
            frames_above_16_67_ms=over16,frames_above_33_33_ms=over33,
            samples=samples,resources=resourceEvents,series_elapsed_ms=elapsed,peak_texture_bytes=peakTextureBytes,peak_managed_action_bytes=peakActionBytes,
            gpu_drained_series_fps=#samples*1000/elapsed,
            width=width,height=height,forced_mobile=os.getenv("PICTURE_SHOP_MOBILE")=="1",
            renderer=renderer,renderer_version=version,gpu_vendor=vendor,gpu_device=device,vsync=love.window.getVSync(),
            timing_note=temperature~="warm" and temperature~="baseline" and "Each frame includes GPU readback; PNG encoding is excluded. Cold mode clears public action caches; ready mode preserves completed family streaming."
                or "Percentiles measure update/draw/present wall time; GPU work may queue. Final frame drains GPU; PNG encoding is excluded."}
        if prewarm and (temperature=="ready" or temperature=="warm") then
            -- Generic resting/idle images can stream behind an already complete
            -- action pose. Keep their timings, but distinguish them from a
            -- household family that incorrectly declared itself ready.
            local actionLoads,avatarUploads=0,0
            for _,event in ipairs(resourceEvents) do
                if event.kind=="image" and event.source and event.source:find("^assets/generated/characters/") then
                    avatarUploads=avatarUploads+1
                else actionLoads=actionLoads+1 end
            end
            row.resource_loads=#resourceEvents
            row.background_avatar_uploads=avatarUploads
            row.unexpected_action_resource_loads=actionLoads
            if actionLoads>0 then preloadResourceFailures[#preloadResourceFailures+1]={action=kind,stage=temperature,resources=actionLoads} end
        end
        rows[#rows+1]=row
        local progress=assert(io.open(output.."/home-action-progress.json","wb"))
        progress:write(require("tools.performance_probe.json")({rows=rows}));progress:close()
        print(string.format("%s mean=%.3fms p95=%.3fms max=%.3fms first=%.3fms resources=%d",row.name,row.mean_ms,row.p95_ms,row.max_ms,row.first_ms,#resourceEvents));io.flush()
    end
    local passed,skipped=0,{}
    for _,case in ipairs(cases) do
        local kind,target=unpack(case)
        if not filter or (","..filter..","):find(","..kind..",",1,true) then
            local okay,state,p,start=pcall(fixture,kind,target)
            if not okay then
                skipped[#skipped+1]={action=kind,error=tostring(state)}
                print("HOME_ACTION_FIXTURE_FAILED "..kind..": "..tostring(state));io.flush()
            else
                -- Load the room and ordinary avatar separately from action art.
                currentBaselineFrames=0
                local baselineSamples,baselineStarted={},love.timer.getTime()
                events={};observing=true
                local function baselineFrame(fence)
                    currentBaselineFrames=currentBaselineFrames+1;currentSample=currentBaselineFrames
                    local sample,pixels=present(state,p,nil,0,fence)
                    baselineSamples[#baselineSamples+1]=sample
                    return pixels
                end
                for _=1,12 do baselineFrame(false) end
                if prewarm then
                    local idle,deadline=0,love.timer.getTime()+20
                    repeat
                        baselineFrame(false)
                        idle=require("src.image_loader").pending() and 0 or idle+1
                        assert(currentBaselineFrames<6000 and love.timer.getTime()<deadline,"Ordinary room assets did not settle: "..kind)
                    until idle>=3
                end
                local baseline=baselineFrame(true);baseline:release()
                observing=false
                rowFor(kind,"baseline",baselineSamples,events,(love.timer.getTime()-baselineStarted)*1000)
                if not prewarm then Pose.release();Routine.release();Held.release() end
                collectgarbage("collect")
                local started,activity=pcall(start)
                if not started then
                    skipped[#skipped+1]={action=kind,error=tostring(activity)}
                    print("HOME_ACTION_START_FAILED "..kind..": "..tostring(activity));io.flush()
                else
                    if prewarm then
                        local loading,elapsed={},0
                        events={};observing=true
                        local deadline=love.timer.getTime()+20
                        repeat
                            currentSample=#loading+1
                            local sample,pixels=present(state,p,activity,0,true)
                            loading[#loading+1]=sample;elapsed=elapsed+sample.wall_ms
                            if #loading==1 then saveImage(pixels,"home-action-"..kind.."-loading") end
                            pixels:release()
                            assert(not Preload.failure(),Preload.failure())
                            if #loading>=3000 or love.timer.getTime()>=deadline then
                                local diagnostic=assert(io.open(output.."/home-action-timeout-"..kind..".json","wb"))
                                diagnostic:write(require("tools.performance_probe.json")({samples=loading,resources=events}));diagnostic:close()
                                error("Action family streaming timed out: "..kind)
                            end
                        until Preload.ready()
                        observing=false;rowFor(kind,"preload",loading,events,elapsed)
                    end
                    local duration=(activity.endsAt-activity.startedAt)*Calendar.secondsPerDay(state)/24
                    local phases={0,math.min(.25,duration*.1),math.min(.5,duration*.15),math.min(.75,duration*.2),duration*.3,duration*.6,duration*.85,duration*.96}
                    local samples,elapsed={},0
                    events={};observing=true
                    for index,seconds in ipairs(phases) do
                        currentSample=index
                        local sample,pixels=present(state,p,activity,seconds,true)
                        samples[index]=sample;elapsed=elapsed+sample.wall_ms
                        if index==6 then saveImage(pixels,"home-action-"..kind..(prewarm and "-ready" or "-cold")) end
                        pixels:release()
                    end
                    observing=false;rowFor(kind,prewarm and "ready" or "cold",samples,events,elapsed)
                    samples={};events={};observing=true
                    local seriesStart=love.timer.getTime();local pixels
                    for index=1,frames do
                        currentSample=index
                        local sample,image=present(state,p,activity,phases[(index-1)%#phases+1],index==frames)
                        samples[index]=sample;pixels=image or pixels
                    end
                    elapsed=(love.timer.getTime()-seriesStart)*1000
                    observing=false;rowFor(kind,"warm",samples,events,elapsed)
                    saveImage(pixels,"home-action-"..kind.."-warm");pixels:release()
                    passed=passed+1
                end
            end
        end
    end
    love.graphics.newImage=originalImage;love.graphics.newShader=originalShader
    rows[#rows+1]={name="home_action_coverage",passed=passed,failed=#skipped,failures=skipped,
        phases_per_cold_action=8,warm_frames_per_action=frames,apartment=apartment,prewarm=prewarm,
        preload_resource_failures=preloadResourceFailures,
        cache_reset=prewarm and "none; bounded family loader controls retention" or "home_activity_pose.release + home_routine_pose.release + home_held_art.release"}
    print(string.format("HOME_ACTION_COVERAGE passed=%d failed=%d",passed,#skipped));io.flush()
end
