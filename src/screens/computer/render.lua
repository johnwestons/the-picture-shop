-- Office render dispatch.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.ComputerScreen.draw(state, pointerX, pointerY, assets, twelveHourTime)
        Runtime.buttonDrawPointerX, Runtime.buttonDrawPointerY = pointerX, pointerY
        love.graphics.setColor(0.01, 0.02, 0.03, 0.76)
        love.graphics.rectangle("fill", 0, 0, Runtime.Config.baseWidth, Runtime.Config.baseHeight)
        Runtime.drawMonitorFrame(state,twelveHourTime)
        Runtime.panel(Runtime.PANEL, { 0.035, 0.05, 0.065, 0.99 }, { 0.31, 0.56, 0.58, 1 })
        Runtime.drawCritterNetChrome(assets)
        love.graphics.setColor(0.96, 0.94, 0.84, 1)
        local household=Runtime.ComputerScreen.tab=="home" or Runtime.ComputerScreen.tab=="groceries"
            or Runtime.ComputerScreen.tab=="takeout" or Runtime.ComputerScreen.tab=="home_orders" or Runtime.ComputerScreen.tab=="furniture"
        local originalFont = love.graphics.getFont()
        local headerFont = require('src.screens.computer.fonts').get('typewriter', 14)
        if not household then love.graphics.setFont(headerFont) end
        love.graphics.print(household and "MY HOUSEHOLD" or "PICTURE SHOP JOB DESK", 166, 46)
        love.graphics.setFont(originalFont)
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
            if not household then love.graphics.setFont(headerFont) end
            love.graphics.setColor(0.71, 0.83, 0.78, 1)
            love.graphics.printf(item.label, item.x, household and 39 or 42, item.width, "center")
            love.graphics.setFont(originalFont)
            love.graphics.setColor(item.valueColor)
            Runtime.printCenteredFit(item.value, item.x, 52, item.width)
        end
        if pointerX and Runtime.contains(Runtime.CLOSE, pointerX, pointerY) then
            love.graphics.setColor(0.5, 1, 0.85, 0.24)
            love.graphics.rectangle('fill', Runtime.CLOSE.x, Runtime.CLOSE.y,
                Runtime.CLOSE.width, Runtime.CLOSE.height)
        end

        if Runtime.ComputerScreen.tab == "clock" then
            require("src.screens.shop_clock").drawPanel(state,
                {x=110,y=190,width=738,height=394},true,
                Runtime.ComputerScreen.gameClockSpeed(),Runtime.ComputerScreen.canChangeGameClockSpeed(),
                pointerX,pointerY,Runtime.drawComputerButton,twelveHourTime)
        elseif Runtime.ComputerScreen.tab == "home" then
            Runtime.drawContainedPage(function(x,y) Runtime.drawHome(state,x,y) end,
                pointerX,pointerY,Runtime.HOME_PAGE_LAYOUT)
        elseif Runtime.ComputerScreen.tab == 'financials' or Runtime.ComputerScreen.tab == 'bills'
            or Runtime.ComputerScreen.tab == 'player_wages' then
            Runtime.drawFinancials(state,pointerX,pointerY,twelveHourTime)
        elseif Runtime.ComputerScreen.tab=="groceries" or Runtime.ComputerScreen.tab=="takeout" or Runtime.ComputerScreen.tab=="home_orders" or Runtime.ComputerScreen.tab=="furniture" then
            Runtime.drawContainedPage(function(x,y) Runtime.drawHomeShop(state,x,y) end,
                pointerX,pointerY,Runtime.HOME_PAGE_LAYOUT)
        elseif Runtime.ComputerScreen.tab == 'receipts' then
            Runtime.drawReceipts(state,pointerX,pointerY,twelveHourTime)
        elseif Runtime.ComputerScreen.tab == "inventory" then
            Runtime.drawInventory(state)
        elseif Runtime.ComputerScreen.tab == "hiring" then
            Runtime.drawContainedPage(function(x,y)
                Runtime.Hiring.draw(state,Runtime.ComputerScreen.hiring,x,y,false,Runtime.drawComputerButton,
                    Runtime.dependencies.remoteCommand==nil,twelveHourTime)
            end,pointerX,pointerY,Runtime.HIRING_PAGE_LAYOUT)
        elseif Runtime.ComputerScreen.tab == "schedule" then
            Runtime.drawContainedPage(function(x,y)
                Runtime.ComputerScreen.drawSchedule(state,x,y,Runtime.drawComputerButton,twelveHourTime)
            end,pointerX,pointerY,Runtime.SCHEDULE_PAGE_LAYOUT)
        elseif Runtime.ComputerScreen.tab == "warehouse" then
            local layout=Runtime.ComputerScreen.warehouseStagingPage
                and Runtime.WAREHOUSE_STAGING_LAYOUT or Runtime.WAREHOUSE_PAGE_LAYOUT
            Runtime.drawContainedPage(function(x,y) Runtime.drawWarehouse(state,x,y,assets) end,
                pointerX,pointerY,layout)
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
            Runtime.drawContainedPage(function(x,y)
                require("src.jukebox").drawComputerTab(x,y,
                    Runtime.ComputerScreen.radioReadOnly(),Runtime.drawComputerButton)
            end,pointerX,pointerY,Runtime.RADIO_PAGE_LAYOUT)
        elseif Runtime.ComputerScreen.tab == "reviews" then
            Runtime.drawReviews(state, pointerX, pointerY, twelveHourTime)
        else
            Runtime.drawJobList(state, pointerX, pointerY)
            Runtime.drawDetail(state, pointerX, pointerY, assets, twelveHourTime)
        end
        Runtime.drawTabSelector(state, pointerX, pointerY)
        Runtime.drawBrowserToolbar(pointerX, pointerY)
        Runtime.drawBrowserOverlay(pointerX, pointerY)

        Runtime.buttonDrawPointerX, Runtime.buttonDrawPointerY = nil, nil
    end
end

return Component
