local Config = require("src.config")
local Save = require("src.save")
local Ui = require("src.screens.ui")

local TitleScreen = { selected = 1, mode = "normal", message = "", onStart = nil,
    onLocal = nil, hover = nil, pressed = nil }
local BUTTONS = {
    new = { x = 100, y = 520, width = 170, height = 54, label = "NEW SHOP" },
    continue = { x = 290, y = 520, width = 170, height = 54, label = "CONTINUE" },
    delete = { x = 480, y = 520, width = 170, height = 54, label = "DELETE SLOT" },
    quit = { x = 670, y = 520, width = 170, height = 54, label = "QUIT" },
    localPlay = { x = 365, y = 582, width = 230, height = 50, label = "LOCAL PLAY" },
    yes = { x = 330, y = 386, width = 130, height = 48, label = "DELETE" },
    no = { x = 500, y = 386, width = 130, height = 48, label = "CANCEL" },
}

local inside = Ui.contains
local function slotRect(index) return { x = 116, y = 236 + (index - 1) * 72, width = 728, height = 56 } end
local function buttonAt(x, y)
    for name, rect in pairs(BUTTONS) do if inside(rect, x, y) then return name end end
end

function TitleScreen.enter(onStart, onLocal)
    TitleScreen.selected, TitleScreen.mode, TitleScreen.message = 1, "normal", ""
    TitleScreen.hover, TitleScreen.pressed = nil, nil
    TitleScreen.onStart, TitleScreen.onLocal = onStart, onLocal
end
function TitleScreen.slots() return Save.listSlots() end
function TitleScreen.update(_) end
function TitleScreen.buttonCenter(name)
    local rect = BUTTONS[name]
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

local function startNew()
    local payload = Save.newGame(TitleScreen.selected)
    TitleScreen.message = "New shop created in slot " .. TitleScreen.selected
    if TitleScreen.onStart then TitleScreen.onStart(payload, "new") end
end
local function continueGame()
    local payload, status = Save.load(TitleScreen.selected)
    if not payload then
        TitleScreen.message = status == "corrupted"
            and "That save is damaged and has no valid recovery copy. Delete it or choose another slot."
            or "That slot is empty. Choose NEW SHOP."
        return false
    end
    TitleScreen.message = payload.recovered
        and ("Recovered slot " .. TitleScreen.selected .. " from its " .. payload.recoverySource .. " copy.")
        or ("Continuing slot " .. TitleScreen.selected)
    if TitleScreen.onStart then TitleScreen.onStart(payload, "continue") end
    return true
end

local function requestNew()
    local slot = TitleScreen.slots()[TitleScreen.selected]
    if slot and not slot.empty then
        TitleScreen.mode = "overwrite-confirm"
        TitleScreen.message = "Slot " .. TitleScreen.selected .. " already has a shop. Confirm overwrite or cancel."
        return true
    end
    startNew()
    return true
end

local function requestDelete()
    TitleScreen.mode = "delete-confirm"
    TitleScreen.message = "Delete slot " .. TitleScreen.selected .. "?"
    return true
end

local function confirmPending()
    if TitleScreen.mode == "overwrite-confirm" then
        TitleScreen.mode = "normal"
        startNew()
        return true
    end
    if TitleScreen.mode == "delete-confirm" then
        Save.delete(TitleScreen.selected)
        TitleScreen.mode = "normal"
        TitleScreen.message = "Slot deleted."
        return true
    end
    return false
end

local function cancelPending()
    if TitleScreen.mode == "overwrite-confirm" then
        TitleScreen.mode = "normal"
        TitleScreen.message = "Overwrite cancelled. Existing shop preserved."
        return true
    end
    if TitleScreen.mode == "delete-confirm" then
        TitleScreen.mode = "normal"
        TitleScreen.message = "Delete cancelled."
        return true
    end
    return false
end

local function moveSelection(delta)
    TitleScreen.selected = ((TitleScreen.selected - 1 + delta) % Save.SLOT_COUNT) + 1
    TitleScreen.message = "Selected slot " .. TitleScreen.selected .. "."
end

local function openLocalPlay()
    if not TitleScreen.onLocal then
        TitleScreen.message = "Local Play is unavailable in this build."
        return false
    end
    TitleScreen.onLocal(TitleScreen.selected)
    return true
end

function TitleScreen.keypressed(key)
    if TitleScreen.mode ~= "normal" then
        if key == "y" or key == "return" or key == "kpenter" then return confirmPending() end
        if key == "n" or key == "escape" then return cancelPending() end
        return false
    end

    if key == "up" or key == "w" then moveSelection(-1); return true end
    if key == "down" or key == "s" then moveSelection(1); return true end
    if key == "n" then return requestNew() end
    if key == "c" or key == "return" or key == "kpenter" then return continueGame() end
    if key == "d" then return requestDelete() end
    if key == "l" then return openLocalPlay() end
    if key == "q" or key == "escape" then love.event.quit(); return true end
    return false
end

