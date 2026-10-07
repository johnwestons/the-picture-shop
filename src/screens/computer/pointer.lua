-- Office pointer actions and tab dispatch.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.ComputerScreen.mousepressed(state, x, y, button)
        if button ~= 1 then return nil end
        -- Do not retain Android keyboard focus when the player taps elsewhere.
        -- The estimate and promotion input hit targets below explicitly opt back in.
        Runtime.ComputerScreen.quoteFocused = false
        Runtime.ComputerScreen.promoFocused = false
        if x>=738 and x<=872 and y>=107 and y<=132 then
            Runtime.ComputerScreen.tab="clock";Runtime.ComputerScreen.tabDropdownOpen=false;return {action="clock"}
        end
        if Runtime.contains(Runtime.CLOSE, x, y) then
            Runtime.ComputerScreen.tabDropdownOpen = false
            return { action = "close" }
        end
        if Runtime.contains(Runtime.TAB_DROPDOWN_ARROW, x, y) then
            Runtime.ComputerScreen.tabDropdownOpen = not Runtime.ComputerScreen.tabDropdownOpen
            return { action = Runtime.ComputerScreen.tabDropdownOpen
                and "dropdown_opened" or "dropdown_closed" }
        end
        if Runtime.ComputerScreen.tabDropdownOpen then
            for index, tab in ipairs(Runtime.visibleTabs()) do
                if Runtime.contains(Runtime.tabDropdownRect(index), x, y) then
                    return Runtime.activateTab(state, tab)
                end
            end
            Runtime.ComputerScreen.tabDropdownOpen = false
            return { action = "dropdown_closed" }
        end
        if Runtime.ComputerScreen.tab=="clock" then
            local speed=require("src.screens.shop_clock").speedAt(x,y,
                {x=82,y=184,width=792,height=444})
            if speed then
                if not Runtime.ComputerScreen.canChangeGameClockSpeed() then
                    state.message="Only the host can change game speed."
                    return {action="blocked"}
                end
                if Runtime.dependencies.setGameClockSpeed
                    and Runtime.dependencies.setGameClockSpeed(speed)==true
                then
                    return {action="clock_speed_changed",speed=speed}
                end
                return {action="blocked"}
            end
        end
        if Runtime.ComputerScreen.tab == "warehouse" then return Runtime.warehouseMousepressed(state,x,y) end
        if Runtime.ComputerScreen.tab == "hiring" then
            return Runtime.ComputerScreen.hiringMousepressed(state,x,y)
        end
        if Runtime.ComputerScreen.tab == "schedule" then return Runtime.ComputerScreen.scheduleMousepressed(state,x,y) end
        if Runtime.ComputerScreen.tab == "www" and Runtime.ComputerScreen.cartOpen then
            local maximumPage = math.max(1, math.ceil(#Runtime.ComputerScreen.cart / Runtime.CART_PAGE_SIZE))
            if Runtime.contains(Runtime.CART_BACK, x, y) then
                Runtime.ComputerScreen.cartOpen = false
                return { action = "cart_closed" }
            elseif Runtime.contains(Runtime.CART_CLEAR, x, y) then
                Runtime.ComputerScreen.cart, Runtime.ComputerScreen.cartPage = {}, 1
                state.message = "Online cart cleared."
                return { action = "cart_cleared" }
            elseif Runtime.contains(Runtime.CART_PREVIOUS, x, y) then
                Runtime.ComputerScreen.cartPage = math.max(1, Runtime.ComputerScreen.cartPage - 1)
                return { action = "cart_page" }
            elseif Runtime.contains(Runtime.CART_NEXT, x, y) then
                Runtime.ComputerScreen.cartPage = math.min(maximumPage, Runtime.ComputerScreen.cartPage + 1)
                return { action = "cart_page" }
            elseif Runtime.contains(Runtime.CART_CHECKOUT, x, y) then
                if Runtime.dependencies.remoteCommand then
                    local items = {}
                    for _, entry in ipairs(Runtime.ComputerScreen.cart) do
                        items[#items + 1] = { kind = entry.kind, quantity = entry.quantity,
                            categoryIndex = entry.categoryIndex, itemIndex = entry.itemIndex, offerIndex = entry.offerIndex }
                    end
                    return Runtime.remoteAction("checkout", { items = items })
                end
                local succeeded, result = Runtime.checkoutCart(state)
                if not succeeded then state.message = result; return { action = "blocked" } end
                state.message = string.format(
                    "Checkout complete: %d item%s, $%d total. Receipt email%s received.",
                    result.count, result.count == 1 and "" or "s", result.total,
                    #result.orders == 1 and "" or "s")
                return { action = "cart_checked_out", result = result }
            end
            local first = (Runtime.ComputerScreen.cartPage - 1) * Runtime.CART_PAGE_SIZE + 1
            for visibleIndex = 1, Runtime.CART_PAGE_SIZE do
                local entryIndex = first + visibleIndex - 1
                if Runtime.ComputerScreen.cart[entryIndex] and Runtime.contains(Runtime.cartRemoveRect(visibleIndex), x, y) then
                    table.remove(Runtime.ComputerScreen.cart, entryIndex)
                    Runtime.ComputerScreen.cartPage = math.min(Runtime.ComputerScreen.cartPage,
                        math.max(1, math.ceil(#Runtime.ComputerScreen.cart / Runtime.CART_PAGE_SIZE)))
                    state.message = "Removed item from the online cart."
                    return { action = "cart_item_removed" }
                end
            end
            return nil
        end
        if Runtime.ComputerScreen.tab == "www" and Runtime.contains(Runtime.CART_BUTTON, x, y) then
            Runtime.ComputerScreen.cartOpen = true
            Runtime.ComputerScreen.cartPage = 1
            return { action = "cart_opened" }
        end
        if Runtime.ComputerScreen.tab == "inventory" then return nil end
        if Runtime.ComputerScreen.tab == "www" then
            for index = 1, #Runtime.WWW_SITES do
                if Runtime.contains(Runtime.wwwSiteRect(index), x, y) then
                    Runtime.ComputerScreen.wwwSite = index
                    Runtime.ComputerScreen.wwwSiteChangedAt = love.timer.getTime()
                    return { action = "www_site", site = Runtime.WWW_SITES[index] }
                end
            end
            local site = Runtime.WWW_SITES[Runtime.ComputerScreen.wwwSite] or Runtime.WWW_SITES[1]
            if site.kind ~= "machines" then
                local category = Runtime.Procurement.category(site.categoryIndex)
                for index, item in ipairs(category.items) do
                    if item.available ~= false and item.retailPrice and Runtime.contains(Runtime.retailBuyRect(index), x, y) then
                        Runtime.addToCart({
                            key = string.format("supply:%d:%d", site.categoryIndex, index),
                            kind = "supply", categoryIndex = site.categoryIndex, itemIndex = index,
                            name = item.retailName, price = item.retailPrice,
                        })
                        state.message = item.retailName .. " added to the Critter Net cart."
                        return { action = "cart_item_added" }
                    end
                end
                return nil
            end
            for index, offer in ipairs(Runtime.MachineFleet.offers("online")) do
                if Runtime.contains(Runtime.machineBuyRect(index), x, y) then
                    if (state.money or 0) < offer.price then
                        Runtime.ComputerScreen.tab = "credit"
                        Runtime.ComputerScreen.creditChannel = "online"
                        state.message = "Review the down payment and monthly terms for " .. offer.name .. " in Credit."
                        return { action = "credit_financing" }
                    end
                    Runtime.addToCart({
                        key = "machine:" .. tostring(index), kind = "machine", offerIndex = index,
                        modelId = offer.modelId, name = offer.name, price = offer.price,
                    })
                    state.message = offer.name .. " added to the online cart."
                    return { action = "cart_item_added" }
                end
            end
            local owned, pages = Runtime.ComputerScreen.ownedMachinePage(state)
            if pages > 1 and Runtime.contains(Runtime.ComputerScreen.machinePreviousRect, x, y) then
                Runtime.ComputerScreen.machinePage = math.max(1, Runtime.ComputerScreen.machinePage - 1)
                return { action = "machine_page" }
            end
            if pages > 1 and Runtime.contains(Runtime.ComputerScreen.machineNextRect, x, y) then
                Runtime.ComputerScreen.machinePage = math.min(pages, Runtime.ComputerScreen.machinePage + 1)
                return { action = "machine_page" }
            end
            for visibleIndex = 1, Runtime.ComputerScreen.machinePageSize do
                local item = owned[(Runtime.ComputerScreen.machinePage - 1) * Runtime.ComputerScreen.machinePageSize + visibleIndex]
                if item and Runtime.contains(Runtime.machineSellRect(visibleIndex), x, y) then
                    if Runtime.dependencies.remoteCommand then return Runtime.remoteAction("sell", { id = item.id }) end
                    local succeeded, result = Runtime.MachineFleet.sell(state, item.id, "online")
                    if not succeeded then state.message = tostring(result); return { action = "blocked" } end
                    state.message = string.format("Sold %s online for $%d.", result.machine.name, result.price)
                    return { action = "machine_sold", sale = result }
                end
            end
            return nil
        end
        if Runtime.ComputerScreen.tab == "bills" then
            if Runtime.contains(Runtime.PAY_BILLS, x, y) then
                if Runtime.dependencies.remoteCommand then return Runtime.remoteAction("pay_bills") end
                local paid, result = Runtime.BusinessCalendar.pay(state)
                if not paid then state.message = result; return { action = "blocked" } end
                state.message = string.format("Paid $%.2f in operating bills, customer claims and wages.",result)
                return { action = "bill_paid", amount = result }
            end
            return nil
        end
        if Runtime.ComputerScreen.tab == "credit" then return Runtime.creditMousepressed(state, x, y) end
        if Runtime.ComputerScreen.tab == "calendar" then
            if Runtime.contains(Runtime.CAL_PREVIOUS, x, y) then
                Runtime.ComputerScreen.calendarYear, Runtime.ComputerScreen.calendarMonth = Runtime.BusinessCalendar.shiftMonth(
                    Runtime.ComputerScreen.calendarYear, Runtime.ComputerScreen.calendarMonth, -1)
                Runtime.ComputerScreen.calendarSelectedDay, Runtime.ComputerScreen.calendarScroll = nil, 0
                return { action = "calendar_month" }
            elseif Runtime.contains(Runtime.CAL_NEXT, x, y) then
                Runtime.ComputerScreen.calendarYear, Runtime.ComputerScreen.calendarMonth = Runtime.BusinessCalendar.shiftMonth(
                    Runtime.ComputerScreen.calendarYear, Runtime.ComputerScreen.calendarMonth, 1)
                Runtime.ComputerScreen.calendarSelectedDay, Runtime.ComputerScreen.calendarScroll = nil, 0
                return { action = "calendar_month" }
            end
            local events, maximum = Runtime.clampCalendarScroll(state)
            if Runtime.contains(Runtime.CAL_SCROLL_UP, x, y) then
                Runtime.ComputerScreen.calendarScroll = math.max(0, Runtime.ComputerScreen.calendarScroll - 1)
                return { action = "calendar_scroll" }
            elseif Runtime.contains(Runtime.CAL_SCROLL_DOWN, x, y) then
                Runtime.ComputerScreen.calendarScroll = math.min(maximum, Runtime.ComputerScreen.calendarScroll + 1)
                return { action = "calendar_scroll" }
            end
            local day = Runtime.calendarDayAt(Runtime.ComputerScreen.calendarYear, Runtime.ComputerScreen.calendarMonth, x, y)
            if day then
                Runtime.ComputerScreen.calendarSelectedDay = day
                for index, event in ipairs(events) do
                    if event.day == day then
                        Runtime.ComputerScreen.calendarScroll = math.min(maximum, math.max(0, index - 1))
                        break
                    end
                end
                return { action = "calendar_day", day = day }
            end
            for row = 1, Runtime.CAL_EVENT_LIST.visibleRows do
                local index = Runtime.ComputerScreen.calendarScroll + row
                local rect = { x = Runtime.CAL_EVENT_LIST.x, y = Runtime.CAL_EVENT_LIST.y + (row - 1) * Runtime.CAL_EVENT_LIST.rowHeight,
                    width = Runtime.CAL_EVENT_LIST.width, height = 31 }
                if events[index] and Runtime.contains(rect, x, y) then
                    Runtime.ComputerScreen.calendarSelectedDay = events[index].day
                    return { action = "calendar_event", event = events[index] }
                end
            end
            return nil
        end
        if Runtime.ComputerScreen.tab == "email" or Runtime.ComputerScreen.tab == "estimating" then
            if Runtime.ComputerScreen.promoJobId then
                if Runtime.contains(Runtime.PROMO_INPUT, x, y) then
                    Runtime.ComputerScreen.promoFocused = true
                    return { action = "promo_focus" }
                end
                if Runtime.contains(Runtime.EMAIL_DECLINE, x, y) then
                    Runtime.ComputerScreen.promoJobId, Runtime.ComputerScreen.promoText = nil, ""
                    Runtime.ComputerScreen.promoFocused = false
                    return { action = "promo_cancelled" }
                elseif Runtime.contains(Runtime.PROMO, x, y) then
                    if Runtime.dependencies.remoteCommand then return Runtime.remoteAction("promotion", { id = Runtime.ComputerScreen.promoJobId, text = Runtime.ComputerScreen.promoText }) end
                    local job = Runtime.findJob(state.jobs.completed or {}, Runtime.ComputerScreen.promoJobId)
                    local succeeded, result = Runtime.JobService.sendPromotion(state, job, Runtime.ComputerScreen.promoText)
                    if not succeeded then state.message = tostring(result); return { action = "blocked" } end
                    Runtime.ComputerScreen.promoJobId, Runtime.ComputerScreen.promoText = nil, ""
                    Runtime.ComputerScreen.promoFocused = false
                    state.message = "Sent " .. result.recipient .. " a 10% returning-client offer."
                    return { action = "promotion_sent", promotion = result }
                end
                Runtime.ComputerScreen.promoFocused = false
                return nil
            end
            if Runtime.ComputerScreen.tab == "email" and Runtime.contains(Runtime.EMAIL_FOLDER_INBOX, x, y) then
                Runtime.ComputerScreen.emailFolder = "inbox"
                Runtime.ComputerScreen.emailPage = 1
                Runtime.ComputerScreen.emailSelectionRequired = false
                local inbox = Runtime.inboxForTab(state)
                Runtime.ComputerScreen.selectedEmailId = inbox[1] and inbox[1].id or nil
                local emailRead = Runtime.markEmailRead(state, inbox[1])
                return { action = "email_folder", folder = "inbox", emailRead = emailRead }
            elseif Runtime.ComputerScreen.tab == "email" and Runtime.contains(Runtime.EMAIL_FOLDER_ARCHIVE, x, y) then
                Runtime.ComputerScreen.emailFolder = "archive"
                Runtime.ComputerScreen.emailPage = 1
                Runtime.ComputerScreen.emailSelectionRequired = false
                local inbox = Runtime.inboxForTab(state)
                Runtime.ComputerScreen.selectedEmailId = inbox[1] and inbox[1].id or nil
                return { action = "email_folder", folder = "archive" }
            end
            local inbox = Runtime.inboxForTab(state)
            local pageSize = Runtime.emailPageSize()
            local maximumEmailPage = math.max(1, math.ceil(#inbox / pageSize))
            Runtime.ComputerScreen.emailPage = math.max(1, math.min(Runtime.ComputerScreen.emailPage or 1, maximumEmailPage))
            if Runtime.contains(Runtime.EMAIL_PREVIOUS, x, y) and Runtime.ComputerScreen.emailPage > 1 then
                Runtime.ComputerScreen.emailPage = Runtime.ComputerScreen.emailPage - 1
                local email = inbox[(Runtime.ComputerScreen.emailPage - 1) * pageSize + 1]
                Runtime.ComputerScreen.selectedEmailId = email and email.id or nil
                local emailRead = Runtime.markEmailRead(state, email)
                Runtime.ComputerScreen.emailSelectionRequired = false
                Runtime.resetQuoteText(state)
                return { action = "email_page", emailRead = emailRead }
            elseif Runtime.contains(Runtime.EMAIL_NEXT, x, y) and Runtime.ComputerScreen.emailPage < maximumEmailPage then
                Runtime.ComputerScreen.emailPage = Runtime.ComputerScreen.emailPage + 1
                local email = inbox[(Runtime.ComputerScreen.emailPage - 1) * pageSize + 1]
                Runtime.ComputerScreen.selectedEmailId = email and email.id or nil
                local emailRead = Runtime.markEmailRead(state, email)
                Runtime.ComputerScreen.emailSelectionRequired = false
                Runtime.resetQuoteText(state)
                return { action = "email_page", emailRead = emailRead }
            end
            if not Runtime.ComputerScreen.emailSelectionRequired and not Runtime.ComputerScreen.selectedEmailId and inbox[1] then
                Runtime.ComputerScreen.selectedEmailId = inbox[1].id
            end
            local firstEmail = (Runtime.ComputerScreen.emailPage - 1) * pageSize + 1
            for row = 1, pageSize do
                local email = inbox[firstEmail + row - 1]
                if not email then break end
                local rect = { x = 94, y = Runtime.emailRowY() + (row - 1) * 54, width = 280, height = 46 }
                if Runtime.contains(rect, x, y) then
                    Runtime.ComputerScreen.selectedEmailId = email.id
                    Runtime.ComputerScreen.emailSelectionRequired = false
                    local emailRead = Runtime.markEmailRead(state, email)
                    Runtime.resetQuoteText(state)
                    return { action = "email_select", email = email, emailRead = emailRead }
                end
            end
            local function deleteCurrentEmail(email)
                if Runtime.dependencies.remoteCommand then return Runtime.remoteAction("delete_email", { id = email.id }) end
                local deleted, result = Runtime.JobService.deleteEmail(state, email.id)
                if not deleted then state.message = tostring(result); return { action = "blocked" } end
                Runtime.ComputerScreen.selectedEmailId = nil
                Runtime.ComputerScreen.emailPage = 1
                Runtime.ComputerScreen.emailSelectionRequired = true
                Runtime.resetQuoteText(state)
                state.message = email.awaitingReply and "Cancelled the waiting estimate email."
                    or "Deleted the email."
                return { action = "email_deleted", email = result }
            end
            local currentEmail = Runtime.selectedEmail(state)
            if currentEmail and currentEmail.serviceNotice then
                Runtime.ComputerScreen.quoteFocused = false
                if Runtime.contains(Runtime.EMAIL_DELETE, x, y) then return deleteCurrentEmail(currentEmail) end
                if Runtime.contains(Runtime.EMAIL_DECLINE, x, y) then
                    if Runtime.dependencies.remoteCommand then return Runtime.remoteAction("archive_service", { id = currentEmail.id }) end
                    Runtime.JobService.archiveServiceNotice(state, currentEmail.id)
                    Runtime.ComputerScreen.selectedEmailId = nil
                    Runtime.ComputerScreen.emailSelectionRequired = true
                    state.message = "Archived the technician's service notice."
                    return { action = "service_notice_dismissed" }
                end
                return nil
            end
            if currentEmail and currentEmail.archiveRecord then
                Runtime.ComputerScreen.quoteFocused = false
                if Runtime.contains(Runtime.EMAIL_DELETE, x, y) then return deleteCurrentEmail(currentEmail) end
                return nil
            end
            if currentEmail and not currentEmail.job then
                Runtime.ComputerScreen.quoteFocused = false
                if currentEmail.applicationId and Runtime.contains(Runtime.EMAIL_ACCEPT,x,y) then
                    Runtime.ComputerScreen.openEmploymentResume(currentEmail.applicationId)
                    return {action="hiring_resume_opened"}
                end
                if Runtime.contains(Runtime.EMAIL_DELETE, x, y) then return deleteCurrentEmail(currentEmail) end
                if Runtime.contains(Runtime.EMAIL_DECLINE, x, y) then
                    if Runtime.dependencies.remoteCommand then return Runtime.remoteAction("archive", { id = currentEmail.id }) end
                    Runtime.JobService.dismissInboxNotice(state, currentEmail.id)
                    Runtime.ComputerScreen.selectedEmailId = nil
                    Runtime.ComputerScreen.emailPage = 1
                    Runtime.ComputerScreen.emailSelectionRequired = true
                    state.message = "Archived the email."
                    return { action = "inbox_notice_dismissed" }
                end
                return nil
            end
            if currentEmail and currentEmail.awaitingReply and Runtime.contains(Runtime.EMAIL_DELETE, x, y) then
                return deleteCurrentEmail(currentEmail)
            end
            if Runtime.ComputerScreen.tab == "estimating" and currentEmail
                and currentEmail.job and not currentEmail.awaitingReply
                and Runtime.contains(Runtime.EMAIL_QUOTE_INPUT, x, y)
            then
                Runtime.ComputerScreen.quoteFocused = true
                Runtime.ComputerScreen.quoteReplaceOnType = true
                return { action = "quote_focus" }
            end
            if Runtime.ComputerScreen.tab == "estimating" and currentEmail
                and currentEmail.job and not currentEmail.awaitingReply
                and Runtime.ComputerScreen.selectedEmailId and Runtime.contains(Runtime.EMAIL_ACCEPT, x, y)
            then
                if Runtime.dependencies.remoteCommand then return Runtime.remoteAction("estimate", { id = Runtime.ComputerScreen.selectedEmailId, amount = tonumber(Runtime.ComputerScreen.quoteText) }) end
                local succeeded, result = Runtime.JobService.submitEmailQuote(
                    state, Runtime.ComputerScreen.selectedEmailId, tonumber(Runtime.ComputerScreen.quoteText), os.time())
                if not succeeded then state.message = tostring(result); return { action = "blocked" } end
                Runtime.ComputerScreen.selectedEmailId = nil
                Runtime.ComputerScreen.emailSelectionRequired = true
                Runtime.resetQuoteText(state)
                state.message = string.format("Sent %s a $%d estimate. It expires in 3 days.",
                    result.job.company, result.amount)
                return { action = "estimate_sent", result = result }
            elseif Runtime.ComputerScreen.tab == "estimating" and currentEmail
                and currentEmail.job and not currentEmail.awaitingReply
                and Runtime.ComputerScreen.selectedEmailId and Runtime.contains(Runtime.EMAIL_DECLINE, x, y)
            then
                if Runtime.dependencies.remoteCommand then return Runtime.remoteAction("decline", { id = Runtime.ComputerScreen.selectedEmailId }) end
                local succeeded, result = Runtime.JobService.respondToEmail(
                    state, Runtime.ComputerScreen.selectedEmailId, "declined", os.time())
                if not succeeded then state.message = tostring(result); return { action = "blocked" } end
                Runtime.ComputerScreen.selectedEmailId = nil
                Runtime.ComputerScreen.emailSelectionRequired = true
                Runtime.resetQuoteText(state)
                state.message = "Declined email request " .. result.id .. "."
                return { action = "email_declined", job = result }
            end
            return nil
        end

        local _, visible, page, maximumPage = Runtime.currentPageJobs(state)
        if Runtime.contains(Runtime.PREVIOUS, x, y) and page > 1 then
            Runtime.ComputerScreen.pages[Runtime.ComputerScreen.tab] = page - 1
            local _, pageJobs = Runtime.currentPageJobs(state)
            Runtime.ComputerScreen.selectedJobId = pageJobs[1] and pageJobs[1].id or nil
            return { action = "page", page = page - 1 }
        end
        if Runtime.contains(Runtime.NEXT, x, y) and page < maximumPage then
            Runtime.ComputerScreen.pages[Runtime.ComputerScreen.tab] = page + 1
            local _, pageJobs = Runtime.currentPageJobs(state)
            Runtime.ComputerScreen.selectedJobId = pageJobs[1] and pageJobs[1].id or nil
            return { action = "page", page = page + 1 }
        end
        for row, job in ipairs(visible) do
            local rect = { x = Runtime.LIST.x + 8, y = Runtime.LIST.y + 14 + (row - 1) * Runtime.ROW_HEIGHT,
                width = Runtime.LIST.width - 16, height = 38 }
            if Runtime.contains(rect, x, y) then
                Runtime.ComputerScreen.selectedJobId = job.id
                return { action = "select", job = job }
            end
        end
        local selected = Runtime.findJob(Runtime.jobsForTab(state, Runtime.ComputerScreen.tab), Runtime.ComputerScreen.selectedJobId)
        if Runtime.ComputerScreen.tab == "active" and Runtime.contains(Runtime.COMPLETE, x, y) then
            return { action = Runtime.completionReady(selected) and "pickup_ready" or "completion_blocked",
                job = selected }
        end
        if Runtime.ComputerScreen.tab == "completed" and selected
            and not Runtime.promotionSentForJob(state, selected) and Runtime.contains(Runtime.JOB_PROMO, x, y)
        then
            Runtime.ComputerScreen.promoJobId = selected.id
            Runtime.ComputerScreen.promoText = ""
            Runtime.ComputerScreen.promoFocused = false
            Runtime.ComputerScreen.tab = "email"
            return { action = "promotion_compose", job = selected }
        end
        return nil
    end

    function Runtime.ComputerScreen.wheelmoved(state, _, y)
        if Runtime.ComputerScreen.tab ~= "calendar" or y == 0 then return false end
        local _, maximum = Runtime.clampCalendarScroll(state)
        Runtime.ComputerScreen.calendarScroll = math.min(maximum,
            math.max(0, Runtime.ComputerScreen.calendarScroll - (y > 0 and 1 or -1)))
        return true
    end
end

return Component
