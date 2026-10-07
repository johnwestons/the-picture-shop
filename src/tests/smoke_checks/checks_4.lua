-- Game integration checks with the original assertions and shared scenario state.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.check("customer_enters_building", Context.customer.state == "entering" and Context.customer.visible)
    Context.customer:update(0.50, { x = 500, y = 500 })
    Context.check("customer_waits_at_reception", Context.customer.state == "waiting" and Context.customer.x == 40 and Context.customer.y == 40)
    Context.check("customer_reception_interaction", Context.customer:getInteraction() ~= nil)
    Context.check("customer_begins_review", Context.customer:beginReview() and Context.customer.state == "reviewing")
    Context.check("customer_accepts", Context.customer:resolve("accepted") and Context.customer.state == "exiting")
    Context.customer:update(1, { x = 500, y = 500 })
    Context.check("customer_exits_after_decision", Context.customer.state == "finished"
        and not Context.customer.visible
        and Context.customer.decision == "accepted")

    Context.spacedVisitor = Context.context.Customer.new({
        route = { { x = 0, y = 0 }, { x = 10, y = 0 } },
        initialArrivalDelay = 2,
        arrivalDelayMin = 10,
        arrivalDelayMax = 20,
    })
    Context.check("visitor_uses_initial_arrival_delay", Context.spacedVisitor.timer == 2)
    Context.spacedVisitor:update(1, { x = 500, y = 500 }, true)
    Context.check("visitor_cooldown_pauses_for_occupied_reception", Context.spacedVisitor.timer == 2
        and Context.spacedVisitor.state == "scheduled")
    Context.spacedVisitor:reset(false)
    Context.check("visitor_repeat_arrival_is_randomized_in_range",
        Context.spacedVisitor.timer >= 10 and Context.spacedVisitor.timer <= 20)

    Context.declinedCustomer = Context.context.Customer.new({
        route = { { x = 0, y = 0 }, { x = 10, y = 0 } },
        speed = 100,
        arrivalDelay = 0,
    })
    Context.declinedCustomer:update(1, { x = 500, y = 500 })
    Context.check("customer_decline_review", Context.declinedCustomer:beginReview())
    Context.check("customer_declines", Context.declinedCustomer:resolve("declined")
        and Context.declinedCustomer.decision == "declined")
    Context.blockedCustomer = Context.context.Customer.new({
        route = { { x = 0, y = 0 }, { x = 100, y = 0 } },
        speed = 100, arrivalDelay = 0,
    })
    Context.blockedCustomer.state, Context.blockedCustomer.visible = "entering", true
    Context.blockedCustomer:update(0.25, { x = 0, y = 0 })
    Context.check("blocked_customer_does_not_walk_in_place",
        Context.blockedCustomer.x == 0 and not Context.blockedCustomer:isMoving()
        and Context.blockedCustomer.animationClock == 0)
    Context.blockedCustomer:update(0.25, { x = 500, y = 500 })
    Context.check("customer_walk_clock_tracks_real_movement",
        Context.blockedCustomer.x > 0 and Context.blockedCustomer:isMoving()
        and Context.blockedCustomer.animationClock == 0.25)
    Context.walkingX, Context.walkingY, Context.walkingRotation = Context.context.Technician.pose({
        status = "entering", animationClock = 0.1,
    })
    Context.serviceX, Context.serviceY, Context.serviceRotation = Context.context.Technician.pose({
        status = "servicing", animationClock = 0.1,
    })
    Context.check("technician_walk_and_service_poses_animate",
        Context.walkingX == 0 and (Context.walkingY ~= 0 or Context.walkingRotation ~= 0)
        and (Context.serviceX ~= 0 or Context.serviceY ~= 0 or Context.serviceRotation ~= 0))
    Context.worldCustomer = Context.context.world.customerSnapshot()
    Context.expectedSeat = Context.context.config.customer.seatSpots[Context.worldCustomer.seatIndex]
    Context.check("customer_world_render_ready", Context.worldCustomer.visible
        and Context.worldCustomer.state == "waiting"
        and Context.worldCustomer.x == Context.expectedSeat.x
        and Context.worldCustomer.y == Context.expectedSeat.y)

    Context.timedCustomer = Context.context.Customer.new({
        route = { { x = 0, y = 0 }, { x = 10, y = 0 } },
        speed = 100,
        arrivalDelay = 0,
        maxWaitSeconds = 0.1,
    })
    Context.timedCustomer:update(1, { x = 500, y = 500 })
    Context.check("customer_wait_timeout", Context.timedCustomer:update(0.11, { x = 500, y = 500 }) == "timed_out"
        and Context.timedCustomer.state == "exiting"
        and Context.timedCustomer.decision == "timed_out")

    Context.economy = Context.context.State.new()
    Context.economy.screen = "world"
    Context.startingMoney = Context.economy.money
    Context.check("shop_buy", Context.context.shop.buyPaper(Context.economy))
    Context.check("shop_buy_balance", Context.economy.money == Context.startingMoney - 25 and Context.economy.inventory.paper == 65)
    Context.economy.inventory.prints = 1
    Context.check("shop_sell", Context.context.shop.sellPrint(Context.economy))
    Context.check("shop_sell_balance", Context.economy.money == Context.startingMoney - 13 and Context.economy.inventory.prints == 0)

    Context.calendarState = Context.context.State.new()
    Context.calendarState.money = 2000
    Context.calendarChanged, Context.invoice = Context.context.businessCalendar.update(Context.calendarState,
        31 * Context.context.config.businessCalendar.secondsPerDay)
    Context.check("calendar_five_minute_days_and_month_rollover", Context.calendarChanged and Context.invoice
        and Context.calendarState.calendar.year == 2026 and Context.calendarState.calendar.month == 2
        and Context.calendarState.calendar.day == 1 and Context.calendarState.calendar.totalDays == 31
        and Context.context.businessCalendar.weekNumber(Context.calendarState) == 5
        and Context.context.businessCalendar.daysInMonth(2028, 2) == 29)
    Context.check("calendar_posts_flat_monthly_bills", Context.invoice.total == 3950
        and Context.invoice.charges[1].amount == 3500 and Context.invoice.charges[2].amount == 240
        and Context.invoice.charges[3].amount == 85 and Context.invoice.charges[4].amount == 125
        and Context.calendarState.bills.balance == 3950)
    Context.check("calendar_rent_increase_requires_sufficient_cash",
        not Context.context.businessCalendar.pay(Context.calendarState)
        and Context.calendarState.money == 2000 and Context.calendarState.bills.balance == 3950)
    Context.calendarState.money = 5000
    Context.paidBills, Context.paidAmount = Context.context.businessCalendar.pay(Context.calendarState)
    Context.check("calendar_monthly_bills_require_payment", Context.paidBills and Context.paidAmount == 3950
        and Context.calendarState.money == 1050 and Context.calendarState.bills.balance == 0
        and Context.calendarState.bills.ledger[1].status == "paid")
    Context.calendarEvents = Context.context.businessCalendar.events(Context.calendarState)
    Context.check("calendar_automatically_lists_bill_due_dates", Context.calendarEvents[1]
        and Context.calendarEvents[1].title == "Rent and bills due")

    Context.weekendState = Context.context.State.new()
    Context.context.businessCalendar.update(Context.weekendState,
        2 * Context.context.config.businessCalendar.secondsPerDay)
    Context.weekendVisitor = Context.context.Customer.new({
        route = { { x = 0, y = 0 }, { x = 10, y = 0 } }, arrivalDelay = 0,
    })
    Context.weekendVisitor:update(30, { x = 500, y = 500 },
        Context.context.businessCalendar.isWeekend(Context.weekendState))
    Context.check("weekend_pauses_client_and_salesman_arrivals",
        Context.context.businessCalendar.isWeekend(Context.weekendState)
        and Context.weekendState.calendar.weekday == 6
        and Context.weekendVisitor.state == "scheduled" and Context.weekendVisitor.timer == 0)
    Context.context.businessCalendar.update(Context.weekendState,
        2 * Context.context.config.businessCalendar.secondsPerDay)
    Context.weekendVisitor:update(0.1, { x = 500, y = 500 },
        Context.context.businessCalendar.isWeekend(Context.weekendState))
    Context.check("monday_resumes_visitor_arrivals", not Context.context.businessCalendar.isWeekend(Context.weekendState)
        and Context.weekendState.calendar.weekday == 1 and Context.weekendVisitor.visible)

    do
    local walkInEstimateState = Context.context.State.new()
    local walkInEstimate = Context.context.jobService.createNextOffer(walkInEstimateState, 100)
    local detailsRequested = Context.context.jobService.requestEstimateDetails(
        walkInEstimateState, walkInEstimate, 101)
    Context.check("walk_in_requests_email_details_without_accepting_job", detailsRequested
        and #walkInEstimateState.jobs.active == 0
        and #walkInEstimateState.clientEmails.pending == 1
        and walkInEstimateState.nextJobId == 2)
    local walkInCalendar = Context.context.businessCalendar.events(walkInEstimateState)
    local hiddenReply = true
    for _, event in ipairs(walkInCalendar) do
        if tostring(event.title):find("Incoming email", 1, true) then hiddenReply = false end
    end
    Context.check("walk_in_email_arrival_is_hidden_from_calendar", hiddenReply)
    Context.context.businessCalendar.update(walkInEstimateState,
        7 / 24 * Context.context.config.businessCalendar.secondsPerDay)
    Context.check("walk_in_written_details_arrive_after_delay",
        Context.context.jobService.updateClientEmails(walkInEstimateState)
        and #walkInEstimateState.clientEmails.inbox == 1)
    local walkInRequest = walkInEstimateState.clientEmails.inbox[1]
    local reminderLimit = walkInRequest.followupLimit
    for _ = 1, reminderLimit do
        Context.context.businessCalendar.update(walkInEstimateState,
            Context.context.config.businessCalendar.secondsPerDay)
        Context.context.jobService.updateClientEmails(walkInEstimateState)
    end
    local remindersSent = walkInRequest.followupCount
    Context.context.businessCalendar.update(walkInEstimateState,
        Context.context.config.businessCalendar.secondsPerDay)
    Context.context.jobService.updateClientEmails(walkInEstimateState)
    Context.check("unanswered_estimate_request_stops_after_one_or_two_followups",
        (reminderLimit == 1 or reminderLimit == 2)
        and remindersSent == reminderLimit
        and walkInRequest.followupCount == reminderLimit
        and walkInRequest.nextFollowupAtHours == nil)
    end

    do
    local emailState = Context.context.State.new()
    local priorClientJob = Context.context.jobs.createOffer({
        id = "PRIOR-CLIENT-JOB", company = "Returning Client Co.",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 }, packaging = "flat",
    })
    Context.check("email_requires_completed_client_relationship",
        not Context.context.jobService.scheduleRepeatEmail(emailState, priorClientJob))
    Context.context.jobs.accept(priorClientJob)
    priorClientJob.status = "completed"
    Context.check("completed_client_schedules_followup_email",
        Context.context.jobService.scheduleRepeatEmail(emailState, priorClientJob)
        and #emailState.clientEmails.pending == 1 and #emailState.clientEmails.inbox == 0)
    Context.context.businessCalendar.update(emailState,
        47 / 24 * Context.context.config.businessCalendar.secondsPerDay)
    Context.check("repeat_client_email_observes_delay", not Context.context.jobService.updateClientEmails(emailState)
        and #emailState.clientEmails.inbox == 0)
    Context.context.businessCalendar.update(emailState,
        1 / 24 * Context.context.config.businessCalendar.secondsPerDay + 0.01)
    Context.check("repeat_client_email_arrives", Context.context.jobService.updateClientEmails(emailState)
        and #emailState.clientEmails.pending == 0 and #emailState.clientEmails.inbox == 1
        and emailState.clientEmails.inbox[1].sender == "Returning Client Co."
        and emailState.clientEmails.inbox[1].job.requestChannel == "email")
    local normalSequenceBeforeEmail = emailState.nextJobId
    Context.context.computerScreen.enter(emailState)
    Context.selectComputerTab(Context.context.computerScreen, emailState, "estimating")
    local emailAcceptX, emailAcceptY = Context.context.computerScreen.emailButtonCenter("accept")
    local emailAccepted = Context.context.computerScreen.mousepressed(emailState, emailAcceptX, emailAcceptY, 1)
    Context.check("computer_sends_repeat_client_estimate_without_instant_decision", emailAccepted
        and emailAccepted.action == "estimate_sent" and #emailState.jobs.active == 0
        and emailState.nextJobId == normalSequenceBeforeEmail
        and #emailState.clientEmails.archive == 1
        and emailState.clientEmails.archive[1].response == "estimate_sent"
        and emailState.clientEmails.pending[1].estimateReply == true)
    priorClientJob.status = "completed"
    Context.check("second_completed_job_schedules_email",
        Context.context.jobService.scheduleRepeatEmail(emailState, priorClientJob))
    Context.context.businessCalendar.update(emailState,
        3 * Context.context.config.businessCalendar.secondsPerDay + 0.01)
    Context.context.jobService.updateClientEmails(emailState)
    Context.check("client_estimate_reply_arrives_after_a_delay",
        #emailState.jobs.active == 1
        and emailState.jobs.active[1].company == "Returning Client Co."
        and emailState.jobs.active[1].delivery.status == "pending_arrival")
    local accidentalSecondTap = Context.context.computerScreen.mousepressed(
        emailState, emailAcceptX, emailAcceptY, 1)
    Context.check("android_repeat_tap_cannot_reply_to_the_next_email",
        accidentalSecondTap == nil and #emailState.clientEmails.inbox == 2
        and #emailState.clientEmails.archive == 1)
    Context.context.computerScreen.enter(emailState)
    Context.selectComputerTab(Context.context.computerScreen, emailState, "estimating")
    local emailDeclineX, emailDeclineY = Context.context.computerScreen.emailButtonCenter("decline")
    local emailDeclined = Context.context.computerScreen.mousepressed(emailState, emailDeclineX, emailDeclineY, 1)
    Context.check("computer_declines_repeat_client_email", emailDeclined
        and emailDeclined.action == "email_declined" and #emailState.jobs.declined == 1
        and emailState.jobs.declined[1].requestChannel == "email"
        and emailState.nextJobId == normalSequenceBeforeEmail
        and #emailState.clientEmails.archive == 2)
    local quoteProbe = Context.context.jobService.createNextOffer(emailState, os.time())
    local baseTerms = Context.context.jobService.quoteTerms(emailState, quoteProbe, quoteProbe.quote.totalPrice)
    local highTerms = Context.context.jobService.quoteTerms(emailState, quoteProbe,
        math.floor(quoteProbe.quote.totalPrice * 1.30))
    Context.check("client_quote_probability_uses_price_urgency_and_relationship",
        baseTerms.acceptanceChance == 1
        and highTerms.acceptanceChance < baseTerms.acceptanceChance
        and type(highTerms.urgency) == "string"
        and type(highTerms.relationshipJobs) == "number")
    local shortPromotion = Context.context.jobService.promotionTerms(emailState, "Hi")
    local longPromotion = Context.context.jobService.promotionTerms(emailState, string.rep("x", 200))
    Context.check("promotion_message_length_increases_new_job_chance",
        longPromotion.messageLength == 200
        and longPromotion.responseChance > shortPromotion.responseChance)
    priorClientJob.status = "completed"
    local promotionMessage = string.rep("x", 240)
    local promotionSent, promotion = Context.context.jobService.sendPromotion(
        emailState, priorClientJob, promotionMessage)
    Context.check("player_can_send_personalized_ten_percent_promotion", promotionSent
        and promotion.discountPercent == 10
        and promotion.customMessage == promotionMessage
        and promotion.messageLength == 240 and promotion.responseChance > 0.70
        and promotion.responseOutcome == "new_job"
        and #emailState.clientEmails.sentPromotions == 1
        and emailState.clientEmails.pending[1].discountedTotal
            == emailState.clientEmails.pending[1].job.quote.totalPrice
        and emailState.clientEmails.pending[1].body:find("discounted total", 1, true))
    local duplicatePromotion = Context.context.jobService.sendPromotion(
        emailState, priorClientJob, "A duplicate offer should not send.")
    Context.check("completed_job_ten_percent_promotion_is_single_use",
        not duplicatePromotion and #emailState.clientEmails.sentPromotions == 1)
    local starterState, premiumState = Context.context.State.new(), Context.context.State.new()
    premiumState.reputation.score, premiumState.nextJobId = 80, 3
    local starterOffer = Context.context.jobService.createNextOffer(starterState, 1)
    local premiumOffer = Context.context.jobService.createNextOffer(premiumState, 2)
    Context.check("reputation_unlocks_larger_better_paying_demanding_clients",
        starterOffer.quote.totalSheets == 500 and starterOffer.clientTemperament == "cautious"
        and premiumOffer.quote.totalPrice > starterOffer.quote.totalPrice
        and premiumOffer.clientTemperament == "demanding")
    -- The real-world machine prices are now above the old smoke fixture's
    -- cash, so fund this calendar listing check explicitly.
    emailState.money = 50000
    local productOrdered, productOrder = Context.context.procurement.buyRetail(emailState, 1, 1)
    local machineOrdered, machineOrder = Context.context.machineFleet.orderOnline(emailState, 1)
    local scheduledEvents = Context.context.businessCalendar.events(emailState)
    local eventIds = {}
    for _, event in ipairs(scheduledEvents) do eventIds[event.id] = true end
    local productShipment = Context.context.procurement.orderById(emailState, productOrder.shipmentId)
    local productEventDay = math.floor(productShipment.delivery.expectedAtHours / 24)
    Context.check("calendar_auto_adds_jobs_products_emails_and_machine_arrivals",
        productOrdered and machineOrdered
        and eventIds[productShipment.id .. ":expected:" .. tostring(productEventDay)]
        and eventIds[machineOrder.id .. ":expected:" .. tostring(emailState.calendar.totalDays)]
        and #scheduledEvents >= 4)
    end
end

return Component
