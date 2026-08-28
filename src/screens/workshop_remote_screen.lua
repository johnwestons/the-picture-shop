local BackButton = require("src.screens.back_button")
local Config = require("src.config")
local JobService = require("src.job_service")
local Ui = require("src.screens.ui")
local Wrapper = require("src.wrapper")
local utf8 = require("utf8")

local Screen = {
    resourceId = nil,
    leaseId = nil,
    revision = 0,
    view = nil,
    quoteText = "",
    quoteFocused = false,
    quoteReplaceOnType = true,
    selectedJobId = nil,
    selectedPalletId = nil,
    waiting = false,
    status = "",
}

local PANEL = { x = 92, y = 44, width = 776, height = 590 }
local BACK = { x = 714, y = 58, width = 126, height = 40 }
local QUOTE_INPUT = { x = 566, y = 452, width = 180, height = 42 }
local DECLINE = { x = 246, y = 538, width = 174, height = 48 }
local CONFIRM = { x = 540, y = 538, width = 174, height = 48 }
local ROW_X, ROW_Y, ROW_W, ROW_H, ROW_GAP = 142, 174, 676, 48, 8

local function contains(rect, x, y)
    return Ui.contains(rect, x, y)
end

local function button(rect, label, pointerX, pointerY, enabled, green)
    local hovered = enabled and pointerX and pointerY and contains(rect, pointerX, pointerY)
    if not enabled then
        love.graphics.setColor(0.24, 0.27, 0.29)
    elseif green then
        love.graphics.setColor(hovered and 0.18 or 0.11, hovered and 0.58 or 0.45, 0.29)
    else
        love.graphics.setColor(hovered and 0.72 or 0.57, hovered and 0.28 or 0.20, 0.18)
    end
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setColor(enabled and 0.98 or 0.60, enabled and 0.98 or 0.63,
        enabled and 0.96 or 0.65)
    love.graphics.printf(label, rect.x, rect.y + math.floor(rect.height / 2) - 6,
        rect.width, "center")
end

local function header(title, subtitle, pointerX, pointerY, assets)
    love.graphics.setColor(0.01, 0.02, 0.03, 0.76)
    love.graphics.rectangle("fill", 0, 0, Config.baseWidth, Config.baseHeight)
    love.graphics.setColor(0.91, 0.90, 0.83)
    love.graphics.rectangle("fill", PANEL.x, PANEL.y, PANEL.width, PANEL.height, 6, 6)
    love.graphics.setColor(0.16, 0.21, 0.24)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", PANEL.x, PANEL.y, PANEL.width, PANEL.height, 6, 6)
    love.graphics.rectangle("fill", PANEL.x, PANEL.y, PANEL.width, 72, 6, 6)
    love.graphics.setColor(0.97, 0.84, 0.30)
    love.graphics.printf(title, PANEL.x + 16, PANEL.y + 14, PANEL.width - 32, "center")
    love.graphics.setColor(0.82, 0.87, 0.88)
    love.graphics.printf(subtitle, PANEL.x + 16, PANEL.y + 40, PANEL.width - 32, "center")
    BackButton.draw(assets, BACK, "BACK", pointerX, pointerY, Screen.waiting)
end

