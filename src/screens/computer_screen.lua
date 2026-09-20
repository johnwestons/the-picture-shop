local function create(dependencies)
dependencies = dependencies or {}
local Config = require("src.config")
local BusinessCalendar = require("src.business_calendar")
local JobService = require("src.job_service")
local MachineFleet = require("src.machine_fleet")
local Procurement = require("src.procurement")
local BackButton = require("src.screens.back_button")
local StatusLabels = require("src.status_labels")
local Ui = require("src.screens.ui")
local utf8 = require("utf8")
local Reputation = require("src.reputation")
local Upgrades = require("src.warehouse_upgrades")
local OfficeIntent = require("src.office_intent")
local warehouseRequestPrefix=dependencies.warehouseRequestPrefix

local ComputerScreen = {
    tab = "active",
    selectedJobId = nil,
    selectedEmailId = nil,
    emailPage = 1,
    emailSelectionRequired = false,
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
    wwwSite = 1,
    cart = {},
    cartOpen = false,
    cartPage = 1,
    wwwSiteChangedAt = 0,
    tabDropdownOpen = false,
    warehouseConfirmation = nil,
    warehousePending = false,
    warehouseMessage = nil,
    warehouseRequestNumber = 0,
}

local PANEL = { x = 52, y = 34, width = 856, height = 610 }
local CLOSE = { x = 756, y = 48, width = 132, height = 40 }
local TABS = {
    { id = "active", label = "ACTIVE JOBS", url = "www.thecritternet.com/job-desk/active" },
    { id = "completed", label = "COMPLETED JOBS", url = "www.thecritternet.com/job-desk/completed" },
    { id = "deliveries", label = "DELIVERIES", url = "www.thecritternet.com/job-desk/deliveries" },
    { id = "estimating", label = "ESTIMATING", url = "www.thecritternet.com/job-desk/estimating" },
    { id = "calendar", label = "CALENDAR", url = "www.thecritternet.com/job-desk/calendar" },
    { id = "inventory", label = "INVENTORY", url = "www.thecritternet.com/job-desk/inventory" },
    { id = "www", label = "CRITTERNET WWW", url = "www.thecritternet.com" },
    { id = "email", label = "EMAIL", url = "www.thecritternet.com/job-desk/email" },
    { id = "bills", label = "BILLS", url = "www.thecritternet.com/job-desk/bills" },
    { id = "warehouse", label = "WAREHOUSE", url = "www.thecritternet.com/warehouse" },
}
local TAB_ADDRESS = { x = 170, y = 136, width = 478, height = 40 }
local TAB_DROPDOWN_ARROW = { x = 648, y = 136, width = 40, height = 40 }
local TAB_DROPDOWN = { x = 170, y = 179, width = 518, rowHeight = 39 }
local LIST = { x = 82, y = 190, width = 310, height = 370 }
local DETAIL = { x = 412, y = 190, width = 440, height = 444 }
local PREVIOUS = { x = 82, y = 570, width = 86, height = 30 }
local NEXT = { x = 306, y = 570, width = 86, height = 30 }
local COMPLETE = { x = 598, y = 598, width = 228, height = 36 }
local MONITOR = { x = 16, y = 8, width = 928, height = 660 }
local WWW_SITE = { x = 92, y = 238, width = 140, height = 42, gap = 8 }
local WWW_PRODUCT = { x = 92, y = 296, width = 748, rowHeight = 52, gap = 6 }
local WWW_SITES = {
    { name = "PAPER DEPOT", short = "PAPER", url = "www.thecritternet.com/paper-depot", categoryIndex = 1 },
    { name = "PRESSROOM SUPPLY", short = "PRESS", url = "www.thecritternet.com/pressroom", categoryIndex = 2 },
    { name = "CARTON & WRAP", short = "PACKING", url = "www.thecritternet.com/cartons", categoryIndex = 3 },
    { name = "WRENCHWORKS", short = "TOOLS", url = "www.thecritternet.com/tools", categoryIndex = 4 },
    { name = "MACHINE MARKET", short = "MACHINES", url = "www.thecritternet.com/machines", kind = "machines" },
}
local CART_BUTTON = { x = 714, y = 194, width = 126, height = 36 }
local CART_BACK = { x = 102, y = 548, width = 126, height = 40 }
local CART_CLEAR = { x = 244, y = 548, width = 126, height = 40 }
local CART_CHECKOUT = { x = 630, y = 548, width = 190, height = 40 }
local CART_PREVIOUS = { x = 400, y = 552, width = 42, height = 32 }
local CART_NEXT = { x = 514, y = 552, width = 42, height = 32 }
local CART_PAGE_SIZE = 7
local PAY_BILLS = { x = 612, y = 522, width = 196, height = 46 }
local EMAIL_QUOTE_INPUT = { x = 434, y = 470, width = 190, height = 40 }
local EMAIL_ACCEPT = { x = 640, y = 470, width = 186, height = 40 }
local EMAIL_DECLINE = { x = 434, y = 526, width = 186, height = 44 }
local EMAIL_PREVIOUS = { x = 94, y = 562, width = 82, height = 28 }
local EMAIL_NEXT = { x = 292, y = 562, width = 82, height = 28 }
local EMAIL_PAGE_SIZE = 6
local PROMO = { x = 640, y = 526, width = 186, height = 44 }
local JOB_PROMO = { x = 640, y = 590, width = 186, height = 44 }
local PROMO_INPUT = { x = 434, y = 338, width = 392, height = 122 }
local CAL_PREVIOUS = { x = 96, y = 202, width = 42, height = 30 }
local CAL_NEXT = { x = 542, y = 202, width = 42, height = 30 }
local CAL_GRID = { x = 94, y = 272, cellWidth = 70, cellHeight = 54 }
local CAL_EVENT_LIST = { x = 624, y = 240, width = 216, rowHeight = 34, visibleRows = 9 }
local CAL_SCROLL_UP = { x = 624, y = 558, width = 102, height = 28 }
local CAL_SCROLL_DOWN = { x = 738, y = 558, width = 102, height = 28 }
local MACHINE_OFFER = { x = 92, y = 296, width = 354, height = 82, gap = 10 }
local OWNED_MACHINE = { x = 486, y = 296, width = 354, height = 64, gap = 8 }
local ROW_HEIGHT = 46
local JOBS_PER_PAGE = 7

local contains, commaNumber, money = Ui.contains, Ui.commaNumber, Ui.money

local WAREHOUSE_BAYS = { "front_left", "front_right" }
local WAREHOUSE_OPTIONS = { "floor", "storage", "breakroom" }
local WAREHOUSE_FORKLIFT = {x=670,y=490,width=164,height=40}
local WAREHOUSE_CONFIRM = {x=508,y=514,width=228,height=40}
local WAREHOUSE_CANCEL = {x=216,y=514,width=180,height=40}
local WAREHOUSE_ACK = {x=206,y=430,width=542,height=48}

local function warehouseEnabled()
    return dependencies.warehouseEnabled == true
        or (type(dependencies.warehouseEnabled) == "function" and dependencies.warehouseEnabled() == true)
end

local function warehouseOptionAvailable(bayId,optionId)
    return dependencies.warehouseFirstStorageOnly~=true
        or (bayId=="front_left" and optionId=="storage")
end

