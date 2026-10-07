local Config = require("src.config")
local Save = require("src.save")
local Ui = require("src.screens.ui")
local ShopSetup = require("src.screens.shop_setup_screen")

local TitleScreen = { selected = 1, mode = "normal", message = "", onStart = nil,
    onLocal = nil, onDirect = nil, hover = nil, pressed = nil }
local BUTTONS = {
    new = { x = 126, y = 484, width = 168, height = 52, label = "NEW SHOP" },
    continue = { x = 306, y = 484, width = 168, height = 52, label = "CONTINUE" },
    delete = { x = 486, y = 484, width = 168, height = 52, label = "DELETE SLOT" },
    quit = { x = 666, y = 484, width = 168, height = 52, label = "QUIT" },
    localPlay = { x = 373, y = 548, width = 214, height = 44, label = "LOCAL PLAY" },
    directPlay = { x = 494, y = 548, width = 206, height = 44, label = "DIRECT PLAY" },
    yes = { x = 330, y = 386, width = 130, height = 48, label = "DELETE" },
    no = { x = 500, y = 386, width = 130, height = 48, label = "CANCEL" },
}
local DUAL_LOCAL_PLAY = { x = 260, y = 548, width = 206, height = 44, label = "LOCAL PLAY" }

local inside = Ui.contains
local slotCache
local versionCache
local titleFont, sectionFont, bodyFont, footerFont
local function slotRect(index) return { x = 148, y = 198 + (index - 1) * 60, width = 664, height = 48 } end

local function ensureFonts()
    titleFont = titleFont or love.graphics.newFont(40)
    sectionFont = sectionFont or love.graphics.newFont(14)
    bodyFont = bodyFont or love.graphics.newFont(13)
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
    TitleScreen.hover, TitleScreen.pressed = nil, nil
    TitleScreen.onStart, TitleScreen.onLocal, TitleScreen.onDirect = onStart, onLocal, onDirect
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
function TitleScreen.update(_) end
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

function TitleScreen.keypressed(key)
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
    if key == "n" then return requestNew() end
    if key == "c" or key == "return" or key == "kpenter" then return continueGame() end
    if key == "d" then return requestDelete() end
    if key == "l" then return openLocalPlay() end
    if key == "i" then return openDirectPlay() end
    if key == "q" or key == "escape" then love.event.quit(); return true end
    return false
end

function TitleScreen.mousepressed(x, y, button)
    if button ~= 1 then return false end
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
        if inside(slotRect(index), x, y) then TitleScreen.selected = index; return true end
    end
    local action = buttonAt(x, y)
    TitleScreen.pressed = action
    if action == "new" then return requestNew() end
    if action == "continue" then continueGame(); return true end
    if action == "delete" then return requestDelete() end
    if action == "localPlay" then return openLocalPlay() end
    if action == "directPlay" then return openDirectPlay() end
    if action == "quit" then love.event.quit(); return true end
    return false
end
function TitleScreen.mousereleased(_, _, button) if button == 1 then TitleScreen.pressed = nil end end
function TitleScreen.setHover(x, y) TitleScreen.hover = buttonAt(x, y) end

