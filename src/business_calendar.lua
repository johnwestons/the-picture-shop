local Config = require("src.config")

local Calendar = {}
local WEEKDAYS = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
local MONTHS = { "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December" }

local function settings()
    return Config.businessCalendar or {}
end

local leapYear, daysInMonth

local function dateFromTotalDay(totalDay)
    totalDay = math.max(0, math.floor(tonumber(totalDay) or 0))
    local year, month, remaining = 2026, 1, totalDay
    while true do
        local yearDays = leapYear(year) and 366 or 365
        if remaining < yearDays then break end
        remaining, year = remaining - yearDays, year + 1
    end
    while remaining >= daysInMonth(year, month) do
        remaining = remaining - daysInMonth(year, month)
        month = month + 1
    end
    return {
        year = year,
        month = month,
        day = remaining + 1,
        weekday = (3 + totalDay) % 7 + 1,
        totalDays = totalDay,
    }
end

local function totalDayForDate(year, month, day)
    year, month, day = math.floor(year), math.floor(month), math.floor(day)
    if year < 2026 then return nil end
    local total = 0
    for current = 2026, year - 1 do total = total + (leapYear(current) and 366 or 365) end
    for current = 1, month - 1 do total = total + daysInMonth(year, current) end
    return total + day - 1
end

local function expenses()
    return settings().monthlyExpenses or {}
end

leapYear = function(year)
    return year % 400 == 0 or (year % 4 == 0 and year % 100 ~= 0)
end

daysInMonth = function(year, month)
    if month == 2 then return leapYear(year) and 29 or 28 end
    if month == 4 or month == 6 or month == 9 or month == 11 then return 30 end
    return 31
end

function Calendar.defaultCalendar()
    return { year = 2026, month = 1, day = 1, weekday = 4, elapsed = 0, totalDays = 0 }
end

function Calendar.defaultBills()
    return { balance = 0, nextInvoiceId = 1, ledger = {} }
end

function Calendar.ensure(state)
    state.calendar = type(state.calendar) == "table" and state.calendar or Calendar.defaultCalendar()
    local date = state.calendar
    date.year = math.max(1, math.floor(tonumber(date.year) or 2026))
    date.month = math.min(12, math.max(1, math.floor(tonumber(date.month) or 1)))
    date.day = math.min(daysInMonth(date.year, date.month), math.max(1, math.floor(tonumber(date.day) or 1)))
    date.weekday = math.min(7, math.max(1, math.floor(tonumber(date.weekday) or 4)))
    date.elapsed = math.max(0, tonumber(date.elapsed) or 0)
    date.totalDays = math.max(0, math.floor(tonumber(date.totalDays) or 0))

    state.bills = type(state.bills) == "table" and state.bills or Calendar.defaultBills()
    local bills = state.bills
    bills.balance = math.max(0, tonumber(bills.balance) or 0)
    bills.nextInvoiceId = math.max(1, math.floor(tonumber(bills.nextInvoiceId) or 1))
    bills.ledger = type(bills.ledger) == "table" and bills.ledger or {}
    return date, bills
end

function Calendar.valid(date, bills)
    if type(date) ~= "table" or type(bills) ~= "table" then return false end
    if type(date.year) ~= "number" or date.year < 1 or date.year ~= math.floor(date.year)
        or type(date.month) ~= "number" or date.month < 1 or date.month > 12 or date.month ~= math.floor(date.month)
        or type(date.day) ~= "number" or date.day < 1 or date.day > daysInMonth(date.year, date.month)
        or date.day ~= math.floor(date.day)
        or type(date.weekday) ~= "number" or date.weekday < 1 or date.weekday > 7
        or date.weekday ~= math.floor(date.weekday)
        or type(date.elapsed) ~= "number" or date.elapsed < 0
        or type(date.totalDays) ~= "number" or date.totalDays < 0 or date.totalDays ~= math.floor(date.totalDays)
        or type(bills.balance) ~= "number" or bills.balance < 0
        or type(bills.nextInvoiceId) ~= "number" or bills.nextInvoiceId < 1
        or bills.nextInvoiceId ~= math.floor(bills.nextInvoiceId)
        or type(bills.ledger) ~= "table"
    then return false end
    for index, invoice in ipairs(bills.ledger) do
        if index ~= math.floor(index) or type(invoice) ~= "table"
            or type(invoice.id) ~= "string" or type(invoice.total) ~= "number" or invoice.total < 0
            or (invoice.status ~= "unpaid" and invoice.status ~= "paid")
        then return false end
    end
    return true
