local Config = require("src.config")
local JobService = require("src.job_service")
local Procurement = require("src.procurement")
local BackButton = require("src.screens.back_button")

local ComputerScreen = {
    tab = "active",
    selectedJobId = nil,
    pages = { active = 1, completed = 1, deliveries = 1 },
}

local PANEL = { x = 52, y = 34, width = 856, height = 610 }
local CLOSE = { x = 756, y = 48, width = 132, height = 40 }
local TABS = {
    { id = "active", label = "ACTIVE JOBS", x = 82, y = 128, width = 188, height = 40 },
    { id = "completed", label = "COMPLETED", x = 276, y = 128, width = 188, height = 40 },
    { id = "deliveries", label = "DELIVERIES", x = 470, y = 128, width = 188, height = 40 },
    { id = "inventory", label = "INVENTORY", x = 664, y = 128, width = 188, height = 40 },
}
local LIST = { x = 82, y = 190, width = 310, height = 370 }
local DETAIL = { x = 412, y = 190, width = 440, height = 408 }
local PREVIOUS = { x = 82, y = 570, width = 86, height = 30 }
local NEXT = { x = 306, y = 570, width = 86, height = 30 }
local COMPLETE = { x = 598, y = 548, width = 228, height = 36 }
local ROW_HEIGHT = 46
local JOBS_PER_PAGE = 7

local function contains(rect, x, y)
    return x >= rect.x and y >= rect.y
        and x <= rect.x + rect.width
        and y <= rect.y + rect.height
end

local function commaNumber(value)
    local text = tostring(math.floor(value or 0))
    local changed
    repeat text, changed = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until changed == 0
    return text
end

local function money(value)
    return "$" .. commaNumber(value)
end

local function statusLabel(status)
    local labels = {
        offered = "Offer",
        awaiting_delivery = "Awaiting inbound delivery",
        in_production = "In production",
        delivered = "Delivered",
        cutting = "Cutting in progress",
        ready_for_pickup = "Ready for pickup",
        pickup_in_progress = "Pickup in progress",
        completed = "Completed",
        declined = "Declined",
    }
    return labels[status] or tostring(status or "Unknown")
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
    return result
end

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

function ComputerScreen.enter(state)
    ComputerScreen.tab = "active"
    ComputerScreen.pages = { active = 1, completed = 1, deliveries = 1 }
    ComputerScreen.selectedJobId = nil
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

function ComputerScreen.rowCenter(row)
    return LIST.x + LIST.width / 2, LIST.y + 14 + (row - 1) * ROW_HEIGHT + 18
end

function ComputerScreen.mousepressed(state, x, y, button)
    if button ~= 1 then return nil end
    if contains(CLOSE, x, y) then return { action = "close" } end
    for _, tab in ipairs(TABS) do
        if contains(tab, x, y) then
            ComputerScreen.tab = tab.id
            ensureSelection(state)
            return { action = "tab", tab = tab.id }
        end
    end
    if ComputerScreen.tab == "inventory" then
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
    if contains(COMPLETE, x, y) then
        return { action = completionReady(selected) and "pickup_ready" or "completion_blocked",
            job = selected }
    end
    return nil
end

local function panel(rect, fill, border)
    love.graphics.setColor(fill)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(border)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 4, 4)
end

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
        love.graphics.print(statusLabel(job.status), rect.x + 8, rect.y + 21)
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

