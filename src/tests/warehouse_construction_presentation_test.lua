local Presentation=require("src.warehouse_construction_presentation")
local Renderer=require("src.warehouse_renderer")
local Test={}
local function fixture(stage,bayId,optionId)
    bayId,optionId=bayId or "front_left",optionId or "storage"
    local project={id="WUP-0001",bayId=bayId,optionId=optionId,phase="building",stage=stage}
    return {warehouse={activeProjectId=project.id,projects={project},bays={
        [bayId]={status="building",optionId=optionId,projectId=project.id},
        [bayId=="front_left" and "front_right" or "front_left"]={status="locked"}}}},project
end
local function copy(value)
    if type(value)~="table" then return value end
    local result={} for key,item in pairs(value) do result[key]=copy(item) end return result
end
local function testCatalog()
    local result={front_left={storage={}}}
    for stage=1,4 do result.front_left.storage[stage]={path="stage-"..stage..".png",stage=stage,
        bayId="front_left",optionId="storage",approved=false,includesFloor=true,
        registration={textureWidth=1000,textureHeight=1000,source={x=0,y=0,width=1000,height=1000},
            groundAnchor={x=0,y=1000},worldX=8,worldY=647,scale=0.371,depthY=647}} end
    return result
end
function Test.run(_,check)
    local catalog=Presentation.reviewCatalog()
    local allRegistered,allMappedToCorrectBay=true,true
    for _,bayId in ipairs({"front_left","front_right"}) do
        for _,optionId in ipairs({"floor","storage","breakroom"}) do
            local previousPath
            for stage=1,4 do
                local entry=catalog[bayId] and catalog[bayId][optionId] and catalog[bayId][optionId][stage]
                allRegistered=allRegistered and Presentation.validateEntry(entry)
                    and entry.stage==stage and entry.bayId==bayId and entry.optionId==optionId
                    and entry.approved==false and (optionId~="storage" or entry.path~=previousPath)
                if optionId=="floor" or optionId=="breakroom" then
                    allRegistered=allRegistered and entry.registration.source.width==768
                        and entry.registration.source.height==512
                end
                if entry then
                    local state=fixture(stage,bayId,optionId)
                    local plan=Presentation.plan(state,bayId,{review=true})
                    local registration=entry.registration
                    if plan then
                        local flip=plan.mirrorX and -1 or 1
                        local edgeA=plan.x+(0-plan.originX)*plan.scale*flip
                        local edgeB=plan.x+(plan.source.width-plan.originX)*plan.scale*flip
                        local minX,maxX=math.min(edgeA,edgeB),math.max(edgeA,edgeB)
                        local anchorX=plan.x+(registration.groundAnchor.x-plan.originX)*plan.scale*flip
                        allMappedToCorrectBay=allMappedToCorrectBay
                            and anchorX==registration.worldX
                            and (bayId=="front_left" and maxX<480 or bayId=="front_right" and minX>480)
                    else allMappedToCorrectBay=false end
                else allMappedToCorrectBay=false end
                previousPath=entry and entry.path
            end
        end
    end
    check("construction_sprite_catalog_registers_all_six_choices_and_stages",allRegistered)
    check("construction_sprite_mirror_maps_all_24_states_to_their_bay",allMappedToCorrectBay)
    catalog.front_left.storage[1].path="changed.png"
    check("construction_sprite_catalog_is_immutable_copy",
        Presentation.reviewCatalog().front_left.storage[1].path~="changed.png")

    local options={review=true,catalog=testCatalog()}
    for stage=1,4 do
        local state=fixture(stage)
        local plan=Presentation.plan(state,"front_left",options)
        check("construction_sprite_exact_storage_stage_"..stage,
            plan and plan.optionId=="storage" and plan.stage==stage and plan.path=="stage-"..stage..".png")
    end
    local state,project=fixture(2)
    local plan=Presentation.plan(state,"front_left",options)
    check("construction_sprite_uniform_scale_preserves_registered_footprint",plan.x==8 and plan.y==647
        and plan.scale==0.371 and plan.depthY==647 and plan.originY==1000)
    plan.source.width=2
    check("construction_sprite_plan_is_detached",Presentation.plan(state,"front_left",options).source.width==1000)
    local noReview,code=Presentation.plan(state,"front_left",{catalog=options.catalog})
    check("construction_sprite_draft_art_needs_explicit_review",not noReview and code=="art_not_approved")
    project.pausedAtHours=0
    plan=Presentation.plan(state,"front_left",options)
    check("construction_sprite_pause_keeps_same_visible_progress",plan and plan.paused and plan.stage==2)
    for _,phase in ipairs({"queued","awaiting_notice","awaiting_arrival","complete"}) do
        project.phase=phase
        check("construction_sprite_no_art_for_"..phase,not Presentation.plan(state,"front_left",options))
    end
    project.phase="building"
    project.stage=5
    check("construction_sprite_unknown_stage_is_not_clamped",not Presentation.plan(state,"front_left",options))
    project.stage=2
    options.catalog.front_left.storage[2].stage=3
    check("construction_sprite_wrong_catalog_stage_is_rejected",not Presentation.plan(state,"front_left",options))
    options.catalog.front_left.storage[2].stage=2
    local invalid=copy(options.catalog)
    invalid.front_left.storage[2].registration.source.width=1001
    check("construction_sprite_out_of_bounds_crop_is_rejected",
        not Presentation.plan(state,"front_left",{review=true,catalog=invalid}))
    invalid=copy(options.catalog);invalid.front_left.storage[2].registration.scale=0/0
    check("construction_sprite_invalid_scale_is_rejected",
        not Presentation.plan(state,"front_left",{review=true,catalog=invalid}))

    local rightState=fixture(3,"front_right","breakroom")
    local rightPlan=Presentation.plan(rightState,"front_right",{review=true})
    check("construction_sprite_breakroom_stage_is_registered_for_right_bay",rightPlan
        and rightPlan.mirrorX and rightPlan.stage==3 and rightPlan.optionId=="breakroom"
        and rightPlan.path:match("breakroom%-construction%-atlas%-v1%.png$")
        and rightPlan.source.x==0 and rightPlan.source.y==512
        and rightPlan.originX==730)
    local floorState=fixture(4,"front_left","floor")
    local floorPlan=Presentation.plan(floorState,"front_left",{review=true})
    check("construction_sprite_open_floor_stage_uses_floor_atlas",floorPlan and floorPlan.stage==4
        and floorPlan.includesFloor and floorPlan.source.x==768 and floorPlan.source.y==512
        and floorPlan.path:match("floor%-construction%-atlas%-v2%-clean%.png$"))

    local drawn,quadArgs,drawArgs=0,nil,nil
    local released,pushed,popped=false,false,false
    local graphics={newQuad=function(...)quadArgs={...};return {release=function()released=true end}end,
        push=function()pushed=true end,pop=function()popped=true end,setColor=function()end,
        draw=function(...)drawArgs={...};drawn=drawn+1 end}
    local image=function()return {getDimensions=function()return 1536,1024 end}end
    local okay=Presentation.draw(rightState,"front_right",image,{review=true},graphics)
    check("construction_atlas_crops_and_mirrors_native_quad",okay and drawn==1
        and quadArgs[1]==0 and quadArgs[2]==512 and quadArgs[3]==768 and quadArgs[4]==512
        and rightPlan.originX==730 and drawArgs[6]==-0.49 and drawArgs[3]==581
        and released and pushed and popped)
    local leftState=fixture(3,"front_left","breakroom")
    local leftPlan=Presentation.plan(leftState,"front_left",{review=true})
    local leftBounds={leftPlan.x-leftPlan.originX*leftPlan.scale,
        leftPlan.x+(leftPlan.source.width-leftPlan.originX)*leftPlan.scale}
    local rightBounds={rightPlan.x-(rightPlan.source.width-rightPlan.originX)*rightPlan.scale,
        rightPlan.x+rightPlan.originX*rightPlan.scale}
    check("construction_sprite_mirror_stays_inside_corresponding_bay",
        leftBounds[1]>=0 and leftBounds[2]<=480 and rightBounds[1]>=480 and rightBounds[2]<=960)
    okay,code=Presentation.draw(rightState,"front_right",function()return nil end,{review=true},graphics)
    check("construction_sprite_missing_art_is_reported_without_fake_geometry",
        not okay and code=="image_unavailable" and drawn==1)
    okay,code=Presentation.draw(rightState,"front_right",function()
        return {getDimensions=function()return 999,1000 end}end,{review=true},graphics)
    check("construction_sprite_image_dimensions_are_verified",not okay and code=="image_dimensions")
    local actors={}
    Renderer.addActors(actors,{},state)
    check("construction_sprite_whole_module_uses_front_ground_depth",#actors==1 and actors[1].y==647)
    local okayFloor=pcall(Renderer.drawFloors,{get=function()return nil end},state)
    check("construction_sprite_missing_floor_image_has_no_procedural_fallback",okayFloor)
end
return Test
