local Config = require("src.config")
local BusinessCalendar = require("src.business_calendar")
local JobService = require("src.job_service")
local MachineFleet = require("src.machine_fleet")
local Procurement = require("src.procurement")
local BackButton = require("src.screens.back_button")
local StatusLabels = require("src.status_labels")
local Ui = require("src.screens.ui")
local utf8 = require("utf8")

local ComputerScreen = {
    tab = "active",
    selectedJobId = nil,
    selectedEmailId = nil,
    pages = { active = 1, completed = 1, deliveries = 1 },
    quoteText = "",
    quoteFocused = false,
    quoteReplaceOnType = true,
    promoJobId = nil,
    promoText = "",
    promoFocused = false,
    calendarYear = nil,
    calendarMonth = nil,
    calendarSelectedDay = nil,
    calendarScroll = 0,
    retailPage = 1,
}

local PANEL = { x = 52, y = 34, width = 856, height = 610 }
local CLOSE = { x = 756, y = 48, width = 132, height = 40 }
local TABS = {
    { id = "active", label = "ACTIVE", x = 82, y = 128, width = 90, height = 40 },
    { id = "completed", label = "DONE", x = 178, y = 128, width = 90, height = 40 },
    { id = "deliveries", label = "DELIVERY", x = 274, y = 128, width = 90, height = 40 },
    { id = "calendar", label = "CALENDAR", x = 370, y = 128, width = 90, height = 40 },
    { id = "inventory", label = "STOCK", x = 466, y = 128, width = 90, height = 40 },
    { id = "online", label = "ONLINE", x = 562, y = 128, width = 90, height = 40 },
    { id = "email", label = "EMAIL", x = 658, y = 128, width = 90, height = 40 },
    { id = "bills", label = "BILLS", x = 754, y = 128, width = 90, height = 40 },
}
local LIST = { x = 82, y = 190, width = 310, height = 370 }
local DETAIL = { x = 412, y = 190, width = 440, height = 444 }
local PREVIOUS = { x = 82, y = 570, width = 86, height = 30 }
local NEXT = { x = 306, y = 570, width = 86, height = 30 }
local COMPLETE = { x = 598, y = 598, width = 228, height = 36 }
local RETAIL = { x = 444, y = 388, width = 378, rowHeight = 44, gap = 5 }
local RETAIL_PREVIOUS = { x = 718, y = 354, width = 46, height = 28 }
local RETAIL_NEXT = { x = 776, y = 354, width = 46, height = 28 }
local RETAIL_PAGE_SIZE = 5
local PAY_BILLS = { x = 612, y = 522, width = 196, height = 46 }
local EMAIL_QUOTE_INPUT = { x = 434, y = 470, width = 190, height = 40 }
local EMAIL_ACCEPT = { x = 640, y = 470, width = 186, height = 40 }
local EMAIL_DECLINE = { x = 434, y = 526, width = 186, height = 44 }
local PROMO = { x = 640, y = 526, width = 186, height = 44 }
local JOB_PROMO = { x = 640, y = 590, width = 186, height = 44 }
local PROMO_INPUT = { x = 434, y = 338, width = 392, height = 122 }
local CAL_PREVIOUS = { x = 96, y = 202, width = 42, height = 30 }
local CAL_NEXT = { x = 542, y = 202, width = 42, height = 30 }
local CAL_GRID = { x = 94, y = 272, cellWidth = 70, cellHeight = 54 }
local CAL_EVENT_LIST = { x = 624, y = 240, width = 216, rowHeight = 34, visibleRows = 9 }
local CAL_SCROLL_UP = { x = 624, y = 558, width = 102, height = 28 }
local CAL_SCROLL_DOWN = { x = 738, y = 558, width = 102, height = 28 }
local MACHINE_OFFER = { x = 92, y = 260, width = 354, height = 92, gap = 14 }
local OWNED_MACHINE = { x = 486, y = 260, width = 354, height = 74, gap = 10 }
local ROW_HEIGHT = 46
local JOBS_PER_PAGE = 7

local contains, commaNumber, money = Ui.contains, Ui.commaNumber, Ui.money

