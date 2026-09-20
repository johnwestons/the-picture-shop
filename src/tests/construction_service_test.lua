local State = require("src.state")
local Schema = require("src.save_schema")
local Upgrades = require("src.warehouse_upgrades")
local Service = require("src.construction_service")
local Phone = require("src.work_phone")
local PhoneScreen = require("src.screens.work_phone_screen")

local Test = {}
local function fixture(two)
    local state = State.new()
    state.money = 20000
    assert(Upgrades.purchase(state,"front_left","floor","CONSTRUCTION-LEFT",0))
    if two then assert(Upgrades.purchase(state,"front_right","storage","CONSTRUCTION-RIGHT",0)) end
    return state
end
local function runtime()
    local visits, calls = {}, { started=0, arrived=0, exited=0 }
    return {
        workerStarted=function(_,project)
            calls.started=calls.started+1
            if visits[project.id] then return true,false end
            visits[project.id]={atWork=false,out=false,blocked=false}
            return true,true
        end,
        workerArrived=function(_,project)
            calls.arrived=calls.arrived+1
            return visits[project.id] and visits[project.id].atWork == true
        end,
        workerExited=function(_,project)
            calls.exited=calls.exited+1
            return visits[project.id] and visits[project.id].out == true
        end,
        workerBlocked=function(_,project)
            return visits[project.id] and visits[project.id].blocked == true
        end,
    },visits,calls
end
local function allValid(state) return Schema.validState(Schema.snapshot(state)) end

