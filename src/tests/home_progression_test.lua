-- Sustained household simulation with explicit, controlled business receipts.
-- This tests budget/lifecycle integration, not how many warehouse jobs a human
-- can finish. Demand and consumed business costs are scenario inputs below.
local State=require("src.state")
local Home=require("src.home")
local Catalog=require("src.home_catalog")
local Calendar=require("src.business_calendar")
local Flow=require("src.weekend_flow")
local Finance=require("src.household_finances")
local Shopping=require("src.home_shopping")
local Residents=require("src.home_residents")
local Sleep=require("src.home_sleep")
local Layout=require("src.home_layouts")
local Schema=require("src.save_schema")
local Test={}
local function scenario(context,check,id,preset,count,seconds,percent,report,expectArrears)
    local s=State.new();s.home=assert(Home.new({apartmentId=id,furnishingPreset=preset}));s.calendar.secondsPerDay=seconds
    local players={{id=1,sceneId="warehouse",x=720,y=202}};local owner=players[1]
    for i=2,count do
        local p={id=i,sceneId="warehouse",x=720+i*20,y=202};players[#players+1]=p
        assert(Residents.bind(s,p,string.rep(tostring(i),64),players))
    end
    if percent~=25 then assert(Home.setPayPercent(s.home,percent,s.home.revision)) end
    local label=id.."_"..preset.."_"..count.."_"..seconds.."_"..percent
    local spending,received,consumed,paid,boughtBed=0,0,0,0,false
    local initialFood=s.home.inventory.basic_meal or 0
    local initialBusiness=s.money;local gross,costs,billsPaid=0,0,0
    local function advance(to)
        assert(to+1e-7>=Calendar.absoluteHours(s),"scenario clock moved backwards")
        while Calendar.absoluteHours(s)+1e-7<to do
            local first=Calendar.absoluteHours(s);local hours=math.min(1,to-first)
            Calendar.update(s,hours*Calendar.secondsPerDay(s)/24)
            local last=Calendar.absoluteHours(s)
            Residents.advance(s,players,first,last);Flow.update(s,false)
        end
    end
    local function act(p,command)
        local target=command:match(":([a-z]+)$")
        if target and target~="floor" then
            local fixture=Layout.get(s).fixtures[target];p.x,p.y=Layout.toWorld(unpack(fixture.approach))
        end
        assert(Residents.command(s,p,command))
    end
    local function all(command)
        for _,p in ipairs(players) do
            act(p,command)
            -- Shared fixtures are used one at a time. This also advances needs
            -- for every other connected resident during the wait.
            local a=assert(Residents.get(s,p).activity);advance(a.endsAt)
        end
    end
    local function drink() all("drink:sink") end
    local function eat()
        local before=s.home.inventory.basic_meal or 0
        all("eat:floor");consumed=consumed+count
        assert(s.home.inventory.basic_meal==before-count)
    end
    local function sleep(untilHour)
        for _,p in ipairs(players) do act(p,"sleepfloor:floor") end
        assert(Sleep.status(s,players))
        -- Use the real shared-sleep calendar limiter through a midnight/rent
        -- boundary; it must stop at Monday 07:00 and process events once.
        while Calendar.absoluteHours(s)+1e-7<untilHour do
            local first=Calendar.absoluteHours(s)
            local dt=Sleep.calendarStep(s,players,seconds)
            dt=math.min(dt,(untilHour-first)*seconds/24)
            if dt<=1e-8 then break end
            Calendar.update(s,dt);Residents.advance(s,players,first,Calendar.absoluteHours(s));Flow.update(s,false)
        end
        for _,p in ipairs(players) do if Residents.get(s,p).activity then assert(Residents.command(s,p,"cancel")) end end
    end
    local function order(product,quantity,week)
        local intent={kind=product=="bed" and "home_order_furniture" or "home_order_food",productId=product,
            quantity=quantity,requestId="progress-"..week.."-"..product,expectedRevision=s.home.revision}
        local before=s.home.balanceCents;assert(Shopping.order(s,owner,intent))
        spending=spending+before-s.home.balanceCents
        assert(Shopping.order(s,owner,intent));return intent
    end
    local function reload(week)
        local before=Schema.snapshot(s);local payload={version=39,slot=3,createdAt=1,updatedAt=2,state=before,player={x=owner.x,y=owner.y,sceneId=owner.sceneId}}
        -- Real disk round trip on both sides of two rent boundaries; the
        -- remaining scenarios use the same loader against a snapshot payload.
        if id=="brick-walkup" and preset=="empty" and count==1 and (week==1 or week==9) then
            assert(context.save.save(3,s,payload.player));payload=assert(context.save.load(3))
        end
        local loaded=State.new();assert(State.applyLocalSave(loaded,payload));Residents.recover(loaded);s=loaded
        assert(s.home.balanceCents==before.home.balanceCents and s.home.lease.paidCents==before.home.lease.paidCents)
    end
    for week=1,expectArrears and 13 or 9 do
        -- First Friday has no collected earnings. Later weeks model $2,400
        -- collected sales and $700 consumed supplies, plus actual calendar
        -- operating accrual. Neither starting capital nor loans count as sales.
        if week>1 then
            Finance.ensure(s);s.money=s.money+2400;Finance.record(s,"revenue",240000);gross=gross+240000
            s.money=s.money-700;Finance.purchase(s,"house_sheets",1000,70000);Finance.consume(s,"house_sheets",1000);costs=costs+70000
        end
        local close=s.home.weekend.closesAtHours;local opens=s.home.weekend.opensAtHours
        advance(close);assert(Flow.update(s,true));assert(s.home.weekend.phase=="ready")
        local receipt=s.home.finance.history[#s.home.finance.history];paid=paid+receipt.paidCents
        if week==1 then assert(receipt.paidCents==0) end
        local total=s.money*100+s.home.balanceCents
        assert(not Finance.settle(s,close) and s.money*100+s.home.balanceCents==total)
        assert(Flow.depart(s,s.home.revision))
        for _,p in ipairs(players) do p.sceneId="home";p.x,p.y=Layout.spawn(s,p.id) end
        if preset=="empty" and not boughtBed then order("bed",1,week);boughtBed=true end
        local need=math.max(0,count*2-(s.home.inventory.basic_meal or 0))
        if need>0 then order("meal_pack",math.ceil(need/4),week) end
        advance(close+2)
        if Shopping.waiting(s)>0 then
            local before=s.home.inventory.basic_meal or 0;local target=assert(Shopping.target(owner,s));owner.x,owner.y=target.x,target.y
            assert(Shopping.collect(s,owner));received=received+(s.home.inventory.basic_meal or 0)-before
            assert(not Shopping.collect(s,owner))
        end
        reload(week)
        assert(not Finance.settle(s,close));assert(not Shopping.collect(s,owner))
        sleep(close+10) -- Friday 22:00 -> Saturday 06:00.
        advance(close+12);drink()
        advance(close+24);eat();drink()
        advance(close+26);sleep(close+34)
        advance(close+36);drink();all("bathe:bath")
        advance(close+48);eat();drink()
        advance(close+50);sleep(opens-2)
        drink();advance(opens)
        local ready=true;for _,row in ipairs(Sleep.readiness(s,players)) do ready=ready and row.ready end
        check("home_progression_ready_"..label.."_week"..week,ready)
        local due=Home.amountDue(s.home)
        if due>0 and s.home.balanceCents>=due then
            local business=s.money;local revision=s.home.revision
            assert(Home.payRent(s.home,revision));assert(not Home.payRent(s.home,revision));assert(s.money==business)
        end
        if s.bills.balance>0 and s.money>=s.bills.balance then
            local personal=s.home.balanceCents;local dueBusiness=s.bills.balance
            assert(Calendar.pay(s));billsPaid=billsPaid+dueBusiness*100;assert(s.home.balanceCents==personal)
        end
        check("home_progression_conservation_"..label.."_week"..week,
            s.home.balanceCents==Catalog.ALLOWANCE_CENTS+paid-spending-s.home.lease.paidCents
            and (s.home.inventory.basic_meal or 0)==initialFood+received-consumed
            and math.abs(s.money*100-(initialBusiness*100+gross-costs-paid-billsPaid))<1e-5
            and #s.home.finance.history==week and s.home.lease.invoiceCount<=2 and Schema.validState(Schema.snapshot(s)))
        report[#report+1]=string.format("%s week=%d date=%s pay=%0.2f household=%0.2f rent_paid=%0.2f arrears=%0.2f meals=%d business=%0.2f",
            label,week,Calendar.shortDate(s),receipt.paidCents/100,s.home.balanceCents/100,s.home.lease.paidCents/100,
            Home.amountDue(s.home)/100,s.home.inventory.basic_meal or 0,s.money)
        if week==9 and expectArrears then
            local budget=require("src.home_budget").summary(s);local _,warning=require("src.home_budget").lines(s)
            local business=s.money;local balance=s.home.balanceCents
            check("home_progression_shortfall_preserves_accounts_"..label,Home.amountDue(s.home)>0 and budget.dueShortfallCents>0
                and warning and not Home.payRent(s.home,s.home.revision) and s.money==business and s.home.balanceCents==balance,report[#report])
            assert(Home.setPayPercent(s.home,60,s.home.revision))
            check("home_progression_raise_pay_is_future_only_"..label,not Finance.settle(s,close) and s.home.balanceCents==balance
                and s.home.finance.history[#s.home.finance.history].percent==25)
        end
        assert(Flow.returnToWork(s,s.home.revision));Residents.recover(s)
        for _,p in ipairs(players) do p.sceneId="warehouse" end
        Residents.advance(s,players,opens,opens)
    end
    check("home_progression_two_monthly_invoices_"..label,s.home.lease.invoiceCount==2
        and s.home.lease.chargedCents==2*Catalog.APARTMENTS[id].rentCents)
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    if folder then local file=assert(io.open(folder.."/home-progression-report.txt","wb"));file:write(table.concat(report,"\n").."\n");file:close() end
    check("home_progression_rent_and_food_sustainable_"..label,Home.amountDue(s.home)==0 and s.home.balanceCents>0,report[#report])
end
function Test.run(context,check)
    local report={"Nine-week household scenarios. Controlled business receipts, not a warehouse throughput benchmark.",
        "First week: no income. Following weeks: $2400 collected / $700 consumed supplies / actual operating costs.",
        "Cheaper rents: solo pay 25%, four-player 40%. Higher rents: solo 40%, four-player 50%.",
        "Separate Corner/25% runs incur arrears, then raise pay to 60% after week 9 and recover over four more weekends.",
        "Empty starts buy one $160 delivered bed; others can floor-rest.",
        "Meals, free sink water, shared floor sleep, bathroom access, delivery and rent use production commands."}
    for index,id in ipairs(Catalog.ORDER) do for _,preset in ipairs({"empty","modest"}) do for _,count in ipairs({1,4}) do
        local percent=index<=2 and (count==4 and 40 or 25) or (count==4 and 50 or 40)
        scenario(context,check,id,preset,count,({300,1200,3600})[(index+count)%3+1],percent,report)
    end end end
    for _,count in ipairs({1,4}) do scenario(context,check,"corner","empty",count,1200,25,report,true) end
    assert(context.save.delete(3))
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    if folder then local file=assert(io.open(folder.."/home-progression-report.txt","wb"));file:write(table.concat(report,"\n").."\n");file:close() end
end
return Test