local function visibleTabs()
    local result = {}
    for _,tab in ipairs(TABS) do
        if tab.id ~= "warehouse" or warehouseEnabled() then result[#result+1] = tab end
    end
    return result
end

local function warehouseOptionRect(bayIndex,optionIndex)
    return {x=96+(bayIndex-1)*380,y=280+(optionIndex-1)*51,width=360,height=43}
end

function ComputerScreen.configureWarehouse(options)
    options=options or {}
    dependencies.warehouseEnabled=options.enabled==true
    dependencies.warehouseCommand=options.command
    dependencies.warehouseFirstStorageOnly=options.firstStorageOnly==true
    if options.requestPrefix then warehouseRequestPrefix=options.requestPrefix end
    if not warehouseEnabled() and ComputerScreen.tab=="warehouse" then ComputerScreen.tab="active" end
    ComputerScreen.warehouseConfirmation,ComputerScreen.warehousePending=nil,false
end

function ComputerScreen.warehouseEnabled() return warehouseEnabled() end

function ComputerScreen.resolveWarehouse(accepted,message)
    ComputerScreen.warehousePending=false
    if accepted then ComputerScreen.warehouseConfirmation=nil end
    ComputerScreen.warehouseMessage=message or (accepted and "Purchase confirmed by the host." or "The purchase was not completed.")
end

function ComputerScreen.warehouseButtonCenter(bayId,optionId)
    local rect
    if bayId=="forklift" then rect=WAREHOUSE_FORKLIFT
    elseif bayId=="confirm" then rect=WAREHOUSE_CONFIRM
    elseif bayId=="cancel" then rect=WAREHOUSE_CANCEL
    elseif bayId=="acknowledge" then rect=WAREHOUSE_ACK
    else
        for bi,bay in ipairs(WAREHOUSE_BAYS) do for oi,option in ipairs(WAREHOUSE_OPTIONS) do
            if bayId==bay and optionId==option then rect=warehouseOptionRect(bi,oi) end
        end end
    end
    if rect then return rect.x+rect.width/2,rect.y+rect.height/2 end
end

function ComputerScreen.warehouseView(state)
    local warehouse=state.warehouse or Upgrades.defaultState()
    local result={enabled=warehouseEnabled(),forkliftOwned=warehouse.forkliftOwned==true,
        forklift=Upgrades.catalog("forklift"),bays={},confirmation=ComputerScreen.warehouseConfirmation,
        pending=ComputerScreen.warehousePending,message=ComputerScreen.warehouseMessage}
    for _,bayId in ipairs(WAREHOUSE_BAYS) do
        local bay=warehouse.bays and warehouse.bays[bayId] or {status="locked"}
        local project
        for _,candidate in ipairs(warehouse.projects or {}) do if candidate.id==bay.projectId then project=candidate end end
        local options={Upgrades.catalog("floor"),Upgrades.catalog("storage"),Upgrades.catalog("breakroom")}
        for index,option in ipairs(options) do
            option.available=warehouseOptionAvailable(bayId,WAREHOUSE_OPTIONS[index])
        end
        result.bays[#result.bays+1]={id=bayId,status=bay.status,optionId=bay.optionId,
            phase=project and project.phase,stage=project and project.stage or 0,options={
                options[1],options[2],options[3]}}
    end
    return result
end

local function warehouseMousepressed(state,x,y)
    if not warehouseEnabled() then return {action="blocked",reason="warehouse_disabled"} end
    if ComputerScreen.warehousePending then return {action="blocked",reason="waiting"} end
    local choice=ComputerScreen.warehouseConfirmation
    if choice then
        if contains(WAREHOUSE_CANCEL,x,y) then ComputerScreen.warehouseConfirmation=nil;return {action="warehouse_cancelled"} end
        if contains(WAREHOUSE_ACK,x,y) and choice.warningRequired then
            choice.confirmUpperRows=not choice.confirmUpperRows
            return {action="warehouse_warning_acknowledged"}
        end
        if not contains(WAREHOUSE_CONFIRM,x,y) then return nil end
        if choice.kind=="buy_upgrade" and not warehouseOptionAvailable(choice.bayId,choice.optionId) then
            ComputerScreen.warehouseMessage="This expansion is not ready in this build. Choose the left storage bay."
            return {action="blocked",reason="warehouse_not_ready"}
        end
        if choice.warningRequired and choice.confirmUpperRows~=true then
            ComputerScreen.warehouseMessage="Acknowledge the forklift requirement before buying these shelves."
            return {action="blocked",reason="forklift_warning_required"}
        end
        local product=Upgrades.catalog(choice.optionId or "forklift")
        if (state.money or 0)<product.price then
            ComputerScreen.warehouseMessage="Not enough money for this purchase."
            return {action="blocked",reason="insufficient_funds"}
        end
        local intent={kind=choice.kind,bayId=choice.bayId,optionId=choice.optionId,requestId=choice.requestId}
        if choice.kind=="buy_upgrade" then intent.confirmUpperRows=choice.confirmUpperRows==true end
        local normalized,errorMessage=OfficeIntent.normalize(intent)
        if not normalized then ComputerScreen.warehouseMessage=errorMessage;return {action="blocked"} end
        local command=dependencies.remoteCommand or dependencies.warehouseCommand
        if type(command)~="function" then
            ComputerScreen.warehouseMessage="Warehouse purchasing is not connected to the host."
            return {action="blocked",reason="warehouse_unwired"}
        end
        ComputerScreen.warehousePending=true
        local called,accepted,code,message=pcall(command,normalized)
        if not called or accepted==false then
            ComputerScreen.resolveWarehouse(false,called and (message or code) or "The purchase could not be sent.")
            return {action="blocked"}
        end
        if not dependencies.remoteCommand and accepted==true then
            ComputerScreen.resolveWarehouse(true,message)
            return {action="warehouse_purchased",hostSaved=true}
        end
        return {action="remote_pending"}
    end
    local view=ComputerScreen.warehouseView(state)
    local kind,bayId,optionId
    for bi,bay in ipairs(view.bays) do for oi,option in ipairs(WAREHOUSE_OPTIONS) do
        if contains(warehouseOptionRect(bi,oi),x,y) and bay.status=="locked" then
            if not warehouseOptionAvailable(bay.id,option) then
                ComputerScreen.warehouseMessage="This expansion is not ready in this build. Choose the left storage bay."
                return {action="blocked",reason="warehouse_not_ready"}
            end
            kind,bayId,optionId="buy_upgrade",bay.id,option
        end
    end end
    if contains(WAREHOUSE_FORKLIFT,x,y) and not view.forkliftOwned then kind="buy_forklift" end
    if not kind then return nil end
    ComputerScreen.warehouseRequestNumber=ComputerScreen.warehouseRequestNumber+1
    local warehouse=state.warehouse or Upgrades.defaultState()
    local receiptCount=#(warehouse.receipts or {})
    warehouseRequestPrefix=tostring(warehouseRequestPrefix
        or ("WH-"..os.time().."-"..math.random(1,99999999))):gsub("[^%w_.%-]","-"):sub(1,40)
    local identifier=string.format("%s-%d-%d",warehouseRequestPrefix,receiptCount,ComputerScreen.warehouseRequestNumber)
    ComputerScreen.warehouseConfirmation={kind=kind,bayId=bayId,optionId=optionId,requestId=identifier,
        warningRequired=optionId=="storage" and not view.forkliftOwned,confirmUpperRows=false}
    ComputerScreen.warehouseMessage=nil
    return {action="warehouse_confirmation"}
end

local function tabById(tabId)
    if tabId == "online" then tabId = "www" end
    for _, tab in ipairs(visibleTabs()) do
        if tab.id == tabId then return tab end
    end
end

local function tabDropdownRect(index)
    return {
        x = TAB_DROPDOWN.x,
        y = TAB_DROPDOWN.y + (index - 1) * TAB_DROPDOWN.rowHeight,
        width = TAB_DROPDOWN.width,
        height = TAB_DROPDOWN.rowHeight,
    }
end

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

local function wwwSiteRect(index)
    return { x = WWW_SITE.x + (index - 1) * (WWW_SITE.width + WWW_SITE.gap), y = WWW_SITE.y,
        width = WWW_SITE.width, height = WWW_SITE.height }
end

local function wwwProductRect(index)
    return { x = WWW_PRODUCT.x,
        y = WWW_PRODUCT.y + (index - 1) * (WWW_PRODUCT.rowHeight + WWW_PRODUCT.gap),
        width = WWW_PRODUCT.width, height = WWW_PRODUCT.rowHeight }
end

local function retailBuyRect(index)
    local row = wwwProductRect(index)
    return { x = row.x + row.width - 122, y = row.y + 6, width = 108, height = row.height - 12 }
end

local function cartTotal()
    local total, count = 0, 0
    for _, entry in ipairs(ComputerScreen.cart or {}) do
        local quantity = math.max(1, math.floor(tonumber(entry.quantity) or 1))
        total = total + (tonumber(entry.price) or 0) * quantity
        count = count + quantity
    end
    return total, count
end

local function addToCart(entry)
    ComputerScreen.cart = type(ComputerScreen.cart) == "table" and ComputerScreen.cart or {}
    for _, current in ipairs(ComputerScreen.cart) do
        if current.key == entry.key then
            current.quantity = (current.quantity or 1) + 1
            return current
        end
    end
    entry.quantity = 1
    ComputerScreen.cart[#ComputerScreen.cart + 1] = entry
    return entry
end

local function cartRemoveRect(visibleIndex)
    return { x = 724, y = 248 + (visibleIndex - 1) * 40, width = 82, height = 32 }
end

local function checkoutCart(state)
    local total, count = cartTotal()
    if count == 0 then return false, "Your online cart is empty." end
    if (state.money or 0) < total then return false, "Not enough money to check out this cart." end
    for _, entry in ipairs(ComputerScreen.cart) do
        if entry.kind == "supply" then
            local category = Procurement.categories[entry.categoryIndex]
            local item = category and category.items[entry.itemIndex]
            if not item or item.available == false or item.retailPrice ~= entry.price then
                return false, "A supply item in the cart is no longer available."
            end
        elseif entry.kind == "machine" then
            local offer = MachineFleet.offers("online")[entry.offerIndex]
            if not offer or offer.price ~= entry.price or offer.modelId ~= entry.modelId then
                return false, "A machine listing in the cart has changed."
            end
        else
            return false, "The cart contains an unknown item."
        end
    end
    local orders = {}
    for _, entry in ipairs(ComputerScreen.cart) do
        for _ = 1, entry.quantity do
            local succeeded, result
            if entry.kind == "supply" then
                succeeded, result = Procurement.buyRetail(state, entry.categoryIndex, entry.itemIndex)
            else
                succeeded, result = MachineFleet.orderOnline(state, entry.offerIndex)
            end
            if not succeeded then return false, tostring(result) end
            orders[#orders + 1] = result
        end
    end
    ComputerScreen.cart, ComputerScreen.cartOpen, ComputerScreen.cartPage = {}, false, 1
    return true, { orders = orders, total = total, count = count }
end

function ComputerScreen.checkout(state, entries)
    ComputerScreen.cart = entries
    return checkoutCart(state)
end

local function remoteAction(kind, args)
    args = args or {}
    args.kind = kind
    dependencies.remoteCommand(args)
    return { action = "remote_pending" }
end

local function machineBuyRect(index)
    return { x = MACHINE_OFFER.x + MACHINE_OFFER.width - 100,
        y = MACHINE_OFFER.y + (index - 1) * (MACHINE_OFFER.height + MACHINE_OFFER.gap) + 20,
        width = 88, height = 42 }
end

local function machineSellRect(index)
    return { x = OWNED_MACHINE.x + OWNED_MACHINE.width - 88,
        y = OWNED_MACHINE.y + (index - 1) * (OWNED_MACHINE.height + OWNED_MACHINE.gap) + 13,
        width = 76, height = 36 }
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

local function inboxForTab(state)
    if ComputerScreen.tab == "estimating" then return JobService.estimateInbox(state) end
    return JobService.generalInbox(state)
end

local function selectedEmail(state)
    for _, email in ipairs(inboxForTab(state)) do
        if email.id == ComputerScreen.selectedEmailId then return email end
    end
end

local function promotionSentForJob(state, job)
    if not job then return false end
    if job.promotionSent then return true end
    for _, promotion in ipairs((state.clientEmails and state.clientEmails.sentPromotions) or {}) do
        if promotion.sourceJobId == job.id then return true end
    end
    return false
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
    ComputerScreen.selectedEmailId = nil
    ComputerScreen.emailPage = 1
    ComputerScreen.emailSelectionRequired = false
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
    ComputerScreen.wwwSite = 1
    ComputerScreen.cart = {}
    ComputerScreen.cartOpen = false
    ComputerScreen.cartPage = 1
    ComputerScreen.wwwSiteChangedAt = 0
    ComputerScreen.tabDropdownOpen = false
    ComputerScreen.warehouseConfirmation,ComputerScreen.warehousePending,ComputerScreen.warehouseMessage=nil,false,nil
    ensureSelection(state)
end

function ComputerScreen.tabCenter(tabId)
    if tabId == "online" then tabId = "www" end
    for index, tab in ipairs(visibleTabs()) do
        if tab.id == tabId then
            local rect = tabDropdownRect(index)
            return rect.x + rect.width / 2, rect.y + rect.height / 2
        end
    end
end

function ComputerScreen.dropdownCenter()
    return TAB_DROPDOWN_ARROW.x + TAB_DROPDOWN_ARROW.width / 2,
        TAB_DROPDOWN_ARROW.y + TAB_DROPDOWN_ARROW.height / 2
end

function ComputerScreen.activeUrl()
    if ComputerScreen.tab == "www" then
        local site = WWW_SITES[ComputerScreen.wwwSite] or WWW_SITES[1]
        return site.url
    end
    local tab = tabById(ComputerScreen.tab)
    return tab and tab.url or "www.thecritternet.com/job-desk"
end

local function activateTab(state, tab)
    ComputerScreen.tab = tab.id
    ComputerScreen.tabDropdownOpen = false
    ComputerScreen.cartOpen = false
    if tab.id == "email" or tab.id == "estimating" then
        local inbox = tab.id == "estimating"
            and JobService.estimateInbox(state) or JobService.generalInbox(state)
        ComputerScreen.emailPage = 1
        local found = false
        for _, email in ipairs(inbox) do
            if email.id == ComputerScreen.selectedEmailId then found = true; break end
        end
        if not found then
            ComputerScreen.selectedEmailId = ComputerScreen.emailSelectionRequired
                and nil or (inbox[1] and inbox[1].id or nil)
        end
        if tab.id == "estimating" and not ComputerScreen.promoJobId then
            resetQuoteText(state)
        end
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
    local index = direction == "previous" and 1 or math.min(2, #WWW_SITES)
    local rect = wwwSiteRect(index)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function ComputerScreen.wwwSiteCenter(index)
    local rect = wwwSiteRect(index)
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

function ComputerScreen.cartButtonCenter()
    return CART_BUTTON.x + CART_BUTTON.width / 2, CART_BUTTON.y + CART_BUTTON.height / 2
end

function ComputerScreen.cartCheckoutCenter()
    return CART_CHECKOUT.x + CART_CHECKOUT.width / 2, CART_CHECKOUT.y + CART_CHECKOUT.height / 2
end

function ComputerScreen.cartSummary()
    local total, count = cartTotal()
    return { total = total, count = count, lines = #(ComputerScreen.cart or {}) }
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
    -- The estimate and promotion input hit targets below explicitly opt back in.
    ComputerScreen.quoteFocused = false
    ComputerScreen.promoFocused = false
    if contains(CLOSE, x, y) then
        ComputerScreen.tabDropdownOpen = false
        return { action = "close" }
    end
    if contains(TAB_DROPDOWN_ARROW, x, y) then
        ComputerScreen.tabDropdownOpen = not ComputerScreen.tabDropdownOpen
        return { action = ComputerScreen.tabDropdownOpen
            and "dropdown_opened" or "dropdown_closed" }
    end
    if ComputerScreen.tabDropdownOpen then
        for index, tab in ipairs(visibleTabs()) do
            if contains(tabDropdownRect(index), x, y) then
                return activateTab(state, tab)
            end
        end
        ComputerScreen.tabDropdownOpen = false
        return { action = "dropdown_closed" }
    end
    if ComputerScreen.tab == "warehouse" then return warehouseMousepressed(state,x,y) end
    if ComputerScreen.tab == "www" and ComputerScreen.cartOpen then
        local maximumPage = math.max(1, math.ceil(#ComputerScreen.cart / CART_PAGE_SIZE))
        if contains(CART_BACK, x, y) then
            ComputerScreen.cartOpen = false
            return { action = "cart_closed" }
        elseif contains(CART_CLEAR, x, y) then
            ComputerScreen.cart, ComputerScreen.cartPage = {}, 1
            state.message = "Online cart cleared."
            return { action = "cart_cleared" }
        elseif contains(CART_PREVIOUS, x, y) then
            ComputerScreen.cartPage = math.max(1, ComputerScreen.cartPage - 1)
            return { action = "cart_page" }
        elseif contains(CART_NEXT, x, y) then
            ComputerScreen.cartPage = math.min(maximumPage, ComputerScreen.cartPage + 1)
            return { action = "cart_page" }
        elseif contains(CART_CHECKOUT, x, y) then
            if dependencies.remoteCommand then
                local items = {}
                for _, entry in ipairs(ComputerScreen.cart) do
                    items[#items + 1] = { kind = entry.kind, quantity = entry.quantity,
                        categoryIndex = entry.categoryIndex, itemIndex = entry.itemIndex, offerIndex = entry.offerIndex }
                end
                return remoteAction("checkout", { items = items })
            end
            local succeeded, result = checkoutCart(state)
            if not succeeded then state.message = result; return { action = "blocked" } end
            state.message = string.format(
                "Checkout complete: %d item%s, $%d total. Receipt email%s received.",
                result.count, result.count == 1 and "" or "s", result.total,
                #result.orders == 1 and "" or "s")
            return { action = "cart_checked_out", result = result }
        end
        local first = (ComputerScreen.cartPage - 1) * CART_PAGE_SIZE + 1
        for visibleIndex = 1, CART_PAGE_SIZE do
            local entryIndex = first + visibleIndex - 1
            if ComputerScreen.cart[entryIndex] and contains(cartRemoveRect(visibleIndex), x, y) then
                table.remove(ComputerScreen.cart, entryIndex)
                ComputerScreen.cartPage = math.min(ComputerScreen.cartPage,
                    math.max(1, math.ceil(#ComputerScreen.cart / CART_PAGE_SIZE)))
                state.message = "Removed item from the online cart."
                return { action = "cart_item_removed" }
            end
        end
        return nil
    end
    if ComputerScreen.tab == "www" and contains(CART_BUTTON, x, y) then
        ComputerScreen.cartOpen = true
        ComputerScreen.cartPage = 1
        return { action = "cart_opened" }
    end
    if ComputerScreen.tab == "inventory" then return nil end
    if ComputerScreen.tab == "www" then
        for index = 1, #WWW_SITES do
            if contains(wwwSiteRect(index), x, y) then
                ComputerScreen.wwwSite = index
                ComputerScreen.wwwSiteChangedAt = love.timer.getTime()
                return { action = "www_site", site = WWW_SITES[index] }
            end
        end
        local site = WWW_SITES[ComputerScreen.wwwSite] or WWW_SITES[1]
        if site.kind ~= "machines" then
            local category = Procurement.category(site.categoryIndex)
            for index, item in ipairs(category.items) do
                if item.available ~= false and item.retailPrice and contains(retailBuyRect(index), x, y) then
                    addToCart({
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
        for index, offer in ipairs(MachineFleet.offers("online")) do
            if contains(machineBuyRect(index), x, y) then
                addToCart({
                    key = "machine:" .. tostring(index), kind = "machine", offerIndex = index,
                    modelId = offer.modelId, name = offer.name, price = offer.price,
                })
                state.message = offer.name .. " added to the online cart."
                return { action = "cart_item_added" }
            end
        end
        for index, item in ipairs(MachineFleet.owned(state)) do
            if index <= 4 and contains(machineSellRect(index), x, y) then
                if dependencies.remoteCommand then return remoteAction("sell", { id = item.id }) end
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
            if dependencies.remoteCommand then return remoteAction("pay_bills") end
            local paid, result = BusinessCalendar.pay(state)
            if not paid then state.message = result; return { action = "blocked" } end
            state.message = string.format("Paid $%d in operating bills and customer claims.", result)
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
    if ComputerScreen.tab == "email" or ComputerScreen.tab == "estimating" then
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
                if dependencies.remoteCommand then return remoteAction("promotion", { id = ComputerScreen.promoJobId, text = ComputerScreen.promoText }) end
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
        local inbox = inboxForTab(state)
        local maximumEmailPage = math.max(1, math.ceil(#inbox / EMAIL_PAGE_SIZE))
        ComputerScreen.emailPage = math.max(1, math.min(ComputerScreen.emailPage or 1, maximumEmailPage))
        if contains(EMAIL_PREVIOUS, x, y) and ComputerScreen.emailPage > 1 then
            ComputerScreen.emailPage = ComputerScreen.emailPage - 1
            local email = inbox[(ComputerScreen.emailPage - 1) * EMAIL_PAGE_SIZE + 1]
            ComputerScreen.selectedEmailId = email and email.id or nil
            ComputerScreen.emailSelectionRequired = false
            resetQuoteText(state)
            return { action = "email_page" }
        elseif contains(EMAIL_NEXT, x, y) and ComputerScreen.emailPage < maximumEmailPage then
            ComputerScreen.emailPage = ComputerScreen.emailPage + 1
            local email = inbox[(ComputerScreen.emailPage - 1) * EMAIL_PAGE_SIZE + 1]
            ComputerScreen.selectedEmailId = email and email.id or nil
            ComputerScreen.emailSelectionRequired = false
            resetQuoteText(state)
            return { action = "email_page" }
        end
        if not ComputerScreen.emailSelectionRequired and not ComputerScreen.selectedEmailId and inbox[1] then
            ComputerScreen.selectedEmailId = inbox[1].id
        end
        local firstEmail = (ComputerScreen.emailPage - 1) * EMAIL_PAGE_SIZE + 1
        for row = 1, EMAIL_PAGE_SIZE do
            local email = inbox[firstEmail + row - 1]
            if not email then break end
            local rect = { x = 94, y = 238 + (row - 1) * 54, width = 280, height = 46 }
            if contains(rect, x, y) then
                ComputerScreen.selectedEmailId = email.id
                ComputerScreen.emailSelectionRequired = false
                resetQuoteText(state)
                return { action = "email_select", email = email }
            end
        end
        local currentEmail = selectedEmail(state)
        if currentEmail and currentEmail.serviceNotice then
            ComputerScreen.quoteFocused = false
            if contains(EMAIL_DECLINE, x, y) then
                if dependencies.remoteCommand then return remoteAction("archive_service", { id = currentEmail.id }) end
                MachineFleet.dismissServiceNotice(state, currentEmail.id)
                ComputerScreen.selectedEmailId = nil
                ComputerScreen.emailSelectionRequired = true
                state.message = "Archived the technician's service notice."
                return { action = "service_notice_dismissed" }
            end
            return nil
        end
        if currentEmail and not currentEmail.job then
            ComputerScreen.quoteFocused = false
            if contains(EMAIL_DECLINE, x, y) then
                if dependencies.remoteCommand then return remoteAction("archive", { id = currentEmail.id }) end
                JobService.dismissInboxNotice(state, currentEmail.id)
                ComputerScreen.selectedEmailId = nil
                ComputerScreen.emailPage = 1
                ComputerScreen.emailSelectionRequired = true
                state.message = "Archived the email."
                return { action = "inbox_notice_dismissed" }
            end
            return nil
        end
        if ComputerScreen.tab == "estimating" and currentEmail
            and currentEmail.job and not currentEmail.awaitingReply
            and contains(EMAIL_QUOTE_INPUT, x, y)
        then
            ComputerScreen.quoteFocused = true
            ComputerScreen.quoteReplaceOnType = true
            return { action = "quote_focus" }
        end
        if ComputerScreen.tab == "estimating" and currentEmail
            and currentEmail.job and not currentEmail.awaitingReply
            and ComputerScreen.selectedEmailId and contains(EMAIL_ACCEPT, x, y)
        then
            if dependencies.remoteCommand then return remoteAction("estimate", { id = ComputerScreen.selectedEmailId, amount = tonumber(ComputerScreen.quoteText) }) end
            local succeeded, result = JobService.submitEmailQuote(
                state, ComputerScreen.selectedEmailId, tonumber(ComputerScreen.quoteText), os.time())
            if not succeeded then state.message = tostring(result); return { action = "blocked" } end
            ComputerScreen.selectedEmailId = nil
            ComputerScreen.emailSelectionRequired = true
            resetQuoteText(state)
            state.message = string.format("Sent %s a $%d estimate. It expires in 3 days.",
                result.job.company, result.amount)
            return { action = "estimate_sent", result = result }
        elseif ComputerScreen.tab == "estimating" and currentEmail
            and currentEmail.job and not currentEmail.awaitingReply
            and ComputerScreen.selectedEmailId and contains(EMAIL_DECLINE, x, y)
        then
            if dependencies.remoteCommand then return remoteAction("decline", { id = ComputerScreen.selectedEmailId }) end
            local succeeded, result = JobService.respondToEmail(
                state, ComputerScreen.selectedEmailId, "declined", os.time())
            if not succeeded then state.message = tostring(result); return { action = "blocked" } end
            ComputerScreen.selectedEmailId = nil
            ComputerScreen.emailSelectionRequired = true
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
    if ComputerScreen.tab == "completed" and selected
        and not promotionSentForJob(state, selected) and contains(JOB_PROMO, x, y)
    then
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
        or (ComputerScreen.tab == "estimating" and ComputerScreen.quoteFocused)
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
    elseif ComputerScreen.tab == "estimating" and ComputerScreen.quoteFocused then
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
        or ComputerScreen.tab == "estimating" and ComputerScreen.quoteFocused
end

local panel = Ui.panel

local function drawMonitorFrame()
    -- A thick CRT shell makes the software feel like it lives inside a real
    -- beige 1990s office monitor instead of floating over the warehouse.
    love.graphics.setColor(0.08, 0.075, 0.065, 1)
    love.graphics.rectangle("fill", MONITOR.x + 8, MONITOR.y + 10,
        MONITOR.width, MONITOR.height, 16, 16)
    love.graphics.setColor(0.63, 0.61, 0.54, 1)
    love.graphics.rectangle("fill", MONITOR.x, MONITOR.y,
        MONITOR.width, MONITOR.height, 16, 16)
    love.graphics.setColor(0.88, 0.86, 0.77, 1)
    love.graphics.line(MONITOR.x + 16, MONITOR.y + 8,
        MONITOR.x + MONITOR.width - 16, MONITOR.y + 8)
    love.graphics.line(MONITOR.x + 8, MONITOR.y + 16,
        MONITOR.x + 8, MONITOR.y + MONITOR.height - 16)
    love.graphics.setColor(0.27, 0.26, 0.23, 1)
    love.graphics.line(MONITOR.x + 16, MONITOR.y + MONITOR.height - 8,
        MONITOR.x + MONITOR.width - 16, MONITOR.y + MONITOR.height - 8)
    love.graphics.line(MONITOR.x + MONITOR.width - 8, MONITOR.y + 16,
        MONITOR.x + MONITOR.width - 8, MONITOR.y + MONITOR.height - 16)
    love.graphics.setColor(0.04, 0.045, 0.045, 1)
    love.graphics.rectangle("fill", PANEL.x - 8, PANEL.y - 8,
        PANEL.width + 16, PANEL.height + 16, 9, 9)
    love.graphics.setColor(0.22, 0.21, 0.18, 1)
    for index = 1, 7 do
        love.graphics.rectangle("fill", 62 + (index - 1) * 13, 654, 7, 2)
    end
    love.graphics.setColor(0.08, 0.55, 0.30, 1)
    love.graphics.circle("fill", 876, 655, 4)
    love.graphics.setColor(0.24, 0.23, 0.20, 1)
    love.graphics.print("CRITTERWORKS CRT-17", 374, 649)
end

local function drawTabSelector(pointerX, pointerY)
    love.graphics.setColor(0.72, 0.72, 0.68, 1)
    love.graphics.rectangle("fill", TAB_ADDRESS.x, TAB_ADDRESS.y,
        TAB_ADDRESS.width, TAB_ADDRESS.height)
    love.graphics.setColor(0.97, 0.97, 0.92, 1)
    love.graphics.line(TAB_ADDRESS.x, TAB_ADDRESS.y,
        TAB_ADDRESS.x + TAB_ADDRESS.width, TAB_ADDRESS.y)
    love.graphics.line(TAB_ADDRESS.x, TAB_ADDRESS.y,
        TAB_ADDRESS.x, TAB_ADDRESS.y + TAB_ADDRESS.height)
    love.graphics.setColor(0.25, 0.26, 0.25, 1)
    love.graphics.line(TAB_ADDRESS.x, TAB_ADDRESS.y + TAB_ADDRESS.height,
        TAB_ADDRESS.x + TAB_ADDRESS.width, TAB_ADDRESS.y + TAB_ADDRESS.height)
    love.graphics.setColor(0.035, 0.12, 0.15, 1)
    love.graphics.rectangle("fill", TAB_ADDRESS.x + 7, TAB_ADDRESS.y + 8,
        TAB_ADDRESS.width - 14, TAB_ADDRESS.height - 15)
    love.graphics.setColor(0.76, 0.94, 0.90, 1)
    love.graphics.print(ComputerScreen.activeUrl(), TAB_ADDRESS.x + 15, TAB_ADDRESS.y + 14)

    local hovered = pointerX and contains(TAB_DROPDOWN_ARROW, pointerX, pointerY)
    love.graphics.setColor(hovered and { 0.82, 0.82, 0.77, 1 }
        or { 0.68, 0.68, 0.64, 1 })
    love.graphics.rectangle("fill", TAB_DROPDOWN_ARROW.x, TAB_DROPDOWN_ARROW.y,
        TAB_DROPDOWN_ARROW.width, TAB_DROPDOWN_ARROW.height)
    love.graphics.setColor(0.97, 0.97, 0.92, 1)
    love.graphics.line(TAB_DROPDOWN_ARROW.x, TAB_DROPDOWN_ARROW.y,
        TAB_DROPDOWN_ARROW.x + TAB_DROPDOWN_ARROW.width, TAB_DROPDOWN_ARROW.y)
    love.graphics.line(TAB_DROPDOWN_ARROW.x, TAB_DROPDOWN_ARROW.y,
        TAB_DROPDOWN_ARROW.x, TAB_DROPDOWN_ARROW.y + TAB_DROPDOWN_ARROW.height)
    love.graphics.setColor(0.22, 0.23, 0.23, 1)
    love.graphics.line(TAB_DROPDOWN_ARROW.x, TAB_DROPDOWN_ARROW.y + TAB_DROPDOWN_ARROW.height,
        TAB_DROPDOWN_ARROW.x + TAB_DROPDOWN_ARROW.width,
        TAB_DROPDOWN_ARROW.y + TAB_DROPDOWN_ARROW.height)
    love.graphics.polygon("fill", TAB_DROPDOWN_ARROW.x + 13,
        TAB_DROPDOWN_ARROW.y + (ComputerScreen.tabDropdownOpen and 25 or 15),
        TAB_DROPDOWN_ARROW.x + 27,
        TAB_DROPDOWN_ARROW.y + (ComputerScreen.tabDropdownOpen and 25 or 15),
        TAB_DROPDOWN_ARROW.x + 20,
        TAB_DROPDOWN_ARROW.y + (ComputerScreen.tabDropdownOpen and 14 or 26))

    if not ComputerScreen.tabDropdownOpen then return end
    for index, tab in ipairs(visibleTabs()) do
        local rect = tabDropdownRect(index)
        local selected = ComputerScreen.tab == tab.id
        local itemHovered = pointerX and contains(rect, pointerX, pointerY)
        love.graphics.setColor(selected and { 0.08, 0.47, 0.48, 1 }
            or itemHovered and { 0.20, 0.37, 0.39, 1 }
            or { 0.68, 0.68, 0.64, 1 })
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height)
        love.graphics.setColor(0.94, 0.94, 0.89, 1)
        love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height)
        love.graphics.setColor(selected and { 0.98, 1.00, 0.95, 1 }
            or { 0.04, 0.12, 0.14, 1 })
        love.graphics.print(tab.label, rect.x + 14, rect.y + 13)
        love.graphics.setColor(selected and { 0.75, 0.94, 0.88, 1 }
            or { 0.25, 0.34, 0.35, 1 })
        love.graphics.printf(tab.url, rect.x + 168, rect.y + 13,
            rect.width - 182, "right")
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
        { text = "Client: " .. tostring(selected.clientTemperament or "standard")
            .. " • Reputation tier: " .. tostring(selected.reputationTier or "legacy"), width = 310 },
    }
    if (selected.spoiledSheets or 0) > 0 then
        rows[#rows + 1] = { text = string.format("Cutting waste: %s sheets • $%d redo/replacement charges",
            commaNumber(selected.spoiledSheets), selected.spoilCost or 0), width = DETAIL.width - 40 }
        rows[#rows + 1] = { text = string.format("Replacement stock: %d skid%s • %s sheets delivered or inbound",
            selected.replacementSkids or 0, (selected.replacementSkids or 0) == 1 and "" or "s",
            commaNumber(selected.replacementSheets or 0)), width = DETAIL.width - 40 }
    end
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
    local tableY = valueY + font:getHeight() + 3
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
        local sent = promotionSentForJob(state, selected)
        local hovered = not sent and pointerX and contains(JOB_PROMO, pointerX, pointerY)
        love.graphics.setColor(sent and 0.10 or hovered and 0.19 or 0.12,
            sent and 0.15 or hovered and 0.55 or 0.42, sent and 0.16 or 0.29)
        love.graphics.rectangle("fill", JOB_PROMO.x, JOB_PROMO.y,
            JOB_PROMO.width, JOB_PROMO.height, 3, 3)
        love.graphics.setColor(sent and 0.50 or 0.95, sent and 0.54 or 0.97, sent and 0.53 or 0.94)
        love.graphics.printf(sent and "10% PROMO SENT" or "EMAIL 10% PROMO",
            JOB_PROMO.x, JOB_PROMO.y + 15,
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

local function drawCartButton(pointerX, pointerY)
    local total, count = cartTotal()
    local hovered = pointerX and contains(CART_BUTTON, pointerX, pointerY)
    love.graphics.setColor(hovered and 0.18 or 0.11, hovered and 0.52 or 0.39, 0.30, 1)
    love.graphics.rectangle("fill", CART_BUTTON.x, CART_BUTTON.y,
        CART_BUTTON.width, CART_BUTTON.height, 3, 3)
    love.graphics.setColor(0.96, 0.98, 0.95)
    love.graphics.printf(string.format("CART %d • %s", count, money(total)),
        CART_BUTTON.x, CART_BUTTON.y + 12, CART_BUTTON.width, "center")
end

local function drawCart(state, pointerX, pointerY)
    panel({ x = 82, y = 190, width = 770, height = 408 },
        { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
    local total, count = cartTotal()
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.print("ONLINE CART", 104, 208)
    love.graphics.setColor(0.70, 0.79, 0.80)
    love.graphics.printf("Review everything before checkout. A separate receipt is emailed for every order.",
        300, 208, 524, "right")
    local maximumPage = math.max(1, math.ceil(#ComputerScreen.cart / CART_PAGE_SIZE))
    ComputerScreen.cartPage = math.max(1, math.min(ComputerScreen.cartPage or 1, maximumPage))
    local first = (ComputerScreen.cartPage - 1) * CART_PAGE_SIZE + 1
    if #ComputerScreen.cart == 0 then
        love.graphics.setColor(0.58, 0.66, 0.67)
        love.graphics.printf("Your cart is empty. Return to the store and add the items you need.",
            204, 350, 548, "center")
    end
    for visibleIndex = 1, CART_PAGE_SIZE do
        local entry = ComputerScreen.cart[first + visibleIndex - 1]
        if not entry then break end
        local y = 244 + (visibleIndex - 1) * 40
        love.graphics.setColor(visibleIndex % 2 == 0 and 0.085 or 0.105, 0.12, 0.14, 1)
        love.graphics.rectangle("fill", 102, y, 704, 36, 2, 2)
        love.graphics.setColor(0.86, 0.90, 0.88)
        love.graphics.printf(entry.name, 114, y + 10, 390, "left")
        love.graphics.setColor(0.63, 0.72, 0.73)
        love.graphics.printf("× " .. tostring(entry.quantity), 500, y + 10, 54, "right")
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.printf(money(entry.price * entry.quantity), 566, y + 10, 140, "right")
        local remove = cartRemoveRect(visibleIndex)
        local hovered = pointerX and contains(remove, pointerX, pointerY)
        love.graphics.setColor(hovered and 0.58 or 0.40, 0.17, 0.16, 1)
        love.graphics.rectangle("fill", remove.x, remove.y, remove.width, remove.height, 3, 3)
        love.graphics.setColor(0.98, 0.93, 0.91)
        love.graphics.printf("REMOVE", remove.x, remove.y + 10, remove.width, "center")
    end
    local function cartAction(rect, label, enabled, green)
        local hovered = enabled and pointerX and contains(rect, pointerX, pointerY)
        love.graphics.setColor(enabled and (green and 0.12 or 0.18) or 0.10,
            enabled and (green and (hovered and 0.55 or 0.42) or (hovered and 0.34 or 0.25)) or 0.12,
            enabled and (green and 0.29 or 0.28) or 0.13, 1)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.setColor(enabled and 0.95 or 0.48, enabled and 0.97 or 0.51, enabled and 0.94 or 0.51)
        love.graphics.printf(label, rect.x, rect.y + 13, rect.width, "center")
    end
    cartAction(CART_BACK, "KEEP SHOPPING", true, false)
    cartAction(CART_CLEAR, "CLEAR CART", count > 0, false)
    cartAction(CART_PREVIOUS, "<", ComputerScreen.cartPage > 1, false)
    cartAction(CART_NEXT, ">", ComputerScreen.cartPage < maximumPage, false)
    local affordable = count > 0 and (state.money or 0) >= total
    cartAction(CART_CHECKOUT,
        count == 0 and "CART EMPTY" or affordable and ("CHECKOUT  " .. money(total)) or "INSUFFICIENT CASH",
        affordable, true)
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
    love.graphics.setColor(0.42, 0.73, 0.78)
    love.graphics.printf("Buy more through the WWW tab at www.thecritternet.com",
        400, 380, 406, "right")
    love.graphics.setColor(0.73, 0.80, 0.81)
    love.graphics.print("Loose starter sheets", 116, 414)
    love.graphics.print("Finished samples", 474, 414)
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.printf(commaNumber(inventory.paper or 0), 314, 414, 110, "right")
    love.graphics.printf(commaNumber(inventory.prints or 0), 672, 414, 110, "right")
    local rows = Procurement.inventoryRows(state)
    for index, item in ipairs(rows) do
        local column = math.floor((index - 1) / 5)
        local row = (index - 1) % 5
        local x, y = 116 + column * 358, 456 + row * 32
        love.graphics.setColor(row % 2 == 0 and 0.085 or 0.105, 0.12, 0.14, 1)
        love.graphics.rectangle("fill", x - 8, y - 7, 326, 28, 2, 2)
        love.graphics.setColor(0.73, 0.80, 0.81)
        love.graphics.print(item.label, x, y)
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.printf(commaNumber(item.quantity) .. " " .. item.unit, x + 190, y, 116, "right")
    end
end

local function conditionColor(condition)
    if condition >= 75 then return 0.35, 0.78, 0.48 end
    if condition >= 55 then return 0.88, 0.70, 0.25 end
    return 0.90, 0.35, 0.24
end

local function drawCritterNetSprite(assets, frame, x, y, width, height, alpha)
    local image = assets and assets.images and assets.images.critterNetSprites
    local quad = assets and assets.quads and assets.quads["critterNetSprite" .. tostring(frame)]
    if not image or not quad then return end
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(image, quad.quad, x, y, 0, width / quad.width, height / quad.height)
end

local function drawCritterNetChrome(assets)
    local backdrop = assets and assets.images and assets.images.critterNetMenu
    if not backdrop then return end
    love.graphics.setColor(1, 1, 1, 0.90)
    love.graphics.draw(backdrop, PANEL.x, PANEL.y, 0,
        PANEL.width / backdrop:getWidth(), PANEL.height / backdrop:getHeight())

    local clock = love.timer.getTime()
    local frames = {
        active = 5 + math.floor(clock * 4) % 4,
        completed = 15,
        deliveries = 9 + math.floor(clock * 3) % 4,
        estimating = 13 + math.floor(clock * 2) % 2,
        calendar = 16,
        inventory = 5 + math.floor(clock * 4) % 4,
        www = 1 + math.floor(clock * 2.5) % 4,
        email = 13 + math.floor(clock * 2) % 2,
        bills = 15,
    }
    drawCritterNetSprite(assets, frames[ComputerScreen.tab] or 5,
        696, 52, 46, 31, 0.96)
end

local function drawWww(state, pointerX, pointerY, assets)
    panel({ x = 82, y = 190, width = 770, height = 408 },
        { 0.04, 0.05, 0.08, 1 }, { 0.58, 0.60, 0.58, 1 })
    local backdrop = assets and assets.images and assets.images.critterNetMenu
    if backdrop then
        love.graphics.setColor(1, 1, 1, 0.56)
        love.graphics.draw(backdrop, 82, 190, 0, 770 / backdrop:getWidth(), 408 / backdrop:getHeight())
        love.graphics.setColor(0.01, 0.025, 0.055, 0.48)
        love.graphics.rectangle("fill", 88, 232, 758, 360)
    end
    local site = WWW_SITES[ComputerScreen.wwwSite] or WWW_SITES[1]
    -- Chunky beveled address bar, deliberately styled after a dial-up-era browser.
    love.graphics.setColor(0.72, 0.72, 0.68, 1)
    love.graphics.rectangle("fill", 96, 198, 604, 32)
    love.graphics.setColor(0.95, 0.95, 0.90, 1)
    love.graphics.line(96, 198, 700, 198); love.graphics.line(96, 198, 96, 230)
    love.graphics.setColor(0.28, 0.29, 0.28, 1)
    love.graphics.line(96, 230, 700, 230); love.graphics.line(700, 198, 700, 230)
    love.graphics.setColor(0.05, 0.16, 0.18, 1)
    love.graphics.rectangle("fill", 104, 204, 588, 20)
    love.graphics.setColor(0.78, 0.94, 0.90, 1)
    love.graphics.print(site.url, 114, 209)
    local animationTime = love.timer.getTime()
    local globeFrame = 1 + math.floor(animationTime * 2.5) % 4
    local pulseFrame = 5 + math.floor(animationTime * 4) % 4
    local modemFrame = 9 + math.floor(animationTime * 3) % 4
    drawCritterNetSprite(assets, globeFrame, 646, 196, 58, 38, 1)
    drawCritterNetSprite(assets, pulseFrame, 350, 492, 184, 122, 0.14)
    for index, website in ipairs(WWW_SITES) do
        local rect = wwwSiteRect(index)
        local selected = index == ComputerScreen.wwwSite
        local hovered = pointerX and contains(rect, pointerX, pointerY)
        love.graphics.setColor(selected and 0.10 or hovered and 0.23 or 0.18,
            selected and 0.42 or hovered and 0.38 or 0.31,
            selected and 0.43 or hovered and 0.40 or 0.35, 1)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height)
        love.graphics.setColor(selected and 0.92 or 0.80, selected and 0.94 or 0.82, selected and 0.90 or 0.80)
        love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height)
        love.graphics.printf(website.short, rect.x, rect.y + 14, rect.width, "center")
    end
    drawCritterNetSprite(assets, modemFrame, 730, 536, 100, 60, 0.92)
    local siteChangeAge = animationTime - (ComputerScreen.wwwSiteChangedAt or 0)
    if siteChangeAge < 0.70 then
        drawCritterNetSprite(assets, siteChangeAge < 0.36 and 16 or 15,
            773, 244, 58, 39, 1)
    end
    if site.kind ~= "machines" then
        local category = Procurement.category(site.categoryIndex)
        for index, item in ipairs(category.items) do
            local row, buy = wwwProductRect(index), retailBuyRect(index)
            local available = item.available ~= false and item.retailPrice ~= nil
            local total = cartTotal()
            local affordable = available and (state.money or 0) >= total + (item.retailPrice or 0)
            love.graphics.setColor(index % 2 == 0 and 0.075 or 0.095, 0.11, 0.17, 0.94)
            love.graphics.rectangle("fill", row.x, row.y, row.width, row.height, 2, 2)
            love.graphics.setColor(0.38, 0.78, 0.88, 1)
            love.graphics.printf(item.retailName or item.name, row.x + 14, row.y + 8, 430, "left")
            love.graphics.setColor(0.66, 0.72, 0.72, 1)
            love.graphics.print(available
                and string.format("Ships to loading dock • salesman bulk $%d", item.price)
                or tostring(item.unavailableReason), row.x + 14, row.y + 29)
            love.graphics.setColor(affordable and 0.16 or 0.18, affordable and 0.44 or 0.19, affordable and 0.30 or 0.20)
            love.graphics.rectangle("fill", buy.x, buy.y, buy.width, buy.height, 2, 2)
            love.graphics.setColor(affordable and 0.96 or 0.56, affordable and 0.98 or 0.59, affordable and 0.94 or 0.58)
            love.graphics.printf(available and ("ADD " .. money(item.retailPrice)) or "OFFLINE",
                buy.x, buy.y + 13, buy.width, "center")
        end
        return
    end
    love.graphics.setColor(0.68, 0.83, 0.84)
    love.graphics.print("MACHINE LISTINGS", MACHINE_OFFER.x, 284)
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
        love.graphics.print("Inspected • flatbed delivery", MACHINE_OFFER.x + 12, y + 58)
        local total = cartTotal()
        local affordable = (state.money or 0) >= total + offer.price
        love.graphics.setColor(affordable and { 0.15, 0.44, 0.29, 1 } or { 0.17, 0.18, 0.19, 1 })
        love.graphics.rectangle("fill", buy.x, buy.y, buy.width, buy.height, 3, 3)
        love.graphics.setColor(affordable and { 0.96, 0.98, 0.94, 1 } or { 0.52, 0.55, 0.54, 1 })
        love.graphics.printf("ADD " .. money(offer.price), buy.x, buy.y + 14, buy.width, "center")
    end

    love.graphics.setColor(0.63, 0.72, 0.74)
    love.graphics.print("YOUR MACHINES", OWNED_MACHINE.x, 284)
    local owned = MachineFleet.owned(state)
    if #owned == 0 then
        love.graphics.setColor(0.52, 0.60, 0.62)
        love.graphics.printf("No machines owned. Buy a unit to install it in the shop.",
            OWNED_MACHINE.x, 356, OWNED_MACHINE.width, "center")
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
        love.graphics.print(string.format("%s %.0f%% • %d cycles", weakest.label,
            weakest.value, item.cycles), OWNED_MACHINE.x + 10, y + 46)
        love.graphics.setColor(0.40, 0.20, 0.18, 1)
        love.graphics.rectangle("fill", sell.x, sell.y, sell.width, sell.height, 3, 3)
        love.graphics.setColor(0.96, 0.91, 0.88)
        love.graphics.printf("SELL\n" .. money(MachineFleet.resaleValue(item, "online")),
            sell.x, sell.y + 4, sell.width, "center")
    end
    love.graphics.setColor(0.55, 0.68, 0.69)
    love.graphics.printf("CritterNet verified listings • extra units enter shop storage automatically",
        486, 574, 354, "center")
end

local function drawWarehouse(state,pointerX,pointerY,assets)
    local view=ComputerScreen.warehouseView(state)
    panel({x=82,y=190,width=770,height=408},{0.04,0.065,0.08,1},{0.43,0.61,0.58,1})
    local backdrop=assets and assets.images and assets.images.critterNetMenu
    if backdrop then
        love.graphics.setColor(1,1,1,0.22)
        love.graphics.draw(backdrop,82,190,0,770/backdrop:getWidth(),408/backdrop:getHeight())
    end
    love.graphics.setColor(0.94,0.83,0.34,1)
    love.graphics.print("CRITTERNET / WAREHOUSE IMPROVEMENTS",100,202)
    love.graphics.setColor(0.72,0.84,0.82,1)
    love.graphics.print("Each expansion: four construction stages, one game day per stage.",100,224)
    local function control(rect,text,enabled)
        local hovered=pointerX and pointerY and contains(rect,pointerX,pointerY)
        panel(rect,enabled and (hovered and {0.18,0.38,0.37,1} or {0.10,0.25,0.25,1}) or {0.10,0.13,0.14,1},
            enabled and {0.42,0.72,0.64,1} or {0.28,0.35,0.34,1},3,1)
        love.graphics.setColor(enabled and {0.93,0.96,0.88,1} or {0.49,0.55,0.53,1})
        love.graphics.printf(text,rect.x+5,rect.y+13,rect.width-10,"center")
    end
    for bi,bay in ipairs(view.bays) do
        local x=90+(bi-1)*380
        panel({x=x,y=244,width=372,height=224},{0.04,0.08,0.10,0.97},{0.27,0.46,0.45,1},3,1)
        love.graphics.setColor(0.91,0.93,0.87,1)
        love.graphics.print((bi==1 and "LEFT" or "RIGHT").." EXPANSION BAY",x+14,256)
        for oi,option in ipairs(bay.options) do
            control(warehouseOptionRect(bi,oi),option.name.."  /  "..(option.available and money(option.price) or "NOT READY YET"),
                view.enabled and option.available and bay.status=="locked" and not view.pending)
        end
        local phase=bay.status=="locked" and "Unpurchased / black area"
            or bay.status=="complete" and "Ready: "..(Upgrades.catalog(bay.optionId).name)
            or bay.phase=="building" and ("Building / stage "..bay.stage.." of 4")
            or "Ordered / "..tostring(bay.phase or bay.status):gsub("_"," ")
        love.graphics.setColor(0.64,0.82,0.72,1)
        love.graphics.printf(phase,x+12,441,348,"center")
    end
    panel({x=90,y=480,width=752,height=64},{0.08,0.13,0.15,0.98},{0.45,0.61,0.55,1},3,1)
    love.graphics.setColor(0.95,0.81,0.35,1)
    love.graphics.print("FORKLIFT / "..money(view.forklift.price),104,490)
    love.graphics.setColor(0.74,0.84,0.79,1)
    love.graphics.print("Raise forks for upper shelves and two-high pallet stacks.",104,518)
    control(WAREHOUSE_FORKLIFT,view.forkliftOwned and "OWNED" or "REVIEW PURCHASE",
        view.enabled and not view.forkliftOwned and not view.pending)
    love.graphics.setColor(0.96,0.77,0.38,1)
    love.graphics.printf(view.message or "Shelves: 10 spaces. Lower 5 use a jack or forklift; upper 5 require a forklift.",100,555,736,"left")
    love.graphics.setColor(0.69,0.78,0.78,1)
    love.graphics.printf(view.pending and "Waiting for the host to confirm your purchase."
        or not view.enabled and "Purchasing is not enabled in this build."
        or "Review a choice to confirm its cost. The raccoon mechanic calls before construction.",100,578,736,"left")
    local choice=view.confirmation
    if not choice then return end
    local product=Upgrades.catalog(choice.optionId or "forklift")
    love.graphics.setColor(0,0,0,0.72);love.graphics.rectangle("fill",82,190,770,408)
    panel({x=178,y=242,width=584,height=324},{0.045,0.09,0.11,1},{0.61,0.76,0.61,1},5,2)
    love.graphics.setColor(0.97,0.84,0.35,1)
    love.graphics.printf("CONFIRM "..product.name:upper(),204,265,532,"center")
    love.graphics.setColor(0.92,0.96,0.91,1)
    love.graphics.printf("Host catalog price: "..money(product.price),204,300,532,"center")
    love.graphics.setColor(0.72,0.85,0.82,1)
    love.graphics.printf(choice.kind=="buy_forklift"
        and "One warehouse forklift. Operate it to lift, lower and transfer actual pallets."
        or ((choice.bayId=="front_left" and "Left" or "Right").." expansion bay. Construction takes 4 game days after the mechanic arrives; one full day for each stage."),
        208,336,524,"left")
    if choice.optionId=="storage" then
        love.graphics.setColor(0.97,0.74,0.33,1)
        love.graphics.printf("2 rows x 5 columns. Only the lower five slots work with a pallet jack. You must operate a forklift to use the upper five.",208,388,524,"left")
    end
    if choice.warningRequired then
        control(WAREHOUSE_ACK,(choice.confirmUpperRows and "[X]" or "[ ]").." I understand: the upper 5 shelves need a forklift.",not view.pending)
    end
    if view.message then
        love.graphics.setColor(0.96,0.72,0.41,1)
        love.graphics.printf(view.message,208,486,524,"center")
    end
    control(WAREHOUSE_CANCEL,"CANCEL",not view.pending)
    control(WAREHOUSE_CONFIRM,"CONFIRM "..money(product.price),not view.pending and (state.money or 0)>=product.price
        and (not choice.warningRequired or choice.confirmUpperRows))
end

local function drawBills(state, pointerX, pointerY)
    local charges, monthlyTotal = BusinessCalendar.monthlyCharges()
    local balance = state.bills and state.bills.balance or 0
    local claimTotal = 0
    for _, invoice in ipairs(state.bills and state.bills.ledger or {}) do
        if invoice.status == "unpaid" and invoice.kind == "spoil_claim" then
            claimTotal = claimTotal + (invoice.total or 0)
        end
    end
    panel({ x = 82, y = 190, width = 770, height = 408 },
        { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.print("OPERATING BILLS & CUSTOMER CLAIMS", 108, 214)
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
    love.graphics.setColor(claimTotal > 0 and 0.92 or 0.72, claimTotal > 0 and 0.48 or 0.79, 0.44)
    love.graphics.print("Customer stock replacement claims", 122, 510)
    love.graphics.printf(money(claimTotal), 402, 510, 150, "right")

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
    local estimating = ComputerScreen.tab == "estimating"
    local inbox = inboxForTab(state)
    panel({ x = 82, y = 190, width = 310, height = 408 },
        { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
    panel({ x = 412, y = 190, width = 440, height = 408 },
        { 0.065, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.print(estimating and "JOB ESTIMATING" or "EMAIL INBOX", 96, 202)
    local mailFrame = 13 + math.floor(love.timer.getTime() * 1.4) % 2
    drawCritterNetSprite(assets, mailFrame, 302, 188, 80, 54, 0.92)
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
        love.graphics.print("ADD YOUR OWN MESSAGE — MORE DETAIL HELPS", 434, 320)
        love.graphics.setColor(ComputerScreen.promoFocused and 0.08 or 0.06, 0.12, 0.14, 1)
        love.graphics.rectangle("fill", PROMO_INPUT.x, PROMO_INPUT.y,
            PROMO_INPUT.width, PROMO_INPUT.height, 3, 3)
        love.graphics.setColor(ComputerScreen.promoFocused and 0.46 or 0.25,
            ComputerScreen.promoFocused and 0.75 or 0.40, 0.48, 1)
        love.graphics.rectangle("line", PROMO_INPUT.x, PROMO_INPUT.y,
            PROMO_INPUT.width, PROMO_INPUT.height, 3, 3)
        love.graphics.setColor(0.88, 0.91, 0.89)
        local custom = ComputerScreen.promoText
        if custom == "" then custom = "Click here and type a personal note. More characters improve the chance of a new job." end
        love.graphics.printf(custom .. (ComputerScreen.promoFocused and "_" or ""),
            PROMO_INPUT.x + 10, PROMO_INPUT.y + 10, PROMO_INPUT.width - 20, "left")
        local promoTerms = JobService.promotionTerms(state, ComputerScreen.promoText)
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.printf(string.format("%d / 240 characters   •   %.0f%% chance of a new job",
            promoTerms.messageLength, promoTerms.responseChance * 100),
            434, 474, 392, "center")
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
        love.graphics.printf(estimating
            and "No estimates need attention. Walk-in clients email their written details after the counter visit."
            or "No new receipts, notices, or client messages.",
            106, 332, 262, "center")
        return
    end
    local selected
    local maximumEmailPage = math.max(1, math.ceil(#inbox / EMAIL_PAGE_SIZE))
    ComputerScreen.emailPage = math.max(1, math.min(ComputerScreen.emailPage or 1, maximumEmailPage))
    local firstEmail = (ComputerScreen.emailPage - 1) * EMAIL_PAGE_SIZE + 1
    for row = 1, EMAIL_PAGE_SIZE do
        local email = inbox[firstEmail + row - 1]
        if not email then break end
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
        love.graphics.print(email.awaitingReply and "SENT · WAITING FOR REPLY" or email.subject,
            rect.x + 8, rect.y + 24)
    end
    local function emailPageButton(rect, label, enabled)
        local hovered = enabled and pointerX and contains(rect, pointerX, pointerY)
        love.graphics.setColor(enabled and (hovered and 0.16 or 0.10) or 0.06,
            enabled and (hovered and 0.40 or 0.24) or 0.09, enabled and 0.27 or 0.10, 1)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.setColor(enabled and 0.90 or 0.38, enabled and 0.94 or 0.43, enabled and 0.92 or 0.44)
        love.graphics.printf(label, rect.x, rect.y + 8, rect.width, "center")
    end
    emailPageButton(EMAIL_PREVIOUS, "<", ComputerScreen.emailPage > 1)
    emailPageButton(EMAIL_NEXT, ">", ComputerScreen.emailPage < maximumEmailPage)
    love.graphics.setColor(0.55, 0.63, 0.65)
    love.graphics.printf(string.format("%d/%d", ComputerScreen.emailPage, maximumEmailPage),
        184, 570, 100, "center")
    if not selected and not ComputerScreen.emailSelectionRequired then selected = inbox[1] end
    if not selected and ComputerScreen.emailSelectionRequired then
        love.graphics.setColor(0.58, 0.66, 0.67)
        love.graphics.printf("Reply sent. Select another email when you are ready.",
            454, 350, 352, "center")
        return
    end
    if not selected then return end
    love.graphics.setColor(0.96, 0.84, 0.30)
    love.graphics.print("FROM: " .. selected.sender, 434, 212)
    love.graphics.setColor(0.72, 0.79, 0.80)
    love.graphics.print("SUBJECT: " .. selected.subject, 434, 238)
    love.graphics.printf(selected.body, 434, 270, 392, "left")
    if selected.awaitingReply then
        local remaining = math.max(0, math.ceil((tonumber(selected.expiresAtHours) or 0)
            - BusinessCalendar.absoluteHours(state)))
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.print("ESTIMATE SENT", 434, 350)
        love.graphics.setColor(0.86, 0.90, 0.88)
        love.graphics.print("Job: " .. tostring(selected.sourceJobId or "--"), 434, 382)
        love.graphics.print("Amount: " .. money(selected.quotedPrice or 0), 434, 408)
        love.graphics.print(string.format("Expires in: %d hour%s", remaining,
            remaining == 1 and "" or "s"), 434, 434)
        love.graphics.setColor(0.58, 0.67, 0.68)
        love.graphics.printf("The client is reviewing the estimate. Their reply time is not shown on the calendar.",
            434, 478, 392, "left")
        return
    end
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
    if not selected.job then
        local heading = selected.noticeKind == "receipt" and "ORDER RECEIPT"
            or selected.noticeKind == "salesman_confirmation" and "SALESMAN CONFIRMATION"
            or selected.noticeKind == "client_thanks" and "CLIENT REPLY"
            or selected.noticeKind == "client_estimate_accepted" and "ESTIMATE ACCEPTED"
            or selected.noticeKind == "client_estimate_declined" and "ESTIMATE DECLINED"
            or "EMAIL NOTICE"
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.print(heading, 434, 392)
        if selected.orderId then
            love.graphics.setColor(0.72, 0.79, 0.80)
            love.graphics.print("Order: " .. selected.orderId, 434, 420)
        end
        if selected.total then
            love.graphics.setColor(0.54, 0.84, 0.65)
            love.graphics.print("Total paid: " .. money(selected.total), 434, 446)
        end
        local hovered = pointerX and contains(EMAIL_DECLINE, pointerX, pointerY)
        love.graphics.setColor(hovered and 0.18 or 0.12, hovered and 0.48 or 0.36, 0.29)
        love.graphics.rectangle("fill", EMAIL_DECLINE.x, EMAIL_DECLINE.y,
            EMAIL_DECLINE.width, EMAIL_DECLINE.height, 3, 3)
        love.graphics.setColor(0.96, 0.98, 0.95)
        love.graphics.printf("ARCHIVE EMAIL", EMAIL_DECLINE.x, EMAIL_DECLINE.y + 15,
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
    if not selected.discountedTotal then
        love.graphics.print("Stock arrival: " .. JobService.deliverySummary(job), 434, 446)
    end
    local terms = JobService.quoteTerms(state, job, tonumber(ComputerScreen.quoteText))
    love.graphics.setColor(selected.discountedTotal and 0.54 or 0.58,
        selected.discountedTotal and 0.84 or 0.67, selected.discountedTotal and 0.65 or 0.68)
    love.graphics.print(selected.discountedTotal and "10% DISCOUNT APPLIED" or "YOUR ESTIMATE",
        EMAIL_QUOTE_INPUT.x, 454)
    local quoteSummary = "Recommended " .. money(terms and terms.recommendedPrice or job.quote.totalPrice)
    if selected.discountedTotal then
        quoteSummary = string.format("%s - %s = %s NEW TOTAL",
            money(selected.standardPrice), money(selected.discountAmount), money(selected.discountedTotal))
    end
    love.graphics.printf(quoteSummary, EMAIL_QUOTE_INPUT.x + 170, 454, 222, "right")
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
    responseButton(EMAIL_ACCEPT, "SEND ESTIMATE", true)
    love.graphics.setColor(0.58, 0.67, 0.68)
    love.graphics.printf("Estimate expires 3 days after it is sent.", 630, 518, 196, "center")
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
    drawMonitorFrame()
    panel(PANEL, { 0.035, 0.05, 0.065, 0.99 }, { 0.31, 0.56, 0.58, 1 })
    drawCritterNetChrome(assets)
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
    local reputation = Reputation.ensure(state)
    local reputationTier = Reputation.tier(reputation)
    love.graphics.print("Reputation", 530, 88)
    love.graphics.setColor(0.90, 0.92, 0.90)
    love.graphics.print(string.format("%d %s", reputation.score, reputationTier), 606, 88)
    love.graphics.setColor(0.72, 0.79, 0.80)
    love.graphics.print(BusinessCalendar.shortDate(state), 744, 88)

    BackButton.draw(assets, CLOSE, "BACK", pointerX, pointerY, false)

    if ComputerScreen.tab == "inventory" then
        drawInventory(state)
    elseif ComputerScreen.tab == "warehouse" then
        drawWarehouse(state,pointerX,pointerY,assets)
    elseif ComputerScreen.tab == "www" then
        if ComputerScreen.cartOpen then drawCart(state, pointerX, pointerY)
        else drawWww(state, pointerX, pointerY, assets); drawCartButton(pointerX, pointerY) end
    elseif ComputerScreen.tab == "email" or ComputerScreen.tab == "estimating" then
        drawEmail(state, pointerX, pointerY, assets)
    elseif ComputerScreen.tab == "calendar" then
        drawCalendar(state, pointerX, pointerY)
    elseif ComputerScreen.tab == "bills" then
        drawBills(state, pointerX, pointerY)
    else
        drawJobList(state, pointerX, pointerY)
        drawDetail(state, pointerX, pointerY, assets)
    end
    drawTabSelector(pointerX, pointerY)
end

return ComputerScreen
end

local default = create()
default.new = create
return default
