return function(runtime,app,measure,draw,rows,capture)
    local save=runtime.Save
    assert(save.flush())
    local Schema=require("src.save_schema")
    measure("save_schema_snapshot_populated",12,function()
        assert(Schema.snapshot(runtime._performanceSaveState))
    end)
    measure("save_schema_deep_copy_populated",12,function()
        assert(Schema.copy(runtime._performanceSaveState))
    end)
    measure("async_save_snapshot_and_dispatch_populated",12,function()
        assert(save.queue(1,runtime._performanceSaveState,runtime.World.snapshot()))
    end,function() assert(save.flush()) end)
    local Loader=require("src.image_loader")
    local path=require("src.forklift_presentation").reviewCatalog(true).northwest.path
    measure("cold_forklift_image_synchronous",3,function()
        local image=love.graphics.newImage(path);image:release()
    end)
    Loader.setEnabled(true)
    local image,reason
    local ticks,maxTick,started=0,0,love.timer.getTime()
    repeat
        local before=love.timer.getTime()
        Loader.update()
        image,reason=Loader.load(path)
        maxTick=math.max(maxTick,(love.timer.getTime()-before)*1000)
        ticks=ticks+1
        if not image and reason~="pending" then error(reason) end
        if not image then love.timer.sleep(.001) end
        assert(love.timer.getTime()-started<15,"Image decode timeout")
    until image
    image:release()
    rows[#rows+1]={name="cold_forklift_image_async",main_thread_max_ms=maxTick,
        elapsed_ms=(love.timer.getTime()-started)*1000,responsive_ticks=ticks}
    print(string.format("cold_forklift_image_async main-thread max=%.3fms responsive ticks=%d",maxTick,ticks))
    -- Measure the first player pose through the same async loader used in play.
    -- Keep a real update/draw cycle running while decode and the bounded GPU
    -- upload progress, distinct from the synthetic all-actions warmup row.
    local characters=runtime.CharacterAssets
    characters.retainCharacters({},false)
    local character,action="rabbit-worker","walk_south"
    assert(characters.hasAction(character,action),"Missing representative player walk action")
    characters.get(character,action,1) -- queue the cold request before the first frame
    local characterMaximum,characterFrames,characterBegin=0,0,love.timer.getTime()
    local characterImage
    repeat
        local before=love.timer.getTime()
        app.update(1/60)
        characterImage=characters.get(character,action,1)
        draw()
        characterMaximum=math.max(characterMaximum,(love.timer.getTime()-before)*1000)
        characterFrames=characterFrames+1
        love.timer.sleep(.001)
        assert(love.timer.getTime()-characterBegin<20,"Character action streaming timeout")
    until characterImage
    rows[#rows+1]={name="cold_player_walk_action_async",main_thread_max_ms=characterMaximum,
        elapsed_ms=(love.timer.getTime()-characterBegin)*1000,responsive_frames=characterFrames,
        character=character,action=action}
    print(string.format("cold_player_walk_action_async main-thread max=%.3fms responsive frames=%d",
        characterMaximum,characterFrames))
    characters.retainCharacters({},false)
    -- Real screen draw/update cycle while the cold cutter pack streams.
    runtime.state.screen="world";runtime.state.activeSlot=nil
    assert(runtime.Assets.activatePack(nil));runtime.Assets.clearCache()
    runtime.state.screen="machine";runtime.state.machineType="polar_115"
    local maximum,frames,begin=0,0,love.timer.getTime()
    repeat
        local before=love.timer.getTime()
        app.update(1/60);draw()
        maximum=math.max(maximum,(love.timer.getTime()-before)*1000)
        frames=frames+1
        if frames==1 then capture("loading-cutter") end
        love.timer.sleep(.001)
        assert(love.timer.getTime()-begin<20,"Pack streaming timeout")
    until runtime.Assets.activePackName()=="cutter"
    assert(runtime.state.screen~="asset_error")
    capture("loaded-cutter")
    rows[#rows+1]={name="cold_cutter_screen_async",main_thread_max_ms=maximum,
        elapsed_ms=(love.timer.getTime()-begin)*1000,responsive_frames=frames}
    print(string.format("cold_cutter_screen_async main-thread max=%.3fms responsive frames=%d",maximum,frames))
    Loader.shutdown();Loader.setEnabled(false)
end
