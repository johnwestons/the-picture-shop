local Config = require("src.config")
local Save = require("src.save")
local Ui = require("src.screens.ui")
local ShopSetup = require("src.screens.shop_setup_screen")
local Skin = require("src.screens.title_skin")
local TitleControl = require("src.screens.title_control")
local Props = require("src.screens.title_props")
local Fonts = require("src.screens.title_fonts")
local Motion = require("src.screens.title_motion")

local TitleScreen = { selected = 1, mode = "normal", message = "", onStart = nil,
    onLocal = nil, onDirect = nil, hover = nil, pressed = nil, hoverSlot = nil, pressedSlot = nil }
TitleScreen.DISPLAY_MESSAGES = {
    "Hello Trevor, welcome back to work.", "Happy Printing", "Have a Great Day",
    "Be a Nice Critter", "Sponsored by The CritterNet",
}
TitleScreen.DISPLAY_PERIOD = 5
local BUTTONS = {
    new = { x = 126, y = 522, width = 168, height = 44, label = "NEW SHOP" },
    continue = { x = 306, y = 522, width = 168, height = 44, label = "CONTINUE" },
    delete = { x = 486, y = 522, width = 168, height = 44, label = "DELETE SLOT" },
    quit = { x = 666, y = 522, width = 168, height = 44, label = "QUIT" },
    localPlay = { x = 373, y = 604, width = 214, height = 44, label = "LOCAL PLAY" },
    directPlay = { x = 494, y = 604, width = 206, height = 44, label = "DIRECT PLAY" },
    yes = { x = 330, y = 386, width = 130, height = 48, label = "DELETE" },
    no = { x = 500, y = 386, width = 130, height = 48, label = "CANCEL" },
}
local DUAL_LOCAL_PLAY = { x = 260, y = 604, width = 206, height = 44, label = "LOCAL PLAY" }

local inside = Ui.contains
local slotCache
local versionCache
local sectionFont, bodyFont, footerFont
local function slotRect(index) return { x = 148, y = 344 + (index - 1) * 58, width = 664, height = 52 } end

local function ensureFonts()
    sectionFont = sectionFont or Fonts.get("metal", 16)
    bodyFont = bodyFont or Fonts.get("paper", 13)
    footerFont = footerFont or love.graphics.newFont(10)
end

local function runningVersion()
    if versionCache then return versionCache end
    local ok, metadata = pcall(require, "src.build_version")
    if ok and type(metadata) == "table" and type(metadata.name) == "string" then
        versionCache = metadata.name
    else
        local contents = love.filesystem.read("mobile/config.json")
        versionCache = contents and contents:match('"versionName"%s*:%s*"([%w%._%+%-]+)"')
    end
    versionCache = versionCache or "development"
    return versionCache
end

function TitleScreen.versionText() return "v" .. runningVersion() end
local function buttonRect(name)
    if name == "directPlay" and not TitleScreen.onDirect then return nil end
    if name == "localPlay" and TitleScreen.onDirect then return DUAL_LOCAL_PLAY end
    return BUTTONS[name]
end
local function buttonAt(x, y)
    for name in pairs(BUTTONS) do
        local rect = buttonRect(name)
        if rect and inside(rect, x, y) then return name end
    end
end

function TitleScreen.enter(onStart, onLocal, onDirect)
    slotCache = nil
    TitleScreen.selected, TitleScreen.mode, TitleScreen.message = 1, "normal", ""
    TitleScreen.hover, TitleScreen.pressed, TitleScreen.hoverSlot, TitleScreen.pressedSlot = nil, nil, nil, nil
    TitleScreen.onStart, TitleScreen.onLocal, TitleScreen.onDirect = onStart, onLocal, onDirect
    TitleScreen.displayOverride = nil
    TitleScreen.cycleTime, TitleScreen.feedbackRemaining, TitleScreen.observedMessage = 0, 0, ""
    TitleScreen.pendingAction, TitleScreen.keyboardFocus = nil, nil
    TitleScreen.pointerX, TitleScreen.pointerY = nil, nil
    Motion.reset()
