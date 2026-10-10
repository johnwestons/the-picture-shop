local Test = {}

local function cacheChecks(check)
    local now, released = 0, {}
    local Cache=require("src.texture_cache")
    local cache=Cache.new(128,20,function() return now end)
    local function image(name)
        return {getDimensions=function() return 4,4 end,
            release=function() released[name]=(released[name] or 0)+1 end}
    end
    local a,b,c=image("a"),image("b"),image("c")
    cache:put("a",a);cache:put("b",b)
    local reused=cache:take("a")
    cache:put("a",reused);cache:put("c",c)
    check("performance_texture_cache_evicts_oldest_within_budget",
        cache.bytes==128 and released.b==1 and not released.a and not released.c)
    local active=cache:take("a")
    now=21;cache:prune()
    check("performance_texture_cache_expires_only_inactive_images",
        active==a and not released.a and released.c==1 and cache.bytes==0)
    cache:put("a",active);cache:clear()
    check("performance_texture_cache_clear_releases_once",released.a==1 and cache.bytes==0)
end

local function imageChecks(context,check)
    local assets,characters=context.assets,context.characterAssets
    local previousPack=assets.activePackName()
    assert(assets.activatePack("cutter"))
    local clamp=assets.get("cutterClamp")
    assert(assets.activatePack("menu"))
    local hidden=assets.get("cutterClamp")==nil
    assert(assets.activatePack("cutter"))
    check("performance_machine_screen_reuses_textures_after_options",
        hidden and assets.get("cutterClamp")==clamp
        and assets.cachedTextureBytes()<=32*1024*1024)
    assert(assets.activatePack(previousPack))
    characters.retainCharacters({"rabbit-worker"},true)
    local playerImage=characters.get("rabbit-worker","idle_south",1)
    characters.retainCharacters({},true)
    local inactive=characters.residentActionCount()==0
    characters.retainCharacters({"rabbit-worker"},true)
    check("performance_player_textures_survive_brief_menu_changes",
        inactive and characters.get("rabbit-worker","idle_south",1)==playerImage
        and characters.cachedTextureBytes()<=56*1024*1024)
    characters.retainCharacters({})
    check("performance_explicit_character_release_clears_cache",
        characters.textureBytes()==0 and characters.cachedTextureBytes()==0)
end

local function saveChecks(context,check)
    local save,state=context.save,context.State.new()
    local slot=3
    save.delete(slot)
    state.money=123
    assert(save.save(slot,state,{x=100,y=200}))
    local first=love.filesystem.read("saves/slot3.lua")
    local originalWrite=love.filesystem.write
    local okay,result=pcall(function()
        love.filesystem.write=function(path,bytes,...)
            if path=="saves/slot3.lua.tmp" then return originalWrite(path,bytes:sub(1,30)) end
            return originalWrite(path,bytes,...)
        end
        state.money=456
        return save.save(slot,state,{x=100,y=200})
    end)
    love.filesystem.write=originalWrite
    check("performance_save_rejects_short_write_without_losing_primary",
        okay and result==false and love.filesystem.read("saves/slot3.lua")==first
        and save.load(slot).state.money==123)
    assert(save.save(slot,state,{x=100,y=200}))
    love.filesystem.write("saves/slot3.lua","{")
    local restored,status=save.load(slot)
    check("performance_cached_save_still_recovers_external_corruption",
        restored and status=="recovered" and restored.state.money==123)
    save.delete(slot)
end

