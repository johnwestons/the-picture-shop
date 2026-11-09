local Test={}
function Test.run(check)
    local Loader=require("src.image_loader")
    local Preload=require("src.home_art_preload")
    local Images=require("src.home_art_resources")
    local familyNames={"washing","laundry","wipe","trash","sweep","cooking"}
    local modules={}
    for _,name in ipairs(familyNames) do
        modules[name]=require("src.home_"..name.."_art")
        modules[name].release()
    end
    modules.food=require("src.home_food_art");modules.food.release(true)
    require("src.home_held_art").release()
    Preload.reset()
    local oldGraphics,oldTimer=love.graphics,love.timer
    local oldLoad,oldCancel,oldEnabled=Loader.load,Loader.cancel,Loader.enabled
    local waiting,available,cancelled={}, {}, {}
    local now,uploads,shaders=0,0,0
    local function object()
        return {release=function(self)self.released=true end,setTexture=function()end}
    end
    love.graphics={newImage=function()error("Household art must not synchronously decode")end,
        newQuad=object,newMesh=object,newShader=function()shaders=shaders+1;return object()end}
    love.timer={getTime=function()return now end}
    Loader.enabled=true
    Loader.load=function(path)
        if not available[path] then waiting[path]=true;return nil,"pending" end
        waiting[path]=nil;uploads=uploads+1
        local image=object()
        image.setFilter=function()end
        image.getDimensions=function(self)
            assert(not self.released,"Released image")
            if path:find("stir-",1,true) then return 1254,1254 end
            return 1536,1024
        end
        return image
    end
    Loader.cancel=function(path) cancelled[path]=true;waiting[path]=nil end
    local function pendingCount()local count=0;for _ in pairs(waiting) do count=count+1 end;return count end
    local function deliverOne()
        for path in pairs(waiting) do available[path]=true;return end
    end
    local function prepare(name)
        if name=="washing" then return modules[name].prewarm("dishes","east") end
        return modules[name].prewarm("east")
    end
    local okay,reason=xpcall(function()
        Preload.beginFrame()
        check("home_art_pending_family_uses_normal_actor_fallback",
            modules.washing.draw("dishes","east",1,0,0,{},0)==false and not Preload.ready())
        check("home_art_queues_every_washing_phase_and_prop",pendingCount()==3)
        deliverOne()
        check("home_art_partial_family_stays_unready",not prepare("washing"))
        for _=1,2 do deliverOne();prepare("washing") end
        check("home_art_completed_family_ready",prepare("washing") and pendingCount()==0)
        local beforeUploads,beforeShaders=uploads,shaders
        for _=1,8 do prepare("washing") end
        check("home_art_warm_family_creates_no_images_or_shaders",uploads==beforeUploads and shaders==beforeShaders)
        check("home_art_food_fallback_waits_without_sync_decode",modules.food.draw(14,0,0,20)==false)
        deliverOne()
        check("home_art_food_atlas_streams_once",modules.food.prewarm())
        local foodUploads=uploads
        modules.food.prewarm()
        check("home_art_food_preparation_reuses_uploaded_atlas",uploads==foodUploads)
        local foodShaders=shaders
        modules.food.release();modules.food.prewarmShader()
        check("home_art_food_shader_survives_image_eviction",modules.food.shaderReady() and shaders==foodShaders)
        for _,name in ipairs({"laundry","wipe","trash","sweep","cooking"}) do
            check("home_art_"..name.."_waits_for_complete_family",not prepare(name))
            local count=pendingCount()
            local expected=({laundry=6,wipe=4,trash=5,sweep=2,cooking=3})[name]
            check("home_art_"..name.."_queues_all_phases",count==expected)
            for _=1,count do deliverOne();prepare(name) end
            check("home_art_"..name.."_ready_without_sync_decode",prepare(name) and pendingCount()==0)
        end
        Preload.beginFrame()
        for _,name in ipairs(familyNames) do
            Preload.want(name,function()return prepare(name)end)
        end
        Preload.endFrame()
        check("home_art_active_families_protected_above_budget",Preload.bytes()>Preload.BUDGET_BYTES and Preload.ready())
        now=1;Preload.beginFrame()
        Preload.want("laundry",function()return prepare("laundry")end)
        Preload.endFrame()
        check("home_art_unused_families_evicted_to_budget",Preload.bytes()<=Preload.BUDGET_BYTES)
        check("home_art_active_laundry_keeps_all_phases",modules.laundry.cachedPhases()==4 and prepare("laundry"))
        now=30;Preload.beginFrame();Preload.endFrame()
        check("home_art_idle_resources_released",Preload.bytes()==0)
        Preload.beginFrame()
        Loader.load=function(path)waiting[path]=true;return nil,"pending" end
        Preload.want("laundry",function()return prepare("laundry")end)
        local pending=pendingCount();Preload.endFrame()
        now=31;Preload.beginFrame();Preload.endFrame()
        check("home_art_cancelled_activity_cancels_unused_decode_queue",pending==6 and pendingCount()==0)
        for _,case in ipairs({
            {"laundry","held","assets/generated/home-laundry-v2/bundle-eight-directions.png","bundle"},
            {"held","washing","assets/generated/home-washing-v2/mug-eight-directions.png","mug"},
        }) do
            local idle,live,shared,label=unpack(case)
            Images.load(idle,shared);Images.load(live,shared)
            Images.beginFrame();Images.protect(live)
            cancelled[shared]=nil;Images.cancelPending(idle)
            check("home_art_idle_family_cannot_cancel_active_shared_"..label,not cancelled[shared] and waiting[shared])
            Images.release(idle)
            check("home_art_eviction_preserves_active_shared_"..label,not cancelled[shared] and waiting[shared])
            Images.release(live)
            check("home_art_final_shared_owner_cancels_"..label,cancelled[shared] and not waiting[shared])
        end
    end,debug.traceback)
    for _,module in pairs(modules) do module.release() end
    modules.food.release(true)
    Preload.reset()
    love.graphics,love.timer=oldGraphics,oldTimer
    Loader.load,Loader.cancel,Loader.enabled=oldLoad,oldCancel,oldEnabled
    if not okay then error(reason) end
end
return Test
