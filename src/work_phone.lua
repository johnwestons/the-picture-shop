local BusinessCalendar = require("src.business_calendar")
local JobService = require("src.job_service")
local Procurement = require("src.procurement")
local StatusLabels = require("src.status_labels")

local WorkPhone = {}

local CUSTOMER_NAMES = {
    "Blue Ridge Packaging",
    "Maple Street Books",
    "Harbor Pizza Club",
    "Juniper Trail Outfitters",
    "Moonlight Photo Lab",
}

local VALID_KINDS = {
    customer_order = true,
    customer_status = true,
    supplier_status = true,
    service_order = true,
    construction_notice = true,
}

local LIGHTS = {
    idle = 1,
    customer_order = 2,
    supplier_status = 3,
    service_order = 3,
    construction_notice = 3,
    customer_status = 4,
}

local LOCATION_LABELS = {
    awaiting_delivery = "waiting for customer stock",
    receiving_lane = "at the loading dock",
    warehouse = "in warehouse staging",
    at_cutter = "at the paper cutter",
    cutter_output = "beside the paper cutter",
    at_press = "on the Windmill press",
    press_output = "drying beside the press",
    at_wrapper = "at the skid wrapper",
    wrapper_output = "beside the skid wrapper",
    outbound_truck = "on the customer's pickup truck",
    none = "off the production floor",
}

local function positiveInteger(value, fallback)
    value = math.floor(tonumber(value) or fallback or 1)
    return math.max(1, value)
end

function WorkPhone.defaultState(now)
    return {
        nextCallId = 1,
        nextCallAtHours = math.max(0, tonumber(now) or 0) + 6,
        incoming = nil,
        history = {},
    }
end

function WorkPhone.ensure(state)
    state.workPhone = type(state.workPhone) == "table" and state.workPhone
        or WorkPhone.defaultState(BusinessCalendar.absoluteHours(state))
    local phone = state.workPhone
    phone.nextCallId = positiveInteger(phone.nextCallId, 1)
    phone.nextCallAtHours = math.max(0, tonumber(phone.nextCallAtHours)
        or BusinessCalendar.absoluteHours(state) + 6)
    phone.history = type(phone.history) == "table" and phone.history or {}
    if type(phone.incoming) ~= "table" or not VALID_KINDS[phone.incoming.kind] then
        phone.incoming = nil
    end
    return phone
end

local function findActiveJob(state, jobId)
    for _, job in ipairs(state.jobs and state.jobs.active or {}) do
        if job.id == jobId then return job end
    end
end

local function findPurchaseOrder(state, orderId)
    for _, order in ipairs(state.procurement and state.procurement.orders or {}) do
        if order.id == orderId then return order end
    end
end

