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
    c.powerConnected,c.breakerRepaired=true,true
    local pendingPlate=conditionRenderer.image(state,rendererAssets)
    check("warehouse_condition_pending_variant_does_not_reuse_old_plate",
        closedPlate~=baseWarehouse and pendingPlate==baseWarehouse and pendingPlate~=closedPlate)
    imageLoader.load=oldImageLoaderLoad
    imageLoader.setEnabled(oldImageLoaderEnabled)
    c.powerConnected,c.breakerRepaired=false,false
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
    local westDirt,standingWater,clearFloor=overlayAlpha(150,383),overlayAlpha(758,493),overlayAlpha(500,600)
    check("warehouse_condition_initial_floor_materials_render",
        westDirt>.22 and standingWater>.4 and clearFloor<.005,
        ("dirt=%.3f water=%.3f clear=%.3f"):format(westDirt,standingWater,clearFloor))
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
    check("warehouse_condition_cleanup_has_fixed_order",not okay and code=="not_ready")
    local Rooms=require("src.shop_rooms")
    local Interaction=require("src.interaction")
    local Controls=require("src.shop_room_controls")
    for stage,entry in ipairs({{"west",145,510},{"center",475,495},{"east",760,495}}) do
        local workPlayer={sceneId="warehouse",x=entry[2],y=entry[3]}
        local target=Rooms.targets(workPlayer,state).restorationWork
        local selected=Interaction.select(workPlayer,Rooms.targets(workPlayer,state))
        Controls.open({state=state},"restoration","clean_"..entry[1])
        check("warehouse_condition_"..entry[1].."_cleanup_is_reachable_in_room",
            Rooms.walkable(entry[2],entry[3],"warehouse")
                and target and target.restorationAction=="clean_"..entry[1]
                and selected and selected.kind=="restoration"
                and Controls.selected==stage+3 and Controls.page==1)
        assert(Condition.perform(state,{sceneId="warehouse",x=entry[2],y=entry[3]},"clean_"..entry[1]))
        check("warehouse_condition_stage_"..stage.."_advances_once",
            Condition.stage(state)==stage and Condition.variant(state)=="stage"..stage.."On")
        if stage==1 then
            check("warehouse_condition_west_patch_clears_without_erasing_water",
                overlayAlpha(150,383)<.005 and overlayAlpha(758,493)>.05)
        elseif stage==3 then
            check("warehouse_condition_east_cleanup_removes_old_water",overlayAlpha(758,493)<.005)
        end
    end
    check("warehouse_condition_final_paint_is_stage_four_only",Condition.stage(state)==3)
    local paintPlayer={sceneId="warehouse",x=470,y=245}
    local paintTarget=Rooms.targets(paintPlayer,state).restorationWork
    Controls.open({state=state},"restoration","repaint")
    check("warehouse_condition_paint_is_reachable_after_cleanup",
        Rooms.walkable(paintPlayer.x,paintPlayer.y,"warehouse")
            and paintTarget and paintTarget.restorationAction=="repaint"
            and Controls.selected==7 and Controls.page==2)
    assert(Condition.perform(state,{sceneId="warehouse",x=470,y=245},"repaint"))
    overlay:release();conditionRenderer.clear()
    Controls.mode=nil;state.screen="world"
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
    check("warehouse_condition_wet_surface_is_distinct",Footprints.surface(walked,758,493)=="water"
        and Footprints.surface(walked,150,383)=="dirt")
    Footprints.update(walked,walker,nil,4)
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
    check("warehouse_condition_breaker_approach_is_walkable",
        require("src.shop_rooms").walkable(218,185,"warehouse"))
end
return Test
