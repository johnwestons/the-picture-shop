local State=require("src.state")
local Config=require("src.config")
local Gameplay=require("src.warehouse_gameplay")
local Layout=require("src.warehouse_layout")
local Upgrades=require("src.warehouse_upgrades")
local Storage=require("src.pallet_storage")
local Forklift=require("src.forklift")
local Navigation=require("src.navigation")
local Pallets=require("src.pallet_state")
local Test={}
local function assets(white)
    local mask={getDimensions=function()return 960,678 end,
        getPixel=function()local v=white==false and 0 or 1;return v,v,v,1 end}
    return {getData=function(name)if name=="walkmask"then return mask end end}
end
local function context(white)
    return {assets=assets(white),obstacles=function(state,excludeJack,inflate,_,_,excluded,__,excludeLift)
        local list=Layout.obstacles(state)
        if not excludeLift then local lift=Forklift.obstacle(state,Config.forklift);if lift then list[#list+1]=lift end end
        if state.testObstacle then list[#list+1]={x=state.testObstacle.x,y=state.testObstacle.y,halfWidth=10,halfHeight=10} end
        for _,item in ipairs(Pallets.items(state)) do
            local p=item.pallet
            if p.id~=excluded and p.location=="warehouse" and p.world then
                list[#list+1]={x=p.world.x,y=p.world.y,halfWidth=20,halfHeight=12}
            end
        end
        for _,ob in ipairs(list) do
            if ob.halfWidth then ob.halfWidth=ob.halfWidth+(inflate.x or 0);ob.halfHeight=ob.halfHeight+(inflate.y or 0) end
        end
        return list
    end}
end
local function fresh()
    local state=State.new();state.money=30000
    assert(Upgrades.purchaseForklift(state,"LIVE-LIFT",0))
    local cx=context()
    Gameplay.update(0,state,cx)
    local player={id=1,x=state.forklift.x+60,y=state.forklift.y}
    return state,player,cx
end
local function rack(state)
    assert(Upgrades.purchase(state,"front_left","storage","LIVE-RACK",0))
    Upgrades.update(state,0,{noticeDeliveredProjectId="WUP-0001",noticeCallId="CALL-0001"})
    Upgrades.update(state,2,{workerArrivedProjectId="WUP-0001"})
    Upgrades.update(state,98)
    state.storage.racks["front_left-rack"]=Storage.rackDefinition("front_left")
end
local function pallet(state)
    local x,y=Forklift.dropPosition(state,Config.forklift)
    local p={id="LIVE-PALLET",location="warehouse",status="raw",wrapped=true,quantity=500,
        remainingSheets=473,paper={status="complete",marker="original"},world={x=x,y=y,direction="northwest",spawnProgress=1}}
    state.jobs.active={{id="LIVE-JOB",pallets={p}}}
    return p
end
local function stackTests(check)
    local state,player,cx=fresh()
    assert(Gameplay.command(player,state,{kind="operate"},cx))
    local lift=state.forklift
    lift.direction="west"
    local top=pallet(state)
    top.location,top.world="on_forklift",{x=lift.x,y=lift.y,direction="west",spawnProgress=1}
    lift.carriedPalletId=top.id
    state.jobs.active[1].sourceSize={width=20,height=16}
    local base={id="STACK-BASE",location="warehouse",status="raw",wrapped=true,remainingSheets=800,
        paper={marker="base-paper"},world={x=lift.x-80,y=lift.y,direction="northwest",spawnProgress=1}}
    state.jobs.active[2]={id="STACK-BASE-JOB",sourceSize={width=20,height=16},pallets={base}}
    local topPaper,basePaper=top.paper,base.paper
    local request={kind="stack",requestId="WORLD-STACK-1",expectedRevision=0,vehicle="forklift",
        palletId=top.id,supportPalletId=base.id}
    local candidate=Gameplay.stackCandidate(state)
    check("warehouse_stack_candidate_uses_reachable_floor_support",candidate and candidate.kind=="stack"
        and candidate.palletId==top.id and candidate.supportPalletId==base.id)
    local ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_requires_fully_raised_forks",not ok and code=="wrong_fork_height" and top.location=="on_forklift")
    lift.forkHeight,lift.targetForkHeight=1,1
    lift.moving=true
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_rejects_moving_vehicle",not ok and code=="vehicle_not_stationary")
    lift.moving,lift.lifting=false,true
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_rejects_lift_in_progress",not ok and code=="lift_in_progress")
    lift.lifting=false
    ok,code=Gameplay.command({id=2,x=lift.x,y=lift.y},state,request,cx)
    check("warehouse_stack_rejects_wrong_operator",not ok and code=="not_owner")
    local baseX=base.world.x
    base.world.x=lift.x-10;lift.direction="north"
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_rechecks_fork_heading",not ok and code=="not_aligned")
    base.world.x=baseX;lift.direction="west"
    state.testObstacle={x=base.world.x,y=base.world.y}
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_rechecks_target_clearance",not ok and code=="blocked")
    state.testObstacle=nil
    base.world.x=lift.x-50
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_support_is_not_excluded_from_vehicle_body_clearance",not ok and code=="blocked")
    base.world.x=baseX
    base.paper=nil
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_rejects_nonpaper_loads",not ok and code=="not_stackable")
    base.paper=basePaper
    state.jobs.active[2].sourceSize.width=24
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_rejects_incompatible_footprints",not ok and code=="incompatible_footprint")
    state.jobs.active[2].sourceSize.width=20
    base.world.spawnProgress=0.5
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_rejects_still_unloading_support",not ok and code=="out_of_range")
    base.world.spawnProgress=1
    request.expectedRevision=1
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_rejects_stale_storage_revision",not ok and code=="stale_revision")
    request.expectedRevision=0
    top.wrapped,base.wrapped=false,false
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_commits_original_stock_two_high",ok and code=="stack" and top.location=="stacked"
        and top.storage.supportPalletId==base.id and top.world.x==base.world.x and top.world.y==base.world.y
        and top.paper==topPaper and base.paper==basePaper and top.remainingSheets==473 and base.remainingSheets==800
        and not top.wrapped and not base.wrapped and not lift.carriedPalletId and state.storage.revision==1 and Pallets.validate(state))
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_stack_duplicate_is_exactly_once",ok and code=="replayed" and state.storage.revision==1)
    check("warehouse_stack_base_not_offered_as_floor_pickup",Gameplay.candidate(state)==nil)
    lift.forkHeight,lift.targetForkHeight=0,0
    ok,code=Gameplay.command(player,state,{kind="pickup",palletId=base.id},cx)
    check("warehouse_stack_cannot_remove_support_with_pickup",not ok and code=="supporting_pallet" and base.location=="warehouse")
    candidate=Gameplay.stackCandidate(state)
    check("warehouse_stack_empty_forklift_targets_existing_top",candidate and candidate.kind=="unstack"
        and candidate.palletId==top.id and candidate.supportPalletId==base.id)
    local take={kind="unstack",requestId="WORLD-UNSTACK-1",expectedRevision=1,vehicle="forklift",palletId=top.id,supportPalletId=base.id}
    ok,code=Gameplay.command(player,state,take,cx)
    check("warehouse_unstack_requires_full_height",not ok and code=="wrong_fork_height")
    lift.forkHeight,lift.targetForkHeight=1,1
    ok,code=Gameplay.command(player,state,take,cx)
    check("warehouse_unstack_returns_same_pallet_and_preserves_support",ok and code=="unstack"
        and top.location=="on_forklift" and top.storage==nil and lift.carriedPalletId==top.id
        and top.world.x==lift.x and top.world.direction==lift.direction and base.location=="warehouse"
        and top.paper==topPaper and base.paper==basePaper and top.remainingSheets==473 and base.remainingSheets==800
        and not Storage.isSupporting(state,base.id) and Pallets.validate(state) and state.storage.revision==2)
    ok,code=Gameplay.command(player,state,take,cx)
    check("warehouse_unstack_replays_without_duplication",ok and code=="replayed" and state.storage.revision==2)
    local conflicting={kind="stack",requestId="WORLD-UNSTACK-1",expectedRevision=1,vehicle="forklift",palletId=top.id,supportPalletId=base.id}
    ok,code=Gameplay.command(player,state,conflicting,cx)
    check("warehouse_stack_changed_replay_is_refused",not ok and code=="request_conflict")
end
function Test.run(_,check)
    local oldWarehouse=Config.warehouse
    Config.warehouse={enabled=true}
    local state,player,cx=fresh()
    check("warehouse_live_paid_forklift_spawns_once_at_registered_point",state.forklift.owned
        and state.forklift.x==Layout.forkliftSpawn().x and state.forklift.y==Layout.forkliftSpawn().y)
    state.forklift.x=470
    Gameplay.update(0,state,cx)
    check("warehouse_live_delivery_does_not_respawn_existing_vehicle",state.forklift.x==470)
    player.x,player.y=950,90
    local ok,code=Gameplay.command(player,state,{kind="operate"},cx)
    check("warehouse_live_cannot_mount_forklift_remotely",not ok and code=="out_of_range" and not state.forklift.operating)
    player.x,player.y=state.forklift.x+60,state.forklift.y
    ok=Gameplay.command(player,state,{kind="operate"},cx)
    check("warehouse_live_operate_places_authenticated_worker_in_vehicle",ok and state.forklift.operatorPlayerId==1
        and player.x==state.forklift.x and player.y==state.forklift.y)
    local p=pallet(state)
    local sourcePaper=p.paper
    check("warehouse_live_floor_candidate_is_real_reachable_stock",Gameplay.candidate(state)==p.id)
    state.testObstacle={x=p.world.x,y=p.world.y}
    ok,code=Gameplay.command(player,state,{kind="pickup",palletId=p.id},cx)
    check("warehouse_live_pickup_checks_fresh_world_clearance",not ok and code=="blocked" and p.location=="warehouse")
    state.testObstacle=nil
    ok,code=Gameplay.command(player,state,{kind="pickup",palletId=p.id},cx)
    check("warehouse_live_pickup_transfers_original_pallet_without_copy",ok and p.location=="on_forklift"
        and state.forklift.carriedPalletId==p.id and p.paper==sourcePaper and p.remainingSheets==473 and p.wrapped)
    local x,y=state.forklift.x,state.forklift.y
    Gameplay.move(player,0.1,-1,0,state,cx)
    check("warehouse_live_loaded_forklift_must_raise_to_travel",state.forklift.x==x and state.forklift.y==y)
    Gameplay.command(player,state,{kind="set_height",height=0.08},cx)
    Gameplay.update(0.3,state,cx)
    Gameplay.move(player,0.1,-1,0,state,cx)
    check("warehouse_live_host_drive_moves_vehicle_operator_and_same_stock",state.forklift.x<x
        and player.x==state.forklift.x and p.world.x==state.forklift.x and p.location=="on_forklift")
    x=state.forklift.x
    Gameplay.move(player,0.1,1,0,state,cx,true)
    check("warehouse_live_client_pose_attachment_cannot_move_authoritative_vehicle",state.forklift.x==x and p.world.x==x)
    Gameplay.move(player,0.1,0,0,state,cx)
    ok,code=Gameplay.command(player,state,{kind="drop"},cx)
    check("warehouse_live_floor_drop_requires_lowered_forks",not ok and code=="lower_forks_first" and p.location=="on_forklift")
    Gameplay.command(player,state,{kind="set_height",height=0},cx)
    Gameplay.update(0.3,state,cx)
    ok=Gameplay.command(player,state,{kind="drop"},cx)
    check("warehouse_live_drop_preserves_stock_and_clears_vehicle_custody",ok and p.location=="warehouse"
        and not state.forklift.carriedPalletId and p.paper==sourcePaper and p.remainingSheets==473 and Pallets.validate(state))
    ok=Gameplay.command(player,state,{kind="pickup",palletId=p.id},cx)
    check("warehouse_live_can_pick_up_previously_dropped_pallet",ok and p.location=="on_forklift")
    rack(state)
    state.forklift.x,state.forklift.y,state.forklift.direction=330,510,"west"
    player.x,player.y=330,510
    require("src.forklift_cargo").sync(state,Config.forklift)
    local rc=Gameplay.rackContext(player,state,"front_left-rack",cx)
    check("warehouse_live_rack_context_uses_physical_vehicle_and_approach",rc.vehicle=="forklift" and rc.near and rc.aligned and rc.clear)
    local request={kind="store",requestId="LIVE-STORE",expectedRevision=0,vehicle="forklift",palletId=p.id,rackId="front_left-rack",row=2,column=5}
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_live_upper_shelf_requires_actual_full_fork_height",not ok and code=="wrong_fork_height" and p.location=="on_forklift")
    Gameplay.command(player,state,{kind="set_height",height=1},cx)
    Gameplay.update(3,state,cx)
    ok=Gameplay.command(player,state,request,cx)
    check("warehouse_live_store_upper_row_moves_same_pallet_into_selected_slot",ok and p.location=="rack"
        and p.storage.row==2 and p.storage.column==5 and not state.forklift.carriedPalletId and p.world==nil)
    ok,code=Gameplay.command(player,state,request,cx)
    check("warehouse_live_duplicate_store_replays_without_second_transfer",ok and code=="replayed" and state.storage.revision==1)
    local retrieve={kind="retrieve",requestId="LIVE-RETRIEVE",expectedRevision=1,vehicle="forklift",palletId=p.id,rackId="front_left-rack",row=2,column=5}
    state.forklift.direction="east"
    ok,code=Gameplay.command(player,state,retrieve,cx)
    check("warehouse_live_shelf_transfer_checks_current_heading",not ok and code=="not_aligned" and p.location=="rack")
    state.forklift.direction="west"
    ok=Gameplay.command(player,state,retrieve,cx)
    check("warehouse_live_retrieve_upper_row_restores_original_cargo",ok and p.location=="on_forklift"
        and state.forklift.carriedPalletId==p.id and p.paper==sourcePaper and p.wrapped and p.remainingSheets==473)
    local stranger={id=2,x=state.forklift.x,y=state.forklift.y}
    ok,code=Gameplay.command(stranger,state,{kind="set_height",height=0},cx)
    check("warehouse_live_other_worker_cannot_control_occupied_forklift",not ok and code=="not_owner" and state.forklift.targetForkHeight==1)
    Gameplay.command(player,state,{kind="set_height",height=0},cx)
    Gameplay.update(3,state,cx)
    local seatX,seatY=player.x,player.y
    local noExit=context(false)
    noExit.obstacles=function()return {{x=seatX,y=seatY,radius=1000}} end
    ok=Gameplay.command(player,state,{kind="release"},noExit)
    check("warehouse_live_release_requires_clear_standing_position",not ok and state.forklift.operating and player.x==seatX and player.y==seatY)
    ok=Gameplay.command(player,state,{kind="release"},cx)
    check("warehouse_live_release_exits_without_abandoning_loaded_stock",ok and not state.forklift.operating
        and (player.x~=seatX or player.y~=seatY) and p.location=="on_forklift" and state.forklift.carriedPalletId==p.id)

    local crowded,crowdedPlayer=fresh()
    crowded.forklift.x,crowded.forklift.y=500,400
    crowdedPlayer.x,crowdedPlayer.y=500,400
    assert(Gameplay.command(crowdedPlayer,crowded,{kind="operate"},context()))
    local blockedOffsets={{72,0},{-72,0},{0,48},{0,-48},{64,48},{-64,48},{64,-48},{-64,-48}}
    local crowdedContext={assets=assets(),obstacles=function()
        local result={Forklift.obstacle(crowded,Config.forklift)}
        for _,offset in ipairs(blockedOffsets) do
            result[#result+1]={x=500+offset[1],y=400+offset[2],radius=30}
        end
        return result
    end}
    ok=Gameplay.command(crowdedPlayer,crowded,{kind="release"},crowdedContext)
    check("warehouse_live_release_searches_beyond_blocked_side_exits",ok
        and not crowded.forklift.operating
        and (crowdedPlayer.x-500)^2+(crowdedPlayer.y-400)^2>=80^2
        and Navigation.isWalkable(Gameplay.assets(crowdedContext.assets,crowded),
            crowdedPlayer.x,crowdedPlayer.y,crowdedContext.obstacles()))

    local loaded,loadedPlayer,loadedContext=fresh()
    loaded.forklift.x,loaded.forklift.y=500,400
    loadedPlayer.x,loadedPlayer.y=500,400
    assert(Gameplay.command(loadedPlayer,loaded,{kind="operate"},loadedContext))
    loaded.forklift.direction="east"
    local carried=pallet(loaded)
    assert(Gameplay.command(loadedPlayer,loaded,{kind="pickup",palletId=carried.id},loadedContext))
    local forkX,forkY=Forklift.dropPosition(loaded,Config.forklift)
    local exit
    ok,code,exit=Gameplay.forceRelease(loadedPlayer,loaded,loadedContext)
    check("warehouse_live_loaded_exit_avoids_fork_tips_and_stays_visible",ok and exit
        and loadedPlayer.y>loaded.forklift.y and loadedPlayer.x<loaded.forklift.x
        and (loadedPlayer.x-forkX)^2+(loadedPlayer.y-forkY)^2>64^2
        and carried.location=="on_forklift" and loaded.forklift.carriedPalletId==carried.id)

    local locked=State.new()
    local wrapped=Gameplay.assets(assets(false),locked)
    check("warehouse_live_locked_black_expansion_is_not_walkable",not Navigation.isWalkable(wrapped,60,580,{}))
    locked.money=20000;rack(locked)
    check("warehouse_live_completed_extension_joins_existing_navigation",Navigation.isWalkable(wrapped,60,580,{})
        and not Navigation.isWalkable(wrapped,900,580,{}))
    local existingCore=Gameplay.assets(assets(),State.new())
    check("warehouse_live_expansion_seam_never_erases_existing_core_walkmask",
        Navigation.isWalkable(existingCore,855,450,{}) and Navigation.isWalkable(existingCore,861,450,{}))
    local blocked=State.new();blocked.money=10000
    Upgrades.purchaseForklift(blocked,"BLOCKED-DELIVERY",0)
    Gameplay.update(0,blocked,context(false))
    check("warehouse_live_blocked_delivery_never_spawns_vehicle_inside_collision",not blocked.forklift.owned and blocked.warehouse.forkliftOwned)
    stackTests(check)
    Config.warehouse=oldWarehouse
end
return Test
