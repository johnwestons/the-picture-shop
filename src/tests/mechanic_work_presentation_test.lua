local Presentation=require("src.mechanic_work_presentation")
local Construction=require("src.warehouse_construction")
local State=require("src.state")
local Schema=require("src.save_schema")
local Upgrades=require("src.warehouse_upgrades")
local Test={}
local function actor(stage)
    local worker={phase="working",moving=false,x=260,y=505,projectId="WUP-0001",bayId="front_left",
        workStage=stage,workTime=0}
    local project={id=worker.projectId,bayId=worker.bayId,phase="building",stage=stage}
    return worker,{warehouse={activeProjectId=worker.projectId,projects={project}}},project
end
local function fakeSheet()
    return {path="test.png",width=100,height=100,bodyReferenceHeight=80,approved=false,fps=4,
        frames={{source={x=0,y=0,width=50,height=100},footAnchor={x=25,y=90}},
            {source={x=50,y=0,width=50,height=100},footAnchor={x=25,y=90}}},sequence={1,2}}
end
function Test.run(context,check)
    local worker,state,project=actor(1)
    local catalog=Presentation.reviewCatalog()
    for stage,tool in ipairs({"concrete","hammer","drill","paint"}) do
        local toolWorker,toolState=actor(stage)
        local seen={}
        local complete=Presentation.validateSheet(catalog[tool]) and catalog[tool].usable~=false
        for pose=1,4 do
            toolWorker.workTime=(pose-1)/4
            local current=Presentation.plan(toolWorker,toolState,{review=true})
            complete=complete and current and current.tool==tool and not seen[current.frameIndex]
            if current then seen[current.frameIndex]=true end
        end
        check("mechanic_work_"..tool.."_has_four_distinct_registered_phases",complete)
    end
    check("mechanic_work_source_registration_is_review_only",catalog.concrete.approved==false
        and catalog.hammer.approved==false and catalog.drill.approved==false and catalog.paint.approved==false)
    check("mechanic_work_concrete_has_individual_source_registrations",Presentation.validateSheet(catalog.concrete)
        and #catalog.concrete.frames>=2 and catalog.concrete.frames[1].footAnchor
        and catalog.concrete.frames[2].source.x~=catalog.concrete.frames[1].source.x)
    local blocked,code=Presentation.plan(worker,state)
    check("mechanic_work_unapproved_art_requires_explicit_review",not blocked and code=="art_not_approved")
    local plan=Presentation.plan(worker,state,{review=true})
    check("mechanic_work_body_scale_excludes_tool_height",plan
        and math.abs(plan.scale*catalog.concrete.bodyReferenceHeight-76.8)<0.000001)
    local first=plan.frameIndex
    worker.workTime=0.25
    check("mechanic_work_active_time_selects_real_second_pose",Presentation.plan(worker,state,{review=true}).frameIndex~=first)
    worker.workTime=0/0
    check("mechanic_work_nonfinite_visual_time_safely_resets",Presentation.plan(worker,state,{review=true}).sequenceIndex==1)
    worker.workTime=1;worker.workStage=2
    check("mechanic_work_stage_change_starts_neutral_pose",Presentation.plan(worker,state,{review=true}).sequenceIndex==1)
    for _,phase in ipairs({"arriving","leaving","exited","hidden"}) do
        worker.phase=phase
        check("mechanic_work_no_tool_loop_while_"..phase,not Presentation.plan(worker,state,{review=true}))
    end
    worker.phase="working";worker.moving=true
    check("mechanic_work_walking_never_uses_tool_loop",not Presentation.plan(worker,state,{review=true}))
    worker.moving=false;project.pausedAtHours=0
    check("mechanic_work_blocked_worksite_uses_idle_fallback",not Presentation.plan(worker,state,{review=true}))
    project.pausedAtHours=nil;state.warehouse.activeProjectId="WUP-0002"
    check("mechanic_work_stale_worker_cannot_borrow_new_project_stage",not Presentation.plan(worker,state,{review=true}))
    state.warehouse.activeProjectId=worker.projectId;project.phase="complete"
    check("mechanic_work_completion_stops_tools_immediately",not Presentation.plan(worker,state,{review=true}))
    project.phase="building";project.stage=2;worker.workStage=2
    local fake=fakeSheet()
    check("mechanic_work_stage2_selects_hammer_contract",Presentation.plan(worker,state,
        {review=true,catalog={hammer=fake}}).tool=="hammer")
    project.stage=3;worker.workStage=3
    check("mechanic_work_stage3_selects_drill_contract",Presentation.plan(worker,state,
        {review=true,catalog={drill=fake}}).tool=="drill")
    project.stage=4;worker.workStage=4
    check("mechanic_work_stage4_selects_paint_contract",Presentation.plan(worker,state,
        {review=true,catalog={paint=fake}}).tool=="paint")
    fake.frames[1].source.x=-1
    check("mechanic_work_invalid_crop_falls_back_without_drawing",not Presentation.plan(worker,state,
        {review=true,catalog={paint=fake}}))
    local drawWorker,drawState=actor(1)
    local drawn,drawCode=Presentation.draw(drawWorker,drawState,function() return nil end,{review=true})
    check("mechanic_work_missing_source_uses_safe_fallback",not drawn and drawCode=="image_unavailable")
    drawn,drawCode=Presentation.draw(drawWorker,drawState,function()
        return {getDimensions=function() return 1,1 end} end,{review=true})
    check("mechanic_work_source_size_mismatch_uses_safe_fallback",not drawn and drawCode=="image_dimensions")
    local released,pushed,popped=false,false,false
    local graphics={newQuad=function() return {release=function() released=true end} end,
        push=function() pushed=true end,pop=function() popped=true end,setColor=function() end,
        draw=function() error("intentional render refusal") end}
    drawn=Presentation.draw(drawWorker,drawState,function()
        return {getDimensions=function() return catalog.concrete.width,catalog.concrete.height end} end,
        {review=true},graphics)
    check("mechanic_work_draw_error_restores_graphics_and_releases_quad",not drawn and released and pushed and popped)
    local detached=Presentation.reviewCatalog();detached.concrete.frames[1].footAnchor.x=-99
    check("mechanic_work_review_catalog_is_detached",Presentation.reviewCatalog().concrete.frames[1].footAnchor.x>=0)
    drawState.warehouse.projects="bad snapshot"
    check("mechanic_work_malformed_project_list_cannot_crash_renderer",not Presentation.plan(drawWorker,drawState,{review=true}))
    local function options(now,clear) return {nowHours=now,canMove=function() return clear~=false end,
        workPoint=function() return 350,500 end} end
    local live=State.new();live.money=10000
    assert(Upgrades.purchase(live,"front_left","storage","WORK-CLOCK",0))
    Construction.update(live,0,options(0))
    for _=1,400 do Construction.update(live,0.1,options(2));if live.constructionWorker
        and live.constructionWorker.phase=="working" then break end end
    local builder=live.constructionWorker
    check("mechanic_work_clock_starts_only_after_physical_arrival",builder.phase=="working"
        and builder.workStage==1 and builder.workTime==0)
    Construction.update(live,10,options(2))
    check("mechanic_work_huge_dt_is_clamped",math.abs(builder.workTime-0.1)<0.000001)
    local before=builder.workTime
    Construction.update(live,-1,options(2))
    Construction.update(live,0/0,options(2))
    check("mechanic_work_invalid_dt_does_not_mutate_clock",builder.workTime==before)
    Construction.update(live,0.1,options(3,false))
    check("mechanic_work_blocked_clock_freezes",builder.workTime==before and live.warehouse.projects[1].pausedAtHours~=nil)
    Construction.update(live,0.1,options(3,true))
    check("mechanic_work_unblocked_clock_resumes",builder.workTime>before and live.warehouse.projects[1].pausedAtHours==nil)
    Construction.update(live,0.1,options(live.warehouse.projects[1].stageDueAtHours))
    check("mechanic_work_day_boundary_resets_tool_cycle",builder.workStage==2 and builder.workTime==0)
    builder.workTime=3599.98
    Construction.update(live,0.1,options(live.warehouse.projects[1].stageStartedAtHours))
    check("mechanic_work_clock_remains_bounded",builder.workTime<0.11 and Construction.valid(builder,live.warehouse))
    local snapshot=Schema.snapshot(live)
    local guest=State.new()
    check("mechanic_work_client_snapshot_preserves_authoritative_pose",State.applySharedSnapshot(guest,snapshot)
        and guest.constructionWorker.workTime==builder.workTime and guest.constructionWorker.workStage==builder.workStage)
    snapshot.constructionWorker.workTime=nil;snapshot.constructionWorker.workStage=nil
    check("mechanic_work_pre_clock_saves_remain_compatible",Schema.validState(snapshot))
    snapshot.constructionWorker.workTime=-1
    check("mechanic_work_invalid_saved_clock_is_rejected",not Schema.validState(snapshot))
    snapshot.constructionWorker.workTime=0;snapshot.constructionWorker.workStage=9
    check("mechanic_work_invalid_saved_stage_is_rejected",not Schema.validState(snapshot))
    snapshot.constructionWorker.workStage=1;snapshot.constructionWorker.workTime=math.huge
    check("mechanic_work_infinite_saved_clock_is_rejected",not Schema.validState(snapshot))
    local getImage=context and context.workImage
    local ownedImage
    if not getImage and love and love.graphics and love.filesystem.getInfo(catalog.concrete.path) then
        ownedImage=love.graphics.newImage(catalog.concrete.path)
        getImage=function() return ownedImage end
    end
    if getImage then
        local image=getImage(catalog.concrete.path)
        local width,height=image:getDimensions()
        check("mechanic_work_atlas_metadata_matches_registration",width==1254 and height==1254
            and width==catalog.concrete.width and height==catalog.concrete.height)
        local canvas=love.graphics.newCanvas(128,160)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,0)
        for stage,tool in ipairs({"concrete","hammer","drill","paint"}) do
            local actualWorker,actualState=actor(stage);actualWorker.x=64;actualWorker.y=140
            local okay=Presentation.draw(actualWorker,actualState,getImage,{review=true})
            check("mechanic_work_"..tool.."_renders_real_source_in_engine",okay)
        end
        love.graphics.pop();canvas:release()
        if ownedImage then ownedImage:release() end
    end
end
return Test