function Test.run(_,check)
    local idle=State.new()
    local idleMoney=idle.money
    local changed,events=Service.update(idle,0)
    check("construction_service_empty_queue_does_not_create_call_or_worker",
        not changed and #events==0 and idle.workPhone.incoming==nil
        and idle.money==idleMoney and allValid(idle))

    local state=fixture()
    local money=state.money
    changed,events=Service.update(state,0)
    local call=state.workPhone.incoming
    check("construction_service_queues_neutral_project_notice_before_any_dispatch",
        changed and call and call.kind=="construction_notice" and call.projectId=="WUP-0001"
        and call.bayId=="front_left" and call.optionId=="floor"
        and call.role=="CONSTRUCTION SERVICE" and call.message:find("front entrance",1,true)
        and Phone.lightIndex(state)==3 and state.warehouse.projects[1].phase=="awaiting_arrival"
        and state.warehouse.projects[1].arrivalDueAtHours==2 and state.money==money and allValid(state))
    local callId=call.id
    changed,events=Service.update(state,0.5)
    check("construction_service_repeated_update_does_not_duplicate_notice_or_charge",
        not changed and #events==0 and state.workPhone.incoming.id==callId
        and state.workPhone.nextCallId==2 and #state.workPhone.history==0 and state.money==money)
    Service.update(state,1)
    check("construction_service_unanswered_notice_archives_at_ring_timeout",
        state.workPhone.incoming==nil and #state.workPhone.history==1
        and state.workPhone.history[1].id==callId and state.workPhone.history[1].outcome=="missed"
        and state.workPhone.history[1].endedAtHours==1 and state.warehouse.projects[1].arrivalDueAtHours==2
        and allValid(state))
    changed,events=Service.update(state,10000)
    check("construction_service_default_never_starts_or_completes_phantom_work",
        not changed and #events==0 and #state.workPhone.history==1
        and state.warehouse.projects[1].phase=="awaiting_arrival" and state.warehouse.projects[1].stage==0
        and not Upgrades.isBayAccessible(state,"front_left") and state.money==money)
    Service.update(state,10000,{workerArrived=function() return true end})
    check("construction_service_arrival_alone_cannot_bypass_physical_dispatch_gate",
        state.warehouse.projects[1].stage==0 and state.warehouse.projects[1].phase=="awaiting_arrival")

    local busy=fixture()
    assert(Phone.queueCall(busy,{kind="customer_status",caller="Existing customer",role="CUSTOMER",
        subject="JOB STATUS",message="Existing fixture call."}))
    local customerCall=busy.workPhone.incoming
    local callbacks,visits,calls=runtime()
    Service.update(busy,0,callbacks)
    Service.update(busy,500,callbacks)
    check("construction_service_busy_phone_retries_without_replacing_other_caller",
        busy.workPhone.incoming==customerCall and busy.workPhone.nextCallId==2
        and #busy.workPhone.history==0 and Upgrades.pendingNotice(busy).projectId=="WUP-0001"
        and calls.started==0 and next(visits)==nil)
    assert(Phone.dismiss(busy))
    Service.update(busy,500,callbacks)
    local constructionCall=busy.workPhone.incoming
    check("construction_service_busy_line_release_queues_once_with_fresh_lead",
        constructionCall.kind=="construction_notice" and constructionCall.receivedAtHours==500
        and busy.warehouse.projects[1].arrivalDueAtHours==502 and calls.started==0
        and busy.money==17500 and #busy.procurement.orders==0 and allValid(busy))
    local premature=Phone.respond(busy)
    check("construction_service_acknowledgement_requires_answer",
        not premature and Phone.actionLabel(busy)=="ACKNOWLEDGE"
        and busy.workPhone.incoming==constructionCall and busy.money==17500)
    PhoneScreen.enter(busy)
    local x,y=PhoneScreen.buttonCenter("action")
    local firstIntent,firstArgs=PhoneScreen.remoteIntent(busy,x,y)
    local answered=PhoneScreen.mousepressed(busy,x,y,1)
    local secondIntent,secondArgs=PhoneScreen.remoteIntent(busy,x,y)
    local acknowledged=PhoneScreen.mousepressed(busy,x,y,1)
    check("construction_service_phone_gui_reuses_existing_answer_respond_wire_intents",
        firstIntent=="phone_answer" and firstArgs.callId==constructionCall.id
        and secondIntent=="phone_respond" and secondArgs.callId==constructionCall.id
        and answered.action=="answered" and acknowledged.action=="call_completed"
        and busy.workPhone.incoming==nil and #busy.workPhone.history==2)
    check("construction_service_acknowledge_does_not_order_supplies_or_cancel_appointment",
        busy.workPhone.history[2].outcome=="acknowledged" and busy.workPhone.history[2].projectId=="WUP-0001"
        and busy.warehouse.projects[1].phase=="awaiting_arrival" and busy.warehouse.projects[1].arrivalDueAtHours==502
        and busy.money==17500 and #busy.procurement.orders==0 and #busy.clientEmails.pending==0
        and not Phone.respond(busy) and allValid(busy))
    Service.update(busy,501,callbacks)
    check("construction_service_dispatch_waits_for_announced_lead",calls.started==0 and next(visits)==nil)
    changed,events=Service.update(busy,502,callbacks)
    check("construction_service_dispatch_callback_does_not_fake_worker_arrival",
        changed and calls.started==1 and visits["WUP-0001"] and not visits["WUP-0001"].atWork
        and busy.warehouse.projects[1].phase=="awaiting_arrival" and busy.warehouse.projects[1].stage==0)
    visits["WUP-0001"].atWork=true
    Service.update(busy,505,callbacks)
    check("construction_service_actual_anchor_arrival_starts_full_first_day",
        busy.warehouse.projects[1].phase=="building" and busy.warehouse.projects[1].stageStartedAtHours==505
        and busy.warehouse.projects[1].stageDueAtHours==529 and busy.warehouse.projects[1].stage==1
        and allValid(busy))
    Service.update(busy,529,callbacks)
    check("construction_service_present_worker_advances_exact_day_boundary",
        busy.warehouse.projects[1].stage==2 and busy.warehouse.projects[1].stageDueAtHours==553)

    for _,answeredFirst in ipairs({false,true}) do
        local dismissed=fixture()
        Service.update(dismissed,0)
        if answeredFirst then assert(Phone.answer(dismissed)) end
        local noticeId=dismissed.workPhone.incoming.id
        local closed=Phone.dismiss(dismissed)
        Service.update(dismissed,5)
        check("construction_service_dismiss_"..(answeredFirst and "answered" or "ringing").."_keeps_scheduled_visit",
            closed and dismissed.workPhone.incoming==nil and #dismissed.workPhone.history==1
            and dismissed.workPhone.history[1].id==noticeId
            and dismissed.warehouse.projects[1].phase=="awaiting_arrival"
            and dismissed.warehouse.projects[1].arrivalDueAtHours==2 and dismissed.money==17500)
    end
    local connected=fixture()
    Service.update(connected,0)
    Phone.answer(connected)
    Service.update(connected,10)
    check("construction_service_answered_notice_is_not_timed_out_mid_call",
        connected.workPhone.incoming and connected.workPhone.incoming.answered
        and #connected.workPhone.history==0 and connected.warehouse.projects[1].stage==0)

    local two=fixture(true)
    local bothMoney=two.money
    local cb,workers=runtime()
    Service.update(two,0,cb)
    Service.update(two,2,cb)
    workers["WUP-0001"].atWork=true
    Service.update(two,2,cb)
    Service.update(two,98,cb)
    check("construction_service_four_work_days_complete_first_project_only",
        two.warehouse.projects[1].phase=="complete" and two.warehouse.projects[1].completedAtHours==98
        and two.warehouse.projects[2].phase=="queued" and workers["WUP-0002"]==nil
        and Upgrades.isBayAccessible(two,"front_left") and not Upgrades.isBayAccessible(two,"front_right")
        and two.money==bothMoney and allValid(two))
    changed,events=Service.update(two,99,cb)
    check("construction_service_completion_does_not_release_worker_before_exit",
        not changed and #events==0 and two.warehouse.activeProjectId=="WUP-0001"
        and two.warehouse.projects[2].phase=="queued")
    workers["WUP-0001"].out=true
    Service.update(two,100,cb)
    Service.update(two,100,cb)
    check("construction_service_worker_exit_unlocks_single_next_call",
        two.warehouse.activeProjectId=="WUP-0002" and two.warehouse.projects[2].phase=="awaiting_arrival"
        and two.workPhone.incoming.projectId=="WUP-0002" and two.workPhone.nextCallId==3
        and workers["WUP-0002"]==nil and two.money==bothMoney and allValid(two))
    Service.update(two,100.5,cb)
    check("construction_service_second_notice_replay_preserves_cash_and_count",
        two.workPhone.nextCallId==3 and #two.workPhone.history==1 and two.money==bothMoney)

    local paused=fixture()
    local pcb,pworkers=runtime()
    Service.update(paused,0,pcb)
    Service.update(paused,2,pcb)
    pworkers["WUP-0001"].atWork=true
    Service.update(paused,2,pcb)
    Service.update(paused,8,pcb)
    pworkers["WUP-0001"].blocked=true
    Service.update(paused,10,pcb)
    check("construction_service_blocked_worker_preserves_last_confirmed_effort",
        paused.warehouse.projects[1].pausedAtHours==8 and paused.warehouse.projects[1].stage==1)
    Service.update(paused,200,pcb)
    check("construction_service_blocked_stage_cannot_catch_up_to_phantom_completion",
        paused.warehouse.projects[1].stage==1 and paused.warehouse.projects[1].phase=="building"
        and not Upgrades.isBayAccessible(paused,"front_left") and allValid(paused))
    pworkers["WUP-0001"].blocked=false
    Service.update(paused,200,pcb)
    check("construction_service_unblocked_worker_resumes_remaining_stage_hours",
        paused.warehouse.projects[1].pausedAtHours==nil and paused.warehouse.projects[1].stageDueAtHours==218)
    local reopened=State.new()
    assert(State.applyLocalSave(reopened,{slot=1,state=Schema.snapshot(paused)}))
    Service.update(reopened,1000)
    check("construction_service_reload_without_worker_runtime_pauses_instead_of_finishing",
        reopened.warehouse.projects[1].phase=="building" and reopened.warehouse.projects[1].stage==1
        and reopened.warehouse.projects[1].pausedAtHours~=nil and not Upgrades.isBayAccessible(reopened,"front_left")
        and allValid(reopened))
    local reused=fixture()
    local rcb,rworkers=runtime()
    Service.update(reused,0,rcb)
    Service.update(reused,2,rcb)
    rworkers["WUP-0001"].atWork=true
    Service.update(reused,2,rcb)
    local earlySave=Schema.snapshot(reused)
    Service.update(reused,50,rcb)
    assert(State.applyLocalSave(reused,{slot=1,state=earlySave}))
    Service.update(reused,100)
    check("construction_service_same_state_reload_cannot_reuse_future_worker_observation",
        reused.warehouse.projects[1].stage==1 and reused.warehouse.projects[1].phase=="building"
        and reused.warehouse.projects[1].pausedAtHours<reused.warehouse.projects[1].stageDueAtHours
        and allValid(reused))

    local interrupted=fixture()
    Service.update(interrupted,0)
    changed,events=Service.update(interrupted,2,{workerStarted=function() error("route unavailable") end,
        workerArrived=function() return true end})
    local failure=false
    for _,event in ipairs(events) do if event.kind=="worker_callback_failed" then failure=true end end
    check("construction_service_failed_runtime_callback_cannot_start_work",
        failure and interrupted.warehouse.projects[1].stage==0 and allValid(interrupted))
    local counterfeit=fixture()
    local callbackMoney=counterfeit.money
    local badCallbacks,badError=Service.update(counterfeit,0,{workerArrived=true})
    local badTime,timeError=Service.update(counterfeit,0/0)
    check("construction_service_invalid_callbacks_and_time_rejected",
        not badCallbacks and type(badError)=="string" and not badTime and type(timeError)=="string"
        and counterfeit.money==callbackMoney and counterfeit.workPhone.incoming==nil)
    local malformed=Phone.queueCall(counterfeit,{kind="construction_notice",projectId="BAD",bayId="front_left",optionId="floor"})
    check("construction_service_malformed_phone_project_spec_does_not_allocate_call",
        not malformed and counterfeit.workPhone.nextCallId==1 and counterfeit.workPhone.incoming==nil)

    local restored=fixture()
    Upgrades.update(restored,0)
    assert(Phone.queueCall(restored,{kind="construction_notice",projectId="WUP-0001",bayId="front_left",optionId="floor",
        caller="Warehouse construction",role="CONSTRUCTION SERVICE",subject="UPGRADE APPOINTMENT",
        message="Saved construction notice."},0))
    Phone.dismiss(restored)
    Service.update(restored,0.5)
    check("construction_service_saved_notice_recovery_does_not_queue_duplicate",
        restored.warehouse.projects[1].phase=="awaiting_arrival" and restored.warehouse.projects[1].noticeCallId=="CALL-0001"
        and restored.workPhone.nextCallId==2 and #restored.workPhone.history==1 and allValid(restored))
end

return Test
