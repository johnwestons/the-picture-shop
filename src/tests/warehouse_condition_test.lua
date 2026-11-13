local Condition=require("src.warehouse_condition")
local State=require("src.state")
local Schema=require("src.save_schema")
local Calendar=require("src.business_calendar")
local Footprints=require("src.warehouse_footprints")
local Protocol=require("src.net.protocol")
local Service=require("src.job_service")
local Guide=require("src.story_restoration_guide")
local Notices=require("src.notifications")
local WorkPhone=require("src.work_phone")
local Rooms=require("src.shop_rooms")
local Interaction=require("src.interaction")
local Test={}
function Test.run(context,check)
    local quick=State.new()
    check("warehouse_condition_quick_start_remains_operational",
        Condition.valid(quick.warehouse.condition) and Condition.complete(quick)
        and Condition.powered(quick) and Condition.waterReady(quick)
        and Condition.variant(quick)=="stage4On"
        and not quick.inventory.stock.maintenance_kit)
    local storyPayload=assert(context.save.newGame(1,{startMode="story"}))
    check("warehouse_condition_new_story_has_grandpa_repair_allowance",
        storyPayload.state.money==180+Condition.GRANDPA_ALLOWANCE
            and storyPayload.state.inventory.stock.maintenance_kit==nil
            and storyPayload.state.warehouse.condition.grandpaAllowanceGranted)
    local storyCutter,storyWrapper=storyPayload.state.machines.items[1],storyPayload.state.machines.items[2]
    check("warehouse_condition_story_machines_need_real_service",
        storyCutter.modelId=="polar_115" and storyCutter.variables.bladeSharpness<75
            and storyWrapper.modelId=="skid_wrapper" and storyWrapper.condition<80
            and Schema.validState(storyPayload.state))
    local olderStory=Schema.copy(storyPayload)
    olderStory.state.money=180
    olderStory.state.warehouse.condition.grandpaAllowanceGranted=nil
    local restoredStory=State.new()
    local restored=State.applySave(restoredStory,olderStory)
    check("warehouse_condition_older_story_receives_allowance_once",
        restored and restoredStory.money==180+Condition.GRANDPA_ALLOWANCE
            and restoredStory.warehouse.condition.grandpaAllowanceGranted
            and not Condition.ensureGrandpaAllowance(restoredStory)
            and restoredStory.money==180+Condition.GRANDPA_ALLOWANCE
            and restoredStory.inventory.stock.maintenance_kit==nil)
    local purchaseState=State.new()
    purchaseState.warehouse.condition=Condition.new("story",19)
    Condition.ensureGrandpaAllowance(purchaseState)
    local buyer={sceneId="warehouse",x=218,y=185}
    local powerPaid=Condition.perform(purchaseState,buyer,"call_power")
    local waterPaid=Condition.perform(purchaseState,buyer,"call_water")
    local breakerFixed=Condition.perform(purchaseState,buyer,"repair_breaker")
    local Procurement=require("src.procurement")
    local firstKit,firstOrder=Procurement.buy(purchaseState,4,1,"computer")
    local secondKit,secondOrder=Procurement.buy(purchaseState,4,1,"computer")
    check("warehouse_condition_allowance_funds_utilities_and_two_purchased_kits",
        powerPaid and waterPaid and breakerFixed and firstKit and secondKit
            and purchaseState.money==180+Condition.GRANDPA_ALLOWANCE-95-350
            and #purchaseState.procurement.orders==2
            and purchaseState.inventory.stock.maintenance_kit==nil)
    local Config=require("src.config")
    local firstDelivered=firstKit and Procurement.unload(purchaseState,firstOrder.id,firstOrder.pallets[1].id,
        Config.palletLogistics.spawnPoints,Config.palletLogistics.unloadOrigin)
    local secondDelivered=secondKit and Procurement.unload(purchaseState,secondOrder.id,secondOrder.pallets[1].id,
        Config.palletLogistics.spawnPoints,Config.palletLogistics.unloadOrigin)
    local fleet=require("src.machine_fleet")
    local serviced={}
    if firstDelivered and secondDelivered then
        for _,model in ipairs({"polar_115","skid_wrapper"}) do
            local machine=fleet.installed(purchaseState,model)
            local scores={}
            for _,task in ipairs(fleet.maintenancePlan(purchaseState,machine.id).tasks) do
                scores[task.id]=1
            end
            serviced[model]=fleet.completeMaintenance(purchaseState,machine.id,scores)
        end
    end
    check("warehouse_condition_purchased_kits_can_service_both_machines",
        firstDelivered and secondDelivered and serviced.polar_115 and serviced.skid_wrapper
            and fleet.installed(purchaseState,"polar_115").maintenance.serviceCount==1
            and fleet.installed(purchaseState,"skid_wrapper").maintenance.serviceCount==1
            and purchaseState.inventory.stock.maintenance_kit==0 and purchaseState.money==155)
    local switched=Condition.perform(quick,{sceneId="warehouse",x=218,y=185},"lights_off")
    check("warehouse_condition_quick_light_switch_preserves_power",switched and not Condition.lit(quick)
        and Condition.powered(quick) and Condition.valid(quick.warehouse.condition)
        and Condition.variant(quick)=="stage4Off")
    local legacy=Schema.copy(quick)
    legacy.warehouse.condition=nil
    local normalized=require("src.warehouse_upgrades").normalize(legacy.warehouse)
    check("warehouse_condition_legacy_save_migrates_clean",
        normalized and Condition.valid(normalized.condition)
        and Condition.complete({warehouse=normalized}))
    local state=State.new()
    state.warehouse.condition=Condition.new("story",771)
    local c=state.warehouse.condition
    local conditionRenderer=require("src.warehouse_condition_renderer")
    local imageLoader=require("src.image_loader")
    local oldImageLoaderEnabled,oldImageLoaderLoad=imageLoader.enabled,imageLoader.load
    local baseWarehouse={kind="base-warehouse"}
    local rendererAssets={get=function(name) return name=="warehouse" and baseWarehouse end}
    conditionRenderer.clear()
    imageLoader.setEnabled(true)
    local closedPlate=conditionRenderer.image(state,rendererAssets)
    imageLoader.load=function() return nil,"pending" end
    c.powerConnected,c.breakerRepaired,c.lightsOn=true,true,true
    local pendingPlate=conditionRenderer.image(state,rendererAssets)
    check("warehouse_condition_pending_variant_does_not_reuse_old_plate",
        closedPlate~=baseWarehouse and pendingPlate==baseWarehouse and pendingPlate~=closedPlate)
    imageLoader.load=oldImageLoaderLoad
    imageLoader.setEnabled(oldImageLoaderEnabled)
    c.powerConnected,c.breakerRepaired,c.lightsOn=false,false,false
    conditionRenderer.clear()
    local overlay=love.graphics.newCanvas(960,678)
    local function overlayAlpha(x,y)
        love.graphics.push("all")
        love.graphics.setCanvas(overlay)
        love.graphics.clear(0,0,0,0)
        conditionRenderer.drawStatic(state)
        love.graphics.pop()
        local data=overlay:newImageData()
        local _,_,_,alpha=data:getPixel(x,y)
        data:release()
        return alpha
    end
    local firstSpill,secondSpill=Condition.anchors.puddle1,Condition.anchors.puddle2
    local standingWater,clearFloor=overlayAlpha(firstSpill.x,firstSpill.y),overlayAlpha(500,600)
    check("warehouse_condition_fixed_floor_renders_only_spills",
        overlayAlpha(150,383)<.005 and standingWater>.55 and clearFloor<.005,
        ("water=%.3f clear=%.3f"):format(standingWater,clearFloor))
    check("warehouse_condition_puddles_are_separate_and_visible_in_middle_floor",
        overlayAlpha(secondSpill.x,secondSpill.y)>.55
            and overlayAlpha(515,520)<.05
            and Rooms.walkable(firstSpill.x,firstSpill.y,"warehouse")
            and Rooms.walkable(secondSpill.x,secondSpill.y,"warehouse"),
        ("left=%.3f right=%.3f gap=%.3f walkable=%s/%s"):format(
            overlayAlpha(firstSpill.x,firstSpill.y),overlayAlpha(secondSpill.x,secondSpill.y),
            overlayAlpha(515,520),tostring(Rooms.walkable(firstSpill.x,firstSpill.y,"warehouse")),
            tostring(Rooms.walkable(secondSpill.x,secondSpill.y,"warehouse"))))
    local dryEdgeX=firstSpill.x+math.floor(firstSpill.visualRadiusX*.9)
    check("warehouse_condition_mop_hit_area_follows_visible_spill",
        overlayAlpha(dryEdgeX,firstSpill.y)<.005
            and not Condition.puddleAt(state,"puddle1",dryEdgeX,firstSpill.y))
    for _,model in ipairs({"polar_115","skid_wrapper"}) do
        local operable,reason=fleet.canOperate(state,model)
        check("warehouse_condition_"..model.."_cannot_run_without_power",
            not operable and reason:find("Reconnect power",1,true)~=nil)
    end
    check("warehouse_condition_closed_selects_crisp_stage_zero",Condition.variant(state)=="stage0Off")
    check("warehouse_condition_clients_wait_for_grand_opening",not Condition.openForBusiness(state)
        and Service.createNextOffer(state,1)==nil and Guide.nextStep(state)=="power")
    local queued=WorkPhone.queueCall(state,{kind="customer_order",caller="Early client"})
    local requested=Service.requestEstimateDetails(state,{status="offered",id="JOB-EARLY"},1)
    check("warehouse_condition_direct_client_channels_wait_for_opening",
        not queued and not requested and state.workPhone.incoming==nil)
    state.calendar.elapsed=state.calendar.secondsPerDay*9/24
    state.workPhone.nextCallAtHours=0
    WorkPhone.update(state,0)
    check("warehouse_condition_no_job_calls_before_opening",state.workPhone.incoming==nil)
    state.tutorial.enabled=true
    local feedback={context={state=state},dirty=false}
    function feedback:enqueue(kind,title,detail,body,key)
        return Notices.add(self.context.state,kind,title,detail,body,key)
    end
    local firstNotice=Guide.update(feedback)
    check("warehouse_condition_tutorial_guides_without_spam",firstNotice and not Guide.update(feedback)
        and Notices.findKey(state,"story-restoration:power")~=nil)
    local player={sceneId="warehouse",x=218,y=185}
    local landline=State.new()
    landline.warehouse.condition=Condition.new("story",772)
    local powerCall,powerCallState=WorkPhone.placeCall(landline,"power_company")
    WorkPhone.update(landline,1)
    local powerRestored=WorkPhone.respond(landline)
    check("warehouse_condition_wall_phone_reconnects_power_without_building_power",
        powerCall and powerCallState and powerCallState.direction=="outgoing"
            and powerRestored and Condition.of(landline).powerConnected
            and not Condition.powered(landline) and #landline.receipts.entries==1)
    WorkPhone.dismiss(landline)
    local waterCall,waterCallState=WorkPhone.placeCall(landline,"water_company")
    WorkPhone.update(landline,1)
    local waterRestored=WorkPhone.respond(landline)
    check("warehouse_condition_wall_phone_reconnects_water_by_call",
        waterCall and waterCallState and waterCallState.kind=="outgoing_water"
            and waterRestored and Condition.of(landline).waterConnected
            and #landline.receipts.entries==2
            and Schema.validState(Schema.snapshot(landline)))
    local okay,code=Condition.perform(state,player,"repair_breaker")
    check("warehouse_condition_breaker_requires_service",not okay and code=="no_service")
    local before=state.money
    okay=Condition.perform(state,player,"call_power")
    check("warehouse_condition_power_reconnect_pays_once",okay and c.powerConnected
        and math.abs(state.money-(before-Condition.POWER_FEE_CENTS/100))<.00001
        and #state.receipts.entries==1)
    before=state.money
    okay,code=Condition.perform(state,player,"call_power")
    check("warehouse_condition_replayed_call_does_not_charge",okay and code=="already_applied"
        and state.money==before and #state.receipts.entries==1)
    okay,code=Condition.perform(state,{sceneId="warehouse",x=500,y=500},"repair_breaker")
    check("warehouse_condition_remote_repair_rejected",not okay and code=="out_of_range")
    okay=Condition.perform(state,player,"repair_breaker")
    check("warehouse_condition_power_after_breaker_repair",okay and Condition.powered(state)
        and Condition.variant(state)=="stage0Off")
    check("warehouse_condition_guide_requires_switch_after_repair",Guide.nextStep(state)=="lights")
    local switchTarget=Rooms.targets(player,state).restoration
    check("warehouse_condition_breaker_has_direct_light_switch",
        switchTarget and switchTarget.restorationAction=="lights_on")
    okay=Condition.perform(state,player,"lights_on")
    check("warehouse_condition_lights_need_separate_switch",okay and Condition.lit(state)
        and Condition.variant(state)=="stage0On")
    for _,model in ipairs({"polar_115","skid_wrapper"}) do
        check("warehouse_condition_"..model.."_can_run_after_breaker_repair",
            fleet.canOperate(state,model))
    end
    okay=Condition.perform(state,player,"call_water")
    check("warehouse_condition_water_reconnect_receipted",okay and c.waterConnected
        and #state.receipts.entries==2 and Condition.waterReady(state))
    okay,code=Condition.perform(state,player,"repair_pipe")
    check("warehouse_condition_has_no_pipe_repair",not okay and code=="not_allowed")
    okay,code=Condition.perform(state,{sceneId="warehouse",x=475,y=495},"clean_center")
    check("warehouse_condition_floor_cleanup_uses_spills_only",not okay and code=="not_allowed")
    check("warehouse_condition_guide_points_to_first_spill",Guide.nextStep(state)=="clean-puddle1")
    local baseImage=love.graphics.newImage(Config.paths.warehouse)
    local floorAssets={get=function(name) return name=="warehouse" and baseImage end}
    local function preview(name)
        local folder=os.getenv("PICTURE_SHOP_RESTORATION_PREVIEW_DIR")
        if not folder then return end
        local graphics=love.graphics
        local picture=graphics.newCanvas(960,678)
        graphics.push("all")
        graphics.setCanvas(picture)
        graphics.clear(0,0,0,1)
        graphics.setColor(1,1,1,1)
        local plate=assert(conditionRenderer.image(state,floorAssets))
        graphics.draw(plate,0,0,0,960/plate:getWidth(),678/plate:getHeight())
        conditionRenderer.drawStatic(state)
        graphics.pop()
        local data=picture:newImageData()
        local encoded=data:encode("png")
        local file=assert(io.open(folder.."/"..name..".png","wb"))
        file:write(encoded:getString());file:close()
        data:release();picture:release()
    end
    preview("warehouse-spills-before")
    check("warehouse_condition_requested_plate_is_lit_base",
        Config.paths.warehouse=="assets/generated/warehouse-condition-v2/stage3-on.png"
            and conditionRenderer.image(state,floorAssets)==baseImage)
    c.lightsOn=false
    local offImage=conditionRenderer.image(state,floorAssets)
    check("warehouse_condition_matching_off_plate_is_selected",
        offImage and offImage~=baseImage
            and offImage:getWidth()==baseImage:getWidth()
            and offImage:getHeight()==baseImage:getHeight())
    preview("warehouse-spills-off")
    c.lightsOn=true
    for _,puddle in ipairs({"puddle1","puddle2"}) do
        local point=Condition.anchors[puddle]
        local workPlayer={sceneId="warehouse",x=point.x,y=point.y}
        local targets=Rooms.targets(workPlayer,state)
        local target=targets["restoration_"..puddle]
        local selected=Interaction.select(workPlayer,targets)
        check("warehouse_condition_"..puddle.."_art_matches_reachable_action",
            Rooms.walkable(point.x,point.y,"warehouse")
                and overlayAlpha(point.x,point.y)>.55
                and target and target.restorationAction=="clean_"..puddle
                and selected and selected.target==target)
        okay,code=Condition.perform(state,workPlayer,"clean_"..puddle)
        check("warehouse_condition_"..puddle.."_cannot_vanish_in_one_action",
            not okay and code=="mop_required")
        local alphaBefore=overlayAlpha(point.x,point.y)
        local changed,done=Condition.mopPoint(state,puddle,point.x,point.y)
        local partial=Condition.puddleProgress(state,puddle)
        local alphaAfter=overlayAlpha(point.x,point.y)
        check("warehouse_condition_"..puddle.."_first_pass_eraser_is_partial",
            changed and not done and partial>0 and partial<1
                and alphaAfter>0 and alphaAfter<alphaBefore,
            ("changed=%s done=%s fade=%.3f alpha=%.3f/%.3f stamps=%d"):format(
                tostring(changed),tostring(done),partial,alphaBefore,alphaAfter,#c.puddleStrokes[puddle]))
        if puddle=="puddle1" then preview("warehouse-spills-partial") end
        for _=1,3 do
            -- Keep contact samples close enough that the mop head overlaps
            -- its previous stamp instead of testing with wide artificial gaps.
            for y=point.y-point.visualRadiusY,point.y+point.visualRadiusY,8 do
                for x=point.x-point.visualRadiusX,point.x+point.visualRadiusX,13 do
                    Condition.mopPoint(state,puddle,x,y, false)
                end
            end
        end
        check("warehouse_condition_"..puddle.."_can_be_mopped_progressively",
            c.cleanedPuddles[puddle] and Condition.puddleProgress(state,puddle)==1
                and overlayAlpha(point.x,point.y)<.005,
            ("clean=%s faded=%.3f alpha=%.3f stamps=%d"):format(
                tostring(c.cleanedPuddles[puddle]),Condition.puddleProgress(state,puddle),
                overlayAlpha(point.x,point.y),#c.puddleStrokes[puddle]))
    end
    check("warehouse_condition_floor_finishes_without_repaint",
        c.cleaned.west and c.cleaned.center and c.cleaned.east
            and Condition.stage(state)==4 and conditionRenderer.image(state,floorAssets)==baseImage)
    preview("warehouse-spills-clean")
    baseImage:release()
    overlay:release();conditionRenderer.clear()
    state.screen="world"
    check("warehouse_condition_complete_after_all_work",Condition.complete(state)
        and Condition.variant(state)=="stage4On")
    okay,code=Condition.perform(state,player,"grand_opening")
    check("warehouse_condition_opening_requires_machine_service",not okay and code=="not_ready")
    -- Carry the two machines serviced with purchased kits into the restored shop.
    state.machines.items=purchaseState.machines.items
    c.grandpaMet=true
    okay=Condition.perform(state,player,"grand_opening")
    check("warehouse_condition_grand_opening_unlocks_jobs",okay and Condition.openForBusiness(state)
        and Service.createNextOffer(state,1)~=nil)
    WorkPhone.update(state,0)
    check("warehouse_condition_calls_resume_after_opening",state.workPhone.incoming~=nil)
    okay,code=Condition.perform(state,{sceneId="home",x=218,y=185},"grand_opening")
    check("warehouse_condition_replayed_opening_is_idempotent",okay and code=="already_applied")
    local snapshot=Schema.snapshot(state)
    check("warehouse_condition_roundtrips_persistent_state",snapshot and Schema.validState(snapshot)
        and snapshot.warehouse.condition.seed==771 and Condition.complete(snapshot))
    local unpaid=State.new()
    unpaid.warehouse.condition=Condition.new("story",7)
    unpaid.money=0
    okay,code=Condition.perform(unpaid,player,"call_power")
    check("warehouse_condition_insufficient_funds_no_partial_connection",not okay and code=="insufficient_funds"
        and not unpaid.warehouse.condition.powerConnected and #unpaid.receipts.entries==0)
    local billState=State.new()
    billState.warehouse.condition=Condition.new("story",9)
    billState.calendar.day,billState.calendar.totalDays=31,30
    billState.calendar.elapsed=billState.calendar.secondsPerDay-1
    Calendar.update(billState,2)
    local charges=billState.bills.ledger[1] and billState.bills.ledger[1].charges or {}
    local hasPower,hasWater=false,false
    for _,charge in ipairs(charges) do
        hasPower=hasPower or charge.id=="power"
        hasWater=hasWater or charge.id=="water"
    end
    check("warehouse_condition_disconnected_utilities_not_billed",#charges==3 and not hasPower and not hasWater)
    local walked=State.new()
    walked.warehouse.condition=Condition.new("story",13)
    Footprints.reset()
    local walker={sceneId="warehouse",x=112,y=383}
    Footprints.update(walked,walker,nil,0)
    walker.x=199
    Footprints.update(walked,walker,nil,.2)
    check("warehouse_condition_dirty_steps_keep_only_five_marks",Footprints.count()==5)
    check("warehouse_condition_wet_surface_is_distinct",
        Footprints.surface(walked,Condition.anchors.puddle1.x,Condition.anchors.puddle1.y)=="water"
        and Footprints.surface(walked,150,383)=="concrete")
    Footprints.update(walked,walker,nil,10)
    check("warehouse_condition_footprints_fade_quickly",Footprints.count()==0)
    Footprints.reset()
    local request={sessionId="restoration-test",requestId=1,targetKind="restoration",desiredState="call_power"}
    local packet=Protocol.encode("interaction_request",request)
    local decoded=packet and Protocol.decode(packet)
    check("warehouse_condition_network_accepts_known_action",decoded and decoded.payload
        and decoded.payload.desiredState=="call_power")
    request.desiredState="repair_pipe"
    check("warehouse_condition_network_rejects_removed_pipe_action",
        Protocol.encode("interaction_request",request)==nil)
    local mopActor={sceneId="warehouse",character="rabbit-worker",x=Condition.anchors.puddle1.x,
        y=Condition.anchors.puddle1.y,taskAction="mop_puddle1",intentX=1,intentY=0}
    local remoteState=State.new()
    remoteState.warehouse.condition=Condition.new("story",14)
    local remoteTask={puddle="puddle1",direction="east",elapsed=0}
    local MopMotion=require("src.warehouse_mop_motion")
    local stamps,remoteDone=MopMotion.advance(remoteState,remoteTask,mopActor,.2,
        mopActor.x,mopActor.y,mopActor.x+30,mopActor.y,false)
    local remoteProgress=Condition.puddleProgress(remoteState,"puddle1")
    mopActor.taskAction="none"
    check("warehouse_condition_multiplayer_mop_samples_animation_contact",
        stamps>0 and not remoteDone and remoteProgress>0 and #remoteState.warehouse.condition.puddleStrokes.puddle1>0)
    local shortMoveState=State.new()
    shortMoveState.warehouse.condition=Condition.new("story",15)
    local shortActor={sceneId="warehouse",x=Condition.anchors.puddle1.x,y=Condition.anchors.puddle1.y}
    local shortTask={puddle="puddle1",direction="east",elapsed=0}
    MopMotion.advance(shortMoveState,shortTask,shortActor,0,shortActor.x,shortActor.y,
        shortActor.x,shortActor.y,false)
    local contactCount=#shortMoveState.warehouse.condition.puddleStrokes.puddle1
    for _=1,4 do
        local startX=shortActor.x
        shortActor.x=shortActor.x+2
        MopMotion.advance(shortMoveState,shortTask,shortActor,0,startX,shortActor.y,
            shortActor.x,shortActor.y,false)
    end
    check("warehouse_condition_small_movement_accumulates_mop_contact",
        contactCount>0 and #shortMoveState.warehouse.condition.puddleStrokes.puddle1>contactCount)
    local mopPacket=Protocol.encode("input",{sessionId="restoration-test",sequence=1,
        moveX=1,moveY=0,taskAction="mop_puddle1"})
    local mopDecoded=mopPacket and Protocol.decode(mopPacket)
    check("warehouse_condition_multiplayer_mop_input_roundtrips",
        mopDecoded and mopDecoded.payload.taskAction=="mop_puddle1")
    check("warehouse_condition_breaker_approach_is_walkable",
        require("src.shop_rooms").walkable(218,185,"warehouse"))
end
return Test
