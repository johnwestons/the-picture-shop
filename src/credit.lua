local Calendar = require("src.business_calendar")
local MachineFleet = require("src.machine_fleet")

local Credit = {}

Credit.STARTING_SCORE = 560
Credit.MIN_SCORE = 300
Credit.MAX_SCORE = 850
Credit.MAX_OPEN_LOANS = 3

local TIERS = {
    { minimum = 740, label = "Excellent", apr = 7.49, downPercent = 5, termMonths = 72 },
    { minimum = 680, label = "Good", apr = 9.99, downPercent = 10, termMonths = 60 },
    { minimum = 620, label = "Fair", apr = 12.49, downPercent = 15, termMonths = 48 },
    { minimum = 580, label = "Fair", apr = 15.49, downPercent = 20, termMonths = 48 },
    { minimum = 300, label = "Poor", apr = 18.99, downPercent = 25, termMonths = 36 },
}

local LATE_SCORE_HITS = { 30, 45, 65, 80 }

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and (maximum == nil or value <= maximum)
end

local function nonnegative(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

function Credit.defaultState()
    return { score = Credit.STARTING_SCORE, nextLoanId = 1, loans = {}, history = {} }
end

local function loanValid(loan)
    return type(loan) == "table"
        and type(loan.id) == "string" and loan.id:match("^CR%-%d+$") ~= nil
        and type(loan.requestId) == "string" and #loan.requestId > 0 and #loan.requestId <= 64
        and (loan.channel == nil or loan.channel == "online" or loan.channel == "dealer")
        and type(loan.machineId) == "string" and loan.machineId:match("^MCH%-%d+$") ~= nil
        and MachineFleet.definition(loan.modelId) ~= nil
        and type(loan.machineName) == "string" and #loan.machineName <= 120
        and integer(loan.purchasePrice, 1, 100000000)
        and integer(loan.downPayment, 1, loan.purchasePrice)
        and integer(loan.principal, 1, loan.purchasePrice)
        and loan.principal == loan.purchasePrice - loan.downPayment
        and nonnegative(loan.balance) and loan.balance <= loan.principal * 20
        and integer(loan.aprBasisPoints, 1, 5000)
        and integer(loan.termMonths, 1, 120)
        and integer(loan.monthlyPayment, 1, 10000000)
        and integer(loan.amountDue, 0, 100000000)
        and integer(loan.installmentsDue, 0, 1200)
        and integer(loan.accruedInterest, 0, 100000000)
        and integer(loan.feesDue, 0, 100000000)
        and integer(loan.scheduledCount, 0, 1200)
        and integer(loan.nextDueDay, 0)
        and integer(loan.openedAtDay, 0)
        and (loan.oldestDueDay == nil or integer(loan.oldestDueDay, 0))
        and integer(loan.delinquencyLevel, 0, 4)
        and (loan.status == "active" or loan.status == "paid" or loan.status == "defaulted")
        and type(loan.lateFeeCharged) == "boolean"
        and type(loan.lienReleased) == "boolean"
end

function Credit.validState(value)
    if type(value) ~= "table" or not integer(value.score, Credit.MIN_SCORE, Credit.MAX_SCORE)
        or not integer(value.nextLoanId, 1, 1000000)
        or type(value.loans) ~= "table" or #value.loans > 100
        or type(value.history) ~= "table" or #value.history > 24
    then return false end
    local ids, requests = {}, {}
    for index, loan in ipairs(value.loans) do
        if index ~= math.floor(index) or not loanValid(loan) or ids[loan.id] or requests[loan.requestId] then
            return false
        end
        ids[loan.id], requests[loan.requestId] = true, true
    end
    for index, entry in ipairs(value.history) do
        if index ~= math.floor(index) or type(entry) ~= "table"
            or not integer(entry.day, 0) or not integer(entry.score, Credit.MIN_SCORE, Credit.MAX_SCORE)
            or not integer(entry.delta, -1000, 1000) or type(entry.reason) ~= "string"
            or #entry.reason > 160
        then return false end
    end
    return true
end

function Credit.normalize(value)
    if value == nil then return Credit.defaultState() end
    if not Credit.validState(value) then return nil end
    return copy(value)
end

function Credit.ensure(state)
    if type(state) ~= "table" then return nil end
    if not Credit.validState(state.credit) then state.credit = Credit.defaultState() end
    return state.credit
end

function Credit.tierFor(score)
    score = math.max(Credit.MIN_SCORE, math.min(Credit.MAX_SCORE, math.floor(tonumber(score) or Credit.STARTING_SCORE)))
    for _, tier in ipairs(TIERS) do
        if score >= tier.minimum then return tier end
    end
    return TIERS[#TIERS]
end

local function round(value)
    return math.floor(value + 0.5)
end

function Credit.monthlyPayment(principal, aprBasisPoints, months)
    principal = math.max(0, tonumber(principal) or 0)
    months = math.max(1, math.floor(tonumber(months) or 1))
    if principal == 0 then return 0 end
    local rate = (tonumber(aprBasisPoints) or 0) / 120000
    if rate <= 0 then return math.ceil(principal / months) end
    return round(principal * rate / (1 - (1 + rate) ^ -months))
end

local function activeLoans(credit)
    local count = 0
    for _, loan in ipairs(credit.loans) do
        if loan.status == "active" or loan.status == "defaulted" then count = count + 1 end
    end
    return count
end

function Credit.profile(state)
    local credit = Credit.ensure(state)
    local tier = Credit.tierFor(credit.score)
    local balance, monthlyDue = 0, 0
    for _, loan in ipairs(credit.loans) do
        if loan.status == "active" or loan.status == "defaulted" then
            balance = balance + loan.balance
            monthlyDue = monthlyDue + loan.monthlyPayment
        end
    end
    return {
        score = credit.score,
        tier = tier.label,
        apr = tier.apr,
        aprBasisPoints = round(tier.apr * 100),
        downPercent = tier.downPercent,
        termMonths = tier.termMonths,
        openLoans = activeLoans(credit),
        totalBalance = balance,
        monthlyDue = monthlyDue,
        history = credit.history,
    }
end

function Credit.machineQuotes(state, channel)
    channel = channel == "dealer" and "dealer" or "online"
    local profile = Credit.profile(state)
    local offers = MachineFleet.offers(channel)
    local result = {}
    local eligible = profile.score >= 500 and profile.openLoans < Credit.MAX_OPEN_LOANS
    for index, offer in ipairs(offers) do
        local downPayment = math.ceil(offer.price * profile.downPercent / 100)
        local principal = offer.price - downPayment
        result[index] = {
            offerIndex = index,
            modelId = offer.modelId,
            channel = channel,
            name = offer.name,
            condition = offer.condition,
            price = offer.price,
            downPayment = downPayment,
            principal = principal,
            apr = profile.apr,
            aprBasisPoints = profile.aprBasisPoints,
            termMonths = profile.termMonths,
            monthlyPayment = Credit.monthlyPayment(principal, profile.aprBasisPoints, profile.termMonths),
            eligible = eligible and (tonumber(state.money) or 0) >= downPayment,
            reason = profile.score < 500 and "Credit score is below the lender's 500-point minimum."
                or profile.openLoans >= Credit.MAX_OPEN_LOANS and "Three machine loans are already open."
                or (tonumber(state.money) or 0) < downPayment and "Save enough cash for the required down payment."
                or nil,
        }
    end
    return result
end

local function historyEntry(credit, state, delta, reason)
    local current = credit.score
    credit.score = math.max(Credit.MIN_SCORE, math.min(Credit.MAX_SCORE, current + delta))
    delta = credit.score - current
    credit.history[#credit.history + 1] = {
        day = math.max(0, math.floor(tonumber(state.calendar and state.calendar.totalDays) or 0)),
        delta = delta,
        score = credit.score,
        reason = tostring(reason):sub(1, 160),
    }
    while #credit.history > 24 do table.remove(credit.history, 1) end
end

local function findRequest(credit, requestId)
    for _, loan in ipairs(credit.loans) do
        if loan.requestId == requestId then return loan end
    end
end

function Credit.financeMachine(state, offerIndex, requestId, channel)
    if type(requestId) ~= "string" or #requestId < 1 or #requestId > 64
        or not requestId:match("^[%w_.%-]+$") then return false, "Invalid finance request." end
    channel = channel == "dealer" and "dealer" or "online"
    local credit = Credit.ensure(state)
    local previous = findRequest(credit, requestId)
    if previous then return true, { loan = previous, replayed = true }, "replayed" end
    local quote = Credit.machineQuotes(state, channel)[tonumber(offerIndex) or 0]
    if not quote then return false, "That machine financing offer is no longer available." end
    if not quote.eligible then return false, quote.reason or "This machine financing offer is unavailable." end

    local fleet = MachineFleet.ensure(state)
    local loanId = string.format("CR-%04d", credit.nextLoanId)
    local now = math.max(0, math.floor(tonumber(state.calendar and state.calendar.totalDays) or 0))
    local machineId = string.format("MCH-%04d", fleet.nextId)
    local bought, purchase = MachineFleet.buy(state, channel, quote.offerIndex, {
        cashPayment = quote.downPayment,
        loanId = loanId,
    })
    if not bought then return false, tostring(purchase) end
    if channel == "dealer" then machineId = purchase.id end

    local loan = {
        id = loanId,
        requestId = requestId,
        channel = channel,
        machineId = machineId,
        modelId = quote.modelId,
        machineName = quote.name,
        purchasePrice = quote.price,
        downPayment = quote.downPayment,
        principal = quote.principal,
        balance = quote.principal,
        aprBasisPoints = quote.aprBasisPoints,
        termMonths = quote.termMonths,
        monthlyPayment = quote.monthlyPayment,
        amountDue = 0,
        installmentsDue = 0,
        accruedInterest = 0,
        feesDue = 0,
        scheduledCount = 0,
        nextDueDay = nil,
        openedAtDay = now,
        oldestDueDay = nil,
        delinquencyLevel = 0,
        lateFeeCharged = false,
        status = "active",
        lienReleased = false,
    }
    local year, month = Calendar.shiftMonth(state.calendar.year, state.calendar.month, 1)
    local dueDay = math.min(state.calendar.day, (month == 2 and (year % 400 == 0 or year % 4 == 0 and year % 100 ~= 0))
        and 29 or month == 2 and 28
        or (month == 4 or month == 6 or month == 9 or month == 11) and 30 or 31)
    loan.nextDueDay = Calendar.totalDayForDate(year, month, dueDay)
    credit.nextLoanId = credit.nextLoanId + 1
    credit.loans[#credit.loans + 1] = loan
    historyEntry(credit, state, -4, "Machine loan application inquiry")
    if channel == "online" then purchase.loanId = loan.id end
    return true, { loan = loan, order = purchase }
end

function Credit.hasLien(state, machineId)
    local credit = Credit.ensure(state)
    for _, loan in ipairs(credit.loans) do
        if loan.machineId == machineId and not loan.lienReleased then return true, loan end
    end
    return false
end

function Credit.payLoan(state, loanId)
    local credit = Credit.ensure(state)
    local loan
    for _, candidate in ipairs(credit.loans) do
        if candidate.id == loanId then loan = candidate; break end
    end
    if not loan or (loan.status ~= "active" and loan.status ~= "defaulted") then
        return false, "That machine loan is not open."
    end
    if loan.installmentsDue < 1 or loan.amountDue < 1 then return false, "No machine payment is due yet." end
    local totalDue = loan.amountDue + loan.feesDue
    if (tonumber(state.money) or 0) < totalDue then
        return false, string.format("Payment due is $%d, but only $%d is available.", totalDue,
            math.floor(tonumber(state.money) or 0))
    end
    local wasOnTime = loan.installmentsDue == 1 and loan.oldestDueDay ~= nil
        and (state.calendar.totalDays or 0) <= loan.oldestDueDay
    state.money = state.money - totalDue
    loan.balance = math.max(0, loan.balance - loan.amountDue)
    loan.amountDue, loan.feesDue, loan.accruedInterest = 0, 0, 0
    loan.installmentsDue, loan.oldestDueDay = 0, nil
    loan.delinquencyLevel, loan.lateFeeCharged = 0, false
    if loan.balance == 0 then
        loan.status, loan.lienReleased = "paid", true
    elseif loan.status == "defaulted" then
        loan.status = "active"
    end
    historyEntry(credit, state, wasOnTime and 2 or 0,
        wasOnTime and "Machine installment paid on time" or "Machine installment paid")
    return true, { loan = loan, amount = totalDue, onTime = wasOnTime }
end

function Credit.recordBillsPaid(state, invoices)
    local credit = Credit.ensure(state)
    local currentDay = math.max(0, math.floor(tonumber(state.calendar and state.calendar.totalDays) or 0))
    for _, invoice in ipairs(invoices or {}) do
        if invoice.kind ~= "spoil_claim" and invoice.paidOnDay == currentDay
            and invoice.dueOnDay ~= nil and currentDay <= invoice.dueOnDay
        then
            historyEntry(credit, state, 2, "Monthly operating bills paid on time")
        end
    end
end

local function nextMonthDay(day)
    local date = Calendar.dateFromTotalDay(day)
    local year, month = Calendar.shiftMonth(date.year, date.month, 1)
    local nextMonthLength = month == 2 and (year % 400 == 0 or year % 4 == 0 and year % 100 ~= 0)
        and 29 or month == 2 and 28
        or (month == 4 or month == 6 or month == 9 or month == 11) and 30 or 31
    return Calendar.totalDayForDate(year, month, math.min(date.day, nextMonthLength))
end

local function markDelinquency(state, account, currentDay, label)
    if account.dueOnDay == nil and account.oldestDueDay == nil then return end
    local oldest = account.dueOnDay or account.oldestDueDay
    local daysLate = math.max(0, currentDay - oldest)
    if daysLate >= 15 and not account.lateFeeCharged then
        local amount = account.total or account.amountDue or 0
        local fee = math.min(50, math.max(10, math.ceil(amount * 0.05)))
        if account.id and account.id:match("^CR%-%d+$") then account.feesDue = account.feesDue + fee
        else
            local _, bills = Calendar.ensure(state)
            account.lateFeeAmount = fee
            bills.balance = bills.balance + fee
        end
        account.lateFeeCharged = true
    end
    local level = math.min(4, math.floor(daysLate / 30))
    while (account.delinquencyLevel or account.creditDelinquencyLevel or 0) < level do
        local currentLevel = account.delinquencyLevel or account.creditDelinquencyLevel or 0
        historyEntry(Credit.ensure(state), state, -LATE_SCORE_HITS[currentLevel + 1],
            string.format("%s reported %d days late", label, (currentLevel + 1) * 30))
        if account.id and account.id:match("^CR%-%d+$") then
            account.delinquencyLevel = currentLevel + 1
            if account.delinquencyLevel >= 4 then account.status = "defaulted" end
        else
            account.creditDelinquencyLevel = currentLevel + 1
        end
    end
end

function Credit.onDay(state)
    local credit = Credit.ensure(state)
    local currentDay = math.max(0, math.floor(tonumber(state.calendar and state.calendar.totalDays) or 0))
    for _, loan in ipairs(credit.loans) do
        if loan.status == "active" or loan.status == "defaulted" then
            while currentDay >= loan.nextDueDay do
                local interest = round(loan.balance * loan.aprBasisPoints / 120000)
                loan.balance = loan.balance + interest
                loan.accruedInterest = loan.accruedInterest + interest
                loan.installmentsDue = loan.installmentsDue + 1
                loan.scheduledCount = loan.scheduledCount + 1
                if loan.scheduledCount >= loan.termMonths then
                    -- The maturity installment settles the remaining balance,
                    -- including interest already accrued into it.
                    loan.amountDue = loan.balance
                else
                    loan.amountDue = loan.amountDue + loan.monthlyPayment
                end
                loan.oldestDueDay = loan.oldestDueDay or loan.nextDueDay
                loan.nextDueDay = nextMonthDay(loan.nextDueDay)
            end
            if loan.installmentsDue > 0 then
                markDelinquency(state, loan, currentDay, loan.machineName)
            end
        end
    end
    for _, invoice in ipairs(state.bills and state.bills.ledger or {}) do
        if invoice.status == "unpaid" and invoice.dueOnDay ~= nil then
            local account = {
                id = invoice.id,
                total = invoice.total,
                dueOnDay = invoice.dueOnDay,
                creditDelinquencyLevel = invoice.creditDelinquencyLevel or 0,
                lateFeeCharged = invoice.lateFeeCharged == true,
            }
            markDelinquency(state, account, currentDay,
                invoice.kind == "spoil_claim" and "Customer claim" or "Operating bills")
            invoice.creditDelinquencyLevel = account.creditDelinquencyLevel
            invoice.lateFeeCharged = account.lateFeeCharged
            if account.lateFeeAmount then
                invoice.lateFeeAmount = account.lateFeeAmount
                account.lateFeeAmount = nil
            end
        end
    end
end

function Credit.loanRows(state)
    local credit = Credit.ensure(state)
    local result = {}
    for _, loan in ipairs(credit.loans) do
        result[#result + 1] = loan
    end
    table.sort(result, function(left, right)
        local leftOpen = left.status == "active" or left.status == "defaulted"
        local rightOpen = right.status == "active" or right.status == "defaulted"
        if leftOpen ~= rightOpen then return leftOpen end
        return (tonumber(left.openedAtDay) or 0) > (tonumber(right.openedAtDay) or 0)
    end)
    return result
end

return Credit
