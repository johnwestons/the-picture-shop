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
function Test.run(_,check)
    local quick=State.new()
    check("warehouse_condition_quick_start_remains_operational",
        Condition.valid(quick.warehouse.condition) and Condition.complete(quick)
        and Condition.powered(quick) and Condition.waterReady(quick)
        and Condition.variant(quick)=="stage4On")
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
    okay=Condition.perform(state,player,"call_water")
    check("warehouse_condition_water_reconnect_receipted",okay and c.waterConnected
        and #state.receipts.entries==2 and Condition.waterReady(state))
    okay,code=Condition.perform(state,player,"repair_pipe")
    check("warehouse_condition_has_no_pipe_repair",not okay and code=="not_allowed")
    okay,code=Condition.perform(state,{sceneId="warehouse",x=475,y=495},"clean_center")
    check("warehouse_condition_cleanup_has_fixed_order",not okay and code=="not_ready")
    for stage,entry in ipairs({{"west",145,510},{"center",475,495},{"east",760,495}}) do
        assert(Condition.perform(state,{sceneId="warehouse",x=entry[2],y=entry[3]},"clean_"..entry[1]))
        check("warehouse_condition_stage_"..stage.."_advances_once",
            Condition.stage(state)==stage and Condition.variant(state)=="stage"..stage.."On")
    end
    check("warehouse_condition_final_paint_is_stage_four_only",Condition.stage(state)==3)
    assert(Condition.perform(state,{sceneId="warehouse",x=470,y=245},"repaint"))
    check("warehouse_condition_complete_after_all_work",Condition.complete(state)
        and Condition.variant(state)=="stage4On")
    okay,code=Condition.perform(state,player,"grand_opening")
    check("warehouse_condition_opening_requires_machine_service",not okay and code=="not_ready")
    local fleet=require("src.machine_fleet")
    fleet.installed(state,"polar_115").maintenance.serviceCount=1
    fleet.installed(state,"skid_wrapper").maintenance.serviceCount=1
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
