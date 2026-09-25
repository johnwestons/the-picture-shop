local Presentation=require("src.warehouse_rack_presentation")
local Test={}
local function fixture()
    local slots={{},{}}
    for row=1,2 do for column=1,5 do
        slots[row][column]={x=column*200,y=400+column*50-(row-1)*160,groundY=425+column*50}
    end end
    return {front_left={path="authored-world-rack.png",bayId="front_left",approved=false,
        registration={textureWidth=1536,textureHeight=1024,x=20,y=600,originX=0,originY=900,
            scale=0.25,depthY=626,slots=slots,frontPolygons={{100,200,120,200,120,600,100,600}}}}}
end
function Test.run(_,check)
    local function test(name,value) check("warehouse_rack_presentation_"..name,value) end
    local state={warehouse={bays={front_left={status="complete",optionId="storage"}}}}
    local catalog=fixture()
    test("authored_registration_valid",Presentation.validateEntry(catalog.front_left))
    local plan,reason=Presentation.plan(state,"front_left",{catalog=catalog})
    test("draft_art_requires_review",not plan and reason=="art_not_approved")
    plan=Presentation.plan(state,"front_left",{catalog=catalog,review=true})
    test("native_sprite_transform",plan and plan.scale==0.25 and plan.originY==900 and not plan.approved)
    for column=1,5 do
        local lower=Presentation.slotPoint(plan,1,column)
        local upper=Presentation.slotPoint(plan,2,column)
        test("two_levels_"..column,lower.x==upper.x and lower.groundY==upper.groundY
            and lower.y-upper.y==40 and lower.x==20+column*50)
    end
    test("slot_bounds",not Presentation.slotPoint(plan,0,1) and not Presentation.slotPoint(plan,1,6)
        and not Presentation.slotPoint(plan,1,1.5))
    local original=catalog.front_left.registration.slots[1][1].x
    plan.slots[1][1].x=0
    test("plan_detached_from_registration",catalog.front_left.registration.slots[1][1].x==original)
    catalog.front_left.path="assets/source/warehouse-expansion-v1/rack-front-2x5-approved.png"
    test("first_person_backdrop_forbidden",not Presentation.validateEntry(catalog.front_left))
    catalog=fixture();catalog.front_left.registration.slots[2][5]=nil
    test("incomplete_slot_registration_rejected",not Presentation.validateEntry(catalog.front_left))
    catalog=fixture();catalog.front_left.registration.slots[2][1].y=900
    test("inverted_upper_anchor_rejected",not Presentation.validateEntry(catalog.front_left))
    catalog=fixture();catalog.front_left.registration.scale=0/0
    test("nonfinite_scale_rejected",not Presentation.validateEntry(catalog.front_left))
    catalog=fixture();catalog.front_left.registration.frontPolygons[1][1]=-1
    test("out_of_texture_occlusion_rejected",not Presentation.validateEntry(catalog.front_left))
    catalog=fixture();state.warehouse.bays.front_left.status="building"
    test("construction_never_draws_finished_rack",not Presentation.plan(state,"front_left",{catalog=catalog,review=true}))
    state.warehouse.bays.front_left.status="complete"
    plan=Presentation.plan(state,"front_left",{catalog=catalog,review=true})
    local image={getDimensions=function()return 1536,1024 end}
    local calls={}
    local graphics={setColor=function()end,push=function()end,pop=function()end,
        setStencilTest=function()end,stencil=function(callback)callback()end,
        polygon=function(...)calls[#calls+1]={kind="mask",...}end,
        draw=function(...)calls[#calls+1]={kind="draw",...}end}
    test("native_back_draws",Presentation.drawBack(plan,function()return image end,graphics))
    test("back_uses_uniform_unrotated_sprite",calls[1][1]==image and calls[1][4]==0
        and calls[1][5]==0.25 and calls[1][6]==0.25)
    test("front_draws_authored_texture",Presentation.drawFront(plan,function()return image end,graphics)
        and calls[2].kind=="mask" and calls[3].kind=="draw" and calls[3][1]==image)
    test("missing_image_fails_explicitly",not Presentation.drawBack(plan,function()return nil end,graphics))
    test("wrong_dimensions_fail_explicitly",not Presentation.drawBack(plan,function()
        return {getDimensions=function()return 100,100 end}end,graphics))
    local Renderer=require("src.warehouse_renderer")
    local pallets,byId={},{}
    for column=1,5 do for row=1,2 do
        local pallet={id="WORLD-RACK-"..row.."-"..column,number=#pallets+1,location="rack",
            wrapped=row==2,remainingSheets=100+column,paper={marker=column},
            storage={rackId="front_left-rack",row=row,column=column}}
        pallets[#pallets+1]=pallet;byId[pallet.id]=pallet
    end end
    state.jobs={active={{id="WORLD-RACK-JOB",pallets=pallets}}}
    local originalPlan,originalBack,originalFront=Presentation.plan,Presentation.drawBack,Presentation.drawFront
    local sequence,draws={},{}
    Presentation.plan=function()return plan end
    Presentation.drawBack=function()sequence[#sequence+1]="back";return true end
    Presentation.drawFront=function()sequence[#sequence+1]="front";return true end
    local okay,why=pcall(function()
        local actors={}
        Renderer.addActors(actors,{},state,function(_,item)
            sequence[#sequence+1]="pallet";draws[#draws+1]=item
        end)
        test("one_authored_object_not_five_gui_panels",#actors==1)
        actors[1].draw()
    end)
    Presentation.plan,Presentation.drawBack,Presentation.drawFront=originalPlan,originalBack,originalFront
    if not okay then error(why) end
    local fallbackActors={}
    Renderer.addActors(fallbackActors,{},state)
    test("unregistered_art_keeps_playable_rack",#fallbackActors==5
        and Renderer.rackIssue("front_left")=="world_rack_not_registered")
    test("rear_then_ten_pallets_then_front",#sequence==12 and sequence[1]=="back" and sequence[12]=="front")
    local canonical,unchangedScale=true,true
    for _,item in ipairs(draws) do
        canonical=canonical and byId[item.pallet.id]==item.pallet and item.pallet.paper==byId[item.pallet.id].paper
        unchangedScale=unchangedScale and item.scale==nil and item.drawScale==nil
    end
    test("all_ten_pallets_remain_canonical",#draws==10 and canonical)
    test("world_pallet_scale_not_overridden",unchangedScale)
end
return Test
