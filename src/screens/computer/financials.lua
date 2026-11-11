-- A single finance destination keeps the budget, bills, and wage detail together.
local Component={}
local Budget=require('src.screens.shop_budget')
local ShopFinances=require('src.staff_finances')

local tabs={
    {id='overview',label='OVERVIEW'},
    {id='bills',label='BILLS + WAGES'},
    {id='staff',label='STAFF PAYROLL'},
    {id='players',label='PLAYER WAGES'},
}
local tabRects={}
for index,tab in ipairs(tabs) do
    tabRects[tab.id]={x=114+(index-1)*181,y=190,width=175,height=32}
end
local function section(Runtime)
    if Runtime.ComputerScreen.tab=='bills' then return 'bills' end
    if Runtime.ComputerScreen.tab=='player_wages' then return 'players' end
    return Runtime.ComputerScreen.financialSection or 'overview'
end
local function drawTabs(Runtime,pointerX,pointerY)
    for _,tab in ipairs(tabs) do
        local rect=tabRects[tab.id]
        local selected=section(Runtime)==tab.id
        local hovered=pointerX and pointerY and Runtime.contains(rect,pointerX,pointerY)
        Runtime.drawComputerButton(rect,tab.label,selected and (hovered and 'primaryHover' or 'primary')
            or hovered and 'hover' or 'secondary')
    end
end

function Component.install(Runtime)
    function Runtime.ComputerScreen.financialSectionCenter(id)
        local rect=tabRects[id]
        if rect then return rect.x+rect.width/2,rect.y+rect.height/2 end
    end
    function Runtime.drawFinancials(state,pointerX,pointerY,twelveHourTime)
        local active=section(Runtime)
        if active=='overview' then
            Runtime.panel({x=110,y=182,width=738,height=402},{.045,.07,.08,1},{.30,.50,.49,1})
            local summary=ShopFinances.summary(state)
            Budget.draw(state.money or 0,summary,ShopFinances.plan(summary))
        elseif active=='bills' then
            love.graphics.push()
            love.graphics.translate(0,30)
            Runtime.drawBills(state,pointerX,pointerY and pointerY-30)
            love.graphics.pop()
        elseif active=='staff' then
            local ui=Runtime.ComputerScreen.financialHiring
            ui.section='payroll';ui.view='detail'
            Runtime.drawContainedPage(function(x,y)
                Runtime.Hiring.draw(state,ui,x,y,false,Runtime.drawComputerButton,
                    Runtime.dependencies.remoteCommand==nil,twelveHourTime,true)
            end,pointerX,pointerY,Runtime.HIRING_PAGE_LAYOUT)
        else
            love.graphics.push()
            love.graphics.translate(0,30)
            Runtime.drawPlayerWages(state,pointerX,pointerY and pointerY-30)
            love.graphics.pop()
        end
        drawTabs(Runtime,pointerX,pointerY)
    end
    function Runtime.financialsMousepressed(state,x,y)
        local active=section(Runtime)
        Runtime.ComputerScreen.tab='financials'
        Runtime.ComputerScreen.financialSection=active
        for _,tab in ipairs(tabs) do
            if Runtime.contains(tabRects[tab.id],x,y) then
                Runtime.ComputerScreen.financialSection=tab.id
                return {action='financials_view',section=tab.id}
            end
        end
        if active=='bills' then
            local payRect={x=Runtime.PAY_BILLS.x,y=Runtime.PAY_BILLS.y+30,
                width=Runtime.PAY_BILLS.width,height=Runtime.PAY_BILLS.height}
            if Runtime.contains(payRect,x,y) then
                if Runtime.dependencies.remoteCommand then return Runtime.remoteAction('pay_bills') end
                local paid,result=Runtime.BusinessCalendar.pay(state)
                if not paid then state.message=result;return {action='blocked'} end
                state.message=string.format('Paid $%.2f in operating bills, customer claims and wages.',result)
                return {action='bill_paid',amount=result}
            end
            return nil
        elseif active=='players' then
            return Runtime.playerWagesMousepressed(state,x,y-30)
        elseif active=='staff' then
            local hx,hy=Runtime.containedPagePoint(x,y,Runtime.HIRING_PAGE_LAYOUT)
            -- The embedded payroll view uses the old Shop Budget button as its
            -- return path, and omits the Hiring navigation row above the ledger.
            if hx>=364 and hx<=578 and hy>=554 and hy<=600 then
                Runtime.ComputerScreen.financialSection='overview'
                return {action='financials_view',section='overview'}
            end
            if y<240 then return nil end
            return Runtime.Hiring.mousepressed(state,Runtime.ComputerScreen.financialHiring,hx,hy,
                function(intent) return Runtime.ComputerScreen.employeeCommand(state,intent) end,
                false,Runtime.dependencies.remoteCommand==nil,
                Runtime.twelveHourTime())
        end
    end
end

return Component