function TitleScreen.mousepressed(x, y, button)
    if button ~= 1 then return false end
    if TitleScreen.mode ~= "normal" then
        local action = buttonAt(x, y)
        if action == "yes" then return confirmPending() end
        if action == "no" then return cancelPending() end
        return false
    end
    for index = 1, Save.SLOT_COUNT do
        if inside(slotRect(index), x, y) then TitleScreen.selected = index; return true end
    end
    local action = buttonAt(x, y)
    TitleScreen.pressed = action
    if action == "new" then return requestNew() end
    if action == "continue" then continueGame(); return true end
    if action == "delete" then return requestDelete() end
    if action == "localPlay" then return openLocalPlay() end
    if action == "quit" then love.event.quit(); return true end
    return false
end
function TitleScreen.mousereleased(_, _, button) if button == 1 then TitleScreen.pressed = nil end end
function TitleScreen.setHover(x, y) TitleScreen.hover = buttonAt(x, y) end

local function drawButton(assets, name, danger, label)
    local rect = BUTTONS[name]
    local image = assets and assets.get("cutterControlButtons")
    local frame = danger and (TitleScreen.pressed == name and 4 or 3) or (TitleScreen.pressed == name and 2 or 1)
    local sprite = assets and assets.getQuad("cutterControlButton" .. frame)
    if image and sprite then
        local scale = math.min(rect.width / sprite.width, rect.height / sprite.height)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, sprite.quad, rect.x + rect.width / 2, rect.y, 0, scale, scale, sprite.width / 2, 0)
    else
        love.graphics.setColor(danger and { 0.34, 0.11, 0.10, 1 } or { 0.12, 0.24, 0.27, 1 })
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
    end
    love.graphics.setColor(0.94, 0.96, 0.93)
    love.graphics.printf(label or rect.label, rect.x, rect.y + rect.height - 17, rect.width, "center")
end

function TitleScreen.draw(assets, mouseX, mouseY)
    if mouseX and mouseY then TitleScreen.setHover(mouseX, mouseY) end
    love.graphics.clear(0.05, 0.06, 0.07)
    local panel = assets and assets.get("polarOperatorConsole")
    if panel then
        love.graphics.setColor(1, 1, 1)
    love.graphics.draw(panel, 42, 72, 0, 876 / panel:getWidth(), 430 / panel:getHeight())
    end
    love.graphics.setColor(0.95, 0.82, 0.26); love.graphics.printf("THE PICTURE SHOP", 0, 12, Config.baseWidth, "center")
    love.graphics.setColor(0.84, 0.88, 0.88); love.graphics.printf("POLAR JOB CONTROL // SELECT SHOP MEMORY", 0, 40, Config.baseWidth, "center")
    for index, slot in ipairs(TitleScreen.slots()) do
        local rect, selected = slotRect(index), index == TitleScreen.selected
        love.graphics.setColor(selected and { 0.20, 0.28, 0.28, 0.98 } or { 0.10, 0.12, 0.12, 0.96 })
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.setLineWidth(selected and 3 or 1)
        love.graphics.setColor(selected and { 0.86, 0.70, 0.30, 1 } or { 0.44, 0.48, 0.46, 1 })
        love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.setColor(0.93, 0.92, 0.84); love.graphics.print("SLOT " .. index, rect.x + 18, rect.y + 18)
        love.graphics.setColor(slot.corrupted and { 0.96, 0.36, 0.30, 1 } or { 0.72, 0.76, 0.73, 1 })
        local slotText = slot.corrupted and "SAVE DAMAGED — NO RECOVERY COPY"
            or (slot.empty and "EMPTY PAPER TICKET"
            or ((slot.recovered and "RECOVERED SHOP" or "ACTIVE SHOP") .. "    CASH $" .. tostring(slot.money)))
        love.graphics.print(slotText, rect.x + 170, rect.y + 18)
    end
    if TitleScreen.mode ~= "normal" then
        local overwriting = TitleScreen.mode == "overwrite-confirm"
        love.graphics.setColor(0.08, 0.09, 0.09, 0.98); love.graphics.rectangle("fill", 260, 330, 440, 132, 4, 4)
        love.graphics.setColor(0.94, 0.38, 0.30)
        love.graphics.printf((overwriting and "OVERWRITE SLOT " or "DELETE SLOT ") .. TitleScreen.selected .. "?", 260, 348, 440, "center")
        drawButton(assets, "yes", true, overwriting and "OVERWRITE" or "DELETE")
        drawButton(assets, "no", false, "CANCEL")
        love.graphics.setColor(0.68, 0.72, 0.70)
        love.graphics.printf("Y / ENTER confirm    N / ESC cancel", 260, 442, 440, "center")
    else
        drawButton(assets, "new", false); drawButton(assets, "continue", false)
        drawButton(assets, "delete", true); drawButton(assets, "quit", true)
        drawButton(assets, "localPlay", false)
    end
    love.graphics.setColor(0.68, 0.72, 0.70)
    local mobile = love.system and love.system.getOS and love.system.getOS() == "Android"
    love.graphics.printf(TitleScreen.message ~= "" and TitleScreen.message
        or (mobile and "Tap a slot and button  |  Controller: D-pad or cursor + A"
            or "Mouse or W/S/Arrows | N New | C Continue | D Delete | L Local | Q Quit"),
        0, 648, Config.baseWidth, "center")
end

return TitleScreen
