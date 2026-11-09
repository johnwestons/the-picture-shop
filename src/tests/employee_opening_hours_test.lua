local Contracts=require("src.employment_contracts")
local State=require("src.state")
local Schema=require("src.save_schema")
local Employees=require("src.employees")
local Payroll=require("src.payroll")
local Calendar=require("src.business_calendar")
local Finance=require("src.staff_finances")
local Hiring=require("src.screens.hiring_screen")
local Test={}
local function terms(days,first,last)
    local t=Contracts.terms(2200,days,first,last,1);t.revision=1;t.startDay=0;t.signedAtHours=0;return t
end
local function worker(t) return {visible=true,clockedIn=true,phase="idle",contract=t,weeks={}} end
local function hire(s)
    local a=assert(Employees.createApplicant(s,0));a.shiftPreference="flexible"
    assert(Employees.requestResume(s,a.id,0));Employees.advance(s,.5)
    assert(Employees.command(s,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,wageCents=2500,days=31,startHour=9,endHour=17},.5))
    Employees.advance(s,1.25);assert(Employees.command(s,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    return s.employment.staff[1],a
end
function Test.run(context,check)
    local t=terms(127,9,17);local wage,hours=Contracts.weeklyEstimate(t)
    check("opening_contract_all_days_forecast_only_five_open_shifts",wage==797.5 and hours==36.25)
    check("opening_contract_no_weekend_attendance",not Contracts.onShift(t,57) and not Contracts.onShift(t,81) and Contracts.onShift(t,105))
    t=terms(31,21,5);wage,hours=Contracts.weeklyEstimate(t)
    check("opening_contract_mon_thu_overnights_retained",hours==29 and wage==638 and Contracts.onShift(t,26) and not Contracts.onShift(t,46))
    local a,b=Contracts.shiftBounds(t,0)
    check("opening_contract_overnight_not_cut_at_midnight",a==21 and b==29)
    t=terms(1,6,14);a,b=Contracts.shiftBounds(t,4)
    check("opening_contract_monday_starts_at_nine",a==105 and b==110 and not Contracts.onShift(t,104) and Contracts.onShift(t,105)
        and Contracts.nextDay(t,104)==4 and Contracts.nextStart(t,104)==105)
    local d,p,productive=Contracts.shiftMetrics(t,4)
    check("opening_contract_break_estimate_uses_effective_length",d==5 and p==4.25 and productive==4)
    t=terms(16,18,6);a,b=Contracts.shiftBounds(t,1);d,p,productive=Contracts.shiftMetrics(t,1)
    check("opening_contract_friday_evening_clips_without_phantom_lunch",a==42 and b==44 and d==2 and p==2 and productive==2)
    local w=worker(t);Payroll.accrue(w,42,54,false)
    check("opening_payroll_cannot_accrue_closed_friday_tail",w.weeks[1].paidHours==2 and Payroll.balance(w,100,true)==4400)
    Payroll.accrue(w,44,44.25,true)
    check("opening_payroll_preserves_paid_safe_shutdown_work",w.weeks[1].paidHours==2.25 and Payroll.balance(w,100,true)==4950)
    t=terms(96,9,17);check("opening_legacy_weekend_only_contract_valid_but_inactive",Contracts.valid(t) and Contracts.weeklyEstimate(t)==0
        and not Contracts.nextStart(t,44) and Contracts.nextDay(t,44)==8 and not Contracts.onShift(t,57))
    w=worker(t);Payroll.accrue(w,48,96,false);check("opening_payroll_no_weekend_buckets",#w.weeks==0)
    t=terms(64,22,10);a,b=Contracts.shiftBounds(t,3)
    check("opening_legacy_sunday_overnight_only_attends_monday_tail",a==105 and b==106 and Contracts.weeklyEstimate(t)==22
        and not Contracts.onShift(t,94) and Contracts.onShift(t,105.5))
    local s=State.new();local employee,applicant=hire(s);employee.contract=terms(96,9,17)
    employee.weeks={{week=-3,dueAtHours=105,paidHours=2,earnedCents=4400,paidCents=1000,notified=false}}
    local snapshot=Schema.snapshot(s)
    check("opening_legacy_contract_and_earned_debt_survive_snapshot",Schema.validState(snapshot) and snapshot.employment.staff[1].contract.days==96
        and snapshot.employment.staff[1].weeks[1].earnedCents==4400 and Payroll.balance(employee,200,true)==3400)
    local f=Finance.summary(s)
    check("opening_legacy_closed_schedule_has_no_future_capacity_or_wage_reserve",f.weeklyWages==0 and f.capacity==0 and f.earnedUnpaid==34
        and require("src.household_finances").reserves(s).payroll==0)
    check("opening_staff_explains_legacy_closed_schedule",Hiring.staffScheduleStatus(s,employee)=="No open shift")
    employee.contract=terms(31,9,17);local weekday=Finance.summary(s)
    employee.contract.days=127;local allDays=Finance.summary(s)
    check("opening_staff_forecast_weekend_bits_do_not_add_capacity",weekday.weeklyWages==allDays.weeklyWages and weekday.capacity==allDays.capacity
        and weekday.cycleReserve==allDays.cycleReserve and weekday.capacity>0)
    employee.contract=terms(1,6,14);employee.visible=true;employee.clockedIn=true;employee.phase="idle";employee.shiftDay=4;employee.breaksTaken=0
    s.calendar=Calendar.dateFromHours(105);s.calendar.elapsed=9/24*Calendar.secondsPerDay(s)
    require("src.employee_ai").worker(s,employee,.1,105,{idlePoint=function(w) return {x=w.x,y=w.y} end,freeSeat=function() return nil end})
    check("opening_monday_late_start_does_not_take_immediate_break",employee.phase~="break" and employee.breaksTaken==0)
    s.calendar=Calendar.dateFromHours(57);s.calendar.elapsed=9/24*Calendar.secondsPerDay(s)
    local title,detail=Hiring.staffScheduleStatus(s,employee)
    check("opening_staff_displays_next_actual_shift",title=="Shop closed / work waiting" and detail:find("09:00",1,true))
    local fresh=State.new();local app=assert(Employees.createApplicant(fresh,0));app.shiftPreference="flexible"
    assert(Employees.requestResume(fresh,app.id,0));Employees.advance(fresh,.5)
    local revision=app.revision
    check("opening_new_weekend_only_offer_rejected_atomically",not Employees.command(fresh,{kind="offer_employee",applicationId=app.id,
        expectedRevision=revision,wageCents=2500,days=96,startHour=9,endHour=17},.5) and app.revision==revision and app.offer==nil)
    local ui=Hiring.new();ui.selectedId=app.id;ui.view="offer";ui.terms=terms(96,9,17)
    local sent=false;local x,y=Hiring.buttonCenter("send")
    local result=Hiring.mousepressed(fresh,ui,x,y,function() sent=true end,false)
    check("opening_offer_gui_does_not_send_closed_only_terms",result.action=="blocked" and not sent)
    app.status="offer_accepted";app.offer=terms(96,9,17)
    check("opening_legacy_accepted_closed_offer_cannot_hire",not Employees.command(fresh,{kind="hire_employee",applicationId=app.id,
        expectedRevision=revision},1) and app.revision==revision and #fresh.employment.staff==0 and app.status=="offer_accepted")
    ui.view="detail";x,y=Hiring.buttonCenter("sign")
    result=Hiring.mousepressed(fresh,ui,x,y,function() sent=true end,false)
    check("opening_legacy_accepted_offer_gui_blocks_sign",result.action=="blocked" and not sent)
    local before=employee.contract;local oldRevision=before.revision
    check("opening_change_to_closed_only_hours_rejected_atomically",not Employees.command(s,{kind="change_employee_hours",employeeId=employee.id,
        expectedRevision=oldRevision,days=96,startHour=9,endHour=17},57) and employee.contract==before
        and before.revision==oldRevision and employee.pendingSchedule==nil and Payroll.balance(employee,200,true)==3400)
    ui.view="offer"
    ui.terms=terms(31,18,6)
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    if folder then
        local canvas=love.graphics.newCanvas(960,678);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.04,.06,.07,1)
        Hiring.draw(fresh,ui,nil,nil,false);love.graphics.pop()
        local data=canvas:newImageData();local bytes=data:encode("png");local file=assert(io.open(folder.."/home-effective-shift-offer.png","wb"))
        file:write(bytes:getString());file:close();bytes:release();data:release();canvas:release()
    end
end
return Test
