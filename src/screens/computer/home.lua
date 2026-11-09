local Home=require("src.home")
local Catalog=require("src.home_catalog")
local Finance=require("src.household_finances")
local Guide=require("src.screens.computer.home_guide")
local Budget=require("src.home_budget")
local FinanceCharts=require("src.screens.finance_charts")
local Component={}
local controls={guide={x=478,y=554,width=350,height=44},sleep={x=104,y=554,width=310,height=44},pay={x=104,y=504,width=310,height=44},
    minus={x=478,y=443,width=48,height=44},plus={x=788,y=443,width=48,height=44},
    earnings={x=478,y=504,width=350,height=44},back={x=104,y=554,width=180,height=44},
    history={x=306,y=554,width=180,height=44},previous={x=576,y=554,width=110,height=44},
    next={x=704,y=554,width=124,height=44}}
local slider={x=540,y=447,width=232,height=36}
local expenseColors={
    revenue={.59,.89,.67,1},materials={.40,.84,.81,1},wages={.96,.77,.47,1},operating={.77,.63,.94,1},
    refunds={1,.59,.50,1},interest={.95,.72,.36,1},services={.55,.76,.96,1},
}
local financeLabels={revenue="Collected sales",materials="Materials",wages="Earned wages",
    operating="Operating",refunds="Claims / refunds",interest="Interest / fees",services="Services"}
local function shortMoney(value)
    value=tonumber(value) or 0
    local sign=value<0 and "−" or "";value=math.abs(value)
    if value>=1000000 then return string.format("%s$%.1fm",sign,value/1000000) end
    if value>=10000 then return string.format("%s$%.0fk",sign,value/1000) end
    if value>=1000 then return string.format("%s$%.1fk",sign,value/1000) end
    return string.format("%s$%.0f",sign,value)
