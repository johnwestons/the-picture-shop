local State=require("src.state")
local Schema=require("src.save_schema")
local Employees=require("src.employees")
local Contracts=require("src.employment_contracts")
local Payroll=require("src.payroll")
local Labor=require("src.employee_labor")
local Schedule=require("src.employee_schedule")
local AI=require("src.employee_ai")
local Work=require("src.employee_work")
local Jobs=require("src.jobs")
local Service=require("src.job_service")
local Fleet=require("src.machine_fleet")
local Calendar=require("src.business_calendar")
local Office=require("src.office_authority")
local Ui=require("src.screens.ui")
local Test={}
local function hours(s,h) local pace=Calendar.secondsPerDay(s);s.calendar=Calendar.dateFromTotalDay(math.floor(h/24));s.calendar.secondsPerDay=pace;s.calendar.elapsed=h%24/24*Calendar.secondsPerDay(s) end
local function hire(s,wage)
    local a=Employees.createApplicant(s,0)
    Employees.requestResume(s,a.id,0);Employees.advance(s,.5)
    local startHour=a.shiftPreference=="night" and 21 or 9
    local endHour=a.shiftPreference=="night" and 5 or 17
    assert(Employees.command(s,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,
        wageCents=wage or math.max(2200,a.requestedWage),days=31,
        startHour=startHour,endHour=endHour},.5))
    Employees.advance(s,1.25);assert(Employees.command(s,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    local w=s.employment.staff[#s.employment.staff];w.visible=true;w.clockedIn=true;w.phase="working";hours(s,9);return w
end
local function offer(id,press)
    return assert(Jobs.createOffer({id=id,company="Employee cost client",sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500},
        press=press and {colors=1,colorSequence={"Black"},artworkSize={width=5,height=7},coverage=.4} or nil}))
end
local function near(a,b) return math.abs(a-b)<1e-6 end
function Test.run(context,check)
    local state=State.new();state.calendar.secondsPerDay=300;local job=offer("JOB-LABOR-QUOTE")
    local baseline=Service.quoteTerms(state,job)
    check("employee_billing_owner_only_quote_keeps_existing_service_price",baseline.recommendedPrice==150 and baseline.employeeBudget==nil)
    local w=hire(state)
    local low=Service.quoteTerms(state,job)
    check("employee_billing_quote_discloses_negotiated_labor_without_double_surcharge",low.employeeBudget and low.employeeBudget.wagePerHour==22
        and low.employeeBudget.laborCost>0 and low.recommendedPrice==150 and job.quote.totalPrice==150)
    hire(state,10000)
    local high=Service.quoteTerms(state,job)
    check("employee_billing_high_wages_raise_price_to_cover_cost_and_margin",high.recommendedPrice>low.recommendedPrice and high.employeeBudget.wagePerHour==100)
    check("employee_billing_repeat_estimate_never_compounds_labor",Service.quoteTerms(state,job).recommendedPrice==high.recommendedPrice and job.quote.totalPrice==150)
    local trial=offer("JOB-LABOR-TRIAL");trial.quote.servicePrice=120;trial.quote.recommendedPrice=120;trial.quote.totalPrice=120
    local trialTerms=Service.quoteTerms(state,trial)
    check("employee_billing_trial_pricing_still_covers_staff_cost_floor",trialTerms.recommendedPrice>=trialTerms.employeeBudget.minimumCuttingCharge)
    local printing=offer("JOB-LABOR-PRINT",true);local pressAllowance=printing.quote.pressBudget.laborCost
    local printTerms=Service.quoteTerms(state,printing)
    check("employee_billing_press_quote_covers_employee_time_without_mutating_press_allowance",
        printTerms.recommendedPrice>=high.recommendedPrice+printing.quote.pressBudget.recommendedCharge
            and printTerms.employeeBudget.minimumCuttingCharge>high.employeeBudget.minimumCuttingCharge
            and printing.quote.pressBudget.laborCost==pressAllowance)
    local wallet=state.money
    local accepted,result=Service.submitQuote(state,job,high.recommendedPrice,1)
    local agreed=job.quote.totalPrice
    check("employee_billing_staff_quote_accepts_and_records_correct_receivable",accepted and result.accepted and state.accountsReceivable==agreed and state.money==wallet)
    state.employment.staff[2].contract.wageCents=5000
    check("employee_billing_accepted_price_stays_fixed_when_wages_change",Service.quoteTerms(state,job).recommendedPrice==agreed and job.quote.totalPrice==agreed
        and not Service.submitQuote(state,job,1,2) and job.quote.totalPrice==agreed)
    w.assignment={jobId=job.id,palletId=job.pallets[1].id,machineId="MCH-0001"};w.reserved=true
    Payroll.accrue(w,9,10,false,state)
    check("employee_billing_actual_job_hours_allocate_exact_wages",near(job.labor.paidHours,1) and near(job.labor.wageCents,2200)
        and near(w.laborTotals.jobCents,2200) and state.money==wallet)
    w.reserved=false;w.phase="idle";Payroll.accrue(w,10,10.5,false,state)
    w.phase="break";w.breakKind="rest";Payroll.accrue(w,11,11.25,false,state)
    check("employee_billing_waiting_and_paid_breaks_are_shop_cost",near(w.laborTotals.shopHours,.75) and near(w.laborTotals.shopCents,1650) and near(job.labor.wageCents,2200))
    w.breakKind="meal";local unpaid=Payroll.accrue(w,13,13.5,false,state)
    check("employee_billing_unpaid_meals_create_no_payroll_or_job_cost",unpaid==0 and near(w.laborTotals.shopCents,1650))
    w.phase="working";w.breakKind=nil;w.reserved=true
    Payroll.accrue(w,17,17.25,true,state)
    check("employee_billing_safe_cycle_after_shift_is_allocated_and_paid",near(job.labor.wageCents,2750) and near(job.labor.paidHours,1.25))
    w.visible=false;local offsite=Payroll.accrue(w,24,105,false,state)
    check("employee_billing_offsite_shift_gap_accrues_no_wages",offsite==0 and near(job.labor.wageCents,2750))
    local saved=Schema.snapshot(state);local loaded=State.new()
    check("employee_billing_actual_costs_survive_saved_shop_and_shared_state",saved and State.applyLocalSave(loaded,{state=saved,slot=1})
        and near(loaded.jobs.active[1].labor.wageCents,2750) and near(loaded.employment.staff[1].laborTotals.shopCents,1650))
    local shared=State.new()
    check("employee_billing_guests_receive_host_job_costs_and_quote_budget",State.applySharedSnapshot(shared,saved)
        and near(shared.jobs.active[1].labor.wageCents,2750) and shared.jobs.active[1].quote.employeeBudget.employeeId==job.quote.employeeBudget.employeeId)
    local bad=Schema.copy(saved);bad.jobs.active[1].labor.wageCents=0/0
    check("employee_billing_malformed_job_wages_are_rejected",not Schema.validState(bad) and Schema.snapshot(bad)==nil)
    bad=Schema.copy(saved);bad.jobs.active[1].quote.employeeBudget.employeeId="1"
    check("employee_billing_budget_cannot_alias_human_player",not Schema.validState(bad))
    local legacy={version=18,slot=1,createdAt=1,updatedAt=1,player={x=500,y=455},state=Schema.copy(saved)}
    legacy.state.employment.version=2
    for _,old in ipairs(legacy.state.employment.staff) do old.laborTotals=nil end
    local migrated=Schema.migrate(legacy)
    check("employee_billing_v18_migration_retains_queues_wages_and_agreed_prices",migrated and migrated.version==21 and migrated.state.employment.version==6
        and near(migrated.state.employment.staff[1].laborTotals.shopCents,4400) and migrated.state.jobs.active[1].quote.totalPrice==agreed
        and legacy.state.employment.staff[1].laborTotals==nil)
    -- The Bills page and Payroll settle the same obligations exactly once.
    hours(state,105);Calendar.addCharge(state,"Billing fixture claim",100,job.id)
    local due,operating,wages=Calendar.amountDue(state)
    check("employee_billing_total_due_includes_weekly_wages_once",near(due,144) and operating==100 and near(wages,44))
    local office=Office.command({state=state,save=function() end,world={validateNetworkWorkshopAccess=function() return true end}})
    local guest,code=office.perform({}, {id=2},{officeIntent={kind="pay_bills"}})
    check("employee_billing_guest_cannot_bypass_owner_payroll_policy",not guest and code=="owner_only" and Calendar.amountDue(state)==due)
    state.money=143.99;local cannotPay=Calendar.pay(state)
    check("employee_billing_insufficient_cash_changes_neither_bills_nor_payroll",not cannotPay and state.money==143.99 and Calendar.amountDue(state)==due)
    state.money=1000;local paid,spent=Calendar.pay(state)
    check("employee_billing_pay_all_settles_bills_and_wages_once",paid and near(spent,144) and near(state.money,856) and Calendar.amountDue(state)==0)
    Payroll.pay(state,105,false);local again=Calendar.pay(state)
    check("employee_billing_weekly_auto_pay_cannot_charge_paid_bill_again",not again and near(state.money,856) and near(job.labor.wageCents,2750))
    local cents=State.new();local cw=hire(cents,2215)
    Payroll.accrue(cw,9,9.25,false,cents);hours(cents,105);cents.money=100
    check("employee_billing_due_and_display_retain_cents",near(Calendar.amountDue(cents),5.54) and Ui.money(Calendar.amountDue(cents))=="$5.54")
    Calendar.pay(cents)
    check("employee_billing_cents_settle_without_fractional_debt",near(cents.money,94.46) and Payroll.total(cents,105,true)==0)
    local overtime=State.new();local ow=hire(overtime);local oj=offer("JOB-LABOR-OVERTIME");Jobs.accept(oj);overtime.jobs.active[1]=oj
    ow.assignment={jobId=oj.id,palletId=oj.pallets[1].id,machineId="MCH-0001"};ow.reserved=true
    ow.weeks={{week=-3,dueAtHours=105,paidHours=39.75,earnedCents=87450,paidCents=0,notified=false}};ow.laborTotals=Labor.fromWeeks(ow.weeks)
    Payroll.accrue(ow,9,9.5,false,overtime)
    check("employee_billing_actual_overtime_is_allocated_to_job",near(oj.labor.wageCents,1375) and near(ow.weeks[1].earnedCents,88825))
    -- Navigate actual computer renderers, including a due-wage guest view.
    local computer=context.computerScreen.new();computer.enter(state)
    for _,tab in ipairs({"bills","hiring","active"}) do
        computer.tab=tab;computer.hiring.section="payroll";computer.selectedJobId=job.id
        love.graphics.push("all");local okay,err=pcall(computer.draw,state,nil,nil,context.assets);love.graphics.pop()
        check("employee_billing_"..tab.."_page_draws",okay,tostring(err))
    end
    -- Real cutter progress must resume after Friday, a weekend and save/reload.
    local continuation=State.new();local worker=hire(continuation);worker.pressSkill,worker.wrappingSkill=60,50
    local first=offer("JOB-NEXT-SHIFT-A");local second=offer("JOB-NEXT-SHIFT-B")
    for _,j in ipairs({first,second}) do Jobs.accept(j);continuation.jobs.active[#continuation.jobs.active+1]=j end
    local machine=Fleet.installedUnits(continuation,"polar_115")[1]
    for _,j in ipairs({first,second}) do
        context.PalletLogistics.unload(continuation,j.id,j.pallets[1].id,context.config.palletLogistics.spawnPoints,context.config.palletLogistics.unloadOrigin)
        assert(Employees.command(continuation,{kind="queue_employee_job",employeeId=worker.id,jobId=j.id,machineId=machine.id},9))
    end
    local ix,iy=context.CutterZones.inputAnchor(continuation,context.config.cutterPlacement)
    for _,j in ipairs({first,second}) do local p=j.pallets[1];p.world.x,p.world.y=ix,iy;p.world.fromX,p.world.fromY=ix,iy;p.world.spawnProgress=1 end
    context.machine.reset(continuation)
    local oldResolver=context.machine.forId(machine.id).outputResolver
    context.machine.setOutputResolver(function()
        return {x=continuation.wrapper.x+80,y=continuation.wrapper.y,direction="northwest"}
    end)
    local oldMove=AI.move
    AI.move=function(actor,goal) actor.x,actor.y=goal.x,goal.y;actor.moving=false;return true end
    local okay,err=pcall(function()
        worker.breaksTaken=7;hours(continuation,40.9)
        local wc={canClaim=function() return true end,operatorPoint=function() return {x=700,y=470} end,idlePoint=function(a) return {x=a.x,y=a.y} end,freeSeat=function() end}
        local cutter=context.machine.forId(machine.id)
        for i=1,600 do AI.worker(continuation,worker,.1,40.9,wc);context.machine.updateAll(.1,continuation)
            if cutter.step=="cutting" and cutter.paper.activeCut==2 then break end end
        check("employee_shift_end_waits_only_for_running_safe_cycle",cutter.step=="cutting" and cutter.paper.activeCut==2)
        AI.worker(continuation,worker,.1,41,wc)
        check("employee_shift_end_retains_assignment_during_blade_cycle",worker.visible and worker.reserved and worker.assignment.jobId==first.id)
        for i=1,100 do context.machine.updateAll(.1,continuation);if Work.safe(worker) then break end end
        AI.worker(continuation,worker,.1,41,wc)
        if worker.phase=="leaving" and worker.greetingUntilHours then
            AI.worker(continuation,worker,.1,math.max(41,worker.greetingUntilHours),wc)
        end
        local history=#first.pallets[1].paper.history
        check("employee_shift_end_leaves_with_unfinished_job_and_cut_progress",not worker.visible and not worker.clockedIn and not worker.reserved
            and worker.assignment.jobId==first.id and #worker.schedule.items==2 and history==2,
            "visible="..tostring(worker.visible).." clocked="..tostring(worker.clockedIn)
                .." reserved="..tostring(worker.reserved)
                .." assignment="..tostring(worker.assignment and worker.assignment.jobId)
                .." queued="..#worker.schedule.items.." history="..history
                .." phase="..tostring(worker.phase).." activity="..tostring(worker.activity))
        hours(continuation,41);local carry=Schema.snapshot(continuation);local resumed=State.new()
        assert(carry and State.applyLocalSave(resumed,{state=carry,slot=1}))
        worker=resumed.employment.staff[1];context.machine.reset(resumed)
        AI.worker(resumed,worker,.1,58,wc)
        check("employee_day_off_keeps_job_queued_without_work_or_wages",not worker.visible and worker.assignment.jobId==first.id
            and #resumed.jobs.active[1].pallets[1].paper.history==history and Payroll.accrue(worker,41,105,false,resumed)==0)
        hours(resumed,105)
        AI.worker(resumed,worker,.1,105,wc)
        check("employee_next_agreed_shift_reclaims_same_unfinished_pallet",worker.visible and worker.clockedIn and worker.assignment.jobId==first.id
            and worker.assignment.palletId==first.pallets[1].id)
        for i=1,3000 do AI.worker(resumed,worker,.1,105,wc);context.machine.updateAll(.1,resumed);context.wrapper.updateAll(.1,resumed)
            if #worker.schedule.items==0 and #resumed.employment.teamSchedule.items==0 and not worker.assignment then break end end
        local teamRow=resumed.employment.teamSchedule.items[1]
        local teamBlock
        if teamRow then local _,_,_,reason=Schedule.resolve(resumed,worker,teamRow);teamBlock=reason end
        check("employee_next_shift_finishes_remaining_cuts_then_next_job_exactly_once",#worker.schedule.items==0 and #worker.schedule.history==2
            and resumed.inventory.finishedPallets==2 and resumed.jobs.active[1].pallets[1].finishedSheets==500
            and resumed.jobs.active[2].pallets[1].finishedSheets==500,
            "personal="..#worker.schedule.items.." team="..#resumed.employment.teamSchedule.items
                .." assignment="..tostring(worker.assignment and worker.assignment.jobId)
                .." activity="..tostring(worker.activity)
                .." first="..resumed.jobs.active[1].pallets[1].status..":"..resumed.jobs.active[1].pallets[1].finishedSheets
                .." second="..resumed.jobs.active[2].pallets[1].status..":"..resumed.jobs.active[2].pallets[1].finishedSheets
                .." wrapper="..tostring(resumed.wrapper.step)
                .." row="..tostring(resumed.employment.teamSchedule.items[1]
                    and resumed.employment.teamSchedule.items[1].jobId)
                .." enabled="..tostring(resumed.employment.teamSchedule.enabled)
                .." shift="..tostring(Contracts.onShift(worker.contract,105))
                .." visible="..tostring(worker.visible).." clocked="..tostring(worker.clockedIn)
                .." skills="..worker.cutterSkill..","..worker.pressSkill..","..worker.wrappingSkill
                .." paper="..tostring(resumed.jobs.active[1].pallets[1].paper.status)
                ..":"..tostring(resumed.jobs.active[1].pallets[1].paper.activeCut)
                .." remaining="..tostring(resumed.jobs.active[1].pallets[1].remainingSheets)
                .." loaded="..tostring(resumed.jobs.active[1].pallets[1].status)
                ..":"..tostring(resumed.jobs.active[1].pallets[1].location)
                .." blocker="..tostring(teamBlock))
    end)
    AI.move=oldMove;context.machine.setOutputResolver(oldResolver);context.machine.reset(continuation)
    if not okay then error(err) end
end
return Test
