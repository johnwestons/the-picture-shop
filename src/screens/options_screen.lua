local Config = require("src.config")
local SaveEditor = require("src.save_editor")
local Settings = require("src.settings")
local RabbitColorways = require("src.rabbit_colorways")
local CharacterAssets = require("src.character_assets")
local Ui = require("src.screens.ui")

local OptionsScreen = {
    tab = "game",
    selectedRow = 1,
    selectedSlot = 1,
    message = "",
    hover = nil,
    editField = nil,
    editBuffer = "",
    draggingControl = nil,
    context = nil,
}

local ACCESS = { x = 828, y = 14, width = 116, height = 42 }
local ACCESS_HEADER = { x = 828, y = 0, width = 116, height = 42 }
local ACCESS_FOOTER = { x = 828, y = 630, width = 116, height = 42 }
local ACCESS_RACK = { x = 696, y = 28, width = 116, height = 42 }
local ACCESS_MACHINE = { x = 662, y = 28, width = 116, height = 42 }
local CLOSE = { x = 812, y = 20, width = 112, height = 42 }
local TABS = {
    game = { x = 105, y = 90, width = 140, height = 48, label = "GAME" },
    audio = { x = 255, y = 90, width = 140, height = 48, label = "AUDIO" },
    controls = { x = 405, y = 90, width = 140, height = 48, label = "CONTROLS" },
    character = { x = 555, y = 90, width = 140, height = 48, label = "PLAYER" },
    cheats = { x = 705, y = 90, width = 140, height = 48, label = "CHEATS" },
}
local TAB_ORDER = { "game", "audio", "controls", "character", "cheats" }
local SLOT_RECTS = {
    { x = 286, y = 166, width = 116, height = 42 },
    { x = 422, y = 166, width = 116, height = 42 },
    { x = 558, y = 166, width = 116, height = 42 },
}

local GAME_ROWS = {
    { id = "fullscreen", label = "Fullscreen", kind = "toggle" },
    { id = "vsync", label = "Vertical sync", kind = "toggle" },
    { id = "followPlayerCamera", label = "Follow player camera", kind = "toggle" },
    { id = "twelveHourTime", label = "Time format", kind = "choice" },
}
local AUDIO_ROWS = {
    { id = "masterVolume", label = "Master volume", kind = "level" },
    { id = "sfxVolume", label = "Effects volume", kind = "level" },
    { id = "ambientVolume", label = "Ambience volume", kind = "level" },
    { id = "muted", label = "Mute all audio", kind = "toggle" },
}
local CONTROL_PREVIEW = { x = 205, y = 176, width = 550, height = 350 }
local RESET_CONTROLS = { x = 370, y = 548, width = 220, height = 42 }
local COLORWAY_GROUPS = {
    { id = "furColorway", group = "fur", label = "FUR", y = 230 },
    { id = "overallsColorway", group = "overalls", label = "OVERALLS", y = 390 },
}
local CONTROL_SPECS = {
    joystick = { label = "MOVE", radius = 43 },
    primary = { label = "USE", radius = 36 },
    extra1 = { label = "ACTION 1", radius = 27 },
    extra2 = { label = "ACTION 2", radius = 27 },
}

local function rowRect(index, cheats)
    return { x = 164, y = (cheats and 244 or 202) + (index - 1) * (cheats and 48 or 52),
        width = 632, height = 42 }
end

local function controlRects(index, cheats)
    local row = rowRect(index, cheats)
    return {
        value = { x = 447, y = row.y + 3, width = 142, height = 36 },
        minus = { x = 607, y = row.y + 3, width = 70, height = 36 },
        plus = { x = 690, y = row.y + 3, width = 70, height = 36 },
    }
end

local function persistSettings()
    local context = OptionsScreen.context
    if not context then return false end
    Settings.applyAudio(context.settings, context.sound)
    Settings.applyDisplay(context.settings)
    local saved = Settings.save(context.settings)
    OptionsScreen.message = saved and "Settings saved." or "Settings changed for this session, but could not be saved."
    return saved
end

