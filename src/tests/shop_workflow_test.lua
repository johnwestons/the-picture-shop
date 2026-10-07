local State=require("src.state")
local Schema=require("src.save_schema")
local Calendar=require("src.business_calendar")
local Employees=require("src.employees")
local Contracts=require("src.employment_contracts")
local Payroll=require("src.payroll")
local AI=require("src.employee_ai")
local Jobs=require("src.jobs")
local Fleet=require("src.machine_fleet")
local Finances=require("src.staff_finances")
local Credit=require("src.credit")
local Guide=require("src.cutter_cut_guide")
local Staging=require("src.cutter_staging")
local Setup=require("src.screens.shop_setup_screen")
local Clock=require("src.screens.shop_clock")
local Hiring=require("src.screens.hiring_screen")
local Test={}
local function near(a,b) return math.abs(a-b)<1e-5 end
local function hours(s,h)
    local pace=Calendar.secondsPerDay(s)
    s.calendar=Calendar.dateFromTotalDay(math.floor(h/24));s.calendar.secondsPerDay=pace
    s.calendar.elapsed=h%24/24*pace
end
local function hire(s,terms)
    local a=Employees.createApplicant(s,0)
    -- Payroll scenarios exercise arbitrary shift terms at a fixed wage.
    a.shiftPreference="flexible"
    Employees.requestResume(s,a.id,0);Employees.advance(s,.5)
    assert(Employees.command(s,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,
        wageCents=terms.wageCents,days=terms.days,startHour=terms.startHour,endHour=terms.endHour,payWeeks=terms.payWeeks},.5))
    Employees.advance(s,1.25)
    assert(Employees.command(s,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    local w=s.employment.staff[#s.employment.staff]
    w.visible=true;w.clockedIn=true;w.phase="idle"
    return w,a
end
local function job(s,id,x,y)
    local j=assert(Jobs.createOffer({id=id,company="Shop workflow test",sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts={500}}))
    Jobs.accept(j);s.jobs.active[#s.jobs.active+1]=j
    local p=j.pallets[1]
    p.location="warehouse";p.world={x=x,y=y,fromX=x,fromY=y,direction="northwest",rotation=1,spawnProgress=1}
    return j,p
end
local function paidWeek(s,w,weekStart)
    for day=weekStart,weekStart+6 do
        if Contracts.hasDay(w.contract.days,Contracts.weekday(day)) then
            local start=day*24+w.contract.startHour
            -- Paid rest breaks are included; exclude the half-hour meal.
            Payroll.accrue(w,start,start+4,false,s)
            Payroll.accrue(w,start+4.5,start+Contracts.duration(w.contract),false,s)
        end
    end
end
function Test.run(context,check)
    for minutes=5,60 do
        local payload=context.save.newGame(1,{dayLengthMinutes=minutes})
        local s=State.new();State.applyLocalSave(s,payload)
        Calendar.update(s,minutes*30)
        check("shop_setup_persists_clock_pace_"..minutes,payload.state.calendar.secondsPerDay==minutes*60
            and near(Calendar.absoluteHours(s),12) and Calendar.timeText(s)=="12:00"
            and Schema.snapshot(s).calendar.secondsPerDay==minutes*60)
    end
    for i,value in ipairs({4,61,5.5,"20",0/0,math.huge}) do
        check("shop_setup_rejects_invalid_pace_"..i,context.save.newGame(1,{dayLengthMinutes=value})==nil)
    end
    local options=Setup.new();options.dayLengthMinutes=5;Setup.keypressed(options,"left")
    check("shop_setup_lower_bound_and_keyboard",options.dayLengthMinutes==5)
    options.dayLengthMinutes=60;Setup.keypressed(options,"up")
    check("shop_setup_upper_bound_and_keyboard",options.dayLengthMinutes==60)
    Setup.mousepressed(options,480,402)
    check("shop_setup_slider_selects_intermediate_minute",options.dayLengthMinutes==33)
    for _,name in ipairs({"fast","standard","slow"}) do
        local x,y=Setup.buttonCenter(name);Setup.mousepressed(options,x,y)
        check("shop_setup_preset_"..name,options.dayLengthMinutes==(name=="fast" and 5 or name=="slow" and 60 or 20))
    end
    local old=State.new();local oldWorker=hire(old,Contracts.terms(2200,31,9,17,1))
    hours(old,10);Payroll.accrue(oldWorker,9,10,false,old)
    local legacy={version=19,slot=1,player={x=500,y=455},state=Schema.snapshot(old)}
    legacy.state.calendar.secondsPerDay=nil;legacy.state.calendar.elapsed=125
    legacy.state.employment.version=3;legacy.state.employment.lastAtHours=10
    for _,w in ipairs(legacy.state.employment.staff) do w.contract.payWeeks=nil end
    for _,a in ipairs(legacy.state.employment.applications) do if a.offer then a.offer.payWeeks=nil end end
    local migrated=Schema.migrate(legacy)
    check("shop_v19_migration_keeps_legacy_clock_and_weekly_pay",migrated and migrated.version==21
        and migrated.state.calendar.secondsPerDay==300 and near(Calendar.absoluteHours(migrated.state),10)
        and migrated.state.employment.staff[1].contract.payWeeks==1
        and near(migrated.state.employment.staff[1].weeks[1].earnedCents,2200)
        and legacy.state.employment.staff[1].contract.payWeeks==nil)
    local bad=Schema.snapshot(old);bad.calendar.secondsPerDay=299
    check("shop_saved_invalid_pace_rejected",not Schema.validState(bad) and not Schema.snapshot(bad))
    local nightly=Contracts.terms(2200,64,20,8,4);nightly.startDay=3
    check("shop_night_shift_uses_start_day_across_week_boundary",Contracts.validTerms(nightly)
        and Contracts.onShift(nightly,3*24+21) and Contracts.onShift(nightly,4*24+7.99)
        and not Contracts.onShift(nightly,4*24+8) and not Contracts.onShift(nightly,4*24+20))
    for hoursLong=4,12 do
        local t=Contracts.terms(2200,31,20,(20+hoursLong)%24,1)
        check("shop_contract_accepts_day_and_night_length_"..hoursLong,Contracts.validTerms(t))
    end
    check("shop_contract_rejects_excessive_or_empty_shifts",not Contracts.validTerms(Contracts.terms(2200,31,8,21))
        and not Contracts.validTerms(Contracts.terms(2200,31,8,8)))
    local night=State.new();local nw=hire(night,Contracts.terms(2200,64,20,8,4));nw.contract.startDay=3
    Payroll.accrue(nw,3*24+20,4*24+8,false,night)
    check("shop_night_payroll_splits_actual_week_without_double_pay",#nw.weeks==2
        and near(nw.weeks[1].paidHours,4) and near(nw.weeks[2].paidHours,8)
        and near(Payroll.balance(nw,0,true),12*2200))
    local nightContext={idlePoint=function(w) return {x=w.x,y=w.y} end,freeSeat=function() end}
    nw.shiftDay=3;nw.breaksTaken=7;nw.fatigue=0;nw.focus=100;hours(night,4*24+6)
    AI.worker(night,nw,.1,4*24+6,nightContext)
    check("shop_twelve_hour_shift_has_third_paid_rest",nw.phase=="break" and nw.breakKind=="rest" and nw.breaksTaken==15 and nw.shiftDay==3)
    for cycle=1,4 do
        local s=State.new();s.money=100000
        local w=hire(s,Contracts.terms(2200,31,8,20,cycle));w.contract.startDay=4
        for week=0,cycle-1 do paidWeek(s,w,4+week*7) end
        local due=(4+cycle*7)*24+9
        check("shop_pay_cycle_accrues_without_instant_cash_charge_"..cycle,s.money==100000
            and near(Payroll.balance(w,due-1e-5,true),145750*cycle)
            and Payroll.balance(w,due-1e-5,false)==0 and not Payroll.pay(s,due-1e-5,false))
        Payroll.pay(s,due,false);local wallet=s.money
        check("shop_pay_cycle_settles_exactly_once_with_weekly_overtime_"..cycle,
            near(wallet,100000-1457.5*cycle) and not Payroll.pay(s,due,false) and s.money==wallet
            and #w.weeks==cycle and near(w.weeks[1].paidHours,57.5))
    end
    for _,minutes in ipairs({5,20,60}) do for _,endHour in ipairs({20,8}) do
        local s=State.new();s.calendar.secondsPerDay=minutes*60;s.money=100000
        local w=hire(s,Contracts.terms(2200,31,endHour==20 and 8 or 20,endHour,4))
        assert(Credit.financeMachine(s,1,"SHOP-BUDGET-"..minutes.."-"..endHour,"online"))
        local f=Finances.summary(s);local p=Finances.plan(f,20)
        local quoteJob=assert(Jobs.createOffer({id="JOB-PROFIT-"..minutes.."-"..endHour,
            company="Shop workflow test",sourceSize={width=20,height=16},
            finishedSize={width=10,height=8},sheetCounts={500}}))
        local quote=context.jobService.quoteTerms(s,quoteJob)
        check("shop_regular_twelve_hour_staff_can_profit_at_pace_"..minutes.."_end_"..endHour,
            near(f.weeklyWages,1457.5) and f.weeklyLoans>0 and p.profit>0 and p.withinCapacity
            and f.breakEvenLifts<20 and near(f.cycleReserve,5830) and quote.recommendedPrice>=f.pricePerLift,
            string.format("wages=%s loans=%s profit=%s capacity=%s breakEven=%s reserve=%s quote=%s lift=%s",
                tostring(f.weeklyWages),tostring(f.weeklyLoans),tostring(p.profit),tostring(p.withinCapacity),
                tostring(f.breakEvenLifts),tostring(f.cycleReserve),tostring(quote.recommendedPrice),tostring(f.pricePerLift)))
        check("shop_idle_payroll_does_not_claim_a_profit_"..minutes.."_end_"..endHour,
            Finances.plan(f,0).profit<0 and Finances.plan(f,f.breakEvenLifts).profit>=0)
    end end
    local s=State.new();s.money=5000;local w=hire(s,Contracts.terms(2200,31,8,20,4))
    Payroll.accrue(w,8,10,false,s);s.bills.balance=100
    local f=Finances.summary(s)
    check("shop_budget_reserves_earned_wages_before_spending",near(f.freeCash,4856) and near(f.earnedUnpaid,44))
    local longer=Contracts.terms(2200,31,8,20,1);local shorter=Finances.summary(s,longer)
    longer.payWeeks=4;local more=Finances.summary(s,longer)
    check("shop_longer_pay_cycle_changes_cash_reserve_not_profit",near(shorter.weeklyFixed,more.weeklyFixed)
        and more.cycleReserve>shorter.cycleReserve and near(Finances.plan(shorter,20).profit,Finances.plan(more,20).profit))
    local h=Hiring.new();h.section="payroll"
    local x,y=Hiring.buttonCenter("finances")
    local commands=0
    Hiring.mousepressed(s,h,x,y,function() commands=commands+1 end,true)
    x,y=Hiring.buttonCenter("liftsPlus");Hiring.mousepressed(s,h,x,y,function() commands=commands+1 end,true)
    local renderOkay,err=pcall(Hiring.draw,s,h,nil,nil,true)
    check("shop_budget_guest_can_plan_without_mutating_shop",h.view=="finances" and h.lifts==21 and commands==0 and s.money==5000 and renderOkay,err)
    local paper=require("src.paper_work").createStockPaper()
    for cut=1,4 do for turn=0,3 do
        paper.activeCut=cut;paper.orientation=turn*90
        local g=Guide.current(paper,cut)
        check("shop_cutter_active_margin_tracks_rotation_"..cut.."_"..turn,
            g.number==cut and (g.screenEdge=="bottom")==g.rotationReady
            and g.rotationReady==(paper.orientation==paper.cuts[cut].orientation)
            and Guide.band(g,0,0,150,100,20,16)~=nil)
    end end
    paper.activeCut=5
    check("shop_cutter_completed_paper_has_no_next_cut_highlight",Guide.current(paper)==nil)
    local staged=State.new();context.machine.reset(staged)
    local slots=Staging.slots()
    for i,slot in ipairs(slots) do
        local output=context.world.findCutterOutput(staged,context.assets)
        check("shop_staging_fills_slot_in_order_"..i,output and output.x==slot.x and output.y==slot.y,
            output and (output.x..","..output.y) or "No safe slot")
        job(staged,"JOB-STAGE-"..i,slot.x,slot.y)
    end
    check("shop_staging_full_waits_for_space",context.world.findCutterOutput(staged,context.assets)==nil)
    table.remove(staged.jobs.active,3)
    local hole=context.world.findCutterOutput(staged,context.assets)
    check("shop_staging_reuses_first_available_space",hole and hole.x==slots[3].x and hole.y==slots[3].y)
    local reserved=State.new();reserved.money=100000
    assert(Fleet.buy(reserved,"dealer",1))
    local units=Fleet.installedUnits(reserved,"polar_115")
    local first=context.machine.forId(units[1].id);local second=context.machine.forId(units[2].id)
    first.pallet={id="PENDING-ONE"};first.pendingOutput=slots[1]
    second.pallet={id="PENDING-TWO"};second.pendingOutput=slots[2]
    local a=context.world.findCutterOutput(reserved,context.assets,"PENDING-ONE")
    local b=context.world.findCutterOutput(reserved,context.assets,"PENDING-TWO")
    check("shop_two_cutters_keep_distinct_staging_reservations",a and b and a.number==1 and b.number==2)
    first.pendingOutput=nil;second.pendingOutput=nil;first.pallet=nil;second.pallet=nil
    local returning=State.new();context.machine.reset(returning)
    local j,p=job(returning,"JOB-RETURN-CHECK",420,470)
    p.location="at_cutter";p.remainingSheets=0;p.finishedSheets=500;p.completedLifts=1;p.programVerified=true
    p.paper.status="complete";p.paper.activeCut=5;p.paper.currentSize=Schema.copy(p.paper.finishedSize)
    context.machine.pallet=p;context.machine.job=j;context.machine.paper=p.paper
    context.machine.loaded=true;context.machine.step="cut_complete";context.machine.programIndex=4
    returning.inventory.inProcessPallets=1
    local resolver=context.machine.outputResolver
    context.machine.setOutputResolver(function(target,pallet) return context.world.findCutterOutput(target,context.assets,pallet.id) end)
    assert(context.machine.unload(returning))
    for i,slot in ipairs(slots) do job(returning,"JOB-BLOCK-RETURN-"..i,slot.x,slot.y) end
    context.machine.update(context.machine.transferTime+.01,returning)
    check("shop_output_blocked_during_return_keeps_stock_and_retries",context.machine.step=="cut_complete" and p.location=="at_cutter"
        and context.machine.pendingOutput==nil and returning.inventory.finishedPallets==0)
    table.remove(returning.jobs.active,4)
    assert(context.machine.unload(returning));context.machine.update(context.machine.transferTime+.01,returning)
    check("shop_output_return_uses_newly_cleared_space_once",p.location=="cutter_output" and p.world.x==slots[3].x
        and p.world.y==slots[3].y and returning.inventory.finishedPallets==1,
        tostring(p.location).." / "..context.machine.step.." / "..tostring(returning.message))
    context.machine.setOutputResolver(resolver)
    local clockState=State.new();hours(clockState,3.5)
    local ha,ma=Clock.handAngles(clockState)
    check("shop_clock_analog_matches_digital_minutes",Calendar.timeText(clockState)=="03:30"
        and near(ha,3.5/12*math.pi*2-math.pi/2) and near(ma,math.pi/2))
    hours(clockState,24)
    check("shop_clock_rolls_date_at_midnight",Calendar.timeText(clockState)=="00:00" and clockState.calendar.day==2)
    local computer=context.computerScreen.new();computer.enter(clockState)
    computer.quoteFocused=true;computer.promoFocused=true
    check("shop_clock_computer_header_opens_live_clock",computer.mousepressed(clockState,800,118,1).action=="clock"
        and computer.tab=="clock" and not computer.quoteFocused and not computer.promoFocused)
    local c=context.config.interactables.shopClock
    local saves=0;local input={state=clockState,hud={hitTest=function() end},world={},saveCurrent=function() saves=saves+1 end,
        worldPointerCoordinates=function() return c.wallX,c.wallY end,isNetworkClient=function() return true end}
    clockState.screen="world"
    check("shop_clock_phone_world_tap_opens_for_guest",context.input.mousepressed(0,0,1,input) and clockState.screen=="shop_clock")
    check("shop_clock_closes_without_save_or_cash_changes",context.input.closeScreen(input) and clockState.screen=="world" and saves==0)
    local catalog=require("src.worker_catalog")
    local renderer=require("src.employee_renderer")
    local crew=State.new();crew.money=100000
    local directions={{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}}
    for i,profile in ipairs(catalog.profiles) do
        local employee=hire(crew,Contracts.terms(profile.requestedWage,31,8,20,4))
        check("shop_mouse_worker_can_negotiate_and_hire_"..i,employee.name==profile.name and employee.character==profile.character
            and employee.contract.payWeeks==4 and Contracts.duration(employee.contract)==12)
        local entry={worker=employee,actor=employee}
        for dir,v in ipairs(directions) do
            employee.intentX,employee.intentY=v[1],v[2];employee.moving=true;employee.distance=13*3
            local action,frame,mirror=renderer.pose(entry)
            local image,quad,count=context.characterAssets.get(employee.character,action,frame)
            employee.moving=false;local idle,idleFrame,idleMirror=renderer.pose(entry)
            local idleImage,_,idleCount=context.characterAssets.get(employee.character,idle,idleFrame)
            check("shop_mouse_worker_walk_idle_and_mirror_"..i.."_"..dir,image and quad and count==8 and frame==4
                and idleImage and idleCount==2 and mirror==idleMirror and (mirror==1 or mirror==-1))
        end
        employee.phase="working";local drawOkay,drawErr=pcall(renderer.draw,entry,context.characterAssets)
        check("shop_mouse_worker_uses_own_work_pose_"..i,drawOkay,drawErr)
        employee.phase="break";employee.seatBay="front_left";employee.breakRemaining=.2
        drawOkay,drawErr=pcall(renderer.draw,entry,context.characterAssets)
        check("shop_mouse_worker_uses_own_seated_pose_"..i,drawOkay,drawErr)
        employee.phase="idle";employee.seatBay=nil
    end
    local crewSnapshot=Schema.snapshot(crew);local guest=State.new()
    check("shop_three_worker_types_survive_shared_snapshot",crewSnapshot and State.applySharedSnapshot(guest,crewSnapshot)
        and guest.employment.staff[2].character=="tinker-fox-worker" and guest.employment.staff[3].character=="ferret-engineer-worker")
    local events=Calendar.events(crew);local shift,pay=false,false
    for _,event in ipairs(events) do shift=shift or event.kind=="shift";pay=pay or event.kind=="payroll" end
    check("shop_calendar_shows_agreed_shifts_and_contract_paydays",shift and pay)
    local sharedCapacity=Finances.summary(crew).capacity
    assert(Fleet.buy(crew,"dealer",1));assert(Fleet.buy(crew,"dealer",1))
    local parallelCapacity=Finances.summary(crew).capacity
    check("shop_budget_accounts_for_employees_sharing_one_cutter",parallelCapacity>sharedCapacity*2
        and Finances.summary(crew).weeklyWages==Finances.summary(guest).weeklyWages)
    for i,profile in ipairs(catalog.profiles) do
        local shop=State.new();shop.calendar.secondsPerDay=300;shop.employment.nextApplicantId=i
        hire(shop,Contracts.terms(profile.requestedWage,31,8,20,4))
        local plan=Finances.plan(Finances.summary(shop),20)
        check("shop_each_mouse_worker_is_profitable_at_requested_wage_"..i,plan.profit>0 and plan.withinCapacity)
    end
    context.characterAssets.retainCharacters({})
    context.machine.reset(context.state)
end
return Test
