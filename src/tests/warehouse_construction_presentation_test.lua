local Presentation=require("src.warehouse_construction_presentation")
local Renderer=require("src.warehouse_renderer")
local Test={}
local function fixture(stage)
    local project={id="WUP-0001",bayId="front_left",optionId="storage",phase="building",stage=stage}
    return {warehouse={activeProjectId=project.id,projects={project},bays={
        front_left={status="building",optionId="storage",projectId=project.id},
        front_right={status="locked"}}}},project
end
local function registeredCatalog()
    local result={front_left={}}
    for stage=1,4 do result.front_left[stage]={path="stage-"..stage..".png",stage=stage,bayId="front_left",
        optionId="storage",approved=false,includesFloor=true,registration={textureWidth=1000,textureHeight=1000,
            source={x=0,y=0,width=1000,height=1000},groundAnchor={x=0,y=1000},
            worldX=8,worldY=647,scale=0.371,depthY=647}} end
    return result
end
function Test.run(_,check)
    local catalog=Presentation.reviewCatalog()
    local previousPath
    for stage=1,4 do
        local entry=catalog.front_left[stage]
        check("construction_sprite_catalog_stage_"..stage,entry and entry.stage==stage
            and entry.path:match("left%-storage%-stage%-"..stage.."%.png$") and entry.path~=previousPath
            and entry.approved==false)
        previousPath=entry.path
    end
    catalog.front_left[1].path="changed.png"
    check("construction_sprite_catalog_is_immutable_copy",Presentation.reviewCatalog().front_left[1].path~=catalog.front_left[1].path)
    catalog=registeredCatalog()
    local options={review=true,catalog=catalog}
    for stage=1,4 do
        local state=fixture(stage)
        local plan=Presentation.plan(state,"front_left",options)
        check("construction_sprite_exact_stage_"..stage,plan and plan.stage==stage and plan.path=="stage-"..stage..".png")
    end
    local state,project=fixture(2)
    local plan=Presentation.plan(state,"front_left",options)
    check("construction_sprite_uniform_scale_preserves_footprint",plan.x==8 and plan.y==647 and plan.scale==0.371
        and plan.depthY==647 and plan.originY==1000)
    plan.source.width=2
    check("construction_sprite_plan_is_detached",Presentation.plan(state,"front_left",options).source.width==1000)
    local noReview,code=Presentation.plan(state,"front_left",{catalog=catalog})
    check("construction_sprite_draft_art_needs_explicit_review",not noReview and code=="art_not_approved")
    project.pausedAtHours=0
    plan=Presentation.plan(state,"front_left",options)
    check("construction_sprite_pause_keeps_same_visible_progress",plan and plan.paused and plan.stage==2 and project.stage==2)
    for _,phase in ipairs({"queued","awaiting_notice","awaiting_arrival","complete"}) do
        project.phase=phase
        check("construction_sprite_no_art_for_"..phase,not Presentation.plan(state,"front_left",options))
    end
    project.phase="building"
    state.warehouse.activeProjectId="WUP-0002"
    check("construction_sprite_stale_project_cannot_show_progress",not Presentation.plan(state,"front_left",options))
    state.warehouse.activeProjectId=project.id;project.stage=5
    check("construction_sprite_unknown_stage_is_not_clamped_into_fake_progress",not Presentation.plan(state,"front_left",options))
    project.stage=2;catalog.front_left[2].stage=3
    check("construction_sprite_wrong_catalog_stage_is_rejected",not Presentation.plan(state,"front_left",options))
    catalog.front_left[2].stage=2
    local r=catalog.front_left[2].registration
    r.source.width=1001
    check("construction_sprite_out_of_bounds_crop_is_rejected",not Presentation.plan(state,"front_left",options))
    r.source.width=1000;r.scale=0/0
    check("construction_sprite_invalid_scale_is_rejected",not Presentation.plan(state,"front_left",options))
    r.scale=0.371
    local drawn=0
    local primitives=0
    local released,pushed,popped=false,false,false
    local function forbidden() primitives=primitives+1;error("Procedural construction geometry is forbidden") end
    local graphics={polygon=forbidden,line=forbidden,rectangle=forbidden,ellipse=forbidden,circle=forbidden,
        newQuad=function() return {release=function() released=true end} end,
        push=function() pushed=true end,pop=function() popped=true end,setColor=function() end,
        draw=function() drawn=drawn+1 end}
    local function image() return {getDimensions=function() return 1000,1000 end} end
    local okay=Presentation.draw(state,"front_left",image,options,graphics)
    check("construction_sprite_environment_draw_is_image_only",okay and drawn==1 and primitives==0)
    check("construction_sprite_draw_releases_quad_and_restores_state",released and pushed and popped)
    local oldDrawn=drawn
    okay,code=Presentation.draw(state,"front_left",function() return nil end,options,graphics)
    check("construction_sprite_missing_art_is_reported_without_fake_geometry",not okay and code=="image_unavailable"
        and drawn==oldDrawn and primitives==0)
    okay,code=Presentation.draw(state,"front_left",function() error("missing source") end,options,graphics)
    check("construction_sprite_image_loader_failure_is_safe",not okay and code=="image_unavailable" and primitives==0)
    okay,code=Presentation.draw(state,"front_left",function()
        return {getDimensions=function() return 999,1000 end} end,options,graphics)
    check("construction_sprite_image_dimensions_are_verified",not okay and code=="image_dimensions" and drawn==oldDrawn)
    graphics.draw=function() error("driver failure") end;released=false;popped=false
    okay=Presentation.draw(state,"front_left",image,options,graphics)
    check("construction_sprite_draw_failure_restores_graphics",not okay and released and popped and primitives==0)
    local actors={}
    Renderer.addActors(actors,{},state)
    check("construction_sprite_whole_module_uses_front_ground_depth",#actors==1 and actors[1].y==647)
    local okayFloor=pcall(Renderer.drawFloors,{get=function() return nil end},state)
    check("construction_sprite_missing_floor_image_has_no_procedural_fallback",okayFloor)
end
return Test
