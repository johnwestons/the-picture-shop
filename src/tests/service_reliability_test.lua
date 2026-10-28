local State=require("src.state")
local Calendar=require("src.business_calendar")
local Maintenance=require("src.machine_maintenance")
local Fleet=require("src.machine_fleet")
local Technician=require("src.technician")
local Schema=require("src.save_schema")
local Test={}

local function fixture(day)
    local state=State.new()
    state.calendar=Calendar.dateFromTotalDay(day)
    assert(Maintenance.prepareBladeForTechnician(state))
    local _,cutter=Maintenance.cutterStatus(state)
    cutter.nextTechnicianDay,cutter.appointmentType=day,"requested"
    return state,cutter
end

local function distribution(check)
    local onTime,late,calledOut=0,0,0
    for day=1,100 do
        local state,cutter=fixture(day)
        assert(Maintenance.updateTechnician(state))
        if state.technicianVisit then onTime=onTime+1
        elseif cutter.nextTechnicianDay==day+1 then late=late+1
        elseif cutter.nextTechnicianDay==day+7 then calledOut=calledOut+1 end
    end
    check("service_reliability_most_bookings_arrive_as_scheduled",onTime==93 and late==5 and calledOut==2,
        string.format("on time=%d late=%d called out=%d",onTime,late,calledOut))
end

local function busy(check)
    local state,cutter=fixture(1)
    state.money=10000;assert(Fleet.buy(state,"dealer",3))
    assert(Technician.schedule(state,"windmill",1,false))
    local current=state.technicianVisit
    for _=1,500 do Maintenance.updateTechnician(state) end
    check("service_reliability_waiting_for_other_technician_never_rerolls_booking",
        state.technicianVisit==current and cutter.nextTechnicianDay==1 and cutter.technicianSequence==0
        and #Fleet.serviceInbox(state)==0)
    state.technicianVisit=nil
    check("service_reliability_waiting_booking_starts_once_actor_is_free",Maintenance.updateTechnician(state)
        and state.technicianVisit.kind=="cutter" and cutter.technicianSequence==1 and not cutter.nextTechnicianDay)
end

local function rescheduled(context,check)
    for _,case in ipairs({{name="late",day=26,delay=1,sequence=9},
        {name="call_out",day=80,delay=7,sequence=29}}) do
        local state,cutter=fixture(case.day)
        local updated=Maintenance.updateTechnician(state)
        check("service_reliability_"..case.name.."_sends_one_notice",updated and not state.technicianVisit
            and cutter.nextTechnicianDay==case.day+case.delay and cutter.technicianRescheduled
            and #Fleet.serviceInbox(state)==1)
        for _=1,300 do Maintenance.updateTechnician(state) end
        check("service_reliability_"..case.name.."_notice_does_not_repeat",#Fleet.serviceInbox(state)==1
            and cutter.technicianSequence==1 and cutter.nextTechnicianDay==case.day+case.delay)
        -- These seeds would cause another call-out if a replacement date were
        -- rolled again. A postponed booking must instead attend as promised.
        cutter.technicianSequence=case.sequence
        assert(context.save.save(3,state,context.world.snapshot()))
        local loaded=assert(context.save.load(3))
        local resumed=State.new();assert(State.applySave(resumed,loaded))
        context.save.delete(3)
        local _,savedCutter=Maintenance.cutterStatus(resumed)
        resumed.calendar=Calendar.dateFromTotalDay(savedCutter.nextTechnicianDay)
        check("service_reliability_"..case.name.."_replacement_date_survives_reload_without_another_delay",
            savedCutter.technicianRescheduled and Maintenance.updateTechnician(resumed)
            and resumed.technicianVisit and resumed.technicianVisit.kind=="cutter"
            and not savedCutter.nextTechnicianDay and savedCutter.technicianSequence==case.sequence
            and #Fleet.serviceInbox(resumed)==1)
        resumed.technicianVisit.recurring=true
        assert(Maintenance.completeTechnicianVisit(resumed,"cutter",resumed.technicianVisit))
        check("service_reliability_"..case.name.."_completion_resets_for_next_booking",not savedCutter.technicianRescheduled
            and savedCutter.nextTechnicianDay==resumed.calendar.totalDays+7 and Schema.snapshot(resumed)~=nil)
    end
end

function Test.run(context,check)
    distribution(check)
    busy(check)
    rescheduled(context,check)
    local state,cutter=fixture(1)
    cutter.bladeRemoved,cutter.bladeInSleeve=false,false
    Maintenance.updateTechnician(state)
    check("service_reliability_still_requires_a_safely_prepared_blade",not state.technicianVisit
        and not cutter.nextTechnicianDay and Fleet.serviceInbox(state)[1].subject=="Blade was not ready for service")
end

return Test