local function warehouseImageChecks(context,check)
    local renderer=require("src.warehouse_renderer")
    local state=context.State.new()
    state.forklift.owned=true
    local headings={"northwest","north","northeast","east","southeast","south","southwest","west"}
    for index=1,16 do
        state.forklift.direction=headings[(index-1)%8+1]
        state.forklift.operating=index>8
        renderer.beginFrame()
        renderer.drawForklift(context.assets,state)
        renderer.endFrame()
    end
    check("performance_forklift_views_have_bounded_resident_artwork",
        renderer.cachedTextureBytes()<=64*1024*1024
        and renderer.sourceTextureBytes()<=76*1024*1024)
    local uploads=0
    local originalImage=love.graphics.newImage
    local okay,reason=pcall(function()
        love.graphics.newImage=function(...)
            uploads=uploads+1;return originalImage(...)
        end
        for _,direction in ipairs(headings) do
            state.forklift.direction=direction
            renderer.beginFrame();renderer.drawForklift(context.assets,state);renderer.endFrame()
        end
    end)
    love.graphics.newImage=originalImage
    if not okay then error(reason) end
    check("performance_repeated_driving_views_do_not_reload_textures",uploads==0)
    renderer.beginFrame();renderer.endFrame();renderer.clearCache()
    check("performance_warehouse_cache_clears_without_active_scene",renderer.sourceTextureBytes()==0)
end

local function titleChecks(context,check)
    local title,save=context.title,context.save
    local originalList,originalRevision=save.listSlots,save.revision
    local originalClock=love.timer.getTime
    local originalIdentity=love.filesystem.getIdentity
    local now,revision,reads,identity=10,1,0,"performance-listing-a"
    local okay,reason=pcall(function()
        save.listSlots=function() reads=reads+1;return {{money=reads}} end
        save.revision=function() return revision end
        love.timer.getTime=function() return now end
        love.filesystem.getIdentity=function() return identity end
        for _=1,180 do title.slots() end
        check("performance_title_does_not_read_slots_every_frame",reads==1)
        revision=2;title.slots()
        check("performance_title_refreshes_immediately_after_save_changes",reads==2)
        identity="performance-listing-b";title.slots()
        now=10.6;title.slots()
        check("performance_title_refreshes_after_identity_or_external_changes",reads==4)
    end)
    save.listSlots,save.revision=originalList,originalRevision
    love.timer.getTime,love.filesystem.getIdentity=originalClock,originalIdentity
    if not okay then error(reason) end
end

local function frameChecks(check)
    local noop=function() end
    local changed=function() return true end
    local client=function() return false end
    local saves,networkServiced,finalState=0,false,false
    local Runtime={
        App={gameClockSpeed=1,syncPlayerColorways=noop,
            multiplayerFocusGrace={isExpired=client}},
        Assets={pruneCache=noop},CharacterAssets={pruneCache=noop},
        WorldRenderer={pruneCache=noop},
        state={screen="computer",activeSlot=1,employment={applications={1},staff={}}},
        Config={palletJack={}},World={player={id=1},updateWarehouse=changed,
            updateSimulation=changed},
        multiplayer={isClient=client,isHost=client,setMultiplayerSingleControl=noop,isActive=client},
        PalletJack={isOperator=client},DirectIpv4Runtime={updateHosts=noop,updateConnection=noop},
        Machine={setMultiplayerSingleControl=noop,updateAll=function() finalState=networkServiced;return true end},
        Windmill={updateAll=changed},Wrapper={updateAll=changed},
        BusinessCalendar={update=changed},JobService={updateClientEmails=changed},
        MachineMaintenance={updateTechnician=changed},WorkPhone={update=changed},
        syncCamera=noop,updateLanConvenience=noop,warehouseSaveClock=.99,employmentSaveClock=.99,
        updateMultiplayer=function() networkServiced=true end,
        saveCurrent=function() saves=saves+1 end,
        updateCheckpoint=noop,
    }
    local originalRadio=package.loaded["src.jukebox"]
    package.loaded["src.jukebox"]={update=noop,syncMultiplayer=noop}
    require("src.runtime.simulation").install(Runtime)
    local okay,reason=pcall(Runtime.App.update,.02)
    package.loaded["src.jukebox"]=originalRadio
    if not okay then error(reason) end
    check("performance_simultaneous_changes_commit_one_final_save",saves==1 and finalState)
end

