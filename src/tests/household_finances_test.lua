local Finance=require("src.household_finances")
local State=require("src.state")
local Schema=require("src.save_schema")
local Calendar=require("src.business_calendar")
local Procurement=require("src.procurement")
local Home=require("src.home")
local Test={}
local function rich()
    local s=State.new();s.money=10000;s.inventory.paper=0;s.inventory.stock={};s.inventory.plasticWrapRolls=0;s.inventory.plasticWrapUses=0
    Finance.ensure(s);return s
end
local function stockTests(check)
    local s=rich();local bought,order=Procurement.buy(s,1,1,"salesman");assert(bought)
    local f=s.home.finance
    check("household_stock_purchase_is_basis_not_expense",f.stock.house_sheets.quantity==1000
        and f.stock.house_sheets.basisCents==10000 and f.totals.materials==0 and s.money==9900)
    local config=require("src.config")
    assert(Procurement.unload(s,order.id,order.pallets[1].id,config.palletLogistics.spawnPoints,config.palletLogistics.unloadOrigin))
    assert(Procurement.consumeHousePaper(s,100))
    check("household_consumed_stock_expensed_once",f.totals.materials==1000 and f.stock.house_sheets.basisCents==9000
        and f.stock.house_sheets.quantity==900 and s.money==9900)
    local before=Schema.copy(s)
    local ok=Procurement.consumeStockProducts(s,{{productId="house_sheets",quantity=100},
        {productId="shipping_cartons",quantity=1000000}})
    check("household_failed_batch_rolls_back_material_cost",not ok and f.totals.materials==1000
        and f.stock.house_sheets.basisCents==9000 and s.inventory.stock.house_sheets==900
        and order.pallets[1].remainingQuantity==900)
    assert(Procurement.consumeHousePaper(s,900))
    check("household_last_sheet_drains_cost_basis",f.stock.house_sheets.quantity==0
        and f.stock.house_sheets.basisCents==0 and f.totals.materials==10000)
    local legacy=Schema.copy(before);legacy.home.finance=nil
    local payload={version=26,slot=1,createdAt=1,updatedAt=2,player={x=320,y=400},state=legacy}
    local migrated=assert(Schema.migrate(payload)).state;local migratedFinance=Finance.ensure(migrated)
    check("household_legacy_stock_seeds_remaining_paid_basis",migratedFinance.stock.house_sheets.quantity==900
        and migratedFinance.stock.house_sheets.basisCents==9000 and migratedFinance.totals.materials==0)
    local Shop=require("src.shop")
    assert(Shop.buyPaper(s));assert(Procurement.consumeHousePaper(s,5))
    check("household_abstract_paper_tracks_paid_cost",f.totals.materials==10500 and f.stock.abstract_paper.basisCents==2000)
    Finance.purchase(s,"stretch_film",1,1709)
    for _=1,11 do Finance.consume(s,"stretch_film",1/11) end
    check("household_fractional_wrap_cost_conserves_cents",f.stock.stretch_film.quantity==0
        and f.stock.stretch_film.basisCents==0 and f.totals.materials==12209)