end
function Component.install(Runtime)
    local view,page,guidePage="overview",1,1
    function Runtime.resetHomeView() view,page,guidePage="overview",1,1 end
    function Runtime.ComputerScreen.homeGuideControlCenter(name,index)
        local rect=Guide.rect(name,index);return rect.x+rect.width/2,rect.y+rect.height/2
    end
    function Runtime.ComputerScreen.homeControlCenter(name)
        local rect=name=="slider" and slider or controls[name]
        return rect.x+rect.width/2,rect.y+rect.height/2
    end
    local function readOnly() return Runtime.ComputerScreen.radioReadOnly() end
    function Runtime.homeMousepressed(state,x,y)
        local guideAction
        if view=="guide" then
            guidePage,guideAction=Guide.mousepressed(state,guidePage,x,y,Runtime.contains)
            if guideAction=="back" then view="overview"
            elseif guideAction=="earnings" then view="earnings"
            elseif guideAction and guideAction~="sleep" then
                return Runtime.activateTab(state,Runtime.tabById(guideAction))
            end
            if guideAction~="sleep" then return {action="home_view"} end
        end
        if view=="overview" and Runtime.contains(controls.guide,x,y) then view="guide";return {action="home_view"} end
        if guideAction=="sleep" or view=="overview" and Runtime.contains(controls.sleep,x,y) then
            if not require("src.weekend_flow").atHome(state) then state.message="Sleep and alarms are available at your apartment.";return {action="blocked"} end
            local pane=require("src.home_activity_controls");pane.mode="sleep";pane.page=1;pane.target="floor"
            -- The activity screen resolves the local resident on draw or touch.
            pane.appliance=nil
            pane.alarmHour,pane.alarmMinute=nil,nil
            if Runtime.dependencies.remoteCommand then return {action="home_activity"} end
            state.screen="home_activity";return {action="home_view"}
        end
        if view=="overview" and Runtime.contains(controls.earnings,x,y) then view="earnings";return {action="home_view"} end
        if view~="overview" and Runtime.contains(controls.back,x,y) then view="overview";return {action="home_view"} end
        if view=="earnings" and Runtime.contains(controls.history,x,y) then view="history";page=1;return {action="home_view"} end
        if view=="history" then
            local count=state.home.finance and #state.home.finance.history or 0
            if Runtime.contains(controls.previous,x,y) then page=math.max(1,page-1)
            elseif Runtime.contains(controls.next,x,y) then page=math.min(math.max(1,math.ceil(count/7)),page+1) end
            return {action="home_view"}
        end
        local intent
        if view=="earnings" then
            local reserve=state.home.finance and state.home.finance.reserveCents or 20000
            if Runtime.contains(controls.minus,x,y) then intent={kind="home_set_reserve",reserveCents=math.max(0,reserve-10000)}
            elseif Runtime.contains(controls.plus,x,y) then intent={kind="home_set_reserve",reserveCents=math.min(100000000,reserve+10000)} end
        elseif Runtime.contains(controls.pay,x,y) then intent={kind="home_pay_rent"}
        elseif Runtime.contains(controls.minus,x,y) then intent={kind="home_set_pay",percent=math.max(0,state.home.payPercent-1)}
        elseif Runtime.contains(controls.plus,x,y) then intent={kind="home_set_pay",percent=math.min(100,state.home.payPercent+1)}
        elseif Runtime.contains(slider,x,y) then
            intent={kind="home_set_pay",percent=math.floor((x-slider.x)/slider.width*100+.5)}
        end
        if not intent then return nil end
        if readOnly() then state.message="Only the host can pay rent or set personal pay and reserves.";return {action="blocked"} end
        intent.expectedRevision=state.home.revision
        local ok,message,code
        if Runtime.dependencies.warehouseCommand then ok,code,message=Runtime.dependencies.warehouseCommand(intent)
        else ok,message=Home.command(state,intent) end
        state.message=message or (ok and "Household details saved." or "Household action unavailable.")
        return {action=ok and "home_changed" or "blocked"}
    end
    function Runtime.drawHome(state,pointerX,pointerY)
        local home=state.home;local entry=Catalog.APARTMENTS[home.apartmentId]
        local due=Home.amountDue(home);local lease=home.lease
        Runtime.panel({x=82,y=190,width=792,height=424},{.045,.08,.10,1},{.28,.50,.49,1})
        local function label(value,x,y,width,color,alignment)
            love.graphics.setColor(unpack(color or {.85,.92,.87,1}));love.graphics.printf(value,x,y,width,alignment or "left")
        end
        local function button(rect,title,enabled)
            local hover=pointerX and pointerY and Runtime.contains(rect,pointerX,pointerY)
            Runtime.drawComputerButton(rect,title,enabled and (hover and "primaryHover" or "primary") or "disabled")
        end
        if view=="guide" then Guide.draw(Runtime,state,guidePage,pointerX,pointerY);return
        elseif view=="history" then
            label("PERSONAL PAY HISTORY  /  Friday shutdowns",104,208,710,{1,.86,.41,1})
            local history=home.finance and home.finance.history or {}
            label("Close date",104,248,90);label("Earnings",200,248,78);label("Rate",280,248,36)
            label("Requested",326,248,94);label("Paid",425,248,94)
            if #history==0 then label("Your first settlement appears after a Friday shutdown.",104,298,710) end
            for i=1,7 do
                local row=history[#history-(page-1)*7-i+1]
                if row then
                    local date=Runtime.BusinessCalendar.dateFromTotalDay(math.floor(row.closeHours/24))
                    local y=260+i*35
                    label(string.format("%d/%d/%d",date.month,date.day,date.year),104,y,90)
                    label(string.format("$%.2f",row.netCents/100),200,y,78)
                    label(row.percent.."%",280,y,36)
                    label(string.format("$%.2f",row.requestedCents/100),326,y,94)
                    label(string.format("$%.2f",row.paidCents/100),425,y,94,{.52,.96,.67,1})
                end
            end
            local values={}
            for i=math.max(1,#history-11),#history do values[#values+1]=history[i].paidCents/100 end
            label("RECENT PAYDAYS  /  paid to household",586,286,250,{.96,.86,.47,1})
            FinanceCharts.sparkline(586,310,250,192,values,{.59,.89,.67,1},"OLDER","LATEST")
            button(controls.back,"MY HOME",true)
            button(controls.previous,"PREVIOUS",page>1)
            button(controls.next,"NEXT",page*7<#history)
            return
        elseif view=="earnings" then
            local p=Finance.preview(state);local r=p.reserves
            label("PERSONAL PAY  /  next Friday shutdown",104,208,710,{1,.86,.41,1})
            local names={{"revenue","Collected sales"},{"materials","Used supplies"},{"wages","Earned wages"},
                {"operating","Accrued operating costs"},{"refunds","Refunds / claims"},{"interest","Interest / late fees"},{"services","Outside services"}}
            local costSegments,costTotal={},0
            for _,entry in ipairs(names)do
                if entry[1]~="revenue" then
                    local amount=p.costs[entry[1]] or 0;costTotal=costTotal+amount
                    costSegments[#costSegments+1]={label=entry[2],value=math.max(0,amount),color=expenseColors[entry[1]]}
                end
            end
            for i,entry in ipairs(names) do
                local color=expenseColors[entry[1]]
                love.graphics.setColor(unpack(color));love.graphics.rectangle("fill",104,235+i*24,8,8,2,2)
                label(financeLabels[entry[1]],118,228+i*24,124,color)
                label(string.format("$%.2f",p.costs[entry[1]]/100),244,228+i*24,66,color,"right")
            end
            FinanceCharts.donut(390,335,63,costSegments,"PERIOD COSTS",shortMoney(costTotal/100))
            local carriedLoss=p.lossBeforeCents<0 and -p.lossBeforeCents/100 or 0
            label(string.format("Net earnings: $%.2f\nLoss carried forward: $%.2f",p.netCents/100,carriedLoss),104,422,350)
            label(string.format("Eligible: $%.2f   |   Pay: %d%%",p.eligibleCents/100,p.percent),478,252,350)
            label(string.format("Requested: $%.2f\nCash available for pay: $%.2f\nExpected transfer: $%.2f",p.requestedCents/100,
                p.availableCents/100,p.paidCents/100),478,282,350,{.52,.96,.67,1})
            label(string.format("Reserved: $%.2f\nUnpaid $%.2f | Next wages $%.2f\nOperating $%.2f | Loans $%.2f",
                r.total/100,r.unpaid/100,r.payroll/100,r.operating/100,r.loans/100),478,350,350)
            label(string.format("Cash buffer: $%.2f",r.buffer/100),540,455,238)
            button(controls.minus,"-",not readOnly() and r.buffer>0)
            button(controls.plus,"+",not readOnly() and r.buffer<100000000)
            label("Transfers settle once. Retained earnings stay with the shop; losses reduce future pay.",104,495,730)
            label(readOnly() and "The host sets the cash buffer." or "Cash buffer controls change the reserve by $100.",478,525,350)
            button(controls.back,"MY HOME",true);button(controls.history,"PAY HISTORY",true)
            return
        end
        label("MY HOME  /  "..entry.name,104,208,710,{1,.86,.41,1})
        label("Condition: "..entry.condition,104,238,320)
        label("Household funds",478,238,350)
        label(string.format("$%.2f",home.balanceCents/100),478,264,350,{.52,.96,.67,1})
        label(string.format("Monthly rent: $%.2f\nRent per week (average): $%.2f",lease.monthlyCents/100,
            math.ceil(lease.monthlyCents*12/52)/100),104,280,330)
        local date=Runtime.BusinessCalendar.dateFromTotalDay(lease.nextDueDay)
        label(string.format("Next rent: %s %d, %d",Runtime.BusinessCalendar.monthName(date.month),date.day,date.year),104,338,340)
        label(string.format("Rent outstanding: $%.2f",due/100),104,376,340,due>0 and {1,.78,.39,1} or nil)
        label("Personal pay target",478,338,350,{1,.86,.41,1})
        label(home.payPercent.."% household  /  "..(100-home.payPercent).."% business",478,373,205)
        label("From eligible earnings after business costs and reserves.",478,404,205)
        local covered=math.min(home.balanceCents,due)
        local rentPlan={
            {label="Rent covered",value=covered,color={.96,.77,.47,1},valueText=shortMoney(covered/100)},
            {label="Rent gap",value=math.max(0,due-home.balanceCents),color={1,.59,.50,1},valueText=shortMoney(math.max(0,due-home.balanceCents)/100)},
            {label="Funds left",value=math.max(0,home.balanceCents-due),color={.59,.89,.67,1},valueText=shortMoney(math.max(0,home.balanceCents-due)/100)},
        }
        FinanceCharts.donut(772,307,42,rentPlan,"RENT PLAN",shortMoney(due/100))
        FinanceCharts.legend(700,359,rentPlan,136,14,3)
        local budgetLines,budgetWarning=Budget.lines(state)
        label(table.concat(budgetLines,"\n"),104,422,350,budgetWarning and {1,.78,.39,1} or nil)
        button(controls.pay,due>0 and "PAY RENT FROM HOUSEHOLD" or "RENT UP TO DATE",not readOnly() and due>0 and home.balanceCents>=due)
        button(controls.minus,"-",not readOnly() and home.payPercent>0)
        button(controls.plus,"+",not readOnly() and home.payPercent<100)
        love.graphics.setColor(.19,.31,.32,1);love.graphics.rectangle("fill",slider.x,slider.y+14,slider.width,8,3,3)
        love.graphics.setColor(.95,.79,.35,1);love.graphics.rectangle("fill",slider.x+slider.width*home.payPercent/100-5,slider.y+4,10,28,3,3)
        button(controls.earnings,"EARNINGS, RESERVES & HISTORY",true)
        button(controls.sleep,"HOME SLEEP & ALARMS",require("src.weekend_flow").atHome(state))
        button(controls.guide,"HOME GUIDE & FIRST WEEKEND",true)
    end
end
return Component