local function drawDetail(state, pointerX, pointerY)
    panel(DETAIL, { 0.065, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
    local selected = findJob(jobsForTab(state, ComputerScreen.tab), ComputerScreen.selectedJobId)
    if not selected then
        love.graphics.setColor(0.58, 0.64, 0.66)
        love.graphics.printf("Select a job to view its ticket and pallet progress.",
            DETAIL.x + 24, DETAIL.y + 145, DETAIL.width - 48, "center")
        return
    end
    local details = selected.details or {}
    love.graphics.setColor(0.96, 0.84, 0.30)
    love.graphics.print(selected.id .. "  •  " .. selected.company, DETAIL.x + 20, DETAIL.y + 18)
    love.graphics.setColor(0.72, 0.79, 0.80)
    love.graphics.print(statusLabel(selected.status), DETAIL.x + 20, DETAIL.y + 44)
    love.graphics.print(string.format("Parent: %g × %g in", selected.sourceSize.width, selected.sourceSize.height),
        DETAIL.x + 20, DETAIL.y + 76)
    love.graphics.print(string.format("Finished: %g × %g in", selected.finishedSize.width, selected.finishedSize.height),
        DETAIL.x + 220, DETAIL.y + 76)
    love.graphics.print("Stock: " .. (details.stockDescription or "Customer supplied"), DETAIL.x + 20, DETAIL.y + 102)
    love.graphics.print("Job value: " .. money(selected.quote.totalPrice), DETAIL.x + 20, DETAIL.y + 128)
    love.graphics.print("Required lifts: " .. selected.quote.totalLifts, DETAIL.x + 220, DETAIL.y + 128)

    love.graphics.setColor(0.16, 0.22, 0.24)
    love.graphics.rectangle("fill", DETAIL.x + 18, DETAIL.y + 162, DETAIL.width - 36, 26)
    love.graphics.setColor(0.85, 0.88, 0.87)
    love.graphics.print("PALLET", DETAIL.x + 28, DETAIL.y + 169)
    love.graphics.print("REMAINING", DETAIL.x + 132, DETAIL.y + 169)
    love.graphics.print("LIFTS", DETAIL.x + 270, DETAIL.y + 169)
    love.graphics.print("STATE", DETAIL.x + 340, DETAIL.y + 169)
    for index, pallet in ipairs(selected.pallets or {}) do
        local y = DETAIL.y + 194 + (index - 1) * 28
        love.graphics.setColor(0.12, 0.15, 0.17)
        love.graphics.rectangle("fill", DETAIL.x + 18, y, DETAIL.width - 36, 25)
        love.graphics.setColor(0.78, 0.83, 0.83)
        love.graphics.print(tostring(pallet.number), DETAIL.x + 48, y + 7)
        love.graphics.print(commaNumber(pallet.remainingSheets), DETAIL.x + 153, y + 7)
        love.graphics.print(string.format("%d/%d", pallet.completedLifts, pallet.requiredLifts), DETAIL.x + 274, y + 7)
        love.graphics.print(tostring(pallet.status), DETAIL.x + 340, y + 7)
    end

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
    panel({ x = 92, y = 382, width = 740, height = 198 },
        { 0.06, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
    love.graphics.setColor(0.73, 0.80, 0.81)
    love.graphics.print("SHOP STOCK", 116, 406)
    love.graphics.print("Loose starter sheets", 116, 438)
    love.graphics.print("Finished sample pieces", 116, 466)
    love.graphics.setColor(0.95, 0.84, 0.30)
    love.graphics.print(commaNumber(inventory.paper or 0), 330, 438)
    love.graphics.print(commaNumber(inventory.prints or 0), 330, 466)
    local rows = Procurement.inventoryRows(state)
    for index, item in ipairs(rows) do
        local column = index <= 2 and 0 or 1
        local row = (index - 1) % 2
        local x, y = 116 + column * 350, 504 + row * 28
        love.graphics.setColor(0.73, 0.80, 0.81)
        love.graphics.print(item.label, x, y)
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.printf(commaNumber(item.quantity) .. " " .. item.unit, x + 150, y, 175, "right")
    end
    love.graphics.setColor(0.55, 0.63, 0.65)
    love.graphics.print(string.format("Current film roll: %d / 11 wraps", inventory.plasticWrapUses or 0), 466, 438)
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

    BackButton.draw(assets, CLOSE, "BACK", pointerX, pointerY, false)

    drawTabs(pointerX, pointerY)
    if ComputerScreen.tab == "inventory" then
        drawInventory(state)
    else
        drawJobList(state, pointerX, pointerY)
        drawDetail(state, pointerX, pointerY)
    end
end

return ComputerScreen