local function calendarMonthEvents(state, year, month)
    local result = {}
    for _, event in ipairs(BusinessCalendar.events(state)) do
        if event.year == year and event.month == month then result[#result + 1] = event end
    end
    return result
end

local function calendarDayRect(year, month, day)
    local firstTotal = BusinessCalendar.totalDayForDate(year, month, 1)
    local firstColumn = BusinessCalendar.dateFromTotalDay(firstTotal or 0).weekday
    local cellIndex = firstColumn - 1 + day - 1
    local column, row = cellIndex % 7, math.floor(cellIndex / 7)
    return {
        x = CAL_GRID.x + column * CAL_GRID.cellWidth + 2,
        y = CAL_GRID.y + row * CAL_GRID.cellHeight + 2,
        width = CAL_GRID.cellWidth - 4,
        height = CAL_GRID.cellHeight - 4,
    }
end

local function calendarDayAt(year, month, x, y)
    for day = 1, BusinessCalendar.daysInMonth(year, month) do
        if contains(calendarDayRect(year, month, day), x, y) then return day end
    end
end

local function clampCalendarScroll(state)
    local events = calendarMonthEvents(state, ComputerScreen.calendarYear, ComputerScreen.calendarMonth)
    local maximum = math.max(0, #events - CAL_EVENT_LIST.visibleRows)
    ComputerScreen.calendarScroll = math.min(maximum, math.max(0, ComputerScreen.calendarScroll or 0))
    return events, maximum
end

local function retailCatalog()
    local result = {}
    for _, offer in ipairs(Procurement.retailCatalog()) do
        if offer.available then result[#result + 1] = offer end
    end
    return result
end

local function retailBuyRect(index)
    return { x = RETAIL.x + RETAIL.width - 104,
        y = RETAIL.y + (index - 1) * (RETAIL.rowHeight + RETAIL.gap), width = 98, height = RETAIL.rowHeight }
end

local function machineBuyRect(index)
    return { x = MACHINE_OFFER.x + MACHINE_OFFER.width - 100,
        y = MACHINE_OFFER.y + (index - 1) * (MACHINE_OFFER.height + MACHINE_OFFER.gap) + 24,
        width = 88, height = 46 }
end

local function machineSellRect(index)
    return { x = OWNED_MACHINE.x + OWNED_MACHINE.width - 88,
        y = OWNED_MACHINE.y + (index - 1) * (OWNED_MACHINE.height + OWNED_MACHINE.gap) + 18,
        width = 76, height = 38 }
end

local function isPurchaseOrder(item)
    return item and item.vendor ~= nil and item.productName ~= nil
end

local function displayStatus(item)
    if isPurchaseOrder(item) then
        return item.delivery and item.delivery.status or item.status
    end
    return item and item.status
end

local function deliveries(state)
    local result = {}
    for _, job in ipairs(state.jobs.active or {}) do
        if job.status == "awaiting_delivery"
            or job.status == "ready_for_pickup"
            or job.status == "pickup_in_progress"
        then
            result[#result + 1] = job
        end
    end
    local procurement = Procurement.ensure(state)
    for _, order in ipairs(procurement.orders or {}) do result[#result + 1] = order end
    return result
end

function ComputerScreen.deliveryRows(state) return deliveries(state) end
function ComputerScreen.statusLabel(status) return StatusLabels.get(status) end

local function jobsForTab(state, tab)
    if tab == "active" then return state.jobs.active or {} end
    if tab == "completed" then return state.jobs.completed or {} end
    if tab == "deliveries" then return deliveries(state) end
    return {}
end

local function findJob(jobs, id)
    for _, job in ipairs(jobs) do
        if job.id == id then return job end
    end
    return nil
end

local function selectedEmail(state)
    for _, email in ipairs(JobService.emailInbox(state)) do
        if email.id == ComputerScreen.selectedEmailId then return email end
    end
end

local function resetQuoteText(state)
    local email = selectedEmail(state)
    local base = email and email.job and email.job.quote and email.job.quote.totalPrice
    ComputerScreen.quoteText = base and tostring(math.floor(base)) or ""
    ComputerScreen.quoteFocused = false
    ComputerScreen.quoteReplaceOnType = true
end

local function currentPageJobs(state)
    local jobs = jobsForTab(state, ComputerScreen.tab)
    local page = ComputerScreen.pages[ComputerScreen.tab] or 1
    local maximumPage = math.max(1, math.ceil(#jobs / JOBS_PER_PAGE))
    page = math.min(math.max(1, page), maximumPage)
    ComputerScreen.pages[ComputerScreen.tab] = page
    local visible = {}
    local first = (page - 1) * JOBS_PER_PAGE + 1
    for index = first, math.min(#jobs, first + JOBS_PER_PAGE - 1) do
        visible[#visible + 1] = jobs[index]
    end
    return jobs, visible, page, maximumPage
end

local function ensureSelection(state)
    local jobs = jobsForTab(state, ComputerScreen.tab)
    if not findJob(jobs, ComputerScreen.selectedJobId) then
        ComputerScreen.selectedJobId = jobs[1] and jobs[1].id or nil
    end
end

local function completionReady(job)
    return JobService.completionReady(job)
end

function ComputerScreen.packagingText(job)
    if not job then return "Customer instructions not specified" end
    if job.packaging == "boxed" then
        return "Boxed paper on pallets; stretch-wrap each finished pallet"
    end
    if job.packaging == "flat" then
        return "Flat stacked on pallets; stretch-wrap each finished pallet"
    end
    return "Customer instructions not specified"
end

function ComputerScreen.enter(state)
    ComputerScreen.tab = "active"
    ComputerScreen.pages = { active = 1, completed = 1, deliveries = 1 }
    ComputerScreen.selectedJobId = nil
    ComputerScreen.selectedEmailId = JobService.emailInbox(state)[1]
        and JobService.emailInbox(state)[1].id or nil
    ComputerScreen.quoteText = ""
    ComputerScreen.quoteFocused = false
    ComputerScreen.quoteReplaceOnType = true
    ComputerScreen.promoJobId = nil
    ComputerScreen.promoText = ""
    ComputerScreen.promoFocused = false
    ComputerScreen.calendarYear = state.calendar.year
    ComputerScreen.calendarMonth = state.calendar.month
    ComputerScreen.calendarSelectedDay = state.calendar.day
    ComputerScreen.calendarScroll = 0
    ComputerScreen.retailPage = 1
    ensureSelection(state)
end

function ComputerScreen.tabCenter(tabId)
    for _, tab in ipairs(TABS) do
        if tab.id == tabId then return tab.x + tab.width / 2, tab.y + tab.height / 2 end
    end
end

function ComputerScreen.closeCenter()
    return CLOSE.x + CLOSE.width / 2, CLOSE.y + CLOSE.height / 2
end

function ComputerScreen.completeCenter()
    return COMPLETE.x + COMPLETE.width / 2, COMPLETE.y + COMPLETE.height / 2
end

function ComputerScreen.retailButtonCenter(index)
    local rect = retailBuyRect(index)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function ComputerScreen.retailPageCenter(direction)
    local rect = direction == "previous" and RETAIL_PREVIOUS or RETAIL_NEXT
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function ComputerScreen.machineBuyCenter(index)
    local rect = machineBuyRect(index)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function ComputerScreen.machineSellCenter(index)
    local rect = machineSellRect(index)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function ComputerScreen.payBillsCenter()
    return PAY_BILLS.x + PAY_BILLS.width / 2, PAY_BILLS.y + PAY_BILLS.height / 2
end

function ComputerScreen.emailButtonCenter(action)
    local rect = action == "accept" and EMAIL_ACCEPT or EMAIL_DECLINE
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function ComputerScreen.textInputCenter(kind)
    local rect = kind == "promotion" and PROMO_INPUT or EMAIL_QUOTE_INPUT
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function ComputerScreen.rowCenter(row)
    return LIST.x + LIST.width / 2, LIST.y + 14 + (row - 1) * ROW_HEIGHT + 18
end

function ComputerScreen.calendarDayCenter(day)
    local rect = calendarDayRect(ComputerScreen.calendarYear, ComputerScreen.calendarMonth, day)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function ComputerScreen.calendarScrollCenter(direction)
    local rect = direction == "up" and CAL_SCROLL_UP or CAL_SCROLL_DOWN
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function ComputerScreen.mousepressed(state, x, y, button)
    if button ~= 1 then return nil end
    -- Do not retain Android keyboard focus when the player taps elsewhere.
    -- The quote and promotion input hit targets below explicitly opt back in.
    ComputerScreen.quoteFocused = false
    ComputerScreen.promoFocused = false
    if contains(CLOSE, x, y) then return { action = "close" } end
    for _, tab in ipairs(TABS) do
        if contains(tab, x, y) then
            ComputerScreen.tab = tab.id
            if tab.id == "email" then
                local inbox = JobService.emailInbox(state)
                local found = false
                for _, email in ipairs(inbox) do
                    if email.id == ComputerScreen.selectedEmailId then found = true; break end
                end
                if not found then ComputerScreen.selectedEmailId = inbox[1] and inbox[1].id or nil end
                if not ComputerScreen.promoJobId then resetQuoteText(state) end
            elseif tab.id == "calendar" then
                ComputerScreen.calendarYear = state.calendar.year
                ComputerScreen.calendarMonth = state.calendar.month
                ComputerScreen.calendarSelectedDay = state.calendar.day
                ComputerScreen.calendarScroll = 0
            elseif tab.id == "inventory" then
                ComputerScreen.retailPage = 1
            end
            ensureSelection(state)
            return { action = "tab", tab = tab.id }
        end
    end
    if ComputerScreen.tab == "inventory" then
        local catalog = retailCatalog()
        local maxPage = math.max(1, math.ceil(#catalog / RETAIL_PAGE_SIZE))
        if contains(RETAIL_PREVIOUS, x, y) then
            ComputerScreen.retailPage = math.max(1, ComputerScreen.retailPage - 1)
            return { action = "retail_page", page = ComputerScreen.retailPage }
        elseif contains(RETAIL_NEXT, x, y) then
            ComputerScreen.retailPage = math.min(maxPage, ComputerScreen.retailPage + 1)
            return { action = "retail_page", page = ComputerScreen.retailPage }
        end
        local first = (ComputerScreen.retailPage - 1) * RETAIL_PAGE_SIZE + 1
        for visibleIndex = 1, RETAIL_PAGE_SIZE do
            local offer = catalog[first + visibleIndex - 1]
            if offer and contains(retailBuyRect(visibleIndex), x, y) then
                local succeeded, result = Procurement.buyRetail(state, offer.categoryIndex, offer.itemIndex)
                if not succeeded then state.message = tostring(result); return { action = "blocked" } end
                state.message = string.format("Computer order %s placed for %s. Delivery will arrive at the dock.",
                    result.id, result.productName)
                return { action = "supply_order", order = result }
            end
        end
        return nil
    end
    if ComputerScreen.tab == "online" then
        for index, offer in ipairs(MachineFleet.offers("online")) do
            if contains(machineBuyRect(index), x, y) then
                local succeeded, result = MachineFleet.orderOnline(state, index)
                if not succeeded then state.message = tostring(result); return { action = "blocked" } end
                state.message = string.format(
                    "Ordered %s (%s, %.0f%% condition). Flatbed delivery %s will bring unit %s to the dock.",
                    result.machineName, MachineFleet.conditionStatus(result.condition), result.condition,
                    result.id, result.machineId)
                return { action = "machine_ordered", order = result }
            end
        end
        for index, item in ipairs(MachineFleet.owned(state)) do
            if index <= 4 and contains(machineSellRect(index), x, y) then
                local succeeded, result = MachineFleet.sell(state, item.id, "online")
                if not succeeded then state.message = tostring(result); return { action = "blocked" } end
                state.message = string.format("Sold %s online for $%d.", result.machine.name, result.price)
                return { action = "machine_sold", sale = result }
            end
        end
        return nil
    end
    if ComputerScreen.tab == "bills" then
        if contains(PAY_BILLS, x, y) then
            local paid, result = BusinessCalendar.pay(state)
            if not paid then state.message = result; return { action = "blocked" } end
            state.message = string.format("Paid $%d in monthly operating bills.", result)
            return { action = "bill_paid", amount = result }
        end
        return nil
    end
    if ComputerScreen.tab == "calendar" then
        if contains(CAL_PREVIOUS, x, y) then
            ComputerScreen.calendarYear, ComputerScreen.calendarMonth = BusinessCalendar.shiftMonth(
                ComputerScreen.calendarYear, ComputerScreen.calendarMonth, -1)
            ComputerScreen.calendarSelectedDay, ComputerScreen.calendarScroll = nil, 0
            return { action = "calendar_month" }
        elseif contains(CAL_NEXT, x, y) then
            ComputerScreen.calendarYear, ComputerScreen.calendarMonth = BusinessCalendar.shiftMonth(
                ComputerScreen.calendarYear, ComputerScreen.calendarMonth, 1)
            ComputerScreen.calendarSelectedDay, ComputerScreen.calendarScroll = nil, 0
            return { action = "calendar_month" }
        end
        local events, maximum = clampCalendarScroll(state)
        if contains(CAL_SCROLL_UP, x, y) then
            ComputerScreen.calendarScroll = math.max(0, ComputerScreen.calendarScroll - 1)
            return { action = "calendar_scroll" }
        elseif contains(CAL_SCROLL_DOWN, x, y) then
            ComputerScreen.calendarScroll = math.min(maximum, ComputerScreen.calendarScroll + 1)
            return { action = "calendar_scroll" }
        end
        local day = calendarDayAt(ComputerScreen.calendarYear, ComputerScreen.calendarMonth, x, y)
        if day then
            ComputerScreen.calendarSelectedDay = day
            for index, event in ipairs(events) do
                if event.day == day then
                    ComputerScreen.calendarScroll = math.min(maximum, math.max(0, index - 1))
                    break
                end
            end
            return { action = "calendar_day", day = day }
        end
        for row = 1, CAL_EVENT_LIST.visibleRows do
            local index = ComputerScreen.calendarScroll + row
            local rect = { x = CAL_EVENT_LIST.x, y = CAL_EVENT_LIST.y + (row - 1) * CAL_EVENT_LIST.rowHeight,
                width = CAL_EVENT_LIST.width, height = 31 }
            if events[index] and contains(rect, x, y) then
                ComputerScreen.calendarSelectedDay = events[index].day
                return { action = "calendar_event", event = events[index] }
            end
        end
        return nil
    end
    if ComputerScreen.tab == "email" then
        if ComputerScreen.promoJobId then
            if contains(PROMO_INPUT, x, y) then
                ComputerScreen.promoFocused = true
                return { action = "promo_focus" }
            end
            if contains(EMAIL_DECLINE, x, y) then
                ComputerScreen.promoJobId, ComputerScreen.promoText = nil, ""
                ComputerScreen.promoFocused = false
                return { action = "promo_cancelled" }
            elseif contains(PROMO, x, y) then
                local job = findJob(state.jobs.completed or {}, ComputerScreen.promoJobId)
                local succeeded, result = JobService.sendPromotion(state, job, ComputerScreen.promoText)
                if not succeeded then state.message = tostring(result); return { action = "blocked" } end
                ComputerScreen.promoJobId, ComputerScreen.promoText = nil, ""
                ComputerScreen.promoFocused = false
                state.message = "Sent " .. result.recipient .. " a 10% returning-client offer."
                return { action = "promotion_sent", promotion = result }
            end
            ComputerScreen.promoFocused = false
            return nil
        end
        local inbox = JobService.emailInbox(state)
        if not ComputerScreen.selectedEmailId and inbox[1] then
            ComputerScreen.selectedEmailId = inbox[1].id
        end
        for row, email in ipairs(inbox) do
            local rect = { x = 94, y = 238 + (row - 1) * 54, width = 280, height = 46 }
            if contains(rect, x, y) then
                ComputerScreen.selectedEmailId = email.id
                resetQuoteText(state)
                return { action = "email_select", email = email }
            end
        end
        local currentEmail = selectedEmail(state)
        if currentEmail and currentEmail.serviceNotice then
            ComputerScreen.quoteFocused = false
            if contains(EMAIL_DECLINE, x, y) then
                MachineFleet.dismissServiceNotice(state, currentEmail.id)
                ComputerScreen.selectedEmailId = JobService.emailInbox(state)[1]
                    and JobService.emailInbox(state)[1].id or nil
                state.message = "Archived the technician's service notice."
                return { action = "service_notice_dismissed" }
            end
            return nil
        end
        if contains(EMAIL_QUOTE_INPUT, x, y) then
            ComputerScreen.quoteFocused = true
            ComputerScreen.quoteReplaceOnType = true
            return { action = "quote_focus" }
        end
        if ComputerScreen.selectedEmailId and contains(EMAIL_ACCEPT, x, y) then
            local succeeded, result = JobService.submitEmailQuote(
                state, ComputerScreen.selectedEmailId, tonumber(ComputerScreen.quoteText), os.time())
            if not succeeded then state.message = tostring(result); return { action = "blocked" } end
            ComputerScreen.selectedEmailId = JobService.emailInbox(state)[1]
                and JobService.emailInbox(state)[1].id or nil
            resetQuoteText(state)
            state.message = result.accepted
                and string.format("%s accepted your $%d quote. Stock delivery is pending.",
                    result.job.company, result.amount)
                or string.format("%s declined your $%d quote.", result.job.company, result.amount)
            return { action = result.accepted and "quote_accepted" or "quote_rejected", result = result }
        elseif ComputerScreen.selectedEmailId and contains(EMAIL_DECLINE, x, y) then
            local succeeded, result = JobService.respondToEmail(
                state, ComputerScreen.selectedEmailId, "declined", os.time())
            if not succeeded then state.message = tostring(result); return { action = "blocked" } end
            ComputerScreen.selectedEmailId = JobService.emailInbox(state)[1]
                and JobService.emailInbox(state)[1].id or nil
            resetQuoteText(state)
            state.message = "Declined email request " .. result.id .. "."
            return { action = "email_declined", job = result }
        end
        return nil
    end

    local _, visible, page, maximumPage = currentPageJobs(state)
    if contains(PREVIOUS, x, y) and page > 1 then
        ComputerScreen.pages[ComputerScreen.tab] = page - 1
        local _, pageJobs = currentPageJobs(state)
        ComputerScreen.selectedJobId = pageJobs[1] and pageJobs[1].id or nil
        return { action = "page", page = page - 1 }
    end
    if contains(NEXT, x, y) and page < maximumPage then
        ComputerScreen.pages[ComputerScreen.tab] = page + 1
        local _, pageJobs = currentPageJobs(state)
        ComputerScreen.selectedJobId = pageJobs[1] and pageJobs[1].id or nil
        return { action = "page", page = page + 1 }
    end
    for row, job in ipairs(visible) do
        local rect = { x = LIST.x + 8, y = LIST.y + 14 + (row - 1) * ROW_HEIGHT,
            width = LIST.width - 16, height = 38 }
        if contains(rect, x, y) then
            ComputerScreen.selectedJobId = job.id
            return { action = "select", job = job }
        end
    end
    local selected = findJob(jobsForTab(state, ComputerScreen.tab), ComputerScreen.selectedJobId)
    if ComputerScreen.tab == "active" and contains(COMPLETE, x, y) then
        return { action = completionReady(selected) and "pickup_ready" or "completion_blocked",
            job = selected }
    end
    if ComputerScreen.tab == "completed" and selected and contains(JOB_PROMO, x, y) then
        ComputerScreen.promoJobId = selected.id
        ComputerScreen.promoText = ""
        ComputerScreen.promoFocused = false
        ComputerScreen.tab = "email"
        return { action = "promotion_compose", job = selected }
    end
    return nil
end

function ComputerScreen.wheelmoved(state, _, y)
    if ComputerScreen.tab ~= "calendar" or y == 0 then return false end
    local _, maximum = clampCalendarScroll(state)
    ComputerScreen.calendarScroll = math.min(maximum,
        math.max(0, ComputerScreen.calendarScroll - (y > 0 and 1 or -1)))
    return true
end

function ComputerScreen.keypressed(state, key)
    local focused = ComputerScreen.promoJobId and ComputerScreen.promoFocused
        or (ComputerScreen.tab == "email" and ComputerScreen.quoteFocused)
    if not focused then return false end
    if key == "backspace" then
        local value = ComputerScreen.promoJobId and ComputerScreen.promoText or ComputerScreen.quoteText
        if not ComputerScreen.promoJobId and ComputerScreen.quoteReplaceOnType then
            value = ""
            ComputerScreen.quoteReplaceOnType = false
        else
            local offset = utf8.offset(value, -1)
            value = offset and value:sub(1, offset - 1) or ""
        end
        if ComputerScreen.promoJobId then ComputerScreen.promoText = value
        else ComputerScreen.quoteText = value end
        return true
    end
    return false
end

function ComputerScreen.textinput(state, text)
    if ComputerScreen.promoJobId and ComputerScreen.promoFocused then
        if #ComputerScreen.promoText < 240 then
            ComputerScreen.promoText = (ComputerScreen.promoText .. text):sub(1, 240)
        end
        return true
    elseif ComputerScreen.tab == "email" and ComputerScreen.quoteFocused then
        for character in text:gmatch(".") do
            if character:match("%d") and #ComputerScreen.quoteText < 8 then
                if ComputerScreen.quoteReplaceOnType then
                    ComputerScreen.quoteText = ""
                    ComputerScreen.quoteReplaceOnType = false
                end
                ComputerScreen.quoteText = ComputerScreen.quoteText .. character
            end
        end
        return true
    end
    return false
end

function ComputerScreen.wantsTextInput()
    return ComputerScreen.promoJobId and ComputerScreen.promoFocused
        or ComputerScreen.tab == "email" and ComputerScreen.quoteFocused
end

local panel = Ui.panel

local function drawTabs(pointerX, pointerY)
    for _, tab in ipairs(TABS) do
        local selected = ComputerScreen.tab == tab.id
        local hovered = pointerX and contains(tab, pointerX, pointerY)
        love.graphics.setColor(
            selected and 0.19 or hovered and 0.15 or 0.09,
            selected and 0.48 or hovered and 0.35 or 0.16,
            selected and 0.46 or hovered and 0.34 or 0.21
        )
        love.graphics.rectangle("fill", tab.x, tab.y, tab.width, tab.height, 3, 3)
        love.graphics.setColor(0.92, 0.94, 0.94)
        love.graphics.printf(tab.label, tab.x, tab.y + 14, tab.width, "center")
    end
end

local function drawJobList(state, pointerX, pointerY)
    panel(LIST, { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
    local jobs, visible, page, maximumPage = currentPageJobs(state)
    if #jobs == 0 then
        love.graphics.setColor(0.58, 0.64, 0.66)
        love.graphics.printf("No jobs in this view", LIST.x, LIST.y + 155, LIST.width, "center")
    end
    for row, job in ipairs(visible) do
        local rect = { x = LIST.x + 8, y = LIST.y + 14 + (row - 1) * ROW_HEIGHT,
            width = LIST.width - 16, height = 38 }
        local selected = ComputerScreen.selectedJobId == job.id
        local hovered = pointerX and contains(rect, pointerX, pointerY)
        love.graphics.setColor(selected and 0.15 or hovered and 0.12 or 0.08,
            selected and 0.39 or hovered and 0.28 or 0.13,
            selected and 0.38 or hovered and 0.27 or 0.17)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 2, 2)
        love.graphics.setColor(0.93, 0.94, 0.92)
        love.graphics.print(job.id .. "  " .. job.company, rect.x + 8, rect.y + 6)
        love.graphics.setColor(0.62, 0.70, 0.71)
        love.graphics.print(StatusLabels.get(displayStatus(job)), rect.x + 8, rect.y + 21)
    end
    love.graphics.setColor(0.55, 0.63, 0.65)
    love.graphics.printf(string.format("Page %d / %d", page, maximumPage), 168, 578, 138, "center")

    local function pageButton(rect, label, enabled)
        local hovered = enabled and pointerX and contains(rect, pointerX, pointerY)
        love.graphics.setColor(enabled and (hovered and 0.18 or 0.11) or 0.07,
            enabled and (hovered and 0.42 or 0.27) or 0.09,
            enabled and (hovered and 0.40 or 0.29) or 0.10)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 2, 2)
        love.graphics.setColor(enabled and 0.90 or 0.36, enabled and 0.92 or 0.40, enabled and 0.90 or 0.41)
        love.graphics.printf(label, rect.x, rect.y + 9, rect.width, "center")
    end
    pageButton(PREVIOUS, "PREV", page > 1)
    pageButton(NEXT, "NEXT", page < maximumPage)
end

local function drawArtworkPreview(assets, job, x, y, size)
    local key = job and job.artwork and job.artwork.key or job and job.artworkKey or "flower"
    love.graphics.setColor(0.10, 0.14, 0.16)
    love.graphics.rectangle("fill", x, y, size, size, 3, 3)
    love.graphics.setColor(0.35, 0.56, 0.58)
    love.graphics.rectangle("line", x, y, size, size, 3, 3)
    local image = assets and assets.getArtwork and assets.getArtwork(key)
    if image then
        local imageWidth, imageHeight = image:getDimensions()
        local scale = math.min((size - 6) / imageWidth, (size - 6) / imageHeight)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, x + (size - imageWidth * scale) / 2,
            y + (size - imageHeight * scale) / 2, 0, scale, scale)
    end
    love.graphics.setColor(0.72, 0.79, 0.80)
    local name = job and job.artwork and (job.artwork.displayName or job.artwork.fileName) or key
    love.graphics.printf((job and job.press and "CLIENT ART\n" or "JOB ART\n")
        .. string.upper(name or "artwork"),
        x - 31, y + size + 8, size + 62, "center")
end

local function detailRows(selected)
    local details = selected.details or {}
    local rows = {
        { text = string.format("Parent: %g × %g in",
            selected.sourceSize.width, selected.sourceSize.height), width = 310 },
        { text = string.format("Finished: %g × %g in",
            selected.finishedSize.width, selected.finishedSize.height), width = 310 },
        { text = "Stock: " .. (selected.stockSpec and selected.stockSpec.description
            or details.stockDescription or "Customer supplied"), width = 310 },
        { text = "Packaging: " .. ComputerScreen.packagingText(selected), width = 310 },
    }
    if selected.press then
        local actual = selected.press.actual or {}
        rows[#rows + 1] = {
            text = string.format("Print: %s target • %s supplied • %d imp • %d spoil",
                commaNumber(selected.quote.orderedCopies or selected.press.orderedQuantity
                    or selected.quote.totalSheets),
                commaNumber(selected.quote.suppliedSheets or selected.quote.totalSheets),
                actual.impressions or 0, actual.spoilage or 0),
            width = DETAIL.width - 40,
        }
        rows[#rows + 1] = {
            text = string.format("Inks (%d): %s", selected.press.colors or 1,
                table.concat(selected.press.colorSequence or { "Black" }, " → ")),
            width = DETAIL.width - 40,
        }
    end
    return rows
end

function ComputerScreen.jobDetailLayout(selected)
    local font = love.graphics.getFont()
    local y = DETAIL.y + 96
    local rows = detailRows(selected)
    for _, row in ipairs(rows) do
        local _, wrapped = font:getWrap(row.text, row.width)
        row.y = y
        row.height = math.max(1, #wrapped) * font:getHeight()
        y = y + row.height + 4
    end
    local valueY = y + 1
    local tableY = valueY + font:getHeight() + 9
    local palletCount = #(selected.pallets or {})
    local palletRowHeight = palletCount >= 3 and 24 or 28
    return {
        rows = rows,
        valueY = valueY,
        tableY = tableY,
        palletRowHeight = palletRowHeight,
        textBottom = y,
        tableBottom = tableY + 30 + palletCount * palletRowHeight,
        actionTop = ComputerScreen.tab == "completed" and JOB_PROMO.y or COMPLETE.y,
    }
end

local function drawDetail(state, pointerX, pointerY, assets)
    panel(DETAIL, { 0.065, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
    local selected = findJob(jobsForTab(state, ComputerScreen.tab), ComputerScreen.selectedJobId)
    if not selected then
        love.graphics.setColor(0.58, 0.64, 0.66)
        love.graphics.printf("Select a job to view its ticket and pallet progress.",
            DETAIL.x + 24, DETAIL.y + 145, DETAIL.width - 48, "center")
        return
    end
    if isPurchaseOrder(selected) then
        local delivery = selected.delivery or {}
        local pallet = selected.pallets and selected.pallets[1] or {}
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.print(selected.id .. "  •  PURCHASE ORDER", DETAIL.x + 20, DETAIL.y + 18)
        love.graphics.setColor(0.72, 0.79, 0.80)
        love.graphics.print(StatusLabels.get(displayStatus(selected)), DETAIL.x + 20, DETAIL.y + 44)
        love.graphics.print("Vendor: " .. tostring(selected.vendor), DETAIL.x + 20, DETAIL.y + 82)
        love.graphics.print("Product: " .. tostring(selected.productName), DETAIL.x + 20, DETAIL.y + 112)
        love.graphics.print("Purchase price: " .. money(selected.price), DETAIL.x + 20, DETAIL.y + 142)
        love.graphics.print("Order state: " .. StatusLabels.get(selected.status), DETAIL.x + 20, DETAIL.y + 182)
        love.graphics.print("Delivery state: " .. StatusLabels.get(delivery.status), DETAIL.x + 20, DETAIL.y + 212)
        love.graphics.print("Pallet state: " .. StatusLabels.get(pallet.status), DETAIL.x + 20, DETAIL.y + 242)
        love.graphics.print("Pallet location: " .. StatusLabels.get(pallet.location), DETAIL.x + 20, DETAIL.y + 272)
        love.graphics.setColor(0.55, 0.63, 0.65)
        love.graphics.printf("Purchase orders are paid when placed. Received supplies appear in Inventory.",
            DETAIL.x + 20, DETAIL.y + 326, DETAIL.width - 40, "left")
        return
    end
    love.graphics.setColor(0.96, 0.84, 0.30)
    love.graphics.print(selected.id .. "  •  " .. selected.company, DETAIL.x + 20, DETAIL.y + 18)
    love.graphics.setColor(0.72, 0.79, 0.80)
    love.graphics.print(StatusLabels.get(selected.status), DETAIL.x + 20, DETAIL.y + 44)
    love.graphics.printf("Inbound: " .. JobService.deliverySummary(selected, state),
        DETAIL.x + 20, DETAIL.y + 66, 310, "left")
    local layout = ComputerScreen.jobDetailLayout(selected)
    for _, row in ipairs(layout.rows) do
        love.graphics.printf(row.text, DETAIL.x + 20, row.y, row.width, "left")
    end
    love.graphics.print("Job value: " .. money(selected.quote.totalPrice), DETAIL.x + 20, layout.valueY)
    love.graphics.print("Required lifts: " .. selected.quote.totalLifts, DETAIL.x + 190, layout.valueY)
    drawArtworkPreview(assets, selected, DETAIL.x + 350, DETAIL.y + 34, 70)

    love.graphics.setColor(0.16, 0.22, 0.24)
    love.graphics.rectangle("fill", DETAIL.x + 18, layout.tableY, DETAIL.width - 36, 26)
    love.graphics.setColor(0.85, 0.88, 0.87)
    love.graphics.print("PALLET", DETAIL.x + 28, layout.tableY + 7)
    love.graphics.print(selected.press and "GOOD / TARGET" or "REMAINING", DETAIL.x + 132, layout.tableY + 7)
    love.graphics.print("LIFTS", DETAIL.x + 270, layout.tableY + 7)
    love.graphics.print("STATE", DETAIL.x + 340, layout.tableY + 7)
    for index, pallet in ipairs(selected.pallets or {}) do
        local y = layout.tableY + 30 + (index - 1) * layout.palletRowHeight
        love.graphics.setColor(0.12, 0.15, 0.17)
        love.graphics.rectangle("fill", DETAIL.x + 18, y, DETAIL.width - 36,
            layout.palletRowHeight - 3)
        love.graphics.setColor(0.78, 0.83, 0.83)
        love.graphics.print(tostring(pallet.number), DETAIL.x + 48, y + 7)
        if selected.press then
            love.graphics.print(string.format("%s / %s",
                commaNumber(pallet.press and pallet.press.goodSheets or 0),
                commaNumber(pallet.requestedCopies or pallet.initialSheets)), DETAIL.x + 136, y + 7)
        else
            love.graphics.print(commaNumber(pallet.remainingSheets), DETAIL.x + 153, y + 7)
        end
        love.graphics.print(string.format("%d/%d", pallet.completedLifts, pallet.requiredLifts), DETAIL.x + 274, y + 7)
        love.graphics.print(StatusLabels.get(pallet.status), DETAIL.x + 340, y + 7)
    end

    if ComputerScreen.tab == "completed" then
        local hovered = pointerX and contains(JOB_PROMO, pointerX, pointerY)
        love.graphics.setColor(hovered and 0.19 or 0.12, hovered and 0.55 or 0.42, 0.29)
        love.graphics.rectangle("fill", JOB_PROMO.x, JOB_PROMO.y,
            JOB_PROMO.width, JOB_PROMO.height, 3, 3)
        love.graphics.setColor(0.95, 0.97, 0.94)
        love.graphics.printf("EMAIL 10% PROMO", JOB_PROMO.x, JOB_PROMO.y + 15,
            JOB_PROMO.width, "center")
        return
    end
    if ComputerScreen.tab ~= "active" then return end
    local ready = completionReady(selected)
    local hovered = ready and pointerX and contains(COMPLETE, pointerX, pointerY)
    love.graphics.setColor(ready and (hovered and 0.19 or 0.12) or 0.12,
        ready and (hovered and 0.55 or 0.42) or 0.15,
        ready and 0.29 or 0.16)
    love.graphics.rectangle("fill", COMPLETE.x, COMPLETE.y, COMPLETE.width, COMPLETE.height, 3, 3)
    love.graphics.setColor(ready and 0.95 or 0.48, ready and 0.96 or 0.51, ready and 0.93 or 0.51)
    local buttonLabel = ready and "SCHEDULE CUSTOMER PICKUP" or "PRODUCTION NOT COMPLETE"
    if selected.status == "ready_for_pickup" then buttonLabel = "PICKUP AWAITING TRUCK"
    elseif selected.status == "pickup_in_progress" then buttonLabel = "PICKUP IN PROGRESS"
    elseif selected.status == "completed" then buttonLabel = "PAID AND COMPLETED" end
    love.graphics.printf(buttonLabel,
        COMPLETE.x, COMPLETE.y + 11, COMPLETE.width, "center")
end

local function drawInventory(state)
    local inventory = state.inventory or {}
    love.graphics.setColor(0.73, 0.80, 0.81)
    love.graphics.print("PHYSICAL PALLET INVENTORY", 92, 202)
    local cards = {
        { label = "RAW PALLETS", value = inventory.rawPallets or 0, x = 92, color = { 0.37, 0.53, 0.63 } },
        { label = "IN PROCESS", value = inventory.inProcessPallets or 0, x = 350, color = { 0.73, 0.52, 0.20 } },
        { label = "FINISHED", value = inventory.finishedPallets or 0, x = 608, color = { 0.20, 0.57, 0.36 } },
    }
    for _, card in ipairs(cards) do
        panel({ x = card.x, y = 234, width = 224, height = 112 },
            { card.color[1] * 0.30, card.color[2] * 0.30, card.color[3] * 0.30, 1 },
            { card.color[1], card.color[2], card.color[3], 1 })
        love.graphics.setColor(0.80, 0.85, 0.85)
        love.graphics.printf(card.label, card.x, 254, 224, "center")
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.printf(tostring(card.value), card.x, 292, 224, "center")
    end
    panel({ x = 92, y = 360, width = 740, height = 274 },
        { 0.06, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
    love.graphics.setColor(0.73, 0.80, 0.81)
    love.graphics.print("SHOP STOCK", 116, 380)
    love.graphics.print("Loose starter sheets", 116, 410)
    love.graphics.print("Finished samples", 116, 438)
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.print(commaNumber(inventory.paper or 0), 330, 410)
    love.graphics.print(commaNumber(inventory.prints or 0), 330, 438)
    local rows = Procurement.inventoryRows(state)
    for index, item in ipairs(rows) do
        local x, y = 116, 468 + (index - 1) * 17
        love.graphics.setColor(0.73, 0.80, 0.81)
        love.graphics.print(item.label, x, y)
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.printf(commaNumber(item.quantity) .. " " .. item.unit, x + 150, y, 150, "right")
    end
    love.graphics.setColor(0.55, 0.63, 0.65)
    love.graphics.print("COMPUTER SUPPLY STORE", RETAIL.x, 366)
    local catalog = retailCatalog()
    local maxPage = math.max(1, math.ceil(#catalog / RETAIL_PAGE_SIZE))
    ComputerScreen.retailPage = math.max(1, math.min(ComputerScreen.retailPage or 1, maxPage))
    local function pageButton(rect, label, enabled)
        love.graphics.setColor(enabled and 0.14 or 0.10, enabled and 0.38 or 0.14, 0.26)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.setColor(enabled and 0.90 or 0.42, enabled and 0.94 or 0.45, enabled and 0.88 or 0.45)
        love.graphics.printf(label, rect.x, rect.y + 7, rect.width, "center")
    end
    pageButton(RETAIL_PREVIOUS, "<", ComputerScreen.retailPage > 1)
    pageButton(RETAIL_NEXT, ">", ComputerScreen.retailPage < maxPage)
    love.graphics.setColor(0.55, 0.63, 0.65)
    love.graphics.printf(string.format("%d/%d", ComputerScreen.retailPage, maxPage), 660, 361, 52, "right")
    local first = (ComputerScreen.retailPage - 1) * RETAIL_PAGE_SIZE + 1
    for visibleIndex = 1, RETAIL_PAGE_SIZE do
        local offer = catalog[first + visibleIndex - 1]
        if not offer then break end
        local item, buy = offer.item, retailBuyRect(visibleIndex)
        local y = RETAIL.y + (visibleIndex - 1) * (RETAIL.rowHeight + RETAIL.gap)
        love.graphics.setColor(0.11, 0.14, 0.16, 1)
        love.graphics.rectangle("fill", RETAIL.x, y, RETAIL.width, RETAIL.rowHeight, 3, 3)
        love.graphics.setColor(0.78, 0.84, 0.84)
        love.graphics.printf(item.retailName, RETAIL.x + 10, y + 7, RETAIL.width - 122, "left")
        love.graphics.setColor(0.48, 0.58, 0.59)
        love.graphics.print("Salesman bulk: $" .. item.price, RETAIL.x + 10, y + 25)
        local affordable = (state.money or 0) >= item.retailPrice
        love.graphics.setColor(affordable and { 0.18, 0.43, 0.29, 1 } or { 0.19, 0.20, 0.20, 1 })
        love.graphics.rectangle("fill", buy.x, buy.y, buy.width, buy.height, 3, 3)
        love.graphics.setColor(affordable and { 0.95, 0.97, 0.93, 1 } or { 0.52, 0.55, 0.54, 1 })
        love.graphics.printf("$" .. item.retailPrice, buy.x, buy.y + 16, buy.width, "center")
    end
end

local function conditionColor(condition)
    if condition >= 75 then return 0.35, 0.78, 0.48 end
    if condition >= 55 then return 0.88, 0.70, 0.25 end
    return 0.90, 0.35, 0.24
end

local function drawOnline(state, pointerX, pointerY)
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.print("PICTURE SHOP ONLINE • INDUSTRIAL EQUIPMENT", 92, 194)
    love.graphics.setColor(0.63, 0.72, 0.74)
    love.graphics.print("Inspected machines arrive in stronger condition by flatbed and must be unloaded.", 92, 216)
    love.graphics.print("ONLINE LISTINGS", MACHINE_OFFER.x, 244)
    for index, offer in ipairs(MachineFleet.offers("online")) do
        local y = MACHINE_OFFER.y + (index - 1) * (MACHINE_OFFER.height + MACHINE_OFFER.gap)
        local buy = machineBuyRect(index)
        panel({ x = MACHINE_OFFER.x, y = y, width = MACHINE_OFFER.width, height = MACHINE_OFFER.height },
            { 0.06, 0.09, 0.12, 1 }, { 0.24, 0.40, 0.46, 1 })
        love.graphics.setColor(0.92, 0.95, 0.93)
        love.graphics.print(offer.name, MACHINE_OFFER.x + 12, y + 12)
        local red, green, blue = conditionColor(offer.condition)
        love.graphics.setColor(red, green, blue)
        love.graphics.print(string.format("%s • %.0f%% condition", offer.conditionStatus, offer.condition),
            MACHINE_OFFER.x + 12, y + 38)
        love.graphics.setColor(0.58, 0.67, 0.69)
        love.graphics.print("Professionally inspected", MACHINE_OFFER.x + 12, y + 62)
        local affordable = (state.money or 0) >= offer.price
        love.graphics.setColor(affordable and { 0.15, 0.44, 0.29, 1 } or { 0.17, 0.18, 0.19, 1 })
        love.graphics.rectangle("fill", buy.x, buy.y, buy.width, buy.height, 3, 3)
        love.graphics.setColor(affordable and { 0.96, 0.98, 0.94, 1 } or { 0.52, 0.55, 0.54, 1 })
        love.graphics.printf(money(offer.price), buy.x, buy.y + 16, buy.width, "center")
    end

    love.graphics.setColor(0.63, 0.72, 0.74)
    love.graphics.print("YOUR MACHINES", OWNED_MACHINE.x, 244)
    local owned = MachineFleet.owned(state)
    if #owned == 0 then
        love.graphics.setColor(0.52, 0.60, 0.62)
        love.graphics.printf("No machines owned. Buy a unit to install it in the shop.",
            OWNED_MACHINE.x, 320, OWNED_MACHINE.width, "center")
    end
    for index, item in ipairs(owned) do
        if index > 4 then break end
        local y = OWNED_MACHINE.y + (index - 1) * (OWNED_MACHINE.height + OWNED_MACHINE.gap)
        local sell = machineSellRect(index)
        local condition = MachineFleet.condition(item)
        local weakest = MachineFleet.weakestComponent(item)
        panel({ x = OWNED_MACHINE.x, y = y, width = OWNED_MACHINE.width, height = OWNED_MACHINE.height },
            { 0.065, 0.085, 0.10, 1 }, { 0.22, 0.34, 0.38, 1 })
        love.graphics.setColor(0.92, 0.95, 0.93)
        love.graphics.print(item.id .. "  " .. (MachineFleet.definition(item.modelId).shortName),
            OWNED_MACHINE.x + 10, y + 9)
        local red, green, blue = conditionColor(condition)
        love.graphics.setColor(red, green, blue)
        love.graphics.print(string.format("%s %.1f%% • %s", MachineFleet.conditionStatus(condition),
            condition, item.status:upper()), OWNED_MACHINE.x + 10, y + 30)
        love.graphics.setColor(0.55, 0.64, 0.66)
        love.graphics.print(string.format("Weakest: %s %.0f%% • %d cycles", weakest.label,
            weakest.value, item.cycles), OWNED_MACHINE.x + 10, y + 50)
        love.graphics.setColor(0.40, 0.20, 0.18, 1)
        love.graphics.rectangle("fill", sell.x, sell.y, sell.width, sell.height, 3, 3)
        love.graphics.setColor(0.96, 0.91, 0.88)
        love.graphics.printf("SELL\n" .. money(MachineFleet.resaleValue(item, "online")),
            sell.x, sell.y + 4, sell.width, "center")
    end
    love.graphics.setColor(0.55, 0.63, 0.65)
    love.graphics.printf("Additional units are stored automatically. Selling an installed unit promotes a stored unit of the same model.",
        92, 574, 748, "center")
end

local function drawBills(state, pointerX, pointerY)
    local charges, monthlyTotal = BusinessCalendar.monthlyCharges()
    local balance = state.bills and state.bills.balance or 0
    panel({ x = 82, y = 190, width = 770, height = 408 },
        { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.print("MONTHLY OPERATING BILLS", 108, 214)
    love.graphics.setColor(0.76, 0.83, 0.84)
    love.graphics.print(BusinessCalendar.dateText(state), 108, 242)
    love.graphics.print("One game day lasts 5 real minutes. A new invoice posts on the first of each month.", 108, 266)

    love.graphics.setColor(0.16, 0.22, 0.24)
    love.graphics.rectangle("fill", 108, 302, 470, 28)
    love.graphics.setColor(0.86, 0.89, 0.88)
    love.graphics.print("EXPENSE", 122, 310)
    love.graphics.print("FLAT MONTHLY RATE", 408, 310)
    for index, charge in ipairs(charges) do
        local y = 330 + (index - 1) * 34
        love.graphics.setColor(index % 2 == 0 and 0.085 or 0.105, 0.12, 0.14, 1)
        love.graphics.rectangle("fill", 108, y, 470, 32)
        love.graphics.setColor(0.78, 0.84, 0.84)
        love.graphics.print(charge.label, 122, y + 9)
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.printf(money(charge.amount), 402, y + 9, 150, "right")
    end
    love.graphics.setColor(0.72, 0.79, 0.80)
    love.graphics.print("Normal monthly total", 122, 478)
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.printf(money(monthlyTotal), 402, 478, 150, "right")

    panel({ x = 604, y = 302, width = 204, height = 188 },
        { 0.08, 0.10, 0.11, 1 }, { 0.31, 0.48, 0.49, 1 })
    love.graphics.setColor(0.72, 0.79, 0.80)
    love.graphics.printf("TOTAL CURRENTLY DUE", 620, 330, 172, "center")
    love.graphics.setColor(balance > 0 and 0.96 or 0.54, balance > 0 and 0.48 or 0.84, balance > 0 and 0.30 or 0.65)
    love.graphics.printf(money(balance), 620, 370, 172, "center")
    love.graphics.setColor(0.58, 0.66, 0.67)
    love.graphics.printf(balance > 0 and "Unpaid invoices carry forward." or "All operating bills are paid.",
        620, 410, 172, "center")

    local payable = balance > 0 and (state.money or 0) >= balance
    local hovered = payable and pointerX and contains(PAY_BILLS, pointerX, pointerY)
    love.graphics.setColor(payable and (hovered and 0.19 or 0.12) or 0.13,
        payable and (hovered and 0.55 or 0.42) or 0.16, payable and 0.29 or 0.17)
    love.graphics.rectangle("fill", PAY_BILLS.x, PAY_BILLS.y, PAY_BILLS.width, PAY_BILLS.height, 3, 3)
    love.graphics.setColor(payable and 0.95 or 0.50, payable and 0.96 or 0.53, payable and 0.93 or 0.53)
    love.graphics.printf(balance <= 0 and "NO BALANCE DUE" or payable and "PAY ALL BILLS" or "INSUFFICIENT CASH",
        PAY_BILLS.x, PAY_BILLS.y + 16, PAY_BILLS.width, "center")
end

local function drawEmail(state, pointerX, pointerY, assets)
    local inbox = JobService.emailInbox(state)
    panel({ x = 82, y = 190, width = 310, height = 408 },
        { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
    panel({ x = 412, y = 190, width = 440, height = 408 },
        { 0.065, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.print("RETURNING CLIENT INBOX", 96, 202)
    if ComputerScreen.promoJobId then
        local source = findJob(state.jobs.completed or {}, ComputerScreen.promoJobId)
        love.graphics.setColor(0.66, 0.74, 0.75)
        love.graphics.printf("Promotion composer open for a completed client.", 106, 252, 262, "center")
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.print("NEW RETURNING-CLIENT PROMOTION", 434, 212)
        love.graphics.setColor(0.76, 0.83, 0.84)
        love.graphics.print("TO: " .. tostring(source and source.company or "--"), 434, 246)
        love.graphics.printf(source and source.press
            and "We'd like to offer you 10% off your next custom printing job."
            or "We'd like to offer you 10% off your next paper-cutting job.",
            434, 278, 392, "left")
        love.graphics.setColor(0.58, 0.67, 0.68)
        love.graphics.print("ADD YOUR OWN MESSAGE", 434, 320)
        love.graphics.setColor(ComputerScreen.promoFocused and 0.08 or 0.06, 0.12, 0.14, 1)
        love.graphics.rectangle("fill", PROMO_INPUT.x, PROMO_INPUT.y,
            PROMO_INPUT.width, PROMO_INPUT.height, 3, 3)
        love.graphics.setColor(ComputerScreen.promoFocused and 0.46 or 0.25,
            ComputerScreen.promoFocused and 0.75 or 0.40, 0.48, 1)
        love.graphics.rectangle("line", PROMO_INPUT.x, PROMO_INPUT.y,
            PROMO_INPUT.width, PROMO_INPUT.height, 3, 3)
        love.graphics.setColor(0.88, 0.91, 0.89)
        local custom = ComputerScreen.promoText
        if custom == "" then custom = "Click here and type an optional personal note." end
        love.graphics.printf(custom .. (ComputerScreen.promoFocused and "_" or ""),
            PROMO_INPUT.x + 10, PROMO_INPUT.y + 10, PROMO_INPUT.width - 20, "left")
        local function promoButton(rect, label, green)
            local hovered = pointerX and contains(rect, pointerX, pointerY)
            love.graphics.setColor(green and 0.12 or 0.45, green and (hovered and 0.55 or 0.43) or 0.18, 0.25)
            love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
            love.graphics.setColor(0.97, 0.98, 0.95)
            love.graphics.printf(label, rect.x, rect.y + 15, rect.width, "center")
        end
        promoButton(EMAIL_DECLINE, "CANCEL", false)
        promoButton(PROMO, "SEND 10% OFFER", true)
        return
    end
    if #inbox == 0 then
        love.graphics.setColor(0.58, 0.66, 0.67)
        love.graphics.printf("No new requests. Clients can email again after you complete and deliver their first job.",
            106, 332, 262, "center")
        love.graphics.printf("Pending follow-ups: " .. tostring(#((state.clientEmails or {}).pending or {})),
            106, 402, 262, "center")
        return
    end
    local selected
    for row, email in ipairs(inbox) do
        local rect = { x = 94, y = 238 + (row - 1) * 54, width = 280, height = 46 }
        if email.id == ComputerScreen.selectedEmailId then selected = email end
        local active = email.id == ComputerScreen.selectedEmailId
        local hovered = pointerX and contains(rect, pointerX, pointerY)
        love.graphics.setColor(active and 0.15 or hovered and 0.12 or 0.08,
            active and 0.39 or hovered and 0.28 or 0.13,
            active and 0.38 or hovered and 0.27 or 0.17)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 2, 2)
        love.graphics.setColor(0.92, 0.94, 0.92)
        love.graphics.print(email.sender, rect.x + 8, rect.y + 7)
        love.graphics.setColor(0.62, 0.70, 0.71)
        love.graphics.print(email.subject, rect.x + 8, rect.y + 24)
    end
    selected = selected or inbox[1]
    if not selected then return end
    love.graphics.setColor(0.96, 0.84, 0.30)
    love.graphics.print("FROM: " .. selected.sender, 434, 212)
    love.graphics.setColor(0.72, 0.79, 0.80)
    love.graphics.print("SUBJECT: " .. selected.subject, 434, 238)
    love.graphics.printf(selected.body, 434, 270, 392, "left")
    if selected.serviceNotice then
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.print("CUTTER BLADE SERVICE UPDATE", 434, 392)
        love.graphics.setColor(0.66, 0.75, 0.76)
        love.graphics.printf("This is an automated maintenance message from your blade technician.",
            434, 424, 392, "left")
        local hovered = pointerX and contains(EMAIL_DECLINE, pointerX, pointerY)
        love.graphics.setColor(hovered and 0.18 or 0.12, hovered and 0.48 or 0.36, 0.29)
        love.graphics.rectangle("fill", EMAIL_DECLINE.x, EMAIL_DECLINE.y,
            EMAIL_DECLINE.width, EMAIL_DECLINE.height, 3, 3)
        love.graphics.setColor(0.96, 0.98, 0.95)
        love.graphics.printf("ARCHIVE NOTICE", EMAIL_DECLINE.x, EMAIL_DECLINE.y + 15,
            EMAIL_DECLINE.width, "center")
        return
    end
    local job = selected.job
    love.graphics.setColor(0.86, 0.89, 0.88)
    love.graphics.print("PROPOSED JOB  " .. job.id, 434, 320)
    love.graphics.print(string.format("Sheets: %g × %g in → %g × %g in",
        job.sourceSize.width, job.sourceSize.height, job.finishedSize.width, job.finishedSize.height), 434, 344)
    love.graphics.printf("Paper: " .. (job.stockSpec and job.stockSpec.description
        or job.details and job.details.stockDescription or "Customer supplied"), 434, 364,
        job.press and 292 or 392, "left")
    if job.press then
        love.graphics.print(string.format("Order: %s good / %s supplied",
            commaNumber(job.quote.orderedCopies or job.press.orderedQuantity),
            commaNumber(job.quote.suppliedSheets or job.quote.totalSheets)), 434, 386)
        love.graphics.printf("Packaging: " .. ComputerScreen.packagingText(job), 434, 406, 292, "left")
        love.graphics.printf(string.format("Press: %d color%s • %s", job.press.colors or 1,
            (job.press.colors or 1) == 1 and "" or "s",
            table.concat(job.press.colorSequence or { "Black" }, " → ")), 434, 426, 292, "left")
        drawArtworkPreview(assets, job, 766, 330, 48)
    else
        love.graphics.print(string.format("%d pallet%s   %s sheets",
            job.quote.palletCount, job.quote.palletCount == 1 and "" or "s",
            commaNumber(job.quote.totalSheets)), 434, 386)
        love.graphics.printf("Packaging: " .. ComputerScreen.packagingText(job), 434, 406, 392, "left")
    end
    love.graphics.print("Stock arrival: " .. JobService.deliverySummary(job), 434, 446)
    local terms = JobService.quoteTerms(state, job, tonumber(ComputerScreen.quoteText))
    love.graphics.setColor(0.58, 0.67, 0.68)
    love.graphics.print("YOUR QUOTE", EMAIL_QUOTE_INPUT.x, 454)
    love.graphics.printf("Recommended " .. money(terms and terms.recommendedPrice or job.quote.totalPrice),
        EMAIL_QUOTE_INPUT.x + 196, 454, 196, "right")
    love.graphics.setColor(0.06, 0.11, 0.13, 1)
    love.graphics.rectangle("fill", EMAIL_QUOTE_INPUT.x, EMAIL_QUOTE_INPUT.y,
        EMAIL_QUOTE_INPUT.width, EMAIL_QUOTE_INPUT.height, 3, 3)
    love.graphics.setColor(ComputerScreen.quoteFocused and 0.48 or 0.28,
        ComputerScreen.quoteFocused and 0.77 or 0.43, 0.50, 1)
    love.graphics.rectangle("line", EMAIL_QUOTE_INPUT.x, EMAIL_QUOTE_INPUT.y,
        EMAIL_QUOTE_INPUT.width, EMAIL_QUOTE_INPUT.height, 3, 3)
    love.graphics.setColor(0.96, 0.96, 0.92)
    love.graphics.print("$", EMAIL_QUOTE_INPUT.x + 10, EMAIL_QUOTE_INPUT.y + 13)
    love.graphics.printf(ComputerScreen.quoteText .. (ComputerScreen.quoteFocused and "_" or ""),
        EMAIL_QUOTE_INPUT.x + 28, EMAIL_QUOTE_INPUT.y + 13,
        EMAIL_QUOTE_INPUT.width - 38, "right")

    local function responseButton(rect, label, green)
        local hovered = pointerX and contains(rect, pointerX, pointerY)
        love.graphics.setColor(green and (hovered and 0.18 or 0.12) or (hovered and 0.70 or 0.57),
            green and (hovered and 0.55 or 0.43) or 0.18, green and 0.28 or 0.17)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.setColor(0.98, 0.98, 0.96)
        love.graphics.printf(label, rect.x, rect.y + 15, rect.width, "center")
    end
    responseButton(EMAIL_DECLINE, "DECLINE REQUEST", false)
    responseButton(EMAIL_ACCEPT, "SEND QUOTE", true)
end

local function drawCalendar(state, pointerX, pointerY)
    local year = ComputerScreen.calendarYear or state.calendar.year
    local month = ComputerScreen.calendarMonth or state.calendar.month
    panel({ x = 82, y = 190, width = 516, height = 408 },
        { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
    panel({ x = 612, y = 190, width = 240, height = 408 },
        { 0.065, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
    local function navButton(rect, label)
        local hovered = pointerX and contains(rect, pointerX, pointerY)
        love.graphics.setColor(hovered and 0.16 or 0.10, hovered and 0.40 or 0.25, 0.28)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.setColor(0.92, 0.95, 0.93)
        love.graphics.printf(label, rect.x, rect.y + 9, rect.width, "center")
    end
    navButton(CAL_PREVIOUS, "<")
    navButton(CAL_NEXT, ">")
    love.graphics.setColor(0.96, 0.84, 0.30)
    love.graphics.printf(string.upper(BusinessCalendar.monthName(month)) .. " " .. year,
        146, 210, 388, "center")
    local weekdayLabels = { "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN" }
    local gridX, gridY, cellW, cellH = CAL_GRID.x, CAL_GRID.y - 24,
        CAL_GRID.cellWidth, CAL_GRID.cellHeight
    for index, label in ipairs(weekdayLabels) do
        love.graphics.setColor(index > 5 and 0.66 or 0.76, 0.78, 0.79)
        love.graphics.printf(label, gridX + (index - 1) * cellW, gridY, cellW, "center")
    end
    local firstTotal = BusinessCalendar.totalDayForDate(year, month, 1)
    local firstDate = BusinessCalendar.dateFromTotalDay(firstTotal or 0)
    local firstColumn = firstDate.weekday
    local events = calendarMonthEvents(state, year, month)
    local eventsByDay = {}
    for _, event in ipairs(events) do
        eventsByDay[event.day] = eventsByDay[event.day] or {}
        eventsByDay[event.day][#eventsByDay[event.day] + 1] = event
    end
    for day = 1, BusinessCalendar.daysInMonth(year, month) do
        local cellIndex = firstColumn - 1 + day - 1
        local column, row = cellIndex % 7, math.floor(cellIndex / 7)
        local x, y = gridX + column * cellW, CAL_GRID.y + row * cellH
        local today = year == state.calendar.year and month == state.calendar.month and day == state.calendar.day
        local selected = day == ComputerScreen.calendarSelectedDay
        local hovered = pointerX and contains(calendarDayRect(year, month, day), pointerX, pointerY)
        love.graphics.setColor(selected and 0.13 or (today and 0.12 or (hovered and 0.10 or 0.075)),
            selected and 0.43 or (today and 0.37 or (hovered and 0.20 or 0.11)),
            selected and 0.42 or (today and 0.36 or (hovered and 0.22 or 0.13)), 1)
        love.graphics.rectangle("fill", x + 2, y + 2, cellW - 4, cellH - 4, 2, 2)
        if selected or hovered then
            love.graphics.setColor(selected and 0.96 or 0.42, selected and 0.84 or 0.70, selected and 0.30 or 0.72, 1)
            love.graphics.rectangle("line", x + 2, y + 2, cellW - 4, cellH - 4, 2, 2)
        end
        love.graphics.setColor(today and 0.96 or 0.78, today and 0.84 or 0.84, today and 0.30 or 0.83)
        love.graphics.print(tostring(day), x + 7, y + 6)
        local dayEvents = eventsByDay[day] or {}
        for marker = 1, math.min(4, #dayEvents) do
            local event = dayEvents[marker]
            if event.kind == "bill" then love.graphics.setColor(0.93, 0.34, 0.25)
            elseif event.kind == "machine" then love.graphics.setColor(0.76, 0.55, 0.94)
            elseif event.kind == "email" then love.graphics.setColor(0.32, 0.72, 0.92)
            else love.graphics.setColor(0.30, 0.78, 0.48) end
            love.graphics.circle("fill", x + 10 + (marker - 1) * 12, y + 39, 4)
        end
    end
    love.graphics.setColor(0.96, 0.84, 0.30)
    love.graphics.print("MONTH EVENTS", 628, 210)
    local _, maximumScroll = clampCalendarScroll(state)
    local visibleCount = 0
    for row = 1, CAL_EVENT_LIST.visibleRows do
        local event = events[ComputerScreen.calendarScroll + row]
        if event then
            visibleCount = visibleCount + 1
            local y = CAL_EVENT_LIST.y + (row - 1) * CAL_EVENT_LIST.rowHeight
            local selected = event.day == ComputerScreen.calendarSelectedDay
            love.graphics.setColor(0.10, 0.14, 0.16, 1)
            if selected then love.graphics.setColor(0.12, 0.29, 0.30, 1) end
            love.graphics.rectangle("fill", CAL_EVENT_LIST.x, y, CAL_EVENT_LIST.width, 31, 2, 2)
            love.graphics.setColor(0.95, 0.84, 0.30)
            love.graphics.print(tostring(event.day), 632, y + 8)
            love.graphics.setColor(0.80, 0.86, 0.85)
            love.graphics.printf(event.title, 656, y + 5, 176, "left")
        end
    end
    if visibleCount == 0 then
        love.graphics.setColor(0.56, 0.64, 0.65)
        love.graphics.printf("No scheduled events this month.", 628, 340, 208, "center")
    end
    local function scrollButton(rect, label, enabled)
        local hovered = enabled and pointerX and contains(rect, pointerX, pointerY)
        love.graphics.setColor(enabled and (hovered and 0.16 or 0.10) or 0.06,
            enabled and (hovered and 0.40 or 0.25) or 0.09, enabled and 0.28 or 0.10, 1)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.setColor(enabled and 0.90 or 0.38, enabled and 0.94 or 0.43, enabled and 0.92 or 0.44)
        love.graphics.printf(label, rect.x, rect.y + 8, rect.width, "center")
    end
    scrollButton(CAL_SCROLL_UP, "UP", ComputerScreen.calendarScroll > 0)
    scrollButton(CAL_SCROLL_DOWN, "DOWN", ComputerScreen.calendarScroll < maximumScroll)

    local hoverDay = pointerX and calendarDayAt(year, month, pointerX, pointerY)
    if hoverDay then
        local dayEvents = eventsByDay[hoverDay] or {}
        local shown = math.min(6, #dayEvents)
        local tooltipWidth = 440
        local font, contentWidth = love.graphics.getFont(), 406
        local rows, rowsHeight = {}, 0
        for index = 1, shown do
            local event = dayEvents[index]
            local _, titleLines = font:getWrap("• " .. tostring(event.title), contentWidth)
            local detailLines = {}
            if event.detail and event.detail ~= "" then
                _, detailLines = font:getWrap(tostring(event.detail), contentWidth - 12)
            end
            local height = math.max(22, #titleLines * font:getHeight()
                + #detailLines * font:getHeight() + 7)
            rows[index] = { event = event, height = height }
            rowsHeight = rowsHeight + height
        end
        local tooltipHeight = 48 + math.max(30, rowsHeight) + (#dayEvents > shown and 22 or 0)
        local tx = math.min(Config.baseWidth - tooltipWidth - 12, pointerX + 16)
        local ty = math.min(Config.baseHeight - tooltipHeight - 12, pointerY + 18)
        panel({ x = tx, y = ty, width = tooltipWidth, height = tooltipHeight },
            { 0.025, 0.04, 0.05, 0.98 }, { 0.42, 0.70, 0.72, 1 })
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.print(string.format("%s %d, %d", BusinessCalendar.monthName(month), hoverDay, year), tx + 12, ty + 11)
        if #dayEvents == 0 then
            love.graphics.setColor(0.65, 0.72, 0.73)
            love.graphics.print("No scheduled events", tx + 12, ty + 46)
        else
            local rowY = ty + 40
            for index = 1, shown do
                local row, event = rows[index], rows[index].event
                love.graphics.setColor(0.84, 0.90, 0.88)
                love.graphics.printf("• " .. event.title, tx + 12, rowY, contentWidth, "left")
                if event.detail and event.detail ~= "" then
                    local _, titleLines = font:getWrap("• " .. tostring(event.title), contentWidth)
                    love.graphics.setColor(0.56, 0.66, 0.67)
                    love.graphics.printf(tostring(event.detail), tx + 24,
                        rowY + #titleLines * font:getHeight(), contentWidth - 12, "left")
                end
                rowY = rowY + row.height
            end
            if #dayEvents > shown then
                love.graphics.setColor(0.65, 0.72, 0.73)
                love.graphics.print("+" .. (#dayEvents - shown) .. " more", tx + 12, ty + tooltipHeight - 21)
            end
        end
    end
end

function ComputerScreen.draw(state, pointerX, pointerY, assets)
    love.graphics.setColor(0.01, 0.02, 0.03, 0.76)
    love.graphics.rectangle("fill", 0, 0, Config.baseWidth, Config.baseHeight)
    panel(PANEL, { 0.035, 0.05, 0.065, 0.99 }, { 0.31, 0.56, 0.58, 1 })
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.print("PICTURE SHOP JOB DESK", 82, 54)
    love.graphics.setColor(0.72, 0.79, 0.80)
    love.graphics.print("Cash", 82, 88)
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.print(money(state.money), 128, 88)
    love.graphics.setColor(0.72, 0.79, 0.80)
    love.graphics.print("Accounts receivable", 250, 88)
    love.graphics.setColor(0.54, 0.84, 0.65)
    love.graphics.print(money(state.accountsReceivable), 390, 88)
    love.graphics.setColor(0.72, 0.79, 0.80)
    love.graphics.print("Active jobs", 570, 88)
    love.graphics.setColor(0.90, 0.92, 0.90)
    love.graphics.print(tostring(#(state.jobs.active or {})), 655, 88)
    love.graphics.setColor(0.72, 0.79, 0.80)
    love.graphics.print(BusinessCalendar.shortDate(state), 700, 88)

    BackButton.draw(assets, CLOSE, "BACK", pointerX, pointerY, false)

    drawTabs(pointerX, pointerY)
    if ComputerScreen.tab == "inventory" then
        drawInventory(state)
    elseif ComputerScreen.tab == "online" then
        drawOnline(state, pointerX, pointerY)
    elseif ComputerScreen.tab == "email" then
        drawEmail(state, pointerX, pointerY, assets)
    elseif ComputerScreen.tab == "calendar" then
        drawCalendar(state, pointerX, pointerY)
    elseif ComputerScreen.tab == "bills" then
        drawBills(state, pointerX, pointerY)
    else
        drawJobList(state, pointerX, pointerY)
        drawDetail(state, pointerX, pointerY, assets)
    end
end

return ComputerScreen