end
local function expenseTests(check)
    local s=rich();local f=s.home.finance
    Calendar.addCharge(s,"Customer refund",125,"JOB-REFUND","customer_refund")
    assert(Calendar.pay(s))
    check("household_refund_expense_not_repeated_at_payment",f.totals.refunds==12500 and s.money==9875)
    local worker={id="EMP-FINANCE",name="Finance test",visible=true,clockedIn=true,phase="idle",weeks={},
        status="employed",contract={role="cutter",wageCents=2000,days=31,startHour=9,endHour=17,
            payWeeks=1,startDay=0,signedAtHours=0,revision=1}}
    s.employment.staff={worker}
    require("src.payroll").accrue(worker,9,10,false,s)
    local reserves=Finance.reserves(s)
    check("household_wages_booked_when_earned_and_reserved",f.totals.wages==2000 and reserves.unpaid==2000)
    require("src.payroll").pay(s,1000,false)
    check("household_payroll_payment_does_not_reexpense",f.totals.wages==2000 and s.money==9855)
    for _=1,10000 do Finance.record(s,"wages",.01) end
    check("household_fractional_wages_keep_cents",f.totals.wages==2100 and f.fractions.wages<1e-6)
    local stepped,big=rich(),rich()
    for _=1,62*24 do Calendar.update(stepped,Calendar.secondsPerDay(stepped)/24) end
    Calendar.update(big,Calendar.secondsPerDay(big)*62)
    check("household_accrual_crosses_months_and_frame_sizes",stepped.home.finance.totals.operating==big.home.finance.totals.operating
        and big.home.finance.totals.operating==828225 and big.bills.balance==7950)
    local beforeOperating=big.home.finance.totals.operating
    big.money=100000;assert(Calendar.pay(big))
    check("household_operating_payment_not_double_counted",big.home.finance.totals.operating==beforeOperating)
    local financed=rich();financed.money=100000
    local Credit=require("src.credit")
    local opened,result=Credit.financeMachine(financed,1,"HOME-FINANCE-LOAN","online");assert(opened,result)
    local loan=result.loan
    check("household_machine_financing_is_not_profit",financed.home.finance.totals.revenue==0
        and financed.home.finance.totals.materials==0)
    financed.calendar=Calendar.dateFromTotalDay(loan.nextDueDay-1)
    check("household_upcoming_loan_payment_reserved",Finance.reserves(financed).loans>0)
    financed.calendar=Calendar.dateFromTotalDay(loan.nextDueDay);Credit.onDay(financed)
    local interest=financed.home.finance.totals.interest;local principal=loan.balance
    check("household_loan_interest_booked_once",interest==loan.accruedInterest*100 and interest>0)
    assert(Credit.payLoan(financed,loan.id))
    check("household_loan_principal_repayment_not_expensed",loan.balance<principal
        and financed.home.finance.totals.interest==interest and financed.home.finance.totals.services==0)
