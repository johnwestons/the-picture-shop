local State=require("src.state")
local Schema=require("src.save_schema")
local Upgrades=require("src.warehouse_upgrades")
local Construction=require("src.warehouse_construction")
local Config=require("src.config")
local Test={}
local function options(now,canMove)
    return {nowHours=now,canMove=canMove or function() return true end,
        workPoint=function(bay) return bay=="front_left" and 350 or 750,500 end}
end
local function fixture(two)
    local state=State.new();state.money=20000
    assert(Upgrades.purchase(state,"front_left","storage","BUILD-LEFT",0))
    if two then assert(Upgrades.purchase(state,"front_right","floor","BUILD-RIGHT",0)) end
    return state
end
local function walk(state,now,phase,canMove)
    for _=1,400 do
        Construction.update(state,0.1,options(now,canMove))
        if (not state.constructionWorker and phase=="gone")
            or (state.constructionWorker and state.constructionWorker.phase==phase) then return true end
    end
    return false
end
function Test.run(_,check)
    local state=fixture(true)
    Construction.update(state,0.1,options(0))
    check("construction_live_calls_before_worker_spawn",state.workPhone.incoming
        and state.workPhone.incoming.kind=="construction_notice" and state.constructionWorker==nil)
    Construction.update(state,0.1,options(1.99))
    check("construction_live_waits_for_scheduled_arrival",state.constructionWorker==nil)
    Construction.update(state,0,options(2))
    local worker=Construction.worker(state)
    check("construction_live_spawns_at_actual_glass_entrance",worker
        and worker.x==Config.customer.route[1].x and worker.y==Config.customer.route[1].y
        and worker.phase=="arriving" and worker.animationDistance==0)
    local startX,startY=worker.x,worker.y
    Construction.update(state,0.1,options(2))
    check("construction_live_animates_actual_collision_resolved_distance",worker.moving
        and worker.animationDistance>0 and worker.animationDistance<8
        and math.abs(worker.animationDistance-math.sqrt((worker.x-startX)^2+(worker.y-startY)^2))<0.00001
        and state.warehouse.projects[1].stage==0)
    local distance,x,y=worker.animationDistance,worker.x,worker.y
    Construction.update(state,0.1,options(20,function() return false end))
    check("construction_live_blocked_actor_never_advances_gait_or_work",worker.x==x and worker.y==y
        and worker.animationDistance==distance and not worker.moving and state.warehouse.projects[1].stage==0)
    local snapshot=Schema.snapshot(state)
    local restored=State.new()
    local loaded=State.applySave(restored,{slot=1,state=snapshot})
    check("construction_live_route_pose_survives_save_reload",loaded and Schema.validState(snapshot)
        and restored.constructionWorker.x==x and restored.constructionWorker.y==y
        and restored.constructionWorker.animationDistance==distance)
    state=restored
    check("construction_live_walks_to_work_point_before_foundation",walk(state,20,"working")
        and state.warehouse.projects[1].phase=="building" and state.warehouse.projects[1].stage==1
        and state.warehouse.projects[1].workerArrivedAtHours==20
        and state.constructionWorker.x==350 and state.constructionWorker.y==500)
    local stationary=state.constructionWorker.animationDistance
    for stage=1,4 do
        Construction.update(state,0.1,options(20+stage*24-0.001))
        check("construction_live_stage_"..stage.."_requires_full_day",state.warehouse.projects[1].stage==stage
            and state.warehouse.projects[1].phase=="building" and not state.storage.racks["front_left-rack"])
        Construction.update(state,0.1,options(20+stage*24))
        check("construction_live_stage_"..stage.."_advances_at_day_boundary",state.warehouse.projects[1].stage==math.min(4,stage+1)
            and (stage<4 or state.warehouse.projects[1].phase=="complete"))
    end
    local rack=state.storage.racks["front_left-rack"]
    check("construction_live_completion_registers_one_usable_rack",rack and rack.bayId=="front_left"
        and state.warehouse.projects[2].phase=="queued" and state.constructionWorker.phase=="leaving"
        and state.constructionWorker.animationDistance>=stationary)
    Construction.update(state,0,options(116))
    check("construction_live_registry_is_idempotent",state.storage.racks["front_left-rack"]==rack
        and state.storage.revision==0 and Schema.validState(Schema.snapshot(state)))
    local secondReady=false
    for _=1,400 do
        Construction.update(state,0.1,options(116))
        if state.warehouse.projects[2].phase=="awaiting_arrival" then secondReady=true;break end
    end
    check("construction_live_departure_releases_next_project_only_at_front_door",secondReady
        and state.warehouse.projects[1].workerReleasedAtHours==116 and state.constructionWorker==nil
        and state.workPhone.incoming.projectId=="WUP-0002")

    local detoured=fixture()
    local function obstacle(px,py) return not (px>470 and px<540 and py>375 and py<450) end
    Construction.update(detoured,0,options(0,obstacle))
    check("construction_live_routes_around_fixed_collision_obstacle",walk(detoured,2,"working",obstacle)
        and detoured.constructionWorker.animationDistance>430)
    local distanceBefore=detoured.constructionWorker.animationDistance
    Construction.update(detoured,0.1,options(8))
    Construction.update(detoured,0.1,options(10,function() return false end))
    Construction.update(detoured,0.1,options(200,function() return false end))
    check("construction_live_blocked_worksite_pauses_day_progress",detoured.warehouse.projects[1].stage==1
        and detoured.warehouse.projects[1].pausedAtHours~=nil
        and detoured.constructionWorker.animationDistance==distanceBefore)
    Construction.update(detoured,0.1,options(200))
    check("construction_live_unblocked_worksite_resumes_remaining_hours",detoured.warehouse.projects[1].pausedAtHours==nil
        and detoured.warehouse.projects[1].stageDueAtHours==218)

    local fresh=fixture()
    Construction.update(fresh,0,options(0))
    Construction.update(fresh,0.1,options(2,function() return false end))
    check("construction_live_blocked_entrance_cannot_spawn_or_start",fresh.constructionWorker==nil and fresh.warehouse.projects[1].stage==0)
    local bad=Schema.copy(detoured)
    bad.constructionWorker.projectId="WUP-9999"
    local before=Schema.snapshot(detoured)
    check("construction_live_rejects_forged_worker_project_atomically",not State.applySave(detoured,{state=bad})
        and detoured.constructionWorker.projectId==before.constructionWorker.projectId)
    local guest=State.new()
    check("construction_live_shared_snapshot_carries_exact_worker_pose",State.applySharedSnapshot(guest,Schema.snapshot(detoured))
        and guest.constructionWorker.x==detoured.constructionWorker.x
        and guest.constructionWorker.phase==detoured.constructionWorker.phase)
    local phaseWorker={animationDistance=0,idleTime=0,moving=true}
    for n=0,7 do phaseWorker.animationDistance=n*13
        check("construction_live_gait_frame_"..(n+1),Construction.frame(phaseWorker)==n+1) end
end
return Test