local function firstPendingPurchase(state, serial)
    local pending = {}
    for _, order in ipairs(state.procurement and state.procurement.orders or {}) do
        if order.status ~= "received" and order.status ~= "completed" then
            pending[#pending + 1] = order
        end
    end
    if #pending == 0 then return nil end
    return pending[(serial - 1) % #pending + 1]
end

local function callSpec(state, serial)
    local active = state.jobs and state.jobs.active or {}
    local purchase = firstPendingPurchase(state, serial)
    if #active > 0 and serial % 3 == 0 then
        local job = active[(serial - 1) % #active + 1]
        return {
            kind = "customer_status",
            caller = job.company,
            role = "CUSTOMER",
            subject = "CURRENT JOB QUESTION",
            message = string.format(
                "Hello, this is %s. Could you tell us where job %s is right now and when you expect it to be finished?",
                job.company, job.id),
            jobId = job.id,
        }
    end
    if purchase and serial % 4 == 0 then
        return {
            kind = "supplier_status",
            caller = purchase.vendor,
            role = "SUPPLIER / SERVICE",
            subject = "ORDER DELIVERY UPDATE",
            message = string.format(
                "We're calling about %s. Would you like the current delivery status for your %s order?",
                purchase.id, purchase.productName),
            orderId = purchase.id,
        }
    end
    if serial % 2 == 0 then
        local category = Procurement.category(4)
        return {
            kind = "service_order",
            caller = category.salesman,
            role = "MACHINE SERVICE SUPPLIER",
            subject = "SERVICE SUPPLY CHECK-IN",
            message = "I'm checking in from the service shop. Would you like me to place a bulk machine-maintenance kit order for dock delivery?",
            categoryIndex = 4,
            itemIndex = 1,
        }
    end
    local caller = CUSTOMER_NAMES[(serial - 1) % #CUSTOMER_NAMES + 1]
    return {
        kind = "customer_order",
        caller = caller,
        role = "CUSTOMER",
        subject = "NEW JOB ORDER",
        message = string.format(
            "Hi, this is %s. We have a new print-shop job to place. Can you take the order and have us send the written specifications?",
            caller),
    }
end

local function validHours(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function validConstructionSpec(spec)
    return type(spec.projectId) == "string" and #spec.projectId <= 64
        and spec.projectId:match("^WUP%-%d+$") ~= nil
        and (spec.bayId == "front_left" or spec.bayId == "front_right")
        and (spec.optionId == "floor" or spec.optionId == "storage" or spec.optionId == "breakroom")
end

function WorkPhone.queueCall(state, spec, nowHours)
    local phone = WorkPhone.ensure(state)
    if phone.incoming then return false, "The work phone is already ringing." end
    spec = type(spec) == "table" and spec or {}
    if not VALID_KINDS[spec.kind] then return false, "That caller type is not supported." end
    if spec.kind == "construction_notice" and not validConstructionSpec(spec) then
        return false, "Choose a valid warehouse construction project."
    end
    if nowHours ~= nil and not validHours(nowHours) then return false, "Invalid call time." end
    local number = phone.nextCallId
    phone.nextCallId = number + 1
    phone.incoming = {
        id = string.format("CALL-%04d", number),
        kind = spec.kind,
        caller = tostring(spec.caller or "Unknown caller"),
        role = tostring(spec.role or "CALLER"),
        subject = tostring(spec.subject or "WORK PHONE CALL"),
        message = tostring(spec.message or "Hello, I'm calling the Picture Shop."),
        jobId = spec.jobId,
        orderId = spec.orderId,
        projectId = spec.projectId,
        bayId = spec.bayId,
        optionId = spec.optionId,
        categoryIndex = spec.categoryIndex,
        itemIndex = spec.itemIndex,
        receivedAtHours = nowHours or BusinessCalendar.absoluteHours(state),
        answered = false,
    }
    state.message = phone.incoming.caller .. " is calling the work phone."
    return true, phone.incoming
end

function WorkPhone.update(state)
    local phone = WorkPhone.ensure(state)
    if phone.incoming or BusinessCalendar.isWeekend(state) then return false end
    local now = BusinessCalendar.absoluteHours(state)
    if now + 0.000001 < phone.nextCallAtHours then return false end
    local spec = callSpec(state, phone.nextCallId)
    return WorkPhone.queueCall(state, spec)
end

function WorkPhone.answer(state)
    local call = WorkPhone.ensure(state).incoming
    if not call then return false, "No one is calling right now." end
    call.answered = true
    return true, call
end

local function uniqueLocations(job)
    local result, seen = {}, {}
    for _, pallet in ipairs(job.pallets or {}) do
        local location = LOCATION_LABELS[pallet.location] or tostring(pallet.location or "in production")
        if not seen[location] then seen[location] = true; result[#result + 1] = location end
    end
    return #result > 0 and table.concat(result, ", ") or "in the job queue"
end

local function remainingPallets(job)
    local remaining = 0
    for _, pallet in ipairs(job.pallets or {}) do
        if pallet.status ~= "wrapped" and pallet.status ~= "picked_up"
            and pallet.status ~= "spoiled_discarded"
        then remaining = remaining + 1 end
    end
    return remaining
end

function WorkPhone.jobUpdate(state, jobId)
    local job = findActiveJob(state, jobId)
    if not job then
        for _, completed in ipairs(state.jobs and state.jobs.completed or {}) do
            if completed.id == jobId then
                return string.format("%s is complete and has been paid and picked up.", jobId)
            end
        end
        return "That job is no longer in the active production list."
    end
    local status = StatusLabels.get(job.status)
    local location = uniqueLocations(job)
    local timing
    if job.status == "awaiting_delivery" and job.delivery and job.delivery.readyAtHours then
        local hours = math.max(0, math.ceil(job.delivery.readyAtHours
            - BusinessCalendar.absoluteHours(state)))
        timing = hours == 0 and "Its stock is due now."
            or string.format("Its stock is expected in about %d game hour%s.", hours, hours == 1 and "" or "s")
    elseif job.status == "pickup_ready" or job.status == "pickup_in_progress" then
        timing = "Production is finished; it is ready for customer pickup."
    else
        local pallets = remainingPallets(job)
        local hours = math.max(2, pallets * (job.press and 10 or 6))
        timing = string.format("The shop estimate is about %d more production hour%s (%s).",
            hours, hours == 1 and "" or "s", job.details and job.details.dueDate or "standard turnaround")
    end
    return string.format("%s is %s. The material is %s. %s", job.id, status:lower(), location, timing)
end

local function purchaseUpdate(state, orderId)
    local order = findPurchaseOrder(state, orderId)
    if not order then return "That supply order is not in the current order list." end
    local delivery = order.delivery or {}
    local status = StatusLabels.get(delivery.status or order.status)
    local timing = ""
    if delivery.expectedAtHours then
        local hours = math.max(0, math.ceil(delivery.expectedAtHours
            - BusinessCalendar.absoluteHours(state)))
        timing = hours == 0 and " It is due at the loading dock now."
            or string.format(" It is expected in about %d game hour%s.", hours, hours == 1 and "" or "s")
    end
    return string.format("%s for %s is %s.%s", order.id, order.productName, status:lower(), timing)
end

local function archiveCurrent(state, outcome, response, nowHours)
    local phone = WorkPhone.ensure(state)
    local call = phone.incoming
    if not call then return nil end
    call.outcome = outcome
    call.response = response
    call.endedAtHours = math.max(call.receivedAtHours or 0,
        validHours(nowHours) and nowHours or BusinessCalendar.absoluteHours(state))
    phone.history[#phone.history + 1] = call
    while #phone.history > 12 do table.remove(phone.history, 1) end
    phone.incoming = nil
    phone.nextCallAtHours = call.endedAtHours + 10 + (phone.nextCallId % 4) * 4
    return call
end

function WorkPhone.respond(state)
    local phone = WorkPhone.ensure(state)
    local call = phone.incoming
    if not call then return false, "No call is active." end
    if not call.answered then return false, "Answer the phone before responding." end
    local response
    if call.kind == "customer_order" then
        local offer, errors = JobService.createNextOffer(state, os.time())
        if not offer then return false, table.concat(errors or { "Could not prepare the order." }, "; ") end
        offer.company = call.caller
        offer.requestChannel = "phone"
        local requested, emailOrError = JobService.requestEstimateDetails(state, offer, os.time())
        if not requested then return false, tostring(emailOrError) end
        response = string.format(
            "Order %s was taken by phone. %s will email the written specifications for estimating.",
            offer.id, call.caller)
        call.jobId = offer.id
    elseif call.kind == "customer_status" then
        response = WorkPhone.jobUpdate(state, call.jobId)
    elseif call.kind == "supplier_status" then
        response = purchaseUpdate(state, call.orderId)
    elseif call.kind == "construction_notice" then
        response = "Construction appointment acknowledged. The scheduled visit remains active; keep the bay approach clear."
    else
        local purchased, orderOrError = Procurement.buy(state,
            call.categoryIndex or 4, call.itemIndex or 1, "salesman")
        if not purchased then return false, tostring(orderOrError) end
        call.orderId = orderOrError.id
        response = string.format(
            "%s placed by phone for $%d. The salesperson will send confirmation and arrange dock delivery.",
            orderOrError.productName, orderOrError.price)
    end
    archiveCurrent(state, call.kind == "construction_notice" and "acknowledged" or "completed", response)
    state.message = response
    return true, response
end

function WorkPhone.dismiss(state)
    local call = WorkPhone.ensure(state).incoming
    if not call then return false, "No call is active." end
    local response = call.kind == "construction_notice"
        and "Construction notice saved. The appointment remains scheduled."
        or (call.answered and "Call ended without taking further action."
            or "Missed call from " .. call.caller .. ".")
    archiveCurrent(state, call.answered and "ended" or "missed", response)
    state.message = response
    return true, response
end

-- The construction adapter alone requests a timed missed notice. Other caller
-- kinds are never silently dismissed to make room for a building appointment.
function WorkPhone.missConstructionNotice(state, callId, nowHours)
    if not validHours(nowHours) then return false, "Invalid call time." end
    local call = WorkPhone.ensure(state).incoming
    if not call or call.id ~= callId or call.kind ~= "construction_notice" or call.answered then
        return false, "That unanswered construction notice is no longer active."
    end
    local response = "Missed construction notice saved. The appointment remains scheduled."
    archiveCurrent(state, "missed", response, nowHours)
    state.message = response
    return true, response
end

function WorkPhone.lightIndex(state)
    local call = WorkPhone.ensure(state).incoming
    return call and (LIGHTS[call.kind] or 1) or 1
end

function WorkPhone.spriteFrame(state, clock)
    local phone = WorkPhone.ensure(state)
    local light = WorkPhone.lightIndex(state)
    if not phone.incoming or phone.incoming.answered then return light end
    return light + (math.floor((tonumber(clock) or 0) * 5) % 2) * 4
end

function WorkPhone.actionLabel(state)
    local call = WorkPhone.ensure(state).incoming
    if not call then return "" end
    if call.kind == "customer_order" then return "TAKE ORDER" end
    if call.kind == "customer_status" then return "GIVE JOB UPDATE" end
    if call.kind == "supplier_status" then return "HEAR DELIVERY UPDATE" end
    if call.kind == "construction_notice" then return "ACKNOWLEDGE" end
    return "PLACE SERVICE ORDER"
end

return WorkPhone
