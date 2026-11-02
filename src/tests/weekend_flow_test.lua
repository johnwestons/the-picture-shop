local Flow=require("src.weekend_flow")
local Calendar=require("src.business_calendar")
local Schema=require("src.save_schema")
local Test={}
local function at(state,hours)
    local seconds=Calendar.secondsPerDay(state)
    state.calendar=Calendar.dateFromHours(hours);state.calendar.secondsPerDay=seconds
    state.calendar.elapsed=(hours%24)/24*seconds
end
function Test.run(context,check)
    for _,seconds in ipairs({300,1200,3600}) do
        local state=require("src.state").new();state.calendar.secondsPerDay=seconds
        at(state,42)
        check("weekend_warning_"..seconds,Flow.update(state,false) and state.home.weekend.phase=="working")
        local revision=state.home.revision
        check("weekend_warning_once_"..seconds,not Flow.update(state,false) and state.home.revision==revision)
        Calendar.update(state,Flow.limitCalendarStep(state,seconds*100))
        check("weekend_large_step_stops_at_friday_"..seconds,Calendar.absoluteHours(state)==44)
        check("weekend_closing_requires_safety_"..seconds,Flow.update(state,false)
            and state.home.weekend.phase=="closing" and not Flow.shopClosed(state) and not Flow.acceptsNewWork(state))
        check("weekend_cannot_depart_unsafe_"..seconds,not Flow.depart(state,state.home.revision))
        Calendar.update(state,Flow.limitCalendarStep(state,seconds/24))
        check("weekend_shutdown_time_keeps_running_"..seconds,Calendar.absoluteHours(state)==45)
        check("weekend_ready_"..seconds,Flow.update(state,true) and Flow.shopClosed(state))
        local before=Calendar.absoluteHours(state)
        Calendar.update(state,Flow.limitCalendarStep(state,seconds*10))
        check("weekend_ready_holds_calendar_"..seconds,Calendar.absoluteHours(state)==before)
        check("weekend_stale_departure_"..seconds,not Flow.depart(state,state.home.revision-1))
        check("weekend_departure_"..seconds,Flow.depart(state,state.home.revision)
            and state.home.weekend.phase=="home" and state.home.weekend.transition==1)
        local snapshot=assert(Schema.snapshot(state))
        check("weekend_save_phase_"..seconds,Schema.validState(snapshot) and snapshot.home.weekend.phase=="home")
        state=snapshot
        check("weekend_departure_not_replayed_"..seconds,not Flow.depart(state,state.home.revision))
        at(state,72)
        check("weekend_no_sunday_work_"..seconds,not Flow.returnToWork(state,state.home.revision))
        at(state,103)
        check("weekend_monday_reminder_"..seconds,Flow.update(state,false) and not Flow.update(state,false))
        check("weekend_no_early_reopening_"..seconds,not Flow.returnToWork(state,state.home.revision))
        at(state,107)
        check("weekend_late_return_never_rewinds_"..seconds,Flow.returnToWork(state,state.home.revision)
            and Calendar.absoluteHours(state)==107 and state.home.weekend.closesAtHours==212
            and state.home.weekend.transition==2 and Flow.acceptsNewWork(state) and not Flow.shopClosed(state))
        check("weekend_return_not_replayed_"..seconds,not Flow.returnToWork(state,state.home.revision))
        local malformed=Schema.copy(state);malformed.home.weekend.phase="teleport"
        check("weekend_bad_phase_rejected_"..seconds,not Schema.validState(malformed))
    end
    for _,seconds in ipairs({300,1200,3600}) do
        local rounded=require("src.state").new();rounded.calendar.secondsPerDay=seconds;at(rounded,44-5e-8)
        local now=Calendar.absoluteHours(rounded)
        assert(Flow.update(rounded,false));assert(Flow.update(rounded,true))
        check("weekend_fractional_shutdown_timestamp_is_saveable_"..seconds,
            rounded.home.weekend.closedAtHours==44 and Calendar.absoluteHours(rounded)==now
            and Flow.valid(rounded.home.weekend) and Schema.validState(Schema.snapshot(rounded)))
        assert(Flow.depart(rounded,rounded.home.revision))
        check("weekend_fractional_departure_replays_valid_snapshot_"..seconds,Schema.validState(Schema.snapshot(rounded))
            and not require("src.household_finances").settle(rounded,44))
    end
    local legacy=require("src.state").new();legacy.home.weekend=nil;at(legacy,60)
    check("weekend_legacy_saturday_closes_without_rewind",Flow.update(legacy,true)
        and legacy.home.weekend.phase=="ready" and Calendar.absoluteHours(legacy)==60)
    assert(Flow.depart(legacy,legacy.home.revision));at(legacy,220)
    check("weekend_missed_week_stays_closed_saturday",not Flow.returnToWork(legacy,legacy.home.revision))
    at(legacy,274)
    check("weekend_missed_week_can_return_next_monday",Flow.returnToWork(legacy,legacy.home.revision)
        and legacy.home.weekend.closesAtHours==380 and Calendar.absoluteHours(legacy)==274)
    local construction=require("src.state").new();construction.money=10000
    local upgrades=require("src.warehouse_upgrades")
    assert(upgrades.purchase(construction,"front_left","floor","weekend-construction",0))
    upgrades.update(construction,0)
    local project=upgrades.activeProject(construction)
    upgrades.update(construction,2,{noticeDeliveredProjectId=project.id,noticeCallId="CALL-WEEKEND"})
    upgrades.update(construction,4,{workerArrivedProjectId=project.id})
    at(construction,10)
    assert(require("src.shop_shutdown").pauseConstruction(construction))
    construction=assert(Schema.snapshot(construction))
    check("weekend_construction_pause_persisted",Schema.validState(construction)
        and upgrades.activeProject(construction).pausedAtHours==10)
    upgrades.update(construction,100,{unblockedProjectId=project.id})
    local resumed=upgrades.activeProject(construction)
    check("weekend_construction_resumes_without_closed_time",resumed.stage==1 and resumed.stageDueAtHours==118
        and resumed.pausedAtHours==nil and Schema.validState(construction))
end
return Test