local function drawButton(assets, name, danger, label)
    local rect = buttonRect(name)
    if not rect then return end
    local hovered = TitleScreen.hover == name
    local pressed = TitleScreen.pressed == name
    love.graphics.setColor(danger and { 0.15, 0.09, 0.08, 0.96 } or { 0.055, 0.13, 0.14, 0.97 })
    love.graphics.rectangle("fill", rect.x, rect.y + (pressed and 2 or 0), rect.width, rect.height, 7, 7)
    love.graphics.setLineWidth(hovered and 2 or 1)
    love.graphics.setColor(hovered and { 0.98, 0.79, 0.35, 1 }
        or (danger and { 0.56, 0.34, 0.25, 0.95 } or { 0.30, 0.52, 0.49, 0.95 }))
    love.graphics.rectangle("line", rect.x, rect.y + (pressed and 2 or 0), rect.width, rect.height, 7, 7)
    love.graphics.setColor(danger and { 0.86, 0.54, 0.35, 0.95 } or { 0.85, 0.69, 0.34, 0.98 })
    love.graphics.rectangle("fill", rect.x + 8, rect.y + 9 + (pressed and 2 or 0), 3, rect.height - 18, 1, 1)
    love.graphics.setFont(bodyFont)
    love.graphics.setColor(0.95, 0.95, 0.89, 1)
    love.graphics.printf(label or rect.label, rect.x + 14, rect.y + rect.height / 2 - 7 + (pressed and 2 or 0),
        rect.width - 22, "center")
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

    love.graphics.setColor(0.035, 0.065, 0.069, 0.91)
    love.graphics.rectangle("fill", 108, 18, 744, 116, 15, 15)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.75, 0.61, 0.30, 0.90)
    love.graphics.rectangle("line", 108, 18, 744, 116, 15, 15)
    love.graphics.setFont(titleFont)
    love.graphics.setColor(0.96, 0.84, 0.50, 1)
    love.graphics.printf("THE PICTURE SHOP", 130, 31, 700, "center")
    love.graphics.setFont(sectionFont)
    love.graphics.setColor(0.76, 0.86, 0.81, 1)
    love.graphics.printf("PRINT  •  PACK  •  KEEP THE DOORS OPEN", 130, 86, 700, "center")
    love.graphics.setColor(0.48, 0.67, 0.61, 0.88)
    love.graphics.line(278, 112, 682, 112)

    love.graphics.setColor(0.025, 0.047, 0.05, 0.94)
    love.graphics.rectangle("fill", 126, 148, 708, 307, 10, 10)
    love.graphics.setColor(0.33, 0.48, 0.44, 0.93)
    love.graphics.rectangle("line", 126, 148, 708, 307, 10, 10)
    love.graphics.setFont(sectionFont)
    love.graphics.setColor(0.90, 0.76, 0.43, 1)
    love.graphics.print("SHOP FILES", 148, 164)
    love.graphics.setFont(footerFont)
    love.graphics.setColor(0.67, 0.76, 0.73, 1)
    love.graphics.printf("SELECT A SHOP OR START A NEW ONE", 148, 168, 664, "right")
    for index, slot in ipairs(TitleScreen.slots()) do
        local rect, selected = slotRect(index), index == TitleScreen.selected
        love.graphics.setColor(selected and { 0.11, 0.18, 0.17, 0.98 } or { 0.055, 0.085, 0.087, 0.94 })
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 6, 6)
        love.graphics.setLineWidth(selected and 2 or 1)
        love.graphics.setColor(selected and { 0.88, 0.70, 0.34, 1 } or { 0.28, 0.40, 0.38, 0.95 })
        love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 6, 6)
        love.graphics.setColor(selected and { 0.89, 0.71, 0.34, 1 } or { 0.37, 0.55, 0.51, 1 })
        love.graphics.rectangle("fill", rect.x + 1, rect.y + 7, 3, rect.height - 14, 1, 1)
        love.graphics.setFont(bodyFont)
        love.graphics.setColor(0.95, 0.94, 0.86, 1)
        love.graphics.print(string.format("SLOT %02d", index), rect.x + 16, rect.y + 15)
        love.graphics.setColor(slot.corrupted and { 0.98, 0.48, 0.37, 1 } or { 0.72, 0.79, 0.75, 1 })
        local slotText = slot.corrupted and "SAVE DAMAGED — NO RECOVERY COPY"
            or (slot.empty and "EMPTY  •  READY FOR A NEW SHOP"
            or (slot.recovered and "RECOVERED SHOP" or "ACTIVE SHOP"))
        love.graphics.print(slotText, rect.x + 124, rect.y + 15)
        if not slot.empty and not slot.corrupted then
            love.graphics.setColor(0.96, 0.84, 0.51, 1)
            love.graphics.printf("CASH  $" .. tostring(slot.money), rect.x + 440, rect.y + 15, 206, "right")
        end
    end
    if TitleScreen.mode == "shop-setup" then
        ShopSetup.draw(TitleScreen.setup,TitleScreen.selected)
    elseif TitleScreen.mode ~= "normal" then
        local overwriting = TitleScreen.mode == "overwrite-confirm"
        love.graphics.setColor(0.035, 0.055, 0.057, 0.98); love.graphics.rectangle("fill", 260, 330, 440, 132, 8, 8)
        love.graphics.setColor(0.75, 0.61, 0.30, 0.96); love.graphics.rectangle("line", 260, 330, 440, 132, 8, 8)
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
    love.graphics.printf(TitleScreen.message ~= "" and TitleScreen.message
        or (mobile and "Tap a slot and button  |  Controller: D-pad or cursor + A"
            or (TitleScreen.onDirect
                and "Mouse or W/S/Arrows | N New | C Continue | D Delete | L Local | I Direct | Q Quit"
                or "Mouse or W/S/Arrows | N New | C Continue | D Delete | L Local | Q Quit")),
        12, 614, Config.baseWidth - 24, "center")
    love.graphics.setColor(0.94, 0.82, 0.50, 0.95)
    love.graphics.printf(TitleScreen.versionText(), 0, 650, Config.baseWidth, "center")
    love.graphics.pop()
end

return TitleScreen