local function setColorway(id, value)
    local context = OptionsScreen.context
    if not context then return false end
    local choices = id == "furColorway" and RabbitColorways.fur or RabbitColorways.overalls
    local fur, overalls = RabbitColorways.normalize(
        context.settings.furColorway, context.settings.overallsColorway)
    local current = id == "furColorway" and fur or overalls
    value = math.max(1, math.min(#choices, value))
    if current == value then return true end
    context.settings[id] = value
    if context.applyPlayerColorways then
        context.applyPlayerColorways(context.settings.furColorway, context.settings.overallsColorway)
    end
    local saved = persistSettings()
    OptionsScreen.message = saved
        and "Rabbit colors saved. Other players can see them online."
        or "Rabbit colors are active for this session but could not be saved."
    return true
end

local function adjustColorway(rowIndex, delta)
    local row = COLORWAY_GROUPS[rowIndex]
    if not row then return false end
    local current = tonumber(OptionsScreen.context.settings[row.id]) or 1
    local count = RabbitColorways.count(row.group)
    return setColorway(row.id, (current - 1 + delta) % count + 1)
end

local function colorwayCellRect(rowIndex, choiceIndex)
    local row = COLORWAY_GROUPS[rowIndex]
    return { x = 292 + (choiceIndex - 1) * 80, y = row.y + 31, width = 72, height = 80 }
end

local function slotState()
    local context = OptionsScreen.context
    if not context then return nil, "empty" end
    return SaveEditor.inspectSlot({
        save = context.save,
        state = context.state,
        useActiveState = context.useActiveState,
    }, OptionsScreen.selectedSlot)
end

local function close()
    local context = OptionsScreen.context
    OptionsScreen.editField, OptionsScreen.editBuffer = nil, ""
    if context and context.onClose then context.onClose() end
    return true
end

function OptionsScreen.enter(context)
    OptionsScreen.context = assert(context, "options context is required")
    OptionsScreen.selectedSlot = context.preferredSlot or 1
    OptionsScreen.selectedSlot = math.max(1,
        math.min(context.save.SLOT_COUNT or 3, OptionsScreen.selectedSlot))
    OptionsScreen.selectedRow = 1
    OptionsScreen.editField, OptionsScreen.editBuffer = nil, ""
    OptionsScreen.draggingControl = nil
    OptionsScreen.message = context.isNetworkClient and context.isNetworkClient()
        and "Audio and game settings are local. Save cheats are host-only."
        or "Changes are saved immediately."
end

function OptionsScreen.leave()
    return close()
end

function OptionsScreen.wantsTextInput()
    return OptionsScreen.editField ~= nil
end

function OptionsScreen.accessRect(screen, bounds)
    -- Keep the global shortcut clear of each console's own Back/Exit controls.
    if screen == "world" then
        local right = bounds and bounds.right or Config.baseWidth
        return { x = right - 272, y = 14, width = ACCESS.width, height = ACCESS.height }
    elseif screen == "machine" then
        return ACCESS_MACHINE
    elseif screen == "machine_service" or screen == "workshop_remote"
        or screen == "shop_clock" or screen == "job_offer" then
        return ACCESS_FOOTER
    elseif screen == "computer" or screen == "work_phone" then
        return ACCESS_HEADER
    elseif screen == "pallet_rack" then
        return ACCESS_RACK
    end
    return ACCESS
end

function OptionsScreen.accessHit(x, y, screen, bounds)
    return Ui.contains(OptionsScreen.accessRect(screen, bounds), x, y)
end

local function selectTab(tab)
    if not TABS[tab] then return false end
    OptionsScreen.tab, OptionsScreen.selectedRow = tab, 1
    OptionsScreen.editField, OptionsScreen.editBuffer = nil, ""
    OptionsScreen.draggingControl = nil
    OptionsScreen.message = tab == "controls"
        and "Drag each control to a comfortable position."
        or tab == "cheats"
        and "Developer tools: save changes are immediate."
        or "Changes are saved immediately."
    return true
end

local function toggleSetting(id)
    local context = OptionsScreen.context
    if not context then return false end
    context.settings[id] = not context.settings[id]
    persistSettings()
    return true
end

local function setTimeFormat(twelveHour)
    local context = OptionsScreen.context
    if not context then return false end
    context.settings.twelveHourTime = twelveHour == true
    persistSettings()
    return true
end

local function adjustSetting(id, delta)
    local context = OptionsScreen.context
    if not context then return false end
    context.settings[id] = math.max(0, math.min(100,
        (tonumber(context.settings[id]) or 0) + delta))
    persistSettings()
    return true
end

local function editContext()
    local context = OptionsScreen.context
    return {
        save = context.save,
        state = context.state,
        saveCurrent = context.saveCurrent,
        isNetworkClient = context.isNetworkClient,
        useActiveState = context.useActiveState,
    }
end

local function setCheatValue(field, value)
    local ok, applied, message = SaveEditor.editSlot(
        editContext(), OptionsScreen.selectedSlot, field.id, value)
    OptionsScreen.message = ok
        and (message .. " " .. field.label .. " is now " .. Ui.commaNumber(applied) .. ".")
        or tostring(applied)
    return ok
end

local function adjustCheat(index, direction)
    local field = SaveEditor.fields()[index]
    local state = slotState()
    if not field or not state then
        OptionsScreen.message = "That slot has no editable shop save."
        return false
    end
    local current = tonumber(SaveEditor.value(state, field.id)) or 0
    return setCheatValue(field, current + field.step * direction)
end

local function beginEdit(index)
    local field = SaveEditor.fields()[index]
    local state = slotState()
    if not field or not state then
        OptionsScreen.message = "That slot has no editable shop save."
        return false
    end
    OptionsScreen.selectedRow = index
    OptionsScreen.editField = field.id
    OptionsScreen.editBuffer = tostring(math.floor(tonumber(SaveEditor.value(state, field.id)) or 0))
    OptionsScreen.message = "Type a value, then press Enter."
    return true
end

local function commitEdit()
    local field = SaveEditor.field(OptionsScreen.editField)
    if not field then return false end
    local value = tonumber(OptionsScreen.editBuffer)
    if not value then
        OptionsScreen.message = "Enter a whole number before saving."
        return false
    end
    local ok = setCheatValue(field, value)
    if ok then OptionsScreen.editField, OptionsScreen.editBuffer = nil, "" end
    return ok
end

local function rowsForTab()
    if OptionsScreen.tab == "game" then return GAME_ROWS end
    if OptionsScreen.tab == "audio" then return AUDIO_ROWS end
    if OptionsScreen.tab == "controls" then return {} end
    if OptionsScreen.tab == "character" then return {} end
    return SaveEditor.fields()
end

function OptionsScreen.isControlsTab()
    return OptionsScreen.tab == "controls"
end

local function controlLayout()
    local context = OptionsScreen.context
    return context and context.getControlLayout and context.getControlLayout()
        or context and context.settings.controlLayout
        or Settings.DEFAULTS.controlLayout
end

local function controlCenter(key)
    local point = controlLayout()[key]
    return CONTROL_PREVIEW.x + point.x * CONTROL_PREVIEW.width,
        CONTROL_PREVIEW.y + point.y * CONTROL_PREVIEW.height
end

local function controlAt(x, y)
    local best, bestDistance
    for key, spec in pairs(CONTROL_SPECS) do
        local centerX, centerY = controlCenter(key)
        local dx, dy = x - centerX, y - centerY
        local distanceSquared = dx * dx + dy * dy
        if distanceSquared <= (spec.radius * 1.25) ^ 2
            and (not bestDistance or distanceSquared < bestDistance)
        then
            best, bestDistance = key, distanceSquared
        end
    end
    return best
end

local function moveDraggedControl(x, y)
    local key = OptionsScreen.draggingControl
    local context = OptionsScreen.context
    if not key or not context or not context.setControlLayout then return false end
    local spec = CONTROL_SPECS[key]
    local layout = controlLayout()
    local marginX, marginY = spec.radius / CONTROL_PREVIEW.width,
        spec.radius / CONTROL_PREVIEW.height
    layout[key] = {
        x = math.max(marginX, math.min(1 - marginX,
            (x - CONTROL_PREVIEW.x) / CONTROL_PREVIEW.width)),
        y = math.max(marginY, math.min(1 - marginY,
            (y - CONTROL_PREVIEW.y) / CONTROL_PREVIEW.height)),
    }
    context.setControlLayout(layout)
    OptionsScreen.message = "Positioning " .. spec.label .. "..."
    return true
end

local function resetControls()
    local context = OptionsScreen.context
    if not context or not context.resetControlLayout then return false end
    context.resetControlLayout()
    OptionsScreen.message = "Touch controls reset to their default positions."
    return true
end

function OptionsScreen.keypressed(key)
    if OptionsScreen.editField then
        if key == "return" or key == "kpenter" then return commitEdit() end
        if key == "escape" then
            OptionsScreen.editField, OptionsScreen.editBuffer = nil, ""
            OptionsScreen.message = "Value edit cancelled."
            return true
        end
        if key == "backspace" then
            OptionsScreen.editBuffer = OptionsScreen.editBuffer:sub(1, -2)
            return true
        end
        return false
    end
    if key == "escape" or key == "o" then return close() end
    if key == "tab" then
        local index = 1
        for current, tab in ipairs(TAB_ORDER) do if tab == OptionsScreen.tab then index = current end end
        return selectTab(TAB_ORDER[index % #TAB_ORDER + 1])
    end
    if OptionsScreen.tab == "controls" then
        if key == "r" then return resetControls() end
        return false
    end
    if OptionsScreen.tab == "character" then
        if key == "up" or key == "w" then
            OptionsScreen.selectedRow = 1
            return true
        elseif key == "down" or key == "s" then
            OptionsScreen.selectedRow = 2
            return true
        elseif key == "left" or key == "a" then
            return adjustColorway(OptionsScreen.selectedRow, -1)
        elseif key == "right" or key == "d" or key == "return" or key == "kpenter" then
            return adjustColorway(OptionsScreen.selectedRow, 1)
        end
        return false
    end
    if OptionsScreen.tab == "cheats" and (key == "1" or key == "2" or key == "3") then
        OptionsScreen.selectedSlot = tonumber(key)
        OptionsScreen.message = "Selected slot " .. key .. "."
        return true
    end
    local rows = rowsForTab()
    if key == "up" or key == "w" then
        OptionsScreen.selectedRow = ((OptionsScreen.selectedRow - 2) % #rows) + 1
        return true
    elseif key == "down" or key == "s" then
        OptionsScreen.selectedRow = (OptionsScreen.selectedRow % #rows) + 1
        return true
    end
    local row = rows[OptionsScreen.selectedRow]
    if OptionsScreen.tab == "cheats" then
        if key == "left" or key == "a" then return adjustCheat(OptionsScreen.selectedRow, -1) end
        if key == "right" or key == "d" then return adjustCheat(OptionsScreen.selectedRow, 1) end
        if key == "return" or key == "kpenter" then return beginEdit(OptionsScreen.selectedRow) end
    elseif row.kind == "choice" then
        if key == "left" or key == "a" then return setTimeFormat(true) end
        if key == "right" or key == "d" then return setTimeFormat(false) end
        if key == "return" or key == "kpenter" then return toggleSetting(row.id) end
    elseif row.kind == "toggle" and (key == "left" or key == "right"
        or key == "return" or key == "kpenter")
    then
        return toggleSetting(row.id)
    elseif row.kind == "level" then
        if key == "left" or key == "a" then return adjustSetting(row.id, -5) end
        if key == "right" or key == "d" then return adjustSetting(row.id, 5) end
    end
    return false
end

function OptionsScreen.textinput(text)
    if not OptionsScreen.editField then return false end
    local digits = tostring(text or ""):gsub("[^0-9]", "")
    if digits == "" then return false end
    OptionsScreen.editBuffer = (OptionsScreen.editBuffer .. digits):sub(1, 9)
    return true
end

function OptionsScreen.mousepressed(x, y, button)
    if button ~= 1 then return false end
    if Ui.contains(CLOSE, x, y) then return close() end
    for tab, rect in pairs(TABS) do
        if Ui.contains(rect, x, y) then return selectTab(tab) end
    end
    if OptionsScreen.tab == "cheats" then
        for slot, rect in ipairs(SLOT_RECTS) do
            if Ui.contains(rect, x, y) then
                OptionsScreen.selectedSlot = slot
                OptionsScreen.editField, OptionsScreen.editBuffer = nil, ""
                OptionsScreen.message = "Selected slot " .. slot .. "."
                return true
            end
        end
    elseif OptionsScreen.tab == "controls" then
        if Ui.contains(RESET_CONTROLS, x, y) then return resetControls() end
        local control = controlAt(x, y)
        if control then
            OptionsScreen.draggingControl = control
            return moveDraggedControl(x, y)
        end
        return false
    elseif OptionsScreen.tab == "character" then
        for rowIndex, row in ipairs(COLORWAY_GROUPS) do
            for choiceIndex = 1, RabbitColorways.count(row.group) do
                if Ui.contains(colorwayCellRect(rowIndex, choiceIndex), x, y) then
                    OptionsScreen.selectedRow = rowIndex
                    return setColorway(row.id, choiceIndex)
                end
            end
        end
        return false
    end
    local rows = rowsForTab()
    for index, row in ipairs(rows) do
        local rects = controlRects(index, OptionsScreen.tab == "cheats")
        if Ui.contains(rowRect(index, OptionsScreen.tab == "cheats"), x, y) then
            OptionsScreen.selectedRow = index
        end
        if Ui.contains(rects.value, x, y) then
            if OptionsScreen.tab == "cheats" then return beginEdit(index) end
            if row.kind == "toggle" or row.kind == "choice" then return toggleSetting(row.id) end
        elseif Ui.contains(rects.minus, x, y) then
            if OptionsScreen.tab == "cheats" then return adjustCheat(index, -1) end
            if row.kind == "level" then return adjustSetting(row.id, -5) end
            if row.kind == "choice" then return setTimeFormat(true) end
            return toggleSetting(row.id)
        elseif Ui.contains(rects.plus, x, y) then
            if OptionsScreen.tab == "cheats" then return adjustCheat(index, 1) end
            if row.kind == "level" then return adjustSetting(row.id, 5) end
            if row.kind == "choice" then return setTimeFormat(false) end
            return toggleSetting(row.id)
        end
    end
    return false
end

function OptionsScreen.mousereleased(_, _, button)
    if button == 1 and OptionsScreen.draggingControl then
        OptionsScreen.draggingControl = nil
        local context = OptionsScreen.context
        if context and context.commitControlLayout then context.commitControlLayout() end
        OptionsScreen.message = "Control layout saved."
        return true
    end
    return false
end

function OptionsScreen.mousemoved(x, y)
    OptionsScreen.hover = { x = x, y = y }
    if OptionsScreen.draggingControl then return moveDraggedControl(x, y) end
end

local function drawButton(rect, label, active, danger)
    local hovered = OptionsScreen.hover and Ui.contains(rect,
        OptionsScreen.hover.x, OptionsScreen.hover.y)
    Ui.panel(rect,
        active and { 0.31, 0.39, 0.34, 1 }
            or hovered and { 0.20, 0.27, 0.27, 1 }
            or danger and { 0.30, 0.12, 0.11, 1 }
            or { 0.12, 0.17, 0.18, 1 },
        active and { 0.96, 0.77, 0.24, 1 } or { 0.43, 0.53, 0.51, 1 }, 4, active and 3 or 1)
    love.graphics.setColor(0.94, 0.95, 0.89)
    love.graphics.printf(label, rect.x, rect.y + rect.height / 2 - 7, rect.width, "center")
end

function OptionsScreen.drawAccessButton(mouseX, mouseY, screen, bounds, assets)
    OptionsScreen.hover = mouseX and mouseY and { x = mouseX, y = mouseY } or nil
    if screen == "title" then
        local rect = OptionsScreen.accessRect(screen, bounds)
        local hovered = mouseX and mouseY and Ui.contains(rect, mouseX, mouseY)
        require("src.screens.title_skin").button(assets or require("src.assets"), rect,
            Ui.pressWithin(rect) and "pressed" or hovered and "hover" or "normal")
        local previousFont = love.graphics.getFont()
        local font = require("src.screens.title_fonts").get("metal", 16)
        love.graphics.setFont(font)
        love.graphics.setColor(0.94, 0.95, 0.89)
        love.graphics.printf("OPTIONS", rect.x + 11, rect.y + (rect.height - font:getHeight()) / 2,
            rect.width - 22, "center")
        love.graphics.setFont(previousFont)
        return
    end
    drawButton(OptionsScreen.accessRect(screen, bounds), "OPTIONS", false, false)
end

local function drawRows(rows, values, cheats)
    for index, row in ipairs(rows) do
        local rect = rowRect(index, cheats)
        local selected = OptionsScreen.selectedRow == index
        Ui.panel(rect, selected and { 0.14, 0.20, 0.20, 1 } or { 0.09, 0.12, 0.13, 1 },
            selected and { 0.67, 0.58, 0.27, 1 } or { 0.25, 0.31, 0.31, 1 }, 3, 1)
        love.graphics.setColor(0.86, 0.88, 0.82)
        love.graphics.print(row.label, rect.x + 18, rect.y + 13)
        local controls = controlRects(index, cheats)
        local value = values[index]
        local editing = cheats and OptionsScreen.editField == row.id
        local twelveHour = row.kind == "choice" and OptionsScreen.context.settings.twelveHourTime
        drawButton(controls.value, editing and (OptionsScreen.editBuffer .. "|") or value,
            editing or twelveHour == true, false)
        if row.kind == "choice" then
            drawButton(controls.minus, "12 HOUR", twelveHour == true, false)
            drawButton(controls.plus, "24 HOUR", twelveHour ~= true, false)
        elseif row.kind == "toggle" then
            drawButton(controls.minus, "TOGGLE", false, false)
            drawButton(controls.plus, "TOGGLE", false, false)
        else
            drawButton(controls.minus, cheats and ("-" .. Ui.commaNumber(row.step)) or "- 5", false, false)
            drawButton(controls.plus, cheats and ("+" .. Ui.commaNumber(row.step)) or "+ 5", false, false)
        end
    end
end

local function slotLabel(slot, state, status)
    if state then return "SLOT " .. slot end
    if status == "corrupted" then return "SLOT " .. slot .. " !" end
    return "SLOT " .. slot .. " —"
end

local function drawControlPreview()
    Ui.panel(CONTROL_PREVIEW, { 0.075, 0.105, 0.12, 1 },
        { 0.36, 0.48, 0.49, 1 }, 8, 2)
    love.graphics.setColor(0.12, 0.17, 0.18, 1)
    for line = 1, 5 do
        local y = CONTROL_PREVIEW.y + line * CONTROL_PREVIEW.height / 6
        love.graphics.line(CONTROL_PREVIEW.x + 10, y,
            CONTROL_PREVIEW.x + CONTROL_PREVIEW.width - 10, y)
    end
    for key, spec in pairs(CONTROL_SPECS) do
        local x, y = controlCenter(key)
        local dragged = OptionsScreen.draggingControl == key
        love.graphics.setColor(0.025, 0.055, 0.07, 0.88)
        love.graphics.circle("fill", x, y, spec.radius)
        love.graphics.setColor(dragged and { 0.98, 0.82, 0.25, 1 }
            or { 0.42, 0.73, 0.78, 1 })
        love.graphics.setLineWidth(dragged and 4 or 3)
        love.graphics.circle("line", x, y, spec.radius)
        love.graphics.setColor(0.96, 0.98, 0.92, 1)
        love.graphics.printf(spec.label, x - spec.radius, y - 6,
            spec.radius * 2, "center", 0, key:find("extra", 1, true) and 0.62 or 0.78,
            key:find("extra", 1, true) and 0.62 or 0.78)
    end
    love.graphics.setLineWidth(1)
end

local function drawColorways()
    love.graphics.setColor(0.78, 0.81, 0.76)
    love.graphics.print("RABBIT COLORWAYS", 164, 166)
    love.graphics.setColor(0.58, 0.64, 0.61)
    love.graphics.printf("Choose a fur tone and overall color. Your choices are saved on this device and shared online.",
        164, 193, 632, "left")
    for rowIndex, row in ipairs(COLORWAY_GROUPS) do
        Ui.panel({ x = 164, y = row.y, width = 632, height = 124 },
            OptionsScreen.selectedRow == rowIndex and { 0.11, 0.15, 0.15, 1 }
                or { 0.075, 0.105, 0.11, 1 },
            OptionsScreen.selectedRow == rowIndex and { 0.67, 0.58, 0.27, 1 }
                or { 0.25, 0.31, 0.31, 1 }, 4, 1)
        love.graphics.setColor(0.86, 0.88, 0.82)
        love.graphics.printf(row.label, 176, row.y + 51, 104, "center")
        local selected = tonumber(OptionsScreen.context.settings[row.id]) or 1
        for choiceIndex = 1, RabbitColorways.count(row.group) do
            local choice = RabbitColorways.choice(row.group, choiceIndex)
            local rect = colorwayCellRect(rowIndex, choiceIndex)
            local hovered = OptionsScreen.hover and Ui.contains(rect,
                OptionsScreen.hover.x, OptionsScreen.hover.y)
            love.graphics.setColor(hovered and { 0.19, 0.25, 0.24, 1 }
                or { 0.10, 0.14, 0.14, 1 })
            love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
            love.graphics.setColor(choice.color[1], choice.color[2], choice.color[3], 1)
            love.graphics.rectangle("fill", rect.x + 18, rect.y + 7, 36, 36, 4, 4)
            love.graphics.setColor(choiceIndex == selected and { 0.98, 0.80, 0.30, 1 }
                or { 0.38, 0.47, 0.45, 1 })
            love.graphics.setLineWidth(choiceIndex == selected and 3 or 1)
            love.graphics.rectangle("line", rect.x + 17, rect.y + 6, 38, 38, 4, 4)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(choiceIndex == selected and { 0.98, 0.84, 0.38, 1 }
                or { 0.78, 0.82, 0.77, 1 })
            love.graphics.printf(choice.name, rect.x + 1, rect.y + 51, rect.width - 2, "center")
        end
    end
    local image, quad = CharacterAssets.get("rabbit-worker", "idle", 1)
    if image and quad then
        local anchorX, anchorY = CharacterAssets.getAnchor("rabbit-worker", "idle", 1)
        local scale = 0.18 * CharacterAssets.getNormalization("rabbit-worker", "idle")
        love.graphics.setColor(1, 1, 1, 1)
        RabbitColorways.draw(image, quad, 462, 596, 0, scale, scale, anchorX, anchorY,
            0, 0, OptionsScreen.context.settings.furColorway,
            OptionsScreen.context.settings.overallsColorway)
    end
    love.graphics.setColor(0.86, 0.88, 0.82)
    love.graphics.print("LIVE PLAYER PREVIEW", 514, 551)
    love.graphics.setColor(0.58, 0.64, 0.61)
    love.graphics.printf("Your online avatar uses these colors.", 514, 575, 250, "left")
end

function OptionsScreen.draw(mouseX, mouseY)
    if mouseX and mouseY then OptionsScreen.mousemoved(mouseX, mouseY) end
    love.graphics.clear(0.045, 0.055, 0.058)
    Ui.panel({ x = 92, y = 66, width = 776, height = 576 },
        { 0.065, 0.085, 0.087, 1 }, { 0.48, 0.55, 0.49, 1 }, 6, 2)
    love.graphics.setColor(0.95, 0.82, 0.26)
    love.graphics.print("SHOP CONTROL", 116, 28, 0, 1.15, 1.15)
    love.graphics.setColor(0.66, 0.72, 0.69)
    love.graphics.print("OPTIONS // O KEY OR CONTROLLER START", 116, 49)
    drawButton(CLOSE, "CLOSE", false, false)
    for _, tab in ipairs(TAB_ORDER) do
        local rect = TABS[tab]
        drawButton(rect, rect.label, OptionsScreen.tab == tab, false)
    end

    if OptionsScreen.tab == "game" then
        love.graphics.setColor(0.78, 0.81, 0.76)
        love.graphics.print("DISPLAY, CAMERA & TIME", 164, 166)
        local android = love.system and love.system.getOS and love.system.getOS() == "Android"
        local values = {
            android and "SYSTEM" or (OptionsScreen.context.settings.fullscreen and "ON" or "OFF"),
            OptionsScreen.context.settings.vsync and "ON" or "OFF",
            OptionsScreen.context.settings.followPlayerCamera and "ON" or "OFF",
            OptionsScreen.context.settings.twelveHourTime and "12 HOUR" or "24 HOUR",
        }
        drawRows(GAME_ROWS, values, false)
        love.graphics.setColor(0.58, 0.64, 0.61)
        love.graphics.printf(android and "Fullscreen is managed by Android."
            or "Display and time-format changes apply immediately.", 164, 416, 632, "center")
        love.graphics.printf("Follow keeps your character centered while walking or zooming.\n"
            .. "Pinch or use the mouse wheel to zoom. Turn follow off to pan on mobile.",
            164, 450, 632, "center")
    elseif OptionsScreen.tab == "audio" then
        love.graphics.setColor(0.78, 0.81, 0.76)
        love.graphics.print("AUDIO MIX", 164, 166)
        local settings = OptionsScreen.context.settings
        drawRows(AUDIO_ROWS, {
            settings.masterVolume .. "%", settings.sfxVolume .. "%",
            settings.ambientVolume .. "%", settings.muted and "ON" or "OFF",
        }, false)
    elseif OptionsScreen.tab == "controls" then
        love.graphics.setColor(0.78, 0.81, 0.76)
        love.graphics.printf("DRAG THE CONTROLS IN THE PREVIEW", 164, 150, 632, "center")
        drawControlPreview()
        drawButton(RESET_CONTROLS, "RESET TO DEFAULT", false, false)
    elseif OptionsScreen.tab == "character" then
        drawColorways()
    else
        for slot, rect in ipairs(SLOT_RECTS) do
            local context = OptionsScreen.context
            local stateForSlot, status = SaveEditor.inspectSlot({
                save = context.save, state = context.state,
                useActiveState = context.useActiveState,
            }, slot)
            drawButton(rect, slotLabel(slot, stateForSlot, status),
                OptionsScreen.selectedSlot == slot, status == "corrupted")
        end
        local stateForSlot, status = slotState()
        love.graphics.setColor(0.68, 0.72, 0.68)
        if stateForSlot then
            local jobs = stateForSlot.jobs or {}
            love.graphics.printf(string.format("%s SAVE  |  %d active jobs  |  %d completed jobs",
                status == "live" and "LIVE" or "OFFLINE",
                #(jobs.active or {}), #(jobs.completed or {})), 164, 220, 632, "center")
            local values = {}
            for index, field in ipairs(SaveEditor.fields()) do
                local value = SaveEditor.value(stateForSlot, field.id) or 0
                values[index] = field.money and Ui.money(value) or Ui.commaNumber(value)
            end
            drawRows(SaveEditor.fields(), values, true)
        else
            love.graphics.setColor(status == "corrupted" and { 0.95, 0.35, 0.30 }
                or { 0.70, 0.74, 0.69 })
            love.graphics.printf(status == "corrupted"
                and "This save is damaged and has no valid recovery copy."
                or "This slot is empty. Create a shop from the title screen first.",
                164, 312, 632, "center")
        end
    end

    love.graphics.setColor(0.72, 0.76, 0.70)
    love.graphics.printf(OptionsScreen.message, 116, 604, 728, "center")
    love.graphics.setColor(0.47, 0.53, 0.50)
    love.graphics.printf("Tab changes section  |  Arrows adjust  |  Enter edits  |  Esc closes",
        116, 654, 728, "center")
end

return OptionsScreen