local function activeJobs(state)
    local rows = {}
    for _, job in ipairs((state.jobs and state.jobs.active) or {}) do
        rows[#rows + 1] = job
        if #rows >= 6 then break end
    end
    return rows
end

local function wrapperRows(state)
    local rows = {}
    if Screen.view and type(Screen.view.pallets) == "table" then
        for _, item in ipairs(Screen.view.pallets) do rows[#rows + 1] = item end
        return rows
    end
    for _, item in ipairs(Wrapper.nearbyPallets(state)) do
        rows[#rows + 1] = {
            palletId = item.pallet.id,
            jobLabel = item.job and ((item.job.company or "Client") .. " · " .. item.job.id)
                or "Client pallet",
            packaging = item.pallet.packaging or "flat",
        }
        if #rows >= 6 then break end
    end
    return rows
end

local function selectedWrapperPallet(rows)
    if Screen.selectedPalletId == nil then return nil end
    for _, item in ipairs(rows) do
        if item.palletId == Screen.selectedPalletId then return item end
    end
    return nil
end

local function rowRect(index)
    return { x = ROW_X, y = ROW_Y + (index - 1) * (ROW_H + ROW_GAP), width = ROW_W, height = ROW_H }
end

function Screen.enter(grant, state)
    Screen.resourceId = grant and grant.resourceId or nil
    Screen.leaseId = grant and grant.leaseId or nil
    Screen.revision = tonumber(grant and grant.revision) or 0
    Screen.view = grant and (grant.view or grant.data) or nil
    Screen.quoteText = tostring(Screen.view and Screen.view.recommendedTotal or "")
    Screen.quoteFocused = false
    Screen.quoteReplaceOnType = true
    Screen.selectedJobId = nil
    Screen.selectedPalletId = Screen.view and Screen.view.selectedPalletId or nil
    Screen.waiting = false
    Screen.status = tostring(grant and grant.message or "Remote console ready.")
    if state then state.screen = "workshop_remote" end
    return Screen.resourceId ~= nil and Screen.leaseId ~= nil
end

function Screen.clear()
    Screen.resourceId, Screen.leaseId, Screen.view = nil, nil, nil
    Screen.quoteFocused, Screen.waiting = false, false
    Screen.selectedJobId, Screen.selectedPalletId = nil, nil
end

function Screen.isOpen() return Screen.resourceId ~= nil and Screen.leaseId ~= nil end
function Screen.canClose()
    return not Screen.waiting
        and (Screen.resourceId ~= "skid_wrapper" or Wrapper.step ~= "wrapping")
end
function Screen.wantsTextInput()
    return Screen.resourceId == "reception_customer" and Screen.quoteFocused
end

function Screen.wrapperStartEnabled(state)
    return Screen.resourceId == "skid_wrapper"
        and not Screen.waiting
        and Wrapper.step ~= "wrapping"
        and selectedWrapperPallet(wrapperRows(state)) ~= nil
end

function Screen.applyResult(result)
    if type(result) ~= "table" or result.resourceId ~= Screen.resourceId then return false end
    Screen.waiting = false
    Screen.revision = tonumber(result.revision) or Screen.revision
    Screen.status = tostring(result.message or (result.accepted and "Action completed." or "Action rejected."))
    if result.view or result.data then Screen.view = result.view or result.data end
    if result.accepted and result.action == "select_pallet" then
        Screen.selectedPalletId = result.palletId
            or (Screen.view and Screen.view.selectedPalletId) or Screen.selectedPalletId
    end
    return true
end

function Screen.applySnapshot(snapshot)
    if type(snapshot) ~= "table" then return false end
    Screen.revision = tonumber(snapshot.revision) or Screen.revision
    local wrapper = snapshot.wrapper
    if Screen.resourceId == "skid_wrapper" and type(wrapper) == "table" then
        Screen.selectedPalletId = wrapper.selectedPalletId
        Screen.view = Screen.view or {}
        for key, value in pairs(wrapper) do Screen.view[key] = value end
    end
    return true
end

function Screen.keypressed(key)
    if Screen.resourceId ~= "reception_customer" or not Screen.quoteFocused then return false end
    if key == "backspace" then
        if Screen.quoteReplaceOnType then
            Screen.quoteText = ""
            Screen.quoteReplaceOnType = false
        else
            local offset = utf8.offset(Screen.quoteText, -1)
            Screen.quoteText = offset and Screen.quoteText:sub(1, offset - 1) or ""
        end
        return true
    end
    return false
end

function Screen.textinput(text)
    if not Screen:wantsTextInput() then return false end
    for character in tostring(text):gmatch(".") do
        if character:match("%d") and #Screen.quoteText < 8 then
            if Screen.quoteReplaceOnType then
                Screen.quoteText = ""
                Screen.quoteReplaceOnType = false
            end
            Screen.quoteText = Screen.quoteText .. character
        end
    end
    return true
end

local function request(sendCommand, action, args)
    if Screen.waiting then return false end
    local ok, errorMessage = sendCommand(action, args or {})
    if ok then
        Screen.waiting = true
        Screen.status = "Waiting for the host device to verify that action..."
    else
        Screen.status = tostring(errorMessage or "The command could not be sent.")
    end
    return true
end

function Screen.mousepressed(state, x, y, button, sendCommand)
    if button ~= 1 or not Screen:isOpen() then return false end
    if contains(BACK, x, y) then return Screen.waiting and true or { action = "close" } end
    if Screen.resourceId == "reception_customer" then
        if contains(QUOTE_INPUT, x, y) then
            Screen.quoteFocused, Screen.quoteReplaceOnType = true, true
            return true
        end
        Screen.quoteFocused = false
        if contains(DECLINE, x, y) then
            request(sendCommand, "decline", {})
            return true
        elseif contains(CONFIRM, x, y) then
            local amount = tonumber(Screen.quoteText)
            if not amount or amount < 1 then
                Screen.status = "Enter a whole-dollar quote first."
                return true
            end
            request(sendCommand, "submit_quote", { amount = math.floor(amount) })
            return true
        end
    elseif Screen.resourceId == "office_computer" then
        local jobs = activeJobs(state)
        for index, job in ipairs(jobs) do
            if contains(rowRect(index), x, y) then
                Screen.selectedJobId = job.id
                Screen.status = JobService.completionReady(job)
                    and "Ready to request customer pickup."
                    or "This job is visible, but every pallet must be finished and wrapped first."
                return true
            end
        end
        if contains(CONFIRM, x, y) and Screen.selectedJobId then
            return request(sendCommand, "request_pickup", { jobId = Screen.selectedJobId })
        end
    elseif Screen.resourceId == "skid_wrapper" then
        local rows = wrapperRows(state)
        for index, item in ipairs(rows) do
            if contains(rowRect(index), x, y) then
                Screen.selectedPalletId = item.palletId
                return request(sendCommand, "select_pallet", { palletId = item.palletId })
            end
        end
        if contains(CONFIRM, x, y) then
            local selected = selectedWrapperPallet(rows)
            if not Screen.wrapperStartEnabled(state) then
                if Screen.waiting or Wrapper.step == "wrapping" then return true end
                Screen.status = #rows == 0
                    and "Park a finished, unwrapped pallet beside the skid wrapper first."
                    or "Select a nearby finished pallet first."
                return true
            end
            return request(sendCommand, "start_cycle", { palletId = selected.palletId })
        end
    end
    return false
end

local function drawCustomer(pointerX, pointerY)
    local view = Screen.view or {}
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("CLIENT", 142, 150)
    love.graphics.printf(tostring(view.company or "Waiting customer"), 260, 150, 500, "left")
    love.graphics.print("JOB", 142, 184)
    love.graphics.printf(tostring(view.jobId or "Pending ticket"), 260, 184, 500, "left")
    love.graphics.print("WORK", 142, 218)
    local source = view.sourceSize or {}
    local finished = view.finishedSize or {}
    local description = string.format("%gx%g stock to %gx%g finished · %s · %s",
        tonumber(source.width) or 0, tonumber(source.height) or 0,
        tonumber(finished.width) or 0, tonumber(finished.height) or 0,
        tostring(view.stock or "customer stock"),
        view.packaging == "boxed" and "boxed" or "flat pallet")
    love.graphics.printf(description, 260, 218, 500, "left")
    love.graphics.print("DELIVERY", 142, 288)
    love.graphics.printf(tostring(view.delivery or "Host-calculated service"), 260, 288, 500, "left")
    love.graphics.setColor(0.18, 0.21, 0.22)
    love.graphics.rectangle("fill", 142, 354, 676, 104, 4, 4)
    love.graphics.setColor(0.94, 0.91, 0.79)
    love.graphics.printf(string.format("Recommended shop quote: $%d",
        tonumber(view.recommendedTotal) or 0), 160, 378, 640, "center")
    love.graphics.setColor(Screen.quoteFocused and 0.98 or 0.88, 0.96, 0.82)
    love.graphics.rectangle("fill", QUOTE_INPUT.x, QUOTE_INPUT.y, QUOTE_INPUT.width,
        QUOTE_INPUT.height, 4, 4)
    love.graphics.setColor(0.08, 0.10, 0.11)
    love.graphics.printf("$" .. Screen.quoteText, QUOTE_INPUT.x, QUOTE_INPUT.y + 13,
        QUOTE_INPUT.width, "center")
    button(DECLINE, "DECLINE", pointerX, pointerY, not Screen.waiting, false)
    button(CONFIRM, "SEND QUOTE", pointerX, pointerY, not Screen.waiting, true)
end

local function drawComputer(state, pointerX, pointerY)
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print(string.format("CASH  $%d", math.floor(tonumber(state.money) or 0)), 142, 136)
    love.graphics.print(string.format("A/R  $%d", math.floor(tonumber(state.accountsReceivable) or 0)), 350, 136)
    love.graphics.print("ACTIVE JOBS — select one to inspect pickup readiness", 142, 158)
    local jobs = activeJobs(state)
    if #jobs == 0 then
        love.graphics.setColor(0.40, 0.42, 0.43)
        love.graphics.printf("No active jobs are in the host shop.", ROW_X, ROW_Y + 30, ROW_W, "center")
    end
    for index, job in ipairs(jobs) do
        local rect = rowRect(index)
        local selected = job.id == Screen.selectedJobId
        love.graphics.setColor(selected and 0.91 or 0.79, selected and 0.72 or 0.78,
            selected and 0.24 or 0.73)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
        love.graphics.setColor(0.08, 0.10, 0.11)
        love.graphics.print(tostring(job.id), rect.x + 14, rect.y + 9)
        love.graphics.printf(tostring(job.company or "Client"), rect.x + 110, rect.y + 9, 280, "left")
        love.graphics.printf(JobService.completionReady(job) and "READY" or tostring(job.status or "ACTIVE"),
            rect.x + 470, rect.y + 9, 184, "right")
    end
    button(CONFIRM, "REQUEST PICKUP", pointerX, pointerY,
        not Screen.waiting and Screen.selectedJobId ~= nil, true)
end

local function drawWrapper(state, pointerX, pointerY)
    local runtime = Wrapper.snapshot()
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("HOST CYCLE", 142, 136)
    love.graphics.print(string.upper(runtime.step), 270, 136)
    local ratio = math.min(1, runtime.progress / math.max(0.001, runtime.cycleTime))
    love.graphics.setColor(0.18, 0.21, 0.22)
    love.graphics.rectangle("fill", 420, 136, 380, 18, 3, 3)
    love.graphics.setColor(0.92, 0.72, 0.20)
    love.graphics.rectangle("fill", 420, 136, 380 * ratio, 18, 3, 3)
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("NEARBY FINISHED PALLETS", 142, 158)
    local rows = wrapperRows(state)
    if #rows == 0 then
        love.graphics.setColor(0.40, 0.42, 0.43)
        love.graphics.printf("No eligible pallet is parked by the wrapper.", ROW_X, ROW_Y + 34, ROW_W, "center")
    end
    for index, item in ipairs(rows) do
        local rect = rowRect(index)
        local selected = item.palletId == Screen.selectedPalletId
        love.graphics.setColor(selected and 0.91 or 0.79, selected and 0.72 or 0.78,
            selected and 0.24 or 0.73)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
        love.graphics.setColor(0.08, 0.10, 0.11)
        love.graphics.print(tostring(item.palletId), rect.x + 14, rect.y + 9)
        love.graphics.printf(tostring(item.jobLabel or "Client pallet"),
            rect.x + 170, rect.y + 9, 300, "left")
        love.graphics.printf(string.upper(tostring(item.packaging or "flat")),
            rect.x + 520, rect.y + 9, 134, "right")
    end
    button(CONFIRM, runtime.step == "wrapping" and "WRAPPING..." or "START CYCLE",
        pointerX, pointerY, Screen.wrapperStartEnabled(state), true)
end

function Screen.draw(state, pointerX, pointerY, assets)
    local titles = {
        reception_customer = { "REMOTE RECEPTION", "The host device owns the customer and verifies your quote" },
        office_computer = { "REMOTE OFFICE COMPUTER", "Shared shop records are live; transactions run on the host device" },
        skid_wrapper = { "REMOTE SKID WRAPPER", "The host device owns the machine cycle and saved pallet state" },
    }
    local copy = titles[Screen.resourceId] or { "REMOTE WORKSHOP", "Host-authoritative console" }
    header(copy[1], copy[2], pointerX, pointerY, assets)
    if Screen.resourceId == "reception_customer" then drawCustomer(pointerX, pointerY)
    elseif Screen.resourceId == "office_computer" then drawComputer(state, pointerX, pointerY)
    elseif Screen.resourceId == "skid_wrapper" then drawWrapper(state, pointerX, pointerY) end
    love.graphics.setColor(0.18, 0.21, 0.22)
    love.graphics.printf(Screen.status, PANEL.x + 24, PANEL.y + PANEL.height - 30,
        PANEL.width - 48, "center")
end

function Screen.backCenter() return BACK.x + BACK.width / 2, BACK.y + BACK.height / 2 end
function Screen.confirmCenter() return CONFIRM.x + CONFIRM.width / 2, CONFIRM.y + CONFIRM.height / 2 end
function Screen.quoteInputCenter()
    return QUOTE_INPUT.x + QUOTE_INPUT.width / 2, QUOTE_INPUT.y + QUOTE_INPUT.height / 2
end
function Screen.rowCenter(index)
    local rect = rowRect(index)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

return Screen
