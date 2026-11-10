-- Office render dispatch.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.ComputerScreen.draw(state, pointerX, pointerY, assets, twelveHourTime)
        local MobileLayout=require('src.screens.computer.mobile_layout')
        local compact=MobileLayout.active()
        Runtime.compactHeader=compact
        local screenPointerX,screenPointerY=pointerX,pointerY
        if compact then pointerX,pointerY=MobileLayout.toContent(pointerX,pointerY) end
        Runtime.buttonDrawPointerX, Runtime.buttonDrawPointerY = pointerX, pointerY
        love.graphics.setColor(0.01, 0.02, 0.03, 0.76)
        love.graphics.rectangle("fill", 0, 0, Runtime.Config.baseWidth, Runtime.Config.baseHeight)
        if not compact then
        Runtime.drawMonitorFrame(state,twelveHourTime)
        love.graphics.setFont(require('src.screens.typography').get(16))
        Runtime.panel(Runtime.PANEL, { 0.035, 0.05, 0.065, 0.99 }, { 0.31, 0.56, 0.58, 1 })
        Runtime.drawCritterNetChrome(assets)
        love.graphics.setColor(0.96, 0.94, 0.84, 1)
        local household=Runtime.ComputerScreen.tab=="home" or Runtime.ComputerScreen.tab=="groceries"
            or Runtime.ComputerScreen.tab=="takeout" or Runtime.ComputerScreen.tab=="home_orders" or Runtime.ComputerScreen.tab=="furniture"
        love.graphics.print(household and "MY HOUSEHOLD" or "PICTURE SHOP JOB DESK", 166, 46)
        love.graphics.setColor(0.42, 0.70, 0.68, 0.92)
        love.graphics.rectangle("fill", 428, 42, 1, 23)
        local reputation = Runtime.Reputation.ensure(state)
        local summary = {
            { label = "CASH", value = Runtime.money(state.money), x = 437, width = 76,
                valueColor = { 0.52, 0.96, 0.67, 1 } },
            { label = "A/R", value = Runtime.money(state.accountsReceivable), x = 515, width = 76,
                valueColor = { 0.91, 0.95, 0.86, 1 } },
            { label = "REP", value = tostring(reputation.score), x = 593, width = 76,
                valueColor = { 1.00, 0.83, 0.47, 1 } },
        }
        if household then
            summary[1].label="HOME";summary[1].value=Runtime.money(state.home.balanceCents/100)
            summary[2].label="RENT";summary[2].value=Runtime.money(state.home.lease.monthlyCents/100)
            summary[3].label="PARCELS";summary[3].value=tostring(require("src.home_shopping").waiting(state))
        end
        for _, item in ipairs(summary) do
            love.graphics.setFont(require('src.screens.typography').get(12))
            love.graphics.setColor(0.71, 0.83, 0.78, 1)
            love.graphics.printf(item.label, item.x, 39, item.width, "center")
            love.graphics.setColor(item.valueColor)
            love.graphics.setFont(require('src.screens.typography').get(14,'bold'))
            Runtime.printCenteredFit(item.value, item.x, 54, item.width)
        end
        love.graphics.setFont(require('src.screens.typography').get(16))
        Runtime.BackButton.draw(assets, Runtime.CLOSE, "BACK", pointerX, pointerY, false)
        else
            local l=MobileLayout.geometry()
            love.graphics.setColor(.025,.045,.05,1)
            love.graphics.rectangle('fill',l.bounds.left,l.bounds.top,l.bounds.width,l.bounds.height)
            love.graphics.push('all');love.graphics.translate(l.x,l.y);love.graphics.scale(l.scale)
            love.graphics.setFont(require('src.screens.typography').get(16))
        end

        if Runtime.ComputerScreen.tab == "clock" then
            require("src.screens.shop_clock").drawPanel(state,
                {x=82,y=184,width=792,height=444},true,
                Runtime.ComputerScreen.gameClockSpeed(),Runtime.ComputerScreen.canChangeGameClockSpeed(),
                pointerX,pointerY,Runtime.drawComputerButton,twelveHourTime)
        elseif Runtime.ComputerScreen.tab == "home" then
            Runtime.drawHome(state,pointerX,pointerY)
        elseif Runtime.ComputerScreen.tab == 'financials' or Runtime.ComputerScreen.tab == 'bills'
            or Runtime.ComputerScreen.tab == 'player_wages' then
            Runtime.drawFinancials(state,pointerX,pointerY,twelveHourTime)
        elseif Runtime.ComputerScreen.tab=="groceries" or Runtime.ComputerScreen.tab=="takeout" or Runtime.ComputerScreen.tab=="home_orders" or Runtime.ComputerScreen.tab=="furniture" then
            Runtime.drawHomeShop(state,pointerX,pointerY)
        elseif Runtime.ComputerScreen.tab == 'receipts' then
            Runtime.drawReceipts(state,pointerX,pointerY,twelveHourTime)
        elseif Runtime.ComputerScreen.tab == "inventory" then
            Runtime.drawInventory(state)
        elseif Runtime.ComputerScreen.tab == "hiring" then
            Runtime.Hiring.draw(state,Runtime.ComputerScreen.hiring,pointerX,pointerY,false,Runtime.drawComputerButton,
                Runtime.dependencies.remoteCommand==nil,twelveHourTime)
        elseif Runtime.ComputerScreen.tab == "schedule" then
            Runtime.ComputerScreen.drawSchedule(state,pointerX,pointerY,Runtime.drawComputerButton,twelveHourTime)
        elseif Runtime.ComputerScreen.tab == "warehouse" then
            Runtime.drawWarehouse(state,pointerX,pointerY,assets)
        elseif Runtime.ComputerScreen.tab == "www" then
            if Runtime.ComputerScreen.cartOpen then Runtime.drawCart(state, pointerX, pointerY)
            else Runtime.drawWww(state, pointerX, pointerY, assets); Runtime.drawCartButton(pointerX, pointerY) end
        elseif Runtime.ComputerScreen.tab == "email" or Runtime.ComputerScreen.tab == "estimating" then
            Runtime.drawEmail(state, pointerX, pointerY, assets)
        elseif Runtime.ComputerScreen.tab == "calendar" then
            Runtime.drawCalendar(state, pointerX, pointerY,twelveHourTime)
        elseif Runtime.ComputerScreen.tab == "credit" then
            Runtime.drawCredit(state, pointerX, pointerY)
        elseif Runtime.ComputerScreen.tab == "radio" then
            require("src.jukebox").drawComputerTab(pointerX,pointerY,
                Runtime.ComputerScreen.radioReadOnly(),Runtime.drawComputerButton)
        elseif Runtime.ComputerScreen.tab == "reviews" then
            Runtime.drawReviews(state, pointerX, pointerY, twelveHourTime)
        else
            Runtime.drawJobList(state, pointerX, pointerY)
            Runtime.drawDetail(state, pointerX, pointerY, assets, twelveHourTime)
        end
        Runtime.drawTabSelector(state, pointerX, pointerY)
        Runtime.drawBrowserToolbar(pointerX, pointerY)
        Runtime.drawBrowserOverlay(pointerX, pointerY)
        if compact then
            love.graphics.pop()
            MobileLayout.drawHeader(Runtime,state,screenPointerX,screenPointerY,twelveHourTime)
        end
        Runtime.buttonDrawPointerX, Runtime.buttonDrawPointerY = nil, nil
    end
end

return Component
