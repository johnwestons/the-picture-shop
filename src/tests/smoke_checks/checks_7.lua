-- Game integration checks with the original assertions and shared scenario state.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.check("computer_status_vocabulary", Context.context.computerScreen.statusLabel("in_production")
        == "In production"
        and Context.context.computerScreen.statusLabel("pickup_in_progress") == "Pickup in progress"
        and Context.context.computerScreen.statusLabel("completed") == "Completed and paid")
    Context.check("computer_inventory_tab_click",
        Context.selectComputerTab(Context.context.computerScreen, Context.serviceState, "inventory").tab == "inventory")
    Context.officeInventory = Context.context.procurement.inventoryRows(Context.serviceState)
    Context.check("computer_inventory_exposes_purchasable_stock", #Context.officeInventory >= 10
        and Context.officeInventory[1].id == "house_sheets"
        and Context.officeInventory[3].id == "shipping_cartons"
        and Context.officeInventory[4].id == "stretch_film"
        and Context.officeInventory[5].id == "maintenance_kit"
        and Context.officeInventory[6].id == "black_ink"
        and Context.officeInventory[10].id == "raw_press_plates")
    Context.wwwTabResult = Context.selectComputerTab(Context.context.computerScreen, Context.serviceState, "www")
    Context.paperSiteX, Context.paperSiteY = Context.context.computerScreen.wwwSiteCenter(1)
    Context.paperSiteResult = Context.context.computerScreen.mousepressed(Context.serviceState, Context.paperSiteX, Context.paperSiteY, 1)
    Context.retailX, Context.retailY = Context.context.computerScreen.retailButtonCenter(1)
    Context.cartAdd = Context.context.computerScreen.mousepressed(Context.serviceState, Context.retailX, Context.retailY, 1)
    Context.cartBeforeCheckout = Context.context.computerScreen.cartSummary()
    Context.cartX, Context.cartY = Context.context.computerScreen.cartButtonCenter()
    Context.context.computerScreen.mousepressed(Context.serviceState, Context.cartX, Context.cartY, 1)
    Context.checkoutX, Context.checkoutY = Context.context.computerScreen.cartCheckoutCenter()
    Context.computerCheckout = Context.context.computerScreen.mousepressed(Context.serviceState, Context.checkoutX, Context.checkoutY, 1)
    Context.computerOrder = Context.computerCheckout and Context.computerCheckout.result.orders[1]
    Context.check("computer_supply_store_reviews_cart_before_delivery_order", Context.wwwTabResult
        and Context.wwwTabResult.tab == "www" and Context.paperSiteResult
        and Context.paperSiteResult.site.url == "www.thecritternet.com/paper-depot" and Context.cartAdd
        and Context.cartAdd.action == "cart_item_added"
        and Context.cartBeforeCheckout.count == 1 and Context.cartBeforeCheckout.total == 30
        and Context.computerCheckout.action == "cart_checked_out"
        and Context.computerOrder.channel == "computer"
        and Context.computerOrder.pallets[1].quantity == 250
        and Context.serviceState.clientEmails.inbox[#Context.serviceState.clientEmails.inbox].orderId == Context.computerOrder.id)
    Context.closeX, Context.closeY = Context.context.computerScreen.closeCenter()
    Context.check("computer_close_hit_target", Context.context.computerScreen.mousepressed(
        Context.serviceState, Context.closeX, Context.closeY, 1).action == "close")
    Context.check("computer_ignores_outside_click", Context.context.computerScreen.mousepressed(
        Context.serviceState, 10, 10, 1) == nil)
    Context.billUiState = Context.context.State.new()
    Context.billUiState.money = 2000
    Context.context.businessCalendar.update(Context.billUiState, 31 * Context.context.config.businessCalendar.secondsPerDay)
    Context.context.computerScreen.enter(Context.billUiState)
    Context.billsTabResult = Context.selectComputerTab(Context.context.computerScreen, Context.billUiState, "bills")
    Context.payBillsX, Context.payBillsY = Context.context.computerScreen.payBillsCenter()
    Context.billPayment = Context.context.computerScreen.mousepressed(Context.billUiState, Context.payBillsX, Context.payBillsY, 1)
    Context.check("computer_bills_tab_pays_monthly_expenses", Context.billsTabResult and Context.billsTabResult.tab == "bills"
        and Context.billPayment and Context.billPayment.action == "bill_paid" and Context.billPayment.amount == 1650
        and Context.billUiState.money == 350 and Context.billUiState.bills.balance == 0)

    Context.calendarUiState = Context.context.State.new()
    Context.calendarUiState.clientEmails.pending = {}
    for index = 1, 12 do
        Context.calendarUiState.clientEmails.pending[index] = {
            id = "CAL-EMAIL-" .. index, sender = "Client " .. index, subject = "Scheduled request",
            readyAtHours = (index - 1) * 24,
        }
        Context.calendarUiState.bills.ledger[index] = {
            id = "CAL-BILL-" .. index, total = 100, status = "unpaid",
            issuedOnDay = index - 1, dueOnDay = index - 1,
        }
    end
    Context.privateReplySchedule = Context.context.businessCalendar.events(Context.calendarUiState)
    Context.leakedClientReply = false
    for _, event in ipairs(Context.privateReplySchedule) do
        if tostring(event.title):find("Incoming email", 1, true) then Context.leakedClientReply = true end
    end
    Context.check("calendar_hides_future_client_email_replies", not Context.leakedClientReply)
    Context.context.computerScreen.enter(Context.calendarUiState)
    Context.selectComputerTab(Context.context.computerScreen, Context.calendarUiState, "calendar")
    Context.calendarDayX, Context.calendarDayY = Context.context.computerScreen.calendarDayCenter(5)
    Context.selectedCalendarDay = Context.context.computerScreen.mousepressed(
        Context.calendarUiState, Context.calendarDayX, Context.calendarDayY, 1)
    Context.check("computer_calendar_days_are_clickable", Context.selectedCalendarDay
        and Context.selectedCalendarDay.action == "calendar_day" and Context.selectedCalendarDay.day == 5
        and Context.context.computerScreen.calendarSelectedDay == 5)
    Context.context.computerScreen.calendarScroll = 0
    Context.check("computer_calendar_event_list_mouse_wheel_scrolls",
        Context.context.computerScreen.wheelmoved(Context.calendarUiState, 0, -1)
        and Context.context.computerScreen.calendarScroll == 1)
    Context.calendarDownX, Context.calendarDownY = Context.context.computerScreen.calendarScrollCenter("down")
    Context.calendarScrollResult = Context.context.computerScreen.mousepressed(
        Context.calendarUiState, Context.calendarDownX, Context.calendarDownY, 1)
    Context.check("computer_calendar_event_list_buttons_scroll", Context.calendarScrollResult
        and Context.calendarScrollResult.action == "calendar_scroll"
        and Context.context.computerScreen.calendarScroll == 2)

    Context.JobLoopIntegration.run(Context.context, Context.check, Context.jobs)

    Context.CutterIntegration.run(Context.context, Context.check, Context.jobs)

    Context.SaveIntegration.run(Context.context, Context.check, Context.economy, Context.jobs)

    Context.UiIntegration.run(Context.context, Context.check)
end

return Component