end
local function settlementTests(context,check)
    local retained=rich();retained.home.payPercent=0;Finance.record(retained,"revenue",100000)
    local _,zero=Finance.settle(retained,44)
    check("household_zero_percent_retains_positive_earnings",zero.eligibleCents==100000 and zero.requestedCents==0 and zero.paidCents==0
        and retained.money==10000 and retained.home.balanceCents==30000 and Finance.valid(retained.home.finance))
    assert(Home.setPayPercent(retained.home,100,retained.home.revision))
    check("household_rate_change_cannot_reclaim_zero_percent_period",not Finance.settle(retained,44)
        and Finance.preview(retained).eligibleCents==0 and retained.home.balanceCents==30000)
    local s=rich();local f=s.home.finance
    s.accountsReceivable=100000;s.money=s.money+50000
    check("household_starting_cash_and_unpaid_quotes_are_not_income",Finance.preview(s).requestedCents==0)
    s.inventory.prints=1;assert(require("src.shop").sellPrint(s))
    check("household_collected_print_sale_is_income",f.totals.revenue==1200)
    Finance.record(s,"revenue",998800);Finance.record(s,"materials",100000)
    local changed,row=Finance.settle(s,44)
    check("household_friday_draw_uses_realized_earnings",changed and row.netCents==900000 and row.paidCents==225000
        and s.home.balanceCents==255000 and s.money==57762 and Finance.valid(f))
    local business,personal=s.money,s.home.balanceCents
    local notices=#s.clientEmails.inbox
    check("household_settlement_replay_cannot_pay_twice",not Finance.settle(s,44) and s.money==business
        and s.home.balanceCents==personal and Finance.preview(s).eligibleCents==0 and #s.clientEmails.inbox==notices)
    assert(context.save.save(3,s,{x=320,y=400}))
    local loaded=assert(context.save.load(3));local restored=State.new();assert(State.applyLocalSave(restored,loaded))
    local guest=State.new();assert(State.applySharedSnapshot(guest,assert(Schema.snapshot(s))))
    check("household_settlement_survives_save_and_guest_snapshot",not Finance.settle(restored,44)
        and restored.money==business and restored.home.balanceCents==personal
        and #guest.home.finance.history==1 and guest.home.finance.history[1].paidCents==225000)
    Finance.record(s,"refunds",50000);assert(Finance.settle(s,212))
    Finance.record(s,"revenue",30000);assert(Finance.settle(s,380))
    check("household_losses_carry_to_future_weeks",f.lossCarryCents==-20000 and s.home.balanceCents==personal)
    Finance.record(s,"revenue",60000);assert(Finance.settle(s,548))
    check("household_recovery_pays_only_after_losses",f.lossCarryCents==0 and s.home.balanceCents==personal+10000)
    local clipped=rich();clipped.home.payPercent=100;Finance.record(clipped,"revenue",1000000)
    local reserve=Finance.reserves(clipped).total;clipped.money=(reserve+12345)/100
    local _,capped=Finance.settle(clipped,44)
    check("household_draw_keeps_obligations_and_reserve",capped.paidCents==12345
        and math.abs(clipped.money-reserve/100)<1e-7 and clipped.home.balanceCents==42345)
    clipped.money=1000000;assert(Finance.settle(clipped,212))
    check("household_unpaid_requested_draw_is_not_company_debt",clipped.home.balanceCents==42345)
    for i=3,60 do assert(Finance.settle(clipped,44+(i-1)*168)) end
    check("household_history_is_bounded_and_valid",#clipped.home.finance.history==52 and Finance.valid(clipped.home.finance))
    local bad=Schema.copy(s);bad.home.finance.history[1].paidCents=1
    check("household_rejects_corrupt_receipt",not Schema.validState(bad))
    bad=Schema.copy(s);bad.home.finance.stock.abstract_paper={quantity=0,basisCents=1}
    check("household_rejects_cost_without_stock",not Schema.validState(bad))
    assert(context.save.delete(3))
end
local function controlsTests(context,check)
    local s=rich();local FinanceScreen=require("src.screens.computer_screen")
    local host=FinanceScreen.new();host.tab="home"
    local function click(screen,name) local x,y=screen.homeControlCenter(name);return screen.mousepressed(s,x,y,1) end
    assert(click(host,"earnings"));assert(click(host,"plus").action=="home_changed")
    check("household_host_can_set_cash_buffer",s.home.finance.reserveCents==30000)
    local guest=FinanceScreen.new({remoteCommand=function() error("Guest tried household write") end});guest.tab="home"
    click(guest,"earnings")
    check("household_guest_can_review_but_not_edit_reserve",click(guest,"minus").action=="blocked" and s.home.finance.reserveCents==30000)
    local intent=require("src.office_intent")
    check("household_reserve_intent_bounded",intent.normalize({kind="home_set_reserve",expectedRevision=s.home.revision,reserveCents=0})
        and not intent.normalize({kind="home_set_reserve",expectedRevision=s.home.revision,reserveCents=.5}))
    Finance.record(s,"revenue",120000);Finance.record(s,"materials",12000);Finance.settle(s,44)
    Finance.record(s,"revenue",95000);Finance.record(s,"materials",22000);Finance.record(s,"wages",17500)
    local destination=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    for _,view in ipairs({"earnings","history"}) do
        if view=="history" then click(host,"history") end
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        host.draw(s,nil,nil,context.assets);love.graphics.pop()
        if destination then
            local data=canvas:newImageData();local encoded=data:encode("png")
            local file=assert(io.open(destination.."/home-"..view..".png","wb"));file:write(encoded:getString());file:close()
            encoded:release();data:release()
        end
        canvas:release();check("household_"..view.."_screen_renders",true)
    end
    check("household_reserve_stale_command_rejected",not Home.command(s,{kind="home_set_reserve",reserveCents=0,expectedRevision=0}))
end
function Test.run(context,check)
    stockTests(check);expenseTests(check);settlementTests(context,check);controlsTests(context,check)
    require("src.tests.home_progression_test").run(context,check)
    require("src.tests.home_budget_test").run(context,check)
end
return Test
