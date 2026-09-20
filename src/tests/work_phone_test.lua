local SaveSchema = require("src.save_schema")
local State = require("src.state")
local WorkPhone = require("src.work_phone")

local Test = {}

local function call(state, spec)
    local queued, result = WorkPhone.queueCall(state, spec)
    assert(queued, result)
    return result
end

function Test.run(context, check)
    local orderState = State.new()
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

    local statusState = State.new()
    statusState.jobs.active = {{
        id = "JOB-0099", company = "Blue Ridge Packaging", status = "in_production",
        details = { dueDate = "Friday" },
        pallets = {{ id = "JOB-0099-P1", status = "raw", location = "warehouse" }},
    }}
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

    local serviceState = State.new()
    serviceState.money = 1000
    call(serviceState, {
        kind = "service_order", caller = "Otis Wrench", role = "MACHINE SERVICE SUPPLIER",
        subject = "SERVICE SUPPLY CHECK-IN", message = "Would you like a maintenance kit?",
        categoryIndex = 4, itemIndex = 1,
    })
    check("work_phone_supplier_light_is_amber", WorkPhone.lightIndex(serviceState) == 3)
    WorkPhone.answer(serviceState)
    local ordered = WorkPhone.respond(serviceState)
    local purchase = serviceState.procurement.orders[1]
    local receipt = serviceState.clientEmails.inbox[#serviceState.clientEmails.inbox]
    check("work_phone_service_person_places_order_and_sends_confirmation",
        ordered and purchase and purchase.channel == "salesman"
        and receipt and receipt.noticeKind == "salesman_confirmation"
        and receipt.body:find("Thanks so much", 1, true) ~= nil)

    local screenState = State.new()
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

    check("work_phone_state_saves_call_history",
        SaveSchema.validState(SaveSchema.snapshot(serviceState)))
end

return Test
