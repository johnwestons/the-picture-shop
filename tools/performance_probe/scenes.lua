-- Window presentation measurements. Unlike the offscreen CPU submission rows,
-- each sample draws the real window and swaps it. A final screenshot readback
-- drains queued GPU work before the series throughput is calculated.
return function(runtime,app,rows,output)
    local frames=math.max(60,math.min(600,tonumber(os.getenv("PICTURE_SHOP_PERFORMANCE_SCENE_FRAMES")) or 180))
    local width,height=love.graphics.getDimensions()
    local renderer,version,vendor,device=love.graphics.getRendererInfo()
    local mobile=os.getenv("PICTURE_SHOP_MOBILE")=="1"
    local function present()
        love.event.pump()
        app.update(1/60)
        love.graphics.setCanvas()
        app.draw()
        love.graphics.present()
    end
    local function sample(name)
        runtime.state.activeSlot=nil
        for _=1,30 do present() end
        collectgarbage("collect")
        local samples,stats,pixels={},nil,nil
        local started=love.timer.getTime()
        for index=1,frames do
            local before=love.timer.getTime()
            love.event.pump()
            app.update(1/60)
            love.graphics.setCanvas()
            app.draw()
            stats=love.graphics.getStats()
            if index==frames then
                love.graphics.captureScreenshot(function(data) pixels=data end)
            end
            love.graphics.present()
            samples[index]=(love.timer.getTime()-before)*1000
        end
        local elapsed=love.timer.getTime()-started
        assert(pixels,"Presentation benchmark did not complete its GPU readback")
        table.sort(samples)
        local row={name="presented_"..name,measurement="update_draw_present_with_final_gpu_readback",
            width=width,height=height,forced_mobile=mobile,vsync=love.window.getVSync(),
            renderer=renderer,renderer_version=version,gpu_vendor=vendor,gpu_device=device,
            repetitions=frames,warmup_frames=30,simulation_step_seconds=1/60,
            elapsed_ms=elapsed*1000,gpu_drained_series_fps=frames/elapsed,
            mean_ms=elapsed*1000/frames,p95_ms=samples[math.ceil(frames*.95)],
            max_ms=samples[#samples],draw_calls=stats.drawcalls,texture_bytes=stats.texturememory,
            timing_note="Percentiles measure update/draw/present wall time; GPU work may queue. Series throughput includes final GPU readback; no frame limiter."}
        rows[#rows+1]=row
        print(string.format("%s presented mean=%.3fms p95=%.3fms max=%.3fms GPU-drained throughput=%.1ffps",
            row.name,row.mean_ms,row.p95_ms,row.max_ms,row.gpu_drained_series_fps))
        io.flush()
        local encoded=pixels:encode("png")
        local file=assert(io.open(output.."/"..row.name..".png","wb"))
        file:write(encoded:getString());file:close();encoded:release();pixels:release()
        assert(runtime.state.screen~="asset_error",table.concat(runtime.state.assetErrors or {},"\n"))
    end

    runtime.state.screen="world"
    runtime.state.optionsReturnScreen=nil
    runtime.World.player.sceneId="warehouse"
    runtime.App.gameClockSpeed=1
    sample("crowded_shop")
    runtime.App.gameClockSpeed=10
    sample("crowded_shop_10x_clock")
    runtime.App.gameClockSpeed=1
    runtime.state.screen="computer"
    runtime.ComputerScreen.enter(runtime.state)
    sample("crowded_office")
    runtime.state.screen="machine"
    runtime.state.machineType="polar_115"
    sample("cutter_screen")

    -- Use the same durable home construction and spawn contract as home_scene_test.
    local state=runtime.State.new()
    state.home=assert(require("src.home").new({apartmentId="corner",furnishingPreset="modest"}))
    local week=state.home.weekend
    week.phase="home";week.closedAtHours=week.closesAtHours
    local at=week.closesAtHours+14
    state.calendar=runtime.BusinessCalendar.dateFromTotalDay(math.floor(at/24))
    state.calendar.elapsed=(at%24)/24*runtime.BusinessCalendar.secondsPerDay(state)
    local x,y=require("src.home_layouts").spawn(state,1)
    assert(runtime.startGame({state=assert(runtime.SaveSchema.snapshot(state)),
        player={id=1,x=x,y=y,sceneId="home"}},"probe"))
    sample("furnished_home")

    -- Authored cabinet setup from critter_kombat_test, with the actual solo game.
    state=runtime.State.new();state.money=50000
    local upgrades=require("src.warehouse_upgrades")
    local games=require("src.breakroom_games")
    assert(upgrades.purchase(state,"front_left","breakroom","PERF-ROOM",0))
    upgrades.update(state,0)
    upgrades.update(state,0,{noticeDeliveredProjectId="WUP-0001",noticeCallId="PERF-CALL"})
    upgrades.update(state,2,{workerArrivedProjectId="WUP-0001"})
    upgrades.update(state,98);upgrades.update(state,98,{workerReleasedProjectId="WUP-0001"})
    assert(games.purchase(state,"front_left","critter_kombat","PERF-CABINET"))
    local cabinet=games.CATALOG.critter_kombat
    assert(runtime.startGame({state=assert(runtime.SaveSchema.snapshot(state)),player={id=1,
        x=cabinet.interactionX,y=cabinet.interactionY,sceneId="front_left"}},"probe"))
    local screen=require("src.screens.critter_kombat_screen")
    screen.enter(runtime,"front_left")
    screen.keypressed(runtime,"1");screen.keypressed(runtime,"1")
    screen.keypressed(runtime,"return")
    for _=1,90 do present() end
    assert(require("src.critter_kombat").matches.front_left.phase=="playing",
        "Arcade presentation fixture did not start its fight")
    sample("arcade_kombat")
    screen.leave(runtime)
end
