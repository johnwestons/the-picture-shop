local Test = {}

local function fleetChecks(context,check)
    local Fleet=require("src.machine_fleet")
    local state=context.State.new()
    local fleet=Fleet.ensure(state)
    local items=fleet.items
    for _=1,100 do Fleet.byId(state,"MCH-0001");Fleet.installedUnits(state) end
    check("scaling_fleet_reads_preserve_normalized_collection",fleet.items==items)
    local extra=Fleet.copy(items[1]);extra.id="MCH-0099";extra.maintenance=nil
    extra.world={x=600,y=500,direction="northwest"}
    items[#items+1]=extra
    check("scaling_fleet_append_normalizes_and_indexes",Fleet.byId(state,extra.id)==extra
        and extra.maintenance.cutter~=nil and fleet.nextId==100)
    table.remove(fleet.items,#fleet.items)
    check("scaling_fleet_removal_invalidates_index",Fleet.byId(state,extra.id)==nil)
    state.machines=Fleet.copy(fleet)
    check("scaling_fleet_snapshot_replacement_has_live_references",
        Fleet.byId(state,"MCH-0001")==state.machines.items[1]
        and state.machines.items[1]~=fleet.items[1])
    state.machines.items[1].variables.bladeEdge=20
    Fleet.ensure(state)
    check("scaling_explicit_fleet_normalization_still_repairs",Fleet.validState(state.machines))
end

local function navigationChecks(check)
    local Navigation=require("src.navigation")
    local Index=require("src.obstacle_index")
    local Footprint=require("src.floor_footprint")
    local assets={getData=function() return nil end}
    local obstacles={}
    for i=1,100 do
        local obstacle={x=80+(i%20)*40,y=250+math.floor(i/20)*30,halfWidth=12,halfHeight=8}
        if i%3==0 then obstacle.shape="diamond"
        elseif i%3==1 then obstacle.halfWidth=nil;obstacle.halfHeight=nil;obstacle.radius=9 end
        if i%5==0 then obstacle=Footprint.expand(obstacle,{x=5,y=4,shape="diamond"}) end
        obstacles[i]=obstacle
    end
    local indexed=Index.new(obstacles)
    local equal=true
    for i=1,300 do
        local x,y=60+(i*37)%840,100+(i*53)%510
        local nx,ny=60+(i*61)%840,100+(i*43)%510
        equal=equal and Navigation.isWalkable(assets,x,y,obstacles)==Navigation.isWalkable(assets,x,y,indexed)
            and Navigation.canTraverse(assets,x,y,nx,ny,obstacles,true)==Navigation.canTraverse(assets,x,y,nx,ny,indexed,true)
    end
    check("scaling_spatial_index_matches_exact_collision_for_mixed_shapes",equal)
    local count,original=0,Footprint.penetration
    local ok,reason=pcall(function()
        Footprint.penetration=function(...) count=count+1;return original(...) end
        assert(Navigation.canTraverse(assets,100,600,850,600,obstacles))
    end)
    Footprint.penetration=original
    if not ok then error(reason) end
    check("scaling_clear_path_does_not_rescan_obstacles_per_pixel",count==#obstacles)
    local thin={{x=400,y=300,halfWidth=.1,halfHeight=60}}
    check("scaling_continuous_collision_still_blocks_thin_obstacles",
        not Navigation.canTraverse(assets,300,300,500,300,thin))
    local embedded={{x=400,y=300,halfWidth=30,halfHeight=20}}
    check("scaling_overlap_escape_allowed_without_deeper_entry",
        Navigation.canTraverse(assets,410,300,445,300,embedded,true)
        and not Navigation.canTraverse(assets,410,300,390,300,embedded,true))
    obstacles[1]={x=450,y=600,halfWidth=1,halfHeight=20}
    check("scaling_new_snapshot_sees_moved_obstacle",
        not Navigation.canTraverse(assets,100,600,850,600,Index.new(obstacles)))
end

local function textureChecks(context,check)
    local characters=context.characterAssets
    characters.retainCharacters({},false)
    characters.beginFrame()
    local south=assert(characters.get("rabbit-worker","idle_south",1))
    local north=assert(characters.get("rabbit-worker","idle_north",1))
    characters.endFrame()
    check("scaling_same_species_concurrent_poses_remain_pinned",characters.residentActionCount()==2)
    characters.beginFrame();characters.get("rabbit-worker","idle_south",1);characters.endFrame()
    check("scaling_unused_action_retires_even_for_visible_species",characters.residentActionCount()==1)
    characters.beginFrame()
    local reused=characters.get("rabbit-worker","idle_north",1)
    local kept=characters.get("rabbit-worker","idle_south",1)
    characters.endFrame()
    check("scaling_recent_actions_reuse_gpu_images",reused==north and kept==south)
    for _,action in ipairs(characters.actions("rabbit-worker")) do
        characters.beginFrame();assert(characters.get("rabbit-worker",action,1));characters.endFrame()
    end
    check("scaling_animation_history_stays_within_inactive_budget",
        characters.residentActionCount()==1 and characters.cachedTextureBytes()<=16*1024*1024)
    characters.retainCharacters({},false)
end

local function checkpointChecks(check)
    local clock=require("src.save_checkpoint").new(5)
    local saves=0
    local function save() saves=saves+1;return true end
    for _=1,20 do clock:update(.25,true,save) end
    check("scaling_background_changes_coalesce_at_five_seconds",saves==1 and not clock.pending)
    clock:update(1,true,save);clock:reset()
    clock:update(5,false,save)
    check("scaling_immediate_commit_clears_pending_checkpoint",saves==1 and not clock.pending)
    clock:update(0,true,function() saves=saves+1;return false end)
    for _=1,19 do clock:update(.25,false,save) end
    check("scaling_failed_checkpoint_retains_dirty_state_without_frame_retries",saves==2 and clock.pending)
    clock:update(.25,false,save)
    check("scaling_failed_checkpoint_retries_latest_state",saves==3 and not clock.pending)
end

function Test.run(context,check)
    fleetChecks(context,check)
    navigationChecks(check)
    textureChecks(context,check)
    checkpointChecks(check)
end
return Test