local function routeAndNetworkChecks(context,check)
    local AI=require("src.employee_ai")
    local calls=0
    local navigation=require("src.navigation")
    local originalWalk=navigation.isWalkable
    local okay,reason=pcall(function()
        navigation.isWalkable=function(...)
            calls=calls+1;return originalWalk(...)
        end
        local obstacles={{x=450,y=330,halfWidth=24,halfHeight=240}}
        local routeContext={assets={getData=function() return nil end},
            obstacles=function() return obstacles end}
        local blocked=AI.findReachablePoint({x=100,y=300},{{x=450,y=300}},routeContext)
        check("performance_worker_rejects_blocked_goal_without_full_search",blocked==nil and calls==1)
        local actor={x=100,y=300,intentX=0,intentY=0,velocityX=0,velocityY=0,
            distance=0,idleClock=0}
        local goal=AI.findReachablePoint(actor,{{x=450,y=300},{x=800,y=300}},routeContext)
        local arrived=false
        for _=1,1500 do
            arrived=AI.move(actor,goal,1/60,routeContext)
            assert(originalWalk(routeContext.assets,actor.x,actor.y,obstacles))
            if arrived then break end
        end
        check("performance_worker_still_reaches_goal_around_obstacles",arrived and goal.x==800)
    end)
    navigation.isWalkable=originalWalk
    if not okay then error(reason) end
    local network=require("src.tests.support.network_impairment_harness").new({maxClients=1})
    local host=require("src.net.session").new({transportFactory=network.factory})
    assert(host:startHost({networkKind="direct"}))
    host:markShopDirty(true)
    local snapshots=0
    local function snapshot() snapshots=snapshots+1;return {} end
    host:update(.25,{localPlayer=context.world.player,getShopSnapshot=snapshot,
        getVisitorSnapshot=snapshot,getEnvironmentSnapshot=snapshot,getWorkshopSnapshot=snapshot,
        getPalletJackSnapshot=snapshot,getCutterSnapshot=snapshot,getWindmillSnapshot=snapshot,
        getWrapperSnapshots=snapshot})
    local unused=snapshots==0 and host.shopDirty
    assert(host:stop("Performance test complete"))
    check("performance_host_defers_unused_snapshots_until_guests_join",unused)
end

local function roomAndMovementChecks(context,check)
    local roomRenderer=require("src.shop_room_renderer")
    local originalMesh=love.graphics.newMesh
    local meshes=0
    local canvas=love.graphics.newCanvas(960,678)
    local pack=context.assets.activePackName()
    assert(context.assets.activatePack(nil))
    roomRenderer.clearCache()
    love.graphics.push("all");love.graphics.setCanvas({canvas,stencil=true})
    local okay,reason=pcall(function()
        love.graphics.newMesh=function(...) meshes=meshes+1;return originalMesh(...) end
        for i=1,120 do roomRenderer.drawDock(context.assets,{progress=math.min(i/60,1)}) end
        check("performance_open_dock_reuses_one_mesh_across_frames",meshes==1)
        roomRenderer.clearCache()
        roomRenderer.drawDock(context.assets,{progress=1})
        check("performance_dock_recreates_after_focus_cache_release",meshes==2)
    end)
    love.graphics.newMesh=originalMesh
    love.graphics.pop();canvas:release();context.assets.activatePack(pack)
    if not okay then error(reason) end

    local logistics=context.PalletLogistics
    local originalObstacles=logistics.obstacles
    local calls=0
    okay,reason=pcall(function()
        logistics.obstacles=function(...) calls=calls+1;return originalObstacles(...) end
        local state=context.State.new()
        local worker={id=2,x=800,y=560,velocityX=100,velocityY=0,sceneId="warehouse"}
        context.world.updateRemotePlayer(worker,.1,1,0,context.assets,state)
        check("performance_player_substeps_share_one_obstacle_snapshot",calls==1 and worker.x>800)
        context.world.updateRemotePlayer(worker,.1,1,0,context.assets,state)
        check("performance_next_movement_update_refreshes_obstacles",calls==2)
    end)
    logistics.obstacles=originalObstacles
    if not okay then error(reason) end
end

function Test.run(context,check)
    cacheChecks(check)
    imageChecks(context,check)
    warehouseImageChecks(context,check)
    saveChecks(context,check)
    titleChecks(context,check)
    frameChecks(check)
    routeAndNetworkChecks(context,check)
    roomAndMovementChecks(context,check)
end
return Test
