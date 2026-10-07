-- Office entry, control positions, and employment actions.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.completionReady(job)
        return Runtime.JobService.completionReady(job)
    end

    function Runtime.ComputerScreen.packagingText(job)
        if not job then return "Customer instructions not specified" end
        if job.packaging == "boxed" then
            return "Boxed paper on pallets; stretch-wrap each finished pallet"
        end
        if job.packaging == "flat" then
            return "Flat stacked on pallets; stretch-wrap each finished pallet"
        end
        return "Customer instructions not specified"
    end

    function Runtime.ComputerScreen.enter(state)
        Runtime.ComputerScreen.tab = "active"
        Runtime.ComputerScreen.emailFolder = "inbox"
        Runtime.ComputerScreen.pages = { active = 1, completed = 1, deliveries = 1 }
        Runtime.ComputerScreen.selectedJobId = nil
        Runtime.ComputerScreen.selectedEmailId = nil
        Runtime.ComputerScreen.emailPage = 1
        Runtime.ComputerScreen.emailSelectionRequired = false
        Runtime.ComputerScreen.quoteText = ""
        Runtime.ComputerScreen.quoteFocused = false
        Runtime.ComputerScreen.quoteReplaceOnType = true
        Runtime.ComputerScreen.promoJobId = nil
        Runtime.ComputerScreen.promoText = ""
        Runtime.ComputerScreen.promoFocused = false
        Runtime.ComputerScreen.calendarYear = state.calendar.year
        Runtime.ComputerScreen.calendarMonth = state.calendar.month
        Runtime.ComputerScreen.calendarSelectedDay = state.calendar.day
        Runtime.ComputerScreen.calendarScroll = 0
        Runtime.ComputerScreen.retailPage = 1
        Runtime.ComputerScreen.wwwSite = 1
        Runtime.ComputerScreen.cart = {}
        Runtime.ComputerScreen.cartOpen = false
        Runtime.ComputerScreen.cartPage = 1
        Runtime.ComputerScreen.machinePage = 1
        Runtime.ComputerScreen.wwwSiteChangedAt = 0
        Runtime.ComputerScreen.tabDropdownOpen = false
        Runtime.ComputerScreen.warehouseConfirmation,Runtime.ComputerScreen.warehousePending,Runtime.ComputerScreen.warehouseMessage=nil,false,nil
        Runtime.ComputerScreen.creditConfirmation = nil
        Runtime.ensureSelection(state)
    end

    function Runtime.ComputerScreen.tabCenter(tabId)
        if tabId == "online" then tabId = "www" end
        for index, tab in ipairs(Runtime.visibleTabs()) do
            if tab.id == tabId then
                local rect = Runtime.tabDropdownRect(index)
                return rect.x + rect.width / 2, rect.y + rect.height / 2
            end
        end
    end

    function Runtime.ComputerScreen.dropdownCenter()
        return Runtime.TAB_DROPDOWN_ARROW.x + Runtime.TAB_DROPDOWN_ARROW.width / 2,
            Runtime.TAB_DROPDOWN_ARROW.y + Runtime.TAB_DROPDOWN_ARROW.height / 2
    end

    function Runtime.ComputerScreen.activeUrl()
        if Runtime.ComputerScreen.tab == "www" then
            local site = Runtime.WWW_SITES[Runtime.ComputerScreen.wwwSite] or Runtime.WWW_SITES[1]
            return site.url
        end
        local tab = Runtime.tabById(Runtime.ComputerScreen.tab)
        return tab and tab.url or "www.thecritternet.com/job-desk"
    end

    function Runtime.activateTab(state, tab)
        Runtime.ComputerScreen.tab = tab.id
        Runtime.ComputerScreen.tabDropdownOpen = false
        Runtime.ComputerScreen.cartOpen = false
        local emailRead = false
        if tab.id == "email" or tab.id == "estimating" then
            local inbox = Runtime.inboxForTab(state)
            Runtime.ComputerScreen.emailPage = 1
            local found = false
            for _, email in ipairs(inbox) do
                if email.id == Runtime.ComputerScreen.selectedEmailId then found = true; break end
            end
            if not found then
                Runtime.ComputerScreen.selectedEmailId = Runtime.ComputerScreen.emailSelectionRequired
                    and nil or (inbox[1] and inbox[1].id or nil)
            end
            emailRead = Runtime.markEmailRead(state, Runtime.selectedEmail(state))
            if tab.id == "estimating" and not Runtime.ComputerScreen.promoJobId then
                Runtime.resetQuoteText(state)
            end
        elseif tab.id == "calendar" then
            Runtime.ComputerScreen.calendarYear = state.calendar.year
            Runtime.ComputerScreen.calendarMonth = state.calendar.month
            Runtime.ComputerScreen.calendarSelectedDay = state.calendar.day
            Runtime.ComputerScreen.calendarScroll = 0
        elseif tab.id == "inventory" then
            Runtime.ComputerScreen.retailPage = 1
        end
        Runtime.ensureSelection(state)
        return { action = "tab", tab = tab.id, emailRead = emailRead }
    end

    function Runtime.ComputerScreen.closeCenter()
        return Runtime.CLOSE.x + Runtime.CLOSE.width / 2, Runtime.CLOSE.y + Runtime.CLOSE.height / 2
    end

    function Runtime.ComputerScreen.completeCenter()
        return Runtime.COMPLETE.x + Runtime.COMPLETE.width / 2, Runtime.COMPLETE.y + Runtime.COMPLETE.height / 2
    end

    function Runtime.ComputerScreen.retailButtonCenter(index)
        local rect = Runtime.retailBuyRect(index)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.retailPageCenter(direction)
        local index = direction == "previous" and 1 or math.min(2, #Runtime.WWW_SITES)
        local rect = Runtime.wwwSiteRect(index)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.wwwSiteCenter(index)
        local rect = Runtime.wwwSiteRect(index)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.machineBuyCenter(index)
        local rect = Runtime.machineBuyRect(index)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.machineSellCenter(index)
        local rect = Runtime.machineSellRect(index)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.machinePageCenter(direction)
        local rect = direction == "previous" and Runtime.ComputerScreen.machinePreviousRect
            or Runtime.ComputerScreen.machineNextRect
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.cartButtonCenter()
        return Runtime.CART_BUTTON.x + Runtime.CART_BUTTON.width / 2, Runtime.CART_BUTTON.y + Runtime.CART_BUTTON.height / 2
    end

    function Runtime.ComputerScreen.cartCheckoutCenter()
        return Runtime.CART_CHECKOUT.x + Runtime.CART_CHECKOUT.width / 2, Runtime.CART_CHECKOUT.y + Runtime.CART_CHECKOUT.height / 2
    end

    function Runtime.ComputerScreen.cartSummary()
        local total, count = Runtime.cartTotal()
        return { total = total, count = count, lines = #(Runtime.ComputerScreen.cart or {}) }
    end

    function Runtime.ComputerScreen.payBillsCenter()
        return Runtime.PAY_BILLS.x + Runtime.PAY_BILLS.width / 2, Runtime.PAY_BILLS.y + Runtime.PAY_BILLS.height / 2
    end

    function Runtime.creditMachineRect(index)
        return { x = Runtime.CREDIT_MACHINE.x, y = Runtime.CREDIT_MACHINE.y + (index - 1) * (Runtime.CREDIT_MACHINE.height + Runtime.CREDIT_MACHINE.gap),
            width = Runtime.CREDIT_MACHINE.width, height = Runtime.CREDIT_MACHINE.height }
    end

    function Runtime.creditMachineActionRect(index)
        local row = Runtime.creditMachineRect(index)
        return { x = Runtime.CREDIT_MACHINE_ACTION.x, y = row.y + 39,
            width = Runtime.CREDIT_MACHINE_ACTION.width, height = Runtime.CREDIT_MACHINE_ACTION.height }
    end

    function Runtime.creditLoanRect(index)
        return { x = Runtime.CREDIT_LOAN.x, y = Runtime.CREDIT_LOAN.y + (index - 1) * (Runtime.CREDIT_LOAN.height + Runtime.CREDIT_LOAN.gap),
            width = Runtime.CREDIT_LOAN.width, height = Runtime.CREDIT_LOAN.height }
    end

    function Runtime.creditLoanActionRect(index)
        local row = Runtime.creditLoanRect(index)
        return { x = Runtime.CREDIT_LOAN_ACTION.x, y = row.y + 42,
            width = Runtime.CREDIT_LOAN_ACTION.width, height = Runtime.CREDIT_LOAN_ACTION.height }
    end

    function Runtime.ComputerScreen.creditMachineCenter(index)
        local rect = Runtime.creditMachineActionRect(index)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.creditChannelCenter(channel)
        local rect = channel == "dealer" and Runtime.CREDIT_CHANNEL_DEALER or Runtime.CREDIT_CHANNEL_ONLINE
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.creditLoanPayCenter(index)
        local rect = Runtime.creditLoanActionRect(index)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.creditSignCenter()
        return Runtime.CREDIT_SIGN.x + Runtime.CREDIT_SIGN.width / 2, Runtime.CREDIT_SIGN.y + Runtime.CREDIT_SIGN.height / 2
    end

    function Runtime.ComputerScreen.creditCancelCenter()
        return Runtime.CREDIT_CANCEL.x + Runtime.CREDIT_CANCEL.width / 2, Runtime.CREDIT_CANCEL.y + Runtime.CREDIT_CANCEL.height / 2
    end

    function Runtime.creditMousepressed(state, x, y)
        local choice = Runtime.ComputerScreen.creditConfirmation
        if choice then
            if Runtime.contains(Runtime.CREDIT_CANCEL, x, y) then
                Runtime.ComputerScreen.creditConfirmation = nil
                return { action = "credit_offer_cancelled" }
            elseif Runtime.contains(Runtime.CREDIT_SIGN, x, y) then
                if Runtime.dependencies.remoteCommand then
                    Runtime.ComputerScreen.creditConfirmation = nil
                    return Runtime.remoteAction("finance_machine", {
                        offerIndex = choice.offerIndex, requestId = choice.requestId, channel = choice.channel,
                    })
                end
                local accepted, result = Runtime.Credit.financeMachine(state, choice.offerIndex,
                    choice.requestId, choice.channel)
                if not accepted then
                    state.message = tostring(result)
                    return { action = "blocked", reason = "finance_offer_changed" }
                end
                Runtime.ComputerScreen.creditConfirmation = nil
                local loan = result.loan
                state.message = string.format("Financed %s: $%d down, $%d financed at %.2f%% APR.",
                    loan.machineName, loan.downPayment, loan.principal, loan.aprBasisPoints / 100)
                return { action = "machine_financed", loan = loan }
            end
            return nil
        end
        if Runtime.contains(Runtime.CREDIT_CHANNEL_ONLINE, x, y) then
            Runtime.ComputerScreen.creditChannel = "online"
            return { action = "credit_channel", channel = "online" }
        elseif Runtime.contains(Runtime.CREDIT_CHANNEL_DEALER, x, y) then
            Runtime.ComputerScreen.creditChannel = "dealer"
            return { action = "credit_channel", channel = "dealer" }
        end
        for index, quote in ipairs(Runtime.Credit.machineQuotes(state, Runtime.ComputerScreen.creditChannel)) do
            if Runtime.contains(Runtime.creditMachineActionRect(index), x, y) then
                if not quote.eligible then
                    state.message = quote.reason or "This financing offer is unavailable."
                    return { action = "blocked", reason = "finance_offer_ineligible" }
                end
                Runtime.ComputerScreen.creditRequestNumber = Runtime.ComputerScreen.creditRequestNumber + 1
                local requestId = Runtime.nextFinanceRequestId(Runtime.ComputerScreen.creditRequestNumber)
                Runtime.ComputerScreen.creditConfirmation = {
                    offerIndex = index, requestId = requestId, channel = Runtime.ComputerScreen.creditChannel,
                }
                return { action = "finance_terms", quote = quote }
            end
        end
        for index, loan in ipairs(Runtime.Credit.loanRows(state)) do
            if Runtime.contains(Runtime.creditLoanActionRect(index), x, y) then
                if loan.installmentsDue < 1 then
                    state.message = "No machine payment is due yet."
                    return { action = "blocked", reason = "no_payment_due" }
                end
                if Runtime.dependencies.remoteCommand then
                    return Runtime.remoteAction("pay_machine_loan", { loanId = loan.id })
                end
                local paid, result = Runtime.Credit.payLoan(state, loan.id)
                if not paid then state.message = tostring(result); return { action = "blocked" } end
                state.message = string.format("Paid $%d on machine loan %s.", result.amount, loan.id)
                return { action = "machine_payment", payment = result }
            end
        end
        return nil
    end

    function Runtime.ComputerScreen.emailButtonCenter(action)
        local rect = action == "accept" and Runtime.EMAIL_ACCEPT or Runtime.EMAIL_DECLINE
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.textInputCenter(kind)
        local rect = kind == "promotion" and Runtime.PROMO_INPUT or Runtime.EMAIL_QUOTE_INPUT
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.rowCenter(row)
        return Runtime.LIST.x + Runtime.LIST.width / 2, Runtime.LIST.y + 14 + (row - 1) * Runtime.ROW_HEIGHT + 18
    end

    function Runtime.ComputerScreen.calendarDayCenter(day)
        local rect = Runtime.calendarDayRect(Runtime.ComputerScreen.calendarYear, Runtime.ComputerScreen.calendarMonth, day)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.calendarScrollCenter(direction)
        local rect = direction == "up" and Runtime.CAL_SCROLL_UP or Runtime.CAL_SCROLL_DOWN
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.ComputerScreen.openEmploymentResume(applicationId)
        Runtime.ComputerScreen.tab="hiring"
        Runtime.Hiring.open(Runtime.ComputerScreen.hiring,applicationId)
    end

    function Runtime.ComputerScreen.hiringMousepressed(state,x,y)
        return Runtime.Hiring.mousepressed(state,Runtime.ComputerScreen.hiring,x,y,function(intent)
            return Runtime.ComputerScreen.employeeCommand(state,intent)
        end,false,Runtime.dependencies.remoteCommand==nil)
    end

    function Runtime.ComputerScreen.scheduleMousepressed(state,x,y)
        return Runtime.ScheduleScreen.mousepressed(state,Runtime.ComputerScreen.schedule,x,y,function(intent)
            return Runtime.ComputerScreen.employeeCommand(state,intent)
        end,false)
    end

    function Runtime.ComputerScreen.drawSchedule(state,x,y,buttonRenderer,twelveHourTime)
        return Runtime.ScheduleScreen.draw(state,Runtime.ComputerScreen.schedule,x,y,false,buttonRenderer,twelveHourTime)
    end

    function Runtime.ComputerScreen.employeeCommand(state,intent)
        local normalized,errorMessage=Runtime.OfficeIntent.normalize(intent)
        if not normalized then state.message=errorMessage;return {action="blocked"} end
        if Runtime.dependencies.remoteCommand then return Runtime.remoteAction(normalized.kind,normalized) end
        local accepted,code,message
        if Runtime.dependencies.warehouseCommand then accepted,code,message=Runtime.dependencies.warehouseCommand(normalized)
        else accepted,message=Runtime.Employees.command(state,normalized) end
        state.message=message or (accepted and "Employment change saved." or "Employment change was not completed.")
        return {action=accepted and "employment_changed" or "blocked"}
    end
end

return Component