end
-- Pass nil to return to live menu feedback. The sprite's LCD stays unlettered,
-- so notices and future player messages can change without regenerating art.
function TitleScreen.setDisplayMessage(text)
    assert(text == nil or type(text) == "string", "Display message must be a string or nil")
    TitleScreen.displayOverride = text
end
function TitleScreen.displayText()
    if TitleScreen.displayOverride ~= nil then return TitleScreen.displayOverride end
    if TitleScreen.message ~= "" then return TitleScreen.message end
    local index = math.floor((TitleScreen.cycleTime or 0) / TitleScreen.DISPLAY_PERIOD) + 1
    return TitleScreen.DISPLAY_MESSAGES[index]
end
function TitleScreen.slots()
    local now = love.timer.getTime()
    local identity, revision = love.filesystem.getIdentity(), Save.revision()
    if not slotCache or slotCache.identity ~= identity or slotCache.revision ~= revision
        or now < slotCache.at or now - slotCache.at >= 0.5 then
        local slots = Save.listSlots()
        slotCache = {identity=identity,revision=Save.revision(),at=now,slots=slots}
    end
    return slotCache.slots
end
function TitleScreen.update(dt)
    dt = math.max(0, tonumber(dt) or 0)
    Motion.update(dt)
    local cycleDt = dt
    if TitleScreen.message ~= TitleScreen.observedMessage then
        TitleScreen.observedMessage, TitleScreen.feedbackRemaining = TitleScreen.message, 3
    end
    if TitleScreen.mode == "normal" and TitleScreen.message ~= "" then
        cycleDt = math.max(0, dt - (TitleScreen.feedbackRemaining or 0))
        TitleScreen.feedbackRemaining = math.max(0, (TitleScreen.feedbackRemaining or 0) - dt)
        if TitleScreen.feedbackRemaining == 0 then TitleScreen.message, TitleScreen.observedMessage = "", "" end
    end
    if TitleScreen.displayOverride == nil and TitleScreen.message == "" then
        TitleScreen.cycleTime = ((TitleScreen.cycleTime or 0) + cycleDt)
            % (TitleScreen.DISPLAY_PERIOD * #TitleScreen.DISPLAY_MESSAGES)
    end
    local pending = TitleScreen.pendingAction
    if pending then
        pending.remaining = pending.remaining - dt
        if pending.remaining <= 0 then
            -- Clear before invoking callbacks, which may enter another screen.
            TitleScreen.pendingAction, TitleScreen.pressed = nil, nil
            TitleScreen.selected = pending.slot
            pending.callback()
        end
    end
end
function TitleScreen.buttonCenter(name)
    local rect = buttonRect(name)
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

local function startNew()
    local payload = Save.newGame(TitleScreen.selected,TitleScreen.setup)
    TitleScreen.mode="normal"
    TitleScreen.message = "New shop created in slot " .. TitleScreen.selected
    if TitleScreen.onStart then TitleScreen.onStart(payload, "new") end
end
local function beginSetup()
    TitleScreen.setup=ShopSetup.new();TitleScreen.mode="shop-setup"
    TitleScreen.message="Choose the clock pace before creating this shop."
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
    beginSetup()
    return true
end

local function requestDelete()
    TitleScreen.mode = "delete-confirm"
    TitleScreen.message = "Delete slot " .. TitleScreen.selected .. "?"
    return true
end

local function confirmPending()
    if TitleScreen.mode == "overwrite-confirm" then
        beginSetup()
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
    TitleScreen.keyboardFocus = "slot-" .. TitleScreen.selected
    Motion.focus(TitleScreen.keyboardFocus)
end

local function openLocalPlay()
    if not TitleScreen.onLocal then
        TitleScreen.message = "Local Play is unavailable in this build."
        return false
    end
    TitleScreen.onLocal(TitleScreen.selected)
    return true
end

local function openDirectPlay()
    if not TitleScreen.onDirect then
        TitleScreen.message = "Direct Play is not available in this build."
        return false
    end
    TitleScreen.onDirect(TitleScreen.selected)
    return true
end

local function disabledButton(name)
    local slot = TitleScreen.slots()[TitleScreen.selected]
    return (name == "continue" and (not slot or slot.empty or slot.corrupted))
        or (name == "delete" and (not slot or slot.empty))
        or (name == "localPlay" and not TitleScreen.onLocal)
        or (name == "directPlay" and not TitleScreen.onDirect)
end

local actions = { new = requestNew, continue = continueGame, delete = requestDelete,
    localPlay = openLocalPlay, directPlay = openDirectPlay, quit = function() love.event.quit() end }
local function activate(name)
    if disabledButton(name) then
        if name == "continue" then return continueGame() end
        if name == "localPlay" then return openLocalPlay() end
        if name == "directPlay" then return openDirectPlay() end
        TitleScreen.message = "That slot is empty. Choose NEW SHOP."
        return false
    end
    Motion.press(name)
    Motion.focus(name)
    TitleScreen.pendingAction = { callback = actions[name], slot = TitleScreen.selected,
        remaining = Motion.CLICK_DURATION }
    return true
end

local function nextFocus(delta)
    local order = { "slot-1", "slot-2", "slot-3", "new" }
    for _, name in ipairs({ "continue", "delete", "quit", "localPlay", "directPlay" }) do
        if not disabledButton(name) then order[#order + 1] = name end
    end
    local current = TitleScreen.selected
    for index, id in ipairs(order) do if id == TitleScreen.keyboardFocus then current = index; break end end
    local id = order[(current - 1 + delta) % #order + 1]
    TitleScreen.keyboardFocus = id
    local slot = id:match("^slot%-(%d)$")
    if slot then TitleScreen.selected = tonumber(slot) end
    Motion.focus(id)
end

function TitleScreen.keypressed(key)
    if TitleScreen.pendingAction then return true end
    if TitleScreen.mode=="shop-setup" then
        local result=ShopSetup.keypressed(TitleScreen.setup,key)
        if result=="start" then startNew()
        elseif result=="cancel" then TitleScreen.mode="normal";TitleScreen.message="Shop creation cancelled." end
        return result~=nil
    end
    if TitleScreen.mode ~= "normal" then
        if key == "y" or key == "return" or key == "kpenter" then return confirmPending() end
        if key == "n" or key == "escape" then return cancelPending() end
        return false
    end

    if key == "up" or key == "w" then moveSelection(-1); return true end
    if key == "down" or key == "s" then moveSelection(1); return true end
    if key == "tab" or key == "left" or key == "right" then
        local backwards = key == "left" or (key == "tab" and love.keyboard.isDown("lshift", "rshift"))
        nextFocus(backwards and -1 or 1); return true
    end
    local name = ({ n = "new", c = "continue", d = "delete", l = "localPlay", i = "directPlay",
        q = "quit", escape = "quit" })[key]
    if key == "return" or key == "kpenter" or key == "space" then
        name = actions[TitleScreen.keyboardFocus] and TitleScreen.keyboardFocus or "continue"
    end
    if name then TitleScreen.keyboardFocus = name; return activate(name) end
    return false
end

function TitleScreen.mousepressed(x, y, button)
    if button ~= 1 then return false end
    if TitleScreen.pendingAction then return true end
    TitleScreen.keyboardFocus = nil
    if TitleScreen.mode=="shop-setup" then
        local result=ShopSetup.mousepressed(TitleScreen.setup,x,y)
        if result=="start" then startNew()
        elseif result=="cancel" then TitleScreen.mode="normal";TitleScreen.message="Shop creation cancelled." end
        return result~=nil
    end
    if TitleScreen.mode ~= "normal" then
        local action = buttonAt(x, y)
        if action == "yes" then return confirmPending() end
        if action == "no" then return cancelPending() end
        return false
    end
    for index = 1, Save.SLOT_COUNT do
        if inside(slotRect(index), x, y) then
            TitleScreen.selected, TitleScreen.pressedSlot = index, index
            Motion.press("slot-" .. index)
            Motion.focus("slot-" .. index)
            return true
        end
    end
    local action = buttonAt(x, y)
    TitleScreen.pressed = action
    if actions[action] then activate(action); return true end
    return false
end
function TitleScreen.mousereleased(_, _, button)
    if button == 1 then TitleScreen.pressed, TitleScreen.pressedSlot = nil, nil end
end
function TitleScreen.setHover(x, y)
    if TitleScreen.pointerX ~= nil and (TitleScreen.pointerX ~= x or TitleScreen.pointerY ~= y) then
        TitleScreen.keyboardFocus = nil
    end
    TitleScreen.pointerX, TitleScreen.pointerY = x, y
    TitleScreen.hover, TitleScreen.hoverSlot = buttonAt(x, y), nil
    if TitleScreen.mode == "normal" then
        for index = 1, Save.SLOT_COUNT do
            if inside(slotRect(index), x, y) then TitleScreen.hoverSlot = index; break end
        end
    end
    Motion.focus(TitleScreen.mode == "normal" and (TitleScreen.keyboardFocus
        or (TitleScreen.hoverSlot and "slot-" .. TitleScreen.hoverSlot) or TitleScreen.hover) or nil)
end

local function drawButton(assets, name, danger, label)
    local rect = buttonRect(name)
    if not rect then return end
    local hovered = TitleScreen.keyboardFocus and TitleScreen.keyboardFocus == name
        or not TitleScreen.keyboardFocus and TitleScreen.hover == name
    local pressed = TitleScreen.pressed == name
    local disabled = disabledButton(name)
    local state = Motion.state(name, disabled and "disabled" or hovered and "hover" or "normal", pressed)
    local toolbox = name == "localPlay" or name == "directPlay"
    local ink = name == "new" or name == "continue" or name == "delete" or name == "quit"
    if toolbox then Props.toolbox(assets, rect, state)
    elseif ink then Props.ink(assets, rect, state, danger)
    else Skin.button(assets, rect, state, danger) end
    if toolbox or ink then
        local kind = toolbox and "toolbox" or "ink"
        local inset = rect.width * (toolbox and 0.23 or 0.15)
        local font = Fonts.fit(toolbox and "metal" or "ink", label or rect.label, 14,
            rect.width - inset * 2, rect.height * Props.labelHeight(kind, state))
        love.graphics.setFont(font)
        love.graphics.setColor(disabled and { 0.40, 0.41, 0.41, 1 } or { 0.12, 0.11, 0.09, 1 })
        local textY = rect.y + rect.height * Props.labelCenter(kind, state) - font:getHeight() / 2
        love.graphics.printf(label or rect.label, rect.x + inset, textY, rect.width - inset * 2, "center")
    else
        love.graphics.setFont(Fonts.get("metal", 16))
        love.graphics.setColor(0.95, 0.95, 0.89, 1)
        love.graphics.printf(label or rect.label, rect.x + 14, rect.y + rect.height / 2 - 7 + (pressed and 2 or 0),
            rect.width - 22, "center")
    end
end

function TitleScreen.draw(assets, mouseX, mouseY)
    if mouseX and mouseY then TitleScreen.setHover(mouseX, mouseY) end
    ensureFonts()
    love.graphics.clear(0.025, 0.04, 0.045)
    local background = assets and assets.get("warehouse")
    if background then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(background, 0, 0, 0,
            Config.baseWidth / background:getWidth(), Config.baseHeight / background:getHeight())
    end
    love.graphics.push("all")
    love.graphics.setColor(0.018, 0.035, 0.042, 0.64)
    love.graphics.rectangle("fill", 0, 0, Config.baseWidth, Config.baseHeight)

    TitleControl.draw(assets, 108, 6, 744, TitleScreen.displayText())
    Props.shelf(assets, { x = 104, y = 310, width = 752, height = 210 })
    love.graphics.setFont(sectionFont)
    love.graphics.setColor(0.16, 0.15, 0.12, 1)
    love.graphics.print("SHOP FILES", 164, 322)
    love.graphics.setFont(footerFont)
    love.graphics.setColor(0.30, 0.31, 0.28, 1)
    love.graphics.printf("SELECT A SHOP OR START A NEW ONE", 164, 326, 632, "right")
    for index, slot in ipairs(TitleScreen.slots()) do
        local rect, selected = slotRect(index), index == TitleScreen.selected
        local state = Motion.state("slot-" .. index, selected and "selected" or "normal",
            TitleScreen.pressedSlot == index)
        local left, right = Props.palletPair(assets, rect, state)
        love.graphics.setFont(bodyFont)
        love.graphics.setColor(0.13, 0.11, 0.08, 1)
        love.graphics.print(string.format("SLOT %02d", index), left.x + 64, left.y + 5)
        love.graphics.setColor(slot.corrupted and { 0.66, 0.15, 0.10, 1 } or { 0.26, 0.23, 0.18, 1 })
        local slotText = slot.corrupted and "SAVE DAMAGED — NO RECOVERY COPY"
            or (slot.empty and "EMPTY  •  READY FOR A NEW SHOP"
            or (slot.recovered and "RECOVERED SHOP" or "ACTIVE SHOP"))
        local statusFont = Fonts.fit("paper", slotText, 13, right.width - 85, 18)
        love.graphics.setFont(statusFont)
        love.graphics.printf(slotText, right.x + 20, right.y + 5, right.width - 85, "center")
        if not slot.empty and not slot.corrupted then
            love.graphics.setFont(bodyFont)
            love.graphics.setColor(0.37, 0.25, 0.07, 1)
            love.graphics.printf("CASH  $" .. tostring(slot.money), left.x + 132, left.y + 5,
                left.width - 166, "right")
        end
    end
    if TitleScreen.mode == "shop-setup" then
        ShopSetup.draw(TitleScreen.setup,TitleScreen.selected,assets,mouseX,mouseY)
    elseif TitleScreen.mode ~= "normal" then
        local overwriting = TitleScreen.mode == "overwrite-confirm"
        Skin.panel(assets, { x = 260, y = 330, width = 440, height = 146 })
        love.graphics.setFont(sectionFont)
        love.graphics.setColor(0.94, 0.38, 0.30)
        love.graphics.printf((overwriting and "OVERWRITE SLOT " or "DELETE SLOT ") .. TitleScreen.selected .. "?", 260, 348, 440, "center")
        drawButton(assets, "yes", true, overwriting and "OVERWRITE" or "DELETE")
        drawButton(assets, "no", false, "CANCEL")
        love.graphics.setFont(footerFont)
        love.graphics.setColor(0.68, 0.72, 0.70)
        love.graphics.printf("Y / ENTER confirm    N / ESC cancel", 260, 442, 440, "center")
    else
        drawButton(assets, "new", false); drawButton(assets, "continue", false)
        drawButton(assets, "delete", true); drawButton(assets, "quit", true)
        drawButton(assets, "localPlay", false)
        if TitleScreen.onDirect then drawButton(assets, "directPlay", false) end
    end
    love.graphics.setColor(0.68, 0.72, 0.70)
    love.graphics.setFont(footerFont)
    local mobile = love.system and love.system.getOS and love.system.getOS() == "Android"
    love.graphics.printf(mobile and "Tap a slot and button  |  Controller: D-pad or cursor + A"
            or (TitleScreen.onDirect
                and "Tab/Arrows focus | Enter activate | N New | C Continue | D Delete | L Local | I Direct | Q Quit"
                or "Tab/Arrows focus | Enter activate | N New | C Continue | D Delete | L Local | Q Quit"),
        12, 652, Config.baseWidth - 24, "center")
    love.graphics.setColor(0.94, 0.82, 0.50, 0.95)
    love.graphics.printf(TitleScreen.versionText(), 0, 663, Config.baseWidth, "center")
    love.graphics.pop()
end

return TitleScreen