end

function Calendar.monthlyCharges()
    local configured = expenses()
    local charges = {
        { id = "rent", label = "Warehouse rent", amount = tonumber(configured.rent) or 1200 },
        { id = "power", label = "Power", amount = tonumber(configured.power) or 240 },
        { id = "water", label = "Water", amount = tonumber(configured.water) or 85 },
        { id = "internet", label = "Internet", amount = tonumber(configured.internet) or 125 },
    }
    local total = 0
    for _, charge in ipairs(charges) do total = total + charge.amount end
    return charges, total
end

local function createInvoice(state)
    local date, bills = Calendar.ensure(state)
    local charges, total = Calendar.monthlyCharges()
    local invoice = {
        id = string.format("BILL-%04d", bills.nextInvoiceId),
        year = date.year,
        month = date.month,
        charges = charges,
        total = total,
        status = "unpaid",
        issuedOnDay = date.totalDays,
        dueOnDay = date.totalDays,
    }
    bills.nextInvoiceId = bills.nextInvoiceId + 1
    bills.balance = bills.balance + total
    bills.ledger[#bills.ledger + 1] = invoice
    return invoice
end

local function advanceDay(state)
    local date = Calendar.ensure(state)
    date.day = date.day + 1
    date.weekday = date.weekday % 7 + 1
    date.totalDays = date.totalDays + 1
    local invoice
    if date.day > daysInMonth(date.year, date.month) then
        date.day = 1
        date.month = date.month + 1
        if date.month > 12 then date.month, date.year = 1, date.year + 1 end
        invoice = createInvoice(state)
    end
    require("src.credit").onDay(state)
    return invoice
end

function Calendar.update(state, dt)
    local date = Calendar.ensure(state)
    local secondsPerDay = math.max(1, tonumber(settings().secondsPerDay) or 300)
    date.elapsed = date.elapsed + math.max(0, tonumber(dt) or 0)
    local daysAdvanced, newestInvoice = 0, nil
    while date.elapsed >= secondsPerDay do
        date.elapsed = date.elapsed - secondsPerDay
        newestInvoice = advanceDay(state) or newestInvoice
        daysAdvanced = daysAdvanced + 1
    end
    if newestInvoice then
        state.message = string.format("Monthly bills posted: $%d due. Pay them on the office computer.", state.bills.balance)
    end
    return daysAdvanced > 0, newestInvoice
end

function Calendar.pay(state)
    local date, bills = Calendar.ensure(state)
    if bills.balance <= 0 then return false, "No bills or customer claims are currently due." end
    if (state.money or 0) < bills.balance then
        return false, string.format("Bills and claims total $%d, but only $%d is available.", bills.balance, state.money or 0)
    end
    local amount = bills.balance
    state.money = state.money - amount
    bills.balance = 0
    for _, invoice in ipairs(bills.ledger) do
        if invoice.status == "unpaid" then
            invoice.status = "paid"
            invoice.paidOnDay = date.totalDays
        end
    end
    require("src.credit").recordBillsPaid(state, bills.ledger)
    return true, amount
end

function Calendar.addCharge(state, label, amount, reference)
    local date, bills = Calendar.ensure(state)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    local invoice = {
        id = string.format("CLAIM-%04d", bills.nextInvoiceId),
        year = date.year,
        month = date.month,
        charges = { { id = "customer_stock", label = tostring(label or "Customer stock replacement"), amount = amount } },
        total = amount,
        status = "unpaid",
        issuedOnDay = date.totalDays,
        dueOnDay = date.totalDays,
        reference = reference,
        kind = "spoil_claim",
    }
    bills.nextInvoiceId = bills.nextInvoiceId + 1
    bills.balance = bills.balance + amount
    bills.ledger[#bills.ledger + 1] = invoice
    return invoice
end

function Calendar.dateText(state)
    local date = Calendar.ensure(state)
    return string.format("%s, %s %d, %d  •  Week %d", WEEKDAYS[date.weekday],
        MONTHS[date.month], date.day, date.year, Calendar.weekNumber(state))
end

function Calendar.shortDate(state)
    local date = Calendar.ensure(state)
    return string.format("%s %d, %d  W%d", MONTHS[date.month]:sub(1, 3),
        date.day, date.year, Calendar.weekNumber(state))
end

function Calendar.weekNumber(state)
    local date = Calendar.ensure(state)
    local elapsedDays = date.day - 1
    for month = 1, date.month - 1 do elapsedDays = elapsedDays + daysInMonth(date.year, month) end
    return math.floor(elapsedDays / 7) + 1
end

function Calendar.isWeekend(state)
    local date = Calendar.ensure(state)
    return date.weekday == 6 or date.weekday == 7
end

function Calendar.dayProgress(state)
    local date = Calendar.ensure(state)
    return math.min(1, date.elapsed / math.max(1, tonumber(settings().secondsPerDay) or 300))
end

function Calendar.absoluteHours(state)
    local date = Calendar.ensure(state)
    local secondsPerDay = math.max(1, tonumber(settings().secondsPerDay) or 300)
    return date.totalDays * 24 + date.elapsed / secondsPerDay * 24
end


function Calendar.dateFromTotalDay(totalDay) return dateFromTotalDay(totalDay) end
function Calendar.dateFromHours(hours) return dateFromTotalDay(math.floor(math.max(0, hours or 0) / 24)) end
function Calendar.totalDayForDate(year, month, day) return totalDayForDate(year, month, day) end
function Calendar.monthName(month) return MONTHS[month] end
function Calendar.weekdayName(weekday) return WEEKDAYS[weekday] end

function Calendar.shiftMonth(year, month, amount)
    local absolute = year * 12 + (month - 1) + amount
    return math.floor(absolute / 12), absolute % 12 + 1
end

function Calendar.events(state)
    Calendar.ensure(state)
    local result, seen = {}, {}
    local function add(totalDay, title, kind, detail, id)
        totalDay = tonumber(totalDay)
        if not totalDay then return end
        totalDay = math.max(0, math.floor(totalDay))
        local key = tostring(id or title) .. ":" .. tostring(totalDay)
        if seen[key] then return end
        seen[key] = true
        local date = dateFromTotalDay(totalDay)
        result[#result + 1] = {
            id = key, totalDay = totalDay, year = date.year, month = date.month, day = date.day,
            title = title, kind = kind or "general", detail = detail,
        }
    end
    local function addHours(hours, title, kind, detail, id)
        if type(hours) == "number" then add(math.floor(hours / 24), title, kind, detail, id) end
    end

    for _, job in ipairs((state.jobs and state.jobs.active) or {}) do
        local delivery = job.delivery or {}
        addHours(delivery.acceptedGameHours, "Job accepted: " .. job.id, "job", job.company,
            job.id .. ":accepted")
        addHours(delivery.readyAtHours, "Stock shipment: " .. job.id, "shipment",
            job.company .. " • " .. tostring((delivery.service or {}).label or "delivery"), job.id .. ":stock")
        addHours(delivery.receivedAtHours, "Job stock received: " .. job.id, "received",
            job.company, job.id .. ":received")
        addHours(job.pickupRequestedAtHours, "Customer pickup: " .. job.id, "pickup", job.company,
            job.id .. ":pickup")
    end
    for _, job in ipairs((state.jobs and state.jobs.completed) or {}) do
        addHours(job.completedAtHours, "Job completed: " .. job.id, "job", job.company,
            job.id .. ":complete")
    end
    local procurement = state.procurement or {}
    if type(procurement.shipments) == "table" and #procurement.shipments > 0 then
        for _, shipment in ipairs(procurement.shipments) do
            local delivery = shipment.delivery or {}
            local count = #(shipment.orderIds or {})
            addHours(delivery.expectedAtHours, "Supply truck: " .. shipment.id, "shipment",
                string.format("%d purchase order%s • grouped dock delivery", count, count == 1 and "" or "s"),
                shipment.id .. ":expected")
            addHours(delivery.receivedAtHours, "Supplies received: " .. shipment.id, "received",
                string.format("%d purchase order%s", count, count == 1 and "" or "s"),
                shipment.id .. ":received")
        end
    else
        for _, order in ipairs(procurement.orders or {}) do
            local delivery = order.delivery or {}
            addHours(delivery.expectedAtHours, "Product delivery: " .. order.id, "shipment",
                order.productName, order.id .. ":expected")
            addHours(delivery.receivedAtHours, "Products received: " .. order.id, "received",
                order.productName, order.id .. ":received")
        end
    end
    for _, order in ipairs((state.machines and state.machines.deliveries) or {}) do
        local delivery = order.delivery or {}
        addHours(delivery.expectedAtHours, "Machine arrival: " .. order.machineName, "machine",
            order.id .. " • flatbed delivery", order.id .. ":expected")
        addHours(delivery.receivedAtHours, "Machine received: " .. order.machineName, "received",
            order.id, order.id .. ":received")
    end
    for _, machine in ipairs((state.machines and state.machines.items) or {}) do
        local cutter = machine.maintenance and machine.maintenance.cutter
        if machine.modelId == "polar_115" and cutter and cutter.nextTechnicianDay then
            add(cutter.nextTechnicianDay, "Cutter blade technician", "machine",
                cutter.weeklyTechnician and "Recurring weekly sharpening visit"
                    or "Requested blade-sharpening visit",
                machine.id .. ":technician")
        end
    end
    local emails = state.clientEmails or {}
    -- Pending client messages are intentionally omitted. The player should
    -- discover estimate details, reminders, and decisions only after they
    -- actually arrive, not by reading their hidden delivery time here.
    for _, email in ipairs(emails.inbox or {}) do
        addHours(email.receivedAtHours, "Email received: " .. email.sender, "email", email.subject,
            email.id .. ":received")
    end
    for _, email in ipairs(emails.archive or {}) do
        addHours(email.respondedAtHours, "Email answered: " .. email.sender, "email",
            email.subject, email.id .. ":answered")
    end
    for _, promotion in ipairs(emails.sentPromotions or {}) do
        addHours(promotion.sentAtHours, "10% offer sent: " .. promotion.recipient, "email",
            promotion.customMessage, promotion.id .. ":sent")
    end
    for _, invoice in ipairs((state.bills and state.bills.ledger) or {}) do
        add(invoice.dueOnDay or invoice.issuedOnDay,
            invoice.kind == "spoil_claim" and "Customer stock claim due" or "Rent and bills due", "bill",
            string.format("%s • $%d • %s", invoice.id, invoice.total, invoice.status), invoice.id)
    end
    for _, loan in ipairs((state.credit and state.credit.loans) or {}) do
        if loan.status == "active" or loan.status == "defaulted" then
            local hasDue = (loan.amountDue or 0) > 0
            local overdue = hasDue and (state.calendar.totalDays or 0) > (loan.oldestDueDay or 0)
            local dueDay = hasDue and (state.calendar.totalDays or 0) or loan.nextDueDay
            local amount = (loan.amountDue or 0) + (loan.feesDue or 0)
            add(dueDay,
                overdue and ("Machine payment overdue: " .. loan.machineName)
                    or ("Machine installment due: " .. loan.machineName),
                "credit",
                hasDue and string.format("%s • $%d due", loan.id, amount)
                    or string.format("%s • $%d • %.2f%% APR", loan.id, loan.monthlyPayment,
                        (loan.aprBasisPoints or 0) / 100),
                loan.id .. ":payment")
        end
    end
    local nextYear, nextMonth = Calendar.shiftMonth(state.calendar.year, state.calendar.month, 1)
    add(totalDayForDate(nextYear, nextMonth, 1), "Rent and bills due", "bill",
        "Warehouse rent and monthly utilities", string.format("projected:%04d-%02d", nextYear, nextMonth))

    table.sort(result, function(a, b)
        if a.totalDay == b.totalDay then return a.title < b.title end
        return a.totalDay < b.totalDay
    end)
    return result
end

Calendar.daysInMonth = daysInMonth
return Calendar
