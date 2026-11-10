local SaveSchema = require("src.save_schema")
local State = require("src.state")
local WorkPhone = require("src.work_phone")
local BusinessCalendar = require("src.business_calendar")
local Inbox = require("src.inbox")

local Test = {}
local function openShop()
    local state=State.new();state.calendar.elapsed=BusinessCalendar.secondsPerDay(state)*9/24
    return state
end

local function call(state, spec)
    local queued, result = WorkPhone.queueCall(state, spec)
    assert(queued, result)
    return result
end

function Test.run(context, check)
    local orderState = openShop()
    call(orderState, {
        kind = "customer_order", caller = "Maple Street Books", role = "CUSTOMER",
        subject = "NEW JOB ORDER", message = "We would like to place a print order.",
    })
    check("work_phone_customer_light_and_ring_animation",
        WorkPhone.lightIndex(orderState) == 2
        and WorkPhone.spriteFrame(orderState, 0) == 2
        and WorkPhone.spriteFrame(orderState, 0.21) == 6)
    local answered = WorkPhone.answer(orderState)
    local completed, response = WorkPhone.respond(orderState)
    check("work_phone_customer_order_enters_written_estimate_email_flow",
        answered and completed and orderState.workPhone.incoming == nil
        and #orderState.workPhone.history == 1
        and #orderState.clientEmails.pending == 1
        and response:find("written specifications", 1, true) ~= nil)

    local statusState = openShop()
    local statusJob = {
        id = "JOB-0099", company = "Blue Ridge Packaging", status = "in_production",
        details = { dueDate = "Friday" },
        pallets = {{ id = "JOB-0099-P1", status = "raw", location = "warehouse" }},
    }
    statusJob.status = "awaiting_delivery"
    statusJob.pallets[1].location = "awaiting_delivery"
    statusState.jobs.active = { statusJob }
    local earlyCall, earlyReason = WorkPhone.queueCall(statusState, {
        kind = "customer_status", caller = "Blue Ridge Packaging", role = "CUSTOMER",
        subject = "CURRENT JOB QUESTION", message = "Where is our job?", jobId = "JOB-0099",
    })
    check("work_phone_customer_status_waits_until_job_arrives_at_warehouse",
        not earlyCall and earlyReason:find("after their job arrives at the warehouse", 1, true) ~= nil
        and statusState.workPhone.incoming == nil)
    statusJob.status = "in_production"
    statusJob.pallets[1].location = "warehouse"
    call(statusState, {
        kind = "customer_status", caller = "Blue Ridge Packaging", role = "CUSTOMER",
        subject = "CURRENT JOB QUESTION", message = "Where is our job?", jobId = "JOB-0099",
    })
    WorkPhone.answer(statusState)
    local updated, statusResponse = WorkPhone.respond(statusState)
    check("work_phone_urgent_customer_gets_location_and_eta",
        updated and WorkPhone.lightIndex(statusState) == 1
        and statusResponse:find("warehouse staging", 1, true) ~= nil
        and statusResponse:find("production hour", 1, true) ~= nil)

    local serviceState = openShop()
    serviceState.money = 1000
    call(serviceState, {
        kind = "service_order", caller = "Otis Wrench", role = "MACHINE SERVICE SUPPLIER",
        subject = "SERVICE SUPPLY CHECK-IN", message = "Would you like a maintenance kit?",
        categoryIndex = 4, itemIndex = 1,
    })
    check("work_phone_supplier_light_is_amber", WorkPhone.lightIndex(serviceState) == 3)
    WorkPhone.answer(serviceState)
    local reviewed, review = WorkPhone.respond(serviceState)
    local ordered = WorkPhone.respond(serviceState)
    local purchase = serviceState.procurement.orders[1]
    local receipt = serviceState.clientEmails.inbox[#serviceState.clientEmails.inbox]
    check("work_phone_service_person_places_order_and_sends_confirmation",
        reviewed and review:find("Confirm below", 1, true) ~= nil
        and ordered and purchase and purchase.channel == "salesman"
        and receipt and receipt.noticeKind == "salesman_confirmation"
        and receipt.body:find("Thanks so much", 1, true) ~= nil)

    local screenState = openShop()
    call(screenState, {
        kind = "supplier_status", caller = "CritterNet Paper Depot",
        role = "SUPPLIER / SERVICE", subject = "DELIVERY UPDATE",
        message = "Calling with your delivery update.", orderId = "PO-4040",
    })
    context.workPhoneScreen.enter(screenState)
    local x, y = context.workPhoneScreen.buttonCenter("action")
    local screenAnswer = context.workPhoneScreen.mousepressed(screenState, x, y, 1)
    local screenUpdate = context.workPhoneScreen.mousepressed(screenState, x, y, 1)
    check("work_phone_screen_answers_then_handles_call",
        screenAnswer and screenAnswer.action == "answered"
        and screenUpdate and screenUpdate.action == "call_completed")

    local weekendState = State.new()
    local weekendDate = BusinessCalendar.ensure(weekendState)
    weekendDate.year, weekendDate.month, weekendDate.day = 2026, 1, 2
    weekendDate.weekday, weekendDate.totalDays, weekendDate.elapsed = 5, 1, BusinessCalendar.secondsPerDay(weekendState)*9/24
    local fridayCall = call(weekendState, {
        kind = "customer_order", caller = "Friday Client", role = "CUSTOMER",
        subject = "NEW JOB ORDER", message = "Please quote a job.",
    })
    weekendDate.day, weekendDate.weekday, weekendDate.totalDays = 3, 6, 2
    local hiddenOnWeekend = WorkPhone.ensure(weekendState)
    local queuedWeekendCall = WorkPhone.queueCall(weekendState, {
        kind = "customer_order", caller = "Saturday Client", role = "CUSTOMER",
        subject = "NEW JOB ORDER", message = "Please quote a job.",
    })
    check("work_phone_client_calls_wait_until_monday",
        hiddenOnWeekend.incoming == nil and #hiddenOnWeekend.deferredCalls == 2
        and hiddenOnWeekend.deferredCalls[1].id == fridayCall.id and queuedWeekendCall)
    local weekendEmailState = State.new()
    local weekendEmailDate = BusinessCalendar.ensure(weekendEmailState)
    weekendEmailDate.day, weekendEmailDate.weekday, weekendEmailDate.totalDays = 3, 6, 2
    weekendEmailState.clientEmails.pending[1] = {
        id = "EMAIL-WEEKEND", sender = "Weekend Client", subject = "New job details",
        body = "Please review the attached job.", readyAtHours = 0, sourceJobId = "JOB-WEEKEND",
    }
    Inbox.addNotice(weekendEmailState, {
        id = "CASE-WEEKEND", sender = "Weekend Client", subject = "Customer follow-up",
        body = "Please review our follow-up.", noticeKind = "customer_case",
        sourceJobId = "JOB-WEEKEND",
    })
    local weekendEmailDelivered = context.jobService.updateClientEmails(weekendEmailState)
    check("client_emails_and_followups_are_held_over_weekend",
        not weekendEmailDelivered and #weekendEmailState.clientEmails.inbox == 0
        and #weekendEmailState.clientEmails.pending == 2)
    weekendDate.day, weekendDate.weekday, weekendDate.totalDays = 5, 1, 4
    local mondayCallDelivered = WorkPhone.update(weekendState, 0)
    check("deferred_client_call_arrives_on_monday",
        mondayCallDelivered and weekendState.workPhone.incoming
        and weekendState.workPhone.incoming.id == fridayCall.id
        and weekendState.workPhone.incoming.receivedAtHours == BusinessCalendar.absoluteHours(weekendState))
    weekendEmailDate.day, weekendEmailDate.weekday, weekendEmailDate.totalDays = 5, 1, 4
    weekendEmailDate.elapsed=BusinessCalendar.secondsPerDay(weekendEmailState)*9/24
    local mondayEmailDelivered = context.jobService.updateClientEmails(weekendEmailState)
    check("deferred_client_emails_arrive_on_monday",
        mondayEmailDelivered and #weekendEmailState.clientEmails.pending == 0
        and #weekendEmailState.clientEmails.inbox == 2)

    check("work_phone_state_saves_call_history",
        SaveSchema.validState(SaveSchema.snapshot(serviceState))
        and SaveSchema.validState(SaveSchema.snapshot(weekendState)))
end

return Test
