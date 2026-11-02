local Deadlines=require("src.business_deadlines")
local Calendar=require("src.business_calendar")
local Schema=require("src.save_schema")
local Test={}
function Test.run(context,check)
    local friday=24+18
    check("business_deadline_friday_to_monday",Deadlines.addWeekdayHours(friday,24)==4*24+18)
    check("business_deadline_weekend_acceptance",Deadlines.addWeekdayHours(2*24+12,24)==5*24)
    check("business_deadline_friday_midnight_is_monday",Deadlines.addWeekdayHours(24,24)==4*24)
    check("business_deadline_zero_lateness_during_weekend",Deadlines.weekdayHoursBetween(48,96)==0)
    check("business_deadline_lateness_excludes_weekend",Deadlines.weekdayHoursBetween(47,98)==3)
    check("business_deadline_reverse_interval",Deadlines.weekdayHoursBetween(98,47)==0)
    local Hours=require("src.business_hours")
    check("business_deadline_no_lateness_while_locked",Hours.between(44,105)==0)
    check("business_deadline_only_open_hours_count_late",Hours.between(43,106)==2)
    local monday={acceptedGameHours=0,details={dueDate="Seven business days"}}
    check("business_deadline_monday_due_at_opening",Deadlines.ensure(monday).dueAtHours==11*24+9)
    monday.completedAtHours=11*24+8
    check("business_deadline_before_opening_not_late",Deadlines.lateByHours(monday)==0)
    local old={deadline={policy="weekdays-v1",acceptedAtHours=0,businessDays=7,dueAtHours=11*24}}
    check("business_deadline_old_promise_extended_to_opening",Deadlines.ensure(old).dueAtHours==11*24+9
        and old.deadline.policy==Deadlines.POLICY)
    -- Independent hour-by-hour calendar oracle checks every weekday, month/year
    -- boundaries, leap day, and several turnaround lengths.
    for _,day in ipairs({0,1,2,3,4,5,6,29,30,31,364,365,790}) do
        for _,length in ipairs({1,5,7,21,365}) do
            local start=day*24+13;local at=start;local remaining=length*24
            while remaining>0 do
                if Calendar.dateFromHours(at).weekday<=5 then remaining=remaining-1 end
                at=at+1
            end
            while Calendar.dateFromHours(at).weekday>5 do at=at+1 end
            check("business_deadline_oracle_"..day.."_"..length,Deadlines.addWeekdayHours(start,length*24)==at)
        end
    end
    local state=require("src.state").new()
    state.calendar=Calendar.dateFromTotalDay(1);state.calendar.elapsed=state.calendar.secondsPerDay*18/24
    local job=assert(require("src.jobs").createOffer({id="JOB-WEEKEND-DEADLINE",company="Weekday Print Co.",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500},packaging="flat",
        details={dueDate="Standard 5-business-day turnaround"}}))
    assert(context.jobService.acceptOffer(state,job,100))
    check("business_deadline_stamped_at_acceptance",job.deadline.policy==Deadlines.POLICY
        and job.deadline.dueAtHours==8*24+18 and job.deadline.acceptedAtHours==friday)
    job.details.dueDate="One business day"
    job.completedAtHours=8*24+19
    check("business_deadline_display_edit_does_not_change_promise",require("src.job_feedback").lateByHours(job)==1)
    local snapshot=assert(Schema.snapshot(state))
    check("business_deadline_saved_and_shared",Schema.validState(snapshot)
        and snapshot.jobs.active[1].deadline.dueAtHours==job.deadline.dueAtHours)
    local bad=Schema.copy(snapshot);bad.jobs.active[1].deadline.dueAtHours=bad.jobs.active[1].deadline.dueAtHours+24
    check("business_deadline_rejects_inconsistent_due",not Schema.validState(bad))
    bad=Schema.copy(snapshot);bad.jobs.active[1].deadline.policy="calendar-days"
    check("business_deadline_rejects_unknown_policy",not Schema.validState(bad))
    local legacy=Schema.copy(snapshot);legacy.jobs.active[1].deadline=nil
    local migrated=assert(Schema.snapshot(legacy))
    check("business_deadline_legacy_initializes_once",migrated.jobs.active[1].deadline.businessDays==1)
    local flexible={acceptedGameHours=friday,details={dueDate="Flexible starter-job turnaround"},completedAtHours=10000}
    check("business_deadline_flexible_never_penalized",Deadlines.lateByHours(flexible)==0 and flexible.deadline.policy=="flexible")
    for _,record in ipairs({{policy="weekdays-v1",businessDays=math.huge},
        {policy="weekdays-v1",acceptedAtHours=0,businessDays=0,dueAtHours=0},
        {policy="weekdays-v1",acceptedAtHours=0,businessDays=5,dueAtHours=0/0},
        {policy="flexible",dueAtHours=99}}) do
        check("business_deadline_invalid_"..tostring(_),not Deadlines.valid(record))
    end
end
return Test
